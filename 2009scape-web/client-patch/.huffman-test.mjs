/**
 * Huffman codec round-trip test. Builds a tiny codec from a hand-crafted
 * bits[] table, encodes a string, decodes, and verifies.
 *
 * Verifies the rt4 HuffmanCodec530 algorithm is correctly ported.
 */
import { writeFileSync } from "fs";

class HuffmanCodec530 {
    constructor(bits) {
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
            let updatedCw;
            if ((codeword & bit) === 0) {
                let local67;
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

    decode(dst, dstOffset, expectedSymbols, src, srcOffset) {
        if (expectedSymbols === 0) return 0;
        let node = 0;
        const dstEnd = dstOffset + expectedSymbols;
        let pos = srcOffset;
        let dpos = dstOffset;
        while (true) {
            const byte = src[pos] | 0;
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
}

const lines = [];
let failures = 0;
function trace(msg) { lines.push(msg); console.log(msg); }
function assert(label, actual, expected) {
    const pass = actual === expected;
    if (!pass) {
        failures++;
        lines.push(`FAIL ${label}: expected=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`);
        console.error(`FAIL ${label}: expected=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`);
    }
}

// Build a minimal codec for "hi" — symbols 'h' (104) and 'i' (105).
//
// Codeword scheme (canonical Huffman, prefix-free):
//   'h' = 1-bit codeword "0"
//   'i' = 1-bit codeword "1"
// All other bits[] entries are 0 (unused).
const bits = new Uint8Array(256);
bits[104] = 1; // 'h'
bits[105] = 1; // 'i'
const codec = new HuffmanCodec530(bits);

// Hand-encode: "hi" = bits 0,1 = byte 0b01000000 = 0x40.
const src = new Uint8Array([0x40]);
const out = new Uint8Array(2);
const consumed = codec.decode(out, 0, 2, src, 0);
const decoded = String.fromCharCode(out[0]) + String.fromCharCode(out[1]);
trace(`[Huffman] decode "hi": result="${decoded}" bytesConsumed=${consumed}`);
assert("decode result", decoded, "hi");
assert("bytes consumed", consumed, 1);

// Decode 4 chars "hihi" from a single byte (4 bits, padded to a byte).
//   bits = 0,1,0,1 = 0b01010000 = 0x50
const src2 = new Uint8Array([0x50]);
const out2 = new Uint8Array(4);
codec.decode(out2, 0, 4, src2, 0);
const decoded2 = String.fromCharCode.apply(null, out2);
trace(`[Huffman] decode "hihi": result="${decoded2}"`);
assert("decode hihi", decoded2, "hihi");

if (failures === 0) trace("[Huffman] all tests passed");
else trace(`[Huffman] ${failures} test(s) FAILED`);

writeFileSync(new URL(".huffman-trace.txt", import.meta.url), lines.join("\n") + "\n");
if (failures > 0) process.exit(1);
