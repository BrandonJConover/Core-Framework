//! Ground item system for items dropped in the world.
//! Handles item spawning, ownership, pickup, and despawning.

use std::collections::HashMap;
use std::time::{Duration, Instant};
use tracing::{debug, info, warn};

use super::entity::{EntityId, Position};
use super::item::ItemId;

/// Default time before item becomes visible to all players (in ticks).
const DEFAULT_OWNER_TIMEOUT: u32 = 100; // ~1 minute

/// Default time before item despawns (in ticks).
const DEFAULT_DESPAWN_TIME: u32 = 200; // ~2 minutes

/// Represents an item on the ground.
#[derive(Debug, Clone)]
pub struct GroundItem {
    /// Unique ground item ID.
    pub id: EntityId,
    /// Item catalog ID.
    pub item_id: ItemId,
    /// Stack amount.
    pub amount: u32,
    /// World position.
    pub position: Position,
    /// Owner player ID (if any).
    pub owner_id: Option<u64>,
    /// When the item was dropped.
    pub spawn_tick: u64,
    /// When owner visibility expires.
    pub owner_timeout_tick: u64,
    /// When the item despawns.
    pub despawn_tick: u64,
    /// Whether this is a respawning item.
    pub respawns: bool,
    /// Respawn delay in ticks.
    pub respawn_delay: u32,
}

impl GroundItem {
    /// Create a new ground item.
    pub fn new(
        id: EntityId,
        item_id: ItemId,
        amount: u32,
        position: Position,
        current_tick: u64,
    ) -> Self {
        Self {
            id,
            item_id,
            amount,
            position,
            owner_id: None,
            spawn_tick: current_tick,
            owner_timeout_tick: current_tick + DEFAULT_OWNER_TIMEOUT as u64,
            despawn_tick: current_tick + DEFAULT_DESPAWN_TIME as u64,
            respawns: false,
            respawn_delay: 0,
        }
    }

    /// Create a dropped item with an owner.
    pub fn dropped(
        id: EntityId,
        item_id: ItemId,
        amount: u32,
        position: Position,
        owner_id: u64,
        current_tick: u64,
    ) -> Self {
        let mut item = Self::new(id, item_id, amount, position, current_tick);
        item.owner_id = Some(owner_id);
        item
    }

    /// Create a respawning item (e.g., static world spawns).
    pub fn respawning(
        id: EntityId,
        item_id: ItemId,
        amount: u32,
        position: Position,
        respawn_delay: u32,
        current_tick: u64,
    ) -> Self {
        let mut item = Self::new(id, item_id, amount, position, current_tick);
        item.respawns = true;
        item.respawn_delay = respawn_delay;
        item.despawn_tick = u64::MAX; // Never despawn
        item
    }

    /// Check if item is visible to a player.
    pub fn visible_to(&self, player_id: u64, current_tick: u64) -> bool {
        // If no owner, visible to all
        if self.owner_id.is_none() {
            return true;
        }

        // Owner can always see
        if self.owner_id == Some(player_id) {
            return true;
        }

        // After timeout, visible to all
        current_tick >= self.owner_timeout_tick
    }

    /// Check if item can be picked up by a player.
    pub fn can_pickup(&self, player_id: u64, current_tick: u64) -> bool {
        self.visible_to(player_id, current_tick)
    }

    /// Check if item should despawn.
    pub fn should_despawn(&self, current_tick: u64) -> bool {
        !self.respawns && current_tick >= self.despawn_tick
    }

    /// Get the location key for spatial lookup.
    pub fn location_key(&self) -> (u16, u16) {
        (self.position.x, self.position.y)
    }
}

/// Manager for all ground items in the world.
#[derive(Debug, Default)]
pub struct GroundItemManager {
    /// All ground items by ID.
    items: HashMap<EntityId, GroundItem>,
    /// Items indexed by location for fast lookup.
    by_location: HashMap<(u16, u16), Vec<EntityId>>,
    /// Next entity ID for new items.
    next_id: u32,
    /// Current game tick.
    current_tick: u64,
    /// Items waiting to respawn.
    respawn_queue: Vec<(u64, GroundItem)>, // (respawn_tick, item_template)
}

impl GroundItemManager {
    /// Create a new ground item manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Get current tick.
    pub fn current_tick(&self) -> u64 {
        self.current_tick
    }

    /// Process a game tick.
    pub fn tick(&mut self) {
        self.current_tick += 1;

        // Process despawns
        let current = self.current_tick;
        let to_remove: Vec<EntityId> = self
            .items
            .iter()
            .filter(|(_, item)| item.should_despawn(current))
            .map(|(id, _)| *id)
            .collect();

        for id in to_remove {
            self.remove(id);
        }

        // Process respawns
        let mut respawned = Vec::new();
        let mut remaining = Vec::new();

        for (tick, template) in self.respawn_queue.drain(..) {
            if current >= tick {
                respawned.push(template);
            } else {
                remaining.push((tick, template));
            }
        }

        self.respawn_queue = remaining;

        for template in respawned {
            self.spawn_respawning(template);
        }
    }

    /// Generate next entity ID.
    fn next_entity_id(&mut self) -> EntityId {
        self.next_id += 1;
        EntityId(self.next_id)
    }

    /// Spawn a ground item.
    pub fn spawn(&mut self, item_id: ItemId, amount: u32, position: Position) -> EntityId {
        let id = self.next_entity_id();
        let item = GroundItem::new(id, item_id, amount, position, self.current_tick);
        self.add_item(item);
        id
    }

    /// Drop an item with owner.
    pub fn drop(
        &mut self,
        item_id: ItemId,
        amount: u32,
        position: Position,
        owner_id: u64,
    ) -> EntityId {
        let id = self.next_entity_id();
        let item = GroundItem::dropped(id, item_id, amount, position, owner_id, self.current_tick);
        debug!(
            "Player {} dropped {} x {} at {:?}",
            owner_id, amount, item_id.0, position
        );
        self.add_item(item);
        id
    }

    /// Register a respawning ground item.
    pub fn register_spawn(
        &mut self,
        item_id: ItemId,
        amount: u32,
        position: Position,
        respawn_delay: u32,
    ) -> EntityId {
        let id = self.next_entity_id();
        let item = GroundItem::respawning(
            id,
            item_id,
            amount,
            position,
            respawn_delay,
            self.current_tick,
        );
        info!(
            "Registered respawning item {} at {:?}",
            item_id.0, position
        );
        self.add_item(item);
        id
    }

    /// Internal add item.
    fn add_item(&mut self, item: GroundItem) {
        let id = item.id;
        let loc = item.location_key();

        self.items.insert(id, item);
        self.by_location.entry(loc).or_default().push(id);
    }

    /// Spawn from respawn template.
    fn spawn_respawning(&mut self, template: GroundItem) {
        let id = self.next_entity_id();
        let mut item = template;
        item.id = id;
        item.spawn_tick = self.current_tick;
        item.owner_id = None;
        item.owner_timeout_tick = self.current_tick;

        debug!("Respawned item {} at {:?}", item.item_id.0, item.position);
        self.add_item(item);
    }

    /// Get item by ID.
    pub fn get(&self, id: EntityId) -> Option<&GroundItem> {
        self.items.get(&id)
    }

    /// Get items at a location.
    pub fn at_location(&self, x: u16, y: u16) -> Vec<&GroundItem> {
        self.by_location
            .get(&(x, y))
            .map(|ids| ids.iter().filter_map(|id| self.items.get(id)).collect())
            .unwrap_or_default()
    }

    /// Get items visible to a player at a location.
    pub fn visible_at(&self, x: u16, y: u16, player_id: u64) -> Vec<&GroundItem> {
        let current = self.current_tick;
        self.at_location(x, y)
            .into_iter()
            .filter(|item| item.visible_to(player_id, current))
            .collect()
    }

    /// Pick up an item.
    pub fn pickup(&mut self, id: EntityId, player_id: u64) -> Option<(ItemId, u32)> {
        let current = self.current_tick;

        // Check if can pickup
        let can_pickup = self
            .items
            .get(&id)
            .map(|item| item.can_pickup(player_id, current))
            .unwrap_or(false);

        if !can_pickup {
            return None;
        }

        let item = self.items.get(&id)?;
        let result = (item.item_id, item.amount);

        // If respawning, queue for respawn
        if item.respawns {
            let respawn_tick = current + item.respawn_delay as u64;
            let template = item.clone();
            self.respawn_queue.push((respawn_tick, template));
        }

        self.remove(id);
        Some(result)
    }

    /// Remove an item from the world.
    pub fn remove(&mut self, id: EntityId) -> Option<GroundItem> {
        if let Some(item) = self.items.remove(&id) {
            let loc = item.location_key();
            if let Some(ids) = self.by_location.get_mut(&loc) {
                ids.retain(|&i| i != id);
            }
            Some(item)
        } else {
            None
        }
    }

    /// Get count of items in the world.
    pub fn count(&self) -> usize {
        self.items.len()
    }

    /// Get all items in an area.
    pub fn in_area(&self, x1: u16, y1: u16, x2: u16, y2: u16) -> Vec<&GroundItem> {
        self.items
            .values()
            .filter(|item| {
                let pos = &item.position;
                pos.x >= x1 && pos.x <= x2 && pos.y >= y1 && pos.y <= y2
            })
            .collect()
    }
}

/// Result of a pickup attempt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PickupResult {
    /// Successfully picked up.
    Success { item_id: ItemId, amount: u32 },
    /// Item doesn't exist.
    NotFound,
    /// Not visible to player yet.
    NotVisible,
    /// Player inventory is full.
    InventoryFull,
    /// Too far away.
    TooFar,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ground_item_visibility() {
        let item = GroundItem::dropped(
            EntityId(1),
            ItemId(10),
            100,
            Position { x: 100, y: 100, plane: 0 },
            42, // owner_id
            0,  // current_tick
        );

        // Owner can always see
        assert!(item.visible_to(42, 0));

        // Others cannot see initially
        assert!(!item.visible_to(99, 0));

        // After timeout, others can see
        assert!(item.visible_to(99, 150));
    }

    #[test]
    fn test_ground_item_manager() {
        let mut manager = GroundItemManager::new();

        // Spawn an item
        let id = manager.spawn(
            ItemId(10),
            100,
            Position { x: 100, y: 100, plane: 0 },
        );

        assert_eq!(manager.count(), 1);
        assert!(manager.get(id).is_some());

        // Items at location
        let items = manager.at_location(100, 100);
        assert_eq!(items.len(), 1);

        // Pickup
        let result = manager.pickup(id, 1);
        assert!(result.is_some());
        assert_eq!(manager.count(), 0);
    }

    #[test]
    fn test_respawning_item() {
        let mut manager = GroundItemManager::new();

        // Register respawning item
        let id = manager.register_spawn(
            ItemId(10),
            1,
            Position { x: 100, y: 100, plane: 0 },
            10, // respawn after 10 ticks
        );

        assert_eq!(manager.count(), 1);

        // Pickup
        manager.pickup(id, 1);
        assert_eq!(manager.count(), 0);

        // Tick until respawn
        for _ in 0..15 {
            manager.tick();
        }

        // Should have respawned
        assert_eq!(manager.count(), 1);
    }
}
