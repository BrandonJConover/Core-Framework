//! Magic and spellcasting system.
//! Handles spell definitions, requirements, and casting logic.

use std::collections::HashMap;
use tracing::{debug, info, warn};

use super::entity::Position;
use super::item::ItemId;
use super::skills::Skills;

/// Rune item IDs for spell requirements.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RuneType {
    Air,
    Water,
    Earth,
    Fire,
    Mind,
    Body,
    Cosmic,
    Chaos,
    Nature,
    Law,
    Death,
    Blood,
    Soul,
}

impl RuneType {
    /// Get the item ID for this rune type.
    pub fn item_id(&self) -> ItemId {
        match self {
            RuneType::Air => ItemId(33),
            RuneType::Water => ItemId(32),
            RuneType::Earth => ItemId(34),
            RuneType::Fire => ItemId(31),
            RuneType::Mind => ItemId(35),
            RuneType::Body => ItemId(36),
            RuneType::Cosmic => ItemId(46),
            RuneType::Chaos => ItemId(41),
            RuneType::Nature => ItemId(40),
            RuneType::Law => ItemId(42),
            RuneType::Death => ItemId(38),
            RuneType::Blood => ItemId(619),
            RuneType::Soul => ItemId(825),
        }
    }

    /// Get the name of this rune type.
    pub fn name(&self) -> &'static str {
        match self {
            RuneType::Air => "Air",
            RuneType::Water => "Water",
            RuneType::Earth => "Earth",
            RuneType::Fire => "Fire",
            RuneType::Mind => "Mind",
            RuneType::Body => "Body",
            RuneType::Cosmic => "Cosmic",
            RuneType::Chaos => "Chaos",
            RuneType::Nature => "Nature",
            RuneType::Law => "Law",
            RuneType::Death => "Death",
            RuneType::Blood => "Blood",
            RuneType::Soul => "Soul",
        }
    }
}

/// Spell category/type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpellCategory {
    /// Combat spells that deal damage.
    Combat,
    /// Teleportation spells.
    Teleport,
    /// Enchantment spells (jewelry).
    Enchant,
    /// Alchemy spells.
    Alchemy,
    /// Utility spells (bones to bananas, etc.).
    Utility,
    /// Curse spells that affect targets.
    Curse,
    /// Charge spells for god staves.
    Charge,
}

/// Rune requirement for a spell.
#[derive(Debug, Clone, PartialEq)]
pub struct RuneRequirement {
    pub rune_type: RuneType,
    pub amount: u32,
}

impl RuneRequirement {
    pub fn new(rune_type: RuneType, amount: u32) -> Self {
        Self { rune_type, amount }
    }
}

/// Spell definition.
#[derive(Debug, Clone)]
pub struct SpellDef {
    /// Unique spell ID.
    pub id: u32,
    /// Spell name.
    pub name: String,
    /// Category of spell.
    pub category: SpellCategory,
    /// Required magic level.
    pub level_required: u8,
    /// Base experience for casting.
    pub base_experience: f64,
    /// Rune requirements.
    pub runes: Vec<RuneRequirement>,
    /// Base damage for combat spells (0 for non-combat).
    pub base_damage: u8,
    /// Teleport destination for teleport spells.
    pub teleport_destination: Option<Position>,
    /// Whether this spell requires a target.
    pub requires_target: bool,
    /// Description of the spell.
    pub description: String,
}

impl SpellDef {
    /// Create a new spell definition builder.
    pub fn builder(id: u32, name: &str) -> SpellDefBuilder {
        SpellDefBuilder::new(id, name)
    }

    /// Check if a player has the required magic level.
    pub fn has_level(&self, magic_level: u8) -> bool {
        magic_level >= self.level_required
    }
}

/// Builder for spell definitions.
pub struct SpellDefBuilder {
    def: SpellDef,
}

impl SpellDefBuilder {
    pub fn new(id: u32, name: &str) -> Self {
        Self {
            def: SpellDef {
                id,
                name: name.to_string(),
                category: SpellCategory::Combat,
                level_required: 1,
                base_experience: 0.0,
                runes: Vec::new(),
                base_damage: 0,
                teleport_destination: None,
                requires_target: false,
                description: String::new(),
            },
        }
    }

    pub fn category(mut self, category: SpellCategory) -> Self {
        self.def.category = category;
        self
    }

    pub fn level(mut self, level: u8) -> Self {
        self.def.level_required = level;
        self
    }

    pub fn experience(mut self, xp: f64) -> Self {
        self.def.base_experience = xp;
        self
    }

    pub fn rune(mut self, rune_type: RuneType, amount: u32) -> Self {
        self.def.runes.push(RuneRequirement::new(rune_type, amount));
        self
    }

    pub fn damage(mut self, damage: u8) -> Self {
        self.def.base_damage = damage;
        self
    }

    pub fn teleport(mut self, x: i32, y: i32) -> Self {
        self.def.teleport_destination = Some(Position { x, y, plane: 0 });
        self.def.category = SpellCategory::Teleport;
        self
    }

    pub fn requires_target(mut self) -> Self {
        self.def.requires_target = true;
        self
    }

    pub fn description(mut self, desc: &str) -> Self {
        self.def.description = desc.to_string();
        self
    }

    pub fn build(self) -> SpellDef {
        self.def
    }
}

/// Spellbook containing all available spells.
#[derive(Debug, Default)]
pub struct Spellbook {
    spells: HashMap<u32, SpellDef>,
}

impl Spellbook {
    /// Create a new empty spellbook.
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a spell to the spellbook.
    pub fn add(&mut self, spell: SpellDef) {
        self.spells.insert(spell.id, spell);
    }

    /// Get a spell by ID.
    pub fn get(&self, id: u32) -> Option<&SpellDef> {
        self.spells.get(&id)
    }

    /// Get all spells sorted by level.
    pub fn all_by_level(&self) -> Vec<&SpellDef> {
        let mut spells: Vec<_> = self.spells.values().collect();
        spells.sort_by_key(|s| s.level_required);
        spells
    }

    /// Load default RSC spells.
    pub fn load_defaults(&mut self) {
        // Combat spells
        self.add(
            SpellDef::builder(0, "Wind Strike")
                .category(SpellCategory::Combat)
                .level(1)
                .experience(5.5)
                .rune(RuneType::Air, 1)
                .rune(RuneType::Mind, 1)
                .damage(2)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(1, "Water Strike")
                .category(SpellCategory::Combat)
                .level(5)
                .experience(7.5)
                .rune(RuneType::Water, 1)
                .rune(RuneType::Air, 1)
                .rune(RuneType::Mind, 1)
                .damage(4)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(2, "Earth Strike")
                .category(SpellCategory::Combat)
                .level(9)
                .experience(9.5)
                .rune(RuneType::Earth, 2)
                .rune(RuneType::Air, 1)
                .rune(RuneType::Mind, 1)
                .damage(6)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(3, "Fire Strike")
                .category(SpellCategory::Combat)
                .level(13)
                .experience(11.5)
                .rune(RuneType::Fire, 3)
                .rune(RuneType::Air, 2)
                .rune(RuneType::Mind, 1)
                .damage(8)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(4, "Wind Bolt")
                .category(SpellCategory::Combat)
                .level(17)
                .experience(13.5)
                .rune(RuneType::Air, 2)
                .rune(RuneType::Chaos, 1)
                .damage(9)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(5, "Water Bolt")
                .category(SpellCategory::Combat)
                .level(23)
                .experience(16.5)
                .rune(RuneType::Water, 2)
                .rune(RuneType::Air, 2)
                .rune(RuneType::Chaos, 1)
                .damage(10)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(6, "Earth Bolt")
                .category(SpellCategory::Combat)
                .level(29)
                .experience(19.5)
                .rune(RuneType::Earth, 3)
                .rune(RuneType::Air, 2)
                .rune(RuneType::Chaos, 1)
                .damage(11)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(7, "Fire Bolt")
                .category(SpellCategory::Combat)
                .level(35)
                .experience(22.5)
                .rune(RuneType::Fire, 4)
                .rune(RuneType::Air, 3)
                .rune(RuneType::Chaos, 1)
                .damage(12)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(8, "Wind Blast")
                .category(SpellCategory::Combat)
                .level(41)
                .experience(25.5)
                .rune(RuneType::Air, 3)
                .rune(RuneType::Death, 1)
                .damage(13)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(9, "Water Blast")
                .category(SpellCategory::Combat)
                .level(47)
                .experience(28.5)
                .rune(RuneType::Water, 3)
                .rune(RuneType::Air, 3)
                .rune(RuneType::Death, 1)
                .damage(14)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(10, "Earth Blast")
                .category(SpellCategory::Combat)
                .level(53)
                .experience(31.5)
                .rune(RuneType::Earth, 4)
                .rune(RuneType::Air, 3)
                .rune(RuneType::Death, 1)
                .damage(15)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(11, "Fire Blast")
                .category(SpellCategory::Combat)
                .level(59)
                .experience(34.5)
                .rune(RuneType::Fire, 5)
                .rune(RuneType::Air, 4)
                .rune(RuneType::Death, 1)
                .damage(16)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(12, "Wind Wave")
                .category(SpellCategory::Combat)
                .level(62)
                .experience(36.0)
                .rune(RuneType::Air, 5)
                .rune(RuneType::Blood, 1)
                .damage(17)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(13, "Water Wave")
                .category(SpellCategory::Combat)
                .level(65)
                .experience(37.5)
                .rune(RuneType::Water, 7)
                .rune(RuneType::Air, 5)
                .rune(RuneType::Blood, 1)
                .damage(18)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(14, "Earth Wave")
                .category(SpellCategory::Combat)
                .level(70)
                .experience(40.0)
                .rune(RuneType::Earth, 7)
                .rune(RuneType::Air, 5)
                .rune(RuneType::Blood, 1)
                .damage(19)
                .requires_target()
                .build(),
        );

        self.add(
            SpellDef::builder(15, "Fire Wave")
                .category(SpellCategory::Combat)
                .level(75)
                .experience(42.5)
                .rune(RuneType::Fire, 7)
                .rune(RuneType::Air, 5)
                .rune(RuneType::Blood, 1)
                .damage(20)
                .requires_target()
                .build(),
        );

        // Teleport spells
        self.add(
            SpellDef::builder(20, "Varrock Teleport")
                .category(SpellCategory::Teleport)
                .level(25)
                .experience(35.0)
                .rune(RuneType::Fire, 1)
                .rune(RuneType::Air, 3)
                .rune(RuneType::Law, 1)
                .teleport(122, 509)
                .build(),
        );

        self.add(
            SpellDef::builder(21, "Lumbridge Teleport")
                .category(SpellCategory::Teleport)
                .level(31)
                .experience(41.0)
                .rune(RuneType::Earth, 1)
                .rune(RuneType::Air, 3)
                .rune(RuneType::Law, 1)
                .teleport(120, 648)
                .build(),
        );

        self.add(
            SpellDef::builder(22, "Falador Teleport")
                .category(SpellCategory::Teleport)
                .level(37)
                .experience(47.0)
                .rune(RuneType::Water, 1)
                .rune(RuneType::Air, 3)
                .rune(RuneType::Law, 1)
                .teleport(312, 552)
                .build(),
        );

        self.add(
            SpellDef::builder(23, "Camelot Teleport")
                .category(SpellCategory::Teleport)
                .level(45)
                .experience(55.5)
                .rune(RuneType::Air, 5)
                .rune(RuneType::Law, 1)
                .teleport(465, 456)
                .build(),
        );

        self.add(
            SpellDef::builder(24, "Ardougne Teleport")
                .category(SpellCategory::Teleport)
                .level(51)
                .experience(61.0)
                .rune(RuneType::Water, 2)
                .rune(RuneType::Law, 2)
                .teleport(588, 621)
                .build(),
        );

        // Alchemy spells
        self.add(
            SpellDef::builder(30, "Low Level Alchemy")
                .category(SpellCategory::Alchemy)
                .level(21)
                .experience(31.0)
                .rune(RuneType::Fire, 3)
                .rune(RuneType::Nature, 1)
                .description("Converts an item into coins at 40% of its value")
                .build(),
        );

        self.add(
            SpellDef::builder(31, "High Level Alchemy")
                .category(SpellCategory::Alchemy)
                .level(55)
                .experience(65.0)
                .rune(RuneType::Fire, 5)
                .rune(RuneType::Nature, 1)
                .description("Converts an item into coins at 60% of its value")
                .build(),
        );

        // Utility spells
        self.add(
            SpellDef::builder(40, "Bones to Bananas")
                .category(SpellCategory::Utility)
                .level(15)
                .experience(25.0)
                .rune(RuneType::Earth, 2)
                .rune(RuneType::Water, 2)
                .rune(RuneType::Nature, 1)
                .description("Converts bones in inventory to bananas")
                .build(),
        );

        self.add(
            SpellDef::builder(41, "Superheat Item")
                .category(SpellCategory::Utility)
                .level(43)
                .experience(53.0)
                .rune(RuneType::Fire, 4)
                .rune(RuneType::Nature, 1)
                .description("Smelts ore without a furnace")
                .build(),
        );

        // Curse spells
        self.add(
            SpellDef::builder(50, "Confuse")
                .category(SpellCategory::Curse)
                .level(3)
                .experience(13.0)
                .rune(RuneType::Water, 3)
                .rune(RuneType::Earth, 2)
                .rune(RuneType::Body, 1)
                .requires_target()
                .description("Reduces opponent's attack by 5%")
                .build(),
        );

        self.add(
            SpellDef::builder(51, "Weaken")
                .category(SpellCategory::Curse)
                .level(11)
                .experience(21.0)
                .rune(RuneType::Water, 3)
                .rune(RuneType::Earth, 2)
                .rune(RuneType::Body, 1)
                .requires_target()
                .description("Reduces opponent's strength by 5%")
                .build(),
        );

        self.add(
            SpellDef::builder(52, "Curse")
                .category(SpellCategory::Curse)
                .level(19)
                .experience(29.0)
                .rune(RuneType::Water, 2)
                .rune(RuneType::Earth, 3)
                .rune(RuneType::Body, 1)
                .requires_target()
                .description("Reduces opponent's defence by 5%")
                .build(),
        );

        info!("Loaded {} spells", self.spells.len());
    }
}

/// Result of a spell cast attempt.
#[derive(Debug, Clone, PartialEq)]
pub enum CastResult {
    /// Spell cast successfully.
    Success {
        experience: f64,
        damage: Option<u8>,
    },
    /// Insufficient magic level.
    InsufficientLevel { required: u8, current: u8 },
    /// Missing runes.
    MissingRunes { missing: Vec<RuneRequirement> },
    /// Spell is on cooldown.
    OnCooldown { remaining_ticks: u32 },
    /// No valid target.
    NoTarget,
    /// Target out of range.
    OutOfRange,
    /// Cannot cast in this area.
    RestrictedArea,
    /// Spell splash (hit 0).
    Splash,
}

/// Magic state for a player.
#[derive(Debug, Clone, Default)]
pub struct MagicState {
    /// Current cast cooldown in ticks.
    cooldown: u32,
    /// Whether god spell charge is active.
    god_charge_active: bool,
    /// Remaining god charge ticks.
    god_charge_ticks: u32,
    /// Last spell cast ID.
    last_spell: Option<u32>,
}

impl MagicState {
    /// Create new magic state.
    pub fn new() -> Self {
        Self::default()
    }

    /// Process a game tick.
    pub fn tick(&mut self) {
        if self.cooldown > 0 {
            self.cooldown -= 1;
        }
        if self.god_charge_ticks > 0 {
            self.god_charge_ticks -= 1;
            if self.god_charge_ticks == 0 {
                self.god_charge_active = false;
            }
        }
    }

    /// Check if magic is on cooldown.
    pub fn is_on_cooldown(&self) -> bool {
        self.cooldown > 0
    }

    /// Set cooldown after casting.
    pub fn set_cooldown(&mut self, ticks: u32) {
        self.cooldown = ticks;
    }

    /// Get remaining cooldown.
    pub fn remaining_cooldown(&self) -> u32 {
        self.cooldown
    }

    /// Activate god charge.
    pub fn activate_god_charge(&mut self, duration_ticks: u32) {
        self.god_charge_active = true;
        self.god_charge_ticks = duration_ticks;
    }

    /// Check if god charge is active.
    pub fn has_god_charge(&self) -> bool {
        self.god_charge_active
    }

    /// Set last spell cast.
    pub fn set_last_spell(&mut self, spell_id: u32) {
        self.last_spell = Some(spell_id);
    }

    /// Get last spell cast.
    pub fn last_spell(&self) -> Option<u32> {
        self.last_spell
    }
}

/// Calculate magic hit chance and damage.
pub fn calculate_magic_damage(
    caster_magic: u8,
    target_magic: u8,
    base_damage: u8,
    has_god_charge: bool,
) -> (bool, u8) {
    // Simplified magic formula
    let hit_chance = 50 + (caster_magic as i32 - target_magic as i32);
    let hit_chance = hit_chance.clamp(5, 95);

    let roll = rand::random::<u8>() % 100;
    if (roll as i32) < hit_chance {
        // Calculate damage
        let mut max_damage = base_damage;
        if has_god_charge {
            max_damage = max_damage.saturating_add(5);
        }
        let damage = rand::random::<u8>() % (max_damage + 1);
        (true, damage)
    } else {
        (false, 0) // Splash
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spellbook_loading() {
        let mut book = Spellbook::new();
        book.load_defaults();

        assert!(book.get(0).is_some()); // Wind Strike
        assert!(book.get(20).is_some()); // Varrock Teleport
        assert!(book.get(30).is_some()); // Low Alchemy
    }

    #[test]
    fn test_spell_requirements() {
        let spell = SpellDef::builder(0, "Test Spell")
            .level(10)
            .rune(RuneType::Air, 2)
            .rune(RuneType::Fire, 1)
            .build();

        assert!(spell.has_level(10));
        assert!(spell.has_level(99));
        assert!(!spell.has_level(9));
        assert_eq!(spell.runes.len(), 2);
    }

    #[test]
    fn test_magic_state() {
        let mut state = MagicState::new();

        state.set_cooldown(5);
        assert!(state.is_on_cooldown());

        for _ in 0..5 {
            state.tick();
        }
        assert!(!state.is_on_cooldown());
    }
}
