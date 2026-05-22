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

    /// Find a path from (startX, startZ) to (destX, destZ) in Java's
    /// region-local coordinate frame. RSCPacketHandler keeps player/entity
    /// positions in this frame after opcode 191 recenters the active region.
    /// Returns array of waypoints (excluding start), or empty if no path found
    func findPath(fromX: Int, fromZ: Int, toX: Int, toZ: Int, maxSteps: Int = 200) -> [(x: Int, z: Int)] {
        guard fromX != toX || fromZ != toZ else { return [] }

        var openSet = [PathNode]()
        var closedSet = Set<Int>()  // hash of x,z
        var cameFrom = [Int: (x: Int, z: Int)]()

        func hash(_ x: Int, _ z: Int) -> Int { x * 100000 + z }
        func heuristic(_ x: Int, _ z: Int) -> Int {
            abs(x - toX) + abs(z - toZ)  // Manhattan distance
        }

        openSet.append(PathNode(x: fromX, z: fromZ, g: 0, h: heuristic(fromX, fromZ)))

        let directions = [(0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)]

        var iterations = 0
        while !openSet.isEmpty && iterations < maxSteps * 10 {
            iterations += 1

            // Get node with lowest f score
            openSet.sort()
            let current = openSet.removeFirst()
            let ch = hash(current.x, current.z)

            if current.x == toX && current.z == toZ {
                // Reconstruct path
                var path = [(x: Int, z: Int)]()
                var cx = current.x; var cz = current.z
                while let prev = cameFrom[hash(cx, cz)] {
                    path.append((x: cx, z: cz))
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
                guard isStepAllowed(fromX: current.x, fromZ: current.z, toX: nx, toZ: nz) else { continue }

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

        // No path found. Java's world.findPath reports -1; callers decide
        // whether to suppress plain walking or use an action fallback.
        return []
    }

    private func isStepAllowed(fromX: Int, fromZ: Int, toX: Int, toZ: Int) -> Bool {
        guard isWalkable(localX: toX, localZ: toZ) else { return false }
        guard !isBlockedByObject(x: toX, z: toZ) else { return false }
        guard !isBlockedByWall(fromX: fromX, fromZ: fromZ, toX: toX, toZ: toZ) else { return false }

        let dx = toX - fromX
        let dz = toZ - fromZ
        if dx != 0 && dz != 0 {
            // Do not cut diagonally through a blocked corner. Java's collision
            // flags check both adjacent cardinal sides before allowing a
            // diagonal step; this approximates that using live object/wall
            // state retained from opcodes 48/91.
            if isBlockedByObject(x: fromX + dx, z: fromZ)
                || isBlockedByObject(x: fromX, z: fromZ + dz)
                || isBlockedByWall(fromX: fromX, fromZ: fromZ, toX: fromX + dx, toZ: fromZ)
                || isBlockedByWall(fromX: fromX, fromZ: fromZ, toX: fromX, toZ: fromZ + dz) {
                return false
            }
        }

        return true
    }

    private func isBlockedByObject(x: Int, z: Int) -> Bool {
        for object in worldState.gameObjects {
            guard let def = GameObjectDefinitions.get(object.objectId) else {
                if object.x == x && object.y == z { return true }
                continue
            }

            var width = max(1, def.width)
            var height = max(1, def.height)
            if object.direction != 0 && object.direction != 4 {
                swap(&width, &height)
            }

            if x >= object.x && x < object.x + width
                && z >= object.y && z < object.y + height {
                return true
            }
        }
        return false
    }

    private func isBlockedByWall(fromX: Int, fromZ: Int, toX: Int, toZ: Int) -> Bool {
        let dx = toX - fromX
        let dz = toZ - fromZ
        guard abs(dx) <= 1, abs(dz) <= 1, dx != 0 || dz != 0 else { return false }

        for wall in worldState.wallObjects {
            switch wall.direction {
            case 0:
                // Horizontal boundary on the north side of (x,z): blocks
                // movement between (x,z-1) and (x,z).
                if ((fromX == wall.x && fromZ == wall.y - 1 && toX == wall.x && toZ == wall.y)
                    || (fromX == wall.x && fromZ == wall.y && toX == wall.x && toZ == wall.y - 1)) {
                    return true
                }
            case 1:
                // Vertical boundary on the west/east tile edge used by Java's
                // walkToWall approach: blocks movement between (x-1,z) and
                // (x,z).
                if ((fromX == wall.x - 1 && fromZ == wall.y && toX == wall.x && toZ == wall.y)
                    || (fromX == wall.x && fromZ == wall.y && toX == wall.x - 1 && toZ == wall.y)) {
                    return true
                }
            default:
                // Diagonal/corner boundary objects occupy the tile for our
                // coarse native pathfinder.
                if toX == wall.x && toZ == wall.y { return true }
            }
        }
        return false
    }

    /// Check if a tile is walkable using landscape data. The pathfinder walks
    /// region-local tiles, while LandscapeLoader indexes true archive/world
    /// coordinates, so convert through RSCWorldState's absolute helpers here.
    private func isWalkable(localX: Int, localZ: Int) -> Bool {
        guard landscapeLoader.isLoaded else { return true }  // Allow all if no data

        let worldX = worldState.absoluteWorldX(localX)
        let worldZ = worldState.absoluteWorldZ(localZ)
        guard let tile = landscapeLoader.getTile(worldX: worldX, worldZ: worldZ, plane: 0) else {
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
