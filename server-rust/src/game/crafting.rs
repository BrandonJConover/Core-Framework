//! Crafting skill system.
//! Handles leather working, gem cutting, jewelry making, and pottery.

use std::collections::HashMap;
use tracing::info;

/// Crafting categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CraftingCategory {
    Leather,
    Gems,
    Jewelry,
    Pottery,
    Spinning,
    Weaving,
}

/// Leather item types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LeatherItem {
    LeatherGloves,
    LeatherBoots,
    LeatherBody,
    LeatherChaps,
    HardleatherBody,
    StuddedBody,
    StuddedChaps,
    CoifHood,
    DragonhideBody,
    DragonhideChaps,
    DragonhideVambraces,
}

impl LeatherItem {
    /// Get item ID.
    pub fn item_id(&self) -> u32 {
        match self {
            LeatherItem::LeatherGloves => 16,
            LeatherItem::LeatherBoots => 17,
            LeatherItem::LeatherBody => 15,
            LeatherItem::LeatherChaps => 206,
            LeatherItem::HardleatherBody => 207,
            LeatherItem::StuddedBody => 208,
            LeatherItem::StuddedChaps => 209,
            LeatherItem::CoifHood => 210,
            LeatherItem::DragonhideBody => 211,
            LeatherItem::DragonhideChaps => 212,
            LeatherItem::DragonhideVambraces => 213,
        }
    }

    /// Get required crafting level.
    pub fn required_level(&self) -> u8 {
        match self {
            LeatherItem::LeatherGloves => 1,
            LeatherItem::LeatherBoots => 7,
            LeatherItem::LeatherBody => 14,
            LeatherItem::LeatherChaps => 18,
            LeatherItem::HardleatherBody => 28,
            LeatherItem::StuddedBody => 41,
            LeatherItem::StuddedChaps => 44,
            LeatherItem::CoifHood => 38,
            LeatherItem::DragonhideBody => 77,
            LeatherItem::DragonhideChaps => 75,
            LeatherItem::DragonhideVambraces => 57,
        }
    }

    /// Get crafting experience.
    pub fn experience(&self) -> u32 {
        match self {
            LeatherItem::LeatherGloves => 55,
            LeatherItem::LeatherBoots => 65,
            LeatherItem::LeatherBody => 100,
            LeatherItem::LeatherChaps => 110,
            LeatherItem::HardleatherBody => 140,
            LeatherItem::StuddedBody => 160,
            LeatherItem::StuddedChaps => 168,
            LeatherItem::CoifHood => 150,
            LeatherItem::DragonhideBody => 310,
            LeatherItem::DragonhideChaps => 296,
            LeatherItem::DragonhideVambraces => 248,
        }
    }

    /// Get required leather amount.
    pub fn leather_required(&self) -> u8 {
        match self {
            LeatherItem::LeatherGloves => 1,
            LeatherItem::LeatherBoots => 1,
            LeatherItem::LeatherBody => 1,
            LeatherItem::LeatherChaps => 1,
            LeatherItem::HardleatherBody => 1,
            LeatherItem::StuddedBody => 1,
            LeatherItem::StuddedChaps => 1,
            LeatherItem::CoifHood => 1,
            LeatherItem::DragonhideBody => 3,
            LeatherItem::DragonhideChaps => 2,
            LeatherItem::DragonhideVambraces => 1,
        }
    }
}

/// Gem types for cutting.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum GemType {
    Opal,
    Jade,
    RedTopaz,
    Sapphire,
    Emerald,
    Ruby,
    Diamond,
    Dragonstone,
}

impl GemType {
    /// Get uncut gem item ID.
    pub fn uncut_id(&self) -> u32 {
        match self {
            GemType::Opal => 891,
            GemType::Jade => 890,
            GemType::RedTopaz => 889,
            GemType::Sapphire => 160,
            GemType::Emerald => 159,
            GemType::Ruby => 158,
            GemType::Diamond => 157,
            GemType::Dragonstone => 523,
        }
    }

    /// Get cut gem item ID.
    pub fn cut_id(&self) -> u32 {
        match self {
            GemType::Opal => 894,
            GemType::Jade => 893,
            GemType::RedTopaz => 892,
            GemType::Sapphire => 164,
            GemType::Emerald => 163,
            GemType::Ruby => 162,
            GemType::Diamond => 161,
            GemType::Dragonstone => 524,
        }
    }

    /// Get required crafting level.
    pub fn required_level(&self) -> u8 {
        match self {
            GemType::Opal => 1,
            GemType::Jade => 13,
            GemType::RedTopaz => 16,
            GemType::Sapphire => 20,
            GemType::Emerald => 27,
            GemType::Ruby => 63,
            GemType::Diamond => 43,
            GemType::Dragonstone => 55,
        }
    }

    /// Get cutting experience.
    pub fn experience(&self) -> u32 {
        match self {
            GemType::Opal => 63,
            GemType::Jade => 80,
            GemType::RedTopaz => 100,
            GemType::Sapphire => 200,
            GemType::Emerald => 270,
            GemType::Ruby => 340,
            GemType::Diamond => 430,
            GemType::Dragonstone => 550,
        }
    }
}

/// Jewelry types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum JewelryType {
    GoldRing,
    SapphireRing,
    EmeraldRing,
    RubyRing,
    DiamondRing,
    DragonstoneRing,
    GoldNecklace,
    SapphireNecklace,
    EmeraldNecklace,
    RubyNecklace,
    DiamondNecklace,
    DragonstoneNecklace,
    GoldAmulet,
    SapphireAmulet,
    EmeraldAmulet,
    RubyAmulet,
    DiamondAmulet,
    DragonstoneAmulet,
}

impl JewelryType {
    /// Get item ID.
    pub fn item_id(&self) -> u32 {
        match self {
            JewelryType::GoldRing => 283,
            JewelryType::SapphireRing => 284,
            JewelryType::EmeraldRing => 285,
            JewelryType::RubyRing => 286,
            JewelryType::DiamondRing => 287,
            JewelryType::DragonstoneRing => 288,
            JewelryType::GoldNecklace => 289,
            JewelryType::SapphireNecklace => 290,
            JewelryType::EmeraldNecklace => 291,
            JewelryType::RubyNecklace => 292,
            JewelryType::DiamondNecklace => 293,
            JewelryType::DragonstoneNecklace => 294,
            JewelryType::GoldAmulet => 295,
            JewelryType::SapphireAmulet => 296,
            JewelryType::EmeraldAmulet => 297,
            JewelryType::RubyAmulet => 298,
            JewelryType::DiamondAmulet => 299,
            JewelryType::DragonstoneAmulet => 300,
        }
    }

    /// Get required crafting level.
    pub fn required_level(&self) -> u8 {
        match self {
            JewelryType::GoldRing => 5,
            JewelryType::SapphireRing => 20,
            JewelryType::EmeraldRing => 27,
            JewelryType::RubyRing => 34,
            JewelryType::DiamondRing => 43,
            JewelryType::DragonstoneRing => 55,
            JewelryType::GoldNecklace => 6,
            JewelryType::SapphireNecklace => 22,
            JewelryType::EmeraldNecklace => 29,
            JewelryType::RubyNecklace => 40,
            JewelryType::DiamondNecklace => 56,
            JewelryType::DragonstoneNecklace => 72,
            JewelryType::GoldAmulet => 8,
            JewelryType::SapphireAmulet => 24,
            JewelryType::EmeraldAmulet => 31,
            JewelryType::RubyAmulet => 50,
            JewelryType::DiamondAmulet => 70,
            JewelryType::DragonstoneAmulet => 80,
        }
    }

    /// Get crafting experience.
    pub fn experience(&self) -> u32 {
        match self {
            JewelryType::GoldRing => 60,
            JewelryType::SapphireRing => 160,
            JewelryType::EmeraldRing => 220,
            JewelryType::RubyRing => 280,
            JewelryType::DiamondRing => 350,
            JewelryType::DragonstoneRing => 400,
            JewelryType::GoldNecklace => 80,
            JewelryType::SapphireNecklace => 180,
            JewelryType::EmeraldNecklace => 240,
            JewelryType::RubyNecklace => 300,
            JewelryType::DiamondNecklace => 420,
            JewelryType::DragonstoneNecklace => 500,
            JewelryType::GoldAmulet => 120,
            JewelryType::SapphireAmulet => 260,
            JewelryType::EmeraldAmulet => 340,
            JewelryType::RubyAmulet => 420,
            JewelryType::DiamondAmulet => 500,
            JewelryType::DragonstoneAmulet => 600,
        }
    }

    /// Get required gem (if any).
    pub fn required_gem(&self) -> Option<GemType> {
        match self {
            JewelryType::GoldRing | JewelryType::GoldNecklace | JewelryType::GoldAmulet => None,
            JewelryType::SapphireRing
            | JewelryType::SapphireNecklace
            | JewelryType::SapphireAmulet => Some(GemType::Sapphire),
            JewelryType::EmeraldRing
            | JewelryType::EmeraldNecklace
            | JewelryType::EmeraldAmulet => Some(GemType::Emerald),
            JewelryType::RubyRing | JewelryType::RubyNecklace | JewelryType::RubyAmulet => {
                Some(GemType::Ruby)
            }
            JewelryType::DiamondRing
            | JewelryType::DiamondNecklace
            | JewelryType::DiamondAmulet => Some(GemType::Diamond),
            JewelryType::DragonstoneRing
            | JewelryType::DragonstoneNecklace
            | JewelryType::DragonstoneAmulet => Some(GemType::Dragonstone),
        }
    }
}

/// Pottery items.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PotteryItem {
    Pot,
    PieDish,
    Bowl,
    PlantPot,
    PotLid,
}

impl PotteryItem {
    /// Get unfired item ID.
    pub fn unfired_id(&self) -> u32 {
        match self {
            PotteryItem::Pot => 279,
            PotteryItem::PieDish => 280,
            PotteryItem::Bowl => 281,
            PotteryItem::PlantPot => 1010,
            PotteryItem::PotLid => 1011,
        }
    }

    /// Get fired item ID.
    pub fn fired_id(&self) -> u32 {
        match self {
            PotteryItem::Pot => 135,
            PotteryItem::PieDish => 251,
            PotteryItem::Bowl => 341,
            PotteryItem::PlantPot => 1012,
            PotteryItem::PotLid => 1013,
        }
    }

    /// Get required crafting level.
    pub fn required_level(&self) -> u8 {
        match self {
            PotteryItem::Pot => 1,
            PotteryItem::PieDish => 7,
            PotteryItem::Bowl => 8,
            PotteryItem::PlantPot => 19,
            PotteryItem::PotLid => 25,
        }
    }

    /// Get crafting experience (for shaping).
    pub fn shape_experience(&self) -> u32 {
        match self {
            PotteryItem::Pot => 25,
            PotteryItem::PieDish => 30,
            PotteryItem::Bowl => 33,
            PotteryItem::PlantPot => 38,
            PotteryItem::PotLid => 40,
        }
    }

    /// Get crafting experience (for firing).
    pub fn fire_experience(&self) -> u32 {
        match self {
            PotteryItem::Pot => 25,
            PotteryItem::PieDish => 30,
            PotteryItem::Bowl => 33,
            PotteryItem::PlantPot => 38,
            PotteryItem::PotLid => 40,
        }
    }
}

/// Item IDs for crafting materials.
pub const LEATHER_ID: u32 = 148;
pub const HARD_LEATHER_ID: u32 = 147;
pub const DRAGON_LEATHER_ID: u32 = 1073;
pub const GOLD_BAR_ID: u32 = 172;
pub const SILVER_BAR_ID: u32 = 384;
pub const CLAY_ID: u32 = 149;
pub const SOFT_CLAY_ID: u32 = 243;
pub const NEEDLE_ID: u32 = 39;
pub const THREAD_ID: u32 = 40;
pub const CHISEL_ID: u32 = 167;
pub const RING_MOULD_ID: u32 = 293;
pub const NECKLACE_MOULD_ID: u32 = 294;
pub const AMULET_MOULD_ID: u32 = 295;

/// Manager for crafting system.
#[derive(Debug, Default)]
pub struct CraftingManager {
    /// Cached gem data.
    gems: HashMap<u32, GemType>,
}

impl CraftingManager {
    /// Create a new crafting manager.
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.load_defaults();
        manager
    }

    /// Load default data.
    pub fn load_defaults(&mut self) {
        // Map uncut gem IDs to gem types
        for gem in [
            GemType::Opal,
            GemType::Jade,
            GemType::RedTopaz,
            GemType::Sapphire,
            GemType::Emerald,
            GemType::Ruby,
            GemType::Diamond,
            GemType::Dragonstone,
        ] {
            self.gems.insert(gem.uncut_id(), gem);
        }

        info!("Loaded {} gem types for crafting", self.gems.len());
    }

    /// Get gem type from uncut item ID.
    pub fn get_gem(&self, uncut_id: u32) -> Option<GemType> {
        self.gems.get(&uncut_id).copied()
    }

    /// Check if player can cut a gem.
    pub fn can_cut_gem(&self, crafting_level: u8, gem: GemType) -> bool {
        crafting_level >= gem.required_level()
    }

    /// Check if player can craft leather item.
    pub fn can_craft_leather(&self, crafting_level: u8, item: LeatherItem) -> bool {
        crafting_level >= item.required_level()
    }

    /// Check if player can make jewelry.
    pub fn can_make_jewelry(&self, crafting_level: u8, jewelry: JewelryType) -> bool {
        crafting_level >= jewelry.required_level()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gem_levels() {
        assert_eq!(GemType::Opal.required_level(), 1);
        assert_eq!(GemType::Dragonstone.required_level(), 55);
    }

    #[test]
    fn test_leather_levels() {
        assert_eq!(LeatherItem::LeatherGloves.required_level(), 1);
        assert_eq!(LeatherItem::DragonhideBody.required_level(), 77);
    }

    #[test]
    fn test_jewelry_gems() {
        assert_eq!(JewelryType::GoldRing.required_gem(), None);
        assert_eq!(
            JewelryType::SapphireRing.required_gem(),
            Some(GemType::Sapphire)
        );
        assert_eq!(
            JewelryType::DiamondAmulet.required_gem(),
            Some(GemType::Diamond)
        );
    }

    #[test]
    fn test_crafting_manager() {
        let manager = CraftingManager::new();
        assert_eq!(manager.get_gem(160), Some(GemType::Sapphire));
        assert!(manager.can_cut_gem(20, GemType::Sapphire));
        assert!(!manager.can_cut_gem(10, GemType::Sapphire));
    }
}
