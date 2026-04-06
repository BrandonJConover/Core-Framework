//! Food and potion consumable system.
//!
//! Defines all RSC food items with healing values, potion definitions with
//! dose-based stat effects, and the consume/drink logic including tick delays.

use std::collections::HashMap;
use once_cell::sync::Lazy;

use super::player::{Item, Player, SkillId};
use super::status_effect::{StatusEffect, StatusEffectManager, StatusType};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Minimum ticks between eating food (3 game ticks = 1.8s at 600ms/tick).
pub const EAT_DELAY_TICKS: u32 = 3;

/// Minimum ticks between drinking potions.
pub const DRINK_DELAY_TICKS: u32 = 3;

/// Item ID for an empty vial, left after finishing a potion.
pub const EMPTY_VIAL_ID: u32 = 465;

// ---------------------------------------------------------------------------
// Food
// ---------------------------------------------------------------------------

/// A food item definition.
#[derive(Debug, Clone)]
pub struct FoodDef {
    pub item_id: u32,
    pub name: &'static str,
    pub heal_amount: u32,
}

/// Static table of every RSC food.
static FOOD_DEFS: Lazy<Vec<FoodDef>> = Lazy::new(|| {
    vec![
        FoodDef { item_id: 319, name: "Shrimp",             heal_amount: 3  },
        FoodDef { item_id: 320, name: "Anchovies",          heal_amount: 1  },
        FoodDef { item_id: 132, name: "Bread",              heal_amount: 4  },
        FoodDef { item_id: 140, name: "Cooked Meat",        heal_amount: 3  },
        FoodDef { item_id: 141, name: "Cooked Chicken",     heal_amount: 3  },
        FoodDef { item_id: 346, name: "Sardine",            heal_amount: 4  },
        FoodDef { item_id: 350, name: "Herring",            heal_amount: 5  },
        FoodDef { item_id: 355, name: "Mackerel",           heal_amount: 6  },
        FoodDef { item_id: 351, name: "Trout",              heal_amount: 7  },
        FoodDef { item_id: 362, name: "Cod",                heal_amount: 7  },
        FoodDef { item_id: 364, name: "Pike",               heal_amount: 8  },
        FoodDef { item_id: 352, name: "Salmon",             heal_amount: 9  },
        FoodDef { item_id: 354, name: "Tuna",               heal_amount: 10 },
        FoodDef { item_id: 316, name: "Lobster",            heal_amount: 12 },
        FoodDef { item_id: 367, name: "Bass",               heal_amount: 13 },
        FoodDef { item_id: 373, name: "Swordfish",          heal_amount: 14 },
        FoodDef { item_id: 546, name: "Shark",              heal_amount: 20 },
        FoodDef { item_id: 370, name: "Manta Ray",          heal_amount: 22 },
        FoodDef { item_id: 369, name: "Sea Turtle",         heal_amount: 21 },
        FoodDef { item_id: 325, name: "Cake",               heal_amount: 4  },
        FoodDef { item_id: 326, name: "2/3 Cake",           heal_amount: 4  },
        FoodDef { item_id: 327, name: "Slice of Cake",      heal_amount: 4  },
        FoodDef { item_id: 330, name: "Chocolate Cake",     heal_amount: 5  },
        FoodDef { item_id: 333, name: "Meat Pie",           heal_amount: 6  },
        FoodDef { item_id: 750, name: "Apple Pie",          heal_amount: 7  },
        FoodDef { item_id: 257, name: "Redberry Pie",       heal_amount: 5  },
        FoodDef { item_id: 335, name: "Meat Pizza",         heal_amount: 7  },
        FoodDef { item_id: 336, name: "Anchovy Pizza",      heal_amount: 9  },
        FoodDef { item_id: 337, name: "Pineapple Pizza",    heal_amount: 11 },
        FoodDef { item_id: 228, name: "Cabbage",            heal_amount: 1  },
        FoodDef { item_id: 18,  name: "Potato",             heal_amount: 1  },
    ]
});

/// Lookup map keyed by item ID for O(1) food resolution.
static FOOD_MAP: Lazy<HashMap<u32, &'static FoodDef>> = Lazy::new(|| {
    FOOD_DEFS.iter().map(|f| (f.item_id, f)).collect()
});

/// Return the food definition for `item_id`, if it exists.
pub fn get_food_def(item_id: u32) -> Option<&'static FoodDef> {
    FOOD_MAP.get(&item_id).copied()
}

// ---------------------------------------------------------------------------
// Potions
// ---------------------------------------------------------------------------

/// Describes a single effect applied when a potion dose is consumed.
#[derive(Debug, Clone)]
pub enum PotionEffect {
    /// Boost a combat skill: `level + level * percent / 100 + flat`.
    BoostSkill {
        skill: SkillId,
        percent: u32,
        flat: u32,
    },
    /// Restore prayer points: `level * percent / 100 + flat`.
    RestorePrayer {
        percent: u32,
        flat: u32,
    },
    /// Cure any active poison.
    CurePoison,
    /// Grant temporary anti-dragonfire protection (duration in ticks).
    Antifire {
        duration_ticks: u32,
    },
}

/// A potion definition.  Each physical potion has four dose variants (4/3/2/1)
/// that share the same effects.  `dose_item_ids[0]` is the 4-dose vial,
/// `dose_item_ids[3]` is the 1-dose vial.
#[derive(Debug, Clone)]
pub struct PotionDef {
    pub name: &'static str,
    pub dose_item_ids: [u32; 4],
    pub effects: Vec<PotionEffect>,
}

impl PotionDef {
    /// Return the item ID of the next lower dose, or `EMPTY_VIAL_ID` when the
    /// last dose is consumed.
    pub fn next_dose_item_id(&self, current_item_id: u32) -> Option<u32> {
        let idx = self.dose_index(current_item_id)?;
        if idx < 3 {
            Some(self.dose_item_ids[idx + 1])
        } else {
            Some(EMPTY_VIAL_ID)
        }
    }

    /// Return the dose number (4..=1) for a given item ID.
    pub fn dose_for_item(&self, item_id: u32) -> Option<u32> {
        self.dose_index(item_id).map(|i| 4 - i as u32)
    }

    fn dose_index(&self, item_id: u32) -> Option<usize> {
        self.dose_item_ids.iter().position(|&id| id == item_id)
    }
}

/// Static table of every RSC potion.
static POTION_DEFS: Lazy<Vec<PotionDef>> = Lazy::new(|| {
    vec![
        // --- Standard potions (10% + 3) ---
        PotionDef {
            name: "Attack Potion",
            dose_item_ids: [474, 475, 476, 477],
            effects: vec![PotionEffect::BoostSkill {
                skill: SkillId::Attack, percent: 10, flat: 3,
            }],
        },
        PotionDef {
            name: "Strength Potion",
            dose_item_ids: [478, 479, 480, 481],
            effects: vec![PotionEffect::BoostSkill {
                skill: SkillId::Strength, percent: 10, flat: 3,
            }],
        },
        PotionDef {
            name: "Defense Potion",
            dose_item_ids: [482, 483, 484, 485],
            effects: vec![PotionEffect::BoostSkill {
                skill: SkillId::Defence, percent: 10, flat: 3,
            }],
        },
        // --- Prayer restore (25% + 7) ---
        PotionDef {
            name: "Prayer Potion",
            dose_item_ids: [483, 484, 485, 486],  // RSC restore prayer
            effects: vec![PotionEffect::RestorePrayer {
                percent: 25, flat: 7,
            }],
        },
        // --- Antipoison ---
        PotionDef {
            name: "Antipoison Potion",
            dose_item_ids: [487, 488, 489, 490],
            effects: vec![PotionEffect::CurePoison],
        },
        // --- Super potions (15% + 5) ---
        PotionDef {
            name: "Super Attack Potion",
            dose_item_ids: [491, 492, 493, 494],
            effects: vec![PotionEffect::BoostSkill {
                skill: SkillId::Attack, percent: 15, flat: 5,
            }],
        },
        PotionDef {
            name: "Super Strength Potion",
            dose_item_ids: [495, 496, 497, 498],
            effects: vec![PotionEffect::BoostSkill {
                skill: SkillId::Strength, percent: 15, flat: 5,
            }],
        },
        PotionDef {
            name: "Super Defense Potion",
            dose_item_ids: [499, 500, 501, 502],
            effects: vec![PotionEffect::BoostSkill {
                skill: SkillId::Defence, percent: 15, flat: 5,
            }],
        },
        // --- Ranging potion (10% + 3) ---
        PotionDef {
            name: "Ranging Potion",
            dose_item_ids: [503, 504, 505, 506],
            effects: vec![PotionEffect::BoostSkill {
                skill: SkillId::Ranged, percent: 10, flat: 3,
            }],
        },
        // --- Magic potion (flat +3) ---
        PotionDef {
            name: "Magic Potion",
            dose_item_ids: [507, 508, 509, 510],
            effects: vec![PotionEffect::BoostSkill {
                skill: SkillId::Magic, percent: 0, flat: 3,
            }],
        },
        // --- Antifire ---
        PotionDef {
            name: "Antifire Potion",
            dose_item_ids: [511, 512, 513, 514],
            effects: vec![PotionEffect::Antifire { duration_ticks: 500 }],
        },
    ]
});

/// Lookup map: any dose item-ID -> index into POTION_DEFS.
static POTION_MAP: Lazy<HashMap<u32, usize>> = Lazy::new(|| {
    let mut map = HashMap::new();
    for (idx, def) in POTION_DEFS.iter().enumerate() {
        for &id in &def.dose_item_ids {
            map.insert(id, idx);
        }
    }
    map
});

/// Return the potion definition that owns `item_id`, if any.
pub fn get_potion_def(item_id: u32) -> Option<&'static PotionDef> {
    POTION_MAP.get(&item_id).map(|&idx| &POTION_DEFS[idx])
}

// ---------------------------------------------------------------------------
// Consume logic
// ---------------------------------------------------------------------------

/// Result of attempting to consume something.
#[derive(Debug)]
pub enum ConsumeResult {
    /// Successfully consumed.  Contains a human-readable message.
    Success(String),
    /// The player must wait before consuming again.
    TooSoon,
    /// The item is not a known consumable.
    NotConsumable,
    /// The item was not found in inventory.
    NotInInventory,
}

/// Eat a food item from the player's inventory.
///
/// Returns the outcome; the caller is responsible for sending the
/// appropriate client message and scheduling the next allowed eat tick.
pub fn consume_food(
    player: &mut Player,
    item_id: u32,
    current_tick: u64,
    last_eat_tick: &mut u64,
) -> ConsumeResult {
    // Enforce eat delay.
    if current_tick.saturating_sub(*last_eat_tick) < EAT_DELAY_TICKS as u64 {
        return ConsumeResult::TooSoon;
    }

    let food = match get_food_def(item_id) {
        Some(f) => f,
        None => return ConsumeResult::NotConsumable,
    };

    // Make sure the player actually has the item.
    if !player.inventory.remove(item_id, 1) {
        return ConsumeResult::NotInInventory;
    }

    // Heal — capped at max hitpoints.
    let max_hp = player.skills.level(SkillId::Hits);
    let cur_hp = player.skills.current_level(SkillId::Hits);
    let new_hp = cur_hp.saturating_add(food.heal_amount as u8).min(max_hp);
    player.skills.set_current_level(SkillId::Hits, new_hp);

    *last_eat_tick = current_tick;

    ConsumeResult::Success(format!(
        "You eat the {}.  It heals {} hitpoints.",
        food.name, food.heal_amount,
    ))
}

/// Drink a dose from a potion in the player's inventory.
///
/// Applies every `PotionEffect` in the definition and swaps the item for the
/// next-lower-dose variant (or an empty vial).
pub fn drink_potion(
    player: &mut Player,
    item_id: u32,
    current_tick: u64,
    last_drink_tick: &mut u64,
    status_effects: &mut StatusEffectManager,
) -> ConsumeResult {
    // Enforce drink delay.
    if current_tick.saturating_sub(*last_drink_tick) < DRINK_DELAY_TICKS as u64 {
        return ConsumeResult::TooSoon;
    }

    let potion = match get_potion_def(item_id) {
        Some(p) => p,
        None => return ConsumeResult::NotConsumable,
    };

    if !player.inventory.remove(item_id, 1) {
        return ConsumeResult::NotInInventory;
    }

    // Apply each effect attached to this potion.
    for effect in &potion.effects {
        apply_potion_effect(player, effect, status_effects);
    }

    // Replace with next dose or empty vial.
    let replacement_id = potion
        .next_dose_item_id(item_id)
        .unwrap_or(EMPTY_VIAL_ID);
    player.inventory.add(Item::new(replacement_id, 1));

    let dose = potion.dose_for_item(item_id).unwrap_or(0);
    *last_drink_tick = current_tick;

    ConsumeResult::Success(format!(
        "You drink a dose of {}.  {} dose{} remaining.",
        potion.name,
        dose.saturating_sub(1),
        if dose.saturating_sub(1) == 1 { "" } else { "s" },
    ))
}

/// Apply a single potion effect to the player.
fn apply_potion_effect(
    player: &mut Player,
    effect: &PotionEffect,
    status_effects: &mut StatusEffectManager,
) {
    match effect {
        PotionEffect::BoostSkill { skill, percent, flat } => {
            let base = player.skills.level(*skill) as u32;
            let boost = (base * percent / 100) + flat;
            let max_boosted = base + boost;
            let current = player.skills.current_level(*skill) as u32;
            let new_level = current.saturating_add(boost).min(max_boosted);
            player.skills.set_current_level(*skill, new_level.min(118) as u8);
        }
        PotionEffect::RestorePrayer { percent, flat } => {
            let base = player.skills.level(SkillId::Prayer) as u32;
            let restore = (base * percent / 100) + flat;
            let current = player.skills.current_level(SkillId::Prayer) as u32;
            let new_level = current.saturating_add(restore).min(base);
            player.skills.set_current_level(SkillId::Prayer, new_level as u8);
        }
        PotionEffect::CurePoison => {
            status_effects.remove_effect(StatusType::Poison);
            status_effects.remove_effect(StatusType::SuperPoison);
            status_effects.add_effect(StatusEffect::antipoison(500));
        }
        PotionEffect::Antifire { duration_ticks } => {
            status_effects.add_effect(StatusEffect::antifire(*duration_ticks));
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_food_lookup() {
        let shrimp = get_food_def(319).expect("shrimp should exist");
        assert_eq!(shrimp.name, "Shrimp");
        assert_eq!(shrimp.heal_amount, 3);

        let shark = get_food_def(546).expect("shark should exist");
        assert_eq!(shark.heal_amount, 20);

        assert!(get_food_def(99999).is_none());
    }

    #[test]
    fn test_potion_lookup() {
        // 4-dose super strength
        let pot = get_potion_def(495).expect("super str should exist");
        assert_eq!(pot.name, "Super Strength Potion");
        assert_eq!(pot.dose_for_item(495), Some(4));
        assert_eq!(pot.next_dose_item_id(495), Some(496));

        // 1-dose variant yields empty vial
        assert_eq!(pot.next_dose_item_id(498), Some(EMPTY_VIAL_ID));
    }

    #[test]
    fn test_consume_food_heals() {
        let mut player = Player::new(1, "test".into());
        // Damage the player: set current HP below base
        player.skills.set_current_level(SkillId::Hits, 5);

        let mut last_eat: u64 = 0;
        let result = consume_food(&mut player, 316, 10, &mut last_eat); // lobster

        assert!(matches!(result, ConsumeResult::Success(_)));
        // 5 + 12 = 17, but max is 10 for a new character
        assert_eq!(player.skills.current_level(SkillId::Hits), 10);
        assert_eq!(last_eat, 10);
    }

    #[test]
    fn test_consume_food_too_soon() {
        let mut player = Player::new(1, "test".into());
        player.inventory.add(Item::new(319, 1)); // shrimp
        player.skills.set_current_level(SkillId::Hits, 5);

        let mut last_eat: u64 = 8;
        let result = consume_food(&mut player, 319, 9, &mut last_eat);
        assert!(matches!(result, ConsumeResult::TooSoon));
    }

    #[test]
    fn test_drink_potion_applies_boost() {
        let mut player = Player::new(1, "test".into());
        player.inventory.add(Item::new(478, 1)); // 4-dose strength pot

        let mut last_drink: u64 = 0;
        let mut effects = StatusEffectManager::new();

        let result = drink_potion(&mut player, 478, 10, &mut last_drink, &mut effects);
        assert!(matches!(result, ConsumeResult::Success(_)));

        // New player: strength base = 1, boost = 1*10/100+3 = 3, so current = 4
        assert!(player.skills.current_level(SkillId::Strength) >= 4);

        // Should now have a 3-dose vial in inventory
        assert_eq!(player.inventory.count(479), 1);
    }

    #[test]
    fn test_antipoison_cures() {
        let mut player = Player::new(1, "test".into());
        player.inventory.add(Item::new(487, 1)); // 4-dose antipoison

        let mut last_drink: u64 = 0;
        let mut effects = StatusEffectManager::new();
        effects.add_effect(StatusEffect::poison(6));
        assert!(effects.is_poisoned());

        let result = drink_potion(&mut player, 487, 10, &mut last_drink, &mut effects);
        assert!(matches!(result, ConsumeResult::Success(_)));
        assert!(!effects.is_poisoned());
    }
}
