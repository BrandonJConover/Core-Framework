/**
 * HuffmanCodec530 — TS port of rt4 HuffmanCodec.java for QuickChat decoding.
 *
 * Source of truth (read-only):
 *   reference/rt4-client/client/src/main/java/rt4/HuffmanCodec.java (250 lines)
 *
 * Construction is from a bits[] array (one byte per symbol = codeword length
 * in bits, 0 if symbol is not used). The decoder walks `symbolTree` bit-by-bit
 * across the input bytes, emitting a symbol every time it lands on a leaf
 * (negative entry encodes ~symbol). Quirks preserved verbatim from rt4:
 *   - symbolTree is dynamically grown via doubling
 *   - Each bit of the input drives left/right traversal; bit ordering matches
 *     rt4's `local25 & mask` checks (high-bit-first within each byte).
 */

export class HuffmanCodec530 {
    private symbolTree: Int32Array;
    private codewords: Int32Array;
    private bits: Uint8Array;

    constructor(bits: Uint8Array) {
        const symbols = bits.length;
        const nextCodewords = new Int32Array(33);
        this.symbolTree = new Int32Array(8);
        this.codewords = new Int32Array(symbols);
        this.bits = bits;
        let nextNode = 0;
        for (let symbol = 0; symbol < symbols; symbol++) {
            const cwBits = bits[symbol] | 0;
            if (cwBits === 0) continue;
            const bit = 1 << (32 - cwBits);
            const codeword = nextCodewords[cwBits] | 0;
            this.codewords[symbol] = codeword;
            let updatedCw: number;
            if ((codeword & bit) === 0) {
                let local67: number;
                for (local67 = cwBits - 1; local67 >= 1; local67--) {
                    const local76 = nextCodewords[local67] | 0;
                    if (codeword !== local76) break;
                    const local92 = 1 << (32 - local67);
                    if ((local76 & local92) !== 0) {
                        nextCodewords[local67] = nextCodewords[local67 - 1];
                        break;
                    }
                    nextCodewords[local67] = local92 | local76;
                }
                updatedCw = codeword | bit;
            } else {
                updatedCw = nextCodewords[cwBits - 1] | 0;
            }
            nextCodewords[cwBits] = updatedCw;
            for (let local67 = cwBits + 1; local67 <= 32; local67++) {
                if (codeword === (nextCodewords[local67] | 0)) {
                    nextCodewords[local67] = updatedCw;
                }
            }
            // Place leaf node in the symbolTree at the path encoded by codeword.
            // Uses the rolling `nextNode` pointer (the size of the tree so far) for
            // the right-branch destination — NOT (node+1), because the tree is built
            // breadth-incrementally as leaves are added.
            let node = 0;
            for (let b = 0; b < cwBits; b++) {
                const branchBit = (0x80000000 >>> b) | 0;
                if ((codeword & branchBit) === 0) {
                    node++;
                } else {
                    if (this.symbolTree[node] === 0) this.symbolTree[node] = nextNode;
                    node = this.symbolTree[node];
                }
                if (this.symbolTree.length <= node) {
                    const grown = new Int32Array(this.symbolTree.length * 2);
                    grown.set(this.symbolTree);
                    this.symbolTree = grown;
                }
            }
            this.symbolTree[node] = ~symbol;
            if (node >= nextNode) nextNode = node + 1;
        }
    }

    /**
     * Decode `expectedSymbols` symbols from `src` starting at byte offset
     * `srcOffset` into `dst[dstOffset..]`. Returns the number of bytes
     * consumed from src. Mirrors rt4 HuffmanCodec.decode.
     */
    decode(dst: Uint8Array, dstOffset: number, expectedSymbols: number, src: Uint8Array, srcOffset: number): number {
        if (expectedSymbols === 0) return 0;
        let node = 0;
        const dstEnd = dstOffset + expectedSymbols;
        let pos = srcOffset;
        let dpos = dstOffset;
        while (true) {
            const byte = src[pos] | 0;
            // 8 bits per source byte. rt4 unrolls but a loop reads cleaner.
            for (let bit = 7; bit >= 0; bit--) {
                if ((byte & (1 << bit)) === 0) {
                    node++;
                } else {
                    node = this.symbolTree[node];
                }
                const leaf = this.symbolTree[node] | 0;
                if (leaf < 0) {
                    dst[dpos++] = (~leaf) & 0xFF;
                    if (dpos >= dstEnd) return pos - srcOffset + 1;
                    node = 0;
                }
            }
            pos++;
        }
    }

    /**
     * Encode plaintext bytes (`src[srcOffset..srcOffset+len]`) into `dst`
     * starting at `dstOffset`. Returns the number of bytes written.
     */
    encode(len: number, src: Uint8Array, srcOffset: number, dst: Uint8Array, dstOffset: number): number {
        let bitPos = dstOffset << 3;
        let buf = 0;
        let pos = srcOffset;
        const end = srcOffset + len;
        while (pos < end) {
            const sym = src[pos++] & 0xFF;
            const cwLen = this.bits[sym] | 0;
            if (cwLen === 0) throw new Error("HuffmanCodec530: no codeword for symbol " + sym);
            const cw = this.codewords[sym] | 0;
            const bytePos = bitPos >> 3;
            const bitOff = bitPos & 7;
            bitPos += cwLen;
            const lastByte = bytePos + ((bitOff + cwLen - 1) >> 3);
            buf &= (-bitOff) >> 31;
            const shift = bitOff + 24;
            dst[bytePos] = (buf |= (cw >>> shift)) & 0xFF;
            let bp = bytePos;
            let s = shift;
            while (bp < lastByte) {
                bp++;
                s -= 8;
                dst[bp] = (buf = (s < 0 ? (cw << -s) : (cw >>> s))) & 0xFF;
            }
        }
        return ((bitPos + 7) >> 3) - dstOffset;
    }
}

/**
 * Decode a QuickChat-style payload that begins with a smart-int symbol
 * count followed by the Huffman-coded body. The codec parameter is
 * optional — when null/undefined we fall back to the stub string the
 * old PacketHandler returned, so this can be wired incrementally.
 */
export function decodeQuickChatString(
    src: Uint8Array,
    srcOffset: number,
    srcEnd: number,
    codec: HuffmanCodec530 | null,
): { text: string; bytesConsumed: number } {
    if (srcOffset >= srcEnd) return { text: "", bytesConsumed: 0 };
    let pos = srcOffset;
    // Symbol count is a 1- or 2-byte smart int (high bit set ⇒ 2-byte form).
    let symbolCount: number;
    const firstByte = src[pos] & 0xFF;
    if (firstByte < 128) {
        symbolCount = firstByte;
        pos += 1;
    } else {
        symbolCount = (((firstByte & 0x7F) << 8) | (src[pos + 1] & 0xFF));
        pos += 2;
    }
    if (!codec || symbolCount <= 0) {
        return { text: "[quickchat]", bytesConsumed: srcEnd - srcOffset };
    }
    const out = new Uint8Array(symbolCount);
    const consumed = codec.decode(out, 0, symbolCount, src, pos);
    pos += consumed;
    let text = "";
    for (let i = 0; i < symbolCount; i++) text += String.fromCharCode(out[i]);
    return { text, bytesConsumed: pos - srcOffset };
}
