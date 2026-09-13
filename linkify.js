.pragma library

function escapeHtml(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function isWebUrl(value) {
    return /^https?:\/\/[^\s<>"']+$/i.test(String(value));
}

function render(value, color) {
    const text = String(value || "");
    const pattern = /https?:\/\/[^\s<>"']+/gi;
    let result = "";
    let previous = 0;
    let match;
    while ((match = pattern.exec(text)) !== null) {
        let url = match[0].replace(/[.,;!?]+$/, "");
        for (const pair of [["(", ")"], ["[", "]"]]) {
            while (url.endsWith(pair[1]) && url.split(pair[1]).length > url.split(pair[0]).length) url = url.slice(0, -1);
        }
        result += escapeHtml(text.slice(previous, match.index));
        result += '<a style="color:' + escapeHtml(color) + '" href="' + escapeHtml(url) + '">' + escapeHtml(url) + '</a>';
        previous = match.index + url.length;
    }
    result += escapeHtml(text.slice(previous));
    return result.replace(/\n/g, "<br>");
}

function localFileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
}

function luminance(color) {
    function channel(value) { return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4); }
    return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

function contrast(a, b) {
    const x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

function readable(background, preferred, alternate) {
    if (contrast(background, preferred) >= 4.5) return preferred;
    if (contrast(background, alternate) >= 4.5) return alternate;
    // Last-resort text colors for arbitrary user palettes, selected by contrast.
    return luminance(background) > 0.179 ? "#000000" : "#ffffff";
}
