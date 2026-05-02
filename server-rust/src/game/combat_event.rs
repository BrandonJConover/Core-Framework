//! Combat event loop — processes active combat encounters each game tick.

use super::combat::{CombatCalculator, CombatStyle, PrayerEffects};
use super::entity::EntityId;
use super::player::SkillId;
use std::collections::HashMap;

/// Ticks between melee combat rounds.
pub const MELEE_ROUND_TICKS: u64 = 3;
/// Ticks between ranged combat rounds.
pub const RANGED_ROUND_TICKS: u64 = 4;
/// Ticks before a player can retreat from combat.
pub const RETREAT_DELAY_TICKS: u64 = 3;

/// Represents one side of a combat encounter.
#[derive(Debug, Clone)]
pub struct Combatant {
    pub entity_id: EntityId,
    pub is_npc: bool,
    // Combat stats snapshot (refreshed each round from live entity)
    pub attack_level: u32,
    pub strength_level: u32,
    pub defense_level: u32,
    pub current_hp: u32,
    pub max_hp: u32,
    pub ranged_level: u32,
    pub magic_level: u32,
    pub prayer_level: u32,
    // Equipment bonuses
    pub attack_bonus: i32,
    pub strength_bonus: i32,
    pub defense_bonus: i32,
    // Active prayer effects
    pub prayer_effects: PrayerEffects,
    // Combat style
    pub combat_style: CombatStyle,
}

/// An active combat encounter between two entities.
#[derive(Debug)]
pub struct CombatEncounter {
    pub id: u64,
    pub attacker: Combatant,
    pub defender: Combatant,
    pub start_tick: u64,
    pub last_round_tick: u64,
    pub round_count: u32,
    pub state: CombatState,
    /// Type of combat (determines round timing)
    pub combat_type: CombatType,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CombatState {
    /// Combat is active
    Active,
    /// Attacker is retreating (will end next tick if not re-engaged)
    AttackerRetreating,
    /// Defender is retreating
    DefenderRetreating,
    /// Combat ended — attacker won
    AttackerWon,
    /// Combat ended — defender won
    DefenderWon,
    /// Combat ended — one party fled
    Fled,
    /// Combat ended — one party logged out
    Interrupted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CombatType {
    Melee,
    Ranged,
    Magic,
}

impl CombatType {
    pub fn round_ticks(&self) -> u64 {
        match self {
            CombatType::Melee => MELEE_ROUND_TICKS,
            CombatType::Ranged => RANGED_ROUND_TICKS,
            CombatType::Magic => RANGED_ROUND_TICKS,
        }
    }
}

/// Result of processing a single combat round.
#[derive(Debug)]
pub struct RoundResult {
    pub attacker_id: EntityId,
    pub defender_id: EntityId,
    pub damage_dealt: u32,
    pub defender_hp_remaining: u32,
    pub defender_hp_max: u32,
    pub defender_died: bool,
    /// XP to award to the attacker
    pub xp_awards: Vec<(SkillId, u32)>,
}

/// Manages all active combat encounters.
#[derive(Debug)]
pub struct CombatManager {
    encounters: HashMap<u64, CombatEncounter>,
    /// Map entity ID to encounter ID for fast lookup
    entity_to_encounter: HashMap<EntityId, u64>,
    next_encounter_id: u64,
}

impl CombatManager {
    pub fn new() -> Self {
        Self {
            encounters: HashMap::new(),
            entity_to_encounter: HashMap::new(),
            next_encounter_id: 1,
        }
    }

    /// Start a new combat encounter.
    /// Returns the encounter ID, or 0 if either entity is already in combat.
    pub fn start_combat(
        &mut self,
        attacker: Combatant,
        defender: Combatant,
        combat_type: CombatType,
        current_tick: u64,
    ) -> u64 {
        // If either is already in combat, don't start a new one
        if self.is_in_combat(&attacker.entity_id) || self.is_in_combat(&defender.entity_id) {
            return 0;
        }

        let encounter_id = self.next_encounter_id;
        self.next_encounter_id += 1;

        self.entity_to_encounter
            .insert(attacker.entity_id, encounter_id);
        self.entity_to_encounter
            .insert(defender.entity_id, encounter_id);

        let encounter = CombatEncounter {
            id: encounter_id,
            attacker,
            defender,
            start_tick: current_tick,
            last_round_tick: current_tick,
            round_count: 0,
            state: CombatState::Active,
            combat_type,
        };

        self.encounters.insert(encounter_id, encounter);
        encounter_id
    }

    /// Check if an entity is currently in combat.
    pub fn is_in_combat(&self, entity_id: &EntityId) -> bool {
        self.entity_to_encounter.contains_key(entity_id)
    }

    /// Check if an entity can retreat (retreat timer expired).
    pub fn can_retreat(&self, entity_id: &EntityId, current_tick: u64) -> bool {
        if let Some(&enc_id) = self.entity_to_encounter.get(entity_id) {
            if let Some(encounter) = self.encounters.get(&enc_id) {
                return current_tick >= encounter.start_tick + RETREAT_DELAY_TICKS;
            }
        }
        false
    }

    /// Request retreat for an entity. Returns false if retreat timer has not expired.
    pub fn request_retreat(&mut self, entity_id: &EntityId, current_tick: u64) -> bool {
        if !self.can_retreat(entity_id, current_tick) {
            return false;
        }

        if let Some(&enc_id) = self.entity_to_encounter.get(entity_id) {
            if let Some(encounter) = self.encounters.get_mut(&enc_id) {
                if encounter.attacker.entity_id == *entity_id {
                    encounter.state = CombatState::AttackerRetreating;
                } else {
                    encounter.state = CombatState::DefenderRetreating;
                }
                return true;
            }
        }
        false
    }

    /// Process all active combat encounters for this tick.
    /// Returns round results for encounters that had a round this tick.
    pub fn process_tick(&mut self, current_tick: u64) -> Vec<RoundResult> {
        let mut results = Vec::new();
        let mut ended_encounters = Vec::new();

        for (&enc_id, encounter) in self.encounters.iter_mut() {
            // Skip finished encounters
            match encounter.state {
                CombatState::AttackerWon
                | CombatState::DefenderWon
                | CombatState::Fled
                | CombatState::Interrupted => {
                    ended_encounters.push(enc_id);
                    continue;
                }
                CombatState::AttackerRetreating | CombatState::DefenderRetreating => {
                    encounter.state = CombatState::Fled;
                    ended_encounters.push(enc_id);
                    continue;
                }
                CombatState::Active => {}
            }

            // Check if it's time for a combat round
            let round_interval = encounter.combat_type.round_ticks();
            if current_tick < encounter.last_round_tick + round_interval {
                continue;
            }

            encounter.last_round_tick = current_tick;
            encounter.round_count += 1;

            // Alternate: odd rounds = attacker hits, even rounds = defender hits
            let (active, target) = if encounter.round_count % 2 == 1 {
                (&encounter.attacker, &mut encounter.defender)
            } else {
                (&encounter.defender, &mut encounter.attacker)
            };

            // Calculate hit chance using existing CombatCalculator API
            let hit_chance = CombatCalculator::calculate_hit_chance(
                (active.attack_level as f64 * active.prayer_effects.attack_multiplier) as u32
                    + active.combat_style.attack_bonus() as u32,
                active.attack_bonus,
                (target.defense_level as f64 * target.prayer_effects.defense_multiplier) as u32
                    + target.combat_style.defense_bonus() as u32,
                target.defense_bonus,
            );

            // Roll to see if the attack hits
            let damage = if CombatCalculator::roll_hit(hit_chance) {
                // Calculate effective strength for max hit
                let effective_strength = (active.strength_level as f64
                    * active.prayer_effects.strength_multiplier)
                    as i32
                    + active.combat_style.strength_bonus()
                    + active.strength_bonus;

                // RSC max hit formula (mirrors CombatCalculator::calculate_max_hit)
                let max_hit = ((effective_strength as f64) * 0.14 + 1.05) as u32;
                let max_hit = max_hit.max(1);

                CombatCalculator::roll_damage(max_hit)
            } else {
                0
            };

            // Apply damage
            if damage >= target.current_hp {
                target.current_hp = 0;
            } else {
                target.current_hp -= damage;
            }

            let defender_died = target.current_hp == 0;

            // Calculate XP awards using existing CombatExperience API
            let xp_result = CombatCalculator::calculate_experience(damage)
                .with_style(active.combat_style);

            let mut xp_awards = Vec::new();
            if xp_result.attack > 0 {
                xp_awards.push((SkillId::Attack, xp_result.attack));
            }
            if xp_result.strength > 0 {
                xp_awards.push((SkillId::Strength, xp_result.strength));
            }
            if xp_result.defense > 0 {
                xp_awards.push((SkillId::Defence, xp_result.defense));
            }
            if xp_result.hits > 0 {
                xp_awards.push((SkillId::Hits, xp_result.hits));
            }

            results.push(RoundResult {
                attacker_id: active.entity_id,
                defender_id: target.entity_id,
                damage_dealt: damage,
                defender_hp_remaining: target.current_hp,
                defender_hp_max: target.max_hp,
                defender_died,
                xp_awards,
            });

            // Check for death
            if defender_died {
                // Determine winner based on who swung this round
                if encounter.round_count % 2 == 1 {
                    encounter.state = CombatState::AttackerWon;
                } else {
                    encounter.state = CombatState::DefenderWon;
                }
                ended_encounters.push(enc_id);
            }
        }

        // Clean up ended encounters
        for enc_id in ended_encounters {
            if let Some(encounter) = self.encounters.remove(&enc_id) {
                self.entity_to_encounter
                    .remove(&encounter.attacker.entity_id);
                self.entity_to_encounter
                    .remove(&encounter.defender.entity_id);
            }
        }

        results
    }

    /// Force-end combat for an entity (e.g., on logout or teleport).
    pub fn force_end(&mut self, entity_id: &EntityId) {
        if let Some(&enc_id) = self.entity_to_encounter.get(entity_id) {
            if let Some(encounter) = self.encounters.get_mut(&enc_id) {
                encounter.state = CombatState::Interrupted;
            }
        }
    }

    /// Get the encounter for an entity (read-only).
    pub fn get_encounter(&self, entity_id: &EntityId) -> Option<&CombatEncounter> {
        self.entity_to_encounter
            .get(entity_id)
            .and_then(|&enc_id| self.encounters.get(&enc_id))
    }

    /// Number of active encounters.
    pub fn active_count(&self) -> usize {
        self.encounters.len()
    }
}

impl Default for CombatManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_combatant(id: u64, hp: u32) -> Combatant {
        Combatant {
            entity_id: EntityId(id),
            is_npc: false,
            attack_level: 10,
            strength_level: 10,
            defense_level: 10,
            current_hp: hp,
            max_hp: hp,
            ranged_level: 1,
            magic_level: 1,
            prayer_level: 1,
            attack_bonus: 0,
            strength_bonus: 0,
            defense_bonus: 0,
            prayer_effects: PrayerEffects::default(),
            combat_style: CombatStyle::Accurate,
        }
    }

    #[test]
    fn test_start_combat() {
        let mut manager = CombatManager::new();
        let a = make_combatant(1, 20);
        let b = make_combatant(2, 20);

        let enc_id = manager.start_combat(a, b, CombatType::Melee, 0);
        assert!(enc_id > 0);
        assert!(manager.is_in_combat(&EntityId(1)));
        assert!(manager.is_in_combat(&EntityId(2)));
        assert!(!manager.is_in_combat(&EntityId(3)));
    }

    #[test]
    fn test_duplicate_combat_rejected() {
        let mut manager = CombatManager::new();
        let a = make_combatant(1, 20);
        let b = make_combatant(2, 20);
        let c = make_combatant(3, 20);

        let enc1 = manager.start_combat(a, b, CombatType::Melee, 0);
        assert!(enc1 > 0);

        // Entity 1 is already in combat — starting a new fight should be rejected
        let a2 = make_combatant(1, 20);
        let enc2 = manager.start_combat(a2, c, CombatType::Melee, 0);
        assert_eq!(enc2, 0);
    }

    #[test]
    fn test_retreat_timer() {
        let mut manager = CombatManager::new();
        let a = make_combatant(1, 20);
        let b = make_combatant(2, 20);

        manager.start_combat(a, b, CombatType::Melee, 0);

        // Cannot retreat until RETREAT_DELAY_TICKS have passed
        assert!(!manager.can_retreat(&EntityId(1), 0));
        assert!(!manager.can_retreat(&EntityId(1), 2));
        assert!(manager.can_retreat(&EntityId(1), 3));
        assert!(manager.can_retreat(&EntityId(2), 5));
    }

    #[test]
    fn test_retreat_request() {
        let mut manager = CombatManager::new();
        let a = make_combatant(1, 20);
        let b = make_combatant(2, 20);

        manager.start_combat(a, b, CombatType::Melee, 0);

        // Too early to retreat
        assert!(!manager.request_retreat(&EntityId(1), 1));

        // Now retreat is allowed
        assert!(manager.request_retreat(&EntityId(1), 3));
        let enc = manager.get_encounter(&EntityId(1)).unwrap();
        assert_eq!(enc.state, CombatState::AttackerRetreating);

        // Next tick processes the retreat — encounter ends with Fled
        let results = manager.process_tick(4);
        assert!(results.is_empty());
        assert!(!manager.is_in_combat(&EntityId(1)));
        assert!(!manager.is_in_combat(&EntityId(2)));
    }

    #[test]
    fn test_combat_processes_rounds() {
        let mut manager = CombatManager::new();
        let a = make_combatant(1, 100);
        let b = make_combatant(2, 100);

        manager.start_combat(a, b, CombatType::Melee, 0);

        // Tick 0-2: no round yet (first round fires at start_tick + round_interval)
        assert!(manager.process_tick(0).is_empty());
        assert!(manager.process_tick(1).is_empty());
        assert!(manager.process_tick(2).is_empty());

        // Tick 3: first round fires
        let results = manager.process_tick(3);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].attacker_id, EntityId(1));
        assert_eq!(results[0].defender_id, EntityId(2));
    }

    #[test]
    fn test_ranged_round_timing() {
        let mut manager = CombatManager::new();
        let a = make_combatant(1, 100);
        let b = make_combatant(2, 100);

        manager.start_combat(a, b, CombatType::Ranged, 0);

        // Ranged rounds fire every 4 ticks
        assert!(manager.process_tick(3).is_empty());
        let results = manager.process_tick(4);
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn test_force_end() {
        let mut manager = CombatManager::new();
        let a = make_combatant(1, 20);
        let b = make_combatant(2, 20);

        manager.start_combat(a, b, CombatType::Melee, 0);
        assert!(manager.is_in_combat(&EntityId(1)));

        manager.force_end(&EntityId(1));

        // Next process_tick will clean it up
        manager.process_tick(1);
        assert!(!manager.is_in_combat(&EntityId(1)));
        assert!(!manager.is_in_combat(&EntityId(2)));
    }

    #[test]
    fn test_combat_to_death() {
        let mut manager = CombatManager::new();
        // Give attacker huge stats, defender 1 HP so first hit kills
        let mut a = make_combatant(1, 100);
        a.attack_level = 99;
        a.strength_level = 99;

        let b = make_combatant(2, 1);

        manager.start_combat(a, b, CombatType::Melee, 0);

        // Process rounds until death occurs (should be fast with 1 HP defender)
        let mut tick = 3;
        let mut death_found = false;
        while tick < 100 {
            let results = manager.process_tick(tick);
            for r in &results {
                if r.defender_died {
                    death_found = true;
                    assert_eq!(r.defender_hp_remaining, 0);
                }
            }
            if death_found {
                break;
            }
            tick += 3;
        }

        // Even if the first hit was a 0, it should eventually die
        // After death, entities are removed from combat
        assert!(!manager.is_in_combat(&EntityId(1)));
        assert!(!manager.is_in_combat(&EntityId(2)));
        assert_eq!(manager.active_count(), 0);
    }

    #[test]
    fn test_xp_awards_with_style() {
        let mut manager = CombatManager::new();
        let mut a = make_combatant(1, 100);
        a.attack_level = 99;
        a.strength_level = 99;
        a.combat_style = CombatStyle::Aggressive;

        let b = make_combatant(2, 100);

        manager.start_combat(a, b, CombatType::Melee, 0);

        // Process until we get a round with nonzero damage
        let mut tick = 3;
        while tick < 300 {
            let results = manager.process_tick(tick);
            for r in &results {
                if r.damage_dealt > 0 {
                    // Aggressive style: strength XP + hits XP
                    let has_strength = r.xp_awards.iter().any(|(s, _)| *s == SkillId::Strength);
                    let has_hits = r.xp_awards.iter().any(|(s, _)| *s == SkillId::Hits);
                    assert!(has_strength, "Aggressive style should award strength XP");
                    assert!(has_hits, "Should always award hits XP");
                    return;
                }
            }
            tick += 3;
        }
        panic!("Expected at least one nonzero damage round");
    }

    #[test]
    fn test_default_trait() {
        let manager = CombatManager::default();
        assert_eq!(manager.active_count(), 0);
    }

    #[test]
    fn test_combat_type_round_ticks() {
        assert_eq!(CombatType::Melee.round_ticks(), 3);
        assert_eq!(CombatType::Ranged.round_ticks(), 4);
        assert_eq!(CombatType::Magic.round_ticks(), 4);
    }
}
