//! Quest engine for wiring the quest system into the game loop.
//! Handles quest state management, trigger dispatching, requirement checking,
//! and packet building for quest-related client updates.

use std::collections::HashMap;

use tracing::{debug, info, warn};

use super::entity::Position;
use super::player::SkillId;
use super::quest::{QuestDef, QuestRepository, QuestRequirement, QuestReward};
use crate::protocol::opcodes::OpcodeOut;
use crate::protocol::{Packet, PacketBuilder};

// ---------------------------------------------------------------------------
// QuestState – per-player, per-quest progress snapshot
// ---------------------------------------------------------------------------

/// Snapshot of a single quest's state for a player.
///
/// Stage encoding follows the RSC convention:
///   0   = not started
///   255 = completed (mapped from `QUEST_COMPLETE`)
///   1-254 = in-progress stages
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct QuestState {
    /// Current stage of the quest.
    pub stage: i32,
}

impl QuestState {
    /// Quest has not been started.
    pub const NOT_STARTED: i32 = 0;
    /// Quest is complete.
    pub const COMPLETED: i32 = -1;

    pub fn not_started() -> Self {
        Self { stage: Self::NOT_STARTED }
    }

    pub fn completed() -> Self {
        Self { stage: Self::COMPLETED }
    }

    pub fn in_progress(stage: i32) -> Self {
        assert!(stage >= 1 && stage <= 254, "in-progress stage must be 1..=254");
        Self { stage }
    }

    pub fn is_not_started(&self) -> bool {
        self.stage == Self::NOT_STARTED
    }

    pub fn is_completed(&self) -> bool {
        self.stage == Self::COMPLETED
    }

    pub fn is_in_progress(&self) -> bool {
        self.stage > 0 && self.stage <= 254
    }
}

impl Default for QuestState {
    fn default() -> Self {
        Self::not_started()
    }
}

// ---------------------------------------------------------------------------
// QuestDefinition – enriched definition used by the engine
// ---------------------------------------------------------------------------

/// Engine-level quest definition that augments `QuestDef` from the quest
/// module with typed requirement / reward structures suitable for runtime
/// evaluation.
#[derive(Debug, Clone)]
pub struct QuestDefinition {
    pub id: u32,
    pub name: String,
    pub description: String,
    pub requirements: Vec<QuestRequirementEntry>,
    pub rewards: QuestRewardInfo,
    pub quest_points: u32,
}

impl QuestDefinition {
    /// Build a `QuestDefinition` from the lower-level `QuestDef`.
    pub fn from_quest_def(def: &QuestDef) -> Self {
        let mut requirements = Vec::new();
        for req in &def.requirements {
            match req {
                QuestRequirement::SkillLevel { skill, level } => {
                    requirements.push(QuestRequirementEntry::SkillLevel(skill_type_to_id(*skill), *level));
                }
                QuestRequirement::QuestComplete { quest_id } => {
                    requirements.push(QuestRequirementEntry::QuestComplete(*quest_id));
                }
                QuestRequirement::CombatLevel { level } => {
                    requirements.push(QuestRequirementEntry::CombatLevel(*level as u32));
                }
                QuestRequirement::QuestPoints { points } => {
                    requirements.push(QuestRequirementEntry::QuestPoints(*points));
                }
                QuestRequirement::HasItem { .. } => {
                    // Item requirements are checked at runtime via inventory, not pre-reqs
                }
            }
        }

        let mut xp_rewards = Vec::new();
        let mut item_rewards = Vec::new();
        let mut coins: u32 = 0;
        let mut qp: u32 = 0;

        for reward in &def.rewards {
            match reward {
                QuestReward::Experience { skill, amount } => {
                    xp_rewards.push((skill_type_to_id(*skill), *amount));
                }
                QuestReward::Item { item_id, amount } => {
                    item_rewards.push((item_id.0, *amount));
                }
                QuestReward::Coins(amount) => {
                    coins += amount;
                }
                QuestReward::QuestPoints(points) => {
                    qp = *points;
                }
                _ => {}
            }
        }

        Self {
            id: def.id,
            name: def.name.clone(),
            description: def.description.clone(),
            requirements,
            rewards: QuestRewardInfo {
                xp_rewards,
                item_rewards,
                quest_points: qp,
                coins,
            },
            quest_points: def.quest_points,
        }
    }
}

// ---------------------------------------------------------------------------
// QuestRequirementEntry – typed requirement enum for the engine
// ---------------------------------------------------------------------------

/// Typed quest requirement for runtime evaluation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QuestRequirementEntry {
    /// Requires a skill at a minimum level.
    SkillLevel(SkillId, u8),
    /// Requires another quest to be completed.
    QuestComplete(u32),
    /// Requires a minimum combat level.
    CombatLevel(u32),
    /// Requires a minimum number of quest points.
    QuestPoints(u32),
}

// ---------------------------------------------------------------------------
// QuestRewardInfo – aggregated reward structure
// ---------------------------------------------------------------------------

/// Aggregated rewards for completing a quest.
#[derive(Debug, Clone, Default)]
pub struct QuestRewardInfo {
    /// Experience rewards as `(skill_id, amount)` pairs.
    pub xp_rewards: Vec<(SkillId, u32)>,
    /// Item rewards as `(item_id, amount)` pairs.
    pub item_rewards: Vec<(u32, u32)>,
    /// Quest points awarded.
    pub quest_points: u32,
    /// Coins awarded.
    pub coins: u32,
}

// ---------------------------------------------------------------------------
// RequirementResult
// ---------------------------------------------------------------------------

/// Result of checking quest requirements for a player.
#[derive(Debug, Clone)]
pub struct RequirementResult {
    /// Whether all requirements are met.
    pub met: bool,
    /// Human-readable descriptions of unmet requirements.
    pub unmet_requirements: Vec<String>,
}

impl RequirementResult {
    pub fn all_met() -> Self {
        Self {
            met: true,
            unmet_requirements: Vec::new(),
        }
    }
}

// ---------------------------------------------------------------------------
// QuestTrigger – event-based quest advancement
// ---------------------------------------------------------------------------

/// Events that can advance quest progress.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum QuestTrigger {
    /// Player talks to an NPC (npc_id).
    TalkToNpc(u32),
    /// Player uses an item (item_id).
    UseItem(u32),
    /// Player enters an area (center, radius).
    EnterArea(Position, i32),
    /// Player kills an NPC (npc_id).
    KillNpc(u32),
    /// Player uses a game object (object_id).
    UseObjectQuest(u32),
}

// ---------------------------------------------------------------------------
// QuestManager
// ---------------------------------------------------------------------------

/// Central quest manager that wires quests into the game loop.
///
/// Maintains per-player quest state, evaluates requirements, dispatches
/// triggers, and builds outgoing packets.
#[derive(Debug)]
pub struct QuestManager {
    /// Per-player quest states: `player_id -> quest_id -> QuestState`.
    player_quests: HashMap<u64, HashMap<u32, QuestState>>,
    /// Engine-level quest definitions indexed by quest ID.
    quest_definitions: HashMap<u32, QuestDefinition>,
    /// Trigger handlers: trigger -> list of `(quest_id, required_stage)`.
    trigger_handlers: HashMap<QuestTrigger, Vec<(u32, i32)>>,
}

impl QuestManager {
    /// Create a new, empty quest manager.
    pub fn new() -> Self {
        Self {
            player_quests: HashMap::new(),
            quest_definitions: HashMap::new(),
            trigger_handlers: HashMap::new(),
        }
    }

    /// Load quest definitions from a `QuestRepository`.
    pub fn load_from_repository(&mut self, repo: &QuestRepository) {
        for def in repo.all() {
            let engine_def = QuestDefinition::from_quest_def(def);
            self.quest_definitions.insert(engine_def.id, engine_def);
        }
        info!("Quest engine loaded {} quest definitions", self.quest_definitions.len());
    }

    /// Register a trigger handler: when `trigger` fires, check if
    /// `quest_id` is at `required_stage` and advance if so.
    pub fn register_trigger(&mut self, trigger: QuestTrigger, quest_id: u32, required_stage: i32) {
        self.trigger_handlers
            .entry(trigger)
            .or_default()
            .push((quest_id, required_stage));
    }

    // -- Player quest state accessors --

    /// Get the quest state for a player and quest. Returns `NotStarted` if absent.
    pub fn get_quest_state(&self, player_id: u64, quest_id: u32) -> QuestState {
        self.player_quests
            .get(&player_id)
            .and_then(|quests| quests.get(&quest_id))
            .copied()
            .unwrap_or_default()
    }

    /// Set the quest stage for a player, returning packets to send.
    pub fn set_quest_stage(
        &mut self,
        player_id: u64,
        quest_id: u32,
        stage: i32,
    ) -> Result<Vec<Packet>, QuestError> {
        // Validate stage
        if stage != QuestState::COMPLETED && (stage < 0 || stage > 254) {
            return Err(QuestError::InvalidStage(stage));
        }

        let quests = self.player_quests.entry(player_id).or_default();
        let state = QuestState { stage };
        quests.insert(quest_id, state);

        debug!("Player {} quest {} set to stage {}", player_id, quest_id, stage);

        let mut packets = Vec::new();
        packets.push(build_quest_update_packet(quest_id, stage));
        Ok(packets)
    }

    /// Complete a quest for a player, returning the reward info.
    pub fn complete_quest(
        &mut self,
        player_id: u64,
        quest_id: u32,
    ) -> Result<QuestRewardInfo, QuestError> {
        let definition = self
            .quest_definitions
            .get(&quest_id)
            .ok_or(QuestError::QuestNotFound(quest_id))?
            .clone();

        let quests = self.player_quests.entry(player_id).or_default();
        quests.insert(quest_id, QuestState::completed());

        info!(
            "Player {} completed quest {} ({})",
            player_id, quest_id, definition.name
        );

        Ok(definition.rewards)
    }

    /// Check whether a player meets all requirements for a quest.
    pub fn check_requirements(
        &self,
        player_id: u64,
        quest_id: u32,
        skill_levels: &HashMap<SkillId, u8>,
        combat_level: u32,
    ) -> RequirementResult {
        let definition = match self.quest_definitions.get(&quest_id) {
            Some(def) => def,
            None => {
                return RequirementResult {
                    met: false,
                    unmet_requirements: vec!["Quest not found".to_string()],
                };
            }
        };

        let mut unmet = Vec::new();

        for req in &definition.requirements {
            match req {
                QuestRequirementEntry::SkillLevel(skill, level) => {
                    let current = skill_levels.get(skill).copied().unwrap_or(1);
                    if current < *level {
                        unmet.push(format!(
                            "Requires {:?} level {} (you have {})",
                            skill, level, current,
                        ));
                    }
                }
                QuestRequirementEntry::QuestComplete(required_id) => {
                    let state = self.get_quest_state(player_id, *required_id);
                    if !state.is_completed() {
                        let name = self
                            .quest_definitions
                            .get(required_id)
                            .map(|d| d.name.as_str())
                            .unwrap_or("Unknown");
                        unmet.push(format!("Requires completion of quest: {}", name));
                    }
                }
                QuestRequirementEntry::CombatLevel(level) => {
                    if combat_level < *level {
                        unmet.push(format!(
                            "Requires combat level {} (you have {})",
                            level, combat_level,
                        ));
                    }
                }
                QuestRequirementEntry::QuestPoints(points) => {
                    let current_qp = self.get_quest_points(player_id);
                    if current_qp < *points {
                        unmet.push(format!(
                            "Requires {} quest points (you have {})",
                            points, current_qp,
                        ));
                    }
                }
            }
        }

        if unmet.is_empty() {
            RequirementResult::all_met()
        } else {
            RequirementResult {
                met: false,
                unmet_requirements: unmet,
            }
        }
    }

    /// Get the total quest points for a player.
    pub fn get_quest_points(&self, player_id: u64) -> u32 {
        let quests = match self.player_quests.get(&player_id) {
            Some(q) => q,
            None => return 0,
        };

        let mut total = 0u32;
        for (quest_id, state) in quests {
            if state.is_completed() {
                if let Some(def) = self.quest_definitions.get(quest_id) {
                    total += def.quest_points;
                }
            }
        }
        total
    }

    /// Get all quest states for a player (for sending the full quest list).
    pub fn get_all_quest_states(&self, player_id: u64) -> HashMap<u32, QuestState> {
        self.player_quests
            .get(&player_id)
            .cloned()
            .unwrap_or_default()
    }

    // -- Trigger dispatching --

    /// Fire a trigger and return packets for any quests that should advance.
    pub fn dispatch_trigger(
        &mut self,
        player_id: u64,
        trigger: &QuestTrigger,
    ) -> Vec<Packet> {
        let handlers = match self.trigger_handlers.get(trigger) {
            Some(h) => h.clone(),
            None => return Vec::new(),
        };

        let mut packets = Vec::new();

        for (quest_id, required_stage) in &handlers {
            let current = self.get_quest_state(player_id, *quest_id);
            if current.stage == *required_stage {
                let next_stage = required_stage + 1;
                match self.set_quest_stage(player_id, *quest_id, next_stage) {
                    Ok(mut p) => {
                        debug!(
                            "Trigger {:?} advanced quest {} for player {} from stage {} to {}",
                            trigger, quest_id, player_id, required_stage, next_stage,
                        );
                        packets.append(&mut p);
                    }
                    Err(e) => {
                        warn!(
                            "Failed to advance quest {} for player {} via trigger: {:?}",
                            quest_id, player_id, e,
                        );
                    }
                }
            }
        }

        packets
    }

    /// Remove all state for a player (e.g., on logout cleanup).
    pub fn remove_player(&mut self, player_id: u64) {
        self.player_quests.remove(&player_id);
    }
}

impl Default for QuestManager {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// QuestError
// ---------------------------------------------------------------------------

/// Errors that can occur in quest operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QuestError {
    QuestNotFound(u32),
    InvalidStage(i32),
    RequirementsNotMet,
    AlreadyCompleted,
}

impl std::fmt::Display for QuestError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            QuestError::QuestNotFound(id) => write!(f, "Quest {} not found", id),
            QuestError::InvalidStage(stage) => write!(f, "Invalid quest stage: {}", stage),
            QuestError::RequirementsNotMet => write!(f, "Quest requirements not met"),
            QuestError::AlreadyCompleted => write!(f, "Quest already completed"),
        }
    }
}

impl std::error::Error for QuestError {}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build the full quest list packet for a player.
///
/// Format: `[quest_count: u16] [quest_id: u32, stage: i16] ...`
pub fn build_quest_list_packet(quests: &HashMap<u32, QuestState>) -> Packet {
    let mut builder = PacketBuilder::new(OpcodeOut::QuestMessage as u8)
        .write_short(quests.len() as u16);

    for (&quest_id, state) in quests {
        builder = builder
            .write_int(quest_id)
            .write_sshort(state.stage as i16);
    }

    builder.build()
}

/// Build a single quest stage update packet.
///
/// Format: `[quest_id: u32] [stage: i16]`
pub fn build_quest_update_packet(quest_id: u32, stage: i32) -> Packet {
    PacketBuilder::new(OpcodeOut::QuestMessage as u8)
        .write_int(quest_id)
        .write_sshort(stage as i16)
        .build()
}

/// Build a quest completion notification packet.
///
/// Format: `[quest_name: string] [quest_points: u16] [xp_count: u8]
///          [skill_id: u8, amount: u32] ... [item_count: u8]
///          [item_id: u32, amount: u32] ... [coins: u32]`
pub fn build_quest_complete_packet(quest_name: &str, rewards: &QuestRewardInfo) -> Packet {
    let mut builder = PacketBuilder::new(OpcodeOut::QuestMessage as u8)
        .write_string(quest_name)
        .write_short(rewards.quest_points as u16)
        .write_byte(rewards.xp_rewards.len() as u8);

    for (skill, amount) in &rewards.xp_rewards {
        builder = builder.write_byte(*skill as u8).write_int(*amount);
    }

    builder = builder.write_byte(rewards.item_rewards.len() as u8);
    for (item_id, amount) in &rewards.item_rewards {
        builder = builder.write_int(*item_id).write_int(*amount);
    }

    builder = builder.write_int(rewards.coins);

    builder.build()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Map the `SkillType` (which is an alias for `SkillId`) back to `SkillId`.
/// Since `SkillType` is re-exported as `SkillId`, this is an identity mapping
/// but keeps the conversion explicit at the boundary.
fn skill_type_to_id(skill: super::skills::SkillType) -> SkillId {
    skill
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_quest_state_default() {
        let state = QuestState::default();
        assert!(state.is_not_started());
        assert!(!state.is_completed());
        assert!(!state.is_in_progress());
    }

    #[test]
    fn test_quest_state_transitions() {
        let not_started = QuestState::not_started();
        assert_eq!(not_started.stage, QuestState::NOT_STARTED);
        assert!(not_started.is_not_started());

        let in_progress = QuestState::in_progress(3);
        assert_eq!(in_progress.stage, 3);
        assert!(in_progress.is_in_progress());
        assert!(!in_progress.is_completed());

        let completed = QuestState::completed();
        assert_eq!(completed.stage, QuestState::COMPLETED);
        assert!(completed.is_completed());
        assert!(!completed.is_in_progress());
    }

    #[test]
    #[should_panic(expected = "in-progress stage must be 1..=254")]
    fn test_quest_state_invalid_stage_zero() {
        QuestState::in_progress(0);
    }

    #[test]
    #[should_panic(expected = "in-progress stage must be 1..=254")]
    fn test_quest_state_invalid_stage_overflow() {
        QuestState::in_progress(255);
    }

    #[test]
    fn test_quest_manager_get_set_stage() {
        let mut mgr = QuestManager::new();

        // Default state is not started
        let state = mgr.get_quest_state(1, 0);
        assert!(state.is_not_started());

        // Set to stage 1
        let packets = mgr.set_quest_stage(1, 0, 1).unwrap();
        assert_eq!(packets.len(), 1);

        let state = mgr.get_quest_state(1, 0);
        assert_eq!(state.stage, 1);
        assert!(state.is_in_progress());
    }

    #[test]
    fn test_quest_manager_complete() {
        let mut mgr = QuestManager::new();

        // Add a definition
        let def = QuestDefinition {
            id: 0,
            name: "Test Quest".to_string(),
            description: "A test quest".to_string(),
            requirements: Vec::new(),
            rewards: QuestRewardInfo {
                xp_rewards: vec![(SkillId::Cooking, 300)],
                item_rewards: Vec::new(),
                quest_points: 1,
                coins: 0,
            },
            quest_points: 1,
        };
        mgr.quest_definitions.insert(0, def);

        // Start and complete
        mgr.set_quest_stage(1, 0, 1).unwrap();
        let rewards = mgr.complete_quest(1, 0).unwrap();
        assert_eq!(rewards.quest_points, 1);
        assert_eq!(rewards.xp_rewards.len(), 1);

        let state = mgr.get_quest_state(1, 0);
        assert!(state.is_completed());
    }

    #[test]
    fn test_quest_points_accumulation() {
        let mut mgr = QuestManager::new();

        // Add two quest definitions
        for id in 0..2u32 {
            mgr.quest_definitions.insert(id, QuestDefinition {
                id,
                name: format!("Quest {}", id),
                description: String::new(),
                requirements: Vec::new(),
                rewards: QuestRewardInfo::default(),
                quest_points: id + 1,
            });
        }

        assert_eq!(mgr.get_quest_points(1), 0);

        mgr.complete_quest(1, 0).unwrap();
        assert_eq!(mgr.get_quest_points(1), 1); // quest 0 = 1 QP

        mgr.complete_quest(1, 1).unwrap();
        assert_eq!(mgr.get_quest_points(1), 3); // quest 0 (1) + quest 1 (2) = 3
    }

    #[test]
    fn test_check_requirements_all_met() {
        let mut mgr = QuestManager::new();
        mgr.quest_definitions.insert(0, QuestDefinition {
            id: 0,
            name: "Easy Quest".to_string(),
            description: String::new(),
            requirements: Vec::new(),
            rewards: QuestRewardInfo::default(),
            quest_points: 1,
        });

        let skills = HashMap::new();
        let result = mgr.check_requirements(1, 0, &skills, 3);
        assert!(result.met);
        assert!(result.unmet_requirements.is_empty());
    }

    #[test]
    fn test_check_requirements_skill_not_met() {
        let mut mgr = QuestManager::new();
        mgr.quest_definitions.insert(0, QuestDefinition {
            id: 0,
            name: "Hard Quest".to_string(),
            description: String::new(),
            requirements: vec![
                QuestRequirementEntry::SkillLevel(SkillId::Mining, 50),
                QuestRequirementEntry::CombatLevel(40),
            ],
            rewards: QuestRewardInfo::default(),
            quest_points: 1,
        });

        let mut skills = HashMap::new();
        skills.insert(SkillId::Mining, 30u8);

        let result = mgr.check_requirements(1, 0, &skills, 20);
        assert!(!result.met);
        assert_eq!(result.unmet_requirements.len(), 2);
    }

    #[test]
    fn test_check_requirements_quest_prereq() {
        let mut mgr = QuestManager::new();

        mgr.quest_definitions.insert(0, QuestDefinition {
            id: 0,
            name: "Prereq Quest".to_string(),
            description: String::new(),
            requirements: Vec::new(),
            rewards: QuestRewardInfo::default(),
            quest_points: 1,
        });

        mgr.quest_definitions.insert(1, QuestDefinition {
            id: 1,
            name: "Sequel Quest".to_string(),
            description: String::new(),
            requirements: vec![QuestRequirementEntry::QuestComplete(0)],
            rewards: QuestRewardInfo::default(),
            quest_points: 1,
        });

        let skills = HashMap::new();

        // Before completing prereq
        let result = mgr.check_requirements(1, 1, &skills, 3);
        assert!(!result.met);

        // After completing prereq
        mgr.complete_quest(1, 0).unwrap();
        let result = mgr.check_requirements(1, 1, &skills, 3);
        assert!(result.met);
    }

    #[test]
    fn test_trigger_dispatch() {
        let mut mgr = QuestManager::new();

        mgr.quest_definitions.insert(0, QuestDefinition {
            id: 0,
            name: "Trigger Quest".to_string(),
            description: String::new(),
            requirements: Vec::new(),
            rewards: QuestRewardInfo::default(),
            quest_points: 1,
        });

        // Register a trigger: talking to NPC 42 at stage 1 advances the quest
        mgr.register_trigger(QuestTrigger::TalkToNpc(42), 0, 1);

        // Set player to stage 1
        mgr.set_quest_stage(1, 0, 1).unwrap();

        // Fire the trigger
        let packets = mgr.dispatch_trigger(1, &QuestTrigger::TalkToNpc(42));
        assert_eq!(packets.len(), 1);

        // Quest should now be at stage 2
        let state = mgr.get_quest_state(1, 0);
        assert_eq!(state.stage, 2);
    }

    #[test]
    fn test_trigger_dispatch_wrong_stage() {
        let mut mgr = QuestManager::new();

        mgr.quest_definitions.insert(0, QuestDefinition {
            id: 0,
            name: "Trigger Quest".to_string(),
            description: String::new(),
            requirements: Vec::new(),
            rewards: QuestRewardInfo::default(),
            quest_points: 1,
        });

        mgr.register_trigger(QuestTrigger::KillNpc(10), 0, 3);

        // Player is at stage 1, trigger requires stage 3 -- should not advance
        mgr.set_quest_stage(1, 0, 1).unwrap();
        let packets = mgr.dispatch_trigger(1, &QuestTrigger::KillNpc(10));
        assert!(packets.is_empty());
        assert_eq!(mgr.get_quest_state(1, 0).stage, 1);
    }

    #[test]
    fn test_invalid_stage_error() {
        let mut mgr = QuestManager::new();
        let result = mgr.set_quest_stage(1, 0, 300);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), QuestError::InvalidStage(300));
    }

    #[test]
    fn test_complete_unknown_quest_error() {
        let mut mgr = QuestManager::new();
        let result = mgr.complete_quest(1, 999);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), QuestError::QuestNotFound(999));
    }

    #[test]
    fn test_build_quest_list_packet() {
        let mut quests = HashMap::new();
        quests.insert(0, QuestState::in_progress(3));
        quests.insert(1, QuestState::completed());

        let packet = build_quest_list_packet(&quests);
        assert!(!packet.is_empty());
    }

    #[test]
    fn test_build_quest_update_packet() {
        let packet = build_quest_update_packet(5, 2);
        assert!(!packet.is_empty());
    }

    #[test]
    fn test_build_quest_complete_packet() {
        let rewards = QuestRewardInfo {
            xp_rewards: vec![(SkillId::Cooking, 300)],
            item_rewards: vec![(10, 1)],
            quest_points: 1,
            coins: 100,
        };
        let packet = build_quest_complete_packet("Cook's Assistant", &rewards);
        assert!(!packet.is_empty());
    }

    #[test]
    fn test_load_from_repository() {
        let mut repo = QuestRepository::new();
        repo.load_defaults();

        let mut mgr = QuestManager::new();
        mgr.load_from_repository(&repo);

        // Should have loaded all quests from the repository
        assert!(!mgr.quest_definitions.is_empty());
        assert!(mgr.quest_definitions.contains_key(&0)); // Cook's Assistant
    }

    #[test]
    fn test_remove_player() {
        let mut mgr = QuestManager::new();
        mgr.set_quest_stage(1, 0, 1).unwrap();
        assert!(mgr.get_quest_state(1, 0).is_in_progress());

        mgr.remove_player(1);
        assert!(mgr.get_quest_state(1, 0).is_not_started());
    }

    #[test]
    fn test_quest_definition_from_quest_def() {
        let def = QuestDef::builder(0, "Test")
            .description("Test quest")
            .quest_points(2)
            .reward_xp(super::super::skills::SkillType::Attack, 500)
            .reward_coins(100)
            .build();

        let engine_def = QuestDefinition::from_quest_def(&def);
        assert_eq!(engine_def.id, 0);
        assert_eq!(engine_def.name, "Test");
        assert_eq!(engine_def.rewards.coins, 100);
        assert_eq!(engine_def.rewards.xp_rewards.len(), 1);
        assert_eq!(engine_def.quest_points, 2);
    }
}
