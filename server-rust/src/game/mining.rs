//! Mining skill system.
//! Handles ore rocks, mining mechanics, and gem drops.

use std::collections::HashMap;
use tracing::{debug, info};

use super::entity::Position;

/// Types of ore that can be mined.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum OreType {
    Clay,
    CopperOre,
    TinOre,
    IronOre,
    Silver,
    Coal,
    Gold,
    Mithril,
    Adamantite,
    Runite,
}

impl OreType {
    /// Get the item ID for this ore.
    pub fn item_id(&self) -> u32 {
        match self {
            OreType::Clay => 149,
            OreType::CopperOre => 150,
            OreType::TinOre => 202,
            OreType::IronOre => 151,
            OreType::Silver => 383,
            OreType::Coal => 155,
            OreType::Gold => 152,
            OreType::Mithril => 153,
            OreType::Adamantite => 154,
            OreType::Runite => 409,
        }
    }

    /// Get the required mining level.
    pub fn required_level(&self) -> u8 {
        match self {
            OreType::Clay => 1,
            OreType::CopperOre => 1,
            OreType::TinOre => 1,
            OreType::IronOre => 15,
            OreType::Silver => 20,
            OreType::Coal => 30,
            OreType::Gold => 40,
            OreType::Mithril => 55,
            OreType::Adamantite => 70,
            OreType::Runite => 85,
        }
    }

    /// Get mining experience for this ore.
    pub fn experience(&self) -> u32 {
        match self {
            OreType::Clay => 20,
            OreType::CopperOre => 70,
            OreType::TinOre => 70,
            OreType::IronOre => 140,
            OreType::Silver => 160,
            OreType::Coal => 200,
            OreType::Gold => 260,
            OreType::Mithril => 320,
            OreType::Adamantite => 380,
            OreType::Runite => 500,
        }
    }

    /// Get respawn time in game ticks.
    pub fn respawn_ticks(&self) -> u32 {
        match self {
            OreType::Clay => 2,
            OreType::CopperOre => 4,
            OreType::TinOre => 4,
            OreType::IronOre => 9,
            OreType::Silver => 100,
            OreType::Coal => 50,
            OreType::Gold => 100,
            OreType::Mithril => 200,
            OreType::Adamantite => 400,
            OreType::Runite => 1200,
        }
    }
}

/// Pickaxe definitions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Pickaxe {
    Bronze,
    Iron,
    Steel,
    Mithril,
    Adamantite,
    Rune,
}

impl Pickaxe {
    /// Get the item ID for this pickaxe.
    pub fn item_id(&self) -> u32 {
        match self {
            Pickaxe::Bronze => 156,
            Pickaxe::Iron => 1258,
            Pickaxe::Steel => 1259,
            Pickaxe::Mithril => 1260,
            Pickaxe::Adamantite => 1261,
            Pickaxe::Rune => 1262,
        }
    }

    /// Get the required mining level for this pickaxe.
    pub fn required_level(&self) -> u8 {
        match self {
            Pickaxe::Bronze => 1,
            Pickaxe::Iron => 1,
            Pickaxe::Steel => 6,
            Pickaxe::Mithril => 21,
            Pickaxe::Adamantite => 31,
            Pickaxe::Rune => 41,
        }
    }

    /// Get the mining speed bonus (higher is faster).
    pub fn speed_bonus(&self) -> u8 {
        match self {
            Pickaxe::Bronze => 1,
            Pickaxe::Iron => 2,
            Pickaxe::Steel => 3,
            Pickaxe::Mithril => 4,
            Pickaxe::Adamantite => 5,
            Pickaxe::Rune => 6,
        }
    }
}

/// Gem types that can be found while mining.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Gem {
    Uncut_Sapphire,
    Uncut_Emerald,
    Uncut_Ruby,
    Uncut_Diamond,
}

impl Gem {
    /// Get the item ID for this gem.
    pub fn item_id(&self) -> u32 {
        match self {
            Gem::Uncut_Sapphire => 160,
            Gem::Uncut_Emerald => 159,
            Gem::Uncut_Ruby => 158,
            Gem::Uncut_Diamond => 157,
        }
    }

    /// Get the rarity weight (lower = rarer).
    pub fn weight(&self) -> u32 {
        match self {
            Gem::Uncut_Sapphire => 64,
            Gem::Uncut_Emerald => 32,
            Gem::Uncut_Ruby => 16,
            Gem::Uncut_Diamond => 8,
        }
    }
}

/// A rock that can be mined.
#[derive(Debug, Clone)]
pub struct Rock {
    /// Position of the rock.
    pub position: Position,
    /// Type of ore in this rock.
    pub ore_type: OreType,
    /// Object ID when full.
    pub full_id: u32,
    /// Object ID when depleted.
    pub depleted_id: u32,
    /// Current respawn timer (0 = available).
    pub respawn_timer: u32,
}

impl Rock {
    /// Create a new rock.
    pub fn new(position: Position, ore_type: OreType, full_id: u32, depleted_id: u32) -> Self {
        Self {
            position,
            ore_type,
            full_id,
            depleted_id,
            respawn_timer: 0,
        }
    }

    /// Check if rock is available to mine.
    pub fn is_available(&self) -> bool {
        self.respawn_timer == 0
    }

    /// Deplete the rock and start respawn timer.
    pub fn deplete(&mut self) {
        self.respawn_timer = self.ore_type.respawn_ticks();
    }

    /// Tick the respawn timer.
    pub fn tick(&mut self) {
        if self.respawn_timer > 0 {
            self.respawn_timer -= 1;
        }
    }
}

/// Calculate mining success chance.
pub fn calculate_mining_chance(
    mining_level: u8,
    ore_level: u8,
    pickaxe: Pickaxe,
) -> f64 {
    let level_diff = mining_level.saturating_sub(ore_level) as f64;
    let pick_bonus = pickaxe.speed_bonus() as f64 * 0.05;
    let base_chance = 0.3 + (level_diff * 0.01) + pick_bonus;
    base_chance.clamp(0.1, 0.95)
}

/// Check if player finds a gem while mining.
pub fn check_gem_drop(mining_level: u8) -> Option<Gem> {
    // Base gem chance is about 1/256, increases slightly with level
    let gem_chance = 256.0 - (mining_level as f64 * 0.5);
    if rand::random::<f64>() * gem_chance > 1.0 {
        return None;
    }

    // Weight-based gem selection
    let total_weight = 64 + 32 + 16 + 8; // 120
    let roll = rand::random::<u32>() % total_weight;

    if roll < 8 {
        Some(Gem::Uncut_Diamond)
    } else if roll < 24 {
        Some(Gem::Uncut_Ruby)
    } else if roll < 56 {
        Some(Gem::Uncut_Emerald)
    } else {
        Some(Gem::Uncut_Sapphire)
    }
}

/// Manager for mining system.
#[derive(Debug, Default)]
pub struct MiningManager {
    /// Rocks by position.
    rocks: HashMap<(u16, u16), Rock>,
}

impl MiningManager {
    /// Create a new mining manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a rock.
    pub fn register_rock(&mut self, rock: Rock) {
        let key = (rock.position.x, rock.position.y);
        self.rocks.insert(key, rock);
    }

    /// Get rock at position.
    pub fn get_rock(&self, x: u16, y: u16) -> Option<&Rock> {
        self.rocks.get(&(x, y))
    }

    /// Get mutable rock at position.
    pub fn get_rock_mut(&mut self, x: u16, y: u16) -> Option<&mut Rock> {
        self.rocks.get_mut(&(x, y))
    }

    /// Tick all rocks (update respawn timers).
    pub fn tick(&mut self) {
        for rock in self.rocks.values_mut() {
            rock.tick();
        }
    }

    /// Get best usable pickaxe from a list of available item IDs.
    pub fn best_pickaxe(available_items: &[u32], mining_level: u8) -> Option<Pickaxe> {
        let pickaxes = [
            Pickaxe::Rune,
            Pickaxe::Adamantite,
            Pickaxe::Mithril,
            Pickaxe::Steel,
            Pickaxe::Iron,
            Pickaxe::Bronze,
        ];

        for pick in pickaxes {
            if mining_level >= pick.required_level() && available_items.contains(&pick.item_id()) {
                return Some(pick);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ore_levels() {
        assert_eq!(OreType::Clay.required_level(), 1);
        assert_eq!(OreType::Runite.required_level(), 85);
    }

    #[test]
    fn test_mining_chance() {
        // High level with rune pick = high chance
        let chance = calculate_mining_chance(99, 1, Pickaxe::Rune);
        assert!(chance > 0.8);

        // Low level with bronze pick = low chance
        let chance2 = calculate_mining_chance(1, 1, Pickaxe::Bronze);
        assert!(chance2 < 0.5);
    }

    #[test]
    fn test_rock_respawn() {
        let pos = Position { x: 100, y: 100, plane: 0 };
        let mut rock = Rock::new(pos, OreType::IronOre, 100, 101);

        assert!(rock.is_available());
        rock.deplete();
        assert!(!rock.is_available());

        // Tick down respawn
        for _ in 0..9 {
            rock.tick();
        }
        assert!(rock.is_available());
    }

    #[test]
    fn test_best_pickaxe() {
        let items = vec![156, 1259]; // Bronze and Steel
        let best = MiningManager::best_pickaxe(&items, 10);
        assert_eq!(best, Some(Pickaxe::Steel));
    }
}
