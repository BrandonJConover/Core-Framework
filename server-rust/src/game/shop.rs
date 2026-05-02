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
            restock_timer: 0,
        }
    }

    /// Create a general store.
    pub fn general_store(id: u32, name: &str) -> Self {
        let mut shop = Self::new(id, name);
        shop.is_general = true;
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

        // Price increases when stock is low
        let stock_factor = if item.amount == 0 {
            150 // 150% price when out of stock (if buying sold item)
        } else if item.amount < item.base_stock / 2 {
            120 // 120% when low stock
        } else {
            100
        };

        Some((base_price * stock_factor) / 100)
    }

    /// Calculate sell price for player selling to shop.
    pub fn calculate_sell_price(
        &self,
        item_id: ItemId,
        item_repo: &ItemRepository,
    ) -> Option<u32> {
        if !self.will_buy(item_id, item_repo) {
            return None;
        }

        let base_price = item_repo.get(item_id)?.base_price;

        // Find if shop stocks this item
        let stock_item = self.find_item(item_id).and_then(|i| self.items.get(i));

        let sell_percentage = if let Some(stock) = stock_item {
            if stock.amount > stock.base_stock * 2 {
                20 // Low price when overstocked
            } else if stock.amount > stock.base_stock {
                30
            } else {
                40 // Standard 40%
            }
        } else {
            // General store buying unstocked item
            30
        };

        Some((base_price * sell_percentage) / 100)
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
        // Lumbridge General Store
        let mut lumbridge_general = Shop::general_store(1, "Lumbridge General Store");
        lumbridge_general.add_stock(ItemId(156), 5); // Pot
        lumbridge_general.add_stock(ItemId(135), 2); // Shears
        lumbridge_general.add_stock(ItemId(166), 2); // Bucket
        lumbridge_general.add_stock(ItemId(167), 2); // Tinderbox
        lumbridge_general.add_stock(ItemId(168), 2); // Chisel
        lumbridge_general.add_stock(ItemId(169), 2); // Hammer
        self.register(lumbridge_general);

        // Varrock Sword Shop
        let mut varrock_swords = Shop::new(2, "Varrock Sword Shop");
        varrock_swords.add_stock(ItemId(1), 10);   // Bronze sword
        varrock_swords.add_stock(ItemId(70), 5);   // Iron sword
        varrock_swords.add_stock(ItemId(71), 3);   // Steel sword
        varrock_swords.add_stock(ItemId(72), 1);   // Mithril sword
        self.register(varrock_swords);

        // Rune Shop
        let mut rune_shop = Shop::new(3, "Aubury's Rune Shop");
        rune_shop.add_stock(ItemId(33), 100); // Air rune
        rune_shop.add_stock(ItemId(32), 100); // Water rune
        rune_shop.add_stock(ItemId(34), 100); // Earth rune
        rune_shop.add_stock(ItemId(31), 100); // Fire rune
        rune_shop.add_stock(ItemId(35), 100); // Mind rune
        rune_shop.add_stock(ItemId(36), 100); // Body rune
        self.register(rune_shop);

        // Food Shop
        let mut food_shop = Shop::new(4, "Wydin's Food Store");
        food_shop.add_stock(ItemId(132), 10); // Raw chicken
        food_shop.add_stock(ItemId(18), 30);  // Bread
        food_shop.add_stock(ItemId(319), 5);  // Chocolate bar
        self.register(food_shop);

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
}
