//! Game logic module for OpenRSC Rust server.
//! Contains game-specific logic like player management, world state, and game mechanics.

pub mod action;
pub mod bank;
pub mod combat;
pub mod entity;
pub mod equipment;
pub mod ground_item;
pub mod inventory;
pub mod item;
pub mod magic;
pub mod npc;
pub mod player;
pub mod prayer;
pub mod quest;
pub mod shop;
pub mod skills;
pub mod trade;
pub mod world;

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn};

pub use player::Player;
pub use world::World;
pub use entity::{Entity, EntityId, Position};

/// Central game state manager.
/// Handles all game logic, player sessions, and world state.
pub struct GameState {
    worlds: HashMap<String, Arc<RwLock<World>>>,
    players: HashMap<u64, Arc<RwLock<Player>>>,
    next_entity_id: EntityId,
    tick_rate: u32,
    started: bool,
}

impl GameState {
    pub fn new(tick_rate: u32) -> Self {
        Self {
            worlds: HashMap::new(),
            players: HashMap::new(),
            next_entity_id: EntityId(1),
            tick_rate,
            started: false,
        }
    }

    /// Initialize the game state with default worlds.
    pub async fn initialize(&mut self) -> anyhow::Result<()> {
        info!("Initializing game state...");

        // Create default world
        let default_world = World::new("Main World".to_string(), 2000);
        self.worlds.insert(
            "main".to_string(),
            Arc::new(RwLock::new(default_world)),
        );

        info!("Game state initialized with {} world(s)", self.worlds.len());
        Ok(())
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
