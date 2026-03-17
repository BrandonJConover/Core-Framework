//! Drop table system.
//! Handles NPC loot tables, rare drops, and drop mechanics.

use std::collections::HashMap;
use tracing::{debug, info};

/// Drop rarity tiers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum DropRarity {
    /// Always drops (100%).
    Always,
    /// Common drop (~1/1 to 1/10).
    Common,
    /// Uncommon drop (~1/10 to 1/50).
    Uncommon,
    /// Rare drop (~1/50 to 1/200).
    Rare,
    /// Very rare drop (~1/200 to 1/1000).
    VeryRare,
    /// Ultra rare drop (~1/1000+).
    UltraRare,
}

impl DropRarity {
    /// Get display color code.
    pub fn color_code(&self) -> &'static str {
        match self {
            DropRarity::Always => "@whi@",
            DropRarity::Common => "@gre@",
            DropRarity::Uncommon => "@cya@",
            DropRarity::Rare => "@yel@",
            DropRarity::VeryRare => "@ora@",
            DropRarity::UltraRare => "@red@",
        }
    }

    /// Get display name.
    pub fn display_name(&self) -> &'static str {
        match self {
            DropRarity::Always => "Always",
            DropRarity::Common => "Common",
            DropRarity::Uncommon => "Uncommon",
            DropRarity::Rare => "Rare",
            DropRarity::VeryRare => "Very Rare",
            DropRarity::UltraRare => "Ultra Rare",
        }
    }
}

/// A single drop entry.
#[derive(Debug, Clone)]
pub struct DropEntry {
    /// Item ID to drop.
    pub item_id: u32,
    /// Minimum amount.
    pub min_amount: u32,
    /// Maximum amount.
    pub max_amount: u32,
    /// Drop weight (higher = more likely).
    pub weight: u32,
    /// Rarity tier.
    pub rarity: DropRarity,
    /// Required player level (optional).
    pub required_level: Option<u8>,
    /// Member-only drop.
    pub members_only: bool,
}

impl DropEntry {
    /// Create a new drop entry.
    pub fn new(item_id: u32, amount: u32, weight: u32) -> Self {
        Self {
            item_id,
            min_amount: amount,
            max_amount: amount,
            weight,
            rarity: DropRarity::Common,
            required_level: None,
            members_only: false,
        }
    }

    /// Set amount range.
    pub fn with_amount_range(mut self, min: u32, max: u32) -> Self {
        self.min_amount = min;
        self.max_amount = max;
        self
    }

    /// Set rarity.
    pub fn with_rarity(mut self, rarity: DropRarity) -> Self {
        self.rarity = rarity;
        self
    }

    /// Set required level.
    pub fn with_required_level(mut self, level: u8) -> Self {
        self.required_level = Some(level);
        self
    }

    /// Set as members only.
    pub fn members_only(mut self) -> Self {
        self.members_only = true;
        self
    }

    /// Calculate the actual amount to drop.
    pub fn roll_amount(&self) -> u32 {
        if self.min_amount == self.max_amount {
            self.min_amount
        } else {
            let range = self.max_amount - self.min_amount + 1;
            self.min_amount + (rand::random::<u32>() % range)
        }
    }
}

/// Special drop types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SpecialDrop {
    /// Nothing (empty slot).
    Nothing,
    /// Roll on gem table.
    GemTable,
    /// Roll on herb table.
    HerbTable,
    /// Roll on rare table.
    RareTable,
    /// Roll on seed table.
    SeedTable,
    /// Roll on rune table.
    RuneTable,
}

/// A drop table for an NPC.
#[derive(Debug, Clone)]
pub struct DropTable {
    /// NPC ID this table is for.
    pub npc_id: u32,
    /// Regular drops.
    drops: Vec<DropEntry>,
    /// Total weight of all drops.
    total_weight: u32,
    /// 100% drops (bones, ashes, etc.).
    guaranteed_drops: Vec<DropEntry>,
    /// Special table references.
    special_drops: Vec<(SpecialDrop, u32)>, // (type, weight)
}

impl DropTable {
    /// Create a new drop table.
    pub fn new(npc_id: u32) -> Self {
        Self {
            npc_id,
            drops: Vec::new(),
            total_weight: 0,
            guaranteed_drops: Vec::new(),
            special_drops: Vec::new(),
        }
    }

    /// Add a drop entry.
    pub fn add_drop(&mut self, entry: DropEntry) {
        self.total_weight += entry.weight;
        self.drops.push(entry);
    }

    /// Add a guaranteed drop.
    pub fn add_guaranteed(&mut self, entry: DropEntry) {
        self.guaranteed_drops.push(entry);
    }

    /// Add a special table reference.
    pub fn add_special(&mut self, special: SpecialDrop, weight: u32) {
        self.total_weight += weight;
        self.special_drops.push((special, weight));
    }

    /// Roll for drops.
    pub fn roll(&self, is_member: bool) -> Vec<(u32, u32)> {
        let mut results = Vec::new();

        // Add guaranteed drops
        for entry in &self.guaranteed_drops {
            if entry.members_only && !is_member {
                continue;
            }
            results.push((entry.item_id, entry.roll_amount()));
        }

        // Roll for main drop
        if self.total_weight > 0 {
            let roll = rand::random::<u32>() % self.total_weight;
            let mut cumulative = 0u32;

            // Check regular drops
            for entry in &self.drops {
                cumulative += entry.weight;
                if roll < cumulative {
                    if entry.members_only && !is_member {
                        break; // Skip members-only drops for F2P
                    }
                    results.push((entry.item_id, entry.roll_amount()));
                    break;
                }
            }

            // Check special drops if we didn't hit a regular drop
            if cumulative <= roll {
                for (special, weight) in &self.special_drops {
                    cumulative += weight;
                    if roll < cumulative {
                        // Special drops are handled externally
                        debug!("Hit special drop table: {:?}", special);
                        break;
                    }
                }
            }
        }

        results
    }

    /// Get drop count.
    pub fn drop_count(&self) -> usize {
        self.drops.len() + self.guaranteed_drops.len()
    }

    /// Builder method to add a drop.
    pub fn with_drop(mut self, entry: DropEntry) -> Self {
        self.add_drop(entry);
        self
    }

    /// Builder method to add a guaranteed drop.
    pub fn with_guaranteed(mut self, entry: DropEntry) -> Self {
        self.add_guaranteed(entry);
        self
    }

    /// Builder method to add a special table.
    pub fn with_special(mut self, special: SpecialDrop, weight: u32) -> Self {
        self.add_special(special, weight);
        self
    }
}

/// Common item IDs for drops.
pub mod items {
    pub const BONES: u32 = 20;
    pub const BIG_BONES: u32 = 413;
    pub const DRAGON_BONES: u32 = 814;
    pub const COINS: u32 = 10;
    pub const NATURE_RUNE: u32 = 40;
    pub const DEATH_RUNE: u32 = 38;
    pub const BLOOD_RUNE: u32 = 619;
    pub const LAW_RUNE: u32 = 42;
    pub const CHAOS_RUNE: u32 = 41;
    pub const FIRE_RUNE: u32 = 31;
    pub const WATER_RUNE: u32 = 32;
    pub const AIR_RUNE: u32 = 33;
    pub const EARTH_RUNE: u32 = 34;
    pub const MIND_RUNE: u32 = 35;
    pub const BODY_RUNE: u32 = 36;
    pub const COSMIC_RUNE: u32 = 46;
    pub const LOBSTER: u32 = 373;
    pub const SWORDFISH: u32 = 370;
    pub const SHARK: u32 = 546;
    pub const COAL: u32 = 155;
    pub const IRON_ORE: u32 = 151;
    pub const MITHRIL_ORE: u32 = 153;
    pub const ADAMANTITE_ORE: u32 = 154;
    pub const RUNITE_ORE: u32 = 409;
    pub const UNCUT_SAPPHIRE: u32 = 160;
    pub const UNCUT_EMERALD: u32 = 159;
    pub const UNCUT_RUBY: u32 = 158;
    pub const UNCUT_DIAMOND: u32 = 157;
    pub const DRAGON_SQUARE_HALF_LEFT: u32 = 1276;
    pub const DRAGON_SQUARE_HALF_RIGHT: u32 = 1277;
}

/// Gem drop table.
pub fn roll_gem_table() -> Option<(u32, u32)> {
    let weights = [
        (items::UNCUT_SAPPHIRE, 32),
        (items::UNCUT_EMERALD, 16),
        (items::UNCUT_RUBY, 8),
        (items::UNCUT_DIAMOND, 4),
    ];

    let total: u32 = weights.iter().map(|(_, w)| w).sum();
    let roll = rand::random::<u32>() % (total + 68); // 68 = nothing

    if roll >= total {
        return None; // No gem
    }

    let mut cumulative = 0;
    for (item, weight) in weights {
        cumulative += weight;
        if roll < cumulative {
            return Some((item, 1));
        }
    }

    None
}

/// Herb drop table.
pub fn roll_herb_table() -> Option<(u32, u32)> {
    // Unidentified herbs
    let herbs = [
        (165, 33), // Guam
        (435, 25), // Marrentill
        (436, 19), // Tarromin
        (437, 14), // Harralander
        (438, 11), // Ranarr
        (439, 8),  // Irit
        (440, 6),  // Avantoe
        (441, 5),  // Kwuarm
        (442, 4),  // Cadantine
        (443, 3),  // Dwarf weed
    ];

    let total: u32 = herbs.iter().map(|(_, w)| w).sum();
    let roll = rand::random::<u32>() % total;

    let mut cumulative = 0;
    for (item, weight) in herbs {
        cumulative += weight;
        if roll < cumulative {
            return Some((item, 1));
        }
    }

    None
}

/// Rare drop table.
pub fn roll_rare_table() -> Option<(u32, u32)> {
    let roll = rand::random::<u32>() % 128;

    if roll < 4 {
        // Dragon square shield half (left)
        Some((items::DRAGON_SQUARE_HALF_LEFT, 1))
    } else {
        None
    }
}

/// Drop table manager.
#[derive(Debug, Default)]
pub struct DropTableManager {
    /// Drop tables by NPC ID.
    tables: HashMap<u32, DropTable>,
}

impl DropTableManager {
    /// Create a new drop table manager.
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.load_defaults();
        manager
    }

    /// Load default drop tables.
    pub fn load_defaults(&mut self) {
        // Chicken (NPC ID 3)
        self.register(
            DropTable::new(3)
                .with_guaranteed(DropEntry::new(items::BONES, 1, 1).with_rarity(DropRarity::Always))
                .with_drop(DropEntry::new(12, 1, 1).with_rarity(DropRarity::Always)) // Raw chicken
                .with_drop(DropEntry::new(381, 1, 5).with_rarity(DropRarity::Common)), // Feather (5)
        );

        // Cow (NPC ID 6)
        self.register(
            DropTable::new(6)
                .with_guaranteed(DropEntry::new(items::BONES, 1, 1).with_rarity(DropRarity::Always))
                .with_drop(DropEntry::new(133, 1, 1).with_rarity(DropRarity::Always)) // Cowhide
                .with_drop(DropEntry::new(134, 1, 1).with_rarity(DropRarity::Always)), // Raw beef
        );

        // Goblin (NPC ID 62)
        self.register(
            DropTable::new(62)
                .with_guaranteed(DropEntry::new(items::BONES, 1, 1).with_rarity(DropRarity::Always))
                .with_drop(DropEntry::new(items::COINS, 3, 30).with_amount_range(1, 5))
                .with_drop(DropEntry::new(items::COINS, 10, 20).with_amount_range(6, 15))
                .with_drop(DropEntry::new(items::MIND_RUNE, 1, 5).with_rarity(DropRarity::Uncommon))
                .with_drop(DropEntry::new(items::CHAOS_RUNE, 1, 2).with_rarity(DropRarity::Rare))
                .with_special(SpecialDrop::GemTable, 1),
        );

        // Hill Giant (NPC ID 21)
        self.register(
            DropTable::new(21)
                .with_guaranteed(DropEntry::new(items::BIG_BONES, 1, 1).with_rarity(DropRarity::Always))
                .with_drop(DropEntry::new(items::COINS, 50, 15).with_amount_range(10, 50))
                .with_drop(DropEntry::new(items::NATURE_RUNE, 3, 8).with_rarity(DropRarity::Uncommon))
                .with_drop(DropEntry::new(items::LAW_RUNE, 2, 4).with_rarity(DropRarity::Rare))
                .with_drop(DropEntry::new(items::DEATH_RUNE, 2, 3).with_rarity(DropRarity::Rare))
                .with_drop(DropEntry::new(items::LOBSTER, 1, 3).with_rarity(DropRarity::Uncommon))
                .with_special(SpecialDrop::HerbTable, 5)
                .with_special(SpecialDrop::GemTable, 2),
        );

        // Lesser Demon (NPC ID 22)
        self.register(
            DropTable::new(22)
                .with_guaranteed(DropEntry::new(items::BONES, 1, 1).with_rarity(DropRarity::Always))
                .with_drop(DropEntry::new(items::COINS, 100, 10).with_amount_range(50, 200))
                .with_drop(DropEntry::new(items::FIRE_RUNE, 10, 8).with_rarity(DropRarity::Uncommon))
                .with_drop(DropEntry::new(items::CHAOS_RUNE, 5, 6).with_rarity(DropRarity::Uncommon))
                .with_drop(DropEntry::new(items::DEATH_RUNE, 3, 4).with_rarity(DropRarity::Rare))
                .with_drop(DropEntry::new(items::BLOOD_RUNE, 2, 2).with_rarity(DropRarity::VeryRare))
                .with_drop(DropEntry::new(items::MITHRIL_ORE, 1, 3).with_rarity(DropRarity::Rare))
                .with_special(SpecialDrop::HerbTable, 8)
                .with_special(SpecialDrop::GemTable, 4)
                .with_special(SpecialDrop::RareTable, 1),
        );

        // Greater Demon (NPC ID 24)
        self.register(
            DropTable::new(24)
                .with_guaranteed(DropEntry::new(items::BIG_BONES, 1, 1).with_rarity(DropRarity::Always))
                .with_drop(DropEntry::new(items::COINS, 200, 8).with_amount_range(100, 300))
                .with_drop(DropEntry::new(items::FIRE_RUNE, 15, 6).with_rarity(DropRarity::Uncommon))
                .with_drop(DropEntry::new(items::BLOOD_RUNE, 5, 4).with_rarity(DropRarity::Rare))
                .with_drop(DropEntry::new(items::ADAMANTITE_ORE, 1, 2).with_rarity(DropRarity::VeryRare))
                .with_special(SpecialDrop::HerbTable, 10)
                .with_special(SpecialDrop::GemTable, 6)
                .with_special(SpecialDrop::RareTable, 2),
        );

        // Black Dragon (NPC ID 201)
        self.register(
            DropTable::new(201)
                .with_guaranteed(DropEntry::new(items::DRAGON_BONES, 1, 1).with_rarity(DropRarity::Always))
                .with_drop(DropEntry::new(items::COINS, 500, 5).with_amount_range(200, 500))
                .with_drop(DropEntry::new(items::BLOOD_RUNE, 10, 4).with_rarity(DropRarity::Rare))
                .with_drop(DropEntry::new(items::LAW_RUNE, 10, 4).with_rarity(DropRarity::Rare))
                .with_drop(DropEntry::new(items::ADAMANTITE_ORE, 2, 3).with_rarity(DropRarity::VeryRare))
                .with_drop(DropEntry::new(items::RUNITE_ORE, 1, 1).with_rarity(DropRarity::UltraRare))
                .with_special(SpecialDrop::HerbTable, 12)
                .with_special(SpecialDrop::GemTable, 8)
                .with_special(SpecialDrop::RareTable, 4),
        );

        info!("Loaded {} drop tables", self.tables.len());
    }

    /// Register a drop table.
    pub fn register(&mut self, table: DropTable) {
        self.tables.insert(table.npc_id, table);
    }

    /// Get drop table for an NPC.
    pub fn get(&self, npc_id: u32) -> Option<&DropTable> {
        self.tables.get(&npc_id)
    }

    /// Roll drops for an NPC.
    pub fn roll_drops(&self, npc_id: u32, is_member: bool) -> Vec<(u32, u32)> {
        if let Some(table) = self.get(npc_id) {
            table.roll(is_member)
        } else {
            Vec::new()
        }
    }

    /// Get all NPC IDs with drop tables.
    pub fn get_npc_ids(&self) -> Vec<u32> {
        self.tables.keys().copied().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_drop_entry() {
        let entry = DropEntry::new(items::COINS, 100, 10)
            .with_amount_range(50, 150)
            .with_rarity(DropRarity::Uncommon);

        assert_eq!(entry.item_id, items::COINS);
        assert_eq!(entry.min_amount, 50);
        assert_eq!(entry.max_amount, 150);
        assert_eq!(entry.rarity, DropRarity::Uncommon);

        let amount = entry.roll_amount();
        assert!(amount >= 50 && amount <= 150);
    }

    #[test]
    fn test_drop_table() {
        let table = DropTable::new(1)
            .with_guaranteed(DropEntry::new(items::BONES, 1, 1))
            .with_drop(DropEntry::new(items::COINS, 10, 50))
            .with_drop(DropEntry::new(items::NATURE_RUNE, 1, 10));

        assert_eq!(table.drop_count(), 3);

        let drops = table.roll(true);
        assert!(!drops.is_empty()); // Should at least have guaranteed drop
    }

    #[test]
    fn test_drop_table_manager() {
        let manager = DropTableManager::new();

        assert!(manager.get(3).is_some()); // Chicken
        assert!(manager.get(62).is_some()); // Goblin

        let drops = manager.roll_drops(3, true);
        assert!(!drops.is_empty());
    }

    #[test]
    fn test_gem_table() {
        // Run multiple times to ensure it works
        for _ in 0..10 {
            let _ = roll_gem_table();
        }
    }

    #[test]
    fn test_rarity_ordering() {
        assert!(DropRarity::UltraRare > DropRarity::VeryRare);
        assert!(DropRarity::VeryRare > DropRarity::Rare);
        assert!(DropRarity::Rare > DropRarity::Uncommon);
    }
}
