import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { loadScript } from 'lightning/platformResourceLoader';
import { createRecord, updateRecord, deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import DAGRE from '@salesforce/resourceUrl/dagre';
import getGraph from '@salesforce/apex/ParcoursGraphController.getGraph';
import TRANSITION_OBJECT from '@salesforce/schema/Transition__c';
import TR_SOURCE from '@salesforce/schema/Transition__c.NoeudSource_FK__c';
import TR_CIBLE from '@salesforce/schema/Transition__c.NoeudCible_FK__c';
import TR_LIBELLE from '@salesforce/schema/Transition__c.Libelle_reponse__c';
import TR_ORDRE from '@salesforce/schema/Transition__c.Ordre__c';
import PARCOURS_ID from '@salesforce/schema/Parcours__c.Id';
import PARCOURS_START from '@salesforce/schema/Parcours__c.NoeudDepart_FK__c';

const NODE_WIDTH = 180;
const NODE_HEIGHT = 64;
const H_GAP = 90; // écart horizontal entre deux niveaux
const V_GAP = 28; // écart vertical entre deux nœuds d'un même niveau
const MARGIN = 24;

const ZOOM_MIN = 0.4;
const ZOOM_MAX = 1.6;
const ZOOM_STEP = 0.2;

// Classe CSS par type de nœud (couleur sémantique).
const TYPE_CLASS = {
    Question: 'node node_question',
    Navigation: 'node node_navigation',
    Conseil: 'node node_conseil',
    Action: 'node node_action',
    Fin: 'node node_fin'
};

/**
 * Visualise un parcours sous forme de graphe (nœuds + transitions) et permet
 * d'administrer un nœud en cliquant dessus : édition des champs, définition du
 * nœud de départ et gestion des réponses/destinations (Transition__c).
 * Data-driven : la lecture passe par Apex, les écritures par Lightning Data
 * Service (aucune DML Apex dédiée).
 */
export default class ParcoursGraphViewer extends LightningElement {
    @api recordId;

    nodes = [];
    edges = [];
    svgWidth = 0;
    svgHeight = 0;
    zoom = 1;
    selectedNodeId;
    selectedNodeName;
    responseRows = [];
    errorMessage;

    _rawNodes = [];
    _rawEdges = [];
    _startNodeId;
    _wiredGraph;
    _graphData;
    _loaded = false;
    _draftSeq = 0;
    _dagreRequested = false;
    _dagreReady = false;

    @wire(getGraph, { parcoursId: '$recordId' })
    wiredGraph(result) {
        this._wiredGraph = result;
        const { data, error } = result;
        if (data) {
            this._loaded = true;
            this.errorMessage = undefined;
            this.buildLayout(data);
            // Conserve la sélection courante après un rafraîchissement.
            if (this.selectedNodeId) {
                this.selectNode(this.selectedNodeId);
            }
        } else if (error) {
            this._loaded = true;
            this.errorMessage = this.reduceError(error);
            this.nodes = [];
            this.edges = [];
        }
    }

    /**
     * Charge dagre (moteur de calcul de layout en couches) une seule fois. Dès
     * qu'il est disponible, on recalcule la disposition pour bénéficier de la
     * minimisation des croisements. En cas d'échec de chargement, la disposition
     * BFS de repli déjà affichée reste en place.
     */
    renderedCallback() {
        if (this._dagreRequested) {
            return;
        }
        this._dagreRequested = true;
        loadScript(this, DAGRE)
            .then(() => {
                this._dagreReady = true;
                if (this._graphData) {
                    this.buildLayout(this._graphData);
                    if (this.selectedNodeId) {
                        this.selectNode(this.selectedNodeId);
                    }
                }
            })
            .catch(() => {
                this._dagreReady = false;
            });
    }

    get hasNodes() {
        return this.nodes.length > 0;
    }

    get hasSelection() {
        return Boolean(this.selectedNodeId);
    }

    get showEmpty() {
        return this._loaded && !this.errorMessage && this.nodes.length === 0;
    }

    get viewBox() {
        return `0 0 ${this.svgWidth} ${this.svgHeight}`;
    }

    get svgRenderWidth() {
        return Math.round(this.svgWidth * this.zoom);
    }

    get svgRenderHeight() {
        return Math.round(this.svgHeight * this.zoom);
    }

    get zoomPercent() {
        return `${Math.round(this.zoom * 100)} %`;
    }

    get disableZoomIn() {
        return this.zoom >= ZOOM_MAX;
    }

    get disableZoomOut() {
        return this.zoom <= ZOOM_MIN;
    }

    get isStartSelected() {
        return Boolean(
            this.selectedNodeId && this.selectedNodeId === this._startNodeId
        );
    }

    // Options du menu déroulant « destination » : tous les nœuds du parcours.
    get nodeOptions() {
        return this._rawNodes.map((node) => ({
            label: node.name,
            value: node.id
        }));
    }

    /**
     * Produit les modèles de vue des nœuds et des arêtes. Le calcul des positions
     * est délégué à dagre (disposition en couches avec minimisation des
     * croisements) dès qu'il est chargé ; tant qu'il ne l'est pas, un repli BFS
     * fournit une disposition immédiate.
     */
    buildLayout(graph) {
        this._graphData = graph;
        const rawNodes = graph.nodes || [];
        const rawEdges = graph.edges || [];
        this._rawNodes = rawNodes;
        this._rawEdges = rawEdges;

        const nodeById = new Map();
        rawNodes.forEach((node) => nodeById.set(node.id, node));

        const startId =
            graph.startNodeId && nodeById.has(graph.startNodeId)
                ? graph.startNodeId
                : rawNodes.length
                ? rawNodes[0].id
                : null;
        this._startNodeId = startId;

        const layout =
            this._dagreReady && window.dagre
                ? this.computeDagreLayout(rawNodes, rawEdges, nodeById)
                : this.computeBfsLayout(rawNodes, rawEdges, nodeById, startId);

        this.nodes = rawNodes
            .filter((node) => layout.positionById.has(node.id))
            .map((node) => {
                const position = layout.positionById.get(node.id);
                const isStart = node.id === startId;
                return {
                    id: node.id,
                    name: node.name,
                    subLabel: this.buildSubLabel(node),
                    x: position.x,
                    y: position.y,
                    textX: position.x + NODE_WIDTH / 2,
                    nameY: position.y + 26,
                    typeY: position.y + 46,
                    width: NODE_WIDTH,
                    height: NODE_HEIGHT,
                    cssClass:
                        (TYPE_CLASS[node.typeNoeud] || 'node') +
                        (isStart ? ' node_start' : '')
                };
            });

        this.edges = layout.edges;
        this.svgWidth = layout.width;
        this.svgHeight = layout.height;
    }

    /**
     * Disposition optimisée par dagre : rangs horizontaux (gauche -> droite),
     * tracés d'arêtes multi-points contournant les nœuds. Les coordonnées de
     * nœud renvoyées par dagre sont des centres : on les ramène au coin supérieur
     * gauche attendu par le rendu SVG.
     */
    computeDagreLayout(rawNodes, rawEdges, nodeById) {
        const g = new window.dagre.graphlib.Graph({ multigraph: true });
        g.setGraph({
            rankdir: 'LR',
            nodesep: V_GAP,
            ranksep: H_GAP,
            marginx: MARGIN,
            marginy: MARGIN
        });
        g.setDefaultEdgeLabel(() => ({}));

        rawNodes.forEach((node) =>
            g.setNode(node.id, { width: NODE_WIDTH, height: NODE_HEIGHT })
        );
        rawEdges.forEach((edge, index) => {
            if (nodeById.has(edge.source) && nodeById.has(edge.target)) {
                g.setEdge(edge.source, edge.target, {}, edge.id || `edge-${index}`);
            }
        });

        window.dagre.layout(g);

        const positionById = new Map();
        rawNodes.forEach((node) => {
            const n = g.node(node.id);
            if (n) {
                positionById.set(node.id, {
                    x: n.x - NODE_WIDTH / 2,
                    y: n.y - NODE_HEIGHT / 2
                });
            }
        });

        const edges = rawEdges
            .filter((edge) => nodeById.has(edge.source) && nodeById.has(edge.target))
            .map((edge, index) => {
                const name = edge.id || `edge-${index}`;
                const e = g.edge(edge.source, edge.target, name);
                const points = (e && e.points) || [];
                return this.buildEdge(name, points, edge.libelle);
            });

        const graphInfo = g.graph();
        return {
            positionById,
            edges,
            width: Math.ceil(graphInfo.width || MARGIN * 2),
            height: Math.ceil(graphInfo.height || MARGIN * 2)
        };
    }

    /**
     * Disposition de repli : profondeur de chaque nœud via un parcours en largeur
     * depuis le départ, nœuds d'un même niveau empilés verticalement. Les arêtes
     * sont des segments droits d'un bord de nœud à l'autre.
     */
    computeBfsLayout(rawNodes, rawEdges, nodeById, startId) {
        const outgoing = new Map();
        rawEdges.forEach((edge) => {
            if (!outgoing.has(edge.source)) {
                outgoing.set(edge.source, []);
            }
            outgoing.get(edge.source).push(edge.target);
        });

        const depthById = new Map();
        const queue = [];
        if (startId) {
            depthById.set(startId, 0);
            queue.push(startId);
        }
        while (queue.length) {
            const current = queue.shift();
            const currentDepth = depthById.get(current);
            (outgoing.get(current) || []).forEach((target) => {
                if (nodeById.has(target) && !depthById.has(target)) {
                    depthById.set(target, currentDepth + 1);
                    queue.push(target);
                }
            });
        }

        let maxDepth = 0;
        depthById.forEach((depth) => {
            if (depth > maxDepth) {
                maxDepth = depth;
            }
        });
        rawNodes.forEach((node) => {
            if (!depthById.has(node.id)) {
                depthById.set(node.id, maxDepth + 1);
            }
        });

        const byDepth = new Map();
        rawNodes.forEach((node) => {
            const depth = depthById.get(node.id);
            if (!byDepth.has(depth)) {
                byDepth.set(depth, []);
            }
            byDepth.get(depth).push(node);
        });

        let maxRows = 0;
        byDepth.forEach((group) => {
            if (group.length > maxRows) {
                maxRows = group.length;
            }
        });

        const positionById = new Map();
        Array.from(byDepth.keys())
            .sort((a, b) => a - b)
            .forEach((depth) => {
                byDepth.get(depth).forEach((node, index) => {
                    positionById.set(node.id, {
                        x: MARGIN + depth * (NODE_WIDTH + H_GAP),
                        y: MARGIN + index * (NODE_HEIGHT + V_GAP)
                    });
                });
            });

        const edges = rawEdges
            .filter(
                (edge) =>
                    positionById.has(edge.source) &&
                    positionById.has(edge.target)
            )
            .map((edge, index) => {
                const source = positionById.get(edge.source);
                const target = positionById.get(edge.target);
                const points = [
                    { x: source.x + NODE_WIDTH, y: source.y + NODE_HEIGHT / 2 },
                    { x: target.x, y: target.y + NODE_HEIGHT / 2 }
                ];
                return this.buildEdge(edge.id || `edge-${index}`, points, edge.libelle);
            });

        return {
            positionById,
            edges,
            width: MARGIN * 2 + (maxDepth + 2) * (NODE_WIDTH + H_GAP),
            height: MARGIN * 2 + Math.max(maxRows, 1) * (NODE_HEIGHT + V_GAP)
        };
    }

    /**
     * Construit le modèle de vue d'une arête à partir d'une polyligne : chaîne
     * `points` pour le tracé, pointe de flèche orientée selon le dernier segment,
     * et position du libellé au milieu du tracé.
     */
    buildEdge(id, points, libelle) {
        const safePoints =
            points && points.length >= 2
                ? points
                : [
                      { x: 0, y: 0 },
                      { x: 0, y: 0 }
                  ];
        const pointsAttr = safePoints.map((p) => `${p.x},${p.y}`).join(' ');

        const tip = safePoints[safePoints.length - 1];
        const prev = safePoints[safePoints.length - 2];
        let dx = tip.x - prev.x;
        let dy = tip.y - prev.y;
        const length = Math.hypot(dx, dy) || 1;
        dx /= length;
        dy /= length;
        const back = 9;
        const half = 5;
        const baseX = tip.x - dx * back;
        const baseY = tip.y - dy * back;
        const perpX = -dy;
        const perpY = dx;
        const arrowPoints = `${tip.x},${tip.y} ${baseX + perpX * half},${
            baseY + perpY * half
        } ${baseX - perpX * half},${baseY - perpY * half}`;

        const mid = safePoints[Math.floor(safePoints.length / 2)];
        return {
            id,
            points: pointsAttr,
            arrowPoints,
            labelX: mid.x,
            labelY: mid.y - 6,
            libelle
        };
    }

    buildSubLabel(node) {
        if (node.typeNoeud === 'Action') {
            return node.typeAction ? `Action : ${node.typeAction}` : 'Action';
        }
        return node.typeNoeud || '';
    }

    /**
     * Sélectionne un nœud : mémorise son identité et reconstruit la liste des
     * réponses/destinations sortantes à partir des arêtes brutes.
     */
    selectNode(nodeId) {
        this.selectedNodeId = nodeId;
        const node = this._rawNodes.find((item) => item.id === nodeId);
        this.selectedNodeName = node ? node.name : '';
        this.responseRows = this._rawEdges
            .filter((edge) => edge.source === nodeId)
            .map((edge) => ({
                key: edge.id,
                transitionId: edge.id,
                libelle: edge.libelle || '',
                targetId: edge.target,
                isNew: false,
                ordre: edge.ordre
            }));
    }

    handleNodeClick(event) {
        this.selectNode(event.currentTarget.dataset.id);
    }

    handleNodeKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleNodeClick(event);
        }
    }

    handleClosePanel() {
        this.selectedNodeId = undefined;
        this.selectedNodeName = undefined;
        this.responseRows = [];
    }

    handleZoomIn() {
        this.zoom = Math.min(ZOOM_MAX, Math.round((this.zoom + ZOOM_STEP) * 10) / 10);
    }

    handleZoomOut() {
        this.zoom = Math.max(ZOOM_MIN, Math.round((this.zoom - ZOOM_STEP) * 10) / 10);
    }

    // Enregistrement du nœud via lightning-record-edit-form (LDS).
    handleNodeSaveSuccess() {
        this.showToast('Succès', 'Nœud enregistré.', 'success');
        return refreshApex(this._wiredGraph);
    }

    handleNodeSaveError(event) {
        const detail = event.detail || {};
        this.showToast(
            'Erreur',
            detail.message || "Impossible d'enregistrer le nœud.",
            'error'
        );
    }

    // « Définir comme départ » : pointe Parcours.NoeudDepart_FK vers ce nœud.
    async handleSetStart() {
        try {
            const fields = {};
            fields[PARCOURS_ID.fieldApiName] = this.recordId;
            fields[PARCOURS_START.fieldApiName] = this.selectedNodeId;
            await updateRecord({ fields });
            this.showToast(
                'Succès',
                'Nœud défini comme point de départ.',
                'success'
            );
            await refreshApex(this._wiredGraph);
        } catch (error) {
            this.showToast('Erreur', this.reduceError(error), 'error');
        }
    }

    handleAddResponse() {
        this._draftSeq += 1;
        this.responseRows = [
            ...this.responseRows,
            {
                key: `draft-${this._draftSeq}`,
                transitionId: null,
                libelle: '',
                targetId: null,
                isNew: true,
                ordre: this.responseRows.length + 1
            }
        ];
    }

    handleResponseLibelle(event) {
        const { key } = event.target.dataset;
        const value = event.target.value;
        this.responseRows = this.responseRows.map((row) =>
            row.key === key ? { ...row, libelle: value } : row
        );
    }

    handleResponseTarget(event) {
        const { key } = event.target.dataset;
        const value = event.detail.value;
        this.responseRows = this.responseRows.map((row) =>
            row.key === key ? { ...row, targetId: value } : row
        );
    }

    async handleDeleteResponse(event) {
        const { key } = event.currentTarget.dataset;
        const row = this.responseRows.find((item) => item.key === key);
        if (row && row.transitionId) {
            try {
                await deleteRecord(row.transitionId);
                this.showToast('Succès', 'Réponse supprimée.', 'success');
                await refreshApex(this._wiredGraph);
            } catch (error) {
                this.showToast('Erreur', this.reduceError(error), 'error');
                return;
            }
        }
        this.responseRows = this.responseRows.filter(
            (item) => item.key !== key
        );
    }

    /**
     * Persiste toutes les réponses : création des brouillons, mise à jour des
     * transitions existantes. Les lignes sans destination sont ignorées.
     */
    async handleSaveResponses() {
        const operations = this.responseRows
            .filter((row) => row.targetId)
            .map((row) => {
                if (row.isNew) {
                    const fields = {};
                    fields[TR_SOURCE.fieldApiName] = this.selectedNodeId;
                    fields[TR_CIBLE.fieldApiName] = row.targetId;
                    fields[TR_LIBELLE.fieldApiName] = row.libelle;
                    fields[TR_ORDRE.fieldApiName] = row.ordre;
                    return createRecord({
                        apiName: TRANSITION_OBJECT.objectApiName,
                        fields
                    });
                }
                const fields = { Id: row.transitionId };
                fields[TR_CIBLE.fieldApiName] = row.targetId;
                fields[TR_LIBELLE.fieldApiName] = row.libelle;
                return updateRecord({ fields });
            });

        if (operations.length === 0) {
            this.showToast(
                'Information',
                'Renseignez au moins une destination avant d’enregistrer.',
                'info'
            );
            return;
        }

        try {
            await Promise.all(operations);
            this.showToast('Succès', 'Réponses enregistrées.', 'success');
            await refreshApex(this._wiredGraph);
        } catch (error) {
            this.showToast('Erreur', this.reduceError(error), 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    reduceError(error) {
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        if (typeof error.message === 'string') {
            return error.message;
        }
        return 'Une erreur est survenue.';
    }
}
