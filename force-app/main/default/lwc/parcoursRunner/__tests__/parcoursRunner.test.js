import { createElement } from 'lwc';
import ParcoursRunner from 'c/parcoursRunner';
import startSession from '@salesforce/apex/ParcoursRunnerController.startSession';
import submitAndNavigate from '@salesforce/apex/ParcoursRunnerController.submitAndNavigate';

// Mock des méthodes Apex imperatives.
jest.mock(
    '@salesforce/apex/ParcoursRunnerController.startSession',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ParcoursRunnerController.getCurrentNode',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ParcoursRunnerController.submitAndNavigate',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const QUESTION_NODE = {
    sessionId: 'a00000000000001',
    nodeId: 'a01000000000001',
    name: 'Q1',
    typeNoeud: 'Question',
    texte: 'Avez-vous constaté une fuite ?',
    isFin: false,
    champs: [],
    transitions: [
        { transitionId: 't1', libelleReponse: 'Oui', noeudCibleId: 'n2' },
        { transitionId: 't2', libelleReponse: 'Non', noeudCibleId: 'n3' }
    ]
};

const FIN_NODE = {
    sessionId: 'a00000000000001',
    nodeId: 'a01000000000009',
    name: 'FIN',
    typeNoeud: 'Fin',
    texte: 'Merci.',
    isFin: true,
    champs: [],
    transitions: []
};

function flushPromises() {
    return Promise.resolve();
}

describe('c-parcours-runner', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('affiche le nœud de départ et ses transitions', async () => {
        startSession.mockResolvedValue(QUESTION_NODE);

        const element = createElement('c-parcours-runner', { is: ParcoursRunner });
        element.parcoursCode = 'EP_FUITE_PART';
        document.body.appendChild(element);

        await flushPromises();

        expect(startSession).toHaveBeenCalled();
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        expect(buttons.length).toBe(2);
    });

    it('avance et affiche l\'état terminé en fin de parcours', async () => {
        startSession.mockResolvedValue(QUESTION_NODE);
        submitAndNavigate.mockResolvedValue(FIN_NODE);

        const element = createElement('c-parcours-runner', { is: ParcoursRunner });
        element.parcoursCode = 'EP_FUITE_PART';
        document.body.appendChild(element);
        await flushPromises();

        const branche = element.shadowRoot.querySelector('lightning-button[data-id="t1"]');
        branche.dispatchEvent(new CustomEvent('click'));
        await flushPromises();
        await flushPromises();

        expect(submitAndNavigate).toHaveBeenCalled();
        const statut = element.shadowRoot.querySelector('[role="status"]');
        expect(statut).not.toBeNull();
    });
});
