//! Fishing skill system.
//! Handles fishing spots, catch mechanics, and fish definitions.

use std::collections::HashMap;
use tracing::info;

use super::entity::Position;

/// Fishing equipment types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FishingEquipment {
    /// Small fishing net.
    SmallNet,
    /// Fishing rod (requires bait).
    FishingRod,
    /// Fly fishing rod (requires feathers).
    FlyFishingRod,
    /// Harpoon.
    Harpoon,
    /// Lobster pot.
    LobsterPot,
    /// Big fishing net.
    BigNet,
    /// Oily fishing rod.
    OilyFishingRod,
}

impl FishingEquipment {
    /// Get the item ID for this equipment.
    pub fn item_id(&self) -> u32 {
        match self {
            FishingEquipment::SmallNet => 376,
            FishingEquipment::FishingRod => 377,
            FishingEquipment::FlyFishingRod => 378,
            FishingEquipment::Harpoon => 379,
            FishingEquipment::LobsterPot => 375,
            FishingEquipment::BigNet => 548,
            FishingEquipment::OilyFishingRod => 589,
        }
    }

    /// Get required bait item ID (if any).
    pub fn bait_id(&self) -> Option<u32> {
        match self {
            FishingEquipment::FishingRod => Some(380), // Fishing bait
            FishingEquipment::FlyFishingRod => Some(381), // Feather
            FishingEquipment::OilyFishingRod => Some(380),
            _ => None,
        }
    }
}

/// A type of fish that can be caught.
#[derive(Debug, Clone)]
pub struct FishDef {
    /// Item ID when caught.
    pub item_id: u32,
    /// Fish name.
    pub name: String,
    /// Required fishing level.
    pub level: u8,
    /// Experience gained.
    pub experience: u32,
    /// Required equipment.
    pub equipment: FishingEquipment,
    /// Catch weight (higher = harder to catch).
    pub difficulty: u8,
}

impl FishDef {
    /// Create a new fish definition.
    pub fn new(
        item_id: u32,
        name: &str,
        level: u8,
        experience: u32,
        equipment: FishingEquipment,
        difficulty: u8,
    ) -> Self {
        Self {
            item_id,
            name: name.to_string(),
            level,
            experience,
            equipment,
            difficulty,
        }
    }
}

/// A fishing spot in the world.
#[derive(Debug, Clone)]
pub struct FishingSpot {
    /// Position of the spot.
    pub position: Position,
    /// Available fish at this spot.
    pub fish: Vec<u32>, // Fish definition IDs
    /// Available fishing options.
    pub options: Vec<(String, FishingEquipment)>,
}

impl FishingSpot {
    /// Create a new fishing spot.
    pub fn new(position: Position) -> Self {
        Self {
            position,
            fish: Vec::new(),
            options: Vec::new(),
        }
    }

    /// Add a fishing option.
    pub fn with_option(mut self, name: &str, equipment: FishingEquipment) -> Self {
        self.options.push((name.to_string(), equipment));
        self
    }

    /// Add available fish.
    pub fn with_fish(mut self, fish_ids: Vec<u32>) -> Self {
        self.fish = fish_ids;
        self
    }
}

/// Calculate fishing success chance.
pub fn calculate_catch_chance(fishing_level: u8, fish_difficulty: u8) -> f64 {
    let level = fishing_level as f64;
    let difficulty = fish_difficulty as f64;

    // Base chance increases with level, decreases with difficulty
    let base_chance = (level - difficulty + 50.0) / 100.0;
    base_chance.clamp(0.1, 0.9)
}

/// Select which fish to catch based on level.
pub fn select_fish<'a>(fishing_level: u8, available_fish: &'a [&'a FishDef]) -> Option<&'a FishDef> {
    // Filter fish the player can catch
    let catchable: Vec<_> = available_fish
        .iter()
        .filter(|f| f.level <= fishing_level)
        .collect();

    if catchable.is_empty() {
        return None;
    }

    // Weight higher level fish more as player level increases
    let total_weight: u32 = catchable
        .iter()
        .map(|f| (fishing_level - f.level + 1) as u32)
        .sum();

    let mut roll = rand::random::<u32>() % total_weight;
    for fish in catchable {
        let weight = (fishing_level - fish.level + 1) as u32;
        if roll < weight {
            return Some(fish);
        }
        roll -= weight;
    }

    available_fish.first().copied()
}

/// Manager for fishing system.
#[derive(Debug, Default)]
pub struct FishingManager {
    /// Fish definitions by ID.
    fish_defs: HashMap<u32, FishDef>,
    /// Fishing spots by location.
    spots: HashMap<(i32, i32), FishingSpot>,
}

impl FishingManager {
    /// Create a new fishing manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a fish definition.
    pub fn register_fish(&mut self, def: FishDef) {
        self.fish_defs.insert(def.item_id, def);
    }

    /// Get a fish definition.
    pub fn get_fish(&self, id: u32) -> Option<&FishDef> {
        self.fish_defs.get(&id)
    }

    /// Register a fishing spot.
    pub fn register_spot(&mut self, spot: FishingSpot) {
        let key = (spot.position.x, spot.position.y);
        self.spots.insert(key, spot);
    }

    /// Get fishing spot at location.
    pub fn spot_at(&self, x: i32, y: i32) -> Option<&FishingSpot> {
        self.spots.get(&(x, y))
    }

    /// Load default fish definitions.
    pub fn load_defaults(&mut self) {
        // Net fishing
        self.register_fish(FishDef::new(350, "Shrimp", 1, 40, FishingEquipment::SmallNet, 1));
        self.register_fish(FishDef::new(351, "Anchovies", 15, 160, FishingEquipment::SmallNet, 15));

        // Bait fishing
        self.register_fish(FishDef::new(352, "Sardine", 5, 80, FishingEquipment::FishingRod, 5));
        self.register_fish(FishDef::new(353, "Herring", 10, 120, FishingEquipment::FishingRod, 10));
        self.register_fish(FishDef::new(354, "Pike", 25, 240, FishingEquipment::FishingRod, 25));

        // Fly fishing
        self.register_fish(FishDef::new(358, "Trout", 20, 200, FishingEquipment::FlyFishingRod, 20));
        self.register_fish(FishDef::new(359, "Salmon", 30, 280, FishingEquipment::FlyFishingRod, 30));

        // Harpoon fishing
        self.register_fish(FishDef::new(361, "Tuna", 35, 320, FishingEquipment::Harpoon, 35));
        self.register_fish(FishDef::new(363, "Swordfish", 50, 400, FishingEquipment::Harpoon, 50));
        self.register_fish(FishDef::new(545, "Shark", 76, 440, FishingEquipment::Harpoon, 76));

        // Lobster pot
        self.register_fish(FishDef::new(372, "Lobster", 40, 360, FishingEquipment::LobsterPot, 40));

        // Big net
        self.register_fish(FishDef::new(545, "Bass", 46, 400, FishingEquipment::BigNet, 46));
        self.register_fish(FishDef::new(622, "Mackerel", 16, 80, FishingEquipment::BigNet, 16));

        // Lava eel
        self.register_fish(FishDef::new(590, "Lava eel", 53, 300, FishingEquipment::OilyFishingRod, 53));

        info!("Loaded {} fish definitions", self.fish_defs.len());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_catch_chance() {
        // High level vs low difficulty = high chance
        let chance = calculate_catch_chance(99, 1);
        assert!(chance > 0.8);

        // Low level vs high difficulty = low chance
        let chance2 = calculate_catch_chance(10, 50);
        assert!(chance2 < 0.2);
    }

    #[test]
    fn test_fishing_manager() {
        let mut manager = FishingManager::new();
        manager.load_defaults();

        let shrimp = manager.get_fish(350);
        assert!(shrimp.is_some());
        assert_eq!(shrimp.unwrap().name, "Shrimp");
    }
}
