//! Runecrafting skill system.
//! Handles rune essence, altars, and rune creation.

use std::collections::HashMap;
use tracing::info;

use super::entity::Position;

/// Types of runes that can be crafted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RuneType {
    Air,
    Mind,
    Water,
    Earth,
    Fire,
    Body,
    Cosmic,
    Chaos,
    Nature,
    Law,
    Death,
    Blood,
}

impl RuneType {
    /// Get the item ID for this rune.
    pub fn item_id(&self) -> u32 {
        match self {
            RuneType::Air => 33,
            RuneType::Mind => 35,
            RuneType::Water => 32,
            RuneType::Earth => 34,
            RuneType::Fire => 31,
            RuneType::Body => 36,
            RuneType::Cosmic => 46,
            RuneType::Chaos => 41,
            RuneType::Nature => 40,
            RuneType::Law => 42,
            RuneType::Death => 38,
            RuneType::Blood => 619,
        }
    }

    /// Get required runecrafting level.
    pub fn required_level(&self) -> u8 {
        match self {
            RuneType::Air => 1,
            RuneType::Mind => 2,
            RuneType::Water => 5,
            RuneType::Earth => 9,
            RuneType::Fire => 14,
            RuneType::Body => 20,
            RuneType::Cosmic => 27,
            RuneType::Chaos => 35,
            RuneType::Nature => 44,
            RuneType::Law => 54,
            RuneType::Death => 65,
            RuneType::Blood => 77,
        }
    }

    /// Get runecrafting experience per essence.
    pub fn experience(&self) -> f64 {
        match self {
            RuneType::Air => 5.0,
            RuneType::Mind => 5.5,
            RuneType::Water => 6.0,
            RuneType::Earth => 6.5,
            RuneType::Fire => 7.0,
            RuneType::Body => 7.5,
            RuneType::Cosmic => 8.0,
            RuneType::Chaos => 8.5,
            RuneType::Nature => 9.0,
            RuneType::Law => 9.5,
            RuneType::Death => 10.0,
            RuneType::Blood => 10.5,
        }
    }

    /// Get the level at which players craft multiple runes per essence.
    pub fn multiple_rune_levels(&self) -> Vec<(u8, u8)> {
        // Returns (level, multiplier) pairs
        match self {
            RuneType::Air => vec![
                (1, 1),
                (11, 2),
                (22, 3),
                (33, 4),
                (44, 5),
                (55, 6),
                (66, 7),
                (77, 8),
                (88, 9),
                (99, 10),
            ],
            RuneType::Mind => vec![
                (2, 1),
                (14, 2),
                (28, 3),
                (42, 4),
                (56, 5),
                (70, 6),
                (84, 7),
                (98, 8),
            ],
            RuneType::Water => vec![(5, 1), (19, 2), (38, 3), (57, 4), (76, 5), (95, 6)],
            RuneType::Earth => vec![(9, 1), (26, 2), (52, 3), (78, 4)],
            RuneType::Fire => vec![(14, 1), (35, 2), (70, 3)],
            RuneType::Body => vec![(20, 1), (46, 2), (92, 3)],
            RuneType::Cosmic => vec![(27, 1), (59, 2)],
            RuneType::Chaos => vec![(35, 1), (74, 2)],
            RuneType::Nature => vec![(44, 1), (91, 2)],
            RuneType::Law => vec![(54, 1)],
            RuneType::Death => vec![(65, 1)],
            RuneType::Blood => vec![(77, 1)],
        }
    }
}

/// Rune essence types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EssenceType {
    /// Regular rune essence.
    RuneEssence,
    /// Pure essence (can craft higher level runes).
    PureEssence,
}

impl EssenceType {
    /// Get item ID.
    pub fn item_id(&self) -> u32 {
        match self {
            EssenceType::RuneEssence => 1436,
            EssenceType::PureEssence => 7936,
        }
    }

    /// Check if this essence can craft a rune type.
    pub fn can_craft(&self, rune: RuneType) -> bool {
        match self {
            EssenceType::RuneEssence => matches!(
                rune,
                RuneType::Air
                    | RuneType::Mind
                    | RuneType::Water
                    | RuneType::Earth
                    | RuneType::Fire
                    | RuneType::Body
            ),
            EssenceType::PureEssence => true,
        }
    }
}

/// Altar definitions.
#[derive(Debug, Clone)]
pub struct Altar {
    /// Object ID of the altar.
    pub object_id: u32,
    /// Position of the altar.
    pub position: Position,
    /// Rune type this altar creates.
    pub rune_type: RuneType,
    /// Talisman item ID required for entry.
    pub talisman_id: u32,
    /// Tiara item ID for easy entry.
    pub tiara_id: u32,
}

impl Altar {
    /// Create a new altar.
    pub fn new(
        object_id: u32,
        position: Position,
        rune_type: RuneType,
        talisman_id: u32,
        tiara_id: u32,
    ) -> Self {
        Self {
            object_id,
            position,
            rune_type,
            talisman_id,
            tiara_id,
        }
    }
}

/// Mysterious ruins (altar entrances).
#[derive(Debug, Clone)]
pub struct MysteriousRuins {
    /// Object ID of the ruins.
    pub object_id: u32,
    /// Position of the ruins.
    pub position: Position,
    /// Rune type of the connected altar.
    pub rune_type: RuneType,
    /// Position player is teleported to.
    pub destination: Position,
}

impl MysteriousRuins {
    /// Create new mysterious ruins.
    pub fn new(
        object_id: u32,
        position: Position,
        rune_type: RuneType,
        destination: Position,
    ) -> Self {
        Self {
            object_id,
            position,
            rune_type,
            destination,
        }
    }
}

/// Talisman definitions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Talisman {
    Air,
    Mind,
    Water,
    Earth,
    Fire,
    Body,
    Cosmic,
    Chaos,
    Nature,
    Law,
    Death,
    Blood,
}

impl Talisman {
    /// Get item ID.
    pub fn item_id(&self) -> u32 {
        match self {
            Talisman::Air => 1438,
            Talisman::Mind => 1448,
            Talisman::Water => 1444,
            Talisman::Earth => 1440,
            Talisman::Fire => 1442,
            Talisman::Body => 1446,
            Talisman::Cosmic => 1454,
            Talisman::Chaos => 1452,
            Talisman::Nature => 1462,
            Talisman::Law => 1458,
            Talisman::Death => 1456,
            Talisman::Blood => 1450,
        }
    }

    /// Get corresponding rune type.
    pub fn rune_type(&self) -> RuneType {
        match self {
            Talisman::Air => RuneType::Air,
            Talisman::Mind => RuneType::Mind,
            Talisman::Water => RuneType::Water,
            Talisman::Earth => RuneType::Earth,
            Talisman::Fire => RuneType::Fire,
            Talisman::Body => RuneType::Body,
            Talisman::Cosmic => RuneType::Cosmic,
            Talisman::Chaos => RuneType::Chaos,
            Talisman::Nature => RuneType::Nature,
            Talisman::Law => RuneType::Law,
            Talisman::Death => RuneType::Death,
            Talisman::Blood => RuneType::Blood,
        }
    }
}

/// Calculate runes crafted per essence.
pub fn calculate_rune_count(runecrafting_level: u8, rune_type: RuneType) -> u8 {
    let levels = rune_type.multiple_rune_levels();
    let mut multiplier = 1u8;

    for (level, mult) in levels {
        if runecrafting_level >= level {
            multiplier = mult;
        } else {
            break;
        }
    }

    multiplier
}

/// Manager for runecrafting system.
#[derive(Debug, Default)]
pub struct RunecraftingManager {
    /// Altars by object ID.
    altars: HashMap<u32, Altar>,
    /// Mysterious ruins by object ID.
    ruins: HashMap<u32, MysteriousRuins>,
    /// Talisman to rune type mapping.
    talisman_map: HashMap<u32, RuneType>,
}

impl RunecraftingManager {
    /// Create a new runecrafting manager.
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.load_defaults();
        manager
    }

    /// Load default data.
    pub fn load_defaults(&mut self) {
        // Map talismans to rune types
        self.talisman_map.insert(1438, RuneType::Air);
        self.talisman_map.insert(1448, RuneType::Mind);
        self.talisman_map.insert(1444, RuneType::Water);
        self.talisman_map.insert(1440, RuneType::Earth);
        self.talisman_map.insert(1442, RuneType::Fire);
        self.talisman_map.insert(1446, RuneType::Body);
        self.talisman_map.insert(1454, RuneType::Cosmic);
        self.talisman_map.insert(1452, RuneType::Chaos);
        self.talisman_map.insert(1462, RuneType::Nature);
        self.talisman_map.insert(1458, RuneType::Law);
        self.talisman_map.insert(1456, RuneType::Death);
        self.talisman_map.insert(1450, RuneType::Blood);

        info!("Loaded {} talisman mappings", self.talisman_map.len());
    }

    /// Register an altar.
    pub fn register_altar(&mut self, altar: Altar) {
        self.altars.insert(altar.object_id, altar);
    }

    /// Register mysterious ruins.
    pub fn register_ruins(&mut self, ruins: MysteriousRuins) {
        self.ruins.insert(ruins.object_id, ruins);
    }

    /// Get altar by object ID.
    pub fn get_altar(&self, object_id: u32) -> Option<&Altar> {
        self.altars.get(&object_id)
    }

    /// Get ruins by object ID.
    pub fn get_ruins(&self, object_id: u32) -> Option<&MysteriousRuins> {
        self.ruins.get(&object_id)
    }

    /// Check if item is a talisman.
    pub fn is_talisman(&self, item_id: u32) -> bool {
        self.talisman_map.contains_key(&item_id)
    }

    /// Get rune type for talisman.
    pub fn talisman_rune_type(&self, item_id: u32) -> Option<RuneType> {
        self.talisman_map.get(&item_id).copied()
    }

    /// Check if player can craft rune.
    pub fn can_craft(&self, runecrafting_level: u8, rune_type: RuneType) -> bool {
        runecrafting_level >= rune_type.required_level()
    }

    /// Calculate experience for crafting runes.
    pub fn calculate_experience(&self, essence_count: u32, rune_type: RuneType) -> u32 {
        (essence_count as f64 * rune_type.experience()) as u32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rune_levels() {
        assert_eq!(RuneType::Air.required_level(), 1);
        assert_eq!(RuneType::Nature.required_level(), 44);
        assert_eq!(RuneType::Blood.required_level(), 77);
    }

    #[test]
    fn test_multiple_runes() {
        // Level 1 air = 1x
        assert_eq!(calculate_rune_count(1, RuneType::Air), 1);
        // Level 11 air = 2x
        assert_eq!(calculate_rune_count(11, RuneType::Air), 2);
        // Level 99 air = 10x
        assert_eq!(calculate_rune_count(99, RuneType::Air), 10);
    }

    #[test]
    fn test_essence_types() {
        assert!(EssenceType::RuneEssence.can_craft(RuneType::Air));
        assert!(EssenceType::RuneEssence.can_craft(RuneType::Body));
        assert!(!EssenceType::RuneEssence.can_craft(RuneType::Cosmic));
        assert!(EssenceType::PureEssence.can_craft(RuneType::Cosmic));
        assert!(EssenceType::PureEssence.can_craft(RuneType::Blood));
    }

    #[test]
    fn test_runecrafting_manager() {
        let manager = RunecraftingManager::new();
        assert!(manager.is_talisman(1438)); // Air talisman
        assert_eq!(manager.talisman_rune_type(1438), Some(RuneType::Air));
        assert!(manager.can_craft(1, RuneType::Air));
        assert!(!manager.can_craft(1, RuneType::Nature));
    }
}
