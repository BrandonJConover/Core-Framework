//! Ranged combat and projectile system.
//! Handles bows, crossbows, throwing weapons, and projectile calculations.

use std::collections::HashMap;
use tracing::{debug, info};

use super::entity::{EntityId, Position};

/// Ranged weapon types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RangedWeaponType {
    /// Standard bows (shortbow, longbow, etc.).
    Bow,
    /// Crossbows.
    Crossbow,
    /// Throwing knives.
    ThrowingKnife,
    /// Throwing darts.
    ThrowingDart,
    /// Throwing spears.
    ThrowingSpear,
}

/// Ammunition types for ranged weapons.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AmmoType {
    BronzeArrows,
    IronArrows,
    SteelArrows,
    MithrilArrows,
    AdamantiteArrows,
    RuneArrows,
    DragonArrows,
    CrossbowBolts,
    DragonBolts,
    OysterPearlBolts,
}

impl AmmoType {
    /// Get the power value for this ammunition.
    pub fn power(&self) -> u32 {
        match self {
            AmmoType::BronzeArrows => 15,
            AmmoType::IronArrows => 20,
            AmmoType::SteelArrows => 25,
            AmmoType::MithrilArrows => 30,
            AmmoType::AdamantiteArrows => 35,
            AmmoType::RuneArrows => 40,
            AmmoType::DragonArrows => 50,
            AmmoType::CrossbowBolts => 20,
            AmmoType::DragonBolts => 50,
            AmmoType::OysterPearlBolts => 30,
        }
    }

    /// Check if this ammo can be poisoned.
    pub fn can_poison(&self) -> bool {
        true // All arrow types can be poisoned in RSC
    }
}

/// Throwing weapon definition.
#[derive(Debug, Clone)]
pub struct ThrowingWeapon {
    /// Item ID.
    pub id: u32,
    /// Weapon type.
    pub weapon_type: RangedWeaponType,
    /// Aim bonus.
    pub aim: u32,
    /// Power bonus.
    pub power: u32,
    /// Whether this can be poisoned.
    pub poisonable: bool,
}

impl ThrowingWeapon {
    /// Create a new throwing knife.
    pub fn knife(id: u32, aim: u32, power: u32) -> Self {
        Self {
            id,
            weapon_type: RangedWeaponType::ThrowingKnife,
            aim,
            power,
            poisonable: true,
        }
    }

    /// Create a new throwing dart.
    pub fn dart(id: u32, aim: u32, power: u32) -> Self {
        Self {
            id,
            weapon_type: RangedWeaponType::ThrowingDart,
            aim,
            power,
            poisonable: true,
        }
    }

    /// Create a new throwing spear.
    pub fn spear(id: u32, aim: u32, power: u32) -> Self {
        Self {
            id,
            weapon_type: RangedWeaponType::ThrowingSpear,
            aim,
            power,
            poisonable: true,
        }
    }
}

/// Bow definition.
#[derive(Debug, Clone)]
pub struct Bow {
    /// Item ID.
    pub id: u32,
    /// Bow name.
    pub name: String,
    /// Aim bonus.
    pub aim: u32,
    /// Required ranged level.
    pub required_level: u8,
    /// Compatible ammo types.
    pub compatible_ammo: Vec<AmmoType>,
}

impl Bow {
    /// Create a new bow.
    pub fn new(id: u32, name: &str, aim: u32, required_level: u8) -> Self {
        Self {
            id,
            name: name.to_string(),
            aim,
            required_level,
            compatible_ammo: vec![
                AmmoType::BronzeArrows,
                AmmoType::IronArrows,
                AmmoType::SteelArrows,
                AmmoType::MithrilArrows,
                AmmoType::AdamantiteArrows,
                AmmoType::RuneArrows,
            ],
        }
    }

    /// Create a crossbow.
    pub fn crossbow(id: u32, name: &str, aim: u32, required_level: u8) -> Self {
        Self {
            id,
            name: name.to_string(),
            aim,
            required_level,
            compatible_ammo: vec![AmmoType::CrossbowBolts, AmmoType::OysterPearlBolts],
        }
    }
}

/// Result of a ranged attack calculation.
#[derive(Debug, Clone)]
pub struct RangedAttackResult {
    /// Whether the attack hit.
    pub hit: bool,
    /// Damage dealt (0 if missed).
    pub damage: u32,
    /// Whether the projectile was recovered.
    pub projectile_recovered: bool,
    /// Whether poison was applied.
    pub poison_applied: bool,
}

/// Calculate ranged accuracy.
pub fn calculate_ranged_accuracy(
    ranged_level: u32,
    weapon_aim: u32,
    target_defense: u32,
    target_armour: u32,
) -> f64 {
    let bonus_constant = 8;
    let accuracy = (ranged_level + bonus_constant) as f64 * (weapon_aim + 1 + 64) as f64;
    let defense = (target_defense + bonus_constant) as f64 * (target_armour + 64) as f64;

    if accuracy > defense {
        1.0 - ((defense + 2.0) / (2.0 * (accuracy + 1.0)))
    } else {
        accuracy / (2.0 * (defense + 1.0))
    }
}

/// Calculate ranged max hit.
pub fn calculate_ranged_max_hit(ranged_level: u32, ammo_power: u32) -> u32 {
    let bonus_constant = 8;
    let max_roll = (ranged_level + bonus_constant) * (ammo_power + 1 + 64);
    (max_roll + 320) / 640
}

/// Determine if a projectile is recovered after use.
pub fn projectile_recovered(damage: u32) -> bool {
    // Projectiles are less likely to be recovered if they deal damage
    if damage == 0 {
        rand::random::<f64>() < 0.8 // 80% recovery on miss
    } else {
        rand::random::<f64>() < 0.5 // 50% recovery on hit
    }
}

/// Manager for ranged combat.
#[derive(Debug, Default)]
pub struct RangedManager {
    /// Registered bows.
    bows: HashMap<u32, Bow>,
    /// Registered throwing weapons.
    throwing_weapons: HashMap<u32, ThrowingWeapon>,
    /// Active projectiles in flight.
    active_projectiles: Vec<Projectile>,
}

/// A projectile in flight.
#[derive(Debug, Clone)]
pub struct Projectile {
    /// Source entity.
    pub source: EntityId,
    /// Target entity.
    pub target: EntityId,
    /// Damage to deal.
    pub damage: u32,
    /// Tick when projectile lands.
    pub land_tick: u64,
    /// Ammo type (for recovery).
    pub ammo_id: Option<u32>,
    /// Whether poisoned.
    pub poisoned: bool,
}

impl RangedManager {
    /// Create a new ranged manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a bow.
    pub fn register_bow(&mut self, bow: Bow) {
        self.bows.insert(bow.id, bow);
    }

    /// Register a throwing weapon.
    pub fn register_throwing(&mut self, weapon: ThrowingWeapon) {
        self.throwing_weapons.insert(weapon.id, weapon);
    }

    /// Get a bow by ID.
    pub fn get_bow(&self, id: u32) -> Option<&Bow> {
        self.bows.get(&id)
    }

    /// Get a throwing weapon by ID.
    pub fn get_throwing(&self, id: u32) -> Option<&ThrowingWeapon> {
        self.throwing_weapons.get(&id)
    }

    /// Add a projectile in flight.
    pub fn add_projectile(&mut self, projectile: Projectile) {
        self.active_projectiles.push(projectile);
    }

    /// Process projectiles for a tick.
    pub fn tick(&mut self, current_tick: u64) -> Vec<Projectile> {
        let (landing, still_flying): (Vec<_>, Vec<_>) = self
            .active_projectiles
            .drain(..)
            .partition(|p| p.land_tick <= current_tick);

        self.active_projectiles = still_flying;
        landing
    }

    /// Check if target is within range.
    pub fn in_range(source: Position, target: Position, weapon_type: RangedWeaponType) -> bool {
        let dx = (source.x as i32 - target.x as i32).abs();
        let dy = (source.y as i32 - target.y as i32).abs();
        let distance = dx.max(dy) as u32;

        let range = match weapon_type {
            RangedWeaponType::Bow => 5,
            RangedWeaponType::Crossbow => 5,
            RangedWeaponType::ThrowingKnife => 4,
            RangedWeaponType::ThrowingDart => 4,
            RangedWeaponType::ThrowingSpear => 3,
        };

        distance <= range
    }

    /// Load default weapons.
    pub fn load_defaults(&mut self) {
        // Bows
        self.register_bow(Bow::new(188, "Shortbow", 10, 1));
        self.register_bow(Bow::new(189, "Longbow", 15, 1));
        self.register_bow(Bow::new(648, "Oak Shortbow", 15, 5));
        self.register_bow(Bow::new(649, "Oak Longbow", 20, 10));
        self.register_bow(Bow::new(650, "Willow Shortbow", 20, 20));
        self.register_bow(Bow::new(651, "Willow Longbow", 25, 25));
        self.register_bow(Bow::new(652, "Maple Shortbow", 25, 30));
        self.register_bow(Bow::new(653, "Maple Longbow", 30, 35));
        self.register_bow(Bow::new(654, "Yew Shortbow", 30, 40));
        self.register_bow(Bow::new(655, "Yew Longbow", 35, 45));
        self.register_bow(Bow::new(656, "Magic Shortbow", 35, 50));
        self.register_bow(Bow::new(657, "Magic Longbow", 40, 55));

        // Crossbows
        self.register_bow(Bow::crossbow(59, "Crossbow", 12, 1));
        self.register_bow(Bow::crossbow(60, "Phoenix Crossbow", 12, 1));

        // Throwing knives
        self.register_throwing(ThrowingWeapon::knife(831, 25, 25)); // Bronze
        self.register_throwing(ThrowingWeapon::knife(832, 30, 30)); // Iron
        self.register_throwing(ThrowingWeapon::knife(833, 35, 35)); // Steel
        self.register_throwing(ThrowingWeapon::knife(834, 35, 35)); // Black
        self.register_throwing(ThrowingWeapon::knife(835, 40, 40)); // Mithril
        self.register_throwing(ThrowingWeapon::knife(836, 45, 45)); // Adamantite
        self.register_throwing(ThrowingWeapon::knife(837, 55, 50)); // Rune

        // Throwing darts
        self.register_throwing(ThrowingWeapon::dart(1013, 25, 15)); // Bronze
        self.register_throwing(ThrowingWeapon::dart(1014, 27, 17)); // Iron
        self.register_throwing(ThrowingWeapon::dart(1015, 30, 22)); // Steel
        self.register_throwing(ThrowingWeapon::dart(1016, 35, 25)); // Mithril
        self.register_throwing(ThrowingWeapon::dart(1017, 40, 27)); // Adamantite
        self.register_throwing(ThrowingWeapon::dart(1018, 45, 30)); // Rune

        // Throwing spears
        self.register_throwing(ThrowingWeapon::spear(1088, 25, 29)); // Bronze
        self.register_throwing(ThrowingWeapon::spear(1089, 33, 37)); // Iron
        self.register_throwing(ThrowingWeapon::spear(1090, 41, 46)); // Steel
        self.register_throwing(ThrowingWeapon::spear(1091, 49, 53)); // Mithril
        self.register_throwing(ThrowingWeapon::spear(1092, 57, 61)); // Adamantite
        self.register_throwing(ThrowingWeapon::spear(1093, 65, 69)); // Rune

        info!(
            "Loaded {} bows and {} throwing weapons",
            self.bows.len(),
            self.throwing_weapons.len()
        );
    }
}

/// Calculate experience for a ranged hit.
pub fn ranged_hit_experience(damage: u32, is_player_target: bool) -> u32 {
    if is_player_target || damage > 0 {
        // 4 XP per damage point
        damage * 4
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ranged_accuracy() {
        // High level with good weapon vs low defense
        let accuracy = calculate_ranged_accuracy(70, 40, 30, 50);
        assert!(accuracy > 0.5);

        // Low level with poor weapon vs high defense
        let accuracy2 = calculate_ranged_accuracy(20, 10, 60, 100);
        assert!(accuracy2 < 0.5);
    }

    #[test]
    fn test_ranged_max_hit() {
        // Level 1 with bronze arrows
        let max = calculate_ranged_max_hit(1, 15);
        assert!(max > 0);

        // Level 99 with dragon arrows
        let max2 = calculate_ranged_max_hit(99, 50);
        assert!(max2 > max);
    }

    #[test]
    fn test_range_check() {
        let source = Position { x: 100, y: 100, plane: 0 };
        let in_range = Position { x: 103, y: 100, plane: 0 };
        let out_of_range = Position { x: 110, y: 100, plane: 0 };

        assert!(RangedManager::in_range(source, in_range, RangedWeaponType::Bow));
        assert!(!RangedManager::in_range(source, out_of_range, RangedWeaponType::Bow));
    }

    #[test]
    fn test_ammo_power() {
        assert!(AmmoType::DragonArrows.power() > AmmoType::BronzeArrows.power());
        assert!(AmmoType::RuneArrows.power() > AmmoType::SteelArrows.power());
    }
}
