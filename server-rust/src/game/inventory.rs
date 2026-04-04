//! Player inventory management system.
//! Handles item storage, stacking, and slot management for player inventories.

use std::collections::HashMap;
use tracing::{debug, warn};

use super::item::{ItemDef, ItemId, ItemRepository};

/// Maximum inventory size for a player.
pub const MAX_INVENTORY_SIZE: usize = 30;

/// Represents an item stack in the inventory.
#[derive(Debug, Clone)]
pub struct InventoryItem {
    /// The item definition ID.
    pub item_id: ItemId,
    /// The quantity of items in this stack.
    pub amount: u32,
    /// Whether this item is noted (certificate form).
    pub noted: bool,
}

impl InventoryItem {
    /// Create a new inventory item.
    pub fn new(item_id: ItemId, amount: u32) -> Self {
        Self {
            item_id,
            amount,
            noted: false,
        }
    }

    /// Create a new noted (certificate) item.
    pub fn new_noted(item_id: ItemId, amount: u32) -> Self {
        Self {
            item_id,
            amount,
            noted: true,
        }
    }

    /// Check if this item can stack with another.
    pub fn can_stack_with(&self, other: &InventoryItem, item_repo: &ItemRepository) -> bool {
        if self.item_id != other.item_id || self.noted != other.noted {
            return false;
        }

        if let Some(def) = item_repo.get(self.item_id) {
            def.stackable || self.noted
        } else {
            false
        }
    }

    /// Get the total value of this item stack.
    pub fn total_value(&self, item_repo: &ItemRepository) -> u64 {
        if let Some(def) = item_repo.get(self.item_id) {
            def.base_price as u64 * self.amount as u64
        } else {
            0
        }
    }
}

/// Player inventory container.
#[derive(Debug, Clone)]
pub struct Inventory {
    /// Items stored in inventory slots.
    slots: Vec<Option<InventoryItem>>,
    /// Maximum capacity of the inventory.
    capacity: usize,
}

impl Default for Inventory {
    fn default() -> Self {
        Self::new(MAX_INVENTORY_SIZE)
    }
}

impl Inventory {
    /// Create a new inventory with the specified capacity.
    pub fn new(capacity: usize) -> Self {
        Self {
            slots: vec![None; capacity],
            capacity,
        }
    }

    /// Get the number of items currently in inventory.
    pub fn count(&self) -> usize {
        self.slots.iter().filter(|s| s.is_some()).count()
    }

    /// Get the number of free slots.
    pub fn free_slots(&self) -> usize {
        self.capacity - self.count()
    }

    /// Check if inventory is full.
    pub fn is_full(&self) -> bool {
        self.free_slots() == 0
    }

    /// Check if inventory is empty.
    pub fn is_empty(&self) -> bool {
        self.count() == 0
    }

    /// Get item at a specific slot.
    pub fn get(&self, slot: usize) -> Option<&InventoryItem> {
        self.slots.get(slot).and_then(|s| s.as_ref())
    }

    /// Get mutable item at a specific slot.
    pub fn get_mut(&mut self, slot: usize) -> Option<&mut InventoryItem> {
        self.slots.get_mut(slot).and_then(|s| s.as_mut())
    }

    /// Check if inventory contains a specific item.
    pub fn contains(&self, item_id: ItemId) -> bool {
        self.slots.iter().any(|s| {
            s.as_ref().map(|i| i.item_id == item_id).unwrap_or(false)
        })
    }

    /// Get total amount of a specific item in inventory.
    pub fn get_amount(&self, item_id: ItemId) -> u32 {
        self.slots
            .iter()
            .filter_map(|s| s.as_ref())
            .filter(|i| i.item_id == item_id)
            .map(|i| i.amount)
            .sum()
    }

    /// Find the first slot containing a specific item.
    pub fn find_slot(&self, item_id: ItemId) -> Option<usize> {
        self.slots.iter().position(|s| {
            s.as_ref().map(|i| i.item_id == item_id).unwrap_or(false)
        })
    }

    /// Find the first empty slot.
    pub fn find_empty_slot(&self) -> Option<usize> {
        self.slots.iter().position(|s| s.is_none())
    }

    /// Add an item to the inventory.
    /// Returns true if successful, false if inventory is full.
    pub fn add(&mut self, item: InventoryItem, item_repo: &ItemRepository) -> bool {
        let is_stackable = item_repo
            .get(item.item_id)
            .map(|d| d.stackable)
            .unwrap_or(false) || item.noted;

        if is_stackable {
            // Try to stack with existing items
            for slot in &mut self.slots {
                if let Some(existing) = slot {
                    if existing.item_id == item.item_id && existing.noted == item.noted {
                        existing.amount = existing.amount.saturating_add(item.amount);
                        debug!("Stacked {} x {} in inventory", item.amount, item.item_id.0);
                        return true;
                    }
                }
            }
        }

        // Find empty slot
        if let Some(empty_idx) = self.find_empty_slot() {
            self.slots[empty_idx] = Some(item.clone());
            debug!("Added {} x {} to inventory slot {}", item.amount, item.item_id.0, empty_idx);
            true
        } else {
            warn!("Inventory full, cannot add item {}", item.item_id.0);
            false
        }
    }

    /// Add an item by ID and amount.
    pub fn add_item(&mut self, item_id: ItemId, amount: u32, item_repo: &ItemRepository) -> bool {
        self.add(InventoryItem::new(item_id, amount), item_repo)
    }

    /// Remove a specific amount of an item from inventory.
    /// Returns the actual amount removed.
    pub fn remove(&mut self, item_id: ItemId, amount: u32, item_repo: &ItemRepository) -> u32 {
        let mut remaining = amount;
        let is_stackable = item_repo
            .get(item_id)
            .map(|d| d.stackable)
            .unwrap_or(false);

        for slot in &mut self.slots {
            if remaining == 0 {
                break;
            }

            if let Some(item) = slot {
                if item.item_id == item_id {
                    if item.amount <= remaining {
                        remaining -= item.amount;
                        *slot = None;
                    } else {
                        item.amount -= remaining;
                        remaining = 0;
                    }
                }
            }
        }

        let removed = amount - remaining;
        debug!("Removed {} x {} from inventory", removed, item_id.0);
        removed
    }

    /// Remove item from a specific slot.
    /// Returns the removed item, if any.
    pub fn remove_slot(&mut self, slot: usize) -> Option<InventoryItem> {
        if slot < self.slots.len() {
            self.slots[slot].take()
        } else {
            None
        }
    }

    /// Swap items between two slots.
    pub fn swap(&mut self, slot_a: usize, slot_b: usize) -> bool {
        if slot_a >= self.capacity || slot_b >= self.capacity {
            return false;
        }

        self.slots.swap(slot_a, slot_b);
        true
    }

    /// Move an item from one slot to another (insert mode).
    pub fn insert(&mut self, from: usize, to: usize) -> bool {
        if from >= self.capacity || to >= self.capacity || from == to {
            return false;
        }

        let item = self.slots[from].take();

        if from < to {
            for i in from..to {
                self.slots[i] = self.slots[i + 1].take();
            }
        } else {
            for i in (to + 1..=from).rev() {
                self.slots[i] = self.slots[i - 1].take();
            }
        }

        self.slots[to] = item;
        true
    }

    /// Get all items as a slice.
    pub fn items(&self) -> &[Option<InventoryItem>] {
        &self.slots
    }

    /// Calculate total inventory value.
    pub fn total_value(&self, item_repo: &ItemRepository) -> u64 {
        self.slots
            .iter()
            .filter_map(|s| s.as_ref())
            .map(|i| i.total_value(item_repo))
            .sum()
    }

    /// Clear the inventory.
    pub fn clear(&mut self) {
        self.slots.fill(None);
    }

    /// Get the capacity.
    pub fn capacity(&self) -> usize {
        self.capacity
    }
}

/// Inventory operation result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InventoryResult {
    /// Operation succeeded.
    Success,
    /// Inventory is full.
    Full,
    /// Not enough items to remove.
    InsufficientItems,
    /// Invalid slot specified.
    InvalidSlot,
    /// Item not found.
    NotFound,
}

/// Container type for various storage contexts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContainerType {
    /// Player inventory.
    Inventory,
    /// Player bank.
    Bank,
    /// Trade window.
    Trade,
    /// Shop inventory.
    Shop,
    /// Ground items.
    Ground,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_repo() -> ItemRepository {
        let mut repo = ItemRepository::new();
        repo.load_defaults();
        repo
    }

    #[test]
    fn test_inventory_add_remove() {
        let repo = test_repo();
        let mut inv = Inventory::new(30);

        // Add coins (stackable)
        assert!(inv.add_item(ItemId(10), 100, &repo));
        assert_eq!(inv.get_amount(ItemId(10)), 100);
        assert_eq!(inv.count(), 1);

        // Add more coins - should stack
        assert!(inv.add_item(ItemId(10), 50, &repo));
        assert_eq!(inv.get_amount(ItemId(10)), 150);
        assert_eq!(inv.count(), 1);

        // Remove some coins
        assert_eq!(inv.remove(ItemId(10), 75, &repo), 75);
        assert_eq!(inv.get_amount(ItemId(10)), 75);
    }

    #[test]
    fn test_inventory_non_stackable() {
        let repo = test_repo();
        let mut inv = Inventory::new(5);

        // Add bronze swords (non-stackable, id 1)
        for _ in 0..5 {
            assert!(inv.add_item(ItemId(1), 1, &repo));
        }

        // Inventory should be full
        assert!(inv.is_full());
        assert!(!inv.add_item(ItemId(1), 1, &repo));
    }

    #[test]
    fn test_inventory_swap() {
        let repo = test_repo();
        let mut inv = Inventory::new(10);

        inv.add_item(ItemId(1), 1, &repo);
        inv.add_item(ItemId(2), 1, &repo);

        assert_eq!(inv.get(0).unwrap().item_id, ItemId(1));
        assert_eq!(inv.get(1).unwrap().item_id, ItemId(2));

        inv.swap(0, 1);

        assert_eq!(inv.get(0).unwrap().item_id, ItemId(2));
        assert_eq!(inv.get(1).unwrap().item_id, ItemId(1));
    }
}
