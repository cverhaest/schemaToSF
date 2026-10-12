/**
 * Tests de ParcoursGraphController : chargement du graphe d'un parcours
 * (nœuds + transitions), chemins nominaux et chemins d'erreur.
 */
@isTest
private class ParcoursGraphControllerTest {
    private static final String MAIN_CODE = 'GRAPH_TEST';
    private static final String EMPTY_CODE = 'GRAPH_EMPTY';
    private static final String START_KEY = 'N_START';
    private static final String MID_KEY = 'N_MID';
    private static final String END_KEY = 'N_END';

    @TestSetup
    static void setupTestData() {
        // Parcours principal : 3 nœuds, 3 transitions, nœud de départ = N_START.
        Parcours__c parcours = TestDataFactory.createParcours(MAIN_CODE, true);
        Noeud__c start = TestDataFactory.createNode(
            parcours.Id,
            START_KEY,
            'Question',
            true
        );
        Noeud__c mid = TestDataFactory.createNode(
            parcours.Id,
            MID_KEY,
            'Navigation',
            true
        );
        Noeud__c fin = TestDataFactory.createNode(
            parcours.Id,
            END_KEY,
            'Fin',
            true
        );
        parcours.NoeudDepart_FK__c = start.Id;
        update parcours;

        TestDataFactory.createTransition(start.Id, mid.Id, 'Oui', 1, true);
        TestDataFactory.createTransition(start.Id, fin.Id, 'Non', 2, true);
        TestDataFactory.createTransition(mid.Id, fin.Id, 'Continuer', 1, true);

        // Parcours secondaire : un seul nœud, aucune transition.
        Parcours__c vide = TestDataFactory.createParcours(EMPTY_CODE, true);
        TestDataFactory.createNode(vide.Id, 'N_SOLO', 'Conseil', true);
    }

    @isTest
    static void shouldReturnGraph_WhenParcoursHasNodesAndEdges() {
        // Given
        Parcours__c parcours = [
            SELECT Id
            FROM Parcours__c
            WHERE Code__c = :MAIN_CODE
            LIMIT 1
        ];
        Noeud__c start = [
            SELECT Id
            FROM Noeud__c
            WHERE Name = :START_KEY AND Parcours_FK__c = :parcours.Id
            LIMIT 1
        ];

        // When
        Test.startTest();
        ParcoursGraphController.ParcoursGraphDTO graph = ParcoursGraphController.getGraph(
            parcours.Id
        );
        Test.stopTest();

        // Then
        Assert.areEqual(
            3,
            graph.nodes.size(),
            'Les trois nœuds du parcours doivent être retournés.'
        );
        Assert.areEqual(
            3,
            graph.edges.size(),
            'Les trois transitions sortantes doivent être retournées.'
        );
        Assert.areEqual(
            start.Id,
            graph.startNodeId,
            'Le nœud de départ doit correspondre à N_START.'
        );
        Assert.areEqual(
            parcours.Id,
            graph.parcoursId,
            'Le parcours retourné doit être celui demandé.'
        );
    }

    @isTest
    static void shouldPopulateNodeFields_WhenNodeIsReturned() {
        // Given
        Parcours__c parcours = [
            SELECT Id
            FROM Parcours__c
            WHERE Code__c = :MAIN_CODE
            LIMIT 1
        ];

        // When
        Test.startTest();
        ParcoursGraphController.ParcoursGraphDTO graph = ParcoursGraphController.getGraph(
            parcours.Id
        );
        Test.stopTest();

        // Then
        Map<String, String> typeByName = new Map<String, String>();
        for (ParcoursGraphController.NodeDTO node : graph.nodes) {
            typeByName.put(node.name, node.typeNoeud);
        }
        Assert.areEqual(
            'Question',
            typeByName.get(START_KEY),
            'Le type du nœud de départ doit être Question.'
        );
        Assert.areEqual(
            'Fin',
            typeByName.get(END_KEY),
            'Le type du nœud final doit être Fin.'
        );
    }

    @isTest
    static void shouldPopulateEdgeFields_WhenEdgeIsReturned() {
        // Given
        Parcours__c parcours = [
            SELECT Id
            FROM Parcours__c
            WHERE Code__c = :MAIN_CODE
            LIMIT 1
        ];
        Noeud__c start = [
            SELECT Id
            FROM Noeud__c
            WHERE Name = :START_KEY AND Parcours_FK__c = :parcours.Id
            LIMIT 1
        ];

        // When
        Test.startTest();
        ParcoursGraphController.ParcoursGraphDTO graph = ParcoursGraphController.getGraph(
            parcours.Id
        );
        Test.stopTest();

        // Then
        Set<String> libellesSortantsDuDepart = new Set<String>();
        for (ParcoursGraphController.EdgeDTO edge : graph.edges) {
            if (edge.source == start.Id) {
                libellesSortantsDuDepart.add(edge.libelle);
            }
        }
        Assert.areEqual(
            2,
            libellesSortantsDuDepart.size(),
            'Le nœud de départ doit porter deux transitions sortantes.'
        );
        Assert.isTrue(
            libellesSortantsDuDepart.contains('Oui'),
            'La branche "Oui" doit être présente.'
        );
        Assert.isTrue(
            libellesSortantsDuDepart.contains('Non'),
            'La branche "Non" doit être présente.'
        );
    }

    @isTest
    static void shouldReturnEmptyEdges_WhenParcoursHasSingleNode() {
        // Given
        Parcours__c vide = [
            SELECT Id
            FROM Parcours__c
            WHERE Code__c = :EMPTY_CODE
            LIMIT 1
        ];

        // When
        Test.startTest();
        ParcoursGraphController.ParcoursGraphDTO graph = ParcoursGraphController.getGraph(
            vide.Id
        );
        Test.stopTest();

        // Then
        Assert.areEqual(
            1,
            graph.nodes.size(),
            'Le parcours secondaire ne contient qu\'un seul noeud.'
        );
        Assert.isTrue(
            graph.edges.isEmpty(),
            'Aucune transition ne doit être retournée pour ce parcours.'
        );
    }

    @isTest
    static void shouldThrowException_WhenIdIsNull() {
        // When / Then
        Test.startTest();
        try {
            ParcoursGraphController.getGraph(null);
            Assert.fail('Un AuraHandledException doit être levé pour un Id null.');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'L\'exception attendue doit etre levee.');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrowException_WhenParcoursNotFound() {
        // Given : un parcours inséré puis supprimé → Id valide mais introuvable.
        Parcours__c ephemere = TestDataFactory.createParcours('GRAPH_GONE', true);
        Id goneId = ephemere.Id;
        delete ephemere;

        // When / Then
        Test.startTest();
        try {
            ParcoursGraphController.getGraph(goneId);
            Assert.fail(
                'Un AuraHandledException doit être levé pour un parcours introuvable.'
            );
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'L\'exception attendue doit etre levee.');
        }
        Test.stopTest();
    }
}
