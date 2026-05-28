// Port of Client_Base/src/orsc/graphics/three/RSModel.java
// All fixed-point arithmetic uses Int32 to match Java `int` semantics.
// Overflow operators (&+, &-, &*) are used where Java silently wraps.

import Foundation

final class RSModel {

    // MARK: - Sentinel
    private let m_Vb: Int32 = 12345678

    // MARK: - Face arrays
    var faceDiffuseLight: [Int32] = []
    var faceHead: Int32 = 0
    var faceIndexCount: [Int32] = []
    var faceIndices: [[Int32]] = []
    var facePickIndex: [Int32] = []
    var faceTextureBack: [Int32] = []
    var faceTextureFront: [Int32] = []

    // MARK: - Vertex arrays
    var vertDiffuseLight: [Int32] = []
    var vertexParam2: [Int32] = []
    var vertexParam6: [Int32] = []
    var vertLightOther: [Int8] = []
    var vertHead: Int32 = 0
    var vertX: [Int32] = []
    var vertXRot: [Int32] = []
    var vertY: [Int32] = []
    var vertYRot: [Int32] = []
    var vertZ: [Int32] = []
    var vertZRot: [Int32] = []

    // MARK: - World-space transform arrays
    var vertXTransform: [Int32] = []
    var vertYTransform: [Int32] = []
    var vertZTransform: [Int32] = []

    // MARK: - Transform state
    var rot256X: Int32 = 0
    var rot256Y: Int32 = 0
    var rot256Z: Int32 = 0
    var translateX: Int32 = 0
    var translateY: Int32 = 0
    var translateZ: Int32 = 0
    var scaleX: Int32 = 256
    var scaleY: Int32 = 256
    var scaleZ: Int32 = 256
    var appliedTransform: Int32 = 0

    // MARK: - Bounding box
    var minX: Int32 = 0
    var maxX: Int32 = 0
    var minY: Int32 = 0
    var maxY: Int32 = 0
    var minZ: Int32 = 0
    var maxZ: Int32 = 0

    // MARK: - Scene / rendering
    var key: Int = 0
    var vertCount: Int32 = 0
    var faceCount: Int32 = 0
    var visible: Bool = false
    /// Terrain is drawn as the floor and should not hide character billboards.
    /// Object and boundary models keep the default `true`, letting Scene build
    /// a coarse depth mask before billboard layers are composited.
    var occludesBillboards: Bool = true
    /// Placed scenery is already culled by tile footprint in RSCGameEngine.
    /// Let those models bypass the broad model-bounds frustum reject and rely
    /// on per-face screen culling; otherwise many real object models are
    /// skipped before their visible faces can be considered.
    var bypassFrustumBoundsCull: Bool = false

    // MARK: - Internal flags (matching Java obfuscated names)
    var m_cb: Bool = false
    var m_dc: Bool = true
    var m_hc: Int32 = 0
    private var m_Kb: Bool = false
    var m_Yb: Int32 = 1
    private var m_zb: [Int8] = []
    private var m_b: Bool = false
    private var m_c: Bool = false
    private var m_db: Bool = false
    private var m_v: Bool = false
    private var dontComputeDiffuse: Bool = false

    // MARK: - Rotation matrix elements (256-scale)
    private var rotM_xToY: Int32 = 256
    private var rotM_xToZ: Int32 = 256
    private var rotM_yToX: Int32 = 256
    private var rotM_yToZ: Int32 = 256
    private var rotM_zToX: Int32 = 256
    private var rotM_zToY: Int32 = 256

    // MARK: - Diffuse lighting params
    private var diffuseParam1: Int32 = 32
    private var diffuseParam2: Int32 = 512
    private var diffuseDirX: Int32 = 180
    private var diffuseDirY: Int32 = 155
    private var diffuseDirZ: Int32 = 95
    private var diffuseMag: Int32 = 256

    // MARK: - Per-face bounding and normal data
    private var faceMaxX: [Int32] = []
    private var faceMaxY: [Int32] = []
    private var faceMaxZ: [Int32] = []
    private var faceMinX: [Int32] = []
    private var faceMinY: [Int32] = []
    private var faceMinZ: [Int32] = []
    private var faceNormX: [Int32] = []
    private var faceNormY: [Int32] = []
    private var faceNormZ: [Int32] = []
    private var faceParam1: [[Int32]] = []
    private var scenePolyNormalShift: [Int32] = []
    private var scenePolyNormalMagnitude: [Int32] = []

    // MARK: - Misc internal state
    private var maxFaceDimension: Int32 = 12345678
    var vertexCount2: Int32 = 0
    private var m_hb: Int32 = 0

    // =========================================================================
    // MARK: - Initialisers
    // =========================================================================

    /// Default init for programmatic geometry building.
    init() {}

    /// Binary .ob3 parser. Reads vertCount + faceCount, then vertex XYZ arrays,
    /// face metadata, and face index lists.
    init(data: Data, offset startOffset: Int) {
        var offset = startOffset

        func readU16() -> Int32 {
            let hi = Int32(data[offset]) << 8
            let lo = Int32(data[offset + 1])
            offset += 2
            return hi | lo
        }

        func readS16() -> Int32 {
            var v = Int32(data[offset]) << 8 | Int32(data[offset + 1])
            offset += 2
            // sign-extend from 16 bits
            if v >= 0x8000 { v -= 0x10000 }
            return v
        }

        func readByte() -> Int32 {
            let v = Int32(data[offset]) & 0xFF
            offset += 1
            return v
        }

        let vertexCount = readU16()
        let fc = readU16()

        setFaceVertexCount(faceCount: fc, vertexCount: vertexCount)
        faceParam1 = [[Int32]](repeating: [Int32](repeating: 0, count: 1), count: Int(fc))

        // Vertex X
        for j in 0 ..< Int(vertexCount) {
            vertX[j] = readS16()
        }
        // Vertex Y
        for j in 0 ..< Int(vertexCount) {
            vertY[j] = readS16()
        }
        // Vertex Z
        for j in 0 ..< Int(vertexCount) {
            vertZ[j] = readS16()
        }

        vertHead = vertexCount

        // Face index counts
        for j in 0 ..< Int(fc) {
            faceIndexCount[j] = readByte()
        }

        // Face texture front
        for j in 0 ..< Int(fc) {
            var v = readS16()
            if v == 32767 { v = m_Vb }
            faceTextureFront[j] = v
        }

        // Face texture back
        for j in 0 ..< Int(fc) {
            var v = readS16()
            if v == 32767 { v = m_Vb }
            faceTextureBack[j] = v
        }

        // Face diffuse light flags
        for j in 0 ..< Int(fc) {
            let b = readByte()
            faceDiffuseLight[j] = (b != 0) ? m_Vb : 0
        }

        // Face vertex indices
        for j in 0 ..< Int(fc) {
            let cnt = Int(faceIndexCount[j])
            var indices = [Int32](repeating: 0, count: cnt)
            for i in 0 ..< cnt {
                if vertexCount < 256 {
                    indices[i] = readByte()
                } else {
                    indices[i] = readU16()
                }
            }
            faceIndices[j] = indices
        }

        faceHead = fc
        m_Yb = 1
    }

    /// Geometry-builder init with explicit vertex/face limits.
    init(vertexCount: Int32, faceCount: Int32) {
        setFaceVertexCount(faceCount: faceCount, vertexCount: vertexCount)
        faceParam1 = [[Int32]](repeating: [Int32](repeating: 0, count: 1), count: Int(faceCount))
        for face in 0 ..< Int(faceCount) {
            faceParam1[face][0] = Int32(face)
        }
    }

    /// Full-flags init used internally.
    init(vertexLimit: Int32, faceLimit: Int32, useTransformAsVert: Bool, useMinC: Bool,
         noDiffuse: Bool, useMinDB: Bool, useMinB: Bool) {
        m_c = useMinC
        m_b = useMinB
        m_db = useMinDB
        m_v = useTransformAsVert
        dontComputeDiffuse = noDiffuse
        setFaceVertexCount(faceCount: faceLimit, vertexCount: vertexLimit)
    }

    // =========================================================================
    // MARK: - Public API
    // =========================================================================

    /// Adds incremental rotations (0–255 space).
    final func addRotation(_ rotX: Int32, _ rotY: Int32, _ rotZ: Int32) {
        rot256X = (rotX + rot256X) & 255
        rot256Y = (rotY + rot256Y) & 255
        rot256Z = 255 & (rot256Z + rotZ)
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Accumulates translation deltas.
    final func translate2(_ tX: Int32, _ tY: Int32, _ tZ: Int32) {
        translateY += tY
        translateZ += tZ
        translateX += tX
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Sets absolute rotation (0–255 space).
    final func setRot256(_ rotX: Int32, _ rotY: Int32, _ rotZ: Int32) {
        rot256X = rotX & 255
        rot256Y = rotY & 255
        rot256Z = rotZ & 255
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Sets absolute translation.
    final func setTranslate(_ tX: Int32, _ tY: Int32, _ tZ: Int32) {
        translateY = tY
        translateX = tX
        translateZ = tZ
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Copies rotation and translation state from another model.
    final func copyRot256AndTranslateFrom(_ model: RSModel, _ var2: Int32) {
        if var2 != 6029 {
            appliedTransform = -128
        }
        translateX = model.translateX
        translateY = model.translateY
        translateZ = model.translateZ
        rot256X = model.rot256X
        rot256Y = model.rot256Y
        rot256Z = model.rot256Z
        computeAppliedTransform()
        m_Yb = 1
    }

    // MARK: - Geometry builders

    /// Inserts or deduplicates a vertex; returns its index.
    final func insertVertex(x: Int32, y: Int32, z: Int32) -> Int32 {
        for i in 0 ..< Int(vertHead) {
            if x == vertX[i] && y == vertY[i] && z == vertZ[i] {
                return Int32(i)
            }
        }
        if vertHead < vertexCount2 {
            let idx = vertHead
            vertX[Int(idx)] = x
            vertY[Int(idx)] = y
            vertZ[Int(idx)] = z
            vertHead += 1
            return idx
        }
        return -1
    }

    /// Appends a face and returns its index.
    @discardableResult
    final func insertFace(count: Int32, indices: [Int32], texFront: Int32, texBack: Int32) -> Int32 {
        if faceCount > faceHead {
            let idx = faceHead
            faceIndexCount[Int(idx)] = count
            faceIndices[Int(idx)] = indices
            faceTextureFront[Int(idx)] = texFront
            faceTextureBack[Int(idx)] = texBack
            m_Yb = 1
            faceHead += 1
            return idx
        }
        return -1
    }

    /// Sets per-vertex `vertLightOther`.
    final func setVertexLightOther(_ id: Int32, _ val: Int32) {
        vertLightOther[Int(id)] = Int8(truncatingIfNeeded: val)
    }

    // MARK: - Lighting

    /// Combined diffuse light + face-colour setter called from PacketHandler.
    final func setDiffuseLightAndColor(_ dirX: Int32, _ dirY: Int32, _ dirZ: Int32,
                                       _ p1: Int32, _ p2: Int32, _ var5: Bool, _ var7: Int32) {
        diffuseParam2 = (64 - p2) &* 16 &+ 128
        diffuseParam1 = 256 &- p1 &* 4

        if !dontComputeDiffuse {
            for i in 0 ..< Int(faceHead) {
                faceDiffuseLight[i] = var5 ? m_Vb : 0
            }
            diffuseDirX = dirX
            diffuseDirZ = dirZ
            diffuseDirY = dirY
            diffuseMag = Int32(Foundation.sqrt(Double(dirY &* dirY &+ dirX &* dirX &+ dirZ &* dirZ)))
            computeDiffuse(-121)
        }
    }

    /// Diffuse light setter (ambient + directional).
    final func setDiffuseLight(ambientParam1 var1: Int32, ambientParam2 var2: Int32,
                               dirX diffuseDirX_: Int32, dirY diffuseDirY_: Int32, dirZ diffuseDirZ_: Int32) {
        diffuseParam1 = 256 &- var2 &* 4
        diffuseParam2 = (64 &- var1) &* 16 &+ 128

        if !dontComputeDiffuse {
            diffuseDirX = diffuseDirX_
            diffuseDirZ = diffuseDirZ_
            diffuseDirY = diffuseDirY_
            diffuseMag = Int32(Foundation.sqrt(
                Double(diffuseDirZ_ &* diffuseDirZ_ &+ diffuseDirY_ &* diffuseDirY_ &+ diffuseDirX_ &* diffuseDirX_)))
            computeDiffuse(-102)
        }
    }

    // MARK: - Deep copy

    /// Returns a deep copy of this model (used extensively by World).
    final func clone() -> RSModel {
        let copy = RSModel()
        copy.m_cb = m_cb
        copy.m_hc = m_hc

        // Copy flags
        copy.m_c = m_c
        copy.m_b = m_b
        copy.m_db = m_db
        copy.m_v = m_v
        copy.dontComputeDiffuse = dontComputeDiffuse

        // Scalar state
        copy.diffuseParam1 = diffuseParam1
        copy.diffuseParam2 = diffuseParam2
        copy.diffuseDirX = diffuseDirX
        copy.diffuseDirY = diffuseDirY
        copy.diffuseDirZ = diffuseDirZ
        copy.diffuseMag = diffuseMag
        copy.rot256X = rot256X
        copy.rot256Y = rot256Y
        copy.rot256Z = rot256Z
        copy.translateX = translateX
        copy.translateY = translateY
        copy.translateZ = translateZ
        copy.scaleX = scaleX
        copy.scaleY = scaleY
        copy.scaleZ = scaleZ
        copy.appliedTransform = appliedTransform
        copy.rotM_xToY = rotM_xToY
        copy.rotM_xToZ = rotM_xToZ
        copy.rotM_yToX = rotM_yToX
        copy.rotM_yToZ = rotM_yToZ
        copy.rotM_zToX = rotM_zToX
        copy.rotM_zToY = rotM_zToY
        copy.minX = minX; copy.maxX = maxX
        copy.minY = minY; copy.maxY = maxY
        copy.minZ = minZ; copy.maxZ = maxZ
        copy.maxFaceDimension = maxFaceDimension
        copy.vertexCount2 = vertexCount2
        copy.m_Yb = m_Yb
        copy.m_dc = m_dc
        copy.occludesBillboards = occludesBillboards
        copy.bypassFrustumBoundsCull = bypassFrustumBoundsCull

        // Deep-copy arrays
        copy.vertX = vertX; copy.vertY = vertY; copy.vertZ = vertZ
        copy.vertXTransform = vertXTransform
        copy.vertYTransform = vertYTransform
        copy.vertZTransform = vertZTransform
        copy.vertXRot = vertXRot; copy.vertYRot = vertYRot; copy.vertZRot = vertZRot
        copy.vertexParam2 = vertexParam2; copy.vertexParam6 = vertexParam6
        copy.vertDiffuseLight = vertDiffuseLight; copy.vertLightOther = vertLightOther
        copy.vertHead = vertHead
        copy.faceCount = faceCount
        copy.faceHead = faceHead
        copy.faceIndexCount = faceIndexCount
        copy.faceIndices = faceIndices.map { $0 }   // deep copy inner arrays
        copy.faceTextureFront = faceTextureFront
        copy.faceTextureBack = faceTextureBack
        copy.faceDiffuseLight = faceDiffuseLight
        copy.facePickIndex = facePickIndex
        copy.scenePolyNormalShift = scenePolyNormalShift
        copy.scenePolyNormalMagnitude = scenePolyNormalMagnitude
        copy.faceNormX = faceNormX; copy.faceNormY = faceNormY; copy.faceNormZ = faceNormZ
        copy.faceMinX = faceMinX; copy.faceMaxX = faceMaxX
        copy.faceMinY = faceMinY; copy.faceMaxY = faceMaxY
        copy.faceMinZ = faceMinZ; copy.faceMaxZ = faceMaxZ
        copy.faceParam1 = faceParam1.map { $0 }
        copy.m_zb = m_zb

        return copy
    }

    // MARK: - Grid subdivision

    /// Splits this model into a grid of sub-models.
    final func divideModelByGrid(xDivisions xDim: Int32, gridSize zGridSize: Int32,
                                 count outModels: Int32) -> [RSModel] {
        commitTransform()

        var outVertCount = [Int32](repeating: 0, count: Int(outModels))
        var outFaceCount = [Int32](repeating: 0, count: Int(outModels))

        // First pass: count verts/faces per cell
        for i in 0 ..< Int(faceHead) {
            var sumX: Int32 = 0
            var sumZ: Int32 = 0
            let fvc = faceIndexCount[i]
            let fv = faceIndices[i]
            for j in 0 ..< Int(fvc) {
                sumX += vertX[Int(fv[j])]
                sumZ += vertZ[Int(fv[j])]
            }
            let id = sumX / (fvc &* zGridSize) &+ sumZ / (zGridSize &* fvc) &* xDim
            if id >= 0 && id < outModels {
                outVertCount[Int(id)] += fvc
                outFaceCount[Int(id)] += 1
            }
        }

        var output = [RSModel]()
        for i in 0 ..< Int(outModels) {
            let sub = RSModel(vertexLimit: outVertCount[i], faceLimit: outFaceCount[i],
                              useTransformAsVert: true, useMinC: true,
                              noDiffuse: true, useMinDB: false, useMinB: true)
            sub.diffuseParam2 = diffuseParam2
            sub.diffuseParam1 = diffuseParam1
            output.append(sub)
        }

        // Second pass: distribute faces
        for f in 0 ..< Int(faceHead) {
            var sumX: Int32 = 0
            var sumZ: Int32 = 0
            let srcIndexCount = faceIndexCount[f]
            let srcIndices = faceIndices[f]
            for i in 0 ..< Int(srcIndexCount) {
                sumX += vertX[Int(srcIndices[i])]
                sumZ += vertZ[Int(srcIndices[i])]
            }
            let id = sumX / (srcIndexCount &* zGridSize) &+ xDim &* (sumZ / (zGridSize &* srcIndexCount))
            if id >= 0 && id < outModels {
                copyFaceTo(faceVert: srcIndices, dest: output[Int(id)],
                           faceVertCount: srcIndexCount, srcFaceID: Int32(f))
            }
        }

        for i in 0 ..< Int(outModels) {
            output[i].clearRotDataAndParams26()
        }
        return output
    }

    // MARK: - Projection (called every frame)

    /// Projects all vertices into camera/screen space.
    /// Exact port of Java rotate1024 — fixed-point Int32 arithmetic throughout.
    ///
    /// - Parameters:
    ///   - yOffset:   World Y offset of camera pivot
    ///   - vParamSrc: Shift amount for screen-space projection
    ///   - xOffset:   World X offset of camera pivot
    ///   - zOffset:   World Z offset of camera pivot
    ///   - rotY:      Camera yaw (0–1023, 1024-table)
    ///   - rotZ:      Camera roll (0–1023, 1024-table)
    ///   - rotX:      Camera pitch (0–1023, 1024-table)
    ///   - zTop:      Near-plane Z threshold
    final func rotate1024(yOffset: Int32, vParamSrc: Int32, xOffset: Int32, zOffset: Int32,
                          rotY: Int32, rotZ: Int32, rotX: Int32, zTop: Int32) {
        resetTransformCache()

        // Frustum / bounding-box visibility cull.
        if !bypassFrustumBoundsCull {
            guard minZ <= Scene.frustumMinX && maxZ >= Scene.frustumMaxX
               && minX <= Scene.frustumMinY && maxX >= Scene.frustumMaxY
               && minY <= Scene.frustumNearZ && maxY >= Scene.frustumFarZ
            else {
                m_dc = false
                return
            }
        }

        m_dc = true
        clearRotDataAndParams26()

        // Pre-fetch trig values (0 if rotation angle is 0)
        var xy_xy: Int32 = 0   // sin(rotZ)
        var xy_yy: Int32 = 0   // cos(rotZ)
        var yz_zy: Int32 = 0   // sin(rotX)
        var yz_zz: Int32 = 0   // cos(rotX)
        var xz_xz: Int32 = 0   // sin(rotY)
        var xz_xx: Int32 = 0   // cos(rotY)

        if rotZ != 0 {
            xy_yy = FastMath.trigTable1024[1024 + Int(rotZ)]
            xy_xy = FastMath.trigTable1024[Int(rotZ)]
        }
        if rotX != 0 {
            yz_zy = FastMath.trigTable1024[Int(rotX)]
            yz_zz = FastMath.trigTable1024[Int(rotX) + 1024]
        }
        if rotY != 0 {
            xz_xz = FastMath.trigTable1024[Int(rotY)]
            xz_xx = FastMath.trigTable1024[Int(rotY) + 1024]
        }

        for var17 in 0 ..< Int(vertHead) {
            var x0: Int32 = vertXTransform[var17] &- xOffset
            var yO: Int32 = vertYTransform[var17] &- yOffset
            var zO: Int32 = vertZTransform[var17] &- zOffset

            // Roll (Z-axis rotation)
            if rotZ != 0 {
                let tmp: Int32 = (yO &* xy_xy &+ xy_yy &* x0) >> 15
                yO = (yO &* xy_yy &- x0 &* xy_xy) >> 15
                x0 = tmp
            }

            // Yaw (Y-axis rotation)
            if rotY != 0 {
                let tmp: Int32 = (xz_xx &* x0 &+ zO &* xz_xz) >> 15
                zO = (xz_xx &* zO &- x0 &* xz_xz) >> 15
                x0 = tmp
            }

            // Pitch (X-axis rotation)
            if rotX != 0 {
                let tmp: Int32 = (yO &* yz_zz &- yz_zy &* zO) >> 15
                zO = (yz_zy &* yO &+ yz_zz &* zO) >> 15
                yO = tmp
            }

            // Perspective projection — guard against divide-by-zero near zTop
            if zO < zTop {
                vertexParam6[var17] = x0 << vParamSrc
            } else {
                vertexParam6[var17] = (x0 << vParamSrc) / zO
            }

            if zO < zTop {
                vertexParam2[var17] = yO << vParamSrc
            } else {
                vertexParam2[var17] = (yO << vParamSrc) / zO
            }

            vertXRot[var17] = x0
            vertYRot[var17] = yO
            vertZRot[var17] = zO
        }
    }

    // MARK: - Internal helpers

    /// Commits the current rot/scale/translate state back into the base vertex arrays
    /// and resets all transform fields to identity.
    final func commitTransform() {
        resetTransformCache()

        for i in 0 ..< Int(vertHead) {
            vertX[i] = vertXTransform[i]
            vertY[i] = vertYTransform[i]
            vertZ[i] = vertZTransform[i]
        }

        rot256Z = 0; rot256X = 0
        rotM_xToZ = 256; rotM_zToY = 256
        translateY = 0; rot256Y = 0
        rotM_xToY = 256; rotM_zToX = 256
        scaleX = 256
        appliedTransform = 0
        translateX = 0
        scaleY = 256
        rotM_yToX = 256
        scaleZ = 256
        translateZ = 0
        rotM_yToZ = 256
    }

    // =========================================================================
    // MARK: - Private methods
    // =========================================================================

    private func setFaceVertexCount(faceCount fc: Int32, vertexCount vc: Int32) {
        let fi = Int(fc)
        let vi = Int(vc)

        if !m_db {
            m_zb = [Int8](repeating: 0, count: fi)
            facePickIndex = [Int32](repeating: 0, count: fi)
        }

        scenePolyNormalMagnitude = [Int32](repeating: 0, count: fi)
        vertY = [Int32](repeating: 0, count: vi)
        vertLightOther = [Int8](repeating: 0, count: vi)
        vertX = [Int32](repeating: 0, count: vi)
        scenePolyNormalShift = [Int32](repeating: -1, count: fi)
        vertZ = [Int32](repeating: 0, count: vi)
        faceTextureBack = [Int32](repeating: 0, count: fi)
        vertDiffuseLight = [Int32](repeating: 0, count: vi)
        faceTextureFront = [Int32](repeating: 0, count: fi)
        faceIndices = [[Int32]](repeating: [], count: fi)
        faceIndexCount = [Int32](repeating: 0, count: fi)

        if !m_b {
            vertexParam2 = [Int32](repeating: 0, count: vi)
            vertYRot = [Int32](repeating: 0, count: vi)
            vertXRot = [Int32](repeating: 0, count: vi)
            vertZRot = [Int32](repeating: 0, count: vi)
            vertexParam6 = [Int32](repeating: 0, count: vi)
        }

        faceDiffuseLight = [Int32](repeating: 0, count: fi)

        // Rotation matrix — identity
        rotM_zToX = 256; rot256Y = 0; rotM_xToZ = 256; rotM_yToX = 256; scaleZ = 256

        if !m_c {
            faceMaxX = [Int32](repeating: 0, count: fi)
            faceMinY = [Int32](repeating: 0, count: fi)
            faceMinZ = [Int32](repeating: 0, count: fi)
            faceMaxY = [Int32](repeating: 0, count: fi)
            faceMaxZ = [Int32](repeating: 0, count: fi)
            faceMinX = [Int32](repeating: 0, count: fi)
        }

        if !dontComputeDiffuse || !m_c {
            faceNormY = [Int32](repeating: 0, count: fi)
            faceNormZ = [Int32](repeating: 0, count: fi)
            faceNormX = [Int32](repeating: 0, count: fi)
        }

        rotM_yToZ = 256; faceHead = 0; rot256X = 0; translateZ = 0; scaleX = 256

        if !m_v {
            vertXTransform = [Int32](repeating: 0, count: vi)
            vertZTransform = [Int32](repeating: 0, count: vi)
            vertYTransform = [Int32](repeating: 0, count: vi)
        } else {
            // Share backing storage (alias)
            vertXTransform = vertX
            vertZTransform = vertZ
            vertYTransform = vertY
        }

        translateX = 0
        vertexCount2 = vc
        rotM_xToY = 256; rotM_zToY = 256; translateY = 0; appliedTransform = 0
        vertHead = 0; scaleY = 256

        faceCount = fc
        rot256Z = 0
    }

    private func computeAppliedTransform() {
        if rotM_yToX == 256 && rotM_yToZ == 256 && rotM_zToX == 256 && rotM_zToY == 256
            && rotM_xToZ == 256 && rotM_xToY == 256 {
            if scaleX == 256 && scaleY == 256 && scaleZ == 256 {
                if rot256X == 0 && rot256Y == 0 && rot256Z == 0 {
                    if translateX == 0 && translateY == 0 && translateZ == 0 {
                        appliedTransform = 0
                    } else {
                        appliedTransform = 1
                    }
                } else {
                    appliedTransform = 2
                }
            } else {
                appliedTransform = 3
            }
        } else {
            appliedTransform = 4
        }
    }

    /// Allocates per-vertex screen-space arrays and sets default diffuse light.
    private func clearRotDataAndParams26() {
        setDiffuseLight(ambientParam1: 40, ambientParam2: 102, dirX: 104, dirY: 108, dirZ: -20)
        vertexParam2 = [Int32](repeating: 0, count: Int(vertHead))
        vertXRot = [Int32](repeating: 0, count: Int(vertHead))
        vertYRot = [Int32](repeating: 0, count: Int(vertHead))
        vertZRot = [Int32](repeating: 0, count: Int(vertHead))
        vertexParam6 = [Int32](repeating: 0, count: Int(vertHead))
    }

    /// Resets transform arrays from base vertex data and applies queued transforms.
    private func resetTransformCache() {
        guard m_Yb != 0 else { return }

        if m_Yb == 2 {
            m_Yb = 0
            for i in 0 ..< Int(vertHead) {
                vertXTransform[i] = vertX[i]
                vertYTransform[i] = vertY[i]
                vertZTransform[i] = vertZ[i]
            }
            maxX = 9999999; maxY = 9999999; minY = -9999999
            maxZ = 9999999; minZ = -9999999; maxFaceDimension = 9999999
            minX = -9999999

        } else if m_Yb == 1 {
            m_Yb = 0
            for i in 0 ..< Int(vertHead) {
                vertXTransform[i] = vertX[i]
                vertYTransform[i] = vertY[i]
                vertZTransform[i] = vertZ[i]
            }

            if appliedTransform >= 2 {
                rotate256(rotX: rot256X, rotZ: rot256Z, rotY: rot256Y)
            }
            if appliedTransform >= 3 {
                applyScale(xScale: scaleX, zScale: scaleZ, yScale: scaleY)
            }
            if appliedTransform >= 4 {
                applyRotMatrix(xToZ: rotM_xToZ, zToY: rotM_zToY, yToX: rotM_yToX,
                               yToZ: rotM_yToZ, zToX: rotM_zToX, xToY: rotM_xToY)
            }
            if appliedTransform >= 1 {
                applyTranslate(startIdx: 0, yt: translateY, zt: translateZ, xt: translateX)
            }

            calculateBoundingBoxes(999999)
            computeNormals()
        }
    }

    /// Applies 256-step (byte-range) rotation to transform arrays.
    private func rotate256(rotX: Int32, rotZ: Int32, rotY: Int32) {
        for v in 0 ..< Int(vertHead) {
            var tmp: Int32
            if rotZ != 0 {
                let xx = FastMath.trigTable256[Int(rotZ) + 256]
                let xy = FastMath.trigTable256[Int(rotZ)]
                tmp = (vertXTransform[v] &* xx &+ vertYTransform[v] &* xy) >> 15
                vertYTransform[v] = (vertYTransform[v] &* xx &- xy &* vertXTransform[v]) >> 15
                vertXTransform[v] = tmp
            }
            if rotX != 0 {
                let yz = FastMath.trigTable256[Int(rotX)]
                let yy = FastMath.trigTable256[256 + Int(rotX)]
                tmp = (yy &* vertYTransform[v] &- yz &* vertZTransform[v]) >> 15
                vertZTransform[v] = (yz &* vertYTransform[v] &+ yy &* vertZTransform[v]) >> 15
                vertYTransform[v] = tmp
            }
            if rotY != 0 {
                let xz = FastMath.trigTable256[Int(rotY)]
                let xx = FastMath.trigTable256[256 + Int(rotY)]
                tmp = (xz &* vertZTransform[v] &+ vertXTransform[v] &* xx) >> 15
                vertZTransform[v] = (vertZTransform[v] &* xx &- vertXTransform[v] &* xz) >> 15
                vertXTransform[v] = tmp
            }
        }
    }

    /// Applies axis-independent scaling (256 = 1.0).
    private func applyScale(xScale: Int32, zScale: Int32, yScale: Int32) {
        for i in 0 ..< Int(vertHead) {
            vertXTransform[i] = (vertXTransform[i] &* xScale) >> 8
            vertYTransform[i] = (vertYTransform[i] &* yScale) >> 8
            vertZTransform[i] = (zScale &* vertZTransform[i]) >> 8
        }
    }

    /// Applies the shear/rotation matrix (256-scale elements).
    private func applyRotMatrix(xToZ: Int32, zToY: Int32, yToX: Int32,
                                yToZ: Int32, zToX: Int32, xToY: Int32) {
        for i in 0 ..< Int(vertHead) {
            if yToX != 0 {
                vertXTransform[i] += (vertYTransform[i] &* yToX) >> 8
            }
            if yToZ != 0 {
                vertZTransform[i] += (yToZ &* vertYTransform[i]) >> 8
            }
            if zToX != 0 {
                vertXTransform[i] += (zToX &* vertZTransform[i]) >> 8
            }
            if zToY != 0 {
                vertYTransform[i] += (zToY &* vertZTransform[i]) >> 8
            }
            if xToZ != 0 {
                vertZTransform[i] += (xToZ &* vertXTransform[i]) >> 8
            }
            if xToY != 0 {
                vertYTransform[i] += (vertXTransform[i] &* xToY) >> 8
            }
        }
    }

    /// Translates a range of vertices.
    private func applyTranslate(startIdx: Int32, yt: Int32, zt: Int32, xt: Int32) {
        for i in Int(startIdx) ..< Int(vertHead) {
            vertXTransform[i] += xt
            vertYTransform[i] += yt
            vertZTransform[i] += zt
        }
    }

    /// Computes AABB and per-face bounding boxes from current transform arrays.
    private func calculateBoundingBoxes(_ yInit: Int32) {
        minX = 999999; minZ = 999999; maxZ = -999999
        minY = yInit; maxX = -999999; maxY = -999999
        maxFaceDimension = -999999

        for face in 0 ..< Int(faceHead) {
            let fIndex = faceIndices[face]
            let fIndexCount = Int(faceIndexCount[face])
            let vID0 = Int(fIndex[0])

            var fMinZ = vertZTransform[vID0];  var fMaxZ = fMinZ
            var fMinY = vertYTransform[vID0];  var fMaxY = fMinY
            var fMinX = vertXTransform[vID0];  var fMaxX = fMinX

            for vert in 0 ..< fIndexCount {
                let vID = Int(fIndex[vert])
                let vz = vertZTransform[vID]
                let vy = vertYTransform[vID]
                let vx = vertXTransform[vID]

                if vz >= fMinZ { if vz > fMaxZ { fMaxZ = vz } } else { fMinZ = vz }
                if vy < fMinY { fMinY = vy } else if vy > fMaxY { fMaxY = vy }
                if fMinX <= vx { if vx > fMaxX { fMaxX = vx } } else { fMinX = vx }
            }

            if !m_c {
                faceMinX[face] = fMinX; faceMaxX[face] = fMaxX
                faceMinY[face] = fMinY; faceMaxY[face] = fMaxY
                faceMinZ[face] = fMinZ; faceMaxZ[face] = fMaxZ
            }

            if fMaxX &- fMinX > maxFaceDimension { maxFaceDimension = fMaxX &- fMinX }
            if fMaxY &- fMinY > maxFaceDimension { maxFaceDimension = fMaxY &- fMinY }
            if maxX < fMaxX { maxX = fMaxX }
            if fMaxZ > maxZ { maxZ = fMaxZ }
            if fMaxZ &- fMinZ > maxFaceDimension { maxFaceDimension = fMaxZ &- fMinZ }
            if maxY < fMaxY { maxY = fMaxY }
            if fMinX < minX { minX = fMinX }
            if fMinY < minY { minY = fMinY }
            if minZ > fMinZ { minZ = fMinZ }
        }
    }

    /// Computes face normals and per-vertex diffuse lighting.
    private func computeNormals() {
        guard !dontComputeDiffuse || !m_c else { return }

        for face in 0 ..< Int(faceHead) {
            let v = faceIndices[face]
            let xp = vertXTransform[Int(v[0])];  let yp = vertYTransform[Int(v[0])];  let zp = vertZTransform[Int(v[0])]
            let x21 = vertXTransform[Int(v[1])] &- xp
            let y21 = vertYTransform[Int(v[1])] &- yp
            let z21 = vertZTransform[Int(v[1])] &- zp
            let x31 = vertXTransform[Int(v[2])] &- xp
            let y31 = vertYTransform[Int(v[2])] &- yp
            let z31 = vertZTransform[Int(v[2])] &- zp

            var xN = z31 &* y21 &- z21 &* y31
            var yN = z21 &* x31 &- x21 &* z31
            var zN = x21 &* y31 &- x31 &* y21

            while xN > 8192 || yN > 8192 || zN > 8192 || xN < -8192 || yN < -8192 || zN < -8192 {
                yN >>= 1; zN >>= 1; xN >>= 1
            }

            var mag = Int32(Foundation.sqrt(Double(yN &* yN &+ xN &* xN &+ zN &* zN)) * 256.0)
            if mag <= 0 { mag = 1 }

            faceNormX[face] = xN &* 65536 / mag
            faceNormY[face] = yN &* 65536 / mag
            faceNormZ[face] = zN &* 65535 / mag
            scenePolyNormalShift[face] = -1
        }

        computeDiffuse(14)
    }

    /// Computes per-face and per-vertex diffuse light values.
    private func computeDiffuse(_ var1: Int32) {
        guard !dontComputeDiffuse else { return }

        let diffuseDivide = (diffuseParam2 &* diffuseMag) >> 8

        for f in 0 ..< Int(faceHead) {
            if faceDiffuseLight[f] != m_Vb {
                if diffuseDivide != 0 {
                    faceDiffuseLight[f] = (faceNormY[f] &* diffuseDirY
                        &+ faceNormX[f] &* diffuseDirX
                        &+ diffuseDirZ &* faceNormZ[f]) / diffuseDivide
                }
            }
        }

        var tmpXNorm = [Int32](repeating: 0, count: Int(vertHead))
        var tmpYNorm = [Int32](repeating: 0, count: Int(vertHead))
        var tmpZNorm = [Int32](repeating: 0, count: Int(vertHead))
        var faceCounts = [Int32](repeating: 0, count: Int(vertHead))

        for i in 0 ..< Int(faceHead) {
            if m_Vb == faceDiffuseLight[i] {
                for fi in 0 ..< Int(faceIndexCount[i]) {
                    let fVert = Int(faceIndices[i][fi])
                    tmpXNorm[fVert] += faceNormX[i]
                    tmpYNorm[fVert] += faceNormY[i]
                    tmpZNorm[fVert] += faceNormZ[i]
                    faceCounts[fVert] += 1
                }
            }
        }

        for i in 0 ..< Int(vertHead) {
            if faceCounts[i] > 0 {
                let d = diffuseDivide &* faceCounts[i]
                if d != 0 {
                    vertDiffuseLight[i] = (tmpZNorm[i] &* diffuseDirZ
                        &+ tmpXNorm[i] &* diffuseDirX
                        &+ tmpYNorm[i] &* diffuseDirY) / d
                }
            }
        }
    }

    /// Copies a face (and its vertices) into a destination model.
    private func copyFaceTo(faceVert: [Int32], dest: RSModel,
                            faceVertCount: Int32, srcFaceID: Int32) {
        var nVerts = [Int32](repeating: 0, count: Int(faceVertCount))

        for i in 0 ..< Int(faceVertCount) {
            let vi = Int(faceVert[i])
            let vID = dest.insertVertex(x: vertX[vi], y: vertY[vi], z: vertZ[vi])
            nVerts[i] = vID
            if vID >= 0 {
                dest.vertDiffuseLight[Int(vID)] = vertDiffuseLight[vi]
                dest.vertLightOther[Int(vID)] = vertLightOther[vi]
            }
        }

        let fIdx = Int(srcFaceID)
        let i = dest.insertFace(count: faceVertCount, indices: nVerts,
                                texFront: faceTextureFront[fIdx],
                                texBack: faceTextureBack[fIdx])
        if !dest.m_db && !m_db, i >= 0 {
            dest.facePickIndex[Int(i)] = facePickIndex[fIdx]
        }
        if i >= 0 {
            dest.faceDiffuseLight[Int(i)] = faceDiffuseLight[fIdx]
            dest.scenePolyNormalShift[Int(i)] = scenePolyNormalShift[fIdx]
            dest.scenePolyNormalMagnitude[Int(i)] = scenePolyNormalMagnitude[fIdx]
        }
    }
}

// MARK: - MiscFunctions frustum stubs
// These mirror the Java statics used in rotate1024's visibility cull.
// They will be replaced by the real MiscFunctions port when that file is ported.
enum MiscFunctions {
    static var frustumMinX: Int32 = Int32.min
    static var frustumMaxX: Int32 = Int32.max
    static var frustumMinY: Int32 = Int32.min
    static var frustumMaxY: Int32 = Int32.max
    static var frustumNearZ: Int32 = Int32.min
    static var frustumFarZ: Int32 = Int32.max
}
