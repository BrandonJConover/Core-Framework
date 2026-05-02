//! Combat module for combat mechanics.

use super::player::{Player, SkillId};
use rand::Rng;

/// Combat style enumeration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CombatStyle {
    Controlled,  // Balanced XP
    Aggressive,  // Strength focused
    Accurate,    // Attack focused
    Defensive,   // Defense focused
}

impl CombatStyle {
    /// Get attack bonus for this style.
    pub fn attack_bonus(&self) -> i32 {
        match self {
            CombatStyle::Accurate => 3,
            CombatStyle::Controlled => 1,
            _ => 0,
        }
    }

    /// Get strength bonus for this style.
    pub fn strength_bonus(&self) -> i32 {
        match self {
            CombatStyle::Aggressive => 3,
            CombatStyle::Controlled => 1,
            _ => 0,
        }
    }

    /// Get defense bonus for this style.
    pub fn defense_bonus(&self) -> i32 {
        match self {
            CombatStyle::Defensive => 3,
            CombatStyle::Controlled => 1,
            _ => 0,
        }
    }
}

/// Combat calculator for damage and accuracy.
pub struct CombatCalculator;

impl CombatCalculator {
    /// Calculate max hit for a player.
    pub fn calculate_max_hit(player: &Player, style: CombatStyle) -> u32 {
        let strength_level = player.skills.current_level(SkillId::Strength) as i32;
        let style_bonus = style.strength_bonus();
        let equipment_bonus = 0; // Would come from equipment stats

        // RSC max hit formula
        let effective_strength = strength_level + style_bonus;
        let max_hit = ((effective_strength + equipment_bonus) as f64 * 0.14 + 1.05) as u32;

        max_hit.max(1)
    }

    /// Calculate hit chance (0.0 to 1.0).
    pub fn calculate_hit_chance(
        attacker_attack: u32,
        attacker_bonus: i32,
        defender_defense: u32,
        defender_bonus: i32,
    ) -> f64 {
        let attack_roll = attacker_attack as f64 * (1.0 + attacker_bonus as f64 / 64.0);
        let defense_roll = defender_defense as f64 * (1.0 + defender_bonus as f64 / 64.0);

        if attack_roll > defense_roll {
            1.0 - (defense_roll + 2.0) / (2.0 * (attack_roll + 1.0))
        } else {
            attack_roll / (2.0 * (defense_roll + 1.0))
        }
    }

    /// Roll for a hit.
    pub fn roll_hit(hit_chance: f64) -> bool {
        let mut rng = rand::thread_rng();
        rng.gen::<f64>() < hit_chance
    }

    /// Roll damage given max hit.
    pub fn roll_damage(max_hit: u32) -> u32 {
        if max_hit == 0 {
            return 0;
        }
        let mut rng = rand::thread_rng();
        rng.gen_range(0..=max_hit)
    }

    /// Calculate experience from combat.
    pub fn calculate_experience(damage: u32) -> CombatExperience {
        // RSC: 4 XP per damage dealt, distributed based on combat style
        let base_xp = damage * 4;

        CombatExperience {
            attack: 0,
            strength: 0,
            defense: 0,
            hits: base_xp / 3, // Hits always gets 1/3
            base_xp,
        }
    }
}

/// Combat experience distribution.
pub struct CombatExperience {
    pub attack: u32,
    pub strength: u32,
    pub defense: u32,
    pub hits: u32,
    pub base_xp: u32,
}

impl CombatExperience {
    /// Apply combat style to distribute remaining XP.
    pub fn with_style(mut self, style: CombatStyle) -> Self {
        let remaining = self.base_xp - self.hits;

        match style {
            CombatStyle::Controlled => {
                // Split evenly between attack, strength, defense
                let each = remaining / 3;
                self.attack = each;
                self.strength = each;
                self.defense = each;
            }
            CombatStyle::Accurate => {
                self.attack = remaining;
            }
            CombatStyle::Aggressive => {
                self.strength = remaining;
            }
            CombatStyle::Defensive => {
                self.defense = remaining;
            }
        }

        self
    }
}

/// Combat state for tracking ongoing fights.
#[derive(Debug)]
pub struct CombatState {
    pub in_combat: bool,
    pub target_id: Option<u64>,
    pub last_attack_tick: u64,
    pub combat_timer: u32,
    pub style: CombatStyle,
    pub retreat_requested: bool,
}

impl Default for CombatState {
    fn default() -> Self {
        Self {
            in_combat: false,
            target_id: None,
            last_attack_tick: 0,
            combat_timer: 0,
            style: CombatStyle::Controlled,
            retreat_requested: false,
        }
    }
}

impl CombatState {
    /// Start combat with a target.
    pub fn start(&mut self, target_id: u64, tick: u64) {
        self.in_combat = true;
        self.target_id = Some(target_id);
        self.last_attack_tick = tick;
        self.combat_timer = 3; // 3 rounds before can retreat
        self.retreat_requested = false;
    }

    /// End combat.
    pub fn end(&mut self) {
        self.in_combat = false;
        self.target_id = None;
        self.combat_timer = 0;
        self.retreat_requested = false;
    }

    /// Check if player can retreat.
    pub fn can_retreat(&self) -> bool {
        self.combat_timer == 0
    }

    /// Process combat tick.
    pub fn tick(&mut self) {
        if self.combat_timer > 0 {
            self.combat_timer -= 1;
        }
    }
}

/// Prayer effects in combat.
#[derive(Debug, Clone, Copy)]
pub struct PrayerEffects {
    pub attack_multiplier: f64,
    pub strength_multiplier: f64,
    pub defense_multiplier: f64,
    pub protect_item: bool,
}

impl Default for PrayerEffects {
    fn default() -> Self {
        Self {
            attack_multiplier: 1.0,
            strength_multiplier: 1.0,
            defense_multiplier: 1.0,
            protect_item: false,
        }
    }
}

impl PrayerEffects {
    /// Apply Clarity of Thought (5% attack boost).
    pub fn with_clarity_of_thought(mut self) -> Self {
        self.attack_multiplier = 1.05;
        self
    }

    /// Apply Improved Reflexes (10% attack boost).
    pub fn with_improved_reflexes(mut self) -> Self {
        self.attack_multiplier = 1.10;
        self
    }

    /// Apply Incredible Reflexes (15% attack boost).
    pub fn with_incredible_reflexes(mut self) -> Self {
        self.attack_multiplier = 1.15;
        self
    }

    /// Apply Burst of Strength (5% strength boost).
    pub fn with_burst_of_strength(mut self) -> Self {
        self.strength_multiplier = 1.05;
        self
    }

    /// Apply Superhuman Strength (10% strength boost).
    pub fn with_superhuman_strength(mut self) -> Self {
        self.strength_multiplier = 1.10;
        self
    }

    /// Apply Ultimate Strength (15% strength boost).
    pub fn with_ultimate_strength(mut self) -> Self {
        self.strength_multiplier = 1.15;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_combat_style_bonuses() {
        assert_eq!(CombatStyle::Accurate.attack_bonus(), 3);
        assert_eq!(CombatStyle::Aggressive.strength_bonus(), 3);
        assert_eq!(CombatStyle::Defensive.defense_bonus(), 3);
    }

    #[test]
    fn test_damage_roll() {
        let damage = CombatCalculator::roll_damage(10);
        assert!(damage <= 10);
    }

    #[test]
    fn test_combat_experience() {
        let exp = CombatCalculator::calculate_experience(10);
        assert_eq!(exp.base_xp, 40);
        assert_eq!(exp.hits, 13); // 40 / 3 = 13

        let exp = exp.with_style(CombatStyle::Aggressive);
        assert_eq!(exp.strength, 27); // 40 - 13 = 27
    }
}
