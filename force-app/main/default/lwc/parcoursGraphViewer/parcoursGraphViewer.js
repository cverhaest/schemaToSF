import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { loadScript } from 'lightning/platformResourceLoader';
import { createRecord, updateRecord, deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import DAGRE from '@salesforce/resourceUrl/dagre';
import getGraph from '@salesforce/apex/ParcoursGraphController.getGraph';
import { measureText, toPlainText, truncateToWidth, wrapText } from 'c/parcoursGraphText';
import TRANSITION_OBJECT from '@salesforce/schema/Transition__c';
import TR_SOURCE from '@salesforce/schema/Transition__c.NoeudSource_FK__c';
import TR_CIBLE from '@salesforce/schema/Transition__c.NoeudCible_FK__c';
import TR_LIBELLE from '@salesforce/schema/Transition__c.Libelle_reponse__c';
import TR_ORDRE from '@salesforce/schema/Transition__c.Ordre__c';
import PARCOURS_ID from '@salesforce/schema/Parcours__c.Id';
import PARCOURS_START from '@salesforce/schema/Parcours__c.NoeudDepart_FK__c';

// Boîtes de nœuds : largeur fixe, hauteur ajustée au nombre de lignes de texte.
const NODE_WIDTH = 200;
const NODE_MIN_HEIGHT = 52;
const NODE_PAD_X = 12;
const NODE_PAD_Y = 10;
const NAME_LINE_HEIGHT = 15;
const SUB_LINE_HEIGHT = 14;
const NAME_SUB_GAP = 4;
const NAME_MAX_LINES = 3;

// Libellés d'arêtes : largeur bornée, place réservée dans la disposition.
const EDGE_LABEL_MAX_WIDTH = 140;
const EDGE_LABEL_MAX_LINES = 2;
const EDGE_LINE_HEIGHT = 13;
const EDGE_LABEL_PAD = 4;

const H_GAP = 40; // écart entre deux niveaux (hors place réservée aux libellés)
const V_GAP = 28; // écart vertical entre deux nœuds d'un même niveau
const MARGIN = 24;

// Polices utilisées pour la mesure ; alignées sur le CSS du composant.
const FONT_FAMILY = "'Salesforce Sans', Arial, sans-serif";
const NAME_FONT = `600 12px ${FONT_FAMILY}`;
const SUB_FONT = `11px ${FONT_FAMILY}`;
const EDGE_FONT = `11px ${FONT_FAMILY}`;

// Longueur maximale du Texte dans les options du menu « destination ».
const OPTION_TEXT_MAX = 60;

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
        return this._rawNodes.map((node) => {
            const texte = toPlainText(node.texte);
            const extrait =
                texte.length > OPTION_TEXT_MAX
                    ? `${texte.slice(0, OPTION_TEXT_MAX).trimEnd()}…`
                    : texte;
            return {
                label: extrait ? `${node.name} — ${extrait}` : node.name,
                value: node.id
            };
        });
    }

    /**
     * Produit les modèles de vue des nœuds et des arêtes. Les textes sont
     * mesurés d'abord (hauteur des boîtes, taille des libellés) pour que la
     * disposition leur réserve la place nécessaire. Le calcul des positions est
     * délégué à dagre (disposition en couches avec minimisation des croisements)
     * dès qu'il est chargé ; tant qu'il ne l'est pas, un repli BFS fournit une
     * disposition immédiate.
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

        const boxById = this.measureNodes(rawNodes);
        const validEdges = rawEdges
            .filter((edge) => nodeById.has(edge.source) && nodeById.has(edge.target))
            .map((edge, index) => ({
                ...edge,
                key: edge.id || `edge-${index}`,
                label: this.measureEdgeLabel(edge.libelle)
            }));

        const layout =
            this._dagreReady && window.dagre
                ? this.computeDagreLayout(rawNodes, validEdges, boxById)
                : this.computeBfsLayout(rawNodes, validEdges, boxById, startId);

        this.nodes = rawNodes
            .filter((node) => layout.positionById.has(node.id))
            .map((node) =>
                this.buildNodeModel(
                    node,
                    layout.positionById.get(node.id),
                    boxById.get(node.id),
                    node.id === startId
                )
            );

        this.edges = layout.edges;
        this.svgWidth = layout.width;
        this.svgHeight = layout.height;
    }

    /**
     * Mesure le contenu de chaque nœud : Texte métier (3 lignes max, à défaut la
     * clé du nœud) puis une ligne « clé · type ». Renvoie lignes et hauteur.
     */
    measureNodes(rawNodes) {
        const textWidth = NODE_WIDTH - NODE_PAD_X * 2;
        const boxById = new Map();
        rawNodes.forEach((node) => {
            const texte = toPlainText(node.texte);
            const nameLines = wrapText(texte || node.name, NAME_FONT, textWidth, NAME_MAX_LINES);
            const subLabel = (texte ? [node.name, this.buildSubLabel(node)] : [this.buildSubLabel(node)])
                .filter(Boolean)
                .join(' · ');
            const subLines = subLabel ? [truncateToWidth(subLabel, SUB_FONT, textWidth)] : [];
            const textHeight =
                nameLines.length * NAME_LINE_HEIGHT +
                (subLines.length ? NAME_SUB_GAP + subLines.length * SUB_LINE_HEIGHT : 0);

            boxById.set(node.id, {
                nameLines,
                subLines,
                textHeight,
                width: NODE_WIDTH,
                height: Math.max(NODE_MIN_HEIGHT, Math.ceil(textHeight + NODE_PAD_Y * 2))
            });
        });
        return boxById;
    }

    /** Mesure le libellé d'une arête (réponse) : lignes et encombrement. */
    measureEdgeLabel(libelle) {
        if (!libelle) {
            return null;
        }
        const lines = wrapText(libelle, EDGE_FONT, EDGE_LABEL_MAX_WIDTH, EDGE_LABEL_MAX_LINES);
        const widest = lines.reduce((max, line) => Math.max(max, measureText(line, EDGE_FONT)), 0);
        return {
            lines,
            width: Math.ceil(widest + EDGE_LABEL_PAD * 2),
            height: lines.length * EDGE_LINE_HEIGHT + EDGE_LABEL_PAD * 2
        };
    }

    /** Modèle de vue d'un nœud : boîte et lignes de texte centrées verticalement. */
    buildNodeModel(node, position, box, isStart) {
        let cursor = position.y + (box.height - box.textHeight) / 2;
        const lines = [];
        box.nameLines.forEach((text, index) => {
            cursor += NAME_LINE_HEIGHT;
            lines.push({ key: `n${index}`, text, y: cursor - 4, cssClass: 'node-name' });
        });
        if (box.subLines.length) {
            cursor += NAME_SUB_GAP;
        }
        box.subLines.forEach((text, index) => {
            cursor += SUB_LINE_HEIGHT;
            lines.push({ key: `s${index}`, text, y: cursor - 3, cssClass: 'node-sub' });
        });

        const texte = toPlainText(node.texte);
        return {
            id: node.id,
            name: node.name,
            tooltip: [texte, node.name, this.buildSubLabel(node)].filter(Boolean).join(' — '),
            ariaLabel: texte ? `${node.name} : ${texte}` : node.name,
            x: position.x,
            y: position.y,
            textX: position.x + box.width / 2,
            lines,
            width: box.width,
            height: box.height,
            cssClass: (TYPE_CLASS[node.typeNoeud] || 'node') + (isStart ? ' node_start' : '')
        };
    }

    /**
     * Disposition optimisée par dagre : rangs horizontaux (gauche -> droite),
     * tracés d'arêtes multi-points contournant les nœuds, place réservée aux
     * libellés d'arêtes. Les coordonnées renvoyées sont des centres : on les
     * ramène au coin supérieur gauche attendu par le rendu SVG.
     */
    computeDagreLayout(rawNodes, edges, boxById) {
        const g = new window.dagre.graphlib.Graph({ multigraph: true });
        g.setGraph({
            rankdir: 'LR',
            nodesep: V_GAP,
            ranksep: H_GAP,
            edgesep: 12,
            marginx: MARGIN,
            marginy: MARGIN
        });
        g.setDefaultEdgeLabel(() => ({}));

        rawNodes.forEach((node) => {
            const box = boxById.get(node.id);
            g.setNode(node.id, { width: box.width, height: box.height });
        });
        edges.forEach((edge) => {
            const label = edge.label
                ? { width: edge.label.width, height: edge.label.height, labelpos: 'c' }
                : {};
            g.setEdge(edge.source, edge.target, label, edge.key);
        });

        window.dagre.layout(g);

        const positionById = new Map();
        rawNodes.forEach((node) => {
            const n = g.node(node.id);
            if (n) {
                positionById.set(node.id, { x: n.x - n.width / 2, y: n.y - n.height / 2 });
            }
        });

        const edgeModels = edges.map((edge) => {
            const e = g.edge(edge.source, edge.target, edge.key);
            const points = (e && e.points) || [];
            const center =
                e && edge.label && Number.isFinite(e.x) && Number.isFinite(e.y)
                    ? { x: e.x, y: e.y }
                    : null;
            return this.buildEdge(edge.key, points, edge.libelle, edge.label, center);
        });

        const graphInfo = g.graph();
        return {
            positionById,
            edges: edgeModels,
            width: Math.ceil(graphInfo.width || MARGIN * 2),
            height: Math.ceil(graphInfo.height || MARGIN * 2)
        };
    }

    /**
     * Disposition de repli : profondeur de chaque nœud via un parcours en largeur
     * depuis le départ, nœuds d'un même niveau empilés verticalement. Les arêtes
     * sont des segments droits d'un bord de nœud à l'autre ; l'écart entre
     * niveaux couvre la largeur maximale d'un libellé d'arête.
     */
    computeBfsLayout(rawNodes, edges, boxById, startId) {
        const outgoing = new Map();
        edges.forEach((edge) => {
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
                if (boxById.has(target) && !depthById.has(target)) {
                    depthById.set(target, currentDepth + 1);
                    queue.push(target);
                }
            });
        }

        let maxDepth = 0;
        depthById.forEach((depth) => {
            maxDepth = Math.max(maxDepth, depth);
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

        const gap = Math.max(H_GAP * 2, EDGE_LABEL_MAX_WIDTH + EDGE_LABEL_PAD * 2 + 32);
        const positionById = new Map();
        let maxColumnHeight = 0;
        let lastDepth = 0;
        Array.from(byDepth.keys())
            .sort((a, b) => a - b)
            .forEach((depth) => {
                let y = MARGIN;
                byDepth.get(depth).forEach((node) => {
                    positionById.set(node.id, { x: MARGIN + depth * (NODE_WIDTH + gap), y });
                    y += boxById.get(node.id).height + V_GAP;
                });
                maxColumnHeight = Math.max(maxColumnHeight, y - V_GAP);
                lastDepth = Math.max(lastDepth, depth);
            });

        const edgeModels = edges
            .filter((edge) => positionById.has(edge.source) && positionById.has(edge.target))
            .map((edge) => {
                const source = positionById.get(edge.source);
                const target = positionById.get(edge.target);
                const sourceBox = boxById.get(edge.source);
                const targetBox = boxById.get(edge.target);
                const points = [
                    { x: source.x + sourceBox.width, y: source.y + sourceBox.height / 2 },
                    { x: target.x, y: target.y + targetBox.height / 2 }
                ];
                return this.buildEdge(edge.key, points, edge.libelle, edge.label, null);
            });

        return {
            positionById,
            edges: edgeModels,
            width: MARGIN * 2 + (lastDepth + 1) * NODE_WIDTH + lastDepth * gap,
            height: Math.max(maxColumnHeight, NODE_MIN_HEIGHT) + MARGIN
        };
    }

    /**
     * Construit le modèle de vue d'une arête à partir d'une polyligne : chaîne
     * `points` pour le tracé, pointe de flèche orientée selon le dernier segment,
     * libellé sur fond, centré sur la place réservée par la disposition ou, à
     * défaut, au milieu du tracé.
     */
    buildEdge(id, points, libelle, label, center) {
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

        const model = { id, points: pointsAttr, arrowPoints, libelle, hasLabel: false };
        if (!label) {
            return model;
        }

        let anchor = center;
        if (!anchor) {
            const first = safePoints[0];
            const last = safePoints[safePoints.length - 1];
            anchor = { x: (first.x + last.x) / 2, y: (first.y + last.y) / 2 };
        }
        const top = anchor.y - label.height / 2;
        return {
            ...model,
            hasLabel: true,
            labelBoxX: anchor.x - label.width / 2,
            labelBoxY: top,
            labelBoxWidth: label.width,
            labelBoxHeight: label.height,
            labelX: anchor.x,
            labelLines: label.lines.map((text, index) => ({
                key: `${id}-l${index}`,
                text,
                y: top + EDGE_LABEL_PAD + (index + 1) * EDGE_LINE_HEIGHT - 3
            }))
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
        this.selectedNodeName = node ? toPlainText(node.texte) || node.name : '';
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
