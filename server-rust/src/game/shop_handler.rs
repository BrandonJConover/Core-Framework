//! Shop handler module for managing player-shop interactions.
//!
//! Provides session tracking, packet building, and dynamic pricing
//! for NPC vendor buy/sell operations.

use std::collections::HashMap;
use tracing::{debug, info};

use crate::protocol::opcodes::OpcodeOut;
use crate::protocol::{Packet, PacketBuilder};

use super::item::{ItemId, ItemRepository};
use super::shop::{Shop, ShopItem, ShopResult};

// ---------------------------------------------------------------------------
// Shop session
// ---------------------------------------------------------------------------

/// Tracks a player's currently-open shop interface.
#[derive(Debug, Clone)]
pub struct ShopSession {
    /// The numeric shop ID the player has open.
    pub shop_id: u32,
    /// The tick at which the shop was last restocked for this player.
    pub last_restock_tick: u64,
}

// ---------------------------------------------------------------------------
// Shop handler manager
// ---------------------------------------------------------------------------

/// Manages all shops and per-player shop sessions.
///
/// This sits *above* the raw `Shop` / `ShopManager` types defined in
/// `super::shop` and adds packet I/O plus dynamic-pricing adjustments.
#[derive(Debug)]
pub struct ShopHandler {
    /// All registered shops, keyed by numeric ID.
    shops: HashMap<u32, Shop>,
    /// Currently open shop sessions, keyed by player ID.
    player_shops: HashMap<u64, ShopSession>,
    /// Shared item repository for price lookups.
    item_repo: ItemRepository,
}

impl ShopHandler {
    /// Create a new handler with the given item repository.
    pub fn new(item_repo: ItemRepository) -> Self {
        Self {
            shops: HashMap::new(),
            player_shops: HashMap::new(),
            item_repo,
        }
    }

    // -- Shop registration --------------------------------------------------

    /// Register a shop definition.
    pub fn register_shop(&mut self, shop: Shop) {
        info!("ShopHandler: registered shop '{}' (ID {})", shop.name, shop.id);
        self.shops.insert(shop.id, shop);
    }

    /// Get a read-only reference to a shop.
    pub fn get_shop(&self, shop_id: u32) -> Option<&Shop> {
        self.shops.get(&shop_id)
    }

    /// Get a mutable reference to a shop.
    pub fn get_shop_mut(&mut self, shop_id: u32) -> Option<&mut Shop> {
        self.shops.get_mut(&shop_id)
    }

    // -- Session management --------------------------------------------------

    /// Open a shop for a player, returning the packets to send.
    pub fn open_shop(&mut self, player_id: u64, shop_id: u32, current_tick: u64) -> Result<Vec<Packet>, ShopHandlerError> {
        let shop = self.shops.get(&shop_id)
            .ok_or(ShopHandlerError::ShopNotFound)?;

        // Record session
        self.player_shops.insert(player_id, ShopSession {
            shop_id,
            last_restock_tick: current_tick,
        });

        debug!("Player {} opened shop {} ('{}')", player_id, shop_id, shop.name);

        Ok(vec![build_open_shop_packet(shop, &self.item_repo)])
    }

    /// Handle a player buying an item from their open shop.
    pub fn handle_buy(
        &mut self,
        player_id: u64,
        item_index: u16,
        amount: u32,
    ) -> Result<Vec<Packet>, ShopHandlerError> {
        let session = self.player_shops.get(&player_id)
            .ok_or(ShopHandlerError::NoOpenShop)?;
        let shop_id = session.shop_id;

        let shop = self.shops.get_mut(&shop_id)
            .ok_or(ShopHandlerError::ShopNotFound)?;

        let idx = item_index as usize;
        let item = shop.get_item_mut(idx)
            .ok_or(ShopHandlerError::Transaction(ShopResult::InvalidItem))?;

        if !item.in_stock() {
            return Err(ShopHandlerError::Transaction(ShopResult::OutOfStock));
        }

        let available = item.amount;
        if available < amount {
            return Err(ShopHandlerError::Transaction(ShopResult::InsufficientStock { available }));
        }

        // Calculate dynamic price *before* mutating stock
        let dynamic_price = calculate_dynamic_buy_price(item, &self.item_repo);

        // Decrease shop stock
        item.decrease_stock(amount);

        let total_cost = dynamic_price.saturating_mul(amount);
        debug!(
            "Player {} bought {}x item index {} for {} each (total {})",
            player_id, amount, item_index, dynamic_price, total_cost
        );

        // Re-borrow immutably for the update packet
        let shop = self.shops.get(&shop_id).unwrap();
        Ok(vec![build_shop_update_packet(shop, &self.item_repo)])
    }

    /// Handle a player selling an item to their open shop.
    pub fn handle_sell(
        &mut self,
        player_id: u64,
        item_id: ItemId,
        amount: u32,
    ) -> Result<Vec<Packet>, ShopHandlerError> {
        let session = self.player_shops.get(&player_id)
            .ok_or(ShopHandlerError::NoOpenShop)?;
        let shop_id = session.shop_id;

        let shop = self.shops.get_mut(&shop_id)
            .ok_or(ShopHandlerError::ShopNotFound)?;

        if !shop.will_buy(item_id, &self.item_repo) {
            return Err(ShopHandlerError::Transaction(ShopResult::WontBuy));
        }

        let sell_price = shop.calculate_sell_price(item_id, &self.item_repo)
            .ok_or(ShopHandlerError::Transaction(ShopResult::InvalidItem))?;

        // Increase shop stock (add to existing slot or create new)
        if let Some(idx) = shop.find_item(item_id) {
            shop.get_item_mut(idx).unwrap().increase_stock(amount);
        } else {
            // General stores accept items they don't normally stock
            let mut new_item = ShopItem::new(item_id, 0);
            new_item.increase_stock(amount);
            shop.add_item(new_item);
        }

        let total_value = sell_price.saturating_mul(amount);
        debug!(
            "Player {} sold {}x {:?} for {} each (total {})",
            player_id, amount, item_id, sell_price, total_value
        );

        let shop = self.shops.get(&shop_id).unwrap();
        Ok(vec![build_shop_update_packet(shop, &self.item_repo)])
    }

    /// Close a player's shop session.
    pub fn close_shop(&mut self, player_id: u64) -> Vec<Packet> {
        if self.player_shops.remove(&player_id).is_some() {
            debug!("Player {} closed shop", player_id);
        }
        vec![build_close_shop_packet()]
    }

    /// Check whether a player currently has a shop open.
    pub fn has_shop_open(&self, player_id: u64) -> bool {
        self.player_shops.contains_key(&player_id)
    }

    // -- Tick / restock ------------------------------------------------------

    /// Advance all shops by one tick, restocking as needed.
    pub fn tick(&mut self, _current_tick: u64) {
        for shop in self.shops.values_mut() {
            shop.tick();
        }
    }
}

// ---------------------------------------------------------------------------
// Dynamic pricing helpers
// ---------------------------------------------------------------------------

/// Calculate a buy price adjusted by current stock level.
///
/// When stock is *above* the base level the price drops (minimum 85% of
/// base).  When stock is *below* the base level the price rises (up to
/// 150% when completely out).
fn calculate_dynamic_buy_price(item: &ShopItem, item_repo: &ItemRepository) -> u32 {
    let base = item.buy_price(item_repo);
    if item.base_stock == 0 {
        return base;
    }

    let ratio_pct = (item.amount as u64 * 100) / item.base_stock as u64;

    let factor = if ratio_pct == 0 {
        150 // Out of stock -> 150 %
    } else if ratio_pct < 50 {
        130 // Low stock -> 130 %
    } else if ratio_pct <= 100 {
        100 // Normal
    } else if ratio_pct <= 200 {
        90 // Overstocked -> 90 %
    } else {
        85 // Very overstocked -> 85 %
    };

    let adjusted = (base as u64 * factor) / 100;
    // Ensure price is at least 1 coin
    adjusted.max(1) as u32
}

/// Calculate a sell price adjusted by current stock level.
///
/// Mirrors the dynamic buy-price logic -- overstocked items fetch less
/// when sold back.
fn calculate_dynamic_sell_price(item: &ShopItem, item_repo: &ItemRepository) -> u32 {
    let base = item.sell_price(item_repo);
    if item.base_stock == 0 {
        return base;
    }

    let ratio_pct = (item.amount as u64 * 100) / item.base_stock as u64;

    let factor = if ratio_pct > 200 {
        60 // Very overstocked -> 60 %
    } else if ratio_pct > 100 {
        80 // Overstocked -> 80 %
    } else {
        100 // Normal / understocked
    };

    let adjusted = (base as u64 * factor) / 100;
    adjusted.max(1) as u32
}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build the packet that opens the shop interface on the client.
///
/// Layout: opcode | item_count(u8) | is_general(u8)
///   then for each item: item_id(u16) | amount(u16) | buy_price(u32) | sell_price(u32)
pub fn build_open_shop_packet(shop: &Shop, item_repo: &ItemRepository) -> Packet {
    let items = shop.items();
    let mut builder = PacketBuilder::new(OpcodeOut::OpenShop as u8)
        .write_byte(items.len() as u8)
        .write_byte(if shop.is_general { 1 } else { 0 });

    for item in items {
        let buy = calculate_dynamic_buy_price(item, item_repo);
        let sell = calculate_dynamic_sell_price(item, item_repo);
        builder = builder
            .write_short(item.item_id.0 as u16)
            .write_short(item.amount as u16)
            .write_int(buy)
            .write_int(sell);
    }

    builder.build()
}

/// Build a shop-contents update packet (same layout, different semantic use).
pub fn build_shop_update_packet(shop: &Shop, item_repo: &ItemRepository) -> Packet {
    // Re-use the open-shop layout so the client can refresh its view.
    build_open_shop_packet(shop, item_repo)
}

/// Build the packet that closes the shop interface.
pub fn build_close_shop_packet() -> Packet {
    PacketBuilder::new(OpcodeOut::CloseInterface as u8).build()
}

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

/// Errors that can occur during shop handler operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ShopHandlerError {
    /// The requested shop does not exist.
    ShopNotFound,
    /// The player does not have a shop open.
    NoOpenShop,
    /// A transaction-level error from the underlying shop logic.
    Transaction(ShopResult),
}

impl std::fmt::Display for ShopHandlerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ShopNotFound => write!(f, "Shop not found"),
            Self::NoOpenShop => write!(f, "No shop is currently open"),
            Self::Transaction(r) => write!(f, "Shop transaction error: {:?}", r),
        }
    }
}

impl std::error::Error for ShopHandlerError {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn make_handler() -> ShopHandler {
        let repo = ItemRepository::new();
        let mut handler = ShopHandler::new(repo);

        // Register a small test shop
        let mut shop = Shop::new(1, "Test Shop");
        shop.add_stock(ItemId(10), 50); // Coins
        shop.add_stock(ItemId(66), 5);  // Bronze sword
        handler.register_shop(shop);

        // Register a general store
        let general = Shop::general_store(2, "General Store");
        handler.register_shop(general);

        handler
    }

    #[test]
    fn test_open_and_close_shop() {
        let mut handler = make_handler();

        let packets = handler.open_shop(1, 1, 0).unwrap();
        assert!(!packets.is_empty());
        assert!(handler.has_shop_open(1));

        let packets = handler.close_shop(1);
        assert!(!packets.is_empty());
        assert!(!handler.has_shop_open(1));
    }

    #[test]
    fn test_open_nonexistent_shop() {
        let mut handler = make_handler();
        assert!(matches!(
            handler.open_shop(1, 999, 0),
            Err(ShopHandlerError::ShopNotFound)
        ));
    }

    #[test]
    fn test_buy_item() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();

        let packets = handler.handle_buy(1, 0, 2).unwrap();
        assert!(!packets.is_empty());

        // Stock should have decreased
        let shop = handler.get_shop(1).unwrap();
        assert_eq!(shop.items()[0].amount, 48); // 50 - 2
    }

    #[test]
    fn test_buy_out_of_stock() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();

        let result = handler.handle_buy(1, 0, 999);
        assert!(matches!(
            result,
            Err(ShopHandlerError::Transaction(ShopResult::InsufficientStock { .. }))
        ));
    }

    #[test]
    fn test_sell_item() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();

        // Sell an item already stocked (Bronze sword ID 66)
        let packets = handler.handle_sell(1, ItemId(66), 3).unwrap();
        assert!(!packets.is_empty());

        let shop = handler.get_shop(1).unwrap();
        assert_eq!(shop.items()[1].amount, 8); // 5 + 3
    }

    #[test]
    fn test_sell_to_general_store() {
        let mut handler = make_handler();
        handler.open_shop(1, 2, 0).unwrap(); // General store

        // General stores should accept tradeable items
        let packets = handler.handle_sell(1, ItemId(10), 5);
        // Coins have a base_price > 0 so the general store will buy them
        assert!(packets.is_ok());
    }

    #[test]
    fn test_buy_without_open_shop() {
        let mut handler = make_handler();
        let result = handler.handle_buy(1, 0, 1);
        assert!(matches!(result, Err(ShopHandlerError::NoOpenShop)));
    }

    #[test]
    fn test_dynamic_pricing_low_stock() {
        let repo = ItemRepository::new();
        let mut item = ShopItem::new(ItemId(66), 10); // Bronze sword, base stock 10
        let normal_price = calculate_dynamic_buy_price(&item, &repo);

        // Reduce stock well below base
        item.amount = 1;
        let high_price = calculate_dynamic_buy_price(&item, &repo);
        assert!(high_price > normal_price, "Low stock should raise buy price");
    }

    #[test]
    fn test_dynamic_pricing_overstock() {
        let repo = ItemRepository::new();
        let mut item = ShopItem::new(ItemId(66), 10);
        let normal_price = calculate_dynamic_buy_price(&item, &repo);

        // Increase stock well above base
        item.amount = 30;
        let low_price = calculate_dynamic_buy_price(&item, &repo);
        assert!(low_price < normal_price, "Overstocked should lower buy price");
    }

    #[test]
    fn test_tick_restocks() {
        let mut handler = make_handler();

        // Drain stock
        handler.open_shop(1, 1, 0).unwrap();
        handler.handle_buy(1, 1, 3).unwrap(); // Buy 3 bronze swords (stock: 5 -> 2)

        let shop = handler.get_shop(1).unwrap();
        assert_eq!(shop.items()[1].amount, 2);

        // Tick many times to trigger restock (rate defaults to 100)
        for t in 0..200 {
            handler.tick(t);
        }

        let shop = handler.get_shop(1).unwrap();
        // Should have restocked towards base (5)
        assert!(shop.items()[1].amount > 2);
    }
}
