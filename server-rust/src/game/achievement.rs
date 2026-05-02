//! Achievement system.
//! Tracks player accomplishments and unlocks rewards.

use std::collections::{HashMap, HashSet};
use tracing::info;

/// Achievement categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AchievementCategory {
    /// Combat achievements.
    Combat,
    /// Skilling achievements.
    Skilling,
    /// Questing achievements.
    Quests,
    /// Exploration achievements.
    Exploration,
    /// Social achievements.
    Social,
    /// Collection achievements.
    Collection,
    /// Miscellaneous achievements.
    Miscellaneous,
}

impl AchievementCategory {
    /// Get display name.
    pub fn display_name(&self) -> &'static str {
        match self {
            AchievementCategory::Combat => "Combat",
            AchievementCategory::Skilling => "Skilling",
            AchievementCategory::Quests => "Quests",
            AchievementCategory::Exploration => "Exploration",
            AchievementCategory::Social => "Social",
            AchievementCategory::Collection => "Collection",
            AchievementCategory::Miscellaneous => "Miscellaneous",
        }
    }
}

/// Achievement difficulty/tier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum AchievementTier {
    /// Easy achievements.
    Easy,
    /// Medium achievements.
    Medium,
    /// Hard achievements.
    Hard,
    /// Elite achievements.
    Elite,
    /// Master achievements.
    Master,
}

impl AchievementTier {
    /// Get display name.
    pub fn display_name(&self) -> &'static str {
        match self {
            AchievementTier::Easy => "Easy",
            AchievementTier::Medium => "Medium",
            AchievementTier::Hard => "Hard",
            AchievementTier::Elite => "Elite",
            AchievementTier::Master => "Master",
        }
    }

    /// Get point value.
    pub fn points(&self) -> u32 {
        match self {
            AchievementTier::Easy => 10,
            AchievementTier::Medium => 25,
            AchievementTier::Hard => 50,
            AchievementTier::Elite => 100,
            AchievementTier::Master => 200,
        }
    }
}

/// Achievement requirement types.
#[derive(Debug, Clone)]
pub enum AchievementRequirement {
    /// Reach a skill level.
    SkillLevel { skill_id: u8, level: u8 },
    /// Gain total experience.
    TotalExperience(u64),
    /// Complete a quest.
    QuestComplete(u16),
    /// Kill a specific NPC.
    KillNpc { npc_id: u32, count: u32 },
    /// Kill any NPC (total count).
    KillCount(u32),
    /// Collect an item.
    CollectItem { item_id: u32, count: u32 },
    /// Reach a location.
    VisitLocation { x: u16, y: u16 },
    /// Reach combat level.
    CombatLevel(u8),
    /// Reach total level.
    TotalLevel(u16),
    /// Complete another achievement.
    CompleteAchievement(u32),
    /// Play for a certain time (seconds).
    PlayTime(u64),
    /// Custom requirement (checked via callback).
    Custom(String),
}

/// Achievement definition.
#[derive(Debug, Clone)]
pub struct Achievement {
    /// Unique achievement ID.
    pub id: u32,
    /// Achievement name.
    pub name: String,
    /// Description.
    pub description: String,
    /// Category.
    pub category: AchievementCategory,
    /// Difficulty tier.
    pub tier: AchievementTier,
    /// Requirements to complete.
    pub requirements: Vec<AchievementRequirement>,
    /// Is this a hidden/secret achievement?
    pub hidden: bool,
    /// Reward item ID (if any).
    pub reward_item: Option<u32>,
    /// Reward experience (skill_id, amount).
    pub reward_experience: Option<(u8, u32)>,
    /// Reward points.
    pub reward_points: u32,
}

impl Achievement {
    /// Create a new achievement.
    pub fn new(
        id: u32,
        name: String,
        description: String,
        category: AchievementCategory,
        tier: AchievementTier,
    ) -> Self {
        Self {
            id,
            name,
            description,
            category,
            tier,
            requirements: Vec::new(),
            hidden: false,
            reward_item: None,
            reward_experience: None,
            reward_points: tier.points(),
        }
    }

    /// Add a requirement.
    pub fn with_requirement(mut self, req: AchievementRequirement) -> Self {
        self.requirements.push(req);
        self
    }

    /// Set as hidden.
    pub fn hidden(mut self) -> Self {
        self.hidden = true;
        self
    }

    /// Set reward item.
    pub fn with_reward_item(mut self, item_id: u32) -> Self {
        self.reward_item = Some(item_id);
        self
    }

    /// Set reward experience.
    pub fn with_reward_experience(mut self, skill_id: u8, amount: u32) -> Self {
        self.reward_experience = Some((skill_id, amount));
        self
    }

    /// Set reward points.
    pub fn with_reward_points(mut self, points: u32) -> Self {
        self.reward_points = points;
        self
    }
}

/// Player's achievement progress.
#[derive(Debug, Clone)]
pub struct AchievementProgress {
    /// Achievement ID.
    pub achievement_id: u32,
    /// Progress for each requirement (index -> progress value).
    pub progress: HashMap<usize, u64>,
    /// Is completed.
    pub completed: bool,
    /// Completion timestamp.
    pub completed_at: Option<u64>,
}

impl AchievementProgress {
    /// Create new progress tracking.
    pub fn new(achievement_id: u32) -> Self {
        Self {
            achievement_id,
            progress: HashMap::new(),
            completed: false,
            completed_at: None,
        }
    }

    /// Get progress for a requirement.
    pub fn get_progress(&self, req_index: usize) -> u64 {
        self.progress.get(&req_index).copied().unwrap_or(0)
    }

    /// Set progress for a requirement.
    pub fn set_progress(&mut self, req_index: usize, value: u64) {
        self.progress.insert(req_index, value);
    }

    /// Increment progress for a requirement.
    pub fn increment_progress(&mut self, req_index: usize, amount: u64) -> u64 {
        let current = self.get_progress(req_index);
        let new_value = current + amount;
        self.set_progress(req_index, new_value);
        new_value
    }
}

/// Player's achievement data.
#[derive(Debug, Default)]
pub struct PlayerAchievements {
    /// Completed achievement IDs.
    completed: HashSet<u32>,
    /// Progress for in-progress achievements.
    progress: HashMap<u32, AchievementProgress>,
    /// Total achievement points.
    total_points: u32,
    /// Achievements completed by category.
    by_category: HashMap<AchievementCategory, u32>,
}

impl PlayerAchievements {
    /// Create new player achievements.
    pub fn new() -> Self {
        Self::default()
    }

    /// Check if achievement is completed.
    pub fn is_completed(&self, achievement_id: u32) -> bool {
        self.completed.contains(&achievement_id)
    }

    /// Get progress for an achievement.
    pub fn get_progress(&self, achievement_id: u32) -> Option<&AchievementProgress> {
        self.progress.get(&achievement_id)
    }

    /// Get mutable progress for an achievement.
    pub fn get_progress_mut(&mut self, achievement_id: u32) -> &mut AchievementProgress {
        self.progress
            .entry(achievement_id)
            .or_insert_with(|| AchievementProgress::new(achievement_id))
    }

    /// Mark achievement as completed.
    pub fn complete(&mut self, achievement: &Achievement) {
        if self.completed.insert(achievement.id) {
            self.total_points += achievement.reward_points;
            *self.by_category.entry(achievement.category).or_insert(0) += 1;

            // Update progress
            if let Some(progress) = self.progress.get_mut(&achievement.id) {
                progress.completed = true;
                progress.completed_at = Some(
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_secs(),
                );
            }
        }
    }

    /// Get total points.
    pub fn total_points(&self) -> u32 {
        self.total_points
    }

    /// Get completed count.
    pub fn completed_count(&self) -> usize {
        self.completed.len()
    }

    /// Get completed count by category.
    pub fn completed_in_category(&self, category: AchievementCategory) -> u32 {
        self.by_category.get(&category).copied().unwrap_or(0)
    }

    /// Get all completed achievement IDs.
    pub fn completed_ids(&self) -> impl Iterator<Item = &u32> {
        self.completed.iter()
    }
}

/// Achievement manager.
#[derive(Debug, Default)]
pub struct AchievementManager {
    /// All achievements by ID.
    achievements: HashMap<u32, Achievement>,
    /// Achievements by category.
    by_category: HashMap<AchievementCategory, Vec<u32>>,
    /// Total possible points.
    total_possible_points: u32,
}

impl AchievementManager {
    /// Create a new achievement manager.
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.load_defaults();
        manager
    }

    /// Load default achievements.
    pub fn load_defaults(&mut self) {
        // Combat achievements
        self.register(
            Achievement::new(
                1,
                "First Blood".to_string(),
                "Defeat your first enemy".to_string(),
                AchievementCategory::Combat,
                AchievementTier::Easy,
            )
            .with_requirement(AchievementRequirement::KillCount(1)),
        );

        self.register(
            Achievement::new(
                2,
                "Warrior".to_string(),
                "Defeat 100 enemies".to_string(),
                AchievementCategory::Combat,
                AchievementTier::Medium,
            )
            .with_requirement(AchievementRequirement::KillCount(100)),
        );

        self.register(
            Achievement::new(
                3,
                "Champion".to_string(),
                "Reach combat level 50".to_string(),
                AchievementCategory::Combat,
                AchievementTier::Medium,
            )
            .with_requirement(AchievementRequirement::CombatLevel(50)),
        );

        self.register(
            Achievement::new(
                4,
                "Legendary Fighter".to_string(),
                "Reach combat level 100".to_string(),
                AchievementCategory::Combat,
                AchievementTier::Hard,
            )
            .with_requirement(AchievementRequirement::CombatLevel(100)),
        );

        // Skilling achievements
        self.register(
            Achievement::new(
                10,
                "Apprentice".to_string(),
                "Reach level 10 in any skill".to_string(),
                AchievementCategory::Skilling,
                AchievementTier::Easy,
            )
            .with_requirement(AchievementRequirement::Custom("any_skill_10".to_string())),
        );

        self.register(
            Achievement::new(
                11,
                "Journeyman".to_string(),
                "Reach level 50 in any skill".to_string(),
                AchievementCategory::Skilling,
                AchievementTier::Medium,
            )
            .with_requirement(AchievementRequirement::Custom("any_skill_50".to_string())),
        );

        self.register(
            Achievement::new(
                12,
                "Expert".to_string(),
                "Reach level 75 in any skill".to_string(),
                AchievementCategory::Skilling,
                AchievementTier::Hard,
            )
            .with_requirement(AchievementRequirement::Custom("any_skill_75".to_string())),
        );

        self.register(
            Achievement::new(
                13,
                "Master".to_string(),
                "Reach level 99 in any skill".to_string(),
                AchievementCategory::Skilling,
                AchievementTier::Elite,
            )
            .with_requirement(AchievementRequirement::Custom("any_skill_99".to_string())),
        );

        self.register(
            Achievement::new(
                14,
                "Total Dedication".to_string(),
                "Reach 500 total level".to_string(),
                AchievementCategory::Skilling,
                AchievementTier::Medium,
            )
            .with_requirement(AchievementRequirement::TotalLevel(500)),
        );

        self.register(
            Achievement::new(
                15,
                "Well Rounded".to_string(),
                "Reach 1000 total level".to_string(),
                AchievementCategory::Skilling,
                AchievementTier::Hard,
            )
            .with_requirement(AchievementRequirement::TotalLevel(1000)),
        );

        // Quest achievements
        self.register(
            Achievement::new(
                20,
                "Adventurer".to_string(),
                "Complete your first quest".to_string(),
                AchievementCategory::Quests,
                AchievementTier::Easy,
            )
            .with_requirement(AchievementRequirement::Custom("any_quest".to_string())),
        );

        // Exploration achievements
        self.register(
            Achievement::new(
                30,
                "Explorer".to_string(),
                "Visit all major cities".to_string(),
                AchievementCategory::Exploration,
                AchievementTier::Medium,
            )
            .with_requirement(AchievementRequirement::Custom("all_cities".to_string())),
        );

        // Social achievements
        self.register(
            Achievement::new(
                40,
                "Friendly".to_string(),
                "Add your first friend".to_string(),
                AchievementCategory::Social,
                AchievementTier::Easy,
            )
            .with_requirement(AchievementRequirement::Custom("first_friend".to_string())),
        );

        // Collection achievements
        self.register(
            Achievement::new(
                50,
                "Collector".to_string(),
                "Own 1,000,000 gold".to_string(),
                AchievementCategory::Collection,
                AchievementTier::Medium,
            )
            .with_requirement(AchievementRequirement::CollectItem {
                item_id: 10, // Coins
                count: 1_000_000,
            }),
        );

        // Miscellaneous achievements
        self.register(
            Achievement::new(
                60,
                "Dedicated".to_string(),
                "Play for 24 hours".to_string(),
                AchievementCategory::Miscellaneous,
                AchievementTier::Medium,
            )
            .with_requirement(AchievementRequirement::PlayTime(86400)),
        );

        info!(
            "Loaded {} achievements ({} total points)",
            self.achievements.len(),
            self.total_possible_points
        );
    }

    /// Register an achievement.
    pub fn register(&mut self, achievement: Achievement) {
        let id = achievement.id;
        let category = achievement.category;
        let points = achievement.reward_points;

        self.total_possible_points += points;
        self.by_category.entry(category).or_default().push(id);
        self.achievements.insert(id, achievement);
    }

    /// Get achievement by ID.
    pub fn get(&self, id: u32) -> Option<&Achievement> {
        self.achievements.get(&id)
    }

    /// Get achievements by category.
    pub fn get_by_category(&self, category: AchievementCategory) -> Vec<&Achievement> {
        self.by_category
            .get(&category)
            .map(|ids| ids.iter().filter_map(|id| self.achievements.get(id)).collect())
            .unwrap_or_default()
    }

    /// Get all achievements.
    pub fn all(&self) -> impl Iterator<Item = &Achievement> {
        self.achievements.values()
    }

    /// Get total achievement count.
    pub fn count(&self) -> usize {
        self.achievements.len()
    }

    /// Get total possible points.
    pub fn total_possible_points(&self) -> u32 {
        self.total_possible_points
    }

    /// Check if a player meets the requirements for an achievement.
    pub fn check_requirements(
        &self,
        achievement_id: u32,
        player_achievements: &PlayerAchievements,
        player_stats: &PlayerStats,
    ) -> bool {
        let achievement = match self.get(achievement_id) {
            Some(a) => a,
            None => return false,
        };

        for (i, req) in achievement.requirements.iter().enumerate() {
            let progress = player_achievements
                .get_progress(achievement_id)
                .map(|p| p.get_progress(i))
                .unwrap_or(0);

            let met = match req {
                AchievementRequirement::SkillLevel { skill_id, level } => {
                    player_stats.get_skill_level(*skill_id) >= *level
                }
                AchievementRequirement::TotalExperience(xp) => player_stats.total_experience >= *xp,
                AchievementRequirement::QuestComplete(quest_id) => {
                    player_stats.completed_quests.contains(quest_id)
                }
                AchievementRequirement::KillNpc { count, .. } => progress >= *count as u64,
                AchievementRequirement::KillCount(count) => progress >= *count as u64,
                AchievementRequirement::CollectItem { count, .. } => progress >= *count as u64,
                AchievementRequirement::VisitLocation { .. } => progress > 0,
                AchievementRequirement::CombatLevel(level) => player_stats.combat_level >= *level,
                AchievementRequirement::TotalLevel(level) => player_stats.total_level >= *level,
                AchievementRequirement::CompleteAchievement(ach_id) => {
                    player_achievements.is_completed(*ach_id)
                }
                AchievementRequirement::PlayTime(seconds) => player_stats.play_time >= *seconds,
                AchievementRequirement::Custom(_) => {
                    // Custom requirements need external checking
                    progress > 0
                }
            };

            if !met {
                return false;
            }
        }

        true
    }
}

/// Player stats for achievement checking.
#[derive(Debug, Default)]
pub struct PlayerStats {
    /// Skill levels.
    pub skill_levels: HashMap<u8, u8>,
    /// Total experience.
    pub total_experience: u64,
    /// Combat level.
    pub combat_level: u8,
    /// Total level.
    pub total_level: u16,
    /// Play time in seconds.
    pub play_time: u64,
    /// Completed quest IDs.
    pub completed_quests: HashSet<u16>,
}

impl PlayerStats {
    /// Get skill level.
    pub fn get_skill_level(&self, skill_id: u8) -> u8 {
        self.skill_levels.get(&skill_id).copied().unwrap_or(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_achievement_creation() {
        let achievement = Achievement::new(
            1,
            "Test".to_string(),
            "Test achievement".to_string(),
            AchievementCategory::Combat,
            AchievementTier::Easy,
        )
        .with_requirement(AchievementRequirement::KillCount(10))
        .with_reward_points(50);

        assert_eq!(achievement.id, 1);
        assert_eq!(achievement.requirements.len(), 1);
        assert_eq!(achievement.reward_points, 50);
    }

    #[test]
    fn test_player_achievements() {
        let mut player_ach = PlayerAchievements::new();

        assert!(!player_ach.is_completed(1));

        let achievement = Achievement::new(
            1,
            "Test".to_string(),
            "Test".to_string(),
            AchievementCategory::Combat,
            AchievementTier::Easy,
        );

        player_ach.complete(&achievement);

        assert!(player_ach.is_completed(1));
        assert_eq!(player_ach.total_points(), 10);
        assert_eq!(player_ach.completed_count(), 1);
    }

    #[test]
    fn test_achievement_manager() {
        let manager = AchievementManager::new();

        assert!(manager.count() > 0);
        assert!(manager.get(1).is_some());
        assert!(manager.total_possible_points() > 0);
    }

    #[test]
    fn test_achievement_tiers() {
        assert!(AchievementTier::Master > AchievementTier::Elite);
        assert!(AchievementTier::Elite > AchievementTier::Hard);
        assert_eq!(AchievementTier::Easy.points(), 10);
        assert_eq!(AchievementTier::Master.points(), 200);
    }
}
