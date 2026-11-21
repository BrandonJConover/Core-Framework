// Port of rsc-c scene.c (software renderer): visible face selection, painter's
// sort with intersection fix-ups, near-plane clipping, scanline generation and
// the flat/gouraud/textured rasterisers, plus 2D entity sprites and picking.
//
// C int arithmetic wraps (-fwrapv), so the maths here is Int32 with &+ &- &*.

public struct Scanline {
    public var startX: Int32 = 0
    public var endX: Int32 = 0
    public var startS: Int32 = 0
    public var endS: Int32 = 0
    public init() {}
    public init(startX: Int32, endX: Int32, startS: Int32, endS: Int32) {
        self.startX = startX; self.endX = endX; self.startS = startS; self.endS = endS
    }
}

public final class GamePolygon {
    public var minPlaneX: Int16 = 0
    public var minPlaneY: Int16 = 0
    public var maxPlaneX: Int16 = 0
    public var maxPlaneY: Int16 = 0
    public var face: Int16 = 0
    public var depth: Int16 = 0
    public var normalX: Int16 = 0
    public var normalY: Int16 = 0
    public var normalZ: Int16 = 0
    public var faceFill: Int16 = 0
    public var visited = false
    public var minZ: Int32 = 0
    public var maxZ: Int32 = 0
    public var visibility: Int32 = 0
    public var index: Int32 = 0
    public var index2: Int32 = -1
    public unowned(unsafe) var model: GameModel? = nil
    public init() {}
}

public final class Scene {
    public static let vertexCount = 40
    public static let rampCount = 50
    public static let rampSize: Int32 = 256
    public static let colourTransparent = Int(Int16.max)
    public static let scrollTextureSize = 64
    public static let scrollTextureArea = 64 * 64

    public var lastVisiblePolygonsCount = 0
    public var clipNear = 5
    public var clipFar3d = 0
    public var clipFar2d = 0
    public var fogZDistance = 0
    public var modelCount = 0
    public let maxModelCount: Int
    public let maxPolygonCount: Int
    public let maxSpriteCount: Int
    public var models: [GameModel?]
    public let view: GameModel
    public let raster: UnsafeMutablePointer<Int32>
    var gradientBase = [Int](repeating: 0, count: Scene.rampCount)
    let gradientRamps = Buf<Int32>(Scene.rampCount * Int(Scene.rampSize))
    var gradientRamp = 0
    public var textureCount = 0
    var textureColours: [[UInt8]?] = []
    var texturePalette: [[Int32]?] = []
    public var textureDimension: [Int8] = []
    var textureLoadedNumber: [Int64] = []
    public var texturePixels: [Buf<Int32>?] = []
    public var textureBackTransparent: [Bool] = []
    var textureColours64: [Buf<Int32>?] = []
    var length64 = 0
    var textureColours128: [Buf<Int32>?] = []
    var length128 = 0
    public var textureCountLoaded: Int64 = 0
    public let surface: Surface
    var scanlines = Buf<Scanline>(1, Scanline())
    public var minY = 0
    public var maxY = 0
    let planeX = Buf<Int32>(Scene.vertexCount)
    let planeY = Buf<Int32>(Scene.vertexCount)
    let vertexShade = Buf<Int32>(Scene.vertexCount)
    let vertexX = Buf<Int32>(Scene.vertexCount)
    let vertexY = Buf<Int32>(Scene.vertexCount)
    let vertexZ = Buf<Int32>(Scene.vertexCount)
    public var interlace = false
    var newStart = 0
    var newEnd = 0
    public var mousePickingActive = false
    public var mouseX = 0
    public var mouseY = 0
    public var mousePickedModels: [GameModel] = []
    public var mousePickedFaces: [Int] = []
    public var mousePickedCount: Int { mousePickedFaces.count }
    public var width = 0
    public var clipX = 0
    public var clipY = 0
    public var baseX = 0
    public var baseY = 0
    public var viewDistance = 512
    public var normalMagnitude = 4
    public var cameraX = 0, cameraY = 0, cameraZ = 0
    public var cameraYaw = 0, cameraPitch = 0, cameraRoll = 0
    public var frustum = Frustum()
    public var visiblePolygonsCount = 0
    public var visiblePolygons: [GamePolygon]
    public var spriteCount = 0
    public var spriteId: [Int]
    public var spriteX: [Int]
    public var spriteZ: [Int]
    public var spriteY: [Int]
    public var spriteWidth: [Int]
    public var spriteHeight: [Int]
    public var spriteTranslateX: [Int]

    public init(surface: Surface, modelCount: Int, polygonCount _: Int, maxSpriteCount: Int) {
        // rsc-c forces 32767 so resizing never runs out of polygons.
        let polygonCount = 32767
        self.surface = surface
        maxModelCount = modelCount
        maxPolygonCount = polygonCount
        self.maxSpriteCount = maxSpriteCount
        raster = surface.pixels
        models = Array(repeating: nil, count: modelCount + 1)
        visiblePolygons = (0..<polygonCount).map { _ in GamePolygon() }
        view = GameModel(vertices: maxSpriteCount * 2, faces: maxSpriteCount)
        spriteId = Array(repeating: 0, count: maxSpriteCount)
        spriteX = spriteId; spriteZ = spriteId; spriteY = spriteId
        spriteWidth = spriteId; spriteHeight = spriteId; spriteTranslateX = spriteId
    }

    // MARK: - Model and sprite management

    public func mousePick(_ model: GameModel, _ face: Int) {
        mousePickedModels.append(model)
        mousePickedFaces.append(face)
    }

    public func addModel(_ model: GameModel?) {
        guard let model else { return }
        if modelCount < maxModelCount {
            models[modelCount] = model
            modelCount += 1
        }
    }

    /// scene_remove_model. Passing nil removes nulled slots, like C's NULL pointer compare.
    public func removeModel(_ model: GameModel?) {
        var i = 0
        while i < modelCount {
            if models[i] === model {
                modelCount -= 1
                // memmove of model_count entries from i + 1, as in C.
                for j in i..<(models.count - 1) { models[j] = models[j + 1] }
                models[models.count - 1] = nil
            }
            i += 1
        }
    }

    public func nullModel(_ model: GameModel) {
        for i in 0..<modelCount where models[i] === model { models[i] = nil }
    }

    public func dispose() {
        for i in 0..<modelCount { models[i] = nil }
        clear()
        modelCount = 0
    }

    public func clear() {
        spriteCount = 0
        for i in 0..<view.faceCount { view.faceVertices[i] = [] }
        view.clear()
    }

    public func reduceSprites(_ i: Int) {
        spriteCount -= i
        view.reduce(deltaFaces: i, deltaVertices: i * 2)
        if spriteCount < 0 { spriteCount = 0 }
    }

    @discardableResult
    public func addSprite(id: Int, x: Int, y: Int, z: Int, width w: Int, height h: Int, tag: Int) -> Int {
        spriteId[spriteCount] = id
        spriteX[spriteCount] = x
        spriteZ[spriteCount] = y
        spriteY[spriteCount] = z
        spriteWidth[spriteCount] = w
        spriteHeight[spriteCount] = h
        spriteTranslateX[spriteCount] = 0
        let v0 = UInt16(truncatingIfNeeded: view.createVertex(x: x, y: y, z: z))
        let v1 = UInt16(truncatingIfNeeded: view.createVertex(x: x, y: y - h, z: z))
        view.createFace([v0, v1], fillFront: 0, fillBack: 0)
        view.faceTag![spriteCount] = Int32(truncatingIfNeeded: tag)
        view.isLocalPlayer![spriteCount] = 0
        spriteCount += 1
        return spriteCount - 1
    }

    public func setLocalPlayer(_ i: Int) { view.isLocalPlayer![i] = 1 }

    public func setSpriteTranslateX(_ i: Int, _ n: Int) { spriteTranslateX[i] = n }

    public func setMouseLocation(x: Int, y: Int) {
        mouseX = x - baseX
        mouseY = y
        mousePickedModels.removeAll(keepingCapacity: true)
        mousePickedFaces.removeAll(keepingCapacity: true)
        mousePickingActive = true
    }

    public func setBounds(width w: Int, height h: Int) {
        baseX = w / 2
        baseY = h / 2
        clipX = baseX
        clipY = baseY
        width = w
        scanlines = Buf<Scanline>(clipY + baseY, Scanline())
    }

    // MARK: - Camera

    func setFrustum(_ x0: Int, _ y0: Int, _ z0: Int) {
        var x = Int32(truncatingIfNeeded: x0), y = Int32(truncatingIfNeeded: y0), z = Int32(truncatingIfNeeded: z0)
        let yaw = (-cameraYaw + 1024) & 1023
        let pitch = (-cameraPitch + 1024) & 1023
        let roll = (-cameraRoll + 1024) & 1023
        let sc = Tables.sinCos2048
        if roll != 0 {
            let s = Int32(sc[roll]), c = Int32(sc[roll + 1024])
            let i3 = (y &* s &+ x &* c) / 32768
            y = (y &* c &- x &* s) / 32768
            x = i3
        }
        if yaw != 0 {
            let s = Int32(sc[yaw]), c = Int32(sc[yaw + 1024])
            let j3 = (y &* c &- z &* s) / 32768
            z = (y &* s &+ z &* c) / 32768
            y = j3
        }
        if pitch != 0 {
            let s = Int32(sc[pitch]), c = Int32(sc[pitch + 1024])
            let k3 = (z &* s &+ x &* c) / 32768
            z = (z &* c &- x &* s) / 32768
            x = k3
        }
        let xi = Int(x), yi = Int(y), zi = Int(z)
        if xi < frustum.maxX { frustum.maxX = xi }
        if xi > frustum.minX { frustum.minX = xi }
        if yi < frustum.maxY { frustum.maxY = yi }
        if yi > frustum.minY { frustum.minY = yi }
        if zi < frustum.farZ { frustum.farZ = zi }
        if zi > frustum.nearZ { frustum.nearZ = zi }
    }

    public func setCamera(x: Int, y: Int, z: Int, yaw y0: Int, pitch p0: Int, roll r0: Int, distance: Int) {
        let yaw = y0 & 1023, pitch = p0 & 1023, roll = r0 & 1023
        cameraYaw = (1024 - yaw) & 1023
        cameraPitch = (1024 - pitch) & 1023
        cameraRoll = (1024 - roll) & 1023
        var ox: Int32 = 0, oy: Int32 = 0, oz = Int32(truncatingIfNeeded: distance)
        let sc = Tables.sinCos2048
        if yaw != 0 {
            let s = Int32(sc[yaw]), c = Int32(sc[yaw + 1024])
            let i4 = (oy &* c &- oz &* s) >> 15
            oz = (oy &* s &+ oz &* c) >> 15
            oy = i4
        }
        if pitch != 0 {
            let s = Int32(sc[pitch]), c = Int32(sc[pitch + 1024])
            let j4 = (oz &* s &+ ox &* c) >> 15
            oz = (oz &* c &- ox &* s) >> 15
            ox = j4
        }
        if roll != 0 {
            let s = Int32(sc[roll]), c = Int32(sc[roll + 1024])
            let k4 = (oy &* s &+ ox &* c) >> 15
            oy = (oy &* c &- ox &* s) >> 15
            ox = k4
        }
        cameraX = x - Int(ox)
        cameraY = y - Int(oy)
        cameraZ = z - Int(oz)
    }

    // MARK: - 2D sprite polygons

    func initialisePolygon2d(_ index: Int) {
        let polygon = visiblePolygons[index]
        let m = polygon.model!
        let face = Int(polygon.face)
        let fv = m.faceVertices[face]
        let pz = m.projectVertexZ!, vvx = m.vertexViewX!, vvy = m.vertexViewY!
        let v0 = Int(fv[0]), v1 = Int(fv[1])
        m.normalMagnitude[face] = 1
        m.normalScale[face] = 0
        polygon.visibility = Int32(pz[v0])
        polygon.normalX = 0
        polygon.normalY = 0
        polygon.normalZ = 1
        var minZ = Int32(pz[v0]), maxZ = minZ
        var minPX = vvx[v0], maxPX = minPX
        if vvx[v1] < minPX { minPX = vvx[v1] } else { maxPX = vvx[v1] }
        var minPY = vvy[v1], maxPY = vvy[v0]
        var pv = Int32(pz[v1])
        if pv > maxZ { maxZ = pv } else if pv < minZ { minZ = pv }
        pv = vvx[v1]
        if pv > maxPX { maxPX = pv } else if pv < minPX { minPX = pv }
        pv = vvy[v1]
        if pv > maxPY { maxPY = pv } else if pv < minPY { minPY = pv }
        polygon.minZ = minZ
        polygon.maxZ = maxZ
        polygon.minPlaneX = Int16(truncatingIfNeeded: minPX &- 20)
        polygon.maxPlaneX = Int16(truncatingIfNeeded: maxPX &+ 20)
        polygon.minPlaneY = Int16(truncatingIfNeeded: minPY)
        polygon.maxPlaneY = Int16(truncatingIfNeeded: maxPY)
    }

    public func initialisePolygons2d() {
        guard view.faceCount > 0 else { return }
        let pz = view.projectVertexZ!, vvx = view.vertexViewX!, vvy = view.vertexViewY!
        for face in 0..<view.faceCount {
            let fv = view.faceVertices[face]
            let v0 = Int(fv[0])
            let projectZ = Int(pz[v0])
            if projectZ < clipNear || projectZ > clipFar2d { continue }
            let viewX = Int(vvx[v0]), viewY = Int(vvy[v0])
            let viewWidth = Scene.cdiv(spriteWidth[face] * viewDistance, projectZ)
            let viewHeight = Scene.cdiv(spriteHeight[face] * viewDistance, projectZ)
            if viewX - viewWidth / 2 <= clipX && viewX + viewWidth / 2 >= -clipX &&
                viewY - viewHeight <= clipY && viewY >= -clipY {
                if visiblePolygonsCount >= maxPolygonCount - 1 { break }
                let polygon = visiblePolygons[visiblePolygonsCount]
                polygon.model = view
                polygon.face = Int16(truncatingIfNeeded: face)
                initialisePolygon2d(visiblePolygonsCount)
                polygon.depth = Int16(truncatingIfNeeded: (projectZ + Int(pz[Int(fv[1])])) / 2)
                visiblePolygonsCount += 1
            }
        }
    }

    public func renderPolygon2dFace(_ face: Int) {
        let fv = view.faceVertices[face]
        let v0 = Int(fv[0])
        let viewX = Int(view.vertexViewX![v0])
        let viewY = Int(view.vertexViewY![v0])
        let projectZ = Int(view.projectVertexZ![v0])
        let w = Scene.cdiv(spriteWidth[face] * viewDistance, projectZ)
        let h = Scene.cdiv(spriteHeight[face] * viewDistance, projectZ)
        let skewX = Int(view.vertexViewX![Int(fv[1])]) - viewX
        var x = viewX - w / 2
        let y = baseY + viewY - h
        surface.drawEntitySprite(x: x + baseX, y: y, width: w, height: h, id: spriteId[face], tx: skewX,
                                 ty: Scene.cdiv(256 * viewDistance, projectZ))
        if mousePickingActive {
            x += Scene.cdiv(spriteTranslateX[face] * viewDistance, projectZ)
            if mouseY >= y && mouseY <= y + h && mouseX >= x && mouseX <= x + w &&
                !view.unpickable && view.isLocalPlayer![face] == 0 {
                mousePick(view, face)
            }
        }
    }

    /// C division truncates toward zero, like Swift's; this only exists to keep a 0 divisor from trapping
    /// where C would also fault, which never happens for z >= clip_near.
    @inline(__always) static func cdiv(_ a: Int, _ b: Int) -> Int {
        Int(Int32(truncatingIfNeeded: a) / Int32(truncatingIfNeeded: b))
    }

    // MARK: - Render

    public func render() {
        interlace = surface.interlace
        let frustumX = (clipX * clipFar3d) / viewDistance
        let frustumY = (clipY * clipFar3d) / viewDistance
        frustum = Frustum()
        setFrustum(-frustumX, -frustumY, clipFar3d)
        setFrustum(-frustumX, frustumY, clipFar3d)
        setFrustum(frustumX, -frustumY, clipFar3d)
        setFrustum(frustumX, frustumY, clipFar3d)
        setFrustum(-clipX, -clipY, 0)
        setFrustum(-clipX, clipY, 0)
        setFrustum(clipX, -clipY, 0)
        setFrustum(clipX, clipY, 0)
        frustum.maxX += cameraX
        frustum.minX += cameraX
        frustum.maxY += cameraY
        frustum.minY += cameraY
        frustum.farZ += cameraZ
        frustum.nearZ += cameraZ

        models[modelCount] = view
        view.transformState = GameModel.transformReset

        // game_model_project's parameters are (pitch, roll, yaw) but scene passes (yaw, pitch, roll).
        for i in 0...modelCount {
            models[i]?.project(cameraX: cameraX, cameraY: cameraY, cameraZ: cameraZ, pitch: cameraYaw,
                               roll: cameraPitch, yaw: cameraRoll, viewDistance: viewDistance,
                               clipNear: clipNear, frustum: frustum)
        }

        visiblePolygonsCount = 0
        let cx = Int32(clipX), cy = Int32(clipY)

        for i in 0..<modelCount {
            guard let m = models[i], m.visible, m.faceCount > 0 else { continue }
            let pz = m.projectVertexZ!, vvx = m.vertexViewX!, vvy = m.vertexViewY!
            for face in 0..<m.faceCount {
                let vc = Int(m.faceVertexCount[face])
                let fv = m.faceVertices[face]
                var visible = false
                for v in 0..<vc {
                    let z = Int(pz[Int(fv[v])])
                    if z <= clipNear || z >= clipFar3d { continue }
                    visible = true
                    break
                }
                if !visible { continue }
                var vxc = 0
                for v in 0..<vc {
                    let x = vvx[Int(fv[v])]
                    if x > -cx { vxc |= 1 }
                    if x < cx { vxc |= 2 }
                    if vxc == 3 { break }
                }
                if vxc != 3 { continue }
                var vyc = 0
                for v in 0..<vc {
                    let y = vvy[Int(fv[v])]
                    if y > -cy { vyc |= 1 }
                    if y < cy { vyc |= 2 }
                    if vyc == 3 { break }
                }
                if vyc != 3 { continue }
                if visiblePolygonsCount >= maxPolygonCount - 1 { break }
                let polygon = visiblePolygons[visiblePolygonsCount]
                polygon.model = m
                polygon.face = Int16(truncatingIfNeeded: face)
                initialisePolygon3d(visiblePolygonsCount)
                let fill: Int
                if polygon.visibility < 0 {
                    fill = Int(m.faceFillFront[face])
                } else {
                    fill = Int(m.faceFillBack[face])
                }
                if fill != Scene.colourTransparent {
                    var h: Int32 = 0
                    for v in 0..<vc { h &+= Int32(pz[Int(fv[v])]) }
                    polygon.depth = Int16(truncatingIfNeeded: h / Int32(vc) &+ Int32(truncatingIfNeeded: m.depth))
                    polygon.faceFill = Int16(truncatingIfNeeded: fill)
                    visiblePolygonsCount += 1
                }
            }
        }

        initialisePolygons2d()

        if visiblePolygonsCount == 0 { return }
        lastVisiblePolygonsCount = visiblePolygonsCount

        Scene.sortByDepth(&visiblePolygons, count: visiblePolygonsCount)
        polygonsIntersectSort(step: 100, count: visiblePolygonsCount)

        for i in 0..<visiblePolygonsCount {
            let polygon = visiblePolygons[i]
            let m = polygon.model!
            let face = Int(polygon.face)
            if m === view {
                renderPolygon2dFace(face)
                continue
            }
            renderPolygon3d(polygon, m, face)
        }

        mousePickingActive = false
    }

    private func renderPolygon3d(_ polygon: GamePolygon, _ m: GameModel, _ face: Int) {
        var planeIndex = 0
        var shade: Int32 = 0
        let fvc = Int(m.faceVertexCount[face])
        let fv = m.faceVertices[face]
        let px = m.projectVertexX!, py = m.projectVertexY!, pz = m.projectVertexZ!
        let vvx = m.vertexViewX!, vvy = m.vertexViewY!
        let near = Int32(clipNear), vd = Int32(viewDistance), fog = Int32(fogZDistance)
        let ambience = Int32(truncatingIfNeeded: m.lightAmbience)
        let faceIntensity = m.faceIntensity[face]
        let gouraud = faceIntensity == GameModel.useGouraud

        if !gouraud {
            if polygon.visibility < 0 {
                shade = ambience &- Int32(faceIntensity)
            } else {
                shade = ambience &+ Int32(faceIntensity)
            }
        }

        for j in 0..<fvc {
            let v = Int(fv[j])
            vertexX[j] = Int32(px[v])
            vertexY[j] = Int32(py[v])
            vertexZ[j] = Int32(pz[v])
            if gouraud {
                if polygon.visibility < 0 {
                    shade = ambience &- Int32(m.vertexIntensity[v]) &+ Int32(m.vertexAmbience[v])
                } else {
                    shade = ambience &+ Int32(m.vertexIntensity[v]) &+ Int32(m.vertexAmbience[v])
                }
            }
            let zv = Int32(pz[v])
            if zv >= near {
                planeX[planeIndex] = vvx[v]
                planeY[planeIndex] = vvy[v]
                vertexShade[planeIndex] = shade
                if zv > fog { vertexShade[planeIndex] &+= zv &- fog }
                planeIndex += 1
            } else {
                var prev = j == 0 ? Int(fv[fvc - 1]) : Int(fv[j - 1])
                if Int32(pz[prev]) >= near {
                    let k7 = zv &- Int32(pz[prev])
                    let i5 = Int32(px[v]) &- ((Int32(px[v]) &- Int32(px[prev])) &* (zv &- near)) / k7
                    let j6 = Int32(py[v]) &- ((Int32(py[v]) &- Int32(py[prev])) &* (zv &- near)) / k7
                    planeX[planeIndex] = (i5 &* vd) / near
                    planeY[planeIndex] = (j6 &* vd) / near
                    vertexShade[planeIndex] = shade
                    planeIndex += 1
                }
                prev = j == fvc - 1 ? Int(fv[0]) : Int(fv[j + 1])
                if Int32(pz[prev]) >= near {
                    // rsc-c bug kept for parity: these interpolate between prev and prev (a zero delta).
                    let l7 = zv &- Int32(pz[prev])
                    let j5 = Int32(px[v]) &- ((Int32(px[prev]) &- Int32(px[prev])) &* (Int32(pz[prev]) &- near)) / l7
                    let k6 = Int32(py[prev]) &- ((Int32(py[prev]) &- Int32(py[prev])) &* (Int32(pz[prev]) &- near)) / l7
                    planeX[planeIndex] = (j5 &* vd) / near
                    planeY[planeIndex] = (k6 &* vd) / near
                    vertexShade[planeIndex] = shade
                    planeIndex += 1
                }
            }
        }

        let fill = Int(polygon.faceFill)
        for j in 0..<fvc {
            if vertexShade[j] < 0 {
                vertexShade[j] = 0
            } else if vertexShade[j] > 255 {
                vertexShade[j] = 255
            }
            if fill >= 0 {
                let dim = fill < textureCount ? textureDimension[fill] : 0
                if dim == 1 {
                    vertexShade[j] <<= 9
                } else {
                    vertexShade[j] <<= 6
                }
            }
        }

        generateScanlines(planeIndex, m, face)
        if maxY > minY {
            rasterize(fvc, fill, m)
        }
    }

    // MARK: - Depth sort

    /// glibc's qsort (a stable top-down merge sort) with scene_polygon_depth_compare. The comparator is not
    /// a strict ordering, so the exact merge order matters for matching rsc-c output.
    static func sortByDepth(_ a: inout [GamePolygon], count: Int) {
        guard count > 1 else { return }
        var tmp = [GamePolygon](a[0..<count])
        a.withUnsafeMutableBufferPointer { buf in
            tmp.withUnsafeMutableBufferPointer { t in
                msort(buf.baseAddress!, count, t.baseAddress!)
            }
        }
    }

    @inline(__always) static func depthCompare(_ a: GamePolygon, _ b: GamePolygon) -> Int {
        if a.depth == 0 { return -1 }
        return Int(b.depth) - Int(a.depth)
    }

    private static func msort(_ b: UnsafeMutablePointer<GamePolygon>, _ n: Int, _ t: UnsafeMutablePointer<GamePolygon>) {
        if n <= 1 { return }
        var n1 = n / 2
        var n2 = n - n1
        let b1Start = b
        let b2Start = b + n1
        msort(b1Start, n1, t)
        msort(b2Start, n2, t)
        var b1 = b1Start, b2 = b2Start, tp = t
        while n1 > 0 && n2 > 0 {
            if depthCompare(b1.pointee, b2.pointee) <= 0 {
                tp.pointee = b1.pointee; tp += 1; b1 += 1; n1 -= 1
            } else {
                tp.pointee = b2.pointee; tp += 1; b2 += 1; n2 -= 1
            }
        }
        while n1 > 0 { tp.pointee = b1.pointee; tp += 1; b1 += 1; n1 -= 1 }
        let copied = n - n2
        for i in 0..<copied { b[i] = t[i] }
    }

    func polygonsIntersectSort(step: Int, count: Int) {
        for i in 0...count {
            let p = visiblePolygons[i]
            p.visited = false
            p.index = Int32(i)
            p.index2 = -1
        }
        var l = 0
        while true {
            while visiblePolygons[l].visited { l += 1 }
            if l == count { return }
            let polygon = visiblePolygons[l]
            polygon.visited = true
            var start = l
            var end = l + step
            if end >= count { end = count - 1 }
            var i = end
            while i >= start + 1 {
                let other = visiblePolygons[i]
                if polygon.minPlaneX < other.maxPlaneX && other.minPlaneX < polygon.maxPlaneX &&
                    polygon.minPlaneY < other.maxPlaneY && other.minPlaneY < polygon.maxPlaneY &&
                    polygon.index != other.index2 && !Scene.separatePolygon(polygon, other) &&
                    Scene.heuristicPolygon(other, polygon) {
                    _ = polygonsOrder(start, i)
                    if visiblePolygons[i] !== other { i += 1 }
                    start = newStart
                    other.index2 = polygon.index
                }
                i -= 1
            }
        }
    }

    func polygonsOrder(_ s: Int, _ e: Int) -> Bool {
        var start = s, end = e
        while true {
            let polygonStart = visiblePolygons[start]
            var i = start + 1
            while i <= end {
                let polygon = visiblePolygons[i]
                if !Scene.separatePolygon(polygon, polygonStart) { break }
                visiblePolygons[start] = polygon
                visiblePolygons[i] = polygonStart
                start = i
                if start == end {
                    newStart = start
                    newEnd = start - 1
                    return true
                }
                i += 1
            }
            let polygonEnd = visiblePolygons[end]
            i = end - 1
            while i >= start {
                let polygon = visiblePolygons[i]
                if !Scene.separatePolygon(polygonEnd, polygon) { break }
                visiblePolygons[end] = polygon
                visiblePolygons[i] = polygonEnd
                end = i
                if start == end {
                    newStart = end + 1
                    newEnd = end
                    return true
                }
                i -= 1
            }
            if start + 1 >= end {
                newStart = start
                newEnd = end
                return false
            }
            if !polygonsOrder(start + 1, end) {
                newStart = start
                return false
            }
            end = newEnd
        }
    }

    func initialisePolygon3d(_ index: Int) {
        let polygon = visiblePolygons[index]
        let m = polygon.model!
        let face = Int(polygon.face)
        let fv = m.faceVertices[face]
        let fvc = Int(m.faceVertexCount[face])
        let px = m.projectVertexX!, py = m.projectVertexY!, pz = m.projectVertexZ!
        let vvx = m.vertexViewX!, vvy = m.vertexViewY!
        var normalScale = Int32(m.normalScale[face])
        let v0 = Int(fv[0]), v1 = Int(fv[1]), v2 = Int(fv[2])
        let xa = Int32(px[v0]), ya = Int32(py[v0]), za = Int32(pz[v0])
        let xba = Int32(px[v1]) &- xa, yba = Int32(py[v1]) &- ya, zba = Int32(pz[v1]) &- za
        let xca = Int32(px[v2]) &- xa, yca = Int32(py[v2]) &- ya, zca = Int32(pz[v2]) &- za
        var nx = yba &* zca &- yca &* zba
        var ny = zba &* xca &- zca &* xba
        var nz = xba &* yca &- xca &* yba

        if normalScale == -1 {
            normalScale = 0
            while nx > 25000 || ny > 25000 || nz > 25000 || nx < -25000 || ny < -25000 || nz < -25000 {
                normalScale += 1
                nx >>= 1
                ny >>= 1
                nz >>= 1
            }
            m.normalScale[face] = Int16(truncatingIfNeeded: normalScale)
            let sum = nx &* nx &+ ny &* ny &+ nz &* nz
            m.normalMagnitude[face] = Scene.toInt32(Double(normalMagnitude) * Double(sum).squareRoot())
        } else {
            nx >>= normalScale
            ny >>= normalScale
            nz >>= normalScale
        }

        polygon.visibility = xa &* nx &+ ya &* ny &+ za &* nz
        polygon.normalX = Int16(truncatingIfNeeded: nx)
        polygon.normalY = Int16(truncatingIfNeeded: ny)
        polygon.normalZ = Int16(truncatingIfNeeded: nz)

        var minZ = za, maxZ = za
        var minPX = vvx[v0], maxPX = minPX
        var minPY = vvy[v0], maxPY = minPY
        if fvc > 1 {
            for i in 1..<fvc {
                let v = Int(fv[i])
                var p = Int32(pz[v])
                if p > maxZ { maxZ = p } else if p < minZ { minZ = p }
                p = vvx[v]
                if p > maxPX { maxPX = p } else if p < minPX { minPX = p }
                p = vvy[v]
                if p > maxPY { maxPY = p } else if p < minPY { minPY = p }
            }
        }
        polygon.minZ = minZ
        polygon.maxZ = maxZ
        polygon.minPlaneX = Int16(truncatingIfNeeded: minPX)
        polygon.maxPlaneX = Int16(truncatingIfNeeded: maxPX)
        polygon.minPlaneY = Int16(truncatingIfNeeded: minPY)
        polygon.maxPlaneY = Int16(truncatingIfNeeded: maxPY)
    }

    /// C's double -> int conversion for in-range values (truncation toward zero).
    @inline(__always) static func toInt32(_ d: Double) -> Int32 {
        if d.isNaN { return Int32.min }
        if d >= 2147483648.0 || d < -2147483648.0 { return Int32.min }
        return Int32(d)
    }

    // MARK: - Polygon separation tests

    private static func planeTest(_ a: GamePolygon, _ b: GamePolygon, _ firstSign: Bool) -> Bool {
        // Returns true when some vertex of `a` lies on the wrong side of `b`'s plane.
        let ma = a.model!, mb = b.model!
        let fa = ma.faceVertices[Int(a.face)], fb = mb.faceVertices[Int(b.face)]
        let fca = Int(ma.faceVertexCount[Int(a.face)])
        let bpx = mb.projectVertexX!, bpy = mb.projectVertexY!, bpz = mb.projectVertexZ!
        let apx = ma.projectVertexX!, apy = ma.projectVertexY!, apz = ma.projectVertexZ!
        let fx = Int32(bpx[Int(fb[0])]), fy = Int32(bpy[Int(fb[0])]), fz = Int32(bpz[Int(fb[0])])
        let nx = Int32(b.normalX), ny = Int32(b.normalY), nz = Int32(b.normalZ)
        let nm = mb.normalMagnitude[Int(b.face)]
        let vis = b.visibility
        for i in 0..<fca {
            let v = Int(fa[i])
            let mag = (fx &- Int32(apx[v])) &* nx &+ (fy &- Int32(apy[v])) &* ny &+ (fz &- Int32(apz[v])) &* nz
            if firstSign {
                if (mag >= 0 &- nm || vis >= 0) && (mag <= nm || vis <= 0) { continue }
            } else {
                if (mag >= 0 &- nm || vis <= 0) && (mag <= nm || vis >= 0) { continue }
            }
            return true
        }
        return false
    }

    private static func outline(_ p: GamePolygon) -> ([Int32], [Int32]) {
        let m = p.model!
        let face = Int(p.face)
        let fv = m.faceVertices[face]
        let n = Int(m.faceVertexCount[face])
        let vvx = m.vertexViewX!, vvy = m.vertexViewY!
        if n == 2 {
            let a = Int(fv[0]), b = Int(fv[1])
            return ([vvx[a] &- 20, vvx[b] &- 20, vvx[b] &+ 20, vvx[a] &+ 20],
                    [vvy[a], vvy[b], vvy[b], vvy[a]])
        }
        var xs = [Int32](repeating: 0, count: n), ys = xs
        for i in 0..<n {
            xs[i] = vvx[Int(fv[i])]
            ys[i] = vvy[Int(fv[i])]
        }
        return (xs, ys)
    }

    static func separatePolygon(_ a: GamePolygon, _ b: GamePolygon) -> Bool {
        if a.minPlaneX >= b.maxPlaneX { return true }
        if b.minPlaneX >= a.maxPlaneX { return true }
        if a.minPlaneY >= b.maxPlaneY { return true }
        if b.minPlaneY >= a.maxPlaneY { return true }
        if a.minZ >= b.maxZ { return true }
        if b.minZ > a.maxZ { return false }
        if !planeTest(a, b, true) { return true }
        if !planeTest(b, a, false) { return true }
        let (xa, ya) = outline(a)
        let (xb, yb) = outline(b)
        return !intersect(xa, ya, xb, yb, xa.count, xb.count)
    }

    static func heuristicPolygon(_ a: GamePolygon, _ b: GamePolygon) -> Bool {
        if !planeTest(a, b, true) { return true }
        return !planeTest(b, a, false)
    }

    @inline(__always) static func m306(_ i: Int32, _ j: Int32, _ k: Int32, _ l: Int32, _ i1: Int32) -> Int32 {
        if l == j { return i }
        return i &+ ((k &- i) &* (i1 &- j)) / (l &- j)
    }

    @inline(__always) static func m307(_ i: Int32, _ j: Int32, _ k: Int32, _ l: Int32, _ flag: Bool) -> Bool {
        if (flag && i <= k) || i < k {
            if i > l { return true }
            if j > k { return true }
            if j > l { return true }
            return !flag
        }
        if i < l { return true }
        if j < k { return true }
        if j < l { return true }
        return flag
    }

    @inline(__always) static func m308(_ i: Int32, _ j: Int32, _ k: Int32, _ flag: Bool) -> Bool {
        if (flag && i <= k) || i < k {
            if j > k { return true }
            return !flag
        }
        if j < k { return true }
        return flag
    }

    // MARK: - Textures

    public func allocateTextures(count: Int, length64 l64: Int, length128 l128: Int) {
        textureCount = count
        textureColours = Array(repeating: nil, count: count)
        texturePalette = Array(repeating: nil, count: count)
        textureLoadedNumber = Array(repeating: 0, count: count)
        textureDimension = Array(repeating: 0, count: count)
        textureBackTransparent = Array(repeating: false, count: count)
        texturePixels = Array(repeating: nil, count: count)
        textureCountLoaded = 0
        textureColours64 = Array(repeating: nil, count: l64)
        length64 = l64
        textureColours128 = Array(repeating: nil, count: l128)
        length128 = l128
    }

    public func defineTexture(_ id: Int, colours: [UInt8], palette: [Int32], wide128: Bool) {
        textureColours[id] = colours
        texturePalette[id] = palette
        textureDimension[id] = wide128 ? 1 : 0
        textureLoadedNumber[id] = 0
        textureBackTransparent[id] = false
        texturePixels[id] = nil
        prepareTexture(id)
    }

    func prepareTexture(_ id: Int) {
        if id < 0 { return }
        var maxId: Int64 = 1 << 30
        var oldId = 0
        textureCountLoaded += 1
        textureLoadedNumber[id] = textureCountLoaded
        if textureCountLoaded == maxId - 1 {
            textureCountLoaded = 0
            textureLoadedNumber[id] = textureCountLoaded
        }
        if texturePixels[id] != nil { return }
        if textureDimension[id] == 0 {
            for i in 0..<length64 where textureColours64[i] == nil {
                let b = Buf<Int32>(128 * 128)
                textureColours64[i] = b
                texturePixels[id] = b
                setTexturePixels(id)
                return
            }
        } else {
            for i in 0..<length128 where textureColours128[i] == nil {
                let b = Buf<Int32>(256 * 256)
                textureColours128[i] = b
                texturePixels[id] = b
                setTexturePixels(id)
                return
            }
        }
        for i in 0..<textureCount {
            if i != id && textureDimension[i] == textureDimension[id] && texturePixels[i] != nil &&
                textureLoadedNumber[i] < maxId {
                maxId = textureLoadedNumber[i]
                oldId = i
            }
        }
        texturePixels[id] = texturePixels[oldId]
        texturePixels[oldId] = nil
        setTexturePixels(id)
    }

    func setTexturePixels(_ id: Int) {
        let tw = textureDimension[id] != 0 ? 128 : 64
        guard let colours = texturePixels[id], let src = textureColours[id], let palette = texturePalette[id] else {
            return
        }
        var count = 0
        for x in 0..<tw {
            for y in 0..<tw {
                var colour = palette[Int(src[y + x * tw])] & 0xf8f8ff
                if colour == 0 {
                    colour = 1
                } else if colour == 0xf800ff {
                    colour = 0
                    textureBackTransparent[id] = true
                }
                colours[count] = colour
                count += 1
            }
        }
        for i in 0..<count {
            let c = colours[i]
            colours[count + i] = (c &- (c >> 3)) & 0xf8f8ff
            colours[count * 2 + i] = (c &- (c >> 2)) & 0xf8f8ff
            colours[count * 3 + i] = (c &- (c >> 2) &- (c >> 3)) & 0xf8f8ff
        }
    }

    public func scrollTexture(_ id: Int) {
        guard let colours = texturePixels[id] else { return }
        let size = Scene.scrollTextureSize, area = Scene.scrollTextureArea
        for i in 0..<size {
            var p = i + area - size
            let colour = colours[p]
            for _ in 0..<(size - 1) {
                colours[p] = colours[p - size]
                p -= size
            }
            colours[p] = colour
        }
        for i in 0..<area {
            let c = colours[i]
            colours[area + i] = (c &- (c >> 3)) & 0xf8f8ff
            colours[area * 2 + i] = (c &- (c >> 2)) & 0xf8f8ff
            colours[area * 3 + i] = (c &- (c >> 2) &- (c >> 3)) & 0xf8f8ff
        }
    }

    public static func rgbToFill(_ r: Int, _ g: Int, _ b: Int) -> Int16 {
        Int16(truncatingIfNeeded: -1 - (((r & 0xff) >> 3) << 10) - (((g & 0xff) >> 3) << 5) - ((b & 0xff) >> 3))
    }

    public func fillColour(_ faceFill: Int) -> Int {
        var fill = faceFill
        if fill == Scene.colourTransparent { return 0 }
        prepareTexture(fill)
        if fill >= 0 { return Int(texturePixels[fill]![0]) }
        fill = -(fill + 1)
        let r = (fill >> 10) & 0x1f, g = (fill >> 5) & 0x1f, b = fill & 0x1f
        return (r << 19) + (g << 11) + (b << 3)
    }

    public func setLightDirection(x: Int, y: Int, z: Int) {
        let x = (x == 0 && y == 0 && z == 0) ? 32 : x
        for i in 0..<modelCount { models[i]?.setLightDirection(x: x, y: y, z: z) }
    }

    public func setLight(ambience: Int, diffuse: Int, x: Int, y: Int, z: Int) {
        let x = (x == 0 && y == 0 && z == 0) ? 32 : x
        for i in 0..<modelCount {
            models[i]?.setLightIntensity(ambience: ambience, diffuse: diffuse, x: x, y: y, z: z)
        }
    }
}
