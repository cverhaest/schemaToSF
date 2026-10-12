/**
 * Fournit la structure complète d'un parcours métier (nœuds + transitions) pour
 * une visualisation graphique côté LWC. Lecture seule, data-driven : aucune
 * logique spécifique à un parcours donné n'est codée ici.
 */
public with sharing class ParcoursGraphController {
    /**
     * Charge le graphe d'un parcours : son nœud de départ, l'ensemble de ses
     * nœuds et toutes les transitions sortantes de ces nœuds.
     *
     * @param parcoursId Id du Parcours__c à charger.
     * @return ParcoursGraphDTO structure sérialisable consommée par le LWC.
     * @throws AuraHandledException si l'Id est absent, le parcours introuvable
     *         ou la lecture refusée par la sécurité.
     * @example
     * ParcoursGraphController.ParcoursGraphDTO g =
     *     ParcoursGraphController.getGraph(parcoursId);
     */
    @AuraEnabled(cacheable=true)
    public static ParcoursGraphDTO getGraph(Id parcoursId) {
        if (parcoursId == null) {
            throw new AuraHandledException('Aucun parcours fourni.');
        }
        try {
            List<Parcours__c> parcoursList = [
                SELECT Id, Name, Code__c, Statut__c, NoeudDepart_FK__c
                FROM Parcours__c
                WHERE Id = :parcoursId
                WITH USER_MODE
                LIMIT 1
            ];
            if (parcoursList.isEmpty()) {
                throw new AuraHandledException('Parcours introuvable.');
            }
            Parcours__c parcours = parcoursList[0];

            List<Noeud__c> noeuds = [
                SELECT Id, Name, TypeNoeud__c, Texte__c, TypeAction__c,
                    ObjetCible__c, CodePresta__c, ParcoursCible_FK__c
                FROM Noeud__c
                WHERE Parcours_FK__c = :parcoursId
                WITH USER_MODE
                ORDER BY Name
            ];

            Set<Id> noeudIds = new Map<Id, Noeud__c>(noeuds).keySet();

            // Une clause IN sur un Set vide est du SOQL valide (0 ligne) :
            // inutile de brancher, ce qui garde la méthode simple.
            List<Transition__c> transitions = [
                SELECT Id, Name, NoeudSource_FK__c, NoeudCible_FK__c,
                    Libelle_reponse__c, Ordre__c
                FROM Transition__c
                WHERE NoeudSource_FK__c IN :noeudIds
                WITH USER_MODE
                ORDER BY Ordre__c NULLS LAST
            ];

            return new ParcoursGraphDTO(parcours, noeuds, transitions);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Impossible de charger le parcours : ' + ex.getMessage()
            );
        }
    }

    /**
     * Graphe sérialisable d'un parcours : métadonnées du parcours, nœuds et arêtes.
     */
    public class ParcoursGraphDTO {
        @AuraEnabled
        public Id parcoursId;
        @AuraEnabled
        public String parcoursName;
        @AuraEnabled
        public String code;
        @AuraEnabled
        public String statut;
        @AuraEnabled
        public Id startNodeId;
        @AuraEnabled
        public List<NodeDTO> nodes;
        @AuraEnabled
        public List<EdgeDTO> edges;

        /**
         * @param parcours Parcours source.
         * @param noeuds Nœuds du parcours.
         * @param transitions Transitions sortantes des nœuds.
         */
        public ParcoursGraphDTO(
            Parcours__c parcours,
            List<Noeud__c> noeuds,
            List<Transition__c> transitions
        ) {
            this.parcoursId = parcours.Id;
            this.parcoursName = parcours.Name;
            this.code = parcours.Code__c;
            this.statut = parcours.Statut__c;
            this.startNodeId = parcours.NoeudDepart_FK__c;
            this.nodes = new List<NodeDTO>();
            for (Noeud__c noeud : noeuds) {
                this.nodes.add(new NodeDTO(noeud));
            }
            this.edges = new List<EdgeDTO>();
            for (Transition__c transition : transitions) {
                this.edges.add(new EdgeDTO(transition));
            }
        }
    }

    /**
     * Représentation légère d'un nœud du parcours.
     */
    public class NodeDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String typeNoeud;
        @AuraEnabled
        public String texte;
        @AuraEnabled
        public String typeAction;
        @AuraEnabled
        public String objetCible;
        @AuraEnabled
        public String codePresta;
        @AuraEnabled
        public Id parcoursCibleId;

        /** @param noeud Nœud source à projeter. */
        public NodeDTO(Noeud__c noeud) {
            this.id = noeud.Id;
            this.name = noeud.Name;
            this.typeNoeud = noeud.TypeNoeud__c;
            this.texte = noeud.Texte__c;
            this.typeAction = noeud.TypeAction__c;
            this.objetCible = noeud.ObjetCible__c;
            this.codePresta = noeud.CodePresta__c;
            this.parcoursCibleId = noeud.ParcoursCible_FK__c;
        }
    }

    /**
     * Représentation légère d'une transition (arête orientée source → cible).
     */
    public class EdgeDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Id source;
        @AuraEnabled
        public Id target;
        @AuraEnabled
        public String libelle;
        @AuraEnabled
        public Decimal ordre;

        /** @param transition Transition source à projeter. */
        public EdgeDTO(Transition__c transition) {
            this.id = transition.Id;
            this.name = transition.Name;
            this.source = transition.NoeudSource_FK__c;
            this.target = transition.NoeudCible_FK__c;
            this.libelle = transition.Libelle_reponse__c;
            this.ordre = transition.Ordre__c;
        }
    }
}
