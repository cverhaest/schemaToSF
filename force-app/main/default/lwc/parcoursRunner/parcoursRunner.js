import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import startSession from '@salesforce/apex/ParcoursRunnerController.startSession';
import getCurrentNode from '@salesforce/apex/ParcoursRunnerController.getCurrentNode';
import submitAndNavigate from '@salesforce/apex/ParcoursRunnerController.submitAndNavigate';

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
    /** Code technique du parcours à exécuter (Parcours__c.Code__c). */
    @api parcoursCode;
    /** Id de l'enregistrement hôte (ex : Case) pour tracer l'origine. */
    @api recordId;
    /** Type de l'enregistrement hôte (ex : Case). */
    @api origineType;

    @track node;
    sessionId;
    isLoading = false;
    isComplete = false;
    errorMessage;

    // Réponses saisies du nœud courant, indexées par Id de champ de saisie.
    answers = {};

    connectedCallback() {
        if (this.parcoursCode) {
            this.begin();
        }
    }

    /** Démarre une nouvelle session de parcours. */
    async begin() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const view = await startSession({
                parcoursCode: this.parcoursCode,
                origineType: this.origineType || null,
                origineId: this.recordId || null,
                accountId: null,
                caseId: this.origineType === 'Case' ? this.recordId : null
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
