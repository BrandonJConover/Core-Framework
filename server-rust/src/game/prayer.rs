//! Prayer system for player prayer activation and management.
//!
//! Implements the RuneScape Classic prayer system with drain rates,
//! prayer point management, and combat bonuses.

use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use tracing::debug;

/// Prayer IDs matching RSC prayer list.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum PrayerId {
    // Combat prayers
    ThickSkin = 0,
    BurstOfStrength = 1,
    ClarityOfThought = 2,
    RockSkin = 3,
    SuperhumanStrength = 4,
    ImprovedReflexes = 5,
    RapidRestore = 6,
    RapidHeal = 7,
    ProtectItems = 8,
    SteelSkin = 9,
    UltimateStrength = 10,
    IncredibleReflexes = 11,
    Paralyze = 12,
    ProtectFromMissiles = 13,
}

impl PrayerId {
    /// Get all prayer IDs.
    pub fn all() -> &'static [PrayerId] {
        &[
            PrayerId::ThickSkin,
            PrayerId::BurstOfStrength,
            PrayerId::ClarityOfThought,
            PrayerId::RockSkin,
            PrayerId::SuperhumanStrength,
            PrayerId::ImprovedReflexes,
            PrayerId::RapidRestore,
            PrayerId::RapidHeal,
            PrayerId::ProtectItems,
            PrayerId::SteelSkin,
            PrayerId::UltimateStrength,
            PrayerId::IncredibleReflexes,
            PrayerId::Paralyze,
            PrayerId::ProtectFromMissiles,
        ]
    }

    /// Get prayer from ID number.
    pub fn from_id(id: u8) -> Option<PrayerId> {
        match id {
            0 => Some(PrayerId::ThickSkin),
            1 => Some(PrayerId::BurstOfStrength),
            2 => Some(PrayerId::ClarityOfThought),
            3 => Some(PrayerId::RockSkin),
            4 => Some(PrayerId::SuperhumanStrength),
            5 => Some(PrayerId::ImprovedReflexes),
            6 => Some(PrayerId::RapidRestore),
            7 => Some(PrayerId::RapidHeal),
            8 => Some(PrayerId::ProtectItems),
            9 => Some(PrayerId::SteelSkin),
            10 => Some(PrayerId::UltimateStrength),
            11 => Some(PrayerId::IncredibleReflexes),
            12 => Some(PrayerId::Paralyze),
            13 => Some(PrayerId::ProtectFromMissiles),
            _ => None,
        }
    }
}

/// Prayer definition with requirements and effects.
#[derive(Debug, Clone)]
pub struct PrayerDef {
    pub id: PrayerId,
    pub name: &'static str,
    pub level_required: u32,
    pub drain_rate: u32, // Points per minute
    pub defense_bonus: i32,
    pub strength_bonus: i32,
    pub attack_bonus: i32,
    pub conflicts_with: &'static [PrayerId],
}

impl PrayerDef {
    /// Get prayer definition.
    pub fn get(id: PrayerId) -> &'static PrayerDef {
        match id {
            PrayerId::ThickSkin => &THICK_SKIN,
            PrayerId::BurstOfStrength => &BURST_OF_STRENGTH,
            PrayerId::ClarityOfThought => &CLARITY_OF_THOUGHT,
            PrayerId::RockSkin => &ROCK_SKIN,
            PrayerId::SuperhumanStrength => &SUPERHUMAN_STRENGTH,
            PrayerId::ImprovedReflexes => &IMPROVED_REFLEXES,
            PrayerId::RapidRestore => &RAPID_RESTORE,
            PrayerId::RapidHeal => &RAPID_HEAL,
            PrayerId::ProtectItems => &PROTECT_ITEMS,
            PrayerId::SteelSkin => &STEEL_SKIN,
            PrayerId::UltimateStrength => &ULTIMATE_STRENGTH,
            PrayerId::IncredibleReflexes => &INCREDIBLE_REFLEXES,
            PrayerId::Paralyze => &PARALYZE,
            PrayerId::ProtectFromMissiles => &PROTECT_FROM_MISSILES,
        }
    }
}

// Prayer definitions
static THICK_SKIN: PrayerDef = PrayerDef {
    id: PrayerId::ThickSkin,
    name: "Thick Skin",
    level_required: 1,
    drain_rate: 3,
    defense_bonus: 5,
    strength_bonus: 0,
    attack_bonus: 0,
    conflicts_with: &[PrayerId::RockSkin, PrayerId::SteelSkin],
};

static BURST_OF_STRENGTH: PrayerDef = PrayerDef {
    id: PrayerId::BurstOfStrength,
    name: "Burst of Strength",
    level_required: 4,
    drain_rate: 3,
    defense_bonus: 0,
    strength_bonus: 5,
    attack_bonus: 0,
    conflicts_with: &[PrayerId::SuperhumanStrength, PrayerId::UltimateStrength],
};

static CLARITY_OF_THOUGHT: PrayerDef = PrayerDef {
    id: PrayerId::ClarityOfThought,
    name: "Clarity of Thought",
    level_required: 7,
    drain_rate: 3,
    defense_bonus: 0,
    strength_bonus: 0,
    attack_bonus: 5,
    conflicts_with: &[PrayerId::ImprovedReflexes, PrayerId::IncredibleReflexes],
};

static ROCK_SKIN: PrayerDef = PrayerDef {
    id: PrayerId::RockSkin,
    name: "Rock Skin",
    level_required: 10,
    drain_rate: 6,
    defense_bonus: 10,
    strength_bonus: 0,
    attack_bonus: 0,
    conflicts_with: &[PrayerId::ThickSkin, PrayerId::SteelSkin],
};

static SUPERHUMAN_STRENGTH: PrayerDef = PrayerDef {
    id: PrayerId::SuperhumanStrength,
    name: "Superhuman Strength",
    level_required: 13,
    drain_rate: 6,
    defense_bonus: 0,
    strength_bonus: 10,
    attack_bonus: 0,
    conflicts_with: &[PrayerId::BurstOfStrength, PrayerId::UltimateStrength],
};

static IMPROVED_REFLEXES: PrayerDef = PrayerDef {
    id: PrayerId::ImprovedReflexes,
    name: "Improved Reflexes",
    level_required: 16,
    drain_rate: 6,
    defense_bonus: 0,
    strength_bonus: 0,
    attack_bonus: 10,
    conflicts_with: &[PrayerId::ClarityOfThought, PrayerId::IncredibleReflexes],
};

static RAPID_RESTORE: PrayerDef = PrayerDef {
    id: PrayerId::RapidRestore,
    name: "Rapid Restore",
    level_required: 19,
    drain_rate: 1,
    defense_bonus: 0,
    strength_bonus: 0,
    attack_bonus: 0,
    conflicts_with: &[],
};

static RAPID_HEAL: PrayerDef = PrayerDef {
    id: PrayerId::RapidHeal,
    name: "Rapid Heal",
    level_required: 22,
    drain_rate: 2,
    defense_bonus: 0,
    strength_bonus: 0,
    attack_bonus: 0,
    conflicts_with: &[],
};

static PROTECT_ITEMS: PrayerDef = PrayerDef {
    id: PrayerId::ProtectItems,
    name: "Protect Items",
    level_required: 25,
    drain_rate: 2,
    defense_bonus: 0,
    strength_bonus: 0,
    attack_bonus: 0,
    conflicts_with: &[],
};

static STEEL_SKIN: PrayerDef = PrayerDef {
    id: PrayerId::SteelSkin,
    name: "Steel Skin",
    level_required: 28,
    drain_rate: 12,
    defense_bonus: 15,
    strength_bonus: 0,
    attack_bonus: 0,
    conflicts_with: &[PrayerId::ThickSkin, PrayerId::RockSkin],
};

static ULTIMATE_STRENGTH: PrayerDef = PrayerDef {
    id: PrayerId::UltimateStrength,
    name: "Ultimate Strength",
    level_required: 31,
    drain_rate: 12,
    defense_bonus: 0,
    strength_bonus: 15,
    attack_bonus: 0,
    conflicts_with: &[PrayerId::BurstOfStrength, PrayerId::SuperhumanStrength],
};

static INCREDIBLE_REFLEXES: PrayerDef = PrayerDef {
    id: PrayerId::IncredibleReflexes,
    name: "Incredible Reflexes",
    level_required: 34,
    drain_rate: 12,
    defense_bonus: 0,
    strength_bonus: 0,
    attack_bonus: 15,
    conflicts_with: &[PrayerId::ClarityOfThought, PrayerId::ImprovedReflexes],
};

static PARALYZE: PrayerDef = PrayerDef {
    id: PrayerId::Paralyze,
    name: "Paralyze Monster",
    level_required: 37,
    drain_rate: 12,
    defense_bonus: 0,
    strength_bonus: 0,
    attack_bonus: 0,
    conflicts_with: &[],
};

static PROTECT_FROM_MISSILES: PrayerDef = PrayerDef {
    id: PrayerId::ProtectFromMissiles,
    name: "Protect from Missiles",
    level_required: 40,
    drain_rate: 12,
    defense_bonus: 0,
    strength_bonus: 0,
    attack_bonus: 0,
    conflicts_with: &[],
};

/// Player's prayer state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrayerState {
    /// Current prayer points.
    pub points: u32,
    /// Maximum prayer points (based on prayer level).
    pub max_points: u32,
    /// Currently active prayers.
    pub active_prayers: HashSet<PrayerId>,
    /// Accumulated drain (fractional points).
    drain_accumulator: f32,
    /// Ticks since last drain.
    ticks_since_drain: u32,
}

impl PrayerState {
    /// Create a new prayer state.
    pub fn new(prayer_level: u32) -> Self {
        Self {
            points: prayer_level,
            max_points: prayer_level,
            active_prayers: HashSet::new(),
            drain_accumulator: 0.0,
            ticks_since_drain: 0,
        }
    }

    /// Update max points based on prayer level.
    pub fn set_level(&mut self, prayer_level: u32) {
        self.max_points = prayer_level;
        self.points = self.points.min(self.max_points);
    }

    /// Activate a prayer.
    pub fn activate(&mut self, prayer: PrayerId, player_level: u32) -> Result<(), PrayerError> {
        let def = PrayerDef::get(prayer);

        // Check level requirement
        if player_level < def.level_required {
            return Err(PrayerError::LevelTooLow {
                required: def.level_required,
                current: player_level,
            });
        }

        // Check prayer points
        if self.points == 0 {
            return Err(PrayerError::NoPrayerPoints);
        }

        // Already active
        if self.active_prayers.contains(&prayer) {
            return Ok(());
        }

        // Deactivate conflicting prayers
        for &conflict in def.conflicts_with {
            self.active_prayers.remove(&conflict);
        }

        self.active_prayers.insert(prayer);
        debug!("Activated prayer: {:?}", prayer);
        Ok(())
    }

    /// Deactivate a prayer.
    pub fn deactivate(&mut self, prayer: PrayerId) -> bool {
        let removed = self.active_prayers.remove(&prayer);
        if removed {
            debug!("Deactivated prayer: {:?}", prayer);
        }
        removed
    }

    /// Deactivate all prayers.
    pub fn deactivate_all(&mut self) {
        self.active_prayers.clear();
        self.drain_accumulator = 0.0;
        debug!("Deactivated all prayers");
    }

    /// Check if a prayer is active.
    pub fn is_active(&self, prayer: PrayerId) -> bool {
        self.active_prayers.contains(&prayer)
    }

    /// Get total defense bonus from active prayers.
    pub fn defense_bonus(&self) -> i32 {
        self.active_prayers
            .iter()
            .map(|&p| PrayerDef::get(p).defense_bonus)
            .sum()
    }

    /// Get total strength bonus from active prayers.
    pub fn strength_bonus(&self) -> i32 {
        self.active_prayers
            .iter()
            .map(|&p| PrayerDef::get(p).strength_bonus)
            .sum()
    }

    /// Get total attack bonus from active prayers.
    pub fn attack_bonus(&self) -> i32 {
        self.active_prayers
            .iter()
            .map(|&p| PrayerDef::get(p).attack_bonus)
            .sum()
    }

    /// Check if Rapid Restore is active (2x skill restore rate).
    pub fn has_rapid_restore(&self) -> bool {
        self.active_prayers.contains(&PrayerId::RapidRestore)
    }

    /// Check if Rapid Heal is active (2x hitpoints restore rate).
    pub fn has_rapid_heal(&self) -> bool {
        self.active_prayers.contains(&PrayerId::RapidHeal)
    }

    /// Check if Protect Items is active (+1 item kept on death).
    pub fn has_protect_items(&self) -> bool {
        self.active_prayers.contains(&PrayerId::ProtectItems)
    }

    /// Process prayer drain for a game tick.
    /// Returns true if prayers were deactivated due to running out of points.
    pub fn tick(&mut self) -> bool {
        if self.active_prayers.is_empty() {
            return false;
        }

        self.ticks_since_drain += 1;

        // Drain is calculated per minute (100 ticks at 600ms = 60 seconds)
        // Accumulate drain and apply when >= 1
        let total_drain_per_minute: u32 = self
            .active_prayers
            .iter()
            .map(|&p| PrayerDef::get(p).drain_rate)
            .sum();

        // Convert to per-tick drain (assuming 100 ticks/minute)
        let drain_per_tick = total_drain_per_minute as f32 / 100.0;
        self.drain_accumulator += drain_per_tick;

        if self.drain_accumulator >= 1.0 {
            let drain = self.drain_accumulator as u32;
            self.drain_accumulator -= drain as f32;

            if drain >= self.points {
                self.points = 0;
                self.deactivate_all();
                debug!("Prayer points exhausted, all prayers deactivated");
                return true;
            } else {
                self.points -= drain;
            }
        }

        false
    }

    /// Restore prayer points.
    pub fn restore(&mut self, amount: u32) {
        self.points = (self.points + amount).min(self.max_points);
        debug!("Restored {} prayer points (now {})", amount, self.points);
    }

    /// Fully restore prayer points.
    pub fn restore_full(&mut self) {
        self.points = self.max_points;
        debug!("Fully restored prayer points to {}", self.max_points);
    }

    /// Get current prayer points.
    pub fn current_points(&self) -> u32 {
        self.points
    }

    /// Get maximum prayer points.
    pub fn max_points(&self) -> u32 {
        self.max_points
    }
}

impl Default for PrayerState {
    fn default() -> Self {
        Self::new(1)
    }
}

/// Prayer-related errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PrayerError {
    LevelTooLow { required: u32, current: u32 },
    NoPrayerPoints,
    PrayerNotFound,
}

impl std::fmt::Display for PrayerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::LevelTooLow { required, current } => {
                write!(
                    f,
                    "Prayer requires level {} (you have {})",
                    required, current
                )
            }
            Self::NoPrayerPoints => write!(f, "You have no prayer points"),
            Self::PrayerNotFound => write!(f, "Unknown prayer"),
        }
    }
}

impl std::error::Error for PrayerError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prayer_activation() {
        let mut state = PrayerState::new(30);

        // Activate a prayer
        state.activate(PrayerId::ThickSkin, 30).unwrap();
        assert!(state.is_active(PrayerId::ThickSkin));
        assert_eq!(state.defense_bonus(), 5);
    }

    #[test]
    fn test_prayer_conflicts() {
        let mut state = PrayerState::new(30);

        // Activate ThickSkin
        state.activate(PrayerId::ThickSkin, 30).unwrap();
        assert!(state.is_active(PrayerId::ThickSkin));

        // Activate RockSkin (conflicts with ThickSkin)
        state.activate(PrayerId::RockSkin, 30).unwrap();
        assert!(!state.is_active(PrayerId::ThickSkin));
        assert!(state.is_active(PrayerId::RockSkin));
        assert_eq!(state.defense_bonus(), 10);
    }

    #[test]
    fn test_prayer_level_requirement() {
        let mut state = PrayerState::new(5);

        // Try to activate a prayer we don't have the level for
        let result = state.activate(PrayerId::RockSkin, 5);
        assert!(matches!(result, Err(PrayerError::LevelTooLow { .. })));
    }

    #[test]
    fn test_prayer_drain() {
        let mut state = PrayerState::new(10);
        state.activate(PrayerId::ThickSkin, 10).unwrap();

        // Simulate many ticks
        for _ in 0..500 {
            if state.tick() {
                break;
            }
        }

        // Points should be drained
        assert!(state.points < 10);
    }

    #[test]
    fn test_prayer_restore() {
        let mut state = PrayerState::new(30);
        state.points = 10;

        state.restore(15);
        assert_eq!(state.points, 25);

        state.restore(100);
        assert_eq!(state.points, 30); // Capped at max
    }
}
