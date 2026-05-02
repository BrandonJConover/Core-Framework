//! Player module for player entity management.

use super::entity::{Direction, Entity, EntityId, Position};
use super::skills::Skills;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::debug;

/// Player entity representing a connected player.
#[derive(Debug)]
pub struct Player {
    pub id: u64,
    pub username: String,
    pub position: Position,
    pub direction: Direction,
    pub skills: Skills,
    pub inventory: Inventory,
    pub equipment: Equipment,
    pub settings: PlayerSettings,
    pub combat_level: u32,
    pub fatigue: u32,
    pub online: bool,
    pub in_combat: bool,
    pub last_tick: u64,
    pub walking_queue: Vec<Position>,
    pub appearance_changed: bool,
    pub player_index: u16,
}

impl Player {
    pub fn new(id: u64, username: String) -> Self {
        Self {
            id,
            username,
            position: Position::new(122, 647), // Lumbridge spawn
            direction: Direction::South,
            skills: Skills::new(),
            inventory: Inventory::new(),
            equipment: Equipment::new(),
            settings: PlayerSettings::default(),
            combat_level: 3,
            fatigue: 0,
            online: true,
            in_combat: false,
            last_tick: 0,
            walking_queue: Vec::new(),
            appearance_changed: true,
            player_index: 0,
        }
    }

    /// Process player tick.
    pub async fn tick(&mut self) {
        self.last_tick += 1;

        // Process walking queue
        if let Some(next_pos) = self.walking_queue.first().cloned() {
            let dx = (next_pos.x - self.position.x).signum();
            let dy = (next_pos.y - self.position.y).signum();

            if dx != 0 || dy != 0 {
                self.direction = Direction::from_offset(dx, dy);
                self.position = Position::new(self.position.x + dx, self.position.y + dy);
            }

            // Remove waypoint if reached
            if self.position == next_pos {
                self.walking_queue.remove(0);
            }
        }

        // Process fatigue recovery if sleeping
        if self.settings.sleeping && self.fatigue > 0 {
            self.fatigue = self.fatigue.saturating_sub(1);
        }
    }

    /// Calculate combat level from skills.
    pub fn calculate_combat_level(&mut self) {
        let attack = self.skills.level(SkillId::Attack) as f64;
        let strength = self.skills.level(SkillId::Strength) as f64;
        let defense = self.skills.level(SkillId::Defence) as f64;
        let hits = self.skills.level(SkillId::Hits) as f64;
        let ranged = self.skills.level(SkillId::Ranged) as f64;
        let prayer = self.skills.level(SkillId::Prayer) as f64;
        let magic = self.skills.level(SkillId::Magic) as f64;

        let base = (defense + hits + (prayer / 8.0)) / 4.0;
        let melee = (attack + strength) * 0.25;
        let range = ranged * 0.375;
        let mage = magic * 0.375;

        let combat = base + melee.max(range).max(mage);
        self.combat_level = combat as u32;
    }

    /// Check if player can attack another player in wilderness.
    pub fn can_attack_in_wilderness(&self, target: &Player) -> bool {
        let wilderness_level = self.position.wilderness_level();
        if wilderness_level == 0 {
            return false;
        }

        let level_diff = (self.combat_level as i32 - target.combat_level as i32).unsigned_abs();
        level_diff <= wilderness_level
    }

    /// Add experience to a skill.
    pub fn add_experience(&mut self, skill: SkillId, exp: u32) {
        if self.fatigue >= 750 {
            // Max fatigue, no XP gain
            return;
        }

        self.skills.add_experience(skill, exp);
        self.fatigue = (self.fatigue + exp / 4).min(750);

        // Recalculate combat level if combat skill
        if matches!(
            skill,
            SkillId::Attack
                | SkillId::Strength
                | SkillId::Defence
                | SkillId::Hits
                | SkillId::Ranged
                | SkillId::Prayer
                | SkillId::Magic
        ) {
            self.calculate_combat_level();
        }
    }
}

impl Entity for Player {
    fn id(&self) -> EntityId {
        EntityId(self.id)
    }

    fn position(&self) -> Position {
        self.position
    }

    fn set_position(&mut self, pos: Position) {
        self.position = pos;
    }

    fn direction(&self) -> Direction {
        self.direction
    }

    fn is_visible(&self) -> bool {
        self.online
    }
}

/// Skill IDs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SkillId {
    Attack = 0,
    Defence = 1,
    Strength = 2,
    Hits = 3,
    Ranged = 4,
    Prayer = 5,
    Magic = 6,
    Cooking = 7,
    Woodcutting = 8,
    Fletching = 9,
    Fishing = 10,
    Firemaking = 11,
    Crafting = 12,
    Smithing = 13,
    Mining = 14,
    Herblore = 15,
    Agility = 16,
    Thieving = 17,
}

/// Player inventory.
#[derive(Debug, Default)]
pub struct Inventory {
    items: Vec<Option<Item>>,
    capacity: usize,
}

impl Inventory {
    pub fn new() -> Self {
        Self {
            items: vec![None; 30],
            capacity: 30,
        }
    }

    pub fn add(&mut self, item: Item) -> bool {
        // Check for existing stack
        if item.stackable {
            for slot in &mut self.items {
                if let Some(existing) = slot {
                    if existing.id == item.id {
                        existing.amount += item.amount;
                        return true;
                    }
                }
            }
        }

        // Find empty slot
        for slot in &mut self.items {
            if slot.is_none() {
                *slot = Some(item);
                return true;
            }
        }

        false // Inventory full
    }

    pub fn remove(&mut self, item_id: u32, amount: u32) -> bool {
        for slot in &mut self.items {
            if let Some(existing) = slot {
                if existing.id == item_id {
                    if existing.amount > amount {
                        existing.amount -= amount;
                    } else {
                        *slot = None;
                    }
                    return true;
                }
            }
        }
        false
    }

    pub fn free_slots(&self) -> usize {
        self.items.iter().filter(|s| s.is_none()).count()
    }

    pub fn count(&self, item_id: u32) -> u32 {
        self.items
            .iter()
            .filter_map(|s| s.as_ref())
            .filter(|i| i.id == item_id)
            .map(|i| i.amount)
            .sum()
    }

    pub fn items(&self) -> &Vec<Option<Item>> {
        &self.items
    }
}

/// Player equipment slots.
#[derive(Debug, Default)]
pub struct Equipment {
    slots: HashMap<EquipmentSlot, Item>,
}

impl Equipment {
    pub fn new() -> Self {
        Self {
            slots: HashMap::new(),
        }
    }

    pub fn equip(&mut self, slot: EquipmentSlot, item: Item) -> Option<Item> {
        self.slots.insert(slot, item)
    }

    pub fn unequip(&mut self, slot: EquipmentSlot) -> Option<Item> {
        self.slots.remove(&slot)
    }

    pub fn get(&self, slot: EquipmentSlot) -> Option<&Item> {
        self.slots.get(&slot)
    }

    pub fn has_equipped(&self, item_id: u32) -> bool {
        self.slots.values().any(|i| i.id == item_id)
    }
}

/// Equipment slot types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EquipmentSlot {
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
}

/// Item representation.
#[derive(Debug, Clone)]
pub struct Item {
    pub id: u32,
    pub amount: u32,
    pub stackable: bool,
    pub noted: bool,
}

impl Item {
    pub fn new(id: u32, amount: u32) -> Self {
        Self {
            id,
            amount,
            stackable: false,
            noted: false,
        }
    }

    pub fn stackable(id: u32, amount: u32) -> Self {
        Self {
            id,
            amount,
            stackable: true,
            noted: false,
        }
    }
}

/// Player settings.
#[derive(Debug, Default)]
pub struct PlayerSettings {
    pub sleeping: bool,
    pub block_chat: bool,
    pub block_private: bool,
    pub block_trade: bool,
    pub block_duel: bool,
    pub camera_auto: bool,
    pub one_mouse_button: bool,
    pub sound_off: bool,
}
