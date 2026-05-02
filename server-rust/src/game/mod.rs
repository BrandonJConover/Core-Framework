//! Game logic module for OpenRSC Rust server.
//! Contains game-specific logic like player management, world state, and game mechanics.

pub mod action;
pub mod achievement;
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
pub mod shop;
pub mod shop_handler;
pub mod skills;
pub mod social;
pub mod server;
pub mod smithing;
pub mod state_updater;
pub mod status_effect;
pub mod thieving;
pub mod trade;
pub mod trade_handler;
pub mod walking;
pub mod wilderness;
pub mod woodcutting;
pub mod world;

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

use npc::{DropEntry, DropTable, NpcDef, NpcManager};
use npc_behavior::{BehaviorEvent, NearbyPlayer, NpcBehaviorProcessor};
use world::GroundItem;

pub use player::Player;
pub use world::World;
pub use entity::{Entity, EntityId, Position};

/// Chebyshev (chessboard) distance — RSC's standard interaction metric.
#[inline]
fn chebyshev(a: Position, b: Position) -> u32 {
    let dx = (a.x - b.x).unsigned_abs();
    let dy = (a.y - b.y).unsigned_abs();
    dx.max(dy)
}

/// Radius within which a player is considered "nearby" to an NPC for
/// aggro and combat processing (larger than view distance so edge-of-view
/// aggro works correctly).
const NEARBY_RADIUS: u32 = 20;

/// Central game state manager.
/// Handles all game logic, player sessions, and world state.
pub struct GameState {
    worlds: HashMap<String, Arc<RwLock<World>>>,
    players: HashMap<u64, Arc<RwLock<Player>>>,
    next_entity_id: EntityId,
    tick_rate: u32,
    started: bool,
    /// Canonical NPC data — stats, HP, position, combat state.
    npc_manager: NpcManager,
    /// AI layer that drives NPC state machines each tick.
    npc_behavior: NpcBehaviorProcessor,
    /// Monotonic game tick counter used by the behavior pipeline.
    game_tick: u64,
}

impl GameState {
    pub fn new(tick_rate: u32) -> Self {
        Self {
            worlds: HashMap::new(),
            players: HashMap::new(),
            next_entity_id: EntityId(1),
            tick_rate,
            started: false,
            npc_manager: NpcManager::new(),
            npc_behavior: NpcBehaviorProcessor::new(),
            game_tick: 0,
        }
    }

    /// Initialize the game state with default worlds and NPC spawns.
    pub async fn initialize(&mut self) -> anyhow::Result<()> {
        info!("Initializing game state...");

        // Create default world
        let default_world = World::new("Main World".to_string(), 2000);
        self.worlds.insert(
            "main".to_string(),
            Arc::new(RwLock::new(default_world)),
        );

        // Register NPC definitions.
        self.seed_npc_definitions();

        // Spawn initial NPCs.
        self.seed_npc_spawns();

        info!(
            "Game state initialized: {} world(s), {} NPC(s)",
            self.worlds.len(),
            self.npc_manager.all().count(),
        );
        Ok(())
    }

    /// Populate the NPC definition registry.
    fn seed_npc_definitions(&mut self) {
        // Man / Woman — non-aggressive, low stats.
        self.npc_manager.add_definition(
            NpcDef::new(1, "Man").with_combat(2, 7, 1, 1, 1),
        );
        self.npc_manager.add_definition(
            NpcDef::new(2, "Woman").with_combat(2, 7, 1, 1, 1),
        );

        // Goblin — aggressive, drops bones + goblin mail.
        let mut goblin_def = NpcDef::new(62, "Goblin")
            .with_combat(7, 15, 5, 5, 5)
            .aggressive();
        goblin_def.wander_radius = 7;
        self.npc_manager.add_definition(goblin_def);
        let mut goblin_drops = DropTable::new();
        goblin_drops.add_always(DropEntry::new(526, 1, 1));   // bones (always)
        goblin_drops.add_drop(DropEntry::new(288, 1, 30));    // goblin mail
        goblin_drops.add_drop(DropEntry::new(1931, 1, 50));   // bread
        goblin_drops.add_drop(DropEntry::range(995, 1, 5, 80)); // coins
        self.npc_manager.set_drop_table(62, goblin_drops);

        // Skeleton — aggressive, moderate stats.
        let mut skeleton_def = NpcDef::new(21, "Skeleton")
            .with_combat(25, 40, 18, 18, 18)
            .aggressive();
        skeleton_def.respawn_time = 150;
        self.npc_manager.add_definition(skeleton_def);
        let mut skeleton_drops = DropTable::new();
        skeleton_drops.add_always(DropEntry::new(526, 1, 1)); // bones
        skeleton_drops.add_drop(DropEntry::range(995, 1, 20, 60)); // coins
        skeleton_drops.add_drop(DropEntry::new(1511, 1, 15)); // logs
        self.npc_manager.set_drop_table(21, skeleton_drops);

        // Guard — aggressive, stronger stats.
        self.npc_manager.add_definition(
            NpcDef::new(9, "Guard")
                .with_combat(21, 35, 15, 15, 15)
                .aggressive(),
        );
    }

    /// Spawn the initial population of NPCs at their home positions.
    fn seed_npc_spawns(&mut self) {
        // Lumbridge area Men
        for (x, y) in [(3222, 3218), (3218, 3225), (3230, 3210)] {
            self.spawn_npc(1, Position::new(x, y));
        }

        // Goblin village goblins
        for (x, y) in [
            (2956, 3503), (2960, 3506), (2964, 3500),
            (2952, 3510), (2958, 3497),
        ] {
            self.spawn_npc(62, Position::new(x, y));
        }

        // Stronghold skeletons
        for (x, y) in [(1861, 5234), (1865, 5238), (1870, 5230)] {
            self.spawn_npc(21, Position::new(x, y));
        }

        // Varrock guards
        for (x, y) in [(3224, 3489), (3229, 3491)] {
            self.spawn_npc(9, Position::new(x, y));
        }
    }

    /// Spawn a single NPC by definition id at the given position.
    /// Registers it with both `NpcManager` and `NpcBehaviorProcessor`.
    pub fn spawn_npc(&mut self, def_id: u32, position: Position) -> Option<EntityId> {
        let eid = self.npc_manager.spawn(def_id, position)?;
        if let Some(def) = self.npc_manager.get_definition(def_id) {
            self.npc_behavior.register(eid, def, position);
        }
        debug!("Spawned NPC def={} eid={:?} at {:?}", def_id, eid, position);
        Some(eid)
    }

    /// Despawn an NPC, removing it from both manager and behavior processor.
    pub fn despawn_npc(&mut self, eid: EntityId) {
        self.npc_manager.remove(eid);
        self.npc_behavior.unregister(eid);
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
    ///
    /// Returns a `Vec<BehaviorEvent>` so the caller (`ServerState::tick`)
    /// can dispatch any events that require session access (e.g. sending
    /// aggro notification packets to individual players).
    pub async fn tick(&mut self) -> Vec<BehaviorEvent> {
        self.game_tick += 1;
        let tick = self.game_tick;

        // --- Phase 1: World ticks (simple Npc wander/respawn in world.rs) ---
        for (_name, world) in &self.worlds {
            let mut world = world.write().await;
            world.tick().await;
        }

        // --- Phase 2: Player ticks ---
        for (_id, player) in &self.players {
            let mut player = player.write().await;
            player.tick().await;
        }

        // --- Phase 3: NPC behavior (aggro, wander AI, death/respawn) ---
        // Build nearby-player snapshot so the behavior processor can run aggro
        // checks without holding async locks during its synchronous processing.
        let nearby_players = self.build_nearby_players_map().await;

        let events = self
            .npc_behavior
            .process_tick(&mut self.npc_manager, tick, &nearby_players);

        // --- Phase 4: Handle events that need game-state writes (ground items).
        //     Events that need session access are forwarded to the caller.
        let mut pending = Vec::with_capacity(events.len());
        for event in events {
            match &event {
                BehaviorEvent::Aggroed { entity_id, target_id } => {
                    debug!(
                        tick,
                        npc = ?entity_id,
                        player = target_id,
                        "NPC aggroed player"
                    );
                    // Forward to ServerState so the player session can be notified.
                    pending.push(event);
                }
                BehaviorEvent::TargetLost { entity_id, target_id } => {
                    debug!(
                        tick,
                        npc = ?entity_id,
                        player = target_id,
                        "NPC lost combat target"
                    );
                    pending.push(event);
                }
                BehaviorEvent::Died { entity_id } => {
                    debug!(tick, npc = ?entity_id, "NPC died");
                    // Roll the drop table and spawn ground items in the world.
                    let drop_result = if let Some(npc) = self.npc_manager.get(*entity_id) {
                        let def_id = npc.def_id;
                        let position = npc.position;
                        if let Some(table) = self.npc_manager.get_drop_table(def_id) {
                            let drops = table.roll();
                            debug!(
                                tick,
                                npc = ?entity_id,
                                def = def_id,
                                drops = ?drops,
                                "NPC drop table rolled"
                            );
                            Some((position, drops))
                        } else {
                            None
                        }
                    } else {
                        None
                    };

                    // Spawn each dropped item in the world's ground-item map.
                    // roll() returns Vec<(item_id, amount, noted)>.
                    if let Some((position, drops)) = drop_result {
                        if let Some(world_arc) = self.worlds.get("Main World") {
                            let mut world = world_arc.write().await;
                            for (item_id, amount, _noted) in &drops {
                                let ground_item = GroundItem::new(*item_id, *amount)
                                    .with_owner(*entity_id, tick + 200);
                                world.drop_item(position, ground_item);
                                debug!(
                                    item = item_id,
                                    amount = amount,
                                    x = position.x,
                                    y = position.y,
                                    "Spawned ground item from NPC death"
                                );
                            }
                        }
                    }
                    pending.push(event);
                }
                BehaviorEvent::Respawned { entity_id } => {
                    debug!(tick, npc = ?entity_id, "NPC respawned");
                    pending.push(event);
                }
            }
        }

        pending
    }

    /// Build a `nearby_players` map keyed by NPC `EntityId`.
    ///
    /// For each NPC, collect the list of players within `NEARBY_RADIUS` tiles.
    /// This snapshot is taken while holding read locks and is then passed to the
    /// synchronous behavior processor so no async locks are held during AI logic.
    async fn build_nearby_players_map(&self) -> HashMap<EntityId, Vec<NearbyPlayer>> {
        // Snapshot all player positions up-front (one read-lock per player).
        struct PlayerSnapshot {
            id: u64,
            position: Position,
            combat_level: u32,
            in_combat: bool,
        }

        let mut snapshots = Vec::with_capacity(self.players.len());
        for (&id, arc) in &self.players {
            let p = arc.read().await;
            snapshots.push(PlayerSnapshot {
                id,
                position: p.position,
                combat_level: p.combat_level,
                in_combat: false, // TODO: expose p.in_combat when combat is wired
            });
        }

        // For each NPC, find players within NEARBY_RADIUS.
        let mut map: HashMap<EntityId, Vec<NearbyPlayer>> = HashMap::new();
        for npc in self.npc_manager.all() {
            if npc.is_dead() {
                continue;
            }
            let nearby: Vec<NearbyPlayer> = snapshots
                .iter()
                .filter(|ps| chebyshev(npc.position, ps.position) <= NEARBY_RADIUS)
                .map(|ps| NearbyPlayer {
                    entity_id: ps.id,
                    position: ps.position,
                    combat_level: ps.combat_level,
                    in_combat: ps.in_combat,
                })
                .collect();
            if !nearby.is_empty() {
                map.insert(npc.entity_id, nearby);
            }
        }
        map
    }

    /// Register a new player.
    pub async fn register_player(&mut self, player: Player) -> u64 {
        let player_id = player.id;
        let player = Arc::new(RwLock::new(player));
        self.players.insert(player_id, player);
        info!("Registered player {}", player_id);
        player_id
    }

    /// Register a player with an existing Arc.
    pub async fn register_player_arc(&mut self, player_id: u64, player: Arc<RwLock<Player>>) {
        self.players.insert(player_id, player);
        info!("Registered player {}", player_id);
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

    /// Borrow the NPC manager (read-only).
    pub fn npc_manager(&self) -> &NpcManager {
        &self.npc_manager
    }

    /// Borrow the NPC behavior processor.
    pub fn npc_behavior(&self) -> &NpcBehaviorProcessor {
        &self.npc_behavior
    }

    /// Mutably borrow the NPC behavior processor (for entering/exiting combat).
    pub fn npc_behavior_mut(&mut self) -> &mut NpcBehaviorProcessor {
        &mut self.npc_behavior
    }
}
