// Port of Client_Base/src/orsc/graphics/three/World.java
import Foundation

final class World {
    static let generatedTerrainViewSize = 32
    static let generatedTerrainHalfExtent = generatedTerrainViewSize / 2

    static func isTileOffsetInsideGeneratedTerrain(dx: Int, dz: Int) -> Bool {
        dx >= -generatedTerrainHalfExtent && dx < generatedTerrainHalfExtent
            && dz >= -generatedTerrainHalfExtent && dz < generatedTerrainHalfExtent
    }

    // Tile grids: [plane][tile_index] where each plane has 64 tiles (8x8)
    var modelLandscapeGrid: [RSModel?]
    var modelWallGrid: [[RSModel?]]
    var modelRoofGrid: [[RSModel?]]

    // Collision and elevation cache
    var collisionFlags: [[Int]]      // [96][96]
    var tileElevationCache: [[Int]]  // [96][96]

    // Palette for tile colors
    var colorToResource: [Int] = []

    // Scene reference
    var scene: Scene
    var graphics: GraphicsController

    // Current loaded region
    var currentPlane: Int = 0
    var currentBaseX: Int = 0
    var currentBaseZ: Int = 0

    // Terrain data (loaded from LandscapeArchiveReader or server)
    var landscapeData: [[[Int]]] = []  // [plane][sector_y][sector_x] containing tile data

    init(scene: Scene, graphics: GraphicsController) {
        self.scene = scene
        self.graphics = graphics

        // Initialize grids
        self.modelLandscapeGrid = [RSModel?](repeating: nil, count: 64)
        self.modelWallGrid = [[RSModel?]](repeating: [RSModel?](repeating: nil, count: 64), count: 4)
        self.modelRoofGrid = [[RSModel?]](repeating: [RSModel?](repeating: nil, count: 64), count: 4)

        // Initialize collision and elevation
        self.collisionFlags = [[Int]](repeating: [Int](repeating: 0, count: 96), count: 96)
        self.tileElevationCache = [[Int]](repeating: [Int](repeating: 0, count: 96), count: 96)

        // Build color-to-resource palette (simplified)
        self.colorToResource = [Int](repeating: 0, count: 256)
        for i in 0..<256 {
            self.colorToResource[i] = i  // Direct mapping for now
        }
    }

    // MARK: - Terrain Loading

    func loadSections(worldX: Int, worldZ: Int, plane: Int) {
        // Called when player enters a new region
        // Load landscape data for this region's 4 sectors (48×48 each → 96×96 tiles)

        currentPlane = plane
        currentBaseX = worldX
        currentBaseZ = worldZ

        // Clear old geometry
        for i in 0..<64 {
            modelLandscapeGrid[i] = nil
            for p in 0..<4 {
                modelWallGrid[p][i] = nil
                modelRoofGrid[p][i] = nil
            }
        }

        // Generate landscape models for this region
        generateLandscapeModel(plane: plane)
    }

    // Reference to landscape loader for real terrain data
    var landscapeLoader: LandscapeLoader?

    func generateLandscapeModel(plane: Int) {
        // Build ground mesh from tile data
        // Each tile is 128×128 game units
        // Uses real landscape data from LandscapeLoader

        let tileSize: Int32 = 128

        // Create landscape model for visible area around player
        // Render 32x32 tiles (1024 faces, 4096 verts) for performance
        let viewSize = Self.generatedTerrainViewSize
        let model = RSModel(vertexCount: Int32(viewSize * viewSize * 4 + 100), faceCount: Int32(viewSize * viewSize + 100))

        // Compute the absolute sector coordinates from the current position
        let absBaseX = currentBaseX  // These should be in sector-space
        let absBaseZ = currentBaseZ

        var faceCount = 0
        var texturedFaceCount = 0
        let half = viewSize / 2
        let loadedTextureCount = scene.loadedTextureCount

        for tileZ in (-half)..<half {
            for tileX in (-half)..<half {
                let worldTX = absBaseX + tileX
                let worldTZ = absBaseZ + tileZ

                var color: Int32
                var terrainTextureIndex: Int32 = -1
                var elev: Int32 = 0

                if let loader = landscapeLoader, loader.isLoaded,
                   let tile = loader.getTile(worldX: worldTX, worldZ: worldTZ, plane: plane) {
                    color = LandscapeLoader.tileColor(overlay: tile.groundOverlay, texture: tile.groundTexture, elevation: tile.groundElevation)
                    if tile.groundTexture > 0 && tile.groundTexture <= loadedTextureCount {
                        terrainTextureIndex = Int32(tile.groundTexture - 1)
                    }
                    elev = Int32(tile.groundElevation)
                } else {
                    let tileDef = EntityDefinitions.getTileDef((tileZ * 96 + tileX) % 25)
                    color = tileDef?.colour ?? Int32(bitPattern: 0xFF808080)
                }

                // Skip transparent tiles
                if color == Scene.TRANSPARENT { continue }

                // Build quad using tile-relative coordinates (relative to player, like Java client)
                // tileX/tileZ are already relative offsets from -half to +half
                let baseX = Int32(tileX) * tileSize
                let baseZ = Int32(tileZ) * tileSize
                let y00 = -landscapeElevation(worldTileX: worldTX, worldTileZ: worldTZ, plane: plane, fallback: elev) * 3
                let y10 = -landscapeElevation(worldTileX: worldTX + 1, worldTileZ: worldTZ, plane: plane, fallback: elev) * 3
                let y11 = -landscapeElevation(worldTileX: worldTX + 1, worldTileZ: worldTZ + 1, plane: plane, fallback: elev) * 3
                let y01 = -landscapeElevation(worldTileX: worldTX, worldTileZ: worldTZ + 1, plane: plane, fallback: elev) * 3

                // 4 vertices for quad — use direct array access (skip duplicate search for speed)
                let vi = model.vertHead
                guard vi + 3 < model.vertexCount2 else { continue }
                model.vertX[Int(vi)] = baseX;     model.vertY[Int(vi)] = y00;   model.vertZ[Int(vi)] = baseZ
                model.vertX[Int(vi+1)] = baseX + tileSize; model.vertY[Int(vi+1)] = y10; model.vertZ[Int(vi+1)] = baseZ
                model.vertX[Int(vi+2)] = baseX + tileSize; model.vertY[Int(vi+2)] = y11; model.vertZ[Int(vi+2)] = baseZ + tileSize
                model.vertX[Int(vi+3)] = baseX;   model.vertY[Int(vi+3)] = y01; model.vertZ[Int(vi+3)] = baseZ + tileSize
                model.vertHead += 4
                let v0 = vi; let v1 = vi + 1; let v2 = vi + 2; let v3 = vi + 3

                // Face with color as front texture
                let faceIndices: [Int32] = [v0, v1, v2, v3]
                model.insertFace(count: 4, indices: faceIndices, texFront: color, texBack: terrainTextureIndex)

                faceCount += 1
                if terrainTextureIndex >= 0 { texturedFaceCount += 1 }
            }
        }

        print("[World] Generated landscape: \(faceCount) faces, \(model.vertHead) verts, textured=\(texturedFaceCount)")

        // Force full bounding box recalculation (m_Yb=2 sets bounds to ±9999999)
        model.m_Yb = 2
        model.occludesBillboards = false

        // Add model to scene
        modelLandscapeGrid[plane] = model
        scene.addModel(model)
    }

    // MARK: - Elevation

    func getElevation(x: Int, z: Int) -> Int {
        // Java World.getElevation expects scene-local world units and samples
        // the 96x96 terrain window. Our mesh is generated relative to the
        // current player tile, so convert the local unit coordinate back to an
        // absolute landscape tile before sampling.
        let tileOffsetX = Self.floorDiv(x, 128)
        let tileOffsetZ = Self.floorDiv(z, 128)
        var xLerp = Self.floorMod(x, 128)
        var zLerp = Self.floorMod(z, 128)

        let xTile = currentBaseX + tileOffsetX
        let zTile = currentBaseZ + tileOffsetZ

        let tileCorner: Int
        let dEX: Int
        let dEZ: Int
        if xLerp <= 128 - zLerp {
            tileCorner = scaledLandscapeElevation(worldTileX: xTile, worldTileZ: zTile)
            dEX = scaledLandscapeElevation(worldTileX: xTile + 1, worldTileZ: zTile) - tileCorner
            dEZ = scaledLandscapeElevation(worldTileX: xTile, worldTileZ: zTile + 1) - tileCorner
        } else {
            tileCorner = scaledLandscapeElevation(worldTileX: xTile + 1, worldTileZ: zTile + 1)
            dEX = scaledLandscapeElevation(worldTileX: xTile, worldTileZ: zTile + 1) - tileCorner
            dEZ = scaledLandscapeElevation(worldTileX: xTile + 1, worldTileZ: zTile) - tileCorner
            xLerp = 128 - xLerp
            zLerp = 128 - zLerp
        }

        return tileCorner + dEX * xLerp / 128 + dEZ * zLerp / 128
    }

    private func landscapeElevation(worldTileX: Int, worldTileZ: Int, plane: Int, fallback: Int32 = 0) -> Int32 {
        guard let loader = landscapeLoader, loader.isLoaded,
              let tile = loader.getTile(worldX: worldTileX, worldZ: worldTileZ, plane: plane) else {
            return fallback
        }
        return Int32(tile.groundElevation)
    }

    private func scaledLandscapeElevation(worldTileX: Int, worldTileZ: Int) -> Int {
        Int(landscapeElevation(worldTileX: worldTileX, worldTileZ: worldTileZ, plane: currentPlane)) * 3
    }

    private static func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        var quotient = value / divisor
        let remainder = value % divisor
        if remainder != 0 && ((remainder > 0) != (divisor > 0)) {
            quotient -= 1
        }
        return quotient
    }

    private static func floorMod(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + abs(divisor)
    }

    // MARK: - Collision

    func addGameObject_UpdateCollisionMap(_ tileX: Int, _ tileZ: Int, _ objectId: Int, _ unknown: Bool) {
        // Add game object to scene and update collision flags
        guard let objectDef = EntityDefinitions.getObjectDef(objectId) else { return }

        let worldX = tileX * 128
        let worldZ = tileZ * 128

        // Mark collision flags
        if tileX >= 0 && tileX < 96 && tileZ >= 0 && tileZ < 96 {
            collisionFlags[tileX][tileZ] |= 0x01  // Mark as blocked
        }

        // Create RSModel for this object
        let objModel = RSModel()
        // (geometry building would go here using objectDef data)

        scene.addModel(objModel)
    }

    func removeGameObject_CollisionFlags(_ objectId: Int, _ tileX: Int, _ tileZ: Int) {
        // Remove object and clear collision
        if tileX >= 0 && tileX < 96 && tileZ >= 0 && tileZ < 96 {
            collisionFlags[tileX][tileZ] &= ~0x01  // Clear blocked flag
        }
    }

    // MARK: - Utility

    func setTerrainData(_ data: [[[Int]]]) {
        // Server sends terrain data with elevation info
        self.landscapeData = data

        // Populate elevation cache from terrain data (opcode 25 format)
        // Each plane contains sector data with elevation values
        if data.count > 0 && data[0].count > 0 {
            for z in 0..<min(96, data[0].count) {
                for x in 0..<min(96, data[0][z].count) {
                    if z < tileElevationCache.count && x < tileElevationCache[z].count {
                        let elevation = data[0][z][x]
                        tileElevationCache[z][x] = elevation
                    }
                }
            }
        }
    }

    /// Helper to populate elevation from world state when terrain loads
    func populateElevation(from worldState: RSCWorldState) {
        // Called when new terrain data arrives from server
        // The server sends elevation deltas via opcode 25
        // This method can be extended to apply those deltas
    }
}
