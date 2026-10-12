/**
 * Couverture du moteur générique d'exécution d'actions ParcoursActionHandler.
 *
 * Les cas valident la création d'enregistrement, l'idempotence, la résolution
 * des jetons ({case}, TODAY+N, réponse saisie), le typage dynamique et les
 * chemins d'erreur (nœud non-action, objet cible absent, champ inconnu).
 * L'objet cible utilisé est Task (standard, inscriptible).
 */
@isTest
private class ParcoursActionHandlerTest {
    private static final String CODE_PARCOURS = 'TEST_FUITE';

    @TestSetup
    static void setupTestData() {
        Account compte = TestDataFactory.createAccount('Client Test', true);
        Case requete = new Case(AccountId = compte.Id, Subject = 'Requête test');
        insert requete;

        Parcours__c parcours = TestDataFactory.createParcours(CODE_PARCOURS, true);

        // Nœud question + champ de saisie exposant le jeton logique « sujet ».
        Noeud__c question = TestDataFactory.createNode(parcours.Id, 'N_SUJET', 'Question', true);
        TestDataFactory.createChampSaisie(question.Id, 'Sujet', 'Text', 'sujet', true);

        // Session liée au compte et à la requête.
        SessionParcours__c session = TestDataFactory.createSession(
            parcours.Id, compte.Id, requete.Id, true
        );

        // Réponse saisie alimentant le jeton {sujet}.
        TestDataFactory.createReponse(session.Id, question.Id, 'Fuite particulier', true);
    }

    private static SessionParcours__c getSession() {
        return [SELECT Id FROM SessionParcours__c LIMIT 1];
    }

    private static Id getParcoursId() {
        return [SELECT Id FROM Parcours__c WHERE Code__c = :CODE_PARCOURS LIMIT 1].Id;
    }

    @isTest
    static void shouldCreateRecord_WhenValidActionNode() {
        // Given
        Id caseId = [SELECT Id FROM Case LIMIT 1].Id;
        SessionParcours__c session = getSession();
        String mapping = '{"Subject":"{sujet}","ActivityDate":"TODAY+2","WhatId":"{case}"}';
        Noeud__c action = TestDataFactory.createActionNode(
            getParcoursId(), 'N_CREER_TASK', 'Créer', 'Task', mapping, true
        );

        // When
        Test.startTest();
        ActionExecutee__c trace = ParcoursActionHandler.executeNodeAction(session.Id, action.Id);
        Test.stopTest();

        // Then
        Assert.areEqual('OK', trace.Statut__c, 'L\'action doit réussir.');
        Assert.isNotNull(trace.RecordCreeId__c, 'L\'Id du record créé doit être tracé.');

        Task cree = [SELECT Subject, ActivityDate, WhatId FROM Task WHERE Id = :trace.RecordCreeId__c];
        Assert.areEqual('Fuite particulier', cree.Subject, 'Le jeton {sujet} doit être résolu.');
        Assert.areEqual(Date.today().addDays(2), cree.ActivityDate, 'TODAY+2 doit être résolu.');
        Assert.areEqual(caseId, cree.WhatId, 'Le jeton {case} doit pointer la requête.');
    }

    @isTest
    static void shouldBeIdempotent_WhenActionAlreadySucceeded() {
        // Given
        SessionParcours__c session = getSession();
        String mapping = '{"Subject":"{sujet}"}';
        Noeud__c action = TestDataFactory.createActionNode(
            getParcoursId(), 'N_IDEM', 'Créer', 'Task', mapping, true
        );

        // When : deux exécutions successives du même nœud.
        Test.startTest();
        ActionExecutee__c premiere = ParcoursActionHandler.executeNodeAction(session.Id, action.Id);
        ActionExecutee__c seconde = ParcoursActionHandler.executeNodeAction(session.Id, action.Id);
        Test.stopTest();

        // Then : une seule Task et la même trace renvoyée.
        Assert.areEqual(premiere.Id, seconde.Id, 'La seconde exécution doit renvoyer la trace existante.');
        Assert.areEqual(1, [SELECT COUNT() FROM Task], 'Une seule Task doit être créée.');
    }

    @isTest
    static void shouldThrowException_WhenNodeNotAction() {
        // Given
        SessionParcours__c session = getSession();
        Noeud__c conseil = TestDataFactory.createNode(getParcoursId(), 'N_CONSEIL', 'Conseil', true);

        // When / Then
        Test.startTest();
        try {
            ParcoursActionHandler.executeNodeAction(session.Id, conseil.Id);
            Assert.fail('Une ParcoursActionException était attendue.');
        } catch (ParcoursActionHandler.ParcoursActionException e) {
            Assert.isTrue(e.getMessage().contains('action'), 'Le message doit signaler un nœud non-action.');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrowException_WhenArgumentsNull() {
        // When / Then
        Test.startTest();
        try {
            ParcoursActionHandler.executeNodeAction(null, null);
            Assert.fail('Une ParcoursActionException était attendue sur arguments nuls.');
        } catch (ParcoursActionHandler.ParcoursActionException e) {
            Assert.isTrue(e.getMessage().contains('obligatoires'), 'Le message doit signaler les paramètres requis.');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldLogError_WhenObjetCibleBlank() {
        // Given : nœud d'action sans objet cible.
        SessionParcours__c session = getSession();
        Noeud__c action = TestDataFactory.createActionNode(
            getParcoursId(), 'N_SANS_CIBLE', 'Créer', null, '{"Subject":"x"}', true
        );

        // When
        Test.startTest();
        ActionExecutee__c trace = ParcoursActionHandler.executeNodeAction(session.Id, action.Id);
        Test.stopTest();

        // Then
        Assert.areEqual('Erreur', trace.Statut__c, 'L\'absence d\'objet cible doit produire une erreur.');
        Assert.isTrue(trace.Message__c.contains('objet cible'), 'Le message doit mentionner l\'objet cible.');
    }

    @isTest
    static void shouldLogError_WhenUnknownField() {
        // Given : champ inexistant sur Task.
        SessionParcours__c session = getSession();
        Noeud__c action = TestDataFactory.createActionNode(
            getParcoursId(), 'N_CHAMP_KO', 'Créer', 'Task', '{"ChampInexistant__x":"x"}', true
        );

        // When
        Test.startTest();
        ActionExecutee__c trace = ParcoursActionHandler.executeNodeAction(session.Id, action.Id);
        Test.stopTest();

        // Then
        Assert.areEqual('Erreur', trace.Statut__c, 'Un champ inconnu doit produire une erreur.');
        Assert.isTrue(trace.Message__c.contains('inconnu'), 'Le message doit signaler le champ inconnu.');
    }

    @isTest
    static void shouldLogError_WhenTokenUnresolved() {
        // Given : jeton absent du contexte.
        SessionParcours__c session = getSession();
        Noeud__c action = TestDataFactory.createActionNode(
            getParcoursId(), 'N_TOKEN_KO', 'Créer', 'Task', '{"Subject":"{inconnu}"}', true
        );

        // When
        Test.startTest();
        ActionExecutee__c trace = ParcoursActionHandler.executeNodeAction(session.Id, action.Id);
        Test.stopTest();

        // Then
        Assert.areEqual('Erreur', trace.Statut__c, 'Un jeton non résolu doit produire une erreur.');
        Assert.isTrue(trace.Message__c.contains('Jeton'), 'Le message doit signaler le jeton non résolu.');
    }

    @isTest
    static void shouldResolveToken_WhenTodayWithoutOffset() {
        // Given
        Map<String, Object> contexte = new Map<String, Object>();

        // When
        Object resultat = ParcoursActionHandler.resolveToken('TODAY', contexte);

        // Then
        Assert.areEqual(Date.today(), resultat, 'TODAY sans décalage doit renvoyer la date du jour.');
    }

    @isTest
    static void shouldCoerceValue_WhenTypedTargets() {
        // When / Then : conversions depuis chaînes.
        Assert.areEqual(42, ParcoursActionHandler.coerce('42', Schema.DisplayType.INTEGER),
            'La conversion entière doit fonctionner.');
        Assert.areEqual(true, ParcoursActionHandler.coerce('true', Schema.DisplayType.BOOLEAN),
            'La conversion booléenne doit fonctionner.');
        Assert.areEqual(Date.newInstance(2026, 1, 15),
            ParcoursActionHandler.coerce('2026-01-15', Schema.DisplayType.DATE),
            'La conversion de date doit fonctionner.');
        Assert.isNull(ParcoursActionHandler.coerce(null, Schema.DisplayType.STRING),
            'Une valeur nulle doit rester nulle.');
    }
}
