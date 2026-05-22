//! Dialogue system.
//! Handles NPC conversations, dialogue trees, and player choices.

use std::collections::HashMap;
use tracing::{debug, warn};

/// Dialogue node types.
#[derive(Debug, Clone)]
pub enum DialogueNode {
    /// NPC says something.
    NpcSay {
        text: Vec<String>,
        next: Option<String>,
    },
    /// Player says something.
    PlayerSay { text: String, next: Option<String> },
    /// Player chooses from options.
    Choice { options: Vec<DialogueOption> },
    /// Execute an action.
    Action {
        action: DialogueAction,
        next: Option<String>,
    },
    /// Conditional branch.
    Condition {
        condition: DialogueCondition,
        if_true: String,
        if_false: String,
    },
    /// End the dialogue.
    End,
}

/// A dialogue option for player choices.
#[derive(Debug, Clone)]
pub struct DialogueOption {
    /// Option text.
    pub text: String,
    /// Node to go to when selected.
    pub next: String,
    /// Condition to show this option.
    pub condition: Option<DialogueCondition>,
}

impl DialogueOption {
    /// Create a new dialogue option.
    pub fn new(text: impl Into<String>, next: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            next: next.into(),
            condition: None,
        }
    }

    /// Add a condition.
    pub fn with_condition(mut self, condition: DialogueCondition) -> Self {
        self.condition = Some(condition);
        self
    }
}

/// Dialogue conditions.
#[derive(Debug, Clone)]
pub enum DialogueCondition {
    /// Check if player has item.
    HasItem { item_id: u32, amount: u32 },
    /// Check if player has completed quest.
    QuestComplete(u16),
    /// Check if player is at quest stage.
    QuestStage { quest_id: u16, stage: u8 },
    /// Check player skill level.
    SkillLevel { skill_id: u8, level: u8 },
    /// Check player combat level.
    CombatLevel(u8),
    /// Check if player has gold.
    HasGold(u32),
    /// Check if player is member.
    IsMember,
    /// Check if player has completed achievement.
    HasAchievement(u32),
    /// Custom condition (checked externally).
    Custom(String),
    /// Combine conditions with AND.
    And(Vec<DialogueCondition>),
    /// Combine conditions with OR.
    Or(Vec<DialogueCondition>),
    /// Negate a condition.
    Not(Box<DialogueCondition>),
}

/// Dialogue actions.
#[derive(Debug, Clone)]
pub enum DialogueAction {
    /// Give item to player.
    GiveItem { item_id: u32, amount: u32 },
    /// Take item from player.
    TakeItem { item_id: u32, amount: u32 },
    /// Give gold to player.
    GiveGold(u32),
    /// Take gold from player.
    TakeGold(u32),
    /// Give experience.
    GiveExperience { skill_id: u8, amount: u32 },
    /// Set quest stage.
    SetQuestStage { quest_id: u16, stage: u8 },
    /// Complete quest.
    CompleteQuest(u16),
    /// Teleport player.
    Teleport { x: u16, y: u16 },
    /// Heal player.
    HealPlayer,
    /// Open shop.
    OpenShop(u32),
    /// Open bank.
    OpenBank,
    /// Play sound.
    PlaySound(String),
    /// Set player variable.
    SetVariable { key: String, value: String },
    /// Custom action.
    Custom(String),
}

/// A complete dialogue tree.
#[derive(Debug, Clone)]
pub struct Dialogue {
    /// Dialogue ID.
    pub id: u32,
    /// NPC ID this dialogue is for.
    pub npc_id: u32,
    /// Starting node.
    pub start_node: String,
    /// All nodes in the dialogue.
    nodes: HashMap<String, DialogueNode>,
}

impl Dialogue {
    /// Create a new dialogue.
    pub fn new(id: u32, npc_id: u32, start_node: impl Into<String>) -> Self {
        Self {
            id,
            npc_id,
            start_node: start_node.into(),
            nodes: HashMap::new(),
        }
    }

    /// Add a node.
    pub fn add_node(&mut self, name: impl Into<String>, node: DialogueNode) {
        self.nodes.insert(name.into(), node);
    }

    /// Get a node by name.
    pub fn get_node(&self, name: &str) -> Option<&DialogueNode> {
        self.nodes.get(name)
    }

    /// Get the start node.
    pub fn get_start_node(&self) -> Option<&DialogueNode> {
        self.nodes.get(&self.start_node)
    }

    /// Builder method to add an NPC say node.
    pub fn npc_say(mut self, name: impl Into<String>, text: Vec<&str>, next: Option<&str>) -> Self {
        self.add_node(
            name,
            DialogueNode::NpcSay {
                text: text.into_iter().map(String::from).collect(),
                next: next.map(String::from),
            },
        );
        self
    }

    /// Builder method to add a player say node.
    pub fn player_say(mut self, name: impl Into<String>, text: &str, next: Option<&str>) -> Self {
        self.add_node(
            name,
            DialogueNode::PlayerSay {
                text: text.to_string(),
                next: next.map(String::from),
            },
        );
        self
    }

    /// Builder method to add a choice node.
    pub fn choice(mut self, name: impl Into<String>, options: Vec<DialogueOption>) -> Self {
        self.add_node(name, DialogueNode::Choice { options });
        self
    }

    /// Builder method to add an action node.
    pub fn action(
        mut self,
        name: impl Into<String>,
        action: DialogueAction,
        next: Option<&str>,
    ) -> Self {
        self.add_node(
            name,
            DialogueNode::Action {
                action,
                next: next.map(String::from),
            },
        );
        self
    }

    /// Builder method to add a condition node.
    pub fn condition(
        mut self,
        name: impl Into<String>,
        condition: DialogueCondition,
        if_true: &str,
        if_false: &str,
    ) -> Self {
        self.add_node(
            name,
            DialogueNode::Condition {
                condition,
                if_true: if_true.to_string(),
                if_false: if_false.to_string(),
            },
        );
        self
    }

    /// Builder method to add an end node.
    pub fn end(mut self, name: impl Into<String>) -> Self {
        self.add_node(name, DialogueNode::End);
        self
    }
}

/// Active dialogue state for a player.
#[derive(Debug, Clone)]
pub struct DialogueState {
    /// Dialogue ID.
    pub dialogue_id: u32,
    /// Current node name.
    pub current_node: String,
    /// NPC index the player is talking to.
    pub npc_index: u32,
    /// Variables set during dialogue.
    pub variables: HashMap<String, String>,
    /// Messages waiting to be sent.
    pub pending_messages: Vec<String>,
    /// Options waiting for player response.
    pub pending_options: Vec<String>,
}

impl DialogueState {
    /// Create a new dialogue state.
    pub fn new(dialogue_id: u32, npc_index: u32, start_node: String) -> Self {
        Self {
            dialogue_id,
            current_node: start_node,
            npc_index,
            variables: HashMap::new(),
            pending_messages: Vec::new(),
            pending_options: Vec::new(),
        }
    }

    /// Set a variable.
    pub fn set_variable(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.variables.insert(key.into(), value.into());
    }

    /// Get a variable.
    pub fn get_variable(&self, key: &str) -> Option<&String> {
        self.variables.get(key)
    }

    /// Clear pending messages and options.
    pub fn clear_pending(&mut self) {
        self.pending_messages.clear();
        self.pending_options.clear();
    }
}

/// Result of processing a dialogue node.
#[derive(Debug)]
pub enum DialogueResult {
    /// Show NPC message(s).
    NpcMessage(Vec<String>),
    /// Show player message.
    PlayerMessage(String),
    /// Show options to player.
    ShowOptions(Vec<String>),
    /// Execute an action.
    ExecuteAction(DialogueAction),
    /// Move to next node.
    Continue(String),
    /// Dialogue ended.
    End,
    /// Error occurred.
    Error(String),
}

/// Dialogue manager.
#[derive(Debug, Default)]
pub struct DialogueManager {
    /// All dialogues by ID.
    dialogues: HashMap<u32, Dialogue>,
    /// Dialogues by NPC ID.
    by_npc: HashMap<u32, Vec<u32>>,
}

impl DialogueManager {
    /// Create a new dialogue manager.
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.load_defaults();
        manager
    }

    /// Load default dialogues.
    pub fn load_defaults(&mut self) {
        // Example: Hans dialogue (Tutorial Island guide)
        let hans_dialogue = Dialogue::new(1, 0, "start")
            .npc_say(
                "start",
                vec!["Hello adventurer!", "Welcome to the game."],
                Some("ask_help"),
            )
            .choice(
                "ask_help",
                vec![
                    DialogueOption::new("Can you help me?", "help_yes"),
                    DialogueOption::new("Who are you?", "who_are_you"),
                    DialogueOption::new("Goodbye.", "goodbye"),
                ],
            )
            .npc_say(
                "help_yes",
                vec!["Of course! What do you need help with?"],
                Some("help_options"),
            )
            .choice(
                "help_options",
                vec![
                    DialogueOption::new("Where am I?", "where_am_i"),
                    DialogueOption::new("How do I train?", "how_train"),
                    DialogueOption::new("Never mind.", "goodbye"),
                ],
            )
            .npc_say(
                "where_am_i",
                vec![
                    "You are in Lumbridge!",
                    "This is a safe place for adventurers to start their journey.",
                ],
                Some("help_options"),
            )
            .npc_say(
                "how_train",
                vec![
                    "You can train your skills by performing various activities.",
                    "Try mining some rocks, or fighting goblins!",
                ],
                Some("help_options"),
            )
            .npc_say(
                "who_are_you",
                vec![
                    "I am Hans, a friendly guide.",
                    "I've been here for a very long time.",
                ],
                Some("ask_help"),
            )
            .npc_say("goodbye", vec!["Farewell, adventurer!"], None)
            .end("end");

        self.register(hans_dialogue);

        // Example: Shop keeper dialogue
        let shopkeeper_dialogue = Dialogue::new(2, 51, "start")
            .npc_say("start", vec!["Welcome to my shop!"], Some("shop_choice"))
            .choice(
                "shop_choice",
                vec![
                    DialogueOption::new("Let me see your wares.", "open_shop"),
                    DialogueOption::new("No thanks.", "goodbye"),
                ],
            )
            .action("open_shop", DialogueAction::OpenShop(1), None)
            .npc_say("goodbye", vec!["Come back soon!"], None)
            .end("end");

        self.register(shopkeeper_dialogue);

        // Example: Banker dialogue
        let banker_dialogue = Dialogue::new(3, 95, "start")
            .npc_say(
                "start",
                vec!["Good day. How may I help you?"],
                Some("bank_choice"),
            )
            .choice(
                "bank_choice",
                vec![
                    DialogueOption::new("I'd like to access my bank account.", "open_bank"),
                    DialogueOption::new("What is this place?", "explain"),
                    DialogueOption::new("Nothing, thanks.", "goodbye"),
                ],
            )
            .action("open_bank", DialogueAction::OpenBank, None)
            .npc_say(
                "explain",
                vec![
                    "This is a bank.",
                    "You can store your items here for safekeeping.",
                ],
                Some("bank_choice"),
            )
            .npc_say("goodbye", vec!["Very well."], None)
            .end("end");

        self.register(banker_dialogue);
    }

    /// Register a dialogue.
    pub fn register(&mut self, dialogue: Dialogue) {
        let id = dialogue.id;
        let npc_id = dialogue.npc_id;

        self.by_npc.entry(npc_id).or_default().push(id);
        self.dialogues.insert(id, dialogue);
    }

    /// Get dialogue by ID.
    pub fn get(&self, id: u32) -> Option<&Dialogue> {
        self.dialogues.get(&id)
    }

    /// Get dialogues for an NPC.
    pub fn get_for_npc(&self, npc_id: u32) -> Vec<&Dialogue> {
        self.by_npc
            .get(&npc_id)
            .map(|ids| ids.iter().filter_map(|id| self.dialogues.get(id)).collect())
            .unwrap_or_default()
    }

    /// Get the first dialogue for an NPC.
    pub fn get_first_for_npc(&self, npc_id: u32) -> Option<&Dialogue> {
        self.by_npc
            .get(&npc_id)
            .and_then(|ids| ids.first())
            .and_then(|id| self.dialogues.get(id))
    }

    /// Process a dialogue node.
    pub fn process_node(&self, dialogue_id: u32, node_name: &str) -> DialogueResult {
        let dialogue = match self.get(dialogue_id) {
            Some(d) => d,
            None => return DialogueResult::Error("Dialogue not found".to_string()),
        };

        let node = match dialogue.get_node(node_name) {
            Some(n) => n,
            None => return DialogueResult::Error(format!("Node '{}' not found", node_name)),
        };

        match node {
            DialogueNode::NpcSay { text, next } => {
                if let Some(next_node) = next {
                    DialogueResult::Continue(next_node.clone())
                } else {
                    DialogueResult::NpcMessage(text.clone())
                }
            }
            DialogueNode::PlayerSay { text, next } => {
                if let Some(next_node) = next {
                    DialogueResult::Continue(next_node.clone())
                } else {
                    DialogueResult::PlayerMessage(text.clone())
                }
            }
            DialogueNode::Choice { options } => {
                let option_texts: Vec<String> = options.iter().map(|o| o.text.clone()).collect();
                DialogueResult::ShowOptions(option_texts)
            }
            DialogueNode::Action { action, next } => DialogueResult::ExecuteAction(action.clone()),
            DialogueNode::Condition { .. } => {
                // Conditions should be evaluated externally
                DialogueResult::Error("Condition needs external evaluation".to_string())
            }
            DialogueNode::End => DialogueResult::End,
        }
    }

    /// Get the next node after selecting an option.
    pub fn select_option(
        &self,
        dialogue_id: u32,
        node_name: &str,
        option_index: usize,
    ) -> Option<String> {
        let dialogue = self.get(dialogue_id)?;
        let node = dialogue.get_node(node_name)?;

        if let DialogueNode::Choice { options } = node {
            options.get(option_index).map(|o| o.next.clone())
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dialogue_creation() {
        let dialogue = Dialogue::new(1, 0, "start")
            .npc_say("start", vec!["Hello!"], Some("choice"))
            .choice(
                "choice",
                vec![
                    DialogueOption::new("Hi", "greet"),
                    DialogueOption::new("Bye", "end"),
                ],
            )
            .end("end");

        assert!(dialogue.get_node("start").is_some());
        assert!(dialogue.get_node("choice").is_some());
        assert!(dialogue.get_node("end").is_some());
    }

    #[test]
    fn test_dialogue_manager() {
        let manager = DialogueManager::new();

        // Should have loaded default dialogues
        assert!(manager.get(1).is_some());
        assert!(manager.get_first_for_npc(0).is_some());
    }

    #[test]
    fn test_dialogue_option() {
        let option = DialogueOption::new("Test", "next_node")
            .with_condition(DialogueCondition::HasGold(100));

        assert_eq!(option.text, "Test");
        assert_eq!(option.next, "next_node");
        assert!(option.condition.is_some());
    }

    #[test]
    fn test_dialogue_state() {
        let mut state = DialogueState::new(1, 0, "start".to_string());

        state.set_variable("test_key", "test_value");
        assert_eq!(
            state.get_variable("test_key"),
            Some(&"test_value".to_string())
        );

        state.pending_messages.push("Hello".to_string());
        state.clear_pending();
        assert!(state.pending_messages.is_empty());
    }
}
