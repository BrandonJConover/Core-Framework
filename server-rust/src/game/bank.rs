//! Banking system for player item storage.
//!
//! Provides a persistent storage system for player items with
//! deposit, withdrawal, and organization features.

use serde::{Deserialize, Serialize};
use tracing::debug;

/// Maximum number of different item types in bank.
pub const MAX_BANK_SLOTS: usize = 192;

/// Maximum number of a single stackable item.
pub const MAX_STACK_SIZE: u32 = i32::MAX as u32;

/// An item stored in the bank.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BankItem {
    pub item_id: u32,
    pub amount: u32,
}

impl BankItem {
    pub fn new(item_id: u32, amount: u32) -> Self {
        Self { item_id, amount }
    }
}

/// Player's bank storage.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bank {
    items: Vec<BankItem>,
    capacity: usize,
}

impl Bank {
    pub fn new() -> Self {
        Self::with_capacity(MAX_BANK_SLOTS)
    }

    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            items: Vec::with_capacity(capacity.min(MAX_BANK_SLOTS)),
            capacity,
        }
    }

    /// Get all items in the bank.
    pub fn items(&self) -> &[BankItem] {
        &self.items
    }

    /// Get the number of unique item types in bank.
    pub fn slot_count(&self) -> usize {
        self.items.len()
    }

    /// Get the bank capacity.
    pub fn capacity(&self) -> usize {
        self.capacity
    }

    /// Check if bank is full.
    pub fn is_full(&self) -> bool {
        self.items.len() >= self.capacity
    }

    /// Get remaining free slots.
    pub fn free_slots(&self) -> usize {
        self.capacity.saturating_sub(self.items.len())
    }

    /// Check if bank contains an item.
    pub fn contains(&self, item_id: u32) -> bool {
        self.items.iter().any(|i| i.item_id == item_id)
    }

    /// Get the amount of a specific item.
    pub fn get_amount(&self, item_id: u32) -> u32 {
        self.items.iter()
            .find(|i| i.item_id == item_id)
            .map(|i| i.amount)
            .unwrap_or(0)
    }

    /// Get an item by ID.
    pub fn get(&self, item_id: u32) -> Option<&BankItem> {
        self.items.iter().find(|i| i.item_id == item_id)
    }

    /// Get an item by slot index.
    pub fn get_by_slot(&self, slot: usize) -> Option<&BankItem> {
        self.items.get(slot)
    }

    /// Deposit an item into the bank.
    pub fn deposit(&mut self, item_id: u32, amount: u32) -> Result<(), BankError> {
        if amount == 0 {
            return Err(BankError::InvalidAmount);
        }

        // Check if item already exists in bank
        if let Some(existing) = self.items.iter_mut().find(|i| i.item_id == item_id) {
            let new_amount = existing.amount.saturating_add(amount);
            if new_amount > MAX_STACK_SIZE {
                return Err(BankError::StackOverflow);
            }
            existing.amount = new_amount;
            debug!("Deposited {} of item {} (now {})", amount, item_id, new_amount);
            return Ok(());
        }

        // New item - check capacity
        if self.is_full() {
            return Err(BankError::BankFull);
        }

        self.items.push(BankItem::new(item_id, amount));
        debug!("Deposited {} of new item {}", amount, item_id);
        Ok(())
    }

    /// Withdraw an item from the bank.
    pub fn withdraw(&mut self, item_id: u32, amount: u32) -> Result<u32, BankError> {
        if amount == 0 {
            return Err(BankError::InvalidAmount);
        }

        let pos = self.items.iter()
            .position(|i| i.item_id == item_id)
            .ok_or(BankError::ItemNotFound)?;

        let item = &mut self.items[pos];
        let withdrawn = amount.min(item.amount);

        if withdrawn >= item.amount {
            // Remove the item entirely
            self.items.remove(pos);
        } else {
            item.amount -= withdrawn;
        }

        debug!("Withdrew {} of item {} (had {})", withdrawn, item_id, withdrawn + self.get_amount(item_id));
        Ok(withdrawn)
    }

    /// Withdraw all of an item from the bank.
    pub fn withdraw_all(&mut self, item_id: u32) -> Result<u32, BankError> {
        let amount = self.get_amount(item_id);
        if amount == 0 {
            return Err(BankError::ItemNotFound);
        }
        self.withdraw(item_id, amount)
    }

    /// Swap two items' positions in the bank.
    pub fn swap(&mut self, slot1: usize, slot2: usize) -> Result<(), BankError> {
        if slot1 >= self.items.len() || slot2 >= self.items.len() {
            return Err(BankError::InvalidSlot);
        }
        self.items.swap(slot1, slot2);
        Ok(())
    }

    /// Insert an item at a specific slot (shift others down).
    pub fn insert_at(&mut self, slot: usize, item_id: u32) -> Result<(), BankError> {
        let current_pos = self.items.iter()
            .position(|i| i.item_id == item_id)
            .ok_or(BankError::ItemNotFound)?;

        if slot >= self.items.len() {
            return Err(BankError::InvalidSlot);
        }

        let item = self.items.remove(current_pos);
        self.items.insert(slot, item);
        Ok(())
    }

    /// Clear all items from the bank.
    pub fn clear(&mut self) {
        self.items.clear();
    }

    /// Search for items by ID prefix or name pattern.
    pub fn search(&self, item_ids: &[u32]) -> Vec<&BankItem> {
        self.items.iter()
            .filter(|i| item_ids.contains(&i.item_id))
            .collect()
    }
}

impl Default for Bank {
    fn default() -> Self {
        Self::new()
    }
}

/// Bank-related errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BankError {
    BankFull,
    ItemNotFound,
    InsufficientAmount,
    InvalidAmount,
    InvalidSlot,
    StackOverflow,
    BankClosed,
}

impl std::fmt::Display for BankError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::BankFull => write!(f, "Bank is full"),
            Self::ItemNotFound => write!(f, "Item not found in bank"),
            Self::InsufficientAmount => write!(f, "Insufficient amount"),
            Self::InvalidAmount => write!(f, "Invalid amount"),
            Self::InvalidSlot => write!(f, "Invalid bank slot"),
            Self::StackOverflow => write!(f, "Stack would exceed maximum"),
            Self::BankClosed => write!(f, "Bank is closed"),
        }
    }
}

impl std::error::Error for BankError {}

/// State of a player's bank session.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BankSessionState {
    Closed,
    Open,
}

/// Manages a player's bank session.
#[derive(Debug)]
pub struct BankSession {
    pub player_id: u64,
    pub state: BankSessionState,
    pub bank: Bank,
}

impl BankSession {
    pub fn new(player_id: u64, bank: Bank) -> Self {
        Self {
            player_id,
            state: BankSessionState::Closed,
            bank,
        }
    }

    /// Open the bank interface.
    pub fn open(&mut self) -> Result<(), BankError> {
        if self.state == BankSessionState::Open {
            return Ok(()); // Already open
        }
        self.state = BankSessionState::Open;
        debug!("Player {} opened bank", self.player_id);
        Ok(())
    }

    /// Close the bank interface.
    pub fn close(&mut self) {
        self.state = BankSessionState::Closed;
        debug!("Player {} closed bank", self.player_id);
    }

    /// Check if bank is open.
    pub fn is_open(&self) -> bool {
        self.state == BankSessionState::Open
    }

    /// Deposit item (only if bank is open).
    pub fn deposit(&mut self, item_id: u32, amount: u32) -> Result<(), BankError> {
        if !self.is_open() {
            return Err(BankError::BankClosed);
        }
        self.bank.deposit(item_id, amount)
    }

    /// Withdraw item (only if bank is open).
    pub fn withdraw(&mut self, item_id: u32, amount: u32) -> Result<u32, BankError> {
        if !self.is_open() {
            return Err(BankError::BankClosed);
        }
        self.bank.withdraw(item_id, amount)
    }
}

/// Manager for bank operations and NPC bank locations.
#[derive(Debug, Default)]
pub struct BankManager {
    /// NPC IDs that can be used for banking.
    bank_npcs: Vec<u32>,
    /// Object IDs that can be used for banking (bank booths).
    bank_objects: Vec<u32>,
}

impl BankManager {
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.initialize_banks();
        manager
    }

    fn initialize_banks(&mut self) {
        // Bank NPCs (Bankers)
        self.bank_npcs = vec![
            95,  // Banker
            224, // Banker
            268, // Gnome banker
            540, // Banker (Shantay)
            617, // Ghost banker
        ];

        // Bank booths/chests
        self.bank_objects = vec![
            64,   // Bank booth
            942,  // Bank chest
        ];
    }

    /// Check if an NPC is a banker.
    pub fn is_bank_npc(&self, npc_id: u32) -> bool {
        self.bank_npcs.contains(&npc_id)
    }

    /// Check if an object can be used for banking.
    pub fn is_bank_object(&self, object_id: u32) -> bool {
        self.bank_objects.contains(&object_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bank_deposit() {
        let mut bank = Bank::new();

        bank.deposit(100, 5).unwrap();
        assert_eq!(bank.get_amount(100), 5);

        bank.deposit(100, 10).unwrap();
        assert_eq!(bank.get_amount(100), 15);
    }

    #[test]
    fn test_bank_withdraw() {
        let mut bank = Bank::new();

        bank.deposit(100, 20).unwrap();

        let withdrawn = bank.withdraw(100, 5).unwrap();
        assert_eq!(withdrawn, 5);
        assert_eq!(bank.get_amount(100), 15);

        let withdrawn = bank.withdraw(100, 15).unwrap();
        assert_eq!(withdrawn, 15);
        assert_eq!(bank.get_amount(100), 0);
        assert!(!bank.contains(100));
    }

    #[test]
    fn test_bank_capacity() {
        let mut bank = Bank::with_capacity(3);

        bank.deposit(1, 10).unwrap();
        bank.deposit(2, 10).unwrap();
        bank.deposit(3, 10).unwrap();

        assert!(bank.is_full());
        assert!(matches!(bank.deposit(4, 10), Err(BankError::BankFull)));

        // But stacking should still work
        bank.deposit(1, 5).unwrap();
        assert_eq!(bank.get_amount(1), 15);
    }

    #[test]
    fn test_bank_swap() {
        let mut bank = Bank::new();

        bank.deposit(100, 5).unwrap();
        bank.deposit(200, 10).unwrap();
        bank.deposit(300, 15).unwrap();

        bank.swap(0, 2).unwrap();

        assert_eq!(bank.get_by_slot(0).unwrap().item_id, 300);
        assert_eq!(bank.get_by_slot(2).unwrap().item_id, 100);
    }

    #[test]
    fn test_bank_session() {
        let bank = Bank::new();
        let mut session = BankSession::new(1, bank);

        // Can't deposit when closed
        assert!(matches!(session.deposit(100, 5), Err(BankError::BankClosed)));

        session.open().unwrap();
        session.deposit(100, 5).unwrap();
        assert_eq!(session.bank.get_amount(100), 5);

        session.close();
        assert!(matches!(session.withdraw(100, 1), Err(BankError::BankClosed)));
    }
}
