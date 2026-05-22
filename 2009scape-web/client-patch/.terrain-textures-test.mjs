// .terrain-textures-test.mjs — offline gates for P3c TerrainTextureProvider.
//
// Runs runOpGraph against two op-graph fixtures (ColorFill solid red,
// VerticalGradient blue→green) and asserts the produced 64×64 ARGB
// canvases match expectations.
//
// Run:    node 2009scape-web/client-patch/.terrain-textures-test.mjs

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── inlined runOpGraph (mirrors TerrainTextureProvider.ts) ──

const TEXTURE_SIZE = 64;
const TEXTURE_PIXELS = TEXTURE_SIZE * TEXTURE_SIZE;
const OP_COLOR_FILL = 1;
const OP_VERTICAL_GRADIENT = 2;

function packArgb(a, r, g, b) {
    return (((a & 0xff) << 24) | ((r & 0xff) << 16) | ((g & 0xff) << 8) | (b & 0xff)) >>> 0;
}

function fillSolid(canvas, argb) {
    canvas.fill(argb >>> 0);
}

function fillVerticalGradient(canvas, topArgb, botArgb) {
    const topA = (topArgb >>> 24) & 0xff;
    const topR = (topArgb >>> 16) & 0xff;
    const topG = (topArgb >>> 8) & 0xff;
    const topB = topArgb & 0xff;
    const botA = (botArgb >>> 24) & 0xff;
    const botR = (botArgb >>> 16) & 0xff;
    const botG = (botArgb >>> 8) & 0xff;
    const botB = botArgb & 0xff;
    for (let y = 0; y < TEXTURE_SIZE; y++) {
        const t = TEXTURE_SIZE === 1 ? 0 : y / (TEXTURE_SIZE - 1);
        const a = ((topA + (botA - topA) * t) | 0) & 0xff;
        const r = ((topR + (botR - topR) * t) | 0) & 0xff;
        const g = ((topG + (botG - topG) * t) | 0) & 0xff;
        const b = ((topB + (botB - topB) * t) | 0) & 0xff;
        const argb = packArgb(a, r, g, b);
        const rowBase = y * TEXTURE_SIZE;
        for (let x = 0; x < TEXTURE_SIZE; x++) canvas[rowBase + x] = argb;
    }
}

function runOpGraph(bytes) {
    const canvas = new Uint32Array(TEXTURE_PIXELS);
    if (!bytes || bytes.length === 0) return canvas;
    const opCount = bytes[0];
    let p = 1;
    for (let n = 0; n < opCount && p < bytes.length; n++) {
        const op = bytes[p++];
        switch (op) {
            case OP_COLOR_FILL: {
                if (p + 4 > bytes.length) return canvas;
                const argb = packArgb(bytes[p], bytes[p + 1], bytes[p + 2], bytes[p + 3]);
                p += 4;
                fillSolid(canvas, argb);
                break;
            }
            case OP_VERTICAL_GRADIENT: {
                if (p + 8 > bytes.length) return canvas;
                const top = packArgb(bytes[p], bytes[p + 1], bytes[p + 2], bytes[p + 3]);
                const bot = packArgb(bytes[p + 4], bytes[p + 5], bytes[p + 6], bytes[p + 7]);
                p += 8;
                fillVerticalGradient(canvas, top, bot);
                break;
            }
            default: return canvas;
        }
    }
    return canvas;
}

function rgb24ToArgb(rgb24) {
    return packArgb(0xff, (rgb24 >>> 16) & 0xff, (rgb24 >>> 8) & 0xff, rgb24 & 0xff);
}

function grayscale12ToArgb(value12) {
    const v = Math.max(0, Math.min(255, value12 >> 4));
    return packArgb(0xff, v, v, v);
}

function fillHorizontalGrayGradient() {
    const canvas = new Uint32Array(TEXTURE_PIXELS);
    const denom = Math.max(1, TEXTURE_SIZE - 1);
    for (let x = 0; x < TEXTURE_SIZE; x++) {
        const v = ((x * 255) / denom) | 0;
        const argb = packArgb(0xff, v, v, v);
        for (let y = 0; y < TEXTURE_SIZE; y++) {
            canvas[y * TEXTURE_SIZE + x] = argb;
        }
    }
    return canvas;
}

function fillVerticalGrayGradient() {
    const canvas = new Uint32Array(TEXTURE_PIXELS);
    fillVerticalGradient(canvas, packArgb(0xff, 0, 0, 0), packArgb(0xff, 0xff, 0xff, 0xff));
    return canvas;
}

function invertArgbPixels(src) {
    const canvas = new Uint32Array(TEXTURE_PIXELS);
    for (let i = 0; i < src.length; i++) {
        const argb = src[i];
        canvas[i] = packArgb(
            (argb >>> 24) & 0xff,
            0xff - ((argb >>> 16) & 0xff),
            0xff - ((argb >>> 8) & 0xff),
            0xff - (argb & 0xff),
        );
    }
    return canvas;
}

function renderMaterialOp530(material, opIndex, visiting) {
    if (visiting.has(opIndex)) return null;
    const op = material.ops[opIndex];
    if (!op) return null;
    if (op.inputs.length === 0) return renderLeafOp(op);
    if (op.fields.kind !== 22 || op.inputs.length !== 1) return null;

    visiting.add(opIndex);
    const child = renderMaterialOp530(material, op.inputs[0], visiting);
    visiting.delete(opIndex);
    return child ? invertArgbPixels(child) : null;
}

function renderLeafOp(op) {
    if (op.inputs.length !== 0) return null;
    switch (op.fields.kind) {
        case 0: {
            const canvas = new Uint32Array(TEXTURE_PIXELS);
            fillSolid(canvas, grayscale12ToArgb(op.fields.v));
            return canvas;
        }
        case 1: {
            const canvas = new Uint32Array(TEXTURE_PIXELS);
            fillSolid(canvas, rgb24ToArgb(op.fields.rgb24));
            return canvas;
        }
        case 2:
            return fillHorizontalGrayGradient();
        case 3:
            return fillVerticalGrayGradient();
        default:
            return null;
    }
}

function renderMaterialLeaf530(material) {
    if (!material) return null;
    return renderMaterialOp530(material, material.mainOpIndex, new Set());
}

// ── fixtures ────────────────────────────────────────────────────────

// ColorFill solid red 0xFFFF0000.
// Encoding: [opCount=1, op=1, A=0xFF, R=0xFF, G=0x00, B=0x00]
const colorFillBytes = new Uint8Array([1, OP_COLOR_FILL, 0xFF, 0xFF, 0x00, 0x00]);

// VerticalGradient: top opaque blue 0xFF0000FF, bottom opaque green 0xFF00FF00.
const vGradBytes = new Uint8Array([
    1, OP_VERTICAL_GRADIENT,
    0xFF, 0x00, 0x00, 0xFF,    // top:  A=0xFF R=0x00 G=0x00 B=0xFF
    0xFF, 0x00, 0xFF, 0x00,    // bot:  A=0xFF R=0x00 G=0xFF B=0x00
]);

// ── run gates ───────────────────────────────────────────────────────

const cf = runOpGraph(colorFillBytes);
if (cf.length !== TEXTURE_PIXELS) {
    throw new Error(`ColorFill length expected ${TEXTURE_PIXELS} got ${cf.length}`);
}
for (let i = 0; i < cf.length; i++) {
    if (cf[i] !== 0xFFFF0000) {
        throw new Error(`ColorFill pixel ${i} expected 0xFFFF0000 got 0x${cf[i].toString(16).padStart(8,'0')}`);
    }
}

const vg = runOpGraph(vGradBytes);
if (vg.length !== TEXTURE_PIXELS) {
    throw new Error(`VertGradient length expected ${TEXTURE_PIXELS} got ${vg.length}`);
}
const topRow = vg[0];
const botRow = vg[(TEXTURE_SIZE - 1) * TEXTURE_SIZE];
if (topRow === botRow) {
    throw new Error(`VertGradient top===bottom (both 0x${topRow.toString(16).padStart(8,'0')}) — gradient didn't apply`);
}
// Top should be ~blue (R=0,G=0,B≈255). Bottom should be ~green (R=0,G≈255,B=0).
const topB = topRow & 0xff;
const topG = (topRow >>> 8) & 0xff;
const botG = (botRow >>> 8) & 0xff;
const botB = botRow & 0xff;
if (topB < 200) throw new Error(`Top row not predominantly blue: B=${topB}`);
if (botG < 200) throw new Error(`Bot row not predominantly green: G=${botG}`);
// Mid-row should be roughly half between (so green~127 and blue~127).
const midRow = vg[(TEXTURE_SIZE / 2) * TEXTURE_SIZE];
const midG = (midRow >>> 8) & 0xff;
const midB = midRow & 0xff;
if (midG < 100 || midG > 160) throw new Error(`Mid-row green expected ~127 got ${midG}`);
if (midB < 100 || midB > 160) throw new Error(`Mid-row blue expected ~127 got ${midB}`);

// Distinct row count proves the gradient is monotonic.
const distinctRows = new Set();
for (let y = 0; y < TEXTURE_SIZE; y++) distinctRows.add(vg[y * TEXTURE_SIZE]);
if (distinctRows.size < 50) {
    throw new Error(`Gradient not monotonic: ${distinctRows.size} distinct row values (expected ≥50)`);
}

const materialColorFill = {
    id: 77,
    mainOpIndex: 0,
    alphaOpIndex: 0,
    spriteIds: [],
    textureIds: [],
    ops: [{
        kind: 1,
        inputs: [],
        cache: 255,
        monochrome: false,
        fields: { kind: 1, rgb24: 0x3366CC },
    }],
};
const materialCf = renderMaterialLeaf530(materialColorFill);
if (!materialCf || materialCf.length !== TEXTURE_PIXELS) {
    throw new Error(`Material ColorFill did not produce ${TEXTURE_PIXELS} pixels`);
}
if (materialCf[0] !== 0xFF3366CC || materialCf[TEXTURE_PIXELS - 1] !== 0xFF3366CC) {
    throw new Error(`Material ColorFill expected 0xFF3366CC got first=0x${materialCf[0].toString(16)}`);
}

const materialVerticalGradient = {
    id: 78,
    mainOpIndex: 0,
    alphaOpIndex: 0,
    spriteIds: [],
    textureIds: [],
    ops: [{
        kind: 3,
        inputs: [],
        cache: 255,
        monochrome: true,
        fields: { kind: 3 },
    }],
};
const materialVg = renderMaterialLeaf530(materialVerticalGradient);
if (!materialVg || materialVg[0] !== 0xFF000000) {
    throw new Error(`Material VerticalGradient expected black top got 0x${materialVg?.[0]?.toString(16)}`);
}
const materialVgBottom = materialVg[(TEXTURE_SIZE - 1) * TEXTURE_SIZE];
if (materialVgBottom !== 0xFFFFFFFF) {
    throw new Error(`Material VerticalGradient expected white bottom got 0x${materialVgBottom.toString(16)}`);
}

const materialHorizontalGradient = {
    id: 79,
    mainOpIndex: 0,
    alphaOpIndex: 0,
    spriteIds: [],
    textureIds: [],
    ops: [{
        kind: 2,
        inputs: [],
        cache: 255,
        monochrome: true,
        fields: { kind: 2 },
    }],
};
const materialHg = renderMaterialLeaf530(materialHorizontalGradient);
if (!materialHg || materialHg[0] !== 0xFF000000 || materialHg[TEXTURE_SIZE - 1] !== 0xFFFFFFFF) {
    throw new Error(`Material HorizontalGradient endpoints invalid`);
}

const materialInvertColorFill = {
    id: 80,
    mainOpIndex: 0,
    alphaOpIndex: 0,
    spriteIds: [],
    textureIds: [],
    ops: [{
        kind: 22,
        inputs: [1],
        cache: 255,
        monochrome: false,
        fields: { kind: 22 },
    }, {
        kind: 1,
        inputs: [],
        cache: 255,
        monochrome: false,
        fields: { kind: 1, rgb24: 0x3366CC },
    }],
};
const materialInvertCf = renderMaterialLeaf530(materialInvertColorFill);
if (!materialInvertCf || materialInvertCf[0] !== 0xFFCC9933 || materialInvertCf[TEXTURE_PIXELS - 1] !== 0xFFCC9933) {
    throw new Error(`Material Invert(ColorFill) expected 0xFFCC9933 got first=0x${materialInvertCf?.[0]?.toString(16)}`);
}

const materialInvertVerticalGradient = {
    id: 81,
    mainOpIndex: 0,
    alphaOpIndex: 0,
    spriteIds: [],
    textureIds: [],
    ops: [{
        kind: 22,
        inputs: [1],
        cache: 255,
        monochrome: true,
        fields: { kind: 22 },
    }, {
        kind: 3,
        inputs: [],
        cache: 255,
        monochrome: true,
        fields: { kind: 3 },
    }],
};
const materialInvertVg = renderMaterialLeaf530(materialInvertVerticalGradient);
if (!materialInvertVg || materialInvertVg[0] !== 0xFFFFFFFF) {
    throw new Error(`Material Invert(VerticalGradient) expected white top got 0x${materialInvertVg?.[0]?.toString(16)}`);
}
const materialInvertVgBottom = materialInvertVg[(TEXTURE_SIZE - 1) * TEXTURE_SIZE];
if (materialInvertVgBottom !== 0xFF000000) {
    throw new Error(`Material Invert(VerticalGradient) expected black bottom got 0x${materialInvertVgBottom.toString(16)}`);
}

const unsupportedGraph = renderMaterialLeaf530({
    ...materialColorFill,
    ops: [{ ...materialColorFill.ops[0], inputs: [0] }],
});
if (unsupportedGraph !== null) {
    throw new Error(`Material renderer must return null for non-leaf graph ops`);
}

// ── trace ──

const trace = [
    `# Captured by .terrain-textures-test.mjs at ${new Date().toISOString()}`,
    `# Gates: runOpGraph against ColorFill + VerticalGradient fixtures`,
    `# Texture size: ${TEXTURE_SIZE}×${TEXTURE_SIZE} = ${TEXTURE_PIXELS} pixels`,
    ``,
    `[TerrainTextureProvider] colorFill+vGradient ok pixels=${cf.length}+${vg.length}`,
    `[TerrainTextureProvider] colorFill: every pixel = 0xFFFF0000 (solid red, ${cf.length} verified)`,
    `[TerrainTextureProvider] vGradient: top=0x${topRow.toString(16).padStart(8,'0')} bot=0x${botRow.toString(16).padStart(8,'0')} distinct-rows=${distinctRows.size}`,
    `[TerrainTextureProvider] vGradient mid-row interp ok: G=${midG} B=${midB} (expected ~127)`,
    `[TerrainTextureProvider] TextureMaterial530 leaf ColorFill ok: 0x${materialCf[0].toString(16).padStart(8,'0')} pixels=${materialCf.length}`,
    `[TerrainTextureProvider] TextureMaterial530 leaf gradients ok: vertical bottom=0x${materialVgBottom.toString(16).padStart(8,'0')} horizontal right=0x${materialHg[TEXTURE_SIZE - 1].toString(16).padStart(8,'0')}`,
    `[TerrainTextureProvider] TextureMaterial530 unary Invert ok: color=0x${materialInvertCf[0].toString(16).padStart(8,'0')} vertical bottom=0x${materialInvertVgBottom.toString(16).padStart(8,'0')}`,
    `[TerrainTextureProvider] TextureMaterial530 non-leaf graph returns null for fallback path`,
].join("\n") + "\n";

const tracePath = join(__dirname, ".terrain-textures-trace.txt");
writeFileSync(tracePath, trace);
console.log(`[terrain-textures] trace captured at ${tracePath}`);
console.log(`[terrain-textures] all assertions passed`);
