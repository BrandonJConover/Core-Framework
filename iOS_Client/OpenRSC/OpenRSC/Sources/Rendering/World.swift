// Port of Client_Base/src/orsc/graphics/three/World.java
import Foundation

final class World {
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

    func generateLandscapeModel(plane: Int) {
        // Build ground mesh from tile data
        // Each tile is 128×128 game units

        let tileSize: Int32 = 128
        let meshSize = 8  // 8×8 tiles per model (64 tiles total)

        // Create a single landscape model for this plane
        let model = RSModel()

        // Build vertices and faces for all 8×8 tiles in this plane
        var faceCount = 0

        for tileY in 0..<8 {
            for tileX in 0..<8 {
                // Get tile data (simplified)
                let tileId = (tileY * 8 + tileX) % 25  // Use first 25 tile definitions

                // Get tile definition color
                let tileDef = EntityDefinitions.getTileDef(tileId)
                let color = tileDef?.colour ?? Int32(bitPattern: 0xFF808080)

                // Skip transparent tiles
                if color == Scene.TRANSPARENT {
                    continue
                }

                // Build quad for this tile with real elevation at each corner
                let baseX = Int32(tileX) * tileSize
                let baseZ = Int32(tileY) * tileSize

                // Get elevation at each corner of the tile quad
                let e0 = Int32(-getElevation(x: Int(baseX), z: Int(baseZ)) * 128)
                let e1 = Int32(-getElevation(x: Int(baseX + tileSize), z: Int(baseZ)) * 128)
                let e2 = Int32(-getElevation(x: Int(baseX + tileSize), z: Int(baseZ + tileSize)) * 128)
                let e3 = Int32(-getElevation(x: Int(baseX), z: Int(baseZ + tileSize)) * 128)

                // 4 vertices for quad with real elevation
                let v0 = model.insertVertex(x: baseX, y: e0, z: baseZ)
                let v1 = model.insertVertex(x: baseX + tileSize, y: e1, z: baseZ)
                let v2 = model.insertVertex(x: baseX + tileSize, y: e2, z: baseZ + tileSize)
                let v3 = model.insertVertex(x: baseX, y: e3, z: baseZ + tileSize)

                // Face
                let faceIndices: [Int32] = [v0, v1, v2, v3]
                model.insertFace(count: 4, indices: faceIndices, texFront: -1, texBack: -1)

                faceCount += 1
            }
        }

        // Add model to scene
        modelLandscapeGrid[plane] = model
        scene.addModel(model)
    }

    // MARK: - Elevation

    func getElevation(x: Int, z: Int) -> Int {
        // Bilinear interpolation of elevation at world position (x, z)
        // Terrain is 96x96 tiles, each tile is 128 game units
        let tileX = x / 128
        let tileZ = z / 128
        let fracX = (x % 128) / 128
        let fracZ = (z % 128) / 128

        guard tileX >= 0 && tileZ >= 0 && tileX < 95 && tileZ < 95 else {
            return 0  // Out of bounds
        }

        // Get the four corner elevation values
        let e00 = tileElevationCache[tileZ][tileX]
        let e10 = tileElevationCache[tileZ][tileX + 1]
        let e01 = tileElevationCache[tileZ + 1][tileX]
        let e11 = tileElevationCache[tileZ + 1][tileX + 1]

        // Bilinear interpolation
        // e(x,z) = e00*(1-x)*(1-z) + e10*x*(1-z) + e01*(1-x)*z + e11*x*z
        let one_x = 128 - fracX
        let one_z = 128 - fracZ

        let result = (e00 * one_x * one_z +
                      e10 * fracX * one_z +
                      e01 * one_x * fracZ +
                      e11 * fracX * fracZ) / (128 * 128)

        return result
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
