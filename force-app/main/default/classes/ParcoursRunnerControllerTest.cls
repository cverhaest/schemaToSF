/**
 * Couverture du contrôleur du moteur de parcours ParcoursRunnerController.
 *
 * Valide l'ouverture de session, la lecture du nœud courant, la navigation sur
 * embranchement (transition choisie) et en linéaire (unique sortie), la clôture
 * sur nœud Fin, la délégation d'action à ParcoursActionHandler et les erreurs.
 *
 * Graphe de test :
 *   Q1 (Question) --T1 "Oui"--> AN (Action: créer Task) --> FIN (Fin)
 *   Q1 (Question) --T2 "Non"--> FIN (Fin)
 */
@isTest
private class ParcoursRunnerControllerTest {
    private static final String CODE_PARCOURS = 'TEST_RUNNER';

    @TestSetup
    static void setupTestData() {
        Parcours__c parcours = TestDataFactory.createParcours(CODE_PARCOURS, true);

        Noeud__c q1 = TestDataFactory.createNode(parcours.Id, 'Q1', 'Question', true);
        TestDataFactory.createChampSaisie(q1.Id, 'Commentaire', 'Text', 'commentaire', true);

        Noeud__c action = TestDataFactory.createActionNode(
            parcours.Id, 'AN', 'Créer', 'Task', '{"Subject":"Action parcours"}', true
        );
        Noeud__c fin = TestDataFactory.createNode(parcours.Id, 'FIN', 'Fin', true);

        // Embranchement depuis Q1.
        insert new List<Transition__c>{
            new Transition__c(NoeudSource_FK__c = q1.Id, NoeudCible_FK__c = action.Id,
                Libelle_reponse__c = 'Oui', Ordre__c = 1),
            new Transition__c(NoeudSource_FK__c = q1.Id, NoeudCible_FK__c = fin.Id,
                Libelle_reponse__c = 'Non', Ordre__c = 2),
            // Sortie linéaire unique depuis le nœud d'action.
            new Transition__c(NoeudSource_FK__c = action.Id, NoeudCible_FK__c = fin.Id,
                Libelle_reponse__c = null, Ordre__c = 1)
        };

        // Nœud de départ du parcours = Q1.
        parcours.NoeudDepart_FK__c = q1.Id;
        update parcours;
    }

    private static Id nodeIdByName(String cle) {
        return [SELECT Id FROM Noeud__c WHERE Name = :cle LIMIT 1].Id;
    }

    @isTest
    static void startSession_WhenActiveParcours_ReturnsStartNode() {
        // When
        Test.startTest();
        ParcoursRunnerController.NodeView view =
            ParcoursRunnerController.startSession(CODE_PARCOURS, 'Case', null, null, null);
        Test.stopTest();

        // Then
        Assert.isNotNull(view.sessionId, 'La session doit être créée.');
        Assert.areEqual('Q1', view.name, 'Le nœud de départ doit être Q1.');
        Assert.areEqual(2, view.transitions.size(), 'Q1 doit exposer deux transitions.');
        Assert.areEqual(1, view.champs.size(), 'Q1 doit exposer un champ de saisie.');
        Assert.isFalse(view.isFin, 'Q1 n\'est pas un nœud de fin.');

        SessionParcours__c session = [
            SELECT NoeudCourant_FK__c, Statut__c FROM SessionParcours__c LIMIT 1
        ];
        Assert.areEqual('En cours', session.Statut__c, 'La session doit être en cours.');
    }

    @isTest
    static void getCurrentNode_WhenSessionActive_ReturnsCurrentNode() {
        // Given
        ParcoursRunnerController.NodeView start =
            ParcoursRunnerController.startSession(CODE_PARCOURS, 'Case', null, null, null);

        // When
        Test.startTest();
        ParcoursRunnerController.NodeView view =
            ParcoursRunnerController.getCurrentNode(start.sessionId);
        Test.stopTest();

        // Then
        Assert.areEqual('Q1', view.name, 'Le nœud courant doit rester Q1.');
    }

    @isTest
    static void submitAndNavigate_WhenBranchChosen_RunsActionAndMovesOn() {
        // Given : on part de Q1 puis on choisit la branche « Oui » vers le nœud d'action.
        ParcoursRunnerController.NodeView start =
            ParcoursRunnerController.startSession(CODE_PARCOURS, 'Case', null, null, null);
        Id transitionOui = start.transitions[0].transitionId;
        String answers = '{"' + start.champs[0].champId + '":"RAS"}';

        // When
        Test.startTest();
        ParcoursRunnerController.NodeView next = ParcoursRunnerController.submitAndNavigate(
            start.sessionId, start.nodeId, answers, transitionOui
        );
        Test.stopTest();

        // Then : on arrive sur le nœud d'action, l'action a été jouée (Task créée),
        // et la réponse libre + le choix de transition sont persistés.
        Assert.areEqual('AN', next.name, 'La branche « Oui » mène au nœud d\'action.');
        Assert.areEqual(1, [SELECT COUNT() FROM Task], 'Le nœud d\'action doit créer une Task.');
        Assert.areEqual(2, [SELECT COUNT() FROM ReponseSaisie__c],
            'La réponse libre et le choix de transition doivent être tracés.');
        Assert.areEqual(1, [SELECT COUNT() FROM ActionExecutee__c],
            'L\'exécution de l\'action doit être tracée.');
    }

    @isTest
    static void submitAndNavigate_WhenLinearNode_FollowsSingleExitToEnd() {
        // Given : session positionnée sur le nœud d'action (sortie linéaire unique vers FIN).
        ParcoursRunnerController.NodeView start =
            ParcoursRunnerController.startSession(CODE_PARCOURS, 'Case', null, null, null);
        ParcoursRunnerController.submitAndNavigate(
            start.sessionId, start.nodeId, null, start.transitions[0].transitionId
        );

        // When : on soumet le nœud d'action sans choisir de transition.
        Test.startTest();
        ParcoursRunnerController.NodeView fin = ParcoursRunnerController.submitAndNavigate(
            start.sessionId, nodeIdByName('AN'), null, null
        );
        Test.stopTest();

        // Then : la sortie unique mène au nœud Fin et clôt la session.
        Assert.areEqual('FIN', fin.name, 'La sortie linéaire doit mener au nœud Fin.');
        Assert.isTrue(fin.isFin, 'Le nœud atteint doit être de type Fin.');
        SessionParcours__c session = [SELECT Statut__c, DateFin__c FROM SessionParcours__c LIMIT 1];
        Assert.areEqual('Terminé', session.Statut__c, 'La session doit être terminée.');
        Assert.isNotNull(session.DateFin__c, 'La date de fin doit être renseignée.');
    }

    @isTest
    static void submitAndNavigate_WhenBranchingWithoutChoice_EndsBranch() {
        // Given : Q1 a deux sorties ; aucune transition choisie => fin de branche.
        ParcoursRunnerController.NodeView start =
            ParcoursRunnerController.startSession(CODE_PARCOURS, 'Case', null, null, null);

        // When
        Test.startTest();
        ParcoursRunnerController.NodeView next = ParcoursRunnerController.submitAndNavigate(
            start.sessionId, start.nodeId, null, null
        );
        Test.stopTest();

        // Then
        Assert.isNull(next, 'Sans transition choisie sur un embranchement, aucun nœud suivant.');
        SessionParcours__c session = [SELECT Statut__c FROM SessionParcours__c LIMIT 1];
        Assert.areEqual('Terminé', session.Statut__c, 'La session doit être clôturée.');
    }

    @isTest
    static void startSession_WhenUnknownCode_ThrowsAuraHandledException() {
        // When / Then
        Test.startTest();
        try {
            ParcoursRunnerController.startSession('INEXISTANT', 'Case', null, null, null);
            Assert.fail('Une AuraHandledException était attendue.');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'L\'exception doit être levée pour un code inconnu.');
        }
        Test.stopTest();
    }

    @isTest
    static void submitAndNavigate_WhenMissingArguments_ThrowsAuraHandledException() {
        // When / Then
        Test.startTest();
        try {
            ParcoursRunnerController.submitAndNavigate(null, null, null, null);
            Assert.fail('Une AuraHandledException était attendue sur arguments nuls.');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'L\'exception doit être levée pour des arguments manquants.');
        }
        Test.stopTest();
    }
}
