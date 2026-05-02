//! World module for game world management.

use super::entity::{Direction, EntityId, Position};
use rand::Rng;
use std::collections::HashMap;
use tracing::{debug, info};

/// Game world containing all entities and state.
pub struct World {
    pub name: String,
    pub max_players: u32,
    pub player_count: u32,
    pub regions: HashMap<RegionId, Region>,
    pub npcs: HashMap<EntityId, Npc>,
    pub ground_items: HashMap<Position, Vec<GroundItem>>,
    pub game_objects: HashMap<Position, GameObject>,
    tick_count: u64,
}

impl World {
    pub fn new(name: String, max_players: u32) -> Self {
        Self {
            name,
            max_players,
            player_count: 0,
            regions: HashMap::new(),
            npcs: HashMap::new(),
            ground_items: HashMap::new(),
            game_objects: HashMap::new(),
            tick_count: 0,
        }
    }

    /// Process world tick.
    pub async fn tick(&mut self) {
        self.tick_count += 1;

        // Process live NPCs
        for (_id, npc) in &mut self.npcs {
            if npc.is_alive() {
                npc.tick();
            }
        }

        // Respawn dead NPCs whose timer has expired
        self.process_npc_respawns();

        // Process ground item timers
        self.process_ground_items();

        // Respawn game objects
        self.process_game_objects();
    }

    fn process_ground_items(&mut self) {
        let current_tick = self.tick_count;

        // Remove expired ground items
        self.ground_items.retain(|pos, items| {
            items.retain(|item| {
                if let Some(expire_tick) = item.expire_tick {
                    current_tick < expire_tick
                } else {
                    true
                }
            });
            !items.is_empty()
        });
    }

    fn process_game_objects(&mut self) {
        let current_tick = self.tick_count;

        // Respawn depleted game objects
        for (pos, obj) in &mut self.game_objects {
            if !obj.active {
                if let Some(respawn_tick) = obj.respawn_tick {
                    if current_tick >= respawn_tick {
                        obj.active = true;
                        obj.respawn_tick = None;
                        debug!("Respawned game object {} at {}", obj.id, pos);
                    }
                }
            }
        }
    }

    /// Spawn an NPC in the world.
    pub fn spawn_npc(&mut self, id: EntityId, npc: Npc) {
        info!("Spawned NPC {} at {}", npc.definition_id, npc.position);
        self.npcs.insert(id, npc);
    }

    /// Remove an NPC from the world.
    pub fn despawn_npc(&mut self, id: EntityId) {
        if self.npcs.remove(&id).is_some() {
            debug!("Despawned NPC {:?}", id);
        }
    }

    /// Drop an item on the ground.
    pub fn drop_item(&mut self, position: Position, item: GroundItem) {
        self.ground_items
            .entry(position)
            .or_insert_with(Vec::new)
            .push(item);
    }

    /// Pick up a ground item.
    pub fn pickup_item(&mut self, position: Position, item_id: u32) -> Option<GroundItem> {
        if let Some(items) = self.ground_items.get_mut(&position) {
            if let Some(index) = items.iter().position(|i| i.item_id == item_id) {
                return Some(items.remove(index));
            }
        }
        None
    }

    /// Get or create a region.
    pub fn get_region(&mut self, region_id: RegionId) -> &mut Region {
        self.regions.entry(region_id).or_insert_with(|| Region::new(region_id))
    }

    /// Get region ID for a position.
    pub fn region_id_for_position(pos: Position) -> RegionId {
        RegionId {
            x: pos.x / 64,
            y: pos.y / 64,
        }
    }

    /// Current world tick counter.
    fn process_npc_respawns(&mut self) {
        let current_tick = self.tick_count;
        for (_id, npc) in &mut self.npcs {
            if let Some(death_tick) = npc.dead_since_tick {
                if current_tick >= death_tick + npc.respawn_ticks as u64 {
                    // Respawn: restore HP, return to spawn point, clear death flag
                    npc.current_hits = npc.max_hits;
                    npc.position = npc.spawn_position;
                    npc.direction = Direction::South;
                    npc.moved_this_tick = false;
                    npc.in_combat = false;
                    npc.dead_since_tick = None;
                    info!("NPC {} respawned at spawn position", npc.definition_id);
                }
            }
        }
    }

    pub fn tick_count(&self) -> u64 {
        self.tick_count
    }

    /// Check if position is walkable.
    pub fn is_walkable(&self, pos: Position) -> bool {
        // Check for blocking game objects
        if let Some(obj) = self.game_objects.get(&pos) {
            if obj.blocks_movement {
                return false;
            }
        }

        // Additional collision checks would go here
        true
    }
}

/// Region identifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct RegionId {
    pub x: i32,
    pub y: i32,
}

/// A region of the world (64x64 tiles).
pub struct Region {
    pub id: RegionId,
    pub players: Vec<EntityId>,
    pub npcs: Vec<EntityId>,
}

impl Region {
    pub fn new(id: RegionId) -> Self {
        Self {
            id,
            players: Vec::new(),
            npcs: Vec::new(),
        }
    }
}

/// NPC entity.
pub struct Npc {
    pub definition_id: u32,
    pub position: Position,
    pub spawn_position: Position,
    pub direction: Direction,
    pub current_hits: u32,
    pub max_hits: u32,
    pub in_combat: bool,
    pub respawn_ticks: u32,
    pub wander_radius: u32,
    /// Set `true` by the walk logic for the duration of one tick then cleared.
    pub moved_this_tick: bool,
    /// Tick on which this NPC died; `None` if the NPC is alive.
    pub dead_since_tick: Option<u64>,
}

impl Npc {
    pub fn new(definition_id: u32, position: Position) -> Self {
        Self {
            definition_id,
            position,
            spawn_position: position,
            direction: Direction::South,
            current_hits: 10,
            max_hits: 10,
            in_combat: false,
            respawn_ticks: 100,
            wander_radius: 5,
            moved_this_tick: false,
            dead_since_tick: None,
        }
    }

    pub fn tick(&mut self) {
        // Clear the per-tick movement flag at the start of each tick so
        // that any walk logic executed below can set it accurately.
        self.moved_this_tick = false;

        if self.in_combat {
            return;
        }

        // Wander: ~25% chance per tick the NPC takes one random step.
        let mut rng = rand::thread_rng();
        if rng.gen_bool(0.25) {
            // Cardinal + diagonal directions with (dx, dy, Direction) tuples.
            let candidates: [(i32, i32, Direction); 8] = [
                ( 0,  1, Direction::North),
                ( 0, -1, Direction::South),
                (-1,  0, Direction::West),
                ( 1,  0, Direction::East),
                (-1,  1, Direction::NorthWest),
                ( 1,  1, Direction::NorthEast),
                (-1, -1, Direction::SouthWest),
                ( 1, -1, Direction::SouthEast),
            ];
            let (dx, dy, dir) = candidates[rng.gen_range(0..8)];
            let candidate = Position::new(
                self.position.x + dx,
                self.position.y + dy,
            );
            // Stay within wander_radius of spawn.
            let dist_x = (candidate.x - self.spawn_position.x).abs();
            let dist_y = (candidate.y - self.spawn_position.y).abs();
            if dist_x <= self.wander_radius as i32 && dist_y <= self.wander_radius as i32 {
                self.position = candidate;
                self.direction = dir;
                self.moved_this_tick = true;
                debug!("NPC {} wandered {:?}", self.definition_id, dir);
            }
        }
    }

    /// Apply damage. Returns `true` if the NPC has just been reduced to 0 HP.
    /// The caller is responsible for calling `die(tick)` when this returns true.
    pub fn take_damage(&mut self, damage: u32) -> bool {
        if damage >= self.current_hits {
            self.current_hits = 0;
            true
        } else {
            self.current_hits -= damage;
            false
        }
    }

    /// Mark the NPC as dead, recording the tick on which it died.
    pub fn die(&mut self, current_tick: u64) {
        self.current_hits = 0;
        self.dead_since_tick = Some(current_tick);
        self.in_combat = false;
    }

    pub fn is_dead(&self) -> bool {
        self.dead_since_tick.is_some()
    }

    /// True if the NPC is alive and visible to players.
    pub fn is_alive(&self) -> bool {
        self.dead_since_tick.is_none()
    }
}

/// Ground item.
#[derive(Debug, Clone)]
pub struct GroundItem {
    pub item_id: u32,
    pub amount: u32,
    pub dropped_by: Option<EntityId>,
    pub visible_to_all: bool,
    pub expire_tick: Option<u64>,
}

impl GroundItem {
    pub fn new(item_id: u32, amount: u32) -> Self {
        Self {
            item_id,
            amount,
            dropped_by: None,
            visible_to_all: true,
            expire_tick: None,
        }
    }

    pub fn with_owner(mut self, owner: EntityId, expire_tick: u64) -> Self {
        self.dropped_by = Some(owner);
        self.visible_to_all = false;
        self.expire_tick = Some(expire_tick);
        self
    }
}

/// Game object (trees, rocks, doors, etc.)
pub struct GameObject {
    pub id: u32,
    pub position: Position,
    pub active: bool,
    pub blocks_movement: bool,
    pub respawn_tick: Option<u64>,
    pub respawn_delay: u32,
}

impl GameObject {
    pub fn new(id: u32, position: Position) -> Self {
        Self {
            id,
            position,
            active: true,
            blocks_movement: false,
            respawn_tick: None,
            respawn_delay: 100,
        }
    }

    pub fn deplete(&mut self, current_tick: u64) {
        self.active = false;
        self.respawn_tick = Some(current_tick + self.respawn_delay as u64);
    }
}
