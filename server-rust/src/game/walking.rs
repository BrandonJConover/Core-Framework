//! Walking queue and collision system for player/NPC movement.
//! Processes queued movement steps with per-tile collision checking.

use std::collections::{HashMap, VecDeque};

use super::entity::{Direction, Position};
use super::game_object::ObjectType;
use super::region::ObjectSpawn;

// ---------------------------------------------------------------------------
// Collision flags (matching Java CollisionFlag values)
// ---------------------------------------------------------------------------

/// Wall on the north edge of a tile.
pub const WALL_NORTH: u32 = 0x1;
/// Wall on the east edge of a tile.
pub const WALL_EAST: u32 = 0x2;
/// Wall on the south edge of a tile.
pub const WALL_SOUTH: u32 = 0x4;
/// Wall on the west edge of a tile.
pub const WALL_WEST: u32 = 0x8;
/// Diagonal wall blocking north-east passage.
pub const DIAGONAL_WALL_NEAST: u32 = 0x10;
/// Diagonal wall blocking south-east passage.
pub const DIAGONAL_WALL_SEAST: u32 = 0x20;
/// Diagonal wall blocking south-west passage.
pub const DIAGONAL_WALL_SWEST: u32 = 0x40;
/// Diagonal wall blocking north-west passage.
pub const DIAGONAL_WALL_NWEST: u32 = 0x80;
/// Full block variant A (large objects, solid walls).
pub const FULL_BLOCK_A: u32 = 0x200000;
/// Full block variant B (medium objects).
pub const FULL_BLOCK_B: u32 = 0x40000;

/// Mask combining both full-block variants.
pub const FULL_BLOCK: u32 = FULL_BLOCK_A | FULL_BLOCK_B;

// ---------------------------------------------------------------------------
// CollisionMap
// ---------------------------------------------------------------------------

/// Tile-flag based collision map keyed by (x, y, plane).
#[derive(Debug, Clone, Default)]
pub struct CollisionMap {
    flags: HashMap<(i32, i32, i32), u32>,
}

impl CollisionMap {
    /// Create an empty collision map.
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the collision flags for a tile, replacing any previous value.
    pub fn set_flags(&mut self, x: i32, y: i32, plane: i32, flags: u32) {
        self.flags.insert((x, y, plane), flags);
    }

    /// Add (bitwise-OR) collision flags to a tile.
    pub fn add_flags(&mut self, x: i32, y: i32, plane: i32, flags: u32) {
        let entry = self.flags.entry((x, y, plane)).or_insert(0);
        *entry |= flags;
    }

    /// Mark a tile as fully blocked for movement.
    pub fn block_tile(&mut self, pos: Position) {
        self.add_flags(pos.x, pos.y, pos.plane, FULL_BLOCK_A);
    }

    /// Get the raw collision flags for a tile (0 if none stored).
    pub fn get_flags(&self, x: i32, y: i32, plane: i32) -> u32 {
        self.flags.get(&(x, y, plane)).copied().unwrap_or(0)
    }

    /// Apply Java/OpenRSC object-location collision for a single loaded loc.
    ///
    /// This first slice mirrors Java boundary registration. Scenery collision
    /// needs object definitions for width/height/type, so it remains a later
    /// data-loader step instead of guessing from loc coordinates alone.
    pub fn apply_java_object_spawn(&mut self, spawn: &ObjectSpawn) {
        if spawn.object_type != ObjectType::Boundary {
            return;
        }

        self.apply_java_boundary(spawn.position, spawn.direction);
    }

    /// Apply Java/OpenRSC object-location collision for a batch of loaded locs.
    pub fn apply_java_object_spawns<'a>(
        &mut self,
        spawns: impl IntoIterator<Item = &'a ObjectSpawn>,
    ) {
        for spawn in spawns {
            self.apply_java_object_spawn(spawn);
        }
    }

    /// Apply boundary-wall collision using Java `World.registerGameObject`
    /// direction semantics for boundary objects.
    pub fn apply_java_boundary(&mut self, position: Position, direction: u8) {
        match direction {
            0 => {
                self.add_flags(position.x, position.y, position.plane, WALL_NORTH);
                self.add_flags(position.x, position.y - 1, position.plane, WALL_SOUTH);
            }
            1 => {
                self.add_flags(position.x, position.y, position.plane, WALL_EAST);
                self.add_flags(position.x - 1, position.y, position.plane, WALL_WEST);
            }
            2 => {
                self.add_flags(position.x, position.y, position.plane, FULL_BLOCK_A);
            }
            3 => {
                self.add_flags(position.x, position.y, position.plane, FULL_BLOCK_B);
            }
            _ => {}
        }
    }

    /// Returns `true` when the tile is fully blocked.
    pub fn is_blocked(&self, pos: Position) -> bool {
        self.get_flags(pos.x, pos.y, pos.plane) & FULL_BLOCK != 0
    }

    /// Check whether movement from `from` to `to` is legal.
    ///
    /// The two positions must be at most 1 tile apart on each axis and share
    /// the same plane. Diagonal movement is only permitted when both
    /// intermediate cardinal tiles are passable.
    pub fn can_move(&self, from: Position, to: Position) -> bool {
        if from.plane != to.plane {
            return false;
        }

        let dx = to.x - from.x;
        let dy = to.y - from.y;

        // Staying in place is always allowed.
        if dx == 0 && dy == 0 {
            return true;
        }

        // Only adjacent (1-tile) moves are handled here.
        if dx.abs() > 1 || dy.abs() > 1 {
            return false;
        }

        // Destination must not be fully blocked.
        if self.is_blocked(to) {
            return false;
        }

        let from_flags = self.get_flags(from.x, from.y, from.plane);
        let to_flags = self.get_flags(to.x, to.y, to.plane);

        // --- Cardinal movement -----------------------------------------------
        if dx == 0 || dy == 0 {
            return self.can_move_cardinal(from_flags, to_flags, dx, dy);
        }

        // --- Diagonal movement ------------------------------------------------
        // Both intermediate cardinal tiles must be passable.
        let mid_a = Position::with_plane(from.x + dx, from.y, from.plane);
        let mid_b = Position::with_plane(from.x, from.y + dy, from.plane);

        if !self.can_move(from, mid_a) || !self.can_move(from, mid_b) {
            return false;
        }
        if !self.can_move(mid_a, to) || !self.can_move(mid_b, to) {
            return false;
        }

        // Check diagonal wall flags on the source tile.
        let diag_flag = match (dx, dy) {
            (1, -1) => DIAGONAL_WALL_NEAST,
            (1, 1) => DIAGONAL_WALL_SEAST,
            (-1, 1) => DIAGONAL_WALL_SWEST,
            (-1, -1) => DIAGONAL_WALL_NWEST,
            _ => 0,
        };
        from_flags & diag_flag == 0
    }

    /// Helper: check a single cardinal step.
    fn can_move_cardinal(&self, from_flags: u32, to_flags: u32, dx: i32, dy: i32) -> bool {
        match (dx, dy) {
            (0, -1) => from_flags & WALL_NORTH == 0 && to_flags & WALL_SOUTH == 0,
            (0, 1) => from_flags & WALL_SOUTH == 0 && to_flags & WALL_NORTH == 0,
            (1, 0) => from_flags & WALL_EAST == 0 && to_flags & WALL_WEST == 0,
            (-1, 0) => from_flags & WALL_WEST == 0 && to_flags & WALL_EAST == 0,
            _ => true,
        }
    }
}

impl crate::game::pathfinding::CollisionMap for CollisionMap {
    fn is_walkable(&self, x: i32, y: i32, plane: i32) -> bool {
        !self.is_blocked(Position::with_plane(x, y, plane))
    }

    fn can_traverse(&self, from: Position, dx: i16, dy: i16) -> bool {
        let to = Position::with_plane(from.x + dx as i32, from.y + dy as i32, from.plane);
        self.can_move(from, to)
    }
}

// ---------------------------------------------------------------------------
// WalkingQueue
// ---------------------------------------------------------------------------

/// Manages queued movement steps for a player or NPC.
///
/// Each game tick the owner calls [`process_tick`] which returns up to one
/// position (walking) or two positions (running).
#[derive(Debug, Clone, Default)]
pub struct WalkingQueue {
    /// Queued destination positions the entity will walk through in order.
    pub waypoints: VecDeque<Position>,
    /// When `true` the entity takes two steps per tick.
    pub is_running: bool,
}

impl WalkingQueue {
    /// Create a new, empty walking queue.
    pub fn new() -> Self {
        Self::default()
    }

    /// Replace the current queue with new waypoints (called on a new walk
    /// command from the client).
    pub fn set_waypoints(&mut self, waypoints: Vec<Position>) {
        self.waypoints = VecDeque::from(waypoints);
    }

    /// Add a single waypoint to the back of the queue.
    pub fn add_waypoint(&mut self, pos: Position) {
        self.waypoints.push_back(pos);
    }

    /// Empty the queue entirely.
    pub fn clear(&mut self) {
        self.waypoints.clear();
    }

    /// Returns `true` when there are no remaining waypoints.
    pub fn finished(&self) -> bool {
        self.waypoints.is_empty()
    }

    /// Take one step from `current` toward the next waypoint.
    ///
    /// Returns the new position after moving one tile, or `None` if the queue
    /// is empty. The step is clamped to a single tile in each axis so the
    /// returned position is always adjacent to `current`.
    pub fn process_step(&mut self, current: Position) -> Option<Position> {
        let target = *self.waypoints.front()?;

        let dx = (target.x - current.x).clamp(-1, 1);
        let dy = (target.y - current.y).clamp(-1, 1);

        if dx == 0 && dy == 0 {
            // Reached this waypoint; remove it and try the next one.
            self.waypoints.pop_front();
            return self.process_step(current);
        }

        let next = Position::with_plane(current.x + dx, current.y + dy, current.plane);

        // If we have now reached the waypoint, consume it.
        if next == target {
            self.waypoints.pop_front();
        }

        Some(next)
    }

    /// Process a full tick of movement.
    ///
    /// Returns a vec of 0, 1, or 2 positions the entity should move through
    /// this tick, validated against the provided [`CollisionMap`].
    pub fn process_tick(&mut self, current: Position, collision: &CollisionMap) -> Vec<Position> {
        let mut moves = Vec::with_capacity(2);
        let mut pos = current;

        // First step (walk).
        if let Some(next) = self.process_step(pos) {
            if collision.can_move(pos, next) {
                moves.push(next);
                pos = next;
            } else {
                self.clear();
                return moves;
            }
        }

        // Second step (run).
        if self.is_running {
            if let Some(next) = self.process_step(pos) {
                if collision.can_move(pos, next) {
                    moves.push(next);
                } else {
                    self.clear();
                }
            }
        }

        moves
    }
}

/// Derive the [`Direction`] an entity should face after moving.
pub fn direction_from_movement(from: Position, to: Position) -> Direction {
    Direction::from_offset(to.x - from.x, to.y - from.y)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // -- CollisionMap ---------------------------------------------------------

    #[test]
    fn test_empty_map_allows_movement() {
        let map = CollisionMap::new();
        let a = Position::new(10, 10);
        let b = Position::new(11, 10);
        assert!(map.can_move(a, b));
    }

    #[test]
    fn test_full_block_prevents_entry() {
        let mut map = CollisionMap::new();
        map.set_flags(5, 5, 0, FULL_BLOCK_A);
        let blocked = Position::new(5, 5);
        assert!(map.is_blocked(blocked));
        assert!(!map.can_move(Position::new(4, 5), blocked));
    }

    #[test]
    fn block_tile_marks_destination_unwalkable() {
        let mut map = CollisionMap::new();
        let blocked = Position::new(5, 5);

        map.block_tile(blocked);

        assert!(map.is_blocked(blocked));
        assert!(!map.can_move(Position::new(4, 5), blocked));
    }

    #[test]
    fn test_wall_north_blocks_north() {
        let mut map = CollisionMap::new();
        map.add_flags(3, 3, 0, WALL_NORTH);
        assert!(!map.can_move(Position::new(3, 3), Position::new(3, 2)));
        // East should still be fine.
        assert!(map.can_move(Position::new(3, 3), Position::new(4, 3)));
    }

    #[test]
    fn test_wall_pair_blocks_from_other_side() {
        let mut map = CollisionMap::new();
        // Wall on southern edge of (3,2) blocks entry from south.
        map.add_flags(3, 2, 0, WALL_SOUTH);
        assert!(!map.can_move(Position::new(3, 3), Position::new(3, 2)));
    }

    #[test]
    fn test_diagonal_requires_both_cardinals() {
        let mut map = CollisionMap::new();
        // Block the tile to the east so diagonal NE is impossible.
        map.set_flags(6, 5, 0, FULL_BLOCK_B);
        assert!(!map.can_move(Position::new(5, 5), Position::new(6, 4)));
    }

    #[test]
    fn test_diagonal_wall_flag_blocks() {
        let mut map = CollisionMap::new();
        map.add_flags(5, 5, 0, DIAGONAL_WALL_NEAST);
        assert!(!map.can_move(Position::new(5, 5), Position::new(6, 4)));
        // Other diagonals from same tile should be fine.
        assert!(map.can_move(Position::new(5, 5), Position::new(4, 4)));
    }

    #[test]
    fn test_cross_plane_blocked() {
        let map = CollisionMap::new();
        let a = Position::with_plane(5, 5, 0);
        let b = Position::with_plane(6, 5, 1);
        assert!(!map.can_move(a, b));
    }

    #[test]
    fn java_boundary_spawn_direction_zero_blocks_north_edge() {
        let mut map = CollisionMap::new();
        let spawn = ObjectSpawn::boundary(1, Position::new(10, 10), 0);

        map.apply_java_object_spawn(&spawn);

        assert_eq!(map.get_flags(10, 10, 0) & WALL_NORTH, WALL_NORTH);
        assert_eq!(map.get_flags(10, 9, 0) & WALL_SOUTH, WALL_SOUTH);
        assert!(!map.can_move(Position::new(10, 10), Position::new(10, 9)));
        assert!(!map.can_move(Position::new(10, 9), Position::new(10, 10)));
        assert!(map.can_move(Position::new(10, 10), Position::new(11, 10)));
    }

    #[test]
    fn java_boundary_spawn_direction_one_blocks_east_edge_like_java() {
        let mut map = CollisionMap::new();
        let spawn = ObjectSpawn::boundary(1, Position::new(10, 10), 1);

        map.apply_java_object_spawn(&spawn);

        assert_eq!(map.get_flags(10, 10, 0) & WALL_EAST, WALL_EAST);
        assert_eq!(map.get_flags(9, 10, 0) & WALL_WEST, WALL_WEST);
        assert!(!map.can_move(Position::new(10, 10), Position::new(11, 10)));
        assert!(map.can_move(Position::new(10, 10), Position::new(10, 11)));
    }

    #[test]
    fn java_boundary_spawn_diagonal_directions_apply_full_blocks() {
        let mut map = CollisionMap::new();
        map.apply_java_object_spawn(&ObjectSpawn::boundary(1, Position::new(10, 10), 2));
        map.apply_java_object_spawn(&ObjectSpawn::boundary(1, Position::new(12, 12), 3));

        assert!(map.is_blocked(Position::new(10, 10)));
        assert!(map.is_blocked(Position::new(12, 12)));
        assert!(!map.can_move(Position::new(9, 10), Position::new(10, 10)));
        assert!(!map.can_move(Position::new(11, 12), Position::new(12, 12)));
    }

    #[test]
    fn java_object_spawn_collision_ignores_scenery_until_defs_are_loaded() {
        let mut map = CollisionMap::new();
        map.apply_java_object_spawns([ObjectSpawn::scenery(70, Position::new(10, 10), 0)].iter());

        assert_eq!(map.get_flags(10, 10, 0), 0);
        assert!(map.can_move(Position::new(9, 10), Position::new(10, 10)));
    }

    #[test]
    fn walking_collision_map_feeds_pathfinding_trait() {
        let mut map = CollisionMap::new();
        map.apply_java_boundary(Position::new(10, 10), 0);

        let collision: &dyn crate::game::pathfinding::CollisionMap = &map;

        assert!(collision.is_walkable(10, 10, 0));
        assert!(!collision.can_traverse(Position::new(10, 10), 0, -1));
        assert!(collision.can_traverse(Position::new(10, 10), 1, 0));
    }

    // -- WalkingQueue ---------------------------------------------------------

    #[test]
    fn test_queue_walk_straight_line() {
        let mut q = WalkingQueue::new();
        q.set_waypoints(vec![Position::new(3, 0)]);

        let map = CollisionMap::new();
        let mut pos = Position::new(0, 0);

        for _ in 0..3 {
            let moves = q.process_tick(pos, &map);
            assert_eq!(moves.len(), 1);
            pos = *moves.last().unwrap();
        }

        assert_eq!(pos, Position::new(3, 0));
        assert!(q.finished());
    }

    #[test]
    fn test_queue_running_takes_two_steps() {
        let mut q = WalkingQueue::new();
        q.is_running = true;
        q.set_waypoints(vec![Position::new(4, 0)]);

        let map = CollisionMap::new();
        let moves = q.process_tick(Position::new(0, 0), &map);
        assert_eq!(moves.len(), 2);
        assert_eq!(moves[0], Position::new(1, 0));
        assert_eq!(moves[1], Position::new(2, 0));
    }

    #[test]
    fn test_queue_stops_on_collision() {
        let mut map = CollisionMap::new();
        map.set_flags(2, 0, 0, FULL_BLOCK_A);

        let mut q = WalkingQueue::new();
        q.set_waypoints(vec![Position::new(5, 0)]);

        let moves = q.process_tick(Position::new(0, 0), &map);
        assert_eq!(moves.len(), 1);
        assert_eq!(moves[0], Position::new(1, 0));

        // Next tick should be blocked and queue cleared.
        let moves = q.process_tick(Position::new(1, 0), &map);
        assert!(moves.is_empty());
        assert!(q.finished());
    }

    #[test]
    fn test_direction_from_movement() {
        assert_eq!(
            direction_from_movement(Position::new(5, 5), Position::new(5, 4)),
            Direction::North,
        );
        assert_eq!(
            direction_from_movement(Position::new(5, 5), Position::new(6, 6)),
            Direction::SouthEast,
        );
    }

    #[test]
    fn test_clear_and_finished() {
        let mut q = WalkingQueue::new();
        assert!(q.finished());
        q.add_waypoint(Position::new(1, 1));
        assert!(!q.finished());
        q.clear();
        assert!(q.finished());
    }
}
