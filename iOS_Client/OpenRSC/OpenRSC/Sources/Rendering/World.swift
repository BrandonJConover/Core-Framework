import Foundation

// MARK: - CollisionFlag

/// Collision flag constants ported from Java CollisionFlag.java.
struct CollisionFlag {
    static let WALL_NORTH         = 1
    static let WALL_EAST          = 2
    static let WALL_SOUTH         = 4
    static let WALL_WEST          = 8

    private static let WALL_NORTH_EAST = WALL_NORTH | WALL_EAST
    private static let WALL_NORTH_WEST = WALL_NORTH | WALL_WEST
    private static let WALL_SOUTH_EAST = WALL_SOUTH | WALL_EAST
    private static let WALL_SOUTH_WEST = WALL_SOUTH | WALL_WEST

    static let FULL_BLOCK_A       = 16
    static let FULL_BLOCK_B       = 32
    static let FULL_BLOCK_C       = 64
    private static let FULL_BLOCK = FULL_BLOCK_A | FULL_BLOCK_B | FULL_BLOCK_C

    static let OBJECT             = 128

    static let WEST_BLOCKED       = FULL_BLOCK | WALL_WEST
    static let SOUTH_BLOCKED      = FULL_BLOCK | WALL_SOUTH
    static let NORTH_BLOCKED      = FULL_BLOCK | WALL_NORTH
    static let EAST_BLOCKED       = FULL_BLOCK | WALL_EAST

    static let SOUTH_EAST_BLOCKED = FULL_BLOCK | WALL_SOUTH_EAST
    static let SOUTH_WEST_BLOCKED = FULL_BLOCK | WALL_SOUTH_WEST
    static let NORTH_EAST_BLOCKED = FULL_BLOCK | WALL_NORTH_EAST
    static let NORTH_WEST_BLOCKED = FULL_BLOCK | WALL_NORTH_WEST

    static let SOURCE_EAST        = 8
    static let SOURCE_NORTH       = 4
    static let SOURCE_SOUTH       = 1
    static let SOURCE_WEST        = 2

    static let SOURCE_NORTH_EAST  = SOURCE_NORTH | SOURCE_EAST
    static let SOURCE_NORTH_WEST  = SOURCE_NORTH | SOURCE_WEST
    static let SOURCE_SOUTH_EAST  = SOURCE_SOUTH | SOURCE_EAST
    static let SOURCE_SOUTH_WEST  = SOURCE_SOUTH | SOURCE_WEST
}

// MARK: - World

/// Port of orsc.graphics.three.World from the Java desktop client.
/// Converts flat tile data into 3D RSModel geometry for the scene.
final class World {

    // MARK: - Constants / Properties

    private var colorToResource = [Int](repeating: 0, count: 256)
    private var tileElevationCache: [[Int]] = Array(repeating: Array(repeating: 0, count: 96), count: 96)
    private var pathFindSource: [[Int]] = Array(repeating: Array(repeating: 0, count: 96), count: 96)
    private var tileDirection: [[Int]] = Array(repeating: Array(repeating: 0, count: 96), count: 96)
    private let showInvisibleWalls = false

    var baseMediaSprite = 750
    var collisionFlags: [[Int]] = Array(repeating: Array(repeating: 0, count: 96), count: 96)
    var faceTileX = [Int](repeating: 0, count: 18432)
    var faceTileZ = [Int](repeating: 0, count: 18432)
    var playerAlive = false

    var modelWallGrid: [[RSModel?]] = Array(repeating: Array(repeating: nil, count: 64), count: 4)
    var modelRoofGrid: [[RSModel?]] = Array(repeating: Array(repeating: nil, count: 64), count: 4)

    private var minimapGraphics: GraphicsController
    private var scene: RSScene
    private var modelAccumulate: RSModel?
    private var modelLandscapeGrid: [RSModel?] = Array(repeating: nil, count: 64)
    private var sectors: [LandscapeSectorData?] = Array(repeating: nil, count: 4)

    // MARK: - Init

    /// Corresponds to Java World(Scene var1, GraphicsController var2).
    init(scene: RSScene, graphics: GraphicsController) {
        self.scene = scene
        self.minimapGraphics = graphics

        // Band 0: green-white gradient (grass)
        for i in 0..<64 {
            colorToResource[i] = World.colorToResourceValue(
                r: 255 - i * 4,
                g: 255 - Int(Double(i) * 1.75),
                b: 255 - i * 4
            )
        }
        // Band 1: dark green
        for i in 0..<64 {
            colorToResource[64 + i] = World.colorToResourceValue(r: i * 3, g: 144, b: 0)
        }
        // Band 2: brown
        for i in 0..<64 {
            colorToResource[128 + i] = World.colorToResourceValue(
                r: 192 - Int(Double(i) * 1.5),
                g: 144 - Int(Double(i) * 1.5),
                b: 0
            )
        }
        // Band 3: dark-to-green
        for i in 0..<64 {
            colorToResource[192 + i] = World.colorToResourceValue(
                r: 96 - Int(Double(i) * 1.5),
                g: Int(Double(i) * 1.5) + 48,
                b: 0
            )
        }

        for i in 0..<4 {
            sectors[i] = nil
        }
    }

    /// Corresponds to Java GenUtil.colorToResource(r, g, b).
    private static func colorToResourceValue(r: Int, g: Int, b: Int) -> Int {
        let bShift = b >> 3
        let rShift = r >> 3
        let gShift = g >> 3
        return -(gShift << 5) - 1 - (rShift << 10) - bShift
    }

    // MARK: - Sector Data Wrapper

    /// Wraps the LandscapeArchive tile access for a loaded sector, providing the same
    /// interface as the Java Sector class.
    private struct LandscapeSectorData {
        let plane: Int
        let sectionX: Int
        let sectionY: Int

        func getTile(_ x: Int, _ y: Int) -> LandscapeTile {
            if let tile = LandscapeArchive.shared.tile(
                atWorldX: sectionX * 48 + x,
                worldY: sectionY * 48 + y,
                plane: plane,
                centeredAt: sectionX * 48 + 24,
                centerY: sectionY * 48 + 24
            ) {
                return tile
            }
            // Default tile
            let defaultOverlay = (plane == 0 || plane == 3) ? 250 : 8
            return LandscapeTile(
                groundElevation: 0, groundTexture: 0, groundOverlay: defaultOverlay,
                roofTexture: 0, horizontalWall: 0, verticalWall: 0, diagonalWalls: 0
            )
        }
    }

    // MARK: - Section Loading

    private func loadSection(_ sector: Int, _ height: Int, _ sectionX: Int, _ sectionY: Int) {
        sectors[sector] = LandscapeSectorData(plane: height, sectionX: sectionX, sectionY: sectionY)
    }

    // MARK: - Tile Accessors (per-chunk routing, mirrors Java)

    private func resolveChunk(_ tileX: Int, _ tileZ: Int) -> (chunk: Int, x: Int, z: Int)? {
        guard tileX >= 0 && tileX < 96 && tileZ >= 0 && tileZ < 96 else { return nil }
        var x = tileX, z = tileZ, chunk = 0
        if x >= 48 && z < 48  { x -= 48; chunk = 1 }
        else if x < 48 && z >= 48 { z -= 48; chunk = 2 }
        else if x >= 48 && z >= 48 { x -= 48; z -= 48; chunk = 3 }
        return (chunk, x, z)
    }

    private func getTerrainColour(_ tileX: Int, _ tileZ: Int) -> Int {
        guard let (chunk, x, z) = resolveChunk(tileX, tileZ),
              let sec = sectors[chunk] else { return 0 }
        return sec.getTile(x, z).groundTexture & 0xFF
    }

    private func getTileDecorationID(_ xTile: Int, _ zTile: Int, _ plane: Int) -> Int {
        guard let (chunk, x, z) = resolveChunk(xTile, zTile),
              let sec = sectors[chunk] else { return 0 }
        return sec.getTile(x, z).groundOverlay & 0xFF
    }

    func getTileDirection(_ xTile: Int, _ zTile: Int) -> Int {
        guard xTile >= 0 && xTile < 96 && zTile >= 0 && zTile < 96 else { return 0 }
        return tileDirection[xTile][zTile]
    }

    private func getTileElevation(_ xTile: Int, _ zTile: Int) -> Int {
        guard let (chunk, x, z) = resolveChunk(xTile, zTile),
              let sec = sectors[chunk] else { return 0 }
        return (sec.getTile(x, z).groundElevation & 0xFF) * 3
    }

    private func getWallDiagonal(_ tileX: Int, _ tileZ: Int) -> Int {
        guard let (chunk, x, z) = resolveChunk(tileX, tileZ),
              let sec = sectors[chunk] else { return 0 }
        return sec.getTile(x, z).diagonalWalls
    }

    private func getVerticalWall(_ tileX: Int, _ tileZ: Int) -> Int {
        guard let (chunk, x, z) = resolveChunk(tileX, tileZ),
              let sec = sectors[chunk] else { return 0 }
        return sec.getTile(x, z).verticalWall & 0xFF
    }

    private func getHorizontalWall(_ xTile: Int, _ zTile: Int) -> Int {
        guard let (chunk, x, z) = resolveChunk(xTile, zTile),
              let sec = sectors[chunk] else { return 0 }
        return sec.getTile(x, z).horizontalWall & 0xFF
    }

    private func getWallRoof(_ tileX: Int, _ tileZ: Int) -> Int {
        guard let (chunk, x, z) = resolveChunk(tileX, tileZ),
              let sec = sectors[chunk] else { return 0 }
        return sec.getTile(x, z).roofTexture
    }

    private func setTileDecoration(_ xTile: Int, _ zTile: Int, _ val: Int) {
        // NOTE: In the Java client, this mutates the sector tile data in place.
        // The iOS LandscapeArchive uses immutable tile structs, so this is a
        // no-op for now. Tile decoration overrides (bridge logic) are handled
        // by the bridge overlay detection in generateLandscapeModel.
    }

    // MARK: - Tile Decoration Helpers

    private func getTileDecorationCacheVal(_ xTile: Int, _ zTile: Int, _ plane: Int, _ defaultVal: Int) -> Int {
        let id = getTileDecorationID(xTile, zTile, plane)
        if id == 0 { return defaultVal }
        guard let tileDef = EntityHandler.shared.getTileDef(id - 1) else { return defaultVal }
        return Int(tileDef.colour)
    }

    private func isTileType2(_ xTile: Int, _ zTile: Int, _ plane: Int) -> Int {
        let id = getTileDecorationID(xTile, zTile, plane)
        if id == 0 { return -1 }
        guard let tileDef = EntityHandler.shared.getTileDef(id - 1) else { return 0 }
        return tileDef.tileValue != 2 ? 0 : 1
    }

    // MARK: - Roof Helpers

    private func hasRoofStrut(_ tileX: Int, _ tileZ: Int) -> Bool {
        return getWallRoof(tileX, tileZ) <= 0
            && getWallRoof(tileX - 1, tileZ) <= 0
            && getWallRoof(tileX - 1, tileZ - 1) <= 0
            && getWallRoof(tileX, tileZ - 1) <= 0
    }

    private func hasRoofTile(_ tileX: Int, _ tileZ: Int) -> Bool {
        return getWallRoof(tileX, tileZ) > 0
            && getWallRoof(tileX - 1, tileZ) > 0
            && getWallRoof(tileX - 1, tileZ - 1) > 0
            && getWallRoof(tileX, tileZ - 1) > 0
    }

    // MARK: - Bridge Overlay

    private func setTileDecorationOnBridge() {
        for x in 0..<96 {
            for z in 0..<96 {
                if getTileDecorationID(x, z, 0) == 250 {
                    if x == 47 && getTileDecorationID(x + 1, z, 0) != 250
                        && getTileDecorationID(x + 1, z, 0) != 2 {
                        setTileDecoration(x, z, 9)
                    } else if z == 47 && getTileDecorationID(x, z + 1, 0) != 250
                        && getTileDecorationID(x, z + 1, 0) != 2 {
                        setTileDecoration(x, z, 9)
                    } else {
                        setTileDecoration(x, z, 2)
                    }
                }
            }
        }
    }

    // MARK: - Elevation

    /// Bilinear interpolation of ground elevation for entity Y positioning.
    /// Corresponds to Java getElevation(int x, int z).
    func getElevation(x: Int, z: Int) -> Int {
        let xTile = x >> 7
        let zTile = z >> 7
        var xLerp = x & 127
        var zLerp = z & 127

        guard xTile >= 0 && zTile >= 0 && xTile < 95 && zTile < 95 else { return 0 }

        let tileCorner: Int
        let dEX: Int
        let dEZ: Int

        if xLerp <= 128 - zLerp {
            tileCorner = getTileElevation(xTile, zTile)
            dEX = getTileElevation(xTile + 1, zTile) - tileCorner
            dEZ = getTileElevation(xTile, zTile + 1) - tileCorner
        } else {
            let corner = getTileElevation(xTile + 1, zTile + 1)
            dEX = getTileElevation(xTile, zTile + 1) - corner
            dEZ = getTileElevation(xTile + 1, zTile) - corner
            xLerp = 128 - xLerp
            zLerp = 128 - zLerp
            return corner + dEX * xLerp / 128 + dEZ * zLerp / 128
        }

        return tileCorner + dEX * xLerp / 128 + dEZ * zLerp / 128
    }

    // MARK: - Collision Helpers

    private func collisionFlagBitwiseOr(_ x: Int, _ z: Int, _ val: Int) {
        collisionFlags[x][z] |= val
    }

    private func collisionFlagModify(_ x: Int, _ z: Int, _ andMask: Int, _ orVal: Int) {
        collisionFlags[x][z] &= (andMask - orVal)
    }

    private func collisionFlagSafe(_ x: Int, _ z: Int) -> Int {
        guard x >= 0 && z >= 0 && x < 96 && z < 96 else { return 0 }
        return collisionFlags[x][z]
    }

    // MARK: - Vertex Light

    private func setVertexLightArea(_ tileX: Int, _ tileZ: Int, _ width: Int, _ height: Int) {
        guard tileX >= 1 && tileZ >= 1 && width + tileX < 96 && height + tileZ < 96 else { return }

        let flag00 = CollisionFlag.FULL_BLOCK_C | CollisionFlag.FULL_BLOCK_B
            | CollisionFlag.WALL_NORTH | CollisionFlag.WALL_EAST
        let flag10 = CollisionFlag.FULL_BLOCK_C | CollisionFlag.FULL_BLOCK_A
            | CollisionFlag.WALL_WEST | CollisionFlag.WALL_NORTH
        let flag01 = CollisionFlag.FULL_BLOCK_C | CollisionFlag.FULL_BLOCK_A
            | CollisionFlag.WALL_SOUTH | CollisionFlag.WALL_EAST
        let flag11 = CollisionFlag.FULL_BLOCK_C | CollisionFlag.FULL_BLOCK_B
            | CollisionFlag.WALL_WEST | CollisionFlag.WALL_SOUTH

        for x in tileX...(width + tileX) {
            for z in tileZ...(tileZ + height) {
                if (collisionFlagSafe(x, z) & flag00) == 0
                    && (collisionFlagSafe(x - 1, z) & flag10) == 0
                    && (collisionFlagSafe(x, z - 1) & flag01) == 0
                    && (collisionFlagSafe(x - 1, z - 1) & flag11) == 0 {
                    setVertexLightOther(x, z, 0)
                } else {
                    setVertexLightOther(x, z, 35)
                }
            }
        }
    }

    private func setVertexLightOther(_ x: Int, _ z: Int, _ light: Int) {
        let chunkX = x / 12
        let chunkZ = z / 12
        let chunkXM1 = (x - 1) / 12
        let chunkZM1 = (z - 1) / 12

        setVertexLightOtherInChunk(chunkX, chunkZ, x, z, light)
        if chunkX != chunkXM1 {
            setVertexLightOtherInChunk(chunkXM1, chunkZ, x, z, light)
        }
        if chunkZM1 != chunkZ {
            setVertexLightOtherInChunk(chunkX, chunkZM1, x, z, light)
        }
        if chunkXM1 != chunkX && chunkZ != chunkZM1 {
            setVertexLightOtherInChunk(chunkXM1, chunkZM1, x, z, light)
        }
    }

    private func setVertexLightOtherInChunk(_ chunkX: Int, _ chunkZ: Int, _ tileX: Int, _ tileZ: Int, _ light: Int) {
        guard let m = modelLandscapeGrid[chunkX + chunkZ * 8] else { return }
        for id in 0..<m.vertHead {
            if m.vertX[id] == tileX * 128 && m.vertZ[id] == tileZ * 128 {
                m.setVertexLightOther(id: id, val: light)
                return
            }
        }
    }

    // MARK: - Minimap Drawing

    private func drawMinimapTile(_ tileX: Int, _ tileZ: Int, _ bridge00_11: Int, _ res01: Int, _ res10: Int) {
        let mx = tileX * 3
        let my = tileZ * 3
        var a = scene.resourceToColor(res10)
        a = (a >> 1) & 0x7F7F7F
        var b = scene.resourceToColor(res01)
        b = (b & 0xFEFEFF) >> 1

        let aColor = UInt32(truncatingIfNeeded: a)
        let bColor = UInt32(truncatingIfNeeded: b)

        if bridge00_11 == 0 {
            minimapGraphics.drawLineHoriz(x: mx, y: my, width: 3, color: aColor)
            minimapGraphics.drawLineHoriz(x: mx, y: 1 + my, width: 2, color: aColor)
            minimapGraphics.drawLineHoriz(x: mx, y: my + 2, width: 1, color: aColor)
            minimapGraphics.drawLineHoriz(x: 2 + mx, y: my + 1, width: 1, color: bColor)
            minimapGraphics.drawLineHoriz(x: mx + 1, y: my + 2, width: 2, color: bColor)
        } else if bridge00_11 == 1 {
            minimapGraphics.drawLineHoriz(x: mx, y: my, width: 3, color: bColor)
            minimapGraphics.drawLineHoriz(x: 1 + mx, y: 1 + my, width: 2, color: bColor)
            minimapGraphics.drawLineHoriz(x: mx + 2, y: my + 2, width: 1, color: bColor)
            minimapGraphics.drawLineHoriz(x: mx, y: my + 1, width: 1, color: aColor)
            minimapGraphics.drawLineHoriz(x: mx, y: 2 + my, width: 2, color: aColor)
        }
    }

    // MARK: - Wall Insertion

    private func insertWallIntoModel(_ wallID: Int, _ model: RSModel, _ t2X: Int, _ t1Z: Int, _ t1X: Int, _ t2Z: Int) {
        setVertexLightOther(t1X, t1Z, 40)
        setVertexLightOther(t2X, t2Z, 40)

        guard let doorDef = EntityHandler.shared.getDoorDef(wallID) else { return }
        let height = doorDef.wallObjectHeight
        let frontTex = doorDef.modelVar2
        let backTex = doorDef.modelVar3

        let x1 = t1X * 128
        let z1 = t1Z * 128
        let x2 = t2X * 128
        let z2 = t2Z * 128

        let v1 = model.insertVertex(x: x1, y: -tileElevationCache[t1X][t1Z], z: z1)
        let v2 = model.insertVertex(x: x1, y: -tileElevationCache[t1X][t1Z] - height, z: z1)
        let v3 = model.insertVertex(x: x2, y: -height - tileElevationCache[t2X][t2Z], z: z2)
        let v4 = model.insertVertex(x: x2, y: -tileElevationCache[t2X][t2Z], z: z2)

        let indices = [v1, v2, v3, v4]
        let face = model.insertFace(indexCount: 4, indices: indices, textureFront: frontTex, textureBack: backTex)
        if doorDef.unknown == 5 {
            model.facePickIndex[face] = 30000 + wallID
        } else {
            model.facePickIndex[face] = 0
        }
    }

    private func applyWallToElevationCache(_ wallID: Int, _ x1: Int, _ z1: Int, _ x2: Int, _ z2: Int) {
        guard let doorDef = EntityHandler.shared.getDoorDef(wallID) else { return }
        let height = doorDef.wallObjectHeight

        if tileElevationCache[x1][z1] < 80000 {
            tileElevationCache[x1][z1] += height + 80000
        }
        if tileElevationCache[x2][z2] < 80000 {
            tileElevationCache[x2][z2] += height + 80000
        }
    }

    // MARK: - Register Object Direction

    func registerObjectDir(_ x: Int, _ y: Int, _ dir: Int) {
        guard x >= 0 && x < 96 && y >= 0 && y < 96 else { return }
        tileDirection[x][y] = dir & 0xFF
    }

    // MARK: - Reset Models

    private func resetModels() {
        scene.removeAllGameObjects()

        for j in 0..<64 {
            modelLandscapeGrid[j] = nil
            for i in 0..<4 {
                modelWallGrid[i][j] = nil
            }
            for i in 0..<4 {
                modelRoofGrid[i][j] = nil
            }
        }
    }

    // MARK: - loadSections (public entry point)

    /// Called when the player moves to a new region. Loads terrain, walls, and roofs.
    /// Corresponds to Java loadSections(int worldX, int worldZ, int plane).
    func loadSections(worldX: Int, worldZ: Int, plane: Int) {
        resetModels()

        let chunkX = (24 + worldX) / 48
        let chunkZ = (24 + worldZ) / 48

        generateLandscapeModel(worldX: worldX, worldZ: worldZ, showWallOnMinimap: true, plane: plane)

        if plane == 0 {
            generateLandscapeModel(worldX: worldX, worldZ: worldZ, showWallOnMinimap: false, plane: 1)
            generateLandscapeModel(worldX: worldX, worldZ: worldZ, showWallOnMinimap: false, plane: 2)
            loadSection(0, plane, chunkX - 1, chunkZ - 1)
            loadSection(1, plane, chunkX, chunkZ - 1)
            loadSection(2, plane, chunkX - 1, chunkZ)
            loadSection(3, plane, chunkX, chunkZ)
            setTileDecorationOnBridge()
        }
    }

    // MARK: - generateLandscapeModel (THE critical method)

    /// Builds 3D geometry for a single plane: ground mesh, walls, and roofs.
    /// Corresponds to Java generateLandscapeModel (line ~507).
    private func generateLandscapeModel(worldX: Int, worldZ: Int, showWallOnMinimap: Bool, plane: Int) {
        let chunkX = (24 + worldX) / 48
        let chunkZ = (24 + worldZ) / 48

        loadSection(0, plane, chunkX - 1, chunkZ - 1)
        loadSection(1, plane, chunkX, chunkZ - 1)
        loadSection(2, plane, chunkX - 1, chunkZ)
        loadSection(3, plane, chunkX, chunkZ)
        setTileDecorationOnBridge()

        if modelAccumulate == nil {
            modelAccumulate = RSModel(vertexCount: 18688, faceCount: 18688)
        }

        // --- Ground mesh ---
        if showWallOnMinimap {
            minimapGraphics.blackScreen()

            for x in 0..<96 {
                for z in 0..<96 {
                    collisionFlags[x][z] = 0
                }
            }

            let worldMod = modelAccumulate!
            worldMod.resetFaceVertHead()

            // Insert ground vertices
            for x in 0..<96 {
                for z in 0..<96 {
                    var y = -getTileElevation(x, z)

                    // Water tiles (tileValue == 4) flatten elevation
                    if getTileDecorationID(x, z, plane) > 0,
                       let td = EntityHandler.shared.getTileDef(getTileDecorationID(x, z, plane) - 1),
                       td.tileValue == 4 {
                        y = 0
                    }
                    if getTileDecorationID(x - 1, z, plane) > 0,
                       let td = EntityHandler.shared.getTileDef(getTileDecorationID(x - 1, z, plane) - 1),
                       td.tileValue == 4 {
                        y = 0
                    }
                    if getTileDecorationID(x, z - 1, plane) > 0,
                       let td = EntityHandler.shared.getTileDef(getTileDecorationID(x, z - 1, plane) - 1),
                       td.tileValue == 4 {
                        y = 0
                    }
                    if getTileDecorationID(x - 1, z - 1, plane) > 0,
                       let td = EntityHandler.shared.getTileDef(getTileDecorationID(x - 1, z - 1, plane) - 1),
                       td.tileValue == 4 {
                        y = 0
                    }

                    let vID = worldMod.insertVertex(x: x * 128, y: y, z: z * 128)
                    let val = Int.random(in: 0..<10) - 5
                    worldMod.setVertexLightOther(id: vID, val: val)
                }
            }

            // Insert ground faces
            for x in 0..<95 {
                for z in 0..<95 {
                    var colorResource = colorToResource[getTerrainColour(x, z)]
                    var res01 = colorResource
                    var defaultVal = colorResource

                    if plane == 1 || plane == 2 {
                        colorResource = RSScene.TRANSPARENT
                        res01 = RSScene.TRANSPARENT
                        defaultVal = RSScene.TRANSPARENT
                    }

                    var bridge00_11 = 0

                    if getTileDecorationID(x, z, plane) > 0 {
                        let decorID = getTileDecorationID(x, z, plane)
                        guard let tileDef = EntityHandler.shared.getTileDef(decorID - 1) else { continue }
                        let decorType = tileDef.tileValue
                        let decorType2 = isTileType2(x, z, plane)

                        colorResource = Int(tileDef.colour)
                        res01 = colorResource

                        if decorType == 4 {
                            colorResource = 1
                            res01 = 1
                            if decorID == 12 {
                                colorResource = 31
                                res01 = 31
                            }
                        }

                        if decorType == 5 {
                            if getWallDiagonal(x, z) > 0 && getWallDiagonal(x, z) < 24000 {
                                if getTileDecorationCacheVal(x - 1, z, plane, defaultVal) != RSScene.TRANSPARENT
                                    && getTileDecorationCacheVal(x, z - 1, plane, defaultVal) != RSScene.TRANSPARENT {
                                    bridge00_11 = 0
                                    colorResource = getTileDecorationCacheVal(x - 1, z, plane, defaultVal)
                                } else if getTileDecorationCacheVal(x + 1, z, plane, defaultVal) != RSScene.TRANSPARENT
                                    && getTileDecorationCacheVal(x, z + 1, plane, defaultVal) != RSScene.TRANSPARENT {
                                    res01 = getTileDecorationCacheVal(x + 1, z, plane, defaultVal)
                                    bridge00_11 = 0
                                } else if getTileDecorationCacheVal(x + 1, z, plane, defaultVal) != RSScene.TRANSPARENT
                                    && getTileDecorationCacheVal(x, z - 1, plane, defaultVal) != RSScene.TRANSPARENT {
                                    res01 = getTileDecorationCacheVal(x + 1, z, plane, defaultVal)
                                    bridge00_11 = 1
                                } else if getTileDecorationCacheVal(x - 1, z, plane, defaultVal) != RSScene.TRANSPARENT
                                    && getTileDecorationCacheVal(x, z + 1, plane, defaultVal) != RSScene.TRANSPARENT {
                                    bridge00_11 = 1
                                    colorResource = getTileDecorationCacheVal(x - 1, z, plane, defaultVal)
                                }
                            }
                        } else if decorType != 2
                            || (getWallDiagonal(x, z) > 0 && getWallDiagonal(x, z) < 24000) {
                            if decorType2 != isTileType2(x - 1, z, plane)
                                && isTileType2(x, z - 1, plane) != decorType2 {
                                colorResource = defaultVal
                                bridge00_11 = 0
                            } else if decorType2 != isTileType2(x + 1, z, plane)
                                && isTileType2(x, z + 1, plane) != decorType2 {
                                bridge00_11 = 0
                                res01 = defaultVal
                            } else if decorType2 != isTileType2(x + 1, z, plane)
                                && isTileType2(x, z - 1, plane) != decorType2 {
                                res01 = defaultVal
                                bridge00_11 = 1
                            } else if decorType2 != isTileType2(x - 1, z, plane)
                                && decorType2 != isTileType2(x, z + 1, plane) {
                                colorResource = defaultVal
                                bridge00_11 = 1
                            }
                        }

                        if tileDef.objectType != 0 {
                            collisionFlags[x][z] |= CollisionFlag.FULL_BLOCK_C
                        }
                        if tileDef.tileValue == 2 {
                            collisionFlags[x][z] |= CollisionFlag.OBJECT
                        }
                    }

                    drawMinimapTile(x, z, bridge00_11, res01, colorResource)

                    let slope = getTileElevation(x + 1, z + 1) - getTileElevation(x, z)
                        + getTileElevation(x, z + 1) - getTileElevation(x + 1, z)

                    if colorResource == res01 && slope == 0 {
                        if colorResource != RSScene.TRANSPARENT {
                            let indices = [
                                z + (x + 1) * 96,   // (x+1, z)
                                z + x * 96,          // (x, z)
                                1 + x * 96 + z,      // (x, z+1)
                                z + (x + 1) * 96 + 1 // (x+1, z+1)
                            ]
                            let faceID = worldMod.insertFace(
                                indexCount: 4, indices: indices,
                                textureFront: RSScene.TRANSPARENT, textureBack: colorResource
                            )
                            faceTileX[faceID] = x
                            faceTileZ[faceID] = z
                            worldMod.facePickIndex[faceID] = faceID + 200000
                        }
                    } else {
                        var faceIndices1 = [Int](repeating: 0, count: 3)
                        var faceIndices2 = [Int](repeating: 0, count: 3)

                        if bridge00_11 == 0 {
                            if colorResource != RSScene.TRANSPARENT {
                                faceIndices1[0] = x * 96 + z + 96
                                faceIndices1[1] = x * 96 + z
                                faceIndices1[2] = 1 + z + x * 96
                                let faceID = worldMod.insertFace(
                                    indexCount: 3, indices: faceIndices1,
                                    textureFront: RSScene.TRANSPARENT, textureBack: colorResource
                                )
                                faceTileX[faceID] = x
                                faceTileZ[faceID] = z
                                worldMod.facePickIndex[faceID] = faceID + 200000
                            }
                            if res01 != RSScene.TRANSPARENT {
                                faceIndices2[0] = 1 + x * 96 + z
                                faceIndices2[1] = 97 + x * 96 + z
                                faceIndices2[2] = z + x * 96 + 96
                                let faceID = worldMod.insertFace(
                                    indexCount: 3, indices: faceIndices2,
                                    textureFront: RSScene.TRANSPARENT, textureBack: res01
                                )
                                faceTileX[faceID] = x
                                faceTileZ[faceID] = z
                                worldMod.facePickIndex[faceID] = faceID + 200000
                            }
                        } else {
                            if colorResource != RSScene.TRANSPARENT {
                                faceIndices1[0] = 1 + x * 96 + z
                                faceIndices1[1] = 96 + x * 96 + z + 1
                                faceIndices1[2] = z + x * 96
                                let faceID = worldMod.insertFace(
                                    indexCount: 3, indices: faceIndices1,
                                    textureFront: RSScene.TRANSPARENT, textureBack: colorResource
                                )
                                faceTileX[faceID] = x
                                faceTileZ[faceID] = z
                                worldMod.facePickIndex[faceID] = faceID + 200000
                            }
                            if res01 != RSScene.TRANSPARENT {
                                faceIndices2[0] = x * 96 + z + 96
                                faceIndices2[1] = z + x * 96
                                faceIndices2[2] = z + (x + 1) * 96 + 1
                                let faceID = worldMod.insertFace(
                                    indexCount: 3, indices: faceIndices2,
                                    textureFront: RSScene.TRANSPARENT, textureBack: res01
                                )
                                faceTileX[faceID] = x
                                faceTileZ[faceID] = z
                                worldMod.facePickIndex[faceID] = faceID + 200000
                            }
                        }
                    }
                }
            }

            // Water/bridge overlay faces (tileValue == 4)
            for x in 1..<95 {
                for z in 1..<95 {
                    if getTileDecorationID(x, z, plane) > 0,
                       let td = EntityHandler.shared.getTileDef(getTileDecorationID(x, z, plane) - 1),
                       td.tileValue == 4 {
                        let tileDecor = Int(td.colour)
                        let v00 = worldMod.insertVertex(x: x * 128, y: -getTileElevation(x, z), z: z * 128)
                        let v10 = worldMod.insertVertex(x: (x + 1) * 128, y: -getTileElevation(x + 1, z), z: z * 128)
                        let v11 = worldMod.insertVertex(x: (x + 1) * 128, y: -getTileElevation(x + 1, z + 1), z: (z + 1) * 128)
                        let v01 = worldMod.insertVertex(x: x * 128, y: -getTileElevation(x, z + 1), z: (z + 1) * 128)
                        let indices = [v00, v10, v11, v01]
                        let faceID = worldMod.insertFace(indexCount: 4, indices: indices, textureFront: tileDecor, textureBack: RSScene.TRANSPARENT)
                        faceTileX[faceID] = x
                        faceTileZ[faceID] = z
                        worldMod.facePickIndex[faceID] = faceID + 200000
                        drawMinimapTile(x, z, 0, tileDecor, tileDecor)
                    } else if getTileDecorationID(x, z, plane) == 0
                        || EntityHandler.shared.getTileDef(getTileDecorationID(x, z, plane) - 1)?.tileValue != 3 {
                        // Check adjacent water tiles and apply bridge overlays
                        applyAdjacentWaterOverlay(worldMod, x, z, plane)
                    }
                }
            }

            // Light and divide ground mesh into 64 sub-models
            worldMod.setDiffuseLightAndColor(dirX: -50, dirY: -10, dirZ: -50, p1: 40, p2: 48, allTransparent: true)
            if let grid = modelAccumulate?.divideModelByGrid(8, 1536, 64, 1536, 1536, false) {
                for i in 0..<64 {
                    modelLandscapeGrid[i] = grid[i]
                    scene.addModel(grid[i])
                }
            }

            // Initialize elevation cache from tile data
            for x in 0..<96 {
                for z in 0..<96 {
                    tileElevationCache[x][z] = getTileElevation(x, z)
                }
            }
        }

        // --- Walls ---
        modelAccumulate!.resetFaceVertHead()

        let wallColor: UInt32 = 0x606060 // 6316128

        for x in 0..<95 {
            for z in 0..<95 {
                var wall = getVerticalWall(x, z)
                if wall > 0 {
                    if let doorDef = EntityHandler.shared.getDoorDef(wall - 1),
                       doorDef.unknown == 0 || showInvisibleWalls {
                        insertWallIntoModel(wall - 1, modelAccumulate!, x + 1, z, x, z)
                        if showWallOnMinimap && doorDef.doorType != 0 {
                            collisionFlags[x][z] |= CollisionFlag.WALL_NORTH
                            if z > 0 {
                                collisionFlagBitwiseOr(x, z - 1, CollisionFlag.WALL_SOUTH)
                            }
                        }
                        if showWallOnMinimap {
                            minimapGraphics.drawLineHoriz(x: x * 3, y: z * 3, width: 3, color: wallColor)
                        }
                    }
                }

                wall = getHorizontalWall(x, z)
                if wall > 0 {
                    if let doorDef = EntityHandler.shared.getDoorDef(wall - 1),
                       doorDef.unknown == 0 || showInvisibleWalls {
                        insertWallIntoModel(wall - 1, modelAccumulate!, x, z, x, z + 1)
                        if showWallOnMinimap && doorDef.doorType != 0 {
                            collisionFlags[x][z] |= CollisionFlag.WALL_EAST
                            if x > 0 {
                                collisionFlagBitwiseOr(x - 1, z, CollisionFlag.WALL_WEST)
                            }
                        }
                        if showWallOnMinimap {
                            minimapGraphics.drawLineVert(x: x * 3, y: z * 3, height: 3, color: wallColor)
                        }
                    }
                }

                wall = getWallDiagonal(x, z)
                if wall > 0 && wall < 12000 {
                    if let doorDef = EntityHandler.shared.getDoorDef(wall - 1),
                       doorDef.unknown == 0 || showInvisibleWalls {
                        insertWallIntoModel(wall - 1, modelAccumulate!, x + 1, z, x, z + 1)
                        if showWallOnMinimap && doorDef.doorType != 0 {
                            collisionFlags[x][z] |= CollisionFlag.FULL_BLOCK_B
                        }
                    }
                }

                if wall > 12000 && wall < 24000 {
                    if let doorDef = EntityHandler.shared.getDoorDef(wall - 12001),
                       doorDef.unknown == 0 || showInvisibleWalls {
                        insertWallIntoModel(wall - 12001, modelAccumulate!, x, z, x + 1, z + 1)
                        if showWallOnMinimap && doorDef.doorType != 0 {
                            collisionFlags[x][z] |= CollisionFlag.FULL_BLOCK_A
                        }
                    }
                }
            }
        }

        // Light and divide wall mesh
        modelAccumulate!.setDiffuseLightAndColor(dirX: -50, dirY: -10, dirZ: -50, p1: 60, p2: 24, allTransparent: false)
        if let grid = modelAccumulate?.divideModelByGrid(8, 1536, 64, 1536, 1536, true) {
            modelWallGrid[plane] = [RSModel?](repeating: nil, count: 64)
            for i in 0..<64 {
                modelWallGrid[plane][i] = grid[i]
                scene.addModel(grid[i])
            }
        }

        // --- Elevation cache for roofs ---
        modelAccumulate!.resetFaceVertHead()

        for x in 0..<95 {
            for z in 0..<95 {
                var wall = getVerticalWall(x, z)
                if wall > 0 {
                    applyWallToElevationCache(wall - 1, x, z, x + 1, z)
                }
                wall = getHorizontalWall(x, z)
                if wall > 0 {
                    applyWallToElevationCache(wall - 1, x, z, x, z + 1)
                }
                wall = getWallDiagonal(x, z)
                if wall > 0 && wall < 12000 {
                    applyWallToElevationCache(wall - 1, x, z, x + 1, z + 1)
                }
                if wall > 12000 && wall < 24000 {
                    applyWallToElevationCache(wall - 12001, x + 1, z, x, z + 1)
                }
            }
        }

        // Clean elevation cache (propagate max height around roof corners)
        for x in 1..<95 {
            for z in 1..<95 {
                let roof = getWallRoof(x, z)
                if roof > 0 {
                    var ec00 = tileElevationCache[x][z]
                    var ec10 = tileElevationCache[x + 1][z]
                    var ec11 = tileElevationCache[x + 1][z + 1]
                    var ec01 = tileElevationCache[x][z + 1]

                    if ec00 > 80000 { ec00 -= 80000 }
                    if ec10 > 80000 { ec10 -= 80000 }
                    if ec11 > 80000 { ec11 -= 80000 }
                    if ec01 > 80000 { ec01 -= 80000 }

                    var maxVal = max(ec00, max(ec10, max(ec11, ec01)))
                    if maxVal >= 80000 { maxVal -= 80000 }

                    if tileElevationCache[x][z] < 80000 {
                        tileElevationCache[x][z] = maxVal
                    } else {
                        tileElevationCache[x][z] -= 80000
                    }
                    if tileElevationCache[x + 1][z] < 80000 {
                        tileElevationCache[x + 1][z] = maxVal
                    } else {
                        tileElevationCache[x + 1][z] -= 80000
                    }
                    if tileElevationCache[x + 1][z + 1] < 80000 {
                        tileElevationCache[x + 1][z + 1] = maxVal
                    } else {
                        tileElevationCache[x + 1][z + 1] -= 80000
                    }
                    if tileElevationCache[x][z + 1] < 80000 {
                        tileElevationCache[x][z + 1] = maxVal
                    } else {
                        tileElevationCache[x][z + 1] -= 80000
                    }
                }
            }
        }

        // --- Roof faces ---
        for x in 1..<95 {
            for z in 1..<95 {
                let roof = getWallRoof(x, z)
                if roof > 0 {
                    insertRoofFaces(x, z, roof)
                }
            }
        }

        // Light and divide roof mesh
        modelAccumulate!.setDiffuseLightAndColor(dirX: -50, dirY: -10, dirZ: -50, p1: 50, p2: 50, allTransparent: true)
        if let grid = modelAccumulate?.divideModelByGrid(8, 1536, 64, 1536, 1536, true) {
            modelRoofGrid[plane] = [RSModel?](repeating: nil, count: 64)
            for i in 0..<64 {
                modelRoofGrid[plane][i] = grid[i]
                scene.addModel(grid[i])
            }
        }

        // Final cleanup of elevation cache
        for x in 0..<96 {
            for z in 0..<96 {
                if tileElevationCache[x][z] >= 80000 {
                    tileElevationCache[x][z] -= 80000
                }
            }
        }
    }

    // MARK: - Adjacent Water Overlay Helper

    /// Applies water tile overlay to an adjacent non-water tile if any neighbor is water.
    private func applyAdjacentWaterOverlay(_ worldMod: RSModel, _ x: Int, _ z: Int, _ plane: Int) {
        // Check z+1
        if getTileDecorationID(x, z + 1, plane) > 0,
           let td = EntityHandler.shared.getTileDef(getTileDecorationID(x, z + 1, plane) - 1),
           td.tileValue == 4 {
            insertWaterQuad(worldMod, x, z, Int(td.colour))
        }
        // Check z-1
        if getTileDecorationID(x, z - 1, plane) > 0,
           let td = EntityHandler.shared.getTileDef(getTileDecorationID(x, z - 1, plane) - 1),
           td.tileValue == 4 {
            insertWaterQuad(worldMod, x, z, Int(td.colour))
        }
        // Check x+1
        if getTileDecorationID(x + 1, z, plane) > 0,
           let td = EntityHandler.shared.getTileDef(getTileDecorationID(x + 1, z, plane) - 1),
           td.tileValue == 4 {
            insertWaterQuad(worldMod, x, z, Int(td.colour))
        }
        // Check x-1
        if getTileDecorationID(x - 1, z, plane) > 0,
           let td = EntityHandler.shared.getTileDef(getTileDecorationID(x - 1, z, plane) - 1),
           td.tileValue == 4 {
            insertWaterQuad(worldMod, x, z, Int(td.colour))
        }
    }

    private func insertWaterQuad(_ worldMod: RSModel, _ x: Int, _ z: Int, _ tileDecor: Int) {
        let v00 = worldMod.insertVertex(x: x * 128, y: -getTileElevation(x, z), z: z * 128)
        let v10 = worldMod.insertVertex(x: (x + 1) * 128, y: -getTileElevation(x + 1, z), z: z * 128)
        let v11 = worldMod.insertVertex(x: (x + 1) * 128, y: -getTileElevation(x + 1, z + 1), z: (z + 1) * 128)
        let v01 = worldMod.insertVertex(x: x * 128, y: -getTileElevation(x, z + 1), z: (z + 1) * 128)
        let indices = [v00, v10, v11, v01]
        let faceID = worldMod.insertFace(indexCount: 4, indices: indices, textureFront: tileDecor, textureBack: RSScene.TRANSPARENT)
        faceTileX[faceID] = x
        faceTileZ[faceID] = z
        worldMod.facePickIndex[faceID] = faceID + 200000
        drawMinimapTile(x, z, 0, tileDecor, tileDecor)
    }

    // MARK: - Roof Face Insertion

    /// Inserts roof geometry for a single tile. Handles eave offsets and diagonal splitting.
    private func insertRoofFaces(_ x: Int, _ z: Int, _ roofID: Int) {
        guard let elevDef = EntityHandler.shared.getElevationDef(roofID - 1) else { return }
        let accumModel = modelAccumulate!

        let roofHeightAdd = elevDef.unknown1

        var ec00 = tileElevationCache[x][z]
        var ec10 = tileElevationCache[x + 1][z]
        var ec11 = tileElevationCache[x + 1][z + 1]
        var ec01 = tileElevationCache[x][z + 1]

        // Apply roof height to corners that have all 4 surrounding roof tiles
        if hasRoofTile(x, z) && ec00 < 80000 {
            ec00 += roofHeightAdd + 80000
            tileElevationCache[x][z] = ec00
        }
        if hasRoofTile(x + 1, z) && ec10 < 80000 {
            ec10 += roofHeightAdd + 80000
            tileElevationCache[x + 1][z] = ec10
        }
        if hasRoofTile(x + 1, z + 1) && ec11 < 80000 {
            ec11 += roofHeightAdd + 80000
            tileElevationCache[x + 1][z + 1] = ec11
        }
        if hasRoofTile(x, z + 1) && ec01 < 80000 {
            ec01 += roofHeightAdd + 80000
            tileElevationCache[x][z + 1] = ec01
        }

        if ec00 >= 80000 { ec00 -= 80000 }
        if ec10 >= 80000 { ec10 -= 80000 }
        if ec11 >= 80000 { ec11 -= 80000 }
        if ec01 >= 80000 { ec01 -= 80000 }

        let roofTex = elevDef.unknown2
        ec00 = -ec00; ec10 = -ec10; ec11 = -ec11; ec01 = -ec01

        // Eave offsets
        let eaveSize = 16
        var p00x = x * 128, p00z = z * 128
        var p10x = (x + 1) * 128, p10z = z * 128
        var p11x = (x + 1) * 128, p11z = (z + 1) * 128
        var p01x = x * 128, p01z = (z + 1) * 128

        if hasRoofStrut(x - 1, z) { p00x -= eaveSize }
        if hasRoofStrut(x + 1, z) { p00x += eaveSize }
        if hasRoofStrut(x, z - 1) { p00z -= eaveSize }
        if hasRoofStrut(x, z + 1) { p00z += eaveSize }

        if hasRoofStrut(x + 1 - 1, z) { p10x -= eaveSize }
        if hasRoofStrut(x + 1 + 1, z) { p10x += eaveSize }
        if hasRoofStrut(x + 1, z - 1) { p10z -= eaveSize }
        if hasRoofStrut(x + 1, z + 1) { p10z += eaveSize }

        if hasRoofStrut(x + 1 - 1, z + 1) { p11x -= eaveSize }
        if hasRoofStrut(x + 1 + 1, z + 1) { p11x += eaveSize }
        if hasRoofStrut(x + 1, z + 1 - 1) { p11z -= eaveSize }
        if hasRoofStrut(x + 1, z + 1 + 1) { p11z += eaveSize }

        if hasRoofStrut(x - 1, z + 1) { p01x -= eaveSize }
        if hasRoofStrut(x + 1, z + 1) { p01x += eaveSize }
        if hasRoofStrut(x, z + 1 - 1) { p01z -= eaveSize }
        if hasRoofStrut(x, z + 1 + 1) { p01z += eaveSize }

        // Determine roof face shape based on diagonal walls
        let diagWall = getWallDiagonal(x, z)

        if diagWall > 12000 && diagWall < 24000 && getWallRoof(x - 1, z - 1) == 0 {
            let idx = [
                accumModel.insertVertex(x: p11x, y: ec11, z: p11z),
                accumModel.insertVertex(x: p01x, y: ec01, z: p01z),
                accumModel.insertVertex(x: p10x, y: ec10, z: p10z)
            ]
            accumModel.insertFace(indexCount: 3, indices: idx, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)
        } else if diagWall > 12000 && diagWall < 24000 && getWallRoof(x + 1, z + 1) == 0 {
            let idx = [
                accumModel.insertVertex(x: p00x, y: ec00, z: p00z),
                accumModel.insertVertex(x: p10x, y: ec10, z: p10z),
                accumModel.insertVertex(x: p01x, y: ec01, z: p01z)
            ]
            accumModel.insertFace(indexCount: 3, indices: idx, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)
        } else if diagWall > 0 && diagWall < 12000 && getWallRoof(x + 1, z - 1) == 0 {
            let idx = [
                accumModel.insertVertex(x: p01x, y: ec01, z: p01z),
                accumModel.insertVertex(x: p00x, y: ec00, z: p00z),
                accumModel.insertVertex(x: p11x, y: ec11, z: p11z)
            ]
            accumModel.insertFace(indexCount: 3, indices: idx, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)
        } else if diagWall > 0 && diagWall < 12000 && getWallRoof(x - 1, z + 1) == 0 {
            let idx = [
                accumModel.insertVertex(x: p10x, y: ec10, z: p10z),
                accumModel.insertVertex(x: p11x, y: ec11, z: p11z),
                accumModel.insertVertex(x: p00x, y: ec00, z: p00z)
            ]
            accumModel.insertFace(indexCount: 3, indices: idx, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)
        } else if ec10 == ec00 && ec11 == ec01 {
            let idx = [
                accumModel.insertVertex(x: p00x, y: ec00, z: p00z),
                accumModel.insertVertex(x: p10x, y: ec10, z: p10z),
                accumModel.insertVertex(x: p11x, y: ec11, z: p11z),
                accumModel.insertVertex(x: p01x, y: ec01, z: p01z)
            ]
            accumModel.insertFace(indexCount: 4, indices: idx, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)
        } else if ec00 == ec01 && ec11 == ec10 {
            let idx = [
                accumModel.insertVertex(x: p01x, y: ec01, z: p01z),
                accumModel.insertVertex(x: p00x, y: ec00, z: p00z),
                accumModel.insertVertex(x: p10x, y: ec10, z: p10z),
                accumModel.insertVertex(x: p11x, y: ec11, z: p11z)
            ]
            accumModel.insertFace(indexCount: 4, indices: idx, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)
        } else {
            // Split into two triangles depending on diagonal neighbor roofs
            var splitDiag = true
            if getWallRoof(x - 1, z - 1) > 0 { splitDiag = false }
            if getWallRoof(x + 1, z + 1) > 0 { splitDiag = false }

            if !splitDiag {
                let idx1 = [
                    accumModel.insertVertex(x: p10x, y: ec10, z: p10z),
                    accumModel.insertVertex(x: p11x, y: ec11, z: p11z),
                    accumModel.insertVertex(x: p00x, y: ec00, z: p00z)
                ]
                accumModel.insertFace(indexCount: 3, indices: idx1, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)

                let idx2 = [
                    accumModel.insertVertex(x: p01x, y: ec01, z: p01z),
                    accumModel.insertVertex(x: p00x, y: ec00, z: p00z),
                    accumModel.insertVertex(x: p11x, y: ec11, z: p11z)
                ]
                accumModel.insertFace(indexCount: 3, indices: idx2, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)
            } else {
                let idx1 = [
                    accumModel.insertVertex(x: p00x, y: ec00, z: p00z),
                    accumModel.insertVertex(x: p10x, y: ec10, z: p10z),
                    accumModel.insertVertex(x: p01x, y: ec01, z: p01z)
                ]
                accumModel.insertFace(indexCount: 3, indices: idx1, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)

                let idx2 = [
                    accumModel.insertVertex(x: p11x, y: ec11, z: p11z),
                    accumModel.insertVertex(x: p01x, y: ec01, z: p01z),
                    accumModel.insertVertex(x: p10x, y: ec10, z: p10z)
                ]
                accumModel.insertFace(indexCount: 3, indices: idx2, textureFront: roofTex, textureBack: RSScene.TRANSPARENT)
            }
        }
    }

    // MARK: - Collision Flag Management

    /// Applies a wall object's collision flags.
    /// Corresponds to Java applyWallToCollisionFlags.
    func applyWallToCollisionFlags(wallID: Int, x: Int, z: Int, dir: Int) {
        guard x >= 0 && z >= 0 && x < 95 && z < 95 else { return }
        guard let doorDef = EntityHandler.shared.getDoorDef(wallID), doorDef.doorType == 1 else { return }

        if dir == 0 {
            collisionFlags[x][z] |= CollisionFlag.WALL_NORTH
            if z > 0 { collisionFlagBitwiseOr(x, z - 1, CollisionFlag.WALL_SOUTH) }
        } else if dir == 1 {
            collisionFlags[x][z] |= CollisionFlag.WALL_EAST
            if x > 0 { collisionFlagBitwiseOr(x - 1, z, CollisionFlag.WALL_WEST) }
        } else if dir == 2 {
            collisionFlags[x][z] |= CollisionFlag.FULL_BLOCK_A
        } else if dir == 3 {
            collisionFlags[x][z] |= CollisionFlag.FULL_BLOCK_B
        }

        setVertexLightArea(x, z, 1, 1)
    }

    /// Adds a game object to the scene and updates collision flags.
    /// Corresponds to Java addGameObject_UpdateCollisionMap.
    func addGameObject_UpdateCollisionMap(xTile: Int, zTile: Int, objectID: Int) {
        guard xTile >= 0 && zTile >= 0 && xTile < 95 && zTile < 95 else { return }
        guard let objDef = EntityHandler.shared.getObjectDef(objectID),
              objDef.type == 1 || objDef.type == 2 else { return }

        let dir = getTileDirection(xTile, zTile)
        let xSize: Int
        let zSize: Int
        if dir == 0 || dir == 4 {
            xSize = objDef.width
            zSize = objDef.height
        } else {
            xSize = objDef.height
            zSize = objDef.width
        }

        for xi in xTile..<(xSize + xTile) {
            for zi in zTile..<(zTile + zSize) {
                if objDef.type == 1 {
                    collisionFlags[xi][zi] |= CollisionFlag.FULL_BLOCK_C
                } else if dir == 0 {
                    collisionFlags[xi][zi] |= CollisionFlag.WALL_EAST
                    if xi > 0 { collisionFlagBitwiseOr(xi - 1, zi, CollisionFlag.WALL_WEST) }
                } else if dir == 2 {
                    collisionFlags[xi][zi] |= CollisionFlag.WALL_SOUTH
                    if zi < 95 { collisionFlagBitwiseOr(xi, zi + 1, CollisionFlag.WALL_NORTH) }
                } else if dir == 4 {
                    collisionFlags[xi][zi] |= CollisionFlag.WALL_WEST
                    if xi < 95 { collisionFlagBitwiseOr(xi + 1, zi, CollisionFlag.WALL_EAST) }
                } else if dir == 6 {
                    collisionFlags[xi][zi] |= CollisionFlag.WALL_NORTH
                    if zi > 0 { collisionFlagBitwiseOr(xi, zi - 1, CollisionFlag.WALL_SOUTH) }
                }
            }
        }

        setVertexLightArea(xTile, zTile, xSize, zSize)
    }

    /// Removes a game object's collision flags.
    /// Corresponds to Java removeGameObject_CollisonFlags.
    func removeGameObject_CollisionFlags(id: Int, x: Int, z: Int) {
        guard x >= 0 && z >= 0 && x < 95 && z < 95 else { return }
        guard let objDef = EntityHandler.shared.getObjectDef(id),
              objDef.type == 1 || objDef.type == 2 else { return }

        let dir = getTileDirection(x, z)
        let xSize: Int
        let zSize: Int
        if dir == 0 || dir == 4 {
            xSize = objDef.width
            zSize = objDef.height
        } else {
            xSize = objDef.height
            zSize = objDef.width
        }

        for xi in x..<(x + xSize) {
            for zi in z..<(z + zSize) {
                if objDef.type == 1 {
                    collisionFlags[xi][zi] &= ~CollisionFlag.FULL_BLOCK_C
                } else if dir == 0 {
                    collisionFlags[xi][zi] &= ~CollisionFlag.WALL_EAST
                    if xi > 0 { collisionFlagModify(xi - 1, zi, 0xFFFF, CollisionFlag.WALL_WEST) }
                } else if dir == 2 {
                    collisionFlags[xi][zi] &= ~CollisionFlag.WALL_SOUTH
                    if zi < 95 { collisionFlagModify(xi, zi + 1, 0xFFFF, CollisionFlag.WALL_NORTH) }
                } else if dir == 4 {
                    collisionFlags[xi][zi] &= ~CollisionFlag.WALL_WEST
                    if xi < 95 { collisionFlagModify(xi + 1, zi, 0xFFFF, CollisionFlag.WALL_EAST) }
                } else if dir == 6 {
                    collisionFlags[xi][zi] &= ~CollisionFlag.WALL_NORTH
                    if zi > 0 { collisionFlagModify(xi, zi - 1, 0xFFFF, CollisionFlag.WALL_SOUTH) }
                }
            }
        }

        setVertexLightArea(x, z, xSize, zSize)
    }

    /// Removes a wall object's collision flags.
    /// Corresponds to Java removeWallObject_CollisionFlags.
    func removeWallObject_CollisionFlags(dir: Int, z: Int, x: Int, id: Int) {
        guard x >= 0 && z >= 0 && x < 95 && z < 95 else { return }
        guard let doorDef = EntityHandler.shared.getDoorDef(id), doorDef.doorType == 1 else { return }

        if dir == 0 {
            collisionFlags[x][z] &= ~CollisionFlag.WALL_NORTH
            if z > 0 { collisionFlagModify(x, z - 1, 0xFFFF, CollisionFlag.WALL_SOUTH) }
        } else if dir == 1 {
            collisionFlags[x][z] &= ~CollisionFlag.WALL_EAST
            if x > 0 { collisionFlagModify(x - 1, z, 0xFFFF, CollisionFlag.WALL_WEST) }
        } else if dir == 2 {
            collisionFlags[x][z] &= ~CollisionFlag.FULL_BLOCK_A
        } else if dir == 3 {
            collisionFlags[x][z] &= ~CollisionFlag.FULL_BLOCK_B
        }

        setVertexLightArea(x, z, 1, 1)
    }

    // MARK: - Login Screen Models

    /// Places 3D object models on the login screen landscape.
    /// Corresponds to Java addLoginScreenModels.
    func addLoginScreenModels(_ modelTable: [RSModel]) {
        for x in 0..<94 {
            for z in 0..<94 {
                let diagWall = getWallDiagonal(x, z)
                if diagWall > 48000 && diagWall < 60000 {
                    let objID = diagWall - 48001
                    guard let objDef = EntityHandler.shared.getObjectDef(objID) else { continue }

                    let dir = getTileDirection(x, z)
                    let xSize: Int
                    let zSize: Int
                    if dir == 0 || dir == 4 {
                        xSize = objDef.width
                        zSize = objDef.height
                    } else {
                        xSize = objDef.height
                        zSize = objDef.width
                    }

                    addGameObject_UpdateCollisionMap(xTile: x, zTile: z, objectID: objID)

                    // Find model index - use objectModel name to find in table
                    // The Java uses EntityHandler.getObjectDef(objID).modelID which maps to an index in modelTable
                    // For now we use objDef.id as a lookup key (the caller provides the table)
                    guard objDef.id >= 0 && objDef.id < modelTable.count else { continue }
                    let copy = modelTable[objDef.id].copyModel(m_v: false, m_c: false, noDiffuse: false, m_db: true)

                    let xTranslate = (xSize + x + x) * 128 / 2
                    let zTranslate = (zSize + z + z) * 128 / 2
                    copy.translate2(dx: xTranslate, dy: -getElevation(x: xTranslate, z: zTranslate), dz: zTranslate)
                    copy.setRot256(x: 0, y: getTileDirection(x, z) * 32, z: 0)
                    scene.addModel(copy)
                    copy.setDiffuseLight(param1: 48, param2: 48, dirX: -50, dirY: -10, dirZ: -50)

                    // Clear duplicate diagonal wall entries for multi-tile objects
                    if xSize > 1 || zSize > 1 {
                        for xi in x..<(x + xSize) {
                            for zi in z..<(zSize + z) {
                                if (x < xi || z < zi) && objID == getWallDiagonal(xi, zi) - 48001 {
                                    // In Java this clears the diagonal wall on that sector tile.
                                    // Since our LandscapeArchive is immutable, this is a no-op.
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Path Finding

    /// A* pathfinding on the collision grid.
    /// Returns the number of nodes in the path, or -1 if no path found.
    /// Corresponds to Java findPath.
    func findPath(pathX: inout [Int], pathZ: inout [Int],
                  startX: Int, startZ: Int,
                  xLow: Int, xHigh: Int,
                  zLow: Int, zHigh: Int,
                  reachBorder: Bool) -> Int {

        for x in 0..<96 {
            for y in 0..<96 {
                pathFindSource[x][y] = 0
            }
        }

        var openListRead = 0
        var x = startX
        var z = startZ
        pathFindSource[startX][startZ] = 99
        pathX[0] = startX
        pathZ[0] = startZ
        var openListWrite = 1
        let openListSize = pathX.count
        var complete = false

        while openListRead != openListWrite {
            x = pathX[openListRead]
            z = pathZ[openListRead]
            openListRead = (1 + openListRead) % openListSize

            if x >= xLow && x <= xHigh && z >= zLow && z <= zHigh {
                complete = true
                break
            }

            if reachBorder {
                if x > 0 && xLow <= x - 1 && xHigh >= x - 1 && zLow <= z && zHigh >= z
                    && (collisionFlags[x - 1][z] & CollisionFlag.WALL_WEST) == 0 {
                    complete = true; break
                }
                if x < 95 && x + 1 >= xLow && x + 1 <= xHigh && z >= zLow && zHigh >= z
                    && (collisionFlags[x + 1][z] & CollisionFlag.WALL_EAST) == 0 {
                    complete = true; break
                }
                if z > 0 && xLow <= x && xHigh >= x && z - 1 >= zLow && zHigh >= z - 1
                    && (collisionFlags[x][z - 1] & CollisionFlag.WALL_SOUTH) == 0 {
                    complete = true; break
                }
                if z < 95 && xLow <= x && x <= xHigh && zLow <= z + 1 && zHigh >= z + 1
                    && (collisionFlags[x][z + 1] & CollisionFlag.WALL_NORTH) == 0 {
                    complete = true; break
                }
            }

            // Cardinal directions
            if x > 0 && pathFindSource[x - 1][z] == 0
                && (collisionFlags[x - 1][z] & CollisionFlag.WEST_BLOCKED) == 0 {
                pathX[openListWrite] = x - 1
                pathZ[openListWrite] = z
                pathFindSource[x - 1][z] = CollisionFlag.SOURCE_WEST
                openListWrite = (openListWrite + 1) % openListSize
            }
            if x < 95 && pathFindSource[x + 1][z] == 0
                && (collisionFlags[x + 1][z] & CollisionFlag.EAST_BLOCKED) == 0 {
                pathX[openListWrite] = x + 1
                pathZ[openListWrite] = z
                pathFindSource[x + 1][z] = CollisionFlag.SOURCE_EAST
                openListWrite = (openListWrite + 1) % openListSize
            }
            if z > 0 && pathFindSource[x][z - 1] == 0
                && (collisionFlags[x][z - 1] & CollisionFlag.SOUTH_BLOCKED) == 0 {
                pathX[openListWrite] = x
                pathZ[openListWrite] = z - 1
                pathFindSource[x][z - 1] = CollisionFlag.SOURCE_SOUTH
                openListWrite = (openListWrite + 1) % openListSize
            }
            if z < 95 && pathFindSource[x][z + 1] == 0
                && (collisionFlags[x][z + 1] & CollisionFlag.NORTH_BLOCKED) == 0 {
                pathX[openListWrite] = x
                pathZ[openListWrite] = z + 1
                pathFindSource[x][z + 1] = CollisionFlag.SOURCE_NORTH
                openListWrite = (openListWrite + 1) % openListSize
            }

            // Diagonal directions
            if x > 0 && z > 0
                && (collisionFlags[x][z - 1] & CollisionFlag.SOUTH_BLOCKED) == 0
                && (collisionFlags[x - 1][z] & CollisionFlag.WEST_BLOCKED) == 0
                && (collisionFlags[x - 1][z - 1] & CollisionFlag.SOUTH_WEST_BLOCKED) == 0
                && pathFindSource[x - 1][z - 1] == 0 {
                pathX[openListWrite] = x - 1
                pathZ[openListWrite] = z - 1
                pathFindSource[x - 1][z - 1] = CollisionFlag.SOURCE_SOUTH_WEST
                openListWrite = (openListWrite + 1) % openListSize
            }
            if x < 95 && z > 0
                && (collisionFlags[x][z - 1] & CollisionFlag.SOUTH_BLOCKED) == 0
                && (collisionFlags[x + 1][z] & CollisionFlag.EAST_BLOCKED) == 0
                && (collisionFlags[x + 1][z - 1] & CollisionFlag.SOUTH_EAST_BLOCKED) == 0
                && pathFindSource[x + 1][z - 1] == 0 {
                pathX[openListWrite] = x + 1
                pathZ[openListWrite] = z - 1
                pathFindSource[x + 1][z - 1] = CollisionFlag.SOURCE_SOUTH_EAST
                openListWrite = (openListWrite + 1) % openListSize
            }
            if x > 0 && z < 95
                && (collisionFlags[x][z + 1] & CollisionFlag.NORTH_BLOCKED) == 0
                && (collisionFlags[x - 1][z] & CollisionFlag.WEST_BLOCKED) == 0
                && (collisionFlags[x - 1][z + 1] & CollisionFlag.NORTH_WEST_BLOCKED) == 0
                && pathFindSource[x - 1][z + 1] == 0 {
                pathX[openListWrite] = x - 1
                pathZ[openListWrite] = z + 1
                pathFindSource[x - 1][z + 1] = CollisionFlag.SOURCE_NORTH_WEST
                openListWrite = (openListWrite + 1) % openListSize
            }
            if x < 95 && z < 95
                && (collisionFlags[x][z + 1] & CollisionFlag.NORTH_BLOCKED) == 0
                && (collisionFlags[x + 1][z] & CollisionFlag.EAST_BLOCKED) == 0
                && (collisionFlags[x + 1][z + 1] & CollisionFlag.NORTH_EAST_BLOCKED) == 0
                && pathFindSource[x + 1][z + 1] == 0 {
                pathX[openListWrite] = x + 1
                pathZ[openListWrite] = z + 1
                pathFindSource[x + 1][z + 1] = CollisionFlag.SOURCE_NORTH_EAST
                openListWrite = (openListWrite + 1) % openListSize
            }
        }

        guard complete else { return -1 }

        pathX[0] = x
        pathZ[0] = z
        var openListIdx = 1

        var prevSource = pathFindSource[x][z]
        var source = prevSource

        while x != startX || z != startZ {
            if prevSource != source {
                prevSource = source
                pathX[openListIdx] = x
                pathZ[openListIdx] = z
                openListIdx += 1
            }

            if (source & CollisionFlag.SOURCE_SOUTH) != 0 {
                z += 1
            } else if (source & CollisionFlag.SOURCE_NORTH) != 0 {
                z -= 1
            }

            if (source & CollisionFlag.SOURCE_WEST) != 0 {
                x += 1
            } else if (source & CollisionFlag.SOURCE_EAST) != 0 {
                x -= 1
            }

            source = pathFindSource[x][z]
        }

        return openListIdx
    }
}
