/**
 * RawModel530 — TypeScript port of rt4-client RawModel.java's byte decoder.
 *
 * Mirrors the rev-530 model byte format exactly. The constructor inspects
 * the last 2 bytes of `src`: if both are 0xFF the data uses the "new"
 * (post-textures-rework) layout, otherwise the "old" layout. Both paths
 * use seven independent buffer cursors over the same underlying byte
 * array, with header offsets pre-computed from sizes packed at the tail.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/RawModel.java
 *     - RawModel(byte[] src)        line 175  (dispatcher)
 *     - decodeNew(byte[] src)       line 919
 *     - decodeOld(byte[] src)       line 1605
 *     - RawModel.create(archive,id) line 456  (idx7, group=id, file=0)
 *
 * Models live in idx7. Each model id is a single-file group whose group
 * id equals the model id; file id is always 0 (per RawModel.create).
 *
 * This file does NOT cover rendering, mesh transforms, animation, or any
 * of the ~1500 lines after the two decoders in the deob — only the byte-
 * format → typed-arrays decode. A future renderer port consumes the
 * fields below directly.
 */

import { Js5Cache } from "../../Js5Cache";

// ── Inlined rt4 Buffer reader (Uint8Array-backed, multi-cursor) ──
// The decoder uses up to seven simultaneous cursors over the same underlying
// byte array, so we hold an array reference and let the caller stamp the
// cursor offset. Mirrors `Buffer.offset = N` / `Buffer.g*()` from rt4.
class ModelReader {
    public buf: Uint8Array;
    public pos: number;

    constructor(buf: Uint8Array, pos: number = 0) {
        this.buf = buf;
        this.pos = pos;
    }

    /** Unsigned 8-bit. rt4 Buffer.g1 */
    g1(): number {
        return this.buf[this.pos++] & 0xFF;
    }

    /** Signed 8-bit. rt4 Buffer.g1b */
    g1b(): number {
        const b = this.buf[this.pos++];
        return (b << 24) >> 24;
    }

    /** Unsigned big-endian 16-bit. rt4 Buffer.g2 */
    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }

    /**
     * rt4 Buffer.gsmart — variable-length signed-int read.
     *   peek byte; if < 128 read 1-byte unsigned and subtract 64
     *   else read 2-byte unsigned and subtract 0xC000
     * Used heavily for vertex deltas + triangle index deltas.
     */
    gsmart(): number {
        const peek = this.buf[this.pos] & 0xFF;
        if (peek < 128) {
            return this.g1() - 64;
        } else {
            return this.g2() - 0xC000;
        }
    }
}

/** Decoded rev-530 model. Field semantics mirror RawModel.java. */
export interface RawModel530Data {
    /** Model id this definition was loaded for. */
    id: number;

    /** Number of vertices. */
    vertexCount: number;
    /** Number of triangles. */
    triangleCount: number;
    /** Number of textured-face descriptors. */
    texturedCount: number;

    // ── Vertex positions (length = vertexCount) ──
    vertexX: number[];
    vertexY: number[];
    vertexZ: number[];

    /** Per-vertex bone id (length = vertexCount) when present, else null. */
    vertexBones: number[] | null;

    // ── Triangle indices into vertex arrays (length = triangleCount) ──
    triangleVertexA: number[];
    triangleVertexB: number[];
    triangleVertexC: number[];

    /** Per-triangle "info" byte (lighting / face-flags) when present, else null. */
    triangleInfo: number[] | null;
    /** Per-triangle render priority when priority opcode == 255, else null. */
    trianglePriorities: number[] | null;
    /** Per-triangle alpha (signed byte) when present, else null. */
    triangleAlpha: number[] | null;
    /** Per-triangle bone id when present, else null. */
    triangleBones: number[] | null;
    /** Per-triangle texture id (signed short) when present, else null. */
    triangleTextures: number[] | null;
    /** Per-triangle index into textureFaces arrays when present, else null. */
    triangleTextureIndex: number[] | null;
    /** Per-triangle base color (HSL16). length = triangleCount. */
    triangleColors: number[];

    /** Default render priority when triangle priorities aren't per-face. */
    priority: number;

    // ── Textured-face descriptors (length = texturedCount when texturedCount > 0) ──
    /** Texture type per face: 0 = simple PMN, 1-3 = complex variants, 2 = cube. */
    textureTypes: number[] | null;
    /** PMN ("p"/"primary") = vertex index of texture's origin. */
    textureFacesP: number[] | null;
    /** PMN "m" = U-axis vertex. */
    textureFacesM: number[] | null;
    /** PMN "n" = V-axis vertex. */
    textureFacesN: number[] | null;

    // ── Complex texture extras (length = complexTextureFaceCount) ──
    texturesScaleX: number[] | null;
    texturesScaleY: number[] | null;
    texturesScaleZ: number[] | null;
    textureRotationY: number[] | null;
    /** rt4 RawModel.aByteArray32 — complex texture payload. */
    textureExtraA: number[] | null;
    /** rt4 RawModel.aByteArray34 — complex texture payload. */
    textureExtraB: number[] | null;

    // ── Cube texture extras (length = cubeTextureFaceCount) ──
    /** rt4 RawModel.aByteArray28 — cube texture payload. */
    cubeExtraA: number[] | null;
    /** rt4 RawModel.aByteArray33 — cube texture payload. */
    cubeExtraB: number[] | null;
}

function blankModel(id: number): RawModel530Data {
    return {
        id,
        vertexCount: 0,
        triangleCount: 0,
        texturedCount: 0,
        vertexX: [],
        vertexY: [],
        vertexZ: [],
        vertexBones: null,
        triangleVertexA: [],
        triangleVertexB: [],
        triangleVertexC: [],
        triangleInfo: null,
        trianglePriorities: null,
        triangleAlpha: null,
        triangleBones: null,
        triangleTextures: null,
        triangleTextureIndex: null,
        triangleColors: [],
        priority: 0,
        textureTypes: null,
        textureFacesP: null,
        textureFacesM: null,
        textureFacesN: null,
        texturesScaleX: null,
        texturesScaleY: null,
        texturesScaleZ: null,
        textureRotationY: null,
        textureExtraA: null,
        textureExtraB: null,
        cubeExtraA: null,
        cubeExtraB: null,
    };
}

/**
 * Top-level dispatcher. Mirrors `RawModel(byte[] src)` line 175:
 *   if last two bytes are 0xFF/0xFF → decodeNew, else decodeOld.
 */
function decode(src: Uint8Array, id: number): RawModel530Data {
    const m = blankModel(id);
    if (src.byteLength < 2) return m;
    const tail0 = src[src.byteLength - 1] & 0xFF;
    const tail1 = src[src.byteLength - 2] & 0xFF;
    if (tail0 === 0xFF && tail1 === 0xFF) {
        decodeNew(src, m);
    } else {
        decodeOld(src, m);
    }
    return m;
}

/**
 * rt4 RawModel.decodeNew (lines 919-1294). Headers at src.length - 23,
 * seven cursors fanning out across the body.
 */
function decodeNew(src: Uint8Array, m: RawModel530Data): void {
    const buffer1 = new ModelReader(src);
    const buffer2 = new ModelReader(src);
    const buffer3 = new ModelReader(src);
    const buffer4 = new ModelReader(src);
    const buffer5 = new ModelReader(src);
    const buffer6 = new ModelReader(src);
    const buffer7 = new ModelReader(src);
    buffer1.pos = src.byteLength - 23;

    const vertexCount = buffer1.g2();
    const triangleCount = buffer1.g2();
    const texturedCount = buffer1.g1();

    const hasInfo = buffer1.g1();
    const hasTriangleInfo = (hasInfo & 0x1) === 1;
    const hasParticleEmitters = (hasInfo & 0x2) === 2; // not used in 530

    const priority = buffer1.g1();
    const hasAlpha = buffer1.g1();
    const hasTriangleBones = buffer1.g1();
    const hasTextures = buffer1.g1();
    const hasVertexBones = buffer1.g1();

    const dxDataLength = buffer1.g2();
    const dyDataLength = buffer1.g2();
    const dzDataLength = buffer1.g2();
    const vertexIndexDataLength = buffer1.g2();
    const triangleTextureDataLength = buffer1.g2();

    let simpleTextureFaceCount = 0;
    let complexTextureFaceCount = 0;
    let cubeTextureFaceCount = 0;

    let textureTypes: number[] | null = null;
    if (texturedCount > 0) {
        textureTypes = newSignedByteArray(texturedCount);
        buffer1.pos = 0;
        for (let i = 0; i < texturedCount; i++) {
            const type = buffer1.g1b();
            textureTypes[i] = type;
            if (type === 0) simpleTextureFaceCount++;
            else if (type >= 1 && type <= 3) complexTextureFaceCount++;
            if (type === 2) cubeTextureFaceCount++;
        }
    }

    let offset = texturedCount + vertexCount;

    const triangleInfoDataOffset = offset;
    if (hasTriangleInfo) offset += triangleCount;

    const triangleTypeDataOffset = offset;
    offset += triangleCount;

    const trianglePriorityDataOffset = offset;
    if (priority === 255) offset += triangleCount;

    const triangleBonesDataOffset = offset;
    if (hasTriangleBones === 1) offset += triangleCount;

    const vertexBonesDataOffset = offset;
    if (hasVertexBones === 1) offset += vertexCount;

    const triangleAlphaDataOffset = offset;
    if (hasAlpha === 1) offset += triangleCount;

    const vertexIndexDataOffset = offset;
    offset += vertexIndexDataLength;

    const triangleTexturesDataOffset = offset;
    if (hasTextures === 1) offset += triangleCount * 2;

    const triangleTextureIndexDataOffset = offset;
    offset += triangleTextureDataLength;

    const triangleColorDataOffset = offset;
    offset += triangleCount * 2;

    const dxDataOffset = offset;
    offset += dxDataLength;

    const dyDataOffset = offset;
    offset += dyDataLength;

    const dzDataOffset = offset;
    offset += dzDataLength;

    const simplePmnDataOffset = offset;
    offset += simpleTextureFaceCount * 6;

    const complexPmnDataOffset = offset;
    offset += complexTextureFaceCount * 6;

    const complexScaleDataOffset = offset;
    offset += complexTextureFaceCount * 6;

    const complexRotationDataOffset = offset;
    offset += complexTextureFaceCount;

    const cube1DataOffset = offset;
    offset += complexTextureFaceCount;

    const cube2DataOffset = offset;
    offset += complexTextureFaceCount + cubeTextureFaceCount * 2;

    m.vertexCount = vertexCount;
    m.triangleCount = triangleCount;
    m.texturedCount = texturedCount;

    m.vertexX = newIntArray(vertexCount);
    m.vertexY = newIntArray(vertexCount);
    m.vertexZ = newIntArray(vertexCount);

    m.triangleVertexA = newIntArray(triangleCount);
    m.triangleVertexB = newIntArray(triangleCount);
    m.triangleVertexC = newIntArray(triangleCount);

    if (hasVertexBones === 1) m.vertexBones = newIntArray(vertexCount);
    if (hasTriangleInfo) m.triangleInfo = newSignedByteArray(triangleCount);

    if (priority === 255) {
        m.trianglePriorities = newSignedByteArray(triangleCount);
    } else {
        m.priority = priority;
    }

    if (hasAlpha === 1) m.triangleAlpha = newSignedByteArray(triangleCount);
    if (hasTriangleBones === 1) m.triangleBones = newIntArray(triangleCount);
    if (hasTextures === 1) m.triangleTextures = newSignedShortArray(triangleCount);
    if (hasTextures === 1 && texturedCount > 0) {
        m.triangleTextureIndex = newSignedByteArray(triangleCount);
    }

    m.triangleColors = newSignedShortArray(triangleCount);

    if (texturedCount > 0) {
        m.textureTypes = textureTypes;
        m.textureFacesP = newSignedShortArray(texturedCount);
        m.textureFacesM = newSignedShortArray(texturedCount);
        m.textureFacesN = newSignedShortArray(texturedCount);

        if (complexTextureFaceCount > 0) {
            m.texturesScaleX = newSignedShortArray(complexTextureFaceCount);
            m.texturesScaleY = newSignedShortArray(complexTextureFaceCount);
            m.texturesScaleZ = newSignedShortArray(complexTextureFaceCount);
            m.textureRotationY = newSignedByteArray(complexTextureFaceCount);
            m.textureExtraA = newSignedByteArray(complexTextureFaceCount);
            m.textureExtraB = newSignedByteArray(complexTextureFaceCount);
        }

        if (cubeTextureFaceCount > 0) {
            m.cubeExtraA = newSignedByteArray(cubeTextureFaceCount);
            m.cubeExtraB = newSignedByteArray(cubeTextureFaceCount);
        }
    }

    // Vertex pass.
    buffer1.pos = texturedCount;
    buffer2.pos = dxDataOffset;
    buffer3.pos = dyDataOffset;
    buffer4.pos = dzDataOffset;
    buffer5.pos = vertexBonesDataOffset;

    let prevVertexX = 0;
    let prevVertexY = 0;
    let prevVertexZ = 0;

    for (let v = 0; v < vertexCount; v++) {
        const flags = buffer1.g1();

        let dx = 0;
        if ((flags & 0x1) !== 0) dx = buffer2.gsmart();

        let dy = 0;
        if ((flags & 0x2) !== 0) dy = buffer3.gsmart();

        let dz = 0;
        if ((flags & 0x4) !== 0) dz = buffer4.gsmart();

        m.vertexX[v] = prevVertexX + dx;
        m.vertexY[v] = prevVertexY + dy;
        m.vertexZ[v] = prevVertexZ + dz;

        prevVertexX = m.vertexX[v];
        prevVertexY = m.vertexY[v];
        prevVertexZ = m.vertexZ[v];

        if (hasVertexBones === 1 && m.vertexBones) {
            m.vertexBones[v] = buffer5.g1();
        }
    }

    // Triangle metadata pass.
    buffer1.pos = triangleColorDataOffset;
    buffer2.pos = triangleInfoDataOffset;
    buffer3.pos = trianglePriorityDataOffset;
    buffer4.pos = triangleAlphaDataOffset;
    buffer5.pos = triangleBonesDataOffset;
    buffer6.pos = triangleTexturesDataOffset;
    buffer7.pos = triangleTextureIndexDataOffset;

    for (let t = 0; t < triangleCount; t++) {
        m.triangleColors[t] = signedShort(buffer1.g2());

        if (hasTriangleInfo && m.triangleInfo) m.triangleInfo[t] = buffer2.g1b();
        if (priority === 255 && m.trianglePriorities) m.trianglePriorities[t] = buffer3.g1b();
        if (hasAlpha === 1 && m.triangleAlpha) m.triangleAlpha[t] = buffer4.g1b();
        if (hasTriangleBones === 1 && m.triangleBones) m.triangleBones[t] = buffer5.g1();
        if (hasTextures === 1 && m.triangleTextures) {
            m.triangleTextures[t] = signedShort(buffer6.g2() - 1);
        }

        if (m.triangleTextureIndex) {
            if (m.triangleTextures && m.triangleTextures[t] === -1) {
                m.triangleTextureIndex[t] = -1;
            } else {
                m.triangleTextureIndex[t] = buffer7.g1() - 1;
            }
        }
    }

    // Triangle indices pass.
    buffer1.pos = vertexIndexDataOffset;
    buffer2.pos = triangleTypeDataOffset;

    let a = 0;
    let b = 0;
    let c = 0;
    let last = 0;

    for (let t = 0; t < triangleCount; t++) {
        const type = buffer2.g1();
        if (type === 1) {
            a = buffer1.gsmart() + last;
            b = buffer1.gsmart() + a;
            c = buffer1.gsmart() + b;
            last = c;
            m.triangleVertexA[t] = a;
            m.triangleVertexB[t] = b;
            m.triangleVertexC[t] = c;
        } else if (type === 2) {
            b = c;
            c = buffer1.gsmart() + last;
            last = c;
            m.triangleVertexA[t] = a;
            m.triangleVertexB[t] = b;
            m.triangleVertexC[t] = c;
        } else if (type === 3) {
            a = c;
            c = buffer1.gsmart() + last;
            last = c;
            m.triangleVertexA[t] = a;
            m.triangleVertexB[t] = b;
            m.triangleVertexC[t] = c;
        } else if (type === 4) {
            const b0 = a;
            a = b;
            b = b0;
            c = buffer1.gsmart() + last;
            last = c;
            m.triangleVertexA[t] = a;
            m.triangleVertexB[t] = b0;
            m.triangleVertexC[t] = c;
        }
    }

    // Textured-face pass.
    buffer1.pos = simplePmnDataOffset;
    buffer2.pos = complexPmnDataOffset;
    buffer3.pos = complexScaleDataOffset;
    buffer4.pos = complexRotationDataOffset;
    buffer5.pos = cube1DataOffset;
    buffer6.pos = cube2DataOffset;

    for (let t = 0; t < texturedCount; t++) {
        const type = (m.textureTypes ? m.textureTypes[t] : 0) & 0xFF;
        if (type === 0) {
            if (m.textureFacesP) m.textureFacesP[t] = signedShort(buffer1.g2());
            if (m.textureFacesM) m.textureFacesM[t] = signedShort(buffer1.g2());
            if (m.textureFacesN) m.textureFacesN[t] = signedShort(buffer1.g2());
        } else if (type === 1) {
            if (m.textureFacesP) m.textureFacesP[t] = signedShort(buffer2.g2());
            if (m.textureFacesM) m.textureFacesM[t] = signedShort(buffer2.g2());
            if (m.textureFacesN) m.textureFacesN[t] = signedShort(buffer2.g2());
            if (m.texturesScaleX) m.texturesScaleX[t] = signedShort(buffer3.g2());
            if (m.texturesScaleY) m.texturesScaleY[t] = signedShort(buffer3.g2());
            if (m.texturesScaleZ) m.texturesScaleZ[t] = signedShort(buffer3.g2());
            if (m.textureRotationY) m.textureRotationY[t] = buffer4.g1b();
            if (m.textureExtraA) m.textureExtraA[t] = buffer5.g1b();
            if (m.textureExtraB) m.textureExtraB[t] = buffer6.g1b();
        } else if (type === 2) {
            if (m.textureFacesP) m.textureFacesP[t] = signedShort(buffer2.g2());
            if (m.textureFacesM) m.textureFacesM[t] = signedShort(buffer2.g2());
            if (m.textureFacesN) m.textureFacesN[t] = signedShort(buffer2.g2());
            if (m.texturesScaleX) m.texturesScaleX[t] = signedShort(buffer3.g2());
            if (m.texturesScaleY) m.texturesScaleY[t] = signedShort(buffer3.g2());
            if (m.texturesScaleZ) m.texturesScaleZ[t] = signedShort(buffer3.g2());
            if (m.textureRotationY) m.textureRotationY[t] = buffer4.g1b();
            if (m.textureExtraA) m.textureExtraA[t] = buffer5.g1b();
            if (m.textureExtraB) m.textureExtraB[t] = buffer6.g1b();
            if (m.cubeExtraA) m.cubeExtraA[t] = buffer6.g1b();
            if (m.cubeExtraB) m.cubeExtraB[t] = buffer6.g1b();
        } else if (type === 3) {
            if (m.textureFacesP) m.textureFacesP[t] = signedShort(buffer2.g2());
            if (m.textureFacesM) m.textureFacesM[t] = signedShort(buffer2.g2());
            if (m.textureFacesN) m.textureFacesN[t] = signedShort(buffer2.g2());
            if (m.texturesScaleX) m.texturesScaleX[t] = signedShort(buffer3.g2());
            if (m.texturesScaleY) m.texturesScaleY[t] = signedShort(buffer3.g2());
            if (m.texturesScaleZ) m.texturesScaleZ[t] = signedShort(buffer3.g2());
            if (m.textureRotationY) m.textureRotationY[t] = buffer4.g1b();
            if (m.textureExtraA) m.textureExtraA[t] = buffer5.g1b();
            if (m.textureExtraB) m.textureExtraB[t] = buffer6.g1b();
        }
    }

    if (hasParticleEmitters) {
        buffer1.pos = offset;
        const particleEmittersLen = buffer1.g1();
        if (particleEmittersLen > 0) buffer1.pos += particleEmittersLen * 4;
        const particleEffectorsLen = buffer1.g1();
        if (particleEffectorsLen > 0) buffer1.pos += particleEffectorsLen * 4;
    }
}

/**
 * rt4 RawModel.decodeOld (lines 1605-1887). Older model layout — header
 * at src.length - 18 (5 bytes shorter than decodeNew), no separate
 * texture-type table, simpler textured-face encoding (PMN only).
 */
function decodeOld(src: Uint8Array, m: RawModel530Data): void {
    let hasFaceTextures = false;
    let hasTriangleInfoFlag = false;
    let hasTexturesFlag = false;

    const buffer1 = new ModelReader(src);
    const buffer2 = new ModelReader(src);
    const buffer3 = new ModelReader(src);
    const buffer4 = new ModelReader(src);
    const buffer5 = new ModelReader(src);
    buffer1.pos = src.byteLength - 18;

    const vertexCount = buffer1.g2();
    const triangleCount = buffer1.g2();
    const texturedCount = buffer1.g1();

    const hasInfo = buffer1.g1();
    const hasPriorities = buffer1.g1();
    const hasAlpha = buffer1.g1();
    const hasTriangleBones = buffer1.g1();
    const hasVertexBones = buffer1.g1();

    const dxDataLength = buffer1.g2();
    const dyDataLength = buffer1.g2();
    const dzDataLength = buffer1.g2();
    const vertexIndexDataLength = buffer1.g2();

    let offset = vertexCount;

    const triangleTypeDataOffset = offset;
    offset += triangleCount;

    const trianglePriorityDataOffset = offset;
    if (hasPriorities === 255) offset += triangleCount;

    const triangleBonesDataOffset = offset;
    if (hasTriangleBones === 1) offset += triangleCount;

    const triangleInfoDataOffset = offset;
    if (hasInfo === 1) offset += triangleCount;

    const vertexBonesOffset = offset;
    if (hasVertexBones === 1) offset += vertexCount;

    const triangleAlphaDataOffset = offset;
    if (hasAlpha === 1) offset += triangleCount;

    const vertexIndexDataOffset = offset;
    offset += vertexIndexDataLength;

    const triangleColorDataOffset = offset;
    offset += triangleCount * 2;

    const pmnDataOffset = offset;
    offset += texturedCount * 6;

    const dxDataOffset = offset;
    offset += dxDataLength;

    const dyDataOffset = offset;
    offset += dyDataLength;

    const dzDataOffset = offset;
    // dzDataLength is the implied tail; the deob does not advance offset
    // here so we don't either.

    m.vertexCount = vertexCount;
    m.triangleCount = triangleCount;
    m.texturedCount = texturedCount;

    m.vertexX = newIntArray(vertexCount);
    m.vertexY = newIntArray(vertexCount);
    m.vertexZ = newIntArray(vertexCount);

    m.triangleVertexA = newIntArray(triangleCount);
    m.triangleVertexB = newIntArray(triangleCount);
    m.triangleVertexC = newIntArray(triangleCount);

    if (texturedCount > 0) {
        m.textureTypes = newSignedByteArray(texturedCount);
        m.textureFacesP = newSignedShortArray(texturedCount);
        m.textureFacesM = newSignedShortArray(texturedCount);
        m.textureFacesN = newSignedShortArray(texturedCount);
    }

    if (hasVertexBones === 1) m.vertexBones = newIntArray(vertexCount);

    if (hasInfo === 1) {
        m.triangleInfo = newSignedByteArray(triangleCount);
        m.triangleTextureIndex = newSignedByteArray(triangleCount);
        m.triangleTextures = newSignedShortArray(triangleCount);
    }

    if (hasPriorities === 255) {
        m.trianglePriorities = newSignedByteArray(triangleCount);
    } else {
        m.priority = hasPriorities;
    }

    if (hasAlpha === 1) m.triangleAlpha = newSignedByteArray(triangleCount);
    if (hasTriangleBones === 1) m.triangleBones = newIntArray(triangleCount);

    m.triangleColors = newSignedShortArray(triangleCount);

    // Vertex pass.
    buffer1.pos = 0;
    buffer2.pos = dxDataOffset;
    buffer3.pos = dyDataOffset;
    buffer4.pos = dzDataOffset;
    buffer5.pos = vertexBonesOffset;

    let prevVertexX = 0;
    let prevVertexY = 0;
    let prevVertexZ = 0;

    for (let v = 0; v < vertexCount; v++) {
        const flags = buffer1.g1();

        let dx = 0;
        if ((flags & 0x1) !== 0) dx = buffer2.gsmart();

        let dy = 0;
        if ((flags & 0x2) !== 0) dy = buffer3.gsmart();

        let dz = 0;
        if ((flags & 0x4) !== 0) dz = buffer4.gsmart();

        m.vertexX[v] = prevVertexX + dx;
        m.vertexY[v] = prevVertexY + dy;
        m.vertexZ[v] = prevVertexZ + dz;

        prevVertexX = m.vertexX[v];
        prevVertexY = m.vertexY[v];
        prevVertexZ = m.vertexZ[v];

        if (hasVertexBones === 1 && m.vertexBones) m.vertexBones[v] = buffer5.g1();
    }

    // Triangle metadata pass.
    buffer1.pos = triangleColorDataOffset;
    buffer2.pos = triangleInfoDataOffset;
    buffer3.pos = trianglePriorityDataOffset;
    buffer4.pos = triangleAlphaDataOffset;
    buffer5.pos = triangleBonesDataOffset;

    for (let t = 0; t < triangleCount; t++) {
        m.triangleColors[t] = signedShort(buffer1.g2());

        if (hasInfo === 1 && m.triangleInfo && m.triangleTextureIndex && m.triangleTextures) {
            const flags = buffer2.g1();
            if ((flags & 0x1) === 1) {
                m.triangleInfo[t] = 1;
                hasTriangleInfoFlag = true;
            } else {
                m.triangleInfo[t] = 0;
            }
            if ((flags & 0x2) === 2) {
                m.triangleTextureIndex[t] = flags >> 2;
                m.triangleTextures[t] = m.triangleColors[t];
                m.triangleColors[t] = 127;
                if (m.triangleTextures[t] !== -1) hasTexturesFlag = true;
            } else {
                m.triangleTextureIndex[t] = -1;
                m.triangleTextures[t] = -1;
            }
        }

        if (hasPriorities === 255 && m.trianglePriorities) m.trianglePriorities[t] = buffer3.g1b();
        if (hasAlpha === 1 && m.triangleAlpha) m.triangleAlpha[t] = buffer4.g1b();
        if (hasTriangleBones === 1 && m.triangleBones) m.triangleBones[t] = buffer5.g1();
    }

    // Triangle indices pass.
    buffer1.pos = vertexIndexDataOffset;
    buffer2.pos = triangleTypeDataOffset;

    let a = 0;
    let b = 0;
    let c = 0;
    let last = 0;

    for (let t = 0; t < triangleCount; t++) {
        const type = buffer2.g1();
        if (type === 1) {
            a = buffer1.gsmart() + last;
            b = buffer1.gsmart() + a;
            c = buffer1.gsmart() + b;
            last = c;
            m.triangleVertexA[t] = a;
            m.triangleVertexB[t] = b;
            m.triangleVertexC[t] = c;
        } else if (type === 2) {
            b = c;
            c = buffer1.gsmart() + last;
            last = c;
            m.triangleVertexA[t] = a;
            m.triangleVertexB[t] = b;
            m.triangleVertexC[t] = c;
        } else if (type === 3) {
            a = c;
            c = buffer1.gsmart() + last;
            last = c;
            m.triangleVertexA[t] = a;
            m.triangleVertexB[t] = b;
            m.triangleVertexC[t] = c;
        } else if (type === 4) {
            const b0 = a;
            a = b;
            b = b0;
            c = buffer1.gsmart() + last;
            last = c;
            m.triangleVertexA[t] = a;
            m.triangleVertexB[t] = b0;
            m.triangleVertexC[t] = c;
        }
    }

    // Textured-face pass — old layout has only the simple "PMN" form.
    buffer1.pos = pmnDataOffset;
    for (let t = 0; t < texturedCount; t++) {
        if (m.textureTypes) m.textureTypes[t] = 0;
        if (m.textureFacesP) m.textureFacesP[t] = signedShort(buffer1.g2());
        if (m.textureFacesM) m.textureFacesM[t] = signedShort(buffer1.g2());
        if (m.textureFacesN) m.textureFacesN[t] = signedShort(buffer1.g2());
    }

    // Per-triangle texture-index post-pass: drop indexes that match the
    // owning face's PMN exactly (no override needed).
    if (m.triangleTextureIndex && m.textureFacesP && m.textureFacesM && m.textureFacesN) {
        for (let i = 0; i < triangleCount; i++) {
            const index = m.triangleTextureIndex[i] & 0xFF;
            if (index !== 255) {
                if (
                    (m.textureFacesP[index] & 0xFFFF) === m.triangleVertexA[i] &&
                    (m.textureFacesM[index] & 0xFFFF) === m.triangleVertexB[i] &&
                    (m.textureFacesN[index] & 0xFFFF) === m.triangleVertexC[i]
                ) {
                    m.triangleTextureIndex[i] = -1;
                } else {
                    hasFaceTextures = true;
                }
            }
        }
        if (!hasFaceTextures) m.triangleTextureIndex = null;
    }

    if (!hasTexturesFlag) m.triangleTextures = null;
    if (!hasTriangleInfoFlag) m.triangleInfo = null;
}

// ── Helpers ──

function newIntArray(n: number): number[] {
    const a: number[] = [];
    for (let i = 0; i < n; i++) a.push(0);
    return a;
}

function newSignedByteArray(n: number): number[] {
    const a: number[] = [];
    for (let i = 0; i < n; i++) a.push(0);
    return a;
}

function newSignedShortArray(n: number): number[] {
    const a: number[] = [];
    for (let i = 0; i < n; i++) a.push(0);
    return a;
}

/** Sign-extend a 16-bit value to the JS number range (−32768..32767). */
function signedShort(v: number): number {
    v &= 0xFFFF;
    return v >= 0x8000 ? v - 0x10000 : v;
}

/**
 * High-level loader. Mirrors RawModel.create(archive, id) at
 * RawModel.java:456 — fetch the model bytes from idx7 (group=id, file=0)
 * and run the byte decoder.
 */
export class RawModel530 {
    /** rt4 idx number for models. */
    public static readonly INDEX = 7;

    static decode(data: Uint8Array, id: number): RawModel530Data {
        return decode(data, id);
    }

    static async load(js5Cache: Js5Cache, id: number): Promise<RawModel530Data | null> {
        if (id < 0) return null;
        const data = await js5Cache.getFileBytes(RawModel530.INDEX, id, 0);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
