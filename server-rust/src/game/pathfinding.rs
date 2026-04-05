//! Pathfinding system for NPC and player movement.
//! Implements A* pathfinding with collision detection.

use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap, HashSet};

use super::entity::Position;

/// Maximum path length.
const MAX_PATH_LENGTH: usize = 100;

/// Direction offsets for 8-directional movement.
const DIRECTIONS: [(i16, i16); 8] = [
    (0, -1),  // North
    (1, -1),  // Northeast
    (1, 0),   // East
    (1, 1),   // Southeast
    (0, 1),   // South
    (-1, 1),  // Southwest
    (-1, 0),  // West
    (-1, -1), // Northwest
];

/// Cardinal directions only (4-directional).
const CARDINAL_DIRECTIONS: [(i16, i16); 4] = [
    (0, -1), // North
    (1, 0),  // East
    (0, 1),  // South
    (-1, 0), // West
];

/// A node in the pathfinding graph.
#[derive(Debug, Clone, Eq, PartialEq)]
struct PathNode {
    position: Position,
    g_cost: u32, // Cost from start
    h_cost: u32, // Heuristic cost to end
}

impl PathNode {
    fn f_cost(&self) -> u32 {
        self.g_cost + self.h_cost
    }
}

impl Ord for PathNode {
    fn cmp(&self, other: &Self) -> Ordering {
        other.f_cost().cmp(&self.f_cost())
    }
}

impl PartialOrd for PathNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Result of a pathfinding query.
#[derive(Debug, Clone)]
pub enum PathResult {
    /// Path found successfully.
    Found(Vec<Position>),
    /// No path exists to destination.
    NoPath,
    /// Path is too long.
    TooFar,
    /// Already at destination.
    AlreadyThere,
}

/// Collision data for the world.
pub trait CollisionMap {
    /// Check if a tile is walkable.
    fn is_walkable(&self, x: i32, y: i32, plane: i32) -> bool;

    /// Check if can walk from one tile to adjacent tile.
    fn can_traverse(&self, from: Position, dx: i16, dy: i16) -> bool;
}

/// Simple collision map for testing.
#[derive(Debug, Default)]
pub struct SimpleCollisionMap {
    /// Blocked tiles.
    blocked: HashSet<(i32, i32, i32)>,
}

impl SimpleCollisionMap {
    /// Create a new empty collision map.
    pub fn new() -> Self {
        Self::default()
    }

    /// Block a tile.
    pub fn block(&mut self, x: i32, y: i32, plane: i32) {
        self.blocked.insert((x, y, plane));
    }

    /// Unblock a tile.
    pub fn unblock(&mut self, x: i32, y: i32, plane: i32) {
        self.blocked.remove(&(x, y, plane));
    }
}

impl CollisionMap for SimpleCollisionMap {
    fn is_walkable(&self, x: i32, y: i32, plane: i32) -> bool {
        !self.blocked.contains(&(x, y, plane))
    }

    fn can_traverse(&self, from: Position, dx: i16, dy: i16) -> bool {
        let to_x = from.x + dx as i32;
        let to_y = from.y + dy as i32;

        // Check destination is walkable
        if !self.is_walkable(to_x, to_y, from.plane) {
            return false;
        }

        // For diagonal movement, check corners
        if dx != 0 && dy != 0 {
            let side1_x = from.x + dx as i32;
            let side1_y = from.y;
            let side2_x = from.x;
            let side2_y = from.y + dy as i32;

            if !self.is_walkable(side1_x, side1_y, from.plane)
                || !self.is_walkable(side2_x, side2_y, from.plane)
            {
                return false;
            }
        }

        true
    }
}

/// Calculate heuristic distance (Chebyshev for 8-directional).
fn heuristic(a: Position, b: Position) -> u32 {
    let dx = (a.x as i32 - b.x as i32).unsigned_abs();
    let dy = (a.y as i32 - b.y as i32).unsigned_abs();
    dx.max(dy)
}

/// Calculate Manhattan distance.
fn manhattan_distance(a: Position, b: Position) -> u32 {
    let dx = (a.x as i32 - b.x as i32).unsigned_abs();
    let dy = (a.y as i32 - b.y as i32).unsigned_abs();
    dx + dy
}

/// Find a path using A* algorithm.
pub fn find_path<C: CollisionMap>(
    start: Position,
    end: Position,
    collision: &C,
    allow_diagonal: bool,
) -> PathResult {
    // Check if already at destination
    if start.x == end.x && start.y == end.y && start.plane == end.plane {
        return PathResult::AlreadyThere;
    }

    // Check if destination is walkable
    if !collision.is_walkable(end.x, end.y, end.plane) {
        return PathResult::NoPath;
    }

    // Check if too far
    if heuristic(start, end) > MAX_PATH_LENGTH as u32 {
        return PathResult::TooFar;
    }

    let directions = if allow_diagonal {
        &DIRECTIONS[..]
    } else {
        &CARDINAL_DIRECTIONS[..]
    };

    let mut open_set = BinaryHeap::new();
    let mut came_from: HashMap<(i32, i32), Position> = HashMap::new();
    let mut g_scores: HashMap<(i32, i32), u32> = HashMap::new();
    let mut closed_set: HashSet<(i32, i32)> = HashSet::new();

    open_set.push(PathNode {
        position: start,
        g_cost: 0,
        h_cost: heuristic(start, end),
    });
    g_scores.insert((start.x, start.y), 0);

    while let Some(current) = open_set.pop() {
        let pos = current.position;

        // Check if reached destination
        if pos.x == end.x && pos.y == end.y {
            // Reconstruct path
            let mut path = Vec::new();
            let mut current_pos = (pos.x, pos.y);

            while current_pos != (start.x, start.y) {
                path.push(Position {
                    x: current_pos.0,
                    y: current_pos.1,
                    plane: start.plane,
                });
                if let Some(prev) = came_from.get(&current_pos) {
                    current_pos = (prev.x, prev.y);
                } else {
                    break;
                }
            }

            path.reverse();
            return PathResult::Found(path);
        }

        if closed_set.contains(&(pos.x, pos.y)) {
            continue;
        }
        closed_set.insert((pos.x, pos.y));

        // Explore neighbors
        for &(dx, dy) in directions {
            if !collision.can_traverse(pos, dx, dy) {
                continue;
            }

            let neighbor_x = pos.x + dx as i32;
            let neighbor_y = pos.y + dy as i32;
            let neighbor_key = (neighbor_x, neighbor_y);

            if closed_set.contains(&neighbor_key) {
                continue;
            }

            // Diagonal moves cost more
            let move_cost = if dx != 0 && dy != 0 { 14 } else { 10 };
            let tentative_g = current.g_cost + move_cost;

            if tentative_g < *g_scores.get(&neighbor_key).unwrap_or(&u32::MAX) {
                let neighbor_pos = Position {
                    x: neighbor_x,
                    y: neighbor_y,
                    plane: pos.plane,
                };

                came_from.insert(neighbor_key, pos);
                g_scores.insert(neighbor_key, tentative_g);

                open_set.push(PathNode {
                    position: neighbor_pos,
                    g_cost: tentative_g,
                    h_cost: heuristic(neighbor_pos, end),
                });
            }
        }
    }

    PathResult::NoPath
}

/// Find path to adjacent tile of target (for attacking, trading, etc.).
pub fn find_path_to_adjacent<C: CollisionMap>(
    start: Position,
    target: Position,
    collision: &C,
) -> PathResult {
    // Check if already adjacent
    let dx = (start.x as i32 - target.x as i32).abs();
    let dy = (start.y as i32 - target.y as i32).abs();
    if dx <= 1 && dy <= 1 && (dx + dy) > 0 {
        return PathResult::AlreadyThere;
    }

    // Find walkable tile adjacent to target
    for &(dx, dy) in &DIRECTIONS {
        let adj_x = target.x + dx as i32;
        let adj_y = target.y + dy as i32;

        if collision.is_walkable(adj_x, adj_y, target.plane) {
            let adj_pos = Position {
                x: adj_x,
                y: adj_y,
                plane: target.plane,
            };

            if let PathResult::Found(path) = find_path(start, adj_pos, collision, true) {
                return PathResult::Found(path);
            }
        }
    }

    PathResult::NoPath
}

/// Walking queue for player movement.
#[derive(Debug, Clone, Default)]
pub struct WalkingQueue {
    /// Waypoints to walk to.
    waypoints: Vec<Position>,
    /// Current waypoint index.
    current_index: usize,
    /// Whether running.
    running: bool,
}

impl WalkingQueue {
    /// Create a new walking queue.
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the path to walk.
    pub fn set_path(&mut self, path: Vec<Position>) {
        self.waypoints = path;
        self.current_index = 0;
    }

    /// Clear the walking queue.
    pub fn clear(&mut self) {
        self.waypoints.clear();
        self.current_index = 0;
    }

    /// Check if queue is empty.
    pub fn is_empty(&self) -> bool {
        self.current_index >= self.waypoints.len()
    }

    /// Get next waypoint to walk to.
    pub fn next(&mut self) -> Option<Position> {
        if self.is_empty() {
            return None;
        }

        let pos = self.waypoints[self.current_index];
        self.current_index += 1;
        Some(pos)
    }

    /// Get next movement, possibly two if running.
    pub fn next_movement(&mut self) -> Vec<Position> {
        let mut movements = Vec::new();

        if let Some(pos) = self.next() {
            movements.push(pos);
        }

        if self.running {
            if let Some(pos) = self.next() {
                movements.push(pos);
            }
        }

        movements
    }

    /// Set running state.
    pub fn set_running(&mut self, running: bool) {
        self.running = running;
    }

    /// Check if running.
    pub fn is_running(&self) -> bool {
        self.running
    }

    /// Get remaining waypoints.
    pub fn remaining(&self) -> usize {
        if self.current_index >= self.waypoints.len() {
            0
        } else {
            self.waypoints.len() - self.current_index
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_path() {
        let collision = SimpleCollisionMap::new();

        let start = Position { x: 0, y: 0, plane: 0 };
        let end = Position { x: 5, y: 5, plane: 0 };

        if let PathResult::Found(path) = find_path(start, end, &collision, true) {
            assert!(!path.is_empty());
            assert_eq!(path.last().unwrap().x, end.x);
            assert_eq!(path.last().unwrap().y, end.y);
        } else {
            panic!("Expected to find path");
        }
    }

    #[test]
    fn test_blocked_path() {
        let mut collision = SimpleCollisionMap::new();

        // Create a wall blocking the path
        for y in 0..10 {
            collision.block(5, y, 0);
        }

        let start = Position { x: 0, y: 5, plane: 0 };
        let end = Position { x: 10, y: 5, plane: 0 };

        // Should still find a path around
        if let PathResult::Found(path) = find_path(start, end, &collision, true) {
            // Path should go around the wall
            for pos in &path {
                assert!(collision.is_walkable(pos.x, pos.y, pos.plane));
            }
        } else {
            panic!("Should find path around wall");
        }
    }

    #[test]
    fn test_walking_queue() {
        let mut queue = WalkingQueue::new();

        let path = vec![
            Position { x: 1, y: 0, plane: 0 },
            Position { x: 2, y: 0, plane: 0 },
            Position { x: 3, y: 0, plane: 0 },
        ];

        queue.set_path(path);

        assert!(!queue.is_empty());
        assert_eq!(queue.remaining(), 3);

        let next = queue.next().unwrap();
        assert_eq!(next.x, 1);

        // Test running (gets 2 waypoints)
        queue.set_running(true);
        let movements = queue.next_movement();
        assert_eq!(movements.len(), 1); // Only 1 left
    }
}
