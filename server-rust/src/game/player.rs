//! Player module for player entity management.

use super::bank_handler::PlayerBank;
use super::combat::CombatStyle;
use super::entity::{Direction, Entity, EntityId, Position};
use super::prayer::PrayerState;
use super::skills::Skills;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::debug;

/// Player entity representing a connected player.
#[derive(Debug)]
pub struct Player {
    pub id: u64,
    pub username: String,
    /// DB primary key — None in accept-all (bench) mode, Some(id) when DB-backed.
    pub db_id: Option<i64>,
    pub position: Position,
    pub direction: Direction,
    pub skills: Skills,
    pub prayer: PrayerState,
    pub inventory: Inventory,
    pub bank: PlayerBank,
    pub equipment: Equipment,
    pub settings: PlayerSettings,
    pub combat_level: u32,
    pub fatigue: u32,
    pub online: bool,
    pub in_combat: bool,
    pub combat_style: CombatStyle,
    pub last_tick: u64,
    pub walking_queue: Vec<Position>,
    pub appearance: Appearance,
    pub appearance_changed: bool,
    pub player_index: u16,
    /// Set true on the tick the player walked one tile. Encoded as a movement
    /// update for nearby players' SEND_PLAYER_COORDS streams; cleared when the
    /// streaming pass finishes.
    pub moved_this_tick: bool,
    /// Server indices of players currently in this player's view area.
    pub local_players: Vec<u64>,
    /// Entity IDs of NPCs currently in this player's view area.
    pub local_npcs: Vec<EntityId>,
    /// Positions of game objects (scenery + boundary) in this player's view.
    pub local_game_objects: Vec<Position>,
    /// (position, item_id) pairs for ground items in this player's view.
    pub local_ground_items: Vec<(Position, u32)>,
    /// Chat messages emitted this tick — drained into SEND_UPDATE_PLAYERS
    /// type-1 entries for nearby players, then cleared.
    pub pending_chat: Vec<String>,
    /// Damage events that landed this tick. Streamed as SEND_UPDATE_PLAYERS
    /// type-2 entries to viewers (and to the player themself). Cleared at
    /// end of tick. Each tuple is (damage, current_hp, max_hp).
    pub pending_hits: Vec<(u8, u8, u8)>,
}

impl Player {
    pub fn new(id: u64, username: String) -> Self {
        Self {
            id,
            username,
            db_id: None,
            position: Position::new(122, 647), // Lumbridge spawn
            direction: Direction::South,
            skills: Skills::new(),
            prayer: PrayerState::new(1),
            inventory: Inventory::new(),
            bank: PlayerBank::new(true),
            equipment: Equipment::new(),
            settings: PlayerSettings::default(),
            combat_level: 3,
            fatigue: 0,
            online: true,
            in_combat: false,
            combat_style: CombatStyle::Controlled,
            last_tick: 0,
            walking_queue: Vec::new(),
            appearance: Appearance::default(),
            appearance_changed: true,
            player_index: 0,
            moved_this_tick: false,
            local_players: Vec::new(),
            local_npcs: Vec::new(),
            local_game_objects: Vec::new(),
            local_ground_items: Vec::new(),
            pending_chat: Vec::new(),
            pending_hits: Vec::new(),
        }
    }

    /// Process player tick.
    pub async fn tick(&mut self) {
        self.last_tick += 1;
        self.moved_this_tick = false;

        // Process walking queue
        if let Some(next_pos) = self.walking_queue.first().cloned() {
            let dx = (next_pos.x - self.position.x).signum();
            let dy = (next_pos.y - self.position.y).signum();

            if dx != 0 || dy != 0 {
                self.direction = Direction::from_offset(dx, dy);
                self.position = Position::new(self.position.x + dx, self.position.y + dy);
                self.moved_this_tick = true;
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
        if skill == SkillId::Prayer {
            self.prayer
                .set_level(self.skills.current_level(SkillId::Prayer) as u32);
        }
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
        self.remove_amount(item_id, amount) == amount
    }

    pub fn remove_amount(&mut self, item_id: u32, amount: u32) -> u32 {
        let mut remaining = amount;
        for slot in &mut self.items {
            if remaining == 0 {
                break;
            }
            if let Some(existing) = slot {
                if existing.id == item_id {
                    if existing.amount > remaining {
                        existing.amount -= remaining;
                        remaining = 0;
                    } else {
                        remaining -= existing.amount;
                        *slot = None;
                    }
                }
            }
        }
        amount - remaining
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

    /// Set a specific slot when hydrating persisted inventory.
    pub fn set_slot(&mut self, slot: usize, item: Item) -> bool {
        if slot >= self.capacity {
            return false;
        }
        self.items[slot] = Some(item);
        true
    }

    /// Remove and return the item in `slot`. Returns None if slot is empty or out of range.
    pub fn take_slot(&mut self, slot: usize) -> Option<Item> {
        self.items.get_mut(slot)?.take()
    }

    /// Toggle the `wielded` flag on `slot`. No-op for empty / out-of-range slots.
    pub fn set_wielded(&mut self, slot: usize, wielded: bool) {
        if let Some(Some(item)) = self.items.get_mut(slot) {
            item.wielded = wielded;
        }
    }

    /// Clear `wielded` on every slot. Used when equipping a new item to make
    /// the per-slot toggle behave like a single-equipment-slot model until the
    /// real item-def slot resolution is wired.
    pub fn unwield_all(&mut self) {
        for slot in self.items.iter_mut() {
            if let Some(item) = slot {
                item.wielded = false;
            }
        }
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
    /// True when the player has equipped this inventory slot. RSC stores
    /// equipment state on inventory items rather than in a separate equipment
    /// container — the inventory packet has a `wielded` byte per slot.
    pub wielded: bool,
}

impl Item {
    pub fn new(id: u32, amount: u32) -> Self {
        Self {
            id,
            amount,
            stackable: false,
            noted: false,
            wielded: false,
        }
    }

    pub fn stackable(id: u32, amount: u32) -> Self {
        Self {
            id,
            amount,
            stackable: true,
            noted: false,
            wielded: false,
        }
    }
}

/// Player visual appearance — set by the client via PLAYER_APPEARANCE_CHANGE.
#[derive(Debug, Clone)]
pub struct Appearance {
    /// 1 = male, 0 = female.
    pub is_male: bool,
    /// Head sprite (1-based, headType+1 in Java).
    pub head_sprite: u8,
    /// Body sprite (1-based, bodyType+1 in Java).
    pub body_sprite: u8,
    pub hair_colour: u8,
    pub top_colour: u8,
    pub trouser_colour: u8,
    pub skin_colour: u8,
}

impl Default for Appearance {
    fn default() -> Self {
        Self {
            is_male: true,
            head_sprite: 1,
            body_sprite: 2,
            hair_colour: 2,
            top_colour: 8,
            trouser_colour: 14,
            skin_colour: 0,
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
