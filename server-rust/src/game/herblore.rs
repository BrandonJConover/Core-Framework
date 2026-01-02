//! Herblore skill system.
//! Handles herb identification and potion brewing.

use std::collections::HashMap;
use tracing::info;

/// Herb types (unidentified and identified).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum HerbType {
    Guam,
    Marrentill,
    Tarromin,
    Harralander,
    Ranarr,
    Irit,
    Avantoe,
    Kwuarm,
    Cadantine,
    DwarfWeed,
    Torstol,
}

impl HerbType {
    /// Get unidentified herb item ID.
    pub fn unid_id(&self) -> u32 {
        match self {
            HerbType::Guam => 165,
            HerbType::Marrentill => 435,
            HerbType::Tarromin => 436,
            HerbType::Harralander => 437,
            HerbType::Ranarr => 438,
            HerbType::Irit => 439,
            HerbType::Avantoe => 440,
            HerbType::Kwuarm => 441,
            HerbType::Cadantine => 442,
            HerbType::DwarfWeed => 443,
            HerbType::Torstol => 444,
        }
    }

    /// Get identified herb item ID.
    pub fn id_id(&self) -> u32 {
        match self {
            HerbType::Guam => 454,
            HerbType::Marrentill => 455,
            HerbType::Tarromin => 456,
            HerbType::Harralander => 457,
            HerbType::Ranarr => 458,
            HerbType::Irit => 459,
            HerbType::Avantoe => 460,
            HerbType::Kwuarm => 461,
            HerbType::Cadantine => 462,
            HerbType::DwarfWeed => 463,
            HerbType::Torstol => 464,
        }
    }

    /// Get required herblore level to identify.
    pub fn identify_level(&self) -> u8 {
        match self {
            HerbType::Guam => 3,
            HerbType::Marrentill => 5,
            HerbType::Tarromin => 11,
            HerbType::Harralander => 20,
            HerbType::Ranarr => 25,
            HerbType::Irit => 40,
            HerbType::Avantoe => 48,
            HerbType::Kwuarm => 54,
            HerbType::Cadantine => 65,
            HerbType::DwarfWeed => 70,
            HerbType::Torstol => 75,
        }
    }

    /// Get experience for identifying.
    pub fn identify_experience(&self) -> u32 {
        match self {
            HerbType::Guam => 10,
            HerbType::Marrentill => 13,
            HerbType::Tarromin => 16,
            HerbType::Harralander => 21,
            HerbType::Ranarr => 26,
            HerbType::Irit => 34,
            HerbType::Avantoe => 40,
            HerbType::Kwuarm => 46,
            HerbType::Cadantine => 54,
            HerbType::DwarfWeed => 60,
            HerbType::Torstol => 66,
        }
    }
}

/// Potion types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PotionType {
    AttackPotion,
    CurePoison,
    StrengthPotion,
    StatRestorePotion,
    DefensePotion,
    PrayerPotion,
    SuperAttackPotion,
    PoisonAntidote,
    FishingPotion,
    SuperStrengthPotion,
    SuperDefensePotion,
    RangingPotion,
    MagicPotion,
    ZamorakPotion,
}

impl PotionType {
    /// Get potion item ID (3 dose).
    pub fn item_id(&self) -> u32 {
        match self {
            PotionType::AttackPotion => 474,
            PotionType::CurePoison => 475,
            PotionType::StrengthPotion => 476,
            PotionType::StatRestorePotion => 477,
            PotionType::DefensePotion => 478,
            PotionType::PrayerPotion => 479,
            PotionType::SuperAttackPotion => 480,
            PotionType::PoisonAntidote => 481,
            PotionType::FishingPotion => 482,
            PotionType::SuperStrengthPotion => 483,
            PotionType::SuperDefensePotion => 484,
            PotionType::RangingPotion => 485,
            PotionType::MagicPotion => 486,
            PotionType::ZamorakPotion => 487,
        }
    }

    /// Get unfinished potion item ID.
    pub fn unfinished_id(&self) -> u32 {
        match self {
            PotionType::AttackPotion => 454,
            PotionType::CurePoison => 455,
            PotionType::StrengthPotion => 456,
            PotionType::StatRestorePotion => 457,
            PotionType::DefensePotion => 458,
            PotionType::PrayerPotion => 458, // Ranarr based
            PotionType::SuperAttackPotion => 459,
            PotionType::PoisonAntidote => 459, // Irit based
            PotionType::FishingPotion => 460,
            PotionType::SuperStrengthPotion => 461,
            PotionType::SuperDefensePotion => 462,
            PotionType::RangingPotion => 463,
            PotionType::MagicPotion => 464,
            PotionType::ZamorakPotion => 464, // Torstol based
        }
    }

    /// Get required herb.
    pub fn required_herb(&self) -> HerbType {
        match self {
            PotionType::AttackPotion => HerbType::Guam,
            PotionType::CurePoison => HerbType::Marrentill,
            PotionType::StrengthPotion => HerbType::Tarromin,
            PotionType::StatRestorePotion => HerbType::Harralander,
            PotionType::DefensePotion => HerbType::Ranarr,
            PotionType::PrayerPotion => HerbType::Ranarr,
            PotionType::SuperAttackPotion => HerbType::Irit,
            PotionType::PoisonAntidote => HerbType::Irit,
            PotionType::FishingPotion => HerbType::Avantoe,
            PotionType::SuperStrengthPotion => HerbType::Kwuarm,
            PotionType::SuperDefensePotion => HerbType::Cadantine,
            PotionType::RangingPotion => HerbType::DwarfWeed,
            PotionType::MagicPotion => HerbType::Torstol,
            PotionType::ZamorakPotion => HerbType::Torstol,
        }
    }

    /// Get required herblore level.
    pub fn required_level(&self) -> u8 {
        match self {
            PotionType::AttackPotion => 3,
            PotionType::CurePoison => 5,
            PotionType::StrengthPotion => 12,
            PotionType::StatRestorePotion => 22,
            PotionType::DefensePotion => 30,
            PotionType::PrayerPotion => 38,
            PotionType::SuperAttackPotion => 45,
            PotionType::PoisonAntidote => 48,
            PotionType::FishingPotion => 50,
            PotionType::SuperStrengthPotion => 55,
            PotionType::SuperDefensePotion => 66,
            PotionType::RangingPotion => 72,
            PotionType::MagicPotion => 76,
            PotionType::ZamorakPotion => 78,
        }
    }

    /// Get brewing experience.
    pub fn experience(&self) -> u32 {
        match self {
            PotionType::AttackPotion => 100,
            PotionType::CurePoison => 100,
            PotionType::StrengthPotion => 120,
            PotionType::StatRestorePotion => 150,
            PotionType::DefensePotion => 150,
            PotionType::PrayerPotion => 175,
            PotionType::SuperAttackPotion => 200,
            PotionType::PoisonAntidote => 200,
            PotionType::FishingPotion => 225,
            PotionType::SuperStrengthPotion => 250,
            PotionType::SuperDefensePotion => 275,
            PotionType::RangingPotion => 300,
            PotionType::MagicPotion => 325,
            PotionType::ZamorakPotion => 350,
        }
    }
}

/// Secondary ingredients.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SecondaryIngredient {
    EyeOfNewt,
    GroundUnicornHorn,
    LimpwurtRoot,
    RedSpidersEggs,
    WhiteBerries,
    SnapeGrass,
    GroundBlueDragonScale,
    WineBerries,
    JangerberryJuice,
    GroundGoatHorn,
}

impl SecondaryIngredient {
    /// Get item ID.
    pub fn item_id(&self) -> u32 {
        match self {
            SecondaryIngredient::EyeOfNewt => 270,
            SecondaryIngredient::GroundUnicornHorn => 473,
            SecondaryIngredient::LimpwurtRoot => 220,
            SecondaryIngredient::RedSpidersEggs => 219,
            SecondaryIngredient::WhiteBerries => 471,
            SecondaryIngredient::SnapeGrass => 469,
            SecondaryIngredient::GroundBlueDragonScale => 472,
            SecondaryIngredient::WineBerries => 501,
            SecondaryIngredient::JangerberryJuice => 502,
            SecondaryIngredient::GroundGoatHorn => 503,
        }
    }
}

/// Item IDs for herblore.
pub const VIAL_ID: u32 = 465;
pub const VIAL_OF_WATER_ID: u32 = 466;
pub const PESTLE_MORTAR_ID: u32 = 468;

/// Manager for herblore system.
#[derive(Debug, Default)]
pub struct HerbloreManager {
    /// Unidentified herb to herb type mappings.
    unid_herbs: HashMap<u32, HerbType>,
    /// Potion recipes.
    recipes: HashMap<(HerbType, u32), PotionType>,
}

impl HerbloreManager {
    /// Create a new herblore manager.
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.load_defaults();
        manager
    }

    /// Load default data.
    pub fn load_defaults(&mut self) {
        // Map unidentified herbs
        for herb in [
            HerbType::Guam,
            HerbType::Marrentill,
            HerbType::Tarromin,
            HerbType::Harralander,
            HerbType::Ranarr,
            HerbType::Irit,
            HerbType::Avantoe,
            HerbType::Kwuarm,
            HerbType::Cadantine,
            HerbType::DwarfWeed,
            HerbType::Torstol,
        ] {
            self.unid_herbs.insert(herb.unid_id(), herb);
        }

        // Map potion recipes (herb + secondary ingredient)
        self.recipes.insert(
            (HerbType::Guam, SecondaryIngredient::EyeOfNewt.item_id()),
            PotionType::AttackPotion,
        );
        self.recipes.insert(
            (
                HerbType::Marrentill,
                SecondaryIngredient::GroundUnicornHorn.item_id(),
            ),
            PotionType::CurePoison,
        );
        self.recipes.insert(
            (
                HerbType::Tarromin,
                SecondaryIngredient::LimpwurtRoot.item_id(),
            ),
            PotionType::StrengthPotion,
        );
        self.recipes.insert(
            (
                HerbType::Harralander,
                SecondaryIngredient::RedSpidersEggs.item_id(),
            ),
            PotionType::StatRestorePotion,
        );
        self.recipes.insert(
            (
                HerbType::Ranarr,
                SecondaryIngredient::WhiteBerries.item_id(),
            ),
            PotionType::DefensePotion,
        );
        self.recipes.insert(
            (HerbType::Ranarr, SecondaryIngredient::SnapeGrass.item_id()),
            PotionType::PrayerPotion,
        );
        self.recipes.insert(
            (HerbType::Irit, SecondaryIngredient::EyeOfNewt.item_id()),
            PotionType::SuperAttackPotion,
        );
        self.recipes.insert(
            (
                HerbType::Kwuarm,
                SecondaryIngredient::LimpwurtRoot.item_id(),
            ),
            PotionType::SuperStrengthPotion,
        );
        self.recipes.insert(
            (
                HerbType::Cadantine,
                SecondaryIngredient::WhiteBerries.item_id(),
            ),
            PotionType::SuperDefensePotion,
        );
        self.recipes.insert(
            (
                HerbType::DwarfWeed,
                SecondaryIngredient::WineBerries.item_id(),
            ),
            PotionType::RangingPotion,
        );
        self.recipes.insert(
            (
                HerbType::Torstol,
                SecondaryIngredient::JangerberryJuice.item_id(),
            ),
            PotionType::ZamorakPotion,
        );

        info!(
            "Loaded {} herb types and {} potion recipes",
            self.unid_herbs.len(),
            self.recipes.len()
        );
    }

    /// Get herb type from unidentified herb ID.
    pub fn get_herb(&self, unid_id: u32) -> Option<HerbType> {
        self.unid_herbs.get(&unid_id).copied()
    }

    /// Get potion recipe.
    pub fn get_recipe(&self, herb: HerbType, secondary_id: u32) -> Option<PotionType> {
        self.recipes.get(&(herb, secondary_id)).copied()
    }

    /// Check if player can identify herb.
    pub fn can_identify(&self, herblore_level: u8, herb: HerbType) -> bool {
        herblore_level >= herb.identify_level()
    }

    /// Check if player can brew potion.
    pub fn can_brew(&self, herblore_level: u8, potion: PotionType) -> bool {
        herblore_level >= potion.required_level()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_herb_levels() {
        assert_eq!(HerbType::Guam.identify_level(), 3);
        assert_eq!(HerbType::Torstol.identify_level(), 75);
    }

    #[test]
    fn test_potion_levels() {
        assert_eq!(PotionType::AttackPotion.required_level(), 3);
        assert_eq!(PotionType::ZamorakPotion.required_level(), 78);
    }

    #[test]
    fn test_herblore_manager() {
        let manager = HerbloreManager::new();

        assert_eq!(manager.get_herb(165), Some(HerbType::Guam));
        assert!(manager.can_identify(5, HerbType::Guam));
        assert!(!manager.can_identify(2, HerbType::Guam));

        let recipe = manager.get_recipe(HerbType::Guam, SecondaryIngredient::EyeOfNewt.item_id());
        assert_eq!(recipe, Some(PotionType::AttackPotion));
    }
}
