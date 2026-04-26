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
        // Synthetic terrain elevation for visual testing
        var elevation = [[Int]](repeating: [Int](repeating: 0, count: 96), count: 96)
        for z in 0..<96 {
            for x in 0..<96 {
                elevation[z][x] = Int((sin(Double(x) * 0.3) + cos(Double(z) * 0.2)) * 20)
            }
        }
        self.tileElevationCache = elevation

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
        let viewSize = 32
        let model = RSModel(vertexCount: Int32(viewSize * viewSize * 4 + 100), faceCount: Int32(viewSize * viewSize + 100))

        // Compute the absolute sector coordinates from the current position
        let absBaseX = currentBaseX  // These should be in sector-space
        let absBaseZ = currentBaseZ

        var faceCount = 0
        let half = viewSize / 2

        for tileZ in (-half)..<half {
            for tileX in (-half)..<half {
                let worldTX = absBaseX + tileX
                let worldTZ = absBaseZ + tileZ

                var color: Int32
                var elev: Int32 = 0

                if let loader = landscapeLoader, loader.isLoaded,
                   let tile = loader.getTile(worldX: worldTX, worldZ: worldTZ, plane: plane) {
                    color = LandscapeLoader.tileColor(overlay: tile.groundOverlay, texture: tile.groundTexture, elevation: tile.groundElevation)
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
                let y = -elev * 3  // Scale elevation

                // 4 vertices for quad — use direct array access (skip duplicate search for speed)
                let vi = model.vertHead
                guard vi + 3 < model.vertexCount2 else { continue }
                model.vertX[Int(vi)] = baseX;     model.vertY[Int(vi)] = y;     model.vertZ[Int(vi)] = baseZ
                model.vertX[Int(vi+1)] = baseX + tileSize; model.vertY[Int(vi+1)] = y; model.vertZ[Int(vi+1)] = baseZ
                model.vertX[Int(vi+2)] = baseX + tileSize; model.vertY[Int(vi+2)] = y; model.vertZ[Int(vi+2)] = baseZ + tileSize
                model.vertX[Int(vi+3)] = baseX;   model.vertY[Int(vi+3)] = y;   model.vertZ[Int(vi+3)] = baseZ + tileSize
                model.vertHead += 4
                let v0 = vi; let v1 = vi + 1; let v2 = vi + 2; let v3 = vi + 3

                // Face with color as front texture
                let faceIndices: [Int32] = [v0, v1, v2, v3]
                model.insertFace(count: 4, indices: faceIndices, texFront: color, texBack: -1)

                faceCount += 1
            }
        }

        print("[World] Generated landscape: \(faceCount) faces, \(model.vertHead) verts")

        // Force full bounding box recalculation (m_Yb=2 sets bounds to ±9999999)
        model.m_Yb = 2

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
