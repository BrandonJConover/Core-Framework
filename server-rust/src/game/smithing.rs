//! Smithing skill system.
//! Handles smelting ores into bars and smithing bars into equipment.

use std::collections::HashMap;
use tracing::info;

/// Metal bar types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BarType {
    Bronze,
    Iron,
    Silver,
    Steel,
    Gold,
    Mithril,
    Adamantite,
    Runite,
}

impl BarType {
    /// Get the item ID for this bar.
    pub fn item_id(&self) -> u32 {
        match self {
            BarType::Bronze => 169,
            BarType::Iron => 170,
            BarType::Silver => 384,
            BarType::Steel => 171,
            BarType::Gold => 172,
            BarType::Mithril => 173,
            BarType::Adamantite => 174,
            BarType::Runite => 408,
        }
    }

    /// Get the required smithing level to smelt.
    pub fn smelt_level(&self) -> u8 {
        match self {
            BarType::Bronze => 1,
            BarType::Iron => 15,
            BarType::Silver => 20,
            BarType::Steel => 30,
            BarType::Gold => 40,
            BarType::Mithril => 50,
            BarType::Adamantite => 70,
            BarType::Runite => 85,
        }
    }

    /// Get smelting experience.
    pub fn smelt_experience(&self) -> u32 {
        match self {
            BarType::Bronze => 25,
            BarType::Iron => 50,
            BarType::Silver => 55,
            BarType::Steel => 70,
            BarType::Gold => 90,
            BarType::Mithril => 100,
            BarType::Adamantite => 150,
            BarType::Runite => 200,
        }
    }
}

/// Smelting recipe definition.
#[derive(Debug, Clone)]
pub struct SmeltRecipe {
    /// Bar produced.
    pub bar: BarType,
    /// Primary ore item ID.
    pub primary_ore: u32,
    /// Secondary ore item ID (None for silver/gold).
    pub secondary_ore: Option<u32>,
    /// Amount of primary ore needed.
    pub primary_amount: u8,
    /// Amount of secondary ore needed.
    pub secondary_amount: u8,
}

impl SmeltRecipe {
    /// Create a new smelting recipe.
    pub fn new(
        bar: BarType,
        primary_ore: u32,
        secondary_ore: Option<u32>,
        primary_amount: u8,
        secondary_amount: u8,
    ) -> Self {
        Self {
            bar,
            primary_ore,
            secondary_ore,
            primary_amount,
            secondary_amount,
        }
    }
}

/// Smithable item categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SmithCategory {
    Dagger,
    Axe,
    Mace,
    MediumHelmet,
    Sword,
    Scimitar,
    LongSword,
    BattleAxe,
    ChainBody,
    KiteShield,
    TwoHandedSword,
    PlateSkirt,
    PlateLegs,
    PlateBody,
    FullHelmet,
    SquareShield,
    Nails,
    DartTips,
    ArrowHeads,
}

impl SmithCategory {
    /// Get bars required for this category.
    pub fn bars_required(&self) -> u8 {
        match self {
            SmithCategory::Dagger | SmithCategory::Nails |
            SmithCategory::ArrowHeads | SmithCategory::DartTips => 1,
            SmithCategory::Axe | SmithCategory::Mace |
            SmithCategory::MediumHelmet | SmithCategory::Sword => 1,
            SmithCategory::Scimitar | SmithCategory::LongSword => 2,
            SmithCategory::BattleAxe | SmithCategory::ChainBody |
            SmithCategory::KiteShield | SmithCategory::TwoHandedSword => 3,
            SmithCategory::PlateSkirt | SmithCategory::PlateLegs |
            SmithCategory::FullHelmet | SmithCategory::SquareShield => 3,
            SmithCategory::PlateBody => 5,
        }
    }

    /// Get smithing level offset for this category (added to bar base level).
    pub fn level_offset(&self) -> u8 {
        match self {
            SmithCategory::Dagger => 0,
            SmithCategory::Axe => 0,
            SmithCategory::Mace => 2,
            SmithCategory::MediumHelmet => 3,
            SmithCategory::Sword => 4,
            SmithCategory::Nails => 4,
            SmithCategory::DartTips => 4,
            SmithCategory::Scimitar => 5,
            SmithCategory::ArrowHeads => 5,
            SmithCategory::LongSword => 6,
            SmithCategory::FullHelmet => 7,
            SmithCategory::SquareShield => 8,
            SmithCategory::BattleAxe => 10,
            SmithCategory::ChainBody => 11,
            SmithCategory::KiteShield => 12,
            SmithCategory::TwoHandedSword => 14,
            SmithCategory::PlateSkirt => 16,
            SmithCategory::PlateLegs => 16,
            SmithCategory::PlateBody => 18,
        }
    }

    /// Get base experience multiplier.
    pub fn exp_multiplier(&self) -> f64 {
        self.bars_required() as f64
    }
}

/// A smithable item definition.
#[derive(Debug, Clone)]
pub struct SmithItem {
    /// Item ID produced.
    pub item_id: u32,
    /// Item name.
    pub name: String,
    /// Bar type required.
    pub bar: BarType,
    /// Category of item.
    pub category: SmithCategory,
    /// Amount produced per smith.
    pub amount: u8,
}

impl SmithItem {
    /// Create a new smith item.
    pub fn new(
        item_id: u32,
        name: &str,
        bar: BarType,
        category: SmithCategory,
        amount: u8,
    ) -> Self {
        Self {
            item_id,
            name: name.to_string(),
            bar,
            category,
            amount,
        }
    }

    /// Get required smithing level.
    pub fn required_level(&self) -> u8 {
        let base_level = match self.bar {
            BarType::Bronze => 1,
            BarType::Iron => 15,
            BarType::Steel => 30,
            BarType::Mithril => 50,
            BarType::Adamantite => 70,
            BarType::Runite => 85,
            _ => 1,
        };
        base_level + self.category.level_offset()
    }

    /// Get experience for smithing this item.
    pub fn experience(&self) -> u32 {
        let base_exp = match self.bar {
            BarType::Bronze => 25,
            BarType::Iron => 50,
            BarType::Steel => 75,
            BarType::Mithril => 100,
            BarType::Adamantite => 125,
            BarType::Runite => 150,
            _ => 25,
        };
        (base_exp as f64 * self.category.exp_multiplier()) as u32
    }
}

/// Calculate iron smelting success chance.
pub fn iron_smelt_chance(smithing_level: u8) -> f64 {
    // Iron has 50% base fail rate, improves with level
    let base_chance = 0.5 + (smithing_level as f64 - 15.0) * 0.01;
    base_chance.clamp(0.5, 0.8)
}

/// Manager for smithing system.
#[derive(Debug, Default)]
pub struct SmithingManager {
    /// Smelting recipes by primary ore ID.
    smelt_recipes: HashMap<u32, SmeltRecipe>,
    /// Smithable items by item ID.
    smith_items: HashMap<u32, SmithItem>,
}

impl SmithingManager {
    /// Create a new smithing manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a smelting recipe.
    pub fn register_smelt(&mut self, recipe: SmeltRecipe) {
        self.smelt_recipes.insert(recipe.primary_ore, recipe);
    }

    /// Get smelting recipe for ore.
    pub fn get_smelt_recipe(&self, ore_id: u32) -> Option<&SmeltRecipe> {
        self.smelt_recipes.get(&ore_id)
    }

    /// Register a smithable item.
    pub fn register_smith_item(&mut self, item: SmithItem) {
        self.smith_items.insert(item.item_id, item);
    }

    /// Get smith items for a bar type.
    pub fn items_for_bar(&self, bar: BarType) -> Vec<&SmithItem> {
        self.smith_items
            .values()
            .filter(|item| item.bar == bar)
            .collect()
    }

    /// Load default recipes.
    pub fn load_defaults(&mut self) {
        // Smelting recipes
        self.register_smelt(SmeltRecipe::new(
            BarType::Bronze, 150, Some(202), 1, 1, // Copper + Tin
        ));
        self.register_smelt(SmeltRecipe::new(
            BarType::Iron, 151, None, 1, 0,
        ));
        self.register_smelt(SmeltRecipe::new(
            BarType::Silver, 383, None, 1, 0,
        ));
        self.register_smelt(SmeltRecipe::new(
            BarType::Steel, 151, Some(155), 1, 2, // Iron + 2 Coal
        ));
        self.register_smelt(SmeltRecipe::new(
            BarType::Gold, 152, None, 1, 0,
        ));
        self.register_smelt(SmeltRecipe::new(
            BarType::Mithril, 153, Some(155), 1, 4, // Mithril + 4 Coal
        ));
        self.register_smelt(SmeltRecipe::new(
            BarType::Adamantite, 154, Some(155), 1, 6, // Adamantite + 6 Coal
        ));
        self.register_smelt(SmeltRecipe::new(
            BarType::Runite, 409, Some(155), 1, 8, // Runite + 8 Coal
        ));

        // Bronze items
        self.register_smith_item(SmithItem::new(62, "Bronze Dagger", BarType::Bronze, SmithCategory::Dagger, 1));
        self.register_smith_item(SmithItem::new(87, "Bronze Axe", BarType::Bronze, SmithCategory::Axe, 1));
        self.register_smith_item(SmithItem::new(94, "Bronze Mace", BarType::Bronze, SmithCategory::Mace, 1));
        self.register_smith_item(SmithItem::new(5, "Bronze Medium Helmet", BarType::Bronze, SmithCategory::MediumHelmet, 1));
        self.register_smith_item(SmithItem::new(66, "Bronze Short Sword", BarType::Bronze, SmithCategory::Sword, 1));
        self.register_smith_item(SmithItem::new(82, "Bronze Scimitar", BarType::Bronze, SmithCategory::Scimitar, 1));
        self.register_smith_item(SmithItem::new(70, "Bronze Long Sword", BarType::Bronze, SmithCategory::LongSword, 1));
        self.register_smith_item(SmithItem::new(205, "Bronze Chain Mail Body", BarType::Bronze, SmithCategory::ChainBody, 1));
        self.register_smith_item(SmithItem::new(102, "Bronze Kite Shield", BarType::Bronze, SmithCategory::KiteShield, 1));
        self.register_smith_item(SmithItem::new(74, "Bronze 2-handed Sword", BarType::Bronze, SmithCategory::TwoHandedSword, 1));
        self.register_smith_item(SmithItem::new(214, "Bronze Plate Mail Body", BarType::Bronze, SmithCategory::PlateBody, 1));

        info!(
            "Loaded {} smelting recipes and {} smithable items",
            self.smelt_recipes.len(),
            self.smith_items.len()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bar_levels() {
        assert_eq!(BarType::Bronze.smelt_level(), 1);
        assert_eq!(BarType::Runite.smelt_level(), 85);
    }

    #[test]
    fn test_smith_item_level() {
        let dagger = SmithItem::new(62, "Bronze Dagger", BarType::Bronze, SmithCategory::Dagger, 1);
        assert_eq!(dagger.required_level(), 1);

        let platebody = SmithItem::new(214, "Bronze Platebody", BarType::Bronze, SmithCategory::PlateBody, 1);
        assert_eq!(platebody.required_level(), 19);
    }

    #[test]
    fn test_iron_smelt_chance() {
        let low_level = iron_smelt_chance(15);
        assert!((low_level - 0.5).abs() < 0.01);

        let high_level = iron_smelt_chance(50);
        assert!(high_level > 0.7);
    }

    #[test]
    fn test_smithing_manager() {
        let mut manager = SmithingManager::new();
        manager.load_defaults();

        // Check bronze smelting recipe
        let recipe = manager.get_smelt_recipe(150);
        assert!(recipe.is_some());
        assert_eq!(recipe.unwrap().bar, BarType::Bronze);
    }
}
