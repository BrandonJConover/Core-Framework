//! Shop system for NPC vendors.
//! Handles shop inventories, buy/sell logic, and pricing.

use std::collections::HashMap;
use tracing::info;

use super::item::{ItemId, ItemRepository};

/// Represents an item slot in a shop.
#[derive(Debug, Clone)]
pub struct ShopItem {
    /// Item ID.
    pub item_id: ItemId,
    /// Current stock amount.
    pub amount: u32,
    /// Base stock amount (restocks to this).
    pub base_stock: u32,
    /// Custom buy price (None = use item base price).
    pub custom_buy_price: Option<u32>,
    /// Custom sell price (None = calculated from buy).
    pub custom_sell_price: Option<u32>,
}

impl ShopItem {
    /// Create a new shop item with default stock.
    pub fn new(item_id: ItemId, base_stock: u32) -> Self {
        Self {
            item_id,
            amount: base_stock,
            base_stock,
            custom_buy_price: None,
            custom_sell_price: None,
        }
    }

    /// Create a shop item with custom pricing.
    pub fn with_prices(item_id: ItemId, base_stock: u32, buy_price: u32, sell_price: u32) -> Self {
        Self {
            item_id,
            amount: base_stock,
            base_stock,
            custom_buy_price: Some(buy_price),
            custom_sell_price: Some(sell_price),
        }
    }

    /// Get the buy price for this item.
    pub fn buy_price(&self, item_repo: &ItemRepository) -> u32 {
        if let Some(price) = self.custom_buy_price {
            return price;
        }
        item_repo
            .get(self.item_id)
            .map(|d| d.base_price)
            .unwrap_or(1)
    }

    /// Get the sell price for this item (what player receives).
    pub fn sell_price(&self, item_repo: &ItemRepository) -> u32 {
        if let Some(price) = self.custom_sell_price {
            return price;
        }
        // Default: 40% of buy price
        let buy = self.buy_price(item_repo);
        (buy * 40) / 100
    }

    /// Check if item is in stock.
    pub fn in_stock(&self) -> bool {
        self.amount > 0
    }

    /// Decrease stock by amount.
    pub fn decrease_stock(&mut self, amount: u32) {
        self.amount = self.amount.saturating_sub(amount);
    }

    /// Increase stock by amount.
    pub fn increase_stock(&mut self, amount: u32) {
        self.amount = self.amount.saturating_add(amount);
    }

    /// Get how many over/under base stock.
    pub fn stock_difference(&self) -> i32 {
        self.amount as i32 - self.base_stock as i32
    }
}

/// Shop definition.
#[derive(Debug, Clone)]
pub struct Shop {
    /// Unique shop ID.
    pub id: u32,
    /// Shop name.
    pub name: String,
    /// Items for sale.
    items: Vec<ShopItem>,
    /// Whether shop is general (buys most items).
    pub is_general: bool,
    /// Currency item ID (default: coins).
    pub currency: ItemId,
    /// Restock rate in ticks.
    pub restock_rate: u32,
    /// Percentage modifier paid to players selling to this shop.
    pub sell_modifier: u8,
    /// Percentage modifier charged to players buying from this shop.
    pub buy_modifier: u8,
    /// Client-side stock sensitivity price modifier.
    pub price_modifier: u8,
    /// Ticks until next restock.
    restock_timer: u32,
}

impl Shop {
    /// Create a new shop.
    pub fn new(id: u32, name: &str) -> Self {
        Self {
            id,
            name: name.to_string(),
            items: Vec::new(),
            is_general: false,
            currency: ItemId(10), // Coins
            restock_rate: 100,    // Restock every 100 ticks (~1 minute)
            sell_modifier: 40,
            buy_modifier: 100,
            price_modifier: 2,
            restock_timer: 0,
        }
    }

    /// Set Java-style shop price modifiers.
    pub fn with_modifiers(
        mut self,
        sell_modifier: u8,
        buy_modifier: u8,
        price_modifier: u8,
    ) -> Self {
        self.sell_modifier = sell_modifier;
        self.buy_modifier = buy_modifier;
        self.price_modifier = price_modifier;
        self
    }

    /// Create a general store.
    pub fn general_store(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name);
        shop.is_general = true;
        shop
    }

    /// Java/OpenRSC authentic general-store catalog.
    ///
    /// Java reference: `plugins/authentic/npcs/GeneralStore.java`
    /// uses `new Shop(true, 12400, 130, 40, 3, ...)`. The constructor
    /// order there is buy modifier then sell modifier, while Rust stores
    /// sell then buy for outbound packet layout.
    pub fn java_general_store(id: u32, name: &str, include_sleeping_bag: bool) -> Self {
        let mut shop = Self::general_store(id, name).with_modifiers(40, 130, 3);
        shop.restock_rate = 12_400;
        shop.add_stock(ItemId(156), 3); // Pot
        shop.add_stock(ItemId(140), 2); // Jug
        shop.add_stock(ItemId(135), 2); // Shears
        shop.add_stock(ItemId(166), 2); // Bucket
        shop.add_stock(ItemId(167), 2); // Tinderbox
        shop.add_stock(ItemId(168), 2); // Chisel
        shop.add_stock(ItemId(169), 5); // Hammer
        if include_sleeping_bag {
            shop.add_stock(ItemId(1263), 10); // Sleeping bag
        }
        shop
    }

    /// Java/OpenRSC authentic Aubury's Rune Shop catalog.
    ///
    /// Java reference: `plugins/authentic/npcs/varrock/AuburysRunes.java`.
    pub fn java_auburys_rune_shop(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name).with_modifiers(70, 100, 2);
        shop.restock_rate = 3_000;
        shop.add_stock(ItemId(31), 50); // Fire rune
        shop.add_stock(ItemId(32), 50); // Water rune
        shop.add_stock(ItemId(33), 50); // Air rune
        shop.add_stock(ItemId(34), 50); // Earth rune
        shop.add_stock(ItemId(35), 50); // Mind rune
        shop.add_stock(ItemId(36), 50); // Body rune
        shop
    }

    /// Java/OpenRSC authentic Varrock Sword Shop catalog.
    ///
    /// Java reference: `plugins/authentic/npcs/varrock/VarrockSwords.java`.
    pub fn java_varrock_sword_shop(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name).with_modifiers(60, 100, 2);
        shop.restock_rate = 30_000;
        shop.add_stock(ItemId(66), 5); // Bronze short sword
        shop.add_stock(ItemId(1), 4); // Iron short sword
        shop.add_stock(ItemId(67), 4); // Steel short sword
        shop.add_stock(ItemId(424), 3); // Black short sword
        shop.add_stock(ItemId(68), 3); // Mithril short sword
        shop.add_stock(ItemId(69), 2); // Adamantite short sword
        shop.add_stock(ItemId(70), 4); // Bronze long sword
        shop.add_stock(ItemId(71), 3); // Iron long sword
        shop.add_stock(ItemId(72), 3); // Steel long sword
        shop.add_stock(ItemId(425), 2); // Black long sword
        shop.add_stock(ItemId(73), 2); // Mithril long sword
        shop.add_stock(ItemId(74), 1); // Adamantite long sword
        shop.add_stock(ItemId(62), 10); // Bronze dagger
        shop.add_stock(ItemId(28), 6); // Iron dagger
        shop.add_stock(ItemId(63), 5); // Steel dagger
        shop.add_stock(ItemId(423), 4); // Black dagger
        shop.add_stock(ItemId(64), 3); // Mithril dagger
        shop.add_stock(ItemId(65), 2); // Adamantite dagger
        shop
    }

    /// Java/OpenRSC authentic Wydin's Food Store catalog.
    ///
    /// Java reference: `plugins/authentic/npcs/portsarim/WydinsGrocery.java`.
    /// OpenRSC's current config branch (`BASED_CONFIG_DATA >= 28`) stocks
    /// three pots of flour; older config data stocked one.
    pub fn java_wydins_food_store(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name).with_modifiers(70, 100, 1);
        shop.restock_rate = 12_500;
        shop.add_stock(ItemId(136), 3); // Pot of flour
        shop.add_stock(ItemId(133), 1); // Raw chicken
        shop.add_stock(ItemId(18), 3); // Cabbage
        shop.add_stock(ItemId(249), 3); // Banana
        shop.add_stock(ItemId(236), 1); // Redberries
        shop.add_stock(ItemId(138), 0); // Bread
        shop.add_stock(ItemId(337), 1); // Chocolate bar
        shop.add_stock(ItemId(319), 3); // Cheese
        shop.add_stock(ItemId(320), 3); // Tomato
        shop.add_stock(ItemId(348), 1); // Potato
        shop
    }

    /// Java/OpenRSC authentic Bob's Axes catalog.
    ///
    /// Java reference: `plugins/authentic/npcs/lumbridge/BobsAxes.java`.
    pub fn java_bobs_axes(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name).with_modifiers(60, 100, 2);
        shop.restock_rate = 15_000;
        shop.add_stock(ItemId(156), 5); // Bronze pickaxe
        shop.add_stock(ItemId(87), 10); // Bronze axe
        shop.add_stock(ItemId(12), 5); // Iron axe
        shop.add_stock(ItemId(88), 3); // Steel axe
        shop.add_stock(ItemId(89), 5); // Iron battle axe
        shop.add_stock(ItemId(90), 2); // Steel battle axe
        shop.add_stock(ItemId(91), 1); // Mithril battle axe
        shop
    }

    /// Java/OpenRSC authentic Lowe's Archery Store catalog.
    ///
    /// Java reference: `plugins/authentic/npcs/varrock/LowesArchery.java`.
    pub fn java_lowes_archery_store(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name).with_modifiers(55, 100, 1);
        shop.restock_rate = 3_000;
        shop.add_stock(ItemId(11), 200); // Bronze arrows
        shop.add_stock(ItemId(190), 150); // Crossbow bolts
        shop.add_stock(ItemId(189), 4); // Shortbow
        shop.add_stock(ItemId(188), 2); // Longbow
        shop.add_stock(ItemId(60), 2); // Crossbow
        shop
    }

    /// Java/OpenRSC authentic Brian's Battle Axe Bazaar catalog.
    ///
    /// Java reference: `plugins/authentic/npcs/portsarim/BriansBattleAxes.java`.
    pub fn java_brians_battle_axes(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name).with_modifiers(55, 100, 1);
        shop.restock_rate = 15_000;
        shop.add_stock(ItemId(205), 4); // Bronze battle axe
        shop.add_stock(ItemId(89), 3); // Iron battle axe
        shop.add_stock(ItemId(90), 2); // Steel battle axe
        shop.add_stock(ItemId(429), 1); // Black battle axe
        shop.add_stock(ItemId(91), 1); // Mithril battle axe
        shop.add_stock(ItemId(92), 1); // Adamantite battle axe
        shop
    }

    /// Java/OpenRSC authentic Horvik the Armourer OpenPK catalog.
    ///
    /// Java reference: `plugins/custom/npcs/HorvikTheArmourerOpenPk.java`.
    pub fn java_horviks_armoury_openpk(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name).with_modifiers(60, 100, 2);
        shop.restock_rate = 30_000;
        shop.add_stock(ItemId(7), 100); // Iron chain mail body
        shop.add_stock(ItemId(6), 100); // Large iron helmet
        shop.add_stock(ItemId(8), 100); // Iron plate mail body
        shop.add_stock(ItemId(9), 100); // Iron plate mail legs
        shop.add_stock(ItemId(2), 100); // Iron kite shield
        shop.add_stock(ItemId(114), 100); // Steel chain mail body
        shop.add_stock(ItemId(109), 100); // Large steel helmet
        shop.add_stock(ItemId(118), 100); // Steel plate mail body
        shop.add_stock(ItemId(121), 100); // Steel plate mail legs
        shop.add_stock(ItemId(129), 100); // Steel kite shield
        shop.add_stock(ItemId(431), 100); // Black chain mail body
        shop.add_stock(ItemId(230), 100); // Large black helmet
        shop.add_stock(ItemId(196), 100); // Black plate mail body
        shop.add_stock(ItemId(248), 100); // Black plate mail legs
        shop.add_stock(ItemId(433), 100); // Black kite shield
        shop.add_stock(ItemId(115), 100); // Mithril chain mail body
        shop.add_stock(ItemId(110), 100); // Large mithril helmet
        shop.add_stock(ItemId(119), 100); // Mithril plate mail body
        shop.add_stock(ItemId(122), 100); // Mithril plate mail legs
        shop.add_stock(ItemId(130), 100); // Mithril kite shield
        shop.add_stock(ItemId(116), 100); // Adamantite chain mail body
        shop.add_stock(ItemId(111), 100); // Large adamantite helmet
        shop.add_stock(ItemId(120), 100); // Adamantite plate mail body
        shop.add_stock(ItemId(123), 100); // Adamantite plate mail legs
        shop.add_stock(ItemId(131), 100); // Adamantite kite shield
        shop.add_stock(ItemId(1006), 100); // Klank's gauntlets
        shop
    }

    /// Add an item to the shop.
    pub fn add_item(&mut self, item: ShopItem) {
        self.items.push(item);
    }

    /// Add a simple item with default pricing.
    pub fn add_stock(&mut self, item_id: ItemId, amount: u32) {
        self.items.push(ShopItem::new(item_id, amount));
    }

    /// Get all items.
    pub fn items(&self) -> &[ShopItem] {
        &self.items
    }

    /// Get a mutable item by index.
    pub fn get_item_mut(&mut self, index: usize) -> Option<&mut ShopItem> {
        self.items.get_mut(index)
    }

    /// Find item index by ID.
    pub fn find_item(&self, item_id: ItemId) -> Option<usize> {
        self.items.iter().position(|i| i.item_id == item_id)
    }

    /// Get item count.
    pub fn item_count(&self) -> usize {
        self.items.len()
    }

    /// Process restock tick.
    pub fn tick(&mut self) {
        self.restock_timer += 1;
        if self.restock_timer >= self.restock_rate {
            self.restock_timer = 0;
            self.restock();
        }
    }

    /// Restock items towards base stock.
    fn restock(&mut self) {
        for item in &mut self.items {
            let diff = item.stock_difference();
            if diff > 0 {
                // Over stock, decrease by 1
                item.decrease_stock(1);
            } else if diff < 0 {
                // Under stock, increase by 1
                item.increase_stock(1);
            }
        }
    }

    /// Check if shop will buy an item.
    pub fn will_buy(&self, item_id: ItemId, item_repo: &ItemRepository) -> bool {
        if self.is_general {
            // General stores buy most tradeable items
            item_repo
                .get(item_id)
                .map(|d| d.base_price > 0)
                .unwrap_or(false)
        } else {
            // Specialty shops only buy items they stock
            self.find_item(item_id).is_some()
        }
    }

    /// Calculate buy price for player purchasing from shop.
    pub fn calculate_buy_price(&self, index: usize, item_repo: &ItemRepository) -> Option<u32> {
        let item = self.items.get(index)?;
        let base_price = item.buy_price(item_repo);

        Some(self.calculate_java_buy_price(item.item_id, base_price, 0, false))
    }

    /// Calculate sell price for player selling to shop.
    pub fn calculate_sell_price(&self, item_id: ItemId, item_repo: &ItemRepository) -> Option<u32> {
        if !self.will_buy(item_id, item_repo) {
            return None;
        }

        let base_price = item_repo.get(item_id)?.base_price;

        Some(self.calculate_java_sell_price(item_id, base_price, 1, false))
    }

    /// Java-compatible buy price for one item at a specific point in a multi-buy.
    pub fn calculate_java_buy_price(
        &self,
        item_id: ItemId,
        default_price: u32,
        total_bought: u32,
        retro_calc: bool,
    ) -> u32 {
        let offset = if retro_calc {
            self.retro_stock_offset(item_id)
        } else {
            self.stock_buy_offset(item_id, total_bought)
        };
        self.price_from_modifier(default_price, self.buy_modifier as i32 + offset)
    }

    /// Java-compatible sell price for one item at a specific point in a multi-sell.
    pub fn calculate_java_sell_price(
        &self,
        item_id: ItemId,
        default_price: u32,
        total_removed: u32,
        retro_calc: bool,
    ) -> u32 {
        let offset = if retro_calc {
            self.retro_stock_offset(item_id)
        } else {
            self.stock_sell_offset(item_id, total_removed)
        };
        self.price_from_modifier(default_price, self.sell_modifier as i32 + offset)
    }

    fn price_from_modifier(&self, default_price: u32, modifier: i32) -> u32 {
        let modifier = modifier.max(10) as u32;
        modifier.saturating_mul(default_price) / 100
    }

    fn base_stock_for(&self, item_id: ItemId) -> u32 {
        self.items
            .iter()
            .find(|item| item.item_id == item_id && item.base_stock > 0)
            .map(|item| item.base_stock)
            .unwrap_or(0)
    }

    fn stock_count(&self, item_id: ItemId) -> u32 {
        self.items
            .iter()
            .filter(|item| item.item_id == item_id)
            .map(|item| item.amount)
            .sum()
    }

    fn stock_buy_offset(&self, item_id: ItemId, total_bought: u32) -> i32 {
        let base_stock = self.base_stock_for(item_id) as i32;
        let current = self.stock_count(item_id) as i32;
        let total_bought = total_bought as i32;
        self.clamp_stock_offset(
            self.price_modifier as i32 * (base_stock - (current - total_bought)),
        )
    }

    fn stock_sell_offset(&self, item_id: ItemId, total_removed: u32) -> i32 {
        let base_stock = self.base_stock_for(item_id).saturating_add(1) as i32;
        let current = self.stock_count(item_id) as i32;
        let total_removed = total_removed as i32;
        self.clamp_stock_offset(
            self.price_modifier as i32 * (base_stock - (current + total_removed)),
        )
    }

    fn retro_stock_offset(&self, item_id: ItemId) -> i32 {
        let base_stock = self.base_stock_for(item_id) as i32;
        let current = self.stock_count(item_id) as i32;
        (base_stock - current).clamp(-127, 127)
    }

    fn clamp_stock_offset(&self, offset: i32) -> i32 {
        offset.clamp(-100, 100)
    }
}

/// Result of a shop transaction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ShopResult {
    /// Transaction successful.
    Success,
    /// Not enough currency.
    InsufficientFunds { required: u32, available: u32 },
    /// Item out of stock.
    OutOfStock,
    /// Shop won't buy this item.
    WontBuy,
    /// Invalid item or index.
    InvalidItem,
    /// Player inventory full.
    InventoryFull,
    /// Amount exceeds stock.
    InsufficientStock { available: u32 },
}

/// Shop manager for all shops in the world.
#[derive(Debug, Default)]
pub struct ShopManager {
    shops: HashMap<u32, Shop>,
}

impl ShopManager {
    /// Create a new shop manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a shop.
    pub fn register(&mut self, shop: Shop) {
        info!("Registered shop: {} (ID: {})", shop.name, shop.id);
        self.shops.insert(shop.id, shop);
    }

    /// Get a shop by ID.
    pub fn get(&self, id: u32) -> Option<&Shop> {
        self.shops.get(&id)
    }

    /// Get a mutable shop by ID.
    pub fn get_mut(&mut self, id: u32) -> Option<&mut Shop> {
        self.shops.get_mut(&id)
    }

    /// Process tick for all shops.
    pub fn tick(&mut self) {
        for shop in self.shops.values_mut() {
            shop.tick();
        }
    }

    /// Load default shops.
    pub fn load_defaults(&mut self) {
        self.register(Shop::java_general_store(
            1,
            "Lumbridge General Store",
            false,
        ));

        self.register(Shop::java_varrock_sword_shop(2, "Varrock Sword Shop"));

        self.register(Shop::java_auburys_rune_shop(3, "Aubury's Rune Shop"));

        self.register(Shop::java_wydins_food_store(4, "Wydin's Food Store"));

        self.register(Shop::java_bobs_axes(5, "Bob's Axes"));

        self.register(Shop::java_lowes_archery_store(6, "Lowe's Archery Store"));

        self.register(Shop::java_brians_battle_axes(
            7,
            "Brian's Battle Axe Bazaar",
        ));

        self.register(Shop::java_horviks_armoury_openpk(8, "Horvik's Armoury"));

        info!("Loaded {} shops", self.shops.len());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_repo() -> ItemRepository {
        ItemRepository::new()
    }

    #[test]
    fn test_shop_creation() {
        let mut shop = Shop::new(1, "Test Shop");
        shop.add_stock(ItemId(1), 10);

        assert_eq!(shop.item_count(), 1);
        assert_eq!(shop.items()[0].amount, 10);
    }

    #[test]
    fn test_shop_restock() {
        let mut shop = Shop::new(1, "Test");
        shop.restock_rate = 1;
        shop.add_stock(ItemId(1), 10);

        // Decrease stock
        shop.get_item_mut(0).unwrap().decrease_stock(5);
        assert_eq!(shop.items()[0].amount, 5);

        // Tick should trigger restock
        shop.tick();
        assert_eq!(shop.items()[0].amount, 6); // Restocked by 1
    }

    #[test]
    fn test_general_store() {
        let repo = test_repo();
        let shop = Shop::general_store(1, "General");

        // General store buys coins (has base price)
        assert!(shop.will_buy(ItemId(10), &repo));
    }

    #[test]
    fn test_price_calculation() {
        let repo = test_repo();
        let mut shop = Shop::new(1, "Test");
        shop.add_stock(ItemId(10), 100); // Coins

        let price = shop.calculate_buy_price(0, &repo);
        assert!(price.is_some());
    }

    #[test]
    fn test_java_modern_shop_price_formula() {
        let repo = test_repo();
        let mut shop = Shop::new(1, "Test").with_modifiers(60, 100, 2);
        shop.add_stock(ItemId(66), 5);

        let default_price = repo.get(ItemId(66)).unwrap().base_price;
        assert_eq!(
            shop.calculate_java_buy_price(ItemId(66), default_price, 0, false),
            24
        );
        assert_eq!(
            shop.calculate_java_buy_price(ItemId(66), default_price, 4, false),
            25
        );
        assert_eq!(
            shop.calculate_java_sell_price(ItemId(66), default_price, 1, false),
            14
        );

        shop.get_item_mut(0).unwrap().amount = 10;
        assert_eq!(
            shop.calculate_java_sell_price(ItemId(66), default_price, 1, false),
            12
        );
    }

    #[test]
    fn test_java_general_store_catalog() {
        let shop = Shop::java_general_store(1, "Lumbridge General Store", false);

        assert!(shop.is_general);
        assert_eq!(shop.restock_rate, 12_400);
        assert_eq!(shop.sell_modifier, 40);
        assert_eq!(shop.buy_modifier, 130);
        assert_eq!(shop.price_modifier, 3);
        assert_eq!(
            shop.items()
                .iter()
                .map(|item| (item.item_id.0, item.base_stock))
                .collect::<Vec<_>>(),
            vec![
                (156, 3),
                (140, 2),
                (135, 2),
                (166, 2),
                (167, 2),
                (168, 2),
                (169, 5)
            ]
        );
    }

    #[test]
    fn test_java_auburys_rune_shop_catalog() {
        let shop = Shop::java_auburys_rune_shop(3, "Aubury's Rune Shop");

        assert!(!shop.is_general);
        assert_eq!(shop.restock_rate, 3_000);
        assert_eq!(shop.sell_modifier, 70);
        assert_eq!(shop.buy_modifier, 100);
        assert_eq!(shop.price_modifier, 2);
        assert_eq!(
            shop.items()
                .iter()
                .map(|item| (item.item_id.0, item.base_stock))
                .collect::<Vec<_>>(),
            vec![(31, 50), (32, 50), (33, 50), (34, 50), (35, 50), (36, 50)]
        );
    }

    #[test]
    fn test_java_varrock_sword_shop_catalog() {
        let shop = Shop::java_varrock_sword_shop(2, "Varrock Sword Shop");

        assert!(!shop.is_general);
        assert_eq!(shop.restock_rate, 30_000);
        assert_eq!(shop.sell_modifier, 60);
        assert_eq!(shop.buy_modifier, 100);
        assert_eq!(shop.price_modifier, 2);
        assert_eq!(
            shop.items()
                .iter()
                .map(|item| (item.item_id.0, item.base_stock))
                .collect::<Vec<_>>(),
            vec![
                (66, 5),
                (1, 4),
                (67, 4),
                (424, 3),
                (68, 3),
                (69, 2),
                (70, 4),
                (71, 3),
                (72, 3),
                (425, 2),
                (73, 2),
                (74, 1),
                (62, 10),
                (28, 6),
                (63, 5),
                (423, 4),
                (64, 3),
                (65, 2)
            ]
        );
    }

    #[test]
    fn test_java_wydins_food_store_catalog() {
        let shop = Shop::java_wydins_food_store(4, "Wydin's Food Store");

        assert!(!shop.is_general);
        assert_eq!(shop.restock_rate, 12_500);
        assert_eq!(shop.sell_modifier, 70);
        assert_eq!(shop.buy_modifier, 100);
        assert_eq!(shop.price_modifier, 1);
        assert_eq!(
            shop.items()
                .iter()
                .map(|item| (item.item_id.0, item.base_stock))
                .collect::<Vec<_>>(),
            vec![
                (136, 3),
                (133, 1),
                (18, 3),
                (249, 3),
                (236, 1),
                (138, 0),
                (337, 1),
                (319, 3),
                (320, 3),
                (348, 1)
            ]
        );
    }

    #[test]
    fn test_java_bobs_axes_catalog() {
        let shop = Shop::java_bobs_axes(5, "Bob's Axes");

        assert!(!shop.is_general);
        assert_eq!(shop.restock_rate, 15_000);
        assert_eq!(shop.sell_modifier, 60);
        assert_eq!(shop.buy_modifier, 100);
        assert_eq!(shop.price_modifier, 2);
        assert_eq!(
            shop.items()
                .iter()
                .map(|item| (item.item_id.0, item.base_stock))
                .collect::<Vec<_>>(),
            vec![
                (156, 5),
                (87, 10),
                (12, 5),
                (88, 3),
                (89, 5),
                (90, 2),
                (91, 1)
            ]
        );
    }

    #[test]
    fn test_java_lowes_archery_store_catalog() {
        let shop = Shop::java_lowes_archery_store(6, "Lowe's Archery Store");

        assert!(!shop.is_general);
        assert_eq!(shop.restock_rate, 3_000);
        assert_eq!(shop.sell_modifier, 55);
        assert_eq!(shop.buy_modifier, 100);
        assert_eq!(shop.price_modifier, 1);
        assert_eq!(
            shop.items()
                .iter()
                .map(|item| (item.item_id.0, item.base_stock))
                .collect::<Vec<_>>(),
            vec![(11, 200), (190, 150), (189, 4), (188, 2), (60, 2)]
        );
    }

    #[test]
    fn test_java_brians_battle_axes_catalog() {
        let shop = Shop::java_brians_battle_axes(7, "Brian's Battle Axe Bazaar");

        assert!(!shop.is_general);
        assert_eq!(shop.restock_rate, 15_000);
        assert_eq!(shop.sell_modifier, 55);
        assert_eq!(shop.buy_modifier, 100);
        assert_eq!(shop.price_modifier, 1);
        assert_eq!(
            shop.items()
                .iter()
                .map(|item| (item.item_id.0, item.base_stock))
                .collect::<Vec<_>>(),
            vec![(205, 4), (89, 3), (90, 2), (429, 1), (91, 1), (92, 1)]
        );
    }

    #[test]
    fn test_java_horviks_armoury_openpk_catalog() {
        let shop = Shop::java_horviks_armoury_openpk(8, "Horvik's Armoury");

        assert!(!shop.is_general);
        assert_eq!(shop.restock_rate, 30_000);
        assert_eq!(shop.sell_modifier, 60);
        assert_eq!(shop.buy_modifier, 100);
        assert_eq!(shop.price_modifier, 2);
        assert_eq!(
            shop.items()
                .iter()
                .map(|item| (item.item_id.0, item.base_stock))
                .collect::<Vec<_>>(),
            vec![
                (7, 100),
                (6, 100),
                (8, 100),
                (9, 100),
                (2, 100),
                (114, 100),
                (109, 100),
                (118, 100),
                (121, 100),
                (129, 100),
                (431, 100),
                (230, 100),
                (196, 100),
                (248, 100),
                (433, 100),
                (115, 100),
                (110, 100),
                (119, 100),
                (122, 100),
                (130, 100),
                (116, 100),
                (111, 100),
                (120, 100),
                (123, 100),
                (131, 100),
                (1006, 100)
            ]
        );
    }
}
