//! World module for game world management.

use super::entity::{Direction, EntityId, Position};
use super::game_object::ObjectType;
use super::region::{ObjectSpawn, SpawnManager};
use super::walking::CollisionMap as WalkingCollisionMap;
use super::world_loader::load_base_java_locs_dir;
use std::collections::HashMap;
use std::io;
use std::path::Path;
use tracing::{debug, info};

/// Counts returned when static spawn definitions are applied to a live world.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct WorldSpawnApplySummary {
    pub npcs: usize,
    pub objects: usize,
    pub ground_items: usize,
}

/// Collision sources to include when validating live movement.
///
/// The default intentionally preserves the current seeded-world behavior:
/// only explicit runtime blockers are included. Java loc collision is opt-in
/// until the server movement adapter enables it after Java data loading.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum MovementCollisionPolicy {
    #[default]
    SeededRuntimeOnly,
    JavaLocs,
}

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
    next_npc_entity_id: u64,
    next_npc_index: u16,
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
            next_npc_entity_id: 1,
            next_npc_index: 1,
        }
    }

    /// Spawn an NPC by definition ID at a position, assigning entity ID + slot index.
    pub fn spawn_npc_at(&mut self, definition_id: u32, position: Position) -> EntityId {
        let entity_id = EntityId(self.next_npc_entity_id);
        self.next_npc_entity_id += 1;
        let mut npc = Npc::new(definition_id, position);
        // Per-def HP. Mirrors the small `npc_stats_for` table on the server
        // side for combat balance — Goblin tougher than Chicken etc.
        let hp = match definition_id {
            1 => 7,  // Man
            3 => 10, // Goblin
            5 => 3,  // Chicken
            _ => 5,
        };
        npc.current_hits = hp;
        npc.max_hits = hp;
        npc.npc_index = self.next_npc_index;
        // Slot indices wrap at 4095 (12 bits in the wire protocol).
        self.next_npc_index = (self.next_npc_index % 4095) + 1;
        self.npcs.insert(entity_id, npc);
        entity_id
    }

    /// Apply static spawn definitions to this live world.
    ///
    /// This is intentionally explicit so `World::new` and the current seeded
    /// default world remain unchanged until initialization opts into Java data.
    pub fn apply_spawn_manager(&mut self, spawns: &SpawnManager) -> WorldSpawnApplySummary {
        for spawn in &spawns.npc_spawns {
            let entity_id = self.spawn_npc_at(spawn.npc_id, spawn.position);
            if let Some(npc) = self.npcs.get_mut(&entity_id) {
                npc.wander_radius = npc_spawn_wander_radius(spawn);
            }
        }

        for spawn in &spawns.object_spawns {
            let obj = game_object_from_spawn(spawn);
            self.game_objects.insert(spawn.position, obj);
        }

        for spawn in &spawns.ground_item_spawns {
            self.ground_items
                .entry(spawn.position)
                .or_insert_with(Vec::new)
                .push(GroundItem::new(spawn.item_id.0, spawn.amount));
        }

        WorldSpawnApplySummary {
            npcs: spawns.npc_spawns.len(),
            objects: spawns.object_spawns.len(),
            ground_items: spawns.ground_item_spawns.len(),
        }
    }

    /// Load the base Java loc file family from `locs_dir` and apply it.
    pub fn apply_base_java_locs_dir(
        &mut self,
        locs_dir: &Path,
    ) -> io::Result<WorldSpawnApplySummary> {
        let spawns = load_base_java_locs_dir(locs_dir)?;
        Ok(self.apply_spawn_manager(&spawns))
    }

    /// Read the current world tick. Used by other systems (combat, etc.) to
    /// stamp time-of-event without having to thread the server tick counter
    /// through every API.
    pub fn tick_count(&self) -> u64 {
        self.tick_count
    }

    /// Process world tick.
    pub async fn tick(&mut self) {
        self.tick_count += 1;
        let current_tick = self.tick_count;

        // Process NPCs (wander + respawn-if-dead).
        for (_id, npc) in &mut self.npcs {
            // Respawn if death_tick has matured.
            if npc.removed {
                if let Some(dt) = npc.death_tick {
                    if current_tick >= dt + npc.respawn_ticks as u64 {
                        npc.removed = false;
                        npc.death_tick = None;
                        npc.position = npc.spawn_position;
                        npc.current_hits = npc.max_hits;
                        npc.in_combat = false;
                    }
                }
            }
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
        self.regions
            .entry(region_id)
            .or_insert_with(|| Region::new(region_id))
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

    /// Build a movement collision map from loaded Java/OpenRSC boundary locs.
    ///
    /// This is opt-in so the current seeded playable area stays behaviorally
    /// unchanged until the server movement adapter is wired to this map.
    pub fn java_loc_collision_map(&self) -> WalkingCollisionMap {
        let mut collision = WalkingCollisionMap::new();
        for obj in self.game_objects.values() {
            if obj.obj_type == 1 {
                collision.apply_java_boundary(obj.position, obj.direction);
            }
        }
        collision
    }

    /// Build the movement collision map a live movement adapter can consume.
    pub fn movement_collision_map(&self, policy: MovementCollisionPolicy) -> WalkingCollisionMap {
        let mut collision = WalkingCollisionMap::new();
        self.apply_runtime_blockers_to_collision_map(&mut collision);

        if policy == MovementCollisionPolicy::JavaLocs {
            self.apply_java_locs_to_collision_map(&mut collision);
        }

        collision
    }

    /// Validate a single adjacent movement step using a selected collision policy.
    pub fn can_move_with_collision(
        &self,
        from: Position,
        to: Position,
        policy: MovementCollisionPolicy,
    ) -> bool {
        self.movement_collision_map(policy).can_move(from, to)
    }

    fn apply_runtime_blockers_to_collision_map(&self, collision: &mut WalkingCollisionMap) {
        for obj in self.game_objects.values() {
            if obj.active && obj.blocks_movement {
                collision.block_tile(obj.position);
            }
        }
    }

    fn apply_java_locs_to_collision_map(&self, collision: &mut WalkingCollisionMap) {
        for obj in self.game_objects.values() {
            if obj.obj_type == 1 {
                collision.apply_java_boundary(obj.position, obj.direction);
            }
        }
    }
}

fn npc_spawn_wander_radius(spawn: &super::region::NpcSpawn) -> u32 {
    let x_radius = (spawn.position.x - spawn.min_x)
        .abs()
        .max((spawn.position.x - spawn.max_x).abs());
    let y_radius = (spawn.position.y - spawn.min_y)
        .abs()
        .max((spawn.position.y - spawn.max_y).abs());
    x_radius.max(y_radius) as u32
}

fn game_object_from_spawn(spawn: &ObjectSpawn) -> GameObject {
    let obj_type = match spawn.object_type {
        ObjectType::Boundary => 1,
        ObjectType::Scenery | ObjectType::GroundDecoration => 0,
    };

    GameObject::new(spawn.object_id, spawn.position)
        .with_type(obj_type)
        .with_direction(spawn.direction)
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
    /// 12-bit slot index used in the wire protocol (1–4095).
    pub npc_index: u16,
    pub removed: bool,
    /// Tick at which the NPC died. While Some, the NPC stays `removed` until
    /// `current_tick >= death_tick + respawn_ticks`, then respawns at full HP
    /// at its `spawn_position`. Cleared back to None on respawn.
    pub death_tick: Option<u64>,
    /// Damage event that landed this tick. Drained into a SEND_UPDATE_NPC
    /// type-2 entry for viewers, then cleared at end-of-tick. Tuple is
    /// (damage, current_hp, max_hp).
    pub pending_hit: Option<(u8, u8, u8)>,
    /// Set to true on the tick the NPC moved one tile. The streaming layer
    /// encodes a "moved" update bit for known NPCs when this is true; cleared
    /// at the end of `World::tick()` after snapshots are taken.
    pub moved_this_tick: bool,
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
            npc_index: 0,
            removed: false,
            moved_this_tick: false,
            death_tick: None,
            pending_hit: None,
        }
    }

    pub fn tick(&mut self) {
        self.moved_this_tick = false;
        if self.in_combat || self.removed {
            return;
        }

        // Wander: ~25% chance per tick of stepping in a random cardinal/diagonal
        // direction, constrained to within `wander_radius` of `spawn_position`.
        // Mirrors the Java NpcWalk loop's "small random step" cadence — RSC NPCs
        // don't pathfind, they just bounce around their spawn tile.
        use rand::Rng;
        let mut rng = rand::thread_rng();
        if rng.gen_range(0..4) != 0 {
            return;
        }
        let dx: i32 = rng.gen_range(-1..=1);
        let dy: i32 = rng.gen_range(-1..=1);
        if dx == 0 && dy == 0 {
            return;
        }
        let next = Position::new(self.position.x + dx, self.position.y + dy);
        let within_x = (next.x - self.spawn_position.x).unsigned_abs() <= self.wander_radius;
        let within_y = (next.y - self.spawn_position.y).unsigned_abs() <= self.wander_radius;
        if within_x && within_y {
            self.direction = Direction::from_offset(dx, dy);
            self.position = next;
            self.moved_this_tick = true;
        }
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
    /// 0 = scenery (rocks, trees, signs); 1 = boundary (walls, doors, fences).
    /// Determines which streaming opcode the object goes through.
    pub obj_type: u8,
    /// Facing direction (0–7). Only meaningful for boundary objects.
    pub direction: u8,
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
            obj_type: 0,
            direction: 0,
        }
    }

    pub fn with_type(mut self, obj_type: u8) -> Self {
        self.obj_type = obj_type;
        self
    }

    pub fn with_direction(mut self, direction: u8) -> Self {
        self.direction = direction;
        self
    }

    pub fn deplete(&mut self, current_tick: u64) {
        self.active = false;
        self.respawn_tick = Some(current_tick + self.respawn_delay as u64);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::item::ItemId;
    use crate::game::region::{GroundItemSpawn, NpcSpawn, ObjectSpawn};
    use std::fs;

    #[test]
    fn apply_spawn_manager_adds_runtime_entities_without_clearing_seeded_state() {
        let mut world = World::new("test".to_string(), 2000);
        let seeded_npc = world.spawn_npc_at(95, Position::new(122, 645));
        let seeded_object_pos = Position::new(124, 647);
        world.game_objects.insert(
            seeded_object_pos,
            GameObject::new(64, seeded_object_pos).with_type(0),
        );
        let seeded_item_pos = Position::new(123, 648);
        world.drop_item(seeded_item_pos, GroundItem::new(10, 1));

        let mut spawns = SpawnManager::new();
        spawns.add_npc_spawn(NpcSpawn::with_bounds(
            401,
            Position::new(400, 20),
            398,
            404,
            18,
            21,
        ));
        spawns.add_object_spawn(ObjectSpawn::boundary(5, Position::new(401, 20), 2));
        spawns.add_ground_item_spawn(GroundItemSpawn::new(
            ItemId(20),
            42,
            Position::new(402, 20),
            30,
        ));

        let summary = world.apply_spawn_manager(&spawns);

        assert_eq!(
            summary,
            WorldSpawnApplySummary {
                npcs: 1,
                objects: 1,
                ground_items: 1,
            }
        );
        assert!(world.npcs.contains_key(&seeded_npc));
        assert!(world.game_objects.contains_key(&seeded_object_pos));
        assert_eq!(world.ground_items[&seeded_item_pos].len(), 1);

        let loaded_npc = world
            .npcs
            .values()
            .find(|npc| npc.definition_id == 401)
            .unwrap();
        assert_eq!(loaded_npc.position, Position::new(400, 20));
        assert_eq!(loaded_npc.spawn_position, Position::new(400, 20));
        assert_eq!(loaded_npc.wander_radius, 4);

        let object = world.game_objects.get(&Position::new(401, 20)).unwrap();
        assert_eq!(object.id, 5);
        assert_eq!(object.obj_type, 1);
        assert_eq!(object.direction, 2);

        let items = world.ground_items.get(&Position::new(402, 20)).unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].item_id, 20);
        assert_eq!(items[0].amount, 42);
        assert!(items[0].visible_to_all);
        assert_eq!(items[0].expire_tick, None);
    }

    #[test]
    fn apply_base_java_locs_dir_loads_and_applies_loc_family() {
        let temp_dir =
            std::env::temp_dir().join(format!("openrsc-world-locs-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&temp_dir);
        fs::create_dir_all(&temp_dir).unwrap();

        fs::write(
            temp_dir.join("NpcLocs.json"),
            r#"{"npclocs":[{"id":7,"start":{"X":10,"Y":11},"min":{"X":9,"Y":10},"max":{"X":12,"Y":13}}]}"#,
        )
        .unwrap();
        fs::write(
            temp_dir.join("SceneryLocs.json"),
            r#"{"sceneries":[{"id":70,"pos":{"X":20,"Y":21},"direction":1}]}"#,
        )
        .unwrap();
        fs::write(
            temp_dir.join("BoundaryLocs.json"),
            r#"{"boundaries":[{"id":5,"pos":{"X":22,"Y":23},"direction":3}]}"#,
        )
        .unwrap();
        fs::write(
            temp_dir.join("GroundItems.json"),
            r#"{"grounditems":[{"id":20,"pos":{"X":24,"Y":25},"amount":99,"respawn":30}]}"#,
        )
        .unwrap();

        let mut world = World::new("test".to_string(), 2000);
        let summary = world.apply_base_java_locs_dir(&temp_dir).unwrap();

        assert_eq!(
            summary,
            WorldSpawnApplySummary {
                npcs: 1,
                objects: 2,
                ground_items: 1,
            }
        );
        assert_eq!(world.npcs.len(), 1);
        assert!(world
            .npcs
            .values()
            .any(|npc| npc.definition_id == 7 && npc.position == Position::new(10, 11)));
        assert_eq!(world.game_objects[&Position::new(20, 21)].obj_type, 0);
        assert_eq!(world.game_objects[&Position::new(22, 23)].obj_type, 1);
        assert_eq!(world.ground_items[&Position::new(24, 25)][0].amount, 99);

        fs::remove_dir_all(&temp_dir).unwrap();
    }

    #[test]
    fn java_loc_collision_map_derives_boundary_blockers_from_loaded_world_objects() {
        let mut world = World::new("test".to_string(), 2000);
        let boundary_pos = Position::new(30, 30);
        world.game_objects.insert(
            boundary_pos,
            GameObject::new(1, boundary_pos)
                .with_type(1)
                .with_direction(0),
        );
        let scenery_pos = Position::new(32, 30);
        world.game_objects.insert(
            scenery_pos,
            GameObject::new(70, scenery_pos)
                .with_type(0)
                .with_direction(0),
        );

        let collision = world.java_loc_collision_map();

        assert!(!collision.can_move(boundary_pos, Position::new(30, 29)));
        assert!(!collision.can_move(Position::new(30, 29), boundary_pos));
        assert!(collision.can_move(Position::new(31, 30), scenery_pos));
    }

    #[test]
    fn movement_collision_policy_keeps_java_locs_opt_in() {
        let mut world = World::new("test".to_string(), 2000);
        let boundary_pos = Position::new(30, 30);
        world.game_objects.insert(
            boundary_pos,
            GameObject::new(1, boundary_pos)
                .with_type(1)
                .with_direction(0),
        );

        assert!(world.can_move_with_collision(
            boundary_pos,
            Position::new(30, 29),
            MovementCollisionPolicy::SeededRuntimeOnly,
        ));
        assert!(!world.can_move_with_collision(
            boundary_pos,
            Position::new(30, 29),
            MovementCollisionPolicy::JavaLocs,
        ));
    }

    #[test]
    fn movement_collision_map_includes_explicit_runtime_blockers_in_all_policies() {
        let mut world = World::new("test".to_string(), 2000);
        let blocked_pos = Position::new(40, 40);
        let mut blocking_object = GameObject::new(99, blocked_pos);
        blocking_object.blocks_movement = true;
        world.game_objects.insert(blocked_pos, blocking_object);

        for policy in [
            MovementCollisionPolicy::SeededRuntimeOnly,
            MovementCollisionPolicy::JavaLocs,
        ] {
            assert!(!world.can_move_with_collision(Position::new(39, 40), blocked_pos, policy,));
        }
    }
}
