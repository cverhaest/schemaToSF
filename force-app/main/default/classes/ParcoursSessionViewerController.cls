/**
 * Reconstruit le chemin réellement parcouru par une session de parcours, pour
 * une visualisation graphique en lecture seule côté LWC (parcoursSessionViewer).
 *
 * Contrairement à ParcoursGraphController — qui expose le graphe statique d'un
 * parcours — ce contrôleur restitue la séquence des nœuds effectivement visités
 * et, pour chaque nœud, la réponse sélectionnée (libellé de la transition
 * choisie) et les valeurs libres saisies. L'ordre vient de l'horodatage des
 * ReponseSaisie__c ; les arêtes relient les nœuds consécutifs du chemin, ce qui
 * reflète fidèlement un éventuel saut vers un sous-parcours.
 *
 * Lecture seule, data-driven : aucune logique propre à un parcours donné.
 */
public with sharing class ParcoursSessionViewerController {
    /**
     * Charge le chemin exécuté d'une session : métadonnées de la session, nœuds
     * visités dans l'ordre chronologique (avec réponse choisie et valeurs
     * saisies) et arêtes reliant les nœuds consécutifs du chemin.
     *
     * @param sessionId Id de la SessionParcours__c à restituer.
     * @return SessionPathDTO structure sérialisable consommée par le LWC.
     * @throws AuraHandledException si l'Id est absent, la session introuvable ou
     *         la lecture refusée par la sécurité.
     * @example
     * ParcoursSessionViewerController.SessionPathDTO p =
     *     ParcoursSessionViewerController.getSessionPath(sessionId);
     */
    @AuraEnabled(cacheable=true)
    public static SessionPathDTO getSessionPath(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('Aucune session fournie.');
        }
        try {
            List<SessionParcours__c> sessions = [
                SELECT
                    Id,
                    Statut__c,
                    DateDebut__c,
                    DateFin__c,
                    NoeudCourant_FK__c,
                    Parcours_FK__r.Name,
                    Agent_FK__r.Name
                FROM SessionParcours__c
                WHERE Id = :sessionId
                WITH USER_MODE
                LIMIT 1
            ];
            if (sessions.isEmpty()) {
                throw new AuraHandledException('Session introuvable.');
            }
            SessionParcours__c session = sessions[0];

            List<ReponseSaisie__c> reponses = [
                SELECT
                    Id,
                    Noeud_FK__c,
                    Noeud_FK__r.Name,
                    Noeud_FK__r.Texte__c,
                    Noeud_FK__r.TypeNoeud__c,
                    Noeud_FK__r.Parcours_FK__r.Name,
                    Transition_FK__c,
                    Transition_FK__r.Libelle_reponse__c,
                    Valeur_libre__c,
                    Horodatage__c
                FROM ReponseSaisie__c
                WHERE Session_FK__c = :sessionId
                WITH USER_MODE
                ORDER BY Horodatage__c ASC NULLS LAST, Name ASC
            ];

            return buildPath(session, reponses);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Impossible de charger le déroulé de la session : ' +
                ex.getMessage()
            );
        }
    }

    /**
     * Assemble le DTO du chemin : agrège les réponses par nœud en préservant
     * l'ordre de première visite, ajoute le nœud courant s'il n'a pas encore de
     * réponse, puis relie les nœuds consécutifs par des arêtes.
     *
     * @param session Session source (déjà hydratée).
     * @param reponses Réponses de la session, triées par horodatage croissant.
     * @return Le chemin sérialisable.
     */
    private static SessionPathDTO buildPath(
        SessionParcours__c session,
        List<ReponseSaisie__c> reponses
    ) {
        // Ordre de première visite + accumulateur par nœud.
        List<Id> orderedNodeIds = new List<Id>();
        Map<Id, StepDTO> stepByNodeId = new Map<Id, StepDTO>();

        for (ReponseSaisie__c reponse : reponses) {
            Id noeudId = reponse.Noeud_FK__c;
            if (noeudId == null) {
                continue;
            }
            StepDTO step = stepByNodeId.get(noeudId);
            if (step == null) {
                step = new StepDTO(reponse);
                stepByNodeId.put(noeudId, step);
                orderedNodeIds.add(noeudId);
            }
            if (
                reponse.Transition_FK__c != null &&
                reponse.Transition_FK__r != null
            ) {
                step.reponse = reponse.Transition_FK__r.Libelle_reponse__c;
            }
            if (String.isNotBlank(reponse.Valeur_libre__c)) {
                step.valeurs.add(reponse.Valeur_libre__c);
            }
        }

        // Nœud courant : s'il n'a pas encore produit de réponse, on l'ajoute en
        // fin de chemin pour marquer l'étape en cours.
        Id currentNodeId = session.NoeudCourant_FK__c;
        if (currentNodeId != null && !stepByNodeId.containsKey(currentNodeId)) {
            StepDTO courant = buildCurrentStep(currentNodeId);
            if (courant != null) {
                stepByNodeId.put(currentNodeId, courant);
                orderedNodeIds.add(currentNodeId);
            }
        }

        SessionPathDTO dto = new SessionPathDTO();
        dto.sessionId = session.Id;
        dto.statut = session.Statut__c;
        dto.dateDebut = session.DateDebut__c;
        dto.dateFin = session.DateFin__c;
        dto.parcoursName = session.Parcours_FK__r != null
            ? session.Parcours_FK__r.Name
            : null;
        dto.agentName = session.Agent_FK__r != null
            ? session.Agent_FK__r.Name
            : null;
        dto.currentNodeId = currentNodeId;
        dto.startNodeId = orderedNodeIds.isEmpty() ? null : orderedNodeIds[0];

        dto.nodes = new List<StepDTO>();
        Integer ordre = 0;
        for (Id noeudId : orderedNodeIds) {
            StepDTO step = stepByNodeId.get(noeudId);
            ordre += 1;
            step.ordre = ordre;
            step.isCurrent = (noeudId == currentNodeId);
            dto.nodes.add(step);
        }

        // Arêtes : chaque couple consécutif du chemin, étiqueté par la réponse
        // choisie au nœud source (le cas échéant).
        dto.edges = new List<EdgeDTO>();
        for (Integer i = 0; i < orderedNodeIds.size() - 1; i++) {
            Id sourceId = orderedNodeIds[i];
            Id targetId = orderedNodeIds[i + 1];
            dto.edges.add(
                new EdgeDTO(
                    sourceId,
                    targetId,
                    stepByNodeId.get(sourceId).reponse
                )
            );
        }
        return dto;
    }

    /**
     * Construit l'étape du nœud courant lorsqu'il n'a encore produit aucune
     * réponse (étape en cours, affichée en bout de chemin).
     *
     * @param nodeId Id du nœud courant.
     * @return L'étape correspondante, ou null si le nœud est introuvable.
     */
    private static StepDTO buildCurrentStep(Id nodeId) {
        List<Noeud__c> noeuds = [
            SELECT Id, Name, Texte__c, TypeNoeud__c, Parcours_FK__r.Name
            FROM Noeud__c
            WHERE Id = :nodeId
            WITH USER_MODE
            LIMIT 1
        ];
        if (noeuds.isEmpty()) {
            return null;
        }
        return new StepDTO(noeuds[0]);
    }

    /**
     * Chemin exécuté sérialisable : métadonnées de la session, nœuds visités
     * (dans l'ordre) et arêtes du chemin.
     */
    public class SessionPathDTO {
        @AuraEnabled
        public Id sessionId;
        @AuraEnabled
        public String parcoursName;
        @AuraEnabled
        public String statut;
        @AuraEnabled
        public Datetime dateDebut;
        @AuraEnabled
        public Datetime dateFin;
        @AuraEnabled
        public String agentName;
        @AuraEnabled
        public Id startNodeId;
        @AuraEnabled
        public Id currentNodeId;
        @AuraEnabled
        public List<StepDTO> nodes;
        @AuraEnabled
        public List<EdgeDTO> edges;
    }

    /**
     * Étape du chemin : un nœud visité, la réponse choisie et les valeurs
     * saisies à ce nœud.
     */
    public class StepDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String texte;
        @AuraEnabled
        public String typeNoeud;
        @AuraEnabled
        public String parcoursNom;
        @AuraEnabled
        public String reponse;
        @AuraEnabled
        public List<String> valeurs;
        @AuraEnabled
        public Integer ordre;
        @AuraEnabled
        public Boolean isCurrent;

        /** @param reponse Réponse saisie dont on projette le nœud. */
        public StepDTO(ReponseSaisie__c reponse) {
            this.id = reponse.Noeud_FK__c;
            this.valeurs = new List<String>();
            this.isCurrent = false;
            if (reponse.Noeud_FK__r != null) {
                this.name = reponse.Noeud_FK__r.Name;
                this.texte = reponse.Noeud_FK__r.Texte__c;
                this.typeNoeud = reponse.Noeud_FK__r.TypeNoeud__c;
                this.parcoursNom = reponse.Noeud_FK__r.Parcours_FK__r != null
                    ? reponse.Noeud_FK__r.Parcours_FK__r.Name
                    : null;
            }
        }

        /** @param noeud Nœud courant (étape sans réponse encore saisie). */
        public StepDTO(Noeud__c noeud) {
            this.id = noeud.Id;
            this.name = noeud.Name;
            this.texte = noeud.Texte__c;
            this.typeNoeud = noeud.TypeNoeud__c;
            this.parcoursNom = noeud.Parcours_FK__r != null
                ? noeud.Parcours_FK__r.Name
                : null;
            this.valeurs = new List<String>();
            this.isCurrent = false;
        }
    }

    /**
     * Arête orientée du chemin (nœud source → nœud suivant), étiquetée par la
     * réponse choisie au nœud source.
     */
    public class EdgeDTO {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public Id source;
        @AuraEnabled
        public Id target;
        @AuraEnabled
        public String libelle;

        /**
         * @param source Nœud source du franchissement.
         * @param target Nœud atteint ensuite.
         * @param libelle Réponse choisie au nœud source (facultative).
         */
        public EdgeDTO(Id source, Id target, String libelle) {
            this.id = source + '-' + target;
            this.source = source;
            this.target = target;
            this.libelle = libelle;
        }
    }
}
