//! Fletching skill system.
//! Handles creating bows, arrows, crossbows, and bolts.

use std::collections::HashMap;
use tracing::info;

/// Bow types that can be fletched.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BowType {
    ShortbowU,
    Shortbow,
    LongbowU,
    Longbow,
    OakShortbowU,
    OakShortbow,
    OakLongbowU,
    OakLongbow,
    WillowShortbowU,
    WillowShortbow,
    WillowLongbowU,
    WillowLongbow,
    MapleShortbowU,
    MapleShortbow,
    MapleLongbowU,
    MapleLongbow,
    YewShortbowU,
    YewShortbow,
    YewLongbowU,
    YewLongbow,
    MagicShortbowU,
    MagicShortbow,
    MagicLongbowU,
    MagicLongbow,
}

impl BowType {
    /// Get item ID.
    pub fn item_id(&self) -> u32 {
        match self {
            BowType::ShortbowU => 277,
            BowType::Shortbow => 188,
            BowType::LongbowU => 276,
            BowType::Longbow => 189,
            BowType::OakShortbowU => 658,
            BowType::OakShortbow => 648,
            BowType::OakLongbowU => 659,
            BowType::OakLongbow => 649,
            BowType::WillowShortbowU => 660,
            BowType::WillowShortbow => 650,
            BowType::WillowLongbowU => 661,
            BowType::WillowLongbow => 651,
            BowType::MapleShortbowU => 662,
            BowType::MapleShortbow => 652,
            BowType::MapleLongbowU => 663,
            BowType::MapleLongbow => 653,
            BowType::YewShortbowU => 664,
            BowType::YewShortbow => 654,
            BowType::YewLongbowU => 665,
            BowType::YewLongbow => 655,
            BowType::MagicShortbowU => 666,
            BowType::MagicShortbow => 656,
            BowType::MagicLongbowU => 667,
            BowType::MagicLongbow => 657,
        }
    }

    /// Get required fletching level.
    pub fn required_level(&self) -> u8 {
        match self {
            BowType::ShortbowU => 5,
            BowType::Shortbow => 5,
            BowType::LongbowU => 10,
            BowType::Longbow => 10,
            BowType::OakShortbowU => 20,
            BowType::OakShortbow => 20,
            BowType::OakLongbowU => 25,
            BowType::OakLongbow => 25,
            BowType::WillowShortbowU => 35,
            BowType::WillowShortbow => 35,
            BowType::WillowLongbowU => 40,
            BowType::WillowLongbow => 40,
            BowType::MapleShortbowU => 50,
            BowType::MapleShortbow => 50,
            BowType::MapleLongbowU => 55,
            BowType::MapleLongbow => 55,
            BowType::YewShortbowU => 65,
            BowType::YewShortbow => 65,
            BowType::YewLongbowU => 70,
            BowType::YewLongbow => 70,
            BowType::MagicShortbowU => 80,
            BowType::MagicShortbow => 80,
            BowType::MagicLongbowU => 85,
            BowType::MagicLongbow => 85,
        }
    }

    /// Get fletching experience.
    pub fn experience(&self) -> u32 {
        match self {
            BowType::ShortbowU => 20,
            BowType::Shortbow => 20,
            BowType::LongbowU => 40,
            BowType::Longbow => 40,
            BowType::OakShortbowU => 66,
            BowType::OakShortbow => 66,
            BowType::OakLongbowU => 100,
            BowType::OakLongbow => 100,
            BowType::WillowShortbowU => 132,
            BowType::WillowShortbow => 132,
            BowType::WillowLongbowU => 166,
            BowType::WillowLongbow => 166,
            BowType::MapleShortbowU => 200,
            BowType::MapleShortbow => 200,
            BowType::MapleLongbowU => 232,
            BowType::MapleLongbow => 232,
            BowType::YewShortbowU => 270,
            BowType::YewShortbow => 270,
            BowType::YewLongbowU => 300,
            BowType::YewLongbow => 300,
            BowType::MagicShortbowU => 332,
            BowType::MagicShortbow => 332,
            BowType::MagicLongbowU => 366,
            BowType::MagicLongbow => 366,
        }
    }

    /// Check if this is an unstrung bow.
    pub fn is_unstrung(&self) -> bool {
        matches!(
            self,
            BowType::ShortbowU
                | BowType::LongbowU
                | BowType::OakShortbowU
                | BowType::OakLongbowU
                | BowType::WillowShortbowU
                | BowType::WillowLongbowU
                | BowType::MapleShortbowU
                | BowType::MapleLongbowU
                | BowType::YewShortbowU
                | BowType::YewLongbowU
                | BowType::MagicShortbowU
                | BowType::MagicLongbowU
        )
    }
}

/// Arrow types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ArrowType {
    BronzeArrows,
    IronArrows,
    SteelArrows,
    MithrilArrows,
    AdamantiteArrows,
    RuneArrows,
}

impl ArrowType {
    /// Get arrow item ID.
    pub fn item_id(&self) -> u32 {
        match self {
            ArrowType::BronzeArrows => 11,
            ArrowType::IronArrows => 190,
            ArrowType::SteelArrows => 191,
            ArrowType::MithrilArrows => 192,
            ArrowType::AdamantiteArrows => 193,
            ArrowType::RuneArrows => 194,
        }
    }

    /// Get arrowhead item ID.
    pub fn arrowhead_id(&self) -> u32 {
        match self {
            ArrowType::BronzeArrows => 876,
            ArrowType::IronArrows => 877,
            ArrowType::SteelArrows => 878,
            ArrowType::MithrilArrows => 879,
            ArrowType::AdamantiteArrows => 880,
            ArrowType::RuneArrows => 881,
        }
    }

    /// Get required fletching level.
    pub fn required_level(&self) -> u8 {
        match self {
            ArrowType::BronzeArrows => 1,
            ArrowType::IronArrows => 15,
            ArrowType::SteelArrows => 30,
            ArrowType::MithrilArrows => 45,
            ArrowType::AdamantiteArrows => 60,
            ArrowType::RuneArrows => 75,
        }
    }

    /// Get fletching experience per arrow.
    pub fn experience(&self) -> u32 {
        match self {
            ArrowType::BronzeArrows => 5,
            ArrowType::IronArrows => 10,
            ArrowType::SteelArrows => 15,
            ArrowType::MithrilArrows => 20,
            ArrowType::AdamantiteArrows => 25,
            ArrowType::RuneArrows => 30,
        }
    }
}

/// Log types for fletching.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FletchingLog {
    Normal,
    Oak,
    Willow,
    Maple,
    Yew,
    Magic,
}

impl FletchingLog {
    /// Get log item ID.
    pub fn log_id(&self) -> u32 {
        match self {
            FletchingLog::Normal => 14,
            FletchingLog::Oak => 632,
            FletchingLog::Willow => 633,
            FletchingLog::Maple => 634,
            FletchingLog::Yew => 635,
            FletchingLog::Magic => 636,
        }
    }

    /// Get arrow shaft experience.
    pub fn shaft_experience(&self) -> u32 {
        match self {
            FletchingLog::Normal => 20,
            FletchingLog::Oak => 30,
            FletchingLog::Willow => 40,
            FletchingLog::Maple => 50,
            FletchingLog::Yew => 60,
            FletchingLog::Magic => 70,
        }
    }

    /// Get number of arrow shafts per log.
    pub fn shafts_per_log(&self) -> u8 {
        15
    }
}

/// Item IDs for fletching materials.
pub const KNIFE_ID: u32 = 13;
pub const ARROW_SHAFTS_ID: u32 = 280;
pub const HEADLESS_ARROWS_ID: u32 = 281;
pub const FEATHER_ID: u32 = 381;
pub const BOW_STRING_ID: u32 = 676;

/// Manager for fletching system.
#[derive(Debug, Default)]
pub struct FletchingManager {
    /// Log to bow mappings.
    log_to_bows: HashMap<u32, Vec<BowType>>,
}

impl FletchingManager {
    /// Create a new fletching manager.
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.load_defaults();
        manager
    }

    /// Load default data.
    pub fn load_defaults(&mut self) {
        // Map logs to bows that can be made
        self.log_to_bows.insert(
            FletchingLog::Normal.log_id(),
            vec![BowType::ShortbowU, BowType::LongbowU],
        );
        self.log_to_bows.insert(
            FletchingLog::Oak.log_id(),
            vec![BowType::OakShortbowU, BowType::OakLongbowU],
        );
        self.log_to_bows.insert(
            FletchingLog::Willow.log_id(),
            vec![BowType::WillowShortbowU, BowType::WillowLongbowU],
        );
        self.log_to_bows.insert(
            FletchingLog::Maple.log_id(),
            vec![BowType::MapleShortbowU, BowType::MapleLongbowU],
        );
        self.log_to_bows.insert(
            FletchingLog::Yew.log_id(),
            vec![BowType::YewShortbowU, BowType::YewLongbowU],
        );
        self.log_to_bows.insert(
            FletchingLog::Magic.log_id(),
            vec![BowType::MagicShortbowU, BowType::MagicLongbowU],
        );

        info!(
            "Loaded fletching data for {} log types",
            self.log_to_bows.len()
        );
    }

    /// Get bows that can be made from a log.
    pub fn get_bows_for_log(&self, log_id: u32) -> Option<&Vec<BowType>> {
        self.log_to_bows.get(&log_id)
    }

    /// Check if player can fletch a bow.
    pub fn can_fletch_bow(&self, fletching_level: u8, bow: BowType) -> bool {
        fletching_level >= bow.required_level()
    }

    /// Check if player can make arrows.
    pub fn can_make_arrows(&self, fletching_level: u8, arrow: ArrowType) -> bool {
        fletching_level >= arrow.required_level()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bow_levels() {
        assert_eq!(BowType::ShortbowU.required_level(), 5);
        assert_eq!(BowType::MagicLongbow.required_level(), 85);
    }

    #[test]
    fn test_arrow_levels() {
        assert_eq!(ArrowType::BronzeArrows.required_level(), 1);
        assert_eq!(ArrowType::RuneArrows.required_level(), 75);
    }

    #[test]
    fn test_fletching_manager() {
        let manager = FletchingManager::new();

        let bows = manager.get_bows_for_log(14);
        assert!(bows.is_some());
        assert_eq!(bows.unwrap().len(), 2);

        assert!(manager.can_fletch_bow(10, BowType::Longbow));
        assert!(!manager.can_fletch_bow(5, BowType::OakShortbow));
    }
}
