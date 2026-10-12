/**
 * Moteur générique d'exécution des actions d'un parcours métier.
 *
 * Un nœud de type « Action » porte un verbe DML (TypeAction__c), un objet cible
 * (ObjetCible__c) et une table de correspondance champ -> valeur sérialisée en
 * JSON (MappageChamps_JSON__c). Cette classe lit ces métadonnées, résout les
 * jetons dynamiques ({client}, {case}, {noeud.CodePresta}, TODAY+N, {champ}),
 * convertit les valeurs vers le type réel des champs de l'objet cible, puis
 * joue l'opération DML en mode utilisateur. Chaque exécution est tracée dans
 * ActionExecutee__c, ce qui rend les relances idempotentes.
 *
 * Une seule classe sert tous les parcours : ajouter un parcours = ajouter des
 * données, sans nouveau code ni déploiement.
 */
public with sharing class ParcoursActionHandler {
    @TestVisible
    private static final String ACTION_CREER = 'Créer';
    @TestVisible
    private static final String ACTION_METTRE_A_JOUR = 'Mettre à jour';
    @TestVisible
    private static final String ACTION_SUPPRIMER = 'Supprimer';
    @TestVisible
    private static final String ACTION_UPSERT = 'Upsert';

    private static final String STATUT_OK = 'OK';
    private static final String STATUT_ERREUR = 'Erreur';
    private static final String TYPE_NOEUD_ACTION = 'Action';

    private static final Pattern TODAY_PATTERN = Pattern.compile('(?i)^TODAY([+-]\\d+)?$');

    /**
     * Exception métier levée lorsqu'un nœud d'action ne peut pas être joué.
     */
    public class ParcoursActionException extends Exception {}

    /**
     * Joue l'action portée par un nœud dans le contexte d'une session.
     *
     * @param sessionId Identifiant de la SessionParcours__c en cours.
     * @param noeudId Identifiant du Noeud__c de type « Action » à exécuter.
     * @return L'ActionExecutee__c persistée (statut OK ou Erreur).
     * @example
     * ActionExecutee__c trace = ParcoursActionHandler.executeNodeAction(sessionId, noeudId);
     */
    public static ActionExecutee__c executeNodeAction(Id sessionId, Id noeudId) {
        if (sessionId == null || noeudId == null) {
            throw new ParcoursActionException('La session et le nœud sont obligatoires.');
        }

        SessionParcours__c session = loadSession(sessionId);
        Noeud__c noeud = loadNoeud(noeudId);

        if (noeud.TypeNoeud__c != TYPE_NOEUD_ACTION) {
            throw new ParcoursActionException(
                'Le nœud ' + noeud.Name + ' n\'est pas un nœud d\'action.'
            );
        }

        // Idempotence : une action déjà jouée avec succès pour ce couple
        // session / nœud n'est pas rejouée.
        ActionExecutee__c existante = findExistingSuccess(sessionId, noeudId);
        if (existante != null) {
            return existante;
        }

        ActionExecutee__c trace = new ActionExecutee__c(
            Session_FK__c = sessionId,
            Noeud_FK__c = noeudId,
            TypeAction__c = noeud.TypeAction__c
        );

        try {
            if (String.isBlank(noeud.ObjetCible__c)) {
                throw new ParcoursActionException(
                    'Aucun objet cible défini sur le nœud ' + noeud.Name + '.'
                );
            }

            Map<String, Object> tokenContext = buildTokenContext(session, noeud);
            Map<String, Object> rawFields = parseMapping(noeud.MappageChamps_JSON__c);
            SObject record = buildRecord(noeud.ObjetCible__c, rawFields, tokenContext);

            Id recordId = performDml(noeud.TypeAction__c, noeud.ObjetCible__c, record);

            trace.RecordCreeId__c = recordId;
            trace.Statut__c = STATUT_OK;
        } catch (Exception e) {
            trace.Statut__c = STATUT_ERREUR;
            trace.Message__c = e.getMessage();
        }

        insert as user trace;
        return trace;
    }

    /**
     * Charge la session et les champs de contexte nécessaires à la résolution
     * des jetons.
     *
     * @param sessionId Identifiant de la session.
     * @return La SessionParcours__c hydratée.
     */
    private static SessionParcours__c loadSession(Id sessionId) {
        List<SessionParcours__c> sessions = [
            SELECT Id, Account_FK_option__c, Case_FK_option__c,
                   OrigineType__c, OrigineId__c, Parcours_FK__c
            FROM SessionParcours__c
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            throw new ParcoursActionException('Session introuvable : ' + sessionId);
        }
        return sessions[0];
    }

    /**
     * Charge le nœud d'action et ses métadonnées de mappage.
     *
     * @param noeudId Identifiant du nœud.
     * @return Le Noeud__c hydraté.
     */
    private static Noeud__c loadNoeud(Id noeudId) {
        List<Noeud__c> noeuds = [
            SELECT Id, Name, TypeNoeud__c, TypeAction__c, ObjetCible__c,
                   CodePresta__c, MappageChamps_JSON__c
            FROM Noeud__c
            WHERE Id = :noeudId
            WITH USER_MODE
            LIMIT 1
        ];
        if (noeuds.isEmpty()) {
            throw new ParcoursActionException('Nœud introuvable : ' + noeudId);
        }
        return noeuds[0];
    }

    /**
     * Recherche une action déjà jouée avec succès pour éviter les doublons.
     *
     * @param sessionId Identifiant de la session.
     * @param noeudId Identifiant du nœud.
     * @return La trace existante ou null.
     */
    private static ActionExecutee__c findExistingSuccess(Id sessionId, Id noeudId) {
        List<ActionExecutee__c> existantes = [
            SELECT Id, RecordCreeId__c, Statut__c, TypeAction__c
            FROM ActionExecutee__c
            WHERE Session_FK__c = :sessionId
              AND Noeud_FK__c = :noeudId
              AND Statut__c = :STATUT_OK
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return existantes.isEmpty() ? null : existantes[0];
    }

    /**
     * Construit la table des jetons disponibles pour la résolution.
     *
     * @param session Session courante (porte client et case éventuels).
     * @param noeud Nœud courant (porte le code prestation).
     * @return Table jeton -> valeur.
     */
    private static Map<String, Object> buildTokenContext(
        SessionParcours__c session,
        Noeud__c noeud
    ) {
        Map<String, Object> context = new Map<String, Object>();
        context.put('client', session.Account_FK_option__c);
        context.put('case', session.Case_FK_option__c);
        context.put('session', session.Id);
        context.put('noeud.CodePresta', noeud.CodePresta__c);

        // Réponses saisies de la session, indexées par leur champ cible
        // (MappageCible du ChampSaisie__c correspondant).
        for (AggregateReponse ar : loadAnswers(session.Id)) {
            if (String.isNotBlank(ar.cle)) {
                context.put(ar.cle, ar.valeur);
            }
        }
        return context;
    }

    /**
     * Charge les réponses saisies, résolues en couples champ-cible / valeur.
     *
     * @param sessionId Identifiant de la session.
     * @return Liste de correspondances clé / valeur.
     */
    private static List<AggregateReponse> loadAnswers(Id sessionId) {
        // On relie chaque réponse au champ de saisie de son nœud pour récupérer
        // le MappageCible (le nom logique du jeton exposé au mappage d'action).
        Map<Id, String> cibleParNoeud = new Map<Id, String>();
        List<ReponseSaisie__c> reponses = [
            SELECT Valeur_libre__c, Noeud_FK__c
            FROM ReponseSaisie__c
            WHERE Session_FK__c = :sessionId
            WITH USER_MODE
        ];
        if (reponses.isEmpty()) {
            return new List<AggregateReponse>();
        }

        Set<Id> noeudIds = new Set<Id>();
        for (ReponseSaisie__c r : reponses) {
            if (r.Noeud_FK__c != null) {
                noeudIds.add(r.Noeud_FK__c);
            }
        }

        for (ChampSaisie__c champ : [
            SELECT Noeud_FK__c, MappageCible__c
            FROM ChampSaisie__c
            WHERE Noeud_FK__c IN :noeudIds
            WITH USER_MODE
        ]) {
            if (String.isNotBlank(champ.MappageCible__c)) {
                cibleParNoeud.put(champ.Noeud_FK__c, champ.MappageCible__c);
            }
        }

        List<AggregateReponse> resultats = new List<AggregateReponse>();
        for (ReponseSaisie__c r : reponses) {
            String cle = cibleParNoeud.get(r.Noeud_FK__c);
            resultats.add(new AggregateReponse(cle, r.Valeur_libre__c));
        }
        return resultats;
    }

    /**
     * Désérialise la table de mappage JSON du nœud.
     *
     * @param mappageJson Contenu de MappageChamps_JSON__c.
     * @return Table champ -> valeur brute (jetons non résolus).
     */
    private static Map<String, Object> parseMapping(String mappageJson) {
        if (String.isBlank(mappageJson)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(mappageJson);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
            throw new ParcoursActionException(
                'Le mappage de champs doit être un objet JSON { "champ": "valeur" }.'
            );
        } catch (JSONException e) {
            throw new ParcoursActionException(
                'Mappage de champs JSON invalide : ' + e.getMessage()
            );
        }
    }

    /**
     * Construit l'enregistrement cible champ par champ, en résolvant les jetons
     * puis en convertissant chaque valeur vers le type réel du champ.
     *
     * @param objetCible API name de l'objet (ex : Event, WorkOrder).
     * @param rawFields Table champ -> valeur brute issue du JSON.
     * @param tokenContext Table des jetons disponibles.
     * @return Le SObject prêt pour la DML.
     */
    private static SObject buildRecord(
        String objetCible,
        Map<String, Object> rawFields,
        Map<String, Object> tokenContext
    ) {
        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objetCible);
        if (sobjectType == null) {
            throw new ParcoursActionException('Objet cible inconnu : ' + objetCible);
        }

        Map<String, Schema.SObjectField> fieldMap = sobjectType
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        SObject record = sobjectType.newSObject();

        for (String fieldName : rawFields.keySet()) {
            Schema.SObjectField token = fieldMap.get(fieldName);
            if (token == null) {
                throw new ParcoursActionException(
                    'Champ inconnu « ' + fieldName + ' » sur ' + objetCible + '.'
                );
            }
            Object resolved = resolveToken(rawFields.get(fieldName), tokenContext);
            Schema.DisplayType displayType = token.getDescribe().getType();
            record.put(fieldName, coerce(resolved, displayType));
        }
        return record;
    }

    /**
     * Résout un jeton unique ({client}, {case}, {noeud.CodePresta}, TODAY+N,
     * {champ}) ; renvoie la valeur inchangée si aucun jeton n'est reconnu.
     *
     * @param rawValue Valeur brute issue du JSON.
     * @param tokenContext Table des jetons disponibles.
     * @return La valeur résolue.
     */
    @TestVisible
    private static Object resolveToken(Object rawValue, Map<String, Object> tokenContext) {
        if (!(rawValue instanceof String)) {
            return rawValue;
        }
        String value = ((String) rawValue).trim();

        // Jeton encadré par des accolades : {client}, {case}, {champ}...
        if (value.startsWith('{') && value.endsWith('}')) {
            String key = value.substring(1, value.length() - 1).trim();
            if (tokenContext.containsKey(key)) {
                return tokenContext.get(key);
            }
            throw new ParcoursActionException('Jeton non résolu : ' + value);
        }

        // Dates relatives : TODAY, TODAY+N, TODAY-N.
        Matcher todayMatcher = TODAY_PATTERN.matcher(value);
        if (todayMatcher.matches()) {
            Integer offset = 0;
            if (todayMatcher.group(1) != null) {
                offset = Integer.valueOf(todayMatcher.group(1));
            }
            return Date.today().addDays(offset);
        }

        return value;
    }

    /**
     * Convertit une valeur résolue vers le type attendu par le champ Salesforce.
     *
     * @param value Valeur résolue (String, Date, Id...).
     * @param displayType Type du champ cible.
     * @return La valeur convertie, prête pour SObject.put.
     */
    @TestVisible
    private static Object coerce(Object value, Schema.DisplayType displayType) {
        if (value == null) {
            return null;
        }
        // Les valeurs déjà typées (Date, Datetime, Id...) traversent sans
        // reconversion lorsque le type correspond.
        String asString = (value instanceof String) ? (String) value : String.valueOf(value);
        if (String.isBlank(asString)) {
            return null;
        }

        switch on displayType {
            when INTEGER {
                return Integer.valueOf(asString);
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Double.valueOf(asString);
            }
            when BOOLEAN {
                return Boolean.valueOf(asString);
            }
            when DATE {
                return (value instanceof Date) ? value : Date.valueOf(asString);
            }
            when DATETIME {
                return (value instanceof Datetime) ? value : Datetime.valueOf(asString);
            }
            when REFERENCE, ID {
                return (Id) asString;
            }
            when else {
                return asString;
            }
        }
    }

    /**
     * Exécute l'opération DML correspondant au verbe du nœud, en mode utilisateur.
     *
     * @param typeAction Verbe DML (Créer, Mettre à jour, Supprimer, Upsert).
     * @param objetCible API name de l'objet cible.
     * @param record Enregistrement construit.
     * @return L'identifiant du record visé.
     */
    private static Id performDml(String typeAction, String objetCible, SObject record) {
        switch on typeAction {
            when 'Créer' {
                insert as user record;
                return record.Id;
            }
            when 'Mettre à jour' {
                if (record.Id == null) {
                    throw new ParcoursActionException(
                        'Mise à jour impossible : aucun Id fourni pour ' + objetCible + '.'
                    );
                }
                update as user record;
                return record.Id;
            }
            when 'Supprimer' {
                if (record.Id == null) {
                    throw new ParcoursActionException(
                        'Suppression impossible : aucun Id fourni pour ' + objetCible + '.'
                    );
                }
                Id cible = record.Id;
                delete as user record;
                return cible;
            }
            when 'Upsert' {
                Database.upsert(record, true, AccessLevel.USER_MODE);
                return record.Id;
            }
            when else {
                throw new ParcoursActionException(
                    'Type d\'action non supporté : ' + typeAction
                );
            }
        }
    }

    /**
     * Petit conteneur interne reliant une réponse saisie à son jeton logique.
     */
    private class AggregateReponse {
        public String cle;
        public Object valeur;

        public AggregateReponse(String cle, Object valeur) {
            this.cle = cle;
            this.valeur = valeur;
        }
    }
}
