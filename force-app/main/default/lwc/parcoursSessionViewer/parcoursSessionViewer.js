import { LightningElement, api, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import DAGRE from '@salesforce/resourceUrl/dagre';
import getSessionPath from '@salesforce/apex/ParcoursSessionViewerController.getSessionPath';
import { measureText, toPlainText, truncateToWidth, wrapText } from 'c/parcoursGraphText';

// Boîtes de nœuds : largeur fixe, hauteur ajustée au nombre de lignes de texte.
const NODE_WIDTH = 200;
const NODE_MIN_HEIGHT = 52;
const NODE_PAD_X = 12;
const NODE_PAD_Y = 10;
const NAME_LINE_HEIGHT = 15;
const SUB_LINE_HEIGHT = 14;
const NAME_SUB_GAP = 4;
const NAME_MAX_LINES = 3;
const PARCOURS_MAX_LINES = 2;

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

const ZOOM_MIN = 0.4;
const ZOOM_MAX = 1.6;
const ZOOM_STEP = 0.2;

// Classe CSS par type de nœud (couleur sémantique, alignée sur le visualiseur
// de parcours).
const TYPE_CLASS = {
    Question: 'node node_question',
    Navigation: 'node node_navigation',
    Conseil: 'node node_conseil',
    Action: 'node node_action',
    Fin: 'node node_fin'
};

/**
 * Visualise le déroulé d'une session de parcours : la suite des nœuds
 * effectivement franchis, la réponse sélectionnée à chaque embranchement (sur
 * l'arête sortante) et les valeurs saisies (dans le panneau de détail). Même
 * nature graphique que parcoursGraphViewer mais en lecture seule et piloté par
 * une session. Data-driven : tout vient du chemin reconstruit côté Apex.
 */
export default class ParcoursSessionViewer extends LightningElement {
    @api recordId;

    nodes = [];
    edges = [];
    svgWidth = 0;
    svgHeight = 0;
    zoom = 1;
    selectedNodeId;
    errorMessage;

    // En-tête : métadonnées de la session.
    parcoursName;
    statut;
    agentName;
    dateDebut;
    dateFin;

    _rawNodes = [];
    _rawEdges = [];
    _startNodeId;
    _pathData;
    _loaded = false;
    _dagreRequested = false;
    _dagreReady = false;

    @wire(getSessionPath, { sessionId: '$recordId' })
    wiredPath({ data, error }) {
        if (data) {
            this._loaded = true;
            this.errorMessage = undefined;
            this.parcoursName = data.parcoursName;
            this.statut = data.statut;
            this.agentName = data.agentName;
            this.dateDebut = data.dateDebut;
            this.dateFin = data.dateFin;
            this.buildLayout(data);
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
     * Charge dagre une seule fois puis recalcule la disposition. En cas d'échec,
     * la disposition BFS de repli déjà affichée reste en place.
     */
    renderedCallback() {
        if (this._dagreRequested) {
            return;
        }
        this._dagreRequested = true;
        loadScript(this, DAGRE)
            .then(() => {
                this._dagreReady = true;
                if (this._pathData) {
                    this.buildLayout(this._pathData);
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

    // Détail de l'étape sélectionnée pour le panneau latéral (lecture seule).
    get selectedStep() {
        if (!this.selectedNodeId) {
            return undefined;
        }
        const step = this._rawNodes.find(
            (node) => node.id === this.selectedNodeId
        );
        if (!step) {
            return undefined;
        }
        const valeurs = (step.valeurs || []).map((valeur, index) => ({
            key: `${step.id}-v${index}`,
            valeur
        }));
        return {
            id: step.id,
            name: step.name,
            texte: toPlainText(step.texte),
            typeNoeud: step.typeNoeud,
            parcoursNom: step.parcoursNom,
            reponse: step.reponse,
            hasReponse: Boolean(step.reponse),
            valeurs,
            hasValeurs: valeurs.length > 0,
            ordre: step.ordre,
            isCurrent: Boolean(step.isCurrent)
        };
    }

    /**
     * Produit les modèles de vue des nœuds et des arêtes du chemin exécuté. Les
     * textes sont mesurés d'abord (hauteur des boîtes, taille des libellés) pour
     * que la disposition leur réserve la place nécessaire. Le calcul des
     * positions est délégué à dagre dès qu'il est chargé, avec un repli BFS
     * immédiat tant qu'il ne l'est pas.
     */
    buildLayout(path) {
        this._pathData = path;
        const rawNodes = path.nodes || [];
        const rawEdges = path.edges || [];
        this._rawNodes = rawNodes;
        this._rawEdges = rawEdges;

        const nodeById = new Map();
        rawNodes.forEach((node) => nodeById.set(node.id, node));

        const startId =
            path.startNodeId && nodeById.has(path.startNodeId)
                ? path.startNodeId
                : rawNodes.length
                ? rawNodes[0].id
                : null;
        this._startNodeId = startId;

        const boxById = this.measureNodes(rawNodes, rawEdges, nodeById, startId);
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
                    boxById.get(node.id)
                )
            );

        this.edges = layout.edges;
        this.svgWidth = layout.width;
        this.svgHeight = layout.height;
    }

    /**
     * Mesure le contenu de chaque nœud : Texte métier (3 lignes max, à défaut la
     * clé du nœud), ligne « clé · type », et nom du parcours uniquement sur le
     * nœud de départ et lorsqu'on entre dans un autre parcours (saut de
     * Navigation). Renvoie lignes et hauteur par nœud.
     */
    measureNodes(rawNodes, rawEdges, nodeById, startId) {
        const parcoursOfPredecessors = new Map();
        rawEdges.forEach((edge) => {
            const source = nodeById.get(edge.source);
            if (!source) {
                return;
            }
            if (!parcoursOfPredecessors.has(edge.target)) {
                parcoursOfPredecessors.set(edge.target, new Set());
            }
            parcoursOfPredecessors.get(edge.target).add(source.parcoursNom);
        });

        const textWidth = NODE_WIDTH - NODE_PAD_X * 2;
        const boxById = new Map();
        rawNodes.forEach((node) => {
            const predecessors = parcoursOfPredecessors.get(node.id);
            const entersParcours =
                Boolean(node.parcoursNom) &&
                (node.id === startId || !predecessors || !predecessors.has(node.parcoursNom));

            const texte = toPlainText(node.texte);
            const nameLines = wrapText(texte || node.name, NAME_FONT, textWidth, NAME_MAX_LINES);
            const subLabel = (texte ? [node.name, node.typeNoeud] : [node.typeNoeud])
                .filter(Boolean)
                .join(' · ');
            const typeLines = subLabel ? [truncateToWidth(subLabel, SUB_FONT, textWidth)] : [];
            const parcoursLines = entersParcours
                ? wrapText(`↪ ${node.parcoursNom}`, SUB_FONT, textWidth, PARCOURS_MAX_LINES)
                : [];
            const subCount = typeLines.length + parcoursLines.length;
            const textHeight =
                nameLines.length * NAME_LINE_HEIGHT +
                (subCount ? NAME_SUB_GAP + subCount * SUB_LINE_HEIGHT : 0);

            boxById.set(node.id, {
                nameLines,
                typeLines,
                parcoursLines,
                textHeight,
                width: NODE_WIDTH,
                height: Math.max(NODE_MIN_HEIGHT, Math.ceil(textHeight + NODE_PAD_Y * 2))
            });
        });
        return boxById;
    }

    /** Mesure le libellé d'une arête (réponse choisie) : lignes et encombrement. */
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
    buildNodeModel(node, position, box) {
        const centerX = position.x + box.width / 2;
        let cursor = position.y + (box.height - box.textHeight) / 2;
        const lines = [];
        box.nameLines.forEach((text, index) => {
            cursor += NAME_LINE_HEIGHT;
            lines.push({ key: `n${index}`, text, y: cursor - 4, cssClass: 'node-name' });
        });
        if (box.typeLines.length || box.parcoursLines.length) {
            cursor += NAME_SUB_GAP;
        }
        box.typeLines.forEach((text, index) => {
            cursor += SUB_LINE_HEIGHT;
            lines.push({ key: `t${index}`, text, y: cursor - 3, cssClass: 'node-type' });
        });
        box.parcoursLines.forEach((text, index) => {
            cursor += SUB_LINE_HEIGHT;
            lines.push({ key: `p${index}`, text, y: cursor - 3, cssClass: 'node-parcours' });
        });

        return {
            id: node.id,
            name: node.name,
            tooltip: [toPlainText(node.texte), node.name, node.typeNoeud, node.parcoursNom]
                .filter(Boolean)
                .join(' — '),
            x: position.x,
            y: position.y,
            textX: centerX,
            lines,
            width: box.width,
            height: box.height,
            cssClass:
                (TYPE_CLASS[node.typeNoeud] || 'node') + (node.isCurrent ? ' node_current' : '')
        };
    }

    /**
     * Disposition optimisée par dagre : rangs horizontaux (gauche -> droite),
     * tracés d'arêtes multi-points, place réservée aux libellés d'arêtes. Les
     * coordonnées renvoyées sont des centres : on les ramène au coin supérieur
     * gauche attendu par le rendu SVG.
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
            const center = e && e.label !== undefined && Number.isFinite(e.x)
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
     * depuis le départ ; arêtes en segments droits d'un bord à l'autre. L'écart
     * entre niveaux couvre la largeur maximale d'un libellé d'arête.
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
     * libellé (réponse choisie) sur fond, centré sur la place réservée par la
     * disposition ou, à défaut, au milieu du tracé.
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

    selectNode(nodeId) {
        this.selectedNodeId = nodeId;
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
    }

    handleZoomIn() {
        this.zoom = Math.min(ZOOM_MAX, Math.round((this.zoom + ZOOM_STEP) * 10) / 10);
    }

    handleZoomOut() {
        this.zoom = Math.max(ZOOM_MIN, Math.round((this.zoom - ZOOM_STEP) * 10) / 10);
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
