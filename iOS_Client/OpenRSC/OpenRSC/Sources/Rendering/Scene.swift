import Foundation

// MARK: - Scene
//
// Port of orsc.graphics.three.Scene from the Java desktop client.
// This is the central 3D rendering pipeline: camera setup, model transformation,
// polygon collection, depth sorting, and rasterization.
//
// Java `>>>` (unsigned right shift) is handled via unsignedRightShift32() or
// by casting through UInt32.

final class Scene {

    static let TRANSPARENT = 12345678

    // MARK: - Unsigned shift helper

    @inline(__always)
    private static func unsignedRightShift32(_ value: Int, _ shift: Int) -> Int {
        return Int(UInt32(truncatingIfNeeded: value) >> UInt32(shift))
    }

    // MARK: - Model storage

    var models: [RSModel?]
    var modelCount: Int = 0
    private let m_u: Int  // max model count

    // MARK: - Polygon storage

    var polygons: [RSPolygon]
    var m_zb: Int = 0  // current polygon count

    // MARK: - Pick / mouse hit state

    private var m_Ab: [RSModel?]
    private var m_qb: [Int]
    private let m_db: Int = 100
    private var m_cc: Int = 0
    private var m_K: Bool = false
    private var m_j: Int = 0
    private var m_Wb: Int = 0

    // MARK: - Model state tracking

    private var m_jb: [Int]

    // MARK: - Sprite billboard model

    var m_T: RSModel
    private var m_n: Int = 0  // sprite count

    // Per-sprite data
    private var m_gb: [Int]   // sprite index
    private var m_Fb: [Int]   // sprite y
    private var m_a: [Int]    // sprite z
    private var m_Ob: [Int]   // sprite x
    private var m_ob: [Int]   // sprite width
    private var m_Eb: [Int]   // sprite height
    private var m_Q: [Int]    // combat x offset

    // MARK: - Scanline buffer

    var m_x: [Scanline] = []

    // MARK: - Camera state

    var rot1024_off_x: Int = 0
    var rot1024_off_y: Int = 0
    var rot1024_off_z: Int = 0
    var cameraProjX: Int = 0
    var cameraProjY: Int = 0
    var cameraProjZ: Int = 0

    // MARK: - Viewport

    var m_A: Int = 0     // half-width
    var m_wb: Int = 192  // half-height
    var m_Nb: Int = 256  // scanline offset (y offset into scanline array)
    var m_vb: Int = 512  // scanline stride
    var m_Zb: Int = 256  // pixel offset

    // MARK: - Frustum / projection

    private let rot1024_zTop: Int = 5
    var rot1024_vp_src: Int = 8

    // MARK: - Scanline rasterizer state

    private var m_Xb: Int = 0  // scanline start row
    private var m_Cb: Int = 0  // scanline end row

    // MARK: - Fog

    var fogSmoothingStartDistance: Int = 10
    var fogZFalloff: Int = 20
    var fogLandscapeDistance: Int = 1000
    var fogEntityDistance: Int = 1000

    // MARK: - Graphics controller reference

    var graphics: GraphicsController

    // MARK: - Pixel data (Int32 for Shader compatibility)

    var pixelData: [Int32]

    // MARK: - Texture database

    var resourceDatabase: [[Int32]?] = []
    private var m_L: [[Int]?] = []      // palette data per texture
    private var m_g: [[UInt8]?] = []    // pixel indices per texture
    private var m_Hb: [Int] = []        // texture type (0=64, 1=128)
    private var m_S: [Bool] = []        // transparency flag
    private var m_D: [Int64] = []       // LRU timestamps
    private var m_cb: Int = 0           // texture count
    private var m_i: [[Int32]?] = []    // small texture pool (64x64)
    private var m_ec: [[Int32]?] = []   // large texture pool (128x128)

    // MARK: - Flat-fill color cache

    private var m_Ib: [[Int]]           // 50 * 256 color gradient LUT
    private let m_ib: Int = 50
    private var m_v: [Int]              // texture index -> m_Ib slot mapping
    private var m_H: [Int] = []         // current gradient LUT for flat fill

    // MARK: - Polygon normal scale

    private let polyNormalScale: Int = 4

    // MARK: - Interlace (kept for parity, always false on iOS)

    private var m_f: Bool = false

    // MARK: - Depth-sort helper state

    private var m_e: Int = 0
    private var m_eb: Int = 0

    // MARK: - Temp arrays for endScene polygon vertex assembly

    private var m_Qb = [Int](repeating: 0, count: 40)  // vertXRot
    private var m_Vb = [Int](repeating: 0, count: 40)  // vertYRot
    private var m_J  = [Int](repeating: 0, count: 40)  // vertZRot
    private var m_yb = [Int](repeating: 0, count: 40)  // screen X
    private var m_B  = [Int](repeating: 0, count: 40)  // screen Y
    private var m_r  = [Int](repeating: 0, count: 40)  // lighting

    // MARK: - Lighting

    var diffuseDirX: Int = 0
    var diffuseDirY: Int = 0
    var diffuseDirZ: Int = 0

    // MARK: - Init

    /// Corresponds to Java Scene(GraphicsController, int modelCapacity, int maxPolygonCount, int spriteCount)
    init(graphics: GraphicsController, modelCount modelCapacity: Int, polyCount maxPolygonCount: Int, spriteCount: Int) {
        self.graphics = graphics
        self.pixelData = [Int32](repeating: 0, count: graphics.width2 * graphics.height2)
        self.m_A = graphics.width2 / 2
        self.m_wb = graphics.height2 / 2
        self.m_u = modelCapacity
        self.models = [RSModel?](repeating: nil, count: modelCapacity + 1) // +1 for m_T
        self.m_jb = [Int](repeating: 0, count: modelCapacity)

        self.polygons = []
        self.polygons.reserveCapacity(maxPolygonCount)
        for _ in 0..<maxPolygonCount {
            self.polygons.append(RSPolygon())
        }

        self.m_T = RSModel(vertexCount: spriteCount * 2, faceCount: spriteCount)

        self.m_ob = [Int](repeating: 0, count: spriteCount)
        self.m_Eb = [Int](repeating: 0, count: spriteCount)
        self.m_Fb = [Int](repeating: 0, count: spriteCount)
        self.m_Ob = [Int](repeating: 0, count: spriteCount)
        self.m_Q  = [Int](repeating: 0, count: spriteCount)
        self.m_gb = [Int](repeating: 0, count: spriteCount)
        self.m_a  = [Int](repeating: 0, count: spriteCount)

        self.m_Ab = [RSModel?](repeating: nil, count: m_db)
        self.m_qb = [Int](repeating: 0, count: m_db)

        self.m_Ib = [[Int]](repeating: [Int](repeating: 0, count: 256), count: m_ib)
        self.m_v  = [Int](repeating: 0, count: m_ib)
    }

    // MARK: - Texture Database Setup

    /// Corresponds to Java setFrustum(int, int, int, int) — the texture database initializer.
    func initTextureDatabase(var1: Int, var2: Int, var3: Int, textureCount: Int) {
        m_L  = [[Int]?](repeating: nil, count: textureCount)
        m_g  = [[UInt8]?](repeating: nil, count: textureCount)
        resourceDatabase = [[Int32]?](repeating: nil, count: textureCount)
        m_i  = [[Int32]?](repeating: nil, count: var3)
        m_S  = [Bool](repeating: false, count: textureCount)
        m_cb = textureCount
        m_Hb = [Int](repeating: 0, count: textureCount)
        m_ec = [[Int32]?](repeating: nil, count: var2)
        m_D  = [Int64](repeating: 0, count: textureCount)
        // Java also sets MiscFunctions.world_s_e here; we use a local counter
    }

    /// LRU texture cache timestamp counter (replaces MiscFunctions.world_s_e).
    private var textureLRUCounter: Int64 = 0

    // MARK: - Load Texture

    /// Corresponds to Java loadTexture(int, int[], int, byte[]).
    func loadTexture(index: Int, palette: [Int], type: Int, data: [UInt8]) {
        m_g[index] = data
        m_L[index] = palette
        m_Hb[index] = type
        m_D[index] = 0
        m_S[index] = false
        resourceDatabase[index] = nil
        ensureTextureLoaded(index)
    }

    // MARK: - Ensure Texture Loaded (Java: b(int, boolean))

    /// Ensures the texture at `index` is loaded into resourceDatabase, evicting LRU if needed.
    private func ensureTextureLoaded(_ index: Int) {
        guard index >= 0 else { return }

        textureLRUCounter += 1
        m_D[index] = textureLRUCounter

        guard resourceDatabase[index] == nil else { return }

        if m_Hb[index] != 0 {
            // Large texture (128x128) -> 65536 entries
            for i in 0..<m_ec.count {
                if m_ec[i] == nil {
                    m_ec[i] = [Int32](repeating: 0, count: 65536)
                    resourceDatabase[index] = m_ec[i]
                    buildTexture(index)
                    return
                }
            }
            // Evict LRU large texture
            var minTime: Int64 = 1073741824
            var victim = 0
            for i in 0..<m_cb {
                if i != index && m_Hb[i] == 1 && resourceDatabase[i] != nil && m_D[i] < minTime {
                    minTime = m_D[i]
                    victim = i
                }
            }
            resourceDatabase[index] = resourceDatabase[victim]
            resourceDatabase[victim] = nil
            buildTexture(index)
        } else {
            // Small texture (64x64) -> 16384 entries
            for i in 0..<m_i.count {
                if m_i[i] == nil {
                    m_i[i] = [Int32](repeating: 0, count: 16384)
                    resourceDatabase[index] = m_i[i]
                    buildTexture(index)
                    return
                }
            }
            // Evict LRU small texture
            var minTime: Int64 = 1073741824
            var victim = 0
            for i in 0..<m_cb {
                if i != index && m_Hb[i] == 0 && resourceDatabase[i] != nil && m_D[i] < minTime {
                    minTime = m_D[i]
                    victim = i
                }
            }
            resourceDatabase[index] = resourceDatabase[victim]
            resourceDatabase[victim] = nil
            buildTexture(index)
        }
    }

    // MARK: - Build Texture (Java: setFrustum(int, byte))

    /// Decodes a texture from palette + pixel indices into resourceDatabase[index].
    private func buildTexture(_ index: Int) {
        guard let palette = m_L[index], let pixelIndices = m_g[index] else { return }
        guard var texData = resourceDatabase[index] else { return }

        let size: Int = m_Hb[index] != 0 ? 128 : 64
        var ptr = 0

        for row in 0..<size {
            for col in 0..<size {
                var color = palette[Int(pixelIndices[col + row * size]) & 255]
                color &= 0xF8F8FF  // 16316671
                if color != 0 {
                    if color == 0xF800FF {  // 16253183 — transparency marker
                        m_S[index] = true
                        color = 0
                    }
                } else {
                    color = 1
                }
                texData[ptr] = Int32(truncatingIfNeeded: color)
                ptr += 1
            }
        }

        // Generate darkened mip levels (3 additional copies)
        for i in 0..<ptr {
            let c = texData[i]
            texData[ptr + i]       = Int32(truncatingIfNeeded: Int(c) - Scene.unsignedRightShift32(Int(c), 3)) & 0xF8F8FF
            texData[ptr * 2 + i]   = Int32(truncatingIfNeeded: Int(c) - Scene.unsignedRightShift32(Int(c), 2)) & 0xF8F8FF
            texData[ptr * 3 + i]   = Int32(truncatingIfNeeded: Int(c) - Scene.unsignedRightShift32(Int(c), 3) - Scene.unsignedRightShift32(Int(c), 2)) & 0xF8F8FF
        }

        resourceDatabase[index] = texData
    }

    // MARK: - Resource To Color

    /// Converts a palette/texture index to an RGB color. Corresponds to Java resourceToColor.
    func resourceToColor(_ resource: Int) -> Int {
        if resource == Scene.TRANSPARENT {
            return 0
        }

        if resource >= 0 {
            ensureTextureLoaded(resource)
            if let tex = resourceDatabase[resource] {
                return Int(tex[0])
            }
            return 0
        } else {
            let r = -(resource + 1)
            let c3 = (r & 0x7C00) >> 10
            let c4 = (r & 0x3E0) >> 5
            let c5 = r & 0x1F
            return (c5 << 3) + (c4 << 11) + (c3 << 19)
        }
    }

    // MARK: - Camera

    /// Corresponds to Java setCamera. Computes camera transform from rotations and offset.
    func setCamera(centerX: Int, centerY: Int, centerZ: Int,
                   xRot: Int, yRot: Int, zRot: Int, offset: Int) {
        let zr = zRot & 1023
        let xr = xRot & 1023
        let yr = yRot & 1023

        cameraProjZ = 1024 - zr & 1023
        cameraProjX = 1024 - xr & 1023
        cameraProjY = 1024 - yr & 1023

        var offX = 0
        var offY = 0
        var offZ = offset

        if xr != 0 {
            let sin = Int(FastMath.trigTable_1024[xr])
            let cos = Int(FastMath.trigTable_1024[xr + 1024])
            let tmp = cos * offY - sin * offset >> 15
            offZ = sin * offY + offset * cos >> 15
            offY = tmp
        }

        if yr != 0 {
            let sin = Int(FastMath.trigTable_1024[yr])
            let cos = Int(FastMath.trigTable_1024[yr + 1024])
            let tmp = offX * cos + offZ * sin >> 15
            offZ = cos * offZ - sin * offX >> 15
            offX = tmp
        }

        if zr != 0 {
            let cos = Int(FastMath.trigTable_1024[zr + 1024])
            let sin = Int(FastMath.trigTable_1024[zr])
            let tmp = offX * cos + sin * offY >> 15
            offY = offY * cos - sin * offX >> 15
            offX = tmp
        }

        rot1024_off_z = centerZ - offZ
        rot1024_off_y = centerY - offY
        rot1024_off_x = centerX - offX
    }

    // MARK: - Set Midpoints

    /// Corresponds to Java setMidpoints.
    func setMidpoints(halfHeight: Int, var2: Bool, stride: Int, halfWidth: Int,
                      scanlineOffset: Int, vpSrc: Int, pixelOffset: Int) {
        rot1024_vp_src = vpSrc
        m_Zb = pixelOffset
        m_vb = stride
        m_Nb = scanlineOffset
        m_wb = halfHeight
        m_A = halfWidth

        m_x = [Scanline]()
        m_x.reserveCapacity(scanlineOffset + halfHeight)
        for _ in 0..<(scanlineOffset + halfHeight) {
            m_x.append(Scanline())
        }

        // Refresh pixel data reference
        syncPixelData()
    }

    /// Copy GraphicsController's UInt32 pixel data into our Int32 buffer.
    func syncPixelData() {
        let count = graphics.width2 * graphics.height2
        if pixelData.count != count {
            pixelData = [Int32](repeating: 0, count: count)
        }
        pixelData.withUnsafeMutableBufferPointer { dest in
            graphics.pixelData.withUnsafeBufferPointer { src in
                for i in 0..<count {
                    dest[i] = Int32(bitPattern: src[i])
                }
            }
        }
    }

    /// Copy our Int32 pixel data back to GraphicsController's UInt32 buffer.
    func flushPixelData() {
        let count = min(pixelData.count, graphics.pixelData.count)
        graphics.pixelData.withUnsafeMutableBufferPointer { dest in
            pixelData.withUnsafeBufferPointer { src in
                for i in 0..<count {
                    dest[i] = UInt32(bitPattern: src[i])
                }
            }
        }
    }

    // MARK: - Model Management

    /// Add a model to the scene. Corresponds to Java addModel.
    func addModel(_ mod: RSModel?) {
        guard let mod = mod else { return }
        if modelCount < m_u {
            m_jb[modelCount] = 0
            models[modelCount] = mod
            modelCount += 1
        }
    }

    /// Remove a model from the scene. Corresponds to Java removeModel.
    func removeModel(_ target: RSModel) {
        var i = 0
        while i < modelCount {
            if models[i] === target {
                modelCount -= 1
                var j = i
                while j < modelCount {
                    models[j] = models[j + 1]
                    m_jb[j] = m_jb[j + 1]
                    j += 1
                }
            }
            i += 1
        }
    }

    /// Remove all models. Corresponds to Java removeAllGameObjects.
    func removeAllGameObjects() {
        resetMTVertHead()
        for i in 0..<modelCount {
            models[i] = nil
        }
        modelCount = 0
    }

    private func resetMTVertHead() {
        m_n = 0
        m_T.resetFaceVertHead()
    }

    // MARK: - Sprite Management

    /// Register a billboard sprite. Corresponds to Java drawSprite (line 2532).
    @discardableResult
    func drawSprite(spriteIndex: Int, x: Int, pickIndex: Int, y: Int,
                    z: Int, width: Int, height: Int) -> Int {
        m_gb[m_n] = spriteIndex
        m_Fb[m_n] = y
        m_a[m_n] = z
        m_Ob[m_n] = x
        m_ob[m_n] = width
        m_Eb[m_n] = height
        m_Q[m_n] = 0

        let v0 = m_T.insertVertex2(x: x, y: y, z: z)
        let v1 = m_T.insertVertex2(x: x, y: y, z: z - height)
        let indices = [v0, v1]
        m_T.insertFace(indexCount: 2, indices: indices, textureFront: 0, textureBack: 0)
        m_T.facePickIndex[m_n] = pickIndex
        m_T.m_zb[m_n] = 0
        m_n += 1
        return m_n - 1
    }

    /// Remove sprites from m_T each frame. Corresponds to Java reduceSprites.
    func reduceSprites(_ count: Int) {
        m_n -= count
        m_T.removeFacesAndOrVerts(deleteVerts: count * 2, deleteFaces: count)
        if m_n < 0 {
            m_n = 0
        }
    }

    // MARK: - Set Face Sprite Local Player

    func setFaceSpriteLocalPlayer(_ var1: Int, _ var2: Int) {
        m_T.m_zb[var2] = 1
    }

    // MARK: - Set Combat X Offset

    func setCombatXOffset(_ var2: Int, _ var3: Int) {
        m_Q[var2] = var3
    }

    // MARK: - Mouse / Picking

    func setMouseLoc(var1: Int, x: Int, y: Int) {
        m_K = true
        m_j = x - m_Zb
        m_Wb = y
        m_cc = var1
    }

    func getPickedModels() -> [RSModel?] {
        return m_Ab
    }

    func getPickedFaces() -> [Int] {
        return m_qb
    }

    func getPickCount() -> Int {
        return m_cc
    }

    // MARK: - Diffuse Light Direction

    /// Corresponds to Java setDiffuseDir.
    func setDiffuseDir(x: Int, y: Int, z: Int) {
        var dx = x, dy = y, dz = z
        if dx == 0 && dy == 0 && dz == 0 {
            dx = 32
        }
        for i in 0..<modelCount {
            models[i]?.setDiffuseDir(dirX: dx, dirY: dy, dirZ: dz)
        }
    }

    /// Corresponds to Java setFrustum(int, int, int, int, int, int) — the light setter.
    func setDiffuseLight(dirZ: Int, param1: Int, fromModel: Int, dirX: Int, dirY: Int, param2: Int) {
        var dx = dirX, dz = dirZ
        if dx == 0 && dz == 0 && dirZ == 0 {
            dx = 32
        }
        for i in fromModel..<modelCount {
            models[i]?.setDiffuseLight(param1: param1, param2: param2, dirX: dx, dirY: dirY, dirZ: dz)
        }
    }

    // MARK: - Frustum Point Test (Java: setFrustum(int x, int y, int z, boolean))

    /// Transforms a point through the inverse camera rotation and updates RSModel frustum bounds.
    private func frustumPointTest(x: Int, y: Int, z: Int) {
        let projX = 1024 - cameraProjX & 1023
        let projY = 1024 - cameraProjY & 1023
        let projZ = 1024 - cameraProjZ & 1023

        var px = x, py = y, pz = z

        if projZ != 0 {
            let sin = Int(FastMath.trigTable_1024[projZ])
            let cos = Int(FastMath.trigTable_1024[1024 + projZ])
            let tmp = cos * py + sin * pz >> 15
            pz = pz * cos - sin * py >> 15
            py = tmp
        }

        if projX != 0 {
            let cos = Int(FastMath.trigTable_1024[1024 + projX])
            let sin = Int(FastMath.trigTable_1024[projX])
            let tmp = pz * cos - sin * px >> 15
            px = cos * px + sin * pz >> 15
            pz = tmp
        }

        if projY != 0 {
            let sin = Int(FastMath.trigTable_1024[projY])
            let cos = Int(FastMath.trigTable_1024[1024 + projY])
            let tmp = sin * px + py * cos >> 15
            px = cos * px - sin * py >> 15
            py = tmp
        }

        if px > RSModel.frustumMinX { RSModel.frustumMinX = px }
        if pz < RSModel.frustumFarZ { RSModel.frustumFarZ = pz }
        if py > RSModel.frustumMinY { RSModel.frustumMinY = py }
        if pz > RSModel.frustumNearZ { RSModel.frustumNearZ = pz }
        if px < RSModel.frustumMaxX { RSModel.frustumMaxX = px }
        if py < RSModel.frustumMaxY { RSModel.frustumMaxY = py }
    }

    // MARK: - Compute Polygon (Java: computePolygon)

    /// Computes polygon normal, orientation, and screen-space bounds.
    private func computePolygon(_ polyID: Int) {
        let poly = polygons[polyID]
        guard let model = poly.model else { return }
        let face = poly.faceID
        let index = model.faceIndices[face]
        let indexCount = model.faceIndexCount[face]
        var fParam4 = model.scenePolyNormalShift[face]

        let v0X = model.vertXRot[index[0]]
        let v0Y = model.vertYRot[index[0]]
        let v0Z = model.vertZRot[index[0]]

        let v1DX = model.vertXRot[index[1]] - v0X
        let v1DY = model.vertYRot[index[1]] - v0Y
        let v1DZ = model.vertZRot[index[1]] - v0Z

        let v2DX = model.vertXRot[index[2]] - v0X
        let v2DY = model.vertYRot[index[2]] - v0Y
        let v2DZ = model.vertZRot[index[2]] - v0Z

        var normX = v2DZ * v1DY - v1DZ * v2DY
        var normY = v2DX * v1DZ - v1DX * v2DZ
        var normZ = v1DX * v2DY - v2DX * v1DY

        if fParam4 != -1 {
            normZ >>= fParam4
            normX >>= fParam4
            normY >>= fParam4
        } else {
            fParam4 = 0
            while normX > 25000 || normY > 25000 || normZ > 25000 ||
                  normX < -25000 || normY < -25000 || normZ < -25000 {
                normX >>= 1
                normY >>= 1
                normZ >>= 1
                fParam4 += 1
            }
            model.scenePolyNormalShift[face] = fParam4
            model.scenePolyNormalMagnitude[face] = Int(Double(polyNormalScale) *
                sqrt(Double(normZ * normZ + normY * normY + normX * normX)))
        }

        poly.normalX = normX
        poly.normalY = normY
        poly.normalZ = normZ
        poly.orientation = normX * v0X + normY * v0Y + normZ * v0Z

        var minZ = model.vertZRot[index[0]]
        var maxZ = minZ
        var minP6 = model.vertexParam6[index[0]]
        var maxP6 = minP6
        var minP2 = model.vertexParam2[index[0]]
        var maxP2 = minP2

        for v in 1..<indexCount {
            var vvt = model.vertZRot[index[v]]
            if vvt > maxZ { maxZ = vvt }
            else if vvt < minZ { minZ = vvt }

            vvt = model.vertexParam6[index[v]]
            if vvt > maxP6 { maxP6 = vvt }
            else if vvt < minP6 { minP6 = vvt }

            vvt = model.vertexParam2[index[v]]
            if vvt > maxP2 { maxP2 = vvt }
            else if vvt < minP2 { minP2 = vvt }
        }

        poly.minP6 = minP6
        poly.maxP6 = maxP6
        poly.maxP2 = maxP2
        poly.maxZ = maxZ
        poly.minP2 = minP2
        poly.minZ = minZ
    }

    // MARK: - Compute Sprite Polygon (Java: b(int, int))

    /// Computes screen-space bounds for a sprite polygon (2-vertex face).
    private func computeSpritePolygon(_ polyID: Int) {
        let poly = polygons[polyID]
        guard let model = poly.model else { return }
        let face = poly.faceID
        let index = model.faceIndices[face]

        model.scenePolyNormalMagnitude[face] = 1
        model.scenePolyNormalShift[face] = 0
        poly.normalX = 0
        poly.normalY = 0
        poly.normalZ = 1

        let v0X = model.vertXRot[index[0]]
        let v0Y = model.vertYRot[index[0]]
        let v0Z = model.vertZRot[index[0]]
        poly.orientation = v0Z

        var minZ = v0Z
        var maxZ = v0Z
        var minP6 = model.vertexParam6[index[0]]
        var maxP6 = minP6

        if model.vertexParam6[index[1]] >= minP6 {
            maxP6 = model.vertexParam6[index[1]]
        } else {
            minP6 = model.vertexParam6[index[1]]
        }

        var minP2 = model.vertexParam2[index[1]]
        var maxP2 = model.vertexParam2[index[0]]

        let vz1 = model.vertZRot[index[1]]
        if vz1 > maxZ { maxZ = vz1 }
        else if vz1 < minZ { minZ = vz1 }

        // Re-check vertexParam2 for vertex 1
        let p2v1 = model.vertexParam2[index[1]]
        if maxP2 < p2v1 {
            maxP2 = p2v1
        } else if p2v1 < minP2 {
            minP2 = p2v1
        }

        poly.maxP6 = maxP6 + 20
        poly.minP6 = minP6 - 20

        poly.maxZ = maxZ
        poly.minZ = minZ
        poly.maxP2 = maxP2
        poly.minP2 = minP2
    }

    // MARK: - Polygon Hit Tests

    /// Tests if polyA's vertices are all on one side of polyB's plane (and vice versa).
    /// Returns true if no overlap. Corresponds to Java polygonHit1.
    private func polygonHit1(_ polyA: RSPolygon, _ polyB: RSPolygon) -> Bool {
        guard let modelA = polyA.model, let modelB = polyB.model else { return true }
        let faceA = polyA.faceID
        let faceB = polyB.faceID
        let indexA = modelA.faceIndices[faceA]
        let indexB = modelB.faceIndices[faceB]
        let indexCountA = modelA.faceIndexCount[faceA]
        let indexCountB = modelB.faceIndexCount[faceB]

        let bv0x = modelB.vertXRot[indexB[0]]
        let bv0y = modelB.vertYRot[indexB[0]]
        let bv0z = modelB.vertZRot[indexB[0]]
        var bnx = polyB.normalX
        var bny = polyB.normalY
        var bnz = polyB.normalZ
        var bfNormMag = modelB.scenePolyNormalMagnitude[faceB]
        var hit = false
        var orientation = polyB.orientation

        for v in 0..<indexCountA {
            let vID = indexA[v]
            let dot = bny * (bv0y - modelA.vertYRot[vID]) +
                      (bv0x - modelA.vertXRot[vID]) * bnx +
                      (bv0z - modelA.vertZRot[vID]) * bnz
            if (-bfNormMag > dot && orientation < 0) || (dot > bfNormMag && orientation > 0) {
                hit = true
                break
            }
        }

        if !hit { return true }

        // Test other direction
        let av0x = modelA.vertXRot[indexA[0]]
        let av0y = modelA.vertYRot[indexA[0]]
        let av0z = modelA.vertZRot[indexA[0]]
        bnx = polyA.normalX
        bny = polyA.normalY
        bnz = polyA.normalZ
        bfNormMag = modelA.scenePolyNormalMagnitude[faceA]
        hit = false
        orientation = polyA.orientation

        for v in 0..<indexCountB {
            let vID = indexB[v]
            let dot = bnx * (av0x - modelB.vertXRot[vID]) -
                      (-(bny * (av0y - modelB.vertYRot[vID])) - (av0z - modelB.vertZRot[vID]) * bnz)
            if (dot < -bfNormMag && orientation > 0) || (bfNormMag < dot && orientation < 0) {
                hit = true
                break
            }
        }

        return !hit
    }

    /// Extended overlap test with screen-space AABB pre-check. Corresponds to Java polygonHit2.
    private func polygonHit2(_ polyA: RSPolygon, _ polyB: RSPolygon) -> Bool {
        if polyB.minP6 >= polyA.maxP6 { return true }
        if polyA.minP6 >= polyB.maxP6 { return true }
        if polyA.maxP2 <= polyB.minP2 { return true }
        if polyB.maxP2 <= polyA.minP2 { return true }
        if polyA.maxZ <= polyB.minZ { return true }
        if polyB.maxZ < polyA.minZ { return false }

        guard let modelB = polyB.model, let modelA = polyA.model else { return true }
        let faceB = polyB.faceID
        let faceA = polyA.faceID
        let indexB = modelB.faceIndices[faceB]
        let indexA = modelA.faceIndices[faceA]
        let countB = modelB.faceIndexCount[faceB]
        let countA = modelA.faceIndexCount[faceA]

        // Test polyB vertices against polyA's plane
        let av0x = modelA.vertXRot[indexA[0]]
        let av0y = modelA.vertYRot[indexA[0]]
        let av0z = modelA.vertZRot[indexA[0]]
        var nx = polyA.normalX
        var ny = polyA.normalY
        var nz = polyA.normalZ
        var normMag = modelA.scenePolyNormalMagnitude[faceA]
        var orient = polyA.orientation
        var hit = false

        for v in 0..<countB {
            let vID = indexB[v]
            let dot = (av0z - modelB.vertZRot[vID]) * nz +
                      (av0y - modelB.vertYRot[vID]) * ny +
                      nx * (av0x - modelB.vertXRot[vID])
            if (dot < -normMag && orient < 0) || (dot > normMag && orient > 0) {
                hit = true
                break
            }
        }
        if !hit { return true }

        // Test polyA vertices against polyB's plane
        hit = false
        orient = polyB.orientation
        let bv0y = modelB.vertYRot[indexB[0]]
        let bv0x = modelB.vertXRot[indexB[0]]
        normMag = modelB.scenePolyNormalMagnitude[faceB]
        let bv0z = modelB.vertZRot[indexB[0]]
        ny = polyB.normalY
        nz = polyB.normalZ
        nx = polyB.normalX

        for v in 0..<countA {
            let vID = indexA[v]
            let dot = (bv0z - modelA.vertZRot[vID]) * nz +
                      (bv0x - modelA.vertXRot[vID]) * nx +
                      (bv0y - modelA.vertYRot[vID]) * ny
            if (-normMag > dot && orient > 0) || (normMag < dot && orient < 0) {
                hit = true
                break
            }
        }
        if !hit { return true }

        // Edge-based overlap test
        var p6A: [Int]
        var p2A: [Int]
        if countB != 2 {
            p6A = [Int](repeating: 0, count: countB)
            p2A = [Int](repeating: 0, count: countB)
            for i in 0..<countB {
                let idx = indexB[i]
                p6A[i] = modelB.vertexParam6[idx]
                p2A[i] = modelB.vertexParam2[idx]
            }
        } else {
            p6A = [Int](repeating: 0, count: 4)
            p2A = [Int](repeating: 0, count: 4)
            let i0 = indexB[0], i1 = indexB[1]
            p6A[0] = modelB.vertexParam6[i0] - 20
            p6A[1] = modelB.vertexParam6[i1] - 20
            p6A[2] = modelB.vertexParam6[i1] + 20
            p6A[3] = modelB.vertexParam6[i0] + 20
            p2A[0] = modelB.vertexParam2[i0]
            p2A[3] = p2A[0]
            p2A[1] = modelB.vertexParam2[i1]
            p2A[2] = p2A[1]
        }

        var p6B: [Int]
        var p2B: [Int]
        if countA != 2 {
            p6B = [Int](repeating: 0, count: countA)
            p2B = [Int](repeating: 0, count: countA)
            for i in 0..<countA {
                let idx = indexA[i]
                p6B[i] = modelA.vertexParam6[idx]
                p2B[i] = modelA.vertexParam2[idx]
            }
        } else {
            p6B = [Int](repeating: 0, count: 4)
            p2B = [Int](repeating: 0, count: 4)
            let i0 = indexA[0], i1 = indexA[1]
            p6B[0] = modelA.vertexParam6[i0] - 20
            p6B[1] = modelA.vertexParam6[i1] - 20
            p6B[2] = modelA.vertexParam6[i1] + 20
            p6B[3] = modelA.vertexParam6[i0] + 20
            p2B[0] = modelA.vertexParam2[i0]
            p2B[3] = p2B[0]
            p2B[1] = modelA.vertexParam2[i1]
            p2B[2] = p2B[1]
        }

        return !frustumEdgeTest(p6B, p2B, p6A, p2A, 1)
    }

    // MARK: - Boolean Combinatoric Helpers

    private func booleanCombinatoric(_ var2: Bool, _ var3: Int, _ var4: Int, _ var5: Int, _ var6: Int) -> Bool {
        if (!var2 || var5 > var6) && var5 >= var6 {
            if var5 < var4 { return true }
            if var3 < var6 { return true }
            if var3 < var4 { return true }
            return var2
        } else {
            if var5 > var4 { return true }
            if var3 > var6 { return true }
            if var3 > var4 { return true }
            return !var2
        }
    }

    private func booleanCombinatoric2(_ var1: Int, _ var2: Bool, _ var3: Int, _ var5: Int) -> Bool {
        if (!var2 || var3 > var1) && var3 >= var1 {
            return var5 < var1 ? true : var2
        } else {
            return var1 >= var5 ? !var2 : true
        }
    }

    private func booleanCombinatoric3(_ var1: Int, _ var3: Int, _ var4: Int, _ var5: Int, _ var6: Int) -> Int {
        return var4 == var1 ? var6 : (var5 - var6) * (var3 - var1) / (var4 - var1) + var6
    }

    // MARK: - Frustum Edge Test (Java: setFrustum(int[], int[], int[], int[], int))

    /// Complex edge-based polygon overlap test. Returns true if polygons overlap.
    private func frustumEdgeTest(_ var1: [Int], _ var2: [Int], _ var3: [Int], _ var4: [Int], _ var5: Int) -> Bool {
        let var6 = var3.count
        let var7 = var1.count
        var var16: Int = 0
        var var8 = 0
        var var18 = var2[0]
        var var20 = var18
        var var10 = 0

        for i in 1..<var6 {
            if var2[i] >= var18 {
                if var2[i] > var20 { var20 = var2[i] }
            } else {
                var8 = i
                var18 = var2[i]
            }
        }

        var var19 = var4[0]
        var var21 = var19

        for i in var5..<var7 {
            if var4[i] >= var19 {
                if var21 < var4[i] { var21 = var4[i] }
            } else {
                var19 = var4[i]
                var10 = i
            }
        }

        if var19 < var20 {
            if var21 <= var18 { return false }

            var var9: Int = 0
            var var11: Int = 0
            var var12: Int = 0
            var var13: Int = 0
            var var14: Int = 0
            var var15: Int = 0
            var var17: Bool = false

            if var4[var10] > var2[var8] {
                var9 = var8
                while var2[var8] < var4[var10] {
                    var8 = (var8 - 1 + var6) % var6
                }
                while var2[var9] < var4[var10] {
                    var9 = (1 + var9) % var6
                }

                var12 = booleanCombinatoric3(var2[(var8 + 1) % var6], var4[var10], var2[var8],
                                             var3[var8], var3[(1 + var8) % var6])
                var13 = booleanCombinatoric3(var2[(var6 + (var9 - 1)) % var6], var4[var10],
                                             var2[var9], var3[var9], var3[(var6 - 1 + var9) % var6])
                var14 = var1[var10]
                var17 = var12 < var14 || var13 < var14
                if booleanCombinatoric2(var14, var17, var12, var13) { return true }

                var11 = (var10 + 1) % var7
                var10 = (var10 + var7 - 1) % var7
                if var8 == var9 { var16 = 1 }
            } else {
                var11 = var10
                while var2[var8] > var4[var10] {
                    var10 = (var10 + var7 - 1) % var7
                }
                var12 = var3[var8]
                while var2[var8] > var4[var11] {
                    var11 = (var11 + 1) % var7
                }

                var14 = booleanCombinatoric3(var4[(var10 + 1) % var7], var2[var8], var4[var10],
                                             var1[var10], var1[(var10 + 1) % var7])
                var15 = booleanCombinatoric3(var4[(var7 + (var11 - 1)) % var7], var2[var8],
                                             var4[var11], var1[var11], var1[(var11 - 1 + var7) % var7])
                var17 = var12 < var14 || var12 < var15
                if booleanCombinatoric2(var12, !var17, var14, var15) { return true }

                var9 = (1 + var8) % var6
                var8 = (var6 + (var8 - 1)) % var6
                if var10 == var11 { var16 = 2 }
            }

            // Main loop
            while var16 == 0 {
                if var2[var8] >= var2[var9] {
                    if var2[var9] >= var4[var10] {
                        if var4[var10] >= var4[var11] {
                            var12 = booleanCombinatoric3(var2[(var8 + 1) % var6], var4[var11], var2[var8], var3[var8], var3[(1 + var8) % var6])
                            var13 = booleanCombinatoric3(var2[(var9 - 1 + var6) % var6], var4[var11], var2[var9], var3[var9], var3[(var6 + (var9 - 1)) % var6])
                            var14 = booleanCombinatoric3(var4[(1 + var10) % var7], var4[var11], var4[var10], var1[var10], var1[(var10 + 1) % var7])
                            var15 = var1[var11]
                            if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                            var11 = (1 + var11) % var7
                            if var11 == var10 { var16 = 2 }
                        } else {
                            var12 = booleanCombinatoric3(var2[(var8 + 1) % var6], var4[var10], var2[var8], var3[var8], var3[(1 + var8) % var6])
                            var13 = booleanCombinatoric3(var2[(var9 + var6 - 1) % var6], var4[var10], var2[var9], var3[var9], var3[(var6 - 1 + var9) % var6])
                            var14 = var1[var10]
                            var15 = booleanCombinatoric3(var4[(var7 + (var11 - 1)) % var7], var4[var10], var4[var11], var1[var11], var1[(var11 - 1 + var7) % var7])
                            if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                            var10 = (var10 - 1 + var7) % var7
                            if var11 == var10 { var16 = 2 }
                        }
                    } else if var2[var9] < var4[var11] {
                        var12 = booleanCombinatoric3(var2[(var8 + 1) % var6], var2[var9], var2[var8], var3[var8], var3[(1 + var8) % var6])
                        var13 = var3[var9]
                        var14 = booleanCombinatoric3(var4[(var10 + 1) % var7], var2[var9], var4[var10], var1[var10], var1[(1 + var10) % var7])
                        var15 = booleanCombinatoric3(var4[(var11 - 1 + var7) % var7], var2[var9], var4[var11], var1[var11], var1[(var11 - 1 + var7) % var7])
                        if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                        var9 = (var9 + 1) % var6
                        if var8 == var9 { var16 = 1 }
                    } else {
                        var12 = booleanCombinatoric3(var2[(var8 + 1) % var6], var4[var11], var2[var8], var3[var8], var3[(var8 + 1) % var6])
                        var13 = booleanCombinatoric3(var2[(var6 + var9 - 1) % var6], var4[var11], var2[var9], var3[var9], var3[(var6 - 1 + var9) % var6])
                        var14 = booleanCombinatoric3(var4[(var10 + 1) % var7], var4[var11], var4[var10], var1[var10], var1[(var10 + 1) % var7])
                        var15 = var1[var11]
                        if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                        var11 = (var11 + 1) % var7
                        if var10 == var11 { var16 = 2 }
                    }
                } else if var4[var10] > var2[var8] {
                    if var2[var8] >= var4[var11] {
                        var12 = booleanCombinatoric3(var2[(1 + var8) % var6], var4[var11], var2[var8], var3[var8], var3[(1 + var8) % var6])
                        var13 = booleanCombinatoric3(var2[(var6 + (var9 - 1)) % var6], var4[var11], var2[var9], var3[var9], var3[(var6 + (var9 - 1)) % var6])
                        var14 = booleanCombinatoric3(var4[(var10 + 1) % var7], var4[var11], var4[var10], var1[var10], var1[(1 + var10) % var7])
                        var15 = var1[var11]
                        if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                        var11 = (1 + var11) % var7
                        if var10 == var11 { var16 = 2 }
                    } else {
                        var12 = var3[var8]
                        var13 = booleanCombinatoric3(var2[(var9 + (var6 - 1)) % var6], var2[var8], var2[var9], var3[var9], var3[(var9 + var6 - 1) % var6])
                        var14 = booleanCombinatoric3(var4[(1 + var10) % var7], var2[var8], var4[var10], var1[var10], var1[(1 + var10) % var7])
                        var15 = booleanCombinatoric3(var4[(var7 - 1 + var11) % var7], var2[var8], var4[var11], var1[var11], var1[(var7 + (var11 - 1)) % var7])
                        if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                        var8 = (var6 + (var8 - 1)) % var6
                        if var8 == var9 { var16 = 1 }
                    }
                } else if var4[var10] < var4[var11] {
                    var12 = booleanCombinatoric3(var2[(1 + var8) % var6], var4[var10], var2[var8], var3[var8], var3[(1 + var8) % var6])
                    var13 = booleanCombinatoric3(var2[(var6 + (var9 - 1)) % var6], var4[var10], var2[var9], var3[var9], var3[(var6 - 1 + var9) % var6])
                    var14 = var1[var10]
                    var15 = booleanCombinatoric3(var4[(var7 + (var11 - 1)) % var7], var4[var10], var4[var11], var1[var11], var1[(var7 + var11 - 1) % var7])
                    if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                    var10 = (var7 + var10 - 1) % var7
                    if var11 == var10 { var16 = 2 }
                } else {
                    var12 = booleanCombinatoric3(var2[(var8 + 1) % var6], var4[var11], var2[var8], var3[var8], var3[(var8 + 1) % var6])
                    var13 = booleanCombinatoric3(var2[(var9 + var6 - 1) % var6], var4[var11], var2[var9], var3[var9], var3[(var6 + (var9 - 1)) % var6])
                    var14 = booleanCombinatoric3(var4[(var10 + 1) % var7], var4[var11], var4[var10], var1[var10], var1[(1 + var10) % var7])
                    var15 = var1[var11]
                    if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                    var11 = (var11 + 1) % var7
                    if var10 == var11 { var16 = 2 }
                }
            }

            // Phase 1 loop
            while var16 == 1 {
                if var2[var8] >= var4[var10] {
                    if var4[var10] < var4[var11] {
                        var12 = booleanCombinatoric3(var2[(1 + var8) % var6], var4[var10], var2[var8], var3[var8], var3[(var8 + 1) % var6])
                        var13 = booleanCombinatoric3(var2[(var9 - 1 + var6) % var6], var4[var10], var2[var9], var3[var9], var3[(var9 - 1 + var6) % var6])
                        var14 = var1[var10]
                        var15 = booleanCombinatoric3(var4[(var11 - 1 + var7) % var7], var4[var10], var4[var11], var1[var11], var1[(var11 + (var7 - 1)) % var7])
                        if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                        var10 = (var10 + (var7 - 1)) % var7
                        if var10 == var11 { var16 = 0 }
                    } else {
                        var12 = booleanCombinatoric3(var2[(1 + var8) % var6], var4[var11], var2[var8], var3[var8], var3[(1 + var8) % var6])
                        var13 = booleanCombinatoric3(var2[(var6 + var9 - 1) % var6], var4[var11], var2[var9], var3[var9], var3[(var9 + (var6 - 1)) % var6])
                        var14 = booleanCombinatoric3(var4[(var10 + 1) % var7], var4[var11], var4[var10], var1[var10], var1[(1 + var10) % var7])
                        var15 = var1[var11]
                        if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                        var11 = (1 + var11) % var7
                        if var10 == var11 { var16 = 0 }
                    }
                } else {
                    if var4[var11] > var2[var8] {
                        var12 = var3[var8]
                        var14 = booleanCombinatoric3(var4[(var10 + 1) % var7], var2[var8], var4[var10], var1[var10], var1[(1 + var10) % var7])
                        var15 = booleanCombinatoric3(var4[(var11 - 1 + var7) % var7], var2[var8], var4[var11], var1[var11], var1[(var7 + (var11 - 1)) % var7])
                        return booleanCombinatoric2(var12, !var17, var14, var15)
                    }

                    var12 = booleanCombinatoric3(var2[(1 + var8) % var6], var4[var11], var2[var8], var3[var8], var3[(1 + var8) % var6])
                    var13 = booleanCombinatoric3(var2[(var9 + var6 - 1) % var6], var4[var11], var2[var9], var3[var9], var3[(var9 + var6 - 1) % var6])
                    var14 = booleanCombinatoric3(var4[(1 + var10) % var7], var4[var11], var4[var10], var1[var10], var1[(1 + var10) % var7])
                    var15 = var1[var11]
                    if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                    var11 = (1 + var11) % var7
                    if var10 == var11 { var16 = 0 }
                }
            }

            // Phase 2 loop
            while var16 == 2 {
                if var4[var10] < var2[var8] {
                    if var4[var10] < var2[var9] {
                        var12 = booleanCombinatoric3(var2[(var8 + 1) % var6], var4[var10], var2[var8], var3[var8], var3[(var8 + 1) % var6])
                        var13 = booleanCombinatoric3(var2[(var9 - 1 + var6) % var6], var4[var10], var2[var9], var3[var9], var3[(var6 - 1 + var9) % var6])
                        var14 = var1[var10]
                        return booleanCombinatoric2(var14, var17, var12, var13)
                    }

                    var12 = booleanCombinatoric3(var2[(1 + var8) % var6], var2[var9], var2[var8], var3[var8], var3[(1 + var8) % var6])
                    var13 = var3[var9]
                    var14 = booleanCombinatoric3(var4[(1 + var10) % var7], var2[var9], var4[var10], var1[var10], var1[(var10 + 1) % var7])
                    var15 = booleanCombinatoric3(var4[(var11 - 1 + var7) % var7], var2[var9], var4[var11], var1[var11], var1[(var11 + var7 - 1) % var7])
                    if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                    var9 = (1 + var9) % var6
                    if var8 == var9 { var16 = 0 }
                } else if var2[var8] >= var2[var9] {
                    var12 = booleanCombinatoric3(var2[(var8 + 1) % var6], var2[var9], var2[var8], var3[var8], var3[(1 + var8) % var6])
                    var13 = var3[var9]
                    var14 = booleanCombinatoric3(var4[(1 + var10) % var7], var2[var9], var4[var10], var1[var10], var1[(1 + var10) % var7])
                    var15 = booleanCombinatoric3(var4[(var11 - 1 + var7) % var7], var2[var9], var4[var11], var1[var11], var1[(var11 + var7 - 1) % var7])
                    if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                    var9 = (1 + var9) % var6
                    if var8 == var9 { var16 = 0 }
                } else {
                    var12 = var3[var8]
                    var13 = booleanCombinatoric3(var2[(var9 + var6 - 1) % var6], var2[var8], var2[var9], var3[var9], var3[(var6 + var9 - 1) % var6])
                    var14 = booleanCombinatoric3(var4[(var10 + 1) % var7], var2[var8], var4[var10], var1[var10], var1[(var10 + 1) % var7])
                    var15 = booleanCombinatoric3(var4[(var11 + (var7 - 1)) % var7], var2[var8], var4[var11], var1[var11], var1[(var7 + var11 - 1) % var7])
                    if booleanCombinatoric(var17, var13, var15, var12, var14) { return true }
                    var8 = (var6 + var8 - 1) % var6
                    if var9 == var8 { var16 = 0 }
                }
            }

            // Final test
            if var4[var10] <= var2[var8] {
                var12 = booleanCombinatoric3(var2[(1 + var8) % var6], var4[var10], var2[var8], var3[var8], var3[(var8 + 1) % var6])
                var13 = booleanCombinatoric3(var2[(var9 - 1 + var6) % var6], var4[var10], var2[var9], var3[var9], var3[(var6 + (var9 - 1)) % var6])
                var14 = var1[var10]
                return booleanCombinatoric2(var14, var17, var12, var13)
            } else {
                var12 = var3[var8]
                var14 = booleanCombinatoric3(var4[(1 + var10) % var7], var2[var8], var4[var10], var1[var10], var1[(var10 + 1) % var7])
                var15 = booleanCombinatoric3(var4[(var7 + (var11 - 1)) % var7], var2[var8], var4[var11], var1[var11], var1[(var7 - 1 + var11) % var7])
                return booleanCombinatoric2(var12, !var17, var14, var15)
            }
        } else {
            return false
        }
    }

    // MARK: - Depth Sort (Quicksort) — Java: setFrustum(int, int, Polygon[], int)

    /// Quicksort polygons by m_t (depth). Recursive.
    private func depthSortQuicksort(_ lo: Int, _ hi: Int, _ arr: inout [RSPolygon]) {
        guard hi > lo else { return }
        let mid = (hi + lo) / 2
        let pivot = arr[mid]
        arr[mid] = arr[lo]
        arr[lo] = pivot
        let pivotVal = pivot.m_t

        var left = lo - 1
        var right = hi + 1

        while right > left {
            repeat { left += 1 } while arr[left].m_t > pivotVal
            repeat { right -= 1 } while pivotVal > arr[right].m_t

            if right > left {
                let tmp = arr[left]
                arr[left] = arr[right]
                arr[right] = tmp
            }
        }

        depthSortQuicksort(lo, right, &arr)
        depthSortQuicksort(right + 1, hi, &arr)
    }

    // MARK: - Depth Sort (Overlap Resolution) — Java: setFrustum(int, Polygon[], int, byte)

    /// Resolves depth ordering when quicksort leaves ambiguous overlapping polygons.
    private func depthSortResolve(_ startIdx: Int, _ arr: inout [RSPolygon], _ endIdx: Int) -> Bool {
        var start = startIdx
        var end = endIdx

        while true {
            let poly = arr[start]
            for i in (start + 1)...end {
                let other = arr[i]
                if !polygonHit2(other, poly) { break }

                arr[start] = other
                start = i
                arr[i] = poly
                if i == end {
                    m_eb = i - 1
                    m_e = i
                    return true
                }
            }

            let last = arr[end]
            for i in stride(from: end - 1, through: start, by: -1) {
                let other = arr[i]
                if !polygonHit2(other, last) { break }

                arr[end] = other
                arr[i] = last
                end = i
                if i == start {
                    m_eb = i
                    m_e = i + 1
                    return true
                }
            }

            if start + 1 >= end {
                m_eb = end
                m_e = start
                return false
            }

            if !depthSortResolve(start + 1, &arr, end) {
                m_e = start
                return false
            }

            end = m_eb
        }
    }

    // MARK: - Depth Sort (Main Pass) — Java: setFrustum(int, int, int, Polygon[])

    /// Main depth sort overlap resolution pass. Corresponds to Java setFrustum(int, int, int, Polygon[]).
    private func depthSortPass(_ totalCount: Int, _ groupSize: Int, _ arr: inout [RSPolygon]) {
        // Initialize sort metadata
        for i in 0..<totalCount {
            arr[i].m_c = false
            arr[i].m_f = i
            arr[i].m_p = -1
        }

        var idx = 0

        while true {
            // Inner loop: process unvisited polygons
            while !arr[idx].m_c {
                if idx == totalCount {
                    return
                }

                let poly = arr[idx]
                poly.m_c = true
                var startIdx = idx
                var endIdx = idx + groupSize
                if endIdx >= totalCount {
                    endIdx = totalCount - 1
                }

                var i = endIdx
                while i >= 1 + startIdx {
                    let other = arr[i]
                    if other.maxP6 > poly.minP6 && other.minP6 < poly.maxP6 &&
                       other.maxP2 > poly.minP2 && other.minP2 < poly.maxP2 &&
                       poly.m_f != other.m_p &&
                       !polygonHit2(other, poly) && polygonHit1(other, poly) {

                        _ = depthSortResolve(startIdx, &arr, i)
                        startIdx = m_e
                        if arr[i] !== other {
                            i += 1  // re-check this index since element was moved
                        }
                        other.m_p = poly.m_f
                    }
                    i -= 1
                }
            }

            idx += 1
        }
    }

    // MARK: - Scanline Edge Setup — Java: setFrustum(int, int, int[], int, int, RSModel, int[], int[], int, int, int)

    /// Sets up the Scanline array for a polygon by walking its edges.
    /// Also handles mouse pick testing (var10 == 5960).
    private func setupScanlines(_ var1: Int, _ var2: Int, _ var3: inout [Int], _ var4: Int,
                                _ var5: Int, _ var6: RSModel, _ var7: [Int], _ var8: [Int],
                                _ var9: Int, _ var10: Int, _ var11: Int) {
        var var1 = var1
        var var4 = var4
        var var5 = var5
        var var9 = var9

        if var11 == 3 {
            setupScanlinesTri(&var3, var7, var8, var11)
        } else if var11 == 4 {
            setupScanlinesQuad(&var3, var7, var8, var11)
        } else if var11 > 4 {
            setupScanlinesNGon(&var3, var7, var8, var11)
        }

        // Mouse picking test
        if var10 == 5960 {
            if m_K && m_cc < m_db && m_Wb >= m_Xb && m_Cb > m_Wb {
                let scanline = m_x[m_Wb]
                if m_j >= scanline.m_d >> 8 && m_j <= scanline.m_k >> 8 &&
                   scanline.m_k >= scanline.m_d && !var6.m_db && var6.m_zb[var2] == 0 {
                    m_Ab[m_cc] = var6
                    m_qb[m_cc] = var2
                    m_cc += 1
                }
            }
        }
    }

    // MARK: - Triangle scanline setup

    private func setupScanlinesTri(_ var3: inout [Int], _ var7: [Int], _ var8: [Int], _ var11: Int) {
        let var12 = m_Nb + var3[0]
        let var13 = var3[1] + m_Nb
        let var14 = m_Nb + var3[2]
        let var15 = var7[0]
        let var16 = var7[1]
        let var17 = var7[2]
        let var18 = var8[0]
        let var19 = var8[1]
        let var20 = var8[2]
        let var21 = m_wb + (m_Nb - 1)

        var var22 = 0, var23 = 0, var24 = 0, var25 = 0
        var var26 = Scene.TRANSPARENT
        var var27 = -Scene.TRANSPARENT

        if var12 != var14 {
            if var12 >= var14 {
                var24 = var20 << 8
                var26 = var14
                var27 = var12
                var22 = var17 << 8
            } else {
                var26 = var12
                var27 = var14
                var22 = var15 << 8
                var24 = var18 << 8
            }
            var25 = (var20 - var18 << 8) / (var14 - var12)
            var23 = (var17 - var15 << 8) / (var14 - var12)
            if var26 < 0 {
                var22 -= var26 * var23
                var24 -= var25 * var26
                var26 = 0
            }
            if var27 > var21 { var27 = var21 }
        }

        var var28 = 0, var29 = 0, var30 = 0, var31 = 0
        var var32 = Scene.TRANSPARENT
        var var33 = -Scene.TRANSPARENT

        if var12 != var13 {
            var29 = (var16 - var15 << 8) / (var13 - var12)
            var31 = (var19 - var18 << 8) / (var13 - var12)
            if var13 > var12 {
                var30 = var18 << 8
                var33 = var13
                var28 = var15 << 8
                var32 = var12
            } else {
                var30 = var19 << 8
                var32 = var13
                var28 = var16 << 8
                var33 = var12
            }
            if var33 > var21 { var33 = var21 }
            if var32 < 0 {
                var30 -= var31 * var32
                var28 -= var32 * var29
                var32 = 0
            }
        }

        var var34 = 0, var35 = 0, var36 = 0, var37 = 0
        var var38 = Scene.TRANSPARENT
        var var39 = -Scene.TRANSPARENT

        if var14 != var13 {
            if var14 > var13 {
                var34 = var16 << 8
                var38 = var13
                var36 = var19 << 8
                var39 = var14
            } else {
                var38 = var14
                var36 = var20 << 8
                var39 = var13
                var34 = var17 << 8
            }
            var37 = (var20 - var19 << 8) / (var14 - var13)
            var35 = (var17 - var16 << 8) / (var14 - var13)
            if var38 < 0 {
                var36 -= var38 * var37
                var34 -= var35 * var38
                var38 = 0
            }
            if var21 < var39 { var39 = var21 }
        }

        m_Xb = var26
        if m_Xb > var32 { m_Xb = var32 }
        if m_Xb > var38 { m_Xb = var38 }

        m_Cb = var27
        if var33 > m_Cb { m_Cb = var33 }
        if m_Cb < var39 { m_Cb = var39 }

        for row in m_Xb..<m_Cb {
            var minX: Int, maxX: Int, minXLight: Int, maxXLight: Int

            if row >= var26 && row < var27 {
                maxX = var22
                minX = var22
                maxXLight = var24
                minXLight = var24
                var22 += var23
                var24 += var25
            } else {
                minX = 655360
                maxX = -655360
                maxXLight = 0
                minXLight = 0
            }

            if var32 <= row && row < var33 {
                if maxX < var28 {
                    maxX = var28
                    maxXLight = var30
                }
                if var28 < minX {
                    minX = var28
                    minXLight = var30
                }
                var30 += var31
                var28 += var29
            }

            if row >= var38 && var39 > row {
                if var34 > maxX {
                    maxXLight = var36
                    maxX = var34
                }
                if var34 < minX {
                    minX = var34
                    minXLight = var36
                }
                var36 += var37
                var34 += var35
            }

            m_x[row].m_e = minXLight
            m_x[row].m_l = maxXLight
            m_x[row].m_d = minX
            m_x[row].m_k = maxX
        }

        if m_Xb < m_Nb - m_wb {
            m_Xb = m_Nb - m_wb
        }
    }

    // MARK: - Quad scanline setup

    private func setupScanlinesQuad(_ var3: inout [Int], _ var7: [Int], _ var8: [Int], _ var11: Int) {
        let var12 = var3[0] + m_Nb
        let var13 = m_Nb + var3[1]
        let var14 = m_Nb + var3[2]
        let var15 = m_Nb + var3[3]
        let var16 = var7[0], var17 = var7[1], var18 = var7[2], var19 = var7[3]
        let var20 = var8[0], var21 = var8[1], var22 = var8[2], var23 = var8[3]
        let var24 = m_wb + m_Nb - 1

        // Edge 0: var15 <-> var12
        var var25 = 0, var26 = 0, var27 = 0, var28 = 0
        var var29 = Scene.TRANSPARENT, var30 = -Scene.TRANSPARENT
        if var15 != var12 {
            var26 = (var19 - var16 << 8) / (var15 - var12)
            var28 = (var23 - var20 << 8) / (var15 - var12)
            if var15 <= var12 {
                var29 = var15; var25 = var19 << 8; var27 = var23 << 8; var30 = var12
            } else {
                var30 = var15; var25 = var16 << 8; var29 = var12; var27 = var20 << 8
            }
            if var29 < 0 { var27 -= var28 * var29; var25 -= var29 * var26; var29 = 0 }
            if var24 < var30 { var30 = var24 }
        }

        // Edge 1: var12 <-> var13
        var var31 = 0, var32 = 0, var33 = 0, var34 = 0
        var var35 = Scene.TRANSPARENT, var36 = -Scene.TRANSPARENT
        if var12 != var13 {
            var34 = (var21 - var20 << 8) / (var13 - var12)
            if var13 <= var12 {
                var35 = var13; var33 = var21 << 8; var36 = var12; var31 = var17 << 8
            } else {
                var35 = var12; var36 = var13; var31 = var16 << 8; var33 = var20 << 8
            }
            var32 = (var17 - var16 << 8) / (var13 - var12)
            if var24 < var36 { var36 = var24 }
            if var35 < 0 { var31 -= var35 * var32; var33 -= var34 * var35; var35 = 0 }
        }

        // Edge 2: var13 <-> var14
        var var37 = 0, var38 = 0, var39 = 0, var40 = 0
        var var55 = Scene.TRANSPARENT, var42 = -Scene.TRANSPARENT
        if var14 != var13 {
            var40 = (var22 - var21 << 8) / (var14 - var13)
            if var14 <= var13 {
                var55 = var14; var39 = var22 << 8; var37 = var18 << 8; var42 = var13
            } else {
                var55 = var13; var39 = var21 << 8; var42 = var14; var37 = var17 << 8
            }
            var38 = (var18 - var17 << 8) / (var14 - var13)
            if var55 < 0 { var39 -= var55 * var40; var37 -= var38 * var55; var55 = 0 }
            if var24 < var42 { var42 = var24 }
        }

        // Edge 3: var14 <-> var15
        var var43 = 0, var44 = 0, var45 = 0, var46 = 0
        var var47 = Scene.TRANSPARENT, var48 = -Scene.TRANSPARENT
        if var15 != var14 {
            var46 = (var23 - var22 << 8) / (var15 - var14)
            if var14 >= var15 {
                var48 = var14; var45 = var23 << 8; var43 = var19 << 8; var47 = var15
            } else {
                var45 = var22 << 8; var48 = var15; var47 = var14; var43 = var18 << 8
            }
            var44 = (var19 - var18 << 8) / (var15 - var14)
            if var47 < 0 { var43 -= var47 * var44; var45 -= var47 * var46; var47 = 0 }
            if var24 < var48 { var48 = var24 }
        }

        m_Xb = var29
        if m_Xb > var35 { m_Xb = var35 }
        if var55 < m_Xb { m_Xb = var55 }
        m_Cb = var30
        if m_Xb > var47 { m_Xb = var47 }
        if var36 > m_Cb { m_Cb = var36 }
        if var42 > m_Cb { m_Cb = var42 }
        if m_Cb < var48 { m_Cb = var48 }

        for row in m_Xb..<m_Cb {
            var minX: Int, maxX: Int, minXLight: Int, maxXLight: Int

            if row >= var29 && var30 > row {
                maxXLight = var27; minXLight = var27
                maxX = var25; minX = var25
                var27 += var28; var25 += var26
            } else {
                maxX = -655360; minX = 655360
                maxXLight = 0; minXLight = 0
            }

            if var35 <= row && var36 > row {
                if var31 < minX { minXLight = var33; minX = var31 }
                if maxX < var31 { maxXLight = var33; maxX = var31 }
                var31 += var32; var33 += var34
            }

            if row >= var55 && row < var42 {
                if var37 > maxX { maxX = var37; maxXLight = var39 }
                if var37 < minX { minX = var37; minXLight = var39 }
                var37 += var38; var39 += var40
            }

            if var47 <= row && var48 > row {
                if var43 > maxX { maxXLight = var45; maxX = var43 }
                if var43 < minX { minX = var43; minXLight = var45 }
                var45 += var46; var43 += var44
            }

            m_x[row].m_e = minXLight
            m_x[row].m_d = minX
            m_x[row].m_k = maxX
            m_x[row].m_l = maxXLight
        }

        if m_Nb - m_wb > m_Xb {
            m_Xb = m_Nb - m_wb
        }
    }

    // MARK: - N-gon scanline setup

    private func setupScanlinesNGon(_ var3: inout [Int], _ var7: [Int], _ var8: [Int], _ var11: Int) {
        // Java: this.m_Cb = this.m_Xb = var3[0] += this.m_Nb;
        var3[0] += m_Nb
        m_Xb = var3[0]
        m_Cb = m_Xb

        for i in 1..<var11 {
            var3[i] += m_Nb
            let v = var3[i]
            if v >= m_Xb {
                if m_Cb < v { m_Cb = v }
            } else {
                m_Xb = v
            }
        }

        if m_Cb >= m_Nb + m_wb {
            m_Cb = m_Nb - 1 + m_wb
        }
        if m_Nb - m_wb > m_Xb {
            m_Xb = m_Nb - m_wb
        }
        if m_Xb >= m_Cb { return }

        for row in m_Xb..<m_Cb {
            m_x[row].m_k = -655360
            m_x[row].m_d = 655360
        }

        let lastEdge = var11 - 1
        var startY = var3[0]
        var endY = var3[lastEdge]

        // Last edge (wrapping from last vertex to first)
        if startY >= endY {
            if endY < startY {
                var xVal = var7[lastEdge] << 8
                let xStep = (var7[0] - var7[lastEdge] << 8) / (startY - endY)
                var lVal = var8[lastEdge] << 8
                let lStep = (var8[0] - var8[lastEdge] << 8) / (startY - endY)
                var clampedStart = startY
                var clampedEnd = endY
                if clampedStart > m_Cb { clampedStart = m_Cb }
                if clampedEnd < 0 {
                    lVal -= lStep * clampedEnd
                    xVal -= xStep * clampedEnd
                    clampedEnd = 0
                }
                for row in clampedEnd...clampedStart {
                    m_x[row].m_d = xVal
                    m_x[row].m_k = xVal
                    m_x[row].m_e = lVal
                    m_x[row].m_l = lVal
                    xVal += xStep
                    lVal += lStep
                }
            }
        } else {
            var xVal = var7[0] << 8
            let xStep = (var7[lastEdge] - var7[0] << 8) / (endY - startY)
            var lVal = var8[0] << 8
            let lStep = (var8[lastEdge] - var8[0] << 8) / (endY - startY)
            var clampedStart = startY
            var clampedEnd = endY
            if clampedStart < 0 {
                xVal -= clampedStart * xStep
                lVal -= clampedStart * lStep
                clampedStart = 0
            }
            if clampedEnd > m_Cb { clampedEnd = m_Cb }
            for row in clampedStart...clampedEnd {
                m_x[row].m_e = lVal
                m_x[row].m_l = lVal
                m_x[row].m_d = xVal
                m_x[row].m_k = xVal
                xVal += xStep
                lVal += lStep
            }
        }

        // Remaining edges
        for edge in 0..<lastEdge {
            startY = var3[edge]
            let nextEdge = edge + 1
            endY = var3[nextEdge]

            if endY <= startY {
                if startY > endY {
                    var xVal = var7[nextEdge] << 8
                    let xStep = (var7[edge] - var7[nextEdge] << 8) / (startY - endY)
                    var lVal = var8[nextEdge] << 8
                    let lStep = (var8[edge] - var8[nextEdge] << 8) / (startY - endY)
                    var clampedEnd = endY
                    var clampedStart = startY
                    if clampedEnd < 0 {
                        xVal -= xStep * clampedEnd
                        lVal -= clampedEnd * lStep
                        clampedEnd = 0
                    }
                    if clampedStart > m_Cb { clampedStart = m_Cb }
                    for row in clampedEnd...clampedStart {
                        if xVal < m_x[row].m_d {
                            m_x[row].m_e = lVal
                            m_x[row].m_d = xVal
                        }
                        if xVal > m_x[row].m_k {
                            m_x[row].m_l = lVal
                            m_x[row].m_k = xVal
                        }
                        lVal += lStep
                        xVal += xStep
                    }
                }
            } else {
                var xVal = var7[edge] << 8
                let xStep = (var7[nextEdge] - var7[edge] << 8) / (endY - startY)
                var lVal = var8[edge] << 8
                let lStep = (var8[nextEdge] - var8[edge] << 8) / (endY - startY)
                var clampedEnd = endY
                var clampedStart = startY
                if clampedEnd > m_Cb { clampedEnd = m_Cb }
                if clampedStart < 0 {
                    xVal -= clampedStart * xStep
                    lVal -= clampedStart * lStep
                    clampedStart = 0
                }
                for row in clampedStart...clampedEnd {
                    if xVal > m_x[row].m_k {
                        m_x[row].m_k = xVal
                        m_x[row].m_l = lVal
                    }
                    if xVal < m_x[row].m_d {
                        m_x[row].m_d = xVal
                        m_x[row].m_e = lVal
                    }
                    lVal += lStep
                    xVal += xStep
                }
            }
        }

        if m_Nb - m_wb > m_Xb {
            m_Xb = m_Nb - m_wb
        }
    }

    // MARK: - Textured Polygon Rasterizer — Java: setFrustum(int[], RSModel, int, int, int, int[], int[], int, int)

    /// Rasterizes a single polygon (textured or flat-fill) using the scanline data.
    private func rasterizePolygon(_ var1: [Int], _ model: RSModel, _ var3: Int, _ var4: Int,
                                  _ var5: Int, _ var6: [Int], _ var7: [Int]) {
        if var5 == -2 { return }

        if var5 >= 0 {
            // Textured polygon
            let texIdx = min(var5, m_cb - 1)
            ensureTextureLoaded(texIdx)
            guard let texData = resourceDatabase[texIdx] else { return }

            let var10 = var7[0]
            let var11 = var1[0]
            let var12 = var6[0]
            let var13 = var10 - var7[1]
            let var14 = var11 - var1[1]
            let reducedVar4 = var4 - 1
            let var15 = var12 - var6[1]
            let var16 = var7[reducedVar4] - var10
            let var17 = var1[reducedVar4] - var11
            let var18 = var6[reducedVar4] - var12

            if m_Hb[texIdx] == 1 {
                // 128x128 texture
                rasterizeTextured128(model, var10, var11, var12, var13, var14, var15,
                                     var16, var17, var18, texIdx, texData)
            } else {
                // 64x64 texture
                rasterizeTextured64(model, var10, var11, var12, var13, var14, var15,
                                    var16, var17, var18, texIdx, texData)
            }
        } else {
            // Flat-fill polygon (solid color with gradient)
            rasterizeFlatFill(model, var5, var3)
        }
    }

    // MARK: - 128x128 Textured Rasterizer

    private func rasterizeTextured128(_ model: RSModel,
                                      _ var10: Int, _ var11: Int, _ var12: Int,
                                      _ var13: Int, _ var14: Int, _ var15: Int,
                                      _ var16: Int, _ var17: Int, _ var18: Int,
                                      _ texIdx: Int, _ texData: [Int32]) {
        let var19 = var11 * var16 - var17 * var10 << 12
        let var20 = var12 * var17 - var18 * var11 << (4 - rot1024_vp_src + 5 + 7)
        let var21 = var18 * var10 - var16 * var12 << (7 - rot1024_vp_src + 5)
        let var22 = var11 * var13 - var10 * var14 << 12
        let var23 = var14 * var12 - var15 * var11 << (5 - rot1024_vp_src + 11)
        let var24 = var10 * var15 - var12 * var13 << (7 + (5 - rot1024_vp_src))
        let var25 = var16 * var14 - var17 * var13 << 5
        let var26 = var15 * var17 - var14 * var18 << (4 + (5 - rot1024_vp_src))
        let var27 = var13 * var18 - var15 * var16 >> (rot1024_vp_src - 5)

        let var28 = var20 >> 4
        let var29 = var23 >> 4
        let var30 = var26 >> 4
        let var31 = m_Xb - m_Nb
        let var32 = m_vb
        var var33 = var32 * m_Xb + m_Zb
        var accU = var19 + var21 * var31
        var accV = var22 + var31 * var24
        var accZ = var25 + var27 * var31

        if !model.m_Kb {
            if m_S[texIdx] {
                // Transparent 128x128 — overload 1 (16-param with transparency)
                for row in m_Xb..<m_Cb {
                    let sl = m_x[row]
                    var x0 = sl.m_d >> 8
                    var x1 = sl.m_k >> 8
                    var span = x1 - x0
                    if span <= 0 {
                        accV += var24; accU += var21; var33 += var32; accZ += var27
                    } else {
                        var light = sl.m_e
                        let lightStep = (sl.m_l - light) / span
                        if -m_A > x0 {
                            light += (-x0 - m_A) * lightStep
                            x0 = -m_A; span = x1 - x0
                        }
                        if x1 > m_A { x1 = m_A; span = x1 - x0 }
                        Shader.shadeScanline(
                            Int32(var23), Int32(10), Int32(0), Int32(0),
                            &pixelData,
                            Int32(accZ + x0 * var30), Int32(light),
                            Int32(x0 * var28 + accU), Int32(accV + x0 * var29),
                            Int32(x0 + var33), Int32(var26), Int32(lightStep),
                            Int32(0), Int32(var20),
                            texData,
                            Int32(span)
                        )
                        var33 += var32; accV += var24; accZ += var27; accU += var21
                    }
                }
            } else {
                // Non-transparent 128x128 — overload 2 (walls, 15-param with Int8 sentinel)
                for row in m_Xb..<m_Cb {
                    let sl = m_x[row]
                    var x0 = sl.m_d >> 8
                    var x1 = sl.m_k >> 8
                    var span = x1 - x0
                    if span <= 0 {
                        accU += var21; accZ += var27; var33 += var32; accV += var24
                    } else {
                        var light = sl.m_e
                        let lightStep = (sl.m_l - light) / span
                        if x0 < -m_A {
                            light += (-m_A - x0) * lightStep
                            x0 = -m_A; span = x1 - x0
                        }
                        if m_A < x1 { x1 = m_A; span = x1 - x0 }
                        Shader.shadeScanline(
                            Int32(accV + var29 * x0),
                            Int32(var20),
                            50,
                            Int32(accZ + x0 * var30),
                            Int32(light),
                            Int32(lightStep << 2),
                            texData,
                            Int32(x0 + var33),
                            Int32(x0 * var28 + accU),
                            Int32(var26),
                            Int32(0), Int32(0),
                            &pixelData,
                            Int32(var23),
                            Int32(span)
                        )
                        accU += var21; accZ += var27; var33 += var32; accV += var24
                    }
                }
            }
        } else {
            // model.m_Kb — overload 3 (15-param with Int8(119) sentinel)
            for row in m_Xb..<m_Cb {
                let sl = m_x[row]
                var x0 = sl.m_d >> 8
                var x1 = sl.m_k >> 8
                var span = x1 - x0
                if span > 0 {
                    var light = sl.m_e
                    let lightStep = (sl.m_l - light) / span
                    if -m_A > x0 {
                        light += lightStep * (-x0 - m_A)
                        x0 = -m_A; span = x1 - x0
                    }
                    if x1 > m_A { x1 = m_A; span = x1 - x0 }
                    Shader.shadeScanline(
                        Int32(x0 + var33),
                        Int32(accV + x0 * var29),
                        Int32(accU + x0 * var28),
                        Int32(0),
                        Int32(light), Int32(var23), Int32(0),
                        Int32(accZ + x0 * var30),
                        Int32(var20),
                        Int32(lightStep << 2),
                        texData,
                        Int32(span), Int32(var26),
                        &pixelData,
                        119
                    )
                    var33 += var32; accV += var24; accU += var21; accZ += var27
                } else {
                    var33 += var32; accZ += var27; accU += var21; accV += var24
                }
            }
        }
    }

    // MARK: - 64x64 Textured Rasterizer

    private func rasterizeTextured64(_ model: RSModel,
                                     _ var10: Int, _ var11: Int, _ var12: Int,
                                     _ var13: Int, _ var14: Int, _ var15: Int,
                                     _ var16: Int, _ var17: Int, _ var18: Int,
                                     _ texIdx: Int, _ texData: [Int32]) {
        let var19 = var16 * var11 - var10 * var17 << 11
        let var20 = var12 * var17 - var18 * var11 << (4 + 6 + (5 - rot1024_vp_src))
        let var21 = var18 * var10 - var16 * var12 << (11 - rot1024_vp_src)
        let var22 = var11 * var13 - var14 * var10 << 11
        let var23 = var12 * var14 - var11 * var15 << (4 - rot1024_vp_src + 11)
        let var24 = var15 * var10 - var12 * var13 << (11 - rot1024_vp_src)
        let var25 = var16 * var14 - var17 * var13 << 5
        let var26 = var17 * var15 - var14 * var18 << (4 + (5 - rot1024_vp_src))
        let var27 = var18 * var13 - var16 * var15 >> (rot1024_vp_src - 5)

        let var28 = var20 >> 4
        let var29 = var23 >> 4
        let var30 = var26 >> 4
        let var31 = m_Xb - m_Nb
        let var32 = m_vb
        var var33 = var32 * m_Xb + m_Zb
        var accU = var19 + var31 * var21
        var accV = var22 + var31 * var24
        var accZ = var25 + var27 * var31

        if !model.m_Kb {
            if !m_S[texIdx] {
                // Non-transparent floor textures — overload 5 (floors)
                for row in m_Xb..<m_Cb {
                    let sl = m_x[row]
                    var x0 = sl.m_d >> 8
                    var x1 = sl.m_k >> 8
                    var span = x1 - x0
                    if span > 0 {
                        var light = sl.m_e
                        let lightStep = (sl.m_l - light) / span
                        if -m_A > x0 {
                            light += (-m_A - x0) * lightStep
                            x0 = -m_A
                            span = x1 - x0
                        }
                        if m_A < x1 {
                            x1 = m_A
                            span = x1 - x0
                        }
                        Shader.shadeScanline(
                            Int32(lightStep),           // var0_in
                            1121159302,                  // var1_sentinel (unused)
                            Int32(var23),                // var2_in
                            Int32(accV + var29 * x0),    // var3_in
                            Int32(var20),                // var4
                            texData,                     // src
                            Int32(light),                // var6_in
                            Int32(0),                    // var7_in
                            Int32(accU + var28 * x0),    // var8_in
                            Int32(0),                    // var9_in
                            &pixelData,                  // dest
                            Int32(var33 + x0),           // var11_in
                            Int32(accZ + x0 * var30),    // var12_in
                            Int32(var26),                // var13
                            Int32(span)                  // var14
                        )
                    }
                    var33 += var32
                    accV += var24
                    accU += var21
                    accZ += var27
                }
            } else {
                // Transparent floor textures — overload 6 (fountain spray & fences)
                for row in m_Xb..<m_Cb {
                    let sl = m_x[row]
                    var x0 = sl.m_d >> 8
                    var x1 = sl.m_k >> 8
                    var span = x1 - x0
                    if span > 0 {
                        var light = sl.m_e
                        let lightStep = (sl.m_l - light) / span
                        if x0 < -m_A {
                            light += lightStep * (-m_A - x0)
                            x0 = -m_A
                            span = x1 - x0
                        }
                        if x1 > m_A {
                            x1 = m_A
                            span = x1 - x0
                        }
                        Shader.shadeScanline(
                            Int32(span),                         // var0_in
                            Int32(accZ + x0 * var30),            // var1_in
                            Int32(0),                            // var2_in
                            25,                                  // var3 sentinel
                            Int32(0),                            // var4_in
                            Int32(var20),                        // var5
                            Int32(var26),                        // var6_in
                            Int32(lightStep),                    // var7_in
                            texData,                             // var8
                            &pixelData,                          // var9
                            Int32(x0 + var33),                   // var10_in
                            Int32(x0 * var28 + accU),            // var11_in
                            Int32(0),                            // var12_in
                            Int32(var23),                        // var13_in
                            Int32(light),                        // var14_in
                            Int32(var29 * x0 + accV)             // var15_in
                        )
                    }
                    accZ += var27
                    accV += var24
                    var33 += var32
                    accU += var21
                }
            }
        } else {
            // model.m_Kb == true — overload 4
            for row in m_Xb..<m_Cb {
                let sl = m_x[row]
                var x0 = sl.m_d >> 8
                var x1 = sl.m_k >> 8
                var span = x1 - x0
                if span > 0 {
                    var light = sl.m_e
                    let lightStep = (sl.m_l - light) / span
                    if x0 < -m_A {
                        light += lightStep * (-m_A - x0)
                        x0 = -m_A
                        span = x1 - x0
                    }
                    if x1 > m_A {
                        x1 = m_A
                        span = x1 - x0
                    }
                    Shader.shadeScanline(
                        &pixelData,                          // var0
                        Int32(var23),                        // var1
                        Int32(var26),                        // var2_in
                        Int32(x0 * var30 + accZ),            // var3_in
                        Int32(lightStep),                    // var4_in
                        Int32(light),                        // var5_in
                        Int32(x0 + var33),                   // var6_in
                        Int32(span),                         // var7
                        Int32(var28 * x0 + accU),            // var8_in
                        Int32(0),                            // var9_in
                        texData,                             // var10
                        false,                               // var11
                        Int32(var20),                        // var12
                        Int32(x0 * var29 + accV),            // var13_in
                        Int32(0)                             // var14_in
                    )
                }
                var33 += var32
                accZ += var27
                accU += var21
                accV += var24
            }
        }
    }

    // MARK: - Flat Fill Rasterizer

    /// Rasterizes a flat-fill polygon using a precomputed color gradient LUT.
    private func rasterizeFlatFill(_ model: RSModel, _ colorIdx: Int, _ var3: Int) {
        // Find or generate the color gradient LUT
        var lutIdx = -1
        for i in 0..<m_ib {
            if m_v[i] == colorIdx {
                m_H = m_Ib[i]
                lutIdx = i
                break
            }
            if i == m_ib - 1 {
                // Generate new gradient
                let slot = Int.random(in: 0..<m_ib)
                m_v[slot] = colorIdx
                let c = -1 - colorIdx
                let cr = ((c & 0x7C00) >> 10) * 8  // 32025 = 0x7D19, but Java uses (32025 & var5) >> 10
                let cg = ((c & 0x3E0) >> 5) * 8
                let cb = (c & 0x1F) * 8

                for j in 0..<256 {
                    let sq = j * j
                    let r = cr * sq / 65536
                    let g = cg * sq / 65536
                    let b = cb * sq / 65536
                    m_Ib[slot][255 - j] = b + (g << 8) + (r << 16)
                }

                m_H = m_Ib[slot]
                lutIdx = slot
            }
        }

        let var10 = m_vb
        var var11 = m_Xb * var10 + m_Zb

        if model.m_cb {
            // Giant crystal blend mode
            for row in m_Xb..<m_Cb {
                let sl = m_x[row]
                var x0 = sl.m_d >> 8
                var x1 = sl.m_k >> 8
                var span = x1 - x0
                if span > 0 {
                    var light = sl.m_e
                    var lightStep = (sl.m_l - light) / span
                    if x0 < -m_A {
                        light += lightStep * (-m_A - x0)
                        x0 = -m_A
                        span = x1 - x0
                    }
                    if m_A < x1 {
                        x1 = m_A
                        span = x1 - x0
                    }
                    // Blend fill: dest = color + (dest >> 1 & 0x7F7F7F)
                    flatFillBlend(light: light, lut: m_H, count: span,
                                  dest: &pixelData, lightStep: lightStep,
                                  destHead: x0 + var11)
                }
                var11 += var10
            }
        } else {
            // Standard flat fill
            for row in m_Xb..<m_Cb {
                let sl = m_x[row]
                var x0 = sl.m_d >> 8
                var x1 = sl.m_k >> 8
                var span = x1 - x0
                if span > 0 {
                    var light = sl.m_e
                    var lightStep = (sl.m_l - light) / span
                    if x0 < -m_A {
                        light += (-x0 - m_A) * lightStep
                        x0 = -m_A
                        span = x1 - x0
                    }
                    if m_A < x1 {
                        x1 = m_A
                        span = x1 - x0
                    }
                    flatFillSolid(light: light, lut: m_H, count: span,
                                  dest: &pixelData, lightStep: lightStep,
                                  destHead: x0 + var11)
                }
                var11 += var10
            }
        }
    }

    // MARK: - Flat Fill Kernels

    /// Standard solid flat fill. Corresponds to Java MiscFunctions.copyBlock16.
    private func flatFillSolid(light: Int, lut: [Int], count: Int,
                               dest: inout [Int32], lightStep: Int, destHead: Int) {
        guard count > 0 else { return }
        var srcI = light
        let srcStep = lightStep << 2
        var color = Int32(lut[(srcI & 0xFF00) >> 8])
        srcI += srcStep
        var di = destHead

        let blocks = count / 16
        for _ in 0..<blocks {
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            color = Int32(lut[(srcI & 0xFF00) >> 8])
            srcI += srcStep
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            color = Int32(lut[(srcI & 0xFF00) >> 8])
            srcI += srcStep
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            color = Int32(lut[(srcI & 0xFF00) >> 8])
            srcI += srcStep
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            dest[di] = color; di += 1
            color = Int32(lut[(srcI & 0xFF00) >> 8])
            srcI += srcStep
        }

        let remainder = count % 16
        for i in 0..<remainder {
            dest[di] = color; di += 1
            if (i & 3) == 3 {
                color = Int32(lut[(srcI & 0xFF00) >> 8])
                srcI += srcStep
            }
        }
    }

    /// Blend flat fill (for giant crystal). Corresponds to Java GraphicsController.a.
    private func flatFillBlend(light: Int, lut: [Int], count: Int,
                               dest: inout [Int32], lightStep: Int, destHead: Int) {
        guard count > 0 else { return }
        var srcI = light
        let srcStep = lightStep << 2
        var color = Int32(lut[(srcI & 0xFF00) >> 8])
        srcI += srcStep
        var di = destHead

        let blocks = count / 16
        for _ in 0..<blocks {
            for _ in 0..<4 {
                dest[di] = color &+ Int32(bitPattern: UInt32(bitPattern: dest[di]) >> 1 & 0x7F7F7F)
                di += 1
            }
            color = Int32(lut[(srcI & 0xFF00) >> 8]); srcI += srcStep
            for _ in 0..<4 {
                dest[di] = color &+ Int32(bitPattern: UInt32(bitPattern: dest[di]) >> 1 & 0x7F7F7F)
                di += 1
            }
            color = Int32(lut[(srcI & 0xFF00) >> 8]); srcI += srcStep
            for _ in 0..<4 {
                dest[di] = color &+ Int32(bitPattern: UInt32(bitPattern: dest[di]) >> 1 & 0x7F7F7F)
                di += 1
            }
            color = Int32(lut[(srcI & 0xFF00) >> 8]); srcI += srcStep
            for _ in 0..<4 {
                dest[di] = color &+ Int32(bitPattern: UInt32(bitPattern: dest[di]) >> 1 & 0x7F7F7F)
                di += 1
            }
            color = Int32(lut[(srcI & 0xFF00) >> 8]); srcI += srcStep
        }

        let remainder = count % 16
        for i in 0..<remainder {
            dest[di] = color &+ Int32(bitPattern: UInt32(bitPattern: dest[di]) >> 1 & 0x7F7F7F)
            di += 1
            if (i & 3) == 3 {
                color = Int32(lut[(srcI & 0xFF00) >> 8])
                srcI += srcStep
            }
        }
    }

    // MARK: - End Scene (THE MAIN RENDER METHOD)

    /// Renders all models in the scene. Corresponds to Java endScene (line 2555).
    func endScene() {
        m_f = graphics.interlace

        // Compute frustum bounds from fog distance
        let var7 = m_A * fogLandscapeDistance >> rot1024_vp_src
        RSModel.frustumFarZ = 0
        RSModel.frustumNearZ = 0
        RSModel.frustumMaxX = 0
        RSModel.frustumMinX = 0
        let var8 = fogLandscapeDistance * m_wb >> rot1024_vp_src
        RSModel.frustumMinY = 0
        RSModel.frustumMaxY = 0

        frustumPointTest(x: fogLandscapeDistance, y: -var7, z: -var8)
        frustumPointTest(x: fogLandscapeDistance, y: -var7, z: var8)
        frustumPointTest(x: fogLandscapeDistance, y: var7, z: -var8)
        frustumPointTest(x: fogLandscapeDistance, y: var7, z: var8)
        frustumPointTest(x: 0, y: -m_A, z: -m_wb)
        frustumPointTest(x: 0, y: -m_A, z: m_wb)
        frustumPointTest(x: 0, y: m_A, z: -m_wb)
        frustumPointTest(x: 0, y: m_A, z: m_wb)

        RSModel.frustumNearZ += rot1024_off_y
        RSModel.frustumMinX += rot1024_off_z
        RSModel.frustumFarZ += rot1024_off_y
        RSModel.frustumMaxY += rot1024_off_x
        RSModel.frustumMaxX += rot1024_off_z
        RSModel.frustumMinY += rot1024_off_x

        // Attach sprite model
        models[modelCount] = m_T
        m_T.m_Yb = 2

        // Transform all models (world -> camera -> screen)
        for i in 0...modelCount {
            models[i]?.rotate1024(
                yOffset: rot1024_off_y,
                vParamSrc: rot1024_vp_src,
                xOffset: rot1024_off_x,
                zOffset: rot1024_off_z,
                rotY: cameraProjY,
                rotZ: cameraProjZ,
                rotX: cameraProjX,
                zTop: rot1024_zTop
            )
        }

        // Collect polygons from all models
        m_zb = 0

        for modelIdx in 0..<modelCount {
            guard let mdl = models[modelIdx], mdl.m_dc else { continue }

            for face in 0..<mdl.faceHead {
                let vertCount = mdl.faceIndexCount[face]
                let indices = mdl.faceIndices[face]

                // Check if any vertex is in the frustum (between zTop and fogDistance)
                var visible = false
                for v in 0..<vertCount {
                    let z = mdl.vertZRot[indices[v]]
                    if z > rot1024_zTop && z < fogLandscapeDistance {
                        visible = true
                        break
                    }
                }
                guard visible else { continue }

                // X frustum check
                var xCheck = 0
                for v in 0..<vertCount {
                    let px = mdl.vertexParam6[indices[v]]
                    if px > -m_A { xCheck |= 1 }
                    if px < m_A { xCheck |= 2 }
                    if xCheck == 3 { break }
                }
                guard xCheck == 3 else { continue }

                // Y frustum check
                var yCheck = 0
                for v in 0..<vertCount {
                    let py = mdl.vertexParam2[indices[v]]
                    if py > -m_wb { yCheck |= 1 }
                    if py < m_wb { yCheck |= 2 }
                    if yCheck == 3 { break }
                }
                guard yCheck == 3 else { continue }

                // Create polygon entry
                let poly = polygons[m_zb]
                poly.model = mdl
                poly.faceID = face
                computePolygon(m_zb)

                let texID: Int
                if poly.orientation < 0 {
                    texID = mdl.faceTextureFront[face]
                } else {
                    texID = mdl.faceTextureBack[face]
                }

                if texID != Scene.TRANSPARENT {
                    var zSum = 0
                    for v in 0..<vertCount {
                        zSum += mdl.vertZRot[indices[v]]
                    }
                    poly.m_t = mdl.m_hc + zSum / vertCount
                    poly.m_b = texID
                    m_zb += 1
                }
            }
        }

        // Collect sprite polygons
        let spriteModel = m_T
        if spriteModel.m_dc {
            for face in 0..<spriteModel.faceHead {
                let indices = spriteModel.faceIndices[face]
                let v0 = indices[0]
                let scrX = spriteModel.vertexParam6[v0]
                let scrY = spriteModel.vertexParam2[v0]
                let zDist = spriteModel.vertZRot[v0]

                if zDist > rot1024_zTop && zDist < fogEntityDistance {
                    let sprW = (m_ob[face] << rot1024_vp_src) / zDist
                    let sprH = (m_Eb[face] << rot1024_vp_src) / zDist

                    if m_A >= scrX - sprW / 2 && -m_A <= scrX + sprW / 2 &&
                       scrY - sprH <= m_wb && scrY >= -m_wb {
                        let poly = polygons[m_zb]
                        poly.faceID = face
                        poly.model = spriteModel
                        computeSpritePolygon(m_zb)
                        poly.m_t = (spriteModel.vertZRot[indices[1]] + zDist) / 2
                        m_zb += 1
                    }
                }
            }
        }

        // Depth sort and render
        guard m_zb != 0 else { return }

        depthSortQuicksort(0, m_zb - 1, &polygons)
        depthSortPass(m_zb, 100, &polygons)

        // Rasterize each polygon
        for polyIdx in 0..<m_zb {
            let poly = polygons[polyIdx]
            let face = poly.faceID
            guard let mdl = poly.model else { continue }

            if mdl === m_T {
                // Sprite billboard rendering
                let indices = mdl.faceIndices[face]
                let v0 = indices[0]
                let scrX = mdl.vertexParam6[v0]
                let scrY = mdl.vertexParam2[v0]
                let zDist = mdl.vertZRot[v0]
                let sprW = (m_ob[face] << rot1024_vp_src) / zDist
                let sprH = (m_Eb[face] << rot1024_vp_src) / zDist
                let yDiff = scrY - mdl.vertexParam2[indices[1]]
                let xOff = mdl.vertexParam6[indices[1]] - scrX

                let drawX = scrX - sprW / 2
                let drawY = m_Nb - (sprH - scrY)

                graphics.drawEntity(
                    index: m_gb[face],
                    x: drawX + m_Zb,
                    y: drawY,
                    width: sprW,
                    height: sprH,
                    perspective: (256 << rot1024_vp_src) / zDist,
                    var8: xOff
                )

                // Mouse pick test for sprites
                if m_K && m_db > m_cc {
                    var pickX = drawX + (m_Q[face] << rot1024_vp_src) / zDist
                    if drawY <= m_Wb && drawY + sprH >= m_Wb &&
                       pickX <= m_j && m_j <= pickX + sprW &&
                       !mdl.m_db && mdl.m_zb[face] == 0 {
                        m_Ab[m_cc] = mdl
                        m_qb[m_cc] = face
                        m_cc += 1
                    }
                }
            } else {
                // Standard polygon rendering
                var vertCount = mdl.faceIndexCount[face]
                var lightBase = 0

                if mdl.faceDiffuseLight[face] != Scene.TRANSPARENT {
                    if poly.orientation < 0 {
                        lightBase = mdl.diffuseParam1 - mdl.faceDiffuseLight[face]
                    } else {
                        lightBase = mdl.diffuseParam1 + mdl.faceDiffuseLight[face]
                    }
                }

                let faceIndices = mdl.faceIndices[face]
                var clippedCount = 0

                for v in 0..<vertCount {
                    let vIdx = faceIndices[v]
                    m_Qb[v] = mdl.vertXRot[vIdx]
                    m_Vb[v] = mdl.vertYRot[vIdx]
                    m_J[v] = mdl.vertZRot[vIdx]

                    if mdl.faceDiffuseLight[face] == Scene.TRANSPARENT {
                        if poly.orientation < 0 {
                            lightBase = mdl.diffuseParam1 + Int(mdl.vertLightOther[vIdx]) - mdl.vertDiffuseLight[vIdx]
                        } else {
                            lightBase = Int(mdl.vertLightOther[vIdx]) + mdl.diffuseParam1 + mdl.vertDiffuseLight[vIdx]
                        }
                    }

                    if mdl.vertZRot[vIdx] >= rot1024_zTop {
                        m_yb[clippedCount] = mdl.vertexParam6[vIdx]
                        m_B[clippedCount] = mdl.vertexParam2[vIdx]
                        m_r[clippedCount] = lightBase
                        if mdl.vertZRot[vIdx] > fogSmoothingStartDistance {
                            m_r[clippedCount] += (mdl.vertZRot[vIdx] - fogSmoothingStartDistance) / fogZFalloff
                        }
                        clippedCount += 1
                    } else {
                        // Near-plane clipping: interpolate with adjacent visible vertices
                        let prevIdx: Int
                        if v != 0 {
                            prevIdx = faceIndices[v - 1]
                        } else {
                            prevIdx = faceIndices[vertCount - 1]
                        }

                        if mdl.vertZRot[prevIdx] >= rot1024_zTop {
                            let dz = mdl.vertZRot[vIdx] - mdl.vertZRot[prevIdx]
                            let clipY = mdl.vertYRot[vIdx] - (mdl.vertZRot[vIdx] - rot1024_zTop) *
                                        (mdl.vertYRot[vIdx] - mdl.vertYRot[prevIdx]) / dz
                            let clipX = mdl.vertXRot[vIdx] - (mdl.vertXRot[vIdx] - mdl.vertXRot[prevIdx]) *
                                        (mdl.vertZRot[vIdx] - rot1024_zTop) / dz
                            m_yb[clippedCount] = (clipX << rot1024_vp_src) / rot1024_zTop
                            m_B[clippedCount] = (clipY << rot1024_vp_src) / rot1024_zTop
                            m_r[clippedCount] = lightBase
                            clippedCount += 1
                        }

                        let nextIdx: Int
                        if vertCount - 1 == v {
                            nextIdx = faceIndices[0]
                        } else {
                            nextIdx = faceIndices[v + 1]
                        }

                        if mdl.vertZRot[nextIdx] >= rot1024_zTop {
                            let dz = mdl.vertZRot[vIdx] - mdl.vertZRot[nextIdx]
                            let clipY = mdl.vertYRot[vIdx] - (mdl.vertZRot[vIdx] - rot1024_zTop) *
                                        (mdl.vertYRot[vIdx] - mdl.vertYRot[nextIdx]) / dz
                            let clipX = mdl.vertXRot[vIdx] - (mdl.vertXRot[vIdx] - mdl.vertXRot[nextIdx]) *
                                        (mdl.vertZRot[vIdx] - rot1024_zTop) / dz
                            m_yb[clippedCount] = (clipX << rot1024_vp_src) / rot1024_zTop
                            m_B[clippedCount] = (clipY << rot1024_vp_src) / rot1024_zTop
                            m_r[clippedCount] = lightBase
                            clippedCount += 1
                        }
                    }
                }

                // Clamp lighting values
                for v in 0..<clippedCount {
                    if m_r[v] < 0 { m_r[v] = 0 }
                    else if m_r[v] > 255 { m_r[v] = 255 }

                    if poly.m_b >= 0 {
                        if m_Hb[poly.m_b] != 1 {
                            m_r[v] <<= 6
                        } else {
                            m_r[v] <<= 9
                        }
                    }
                }

                // Setup scanlines
                var tempB = m_B
                setupScanlines(0, face, &tempB, 0, 0, mdl, m_yb, m_r, 0, 5960, clippedCount)
                m_B = tempB

                // Rasterize the polygon
                if m_Xb < m_Cb {
                    rasterizePolygon(m_Vb, mdl, 1, vertCount, poly.m_b, m_J, m_Qb)
                }
            }
        }

        m_K = false
    }

    // MARK: - Scroll Texture (Java: d(int, int))

    /// Scrolls a texture by one row (used for animated textures like water).
    func scrollTexture(index: Int) {
        guard var texData = resourceDatabase[index] else { return }

        for col in 0..<64 {
            var pos = 4032 + col
            let saved = texData[pos]
            for _ in 0..<63 {
                texData[pos] = texData[pos - 64]
                pos -= 64
            }
            texData[pos] = saved
        }

        let size = 4096
        for i in 0..<size {
            let c = texData[i]
            texData[size + i] = Int32(truncatingIfNeeded: Int(c) - Scene.unsignedRightShift32(Int(c), 3)) & 0xF8F8FF
            texData[size * 2 + i] = Int32(truncatingIfNeeded: Int(c) - Scene.unsignedRightShift32(Int(c), 2)) & 0xF8F8FF
            texData[size * 3 + i] = Int32(truncatingIfNeeded: Int(c) - Scene.unsignedRightShift32(Int(c), 3) - Scene.unsignedRightShift32(Int(c), 2)) & 0xF8F8FF
        }

        resourceDatabase[index] = texData
    }

    // MARK: - Accessors for getX / getY parity

    func getX() -> Int { return m_j + m_Zb }
    func getY() -> Int { return m_Wb }
}
