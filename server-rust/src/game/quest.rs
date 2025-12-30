//! Quest system for tracking player progress through quests.
//! Handles quest definitions, stages, requirements, and rewards.

use std::collections::HashMap;
use tracing::{debug, info};

use super::item::ItemId;
use super::skills::SkillType;

/// Quest stage type.
pub type QuestStage = u8;

/// Quest completion states.
pub const QUEST_NOT_STARTED: QuestStage = 0;
pub const QUEST_COMPLETE: QuestStage = u8::MAX;

/// Requirement types for quests.
#[derive(Debug, Clone)]
pub enum QuestRequirement {
    /// Requires a skill at a certain level.
    SkillLevel { skill: SkillType, level: u8 },
    /// Requires another quest to be complete.
    QuestComplete { quest_id: u32 },
    /// Requires an item in inventory.
    HasItem { item_id: ItemId, amount: u32 },
    /// Requires combat level.
    CombatLevel { level: u8 },
    /// Requires quest points.
    QuestPoints { points: u32 },
}

/// Reward types for completing quests.
#[derive(Debug, Clone)]
pub enum QuestReward {
    /// Experience in a skill.
    Experience { skill: SkillType, amount: u32 },
    /// Quest points.
    QuestPoints(u32),
    /// An item reward.
    Item { item_id: ItemId, amount: u32 },
    /// Coins reward.
    Coins(u32),
    /// Unlocks access to an area.
    AreaAccess(String),
    /// Unlocks ability to use something.
    Unlock(String),
}

/// Quest difficulty rating.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QuestDifficulty {
    Novice,
    Intermediate,
    Experienced,
    Master,
    Grandmaster,
}

impl QuestDifficulty {
    /// Get display name.
    pub fn name(&self) -> &'static str {
        match self {
            QuestDifficulty::Novice => "Novice",
            QuestDifficulty::Intermediate => "Intermediate",
            QuestDifficulty::Experienced => "Experienced",
            QuestDifficulty::Master => "Master",
            QuestDifficulty::Grandmaster => "Grandmaster",
        }
    }
}

/// Quest definition.
#[derive(Debug, Clone)]
pub struct QuestDef {
    /// Unique quest ID.
    pub id: u32,
    /// Quest name.
    pub name: String,
    /// Short description.
    pub description: String,
    /// Difficulty rating.
    pub difficulty: QuestDifficulty,
    /// Whether this is a members-only quest.
    pub members_only: bool,
    /// Requirements to start the quest.
    pub requirements: Vec<QuestRequirement>,
    /// Rewards for completing the quest.
    pub rewards: Vec<QuestReward>,
    /// Quest point value.
    pub quest_points: u32,
    /// Total number of stages (not including complete).
    pub total_stages: u8,
    /// Starting NPC or location hint.
    pub start_hint: String,
}

impl QuestDef {
    /// Create a new quest definition builder.
    pub fn builder(id: u32, name: &str) -> QuestDefBuilder {
        QuestDefBuilder::new(id, name)
    }
}

/// Builder for quest definitions.
pub struct QuestDefBuilder {
    def: QuestDef,
}

impl QuestDefBuilder {
    pub fn new(id: u32, name: &str) -> Self {
        Self {
            def: QuestDef {
                id,
                name: name.to_string(),
                description: String::new(),
                difficulty: QuestDifficulty::Novice,
                members_only: false,
                requirements: Vec::new(),
                rewards: Vec::new(),
                quest_points: 1,
                total_stages: 1,
                start_hint: String::new(),
            },
        }
    }

    pub fn description(mut self, desc: &str) -> Self {
        self.def.description = desc.to_string();
        self
    }

    pub fn difficulty(mut self, diff: QuestDifficulty) -> Self {
        self.def.difficulty = diff;
        self
    }

    pub fn members_only(mut self) -> Self {
        self.def.members_only = true;
        self
    }

    pub fn requires_skill(mut self, skill: SkillType, level: u8) -> Self {
        self.def.requirements.push(QuestRequirement::SkillLevel { skill, level });
        self
    }

    pub fn requires_quest(mut self, quest_id: u32) -> Self {
        self.def.requirements.push(QuestRequirement::QuestComplete { quest_id });
        self
    }

    pub fn requires_item(mut self, item_id: ItemId, amount: u32) -> Self {
        self.def.requirements.push(QuestRequirement::HasItem { item_id, amount });
        self
    }

    pub fn reward_xp(mut self, skill: SkillType, amount: u32) -> Self {
        self.def.rewards.push(QuestReward::Experience { skill, amount });
        self
    }

    pub fn reward_item(mut self, item_id: ItemId, amount: u32) -> Self {
        self.def.rewards.push(QuestReward::Item { item_id, amount });
        self
    }

    pub fn reward_coins(mut self, amount: u32) -> Self {
        self.def.rewards.push(QuestReward::Coins(amount));
        self
    }

    pub fn quest_points(mut self, points: u32) -> Self {
        self.def.quest_points = points;
        self.def.rewards.push(QuestReward::QuestPoints(points));
        self
    }

    pub fn stages(mut self, count: u8) -> Self {
        self.def.total_stages = count;
        self
    }

    pub fn start_hint(mut self, hint: &str) -> Self {
        self.def.start_hint = hint.to_string();
        self
    }

    pub fn build(self) -> QuestDef {
        self.def
    }
}

/// Player's quest progress.
#[derive(Debug, Clone, Default)]
pub struct QuestProgress {
    /// Quest stages by quest ID.
    stages: HashMap<u32, QuestStage>,
    /// Total quest points earned.
    quest_points: u32,
}

impl QuestProgress {
    /// Create new quest progress.
    pub fn new() -> Self {
        Self::default()
    }

    /// Get stage for a quest.
    pub fn get_stage(&self, quest_id: u32) -> QuestStage {
        *self.stages.get(&quest_id).unwrap_or(&QUEST_NOT_STARTED)
    }

    /// Set stage for a quest.
    pub fn set_stage(&mut self, quest_id: u32, stage: QuestStage) {
        self.stages.insert(quest_id, stage);
        debug!("Set quest {} stage to {}", quest_id, stage);
    }

    /// Advance to next stage.
    pub fn advance_stage(&mut self, quest_id: u32) {
        let current = self.get_stage(quest_id);
        if current < QUEST_COMPLETE - 1 {
            self.set_stage(quest_id, current + 1);
        }
    }

    /// Check if quest is started.
    pub fn is_started(&self, quest_id: u32) -> bool {
        self.get_stage(quest_id) > QUEST_NOT_STARTED
    }

    /// Check if quest is complete.
    pub fn is_complete(&self, quest_id: u32) -> bool {
        self.get_stage(quest_id) == QUEST_COMPLETE
    }

    /// Complete a quest.
    pub fn complete(&mut self, quest_id: u32, points: u32) {
        self.set_stage(quest_id, QUEST_COMPLETE);
        self.quest_points += points;
        info!(
            "Quest {} completed, total quest points: {}",
            quest_id, self.quest_points
        );
    }

    /// Get total quest points.
    pub fn quest_points(&self) -> u32 {
        self.quest_points
    }

    /// Get count of completed quests.
    pub fn completed_count(&self) -> usize {
        self.stages
            .values()
            .filter(|&&s| s == QUEST_COMPLETE)
            .count()
    }

    /// Get count of started (in progress) quests.
    pub fn in_progress_count(&self) -> usize {
        self.stages
            .values()
            .filter(|&&s| s > QUEST_NOT_STARTED && s < QUEST_COMPLETE)
            .count()
    }
}

/// Quest repository containing all quest definitions.
#[derive(Debug, Default)]
pub struct QuestRepository {
    quests: HashMap<u32, QuestDef>,
}

impl QuestRepository {
    /// Create a new quest repository.
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a quest.
    pub fn add(&mut self, quest: QuestDef) {
        self.quests.insert(quest.id, quest);
    }

    /// Get a quest by ID.
    pub fn get(&self, id: u32) -> Option<&QuestDef> {
        self.quests.get(&id)
    }

    /// Get all quests.
    pub fn all(&self) -> impl Iterator<Item = &QuestDef> {
        self.quests.values()
    }

    /// Get free quests only.
    pub fn free_quests(&self) -> impl Iterator<Item = &QuestDef> {
        self.quests.values().filter(|q| !q.members_only)
    }

    /// Get members quests only.
    pub fn members_quests(&self) -> impl Iterator<Item = &QuestDef> {
        self.quests.values().filter(|q| q.members_only)
    }

    /// Load default RSC quests.
    pub fn load_defaults(&mut self) {
        // Free-to-play quests
        self.add(
            QuestDef::builder(0, "Cook's Assistant")
                .description("The Lumbridge Castle cook needs your help.")
                .difficulty(QuestDifficulty::Novice)
                .stages(3)
                .quest_points(1)
                .reward_xp(SkillType::Cooking, 300)
                .start_hint("Talk to the Cook in Lumbridge Castle")
                .build(),
        );

        self.add(
            QuestDef::builder(1, "Sheep Shearer")
                .description("Fred the Farmer needs wool for his wife.")
                .difficulty(QuestDifficulty::Novice)
                .stages(2)
                .quest_points(1)
                .reward_coins(60)
                .start_hint("Talk to Fred the Farmer north of Lumbridge")
                .build(),
        );

        self.add(
            QuestDef::builder(2, "The Restless Ghost")
                .description("A ghost is haunting Lumbridge Graveyard.")
                .difficulty(QuestDifficulty::Novice)
                .stages(4)
                .quest_points(1)
                .reward_xp(SkillType::Prayer, 1125)
                .start_hint("Talk to Father Aereck in the Lumbridge church")
                .build(),
        );

        self.add(
            QuestDef::builder(3, "Romeo and Juliet")
                .description("Help Romeo find his beloved Juliet.")
                .difficulty(QuestDifficulty::Novice)
                .stages(6)
                .quest_points(5)
                .start_hint("Talk to Romeo in Varrock Square")
                .build(),
        );

        self.add(
            QuestDef::builder(4, "Doric's Quest")
                .description("Doric the dwarf needs some materials.")
                .difficulty(QuestDifficulty::Novice)
                .stages(2)
                .quest_points(1)
                .reward_xp(SkillType::Mining, 1300)
                .start_hint("Talk to Doric north of Falador")
                .build(),
        );

        self.add(
            QuestDef::builder(5, "Imp Catcher")
                .description("Wizard Mizgog needs his beads back.")
                .difficulty(QuestDifficulty::Novice)
                .stages(2)
                .quest_points(1)
                .reward_xp(SkillType::Magic, 875)
                .start_hint("Talk to Wizard Mizgog in the Wizards' Tower")
                .build(),
        );

        self.add(
            QuestDef::builder(6, "Witch's Potion")
                .description("Help the witch brew a potion.")
                .difficulty(QuestDifficulty::Novice)
                .stages(3)
                .quest_points(1)
                .reward_xp(SkillType::Magic, 325)
                .start_hint("Talk to the Witch in Rimmington")
                .build(),
        );

        self.add(
            QuestDef::builder(7, "Ernest the Chicken")
                .description("Ernest has been turned into a chicken!")
                .difficulty(QuestDifficulty::Novice)
                .stages(5)
                .quest_points(4)
                .reward_coins(300)
                .start_hint("Talk to Veronica outside Draynor Manor")
                .build(),
        );

        self.add(
            QuestDef::builder(8, "Vampire Slayer")
                .description("Slay the vampire terrorizing Draynor Village.")
                .difficulty(QuestDifficulty::Intermediate)
                .stages(4)
                .quest_points(3)
                .reward_xp(SkillType::Attack, 4825)
                .start_hint("Talk to Morgan in Draynor Village")
                .build(),
        );

        self.add(
            QuestDef::builder(9, "Demon Slayer")
                .description("Stop Delrith from destroying Varrock.")
                .difficulty(QuestDifficulty::Intermediate)
                .stages(5)
                .quest_points(3)
                .start_hint("Talk to the Gypsy in Varrock Square")
                .build(),
        );

        self.add(
            QuestDef::builder(10, "Dragon Slayer")
                .description("Prove yourself worthy by slaying Elvarg.")
                .difficulty(QuestDifficulty::Experienced)
                .requires_skill(SkillType::Smithing, 32)
                .stages(8)
                .quest_points(2)
                .reward_xp(SkillType::Strength, 18650)
                .reward_xp(SkillType::Defence, 18650)
                .start_hint("Talk to the Guildmaster in the Champions' Guild")
                .build(),
        );

        // Members quests
        self.add(
            QuestDef::builder(11, "Druidic Ritual")
                .description("Help the druids perform their ritual.")
                .difficulty(QuestDifficulty::Novice)
                .members_only()
                .stages(3)
                .quest_points(4)
                .reward_xp(SkillType::Herblore, 250)
                .start_hint("Talk to Kaqemeex in Taverley")
                .build(),
        );

        self.add(
            QuestDef::builder(12, "Lost City")
                .description("Find the entrance to Zanaris.")
                .difficulty(QuestDifficulty::Experienced)
                .members_only()
                .requires_skill(SkillType::Woodcutting, 36)
                .requires_skill(SkillType::Crafting, 31)
                .stages(5)
                .quest_points(3)
                .start_hint("Talk to the adventurers in the Lumbridge Swamp")
                .build(),
        );

        self.add(
            QuestDef::builder(13, "Hero's Quest")
                .description("Prove you are a true hero.")
                .difficulty(QuestDifficulty::Master)
                .members_only()
                .requires_skill(SkillType::Mining, 50)
                .requires_skill(SkillType::Fishing, 53)
                .requires_skill(SkillType::Cooking, 53)
                .requires_skill(SkillType::Herblore, 25)
                .requires_quest(10) // Dragon Slayer
                .requires_quest(12) // Lost City
                .stages(6)
                .quest_points(1)
                .reward_xp(SkillType::Attack, 3075)
                .reward_xp(SkillType::Defence, 3075)
                .reward_xp(SkillType::Strength, 3075)
                .reward_xp(SkillType::Hits, 3075)
                .start_hint("Talk to Achilles in the Hero's Guild")
                .build(),
        );

        info!("Loaded {} quests", self.quests.len());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_quest_progress() {
        let mut progress = QuestProgress::new();

        assert!(!progress.is_started(0));
        assert!(!progress.is_complete(0));

        // Start quest
        progress.set_stage(0, 1);
        assert!(progress.is_started(0));
        assert!(!progress.is_complete(0));

        // Complete quest
        progress.complete(0, 1);
        assert!(progress.is_complete(0));
        assert_eq!(progress.quest_points(), 1);
        assert_eq!(progress.completed_count(), 1);
    }

    #[test]
    fn test_quest_repository() {
        let mut repo = QuestRepository::new();
        repo.load_defaults();

        // Should have loaded some quests
        assert!(repo.get(0).is_some()); // Cook's Assistant

        // Check free vs members
        let free_count = repo.free_quests().count();
        let members_count = repo.members_quests().count();
        assert!(free_count > 0);
        assert!(members_count > 0);
    }
}
