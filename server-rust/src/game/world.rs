//! World module for game world management.

use super::entity::{EntityId, Position};
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

        // Process NPCs
        for (id, npc) in &mut self.npcs {
            npc.tick();
        }

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
    pub current_hits: u32,
    pub max_hits: u32,
    pub in_combat: bool,
    pub respawn_ticks: u32,
    pub wander_radius: u32,
}

impl Npc {
    pub fn new(definition_id: u32, position: Position) -> Self {
        Self {
            definition_id,
            position,
            spawn_position: position,
            current_hits: 10,
            max_hits: 10,
            in_combat: false,
            respawn_ticks: 100,
            wander_radius: 5,
        }
    }

    pub fn tick(&mut self) {
        if self.in_combat {
            return;
        }

        // Wander logic would go here
    }

    pub fn take_damage(&mut self, damage: u32) -> bool {
        if damage >= self.current_hits {
            self.current_hits = 0;
            true // NPC died
        } else {
            self.current_hits -= damage;
            false
        }
    }

    pub fn is_dead(&self) -> bool {
        self.current_hits == 0
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
