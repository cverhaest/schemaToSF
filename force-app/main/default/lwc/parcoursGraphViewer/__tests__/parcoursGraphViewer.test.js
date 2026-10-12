import { createElement } from 'lwc';
import ParcoursGraphViewer from 'c/parcoursGraphViewer';
import getGraph from '@salesforce/apex/ParcoursGraphController.getGraph';

// Adaptateur de wire Apex simulé.
jest.mock(
    '@salesforce/apex/ParcoursGraphController.getGraph',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

// DML via Lightning Data Service : simulée pour isoler le composant.
jest.mock(
    'lightning/uiRecordApi',
    () => ({
        createRecord: jest.fn(() => Promise.resolve({ id: 'new' })),
        updateRecord: jest.fn(() => Promise.resolve({})),
        deleteRecord: jest.fn(() => Promise.resolve())
    }),
    { virtual: true }
);

const GRAPH_SAMPLE = {
    parcoursId: 'a00000000000001',
    parcoursName: 'Parcours Test',
    code: 'TEST',
    statut: 'Actif',
    startNodeId: 'n1',
    nodes: [
        { id: 'n1', name: 'Depart', typeNoeud: 'Question' },
        { id: 'n2', name: 'Milieu', typeNoeud: 'Navigation' },
        { id: 'n3', name: 'Fin', typeNoeud: 'Fin' }
    ],
    edges: [
        { id: 'e1', source: 'n1', target: 'n2', libelle: 'Oui', ordre: 1 },
        { id: 'e2', source: 'n1', target: 'n3', libelle: 'Non', ordre: 2 }
    ]
};

describe('c-parcours-graph-viewer', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function flushPromises() {
        return Promise.resolve();
    }

    function createComponent() {
        const element = createElement('c-parcours-graph-viewer', {
            is: ParcoursGraphViewer
        });
        element.recordId = 'a00000000000001';
        document.body.appendChild(element);
        return element;
    }

    function clickFirstNode(element) {
        const nodeGroup = element.shadowRoot.querySelector('g.node');
        nodeGroup.dispatchEvent(new CustomEvent('click'));
    }

    it('affiche un nœud par enregistrement retourné', async () => {
        const element = createComponent();
        getGraph.emit(GRAPH_SAMPLE);
        await flushPromises();

        const rects = element.shadowRoot.querySelectorAll('rect.node-rect');
        expect(rects.length).toBe(3);
    });

    it('trace une arête par transition retournée', async () => {
        const element = createComponent();
        getGraph.emit(GRAPH_SAMPLE);
        await flushPromises();

        const lines = element.shadowRoot.querySelectorAll('polyline.edge-line');
        expect(lines.length).toBe(2);
    });

    it('ouvre le panneau d’administration au clic sur un nœud', async () => {
        const element = createComponent();
        getGraph.emit(GRAPH_SAMPLE);
        await flushPromises();

        clickFirstNode(element);
        await flushPromises();

        const form = element.shadowRoot.querySelector(
            'lightning-record-edit-form'
        );
        expect(form).not.toBeNull();
        expect(form.recordId).toBe('n1');
    });

    it('liste les réponses sortantes du nœud sélectionné', async () => {
        const element = createComponent();
        getGraph.emit(GRAPH_SAMPLE);
        await flushPromises();

        clickFirstNode(element);
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('.response-row');
        expect(rows.length).toBe(2);
    });

    it('ajoute une ligne de réponse vierge', async () => {
        const element = createComponent();
        getGraph.emit(GRAPH_SAMPLE);
        await flushPromises();

        clickFirstNode(element);
        await flushPromises();

        const addButton = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((btn) => btn.label === 'Ajouter une réponse');
        addButton.dispatchEvent(new CustomEvent('click'));
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('.response-row');
        expect(rows.length).toBe(3);
    });

    it('affiche un message d’erreur en cas d’échec du wire', async () => {
        const element = createComponent();
        getGraph.error();
        await flushPromises();

        const alert = element.shadowRoot.querySelector('[role="alert"]');
        expect(alert).not.toBeNull();
    });

    it('affiche l’état vide quand aucun nœud n’est retourné', async () => {
        const element = createComponent();
        getGraph.emit({ ...GRAPH_SAMPLE, nodes: [], edges: [] });
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg.graph-svg');
        expect(svg).toBeNull();
    });
});
