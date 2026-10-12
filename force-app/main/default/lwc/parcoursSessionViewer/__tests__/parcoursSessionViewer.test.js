import { createElement } from 'lwc';
import ParcoursSessionViewer from 'c/parcoursSessionViewer';
import getSessionPath from '@salesforce/apex/ParcoursSessionViewerController.getSessionPath';

// Mock de l'adaptateur @wire Apex.
jest.mock(
    '@salesforce/apex/ParcoursSessionViewerController.getSessionPath',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

const PATH_DATA = {
    sessionId: '001000000000001',
    parcoursName: 'Parcours FUITE',
    statut: 'En cours',
    agentName: 'Alice Martin',
    dateDebut: '2026-01-01T09:00:00.000Z',
    dateFin: null,
    startNodeId: 'n1',
    currentNodeId: 'n3',
    nodes: [
        {
            id: 'n1',
            name: 'Fuite constatée ?',
            typeNoeud: 'Question',
            parcoursNom: 'Parcours FUITE',
            reponse: 'Oui',
            valeurs: ['Compteur 1234'],
            ordre: 1,
            isCurrent: false
        },
        {
            id: 'n2',
            name: 'Conseil sécurité',
            typeNoeud: 'Conseil',
            parcoursNom: 'Parcours FUITE',
            reponse: null,
            valeurs: [],
            ordre: 2,
            isCurrent: false
        },
        {
            id: 'n3',
            name: 'Clôture',
            typeNoeud: 'Fin',
            parcoursNom: 'Parcours FUITE',
            reponse: null,
            valeurs: [],
            ordre: 3,
            isCurrent: true
        }
    ],
    edges: [
        { id: 'n1-n2', source: 'n1', target: 'n2', libelle: 'Oui' },
        { id: 'n2-n3', source: 'n2', target: 'n3', libelle: null }
    ]
};

describe('c-parcours-session-viewer', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent() {
        const element = createElement('c-parcours-session-viewer', {
            is: ParcoursSessionViewer
        });
        element.recordId = '001000000000001';
        document.body.appendChild(element);
        return element;
    }

    async function flush() {
        return Promise.resolve();
    }

    it('affiche un nœud par étape du chemin exécuté', async () => {
        const element = createComponent();
        getSessionPath.emit(PATH_DATA);
        await flush();

        const nodes = element.shadowRoot.querySelectorAll('g.node');
        expect(nodes.length).toBe(3);
    });

    it('relie les nœuds consécutifs par des arêtes orientées', async () => {
        const element = createComponent();
        getSessionPath.emit(PATH_DATA);
        await flush();

        const edges = element.shadowRoot.querySelectorAll('g.edge');
        expect(edges.length).toBe(2);
        const arrows = element.shadowRoot.querySelectorAll('polygon.edge-arrow');
        expect(arrows.length).toBe(2);
    });

    it('étiquette une arête avec la réponse choisie au nœud source', async () => {
        const element = createComponent();
        getSessionPath.emit(PATH_DATA);
        await flush();

        const labels = Array.from(
            element.shadowRoot.querySelectorAll('text.edge-label')
        ).map((node) => node.textContent.trim());
        expect(labels).toContain('Oui');
    });

    it('met en évidence le nœud courant', async () => {
        const element = createComponent();
        getSessionPath.emit(PATH_DATA);
        await flush();

        const current = element.shadowRoot.querySelectorAll('g.node_current');
        expect(current.length).toBe(1);
    });

    it('affiche le détail de l’étape sélectionnée (réponse + valeurs)', async () => {
        const element = createComponent();
        getSessionPath.emit(PATH_DATA);
        await flush();

        const firstNode = element.shadowRoot.querySelector('g.node');
        firstNode.dispatchEvent(new CustomEvent('click'));
        await flush();

        const panel = element.shadowRoot.querySelector('.panel');
        expect(panel).not.toBeNull();
        const text = panel.textContent;
        expect(text).toContain('Oui');
        expect(text).toContain('Compteur 1234');
    });

    it('expose les métadonnées de session dans l’en-tête', async () => {
        const element = createComponent();
        getSessionPath.emit(PATH_DATA);
        await flush();

        const summary = element.shadowRoot.querySelector('.session-summary');
        expect(summary.textContent).toContain('Parcours FUITE');
        expect(summary.textContent).toContain('En cours');
        expect(summary.textContent).toContain('Alice Martin');
    });

    it('affiche un message quand aucune étape n’est enregistrée', async () => {
        const element = createComponent();
        getSessionPath.emit({
            ...PATH_DATA,
            nodes: [],
            edges: [],
            currentNodeId: null,
            startNodeId: null
        });
        await flush();

        const nodes = element.shadowRoot.querySelectorAll('g.node');
        expect(nodes.length).toBe(0);
        expect(element.shadowRoot.textContent).toContain(
            'Aucune étape enregistrée'
        );
    });

    it('affiche l’erreur renvoyée par le serveur', async () => {
        const element = createComponent();
        getSessionPath.error({ body: { message: 'Session introuvable.' } });
        await flush();

        const alert = element.shadowRoot.querySelector('[role="alert"]');
        expect(alert).not.toBeNull();
        expect(alert.textContent).toContain('Session introuvable.');
    });
});
