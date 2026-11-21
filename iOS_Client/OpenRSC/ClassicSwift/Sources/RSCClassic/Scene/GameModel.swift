// 3D model: vertices, faces, lighting and transforms. Port of rsc-c's game-model.c.
// Storage widths (Int16 vertices, Int8 ambience, ...) match C so overflow wraps identically.

import Foundation

public final class GameModel {
    public static let transformBegin = 1
    public static let transformReset = 2
    public static let transformTranslate = 1
    public static let transformRotate = 2
    public static let useGouraud = Int16.max
    public static let colourTransparent = Int(Int16.max)

    public var vertexCount = 0
    public var projectVertexX: Buf<Int16>?
    public var projectVertexY: Buf<Int16>?
    public var projectVertexZ: Buf<Int16>?
    public var vertexViewX: Buf<Int32>?
    public var vertexViewY: Buf<Int32>?
    public var vertexIntensity: Buf<Int16>!
    public var vertexAmbience: Buf<Int8>!
    public var faceCount = 0
    public var faceVertexCount: Buf<UInt8>!
    public var faceVertices: [[UInt16]] = []
    public var faceFillFront: Buf<Int16>!
    public var faceFillBack: Buf<Int16>!
    public var faceIntensity: Buf<Int16>!
    public var faceNormalX: Buf<Int16>?
    public var faceNormalY: Buf<Int16>?
    public var faceNormalZ: Buf<Int16>?
    public var normalScale: Buf<Int16>!
    public var normalMagnitude: Buf<Int32>!
    public var depth = 0
    public var visible = true
    public var minX = 0, maxX = 0, minY = 0, maxY = 0, minZ = 0, maxZ = 0
    public var unpickable = false
    public var key = -1
    public var faceTag: Buf<Int32>?
    public var transparent = false
    public var isLocalPlayer: Buf<Int8>?
    public var isolated = false
    public var projected = false
    public var maxVertices = 0
    public var vertexX: Buf<Int16>!
    public var vertexY: Buf<Int16>!
    public var vertexZ: Buf<Int16>!
    public var vertexTransformedX: Buf<Int16>!
    public var vertexTransformedY: Buf<Int16>!
    public var vertexTransformedZ: Buf<Int16>!
    public var unlit = false
    public var lightAmbience = 32
    public var lightDiffuse = 512
    public var lightDirectionX = 180
    public var lightDirectionY = 155
    public var lightDirectionZ = 95
    public var lightDirectionMagnitude = 256
    public var autocommit = false
    public var maxFaces = 0
    public var baseX = 0, baseY = 0, baseZ = 0
    public var orientationYaw = 0, orientationPitch = 0, orientationRoll = 0
    public var transformType = 0
    public var transformState = GameModel.transformBegin

    public init() {}

    public convenience init(vertices: Int, faces: Int) {
        self.init()
        allocate(vertices: vertices, faces: faces)
    }

    public convenience init(vertices: Int, faces: Int, autocommit: Bool, isolated: Bool, unlit: Bool,
                            unpickable: Bool, projected: Bool) {
        self.init()
        self.autocommit = autocommit
        self.isolated = isolated
        self.unlit = unlit
        self.unpickable = unpickable
        self.projected = projected
        allocate(vertices: vertices, faces: faces)
    }

    public convenience init(merging pieces: [GameModel]) {
        self.init()
        merge(pieces)
    }

    public convenience init(merging pieces: [GameModel], autocommit: Bool, isolated: Bool, unlit: Bool, unpickable: Bool) {
        self.init()
        self.autocommit = autocommit
        self.isolated = isolated
        self.unlit = unlit
        self.unpickable = unpickable
        merge(pieces)
    }

    /// Parses a Jagex .ob3 model.
    public convenience init(ob3 data: [UInt8]) {
        self.init()
        var o = 0
        func u8() -> Int { defer { o += 1 }; return o < data.count ? Int(data[o]) : 0 }
        func u16() -> Int { u8() << 8 | u8() }
        func s16() -> Int16 { Int16(truncatingIfNeeded: u16()) }

        let vc = u16()
        let fc = u16()
        allocate(vertices: vc, faces: fc)
        guard vc > 0 else { return }
        for i in 0..<vc { vertexX[i] = s16() }
        for i in 0..<vc { vertexY[i] = s16() }
        for i in 0..<vc { vertexZ[i] = s16() }
        vertexCount = vc
        for i in 0..<fc { faceVertexCount[i] = UInt8(u8()) }
        for i in 0..<fc { faceFillFront[i] = s16() }
        for i in 0..<fc { faceFillBack[i] = s16() }
        for i in 0..<fc { faceIntensity[i] = u8() != 0 ? GameModel.useGouraud : 0 }
        for i in 0..<fc {
            var vs = [UInt16](repeating: 0, count: Int(faceVertexCount[i]))
            for j in 0..<vs.count { vs[j] = UInt16(truncatingIfNeeded: vc < 256 ? u8() : u16()) }
            faceVertices[i] = vs
        }
        faceCount = fc
    }

    public func reset() {
        baseX = 0; baseY = 0; baseZ = 0
        orientationYaw = 0; orientationPitch = 0; orientationRoll = 0
        transformType = 0
    }

    public func allocate(vertices vc: Int, faces fc: Int) {
        // Each terrain, wall and roof location gets a model, even if empty.
        if vc == 0 { return }
        vertexX = Buf(vc); vertexY = Buf(vc); vertexZ = Buf(vc)
        vertexIntensity = Buf(vc)
        vertexAmbience = Buf(vc)
        faceVertexCount = Buf(fc)
        faceVertices = Array(repeating: [], count: fc)
        faceFillFront = Buf(fc); faceFillBack = Buf(fc); faceIntensity = Buf(fc)
        normalScale = Buf(fc)
        normalMagnitude = Buf(fc)
        if !projected {
            projectVertexX = Buf(vc); projectVertexY = Buf(vc); projectVertexZ = Buf(vc)
            vertexViewX = Buf(vc); vertexViewY = Buf(vc)
        }
        if !unpickable {
            isLocalPlayer = Buf(fc)
            faceTag = Buf(fc)
        }
        if autocommit {
            vertexTransformedX = vertexX; vertexTransformedY = vertexY; vertexTransformedZ = vertexZ
        } else {
            vertexTransformedX = Buf(vc); vertexTransformedY = Buf(vc); vertexTransformedZ = Buf(vc)
        }
        if !unlit || !isolated {
            faceNormalX = Buf(fc); faceNormalY = Buf(fc); faceNormalZ = Buf(fc)
        }
        faceCount = 0
        vertexCount = 0
        maxVertices = vc
        maxFaces = fc
        reset()
    }

    public func projectionPrepare() {
        if vertexCount == 0 { return }
        projectVertexX = Buf(vertexCount); projectVertexY = Buf(vertexCount); projectVertexZ = Buf(vertexCount)
        vertexViewX = Buf(vertexCount); vertexViewY = Buf(vertexCount)
    }

    public func clear() {
        faceCount = 0
        vertexCount = 0
    }

    public func reduce(deltaFaces: Int, deltaVertices: Int) {
        var df = deltaFaces, dv = deltaVertices
        if faceCount - df < 0 { df = faceCount }
        if df > 0 { for i in 1...df { faceVertices[faceCount - i] = [] } }
        faceCount -= df
        if vertexCount - dv < 0 { dv = vertexCount }
        vertexCount -= dv
    }

    public func merge(_ pieces: [GameModel]) {
        let fc = pieces.reduce(0) { $0 + $1.faceCount }
        let vc = pieces.reduce(0) { $0 + $1.vertexCount }
        allocate(vertices: vc, faces: fc)
        for source in pieces {
            source.commit()
            lightAmbience = source.lightAmbience
            lightDiffuse = source.lightDiffuse
            lightDirectionX = source.lightDirectionX
            lightDirectionY = source.lightDirectionY
            lightDirectionZ = source.lightDirectionZ
            lightDirectionMagnitude = source.lightDirectionMagnitude
            for f in 0..<source.faceCount {
                let src = source.faceVertices[f]
                var dst = [UInt16](repeating: 0, count: Int(source.faceVertexCount[f]))
                for v in 0..<dst.count {
                    let s = Int(src[v])
                    dst[v] = UInt16(truncatingIfNeeded: vertexAt(x: Int(source.vertexX[s]), y: Int(source.vertexY[s]), z: Int(source.vertexZ[s])))
                }
                let d = createFace(dst, fillFront: Int(source.faceFillFront[f]), fillBack: Int(source.faceFillBack[f]))
                if d >= 0 {
                    faceIntensity[d] = source.faceIntensity[f]
                    normalScale[d] = source.normalScale[f]
                    normalMagnitude[d] = source.normalMagnitude[f]
                }
            }
        }
        transformState = GameModel.transformBegin
    }

    public func vertexAt(x: Int, y: Int, z: Int) -> Int {
        // Terrain assembly calls this ~10k times on an 18k-vertex model, so scan raw storage.
        if vertexCount > 0, let sx = Int16(exactly: x), let sy = Int16(exactly: y), let sz = Int16(exactly: z) {
            let px = vertexX.pointer, py = vertexY.pointer, pz = vertexZ.pointer
            var i = 0
            while i < vertexCount {
                if px[i] == sx && py[i] == sy && pz[i] == sz { return i }
                i += 1
            }
        }
        return createVertex(x: x, y: y, z: z)
    }

    @discardableResult
    public func createVertex(x: Int, y: Int, z: Int) -> Int {
        if vertexCount >= maxVertices { return -1 }
        vertexX[vertexCount] = Int16(truncatingIfNeeded: x)
        vertexY[vertexCount] = Int16(truncatingIfNeeded: y)
        vertexZ[vertexCount] = Int16(truncatingIfNeeded: z)
        vertexCount += 1
        return vertexCount - 1
    }

    @discardableResult
    public func createFace(_ vertices: [UInt16], fillFront: Int, fillBack: Int) -> Int {
        if faceCount >= maxFaces { return -1 }
        faceVertexCount[faceCount] = UInt8(truncatingIfNeeded: vertices.count)
        faceVertices[faceCount] = vertices
        faceFillFront[faceCount] = Int16(truncatingIfNeeded: fillFront)
        faceFillBack[faceCount] = Int16(truncatingIfNeeded: fillBack)
        transformState = GameModel.transformBegin
        faceCount += 1
        return faceCount - 1
    }

    /// Splits a large model (terrain) into `count` grid pieces.
    public func split(pieceDX: Int, pieceDZ: Int, rows: Int, count: Int, pieceMaxVertices: Int, pickable: Bool) -> [GameModel] {
        commit()
        var pieceVertexCount = [Int](repeating: 0, count: count)
        var pieceFaceCount = [Int](repeating: 0, count: count)

        func pieceIndex(_ f: Int) -> Int {
            var sumX = 0, sumZ = 0
            let n = Int(faceVertexCount[f])
            for j in 0..<n {
                sumX += Int(vertexX[Int(faceVertices[f][j])])
                sumZ += Int(vertexZ[Int(faceVertices[f][j])])
            }
            return sumX / (n * pieceDX) + (sumZ / (n * pieceDZ)) * rows
        }

        for f in 0..<faceCount {
            let p = pieceIndex(f)
            pieceVertexCount[p] += Int(faceVertexCount[f])
            pieceFaceCount[p] += 1
        }

        var pieces: [GameModel] = []
        for i in 0..<count {
            if pieceVertexCount[i] > pieceMaxVertices { pieceVertexCount[i] = pieceMaxVertices }
            let piece = GameModel(vertices: pieceVertexCount[i], faces: pieceFaceCount[i], autocommit: true,
                                  isolated: true, unlit: true, unpickable: pickable, projected: true)
            piece.lightDiffuse = lightDiffuse
            piece.lightAmbience = lightAmbience
            pieces.append(piece)
        }

        for f in 0..<faceCount {
            copyLighting(to: pieces[pieceIndex(f)], vertices: faceVertices[f], count: Int(faceVertexCount[f]), face: f)
        }
        for piece in pieces { piece.projectionPrepare() }
        return pieces
    }

    public func copyLighting(to model: GameModel, vertices src: [UInt16], count: Int, face: Int) {
        var dst = [UInt16](repeating: 0, count: count)
        for i in 0..<count {
            let s = Int(src[i])
            let v = model.vertexAt(x: Int(vertexX[s]), y: Int(vertexY[s]), z: Int(vertexZ[s]))
            dst[i] = UInt16(truncatingIfNeeded: v)
            model.vertexIntensity[v] = vertexIntensity[s]
            model.vertexAmbience[v] = vertexAmbience[s]
        }
        let out = model.createFace(dst, fillFront: Int(faceFillFront[face]), fillBack: Int(faceFillBack[face]))
        if !model.unpickable && !unpickable {
            model.faceTag![out] = faceTag![face]
        }
        model.faceIntensity[out] = faceIntensity[face]
        model.normalScale[out] = normalScale[face]
        model.normalMagnitude[out] = normalMagnitude[face]
    }

    // MARK: - Lighting

    public func setLightDirection(x: Int, y: Int, z: Int) {
        if unlit { return }
        lightDirectionX = x
        lightDirectionY = y
        lightDirectionZ = z
        lightDirectionMagnitude = Int(Double(Int32(truncatingIfNeeded: x * x + y * y + z * z)).squareRoot())
        light()
    }

    public func setLightIntensity(ambience: Int, diffuse: Int, x: Int, y: Int, z: Int) {
        lightAmbience = 256 - ambience * 4
        lightDiffuse = (64 - diffuse) * 16 + 128
        setLightDirection(x: x, y: y, z: z)
    }

    public func setLight(gouraud: Bool, ambience: Int, diffuse: Int, x: Int, y: Int, z: Int) {
        if unlit { return }
        for i in 0..<faceCount { faceIntensity[i] = gouraud ? GameModel.useGouraud : 0 }
        setLightIntensity(ambience: ambience, diffuse: diffuse, x: x, y: y, z: z)
    }

    public func setVertexAmbience(_ index: Int, _ ambience: Int) {
        vertexAmbience[index] = Int8(truncatingIfNeeded: ambience & 0xff)
    }

    func faceNormals(reset: Bool) {
        guard let nx = faceNormalX, let ny = faceNormalY, let nz = faceNormalZ else { return }
        guard let vx = vertexTransformedX, let vy = vertexTransformedY, let vz = vertexTransformedZ else { return }
        for i in 0..<faceCount {
            let fv = faceVertices[i]
            let ax = Int(vx[Int(fv[0])]), ay = Int(vy[Int(fv[0])]), az = Int(vz[Int(fv[0])])
            let bax = Int(vx[Int(fv[1])]) - ax, bay = Int(vy[Int(fv[1])]) - ay, baz = Int(vz[Int(fv[1])]) - az
            let cax = Int(vx[Int(fv[2])]) - ax, cay = Int(vy[Int(fv[2])]) - ay, caz = Int(vz[Int(fv[2])]) - az
            var x = Int(Int32(truncatingIfNeeded: bay * caz - cay * baz))
            var y = Int(Int32(truncatingIfNeeded: baz * cax - caz * bax))
            var z = Int(Int32(truncatingIfNeeded: bax * cay - cax * bay))
            while x > 8192 || y > 8192 || z > 8192 || x < -8192 || y < -8192 || z < -8192 {
                x /= 2
                y /= 2
                z /= 2
            }
            var magnitude = Int(256 * Double(Int32(truncatingIfNeeded: x * x + y * y + z * z)).squareRoot())
            if magnitude <= 0 { magnitude = 1 }
            nx[i] = Int16(truncatingIfNeeded: (x * 65536) / magnitude)
            ny[i] = Int16(truncatingIfNeeded: (y * 65536) / magnitude)
            nz[i] = Int16(truncatingIfNeeded: (z * 65535) / magnitude)
            if reset { normalScale[i] = -1 }
        }
    }

    public func light() {
        if unlit { return }
        let divisor = (lightDiffuse * lightDirectionMagnitude) >> 8
        guard let nx = faceNormalX, let ny = faceNormalY, let nz = faceNormalZ else { return } // only nil for empty models
        for i in 0..<faceCount where faceIntensity[i] != GameModel.useGouraud {
            faceIntensity[i] = Int16(truncatingIfNeeded:
                (Int(nx[i]) * lightDirectionX + Int(ny[i]) * lightDirectionY + Int(nz[i]) * lightDirectionZ) / divisor)
        }

        var normalX = [Int16](repeating: 0, count: vertexCount)
        var normalY = normalX, normalZ = normalX
        var magnitude = [Int32](repeating: 0, count: vertexCount)
        for i in 0..<faceCount where faceIntensity[i] == GameModel.useGouraud {
            for j in 0..<Int(faceVertexCount[i]) {
                let v = Int(faceVertices[i][j])
                normalX[v] = normalX[v] &+ nx[i]
                normalY[v] = normalY[v] &+ ny[i]
                normalZ[v] = normalZ[v] &+ nz[i]
                magnitude[v] += 1
            }
        }
        for i in 0..<vertexCount where magnitude[i] > 0 {
            vertexIntensity[i] = Int16(truncatingIfNeeded:
                (Int(normalX[i]) * lightDirectionX + Int(normalY[i]) * lightDirectionY + Int(normalZ[i]) * lightDirectionZ)
                    / (divisor * Int(magnitude[i])))
        }
    }

    public func relight() {
        if unlit && isolated { return }
        faceNormals(reset: true)
        light()
    }

    // MARK: - Transforms

    public func orient(yaw: Int, pitch: Int, roll: Int) {
        orientationYaw = yaw & 255
        orientationPitch = pitch & 255
        orientationRoll = roll & 255
        determineTransformType()
        transformState = GameModel.transformBegin
    }

    public func rotate(yaw: Int, pitch: Int, roll: Int) {
        orient(yaw: orientationYaw + yaw, pitch: orientationPitch + pitch, roll: orientationRoll + roll)
    }

    public func place(x: Int, y: Int, z: Int) {
        baseX = x; baseY = y; baseZ = z
        determineTransformType()
        transformState = GameModel.transformBegin
    }

    public func translate(x: Int, y: Int, z: Int) {
        place(x: baseX + x, y: baseY + y, z: baseZ + z)
    }

    func determineTransformType() {
        if orientationYaw != 0 || orientationPitch != 0 || orientationRoll != 0 {
            transformType = GameModel.transformRotate
        } else if baseX != 0 || baseY != 0 || baseZ != 0 {
            transformType = GameModel.transformTranslate
        } else {
            transformType = 0
        }
    }

    func applyTranslate(dx: Int, dy: Int, dz: Int) {
        guard let tx = vertexTransformedX, let ty = vertexTransformedY, let tz = vertexTransformedZ else { return }
        for i in 0..<vertexCount {
            tx[i] = Int16(truncatingIfNeeded: Int(tx[i]) + dx)
            ty[i] = Int16(truncatingIfNeeded: Int(ty[i]) + dy)
            tz[i] = Int16(truncatingIfNeeded: Int(tz[i]) + dz)
        }
    }

    /// Note the C argument order: (yaw, roll, pitch) though callers pass (yaw, pitch, roll).
    func applyRotation(yaw: Int, roll: Int, pitch: Int) {
        guard let tx = vertexTransformedX, let ty = vertexTransformedY, let tz = vertexTransformedZ else { return }
        let sc = Tables.sinCos512
        for i in 0..<vertexCount {
            if pitch != 0 {
                let s = sc[pitch], c = sc[pitch + 256]
                let x = (Int(ty[i]) * s + Int(tx[i]) * c) >> 15
                ty[i] = Int16(truncatingIfNeeded: (Int(ty[i]) * c - Int(tx[i]) * s) >> 15)
                tx[i] = Int16(truncatingIfNeeded: x)
            }
            if yaw != 0 {
                let s = sc[yaw], c = sc[yaw + 256]
                let y = (Int(ty[i]) * c - Int(tz[i]) * s) >> 15
                tz[i] = Int16(truncatingIfNeeded: (Int(ty[i]) * s + Int(tz[i]) * c) >> 15)
                ty[i] = Int16(truncatingIfNeeded: y)
            }
            if roll != 0 {
                let s = sc[roll], c = sc[roll + 256]
                let x = (Int(tz[i]) * s + Int(tx[i]) * c) >> 15
                tz[i] = Int16(truncatingIfNeeded: (Int(tz[i]) * c - Int(tx[i]) * s) >> 15)
                tx[i] = Int16(truncatingIfNeeded: x)
            }
        }
    }

    func computeBounds() {
        minX = 999_999; minY = 999_999; minZ = 999_999
        maxX = -999_999; maxY = -999_999; maxZ = -999_999
        guard let tx = vertexTransformedX, let ty = vertexTransformedY, let tz = vertexTransformedZ else { return }
        for i in 0..<faceCount {
            let fv = faceVertices[i]
            var v = Int(fv[0])
            var mnx = Int(tx[v]), mny = Int(ty[v]), mnz = Int(tz[v])
            var mxx = mnx, mxy = mny, mxz = mnz
            for j in 0..<Int(faceVertexCount[i]) {
                v = Int(fv[j])
                let x = Int(tx[v]), y = Int(ty[v]), z = Int(tz[v])
                if x < mnx { mnx = x } else if x > mxx { mxx = x }
                if y < mny { mny = y } else if y > mxy { mxy = y }
                if z < mnz { mnz = z } else if z > mxz { mxz = z }
            }
            if mnx < minX { minX = mnx }
            if mxx > maxX { maxX = mxx }
            if mny < minY { minY = mny }
            if mxy > maxY { maxY = mxy }
            if mnz < minZ { minZ = mnz }
            if mxz > maxZ { maxZ = mxz }
        }
    }

    func resetTransform() {
        transformState = 0
        if !autocommit && vertexCount > 0 {
            vertexTransformedX.copy(from: vertexX, count: vertexCount)
            vertexTransformedY.copy(from: vertexY, count: vertexCount)
            vertexTransformedZ.copy(from: vertexZ, count: vertexCount)
        }
    }

    public func apply() {
        if transformState == GameModel.transformReset {
            resetTransform()
            minX = -9_999_999; minY = -9_999_999; minZ = -9_999_999
            maxX = 9_999_999; maxY = 9_999_999; maxZ = 9_999_999
        } else if transformState == GameModel.transformBegin {
            resetTransform()
            if transformType >= GameModel.transformRotate {
                applyRotation(yaw: orientationYaw, roll: orientationPitch, pitch: orientationRoll)
            }
            if transformType >= GameModel.transformTranslate {
                applyTranslate(dx: baseX, dy: baseY, dz: baseZ)
            }
            computeBounds()
            relight()
        }
    }

    public func projectView(cameraX: Int, cameraY: Int, cameraZ: Int, pitch: Int, roll: Int, yaw: Int,
                            viewDistance: Int, clipNear: Int) {
        let sc = Tables.sinCos2048
        var yawSin = 0, yawCos = 0, pitchSin = 0, pitchCos = 0, rollSin = 0, rollCos = 0
        if yaw != 0 { yawSin = sc[yaw]; yawCos = sc[yaw + 1024] }
        if roll != 0 { rollSin = sc[roll]; rollCos = sc[roll + 1024] }
        if pitch != 0 { pitchSin = sc[pitch]; pitchCos = sc[pitch + 1024] }
        guard let tx = vertexTransformedX, let ty = vertexTransformedY, let tz = vertexTransformedZ else { return }
        guard let vvx = vertexViewX, let vvy = vertexViewY,
              let px = projectVertexX, let py = projectVertexY, let pz = projectVertexZ else { return }

        for i in 0..<vertexCount {
            var x = Int(tx[i]) - cameraX
            var y = Int(ty[i]) - cameraY
            var z = Int(tz[i]) - cameraZ
            if yaw != 0 {
                let nx = (y * yawSin + x * yawCos) >> 15
                y = (y * yawCos - x * yawSin) >> 15
                x = nx
            }
            if roll != 0 {
                let nx = (z * rollSin + x * rollCos) >> 15
                z = (z * rollCos - x * rollSin) >> 15
                x = nx
            }
            if pitch != 0 {
                let ny = (y * pitchCos - z * pitchSin) >> 15
                z = (y * pitchSin + z * pitchCos) >> 15
                y = ny
            }
            if z >= clipNear {
                vvx[i] = Int32(truncatingIfNeeded: (x * viewDistance) / z)
                vvy[i] = Int32(truncatingIfNeeded: (y * viewDistance) / z)
            } else {
                vvx[i] = Int32(truncatingIfNeeded: x * viewDistance)
                vvy[i] = Int32(truncatingIfNeeded: y * viewDistance)
            }
            px[i] = Int16(truncatingIfNeeded: x)
            py[i] = Int16(truncatingIfNeeded: y)
            pz[i] = Int16(truncatingIfNeeded: z)
        }
    }

    /// Applies transforms, culls against the scene frustum, then projects.
    public func project(cameraX: Int, cameraY: Int, cameraZ: Int, pitch: Int, roll: Int, yaw: Int,
                        viewDistance: Int, clipNear: Int, frustum: Frustum) {
        apply()
        if minZ > frustum.nearZ || maxZ < frustum.farZ || minX > frustum.minX || maxX < frustum.maxX ||
            minY > frustum.minY || maxY < frustum.maxY {
            visible = false
            return
        }
        visible = true
        projectView(cameraX: cameraX, cameraY: cameraY, cameraZ: cameraZ, pitch: pitch, roll: roll, yaw: yaw,
                    viewDistance: viewDistance, clipNear: clipNear)
    }

    public func commit() {
        apply()
        if !autocommit && vertexCount > 0 {
            vertexX.copy(from: vertexTransformedX, count: vertexCount)
            vertexY.copy(from: vertexTransformedY, count: vertexCount)
            vertexZ.copy(from: vertexTransformedZ, count: vertexCount)
        }
        reset()
    }

    public func copy() -> GameModel {
        let c = GameModel(merging: [self])
        c.depth = depth
        c.transparent = transparent
        return c
    }

    public func copy(autocommit: Bool, isolated: Bool, unlit: Bool, unpickable: Bool) -> GameModel {
        let c = GameModel(merging: [self], autocommit: autocommit, isolated: isolated, unlit: unlit, unpickable: unpickable)
        c.depth = depth
        return c
    }

    public func copyPosition(from source: GameModel) {
        orientationYaw = source.orientationYaw
        orientationPitch = source.orientationPitch
        orientationRoll = source.orientationRoll
        baseX = source.baseX; baseY = source.baseY; baseZ = source.baseZ
        determineTransformType()
        transformState = GameModel.transformBegin
    }

    /// Tints grey face colours (sprite-style masking on model faces).
    public static func maskFaces(_ fill: Buf<Int16>, count: Int, maskColour: Int) {
        for j in 0..<count {
            let fc = -1 - Int(fill[j])
            let r = ((fc >> 10) & 31) * 8, g = ((fc >> 5) & 31) * 8, b = (fc & 31) * 8
            if r == g && g == b {
                let mr = Float((maskColour >> 16) & 0xff) / 255, mg = Float((maskColour >> 8) & 0xff) / 255
                let mb = Float(maskColour & 0xff) / 255
                let nr = Int(Float(r) * mr) & 0xff, ng = Int(Float(g) * mg) & 0xff, nb = Int(Float(b) * mb) & 0xff
                fill[j] = Int16(truncatingIfNeeded: -(((nr / 8) << 10) | ((ng / 8) << 5) | (nb / 8)) - 1)
            }
        }
    }
}

/// The scene's view frustum bounds used for model culling (scene_frustum_* globals in C).
public struct Frustum {
    public var maxX = 0, minX = 0, maxY = 0, minY = 0, farZ = 0, nearZ = 0
    public init() {}
}
