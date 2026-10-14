/**
 * Utilitaires de texte partagés par les visualiseurs de graphe de parcours
 * (parcoursGraphViewer, parcoursSessionViewer) : mesure en pixels, troncature
 * et découpage en lignes pour que les libellés tiennent dans les boîtes SVG,
 * et conversion du Texte d'un nœud (éventuellement en HTML) en texte brut.
 */

const ELLIPSIS = '…';

const HTML_ENTITIES = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'"
};

let measureContext;

/**
 * Largeur en pixels d'un texte dans une police CSS donnée (canvas 2D) ; repli
 * sur une estimation par caractère si le canvas n'est pas disponible.
 */
export function measureText(text, font) {
    if (measureContext === undefined) {
        try {
            measureContext = document.createElement('canvas').getContext('2d') || null;
        } catch {
            // Canvas indisponible (ex : environnement de test) : estimation.
            measureContext = null;
        }
    }
    if (!measureContext) {
        const size = parseInt((font.match(/(\d+)px/) || [])[1] || '12', 10);
        return String(text).length * size * 0.6;
    }
    measureContext.font = font;
    return measureContext.measureText(text).width;
}

/** Tronque un texte avec « … » pour qu'il tienne dans la largeur donnée. */
export function truncateToWidth(text, font, maxWidth) {
    if (measureText(text, font) <= maxWidth) {
        return text;
    }
    let end = text.length;
    while (end > 0 && measureText(text.slice(0, end) + ELLIPSIS, font) > maxWidth) {
        end--;
    }
    return text.slice(0, end).trimEnd() + ELLIPSIS;
}

/**
 * Découpe un texte en lignes (au mot) tenant dans la largeur donnée ; la
 * dernière ligne autorisée absorbe le reste et est tronquée si nécessaire.
 */
export function wrapText(text, font, maxWidth, maxLines) {
    const words = String(text || '').trim().split(/\s+/).filter(Boolean);
    const lines = [];
    let current = '';
    let index = 0;
    while (index < words.length && lines.length < maxLines - 1) {
        const candidate = current ? `${current} ${words[index]}` : words[index];
        if (!current || measureText(candidate, font) <= maxWidth) {
            current = candidate;
            index++;
        } else {
            lines.push(current);
            current = '';
        }
    }
    const rest = [current, ...words.slice(index)].filter(Boolean).join(' ');
    if (rest) {
        lines.push(rest);
    }
    return lines.map((line) => truncateToWidth(line, font, maxWidth));
}

/**
 * Convertit un contenu éventuellement HTML en texte brut sur une ligne :
 * balises retirées, entités courantes décodées, espaces normalisés.
 */
export function toPlainText(value) {
    if (!value) {
        return '';
    }
    return String(value)
        .replace(/<br\s*\/?>|<\/(p|div|li|h\d)>/gi, ' ')
        .replace(/<[^>]*>/g, '')
        .replace(/&[a-z#0-9]+;/gi, (entity) => HTML_ENTITIES[entity.toLowerCase()] ?? entity)
        .replace(/\s+/g, ' ')
        .trim();
}
