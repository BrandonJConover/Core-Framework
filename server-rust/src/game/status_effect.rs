//! Status effect system.
//! Handles poison, stat drains, buffs, debuffs, and timed effects.

use std::collections::HashMap;

/// Types of status effects.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum StatusType {
    /// Poison - periodic damage.
    Poison,
    /// Super poison - stronger periodic damage.
    SuperPoison,
    /// Skull - PK penalty marker.
    Skull,
    /// Stat boost - temporary skill increase.
    StatBoost,
    /// Stat drain - temporary skill decrease.
    StatDrain,
    /// Prayer drain - faster prayer point loss.
    PrayerDrain,
    /// Protection - damage immunity.
    Protection,
    /// Antifire - dragon breath protection.
    Antifire,
    /// Antipoison - poison immunity.
    Antipoison,
    /// Teleblock - cannot teleport.
    Teleblock,
    /// Bind - cannot move.
    Bind,
    /// Stun - cannot act.
    Stun,
    /// Regeneration - faster hitpoint recovery.
    Regeneration,
    /// Strength boost from potion.
    StrengthPotion,
    /// Attack boost from potion.
    AttackPotion,
    /// Defence boost from potion.
    DefencePotion,
    /// Super strength boost.
    SuperStrength,
    /// Super attack boost.
    SuperAttack,
    /// Super defence boost.
    SuperDefence,
    /// Ranging potion boost.
    RangingPotion,
    /// Magic potion boost.
    MagicPotion,
}

impl StatusType {
    /// Check if this effect is negative.
    pub fn is_negative(&self) -> bool {
        matches!(
            self,
            StatusType::Poison
                | StatusType::SuperPoison
                | StatusType::StatDrain
                | StatusType::PrayerDrain
                | StatusType::Teleblock
                | StatusType::Bind
                | StatusType::Stun
        )
    }

    /// Check if this effect is a buff.
    pub fn is_buff(&self) -> bool {
        matches!(
            self,
            StatusType::StatBoost
                | StatusType::Protection
                | StatusType::Antifire
                | StatusType::Antipoison
                | StatusType::Regeneration
                | StatusType::StrengthPotion
                | StatusType::AttackPotion
                | StatusType::DefencePotion
                | StatusType::SuperStrength
                | StatusType::SuperAttack
                | StatusType::SuperDefence
                | StatusType::RangingPotion
                | StatusType::MagicPotion
        )
    }

    /// Check if this effect can stack.
    pub fn can_stack(&self) -> bool {
        matches!(self, StatusType::StatBoost | StatusType::StatDrain)
    }

    /// Get the icon ID for display.
    pub fn icon_id(&self) -> Option<u16> {
        match self {
            StatusType::Poison | StatusType::SuperPoison => Some(1),
            StatusType::Skull => Some(2),
            StatusType::Teleblock => Some(3),
            _ => None,
        }
    }
}

/// A status effect applied to an entity.
#[derive(Debug, Clone)]
pub struct StatusEffect {
    /// Effect type.
    pub effect_type: StatusType,
    /// Effect strength/intensity.
    pub strength: i32,
    /// Duration remaining in game ticks.
    pub duration: u32,
    /// Maximum duration.
    pub max_duration: u32,
    /// Tick interval for periodic effects.
    pub tick_interval: u32,
    /// Ticks until next effect tick.
    pub ticks_until_next: u32,
    /// Source entity (who applied it).
    pub source_id: Option<u64>,
    /// Skill affected (for stat effects).
    pub affected_skill: Option<u8>,
}

impl StatusEffect {
    /// Create a new status effect.
    pub fn new(effect_type: StatusType, strength: i32, duration: u32) -> Self {
        Self {
            effect_type,
            strength,
            duration,
            max_duration: duration,
            tick_interval: 0,
            ticks_until_next: 0,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Create a poison effect.
    pub fn poison(damage: i32) -> Self {
        Self {
            effect_type: StatusType::Poison,
            strength: damage,
            duration: 500, // Long duration, decreases over time
            max_duration: 500,
            tick_interval: 30, // Every 30 ticks (18 seconds)
            ticks_until_next: 30,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Create a super poison effect.
    pub fn super_poison(damage: i32) -> Self {
        Self {
            effect_type: StatusType::SuperPoison,
            strength: damage,
            duration: 800,
            max_duration: 800,
            tick_interval: 30,
            ticks_until_next: 30,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Create a skull effect.
    pub fn skull() -> Self {
        Self {
            effect_type: StatusType::Skull,
            strength: 0,
            duration: 2000, // 20 minutes at 600ms ticks
            max_duration: 2000,
            tick_interval: 0,
            ticks_until_next: 0,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Create a stat boost effect.
    pub fn stat_boost(skill: u8, boost: i32, duration: u32) -> Self {
        Self {
            effect_type: StatusType::StatBoost,
            strength: boost,
            duration,
            max_duration: duration,
            tick_interval: 100, // Decay every 100 ticks
            ticks_until_next: 100,
            source_id: None,
            affected_skill: Some(skill),
        }
    }

    /// Create a stat drain effect.
    pub fn stat_drain(skill: u8, drain: i32, duration: u32) -> Self {
        Self {
            effect_type: StatusType::StatDrain,
            strength: drain,
            duration,
            max_duration: duration,
            tick_interval: 100,
            ticks_until_next: 100,
            source_id: None,
            affected_skill: Some(skill),
        }
    }

    /// Create a teleblock effect.
    pub fn teleblock() -> Self {
        Self {
            effect_type: StatusType::Teleblock,
            strength: 0,
            duration: 500, // 5 minutes
            max_duration: 500,
            tick_interval: 0,
            ticks_until_next: 0,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Create a bind/freeze effect.
    pub fn bind(duration: u32) -> Self {
        Self {
            effect_type: StatusType::Bind,
            strength: 0,
            duration,
            max_duration: duration,
            tick_interval: 0,
            ticks_until_next: 0,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Create a stun effect.
    pub fn stun(duration: u32) -> Self {
        Self {
            effect_type: StatusType::Stun,
            strength: 0,
            duration,
            max_duration: duration,
            tick_interval: 0,
            ticks_until_next: 0,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Create an antipoison effect.
    pub fn antipoison(duration: u32) -> Self {
        Self {
            effect_type: StatusType::Antipoison,
            strength: 0,
            duration,
            max_duration: duration,
            tick_interval: 0,
            ticks_until_next: 0,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Create an antifire effect.
    pub fn antifire(duration: u32) -> Self {
        Self {
            effect_type: StatusType::Antifire,
            strength: 0,
            duration,
            max_duration: duration,
            tick_interval: 0,
            ticks_until_next: 0,
            source_id: None,
            affected_skill: None,
        }
    }

    /// Set source entity.
    pub fn with_source(mut self, source_id: u64) -> Self {
        self.source_id = Some(source_id);
        self
    }

    /// Check if effect is active.
    pub fn is_active(&self) -> bool {
        self.duration > 0
    }

    /// Check if effect should tick now.
    pub fn should_tick(&self) -> bool {
        self.tick_interval > 0 && self.ticks_until_next == 0
    }

    /// Get remaining duration as percentage.
    pub fn remaining_percent(&self) -> f64 {
        if self.max_duration == 0 {
            return 0.0;
        }
        (self.duration as f64 / self.max_duration as f64) * 100.0
    }
}

/// Result of ticking a status effect.
#[derive(Debug, Clone)]
pub struct EffectTickResult {
    /// Damage to apply.
    pub damage: i32,
    /// Stat changes to apply (skill_id, delta).
    pub stat_changes: Vec<(u8, i32)>,
    /// Whether the effect expired.
    pub expired: bool,
    /// Whether to remove the effect.
    pub remove: bool,
}

impl Default for EffectTickResult {
    fn default() -> Self {
        Self {
            damage: 0,
            stat_changes: Vec::new(),
            expired: false,
            remove: false,
        }
    }
}

/// Manager for status effects on an entity.
#[derive(Debug, Default)]
pub struct StatusEffectManager {
    /// Active effects.
    effects: HashMap<StatusType, StatusEffect>,
    /// Stat modifiers by skill ID.
    stat_modifiers: HashMap<u8, i32>,
}

impl StatusEffectManager {
    /// Create a new status effect manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a status effect.
    pub fn add_effect(&mut self, effect: StatusEffect) {
        let effect_type = effect.effect_type;

        // Handle antipoison curing poison
        if effect_type == StatusType::Antipoison {
            self.effects.remove(&StatusType::Poison);
            self.effects.remove(&StatusType::SuperPoison);
        }

        // Check for existing effect
        if let Some(existing) = self.effects.get_mut(&effect_type) {
            if effect_type.can_stack() {
                // Stack the effect
                existing.strength += effect.strength;
                existing.duration = existing.duration.max(effect.duration);
            } else {
                // Replace if stronger or longer
                if effect.strength > existing.strength || effect.duration > existing.duration {
                    *existing = effect;
                }
            }
        } else {
            // Apply stat modifier if applicable
            if let Some(skill) = effect.affected_skill {
                let modifier = match effect.effect_type {
                    StatusType::StatBoost => effect.strength,
                    StatusType::StatDrain => -effect.strength,
                    _ => 0,
                };
                *self.stat_modifiers.entry(skill).or_insert(0) += modifier;
            }

            self.effects.insert(effect_type, effect);
        }
    }

    /// Remove a status effect.
    pub fn remove_effect(&mut self, effect_type: StatusType) -> Option<StatusEffect> {
        if let Some(effect) = self.effects.remove(&effect_type) {
            // Remove stat modifier
            if let Some(skill) = effect.affected_skill {
                if let Some(modifier) = self.stat_modifiers.get_mut(&skill) {
                    match effect.effect_type {
                        StatusType::StatBoost => *modifier -= effect.strength,
                        StatusType::StatDrain => *modifier += effect.strength,
                        _ => {}
                    }
                }
            }
            Some(effect)
        } else {
            None
        }
    }

    /// Check if entity has an effect.
    pub fn has_effect(&self, effect_type: StatusType) -> bool {
        self.effects.contains_key(&effect_type)
    }

    /// Get an effect.
    pub fn get_effect(&self, effect_type: StatusType) -> Option<&StatusEffect> {
        self.effects.get(&effect_type)
    }

    /// Check if entity is poisoned.
    pub fn is_poisoned(&self) -> bool {
        self.has_effect(StatusType::Poison) || self.has_effect(StatusType::SuperPoison)
    }

    /// Check if entity is skulled.
    pub fn is_skulled(&self) -> bool {
        self.has_effect(StatusType::Skull)
    }

    /// Check if entity can teleport.
    pub fn can_teleport(&self) -> bool {
        !self.has_effect(StatusType::Teleblock)
    }

    /// Check if entity can move.
    pub fn can_move(&self) -> bool {
        !self.has_effect(StatusType::Bind) && !self.has_effect(StatusType::Stun)
    }

    /// Check if entity can act.
    pub fn can_act(&self) -> bool {
        !self.has_effect(StatusType::Stun)
    }

    /// Get stat modifier for a skill.
    pub fn get_stat_modifier(&self, skill: u8) -> i32 {
        self.stat_modifiers.get(&skill).copied().unwrap_or(0)
    }

    /// Tick all effects.
    pub fn tick(&mut self) -> Vec<EffectTickResult> {
        let mut results = Vec::new();
        let mut to_remove = Vec::new();

        for (effect_type, effect) in self.effects.iter_mut() {
            let mut result = EffectTickResult::default();

            // Decrease duration
            if effect.duration > 0 {
                effect.duration -= 1;
            }

            // Handle periodic effects
            if effect.tick_interval > 0 {
                if effect.ticks_until_next > 0 {
                    effect.ticks_until_next -= 1;
                }

                if effect.ticks_until_next == 0 {
                    // Effect tick triggered
                    match effect.effect_type {
                        StatusType::Poison => {
                            result.damage = effect.strength;
                            // Poison damage decreases over time
                            if effect.strength > 1 && effect.duration % 50 == 0 {
                                effect.strength -= 1;
                            }
                        }
                        StatusType::SuperPoison => {
                            result.damage = effect.strength;
                            if effect.strength > 2 && effect.duration % 40 == 0 {
                                effect.strength -= 1;
                            }
                        }
                        StatusType::StatBoost | StatusType::StatDrain => {
                            // Stat effects decay over time
                            if let Some(skill) = effect.affected_skill {
                                let decay = if effect.strength > 0 { 1 } else { 0 };
                                if decay > 0 {
                                    effect.strength -= decay;
                                    result.stat_changes.push((skill, -decay));
                                }
                            }
                        }
                        _ => {}
                    }

                    effect.ticks_until_next = effect.tick_interval;
                }
            }

            // Check if expired
            if effect.duration == 0 || effect.strength <= 0 {
                result.expired = true;
                result.remove = true;
                to_remove.push(*effect_type);
            }

            if result.damage > 0 || !result.stat_changes.is_empty() || result.expired {
                results.push(result);
            }
        }

        // Remove expired effects
        for effect_type in to_remove {
            self.remove_effect(effect_type);
        }

        results
    }

    /// Clear all effects.
    pub fn clear_all(&mut self) {
        self.effects.clear();
        self.stat_modifiers.clear();
    }

    /// Clear all negative effects.
    pub fn clear_negative(&mut self) {
        let negative: Vec<_> = self
            .effects
            .keys()
            .filter(|t| t.is_negative())
            .copied()
            .collect();

        for effect_type in negative {
            self.remove_effect(effect_type);
        }
    }

    /// Get all active effect types.
    pub fn active_effects(&self) -> Vec<StatusType> {
        self.effects.keys().copied().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_poison_effect() {
        let mut manager = StatusEffectManager::new();
        manager.add_effect(StatusEffect::poison(6));

        assert!(manager.is_poisoned());
        assert!(manager.has_effect(StatusType::Poison));
    }

    #[test]
    fn test_antipoison() {
        let mut manager = StatusEffectManager::new();
        manager.add_effect(StatusEffect::poison(6));
        assert!(manager.is_poisoned());

        manager.add_effect(StatusEffect::antipoison(500));
        assert!(!manager.is_poisoned());
        assert!(manager.has_effect(StatusType::Antipoison));
    }

    #[test]
    fn test_stat_boost() {
        let mut manager = StatusEffectManager::new();
        manager.add_effect(StatusEffect::stat_boost(0, 5, 100)); // Skill 0 = Attack

        assert_eq!(manager.get_stat_modifier(0), 5);
        assert!(manager.has_effect(StatusType::StatBoost));
    }

    #[test]
    fn test_movement_restrictions() {
        let mut manager = StatusEffectManager::new();
        assert!(manager.can_move());
        assert!(manager.can_teleport());

        manager.add_effect(StatusEffect::bind(10));
        assert!(!manager.can_move());

        manager.add_effect(StatusEffect::teleblock());
        assert!(!manager.can_teleport());
    }

    #[test]
    fn test_skull() {
        let mut manager = StatusEffectManager::new();
        assert!(!manager.is_skulled());

        manager.add_effect(StatusEffect::skull());
        assert!(manager.is_skulled());
    }
}
