/**
 * Tests de ParcoursSessionViewerController : reconstruction du chemin exécuté
 * d'une session (nœuds visités, réponses choisies, valeurs saisies, arêtes),
 * chemins nominaux et chemins d'erreur.
 */
@isTest
private class ParcoursSessionViewerControllerTest {
    private static final String CODE = 'SESSION_TEST';
    private static final String Q_KEY = 'N_QUESTION';
    private static final String MID_KEY = 'N_MILIEU';
    private static final String END_KEY = 'N_FIN';

    @TestSetup
    static void setupTestData() {
        Parcours__c parcours = TestDataFactory.createParcours(CODE, true);
        Noeud__c question = TestDataFactory.createNode(
            parcours.Id,
            Q_KEY,
            'Question',
            true
        );
        Noeud__c milieu = TestDataFactory.createNode(
            parcours.Id,
            MID_KEY,
            'Conseil',
            true
        );
        Noeud__c fin = TestDataFactory.createNode(
            parcours.Id,
            END_KEY,
            'Fin',
            true
        );
        parcours.NoeudDepart_FK__c = question.Id;
        update parcours;

        Transition__c versMillieu = TestDataFactory.createTransition(
            question.Id,
            milieu.Id,
            'Oui',
            1,
            true
        );
        TestDataFactory.createTransition(milieu.Id, fin.Id, 'Continuer', 1, true);

        // Session en cours, actuellement positionnée sur le nœud de fin.
        SessionParcours__c session = TestDataFactory.createSession(
            parcours.Id,
            null,
            null,
            true
        );
        session.NoeudCourant_FK__c = fin.Id;
        update session;

        // Déroulé : au nœud Question, l'agent choisit « Oui » et saisit une
        // valeur libre ; au nœud Milieu, il poursuit. Horodatages croissants
        // pour un ordre déterministe.
        Datetime base = System.now();
        List<ReponseSaisie__c> reponses = new List<ReponseSaisie__c>{
            new ReponseSaisie__c(
                Session_FK__c = session.Id,
                Noeud_FK__c = question.Id,
                Valeur_libre__c = 'Dupont',
                Horodatage__c = base
            ),
            new ReponseSaisie__c(
                Session_FK__c = session.Id,
                Noeud_FK__c = question.Id,
                Transition_FK__c = versMillieu.Id,
                Horodatage__c = base.addSeconds(1)
            ),
            new ReponseSaisie__c(
                Session_FK__c = session.Id,
                Noeud_FK__c = milieu.Id,
                Horodatage__c = base.addSeconds(2)
            )
        };
        insert reponses;
    }

    private static SessionParcours__c loadSession() {
        return [
            SELECT Id
            FROM SessionParcours__c
            WHERE Parcours_FK__r.Code__c = :CODE
            LIMIT 1
        ];
    }

    @isTest
    static void shouldReturnVisitedNodesInOrder_WhenSessionHasPath() {
        // Given
        SessionParcours__c session = loadSession();

        // When
        Test.startTest();
        ParcoursSessionViewerController.SessionPathDTO path = ParcoursSessionViewerController.getSessionPath(
            session.Id
        );
        Test.stopTest();

        // Then : Question -> Milieu -> Fin (courant).
        Assert.areEqual(
            3,
            path.nodes.size(),
            'Les trois nœuds visités (dont le nœud courant) doivent être retournés.'
        );
        Assert.areEqual(
            Q_KEY,
            path.nodes[0].name,
            'Le premier nœud du chemin doit être le nœud Question.'
        );
        Assert.areEqual(
            END_KEY,
            path.nodes[2].name,
            'Le dernier nœud du chemin doit être le nœud de fin courant.'
        );
        Assert.areEqual(
            1,
            path.nodes[0].ordre,
            'L\'ordre du premier nœud doit valoir 1.'
        );
    }

    @isTest
    static void shouldCaptureChosenAnswerAndFreeValues_WhenQuestionAnswered() {
        // Given
        SessionParcours__c session = loadSession();

        // When
        Test.startTest();
        ParcoursSessionViewerController.SessionPathDTO path = ParcoursSessionViewerController.getSessionPath(
            session.Id
        );
        Test.stopTest();

        // Then
        ParcoursSessionViewerController.StepDTO question = path.nodes[0];
        Assert.areEqual(
            'Oui',
            question.reponse,
            'La réponse choisie au nœud Question doit être « Oui ».'
        );
        Assert.areEqual(
            1,
            question.valeurs.size(),
            'Une valeur libre doit être enregistrée au nœud Question.'
        );
        Assert.areEqual(
            'Dupont',
            question.valeurs[0],
            'La valeur libre saisie doit être restituée.'
        );
    }

    @isTest
    static void shouldMarkCurrentNode_WhenSessionInProgress() {
        // Given
        SessionParcours__c session = loadSession();

        // When
        Test.startTest();
        ParcoursSessionViewerController.SessionPathDTO path = ParcoursSessionViewerController.getSessionPath(
            session.Id
        );
        Test.stopTest();

        // Then
        Assert.areEqual(
            path.currentNodeId,
            path.nodes[2].id,
            'Le nœud courant doit être la dernière étape du chemin.'
        );
        Assert.isTrue(
            path.nodes[2].isCurrent,
            'Le nœud courant doit être marqué comme tel.'
        );
        Assert.isFalse(
            path.nodes[0].isCurrent,
            'Un nœud déjà franchi ne doit pas être marqué courant.'
        );
    }

    @isTest
    static void shouldLinkConsecutiveNodes_WhenBuildingEdges() {
        // Given
        SessionParcours__c session = loadSession();

        // When
        Test.startTest();
        ParcoursSessionViewerController.SessionPathDTO path = ParcoursSessionViewerController.getSessionPath(
            session.Id
        );
        Test.stopTest();

        // Then : deux arêtes relient les trois nœuds du chemin.
        Assert.areEqual(
            2,
            path.edges.size(),
            'Le chemin de trois nœuds doit produire deux arêtes.'
        );
        Assert.areEqual(
            path.nodes[0].id,
            path.edges[0].source,
            'La première arête doit partir du premier nœud.'
        );
        Assert.areEqual(
            path.nodes[1].id,
            path.edges[0].target,
            'La première arête doit atteindre le deuxième nœud.'
        );
        Assert.areEqual(
            'Oui',
            path.edges[0].libelle,
            'La première arête doit porter la réponse choisie au nœud source.'
        );
    }

    @isTest
    static void shouldExposeSessionMetadata_WhenSessionLoaded() {
        // Given
        SessionParcours__c session = loadSession();

        // When
        Test.startTest();
        ParcoursSessionViewerController.SessionPathDTO path = ParcoursSessionViewerController.getSessionPath(
            session.Id
        );
        Test.stopTest();

        // Then
        Assert.areEqual(
            'En cours',
            path.statut,
            'Le statut de la session doit être exposé.'
        );
        Assert.areEqual(
            'Parcours ' + CODE,
            path.parcoursName,
            'Le nom du parcours courant doit être exposé.'
        );
        Assert.isNotNull(
            path.dateDebut,
            'La date de début doit être exposée.'
        );
    }

    @isTest
    static void shouldThrowException_WhenIdIsNull() {
        // When / Then
        Test.startTest();
        try {
            ParcoursSessionViewerController.getSessionPath(null);
            Assert.fail('Un AuraHandledException doit être levé pour un Id null.');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'L\'exception attendue doit être levée.');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrowException_WhenSessionNotFound() {
        // Given : une session insérée puis supprimée → Id valide mais introuvable.
        Parcours__c parcours = [
            SELECT Id
            FROM Parcours__c
            WHERE Code__c = :CODE
            LIMIT 1
        ];
        SessionParcours__c ephemere = TestDataFactory.createSession(
            parcours.Id,
            null,
            null,
            true
        );
        Id goneId = ephemere.Id;
        delete ephemere;

        // When / Then
        Test.startTest();
        try {
            ParcoursSessionViewerController.getSessionPath(goneId);
            Assert.fail(
                'Un AuraHandledException doit être levé pour une session introuvable.'
            );
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'L\'exception attendue doit être levée.');
        }
        Test.stopTest();
    }
}
