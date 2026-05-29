//! Game logic module for OpenRSC Rust server.
//! Contains game-specific logic like player management, world state, and game mechanics.

pub mod achievement;
pub mod action;
pub mod agility;
pub mod appearance;
pub mod auth;
pub mod bank;
pub mod bank_handler;
pub mod chat;
pub mod clan;
pub mod combat;
pub mod combat_event;
pub mod consumables;
pub mod content;
pub mod cooking;
pub mod crafting;
pub mod database;
pub mod death;
pub mod dialogue;
pub mod dialogue_handler;
pub mod drop_table;
pub mod duel;
pub mod entity;
pub mod equipment;
pub mod event;
pub mod fatigue;
pub mod firemaking;
pub mod fishing;
pub mod fletching;
pub mod game_object;
pub mod ground_item;
pub mod herblore;
pub mod inventory;
pub mod item;
pub mod item_use;
pub mod magic;
pub mod mining;
pub mod npc;
pub mod npc_behavior;
pub mod party;
pub mod pathfinding;
pub mod player;
pub mod poison;
pub mod prayer;
pub mod protocol;
pub mod quest;
pub mod quest_engine;
pub mod ranged;
pub mod region;
pub mod runecrafting;
pub mod server;
pub mod shop;
pub mod shop_handler;
pub mod skills;
pub mod smithing;
pub mod social;
pub mod state_updater;
pub mod status_effect;
pub mod thieving;
pub mod trade;
pub mod trade_handler;
pub mod walking;
pub mod wilderness;
pub mod woodcutting;
pub mod world;
pub mod world_loader;

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn};

pub use entity::{Entity, EntityId, Position};
pub use player::Player;
use world::load_java_object_collision_defs;
pub use world::World;

/// Environment variable that opts the main world into Java/OpenRSC loc spawns.
pub const JAVA_LOCS_DIR_ENV: &str = "OPENRSC__JAVA_LOCS_DIR";

/// Central game state manager.
/// Handles all game logic, player sessions, and world state.
pub struct GameState {
    worlds: HashMap<String, Arc<RwLock<World>>>,
    players: HashMap<u64, Arc<RwLock<Player>>>,
    next_entity_id: EntityId,
    tick_rate: u32,
    started: bool,
    /// Monotonically incrementing player slot index (wraps at 2000).
    next_player_index: u16,
    java_locs_dir: Option<PathBuf>,
}

impl GameState {
    pub fn new(tick_rate: u32) -> Self {
        Self {
            worlds: HashMap::new(),
            players: HashMap::new(),
            next_entity_id: EntityId(1),
            tick_rate,
            started: false,
            next_player_index: 1,
            java_locs_dir: std::env::var_os(JAVA_LOCS_DIR_ENV).map(PathBuf::from),
        }
    }

    /// Opt into Java/OpenRSC loc spawns for the main world at initialization.
    pub fn with_java_locs_dir<P: Into<PathBuf>>(mut self, locs_dir: P) -> Self {
        self.java_locs_dir = Some(locs_dir.into());
        self
    }

    /// Initialize the game state with default worlds.
    pub async fn initialize(&mut self) -> anyhow::Result<()> {
        info!("Initializing game state...");

        let mut default_world = Self::seeded_default_world();

        if let Some(locs_dir) = &self.java_locs_dir {
            let summary = default_world.apply_base_java_locs_dir(Path::new(locs_dir))?;
            info!(
                "Applied Java loc spawns from {}: {} NPCs, {} objects, {} ground items",
                locs_dir.display(),
                summary.npcs,
                summary.objects,
                summary.ground_items
            );
            let object_defs_path = locs_dir
                .parent()
                .map(|defs_dir| defs_dir.join("GameObjectDef.xml"));
            if let Some(object_defs_path) = object_defs_path {
                match load_java_object_collision_defs(&object_defs_path) {
                    Ok(object_defs) => {
                        let count = object_defs.len();
                        default_world.set_java_object_collision_defs(object_defs);
                        info!(
                            "Loaded {} Java object collision definitions from {}",
                            count,
                            object_defs_path.display()
                        );
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                        warn!(
                            "Java loc spawns configured without {}: scenery collision falls back to boundary-only Java loc collision",
                            object_defs_path.display()
                        );
                    }
                    Err(error) => return Err(error.into()),
                }
            }
        }

        self.worlds
            .insert("main".to_string(), Arc::new(RwLock::new(default_world)));

        info!("Game state initialized with {} world(s)", self.worlds.len());
        Ok(())
    }

    fn seeded_default_world() -> World {
        // Create default world and seed a handful of test NPCs near the
        // Lumbridge spawn (122, 647) so view-tracking has something to stream.
        // Definition IDs picked from RSC: 1=Man, 3=Goblin, 5=Chicken,
        // 95=Banker. The banker lets Java-compatible clients exercise the
        // authentic NPC_COMMAND -> Bank path before full world data lands.
        let mut default_world = World::new("Main World".to_string(), 2000);
        for (def_id, dx, dy) in [
            (1u32, 1i32, 0i32),   // Man
            (1u32, -1i32, 0i32),  // Man
            (3u32, 0i32, 1i32),   // Goblin
            (5u32, 2i32, -1i32),  // Chicken
            (95u32, 0i32, -2i32), // Banker
        ] {
            default_world.spawn_npc_at(def_id, entity::Position::new(122 + dx, 647 + dy));
        }
        info!(
            "Seeded {} test NPCs near Lumbridge spawn",
            default_world.npcs.len()
        );

        // Seed a handful of scenery + boundary objects so view streaming
        // has something to flush. IDs are RSC scenery defs; obj_type 0 =
        // scenery (rocks/trees), obj_type 1 = boundary (walls/doors).
        for (id, dx, dy, ty, dir) in [
            (1u32, 3i32, 0i32, 0u8, 0u8),  // tree (scenery)
            (1u32, -3i32, 0i32, 0u8, 0u8), // tree
            (4u32, 0i32, 3i32, 0u8, 0u8),  // sign post
            (64u32, 2i32, 0i32, 0u8, 0u8), // bank booth
            (5u32, 2i32, 2i32, 1u8, 0u8),  // wall (boundary, facing N)
            (5u32, -2i32, 2i32, 1u8, 2u8), // wall (boundary, facing E)
        ] {
            let pos = entity::Position::new(122 + dx, 647 + dy);
            let obj = world::GameObject::new(id, pos)
                .with_type(ty)
                .with_direction(dir);
            default_world.game_objects.insert(pos, obj);
        }
        info!(
            "Seeded {} game objects near Lumbridge spawn",
            default_world.game_objects.len()
        );

        // Seed a couple of ground items so the SEND_GROUND_ITEM_HANDLER path
        // has something to flush at login. RSC item ids: 10 = bones, 20 = coins.
        for (id, dx, dy, amt) in [
            (10u32, 1i32, 1i32, 1u32),   // bones
            (20u32, -1i32, -1i32, 5u32), // coins x5
        ] {
            let pos = entity::Position::new(122 + dx, 647 + dy);
            default_world
                .ground_items
                .entry(pos)
                .or_insert_with(Vec::new)
                .push(world::GroundItem::new(id, amt));
        }
        info!(
            "Seeded {} ground item piles near Lumbridge spawn",
            default_world
                .ground_items
                .values()
                .map(|v| v.len())
                .sum::<usize>()
        );

        default_world
    }

    /// Start the game loop.
    pub async fn start(&mut self) -> anyhow::Result<()> {
        if self.started {
            warn!("Game loop already started");
            return Ok(());
        }

        self.started = true;
        info!("Game loop started at {} ticks/second", self.tick_rate);
        Ok(())
    }

    /// Process a single game tick.
    pub async fn tick(&mut self) {
        // Process all worlds
        for (name, world) in &self.worlds {
            let mut world = world.write().await;
            world.tick().await;
        }

        // Process all players
        for (id, player) in &self.players {
            let mut player = player.write().await;
            player.tick().await;
        }
    }

    /// Register a new player.
    pub async fn register_player(&mut self, player: Player) -> u64 {
        let player_id = player.id;
        let player = Arc::new(RwLock::new(player));
        self.players.insert(player_id, player);
        info!("Registered player {}", player_id);
        player_id
    }

    /// Register a player with an existing Arc, assigning a slot index (1–2000).
    pub async fn register_player_arc(&mut self, player_id: u64, player: Arc<RwLock<Player>>) {
        let idx = self.next_player_index;
        self.next_player_index = (self.next_player_index % 2000) + 1;
        {
            let mut p = player.write().await;
            p.player_index = idx;
        }
        self.players.insert(player_id, player);
        info!("Registered player {} at slot {}", player_id, idx);
    }

    /// Return a snapshot of all players: (session_id, player_index, position, direction).
    pub fn player_snapshots(&self) -> Vec<Arc<RwLock<Player>>> {
        self.players.values().cloned().collect()
    }

    /// Remove a player from the game.
    pub async fn unregister_player(&mut self, player_id: u64) {
        if self.players.remove(&player_id).is_some() {
            info!("Unregistered player {}", player_id);
        }
    }

    /// Get a player by ID.
    pub fn get_player(&self, player_id: u64) -> Option<Arc<RwLock<Player>>> {
        self.players.get(&player_id).cloned()
    }

    /// Get a world by name.
    pub fn get_world(&self, name: &str) -> Option<Arc<RwLock<World>>> {
        self.worlds.get(name).cloned()
    }

    /// Get the next entity ID and increment the counter.
    pub fn next_entity_id(&mut self) -> EntityId {
        let id = self.next_entity_id;
        self.next_entity_id = EntityId(self.next_entity_id.0 + 1);
        id
    }

    /// Get online player count.
    pub fn online_count(&self) -> usize {
        self.players.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::{Mutex, OnceLock};

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    fn write_test_locs_dir(name: &str) -> PathBuf {
        let temp_dir = std::env::temp_dir().join(format!(
            "openrsc-game-state-locs-{name}-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&temp_dir);
        fs::create_dir_all(&temp_dir).unwrap();

        fs::write(
            temp_dir.join("NpcLocs.json"),
            r#"{"npclocs":[{"id":401,"start":{"X":413,"Y":11},"min":{"X":411,"Y":9},"max":{"X":413,"Y":12}}]}"#,
        )
        .unwrap();
        fs::write(
            temp_dir.join("SceneryLocs.json"),
            r#"{"sceneries":[{"id":70,"pos":{"X":389,"Y":2},"direction":0}]}"#,
        )
        .unwrap();
        fs::write(
            temp_dir.join("BoundaryLocs.json"),
            r#"{"boundaries":[{"id":1,"pos":{"X":424,"Y":18},"direction":1}]}"#,
        )
        .unwrap();
        fs::write(
            temp_dir.join("GroundItems.json"),
            r#"{"grounditems":[{"id":738,"pos":{"X":426,"Y":15},"amount":1,"respawn":30}]}"#,
        )
        .unwrap();

        temp_dir
    }

    #[tokio::test]
    async fn initialize_defaults_to_seeded_playable_area() {
        let _guard = env_lock().lock().unwrap();
        std::env::remove_var(JAVA_LOCS_DIR_ENV);

        let mut state = GameState::new(1);
        state.initialize().await.unwrap();

        let world = state.get_world("main").unwrap();
        let world = world.read().await;
        assert_eq!(world.npcs.len(), 5);
        assert_eq!(world.game_objects.len(), 6);
        assert_eq!(
            world
                .ground_items
                .values()
                .map(|items| items.len())
                .sum::<usize>(),
            2
        );
        assert!(world
            .npcs
            .values()
            .any(|npc| npc.definition_id == 95 && npc.position == entity::Position::new(122, 645)));
        assert!(world
            .game_objects
            .contains_key(&entity::Position::new(124, 647)));
    }

    #[tokio::test]
    async fn initialize_can_apply_java_locs_with_explicit_helper() {
        let locs_dir = write_test_locs_dir("explicit");

        let mut state = GameState::new(1).with_java_locs_dir(locs_dir.clone());
        state.initialize().await.unwrap();

        let world = state.get_world("main").unwrap();
        let world = world.read().await;
        assert_eq!(world.npcs.len(), 6);
        assert!(world
            .npcs
            .values()
            .any(|npc| npc.definition_id == 401 && npc.position == entity::Position::new(413, 11)));
        assert_eq!(world.game_objects[&entity::Position::new(389, 2)].id, 70);
        assert_eq!(
            world.game_objects[&entity::Position::new(424, 18)].obj_type,
            1
        );
        assert_eq!(
            world.ground_items[&entity::Position::new(426, 15)][0].item_id,
            738
        );

        fs::remove_dir_all(locs_dir).unwrap();
    }

    #[tokio::test]
    async fn initialize_loads_java_object_defs_next_to_locs_for_runtime_collision() {
        let base_dir =
            std::env::temp_dir().join(format!("openrsc-game-state-defs-{}", std::process::id()));
        let locs_dir = base_dir.join("locs");
        let _ = fs::remove_dir_all(&base_dir);
        fs::create_dir_all(&locs_dir).unwrap();

        fs::write(
            &base_dir.join("GameObjectDef.xml"),
            r#"<GameObjectDef-array>
  <GameObjectDef><type>0</type><width>1</width><height>1</height></GameObjectDef>
  <GameObjectDef><type>0</type><width>1</width><height>1</height></GameObjectDef>
  <GameObjectDef><type>0</type><width>1</width><height>1</height></GameObjectDef>
  <GameObjectDef><type>1</type><width>1</width><height>1</height></GameObjectDef>
</GameObjectDef-array>"#,
        )
        .unwrap();
        fs::write(locs_dir.join("NpcLocs.json"), r#"{"npclocs":[]}"#).unwrap();
        fs::write(
            locs_dir.join("SceneryLocs.json"),
            r#"{"sceneries":[{"id":3,"pos":{"X":426,"Y":15},"direction":0}]}"#,
        )
        .unwrap();
        fs::write(locs_dir.join("BoundaryLocs.json"), r#"{"boundaries":[]}"#).unwrap();
        fs::write(locs_dir.join("GroundItems.json"), r#"{"grounditems":[]}"#).unwrap();

        let mut state = GameState::new(1).with_java_locs_dir(locs_dir.clone());
        state.initialize().await.unwrap();

        let world = state.get_world("main").unwrap();
        let world = world.read().await;
        assert_eq!(world.java_object_collision_def_count(), 4);
        assert!(!world.can_move_with_collision(
            entity::Position::new(425, 15),
            entity::Position::new(426, 15),
            world::MovementCollisionPolicy::JavaLocs,
        ));

        fs::remove_dir_all(base_dir).unwrap();
    }

    #[tokio::test]
    async fn initialize_can_apply_java_locs_from_env() {
        let _guard = env_lock().lock().unwrap();
        let locs_dir = write_test_locs_dir("env");
        std::env::set_var(JAVA_LOCS_DIR_ENV, &locs_dir);

        let mut state = GameState::new(1);
        state.initialize().await.unwrap();
        std::env::remove_var(JAVA_LOCS_DIR_ENV);

        let world = state.get_world("main").unwrap();
        let world = world.read().await;
        assert!(world
            .npcs
            .values()
            .any(|npc| npc.definition_id == 401 && npc.position == entity::Position::new(413, 11)));
        assert!(world
            .ground_items
            .contains_key(&entity::Position::new(426, 15)));

        fs::remove_dir_all(locs_dir).unwrap();
    }
}
