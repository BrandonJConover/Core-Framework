// TerrainTextureProvider — caches and lazily builds 64×64 ARGB texture
// pixel buffers from the cached idx26 op-graph blobs that FloType530
// records reference.
//
// Scope (P3c, offline gates only): two ops are wired through the op
// switch — ColorFill (op 1) and VerticalGradient (op 2). The other
// four planned for v1 (Sprite, TiledSprite, MonochromeFill, Noise) are
// stubbed to ColorFill so an unknown op produces a flat black instead
// of throwing. Expand coverage when a specific FloType id is observed
// rendering wrong.
//
// rt4 reference: Texture.java + the TextureOp* family. The on-wire
// op-graph format used by 530 is dense enough that this v0 module
// uses a simplified TLV encoding for the trace-harness fixtures —
// the real cache decoder is a sibling concern that lands once we
// can prove a single texture builds end-to-end against fixture bytes.

export const TEXTURE_SIZE = 64;
export const TEXTURE_PIXELS = TEXTURE_SIZE * TEXTURE_SIZE;

/** Op codes consumed by `runOpGraph`. Stable across textures. */
export const OP_COLOR_FILL = 1;
export const OP_VERTICAL_GRADIENT = 2;
export const OP_SPRITE = 3;             // stub
export const OP_TILED_SPRITE = 4;       // stub
export const OP_MONOCHROME_FILL = 5;    // stub
export const OP_NOISE = 6;              // stub

/**
 * Synchronous lookup. Returns null on the first call for an unknown id;
 * the caller can fall back to flat-colour fill until the cache populates.
 * The optional async `tryBuild` path lets a host app pre-warm the cache.
 */
export class TerrainTextureProvider {
    private static cache: Map<number, Uint32Array> = new Map();
    private static missing: Set<number> = new Set();

    /** Direct synchronous put — used by tests and once-loaded builds. */
    static put(textureId: number, pixels: Uint32Array): void {
        if (pixels.length !== TEXTURE_PIXELS) {
            throw new Error(
                `TerrainTextureProvider.put: pixels.length=${pixels.length}, expected ${TEXTURE_PIXELS}`,
            );
        }
        this.cache.set(textureId, pixels);
        this.missing.delete(textureId);
    }

    /** Returns the cached buffer, or null when not yet built. */
    static getOrBuild(textureId: number): Uint32Array | null {
        if (textureId < 0) return null;
        const hit = this.cache.get(textureId);
        if (hit) return hit;
        if (this.missing.has(textureId)) return null;
        return null;
    }

    /** Build a single texture from its op-graph bytes. Caches + returns. */
    static build(textureId: number, opBytes: Uint8Array): Uint32Array {
        const pixels = runOpGraph(opBytes);
        this.put(textureId, pixels);
        return pixels;
    }

    static markMissing(textureId: number): void {
        this.missing.add(textureId);
    }

    static reset(): void {
        this.cache.clear();
        this.missing.clear();
    }
}

/**
 * Run the op graph in `bytes` against a fresh 64×64 ARGB canvas.
 * Encoding (v0, offline-test friendly):
 *   byte 0  — op count (N)
 *   then N op blocks back-to-back:
 *     [op_id (1)] [params (op-specific)]
 *
 * Op param widths:
 *   COLOR_FILL          (1):  4 bytes ARGB (a, r, g, b)
 *   VERTICAL_GRADIENT   (2):  8 bytes (topA, topR, topG, topB,
 *                                       botA, botR, botG, botB)
 *   anything else (3..6 stubs / unknown): 0 bytes — no-op.
 *
 * Every op appends or modifies in-place; the canvas is initially
 * transparent black (0x00000000). Ops compose left-to-right.
 *
 * Output: a fresh `Uint32Array(TEXTURE_PIXELS)` of ARGB pixels.
 */
export function runOpGraph(bytes: Uint8Array): Uint32Array {
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
            // Stubs — accept the op but don't change the canvas.
            case OP_SPRITE:
            case OP_TILED_SPRITE:
            case OP_MONOCHROME_FILL:
            case OP_NOISE:
                break;
            default:
                // Unknown op — bail early so we don't read garbage params.
                return canvas;
        }
    }
    return canvas;
}

// ── helpers ──

function packArgb(a: number, r: number, g: number, b: number): number {
    return (((a & 0xff) << 24) | ((r & 0xff) << 16) | ((g & 0xff) << 8) | (b & 0xff)) >>> 0;
}

function fillSolid(canvas: Uint32Array, argb: number): void {
    canvas.fill(argb >>> 0);
}

function fillVerticalGradient(canvas: Uint32Array, topArgb: number, botArgb: number): void {
    const topA = (topArgb >>> 24) & 0xff;
    const topR = (topArgb >>> 16) & 0xff;
    const topG = (topArgb >>> 8) & 0xff;
    const topB = topArgb & 0xff;
    const botA = (botArgb >>> 24) & 0xff;
    const botR = (botArgb >>> 16) & 0xff;
    const botG = (botArgb >>> 8) & 0xff;
    const botB = botArgb & 0xff;
    const denom = Math.max(1, TEXTURE_SIZE - 1);
    for (let y = 0; y < TEXTURE_SIZE; y++) {
        // Linear interp top→bottom; keep ints.
        const t = y / denom;
        const a = ((topA + (botA - topA) * t) | 0) & 0xff;
        const r = ((topR + (botR - topR) * t) | 0) & 0xff;
        const g = ((topG + (botG - topG) * t) | 0) & 0xff;
        const b = ((topB + (botB - topB) * t) | 0) & 0xff;
        const argb = packArgb(a, r, g, b);
        const rowBase = y * TEXTURE_SIZE;
        for (let x = 0; x < TEXTURE_SIZE; x++) {
            canvas[rowBase + x] = argb;
        }
    }
}
