import { Js5Cache } from "../../Js5Cache";

export interface Sprite530 {
    maxWidth: number;
    maxHeight: number;
    xOffset: number;
    yOffset: number;
    width: number;
    height: number;
    pixels: number[];
    palette: number[];
    alpha: number[] | null;
}

class ByteReader {
    pos: number = 0;
    constructor(private readonly data: Uint8Array) {}

    g1(): number { return this.data[this.pos++] & 0xFF; }

    g1b(): number {
        const v = this.g1();
        return v > 127 ? v - 256 : v;
    }

    g2(): number {
        return (this.g1() << 8) | this.g1();
    }

    g3(): number {
        return (this.g1() << 16) | (this.g1() << 8) | this.g1();
    }
}

/**
 * Minimal TypeScript port of rt4-client SpriteLoader.decode() + method4331().
 * This decodes RT4/530 indexed sprite groups from Js5 idx8.
 */
export class SpriteLoader530 {
    static decode(data: Uint8Array): Sprite530[] | null {
        if (!data || data.byteLength < 9) return null;
        const r = new ByteReader(data);
        r.pos = data.byteLength - 2;
        const frames = r.g2();
        if (frames <= 0 || data.byteLength - frames * 8 - 7 < 0) return null;

        const xOffsets = new Array<number>(frames);
        const yOffsets = new Array<number>(frames);
        const innerWidths = new Array<number>(frames);
        const innerHeights = new Array<number>(frames);

        r.pos = data.byteLength - frames * 8 - 7;
        const maxWidth = r.g2();
        const maxHeight = r.g2();
        const paletteSize = r.g1() + 1;
        if (paletteSize <= 1 || data.byteLength + 3 - frames * 8 - paletteSize * 3 - 7 < 0) return null;

        for (let i = 0; i < frames; i++) xOffsets[i] = r.g2();
        for (let i = 0; i < frames; i++) yOffsets[i] = r.g2();
        for (let i = 0; i < frames; i++) innerWidths[i] = r.g2();
        for (let i = 0; i < frames; i++) innerHeights[i] = r.g2();

        r.pos = data.byteLength + 3 - frames * 8 - paletteSize * 3 - 7;
        const palette = new Array<number>(paletteSize).fill(0);
        for (let i = 1; i < paletteSize; i++) {
            palette[i] = r.g3();
            if (palette[i] === 0) palette[i] = 1;
        }

        r.pos = 0;
        const sprites: Sprite530[] = [];
        for (let i = 0; i < frames; i++) {
            const width = innerWidths[i];
            const height = innerHeights[i];
            const count = width * height;
            if (count < 0 || count > data.byteLength * 64) return null;

            const pixels = new Array<number>(count).fill(0);
            const alpha = new Array<number>(count).fill(255);
            let hasAlpha = false;
            const flags = r.g1();

            if ((flags & 1) === 0) {
                for (let p = 0; p < count; p++) pixels[p] = r.g1b();
                if ((flags & 2) !== 0) {
                    for (let p = 0; p < count; p++) {
                        const a = r.g1b();
                        alpha[p] = a & 0xFF;
                        hasAlpha = hasAlpha || a !== -1;
                    }
                }
            } else {
                for (let x = 0; x < width; x++) {
                    for (let y = 0; y < height; y++) {
                        pixels[x + y * width] = r.g1b();
                    }
                }
                if ((flags & 2) !== 0) {
                    for (let x = 0; x < width; x++) {
                        for (let y = 0; y < height; y++) {
                            const a = r.g1b();
                            alpha[x + y * width] = a & 0xFF;
                            hasAlpha = hasAlpha || a !== -1;
                        }
                    }
                }
            }

            sprites.push({
                maxWidth,
                maxHeight,
                xOffset: xOffsets[i],
                yOffset: yOffsets[i],
                width,
                height,
                pixels,
                palette,
                alpha: hasAlpha ? alpha : null
            });
        }
        return sprites;
    }

    static async loadNamed(cache: Js5Cache, name: string): Promise<Sprite530[] | null> {
        const bytes = await cache.getNamedFileBytes(8, name, "");
        return bytes ? SpriteLoader530.decode(bytes) : null;
    }
}
