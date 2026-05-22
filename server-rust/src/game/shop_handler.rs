//! Shop handler module for managing player-shop interactions.
//!
//! Provides session tracking, packet building, and dynamic pricing
//! for NPC vendor buy/sell operations.

use std::collections::HashMap;
use tracing::{debug, info};

use crate::protocol::opcodes::OpcodeOut;
use crate::protocol::{Packet, PacketBuilder, PacketReader};

use super::item::{ItemId, ItemRepository};
use super::player::{Inventory, Item as PlayerItem};
use super::shop::{Shop, ShopItem, ShopResult};

const COINS: ItemId = ItemId(10);

/// Java shop buy/sell request payload.
///
/// Custom/v235 and v203 encode shop item movement as:
/// `catalog_id(u16) | stock_amount(u16) | amount(u16)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ShopItemAmountRequest {
    pub item_id: ItemId,
    pub stock_amount: u32,
    pub amount: u32,
}

/// Result of a live shop transaction that also touched player inventory.
#[derive(Debug, Default)]
pub struct ShopLiveResult {
    /// Shop/interface packets to send after the operation.
    pub packets: Vec<Packet>,
    /// Whether the caller should refresh the player's inventory packet.
    pub inventory_changed: bool,
    /// Optional Java-style denial/update message for the player.
    pub message: Option<String>,
}

impl ShopItemAmountRequest {
    pub fn parse(packet: &Packet) -> Result<Self, ShopHandlerError> {
        let mut reader = PacketReader::new(packet);
        let item_id = reader
            .read_short()
            .map_err(|_| ShopHandlerError::MalformedPacket)?;
        let stock_amount = reader
            .read_short()
            .map_err(|_| ShopHandlerError::MalformedPacket)?;
        let amount = reader
            .read_short()
            .map_err(|_| ShopHandlerError::MalformedPacket)?;

        if reader.remaining() != 0 {
            return Err(ShopHandlerError::MalformedPacket);
        }

        Ok(Self {
            item_id: ItemId(item_id as u32),
            stock_amount: stock_amount as u32,
            amount: amount as u32,
        })
    }
}

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

    /// Create a handler preloaded with the small built-in shop catalog.
    pub fn with_default_shops(item_repo: ItemRepository) -> Self {
        let mut handler = Self::new(item_repo);
        handler.load_defaults();
        handler
    }

    // -- Shop registration --------------------------------------------------

    /// Register a shop definition.
    pub fn register_shop(&mut self, shop: Shop) {
        info!(
            "ShopHandler: registered shop '{}' (ID {})",
            shop.name, shop.id
        );
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

    /// Load the same minimal default shops currently available to the Rust game.
    pub fn load_defaults(&mut self) {
        self.register_shop(Shop::java_general_store(
            1,
            "Lumbridge General Store",
            false,
        ));

        self.register_shop(Shop::java_varrock_sword_shop(2, "Varrock Sword Shop"));

        self.register_shop(Shop::java_auburys_rune_shop(3, "Aubury's Rune Shop"));

        self.register_shop(Shop::java_wydins_food_store(4, "Wydin's Food Store"));

        self.register_shop(Shop::java_bobs_axes(5, "Bob's Axes"));

        self.register_shop(Shop::java_lowes_archery_store(6, "Lowe's Archery Store"));

        self.register_shop(Shop::java_brians_battle_axes(
            7,
            "Brian's Battle Axe Bazaar",
        ));

        self.register_shop(Shop::java_horviks_armoury_openpk(8, "Horvik's Armoury"));

        info!("ShopHandler loaded {} default shops", self.shops.len());
    }

    // -- Session management --------------------------------------------------

    /// Open a shop for a player, returning the packets to send.
    pub fn open_shop(
        &mut self,
        player_id: u64,
        shop_id: u32,
        current_tick: u64,
    ) -> Result<Vec<Packet>, ShopHandlerError> {
        let shop = self
            .shops
            .get(&shop_id)
            .ok_or(ShopHandlerError::ShopNotFound)?;

        // Record session
        self.player_shops.insert(
            player_id,
            ShopSession {
                shop_id,
                last_restock_tick: current_tick,
            },
        );

        debug!(
            "Player {} opened shop {} ('{}')",
            player_id, shop_id, shop.name
        );

        Ok(vec![build_open_shop_packet(shop, &self.item_repo)])
    }

    /// Handle a player buying an item from their open shop.
    pub fn handle_buy(
        &mut self,
        player_id: u64,
        item_index: u16,
        amount: u32,
    ) -> Result<Vec<Packet>, ShopHandlerError> {
        let session = self
            .player_shops
            .get(&player_id)
            .ok_or(ShopHandlerError::NoOpenShop)?;
        let shop_id = session.shop_id;

        let shop = self
            .shops
            .get_mut(&shop_id)
            .ok_or(ShopHandlerError::ShopNotFound)?;

        let idx = item_index as usize;
        let item_id = shop
            .items()
            .get(idx)
            .ok_or(ShopHandlerError::Transaction(ShopResult::InvalidItem))?;

        if !item_id.in_stock() {
            return Err(ShopHandlerError::Transaction(ShopResult::OutOfStock));
        }

        let available = item_id.amount;
        if available < amount {
            return Err(ShopHandlerError::Transaction(
                ShopResult::InsufficientStock { available },
            ));
        }

        let item_id = item_id.item_id;
        let total_cost = (0..amount)
            .map(|total_bought| {
                calculate_java_buy_price(shop, item_id, &self.item_repo, total_bought)
            })
            .fold(0u32, u32::saturating_add);

        // Decrease shop stock
        shop.get_item_mut(idx).unwrap().decrease_stock(amount);

        debug!(
            "Player {} bought {}x item index {} (total {})",
            player_id, amount, item_index, total_cost
        );

        // Re-borrow immutably for the update packet
        let shop = self.shops.get(&shop_id).unwrap();
        Ok(vec![build_shop_update_packet(shop, &self.item_repo)])
    }

    /// Handle a Java shop-buy request, which addresses items by catalog ID.
    pub fn handle_buy_request(
        &mut self,
        player_id: u64,
        request: ShopItemAmountRequest,
    ) -> Result<Vec<Packet>, ShopHandlerError> {
        if request.amount == 0 {
            return Ok(Vec::new());
        }

        let session = self
            .player_shops
            .get(&player_id)
            .ok_or(ShopHandlerError::NoOpenShop)?;
        let shop = self
            .shops
            .get(&session.shop_id)
            .ok_or(ShopHandlerError::ShopNotFound)?;
        let item_index = shop
            .find_item(request.item_id)
            .ok_or(ShopHandlerError::Transaction(ShopResult::InvalidItem))?;

        self.handle_buy(player_id, item_index as u16, request.amount)
    }

    /// Handle a player selling an item to their open shop.
    pub fn handle_sell(
        &mut self,
        player_id: u64,
        item_id: ItemId,
        amount: u32,
    ) -> Result<Vec<Packet>, ShopHandlerError> {
        let session = self
            .player_shops
            .get(&player_id)
            .ok_or(ShopHandlerError::NoOpenShop)?;
        let shop_id = session.shop_id;

        let shop = self
            .shops
            .get_mut(&shop_id)
            .ok_or(ShopHandlerError::ShopNotFound)?;

        if !shop.will_buy(item_id, &self.item_repo) {
            return Err(ShopHandlerError::Transaction(ShopResult::WontBuy));
        }

        let total_value = (1..=amount)
            .map(|total_removed| {
                calculate_java_sell_price(shop, item_id, &self.item_repo, total_removed)
            })
            .fold(0u32, u32::saturating_add);

        // Increase shop stock (add to existing slot or create new)
        if let Some(idx) = shop.find_item(item_id) {
            shop.get_item_mut(idx).unwrap().increase_stock(amount);
        } else {
            // General stores accept items they don't normally stock
            let mut new_item = ShopItem::new(item_id, 0);
            new_item.increase_stock(amount);
            shop.add_item(new_item);
        }

        debug!(
            "Player {} sold {}x {:?} (total {})",
            player_id, amount, item_id, total_value
        );

        let shop = self.shops.get(&shop_id).unwrap();
        Ok(vec![build_shop_update_packet(shop, &self.item_repo)])
    }

    /// Handle a Java shop-sell request, which uses the same payload as buy.
    pub fn handle_sell_request(
        &mut self,
        player_id: u64,
        request: ShopItemAmountRequest,
    ) -> Result<Vec<Packet>, ShopHandlerError> {
        if request.amount == 0 {
            return Ok(Vec::new());
        }

        self.handle_sell(player_id, request.item_id, request.amount)
    }

    /// Handle a Java buy request and apply the visible player-side inventory
    /// movement for the live server adapter.
    pub fn handle_buy_request_with_inventory(
        &mut self,
        player_id: u64,
        request: ShopItemAmountRequest,
        inventory: &mut Inventory,
    ) -> Result<ShopLiveResult, ShopHandlerError> {
        if request.amount == 0 {
            return Ok(ShopLiveResult::default());
        }

        let (item_index, item_id, currency, total_cost) = {
            let session = self
                .player_shops
                .get(&player_id)
                .ok_or(ShopHandlerError::NoOpenShop)?;
            let shop = self
                .shops
                .get(&session.shop_id)
                .ok_or(ShopHandlerError::ShopNotFound)?;
            let item_index = shop
                .find_item(request.item_id)
                .ok_or(ShopHandlerError::Transaction(ShopResult::InvalidItem))?;
            let item = shop
                .items()
                .get(item_index)
                .ok_or(ShopHandlerError::Transaction(ShopResult::InvalidItem))?;

            if item.amount == 0 {
                return Err(ShopHandlerError::Transaction(ShopResult::OutOfStock));
            }
            if item.amount < request.amount {
                return Err(ShopHandlerError::Transaction(
                    ShopResult::InsufficientStock {
                        available: item.amount,
                    },
                ));
            }

            (
                item_index,
                item.item_id,
                shop.currency,
                (0..request.amount)
                    .map(|total_bought| {
                        calculate_java_buy_price(shop, item.item_id, &self.item_repo, total_bought)
                    })
                    .fold(0u32, u32::saturating_add),
            )
        };

        let available = inventory.count(currency.0);
        if available < total_cost {
            return Err(ShopHandlerError::Transaction(
                ShopResult::InsufficientFunds {
                    required: total_cost,
                    available,
                },
            ));
        }

        if !inventory_can_receive(&self.item_repo, inventory, item_id, request.amount) {
            return Err(ShopHandlerError::Transaction(ShopResult::InventoryFull));
        }

        if total_cost > 0 && inventory.remove_amount(currency.0, total_cost) != total_cost {
            return Err(ShopHandlerError::Transaction(
                ShopResult::InsufficientFunds {
                    required: total_cost,
                    available,
                },
            ));
        }

        let packets = self.handle_buy(player_id, item_index as u16, request.amount)?;
        // TODO(parity): once authentic item definitions/notes are wired, add
        // per-item stack/cert handling instead of this repository-backed flag.
        if !inventory.add(player_item_for(&self.item_repo, item_id, request.amount)) {
            if total_cost > 0 {
                let _ = inventory.add(player_item_for(&self.item_repo, currency, total_cost));
            }
            return Err(ShopHandlerError::Transaction(ShopResult::InventoryFull));
        }

        Ok(ShopLiveResult {
            packets,
            inventory_changed: true,
            message: None,
        })
    }

    /// Handle a Java sell request and apply the visible player-side inventory
    /// movement for the live server adapter.
    pub fn handle_sell_request_with_inventory(
        &mut self,
        player_id: u64,
        request: ShopItemAmountRequest,
        inventory: &mut Inventory,
    ) -> Result<ShopLiveResult, ShopHandlerError> {
        if request.amount == 0 {
            return Ok(ShopLiveResult::default());
        }

        let currency = {
            let session = self
                .player_shops
                .get(&player_id)
                .ok_or(ShopHandlerError::NoOpenShop)?;
            let shop = self
                .shops
                .get(&session.shop_id)
                .ok_or(ShopHandlerError::ShopNotFound)?;

            if !shop.will_buy(request.item_id, &self.item_repo) {
                return Err(ShopHandlerError::Transaction(ShopResult::WontBuy));
            }

            shop.currency
        };

        let amount = request.amount.min(inventory.count(request.item_id.0));
        if amount == 0 {
            return Ok(ShopLiveResult::default());
        }

        let total_value = {
            let session = self
                .player_shops
                .get(&player_id)
                .ok_or(ShopHandlerError::NoOpenShop)?;
            let shop = self
                .shops
                .get(&session.shop_id)
                .ok_or(ShopHandlerError::ShopNotFound)?;
            (1..=amount)
                .map(|total_removed| {
                    calculate_java_sell_price(shop, request.item_id, &self.item_repo, total_removed)
                })
                .fold(0u32, u32::saturating_add)
        };

        let removed = inventory.remove_amount(request.item_id.0, amount);
        if removed == 0 {
            return Ok(ShopLiveResult::default());
        }

        let packets = self.handle_sell(player_id, request.item_id, removed)?;
        if total_value > 0 {
            let _ = inventory.add(player_item_for(&self.item_repo, currency, total_value));
        }

        Ok(ShopLiveResult {
            packets,
            inventory_changed: true,
            message: None,
        })
    }

    /// Close a player's shop session.
    pub fn close_shop(&mut self, player_id: u64) -> Vec<Packet> {
        if self.player_shops.remove(&player_id).is_some() {
            debug!("Player {} closed shop", player_id);
        }
        vec![build_close_shop_packet()]
    }

    /// Clear a player's shop session without sending interface packets.
    pub fn on_logout(&mut self, player_id: u64) {
        self.player_shops.remove(&player_id);
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

fn calculate_java_buy_price(
    shop: &Shop,
    item_id: ItemId,
    item_repo: &ItemRepository,
    total_bought: u32,
) -> u32 {
    let base = item_repo
        .get(item_id)
        .map(|def| def.base_price)
        .unwrap_or(1);
    shop.calculate_java_buy_price(item_id, base, total_bought, false)
}

fn calculate_java_sell_price(
    shop: &Shop,
    item_id: ItemId,
    item_repo: &ItemRepository,
    total_removed: u32,
) -> u32 {
    let base = item_repo
        .get(item_id)
        .map(|def| def.base_price)
        .unwrap_or(1);
    shop.calculate_java_sell_price(item_id, base, total_removed, false)
}

fn inventory_can_receive(
    item_repo: &ItemRepository,
    inventory: &Inventory,
    item_id: ItemId,
    amount: u32,
) -> bool {
    if amount == 0 {
        return true;
    }

    let stackable = item_repo
        .get(item_id)
        .map(|def| def.stackable)
        .unwrap_or(false);
    if stackable && inventory.count(item_id.0) > 0 {
        return true;
    }

    // TODO(parity): classic RSC has richer stack/certificate behavior. The
    // current Rust inventory stores an amount on each slot, so one free slot is
    // enough for this adapter slice.
    inventory.free_slots() > 0
}

fn player_item_for(item_repo: &ItemRepository, item_id: ItemId, amount: u32) -> PlayerItem {
    let stackable = item_repo
        .get(item_id)
        .map(|def| def.stackable)
        .unwrap_or(false);
    if stackable {
        PlayerItem::stackable(item_id.0, amount)
    } else {
        PlayerItem::new(item_id.0, amount)
    }
}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build the packet that opens the shop interface on the client.
///
/// Layout: opcode | item_count(u8) | is_general(u8) | sell_modifier(u8)
///   | buy_modifier(u8) | stock_sensitivity(u8)
///   then for each item: item_id(u16) | amount(u16) | base_amount(u16)
pub fn build_open_shop_packet(shop: &Shop, _item_repo: &ItemRepository) -> Packet {
    let items = shop.items();
    let mut builder = PacketBuilder::new(OpcodeOut::OpenShop.wire())
        .write_byte(items.len() as u8)
        .write_byte(if shop.is_general { 1 } else { 0 })
        .write_byte(shop.sell_modifier)
        .write_byte(shop.buy_modifier)
        .write_byte(shop.price_modifier);

    for item in items {
        builder = builder
            .write_short(item.item_id.0 as u16)
            .write_short(item.amount as u16)
            .write_short(item.base_stock as u16);
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
    PacketBuilder::new(OpcodeOut::CloseInterface.wire()).build()
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
    /// The client packet did not match the Java shop payload shape.
    MalformedPacket,
}

impl std::fmt::Display for ShopHandlerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ShopNotFound => write!(f, "Shop not found"),
            Self::NoOpenShop => write!(f, "No shop is currently open"),
            Self::Transaction(r) => write!(f, "Shop transaction error: {:?}", r),
            Self::MalformedPacket => write!(f, "Malformed shop packet"),
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
        shop.add_stock(ItemId(66), 5); // Bronze sword
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
    fn test_open_shop_packet_uses_java_custom_layout() {
        let repo = ItemRepository::new();
        let mut shop = Shop::general_store(7, "General Store").with_modifiers(40, 130, 3);
        shop.add_stock(ItemId(156), 5);
        shop.get_item_mut(0).unwrap().decrease_stock(2);

        let packet = build_open_shop_packet(&shop, &repo);

        assert_eq!(packet.opcode, OpcodeOut::SEND_SHOP_OPEN.wire());
        assert_eq!(
            packet.payload.as_ref(),
            &[1, 1, 40, 130, 3, 0, 156, 0, 3, 0, 5]
        );
    }

    #[test]
    fn test_default_general_store_matches_java_catalog_packet() {
        let handler = ShopHandler::with_default_shops(ItemRepository::new());
        let shop = handler.get_shop(1).unwrap();
        let packet = build_open_shop_packet(shop, &ItemRepository::new());

        assert_eq!(shop.restock_rate, 12_400);
        assert_eq!(
            packet.payload.as_ref(),
            &[
                7, 1, 40, 130, 3, // count, general, sell, buy, price modifier
                0, 156, 0, 3, 0, 3, // pot
                0, 140, 0, 2, 0, 2, // jug
                0, 135, 0, 2, 0, 2, // shears
                0, 166, 0, 2, 0, 2, // bucket
                0, 167, 0, 2, 0, 2, // tinderbox
                0, 168, 0, 2, 0, 2, // chisel
                0, 169, 0, 5, 0, 5, // hammer
            ]
        );
    }

    #[test]
    fn test_default_aubury_shop_matches_java_catalog_packet() {
        let handler = ShopHandler::with_default_shops(ItemRepository::new());
        let shop = handler.get_shop(3).unwrap();
        let packet = build_open_shop_packet(shop, &ItemRepository::new());

        assert_eq!(shop.restock_rate, 3_000);
        assert_eq!(
            packet.payload.as_ref(),
            &[
                6, 0, 70, 100, 2, // count, specialty, sell, buy, price modifier
                0, 31, 0, 50, 0, 50, // fire rune
                0, 32, 0, 50, 0, 50, // water rune
                0, 33, 0, 50, 0, 50, // air rune
                0, 34, 0, 50, 0, 50, // earth rune
                0, 35, 0, 50, 0, 50, // mind rune
                0, 36, 0, 50, 0, 50, // body rune
            ]
        );
    }

    #[test]
    fn test_default_varrock_sword_shop_matches_java_catalog_packet() {
        let handler = ShopHandler::with_default_shops(ItemRepository::new());
        let shop = handler.get_shop(2).unwrap();
        let packet = build_open_shop_packet(shop, &ItemRepository::new());

        assert_eq!(shop.restock_rate, 30_000);
        assert_eq!(
            packet.payload.as_ref(),
            &[
                18, 0, 60, 100, 2, // count, specialty, sell, buy, price modifier
                0, 66, 0, 5, 0, 5, // bronze short sword
                0, 1, 0, 4, 0, 4, // iron short sword
                0, 67, 0, 4, 0, 4, // steel short sword
                1, 168, 0, 3, 0, 3, // black short sword
                0, 68, 0, 3, 0, 3, // mithril short sword
                0, 69, 0, 2, 0, 2, // adamantite short sword
                0, 70, 0, 4, 0, 4, // bronze long sword
                0, 71, 0, 3, 0, 3, // iron long sword
                0, 72, 0, 3, 0, 3, // steel long sword
                1, 169, 0, 2, 0, 2, // black long sword
                0, 73, 0, 2, 0, 2, // mithril long sword
                0, 74, 0, 1, 0, 1, // adamantite long sword
                0, 62, 0, 10, 0, 10, // bronze dagger
                0, 28, 0, 6, 0, 6, // iron dagger
                0, 63, 0, 5, 0, 5, // steel dagger
                1, 167, 0, 4, 0, 4, // black dagger
                0, 64, 0, 3, 0, 3, // mithril dagger
                0, 65, 0, 2, 0, 2, // adamantite dagger
            ]
        );
    }

    #[test]
    fn test_default_wydins_food_store_matches_java_catalog_packet() {
        let handler = ShopHandler::with_default_shops(ItemRepository::new());
        let shop = handler.get_shop(4).unwrap();
        let packet = build_open_shop_packet(shop, &ItemRepository::new());

        assert_eq!(shop.restock_rate, 12_500);
        assert_eq!(
            packet.payload.as_ref(),
            &[
                10, 0, 70, 100, 1, // count, specialty, sell, buy, price modifier
                0, 136, 0, 3, 0, 3, // pot of flour
                0, 133, 0, 1, 0, 1, // raw chicken
                0, 18, 0, 3, 0, 3, // cabbage
                0, 249, 0, 3, 0, 3, // banana
                0, 236, 0, 1, 0, 1, // redberries
                0, 138, 0, 0, 0, 0, // bread
                1, 81, 0, 1, 0, 1, // chocolate bar
                1, 63, 0, 3, 0, 3, // cheese
                1, 64, 0, 3, 0, 3, // tomato
                1, 92, 0, 1, 0, 1, // potato
            ]
        );
    }

    #[test]
    fn test_default_bobs_axes_matches_java_catalog_packet() {
        let handler = ShopHandler::with_default_shops(ItemRepository::new());
        let shop = handler.get_shop(5).unwrap();
        let packet = build_open_shop_packet(shop, &ItemRepository::new());

        assert_eq!(shop.restock_rate, 15_000);
        assert_eq!(
            packet.payload.as_ref(),
            &[
                7, 0, 60, 100, 2, // count, specialty, sell, buy, price modifier
                0, 156, 0, 5, 0, 5, // bronze pickaxe
                0, 87, 0, 10, 0, 10, // bronze axe
                0, 12, 0, 5, 0, 5, // iron axe
                0, 88, 0, 3, 0, 3, // steel axe
                0, 89, 0, 5, 0, 5, // iron battle axe
                0, 90, 0, 2, 0, 2, // steel battle axe
                0, 91, 0, 1, 0, 1, // mithril battle axe
            ]
        );
    }

    #[test]
    fn test_default_lowes_archery_store_matches_java_catalog_packet() {
        let handler = ShopHandler::with_default_shops(ItemRepository::new());
        let shop = handler.get_shop(6).unwrap();
        let packet = build_open_shop_packet(shop, &ItemRepository::new());

        assert_eq!(shop.restock_rate, 3_000);
        assert_eq!(
            packet.payload.as_ref(),
            &[
                5, 0, 55, 100, 1, // count, specialty, sell, buy, price modifier
                0, 11, 0, 200, 0, 200, // bronze arrows
                0, 190, 0, 150, 0, 150, // crossbow bolts
                0, 189, 0, 4, 0, 4, // shortbow
                0, 188, 0, 2, 0, 2, // longbow
                0, 60, 0, 2, 0, 2, // crossbow
            ]
        );
    }

    #[test]
    fn test_default_brians_battle_axes_matches_java_catalog_packet() {
        let handler = ShopHandler::with_default_shops(ItemRepository::new());
        let shop = handler.get_shop(7).unwrap();
        let packet = build_open_shop_packet(shop, &ItemRepository::new());

        assert_eq!(shop.restock_rate, 15_000);
        assert_eq!(
            packet.payload.as_ref(),
            &[
                6, 0, 55, 100, 1, // count, specialty, sell, buy, price modifier
                0, 205, 0, 4, 0, 4, // bronze battle axe
                0, 89, 0, 3, 0, 3, // iron battle axe
                0, 90, 0, 2, 0, 2, // steel battle axe
                1, 173, 0, 1, 0, 1, // black battle axe
                0, 91, 0, 1, 0, 1, // mithril battle axe
                0, 92, 0, 1, 0, 1, // adamantite battle axe
            ]
        );
    }

    #[test]
    fn test_default_horviks_armoury_openpk_matches_java_catalog_packet() {
        let handler = ShopHandler::with_default_shops(ItemRepository::new());
        let shop = handler.get_shop(8).unwrap();
        let packet = build_open_shop_packet(shop, &ItemRepository::new());

        assert_eq!(shop.restock_rate, 30_000);
        assert_eq!(
            packet.payload.as_ref(),
            &[
                26, 0, 60, 100, 2, // count, specialty, sell, buy, price modifier
                0, 7, 0, 100, 0, 100, // iron chain mail body
                0, 6, 0, 100, 0, 100, // large iron helmet
                0, 8, 0, 100, 0, 100, // iron plate mail body
                0, 9, 0, 100, 0, 100, // iron plate mail legs
                0, 2, 0, 100, 0, 100, // iron kite shield
                0, 114, 0, 100, 0, 100, // steel chain mail body
                0, 109, 0, 100, 0, 100, // large steel helmet
                0, 118, 0, 100, 0, 100, // steel plate mail body
                0, 121, 0, 100, 0, 100, // steel plate mail legs
                0, 129, 0, 100, 0, 100, // steel kite shield
                1, 175, 0, 100, 0, 100, // black chain mail body
                0, 230, 0, 100, 0, 100, // large black helmet
                0, 196, 0, 100, 0, 100, // black plate mail body
                0, 248, 0, 100, 0, 100, // black plate mail legs
                1, 177, 0, 100, 0, 100, // black kite shield
                0, 115, 0, 100, 0, 100, // mithril chain mail body
                0, 110, 0, 100, 0, 100, // large mithril helmet
                0, 119, 0, 100, 0, 100, // mithril plate mail body
                0, 122, 0, 100, 0, 100, // mithril plate mail legs
                0, 130, 0, 100, 0, 100, // mithril kite shield
                0, 116, 0, 100, 0, 100, // adamantite chain mail body
                0, 111, 0, 100, 0, 100, // large adamantite helmet
                0, 120, 0, 100, 0, 100, // adamantite plate mail body
                0, 123, 0, 100, 0, 100, // adamantite plate mail legs
                0, 131, 0, 100, 0, 100, // adamantite kite shield
                3, 238, 0, 100, 0, 100, // klank's gauntlets
            ]
        );
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
    fn test_buy_request_uses_catalog_id() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();

        let request = ShopItemAmountRequest {
            item_id: ItemId(66),
            stock_amount: 5,
            amount: 2,
        };
        let packets = handler.handle_buy_request(1, request).unwrap();
        assert!(!packets.is_empty());

        let shop = handler.get_shop(1).unwrap();
        assert_eq!(shop.items()[1].amount, 3);
    }

    #[test]
    fn test_buy_request_with_inventory_moves_coins_and_item() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();
        let mut inventory = Inventory::new();
        assert!(inventory.add(PlayerItem::stackable(COINS.0, 100)));

        let request = ShopItemAmountRequest {
            item_id: ItemId(66),
            stock_amount: 5,
            amount: 2,
        };

        let result = handler
            .handle_buy_request_with_inventory(1, request, &mut inventory)
            .unwrap();

        assert!(result.inventory_changed);
        assert!(!result.packets.is_empty());
        assert_eq!(inventory.count(66), 2);
        assert_eq!(inventory.count(COINS.0), 52);
        assert_eq!(handler.get_shop(1).unwrap().items()[1].amount, 3);
    }

    #[test]
    fn test_buy_request_with_inventory_denies_insufficient_funds() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();
        let mut inventory = Inventory::new();
        assert!(inventory.add(PlayerItem::stackable(COINS.0, 1)));

        let request = ShopItemAmountRequest {
            item_id: ItemId(66),
            stock_amount: 5,
            amount: 1,
        };

        let result = handler.handle_buy_request_with_inventory(1, request, &mut inventory);

        assert!(matches!(
            result,
            Err(ShopHandlerError::Transaction(
                ShopResult::InsufficientFunds { .. }
            ))
        ));
        assert_eq!(inventory.count(66), 0);
        assert_eq!(handler.get_shop(1).unwrap().items()[1].amount, 5);
    }

    #[test]
    fn test_buy_out_of_stock() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();

        let result = handler.handle_buy(1, 0, 999);
        assert!(matches!(
            result,
            Err(ShopHandlerError::Transaction(
                ShopResult::InsufficientStock { .. }
            ))
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
    fn test_sell_request_uses_catalog_id() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();

        let request = ShopItemAmountRequest {
            item_id: ItemId(66),
            stock_amount: 5,
            amount: 3,
        };
        let packets = handler.handle_sell_request(1, request).unwrap();
        assert!(!packets.is_empty());

        let shop = handler.get_shop(1).unwrap();
        assert_eq!(shop.items()[1].amount, 8);
    }

    #[test]
    fn test_sell_request_with_inventory_moves_item_and_coins() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();
        let mut inventory = Inventory::new();
        assert!(inventory.add(PlayerItem::new(66, 3)));

        let request = ShopItemAmountRequest {
            item_id: ItemId(66),
            stock_amount: 5,
            amount: 2,
        };

        let result = handler
            .handle_sell_request_with_inventory(1, request, &mut inventory)
            .unwrap();

        assert!(result.inventory_changed);
        assert!(!result.packets.is_empty());
        assert_eq!(inventory.count(66), 1);
        assert_eq!(inventory.count(COINS.0), 18);
        assert_eq!(handler.get_shop(1).unwrap().items()[1].amount, 7);
    }

    #[test]
    fn test_zero_amount_shop_request_is_noop() {
        let mut handler = make_handler();
        handler.open_shop(1, 1, 0).unwrap();

        let request = ShopItemAmountRequest {
            item_id: ItemId(66),
            stock_amount: 5,
            amount: 0,
        };

        assert!(handler.handle_buy_request(1, request).unwrap().is_empty());
        assert!(handler.handle_sell_request(1, request).unwrap().is_empty());
        let shop = handler.get_shop(1).unwrap();
        assert_eq!(shop.items()[1].amount, 5);
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
    fn test_parse_shop_item_amount_request() {
        let packet = PacketBuilder::new(236)
            .write_short(66)
            .write_short(5)
            .write_short(2)
            .build();

        let request = ShopItemAmountRequest::parse(&packet).unwrap();
        assert_eq!(request.item_id, ItemId(66));
        assert_eq!(request.stock_amount, 5);
        assert_eq!(request.amount, 2);
    }

    #[test]
    fn test_parse_shop_item_amount_rejects_short_or_extra_payload() {
        let short_packet = Packet::new(236, vec![0, 66, 0, 5]);
        assert!(matches!(
            ShopItemAmountRequest::parse(&short_packet),
            Err(ShopHandlerError::MalformedPacket)
        ));

        let extra_packet = Packet::new(236, vec![0, 66, 0, 5, 0, 2, 99]);
        assert!(matches!(
            ShopItemAmountRequest::parse(&extra_packet),
            Err(ShopHandlerError::MalformedPacket)
        ));
    }

    #[test]
    fn test_dynamic_pricing_low_stock() {
        let repo = ItemRepository::new();
        let mut shop = Shop::new(1, "Test Shop");
        shop.add_stock(ItemId(66), 10);
        let normal_price = calculate_java_buy_price(&shop, ItemId(66), &repo, 0);

        // Reduce stock well below base
        shop.get_item_mut(0).unwrap().amount = 1;
        let high_price = calculate_java_buy_price(&shop, ItemId(66), &repo, 0);
        assert!(
            high_price > normal_price,
            "Low stock should raise buy price"
        );
    }

    #[test]
    fn test_dynamic_pricing_overstock() {
        let repo = ItemRepository::new();
        let mut shop = Shop::new(1, "Test Shop");
        shop.add_stock(ItemId(66), 10);
        let normal_price = calculate_java_buy_price(&shop, ItemId(66), &repo, 0);

        // Increase stock well above base
        shop.get_item_mut(0).unwrap().amount = 30;
        let low_price = calculate_java_buy_price(&shop, ItemId(66), &repo, 0);
        assert!(
            low_price < normal_price,
            "Overstocked should lower buy price"
        );
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
