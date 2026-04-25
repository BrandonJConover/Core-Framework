import { Sprite530 } from "./SpriteLoader530";

export interface Font530 {
    characterPixels: number[][];
    characterWidths: number[];
    characterHeights: number[];
    characterXOffsets: number[];
    characterYOffsets: number[];
    characterScreenWidths: number[];
    characterDefaultHeight: number;
}

/**
 * Compatibility adapter for RT4 font data. The real 530 client renders through
 * Font/SoftwareFont; this converts the same idx8 glyph sprites + idx13 metrics
 * into the older 377 TypeFace shape so the existing renderer can draw readable text.
 */
export class FontLoader530 {
    static decode(metrics: Uint8Array, glyphs: Sprite530[]): Font530 | null {
        if (!metrics || metrics.length < 257 || !glyphs || glyphs.length === 0) return null;

        const screenWidths = new Array<number>(256).fill(6);
        for (let i = 0; i < 256 && i < metrics.length; i++) {
            screenWidths[i] = metrics[i] & 0xFF;
        }

        let defaultHeight = 12;
        if (metrics.length === 257) {
            defaultHeight = metrics[256] & 0xFF;
        } else if (metrics.length >= 768) {
            // rt4 Font.decode(): first 256 glyph widths, next 256 glyph heights,
            // next 256 y bearings; lineHeight = yBearing[' '] + height[' '].
            const height32 = metrics[256 + 32] & 0xFF;
            const yBearing32 = metrics[512 + 32] & 0xFF;
            defaultHeight = yBearing32 + height32;
        }

        const characterPixels = new Array<number[]>(256);
        const characterWidths = new Array<number>(256).fill(0);
        const characterHeights = new Array<number>(256).fill(0);
        const characterXOffsets = new Array<number>(256).fill(0);
        const characterYOffsets = new Array<number>(256).fill(0);

        for (let c = 0; c < 256; c++) {
            const sprite = glyphs[c];
            if (!sprite) {
                characterPixels[c] = [0];
                characterWidths[c] = 1;
                characterHeights[c] = 1;
                continue;
            }
            characterPixels[c] = sprite.pixels.slice();
            characterWidths[c] = sprite.width;
            characterHeights[c] = sprite.height;
            characterXOffsets[c] = sprite.xOffset;
            characterYOffsets[c] = sprite.yOffset;
        }

        return {
            characterPixels,
            characterWidths,
            characterHeights,
            characterXOffsets,
            characterYOffsets,
            characterScreenWidths: screenWidths,
            characterDefaultHeight: defaultHeight || 12
        };
    }
}
