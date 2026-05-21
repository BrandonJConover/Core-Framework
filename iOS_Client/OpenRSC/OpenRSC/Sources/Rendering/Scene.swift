// Port of Client_Base/src/orsc/graphics/three/Scene.java
import Foundation

final class Scene {
    static let TRANSPARENT: Int32 = 12345678

    // Frustum bounds (read by RSModel.rotate1024)
    static var frustumMinX: Int32 = 0
    static var frustumMaxX: Int32 = 0
    static var frustumMinY: Int32 = 0
    static var frustumMaxY: Int32 = 0
    static var frustumNearZ: Int32 = 0
    static var frustumFarZ: Int32 = 0

    // Model list
    var models: [RSModel?]
    var modelCount: Int = 0

    // Polygon list
    var polygons: [Polygon]
    var m_zb: Int = 0  // polygon count

    // Billboard sprite model
    var m_T: RSModel

    // Scanline buffer (one per screen row)
    var m_x: [Scanline]

    // Texture database
    var resourceDatabase: [[Int32]?]
    var textureTypes: [Int]
    var textureIndexData: [Data?]
    var m_L: [[Int32]]
    var m_Hb: [Int32]

    // Camera state
    var rot1024_off_x: Int32 = 0
    var rot1024_off_y: Int32 = 0
    var rot1024_off_z: Int32 = 0
    var cameraProjX: Int32 = 0
    var cameraProjY: Int32 = 0
    var cameraProjZ: Int32 = 0

    // Fog parameters
    var fogLandscapeDistance: Int32 = 1000
    var fogEntityDistance: Int32 = 1000
    var fogZFalloff: Int32 = 20
    var fogSmoothingStartDistance: Int32 = 10

    // Rasterizer references
    var graphics: GraphicsController
    var shader: Shader
    var billboardOcclusionDepth: [Int32]

    // Working state
    var m_A: Int32 = 256  // screen center X
    var m_wb: Int32 = 192  // screen center Y
    var m_vb: Int32 = 512
    var polyNormalScale: Int32 = 4

    // Sprite tracking
    var m_ob: [Int32]  // sprite depths
    var m_Eb: [Int32]  // sprite X
    var m_Fb: [Int32]  // sprite Y
    var m_gb: [Int32]  // sprite width
    var m_Q: [Int32]   // sprite height
    var m_Ob: [Int32]  // sprite indices
    var m_mask1: [Int32]  // colorMask1 (gray-pixel tint)
    var m_mask2: [Int32]  // colorMask2 (white-axis-pixel tint)
    var m_blueMask: [Int32]  // blue-channel mask for select equipment layers
    var m_colourTransform: [Int32]  // Java drawSpriteClipping colourTransform
    var m_flip: [Bool]    // mirrorX flag for direction 5/6/7
    var m_n: Int = 0   // sprite count

    // Debug
    var debugFrameCount = 0

    // Diffuse light direction
    var diffuseLightX: Int32 = 0
    var diffuseLightY: Int32 = 0
    var diffuseLightZ: Int32 = 0

    init(graphics: GraphicsController, modelCount: Int, polyCount: Int, spriteCount: Int) {
        self.graphics = graphics
        self.shader = Shader()
        self.billboardOcclusionDepth = [Int32](repeating: Int32.max, count: Int(graphics.width2 * graphics.height2))

        // Initialize model array
        self.modelCount = 0
        self.models = [RSModel?](repeating: nil, count: modelCount)

        // Initialize polygon array. Polygon is a class, so the
        // `[Polygon](repeating: Polygon(), count: N)` form would have
        // produced N references to one shared instance — every stored
        // polygon would have collapsed onto the last one filled, which
        // is exactly the symptom we were seeing in the device log
        // (370 "visible" polys reporting an identical bounding box).
        // Allocate N distinct Polygon instances instead.
        self.m_zb = 0
        self.polygons = (0..<polyCount).map { _ in Polygon() }

        // Initialize sprite model (2 verts per sprite)
        self.m_T = RSModel()

        // Initialize scanline buffer
        self.m_x = [Scanline](repeating: Scanline(), count: 334)

        // Initialize sprite tracking
        self.m_ob = [Int32](repeating: 0, count: spriteCount)
        self.m_Eb = [Int32](repeating: 0, count: spriteCount)
        self.m_Fb = [Int32](repeating: 0, count: spriteCount)
        self.m_gb = [Int32](repeating: 0, count: spriteCount)
        self.m_Q = [Int32](repeating: 0, count: spriteCount)
        self.m_Ob = [Int32](repeating: 0, count: spriteCount)
        self.m_mask1 = [Int32](repeating: 0, count: spriteCount)
        self.m_mask2 = [Int32](repeating: 0, count: spriteCount)
        self.m_blueMask = [Int32](repeating: 0, count: spriteCount)
        self.m_colourTransform = [Int32](repeating: Int32(bitPattern: 0xFFFFFFFF), count: spriteCount)
        self.m_flip = [Bool](repeating: false, count: spriteCount)

        // Initialize texture database
        self.resourceDatabase = [[Int32]?](repeating: nil, count: 80)
        self.textureTypes = [Int](repeating: 0, count: 80)
        self.textureIndexData = [Data?](repeating: nil, count: 80)
        self.m_L = [[Int32]](repeating: [], count: 80)
        self.m_Hb = [Int32](repeating: 0, count: 80)

        // Set up screen dimensions
        self.m_A = graphics.width2 / 2
        self.m_wb = graphics.height2 / 2

        // Attach shader to graphics - need to use buffer pointer for unsafe assignment
        graphics.pixelData.withUnsafeMutableBufferPointer { buffer in
            self.shader.pixelData = buffer.baseAddress
        }
    }

    // MARK: - Model management

    func addModel(_ model: RSModel) {
        guard modelCount < models.count else { return }
        models[modelCount] = model
        modelCount += 1
    }

    func removeModel(_ model: RSModel) {
        for i in 0..<modelCount {
            if models[i] === model {
                if i < modelCount - 1 {
                    models[i] = models[modelCount - 1]
                }
                models[modelCount - 1] = nil
                modelCount -= 1
                return
            }
        }
    }

    // MARK: - Sprite management

    func drawSprite(var1: Int32, var2: Int32, var3: Int32, var4: Int32, var5: Int32, var6: Int32, var7: Int32) {
        drawSpriteTinted(depth: var1, x: var2, y: var3, width: var4, height: var5,
                         spriteIdx: var6, mask1: 0, mask2: 0, mirrorX: false)
    }

    /// Register a billboard with optional 2-mask color tinting. mask1 tints gray
    /// pixels (hair/top/bottom layer color), mask2 tints white-axis pixels (skin
    /// color). 0 means no tint for that channel.
    func drawSpriteTinted(depth: Int32, x: Int32, y: Int32, width: Int32, height: Int32,
                          spriteIdx: Int32, mask1: Int32, mask2: Int32, blueMask: Int32 = 0,
                          colourTransform: Int32 = Int32(bitPattern: 0xFFFFFFFF),
                          mirrorX: Bool) {
        guard m_n < m_Ob.count else { return }
        m_ob[m_n] = depth
        m_Eb[m_n] = x
        m_Fb[m_n] = y
        m_gb[m_n] = width
        m_Q[m_n] = height
        m_Ob[m_n] = spriteIdx
        m_mask1[m_n] = mask1
        m_mask2[m_n] = mask2
        m_blueMask[m_n] = blueMask
        m_colourTransform[m_n] = colourTransform
        m_flip[m_n] = mirrorX
        m_n += 1
    }

    func reduceSprites(_ count: Int32) {
        m_n = 0
    }

    /// Project a single world-space point through the current camera. Returns
    /// screen-space (x, y) and camera-space depth (z). Depth < zTop means the
    /// point is behind/near the camera and should be skipped. Mirrors the math
    /// in RSModel.rotate1024 line 548+.
    func projectPoint(worldX: Int32, worldY: Int32, worldZ: Int32) -> (screenX: Int32, screenY: Int32, depth: Int32) {
        var x = worldX &- rot1024_off_x
        var y = worldY &- rot1024_off_y
        var z = worldZ &- rot1024_off_z

        let rotY = Int(cameraProjY)
        let rotZ = Int(cameraProjZ)
        let rotX = Int(cameraProjX)

        if cameraProjZ != 0 {
            let sn = FastMath.trigTable1024[rotZ]
            let cs = FastMath.trigTable1024[rotZ + 1024]
            let tmp = (y &* sn &+ cs &* x) >> 15
            y = (y &* cs &- x &* sn) >> 15
            x = tmp
        }
        if cameraProjY != 0 {
            let sn = FastMath.trigTable1024[rotY]
            let cs = FastMath.trigTable1024[rotY + 1024]
            let tmp = (cs &* x &+ z &* sn) >> 15
            z = (cs &* z &- x &* sn) >> 15
            x = tmp
        }
        if cameraProjX != 0 {
            let sn = FastMath.trigTable1024[rotX]
            let cs = FastMath.trigTable1024[rotX + 1024]
            let tmp = (y &* cs &- sn &* z) >> 15
            z = (sn &* y &+ cs &* z) >> 15
            y = tmp
        }

        let sx: Int32
        let sy: Int32
        if z < rot1024_zTop {
            sx = x << rot1024_vp_src
            sy = y << rot1024_vp_src
        } else {
            sx = (x << rot1024_vp_src) / z
            sy = (y << rot1024_vp_src) / z
        }
        return (sx + m_A, sy + m_wb, z)
    }

    // MARK: - Camera setup

    // Viewport scale parameter (matches Java rot1024_vp_src = 8)
    var rot1024_vp_src: Int32 = 8
    var rot1024_zTop: Int32 = 20  // Near plane — lower = more visible tiles

    func setCamera(centerX: Int32, centerY: Int32, centerZ: Int32, xRot: Int32, yRot: Int32, zRot: Int32, offset: Int32) {
        // Matches Java Scene.java:2930 exactly
        let zr = Int(zRot & 1023)
        let xr = Int(xRot & 1023)
        let yr = Int(yRot & 1023)

        cameraProjZ = Int32(1024 - zr) & 1023
        cameraProjX = Int32(1024 - xr) & 1023
        cameraProjY = Int32(1024 - yr) & 1023

        var offX: Int32 = 0
        var offY: Int32 = 0
        var offZ: Int32 = offset

        if xr != 0 {
            let sin = FastMath.trigTable1024[xr]
            let cos = FastMath.trigTable1024[xr + 1024]
            let tmp = (cos &* offY &- sin &* offset) >> 15
            offZ = (sin &* offY &+ offset &* cos) >> 15
            offY = tmp
        }

        if yr != 0 {
            let sin = FastMath.trigTable1024[yr]
            let cos = FastMath.trigTable1024[yr + 1024]
            let tmp = (offX &* cos &+ offZ &* sin) >> 15
            offZ = (cos &* offZ &- sin &* offX) >> 15
            offX = tmp
        }

        if zr != 0 {
            let cos = FastMath.trigTable1024[zr + 1024]
            let sin = FastMath.trigTable1024[zr]
            let tmp = (offX &* cos &+ sin &* offY) >> 15
            offY = (offY &* cos &- sin &* offX) >> 15
            offX = tmp
        }

        rot1024_off_z = centerZ &- offZ
        rot1024_off_y = centerY &- offY
        rot1024_off_x = centerX &- offX
    }

    // MARK: - Rendering

    func endScene(_ var1: Int32) {
        // Clear framebuffer
        graphics.blackScreen()
        resetBillboardOcclusionDepth()

        // Compute frustum extents (matches Java Scene.java:2557-2580)
        let var7 = m_A &* fogLandscapeDistance >> rot1024_vp_src
        let var8 = fogLandscapeDistance &* m_wb >> rot1024_vp_src

        Scene.frustumFarZ = 0; Scene.frustumNearZ = 0
        Scene.frustumMaxX = 0; Scene.frustumMinX = 0
        Scene.frustumMinY = 0; Scene.frustumMaxY = 0

        updateFrustum(fogLandscapeDistance, -var7, -var8)
        updateFrustum(fogLandscapeDistance, -var7, var8)
        updateFrustum(fogLandscapeDistance, var7, -var8)
        updateFrustum(fogLandscapeDistance, var7, var8)
        updateFrustum(0, -m_A, -m_wb)
        updateFrustum(0, -m_A, m_wb)
        updateFrustum(0, m_A, -m_wb)
        updateFrustum(0, m_A, m_wb)

        Scene.frustumNearZ += rot1024_off_y
        Scene.frustumMinX += rot1024_off_z
        Scene.frustumFarZ += rot1024_off_y
        Scene.frustumMaxY += rot1024_off_x
        Scene.frustumMaxX += rot1024_off_z
        Scene.frustumMinY += rot1024_off_x

        // Transform all models to camera space (matches Java Scene.java:2585-2588)
        for i in 0..<modelCount {
            guard let model = models[i] else { continue }
            model.rotate1024(
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

        // Collect visible faces into polygon list (with Z culling)
        m_zb = 0
        var totalFaces = 0
        var zCulled = 0
        var screenCulled = 0
        var modelSkipped = 0
        for i in 0..<modelCount {
            guard let model = models[i] else { continue }
            if !model.m_dc { modelSkipped += 1; continue }

            for faceIdx in 0..<Int(model.faceHead) {
                guard m_zb < polygons.count else { break }

                let indices = model.faceIndices[faceIdx]
                let count = model.faceIndexCount[faceIdx]
                guard count >= 3 else { continue }
                totalFaces += 1

                // Z-cull: skip if all vertices are behind the near plane
                var anyVisible = false
                for vi in 0..<Int(count) {
                    let vIdx = Int(indices[vi])
                    if vIdx < model.vertZRot.count && model.vertZRot[vIdx] >= rot1024_zTop {
                        anyVisible = true
                        break
                    }
                }
                if !anyVisible { zCulled += 1; continue }

                let poly = polygons[m_zb]
                poly.model = model
                poly.faceID = Int32(faceIdx)

                let v0 = Int(indices[0])
                let v1 = Int(indices[1])
                let v2 = Int(indices[2])

                guard v0 < model.vertXRot.count && v1 < model.vertXRot.count && v2 < model.vertXRot.count else { continue }

                // Cross product for face normal
                let nx1 = model.vertXRot[v1] &- model.vertXRot[v0]
                let ny1 = model.vertYRot[v1] &- model.vertYRot[v0]
                let nz1 = model.vertZRot[v1] &- model.vertZRot[v0]
                let nx2 = model.vertXRot[v2] &- model.vertXRot[v0]
                let ny2 = model.vertYRot[v2] &- model.vertYRot[v0]
                let nz2 = model.vertZRot[v2] &- model.vertZRot[v0]
                poly.normalX = ((ny1 &* nz2) &- (nz1 &* ny2)) >> 14
                poly.normalY = ((nz1 &* nx2) &- (nx1 &* nz2)) >> 14
                poly.normalZ = ((nx1 &* ny2) &- (ny1 &* nx2)) >> 14

                poly.minZ = model.minZ
                poly.maxZ = model.maxZ
                poly.minP2 = 999999
                poly.maxP2 = -999999
                poly.minP6 = 999999
                poly.maxP6 = -999999

                // Compute bounding box and average depth
                var avgZ: Int32 = 0
                for j in 0..<Int(count) {
                    let vIdx = Int(indices[j])
                    guard vIdx < model.vertexParam6.count else { continue }
                    let x = model.vertexParam6[vIdx] + m_A
                    let y = model.vertexParam2[vIdx] + m_wb

                    if x < poly.minP6 { poly.minP6 = x }
                    if x > poly.maxP6 { poly.maxP6 = x }
                    if y < poly.minP2 { poly.minP2 = y }
                    if y > poly.maxP2 { poly.maxP2 = y }
                    avgZ += model.vertZRot[vIdx]
                }
                poly.m_t = avgZ / count  // average Z depth for sorting

                // Skip off-screen polygons
                if !(poly.maxP6 > 0 && poly.minP6 < graphics.width2 &&
                     poly.maxP2 > 0 && poly.minP2 < graphics.height2) {
                    screenCulled += 1
                    continue
                }

                m_zb += 1
            }
        }

        // Debug log (first few frames only)
        debugFrameCount += 1
        if debugFrameCount <= 5 {
            print("[Scene] total=\(totalFaces) zCulled=\(zCulled) screenCulled=\(screenCulled) visible=\(m_zb) modelSkip=\(modelSkipped)")
            if totalFaces > 0 && m_zb == 0 {
                // Sample first face's vertex data to debug
                if let model = models[0] {
                    let fi = model.faceIndices[0]
                    let v0 = Int(fi[0])
                    if v0 < model.vertZRot.count {
                        print("[Scene] sample v0: xRot=\(model.vertXRot[v0]) yRot=\(model.vertYRot[v0]) zRot=\(model.vertZRot[v0]) p6=\(model.vertexParam6[v0]) p2=\(model.vertexParam2[v0])")
                    }
                }
            }
        }

        // Depth sort: back to front (painter's algorithm)
        let sortedIndices = (0..<m_zb).sorted { i, j in
            self.polygons[i].m_t > self.polygons[j].m_t  // larger Z = farther = draw first
        }

        // Rasterize polygons. Textured terrain now goes through the ported
        // Shader scanline path; the direct sampler remains only as dead fallback
        // helpers until the Java renderer port is fully retired.
        for idx in sortedIndices {
            let poly = polygons[idx]
            guard let model = poly.model else { continue }
            let fIdx = Int(poly.faceID)
            guard fIdx < model.faceIndices.count else { continue }

            let indices = model.faceIndices[fIdx]
            let count = Int(model.faceIndexCount[fIdx])
            guard count >= 3 else { continue }

            // Get color
            let texFront = model.faceTextureFront[fIdx]
            let color: Int32
            if texFront < -1 || texFront > 100000 {
                color = texFront
            } else {
                let brightness = Int32(model.faceDiffuseLight[fIdx] & 0xFF)
                color = brightness > 0 ? ((brightness << 16) | (brightness << 8) | brightness) | Int32(bitPattern: 0xFF000000) : Int32(bitPattern: 0xFF404040)
            }

            // Get screen coordinates for all vertices (clamped to reasonable range)
            var screenPts = [(x: Int, y: Int)]()
            let maxCoord = Int(graphics.width2) * 4  // allow some off-screen for edge cases
            for vi in 0..<count {
                let vIdx = Int(indices[vi])
                guard vIdx < model.vertexParam6.count else { continue }
                let sx = max(-maxCoord, min(maxCoord, Int(model.vertexParam6[vIdx] + m_A)))
                let sy = max(-maxCoord, min(maxCoord, Int(model.vertexParam2[vIdx] + m_wb)))
                screenPts.append((x: sx, y: sy))
            }
            guard screenPts.count >= 3 else { continue }

            // Fill the polygon's bounding box with its color
            // For small terrain tiles at isometric zoom, bbox fill is accurate and fast
            let minY = max(0, Int(poly.minP2))
            let maxY = min(Int(graphics.height2) - 1, Int(poly.maxP2))
            let minX = max(0, Int(poly.minP6))
            let maxX = min(Int(graphics.width2) - 1, Int(poly.maxP6))
            guard minY <= maxY && minX <= maxX else { continue }

            let terrainTexture = terrainTextureForFace(model: model, faceIndex: fIdx)
            if let terrainTexture {
                rasterizeTerrainTextureScanlines(texture: terrainTexture,
                                                 screenPts: screenPts,
                                                 minY: minY, maxY: maxY,
                                                 fallback: color)
            } else {
                rasterizeFlatScanlines(screenPts: screenPts,
                                       minY: minY, maxY: maxY,
                                       color: color)
            }
            if model.occludesBillboards {
                recordBillboardOccluder(screenPts: screenPts, minY: minY, maxY: maxY, depth: poly.m_t)
            }
        }

        if debugFrameCount <= 5 && m_zb > 0 {
            // Find actual min/max across ALL visible polygons
            var globalMinX: Int32 = 99999, globalMaxX: Int32 = -99999
            var globalMinY: Int32 = 99999, globalMaxY: Int32 = -99999
            for i in 0..<m_zb {
                let p = polygons[i]
                if p.minP6 < globalMinX { globalMinX = p.minP6 }
                if p.maxP6 > globalMaxX { globalMaxX = p.maxP6 }
                if p.minP2 < globalMinY { globalMinY = p.minP2 }
                if p.maxP2 > globalMaxY { globalMaxY = p.maxP2 }
            }
            print("[Scene] \(m_zb) polys, screen range: x=\(globalMinX)..\(globalMaxX) y=\(globalMinY)..\(globalMaxY) (screen=\(graphics.width2)x\(graphics.height2))")
        }

        // Render sprites (billboards)
        for i in 0..<m_n {
            let spriteX = m_Eb[i]
            let spriteY = m_Fb[i]
            let spriteW = m_gb[i]
            let spriteH = m_Q[i]
            let spriteIdx = Int(m_Ob[i])

            let mask1 = m_mask1[i]
            let mask2 = m_mask2[i]
            let blueMask = m_blueMask[i]
            let colourTransform = m_colourTransform[i]
            let mirror = m_flip[i]
            if isBillboardOccluded(x: spriteX, y: spriteY, width: spriteW, height: spriteH, depth: m_ob[i]) {
                continue
            }
            if mask1 != 0 || mask2 != 0 || blueMask != 0 || colourTransform != Int32(bitPattern: 0xFFFFFFFF) {
                graphics.drawEntityTinted(
                    index: spriteIdx,
                    x: spriteX, y: spriteY,
                    width: spriteW, height: spriteH,
                    mask1: mask1, mask2: mask2, blueMask: blueMask,
                    colourTransform: colourTransform,
                    mirrorX: mirror
                )
            } else {
                graphics.drawEntity(
                    index: spriteIdx,
                    x: spriteX, y: spriteY,
                    width: spriteW, height: spriteH,
                    perspective: 0
                )
            }
        }
    }

    private func resetBillboardOcclusionDepth() {
        let count = Int(graphics.width2 * graphics.height2)
        if billboardOcclusionDepth.count != count {
            billboardOcclusionDepth = [Int32](repeating: Int32.max, count: count)
        } else {
            billboardOcclusionDepth.withUnsafeMutableBufferPointer { buf in
                for i in 0..<count { buf[i] = Int32.max }
            }
        }
    }

    private func recordBillboardOccluder(screenPts: [(x: Int, y: Int)],
                                         minY: Int, maxY: Int,
                                         depth: Int32) {
        guard !billboardOcclusionDepth.isEmpty else { return }
        let yStart = max(0, minY)
        let yEnd = min(Int(graphics.height2) - 1, maxY)
        guard yStart <= yEnd else { return }
        let width = Int(graphics.width2)
        for y in yStart...yEnd {
            guard let span = polygonSpan(atY: y, screenPts: screenPts) else { continue }
            let x0 = max(0, span.x0)
            let x1 = min(width - 1, span.x1)
            guard x0 <= x1 else { continue }
            let row = y * width
            for x in x0...x1 {
                let idx = row + x
                if depth < billboardOcclusionDepth[idx] {
                    billboardOcclusionDepth[idx] = depth
                }
            }
        }
    }

    private func isBillboardOccluded(x: Int32, y: Int32, width: Int32, height: Int32, depth: Int32) -> Bool {
        guard width > 0, height > 0, depth >= rot1024_zTop else { return false }
        let screenW = Int(graphics.width2)
        let screenH = Int(graphics.height2)
        guard screenW > 0 && screenH > 0 else { return false }

        let left = max(0, Int(x))
        let right = min(screenW - 1, Int(x + width - 1))
        let top = max(0, Int(y + height / 3))
        let bottom = min(screenH - 1, Int(y + height - 1))
        guard left <= right && top <= bottom else { return false }

        let xs = [left, (left + right) / 2, right]
        let ys = [top, (top + bottom) / 2, bottom]
        var covered = 0
        var samples = 0
        let margin: Int32 = 32
        for sy in ys {
            for sx in xs {
                samples += 1
                let occluderDepth = billboardOcclusionDepth[sy * screenW + sx]
                if occluderDepth != Int32.max && occluderDepth + margin < depth {
                    covered += 1
                }
            }
        }
        return samples > 0 && covered * 2 >= samples
    }

    private func terrainTextureForFace(model: RSModel, faceIndex: Int) -> (index: Int, pixels: [Int32], width: Int, height: Int, ramps: Int)? {
        guard faceIndex >= 0 && faceIndex < model.faceTextureBack.count else { return nil }
        let textureIndex = Int(model.faceTextureBack[faceIndex])
        guard textureIndex >= 0,
              textureIndex < resourceDatabase.count,
              let pixels = resourceDatabase[textureIndex],
              !pixels.isEmpty else { return nil }

        let width: Int
        if textureIndex < textureTypes.count, textureTypes[textureIndex] > 0, pixels.count >= 128 * 128 {
            width = 128
        } else if pixels.count >= 64 * 64 {
            width = 64
        } else {
            width = max(1, Int(Double(pixels.count).squareRoot()))
        }
        let basePixels = width * width
        let ramps = basePixels > 0 ? max(1, pixels.count / basePixels) : 1
        return (textureIndex, pixels, width, width, ramps)
    }

    private func rasterizeFlatScanlines(screenPts: [(x: Int, y: Int)],
                                        minY: Int, maxY: Int,
                                        color: Int32) {
        let yStart = max(0, minY)
        let yEnd = min(Int(graphics.height2) - 1, maxY)
        guard yStart <= yEnd else { return }

        for y in yStart...yEnd {
            guard let span = polygonSpan(atY: y, screenPts: screenPts) else { continue }
            let x0 = max(0, span.x0)
            let x1 = min(Int(graphics.width2) - 1, span.x1)
            guard x0 <= x1 else { continue }
            graphics.drawLineHoriz(x: Int32(x0), y: Int32(y), width: Int32(x1 - x0 + 1), rgb: color)
        }
    }

    private func rasterizeTerrainTextureScanlines(texture: (index: Int, pixels: [Int32], width: Int, height: Int, ramps: Int),
                                                  screenPts: [(x: Int, y: Int)],
                                                  minY: Int, maxY: Int,
                                                  fallback: Int32) {
        let yStart = max(0, minY)
        let yEnd = min(Int(graphics.height2) - 1, maxY)
        guard yStart <= yEnd else { return }

        let pageSize = texture.width * texture.height
        guard pageSize > 0, texture.pixels.count >= pageSize else { return }
        let ramp = terrainBrightnessRamp(for: fallback, rampCount: texture.ramps)
        let page = max(0, min(texture.ramps - 1, ramp))
        let pageStart = min(texture.pixels.count - pageSize, page * pageSize)
        let source = shaderCompatibleTerrainPage(
            pixels: Array(texture.pixels[pageStart..<(pageStart + pageSize)]),
            width: texture.width,
            height: texture.height
        )

        graphics.pixelData.withUnsafeMutableBufferPointer { destBuffer in
            guard let dest = destBuffer.baseAddress else { return }
            source.withUnsafeBufferPointer { srcBuffer in
                guard let src = srcBuffer.baseAddress else { return }

                for y in yStart...yEnd {
                    guard let span = polygonSpan(atY: y, screenPts: screenPts) else { continue }
                    let x0 = max(0, span.x0)
                    let x1 = min(Int(graphics.width2) - 1, span.x1)
                    guard x0 <= x1 else { continue }

                    // Lay down the face's flat colour first. The selected
                    // Java-style brightness page already carries the terrain
                    // luminance; transparent texture pixels (0 after magenta
                    // conversion) preserve this base colour.
                    let rowBase = y * Int(graphics.width2)
                    for x in x0...x1 {
                        dest[rowBase + x] = fallback
                    }

                    guard let uvStart = terrainUVForScreenPoint(x: Double(x0) + 0.5,
                                                                y: Double(y) + 0.5,
                                                                screenPts: screenPts),
                          let uvEnd = terrainUVForScreenPoint(x: Double(x1) + 0.5,
                                                              y: Double(y) + 0.5,
                                                              screenPts: screenPts) else { continue }

                    let spanWidth = max(1, x1 - x0 + 1)
                    let u0 = Int32(max(0, min(63, Int(uvStart.u * 63.0))))
                    let v0 = Int32(max(0, min(63, Int(uvStart.v * 63.0))))
                    let u1 = Int32(max(0, min(63, Int(uvEnd.u * 63.0))))
                    let v1 = Int32(max(0, min(63, Int(uvEnd.v * 63.0))))
                    let uBlockDelta = ((u1 - u0) * 16) / Int32(spanWidth)
                    let vBlockDelta = ((v1 - v0) * 16) / Int32(spanWidth)
                    let destIndex = Int32(rowBase + x0)

                    shader.shadeScanlineTransparentNormal(
                        var0: vBlockDelta, var1: 0, var2: 0, var3: 0,
                        dest: dest,
                        var5: 1, var6: 0,
                        var7: u0, var8: v0, var9: destIndex,
                        var10: 0, var11: 0, var12: 0,
                        var13: uBlockDelta, texture: src,
                        var15: Int32(spanWidth)
                    )
                }
            }
        }
    }

    private func shaderCompatibleTerrainPage(pixels: [Int32], width: Int, height: Int) -> [Int32] {
        guard width > 0, height > 0, pixels.count >= width * height else {
            return [Int32](repeating: 0, count: 64 * 64)
        }
        if width == 64 && height == 64 {
            // The Java-style transparent-normal shader addresses texture rows
            // with `(v & 0x3F80) + (u >> 7)`, which can reach index 8127 for
            // bottom-half V coordinates. Feed it two identical 64x64 halves so
            // the adapter keeps skip-0 semantics without reading past the page.
            return pixels + pixels
        }

        // The transparent-normal Swift shader is currently the Java-compatible
        // path used by terrain faces. Larger texture pages still need the full
        // Java large-overload dispatcher, but they should not fall back to the
        // old affine sampler. Normalize them to a 64x64 page so every terrain
        // face goes through the same skip-0 scanline semantics while preserving
        // stable visual output for 128px pages parsed from the cache.
        var normalized = [Int32](repeating: 0, count: 64 * 64)
        for y in 0..<64 {
            let srcY = min(height - 1, (y * height) / 64)
            for x in 0..<64 {
                let srcX = min(width - 1, (x * width) / 64)
                normalized[y * 64 + x] = pixels[srcY * width + srcX]
            }
        }
        return normalized + normalized
    }

    private func polygonSpan(atY y: Int, screenPts: [(x: Int, y: Int)]) -> (x0: Int, x1: Int)? {
        guard screenPts.count >= 3 else { return nil }
        let sampleY = Double(y) + 0.5
        var xs: [Double] = []
        for i in 0..<screenPts.count {
            let a = screenPts[i]
            let b = screenPts[(i + 1) % screenPts.count]
            let y0 = Double(a.y)
            let y1 = Double(b.y)
            if y0 == y1 { continue }
            let minY = min(y0, y1)
            let maxY = max(y0, y1)
            guard sampleY >= minY && sampleY < maxY else { continue }
            let t = (sampleY - y0) / (y1 - y0)
            xs.append(Double(a.x) + t * Double(b.x - a.x))
        }
        guard xs.count >= 2 else { return nil }
        xs.sort()
        let left = Int(ceil(xs[0]))
        let right = Int(floor(xs[xs.count - 1]))
        guard left <= right else { return nil }
        return (left, right)
    }

    private func sampleTerrainTexture(_ texture: (index: Int, pixels: [Int32], width: Int, height: Int, ramps: Int),
                                      x: Int, y: Int,
                                      screenPts: [(x: Int, y: Int)],
                                      fallback: Int32) -> Int32? {
        guard let uv = terrainUVForScreenPoint(x: Double(x) + 0.5,
                                               y: Double(y) + 0.5,
                                               screenPts: screenPts) else { return nil }
        let u = max(0, min(texture.width - 1, Int(uv.u * Double(texture.width - 1))))
        let v = max(0, min(texture.height - 1, Int(uv.v * Double(texture.height - 1))))
        let ramp = terrainBrightnessRamp(for: fallback, rampCount: texture.ramps)
        let pageSize = texture.width * texture.height
        let pixel = texture.pixels[min(texture.pixels.count - 1, ramp * pageSize + v * texture.width + u)]

        // Java treats magenta as texture transparency after texture loading.
        // Keep the existing flat terrain colour for those holes.
        let rgb = UInt32(bitPattern: pixel) & 0x00FF_FFFF
        if rgb == 0 || rgb == 0x00FF_00FF {
            return fallback
        }
        return blendTerrainTexture(pixel, with: fallback)
    }

    private func terrainBrightnessRamp(for terrainColor: Int32, rampCount: Int) -> Int {
        guard rampCount > 1 else { return 0 }
        let terrain = UInt32(bitPattern: terrainColor)
        let r = Int((terrain >> 16) & 0xFF)
        let g = Int((terrain >> 8) & 0xFF)
        let b = Int(terrain & 0xFF)
        let luminance = (r * 30 + g * 59 + b * 11) / 100
        if luminance < 58 { return min(rampCount - 1, 3) }
        if luminance < 92 { return min(rampCount - 1, 2) }
        if luminance < 132 { return min(rampCount - 1, 1) }
        return 0
    }

    private func terrainUVForScreenPoint(x: Double, y: Double,
                                         screenPts: [(x: Int, y: Int)]) -> (u: Double, v: Double)? {
        guard screenPts.count >= 3 else { return nil }

        if screenPts.count >= 4 {
            let uv0 = (u: 0.0, v: 0.0)
            let uv1 = (u: 1.0, v: 0.0)
            let uv2 = (u: 1.0, v: 1.0)
            let uv3 = (u: 0.0, v: 1.0)
            if let uv = barycentricUV(x: x, y: y,
                                      p0: screenPts[0], p1: screenPts[1], p2: screenPts[2],
                                      uv0: uv0, uv1: uv1, uv2: uv2) {
                return uv
            }
            return barycentricUV(x: x, y: y,
                                 p0: screenPts[0], p1: screenPts[2], p2: screenPts[3],
                                 uv0: uv0, uv1: uv2, uv2: uv3)
        }

        return barycentricUV(x: x, y: y,
                             p0: screenPts[0], p1: screenPts[1], p2: screenPts[2],
                             uv0: (0.0, 0.0), uv1: (1.0, 0.0), uv2: (0.5, 1.0))
    }

    private func containsScreenPoint(x: Double, y: Double,
                                     screenPts: [(x: Int, y: Int)]) -> Bool {
        terrainUVForScreenPoint(x: x, y: y, screenPts: screenPts) != nil
    }

    private func barycentricUV(x: Double, y: Double,
                               p0: (x: Int, y: Int),
                               p1: (x: Int, y: Int),
                               p2: (x: Int, y: Int),
                               uv0: (u: Double, v: Double),
                               uv1: (u: Double, v: Double),
                               uv2: (u: Double, v: Double)) -> (u: Double, v: Double)? {
        let x0 = Double(p0.x), y0 = Double(p0.y)
        let x1 = Double(p1.x), y1 = Double(p1.y)
        let x2 = Double(p2.x), y2 = Double(p2.y)
        let denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        guard abs(denom) > 0.000001 else { return nil }

        let a = ((y1 - y2) * (x - x2) + (x2 - x1) * (y - y2)) / denom
        let b = ((y2 - y0) * (x - x2) + (x0 - x2) * (y - y2)) / denom
        let c = 1.0 - a - b
        let epsilon = -0.0001
        guard a >= epsilon, b >= epsilon, c >= epsilon else { return nil }

        return (
            u: a * uv0.u + b * uv1.u + c * uv2.u,
            v: a * uv0.v + b * uv1.v + c * uv2.v
        )
    }

    private func blendTerrainTexture(_ texturePixel: Int32, with terrainColor: Int32) -> Int32 {
        let texture = UInt32(bitPattern: texturePixel)
        let terrain = UInt32(bitPattern: terrainColor)

        let tr = Int((texture >> 16) & 0xFF)
        let tg = Int((texture >> 8) & 0xFF)
        let tb = Int(texture & 0xFF)

        let fr = Int((terrain >> 16) & 0xFF)
        let fg = Int((terrain >> 8) & 0xFF)
        let fb = Int(terrain & 0xFF)

        // Preserve texture detail but let the existing flat terrain colour
        // carry the current overlay/elevation tone until the Java brightness
        // ramp path replaces this lightweight sampler.
        let r = (tr * 3 + fr) / 4
        let g = (tg * 3 + fg) / 4
        let b = (tb * 3 + fb) / 4
        return Int32(bitPattern: 0xFF00_0000 | UInt32(r << 16) | UInt32(g << 8) | UInt32(b))
    }

    // MARK: - Rasterization

    private func rasterizePolygon(_ poly: Polygon, _ model: RSModel) {
        let faceIdx = Int(poly.faceID)
        guard faceIdx >= 0 && faceIdx < model.faceIndices.count else { return }
        let indices = model.faceIndices[faceIdx]

        let count = Int(model.faceIndexCount[faceIdx])
        guard count >= 3 else { return }

        // Backface culling: skip faces pointing away from camera
        // poly.orientation is not computed by the pipeline, so skip this check
        // to avoid culling all faces (orientation defaults to 0)

        let texFront = model.faceTextureFront[faceIdx]
        let hasTexture = texFront >= 0 && texFront < Int32(resourceDatabase.count)

        // Get texture pixels if available
        let texturePixels: [Int32]?
        if hasTexture, let tex = resourceDatabase[Int(texFront)] {
            texturePixels = tex
        } else {
            texturePixels = nil
        }

        // Clear scanline buffer for this polygon
        let minY = Int(max(0, poly.minP2))
        let maxY = Int(min(Int32(m_x.count - 1), poly.maxP2))
        guard minY <= maxY else { return }

        for y in minY...maxY {
            m_x[y].m_d = Int32.max
            m_x[y].m_k = Int32.min
        }

        // Walk polygon edges to fill scanline buffer
        for i in 0..<count {
            let v0Idx = Int(indices[i])
            let v1Idx = Int(indices[(i + 1) % count])
            walkEdge(model: model, v0: v0Idx, v1: v1Idx)
        }

        // Rasterize as flat color or textured
        if let pixels = texturePixels {
            rasterizeTextured(poly, model, indices, count, pixels)
        } else {
            rasterizeFlat(poly, model, indices, count)
        }
    }

    // Walk an edge and fill scanline bounds
    private func walkEdge(model: RSModel, v0: Int, v1: Int) {
        guard v0 < model.vertexParam2.count && v1 < model.vertexParam2.count else { return }

        // vertexParam6/vertexParam2 are centered at 0 — offset to screen coordinates
        let x0 = model.vertexParam6[v0] + m_A
        let y0 = model.vertexParam2[v0] + m_wb
        let x1 = model.vertexParam6[v1] + m_A
        let y1 = model.vertexParam2[v1] + m_wb

        let minY = Int(min(y0, y1))
        let maxY = Int(max(y0, y1))

        guard minY < m_x.count && maxY >= 0 else { return }

        let yStart = max(0, minY)
        let yEnd = min(m_x.count - 1, maxY)

        guard yStart <= yEnd else { return }

        let dy = y1 - y0
        let dx = x1 - x0

        if dy == 0 {
            // Horizontal edge
            let leftX = min(x0, x1)
            let rightX = max(x0, x1)
            for y in yStart...yEnd {
                m_x[y].m_d = min(m_x[y].m_d, leftX)
                m_x[y].m_k = max(m_x[y].m_k, rightX)
            }
        } else {
            // Bresenham-like edge walk
            let absDy = abs(dy)
            guard absDy > 0 else { return }
            let yDir: Int32 = y1 > y0 ? 1 : -1
            var x = x0
            var error: Int32 = 0

            for step in 0...Int(absDy) {
                let y = y0 + Int32(step) &* yDir
                if y >= 0 && y < Int32(m_x.count) {
                    m_x[Int(y)].m_d = min(m_x[Int(y)].m_d, x)
                    m_x[Int(y)].m_k = max(m_x[Int(y)].m_k, x)
                }

                error += abs(dx)
                if error * 2 >= absDy {
                    let xDir: Int32 = x1 > x0 ? 1 : -1
                    x += xDir
                    error -= absDy
                }
            }
        }
    }

    private func rasterizeTextured(_ poly: Polygon, _ model: RSModel, _ indices: [Int32], _ count: Int, _ texturePixels: [Int32]) {
        let minY = Int(max(0, poly.minP2))
        let maxY = Int(min(Int32(m_x.count - 1), poly.maxP2))
        guard minY <= maxY else { return }

        let color: Int32 = Int32(bitPattern: 0xFFAAAAAA)

        for y in minY...maxY {
            let scanline = m_x[y]
            if scanline.m_d <= scanline.m_k {
                graphics.drawLineHoriz(
                    x: scanline.m_d,
                    y: Int32(y),
                    width: scanline.m_k - scanline.m_d,
                    rgb: color
                )
            }
        }
    }

    private func rasterizeFlat(_ poly: Polygon, _ model: RSModel, _ indices: [Int32], _ count: Int) {
        let faceIdx = Int(poly.faceID)

        let texFront = model.faceTextureFront[faceIdx]
        let color: Int32
        if texFront < -1 || texFront > 100000 {
            color = texFront  // Packed ARGB from terrain
        } else {
            let diffuse = model.faceDiffuseLight[faceIdx]
            let brightness = Int32(diffuse & 0xFF)
            color = ((brightness << 16) | (brightness << 8) | brightness) | Int32(bitPattern: 0xFF000000)
        }

        let minY = Int(max(0, poly.minP2))
        let maxY = Int(min(Int32(m_x.count - 1), poly.maxP2))
        guard minY <= maxY else { return }

        for y in minY...maxY {
            let scanline = m_x[y]
            if scanline.m_d <= scanline.m_k {
                graphics.drawLineHoriz(
                    x: scanline.m_d,
                    y: Int32(y),
                    width: scanline.m_k - scanline.m_d,
                    rgb: color
                )
            }
        }
    }

    // MARK: - Texture management

    var loadedTextureCount: Int {
        resourceDatabase.reduce(0) { count, texture in
            texture == nil ? count : count + 1
        }
    }

    func loadTexture(index: Int, pixels: [Int32], type: Int, data: Data?) {
        guard index >= 0 else { return }
        ensureTextureCapacity(index + 1)
        resourceDatabase[index] = buildTexturePages(palette: pixels, type: type, data: data)
        textureTypes[index] = type
        textureIndexData[index] = data
        m_L[index] = pixels
        m_Hb[index] = Int32(type)
    }

    private func buildTexturePages(palette: [Int32], type: Int, data: Data?) -> [Int32] {
        guard let data, !data.isEmpty, !palette.isEmpty else { return palette }
        let size = type > 0 ? 128 : 64
        let baseCount = size * size
        guard data.count >= baseCount else { return palette }

        var pages = [Int32](repeating: 0, count: baseCount * 4)
        let mask: UInt32 = 0x00F8_F8FF
        for i in 0..<baseCount {
            let paletteIndex = Int(data[data.startIndex + i])
            let palettePixel = paletteIndex < palette.count ? palette[paletteIndex] : 0
            var rgb = UInt32(bitPattern: palettePixel) & 0x00FF_FFFF
            rgb &= mask
            if rgb == 0 {
                rgb = 1
            } else if rgb == 0x00F8_00FF {
                rgb = 0
            }

            let p0 = rgb
            let p1 = (p0 &- (p0 >> 3)) & mask
            let p2 = (p0 &- (p0 >> 2)) & mask
            let p3 = (p0 &- (p0 >> 3) &- (p0 >> 2)) & mask
            pages[i] = Int32(bitPattern: p0)
            pages[baseCount + i] = Int32(bitPattern: p1)
            pages[baseCount * 2 + i] = Int32(bitPattern: p2)
            pages[baseCount * 3 + i] = Int32(bitPattern: p3)
        }
        return pages
    }

    private func ensureTextureCapacity(_ needed: Int) {
        guard needed > resourceDatabase.count else { return }
        let newCount = max(needed, resourceDatabase.count * 2)
        resourceDatabase.append(contentsOf: [[Int32]?](repeating: nil, count: newCount - resourceDatabase.count))
        textureTypes.append(contentsOf: [Int](repeating: 0, count: newCount - textureTypes.count))
        textureIndexData.append(contentsOf: [Data?](repeating: nil, count: newCount - textureIndexData.count))
        m_L.append(contentsOf: [[Int32]](repeating: [], count: newCount - m_L.count))
        m_Hb.append(contentsOf: [Int32](repeating: 0, count: newCount - m_Hb.count))
    }

    func resourceToColor(_ resource: Int32) -> Int32 {
        // Palette lookup (simplified)
        return resource
    }

    // Matches Java Scene.java:566 setFrustum(int x, int y, int z, boolean)
    private func updateFrustum(_ x: Int32, _ y: Int32, _ z: Int32) {
        var fx = x; var fy = y; var fz = z

        let cpx = Int(cameraProjX & 1023)
        let cpy = Int(cameraProjY & 1023)
        let cpz = Int(cameraProjZ & 1023)

        // Apply camera rotation to frustum point
        if cpx != 0 {
            let sin = FastMath.trigTable1024[cpx]
            let cos = FastMath.trigTable1024[cpx + 1024]
            let tmp = (fy &* cos &- fz &* sin) >> 15
            fz = (fy &* sin &+ fz &* cos) >> 15
            fy = tmp
        }
        if cpy != 0 {
            let sin = FastMath.trigTable1024[cpy]
            let cos = FastMath.trigTable1024[cpy + 1024]
            let tmp = (fz &* sin &+ fx &* cos) >> 15
            fz = (fz &* cos &- fx &* sin) >> 15
            fx = tmp
        }
        if cpz != 0 {
            let sin = FastMath.trigTable1024[cpz]
            let cos = FastMath.trigTable1024[cpz + 1024]
            let tmp = (fy &* sin &+ fx &* cos) >> 15
            fy = (fy &* cos &- fx &* sin) >> 15
            fx = tmp
        }

        if fx < Scene.frustumMinY { Scene.frustumMinY = fx }
        if fx > Scene.frustumMaxY { Scene.frustumMaxY = fx }
        if fy < Scene.frustumNearZ { Scene.frustumNearZ = fy }
        if fy > Scene.frustumFarZ { Scene.frustumFarZ = fy }
        if fz < Scene.frustumMinX { Scene.frustumMinX = fz }
        if fz > Scene.frustumMaxX { Scene.frustumMaxX = fz }
    }

    func setDiffuseDir(x: Int32, y: Int32, z: Int32) {
        diffuseLightX = x
        diffuseLightY = y
        diffuseLightZ = z
    }
}
