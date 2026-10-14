/**
 * Contrôleur du moteur générique de parcours (LWC parcoursRunner).
 *
 * Traverse le parcours comme un graphe : le nœud de départ vient de
 * Parcours__c.NoeudDepart_FK, les arêtes sont des Transition__c. Un nœud à une
 * seule transition sortante est linéaire ; plusieurs transitions = embranchement.
 * Ordre ne sert qu'à l'affichage, jamais au routage.
 *
 * Le contrôleur ouvre une session, renvoie le nœud courant à afficher, persiste
 * les réponses saisies, délègue l'exécution des nœuds d'action à
 * ParcoursActionHandler, puis avance le pointeur de session vers le nœud cible.
 */
public with sharing class ParcoursRunnerController {
    private static final String STATUT_EN_COURS = 'En cours';
    private static final String STATUT_TERMINE = 'Terminé';
    private static final String TYPE_FIN = 'Fin';
    private static final String TYPE_ACTION = 'Action';
    private static final String TYPE_NAVIGATION = 'Navigation';

    /**
     * Démarre une session de parcours à partir de son code technique.
     *
     * @param parcoursCode Code unique du parcours (Parcours__c.Code__c).
     * @param origineType Type de l'enregistrement d'origine (ex : Case).
     * @param origineId Id de l'enregistrement d'origine.
     * @param accountId Compte lié (facultatif).
     * @param caseId Requête liée (facultatif).
     * @return La vue du nœud de départ.
     */
    @AuraEnabled
    public static NodeView startSession(
        String parcoursCode,
        String origineType,
        String origineId,
        Id accountId,
        Id caseId
    ) {
        try {
            if (String.isBlank(parcoursCode)) {
                throw new AuraHandledException('Le code du parcours est obligatoire.');
            }

            List<Parcours__c> parcours = [
                SELECT Id, NoeudDepart_FK__c
                FROM Parcours__c
                WHERE Code__c = :parcoursCode AND Statut__c = 'Actif'
                WITH USER_MODE
                LIMIT 1
            ];
            if (parcours.isEmpty()) {
                throw new AuraHandledException('Parcours actif introuvable : ' + parcoursCode);
            }
            if (parcours[0].NoeudDepart_FK__c == null) {
                throw new AuraHandledException('Aucun nœud de départ défini sur le parcours.');
            }

            SessionParcours__c session = new SessionParcours__c(
                Parcours_FK__c = parcours[0].Id,
                OrigineType__c = origineType,
                OrigineId__c = origineId,
                Account_FK_option__c = accountId,
                Case_FK_option__c = caseId,
                NoeudCourant_FK__c = parcours[0].NoeudDepart_FK__c,
                Statut__c = STATUT_EN_COURS,
                DateDebut__c = System.now(),
                Agent_FK__c = UserInfo.getUserId()
            );
            insert as user session;

            return buildNodeView(session.Id, parcours[0].NoeudDepart_FK__c);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Impossible de démarrer le parcours : ' + e.getMessage());
        }
    }

    /**
     * Liste les parcours actifs démarrables (nœud de départ défini), pour la
     * sélection par tuiles lorsque le composant n'est pas configuré avec un code.
     *
     * @return Les parcours actifs triés par catégorie puis par nom.
     */
    @AuraEnabled(cacheable=true)
    public static List<ParcoursTile> getParcoursActifs() {
        try {
            List<ParcoursTile> tiles = new List<ParcoursTile>();
            for (Parcours__c parcours : [
                SELECT Id, Name, Code__c, toLabel(Categorie__c), Version__c
                FROM Parcours__c
                WHERE Statut__c = 'Actif' AND NoeudDepart_FK__c != null
                WITH USER_MODE
                ORDER BY Categorie__c, Name
                LIMIT 1000
            ]) {
                ParcoursTile tile = new ParcoursTile();
                tile.parcoursId = parcours.Id;
                tile.name = parcours.Name;
                tile.code = parcours.Code__c;
                tile.categorie = parcours.Categorie__c;
                tile.version = parcours.Version__c;
                tiles.add(tile);
            }
            return tiles;
        } catch (Exception e) {
            throw new AuraHandledException('Impossible de charger les parcours : ' + e.getMessage());
        }
    }

    /**
     * Renvoie la vue du nœud courant d'une session.
     *
     * @param sessionId Identifiant de la session.
     * @return La vue du nœud courant.
     */
    @AuraEnabled
    public static NodeView getCurrentNode(Id sessionId) {
        try {
            SessionParcours__c session = loadSession(sessionId);
            if (session.NoeudCourant_FK__c == null) {
                throw new AuraHandledException('La session n\'a plus de nœud courant.');
            }
            return buildNodeView(sessionId, session.NoeudCourant_FK__c);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Impossible de charger le nœud : ' + e.getMessage());
        }
    }

    /**
     * Persiste les réponses du nœud courant, joue son action éventuelle, puis
     * avance la session vers le nœud cible choisi.
     *
     * @param sessionId Identifiant de la session.
     * @param nodeId Nœud courant soumis.
     * @param answersJson Réponses saisies, sérialisées { champSaisieId: valeur }.
     * @param transitionId Transition choisie (null si une seule sortie / fin).
     * @return La vue du nœud suivant, ou du nœud terminal si le parcours s'achève.
     */
    @AuraEnabled
    public static NodeView submitAndNavigate(
        Id sessionId,
        Id nodeId,
        String answersJson,
        Id transitionId
    ) {
        try {
            if (sessionId == null || nodeId == null) {
                throw new AuraHandledException('Session et nœud sont obligatoires.');
            }

            persistAnswers(sessionId, nodeId, answersJson, transitionId);

            Noeud__c noeud = loadNoeud(nodeId);
            if (noeud.TypeNoeud__c == TYPE_ACTION) {
                ParcoursActionHandler.executeNodeAction(sessionId, nodeId);
            }

            // Aiguillage vers un sous-parcours : un nœud Navigation porteur d'un
            // parcours cible EST un saut. Il enchaîne sur le nœud de départ de ce
            // parcours et la session bascule sur le parcours cible, en ignorant
            // d'éventuelles transitions locales (le saut est prioritaire).
            Id nextNodeId;
            if (
                noeud.TypeNoeud__c == TYPE_NAVIGATION &&
                noeud.ParcoursCible_FK__c != null
            ) {
                nextNodeId = loadParcoursStart(noeud.ParcoursCible_FK__c);
                advanceSession(sessionId, nextNodeId, noeud.ParcoursCible_FK__c);
            } else {
                nextNodeId = resolveNextNode(nodeId, transitionId);
                advanceSession(sessionId, nextNodeId, null);
            }

            if (nextNodeId == null) {
                return null;
            }
            return buildNodeView(sessionId, nextNodeId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Navigation impossible : ' + e.getMessage());
        }
    }

    /**
     * Construit la vue d'un nœud : son texte, ses champs de saisie et ses
     * transitions sortantes (triées par Ordre pour l'affichage).
     *
     * @param sessionId Session courante.
     * @param nodeId Nœud à afficher.
     * @return La vue structurée du nœud.
     */
    private static NodeView buildNodeView(Id sessionId, Id nodeId) {
        Noeud__c noeud = loadNoeud(nodeId);

        NodeView view = new NodeView();
        view.sessionId = sessionId;
        view.nodeId = noeud.Id;
        view.name = noeud.Name;
        view.typeNoeud = noeud.TypeNoeud__c;
        view.texte = noeud.Texte__c;
        view.isFin = (noeud.TypeNoeud__c == TYPE_FIN);
        // Nom du parcours porteur du nœud : suit automatiquement les sauts de
        // Navigation vers un sous-parcours.
        view.parcoursNom = noeud.Parcours_FK__r?.Name;
        // Nœud d'aiguillage vers un autre parcours : on expose le libellé cible
        // pour que le LWC propose un bouton de continuation explicite.
        view.isNavigation =
            (noeud.TypeNoeud__c == TYPE_NAVIGATION && noeud.ParcoursCible_FK__c != null);
        view.parcoursCibleNom =
            noeud.ParcoursCible_FK__r != null ? noeud.ParcoursCible_FK__r.Name : null;

        view.champs = new List<FieldView>();
        for (ChampSaisie__c champ : [
            SELECT Id, Libelle__c, TypeChamp__c, MappageCible__c, Ordre__c
            FROM ChampSaisie__c
            WHERE Noeud_FK__c = :nodeId
            WITH USER_MODE
            ORDER BY Ordre__c ASC NULLS LAST
        ]) {
            FieldView field = new FieldView();
            field.champId = champ.Id;
            field.libelle = champ.Libelle__c;
            field.typeChamp = champ.TypeChamp__c;
            field.mappageCible = champ.MappageCible__c;
            view.champs.add(field);
        }

        view.transitions = new List<TransitionView>();
        for (Transition__c transition : [
            SELECT Id, Libelle_reponse__c, NoeudCible_FK__c, Ordre__c
            FROM Transition__c
            WHERE NoeudSource_FK__c = :nodeId
            WITH USER_MODE
            ORDER BY Ordre__c ASC NULLS LAST
        ]) {
            TransitionView tr = new TransitionView();
            tr.transitionId = transition.Id;
            tr.libelleReponse = transition.Libelle_reponse__c;
            tr.noeudCibleId = transition.NoeudCible_FK__c;
            view.transitions.add(tr);
        }
        return view;
    }

    /**
     * Enregistre les réponses saisies du nœud et, le cas échéant, le choix de
     * transition, le tout rattaché à la session.
     *
     * @param sessionId Session courante.
     * @param nodeId Nœud soumis.
     * @param answersJson Réponses { champSaisieId: valeur }.
     * @param transitionId Transition choisie (facultative).
     */
    private static void persistAnswers(
        Id sessionId,
        Id nodeId,
        String answersJson,
        Id transitionId
    ) {
        List<ReponseSaisie__c> reponses = new List<ReponseSaisie__c>();

        if (String.isNotBlank(answersJson)) {
            Map<String, Object> parsed;
            try {
                parsed = (Map<String, Object>) JSON.deserializeUntyped(answersJson);
            } catch (JSONException e) {
                throw new AuraHandledException('Réponses JSON invalides : ' + e.getMessage());
            }
            for (String key : parsed.keySet()) {
                Object valeur = parsed.get(key);
                reponses.add(new ReponseSaisie__c(
                    Session_FK__c = sessionId,
                    Noeud_FK__c = nodeId,
                    Valeur_libre__c = valeur == null ? null : String.valueOf(valeur),
                    Horodatage__c = System.now()
                ));
            }
        }

        if (transitionId != null) {
            reponses.add(new ReponseSaisie__c(
                Session_FK__c = sessionId,
                Noeud_FK__c = nodeId,
                Transition_FK__c = transitionId,
                Horodatage__c = System.now()
            ));
        }

        if (!reponses.isEmpty()) {
            insert as user reponses;
        }
    }

    /**
     * Détermine le nœud suivant : la cible de la transition choisie, ou l'unique
     * transition sortante si le nœud est linéaire, sinon null (fin de branche).
     *
     * @param nodeId Nœud courant.
     * @param transitionId Transition choisie (facultative).
     * @return L'identifiant du nœud suivant ou null.
     */
    private static Id resolveNextNode(Id nodeId, Id transitionId) {
        if (transitionId != null) {
            List<Transition__c> choisies = [
                SELECT NoeudCible_FK__c
                FROM Transition__c
                WHERE Id = :transitionId
                WITH USER_MODE
                LIMIT 1
            ];
            return choisies.isEmpty() ? null : choisies[0].NoeudCible_FK__c;
        }

        List<Transition__c> sorties = [
            SELECT NoeudCible_FK__c
            FROM Transition__c
            WHERE NoeudSource_FK__c = :nodeId
            WITH USER_MODE
            LIMIT 2
        ];
        if (sorties.size() == 1) {
            return sorties[0].NoeudCible_FK__c;
        }
        return null;
    }

    /**
     * Avance le pointeur de session vers le nœud cible ; clôt la session quand
     * la branche se termine ou atteint un nœud de type Fin. Lors d'un aiguillage
     * vers un sous-parcours, bascule aussi le parcours courant de la session pour
     * que le suivi reflète le parcours réellement déroulé.
     *
     * @param sessionId Session à mettre à jour.
     * @param nextNodeId Nœud cible (null si fin de branche).
     * @param nouveauParcoursId Parcours cible lors d'un saut (null sinon).
     */
    private static void advanceSession(
        Id sessionId,
        Id nextNodeId,
        Id nouveauParcoursId
    ) {
        SessionParcours__c session = new SessionParcours__c(Id = sessionId);
        session.NoeudCourant_FK__c = nextNodeId;
        if (nouveauParcoursId != null) {
            session.Parcours_FK__c = nouveauParcoursId;
        }

        Boolean termine = (nextNodeId == null);
        if (!termine) {
            termine = (loadNoeud(nextNodeId).TypeNoeud__c == TYPE_FIN);
        }
        if (termine) {
            session.Statut__c = STATUT_TERMINE;
            session.DateFin__c = System.now();
        }
        update as user session;
    }

    /**
     * Résout le nœud de départ d'un parcours cible actif, pour un aiguillage.
     *
     * @param parcoursId Identifiant du parcours cible.
     * @return L'identifiant de son nœud de départ.
     */
    private static Id loadParcoursStart(Id parcoursId) {
        List<Parcours__c> cibles = [
            SELECT Id, NoeudDepart_FK__c, Statut__c
            FROM Parcours__c
            WHERE Id = :parcoursId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cibles.isEmpty()) {
            throw new AuraHandledException('Parcours cible introuvable.');
        }
        if (cibles[0].Statut__c != 'Actif') {
            throw new AuraHandledException(
                'Le parcours cible n\'est pas actif.'
            );
        }
        if (cibles[0].NoeudDepart_FK__c == null) {
            throw new AuraHandledException(
                'Le parcours cible n\'a pas de nœud de départ.'
            );
        }
        return cibles[0].NoeudDepart_FK__c;
    }

    /**
     * Charge une session et son nœud courant.
     *
     * @param sessionId Identifiant de la session.
     * @return La session hydratée.
     */
    private static SessionParcours__c loadSession(Id sessionId) {
        List<SessionParcours__c> sessions = [
            SELECT Id, NoeudCourant_FK__c, Statut__c
            FROM SessionParcours__c
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            throw new AuraHandledException('Session introuvable : ' + sessionId);
        }
        return sessions[0];
    }

    /**
     * Charge un nœud et ses attributs d'affichage.
     *
     * @param nodeId Identifiant du nœud.
     * @return Le nœud hydraté.
     */
    private static Noeud__c loadNoeud(Id nodeId) {
        List<Noeud__c> noeuds = [
            SELECT Id, Name, TypeNoeud__c, Texte__c, Parcours_FK__r.Name,
                   ParcoursCible_FK__c, ParcoursCible_FK__r.Name
            FROM Noeud__c
            WHERE Id = :nodeId
            WITH USER_MODE
            LIMIT 1
        ];
        if (noeuds.isEmpty()) {
            throw new AuraHandledException('Nœud introuvable : ' + nodeId);
        }
        return noeuds[0];
    }

    /**
     * Tuile de sélection d'un parcours exposée au composant LWC.
     */
    public class ParcoursTile {
        @AuraEnabled public Id parcoursId;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public String categorie;
        @AuraEnabled public Decimal version;
    }

    /**
     * Vue d'un nœud exposée au composant LWC.
     */
    public class NodeView {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public Id nodeId;
        @AuraEnabled public String name;
        @AuraEnabled public String typeNoeud;
        @AuraEnabled public String texte;
        @AuraEnabled public String parcoursNom;
        @AuraEnabled public Boolean isFin;
        @AuraEnabled public Boolean isNavigation;
        @AuraEnabled public String parcoursCibleNom;
        @AuraEnabled public List<FieldView> champs;
        @AuraEnabled public List<TransitionView> transitions;
    }

    /**
     * Vue d'un champ de saisie.
     */
    public class FieldView {
        @AuraEnabled public Id champId;
        @AuraEnabled public String libelle;
        @AuraEnabled public String typeChamp;
        @AuraEnabled public String mappageCible;
    }

    /**
     * Vue d'une transition sortante.
     */
    public class TransitionView {
        @AuraEnabled public Id transitionId;
        @AuraEnabled public String libelleReponse;
        @AuraEnabled public Id noeudCibleId;
    }
}
