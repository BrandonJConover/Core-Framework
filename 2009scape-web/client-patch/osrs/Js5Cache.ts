/**
 * Js5Cache — TypeScript port of rt4-client's Cache.java + Js5Index.java + Js5Compression.java.
 *
 * The 530 cache uses the same sector-chain format the 377 cache used, with two changes:
 *   1. The "archive id" byte in a sector header is 0-indexed (idx0 → 0, idx1 → 1, …).
 *   2. Group ids ≥ 65536 use a 10-byte sector header (4-byte group id + 2 chunk + 3 next + 1 archive)
 *      instead of the usual 8-byte header (2 group + 2 chunk + 3 next + 1 archive).
 *
 * File layout within a group:
 *   1 byte  compressionType  (0=raw, 1=BZIP2, 2=GZIP, 3=LZMA)
 *   4 bytes compressedLength
 *   if type != 0:
 *     4 bytes uncompressedLength
 *     compressedLength bytes of compressed data
 *   else:
 *     compressedLength bytes of raw data
 *
 * A group is a container of one or more files. The Js5Index describes how the bytes of a group
 * are split across files. For groups with a single file, the group's bytes ARE the file bytes.
 * For multi-file groups, the bytes end with a trailer describing per-file chunking.
 *
 * This port is intentionally synchronous — data is already in memory as ArrayBuffer when the
 * client boots (bundled by Parcel's cacheData/cacheIndices imports), so we don't need the
 * rt4-client's async/network logic.
 */

import { BZip2Decompressor } from "./cache/bzip/BZip2Decompressor";
// seek-bzip is a clean pure-JS BZip2 decoder. Used as the primary path because
// the in-tree BZip2Decompressor port has shown CPU-spin behaviour on certain
// 530 idx13 streams; we keep that decoder as a fallback for any edge case
// seek-bzip rejects.
// @ts-ignore — vendored JS, no .d.ts shipped
import Bunzip from "seek-bzip";

export class Js5Sector {
    static readonly SECTOR_SIZE = 520;
    static readonly SMALL_HEADER = 8;   // group(2) chunk(2) nextSector(3) archive(1)
    static readonly LARGE_HEADER = 10;  // group(4) chunk(2) nextSector(3) archive(1)
    static readonly SMALL_DATA_SIZE = 512;
    static readonly LARGE_DATA_SIZE = 510;
}

/** Reads a group's raw (still-compressed) bytes out of an idx/dat pair. */
export class Js5DatIndex {
    readonly archiveId: number;
    readonly indexBuffer: Uint8Array;
    readonly dataBuffer: Uint8Array;

    constructor(archiveId: number, dataBuffer: ArrayBuffer, indexBuffer: ArrayBuffer) {
        this.archiveId = archiveId;
        this.indexBuffer = new Uint8Array(indexBuffer);
        this.dataBuffer = new Uint8Array(dataBuffer);
    }

    /**
     * Returns the number of groups (computed from index-file size).
     */
    capacity(): number {
        return (this.indexBuffer.byteLength / 6) | 0;
    }

    /**
     * Read a group's raw bytes (still compressed). Returns null if the group doesn't exist
     * or the sector chain is invalid.
     */
    readGroup(groupId: number): Uint8Array | null {
        if (groupId < 0 || groupId * 6 + 6 > this.indexBuffer.byteLength) return null;

        // Index entry: size(3) + startSector(3)
        const entryOff = groupId * 6;
        const size =
            ((this.indexBuffer[entryOff] & 0xFF) << 16) |
            ((this.indexBuffer[entryOff + 1] & 0xFF) << 8) |
             (this.indexBuffer[entryOff + 2] & 0xFF);
        let sector =
            ((this.indexBuffer[entryOff + 3] & 0xFF) << 16) |
            ((this.indexBuffer[entryOff + 4] & 0xFF) << 8) |
             (this.indexBuffer[entryOff + 5] & 0xFF);

        if (size <= 0 || sector <= 0) return null;
        if (sector * Js5Sector.SECTOR_SIZE >= this.dataBuffer.byteLength) return null;

        const useLargeHeader = groupId >= 65536;
        const headerSize = useLargeHeader ? Js5Sector.LARGE_HEADER : Js5Sector.SMALL_HEADER;
        const dataSize = Js5Sector.SECTOR_SIZE - headerSize;

        const out = new Uint8Array(size);
        let written = 0;
        let chunk = 0;

        while (written < size) {
            if (sector === 0) return null;
            const base = sector * Js5Sector.SECTOR_SIZE;
            if (base + Js5Sector.SECTOR_SIZE > this.dataBuffer.byteLength) return null;

            // Parse header
            let headerGroupId: number;
            let headerOffset: number;
            if (useLargeHeader) {
                headerGroupId =
                    ((this.dataBuffer[base] & 0xFF) << 24) |
                    ((this.dataBuffer[base + 1] & 0xFF) << 16) |
                    ((this.dataBuffer[base + 2] & 0xFF) << 8) |
                     (this.dataBuffer[base + 3] & 0xFF);
                headerOffset = 4;
            } else {
                headerGroupId =
                    ((this.dataBuffer[base] & 0xFF) << 8) |
                     (this.dataBuffer[base + 1] & 0xFF);
                headerOffset = 2;
            }
            const headerChunk =
                ((this.dataBuffer[base + headerOffset] & 0xFF) << 8) |
                 (this.dataBuffer[base + headerOffset + 1] & 0xFF);
            const headerNext =
                ((this.dataBuffer[base + headerOffset + 2] & 0xFF) << 16) |
                ((this.dataBuffer[base + headerOffset + 3] & 0xFF) << 8) |
                 (this.dataBuffer[base + headerOffset + 4] & 0xFF);
            const headerArchive = this.dataBuffer[base + headerOffset + 5] & 0xFF;

            if (headerGroupId !== groupId || headerChunk !== chunk || headerArchive !== this.archiveId) {
                return null;
            }

            const copyLen = Math.min(dataSize, size - written);
            const dataStart = base + headerSize;
            for (let i = 0; i < copyLen; i++) {
                out[written + i] = this.dataBuffer[dataStart + i];
            }
            written += copyLen;
            sector = headerNext;
            chunk++;
        }
        return out;
    }
}

/** Decompresses a Js5-wrapped blob. Supports raw (0), BZip2 (1), and GZip (2). */
export class Js5Compression {
    /**
     * Decompresses the standard Js5 compressed blob. Returns the uncompressed payload.
     * If decompression fails (bad data or unsupported type) returns null rather than throwing.
     */
    static async uncompress(input: Uint8Array): Promise<Uint8Array | null> {
        if (input.byteLength < 5) return null;
        const type = input[0] & 0xFF;
        const compressedLen =
            ((input[1] & 0xFF) << 24) |
            ((input[2] & 0xFF) << 16) |
            ((input[3] & 0xFF) << 8) |
             (input[4] & 0xFF);
        if (compressedLen < 0 || 5 + compressedLen > input.byteLength) return null;

        if (type === 0) {
            return input.slice(5, 5 + compressedLen);
        }

        if (input.byteLength < 9) return null;
        const uncompressedLen =
            ((input[5] & 0xFF) << 24) |
            ((input[6] & 0xFF) << 16) |
            ((input[7] & 0xFF) << 8) |
             (input[8] & 0xFF);
        if (uncompressedLen < 0) return null;

        if (type === 1) {
            // BZip2. Js5 strips the "BZh1" file header; re-prepend it before decoding.
            if (uncompressedLen > 16 * 1024 * 1024) return null;
            if (uncompressedLen > compressedLen * 64) return null;
            const bz2Input = new Uint8Array(4 + compressedLen);
            bz2Input[0] = 0x42; // 'B'
            bz2Input[1] = 0x5A; // 'Z'
            bz2Input[2] = 0x68; // 'h'
            bz2Input[3] = 0x31; // '1'
            for (let i = 0; i < compressedLen; i++) bz2Input[4 + i] = input[9 + i];
            // Primary path: seek-bzip. Reliable, well-tested, doesn't CPU-spin on
            // edge cases. Pass uncompressedLen as the output buffer size hint.
            try {
                const decoded = Bunzip.decode(bz2Input, uncompressedLen);
                if (decoded && decoded.length >= uncompressedLen) {
                    const u8 = new Uint8Array(uncompressedLen);
                    for (let i = 0; i < uncompressedLen; i++) u8[i] = decoded[i] & 0xFF;
                    return u8;
                }
            } catch (e) {
                // fall through to legacy decoder
            }
            // Fallback: in-tree decoder for any stream seek-bzip refuses.
            const out = new Array<number>(uncompressedLen).fill(0);
            const legacyInput = new Array<number>(4 + compressedLen);
            for (let i = 0; i < bz2Input.length; i++) legacyInput[i] = bz2Input[i];
            try {
                BZip2Decompressor.decompress$byte_A$int$byte_A$int$int(
                    out, uncompressedLen, legacyInput, compressedLen + 4, 0
                );
            } catch (e) {
                return null;
            }
            const u8 = new Uint8Array(uncompressedLen);
            for (let i = 0; i < uncompressedLen; i++) u8[i] = out[i] & 0xFF;
            return u8;
        }

        if (type === 2) {
            // GZip — use browser DecompressionStream if available.
            const ds = (globalThis as any).DecompressionStream;
            if (!ds) return null;
            try {
                const stream = new Response(input.slice(9, 9 + compressedLen)).body;
                if (!stream) return null;
                const decompressed = stream.pipeThrough(new ds("gzip"));
                const buf = await new Response(decompressed).arrayBuffer();
                return new Uint8Array(buf);
            } catch (e) {
                return null;
            }
        }

        // Type 3 (LZMA) not supported yet — most 530 archives use GZip.
        return null;
    }
}

/** Metadata describing the groups / files inside one of the regular (0..N) indexes. */
export class Js5IndexMeta {
    version: number = 0;
    size: number = 0;
    capacity: number = 0;
    groupIds: number[] = [];
    groupNameHashes: number[] | null = null;
    groupCapacities: number[] = [];
    groupSizes: number[] = [];
    groupVersions: number[] = [];
    groupChecksums: number[] = [];
    // fileIds[group] is null when files are densely packed 0..N-1.
    fileIds: (number[] | null)[] = [];
    // fileNameHashes[group][fileId] = name-hash of that file (or -1 if unnamed).
    fileNameHashes: (number[] | null)[] | null = null;

    /** Parse the bytes of a Js5 index-metadata group (from idx255). */
    static parse(blob: Uint8Array): Js5IndexMeta | null {
        const meta = new Js5IndexMeta();
        let pos = 0;
        const u8 = blob;
        const g1 = () => u8[pos++] & 0xFF;
        const g2 = () => {
            const a = u8[pos++] & 0xFF;
            const b = u8[pos++] & 0xFF;
            return (a << 8) | b;
        };
        const g4 = () => {
            const a = u8[pos++] & 0xFF, b = u8[pos++] & 0xFF, c = u8[pos++] & 0xFF, d = u8[pos++] & 0xFF;
            return ((a << 24) | (b << 16) | (c << 8) | d) >>> 0;
        };

        const format = g1();
        if (format !== 5 && format !== 6) return null;
        meta.version = format >= 6 ? g4() : 0;
        const flags = g1();
        meta.size = g2();

        // groupIds — delta-encoded
        let last = -1;
        let maxGroup = -1;
        meta.groupIds = new Array(meta.size);
        let accum = 0;
        for (let i = 0; i < meta.size; i++) {
            accum += g2();
            meta.groupIds[i] = accum;
            if (accum > maxGroup) maxGroup = accum;
        }
        meta.capacity = maxGroup + 1;

        meta.groupVersions = new Array(meta.capacity).fill(0);
        meta.fileIds = new Array(meta.capacity).fill(null);
        meta.groupChecksums = new Array(meta.capacity).fill(0);
        meta.groupCapacities = new Array(meta.capacity).fill(0);
        meta.groupSizes = new Array(meta.capacity).fill(0);

        if ((flags & 1) !== 0) {
            meta.groupNameHashes = new Array(meta.capacity).fill(-1);
            for (let i = 0; i < meta.size; i++) {
                meta.groupNameHashes[meta.groupIds[i]] = (g4() | 0);
            }
        }

        for (let i = 0; i < meta.size; i++) meta.groupChecksums[meta.groupIds[i]] = g4() | 0;
        for (let i = 0; i < meta.size; i++) meta.groupVersions[meta.groupIds[i]] = g4() | 0;
        for (let i = 0; i < meta.size; i++) meta.groupSizes[meta.groupIds[i]] = g2();

        for (let i = 0; i < meta.size; i++) {
            const groupId = meta.groupIds[i];
            const groupSize = meta.groupSizes[groupId];
            let maxFile = -1;
            meta.fileIds[groupId] = new Array(groupSize);
            let fileAccum = 0;
            for (let j = 0; j < groupSize; j++) {
                fileAccum += g2();
                meta.fileIds[groupId]![j] = fileAccum;
                if (fileAccum > maxFile) maxFile = fileAccum;
            }
            meta.groupCapacities[groupId] = maxFile + 1;
            // If densely packed, we can drop the lookup table.
            if (maxFile + 1 === groupSize) meta.fileIds[groupId] = null;
        }

        if ((flags & 1) !== 0) {
            meta.fileNameHashes = new Array(meta.capacity).fill(null);
            for (let i = 0; i < meta.size; i++) {
                const groupId = meta.groupIds[i];
                const groupSize = meta.groupSizes[groupId];
                const hashes = new Array(meta.groupCapacities[groupId]).fill(-1);
                for (let j = 0; j < groupSize; j++) {
                    const fileId = meta.fileIds[groupId] ? meta.fileIds[groupId]![j] : j;
                    hashes[fileId] = g4() | 0;
                }
                meta.fileNameHashes[groupId] = hashes;
            }
        }

        return meta;
    }
}

/**
 * Extracts individual files from a decompressed group blob. Group format: concatenated
 * file bytes followed by a trailer describing file sizes (multi-file groups) or just
 * the file's bytes (single-file groups).
 */
export class Js5Group {
    /** Returns an array of file bytes indexed by dense [0..capacity-1]. */
    static unpack(groupBlob: Uint8Array, fileCount: number): (Uint8Array | null)[] {
        const files: (Uint8Array | null)[] = new Array(fileCount).fill(null);
        if (fileCount === 1) {
            files[0] = groupBlob;
            return files;
        }
        // Multi-file. Last byte is "stripes" count. Then at (end - 1 - stripes*fileCount*4)
        // there's a matrix of per-stripe per-file size deltas.
        if (groupBlob.byteLength === 0) return files;
        const stripes = groupBlob[groupBlob.byteLength - 1] & 0xFF;
        if (stripes === 0) return files;
        const trailerStart = groupBlob.byteLength - 1 - stripes * fileCount * 4;
        if (trailerStart < 0) return files;

        const sizes = new Array<number>(fileCount).fill(0);
        let pos = trailerStart;
        for (let s = 0; s < stripes; s++) {
            let running = 0;
            for (let f = 0; f < fileCount; f++) {
                const delta =
                    ((groupBlob[pos] & 0xFF) << 24) |
                    ((groupBlob[pos + 1] & 0xFF) << 16) |
                    ((groupBlob[pos + 2] & 0xFF) << 8) |
                     (groupBlob[pos + 3] & 0xFF);
                pos += 4;
                running += (delta | 0);
                sizes[f] += running;
            }
        }

        for (let f = 0; f < fileCount; f++) files[f] = new Uint8Array(sizes[f]);

        // Second pass: copy data.
        const writePos = new Array<number>(fileCount).fill(0);
        let readPos = 0;
        pos = trailerStart;
        for (let s = 0; s < stripes; s++) {
            let running = 0;
            for (let f = 0; f < fileCount; f++) {
                const delta =
                    ((groupBlob[pos] & 0xFF) << 24) |
                    ((groupBlob[pos + 1] & 0xFF) << 16) |
                    ((groupBlob[pos + 2] & 0xFF) << 8) |
                     (groupBlob[pos + 3] & 0xFF);
                pos += 4;
                running += (delta | 0);
                const dst = files[f]!;
                for (let i = 0; i < running; i++) dst[writePos[f] + i] = groupBlob[readPos + i];
                writePos[f] += running;
                readPos += running;
            }
        }
        return files;
    }
}

/**
 * High-level facade over the 530 cache. Holds every idx + the shared dat file and exposes
 * getGroup(idx, group) / getFile(idx, group, file) returning raw uncompressed bytes.
 */
export class Js5Cache {
    private readonly indexes: Js5DatIndex[] = [];
    private readonly masterIndex: Js5DatIndex;
    // Lazily-parsed metadata per real index.
    private readonly metaCache: (Js5IndexMeta | null | undefined)[] = [];
    // Lazily-fetched decompressed groups, keyed as `${idxNum}:${groupId}`.
    private readonly groupCache: Map<string, Uint8Array | null> = new Map();

    constructor(dataBuffer: ArrayBuffer, indexBuffers: (ArrayBuffer | null)[], masterIndexBuffer: ArrayBuffer) {
        for (let i = 0; i < indexBuffers.length; i++) {
            if (indexBuffers[i]) {
                this.indexes[i] = new Js5DatIndex(i, dataBuffer, indexBuffers[i]!);
            }
        }
        this.masterIndex = new Js5DatIndex(255, dataBuffer, masterIndexBuffer);
    }

    /** Returns the Js5Index metadata for one of the real indexes (0..N), or null. */
    async getMeta(idxNum: number): Promise<Js5IndexMeta | null> {
        if (this.metaCache[idxNum] !== undefined) return this.metaCache[idxNum] as Js5IndexMeta | null;
        const rawMetaBlob = this.masterIndex.readGroup(idxNum);
        if (!rawMetaBlob) {
            this.metaCache[idxNum] = null;
            return null;
        }
        const decompressed = await Js5Compression.uncompress(rawMetaBlob);
        if (!decompressed) {
            this.metaCache[idxNum] = null;
            return null;
        }
        const meta = Js5IndexMeta.parse(decompressed);
        this.metaCache[idxNum] = meta;
        return meta;
    }

    /** Read & decompress a group's payload. */
    async getGroupBytes(idxNum: number, groupId: number): Promise<Uint8Array | null> {
        const key = `${idxNum}:${groupId}`;
        if (this.groupCache.has(key)) return this.groupCache.get(key)!;
        const idx = this.indexes[idxNum];
        if (!idx) {
            this.groupCache.set(key, null);
            return null;
        }
        const raw = idx.readGroup(groupId);
        if (!raw) {
            this.groupCache.set(key, null);
            return null;
        }
        const decompressed = await Js5Compression.uncompress(raw);
        this.groupCache.set(key, decompressed);
        return decompressed;
    }

    /** Read a single file out of a multi-file group. */
    async getFileBytes(idxNum: number, groupId: number, fileId: number): Promise<Uint8Array | null> {
        const group = await this.getGroupBytes(idxNum, groupId);
        if (!group) return null;
        const meta = await this.getMeta(idxNum);
        if (!meta) return null;
        const fileCount = meta.groupCapacities[groupId] || 1;
        if (fileCount <= 1) return group;
        const files = Js5Group.unpack(group, fileCount);
        // Map dense file slot → logical file id via meta.fileIds if sparse.
        const ids = meta.fileIds[groupId];
        if (ids) {
            for (let i = 0; i < ids.length; i++) {
                if (ids[i] === fileId) return files[i];
            }
            return null;
        }
        return files[fileId] || null;
    }

    /**
     * RT4/Js5 name hash used by JagString.getHash(). Names are looked up lower-case
     * by the reference client before hashing. This is different from the older 377
     * archive filename hash (`hash * 61 + c - 32`) still used by Archive.ts.
     */
    static nameHash(name: string): number {
        let hash = 0;
        const lower = name.toLowerCase();
        for (let i = 0; i < lower.length; i++) {
            hash = (lower.charCodeAt(i) + Math.imul(hash, 31)) | 0;
        }
        return hash;
    }

    async getGroupId(idxNum: number, groupName: string): Promise<number> {
        const meta = await this.getMeta(idxNum);
        if (!meta || !meta.groupNameHashes) return -1;
        const hash = Js5Cache.nameHash(groupName);
        for (let groupId = 0; groupId < meta.groupNameHashes.length; groupId++) {
            if (meta.groupNameHashes[groupId] === hash) return groupId;
        }
        return -1;
    }

    async getFileId(idxNum: number, groupId: number, fileName: string): Promise<number> {
        const meta = await this.getMeta(idxNum);
        if (!meta || !meta.fileNameHashes || !meta.fileNameHashes[groupId]) return -1;
        const hash = Js5Cache.nameHash(fileName);
        const hashes = meta.fileNameHashes[groupId]!;
        for (let fileId = 0; fileId < hashes.length; fileId++) {
            if (hashes[fileId] === hash) return fileId;
        }
        return -1;
    }

    async getNamedGroupBytes(idxNum: number, groupName: string): Promise<Uint8Array | null> {
        const groupId = await this.getGroupId(idxNum, groupName);
        return groupId >= 0 ? this.getGroupBytes(idxNum, groupId) : null;
    }

    async getNamedFileBytes(idxNum: number, groupName: string, fileName: string = ""): Promise<Uint8Array | null> {
        const groupId = await this.getGroupId(idxNum, groupName);
        if (groupId < 0) return null;
        if (!fileName) return this.getFileBytes(idxNum, groupId, 0);
        const fileId = await this.getFileId(idxNum, groupId, fileName);
        return fileId >= 0 ? this.getFileBytes(idxNum, groupId, fileId) : null;
    }

    capacityOf(idxNum: number): number {
        const idx = this.indexes[idxNum];
        return idx ? idx.capacity() : 0;
    }
}
