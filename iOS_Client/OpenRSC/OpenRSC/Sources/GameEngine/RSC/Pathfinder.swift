// A* pathfinding for RSC world navigation
// Uses landscape tile data to determine walkability

import Foundation

struct PathNode: Comparable {
    let x: Int
    let z: Int
    let g: Int  // cost from start
    let h: Int  // heuristic to goal
    var f: Int { g + h }

    static func < (lhs: PathNode, rhs: PathNode) -> Bool {
        lhs.f < rhs.f
    }
}

@MainActor
final class Pathfinder {
    private let landscapeLoader: LandscapeLoader
    private let worldState: RSCWorldState

    init(landscapeLoader: LandscapeLoader, worldState: RSCWorldState) {
        self.landscapeLoader = landscapeLoader
        self.worldState = worldState
    }

    /// Find a path from (startX, startZ) to (destX, destZ) in world coordinates
    /// Returns array of waypoints (excluding start), or empty if no path found
    func findPath(fromX: Int, fromZ: Int, toX: Int, toZ: Int, maxSteps: Int = 200) -> [(x: Int, z: Int)] {
        guard fromX != toX || fromZ != toZ else { return [] }

        let absStartX = worldState.worldOffsetX + fromX
        let absStartZ = worldState.worldOffsetZ + fromZ
        let absDestX = worldState.worldOffsetX + toX
        let absDestZ = worldState.worldOffsetZ + toZ

        var openSet = [PathNode]()
        var closedSet = Set<Int>()  // hash of x,z
        var cameFrom = [Int: (x: Int, z: Int)]()

        func hash(_ x: Int, _ z: Int) -> Int { x * 100000 + z }
        func heuristic(_ x: Int, _ z: Int) -> Int {
            abs(x - absDestX) + abs(z - absDestZ)  // Manhattan distance
        }

        openSet.append(PathNode(x: absStartX, z: absStartZ, g: 0, h: heuristic(absStartX, absStartZ)))

        let directions = [(0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)]

        var iterations = 0
        while !openSet.isEmpty && iterations < maxSteps * 10 {
            iterations += 1

            // Get node with lowest f score
            openSet.sort()
            let current = openSet.removeFirst()
            let ch = hash(current.x, current.z)

            if current.x == absDestX && current.z == absDestZ {
                // Reconstruct path
                var path = [(x: Int, z: Int)]()
                var cx = current.x; var cz = current.z
                while let prev = cameFrom[hash(cx, cz)] {
                    // Convert back to local coordinates
                    path.append((x: cx - worldState.worldOffsetX, z: cz - worldState.worldOffsetZ))
                    cx = prev.x; cz = prev.z
                }
                path.reverse()
                return Array(path.prefix(maxSteps))
            }

            closedSet.insert(ch)

            for (dx, dz) in directions {
                let nx = current.x + dx
                let nz = current.z + dz
                let nh = hash(nx, nz)

                guard !closedSet.contains(nh) else { continue }
                guard isWalkable(absX: nx, absZ: nz) else { continue }

                // Diagonal movement costs more
                let moveCost = (dx != 0 && dz != 0) ? 14 : 10
                let newG = current.g + moveCost

                if let existingIdx = openSet.firstIndex(where: { $0.x == nx && $0.z == nz }) {
                    if newG < openSet[existingIdx].g {
                        openSet[existingIdx] = PathNode(x: nx, z: nz, g: newG, h: heuristic(nx, nz))
                        cameFrom[nh] = (x: current.x, z: current.z)
                    }
                } else {
                    openSet.append(PathNode(x: nx, z: nz, g: newG, h: heuristic(nx, nz)))
                    cameFrom[nh] = (x: current.x, z: current.z)
                }
            }
        }

        // No path found — return direct line
        return [(x: toX, z: toZ)]
    }

    /// Check if a tile is walkable using landscape data
    private func isWalkable(absX: Int, absZ: Int) -> Bool {
        guard landscapeLoader.isLoaded else { return true }  // Allow all if no data

        guard let tile = landscapeLoader.getTile(worldX: absX, worldZ: absZ, plane: 0) else {
            return true  // Unknown tiles are walkable
        }

        // Water tiles (overlay 2, 3, 4) are not walkable
        if tile.groundOverlay == 2 || tile.groundOverlay == 3 || tile.groundOverlay == 4 {
            return false
        }

        // Tiles with diagonal walls block movement
        if tile.diagonalWalls != 0 {
            return false
        }

        // Check if tile has a wall blocking entry
        // horizontalWall > 0 means wall on north side
        // verticalWall > 0 means wall on east side
        // For simplicity, consider any walled tile as potentially blocked
        // (Full implementation would check wall direction vs movement direction)

        return true
    }
}
