//! World region system for spatial tile data, collision, and spawn management.
//!
//! The game world is divided into 64x64 tile regions. Each region stores per-tile
//! data including elevation, collision flags, and texture overlays. The
//! [`RegionManager`] provides lookups by world coordinates, while the
//! [`SpawnManager`] tracks NPC, object, and ground item spawn definitions loaded
//! from data files or a database.

use std::collections::HashMap;
use std::io::{self, BufRead, BufReader};
use std::path::Path;

use tracing::{debug, info, warn};

use super::entity::Position;
use super::game_object::ObjectType;
use super::item::ItemId;
use super::pathfinding::CollisionMap;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Width / height of a single region in tiles.
pub const REGION_SIZE: usize = 64;

/// The total number of tiles per region.
pub const TILES_PER_REGION: usize = REGION_SIZE * REGION_SIZE;

// ---------------------------------------------------------------------------
// Collision flags (bitfield)
// ---------------------------------------------------------------------------

/// Full tile block - nothing can walk here.
pub const COLLISION_FULL_BLOCK: u32 = 1 << 0;

/// Blocked to the north.
pub const COLLISION_NORTH: u32 = 1 << 1;

/// Blocked to the east.
pub const COLLISION_EAST: u32 = 1 << 2;

/// Blocked to the south.
pub const COLLISION_SOUTH: u32 = 1 << 3;

/// Blocked to the west.
pub const COLLISION_WEST: u32 = 1 << 4;

/// Blocked diagonally (NE).
pub const COLLISION_NORTH_EAST: u32 = 1 << 5;

/// Blocked diagonally (SE).
pub const COLLISION_SOUTH_EAST: u32 = 1 << 6;

/// Blocked diagonally (SW).
pub const COLLISION_SOUTH_WEST: u32 = 1 << 7;

/// Blocked diagonally (NW).
pub const COLLISION_NORTH_WEST: u32 = 1 << 8;

/// Object blocking flag (scenery placed on the tile).
pub const COLLISION_OBJECT: u32 = 1 << 9;

/// Water tile - only boats / certain spells can cross.
pub const COLLISION_WATER: u32 = 1 << 10;

// ---------------------------------------------------------------------------
// TileValue
// ---------------------------------------------------------------------------

/// Per-tile data stored inside a [`Region`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TileValue {
    /// Elevation level (0-255).
    pub elevation: u8,

    /// Collision flag bitfield.  See `COLLISION_*` constants.
    pub collision: u32,

    /// Texture overlay type index.
    pub overlay: u8,
}

impl Default for TileValue {
    fn default() -> Self {
        Self {
            elevation: 0,
            collision: 0,
            overlay: 0,
        }
    }
}

impl TileValue {
    /// Create a new tile with the given values.
    pub fn new(elevation: u8, collision: u32, overlay: u8) -> Self {
        Self {
            elevation,
            collision,
            overlay,
        }
    }

    /// Returns `true` when no blocking collision flags are set.
    pub fn is_walkable(&self) -> bool {
        self.collision & COLLISION_FULL_BLOCK == 0
    }

    /// Returns `true` when the full-block flag is set.
    pub fn is_blocked(&self) -> bool {
        self.collision & COLLISION_FULL_BLOCK != 0
    }

    /// Returns `true` if the given directional flag is set.
    pub fn has_flag(&self, flag: u32) -> bool {
        self.collision & flag != 0
    }
}

// ---------------------------------------------------------------------------
// Region
// ---------------------------------------------------------------------------

/// A 64x64 tile region of the game world.
///
/// Region coordinates are derived from world coordinates:
/// `region_x = world_x / 64`, `region_y = world_y / 64`.
#[derive(Debug, Clone)]
pub struct Region {
    /// Region coordinate (not world coordinate).
    pub region_x: i32,
    /// Region coordinate (not world coordinate).
    pub region_y: i32,
    /// Flat array of tile values, indexed as `[local_y * REGION_SIZE + local_x]`.
    tiles: Vec<TileValue>,
}

impl Region {
    /// Create a new region filled with default (empty, walkable) tiles.
    pub fn new(region_x: i32, region_y: i32) -> Self {
        Self {
            region_x,
            region_y,
            tiles: vec![TileValue::default(); TILES_PER_REGION],
        }
    }

    // -- coordinate helpers ------------------------------------------------

    /// Convert world coordinates to the local (0..63) offset inside this region.
    #[inline]
    pub fn to_local(world_coord: i32) -> usize {
        // Handles negative coordinates correctly via rem_euclid.
        (world_coord.rem_euclid(REGION_SIZE as i32)) as usize
    }

    /// Convert a flat index back to (local_x, local_y).
    #[inline]
    fn index_to_local(index: usize) -> (usize, usize) {
        (index % REGION_SIZE, index / REGION_SIZE)
    }

    /// Flat index from local coordinates, with bounds check.
    #[inline]
    fn tile_index(local_x: usize, local_y: usize) -> Option<usize> {
        if local_x < REGION_SIZE && local_y < REGION_SIZE {
            Some(local_y * REGION_SIZE + local_x)
        } else {
            None
        }
    }

    // -- tile access -------------------------------------------------------

    /// Get the tile at the given *local* coordinates.
    pub fn get_tile(&self, local_x: usize, local_y: usize) -> Option<&TileValue> {
        Self::tile_index(local_x, local_y).map(|i| &self.tiles[i])
    }

    /// Get a mutable reference to the tile at the given *local* coordinates.
    pub fn get_tile_mut(&mut self, local_x: usize, local_y: usize) -> Option<&mut TileValue> {
        Self::tile_index(local_x, local_y).map(|i| &mut self.tiles[i])
    }

    /// Set the collision flags on a tile (replaces existing flags).
    pub fn set_collision(&mut self, local_x: usize, local_y: usize, flags: u32) {
        if let Some(tile) = self.get_tile_mut(local_x, local_y) {
            tile.collision = flags;
        }
    }

    /// Add (bitwise OR) collision flags to a tile.
    pub fn add_collision(&mut self, local_x: usize, local_y: usize, flags: u32) {
        if let Some(tile) = self.get_tile_mut(local_x, local_y) {
            tile.collision |= flags;
        }
    }

    /// Remove (bitwise AND NOT) collision flags from a tile.
    pub fn remove_collision(&mut self, local_x: usize, local_y: usize, flags: u32) {
        if let Some(tile) = self.get_tile_mut(local_x, local_y) {
            tile.collision &= !flags;
        }
    }

    /// Set the full tile value at local coordinates.
    pub fn set_tile(&mut self, local_x: usize, local_y: usize, value: TileValue) {
        if let Some(idx) = Self::tile_index(local_x, local_y) {
            self.tiles[idx] = value;
        }
    }

    /// Iterate over all tiles with their local coordinates.
    pub fn iter_tiles(&self) -> impl Iterator<Item = (usize, usize, &TileValue)> {
        self.tiles.iter().enumerate().map(|(i, tile)| {
            let (lx, ly) = Self::index_to_local(i);
            (lx, ly, tile)
        })
    }
}

// ---------------------------------------------------------------------------
// RegionManager
// ---------------------------------------------------------------------------

/// Manages all loaded regions keyed by `(region_x, region_y)`.
#[derive(Debug, Default)]
pub struct RegionManager {
    regions: HashMap<(i32, i32), Region>,
}

impl RegionManager {
    /// Create an empty region manager.
    pub fn new() -> Self {
        Self::default()
    }

    // -- coordinate helpers ------------------------------------------------

    /// Derive region coordinates from world coordinates.
    #[inline]
    pub fn world_to_region(world_x: i32, world_y: i32) -> (i32, i32) {
        (
            world_x.div_euclid(REGION_SIZE as i32),
            world_y.div_euclid(REGION_SIZE as i32),
        )
    }

    // -- region access -----------------------------------------------------

    /// Get a reference to the region that contains the given world coordinates.
    pub fn get_region(&self, world_x: i32, world_y: i32) -> Option<&Region> {
        let key = Self::world_to_region(world_x, world_y);
        self.regions.get(&key)
    }

    /// Get a mutable reference to the region at the given world coordinates.
    pub fn get_region_mut(&mut self, world_x: i32, world_y: i32) -> Option<&mut Region> {
        let key = Self::world_to_region(world_x, world_y);
        self.regions.get_mut(&key)
    }

    /// Get or create the region for the given world coordinates.
    pub fn get_or_create_region(&mut self, world_x: i32, world_y: i32) -> &mut Region {
        let (rx, ry) = Self::world_to_region(world_x, world_y);
        self.regions
            .entry((rx, ry))
            .or_insert_with(|| Region::new(rx, ry))
    }

    /// Insert (or replace) a fully-built region.
    pub fn insert_region(&mut self, region: Region) {
        self.regions
            .insert((region.region_x, region.region_y), region);
    }

    // -- tile access (by world coords) -------------------------------------

    /// Get the tile at the given *world* coordinates and plane.
    ///
    /// `plane` is reserved for future multi-level support; currently only
    /// plane 0 stores data so other planes return `None`.
    pub fn get_tile(&self, world_x: i32, world_y: i32, _plane: i32) -> Option<&TileValue> {
        let region = self.get_region(world_x, world_y)?;
        let lx = Region::to_local(world_x);
        let ly = Region::to_local(world_y);
        region.get_tile(lx, ly)
    }

    /// Check whether the tile at `(world_x, world_y, plane)` is walkable.
    ///
    /// Tiles in unloaded regions are treated as **not** walkable.
    pub fn is_walkable(&self, world_x: i32, world_y: i32, plane: i32) -> bool {
        self.get_tile(world_x, world_y, plane)
            .map(|t| t.is_walkable())
            .unwrap_or(false)
    }

    /// Set collision flags on a world-coordinate tile (creates the region if
    /// it does not exist yet).
    pub fn set_collision(&mut self, world_x: i32, world_y: i32, flags: u32) {
        let region = self.get_or_create_region(world_x, world_y);
        let lx = Region::to_local(world_x);
        let ly = Region::to_local(world_y);
        region.set_collision(lx, ly, flags);
    }

    /// Add collision flags (OR) on a world-coordinate tile.
    pub fn add_collision(&mut self, world_x: i32, world_y: i32, flags: u32) {
        let region = self.get_or_create_region(world_x, world_y);
        let lx = Region::to_local(world_x);
        let ly = Region::to_local(world_y);
        region.add_collision(lx, ly, flags);
    }

    // -- bulk loading ------------------------------------------------------

    /// Load tile data from a directory of region files.
    ///
    /// Expected file name format: `region_<rx>_<ry>.dat`
    ///
    /// Each line in a region file is:
    /// ```text
    /// local_x local_y elevation collision overlay
    /// ```
    ///
    /// Lines starting with `#` are treated as comments and skipped.
    pub fn load_from_data(&mut self, data_path: &Path) -> io::Result<()> {
        if !data_path.is_dir() {
            warn!(
                "Region data path does not exist or is not a directory: {}",
                data_path.display()
            );
            return Ok(());
        }

        let mut loaded = 0u32;

        for entry in std::fs::read_dir(data_path)? {
            let entry = entry?;
            let path = entry.path();

            // Only process .dat files matching the naming convention.
            let file_name = match path.file_name().and_then(|n| n.to_str()) {
                Some(n) if n.starts_with("region_") && n.ends_with(".dat") => n.to_owned(),
                _ => continue,
            };

            // Parse region coordinates from filename.
            let parts: Vec<&str> = file_name
                .trim_start_matches("region_")
                .trim_end_matches(".dat")
                .split('_')
                .collect();

            if parts.len() != 2 {
                warn!("Skipping malformed region file name: {}", file_name);
                continue;
            }

            let rx: i32 = match parts[0].parse() {
                Ok(v) => v,
                Err(_) => {
                    warn!("Bad region x in file name: {}", file_name);
                    continue;
                }
            };
            let ry: i32 = match parts[1].parse() {
                Ok(v) => v,
                Err(_) => {
                    warn!("Bad region y in file name: {}", file_name);
                    continue;
                }
            };

            let mut region = Region::new(rx, ry);
            let file = std::fs::File::open(&path)?;
            let reader = BufReader::new(file);

            for line in reader.lines() {
                let line = line?;
                let line = line.trim();
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }

                let tokens: Vec<&str> = line.split_whitespace().collect();
                if tokens.len() < 5 {
                    continue;
                }

                let lx: usize = tokens[0].parse().unwrap_or(0);
                let ly: usize = tokens[1].parse().unwrap_or(0);
                let elevation: u8 = tokens[2].parse().unwrap_or(0);
                let collision: u32 = tokens[3].parse().unwrap_or(0);
                let overlay: u8 = tokens[4].parse().unwrap_or(0);

                region.set_tile(lx, ly, TileValue::new(elevation, collision, overlay));
            }

            self.insert_region(region);
            loaded += 1;
        }

        info!(
            "Loaded {} region file(s) from {}",
            loaded,
            data_path.display()
        );
        Ok(())
    }

    /// Number of regions currently loaded.
    pub fn region_count(&self) -> usize {
        self.regions.len()
    }
}

// Implement the pathfinding CollisionMap trait so the region data can be fed
// directly into the A* pathfinder.
impl CollisionMap for RegionManager {
    fn is_walkable(&self, x: i32, y: i32, plane: i32) -> bool {
        self.is_walkable(x, y, plane)
    }

    fn can_traverse(&self, from: Position, dx: i16, dy: i16) -> bool {
        let to_x = from.x + dx as i32;
        let to_y = from.y + dy as i32;

        // Destination must be walkable.
        if !self.is_walkable(to_x, to_y, from.plane) {
            return false;
        }

        // For diagonal movement check that both adjacent cardinal tiles are
        // also passable (prevents corner-cutting through walls).
        if dx != 0 && dy != 0 {
            if !self.is_walkable(from.x + dx as i32, from.y, from.plane) {
                return false;
            }
            if !self.is_walkable(from.x, from.y + dy as i32, from.plane) {
                return false;
            }
        }

        // Check directional flags on the *source* tile.
        if let Some(src) = self.get_tile(from.x, from.y, from.plane) {
            let blocked = match (dx.signum(), dy.signum()) {
                (0, -1) => src.has_flag(COLLISION_NORTH),
                (1, -1) => src.has_flag(COLLISION_NORTH_EAST),
                (1, 0) => src.has_flag(COLLISION_EAST),
                (1, 1) => src.has_flag(COLLISION_SOUTH_EAST),
                (0, 1) => src.has_flag(COLLISION_SOUTH),
                (-1, 1) => src.has_flag(COLLISION_SOUTH_WEST),
                (-1, 0) => src.has_flag(COLLISION_WEST),
                (-1, -1) => src.has_flag(COLLISION_NORTH_WEST),
                _ => false,
            };
            if blocked {
                return false;
            }
        }

        true
    }
}

// ---------------------------------------------------------------------------
// NpcSpawn
// ---------------------------------------------------------------------------

/// Definition for a world NPC spawn point.
#[derive(Debug, Clone)]
pub struct NpcSpawn {
    /// NPC definition id.
    pub npc_id: u32,
    /// Spawn (and initial) position.
    pub position: Position,

    // Wander / patrol bounding box (world coordinates).
    pub min_x: i32,
    pub max_x: i32,
    pub min_y: i32,
    pub max_y: i32,
}

impl NpcSpawn {
    /// Create a spawn at a fixed position with no wander area.
    pub fn fixed(npc_id: u32, position: Position) -> Self {
        Self {
            npc_id,
            position,
            min_x: position.x,
            max_x: position.x,
            min_y: position.y,
            max_y: position.y,
        }
    }

    /// Create a spawn with a wander bounding box.
    pub fn with_bounds(
        npc_id: u32,
        position: Position,
        min_x: i32,
        max_x: i32,
        min_y: i32,
        max_y: i32,
    ) -> Self {
        Self {
            npc_id,
            position,
            min_x,
            max_x,
            min_y,
            max_y,
        }
    }

    /// Whether this NPC is allowed to wander (bounds larger than a single tile).
    pub fn can_wander(&self) -> bool {
        self.max_x > self.min_x || self.max_y > self.min_y
    }
}

// ---------------------------------------------------------------------------
// ObjectSpawn
// ---------------------------------------------------------------------------

/// Definition for a world object spawn point.
#[derive(Debug, Clone)]
pub struct ObjectSpawn {
    /// Object definition id.
    pub object_id: u32,
    /// World position.
    pub position: Position,
    /// Facing direction (0=N,1=E,2=S,3=W).
    pub direction: u8,
    /// Object type (Scenery / Boundary / GroundDecoration).
    pub object_type: ObjectType,
}

impl ObjectSpawn {
    pub fn new(object_id: u32, position: Position, direction: u8, object_type: ObjectType) -> Self {
        Self {
            object_id,
            position,
            direction,
            object_type,
        }
    }

    /// Convenience constructor for scenery objects.
    pub fn scenery(object_id: u32, position: Position, direction: u8) -> Self {
        Self::new(object_id, position, direction, ObjectType::Scenery)
    }

    /// Convenience constructor for boundary objects.
    pub fn boundary(object_id: u32, position: Position, direction: u8) -> Self {
        Self::new(object_id, position, direction, ObjectType::Boundary)
    }
}

// ---------------------------------------------------------------------------
// GroundItemSpawn
// ---------------------------------------------------------------------------

/// Definition for a respawning ground item.
#[derive(Debug, Clone)]
pub struct GroundItemSpawn {
    /// Item definition id.
    pub item_id: ItemId,
    /// Stack amount.
    pub amount: u32,
    /// World position.
    pub position: Position,
    /// Respawn delay in game ticks.
    pub respawn_ticks: u32,
}

impl GroundItemSpawn {
    pub fn new(item_id: ItemId, amount: u32, position: Position, respawn_ticks: u32) -> Self {
        Self {
            item_id,
            amount,
            position,
            respawn_ticks,
        }
    }
}

// ---------------------------------------------------------------------------
// SpawnManager
// ---------------------------------------------------------------------------

/// Central registry of spawn definitions loaded from data / config files.
#[derive(Debug, Default)]
pub struct SpawnManager {
    pub npc_spawns: Vec<NpcSpawn>,
    pub object_spawns: Vec<ObjectSpawn>,
    pub ground_item_spawns: Vec<GroundItemSpawn>,
}

impl SpawnManager {
    /// Create an empty spawn manager.
    pub fn new() -> Self {
        Self::default()
    }

    // -- NPC spawns --------------------------------------------------------

    /// Register an NPC spawn definition.
    pub fn add_npc_spawn(&mut self, spawn: NpcSpawn) {
        self.npc_spawns.push(spawn);
    }

    /// Get all NPC spawns whose position falls inside the given rectangle.
    pub fn npc_spawns_in_area(
        &self,
        min_x: i32,
        min_y: i32,
        max_x: i32,
        max_y: i32,
    ) -> Vec<&NpcSpawn> {
        self.npc_spawns
            .iter()
            .filter(|s| {
                s.position.x >= min_x
                    && s.position.x <= max_x
                    && s.position.y >= min_y
                    && s.position.y <= max_y
            })
            .collect()
    }

    // -- Object spawns -----------------------------------------------------

    /// Register an object spawn definition.
    pub fn add_object_spawn(&mut self, spawn: ObjectSpawn) {
        self.object_spawns.push(spawn);
    }

    /// Get all object spawns inside the given rectangle.
    pub fn object_spawns_in_area(
        &self,
        min_x: i32,
        min_y: i32,
        max_x: i32,
        max_y: i32,
    ) -> Vec<&ObjectSpawn> {
        self.object_spawns
            .iter()
            .filter(|s| {
                s.position.x >= min_x
                    && s.position.x <= max_x
                    && s.position.y >= min_y
                    && s.position.y <= max_y
            })
            .collect()
    }

    // -- Ground item spawns ------------------------------------------------

    /// Register a ground item spawn definition.
    pub fn add_ground_item_spawn(&mut self, spawn: GroundItemSpawn) {
        self.ground_item_spawns.push(spawn);
    }

    // -- Bulk loading from config files ------------------------------------

    /// Load NPC spawns from a simple text file.
    ///
    /// Format per line: `npc_id x y plane min_x max_x min_y max_y`
    pub fn load_npc_spawns(&mut self, path: &Path) -> io::Result<()> {
        let file = std::fs::File::open(path)?;
        let reader = BufReader::new(file);
        let mut count = 0u32;

        for line in reader.lines() {
            let line = line?;
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            let tokens: Vec<&str> = line.split_whitespace().collect();
            if tokens.len() < 8 {
                debug!("Skipping short NPC spawn line: {}", line);
                continue;
            }

            let npc_id: u32 = tokens[0].parse().unwrap_or(0);
            let x: i32 = tokens[1].parse().unwrap_or(0);
            let y: i32 = tokens[2].parse().unwrap_or(0);
            let plane: i32 = tokens[3].parse().unwrap_or(0);
            let min_x: i32 = tokens[4].parse().unwrap_or(x);
            let max_x: i32 = tokens[5].parse().unwrap_or(x);
            let min_y: i32 = tokens[6].parse().unwrap_or(y);
            let max_y: i32 = tokens[7].parse().unwrap_or(y);

            self.add_npc_spawn(NpcSpawn::with_bounds(
                npc_id,
                Position::with_plane(x, y, plane),
                min_x,
                max_x,
                min_y,
                max_y,
            ));
            count += 1;
        }

        info!("Loaded {} NPC spawn(s) from {}", count, path.display());
        Ok(())
    }

    /// Load object spawns from a simple text file.
    ///
    /// Format per line: `object_id x y plane direction type`
    /// where `type` is one of: `scenery`, `boundary`, `decoration`.
    pub fn load_object_spawns(&mut self, path: &Path) -> io::Result<()> {
        let file = std::fs::File::open(path)?;
        let reader = BufReader::new(file);
        let mut count = 0u32;

        for line in reader.lines() {
            let line = line?;
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            let tokens: Vec<&str> = line.split_whitespace().collect();
            if tokens.len() < 6 {
                debug!("Skipping short object spawn line: {}", line);
                continue;
            }

            let object_id: u32 = tokens[0].parse().unwrap_or(0);
            let x: i32 = tokens[1].parse().unwrap_or(0);
            let y: i32 = tokens[2].parse().unwrap_or(0);
            let plane: i32 = tokens[3].parse().unwrap_or(0);
            let direction: u8 = tokens[4].parse().unwrap_or(0);
            let obj_type = match tokens[5] {
                "boundary" => ObjectType::Boundary,
                "decoration" => ObjectType::GroundDecoration,
                _ => ObjectType::Scenery,
            };

            self.add_object_spawn(ObjectSpawn::new(
                object_id,
                Position::with_plane(x, y, plane),
                direction,
                obj_type,
            ));
            count += 1;
        }

        info!("Loaded {} object spawn(s) from {}", count, path.display());
        Ok(())
    }

    /// Load ground item spawns from a simple text file.
    ///
    /// Format per line: `item_id amount x y plane respawn_ticks`
    pub fn load_ground_item_spawns(&mut self, path: &Path) -> io::Result<()> {
        let file = std::fs::File::open(path)?;
        let reader = BufReader::new(file);
        let mut count = 0u32;

        for line in reader.lines() {
            let line = line?;
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            let tokens: Vec<&str> = line.split_whitespace().collect();
            if tokens.len() < 6 {
                debug!("Skipping short ground item spawn line: {}", line);
                continue;
            }

            let item_id: u32 = tokens[0].parse().unwrap_or(0);
            let amount: u32 = tokens[1].parse().unwrap_or(1);
            let x: i32 = tokens[2].parse().unwrap_or(0);
            let y: i32 = tokens[3].parse().unwrap_or(0);
            let plane: i32 = tokens[4].parse().unwrap_or(0);
            let respawn_ticks: u32 = tokens[5].parse().unwrap_or(100);

            self.add_ground_item_spawn(GroundItemSpawn::new(
                ItemId(item_id),
                amount,
                Position::with_plane(x, y, plane),
                respawn_ticks,
            ));
            count += 1;
        }

        info!(
            "Loaded {} ground item spawn(s) from {}",
            count,
            path.display()
        );
        Ok(())
    }

    /// Total number of registered spawns (all types).
    pub fn total_spawns(&self) -> usize {
        self.npc_spawns.len() + self.object_spawns.len() + self.ground_item_spawns.len()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // -- TileValue ---------------------------------------------------------

    #[test]
    fn test_tile_default_is_walkable() {
        let tile = TileValue::default();
        assert!(tile.is_walkable());
        assert!(!tile.is_blocked());
    }

    #[test]
    fn test_tile_full_block() {
        let tile = TileValue::new(0, COLLISION_FULL_BLOCK, 0);
        assert!(!tile.is_walkable());
        assert!(tile.is_blocked());
    }

    #[test]
    fn test_tile_directional_flag() {
        let tile = TileValue::new(0, COLLISION_NORTH | COLLISION_EAST, 0);
        assert!(tile.has_flag(COLLISION_NORTH));
        assert!(tile.has_flag(COLLISION_EAST));
        assert!(!tile.has_flag(COLLISION_SOUTH));
        // Directional flags alone do not make the tile un-walkable (only FULL_BLOCK does).
        assert!(tile.is_walkable());
    }

    // -- Region ------------------------------------------------------------

    #[test]
    fn test_region_get_set_tile() {
        let mut region = Region::new(0, 0);

        // Default tile
        let tile = region.get_tile(10, 20).unwrap();
        assert!(tile.is_walkable());

        // Set and retrieve
        region.set_tile(10, 20, TileValue::new(5, COLLISION_FULL_BLOCK, 3));
        let tile = region.get_tile(10, 20).unwrap();
        assert_eq!(tile.elevation, 5);
        assert_eq!(tile.overlay, 3);
        assert!(!tile.is_walkable());
    }

    #[test]
    fn test_region_out_of_bounds() {
        let region = Region::new(0, 0);
        assert!(region.get_tile(64, 0).is_none());
        assert!(region.get_tile(0, 64).is_none());
        assert!(region.get_tile(100, 100).is_none());
    }

    #[test]
    fn test_region_collision_operations() {
        let mut region = Region::new(0, 0);

        region.add_collision(5, 5, COLLISION_NORTH);
        assert!(region.get_tile(5, 5).unwrap().has_flag(COLLISION_NORTH));

        region.add_collision(5, 5, COLLISION_EAST);
        assert!(region.get_tile(5, 5).unwrap().has_flag(COLLISION_NORTH));
        assert!(region.get_tile(5, 5).unwrap().has_flag(COLLISION_EAST));

        region.remove_collision(5, 5, COLLISION_NORTH);
        assert!(!region.get_tile(5, 5).unwrap().has_flag(COLLISION_NORTH));
        assert!(region.get_tile(5, 5).unwrap().has_flag(COLLISION_EAST));
    }

    #[test]
    fn test_to_local() {
        assert_eq!(Region::to_local(0), 0);
        assert_eq!(Region::to_local(63), 63);
        assert_eq!(Region::to_local(64), 0);
        assert_eq!(Region::to_local(65), 1);
        assert_eq!(Region::to_local(128), 0);
        // Negative world coordinates.
        assert_eq!(Region::to_local(-1), 63);
        assert_eq!(Region::to_local(-64), 0);
        assert_eq!(Region::to_local(-65), 63);
    }

    // -- RegionManager -----------------------------------------------------

    #[test]
    fn test_world_to_region() {
        assert_eq!(RegionManager::world_to_region(0, 0), (0, 0));
        assert_eq!(RegionManager::world_to_region(63, 63), (0, 0));
        assert_eq!(RegionManager::world_to_region(64, 0), (1, 0));
        assert_eq!(RegionManager::world_to_region(128, 128), (2, 2));
        assert_eq!(RegionManager::world_to_region(-1, -1), (-1, -1));
        assert_eq!(RegionManager::world_to_region(-64, -64), (-1, -1));
        assert_eq!(RegionManager::world_to_region(-65, -65), (-2, -2));
    }

    #[test]
    fn test_region_manager_walkability() {
        let mut mgr = RegionManager::new();

        // Unloaded region => not walkable.
        assert!(!mgr.is_walkable(100, 100, 0));

        // Create region and set one tile blocked.
        mgr.get_or_create_region(100, 100);
        assert!(mgr.is_walkable(100, 100, 0));

        mgr.set_collision(100, 100, COLLISION_FULL_BLOCK);
        assert!(!mgr.is_walkable(100, 100, 0));
    }

    #[test]
    fn test_region_manager_collision_map() {
        let mut mgr = RegionManager::new();

        // Create a small walkable area.
        for x in 0..10 {
            for y in 0..10 {
                mgr.get_or_create_region(x, y);
            }
        }

        // Block a tile.
        mgr.set_collision(5, 5, COLLISION_FULL_BLOCK);

        // CollisionMap trait usage.
        let cm: &dyn CollisionMap = &mgr;
        assert!(cm.is_walkable(0, 0, 0));
        assert!(!cm.is_walkable(5, 5, 0));

        let from = Position::new(4, 5);
        assert!(cm.can_traverse(from, 0, -1)); // north: walkable
        assert!(!cm.can_traverse(from, 1, 0)); // east into blocked tile
    }

    // -- NpcSpawn ----------------------------------------------------------

    #[test]
    fn test_npc_spawn_fixed() {
        let spawn = NpcSpawn::fixed(42, Position::new(100, 200));
        assert_eq!(spawn.npc_id, 42);
        assert!(!spawn.can_wander());
    }

    #[test]
    fn test_npc_spawn_with_bounds() {
        let spawn = NpcSpawn::with_bounds(1, Position::new(100, 200), 95, 105, 195, 205);
        assert!(spawn.can_wander());
    }

    // -- ObjectSpawn -------------------------------------------------------

    #[test]
    fn test_object_spawn() {
        let spawn = ObjectSpawn::scenery(10, Position::new(50, 50), 0);
        assert_eq!(spawn.object_type, ObjectType::Scenery);
        assert_eq!(spawn.direction, 0);
    }

    // -- SpawnManager ------------------------------------------------------

    #[test]
    fn test_spawn_manager_add_and_query() {
        let mut sm = SpawnManager::new();

        sm.add_npc_spawn(NpcSpawn::fixed(1, Position::new(10, 10)));
        sm.add_npc_spawn(NpcSpawn::fixed(2, Position::new(100, 100)));
        sm.add_object_spawn(ObjectSpawn::scenery(5, Position::new(10, 10), 0));
        sm.add_ground_item_spawn(GroundItemSpawn::new(
            ItemId(100),
            1,
            Position::new(10, 10),
            50,
        ));

        assert_eq!(sm.total_spawns(), 4);

        // Area query for NPCs.
        let near = sm.npc_spawns_in_area(0, 0, 50, 50);
        assert_eq!(near.len(), 1);
        assert_eq!(near[0].npc_id, 1);

        // Area query for objects.
        let objs = sm.object_spawns_in_area(0, 0, 50, 50);
        assert_eq!(objs.len(), 1);
    }
}
