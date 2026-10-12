/**
 * Fabrique de données de test pour le moteur de parcours.
 *
 * Centralise la création des enregistrements Parcours__c, Noeud__c,
 * ChampSaisie__c, SessionParcours__c et ReponseSaisie__c afin que les classes
 * de test ne construisent jamais de données en ligne.
 */
@isTest
public class TestDataFactory {
    /**
     * Crée un parcours actif.
     *
     * @param code Code technique unique du parcours.
     * @param doInsert Insère l'enregistrement si vrai.
     * @return Le Parcours__c créé.
     */
    public static Parcours__c createParcours(String code, Boolean doInsert) {
        Parcours__c parcours = new Parcours__c(
            Name = 'Parcours ' + code,
            Code__c = code,
            Version__c = 1,
            Statut__c = 'Actif',
            Categorie__c = 'Eau potable'
        );
        if (doInsert) {
            insert parcours;
        }
        return parcours;
    }

    /**
     * Crée un nœud d'action rattaché à un parcours.
     *
     * @param parcoursId Parcours parent.
     * @param cle Clé lisible du nœud.
     * @param typeAction Verbe DML (Créer, Mettre à jour, Supprimer, Upsert).
     * @param objetCible API name de l'objet cible.
     * @param mappageJson Table de mappage champ -> valeur sérialisée.
     * @param doInsert Insère l'enregistrement si vrai.
     * @return Le Noeud__c créé.
     */
    public static Noeud__c createActionNode(
        Id parcoursId,
        String cle,
        String typeAction,
        String objetCible,
        String mappageJson,
        Boolean doInsert
    ) {
        Noeud__c noeud = new Noeud__c(
            Name = cle,
            Parcours_FK__c = parcoursId,
            TypeNoeud__c = 'Action',
            TypeAction__c = typeAction,
            ObjetCible__c = objetCible,
            MappageChamps_JSON__c = mappageJson
        );
        if (doInsert) {
            insert noeud;
        }
        return noeud;
    }

    /**
     * Crée un nœud générique (type paramétrable, sans action).
     *
     * @param parcoursId Parcours parent.
     * @param cle Clé lisible du nœud.
     * @param typeNoeud Type du nœud (Question, Conseil, Fin...).
     * @param doInsert Insère l'enregistrement si vrai.
     * @return Le Noeud__c créé.
     */
    public static Noeud__c createNode(
        Id parcoursId,
        String cle,
        String typeNoeud,
        Boolean doInsert
    ) {
        Noeud__c noeud = new Noeud__c(
            Name = cle,
            Parcours_FK__c = parcoursId,
            TypeNoeud__c = typeNoeud
        );
        if (doInsert) {
            insert noeud;
        }
        return noeud;
    }

    /**
     * Crée une transition orientée entre deux nœuds.
     *
     * @param sourceId Nœud source.
     * @param cibleId Nœud cible.
     * @param libelle Libellé de la réponse portée par l'arête.
     * @param ordre Ordre d'affichage (ne pilote pas le routage).
     * @param doInsert Insère l'enregistrement si vrai.
     * @return La Transition__c créée.
     */
    public static Transition__c createTransition(
        Id sourceId,
        Id cibleId,
        String libelle,
        Decimal ordre,
        Boolean doInsert
    ) {
        Transition__c transition = new Transition__c(
            NoeudSource_FK__c = sourceId,
            NoeudCible_FK__c = cibleId,
            Libelle_reponse__c = libelle,
            Ordre__c = ordre
        );
        if (doInsert) {
            insert transition;
        }
        return transition;
    }

    /**
     * Crée un champ de saisie rattaché à un nœud question.
     *
     * @param noeudId Nœud parent.
     * @param libelle Libellé du champ.
     * @param typeChamp Type de saisie.
     * @param mappageCible Jeton logique exposé au mappage d'action.
     * @param doInsert Insère l'enregistrement si vrai.
     * @return Le ChampSaisie__c créé.
     */
    public static ChampSaisie__c createChampSaisie(
        Id noeudId,
        String libelle,
        String typeChamp,
        String mappageCible,
        Boolean doInsert
    ) {
        ChampSaisie__c champ = new ChampSaisie__c(
            Noeud_FK__c = noeudId,
            Libelle__c = libelle,
            TypeChamp__c = typeChamp,
            MappageCible__c = mappageCible,
            Ordre__c = 1
        );
        if (doInsert) {
            insert champ;
        }
        return champ;
    }

    /**
     * Crée une session de parcours en cours.
     *
     * @param parcoursId Parcours exécuté.
     * @param accountId Compte lié (facultatif).
     * @param caseId Requête liée (facultatif).
     * @param doInsert Insère l'enregistrement si vrai.
     * @return La SessionParcours__c créée.
     */
    public static SessionParcours__c createSession(
        Id parcoursId,
        Id accountId,
        Id caseId,
        Boolean doInsert
    ) {
        SessionParcours__c session = new SessionParcours__c(
            Parcours_FK__c = parcoursId,
            Account_FK_option__c = accountId,
            Case_FK_option__c = caseId,
            OrigineType__c = 'Case',
            Statut__c = 'En cours',
            DateDebut__c = System.now()
        );
        if (doInsert) {
            insert session;
        }
        return session;
    }

    /**
     * Crée une réponse saisie pour une session et un nœud.
     *
     * @param sessionId Session parente (master-detail).
     * @param noeudId Nœud de saisie.
     * @param valeur Valeur libre renseignée.
     * @param doInsert Insère l'enregistrement si vrai.
     * @return La ReponseSaisie__c créée.
     */
    public static ReponseSaisie__c createReponse(
        Id sessionId,
        Id noeudId,
        String valeur,
        Boolean doInsert
    ) {
        ReponseSaisie__c reponse = new ReponseSaisie__c(
            Session_FK__c = sessionId,
            Noeud_FK__c = noeudId,
            Valeur_libre__c = valeur,
            Horodatage__c = System.now()
        );
        if (doInsert) {
            insert reponse;
        }
        return reponse;
    }

    /**
     * Crée un compte simple.
     *
     * @param nom Nom du compte.
     * @param doInsert Insère l'enregistrement si vrai.
     * @return L'Account créé.
     */
    public static Account createAccount(String nom, Boolean doInsert) {
        Account compte = new Account(Name = nom);
        if (doInsert) {
            insert compte;
        }
        return compte;
    }
}
