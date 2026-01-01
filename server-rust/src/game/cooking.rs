//! Cooking skill system.
//! Handles cooking mechanics, burn rates, and food definitions.

use std::collections::HashMap;
use tracing::{debug, info};

/// Cooking heat sources.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeatSource {
    /// Regular fire.
    Fire,
    /// Cooking range (lower burn rate).
    Range,
    /// Sinister Stranger's cooking.
    SinisterStranger,
}

impl HeatSource {
    /// Get burn rate modifier (lower is better).
    pub fn burn_modifier(&self) -> f64 {
        match self {
            HeatSource::Fire => 1.0,
            HeatSource::Range => 0.8, // 20% less likely to burn on range
            HeatSource::SinisterStranger => 0.0, // Never burns
        }
    }
}

/// A cookable food item definition.
#[derive(Debug, Clone)]
pub struct CookableDef {
    /// Raw item ID.
    pub raw_id: u32,
    /// Cooked item ID.
    pub cooked_id: u32,
    /// Burnt item ID.
    pub burnt_id: u32,
    /// Food name.
    pub name: String,
    /// Required cooking level.
    pub level: u8,
    /// Experience gained on success.
    pub experience: u32,
    /// Level at which burning stops.
    pub stop_burn_level: u8,
}

impl CookableDef {
    /// Create a new cookable definition.
    pub fn new(
        raw_id: u32,
        cooked_id: u32,
        burnt_id: u32,
        name: &str,
        level: u8,
        experience: u32,
        stop_burn_level: u8,
    ) -> Self {
        Self {
            raw_id,
            cooked_id,
            burnt_id,
            name: name.to_string(),
            level,
            experience,
            stop_burn_level,
        }
    }
}

/// Cooked food definition for eating.
#[derive(Debug, Clone)]
pub struct FoodDef {
    /// Item ID.
    pub item_id: u32,
    /// Food name.
    pub name: String,
    /// Hitpoints healed.
    pub heal_amount: u8,
}

impl FoodDef {
    /// Create a new food definition.
    pub fn new(item_id: u32, name: &str, heal_amount: u8) -> Self {
        Self {
            item_id,
            name: name.to_string(),
            heal_amount,
        }
    }
}

/// Calculate burn chance when cooking.
pub fn calculate_burn_chance(
    cooking_level: u8,
    required_level: u8,
    stop_burn_level: u8,
    heat_source: HeatSource,
) -> f64 {
    // Never burn if above stop burn level
    if cooking_level >= stop_burn_level {
        return 0.0;
    }

    let level_diff = cooking_level.saturating_sub(required_level) as f64;
    let total_range = (stop_burn_level - required_level) as f64;

    // Base burn chance decreases linearly from required level to stop burn level
    let base_chance = if total_range > 0.0 {
        1.0 - (level_diff / total_range)
    } else {
        0.5
    };

    // Apply heat source modifier
    (base_chance * heat_source.burn_modifier()).clamp(0.0, 0.9)
}

/// Manager for cooking system.
#[derive(Debug, Default)]
pub struct CookingManager {
    /// Cookable definitions by raw item ID.
    cookables: HashMap<u32, CookableDef>,
    /// Food definitions by item ID.
    foods: HashMap<u32, FoodDef>,
}

impl CookingManager {
    /// Create a new cooking manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a cookable item.
    pub fn register_cookable(&mut self, def: CookableDef) {
        self.cookables.insert(def.raw_id, def);
    }

    /// Get cookable definition by raw item ID.
    pub fn get_cookable(&self, raw_id: u32) -> Option<&CookableDef> {
        self.cookables.get(&raw_id)
    }

    /// Register a food item.
    pub fn register_food(&mut self, def: FoodDef) {
        self.foods.insert(def.item_id, def);
    }

    /// Get food definition by item ID.
    pub fn get_food(&self, item_id: u32) -> Option<&FoodDef> {
        self.foods.get(&item_id)
    }

    /// Load default cooking definitions.
    pub fn load_defaults(&mut self) {
        // Fish
        self.register_cookable(CookableDef::new(
            350, 352, 353, "Shrimp", 1, 120, 34,
        ));
        self.register_cookable(CookableDef::new(
            351, 354, 355, "Anchovies", 1, 120, 34,
        ));
        self.register_cookable(CookableDef::new(
            356, 358, 359, "Sardine", 1, 160, 38,
        ));
        self.register_cookable(CookableDef::new(
            360, 362, 363, "Herring", 5, 200, 41,
        ));
        self.register_cookable(CookableDef::new(
            364, 366, 367, "Trout", 15, 280, 50,
        ));
        self.register_cookable(CookableDef::new(
            368, 370, 371, "Pike", 20, 320, 53,
        ));
        self.register_cookable(CookableDef::new(
            372, 374, 375, "Salmon", 25, 360, 58,
        ));
        self.register_cookable(CookableDef::new(
            376, 378, 379, "Tuna", 30, 400, 63,
        ));
        self.register_cookable(CookableDef::new(
            380, 382, 383, "Lobster", 40, 480, 74,
        ));
        self.register_cookable(CookableDef::new(
            384, 386, 387, "Swordfish", 45, 560, 86,
        ));
        self.register_cookable(CookableDef::new(
            388, 390, 391, "Shark", 80, 840, 99,
        ));

        // Meat
        self.register_cookable(CookableDef::new(
            132, 133, 134, "Meat", 1, 120, 31,
        ));
        self.register_cookable(CookableDef::new(
            135, 136, 137, "Chicken", 1, 120, 31,
        ));

        // Bread
        self.register_cookable(CookableDef::new(
            136, 138, 139, "Bread", 1, 160, 34,
        ));

        // Pies
        self.register_cookable(CookableDef::new(
            250, 252, 253, "Redberry pie", 10, 312, 45,
        ));
        self.register_cookable(CookableDef::new(
            254, 256, 257, "Meat pie", 20, 440, 55,
        ));
        self.register_cookable(CookableDef::new(
            258, 260, 261, "Apple pie", 30, 520, 65,
        ));

        // Food healing values
        self.register_food(FoodDef::new(352, "Shrimp", 3));
        self.register_food(FoodDef::new(354, "Anchovies", 1));
        self.register_food(FoodDef::new(358, "Sardine", 4));
        self.register_food(FoodDef::new(362, "Herring", 5));
        self.register_food(FoodDef::new(366, "Trout", 7));
        self.register_food(FoodDef::new(370, "Pike", 8));
        self.register_food(FoodDef::new(374, "Salmon", 9));
        self.register_food(FoodDef::new(378, "Tuna", 10));
        self.register_food(FoodDef::new(382, "Lobster", 12));
        self.register_food(FoodDef::new(386, "Swordfish", 14));
        self.register_food(FoodDef::new(390, "Shark", 20));
        self.register_food(FoodDef::new(133, "Cooked meat", 3));
        self.register_food(FoodDef::new(138, "Bread", 4));
        self.register_food(FoodDef::new(252, "Redberry pie", 6));
        self.register_food(FoodDef::new(256, "Meat pie", 8));
        self.register_food(FoodDef::new(260, "Apple pie", 10));

        info!(
            "Loaded {} cookable items and {} food items",
            self.cookables.len(),
            self.foods.len()
        );
    }
}

/// Calculate experience for successful cooking.
pub fn cooking_experience(base_exp: u32, is_range: bool) -> u32 {
    base_exp
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_burn_chance() {
        // At required level, high burn chance
        let chance = calculate_burn_chance(1, 1, 34, HeatSource::Fire);
        assert!(chance > 0.5);

        // Well above required, low burn chance
        let chance2 = calculate_burn_chance(30, 1, 34, HeatSource::Fire);
        assert!(chance2 < 0.2);

        // At stop burn level, no burn
        let chance3 = calculate_burn_chance(34, 1, 34, HeatSource::Fire);
        assert_eq!(chance3, 0.0);

        // Range has lower burn chance
        let fire_chance = calculate_burn_chance(15, 1, 34, HeatSource::Fire);
        let range_chance = calculate_burn_chance(15, 1, 34, HeatSource::Range);
        assert!(range_chance < fire_chance);
    }

    #[test]
    fn test_cooking_manager() {
        let mut manager = CookingManager::new();
        manager.load_defaults();

        let shrimp = manager.get_cookable(350);
        assert!(shrimp.is_some());
        assert_eq!(shrimp.unwrap().level, 1);

        let cooked = manager.get_food(352);
        assert!(cooked.is_some());
        assert_eq!(cooked.unwrap().heal_amount, 3);
    }
}
