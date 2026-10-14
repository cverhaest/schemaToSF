import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import startSession from '@salesforce/apex/ParcoursRunnerController.startSession';
import getCurrentNode from '@salesforce/apex/ParcoursRunnerController.getCurrentNode';
import submitAndNavigate from '@salesforce/apex/ParcoursRunnerController.submitAndNavigate';
import getParcoursActifs from '@salesforce/apex/ParcoursRunnerController.getParcoursActifs';

// Correspondance entre le type de champ métier et le type lightning-input.
const INPUT_TYPE_BY_CHAMP = {
    Text: 'text',
    Phone: 'tel',
    Email: 'email',
    Number: 'number',
    Date: 'date',
    Checkbox: 'checkbox'
};

/**
 * Moteur générique de parcours : affiche le nœud courant (texte, champs de
 * saisie, transitions) et avance dans le graphe via le contrôleur Apex. Aucun
 * code n'est spécifique à un parcours : tout vient des données.
 */
export default class ParcoursRunner extends LightningElement {
    /**
     * Code technique du parcours à exécuter (Parcours__c.Code__c). Facultatif :
     * s'il est vide, le composant propose les parcours actifs sous forme de tuiles.
     */
    @api parcoursCode;
    /** Id de l'enregistrement hôte (ex : Case) pour tracer l'origine. */
    @api recordId;
    /** API name de l'objet hôte, fourni automatiquement sur une page d'enregistrement. */
    @api objectApiName;
    /** Type de l'enregistrement hôte (ex : Case) ; par défaut l'objet de la page. */
    @api origineType;

    @track node;
    sessionId;
    // Nom du parcours en cours ; conservé après la fin pour le titre de la carte.
    parcoursNom;
    isLoading = false;
    isComplete = false;
    errorMessage;

    // Mode sélection : parcours choisi par l'utilisateur et tuiles disponibles.
    selectedCode;
    tiles = [];
    searchTerm = '';

    // Réponses saisies du nœud courant, indexées par Id de champ de saisie.
    answers = {};

    connectedCallback() {
        if (this.parcoursCode) {
            this.begin();
        } else {
            this.loadTiles();
        }
    }

    /** Charge les parcours actifs proposés en tuiles. */
    async loadTiles() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.tiles = await getParcoursActifs();
        } catch (error) {
            this.reportError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /** Clic sur une tuile : démarre le parcours choisi. */
    handleSelectParcours(event) {
        this.selectedCode = event.currentTarget.dataset.code;
        this.begin();
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    /** Abandonne l'affichage du parcours courant et revient au choix des tuiles. */
    handleBackToPicker() {
        this.selectedCode = undefined;
        this.sessionId = undefined;
        this.node = undefined;
        this.parcoursNom = undefined;
        this.isComplete = false;
        this.errorMessage = undefined;
        this.answers = {};
    }

    /** Démarre une nouvelle session de parcours. */
    async begin() {
        this.isLoading = true;
        this.errorMessage = undefined;
        const origine = this.effectiveOrigineType;
        try {
            const view = await startSession({
                parcoursCode: this.activeCode,
                origineType: origine || null,
                origineId: this.recordId || null,
                accountId: origine === 'Account' ? this.recordId : null,
                caseId: origine === 'Case' ? this.recordId : null
            });
            this.applyNode(view);
        } catch (error) {
            this.reportError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /** Recharge le nœud courant depuis le serveur. */
    async refresh() {
        if (!this.sessionId) {
            return;
        }
        this.isLoading = true;
        try {
            const view = await getCurrentNode({ sessionId: this.sessionId });
            this.applyNode(view);
        } catch (error) {
            this.reportError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Soumet le nœud courant puis avance vers la cible choisie.
     *
     * @param {string} transitionId Transition sélectionnée (optionnelle).
     */
    async navigate(transitionId) {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const view = await submitAndNavigate({
                sessionId: this.sessionId,
                nodeId: this.node.nodeId,
                answersJson: JSON.stringify(this.answers),
                transitionId: transitionId || null
            });
            if (view) {
                this.applyNode(view);
            } else {
                this.isComplete = true;
                this.node = undefined;
            }
        } catch (error) {
            this.reportError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /** Clic sur une transition d'embranchement. */
    handleTransition(event) {
        this.navigate(event.currentTarget.dataset.id);
    }

    /** Bouton « Suivant » pour un nœud linéaire (sortie unique). */
    handleNext() {
        const only = this.hasSingleTransition ? this.node.transitions[0].transitionId : null;
        this.navigate(only);
    }

    /** Bouton de continuation d'un nœud d'aiguillage vers un sous-parcours. */
    handleNavigate() {
        this.navigate(null);
    }

    /** Mémorise la valeur saisie pour un champ. */
    handleInputChange(event) {
        const champId = event.target.dataset.id;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.answers = { ...this.answers, [champId]: value };
    }

    /** Applique une vue de nœud reçue du serveur et réinitialise les saisies. */
    applyNode(view) {
        this.sessionId = view.sessionId;
        this.parcoursNom = view.parcoursNom || this.parcoursNom;
        this.answers = {};
        this.isComplete = Boolean(view.isFin) && (!view.transitions || view.transitions.length === 0);
        this.node = {
            ...view,
            champs: (view.champs || []).map((champ) => ({
                ...champ,
                inputType: INPUT_TYPE_BY_CHAMP[champ.typeChamp] || 'text'
            }))
        };
    }

    reportError(error) {
        this.errorMessage =
            error && error.body && error.body.message
                ? error.body.message
                : 'Une erreur est survenue pendant le parcours.';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Parcours',
                message: this.errorMessage,
                variant: 'error'
            })
        );
    }

    get cardTitle() {
        if (this.isPicker) {
            return 'Choisir un parcours';
        }
        return this.parcoursNom || 'Parcours métier';
    }

    /** Code effectivement exécuté : configuré dans App Builder ou choisi en tuile. */
    get activeCode() {
        return this.parcoursCode || this.selectedCode;
    }

    get effectiveOrigineType() {
        return this.origineType || this.objectApiName;
    }

    /** Aucun code configuré ni choisi : on affiche les tuiles. */
    get isPicker() {
        return !this.activeCode;
    }

    /** Le retour au choix n'existe que si le parcours n'est pas imposé par la configuration. */
    get canChangeParcours() {
        return !this.parcoursCode && Boolean(this.selectedCode);
    }

    get filteredTiles() {
        const term = this.searchTerm.trim().toLowerCase();
        const tiles = term
            ? this.tiles.filter((tile) =>
                  [tile.name, tile.code, tile.categorie].some(
                      (value) => value && value.toLowerCase().includes(term)
                  )
              )
            : this.tiles;
        return tiles.map((tile) => ({
            ...tile,
            versionLabel: tile.version != null ? `v${tile.version}` : ''
        }));
    }

    get hasTiles() {
        return this.filteredTiles.length > 0;
    }

    get showNoTiles() {
        return this.isPicker && !this.isLoading && !this.hasTiles;
    }

    get noTilesMessage() {
        return this.searchTerm
            ? 'Aucun parcours ne correspond à la recherche.'
            : 'Aucun parcours actif disponible.';
    }

    get hasChamps() {
        return this.node && this.node.champs && this.node.champs.length > 0;
    }

    get hasTransitions() {
        return this.node && this.node.transitions && this.node.transitions.length > 0;
    }

    get hasSingleTransition() {
        return this.node && this.node.transitions && this.node.transitions.length === 1;
    }

    get isBranching() {
        return this.node && this.node.transitions && this.node.transitions.length > 1;
    }

    // Nœud d'aiguillage vers un sous-parcours, sans transition locale : on
    // propose un bouton de continuation explicite.
    get isNavigationJump() {
        return Boolean(this.node && this.node.isNavigation) && !this.hasTransitions;
    }

    get navigationLabel() {
        return this.node && this.node.parcoursCibleNom
            ? `Continuer vers « ${this.node.parcoursCibleNom} »`
            : 'Continuer';
    }
}
