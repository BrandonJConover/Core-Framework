//! Firemaking skill system.
//! Handles lighting logs on fire.

use std::collections::HashMap;
use tracing::{debug, info};

use super::entity::Position;

/// Types of logs that can be lit.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LogType {
    NormalLogs,
    OakLogs,
    WillowLogs,
    MapleLogs,
    YewLogs,
    MagicLogs,
}

impl LogType {
    /// Get the item ID for this log type.
    pub fn item_id(&self) -> u32 {
        match self {
            LogType::NormalLogs => 14,
            LogType::OakLogs => 632,
            LogType::WillowLogs => 633,
            LogType::MapleLogs => 634,
            LogType::YewLogs => 635,
            LogType::MagicLogs => 636,
        }
    }

    /// Get required firemaking level.
    pub fn required_level(&self) -> u8 {
        match self {
            LogType::NormalLogs => 1,
            LogType::OakLogs => 15,
            LogType::WillowLogs => 30,
            LogType::MapleLogs => 45,
            LogType::YewLogs => 60,
            LogType::MagicLogs => 75,
        }
    }

    /// Get firemaking experience.
    pub fn experience(&self) -> u32 {
        match self {
            LogType::NormalLogs => 100,
            LogType::OakLogs => 150,
            LogType::WillowLogs => 180,
            LogType::MapleLogs => 202,
            LogType::YewLogs => 252,
            LogType::MagicLogs => 607,
        }
    }

    /// Get fire duration in game ticks.
    pub fn fire_duration(&self) -> u32 {
        match self {
            LogType::NormalLogs => 100,
            LogType::OakLogs => 150,
            LogType::WillowLogs => 200,
            LogType::MapleLogs => 250,
            LogType::YewLogs => 300,
            LogType::MagicLogs => 400,
        }
    }
}

/// Tinderbox item ID.
pub const TINDERBOX_ID: u32 = 166;

/// Fire object IDs.
pub const FIRE_OBJECT_ID: u32 = 97;
pub const FIRE_ASHES_ID: u32 = 181; // Ashes item ID

/// A fire burning in the world.
#[derive(Debug, Clone)]
pub struct Fire {
    /// Position of the fire.
    pub position: Position,
    /// Log type that created this fire.
    pub log_type: LogType,
    /// Remaining burn time in ticks.
    pub remaining_ticks: u32,
}

impl Fire {
    /// Create a new fire.
    pub fn new(position: Position, log_type: LogType) -> Self {
        Self {
            position,
            log_type,
            remaining_ticks: log_type.fire_duration(),
        }
    }

    /// Check if fire is still burning.
    pub fn is_burning(&self) -> bool {
        self.remaining_ticks > 0
    }

    /// Tick the fire (reduce remaining time).
    pub fn tick(&mut self) {
        if self.remaining_ticks > 0 {
            self.remaining_ticks -= 1;
        }
    }
}

/// Calculate lighting success chance.
pub fn calculate_light_chance(firemaking_level: u8, log_level: u8) -> f64 {
    let level_diff = firemaking_level.saturating_sub(log_level) as f64;
    let base_chance = 0.5 + (level_diff * 0.02);
    base_chance.clamp(0.3, 0.95)
}

/// Manager for firemaking system.
#[derive(Debug, Default)]
pub struct FiremakingManager {
    /// Active fires by position.
    fires: HashMap<(u16, u16), Fire>,
}

impl FiremakingManager {
    /// Create a new firemaking manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a fire at position.
    pub fn add_fire(&mut self, fire: Fire) {
        let key = (fire.position.x, fire.position.y);
        self.fires.insert(key, fire);
    }

    /// Get fire at position.
    pub fn get_fire(&self, x: u16, y: u16) -> Option<&Fire> {
        self.fires.get(&(x, y))
    }

    /// Check if there's a fire at position.
    pub fn has_fire(&self, x: u16, y: u16) -> bool {
        self.fires.contains_key(&(x, y))
    }

    /// Tick all fires and remove burnt out ones.
    pub fn tick(&mut self) -> Vec<Position> {
        let mut burnt_out = Vec::new();

        self.fires.retain(|_, fire| {
            fire.tick();
            if fire.is_burning() {
                true
            } else {
                burnt_out.push(fire.position);
                false
            }
        });

        burnt_out
    }

    /// Get log type from item ID.
    pub fn log_type_from_id(item_id: u32) -> Option<LogType> {
        match item_id {
            14 => Some(LogType::NormalLogs),
            632 => Some(LogType::OakLogs),
            633 => Some(LogType::WillowLogs),
            634 => Some(LogType::MapleLogs),
            635 => Some(LogType::YewLogs),
            636 => Some(LogType::MagicLogs),
            _ => None,
        }
    }

    /// Check if position is valid for fire (not blocking).
    pub fn can_light_at(x: u16, y: u16) -> bool {
        // In a real implementation, would check for objects/blocking tiles
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_levels() {
        assert_eq!(LogType::NormalLogs.required_level(), 1);
        assert_eq!(LogType::MagicLogs.required_level(), 75);
    }

    #[test]
    fn test_light_chance() {
        // High level = high chance
        let chance = calculate_light_chance(99, 1);
        assert!(chance > 0.9);

        // At required level = moderate chance
        let chance2 = calculate_light_chance(1, 1);
        assert!((chance2 - 0.5).abs() < 0.1);
    }

    #[test]
    fn test_fire_lifecycle() {
        let pos = Position { x: 100, y: 100, plane: 0 };
        let mut fire = Fire::new(pos, LogType::NormalLogs);

        assert!(fire.is_burning());

        // Tick down to 0
        for _ in 0..100 {
            fire.tick();
        }

        assert!(!fire.is_burning());
    }

    #[test]
    fn test_log_type_lookup() {
        assert_eq!(
            FiremakingManager::log_type_from_id(14),
            Some(LogType::NormalLogs)
        );
        assert_eq!(
            FiremakingManager::log_type_from_id(636),
            Some(LogType::MagicLogs)
        );
        assert_eq!(FiremakingManager::log_type_from_id(999), None);
    }
}
