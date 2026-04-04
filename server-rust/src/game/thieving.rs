//! Thieving skill system.
//! Handles pickpocketing NPCs and stealing from stalls/chests.

use std::collections::HashMap;
use tracing::info;

/// Pickpocket target types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PickpocketTarget {
    Man,
    Farmer,
    Warrior,
    Rogue,
    Guard,
    Knight,
    Watchman,
    Paladin,
    Gnome,
    Hero,
}

impl PickpocketTarget {
    /// Get required thieving level.
    pub fn required_level(&self) -> u8 {
        match self {
            PickpocketTarget::Man => 1,
            PickpocketTarget::Farmer => 10,
            PickpocketTarget::Warrior => 25,
            PickpocketTarget::Rogue => 32,
            PickpocketTarget::Guard => 40,
            PickpocketTarget::Knight => 55,
            PickpocketTarget::Watchman => 65,
            PickpocketTarget::Paladin => 70,
            PickpocketTarget::Gnome => 75,
            PickpocketTarget::Hero => 80,
        }
    }

    /// Get thieving experience.
    pub fn experience(&self) -> u32 {
        match self {
            PickpocketTarget::Man => 32,
            PickpocketTarget::Farmer => 57,
            PickpocketTarget::Warrior => 100,
            PickpocketTarget::Rogue => 140,
            PickpocketTarget::Guard => 188,
            PickpocketTarget::Knight => 268,
            PickpocketTarget::Watchman => 380,
            PickpocketTarget::Paladin => 456,
            PickpocketTarget::Gnome => 480,
            PickpocketTarget::Hero => 550,
        }
    }

    /// Get stun time in ticks if caught.
    pub fn stun_time(&self) -> u32 {
        match self {
            PickpocketTarget::Man => 5,
            PickpocketTarget::Farmer => 5,
            PickpocketTarget::Warrior => 5,
            PickpocketTarget::Rogue => 5,
            PickpocketTarget::Guard => 5,
            PickpocketTarget::Knight => 5,
            PickpocketTarget::Watchman => 5,
            PickpocketTarget::Paladin => 5,
            PickpocketTarget::Gnome => 5,
            PickpocketTarget::Hero => 6,
        }
    }

    /// Get damage if caught.
    pub fn stun_damage(&self) -> u8 {
        match self {
            PickpocketTarget::Man => 1,
            PickpocketTarget::Farmer => 1,
            PickpocketTarget::Warrior => 2,
            PickpocketTarget::Rogue => 2,
            PickpocketTarget::Guard => 2,
            PickpocketTarget::Knight => 3,
            PickpocketTarget::Watchman => 3,
            PickpocketTarget::Paladin => 3,
            PickpocketTarget::Gnome => 1,
            PickpocketTarget::Hero => 4,
        }
    }

    /// Get base success chance at required level.
    pub fn base_success_rate(&self) -> f64 {
        match self {
            PickpocketTarget::Man => 0.85,
            PickpocketTarget::Farmer => 0.80,
            PickpocketTarget::Warrior => 0.75,
            PickpocketTarget::Rogue => 0.70,
            PickpocketTarget::Guard => 0.65,
            PickpocketTarget::Knight => 0.60,
            PickpocketTarget::Watchman => 0.55,
            PickpocketTarget::Paladin => 0.50,
            PickpocketTarget::Gnome => 0.50,
            PickpocketTarget::Hero => 0.45,
        }
    }
}

/// Stall types for stealing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum StallType {
    BakeryStall,
    SilkStall,
    FurStall,
    SilverStall,
    SpiceStall,
    GemStall,
}

impl StallType {
    /// Get required thieving level.
    pub fn required_level(&self) -> u8 {
        match self {
            StallType::BakeryStall => 5,
            StallType::SilkStall => 20,
            StallType::FurStall => 35,
            StallType::SilverStall => 50,
            StallType::SpiceStall => 65,
            StallType::GemStall => 75,
        }
    }

    /// Get thieving experience.
    pub fn experience(&self) -> u32 {
        match self {
            StallType::BakeryStall => 64,
            StallType::SilkStall => 96,
            StallType::FurStall => 144,
            StallType::SilverStall => 216,
            StallType::SpiceStall => 324,
            StallType::GemStall => 400,
        }
    }

    /// Get respawn time in ticks.
    pub fn respawn_ticks(&self) -> u32 {
        match self {
            StallType::BakeryStall => 4,
            StallType::SilkStall => 8,
            StallType::FurStall => 20,
            StallType::SilverStall => 40,
            StallType::SpiceStall => 80,
            StallType::GemStall => 180,
        }
    }
}

/// Chest types for lockpicking.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ChestType {
    Chest10Coins,
    ChestNature,
    Chest50Coins,
    ChestBlood,
}

impl ChestType {
    /// Get required thieving level.
    pub fn required_level(&self) -> u8 {
        match self {
            ChestType::Chest10Coins => 13,
            ChestType::ChestNature => 28,
            ChestType::Chest50Coins => 43,
            ChestType::ChestBlood => 59,
        }
    }

    /// Get thieving experience.
    pub fn experience(&self) -> u32 {
        match self {
            ChestType::Chest10Coins => 30,
            ChestType::ChestNature => 50,
            ChestType::Chest50Coins => 125,
            ChestType::ChestBlood => 250,
        }
    }
}

/// Calculate pickpocket success chance.
pub fn calculate_pickpocket_chance(thieving_level: u8, target: PickpocketTarget) -> f64 {
    let level_diff = thieving_level.saturating_sub(target.required_level()) as f64;
    let base_chance = target.base_success_rate();
    let bonus = level_diff * 0.005; // 0.5% per level above requirement
    (base_chance + bonus).clamp(0.2, 0.95)
}

/// Manager for thieving system.
#[derive(Debug, Default)]
pub struct ThievingManager {
    /// NPC ID to pickpocket target mappings.
    npc_targets: HashMap<u32, PickpocketTarget>,
}

impl ThievingManager {
    /// Create a new thieving manager.
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.load_defaults();
        manager
    }

    /// Load default data.
    pub fn load_defaults(&mut self) {
        // Map NPC IDs to pickpocket targets
        self.npc_targets.insert(11, PickpocketTarget::Man);
        self.npc_targets.insert(63, PickpocketTarget::Farmer);
        self.npc_targets.insert(86, PickpocketTarget::Warrior);
        self.npc_targets.insert(342, PickpocketTarget::Rogue);
        self.npc_targets.insert(65, PickpocketTarget::Guard);
        self.npc_targets.insert(322, PickpocketTarget::Knight);
        self.npc_targets.insert(574, PickpocketTarget::Paladin);
        self.npc_targets.insert(592, PickpocketTarget::Hero);

        info!("Loaded {} pickpocket targets", self.npc_targets.len());
    }

    /// Get pickpocket target for NPC.
    pub fn get_target(&self, npc_id: u32) -> Option<PickpocketTarget> {
        self.npc_targets.get(&npc_id).copied()
    }

    /// Check if player can pickpocket target.
    pub fn can_pickpocket(&self, thieving_level: u8, target: PickpocketTarget) -> bool {
        thieving_level >= target.required_level()
    }

    /// Check if player can steal from stall.
    pub fn can_steal_from_stall(&self, thieving_level: u8, stall: StallType) -> bool {
        thieving_level >= stall.required_level()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pickpocket_levels() {
        assert_eq!(PickpocketTarget::Man.required_level(), 1);
        assert_eq!(PickpocketTarget::Hero.required_level(), 80);
    }

    #[test]
    fn test_stall_levels() {
        assert_eq!(StallType::BakeryStall.required_level(), 5);
        assert_eq!(StallType::GemStall.required_level(), 75);
    }

    #[test]
    fn test_pickpocket_chance() {
        // At required level
        let chance = calculate_pickpocket_chance(1, PickpocketTarget::Man);
        assert!((chance - 0.85).abs() < 0.01);

        // Well above required level
        let chance2 = calculate_pickpocket_chance(50, PickpocketTarget::Man);
        assert!(chance2 > 0.9);
    }

    #[test]
    fn test_thieving_manager() {
        let manager = ThievingManager::new();
        assert_eq!(manager.get_target(11), Some(PickpocketTarget::Man));
        assert!(manager.can_pickpocket(1, PickpocketTarget::Man));
        assert!(!manager.can_pickpocket(1, PickpocketTarget::Hero));
    }
}
