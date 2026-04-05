//! Skills module for player skill management.

use super::player::SkillId;
pub use super::player::SkillId as SkillType;
use std::collections::HashMap;

/// Experience table for levels 1-99.
const EXPERIENCE_TABLE: [u32; 99] = [
    0, 83, 174, 276, 388, 512, 650, 801, 969, 1154,
    1358, 1584, 1833, 2107, 2411, 2746, 3115, 3523, 3973, 4470,
    5018, 5624, 6291, 7028, 7842, 8740, 9730, 10824, 12031, 13363,
    14833, 16456, 18247, 20224, 22406, 24815, 27473, 30408, 33648, 37224,
    41171, 45529, 50339, 55649, 61512, 67983, 75127, 83014, 91721, 101333,
    111945, 123660, 136594, 150872, 166636, 184040, 203254, 224466, 247886, 273742,
    302288, 333804, 368599, 407015, 449428, 496254, 547953, 605032, 668051, 737627,
    814445, 899257, 992895, 1096278, 1210421, 1336443, 1475581, 1629200, 1798808, 1986068,
    2192818, 2421087, 2673114, 2951373, 3258594, 3597792, 3972294, 4385776, 4842295, 5346332,
    5902831, 6517253, 7195629, 7944614, 8771558, 9684577, 10692629, 11805606, 13034431,
];

/// Player skills container.
#[derive(Debug)]
pub struct Skills {
    levels: HashMap<SkillId, u8>,
    current_levels: HashMap<SkillId, u8>,
    experience: HashMap<SkillId, u32>,
}

impl Skills {
    pub fn new() -> Self {
        let mut skills = Self {
            levels: HashMap::new(),
            current_levels: HashMap::new(),
            experience: HashMap::new(),
        };

        // Initialize all skills to level 1
        for skill in ALL_SKILLS.iter() {
            skills.levels.insert(*skill, 1);
            skills.current_levels.insert(*skill, 1);
            skills.experience.insert(*skill, 0);
        }

        // Hits starts at 10
        skills.levels.insert(SkillId::Hits, 10);
        skills.current_levels.insert(SkillId::Hits, 10);
        skills.experience.insert(SkillId::Hits, 1154);

        skills
    }

    /// Get the base level of a skill.
    pub fn level(&self, skill: SkillId) -> u8 {
        *self.levels.get(&skill).unwrap_or(&1)
    }

    /// Alias for `level()` — get the base level of a skill.
    pub fn get_level(&self, skill: SkillId) -> u8 {
        self.level(skill)
    }

    /// Get the current level of a skill (may be boosted/drained).
    pub fn current_level(&self, skill: SkillId) -> u8 {
        *self.current_levels.get(&skill).unwrap_or(&1)
    }

    /// Get experience in a skill.
    pub fn experience(&self, skill: SkillId) -> u32 {
        *self.experience.get(&skill).unwrap_or(&0)
    }

    /// Add experience to a skill.
    pub fn add_experience(&mut self, skill: SkillId, exp: u32) -> bool {
        let current_exp = self.experience.entry(skill).or_insert(0);
        let old_level = self.level_for_experience(*current_exp);

        *current_exp = current_exp.saturating_add(exp);

        // Cap at max experience
        if *current_exp > 13034431 {
            *current_exp = 13034431;
        }

        let new_level = self.level_for_experience(*current_exp);

        // Level up
        if new_level > old_level {
            self.levels.insert(skill, new_level);

            // Increase current level too
            let current = self.current_levels.entry(skill).or_insert(1);
            *current = (*current as u16 + (new_level - old_level) as u16).min(99) as u8;

            true // Leveled up
        } else {
            false
        }
    }

    /// Set current level (for boosts/drains).
    pub fn set_current_level(&mut self, skill: SkillId, level: u8) {
        self.current_levels.insert(skill, level.min(118)); // Cap at 118 (boosted max)
    }

    /// Restore current level to base level.
    pub fn restore(&mut self, skill: SkillId) {
        let base = self.level(skill);
        self.current_levels.insert(skill, base);
    }

    /// Restore all skills to base levels.
    pub fn restore_all(&mut self) {
        for skill in ALL_SKILLS.iter() {
            self.restore(*skill);
        }
    }

    /// Get level for given experience amount.
    fn level_for_experience(&self, exp: u32) -> u8 {
        for (level, &required) in EXPERIENCE_TABLE.iter().enumerate() {
            if exp < required {
                return level as u8;
            }
        }
        99
    }

    /// Get experience required for a level.
    pub fn experience_for_level(level: u8) -> u32 {
        if level == 0 || level > 99 {
            return 0;
        }
        EXPERIENCE_TABLE[(level - 1) as usize]
    }

    /// Get total level (sum of all base levels).
    pub fn total_level(&self) -> u32 {
        self.levels.values().map(|&l| l as u32).sum()
    }

    /// Get total experience (sum of all experience).
    pub fn total_experience(&self) -> u64 {
        self.experience.values().map(|&e| e as u64).sum()
    }

    /// Calculate combat level from combat skills.
    pub fn combat_level(&self) -> u32 {
        let attack = self.level(SkillId::Attack) as f64;
        let strength = self.level(SkillId::Strength) as f64;
        let defense = self.level(SkillId::Defence) as f64;
        let hits = self.level(SkillId::Hits) as f64;
        let ranged = self.level(SkillId::Ranged) as f64;
        let prayer = self.level(SkillId::Prayer) as f64;
        let magic = self.level(SkillId::Magic) as f64;

        let base = (defense + hits + (prayer / 8.0)) / 4.0;
        let melee = (attack + strength) * 0.25;
        let range = ranged * 0.375;
        let mage = magic * 0.375;

        (base + melee.max(range).max(mage)) as u32
    }
}

impl Default for Skills {
    fn default() -> Self {
        Self::new()
    }
}

/// All skill IDs.
const ALL_SKILLS: [SkillId; 18] = [
    SkillId::Attack,
    SkillId::Defence,
    SkillId::Strength,
    SkillId::Hits,
    SkillId::Ranged,
    SkillId::Prayer,
    SkillId::Magic,
    SkillId::Cooking,
    SkillId::Woodcutting,
    SkillId::Fletching,
    SkillId::Fishing,
    SkillId::Firemaking,
    SkillId::Crafting,
    SkillId::Smithing,
    SkillId::Mining,
    SkillId::Herblore,
    SkillId::Agility,
    SkillId::Thieving,
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_player_skills() {
        let skills = Skills::new();
        assert_eq!(skills.level(SkillId::Attack), 1);
        assert_eq!(skills.level(SkillId::Hits), 10);
    }

    #[test]
    fn test_add_experience() {
        let mut skills = Skills::new();
        let leveled = skills.add_experience(SkillId::Attack, 200);
        assert!(leveled);
        assert_eq!(skills.level(SkillId::Attack), 2);
    }

    #[test]
    fn test_combat_level() {
        let skills = Skills::new();
        let combat = skills.combat_level();
        assert_eq!(combat, 3); // Default combat level for new player
    }
}
