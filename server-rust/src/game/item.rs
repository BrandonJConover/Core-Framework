//! Item definitions and properties for game items.
//!
//! Contains item metadata, equipment bonuses, and item requirements.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Item categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ItemCategory {
    Weapon,
    Armor,
    Shield,
    Ammunition,
    Food,
    Potion,
    Rune,
    Tool,
    Resource,
    Quest,
    Misc,
}

/// Equipment slot that an item can be worn in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum EquipSlot {
    Head,
    Cape,
    Amulet,
    Weapon,
    Body,
    Shield,
    Legs,
    Gloves,
    Boots,
    Ring,
    Arrows,
}

/// Combat bonuses from an item.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct CombatBonuses {
    pub attack_stab: i16,
    pub attack_slash: i16,
    pub attack_crush: i16,
    pub attack_magic: i16,
    pub attack_ranged: i16,
    pub defense_stab: i16,
    pub defense_slash: i16,
    pub defense_crush: i16,
    pub defense_magic: i16,
    pub defense_ranged: i16,
    pub strength_bonus: i16,
    pub ranged_strength: i16,
    pub magic_damage: i16,
    pub prayer_bonus: i16,
}

impl CombatBonuses {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn melee_weapon(attack: i16, strength: i16) -> Self {
        Self {
            attack_stab: attack,
            attack_slash: attack,
            attack_crush: attack,
            strength_bonus: strength,
            ..Default::default()
        }
    }

    pub fn ranged_weapon(attack: i16, strength: i16) -> Self {
        Self {
            attack_ranged: attack,
            ranged_strength: strength,
            ..Default::default()
        }
    }

    pub fn armor(stab: i16, slash: i16, crush: i16, magic: i16, ranged: i16) -> Self {
        Self {
            defense_stab: stab,
            defense_slash: slash,
            defense_crush: crush,
            defense_magic: magic,
            defense_ranged: ranged,
            ..Default::default()
        }
    }
}

/// Skill requirements for using an item.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ItemRequirements {
    pub attack: u8,
    pub defense: u8,
    pub strength: u8,
    pub ranged: u8,
    pub magic: u8,
    pub prayer: u8,
    pub crafting: u8,
    pub smithing: u8,
    pub mining: u8,
    pub quest_points: u8,
}

impl ItemRequirements {
    pub fn none() -> Self {
        Self::default()
    }

    pub fn melee(attack: u8, defense: u8) -> Self {
        Self { attack, defense, ..Default::default() }
    }

    pub fn ranged(level: u8) -> Self {
        Self { ranged: level, ..Default::default() }
    }

    pub fn magic(level: u8) -> Self {
        Self { magic: level, ..Default::default() }
    }
}

/// Item definition containing all metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemDef {
    pub id: u32,
    pub name: String,
    pub description: String,
    pub category: ItemCategory,
    pub stackable: bool,
    pub tradeable: bool,
    pub members_only: bool,
    pub base_price: u32,
    pub high_alch: u32,
    pub low_alch: u32,
    pub weight: f32,
    pub equip_slot: Option<EquipSlot>,
    pub bonuses: CombatBonuses,
    pub requirements: ItemRequirements,
    pub two_handed: bool,
}

impl ItemDef {
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            description: String::new(),
            category: ItemCategory::Misc,
            stackable: false,
            tradeable: true,
            members_only: false,
            base_price: 1,
            high_alch: 0,
            low_alch: 0,
            weight: 0.0,
            equip_slot: None,
            bonuses: CombatBonuses::default(),
            requirements: ItemRequirements::default(),
            two_handed: false,
        }
    }

    pub fn with_description(mut self, desc: impl Into<String>) -> Self {
        self.description = desc.into();
        self
    }

    pub fn category(mut self, cat: ItemCategory) -> Self {
        self.category = cat;
        self
    }

    pub fn stackable(mut self) -> Self {
        self.stackable = true;
        self
    }

    pub fn untradeable(mut self) -> Self {
        self.tradeable = false;
        self
    }

    pub fn members(mut self) -> Self {
        self.members_only = true;
        self
    }

    pub fn price(mut self, base: u32, high_alch: u32, low_alch: u32) -> Self {
        self.base_price = base;
        self.high_alch = high_alch;
        self.low_alch = low_alch;
        self
    }

    pub fn weight(mut self, w: f32) -> Self {
        self.weight = w;
        self
    }

    pub fn equippable(mut self, slot: EquipSlot) -> Self {
        self.equip_slot = Some(slot);
        self
    }

    pub fn bonuses(mut self, bonuses: CombatBonuses) -> Self {
        self.bonuses = bonuses;
        self
    }

    pub fn requirements(mut self, reqs: ItemRequirements) -> Self {
        self.requirements = reqs;
        self
    }

    pub fn two_handed(mut self) -> Self {
        self.two_handed = true;
        self
    }

    /// Check if a player meets the requirements to use this item.
    pub fn can_use(&self, skills: &[(u8, u8)]) -> bool {
        // skills is a slice of (skill_id, level) pairs
        let get_level = |skill_id: u8| -> u8 {
            skills.iter()
                .find(|(id, _)| *id == skill_id)
                .map(|(_, lvl)| *lvl)
                .unwrap_or(1)
        };

        get_level(0) >= self.requirements.attack &&
        get_level(1) >= self.requirements.defense &&
        get_level(2) >= self.requirements.strength &&
        get_level(4) >= self.requirements.ranged &&
        get_level(6) >= self.requirements.magic
    }
}

/// Item definition repository.
#[derive(Debug, Default)]
pub struct ItemRepository {
    items: HashMap<u32, ItemDef>,
}

impl ItemRepository {
    pub fn new() -> Self {
        let mut repo = Self::default();
        repo.load_defaults();
        repo
    }

    fn load_defaults(&mut self) {
        // Coins and currency
        self.add(ItemDef::new(10, "Coins")
            .with_description("Lovely money!")
            .category(ItemCategory::Misc)
            .stackable());

        // Basic weapons
        self.add(ItemDef::new(66, "Bronze Sword")
            .with_description("A bronze sword")
            .category(ItemCategory::Weapon)
            .equippable(EquipSlot::Weapon)
            .bonuses(CombatBonuses::melee_weapon(4, 3))
            .price(24, 14, 9));

        self.add(ItemDef::new(67, "Iron Sword")
            .with_description("An iron sword")
            .category(ItemCategory::Weapon)
            .equippable(EquipSlot::Weapon)
            .bonuses(CombatBonuses::melee_weapon(10, 8))
            .requirements(ItemRequirements::melee(1, 0))
            .price(56, 33, 22));

        self.add(ItemDef::new(68, "Steel Sword")
            .with_description("A steel sword")
            .category(ItemCategory::Weapon)
            .equippable(EquipSlot::Weapon)
            .bonuses(CombatBonuses::melee_weapon(16, 14))
            .requirements(ItemRequirements::melee(5, 0))
            .price(200, 120, 80));

        self.add(ItemDef::new(69, "Mithril Sword")
            .with_description("A mithril sword")
            .category(ItemCategory::Weapon)
            .equippable(EquipSlot::Weapon)
            .bonuses(CombatBonuses::melee_weapon(23, 21))
            .requirements(ItemRequirements::melee(20, 0))
            .price(520, 312, 208));

        self.add(ItemDef::new(70, "Adamant Sword")
            .with_description("An adamant sword")
            .category(ItemCategory::Weapon)
            .equippable(EquipSlot::Weapon)
            .bonuses(CombatBonuses::melee_weapon(33, 31))
            .requirements(ItemRequirements::melee(30, 0))
            .price(1280, 768, 512));

        self.add(ItemDef::new(71, "Rune Sword")
            .with_description("A rune sword")
            .category(ItemCategory::Weapon)
            .equippable(EquipSlot::Weapon)
            .bonuses(CombatBonuses::melee_weapon(45, 44))
            .requirements(ItemRequirements::melee(40, 0))
            .price(12800, 7680, 5120));

        // Basic armor
        self.add(ItemDef::new(117, "Bronze Platebody")
            .with_description("Provides some protection")
            .category(ItemCategory::Armor)
            .equippable(EquipSlot::Body)
            .bonuses(CombatBonuses::armor(15, 14, 12, -5, 0))
            .price(160, 96, 64));

        self.add(ItemDef::new(118, "Iron Platebody")
            .with_description("Provides some protection")
            .category(ItemCategory::Armor)
            .equippable(EquipSlot::Body)
            .bonuses(CombatBonuses::armor(22, 20, 17, -10, 0))
            .requirements(ItemRequirements::melee(0, 1))
            .price(560, 336, 224));

        // Food
        self.add(ItemDef::new(132, "Bread")
            .with_description("Nice and crusty")
            .category(ItemCategory::Food)
            .price(12, 7, 4));

        self.add(ItemDef::new(316, "Lobster")
            .with_description("Yum!")
            .category(ItemCategory::Food)
            .price(150, 90, 60));

        self.add(ItemDef::new(373, "Swordfish")
            .with_description("Very tasty!")
            .category(ItemCategory::Food)
            .price(200, 120, 80));

        self.add(ItemDef::new(546, "Shark")
            .with_description("Very nutritious!")
            .category(ItemCategory::Food)
            .members()
            .price(400, 240, 160));

        // Bones
        self.add(ItemDef::new(20, "Bones")
            .with_description("Ew, it's a pile of bones")
            .category(ItemCategory::Misc)
            .price(1, 0, 0));

        self.add(ItemDef::new(604, "Big Bones")
            .with_description("Some bones from a big creature")
            .category(ItemCategory::Misc)
            .price(25, 15, 10));

        self.add(ItemDef::new(614, "Dragon Bones")
            .with_description("Bones from a dragon")
            .category(ItemCategory::Misc)
            .price(400, 240, 160));

        // Runes
        self.add(ItemDef::new(33, "Air Rune")
            .with_description("One of the 4 basic elemental runes")
            .category(ItemCategory::Rune)
            .stackable()
            .price(4, 2, 1));

        self.add(ItemDef::new(34, "Water Rune")
            .with_description("One of the 4 basic elemental runes")
            .category(ItemCategory::Rune)
            .stackable()
            .price(4, 2, 1));

        self.add(ItemDef::new(35, "Fire Rune")
            .with_description("One of the 4 basic elemental runes")
            .category(ItemCategory::Rune)
            .stackable()
            .price(4, 2, 1));

        self.add(ItemDef::new(36, "Earth Rune")
            .with_description("One of the 4 basic elemental runes")
            .category(ItemCategory::Rune)
            .stackable()
            .price(4, 2, 1));

        self.add(ItemDef::new(31, "Mind Rune")
            .with_description("Used for low level missile spells")
            .category(ItemCategory::Rune)
            .stackable()
            .price(4, 2, 1));

        self.add(ItemDef::new(41, "Chaos Rune")
            .with_description("Used for mid level missile spells")
            .category(ItemCategory::Rune)
            .stackable()
            .price(80, 48, 32));

        self.add(ItemDef::new(38, "Death Rune")
            .with_description("Used for high level missile spells")
            .category(ItemCategory::Rune)
            .stackable()
            .price(180, 108, 72));

        self.add(ItemDef::new(42, "Blood Rune")
            .with_description("Used for the highest level spells")
            .category(ItemCategory::Rune)
            .stackable()
            .members()
            .price(300, 180, 120));

        // Arrows
        self.add(ItemDef::new(11, "Bronze Arrows")
            .with_description("Bronze tipped arrows")
            .category(ItemCategory::Ammunition)
            .stackable()
            .equippable(EquipSlot::Arrows)
            .price(2, 1, 0));

        self.add(ItemDef::new(12, "Iron Arrows")
            .with_description("Iron tipped arrows")
            .category(ItemCategory::Ammunition)
            .stackable()
            .equippable(EquipSlot::Arrows)
            .requirements(ItemRequirements::ranged(1))
            .price(7, 4, 2));

        self.add(ItemDef::new(13, "Steel Arrows")
            .with_description("Steel tipped arrows")
            .category(ItemCategory::Ammunition)
            .stackable()
            .equippable(EquipSlot::Arrows)
            .requirements(ItemRequirements::ranged(5))
            .price(20, 12, 8));
    }

    /// Add an item definition.
    pub fn add(&mut self, def: ItemDef) {
        self.items.insert(def.id, def);
    }

    /// Get an item definition by ID.
    pub fn get(&self, id: u32) -> Option<&ItemDef> {
        self.items.get(&id)
    }

    /// Search items by name (case-insensitive).
    pub fn search(&self, query: &str) -> Vec<&ItemDef> {
        let query_lower = query.to_lowercase();
        self.items.values()
            .filter(|def| def.name.to_lowercase().contains(&query_lower))
            .collect()
    }

    /// Get all items in a category.
    pub fn by_category(&self, category: ItemCategory) -> Vec<&ItemDef> {
        self.items.values()
            .filter(|def| def.category == category)
            .collect()
    }

    /// Get all equippable items for a slot.
    pub fn for_slot(&self, slot: EquipSlot) -> Vec<&ItemDef> {
        self.items.values()
            .filter(|def| def.equip_slot == Some(slot))
            .collect()
    }
}

/// Food healing values.
pub fn food_heals(item_id: u32) -> Option<u32> {
    match item_id {
        132 => Some(4),   // Bread
        140 => Some(3),   // Meat
        316 => Some(12),  // Lobster
        373 => Some(14),  // Swordfish
        546 => Some(20),  // Shark
        367 => Some(8),   // Bass
        352 => Some(9),   // Salmon
        351 => Some(7),   // Trout
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_item_repository() {
        let repo = ItemRepository::new();

        let coins = repo.get(10).unwrap();
        assert_eq!(coins.name, "Coins");
        assert!(coins.stackable);
    }

    #[test]
    fn test_item_search() {
        let repo = ItemRepository::new();

        let swords = repo.search("sword");
        assert!(!swords.is_empty());
        assert!(swords.iter().all(|i| i.name.to_lowercase().contains("sword")));
    }

    #[test]
    fn test_item_requirements() {
        let repo = ItemRepository::new();

        let rune_sword = repo.get(71).unwrap();
        assert_eq!(rune_sword.requirements.attack, 40);

        // Player with attack 50 can use it
        let skills = vec![(0u8, 50u8)]; // attack = 50
        assert!(rune_sword.can_use(&skills));

        // Player with attack 30 cannot
        let skills = vec![(0u8, 30u8)]; // attack = 30
        assert!(!rune_sword.can_use(&skills));
    }

    #[test]
    fn test_combat_bonuses() {
        let bonuses = CombatBonuses::melee_weapon(20, 15);
        assert_eq!(bonuses.attack_stab, 20);
        assert_eq!(bonuses.strength_bonus, 15);
    }
}
