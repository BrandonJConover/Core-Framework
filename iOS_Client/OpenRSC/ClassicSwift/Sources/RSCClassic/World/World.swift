// Port of rsc-c world.c: map section loading (.hei/.dat/.loc and .jm), terrain,
// wall and roof model assembly, the minimap raster, walk adjacency and routing.

public final class World {
    public static let regionWidth = 96
    public static let regionHeight = 96
    public static let tileSize = 128
    public static let planeCount = 4
    public static let terrainCount = 64
    public static let localCount = 18432
    public static let regionSize = 48
    public static let tileCount = regionSize * regionSize
    public static let planeHeight = 80000
    public static let terrainMaxFaces = 18688
    public static let terrainMaxVertices = 18688
    public static let roofSlope = 16
    public static let tileFaceTag = 200000
    public static let pathStepsMax = 8000

    static let floorTile = 2, liquidTile = 3, bridgeTile = 4, holeTile = 5
    static let bridgeTileDecoration = 12
    static let dirNorth = 0, dirWest = 2, dirSouth = 4, dirEast = 6

    public static let terrainColours: [Int16] = {
        var c = [Int16](repeating: 0, count: 256)
        for i in 0..<64 {
            c[i] = Scene.rgbToFill(255 - i * 4, 255 - Int(Double(i) * 1.75), 255 - i * 4)
            c[i + 64] = Scene.rgbToFill(i * 3, 144, 0)
            c[i + 128] = Scene.rgbToFill(192 - Int(Double(i) * 1.5), 144 - Int(Double(i) * 1.5), 0)
            c[i + 192] = Scene.rgbToFill(96 - Int(Double(i) * 1.5), 48 + Int(Double(i) * 1.5), 0)
        }
        return c
    }()

    public let scene: Scene
    public let surface: Surface
    public let gameData: GameData
    public var random = CRandom.shared
    public var playerAlive = false
    public var version: Int
    public var baseMediaSprite = 0
    public var landscapePack: JagArchive?
    public var mapPack: JagArchive?
    public var memberLandscapePack: JagArchive?
    public var memberMapPack: JagArchive?
    var parentModel: GameModel?
    public var objectAdjacency = [Int](repeating: 0, count: 96 * 96)
    public var routeVia = [Int](repeating: 0, count: 96 * 96)
    public var terrainHeightLocal = [Int](repeating: 0, count: 96 * 96)
    var wallsDiagonal = [UInt16](repeating: 0, count: 4 * 2304)
    public var terrainModels = [GameModel?](repeating: nil, count: 64)
    var terrainColour = [Int8](repeating: 0, count: 4 * 2304)
    var terrainHeight = [Int8](repeating: 0, count: 4 * 2304)
    var tileDecoration = [Int8](repeating: 0, count: 4 * 2304)
    var tileDirection = [Int8](repeating: 0, count: 4 * 2304)
    public var wallModels = [[GameModel?]](repeating: [GameModel?](repeating: nil, count: 64), count: 4)
    var wallsEastWest = [Int8](repeating: 0, count: 4 * 2304)
    var wallsNorthSouth = [Int8](repeating: 0, count: 4 * 2304)
    public var roofModels = [[GameModel?]](repeating: [GameModel?](repeating: nil, count: 64), count: 4)
    var wallsRoof = [Int8](repeating: 0, count: 4 * 2304)
    public var localX = [Int](repeating: 0, count: World.localCount)
    public var localY = [Int](repeating: 0, count: World.localCount)
    public var thickWalls = false

    public init(scene: Scene, surface: Surface, gameData: GameData, version: Int) {
        self.scene = scene
        self.surface = surface
        self.gameData = gameData
        self.version = version
    }

    @inline(__always) static func ai(_ x: Int, _ y: Int) -> Int { x * 96 + y }

    // MARK: - Plane-split arrays

    /// get_byte_plane_coord's index: the 96x96 local area is four 48x48 sections.
    @inline(__always) static func planeIndex(_ x0: Int, _ y0: Int) -> Int? {
        if x0 < 0 || x0 >= regionWidth || y0 < 0 || y0 >= regionHeight { return nil }
        var x = x0, y = y0, h = 0
        if x >= regionSize && y < regionSize {
            h = 1; x -= regionSize
        } else if x < regionSize && y >= regionSize {
            h = 2; y -= regionSize
        } else if x >= regionSize && y >= regionSize {
            h = 3; x -= regionSize; y -= regionSize
        }
        return h * tileCount + x * regionSize + y
    }

    @inline(__always) func byte(_ a: [Int8], _ x: Int, _ y: Int) -> Int {
        guard let i = World.planeIndex(x, y) else { return 0 }
        return Int(a[i]) & 0xff
    }

    func wallEastWest(_ x: Int, _ y: Int) -> Int { byte(wallsEastWest, x, y) }
    func wallNorthSouth(_ x: Int, _ y: Int) -> Int { byte(wallsNorthSouth, x, y) }
    public func wallRoof(_ x: Int, _ y: Int) -> Int { byte(wallsRoof, x, y) }
    public func tileDirection(_ x: Int, _ y: Int) -> Int { byte(tileDirection, x, y) }
    func tileDecoration(_ x: Int, _ y: Int) -> Int { byte(tileDecoration, x, y) }
    func terrainColourAt(_ x: Int, _ y: Int) -> Int { byte(terrainColour, x, y) }
    func terrainHeightAt(_ x: Int, _ y: Int) -> Int { byte(terrainHeight, x, y) * 3 }

    func wallDiagonal(_ x: Int, _ y: Int) -> Int {
        guard let i = World.planeIndex(x, y) else { return 0 }
        return Int(wallsDiagonal[i])
    }

    func setTileDecoration(_ x: Int, _ y: Int, _ d: Int) {
        guard let i = World.planeIndex(x, y) else { return }
        tileDecoration[i] = Int8(truncatingIfNeeded: d)
    }

    func objectAdjacencyAt(_ x: Int, _ y: Int) -> Int {
        if x < 0 || x >= World.regionWidth || y < 0 || y >= World.regionHeight { return 0 }
        return objectAdjacency[World.ai(x, y)]
    }

    func setBlocked(_ x: Int, _ y: Int, _ v: Int) { objectAdjacency[World.ai(x, y)] |= v }
    func setUnblocked(_ x: Int, _ y: Int, _ v: Int) { objectAdjacency[World.ai(x, y)] &= 0xffff - v }

    func hasRoof(_ x: Int, _ y: Int) -> Bool {
        wallRoof(x, y) > 0 && wallRoof(x - 1, y) > 0 && wallRoof(x - 1, y - 1) > 0 && wallRoof(x, y - 1) > 0
    }

    func hasNeighbouringRoof(_ x: Int, _ y: Int) -> Bool {
        wallRoof(x, y) > 0 || wallRoof(x - 1, y) > 0 || wallRoof(x - 1, y - 1) > 0 || wallRoof(x, y - 1) > 0
    }

    func decorationOrColour(_ x: Int, _ y: Int, _ colour: Int) -> Int {
        let d = tileDecoration(x, y)
        if d == 0 { return colour }
        return gameData.tiles[d - 1].decoration
    }

    func tileType(_ x: Int, _ y: Int) -> Int {
        let d = tileDecoration(x, y)
        if d == 0 { return -1 }
        return gameData.tiles[d - 1].type == 2 ? 1 : 0
    }

    // MARK: - Queries

    public func elevation(_ x: Int, _ y: Int) -> Int {
        let sx = x / World.tileSize, sy = y / World.tileSize
        var ax = x & (World.tileSize - 1), ay = y & (World.tileSize - 1)
        if sx < 0 || sy < 0 || sx >= 95 || sy >= 95 { return 0 }
        let h: Int, he: Int, hs: Int
        if ax <= World.tileSize - ay {
            h = terrainHeightAt(sx, sy)
            he = terrainHeightAt(sx + 1, sy) - h
            hs = terrainHeightAt(sx, sy + 1) - h
        } else {
            h = terrainHeightAt(sx + 1, sy + 1)
            he = terrainHeightAt(sx, sy + 1) - h
            hs = terrainHeightAt(sx + 1, sy) - h
            ax = World.tileSize - ax
            ay = World.tileSize - ay
        }
        return h + (he * ax) / World.tileSize + (hs * ay) / World.tileSize
    }

    public func isUnderRoof(_ x: Int, _ y: Int) -> Bool {
        objectAdjacency[World.ai(x / 128, y / 128)] & 128 != 0
    }

    // MARK: - Objects

    public func registerObject(x: Int, y: Int, id: Int) {
        if x < 0 || y < 0 || x >= 95 || y >= 95 { return }
        let obj = gameData.objects[id]
        guard obj.type == 1 || obj.type == 2 else { return }
        let dir = tileDirection(x, y)
        let w: Int, h: Int
        if dir == World.dirNorth || dir == World.dirSouth {
            w = obj.width; h = obj.height
        } else {
            h = obj.width; w = obj.height
        }
        for mx in x..<max(x, x + w) {
            for my in y..<max(y, y + h) {
                if obj.type == 1 {
                    objectAdjacency[World.ai(mx, my)] |= 0x40
                } else if dir == World.dirNorth {
                    objectAdjacency[World.ai(mx, my)] |= 2
                    if mx > 0 { setBlocked(mx - 1, my, 8) }
                } else if dir == World.dirWest {
                    objectAdjacency[World.ai(mx, my)] |= 4
                    if my < 95 { setBlocked(mx, my + 1, 1) }
                } else if dir == World.dirSouth {
                    objectAdjacency[World.ai(mx, my)] |= 8
                    if mx < 95 { setBlocked(mx + 1, my, 2) }
                } else if dir == World.dirEast {
                    objectAdjacency[World.ai(mx, my)] |= 1
                    if my > 0 { setBlocked(mx, my - 1, 4) }
                }
            }
        }
        updateShadowRect(x, y, w, h)
    }

    public func removeObject(x: Int, y: Int, id: Int) {
        if x < 0 || y < 0 || x >= World.regionWidth - 1 || y >= World.regionHeight - 1 { return }
        let obj = gameData.objects[id]
        guard obj.type == 1 || obj.type == 2 else { return }
        let dir = tileDirection(x, y)
        let w: Int, h: Int
        if dir == World.dirNorth || dir == World.dirSouth {
            w = obj.width; h = obj.height
        } else {
            h = obj.width; w = obj.height
        }
        for xx in x..<max(x, x + w) {
            for yy in y..<max(y, y + h) {
                if obj.type == 1 {
                    objectAdjacency[World.ai(xx, yy)] &= 0xffbf
                } else if dir == World.dirNorth {
                    objectAdjacency[World.ai(xx, yy)] &= 0xfffd
                    if xx > 0 { setUnblocked(xx - 1, yy, 8) }
                } else if dir == World.dirWest {
                    objectAdjacency[World.ai(xx, yy)] &= 0xfffb
                    if yy < World.regionHeight - 1 { setUnblocked(xx, yy + 1, 1) }
                } else if dir == World.dirSouth {
                    objectAdjacency[World.ai(xx, yy)] &= 0xfff7
                    if xx < World.regionWidth - 1 { setUnblocked(xx + 1, yy, 2) }
                } else if dir == World.dirEast {
                    objectAdjacency[World.ai(xx, yy)] &= 0xfffe
                    if yy > 0 { setUnblocked(xx, yy - 1, 4) }
                }
            }
        }
        updateShadowRect(x, y, w, h)
    }

    public func registerWallObject(x: Int, y: Int, dir: Int, id: Int) {
        if x < 0 || y < 0 || x >= 95 || y >= 95 { return }
        guard gameData.walls[id].blocking == 1 else { return }
        if dir == 0 {
            objectAdjacency[World.ai(x, y)] |= 1
            if y > 0 { setBlocked(x, y - 1, 4) }
        } else if dir == 1 {
            objectAdjacency[World.ai(x, y)] |= 2
            if x > 0 { setBlocked(x - 1, y, 8) }
        } else if dir == 2 {
            objectAdjacency[World.ai(x, y)] |= 0x10
        } else if dir == 3 {
            objectAdjacency[World.ai(x, y)] |= 0x20
        }
        updateShadowRect(x, y, 1, 1)
    }

    public func removeWallObject(x: Int, y: Int, dir k: Int, id: Int) {
        if x < 0 || y < 0 || x >= 95 || y >= 95 { return }
        guard gameData.walls[id].blocking == 1 else { return }
        if k == 0 {
            objectAdjacency[World.ai(x, y)] &= 0xfffe
            if y > 0 { setUnblocked(x, y - 1, 4) }
        } else if k == 1 {
            objectAdjacency[World.ai(x, y)] &= 0xfffd
            if x > 0 { setUnblocked(x - 1, y, 8) }
        } else if k == 2 {
            objectAdjacency[World.ai(x, y)] &= 0xffef
        } else if k == 3 {
            objectAdjacency[World.ai(x, y)] &= 0xffdf
        }
        updateShadowRect(x, y, 1, 1)
    }

    // MARK: - Shadows

    func setTerrainAmbience(_ tx: Int, _ ty: Int, _ vx: Int, _ vy: Int, _ ambience: Int) {
        let index = tx + ty * 8
        guard index >= 0 && index < terrainModels.count, let m = terrainModels[index], m.vertexCount > 0 else { return }
        let px = m.vertexX.pointer, pz = m.vertexZ.pointer
        let wx = vx * World.tileSize, wz = vy * World.tileSize
        for i in 0..<m.vertexCount where Int(px[i]) == wx && Int(pz[i]) == wz {
            m.setVertexAmbience(i, ambience)
            break
        }
    }

    func vertexShadow(_ vx: Int, _ vz: Int, _ ambience: Int) {
        let tx = vx / 12, ty = vz / 12
        let x2 = (vx - 1) / 12, y2 = (vz - 1) / 12
        setTerrainAmbience(tx, ty, vx, vz, ambience)
        if tx != x2 { setTerrainAmbience(x2, ty, vx, vz, ambience) }
        if ty != y2 { setTerrainAmbience(tx, y2, vx, vz, ambience) }
        if tx != x2 && ty != y2 { setTerrainAmbience(x2, y2, vx, vz, ambience) }
    }

    func updateShadowRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        if x < 1 || y < 1 || x + w >= World.regionWidth || y + h >= World.regionHeight { return }
        for xx in x...(x + w) {
            for yy in y...(y + h) {
                if objectAdjacencyAt(xx, yy) & 0x63 != 0 || objectAdjacencyAt(xx - 1, yy) & 0x59 != 0 ||
                    objectAdjacencyAt(xx, yy - 1) & 0x56 != 0 || objectAdjacencyAt(xx - 1, yy - 1) & 0x6c != 0 {
                    vertexShadow(xx, yy, 35)
                } else {
                    vertexShadow(xx, yy, 0)
                }
            }
        }
    }

    // MARK: - Minimap

    func drawMapTile(_ x: Int, _ y: Int, _ direction: Int, _ fill1: Int, _ fill2: Int) {
        let lx = x * 3, ly = y * 3
        let c1 = Int32(truncatingIfNeeded: (scene.fillColour(fill1) >> 1) & 0x7f7f7f)
        let c2 = Int32(truncatingIfNeeded: (scene.fillColour(fill2) >> 1) & 0x7f7f7f)
        if direction == 0 {
            surface.drawLineHorizontal(x: lx, y: ly, width: 3, colour: c1)
            surface.drawLineHorizontal(x: lx, y: ly + 1, width: 2, colour: c1)
            surface.drawLineHorizontal(x: lx, y: ly + 2, width: 1, colour: c1)
            surface.drawLineHorizontal(x: lx + 2, y: ly + 1, width: 1, colour: c2)
            surface.drawLineHorizontal(x: lx + 1, y: ly + 2, width: 2, colour: c2)
        } else if direction == 1 {
            surface.drawLineHorizontal(x: lx, y: ly, width: 3, colour: c2)
            surface.drawLineHorizontal(x: lx + 1, y: ly + 1, width: 2, colour: c2)
            surface.drawLineHorizontal(x: lx + 2, y: ly + 2, width: 1, colour: c2)
            surface.drawLineHorizontal(x: lx, y: ly + 1, width: 1, colour: c1)
            surface.drawLineHorizontal(x: lx, y: ly + 2, width: 2, colour: c1)
        }
    }

    // MARK: - Reset

    public func reset(dispose: Bool) {
        for i in 0..<World.terrainCount {
            if let m = terrainModels[i] { scene.nullModel(m) }
            terrainModels[i] = nil
            for j in 0..<World.planeCount {
                if let m = wallModels[j][i] { scene.nullModel(m) }
                wallModels[j][i] = nil
            }
            for j in 0..<World.planeCount {
                if let m = roofModels[j][i] { scene.nullModel(m) }
                roofModels[j][i] = nil
            }
        }
        if dispose { scene.dispose() }
    }

    func fillEdges() {
        for x in 0..<World.regionWidth {
            for y in 0..<World.regionHeight {
                if tileDecoration(x, y) != 250 { continue }
                if x == World.regionSize - 1 && tileDecoration(x + 1, y) != 250 && tileDecoration(x + 1, y) != 2 {
                    setTileDecoration(x, y, 9)
                } else if y == World.regionSize - 1 && tileDecoration(x, y + 1) != 250 && tileDecoration(x, y + 1) != 2 {
                    setTileDecoration(x, y, 9)
                } else {
                    setTileDecoration(x, y, 2)
                }
            }
        }
    }

    // MARK: - Login screen scenery

    /// world_add_models: places the scenery stored in .loc data (login screen backgrounds).
    public func addModels(_ models: [GameModel]) {
        for x in 0..<94 {
            for y in 0..<94 {
                let diagonal = wallDiagonal(x, y)
                guard diagonal > 48000 && diagonal < 60000 else { continue }
                let objectId = diagonal - 48001
                let dir = tileDirection(x, y)
                let obj = gameData.objects[objectId]
                let w: Int, h: Int
                if dir == World.dirNorth || dir == World.dirSouth {
                    w = obj.width; h = obj.height
                } else {
                    h = obj.width; w = obj.height
                }
                registerObject(x: x, y: y, id: objectId)
                let m = models[obj.modelIndex].copy(autocommit: false, isolated: true, unlit: false, unpickable: false)
                let tx = ((x + x + w) * World.tileSize) / 2
                let ty = ((y + y + h) * World.tileSize) / 2
                m.translate(x: tx, y: -elevation(tx, ty), z: ty)
                m.orient(yaw: 0, pitch: tileDirection(x, y) * 32, roll: 0)
                scene.addModel(m)
                m.setLightIntensity(ambience: 48, diffuse: 48, x: -50, y: -10, z: -50)
                if w > 1 || h > 1 {
                    for xx in x..<(x + w) {
                        for yy in y..<(y + h) where (xx > x || yy > y) && wallDiagonal(xx, yy) - 48001 == objectId {
                            if let i = World.planeIndex(xx, yy) { wallsDiagonal[i] = 0 }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Routing

    /// world_route: breadth-first search over the adjacency flags. Returns the number of waypoints written
    /// to routeX/routeY (destination first), or -1.
    public func route(startX: Int, startY: Int, endX1: Int, endY1: Int, endX2: Int, endY2: Int,
                      routeX: inout [Int], routeY: inout [Int], objects: Bool) -> Int {
        for i in 0..<routeVia.count { routeVia[i] = 0 }
        var writePtr = 0, readPtr = 0
        var x = startX, y = startY
        routeVia[World.ai(startX, startY)] = 99
        routeX[writePtr] = startX
        routeY[writePtr] = startY
        writePtr += 1
        var reached = false
        let adj = objectAdjacency
        let maxXY = World.regionWidth - 1
        func a(_ x: Int, _ y: Int) -> Int { adj[World.ai(x, y)] }
        func via(_ x: Int, _ y: Int) -> Int { routeVia[World.ai(x, y)] }
        func push(_ nx: Int, _ ny: Int, _ v: Int) {
            routeX[writePtr] = nx
            routeY[writePtr] = ny
            writePtr = (writePtr + 1) % World.pathStepsMax
            routeVia[World.ai(nx, ny)] = v
        }

        while readPtr != writePtr {
            x = routeX[readPtr]
            y = routeY[readPtr]
            readPtr = (readPtr + 1) % World.pathStepsMax
            if x >= endX1 && x <= endX2 && y >= endY1 && y <= endY2 {
                reached = true
                break
            }
            if objects {
                if x > 0 && x - 1 >= endX1 && x - 1 <= endX2 && y >= endY1 && y <= endY2 && a(x - 1, y) & 8 == 0 {
                    reached = true; break
                }
                if x < maxXY && x + 1 >= endX1 && x + 1 <= endX2 && y >= endY1 && y <= endY2 && a(x + 1, y) & 2 == 0 {
                    reached = true; break
                }
                if y > 0 && x >= endX1 && x <= endX2 && y - 1 >= endY1 && y - 1 <= endY2 && a(x, y - 1) & 4 == 0 {
                    reached = true; break
                }
                if y < maxXY && x >= endX1 && x <= endX2 && y + 1 >= endY1 && y + 1 <= endY2 && a(x, y + 1) & 1 == 0 {
                    reached = true; break
                }
            }
            if x > 0 && via(x - 1, y) == 0 && a(x - 1, y) & 0x78 == 0 { push(x - 1, y, 2) }
            if x < maxXY && via(x + 1, y) == 0 && a(x + 1, y) & 0x72 == 0 { push(x + 1, y, 8) }
            if y > 0 && via(x, y - 1) == 0 && a(x, y - 1) & 0x74 == 0 { push(x, y - 1, 1) }
            if y < maxXY && via(x, y + 1) == 0 && a(x, y + 1) & 0x71 == 0 { push(x, y + 1, 4) }
            if x > 0 && y > 0 && a(x, y - 1) & 0x74 == 0 && a(x - 1, y) & 0x78 == 0 &&
                a(x - 1, y - 1) & 0x7c == 0 && via(x - 1, y - 1) == 0 { push(x - 1, y - 1, 3) }
            if x < maxXY && y > 0 && a(x, y - 1) & 0x74 == 0 && a(x + 1, y) & 0x72 == 0 &&
                a(x + 1, y - 1) & 0x76 == 0 && via(x + 1, y - 1) == 0 { push(x + 1, y - 1, 9) }
            if x > 0 && y < maxXY && a(x, y + 1) & 0x71 == 0 && a(x - 1, y) & 0x78 == 0 &&
                a(x - 1, y + 1) & 0x79 == 0 && via(x - 1, y + 1) == 0 { push(x - 1, y + 1, 6) }
            if x < maxXY && y < maxXY && a(x, y + 1) & 0x71 == 0 && a(x + 1, y) & 0x72 == 0 &&
                a(x + 1, y + 1) & 0x73 == 0 && via(x + 1, y + 1) == 0 { push(x + 1, y + 1, 12) }
        }
        if !reached { return -1 }

        readPtr = 0
        routeX[readPtr] = x
        routeY[readPtr] = y
        readPtr += 1
        var stride = via(x, y)
        var step = stride
        while x != startX || y != startY {
            if step != stride {
                stride = step
                routeX[readPtr] = x
                routeY[readPtr] = y
                readPtr += 1
            }
            if step & 2 != 0 { x += 1 } else if step & 8 != 0 { x -= 1 }
            if step & 1 != 0 { y += 1 } else if step & 4 != 0 { y -= 1 }
            step = via(x, y)
        }
        return readPtr
    }
}
