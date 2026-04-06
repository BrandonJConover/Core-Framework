import Foundation

/// Port of orsc.graphics.three.RSModel from the Java desktop client.
/// Core 3D geometry representation used by the entire rendering engine.
final class RSModel {

    // MARK: - Constants

    static let TRANSPARENT = 12345678

    // MARK: - Frustum (static, set externally like MiscFunctions in Java)

    static var frustumMinX = 0
    static var frustumMaxX = 0
    static var frustumMinY = 0
    static var frustumMaxY = 0
    static var frustumNearZ = 0
    static var frustumFarZ = 0

    // MARK: - Vertex Data

    var vertX: [Int] = []
    var vertY: [Int] = []
    var vertZ: [Int] = []
    var vertXTransform: [Int] = []
    var vertYTransform: [Int] = []
    var vertZTransform: [Int] = []
    var vertXRot: [Int] = []
    var vertYRot: [Int] = []
    var vertZRot: [Int] = []
    var vertexParam6: [Int] = []     // projected screen-space X
    var vertexParam2: [Int] = []     // projected screen-space Y
    var vertDiffuseLight: [Int] = []
    var vertLightOther: [Int8] = []
    var vertHead: Int = 0

    // MARK: - Face Data

    var faceIndices: [[Int]] = []
    var faceIndexCount: [Int] = []
    var faceTextureFront: [Int] = []
    var faceTextureBack: [Int] = []
    var faceDiffuseLight: [Int] = []
    var facePickIndex: [Int] = []
    var faceHead: Int = 0
    private var faceCount: Int = 0

    var scenePolyNormalShift: [Int] = []
    var scenePolyNormalMagnitude: [Int] = []

    // MARK: - Face Normals

    private var faceNormX: [Int] = []
    private var faceNormY: [Int] = []
    private var faceNormZ: [Int] = []

    // MARK: - Face Bounding Boxes

    private var faceMinX: [Int] = []
    private var faceMaxX: [Int] = []
    private var faceMinY: [Int] = []
    private var faceMaxY: [Int] = []
    private var faceMinZ: [Int] = []
    private var faceMaxZ: [Int] = []

    // MARK: - Face Param1 (for model merging/picking)

    private var faceParam1: [[Int]] = []

    // MARK: - Transform State

    private var rot256X: Int = 0
    private var rot256Y: Int = 0
    private var rot256Z: Int = 0
    private var translateX: Int = 0
    private var translateY: Int = 0
    private var translateZ: Int = 0
    private var scaleX: Int = 256
    private var scaleY: Int = 256
    private var scaleZ: Int = 256
    private var appliedTransform: Int = 0

    // Rotation matrix components (0-255 -> 0-1 scale via >>8)
    private var rotM_yToX: Int = 256
    private var rotM_yToZ: Int = 256
    private var rotM_zToX: Int = 256
    private var rotM_zToY: Int = 256
    private var rotM_xToZ: Int = 256
    private var rotM_xToY: Int = 256

    /// Special flag (giantcrystal)
    var m_cb: Bool = false

    // MARK: - Bounding Box

    private var minX: Int = 0
    private var maxX: Int = 0
    private var minY: Int = 0
    private var maxY: Int = 0
    private var minZ: Int = 0
    private var maxZ: Int = 0
    private var maxFaceDimension: Int = RSModel.TRANSPARENT

    // MARK: - Lighting Params

    var diffuseParam1: Int = 32
    var diffuseParam2: Int = 512
    private var diffuseDirX: Int = 180
    private var diffuseDirY: Int = 155
    private var diffuseDirZ: Int = 95
    private var diffuseMag: Int = 256

    // MARK: - Internal State

    var key: Int = -1
    var m_hc: Int = 0
    var m_Yb: Int = 1
    private var vertexCount2: Int = 0
    private var m_hb: Int = 0

    // Internal boolean flags matching Java
    var m_db: Bool = false
    var m_dc: Bool = true
    var m_Kb: Bool = false
    private var m_v: Bool = false
    private var m_c: Bool = false
    private var m_b: Bool = false
    private var dontComputeDiffuse: Bool = false
    var m_zb: [Int8] = []

    // MARK: - Initializers

    /// Allocate arrays for given vertex and face capacity.
    /// Corresponds to Java RSModel(int vertexCount, int faceCount).
    init(vertexCount: Int, faceCount: Int) {
        setFaceVertexCount(faceCount: faceCount, vertexCount: vertexCount, var3: 69)
        self.faceParam1 = [[Int]](repeating: [], count: faceCount)
        for face in 0..<faceCount {
            self.faceParam1[face] = [face]
        }
    }

    /// Binary .ob3 model parser.
    /// Corresponds to Java RSModel(byte[] data, int offset, boolean var3).
    init(data: Data, offset: Int) {
        var off = offset

        let vertexCount = RSModel.get16(off, data)
        off += 2
        let fc = RSModel.get16(off, data)
        off += 2

        setFaceVertexCount(faceCount: fc, vertexCount: vertexCount, var3: 115)
        self.faceParam1 = [[Int]](repeating: [0], count: fc)

        for j in 0..<vertexCount {
            self.vertX[j] = RSModel.readShort(data, off)
            off += 2
        }

        for j in 0..<vertexCount {
            self.vertY[j] = RSModel.readShort(data, off)
            off += 2
        }

        for j in 0..<vertexCount {
            self.vertZ[j] = RSModel.readShort(data, off)
            off += 2
        }

        self.vertHead = vertexCount

        for j in 0..<fc {
            self.faceIndexCount[j] = Int(data[off]) & 255
            off += 1
        }

        for j in 0..<fc {
            self.faceTextureFront[j] = RSModel.readShort(data, off)
            if self.faceTextureFront[j] == 32767 {
                self.faceTextureFront[j] = RSModel.TRANSPARENT
            }
            off += 2
        }

        for j in 0..<fc {
            self.faceTextureBack[j] = RSModel.readShort(data, off)
            if self.faceTextureBack[j] == 32767 {
                self.faceTextureBack[j] = RSModel.TRANSPARENT
            }
            off += 2
        }

        for j in 0..<fc {
            let i = Int(data[off]) & 255
            off += 1
            if i != 0 {
                self.faceDiffuseLight[j] = RSModel.TRANSPARENT
            } else {
                self.faceDiffuseLight[j] = 0
            }
        }

        for j in 0..<fc {
            self.faceIndices[j] = [Int](repeating: 0, count: self.faceIndexCount[j])
            for i in 0..<self.faceIndexCount[j] {
                if vertexCount < 256 {
                    self.faceIndices[j][i] = Int(data[off]) & 255
                    off += 1
                } else {
                    self.faceIndices[j][i] = RSModel.get16(off, data)
                    off += 2
                }
            }
        }

        self.faceHead = fc
        self.m_Yb = 1
    }

    /// Internal initializer for model subdivision/copying with flags.
    /// Corresponds to Java RSModel(int, int, boolean, boolean, boolean, boolean, boolean).
    private init(vertexLimit: Int, faceLimit: Int, m_v: Bool, m_c: Bool, dontComputeDiffuse: Bool, m_db: Bool, m_b: Bool) {
        self.m_c = m_c
        self.m_b = m_b
        self.m_db = m_db
        self.m_v = m_v
        self.dontComputeDiffuse = dontComputeDiffuse
        setFaceVertexCount(faceCount: faceLimit, vertexCount: vertexLimit, var3: 69)
    }

    /// Internal initializer for merging models (clone/addModels path).
    /// Corresponds to Java RSModel(RSModel[], int).
    private init(models: [RSModel], modelCount: Int) {
        addModels(offset: 0, models: models, var3: true, modelCount: modelCount)
    }

    /// Internal initializer for copyModel with flags.
    /// Corresponds to Java RSModel(RSModel[], int, boolean, boolean, boolean, boolean).
    private init(models: [RSModel], modelCount: Int, m_v: Bool, m_c: Bool, dontComputeDiffuse: Bool, m_db: Bool) {
        self.dontComputeDiffuse = dontComputeDiffuse
        self.m_c = m_c
        self.m_db = m_db
        self.m_v = m_v
        addModels(offset: 0, models: models, var3: false, modelCount: modelCount)
    }

    // MARK: - Binary Helpers

    /// Read unsigned 16-bit big-endian value.
    private static func get16(_ offset: Int, _ data: Data) -> Int {
        return (Int(data[offset]) & 255) << 8 | (Int(data[offset + 1]) & 255)
    }

    /// Read signed 16-bit big-endian value.
    private static func readShort(_ data: Data, _ index: Int) -> Int {
        var val = (Int(data[index]) & 255) * 256 + (Int(data[index + 1]) & 255)
        if val > 32767 {
            val -= 65536
        }
        return val
    }

    // MARK: - setFaceVertexCount

    /// Allocates all internal arrays. Corresponds to Java setFaceVertexCount.
    private func setFaceVertexCount(faceCount fc: Int, vertexCount vc: Int, var3: Int) {
        if !self.m_db {
            self.m_zb = [Int8](repeating: 0, count: fc)
            self.facePickIndex = [Int](repeating: 0, count: fc)
        }

        self.scenePolyNormalMagnitude = [Int](repeating: 0, count: fc)
        self.vertY = [Int](repeating: 0, count: vc)
        self.vertLightOther = [Int8](repeating: 0, count: vc)
        self.vertX = [Int](repeating: 0, count: vc)
        self.scenePolyNormalShift = [Int](repeating: 0, count: fc)
        self.vertZ = [Int](repeating: 0, count: vc)
        self.faceTextureBack = [Int](repeating: 0, count: fc)
        self.vertDiffuseLight = [Int](repeating: 0, count: vc)
        self.faceTextureFront = [Int](repeating: 0, count: fc)
        self.faceIndices = [[Int]](repeating: [], count: fc)
        self.faceIndexCount = [Int](repeating: 0, count: fc)

        if !self.m_b {
            self.vertexParam2 = [Int](repeating: 0, count: vc)
            self.vertYRot = [Int](repeating: 0, count: vc)
            self.vertXRot = [Int](repeating: 0, count: vc)
            self.vertZRot = [Int](repeating: 0, count: vc)
            self.vertexParam6 = [Int](repeating: 0, count: vc)
        }

        self.faceDiffuseLight = [Int](repeating: 0, count: fc)
        self.rotM_zToX = 256
        self.rot256Y = 0
        self.rotM_xToZ = 256
        self.rotM_yToX = 256
        self.scaleZ = 256

        if !self.m_c {
            self.faceMaxX = [Int](repeating: 0, count: fc)
            self.faceMinY = [Int](repeating: 0, count: fc)
            self.faceMinZ = [Int](repeating: 0, count: fc)
            self.faceMaxY = [Int](repeating: 0, count: fc)
            self.faceMaxZ = [Int](repeating: 0, count: fc)
            self.faceMinX = [Int](repeating: 0, count: fc)
        }

        if !self.dontComputeDiffuse || !self.m_c {
            self.faceNormY = [Int](repeating: 0, count: fc)
            self.faceNormZ = [Int](repeating: 0, count: fc)
            self.faceNormX = [Int](repeating: 0, count: fc)
        }

        self.rotM_yToZ = 256
        self.faceHead = 0
        self.rot256X = 0
        self.translateZ = 0
        self.scaleX = 256

        if !self.m_v {
            self.vertXTransform = [Int](repeating: 0, count: vc)
            self.vertZTransform = [Int](repeating: 0, count: vc)
            self.vertYTransform = [Int](repeating: 0, count: vc)
        } else {
            self.vertXTransform = self.vertX
            self.vertZTransform = self.vertZ
            self.vertYTransform = self.vertY
        }

        self.translateX = 0
        self.vertexCount2 = vc
        self.rotM_xToY = 256
        self.rotM_zToY = 256
        self.translateY = 0
        self.appliedTransform = 0
        self.vertHead = 0
        self.scaleY = 256

        if var3 <= 68 {
            // Java nulls this out, we leave as empty (shouldn't happen with our callers)
        }

        self.faceCount = fc
        self.rot256Z = 0
    }

    // MARK: - Vertex / Face Insertion

    /// Append a vertex, returning its index. De-duplicates by checking existing vertices.
    /// Corresponds to Java insertVertex (line 883).
    @discardableResult
    func insertVertex(x: Int, y: Int, z: Int) -> Int {
        for i in 0..<vertHead {
            if x == vertX[i] && y == vertY[i] && z == vertZ[i] {
                return i
            }
        }

        if vertHead < vertexCount2 {
            vertX[vertHead] = x
            vertY[vertHead] = y
            vertZ[vertHead] = z
            let idx = vertHead
            vertHead += 1
            return idx
        } else {
            return -1
        }
    }

    /// Append a vertex without de-duplication.
    /// Corresponds to Java insertVertex2 (line 906).
    @discardableResult
    func insertVertex2(x: Int, y: Int, z: Int) -> Int {
        if vertHead >= vertexCount2 {
            return -1
        }
        vertX[vertHead] = x
        vertY[vertHead] = y
        vertZ[vertHead] = z
        let idx = vertHead
        vertHead += 1
        return idx
    }

    /// Append a face, returning its index.
    /// Corresponds to Java insertFace (line 860).
    @discardableResult
    func insertFace(indexCount: Int, indices: [Int], textureFront: Int, textureBack: Int) -> Int {
        if faceHead < faceCount {
            faceIndexCount[faceHead] = indexCount
            faceIndices[faceHead] = indices
            faceTextureFront[faceHead] = textureFront
            faceTextureBack[faceHead] = textureBack
            m_Yb = 1
            let idx = faceHead
            faceHead += 1
            return idx
        } else {
            return -1
        }
    }

    // MARK: - Transform Methods

    /// Set rotation (0-255 range). Corresponds to Java setRot256 (line 1307).
    func setRot256(x: Int, y: Int, z: Int) {
        rot256X = x & 255
        rot256Y = y & 255
        rot256Z = z & 255
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Add rotation increments. Corresponds to Java addRotation (line 383).
    func addRotation(rotX: Int, rotY: Int, rotZ: Int) {
        rot256X = (rotX + rot256X) & 255
        rot256Y = (rotY + rot256Y) & 255
        rot256Z = (rot256Z + rotZ) & 255
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Set translation. Corresponds to Java setTranslate (line 1320).
    func setTranslate(tX: Int, tY: Int, tZ: Int) {
        translateX = tX
        translateY = tY
        translateZ = tZ
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Add to translation. Corresponds to Java translate2 (line 1357).
    func translate2(dx: Int, dy: Int, dz: Int) {
        translateX += dx
        translateY += dy
        translateZ += dz
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Copy rotation and translation from another model. Corresponds to Java copyRot256AndTranslateFrom (line 752).
    func copyRot256AndTranslateFrom(_ model: RSModel) {
        translateX = model.translateX
        translateY = model.translateY
        translateZ = model.translateZ
        rot256X = model.rot256X
        rot256Y = model.rot256Y
        rot256Z = model.rot256Z
        computeAppliedTransform()
        m_Yb = 1
    }

    /// Determines transform complexity level. Corresponds to Java computeAppliedTransform (line 591).
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

    /// Applies rot256/translate/scale to get vertXTransform from vertX.
    /// Corresponds to Java commitTransform (line 559).
    func commitTransform() {
        resetTransformCache()

        for i in 0..<vertHead {
            vertX[i] = vertXTransform[i]
            vertY[i] = vertYTransform[i]
            vertZ[i] = vertZTransform[i]
        }

        rot256Z = 0
        rot256X = 0
        rotM_xToZ = 256
        rotM_zToY = 256
        translateY = 0
        rot256Y = 0
        rotM_xToY = 256
        rotM_zToX = 256
        scaleX = 256
        appliedTransform = 0
        translateX = 0
        scaleY = 256
        rotM_yToX = 256
        scaleZ = 256
        translateZ = 0
        rotM_yToZ = 256
    }

    // MARK: - resetTransformCache

    /// Corresponds to Java resetTransformCache (line 954).
    private func resetTransformCache() {
        if m_Yb == 2 {
            m_Yb = 0

            for i in 0..<vertHead {
                vertXTransform[i] = vertX[i]
                vertYTransform[i] = vertY[i]
                vertZTransform[i] = vertZ[i]
            }

            maxX = 9999999
            maxY = 9999999
            minY = -9999999
            maxZ = 9999999
            minZ = -9999999
            maxFaceDimension = 9999999
            minX = -9999999
        } else if m_Yb == 1 {
            m_Yb = 0

            for i in 0..<vertHead {
                vertXTransform[i] = vertX[i]
                vertYTransform[i] = vertY[i]
                vertZTransform[i] = vertZ[i]
            }

            if appliedTransform >= 2 {
                rotate256(rotX: rot256X, rotZ: rot256Z, rotY: rot256Y)
            }

            if appliedTransform >= 3 {
                scale(xScale: scaleX, zScale: scaleZ, yScale: scaleY)
            }

            if appliedTransform >= 4 {
                applyRotMatrix(xToZ: rotM_xToZ, zToY: rotM_zToY, yToX: rotM_yToX,
                               yToZ: rotM_yToZ, zToX: rotM_zToX, xToY: rotM_xToY)
            }

            if appliedTransform >= 1 {
                translate(vOff: 0, yt: translateY, zt: translateZ, xt: translateX)
            }

            calculateBoundingBoxes()
            computeNormals()
        }
    }

    // MARK: - rotate256

    /// Applies 256-based rotation to transform coords. Corresponds to Java rotate256 (line 1097).
    private func rotate256(rotX: Int, rotZ: Int, rotY: Int) {
        for v in 0..<vertHead {
            var tmp: Int
            if rotZ != 0 {
                let xx = Int(FastMath.trigTable256[rotZ + 256])
                let xy = Int(FastMath.trigTable256[rotZ])
                tmp = (vertXTransform[v] * xx + vertYTransform[v] * xy) >> 15
                vertYTransform[v] = (vertYTransform[v] * xx - xy * vertXTransform[v]) >> 15
                vertXTransform[v] = tmp
            }

            if rotX != 0 {
                let yz = Int(FastMath.trigTable256[rotX])
                let yy = Int(FastMath.trigTable256[256 + rotX])
                tmp = (yy * vertYTransform[v] - yz * vertZTransform[v]) >> 15
                vertZTransform[v] = (yz * vertYTransform[v] + yy * vertZTransform[v]) >> 15
                vertYTransform[v] = tmp
            }

            if rotY != 0 {
                let xz = Int(FastMath.trigTable256[rotY])
                let xx = Int(FastMath.trigTable256[256 + rotY])
                tmp = (xz * vertZTransform[v] + vertXTransform[v] * xx) >> 15
                vertZTransform[v] = (vertZTransform[v] * xx - vertXTransform[v] * xz) >> 15
                vertXTransform[v] = tmp
            }
        }
    }

    // MARK: - scale

    /// Applies scale to transform coords. Corresponds to Java scale (line 1139).
    private func scale(xScale: Int, zScale: Int, yScale: Int) {
        for i in 0..<vertHead {
            vertXTransform[i] = (vertXTransform[i] * xScale) >> 8
            vertYTransform[i] = (vertYTransform[i] * yScale) >> 8
            vertZTransform[i] = (zScale * vertZTransform[i]) >> 8
        }
    }

    // MARK: - applyRotMatrix

    /// Applies rotation matrix components. Corresponds to Java applyRotMatrix (line 399).
    private func applyRotMatrix(xToZ: Int, zToY: Int, yToX: Int, yToZ: Int, zToX: Int, xToY: Int) {
        for i in 0..<vertHead {
            if yToX != 0 {
                vertXTransform[i] += (vertYTransform[i] * yToX) >> 8
            }
            if yToZ != 0 {
                vertZTransform[i] += (yToZ * vertYTransform[i]) >> 8
            }
            if zToX != 0 {
                vertXTransform[i] += (zToX * vertZTransform[i]) >> 8
            }
            if zToY != 0 {
                vertYTransform[i] += (zToY * vertZTransform[i]) >> 8
            }
            if xToZ != 0 {
                vertZTransform[i] += (xToZ * vertXTransform[i]) >> 8
            }
            if xToY != 0 {
                vertYTransform[i] += (vertXTransform[i] * xToY) >> 8
            }
        }
    }

    // MARK: - translate

    /// Translates transform coords. Corresponds to Java translate (line 1342).
    private func translate(vOff: Int, yt: Int, zt: Int, xt: Int) {
        for i in vOff..<vertHead {
            vertXTransform[i] += xt
            vertYTransform[i] += yt
            vertZTransform[i] += zt
        }
    }

    // MARK: - calculateBoundingBoxes

    /// Computes bounding boxes for the model and per-face. Corresponds to Java calculateBoundingBoxes (line 430).
    private func calculateBoundingBoxes() {
        self.minX = 999999
        self.minZ = 999999
        self.maxZ = -999999
        self.minY = 999999
        self.maxX = -999999
        self.maxY = -999999
        self.maxFaceDimension = -999999

        for face in 0..<faceHead {
            let fIndex = faceIndices[face]
            let fIndexCount = faceIndexCount[face]
            let vID0 = fIndex[0]
            var fMinZ = vertZTransform[vID0]
            var fMaxZ = fMinZ
            var fMinY = vertYTransform[vID0]
            var fMaxY = fMinY
            var fMinX = vertXTransform[vID0]
            var fMaxX = fMinX

            for vert in 0..<fIndexCount {
                let vID = fIndex[vert]
                if vertZTransform[vID] < fMinZ {
                    fMinZ = vertZTransform[vID]
                } else if vertZTransform[vID] > fMaxZ {
                    fMaxZ = vertZTransform[vID]
                }

                if vertYTransform[vID] < fMinY {
                    fMinY = vertYTransform[vID]
                } else if vertYTransform[vID] > fMaxY {
                    fMaxY = vertYTransform[vID]
                }

                if vertXTransform[vID] < fMinX {
                    fMinX = vertXTransform[vID]
                } else if vertXTransform[vID] > fMaxX {
                    fMaxX = vertXTransform[vID]
                }
            }

            if !m_c {
                self.faceMinX[face] = fMinX
                self.faceMaxX[face] = fMaxX
                self.faceMinY[face] = fMinY
                self.faceMaxY[face] = fMaxY
                self.faceMinZ[face] = fMinZ
                self.faceMaxZ[face] = fMaxZ
            }

            if fMaxX - fMinX > maxFaceDimension {
                maxFaceDimension = fMaxX - fMinX
            }

            if fMaxY - fMinY > maxFaceDimension {
                maxFaceDimension = fMaxY - fMinY
            }

            if maxX < fMaxX {
                maxX = fMaxX
            }

            if fMaxZ > maxZ {
                maxZ = fMaxZ
            }

            if fMaxZ - fMinZ > maxFaceDimension {
                maxFaceDimension = fMaxZ - fMinZ
            }

            if maxY < fMaxY {
                maxY = fMaxY
            }

            if fMinX < minX {
                minX = fMinX
            }

            if fMinY < minY {
                minY = fMinY
            }

            if minZ > fMinZ {
                minZ = fMinZ
            }
        }
    }

    // MARK: - computeNormals

    /// Computes face normals via cross product. Corresponds to Java computeNormals (line 672).
    private func computeNormals() {
        if dontComputeDiffuse && m_c {
            return
        }

        for face in 0..<faceHead {
            let verts = faceIndices[face]
            let xp = vertXTransform[verts[0]]
            let yp = vertYTransform[verts[0]]
            let zp = vertZTransform[verts[0]]

            let x21 = vertXTransform[verts[1]] - xp
            let y21 = vertYTransform[verts[1]] - yp
            let z21 = vertZTransform[verts[1]] - zp

            let x31 = vertXTransform[verts[2]] - xp
            let y31 = vertYTransform[verts[2]] - yp
            let z31 = vertZTransform[verts[2]] - zp

            var xN = z31 * y21 - z21 * y31
            var yN = z21 * x31 - x21 * z31
            var zN = x21 * y31 - x31 * y21

            while xN > 8192 || yN > 8192 || zN > 8192 || xN < -8192 || yN < -8192 || zN < -8192 {
                yN >>= 1
                zN >>= 1
                xN >>= 1
            }

            var mag = Int(sqrt(Double(yN * yN + xN * xN + zN * zN)) * 256.0)
            if mag <= 0 {
                mag = 1
            }

            faceNormX[face] = xN * 65536 / mag
            faceNormY[face] = yN * 65536 / mag
            faceNormZ[face] = zN * 65535 / mag
            scenePolyNormalShift[face] = -1
        }

        computeDiffuse()
    }

    // MARK: - computeDiffuse

    /// Computes per-face and per-vertex diffuse lighting. Corresponds to Java computeDiffuse (line 617).
    private func computeDiffuse() {
        if dontComputeDiffuse {
            return
        }

        let diffuseDivide = (diffuseParam2 * diffuseMag) >> 8

        for f in 0..<faceHead {
            if faceDiffuseLight[f] != RSModel.TRANSPARENT {
                faceDiffuseLight[f] = (faceNormY[f] * diffuseDirY
                    + faceNormX[f] * diffuseDirX + diffuseDirZ * faceNormZ[f])
                    / diffuseDivide
            }
        }

        var tmpXNorm = [Int](repeating: 0, count: vertHead)
        var tmpYNorm = [Int](repeating: 0, count: vertHead)
        var tmpZNorm = [Int](repeating: 0, count: vertHead)
        var vertFaceCount = [Int](repeating: 0, count: vertHead)

        for i in 0..<faceHead {
            if RSModel.TRANSPARENT == faceDiffuseLight[i] {
                for fi in 0..<faceIndexCount[i] {
                    let fVert = faceIndices[i][fi]
                    tmpXNorm[fVert] += faceNormX[i]
                    tmpYNorm[fVert] += faceNormY[i]
                    tmpZNorm[fVert] += faceNormZ[i]
                    vertFaceCount[fVert] += 1
                }
            }
        }

        for i in 0..<vertHead {
            if vertFaceCount[i] > 0 {
                vertDiffuseLight[i] = (tmpZNorm[i] * diffuseDirZ + tmpXNorm[i] * diffuseDirX
                    + tmpYNorm[i] * diffuseDirY) / (diffuseDivide * vertFaceCount[i])
            }
        }
    }

    // MARK: - clearRotDataAndParams26

    /// Allocates screen-space and rotation arrays. Corresponds to Java clearRotDataAndParams26 (line 528).
    private func clearRotDataAndParams26() {
        vertexParam2 = [Int](repeating: 0, count: vertHead)
        vertXRot = [Int](repeating: 0, count: vertHead)
        vertYRot = [Int](repeating: 0, count: vertHead)
        vertZRot = [Int](repeating: 0, count: vertHead)
        vertexParam6 = [Int](repeating: 0, count: vertHead)
    }

    // MARK: - rotate1024 (THE CRITICAL METHOD)

    /// Camera rotation and projection. Exact line-by-line port of Java rotate1024 (line 1013).
    func rotate1024(yOffset: Int, vParamSrc: Int, xOffset: Int, zOffset: Int, rotY: Int, rotZ: Int, rotX: Int, zTop: Int) {
        resetTransformCache()

        if minZ <= RSModel.frustumMinX && maxZ >= RSModel.frustumMaxX
            && minX <= RSModel.frustumMinY && maxX >= RSModel.frustumMaxY
            && minY <= RSModel.frustumNearZ && maxY >= RSModel.frustumFarZ {

            m_dc = true
            var xy_xy = 0
            var xy_yy = 0
            var yz_zy = 0
            var yz_zz = 0
            var xz_xz = 0
            var xz_xx = 0

            if rotZ != 0 {
                xy_yy = Int(FastMath.trigTable1024[1024 + rotZ])
                xy_xy = Int(FastMath.trigTable1024[rotZ])
            }

            if rotX != 0 {
                yz_zy = Int(FastMath.trigTable1024[rotX])
                yz_zz = Int(FastMath.trigTable1024[rotX + 1024])
            }

            if rotY != 0 {
                xz_xz = Int(FastMath.trigTable1024[rotY])
                xz_xx = Int(FastMath.trigTable1024[rotY + 1024])
            }

            for v in 0..<vertHead {
                var x0 = vertXTransform[v] - xOffset
                var yO = vertYTransform[v] - yOffset
                var zO = vertZTransform[v] - zOffset

                var tmp: Int
                if rotZ != 0 {
                    tmp = (yO * xy_xy + xy_yy * x0) >> 15
                    yO = (yO * xy_yy - x0 * xy_xy) >> 15
                    x0 = tmp
                }

                if rotY != 0 {
                    tmp = (xz_xx * x0 + zO * xz_xz) >> 15
                    zO = (xz_xx * zO - x0 * xz_xz) >> 15
                    x0 = tmp
                }

                if rotX != 0 {
                    tmp = (yO * yz_zz - yz_zy * zO) >> 15
                    zO = (yz_zy * yO + yz_zz * zO) >> 15
                    yO = tmp
                }

                if zO < zTop {
                    vertexParam6[v] = x0 << vParamSrc
                } else {
                    vertexParam6[v] = (x0 << vParamSrc) / zO
                }

                if zO < zTop {
                    vertexParam2[v] = yO << vParamSrc
                } else {
                    vertexParam2[v] = (yO << vParamSrc) / zO
                }

                vertXRot[v] = x0
                vertYRot[v] = yO
                vertZRot[v] = zO
            }
        } else {
            m_dc = false
        }
    }

    // MARK: - Lighting Methods

    /// Sets diffuse light parameters and recomputes lighting.
    /// Corresponds to Java setDiffuseLight (line 1176).
    func setDiffuseLight(param1: Int, param2: Int, dirX: Int, dirY: Int, dirZ: Int) {
        diffuseParam1 = 256 - param2 * 4
        diffuseParam2 = (64 - param1) * 16 + 128

        if !dontComputeDiffuse {
            diffuseDirX = dirX
            diffuseDirZ = dirZ
            diffuseDirY = dirY
            diffuseMag = Int(sqrt(Double(dirZ * dirZ + dirY * dirY + dirX * dirX)))
            computeDiffuse()
        }
    }

    /// Sets diffuse light and also sets face colors.
    /// Corresponds to Java setDiffuseLightAndColor (line 1199).
    func setDiffuseLightAndColor(dirX: Int, dirY: Int, dirZ: Int, p1: Int, p2: Int, allTransparent: Bool) {
        diffuseParam2 = (64 - p2) * 16 + 128
        diffuseParam1 = 256 - p1 * 4

        if !dontComputeDiffuse {
            for i in 0..<faceHead {
                if allTransparent {
                    faceDiffuseLight[i] = RSModel.TRANSPARENT
                } else {
                    faceDiffuseLight[i] = 0
                }
            }

            diffuseDirX = dirX
            diffuseDirZ = dirZ
            diffuseDirY = dirY
            diffuseMag = Int(sqrt(Double(dirY * dirY + dirX * dirX + dirZ * dirZ)))
            computeDiffuse()
        }
    }

    /// Sets diffuse direction and recomputes. Corresponds to Java setDiffuseDir (line 1157).
    func setDiffuseDir(dirX: Int, dirY: Int, dirZ: Int) {
        if !dontComputeDiffuse {
            diffuseDirZ = dirZ
            diffuseDirY = dirY
            diffuseDirX = dirX
            diffuseMag = Int(sqrt(Double(dirZ * dirZ + dirY * dirY + dirX * dirX)))
            computeDiffuse()
        }
    }

    // MARK: - Vertex Light Other

    /// Sets per-vertex additional light data. Corresponds to Java setVertexLightOther (line 1333).
    func setVertexLightOther(id: Int, val: Int) {
        vertLightOther[id] = Int8(truncatingIfNeeded: val)
    }

    // MARK: - Face / Vertex Removal

    /// Removes faces and/or vertices from the tail. Corresponds to Java removeFacesAndOrVerts (line 922).
    func removeFacesAndOrVerts(deleteVerts: Int, deleteFaces: Int) {
        faceHead -= deleteFaces
        if faceHead < 0 {
            faceHead = 0
        }
        vertHead -= deleteVerts
        if vertHead < 0 {
            vertHead = 0
        }
    }

    /// Resets face and vertex counts to zero. Corresponds to Java resetFaceVertHead (line 944).
    func resetFaceVertHead() {
        faceHead = 0
        vertHead = 0
    }

    // MARK: - copyModel

    /// Deep copy of this model. Corresponds to Java clone() (line 546).
    func copyModel() -> RSModel {
        let copy = RSModel(models: [self], modelCount: 1)
        copy.m_cb = self.m_cb
        copy.m_hc = self.m_hc
        return copy
    }

    /// Copy with flags. Corresponds to Java copyModel (line 301).
    func copyModel(m_v: Bool, m_c: Bool, noDiffuse: Bool, m_db: Bool) -> RSModel {
        let copy = RSModel(models: [self], modelCount: 1, m_v: m_v, m_c: m_c, dontComputeDiffuse: noDiffuse, m_db: m_db)
        copy.m_hc = self.m_hc
        return copy
    }

    // MARK: - addModels

    /// Merge vertices and faces from other models. Corresponds to Java addModels (line 314).
    private func addModels(offset: Int, models: [RSModel], var3: Bool, modelCount: Int) {
        var totalFaceCount = 0
        var totalVertCount = 0

        for i in 0..<modelCount {
            totalFaceCount += models[i].faceHead
            totalVertCount += models[i].vertHead
        }

        setFaceVertexCount(faceCount: totalFaceCount, vertexCount: totalVertCount, var3: 88)
        if var3 {
            self.faceParam1 = [[Int]](repeating: [], count: totalFaceCount)
        }

        for i in offset..<modelCount {
            let model = models[i]
            model.commitTransform()
            self.diffuseMag = model.diffuseMag
            self.diffuseDirX = model.diffuseDirX
            self.diffuseDirY = model.diffuseDirY
            self.diffuseParam2 = model.diffuseParam2
            self.diffuseDirZ = model.diffuseDirZ
            self.diffuseParam1 = model.diffuseParam1

            for f in 0..<model.faceHead {
                var newIndices = [Int](repeating: 0, count: model.faceIndexCount[f])
                let srcIndices = model.faceIndices[f]

                for v in 0..<model.faceIndexCount[f] {
                    newIndices[v] = insertVertex(x: model.vertX[srcIndices[v]],
                                                 y: model.vertY[srcIndices[v]],
                                                 z: model.vertZ[srcIndices[v]])
                }

                let fID = insertFace(indexCount: model.faceIndexCount[f], indices: newIndices,
                                     textureFront: model.faceTextureFront[f],
                                     textureBack: model.faceTextureBack[f])
                self.faceDiffuseLight[fID] = model.faceDiffuseLight[f]
                self.scenePolyNormalShift[fID] = model.scenePolyNormalShift[f]
                self.scenePolyNormalMagnitude[fID] = model.scenePolyNormalMagnitude[f]

                if var3 {
                    if modelCount <= 1 {
                        self.faceParam1[fID] = [Int](repeating: 0, count: model.faceParam1[f].count)
                        for j in 0..<model.faceParam1[f].count {
                            self.faceParam1[fID][j] = model.faceParam1[f][j]
                        }
                    } else {
                        self.faceParam1[fID] = [Int](repeating: 0, count: model.faceParam1[f].count + 1)
                        self.faceParam1[fID][0] = i
                        for j in 0..<model.faceParam1[f].count {
                            self.faceParam1[fID][1 + j] = model.faceParam1[f][j]
                        }
                    }
                }
            }
        }

        m_Yb = 1
    }

    // MARK: - copyFaceTo

    /// Copies a single face to another model. Corresponds to Java copyFaceTo (line 720).
    private func copyFaceTo(faceVert: [Int], dest: RSModel, faceVertCount: Int, srcFaceID: Int) {
        var nVerts = [Int](repeating: 0, count: faceVertCount)

        for i in 0..<faceVertCount {
            let vID = dest.insertVertex(x: vertX[faceVert[i]], y: vertY[faceVert[i]], z: vertZ[faceVert[i]])
            nVerts[i] = vID
            dest.vertDiffuseLight[vID] = vertDiffuseLight[faceVert[i]]
            dest.vertLightOther[vID] = vertLightOther[faceVert[i]]
        }

        let fID = dest.insertFace(indexCount: faceVertCount, indices: nVerts,
                                   textureFront: faceTextureFront[srcFaceID],
                                   textureBack: faceTextureBack[srcFaceID])
        if !dest.m_db && !m_db {
            dest.facePickIndex[fID] = facePickIndex[srcFaceID]
        }

        dest.faceDiffuseLight[fID] = faceDiffuseLight[srcFaceID]
        dest.scenePolyNormalShift[fID] = scenePolyNormalShift[srcFaceID]
        dest.scenePolyNormalMagnitude[fID] = scenePolyNormalMagnitude[srcFaceID]
    }

    // MARK: - divideModelByGrid

    /// Splits model into a grid of sub-models. Used by World to partition landscape into chunks.
    /// Corresponds to Java divideModelByGrid (line 772).
    func divideModelByGrid(_ xDim: Int, _ zGridSize: Int, _ outModels: Int, _ limitVertCount: Int,
                           _ xGridSize: Int, _ m_db: Bool) -> [RSModel?] {
        commitTransform()

        var outVertCount = [Int](repeating: 0, count: outModels)
        var outFaceCount = [Int](repeating: 0, count: outModels)

        // First pass: count verts and faces per grid cell
        for i in 0..<faceHead {
            var sumX = 0
            var sumZ = 0
            let faceVertCount = faceIndexCount[i]
            let faceVert = faceIndices[i]

            for j in 0..<faceVertCount {
                sumX += vertX[faceVert[j]]
                sumZ += vertZ[faceVert[j]]
            }

            let id = sumX / (faceVertCount * xGridSize) + sumZ / (zGridSize * faceVertCount) * xDim
            outVertCount[id] += faceVertCount
            outFaceCount[id] += 1
        }

        // Allocate output models
        var output = [RSModel?](repeating: nil, count: outModels)

        for i in 0..<outModels {
            if limitVertCount < outVertCount[i] {
                outVertCount[i] = limitVertCount
            }
            output[i] = RSModel(vertexLimit: outVertCount[i], faceLimit: outFaceCount[i],
                                m_v: true, m_c: true, dontComputeDiffuse: true, m_db: m_db, m_b: true)
            output[i]!.diffuseParam2 = self.diffuseParam2
            output[i]!.diffuseParam1 = self.diffuseParam1
        }

        // Second pass: copy faces to appropriate grid cell
        for f in 0..<faceHead {
            var sumX = 0
            var sumZ = 0
            let srcIndexCount = faceIndexCount[f]
            let srcIndices = faceIndices[f]

            for i in 0..<srcIndexCount {
                sumX += vertX[srcIndices[i]]
                sumZ += vertZ[srcIndices[i]]
            }

            let id = sumX / (srcIndexCount * xGridSize) + xDim * (sumZ / (zGridSize * srcIndexCount))
            copyFaceTo(faceVert: srcIndices, dest: output[id]!, faceVertCount: srcIndexCount, srcFaceID: f)
        }

        // Initialize screen-space arrays for each output model
        for i in 0..<outModels {
            output[i]!.clearRotDataAndParams26()
        }

        return output
    }

    // MARK: - computeBounds

    /// Compute minX/maxX/minY/maxY/minZ/maxZ from vertex data.
    func computeBounds() {
        resetTransformCache()
    }
}
