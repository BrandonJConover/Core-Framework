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
    var m_n: Int = 0   // sprite count

    // Diffuse light direction
    var diffuseLightX: Int32 = 0
    var diffuseLightY: Int32 = 0
    var diffuseLightZ: Int32 = 0

    init(graphics: GraphicsController, modelCount: Int, polyCount: Int, spriteCount: Int) {
        self.graphics = graphics
        self.shader = Shader()

        // Initialize model array
        self.modelCount = 0
        self.models = [RSModel?](repeating: nil, count: modelCount)

        // Initialize polygon array
        self.m_zb = 0
        self.polygons = [Polygon](repeating: Polygon(), count: polyCount)

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

        // Initialize texture database
        self.resourceDatabase = [[Int32]?](repeating: nil, count: 50)
        self.m_L = [[Int32]](repeating: [], count: 50)
        self.m_Hb = [Int32](repeating: 0, count: 50)

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
        guard m_n < m_Ob.count else { return }

        // Register sprite position and dimensions
        m_ob[m_n] = var1  // depth
        m_Eb[m_n] = var2  // x
        m_Fb[m_n] = var3  // y
        m_gb[m_n] = var4  // width
        m_Q[m_n] = var5   // height
        m_Ob[m_n] = var6  // sprite index
        m_n += 1
    }

    func reduceSprites(_ count: Int32) {
        m_n = 0
    }

    // MARK: - Camera setup

    func setCamera(centerX: Int32, centerY: Int32, centerZ: Int32, xRot: Int32, yRot: Int32, zRot: Int32, offset: Int32) {
        // Set camera position
        cameraProjX = centerX
        cameraProjY = centerY
        cameraProjZ = centerZ

        // Set camera rotation in 1024-scale
        rot1024_off_x = xRot / 4
        rot1024_off_y = yRot / 4
        rot1024_off_z = zRot

        // Compute frustum bounds
        let fov = 512  // field of view
        Scene.frustumMinX = -Int32(fov)
        Scene.frustumMaxX = Int32(fov)
        Scene.frustumMinY = -Int32(fov)
        Scene.frustumMaxY = Int32(fov)
        Scene.frustumNearZ = 50
        Scene.frustumFarZ = 10000
    }

    // MARK: - Rendering

    func endScene(_ var1: Int32) {
        // Clear framebuffer
        graphics.blackScreen()

        // Transform all models to camera space
        for i in 0..<modelCount {
            guard let model = models[i] else { continue }

            // Apply camera transform
            model.rotate1024(
                yOffset: 0,
                vParamSrc: 0,
                xOffset: cameraProjX,
                zOffset: cameraProjZ,
                rotY: rot1024_off_y,
                rotZ: rot1024_off_z,
                rotX: rot1024_off_x,
                zTop: 5
            )
        }

        // Collect visible faces into polygon list
        m_zb = 0
        for i in 0..<modelCount {
            guard let model = models[i] else { continue }

            for faceIdx in 0..<Int(model.faceCount) {
                guard m_zb < polygons.count else { break }

                let poly = polygons[m_zb]
                poly.model = model
                poly.faceID = Int32(faceIdx)

                // Compute face normal (simplified)
                let indices = model.faceIndices[faceIdx]
                let count = model.faceIndexCount[faceIdx]

                if count >= 3 {
                    let v0 = Int(indices[0])
                    let v1 = Int(indices[1])
                    let v2 = Int(indices[2])

                    let x1 = model.vertXRot[v1] - model.vertXRot[v0]
                    let y1 = model.vertYRot[v1] - model.vertYRot[v0]
                    let z1 = model.vertZRot[v1] - model.vertZRot[v0]

                    let x2 = model.vertXRot[v2] - model.vertXRot[v0]
                    let y2 = model.vertYRot[v2] - model.vertYRot[v0]
                    let z2 = model.vertZRot[v2] - model.vertZRot[v0]

                    // Cross product for normal
                    poly.normalX = Int32((y1 &* z2) &- (z1 &* y2)) / 16384
                    poly.normalY = Int32((z1 &* x2) &- (x1 &* z2)) / 16384
                    poly.normalZ = Int32((x1 &* y2) &- (y1 &* x2)) / 16384
                }

                poly.minZ = model.minZ
                poly.maxZ = model.maxZ
                poly.minP2 = 999999
                poly.maxP2 = -999999
                poly.minP6 = 999999
                poly.maxP6 = -999999

                // Compute bounding box
                for j in 0..<Int(count) {
                    let vIdx = Int(indices[j])
                    let x = model.vertexParam6[vIdx]
                    let y = model.vertexParam2[vIdx]

                    if x < poly.minP6 { poly.minP6 = x }
                    if x > poly.maxP6 { poly.maxP6 = x }
                    if y < poly.minP2 { poly.minP2 = y }
                    if y > poly.maxP2 { poly.maxP2 = y }
                }

                m_zb += 1
            }
        }

        // Simple depth sort (painter's algorithm)
        // Sort polygons by max Z (back to front)
        let sortedIndices = (0..<m_zb).sorted { i, j in
            polygons[i].maxZ < polygons[j].maxZ
        }

        // Rasterize polygons in sorted order
        for idx in sortedIndices {
            let poly = polygons[idx]
            guard let model = poly.model else { continue }

            rasterizePolygon(poly, model)
        }

        // Render sprites (billboards)
        for i in 0..<m_n {
            let spriteX = m_Eb[i]
            let spriteY = m_Fb[i]
            let spriteW = m_gb[i]
            let spriteH = m_Q[i]
            let spriteIdx = Int(m_Ob[i])

            graphics.drawEntity(
                index: spriteIdx,
                x: spriteX,
                y: spriteY,
                width: spriteW,
                height: spriteH,
                perspective: 0
            )
        }
    }

    // MARK: - Rasterization

    private func rasterizePolygon(_ poly: Polygon, _ model: RSModel) {
        let faceIdx = Int(poly.faceID)
        guard faceIdx >= 0 && faceIdx < model.faceIndices.count else { return }
        let indices = model.faceIndices[faceIdx]

        let count = Int(model.faceIndexCount[faceIdx])
        guard count >= 3 else { return }

        // Backface culling: skip if orientation (dot product) is positive
        if poly.orientation > 0 {
            return
        }

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

        let x0 = model.vertexParam6[v0]
        let y0 = model.vertexParam2[v0]
        let x1 = model.vertexParam6[v1]
        let y1 = model.vertexParam2[v1]

        let minY = Int(min(y0, y1))
        let maxY = Int(max(y0, y1))

        guard minY < m_x.count && maxY >= 0 else { return }

        let yStart = max(0, minY)
        let yEnd = min(m_x.count - 1, maxY)

        if yStart > yEnd { return }

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
            let yDir = if y1 > y0 { 1 } else { -1 }
            var x = x0
            var error: Int32 = 0

            for step in 0...abs(dy) {
                let y = y0 + Int32(step) * Int32(yDir)
                if y >= 0 && y < Int32(m_x.count) {
                    m_x[Int(y)].m_d = min(m_x[Int(y)].m_d, x)
                    m_x[Int(y)].m_k = max(m_x[Int(y)].m_k, x)
                }

                error += abs(dx)
                if error * 2 >= abs(dy) {
                    let xDir = if x1 > x0 { 1 } else { -1 }
                    x += Int32(xDir)
                    error -= abs(dy)
                }
            }
        }
    }

    private func rasterizeTextured(_ poly: Polygon, _ model: RSModel, _ indices: [Int32], _ count: Int, _ texturePixels: [Int32]) {
        // Textured rendering: for now, fill with a light color
        // Full perspective-correct texture mapping would require complex setup with shader
        let minY = Int(max(0, poly.minP2))
        let maxY = Int(min(Int32(m_x.count - 1), poly.maxP2))

        let color: Int32 = Int32(bitPattern: 0xFFAAAAAA)  // Light gray for textured faces

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
        // Get diffuse light
        let faceIdx = Int(poly.faceID)
        let diffuse = model.faceDiffuseLight[faceIdx]
        let brightness = Int32(diffuse & 0xFF)

        // Simple color based on brightness
        let color = ((brightness << 16) | (brightness << 8) | brightness) | Int32(bitPattern: 0xFF000000)

        let minY = Int(max(0, poly.minP2))
        let maxY = Int(min(Int32(m_x.count - 1), poly.maxP2))

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

    func loadTexture(index: Int, pixels: [Int32], type: Int, data: Data?) {
        guard index >= 0 && index < resourceDatabase.count else { return }
        resourceDatabase[index] = pixels
    }

    func resourceToColor(_ resource: Int32) -> Int32 {
        // Palette lookup (simplified)
        return resource
    }

    func setDiffuseDir(x: Int32, y: Int32, z: Int32) {
        diffuseLightX = x
        diffuseLightY = y
        diffuseLightZ = z
    }
}
