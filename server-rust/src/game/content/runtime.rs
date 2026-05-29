//! Runtime-facing translation for compiled content effects.
//!
//! Content plugins stay pure by returning [`ContentEffect`] values. This module
//! gives live handlers a typed command batch they can dispatch into packet,
//! inventory, quest, dialogue, shop, and world systems without embedding that
//! runtime state in the content registry.

use std::fmt;

use super::{ContentEffect, ContentEvent, ContentRegistry, ContentResult};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContentRuntimeCommand {
    SendMessage {
        player_id: u64,
        text: String,
    },
    OpenShop {
        player_id: u64,
        shop_id: u32,
    },
    OpenBank {
        player_id: u64,
    },
    StartDialogue {
        player_id: u64,
        dialogue_id: String,
    },
    SendNpcDialogue {
        player_id: u64,
        npc_name: String,
        lines: Vec<String>,
    },
    ShowDialogueOptions {
        player_id: u64,
        options: Vec<String>,
    },
    SetQuestStage {
        player_id: u64,
        quest_id: String,
        stage: i32,
    },
    AddInventoryItem {
        player_id: u64,
        item_id: u32,
        amount: u32,
    },
    RemoveInventoryItem {
        player_id: u64,
        item_id: u32,
        amount: u32,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContentRuntimeError {
    CommandFailed { index: usize, reason: String },
}

impl fmt::Display for ContentRuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::CommandFailed { index, reason } => {
                write!(f, "content runtime command {index} failed: {reason}")
            }
        }
    }
}

impl std::error::Error for ContentRuntimeError {}

pub trait ContentRuntimeSink {
    fn send_message(&mut self, player_id: u64, text: &str) -> Result<(), String>;
    fn open_shop(&mut self, player_id: u64, shop_id: u32) -> Result<(), String>;
    fn open_bank(&mut self, player_id: u64) -> Result<(), String>;
    fn start_dialogue(&mut self, player_id: u64, dialogue_id: &str) -> Result<(), String>;
    fn send_npc_dialogue(
        &mut self,
        player_id: u64,
        npc_name: &str,
        lines: &[String],
    ) -> Result<(), String>;
    fn show_dialogue_options(&mut self, player_id: u64, options: &[String]) -> Result<(), String>;
    fn set_quest_stage(&mut self, player_id: u64, quest_id: &str, stage: i32)
        -> Result<(), String>;
    fn add_inventory_item(
        &mut self,
        player_id: u64,
        item_id: u32,
        amount: u32,
    ) -> Result<(), String>;
    fn remove_inventory_item(
        &mut self,
        player_id: u64,
        item_id: u32,
        amount: u32,
    ) -> Result<(), String>;
}

impl ContentRuntimeCommand {
    pub fn player_id(&self) -> u64 {
        match self {
            Self::SendMessage { player_id, .. }
            | Self::OpenShop { player_id, .. }
            | Self::OpenBank { player_id }
            | Self::StartDialogue { player_id, .. }
            | Self::SendNpcDialogue { player_id, .. }
            | Self::ShowDialogueOptions { player_id, .. }
            | Self::SetQuestStage { player_id, .. }
            | Self::AddInventoryItem { player_id, .. }
            | Self::RemoveInventoryItem { player_id, .. } => *player_id,
        }
    }

    pub fn apply_to(&self, sink: &mut impl ContentRuntimeSink) -> Result<(), String> {
        match self {
            Self::SendMessage { player_id, text } => sink.send_message(*player_id, text),
            Self::OpenShop { player_id, shop_id } => sink.open_shop(*player_id, *shop_id),
            Self::OpenBank { player_id } => sink.open_bank(*player_id),
            Self::StartDialogue {
                player_id,
                dialogue_id,
            } => sink.start_dialogue(*player_id, dialogue_id),
            Self::SendNpcDialogue {
                player_id,
                npc_name,
                lines,
            } => sink.send_npc_dialogue(*player_id, npc_name, lines),
            Self::ShowDialogueOptions { player_id, options } => {
                sink.show_dialogue_options(*player_id, options)
            }
            Self::SetQuestStage {
                player_id,
                quest_id,
                stage,
            } => sink.set_quest_stage(*player_id, quest_id, *stage),
            Self::AddInventoryItem {
                player_id,
                item_id,
                amount,
            } => sink.add_inventory_item(*player_id, *item_id, *amount),
            Self::RemoveInventoryItem {
                player_id,
                item_id,
                amount,
            } => sink.remove_inventory_item(*player_id, *item_id, *amount),
        }
    }
}

impl From<ContentEffect> for ContentRuntimeCommand {
    fn from(effect: ContentEffect) -> Self {
        match effect {
            ContentEffect::Message { player_id, text } => Self::SendMessage { player_id, text },
            ContentEffect::OpenShop { player_id, shop_id } => Self::OpenShop { player_id, shop_id },
            ContentEffect::OpenBank { player_id } => Self::OpenBank { player_id },
            ContentEffect::StartDialogue {
                player_id,
                dialogue_id,
            } => Self::StartDialogue {
                player_id,
                dialogue_id,
            },
            ContentEffect::NpcDialogue {
                player_id,
                npc_name,
                lines,
            } => Self::SendNpcDialogue {
                player_id,
                npc_name,
                lines,
            },
            ContentEffect::DialogueOptions { player_id, options } => {
                Self::ShowDialogueOptions { player_id, options }
            }
            ContentEffect::SetQuestStage {
                player_id,
                quest_id,
                stage,
            } => Self::SetQuestStage {
                player_id,
                quest_id,
                stage,
            },
            ContentEffect::GiveItem {
                player_id,
                item_id,
                amount,
            } => Self::AddInventoryItem {
                player_id,
                item_id,
                amount,
            },
            ContentEffect::TakeItem {
                player_id,
                item_id,
                amount,
            } => Self::RemoveInventoryItem {
                player_id,
                item_id,
                amount,
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ContentRuntimePlan {
    commands: Vec<ContentRuntimeCommand>,
}

impl ContentRuntimePlan {
    pub fn new(commands: Vec<ContentRuntimeCommand>) -> Self {
        Self { commands }
    }

    pub fn from_effects(effects: ContentResult) -> Self {
        Self {
            commands: effects.into_iter().map(Into::into).collect(),
        }
    }

    pub fn from_event(registry: &ContentRegistry, event: &ContentEvent) -> Self {
        Self::from_effects(registry.dispatch(event))
    }

    pub fn commands(&self) -> &[ContentRuntimeCommand] {
        &self.commands
    }

    pub fn into_commands(self) -> Vec<ContentRuntimeCommand> {
        self.commands
    }

    pub fn is_empty(&self) -> bool {
        self.commands.is_empty()
    }

    pub fn len(&self) -> usize {
        self.commands.len()
    }

    pub fn commands_for_player(
        &self,
        player_id: u64,
    ) -> impl Iterator<Item = &ContentRuntimeCommand> {
        self.commands
            .iter()
            .filter(move |command| command.player_id() == player_id)
    }

    pub fn apply_to(&self, sink: &mut impl ContentRuntimeSink) -> Result<(), ContentRuntimeError> {
        for (index, command) in self.commands.iter().enumerate() {
            command
                .apply_to(sink)
                .map_err(|reason| ContentRuntimeError::CommandFailed { index, reason })?;
        }
        Ok(())
    }
}

impl From<ContentResult> for ContentRuntimePlan {
    fn from(effects: ContentResult) -> Self {
        Self::from_effects(effects)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::content::{
        beginner::{
            BeginnerTutorialPlugin, COMMUNITY_INSTRUCTOR_DIALOGUE_ID, COMMUNITY_INSTRUCTOR_NPC_ID,
            GUIDE_STARTING_DIALOGUE_ID, GUIDE_STARTING_NPC_ID, TUTORIAL_QUEST_ID,
        },
        ContentPlugin,
    };
    use crate::game::dialogue_handler::{build_npc_message_packet, build_option_menu_packet};
    use crate::game::protocol::{Packet, ServerOpcode};

    #[derive(Debug, Clone, PartialEq, Eq)]
    enum RecordedRuntimeAction {
        Message(u64, String),
        Shop(u64, u32),
        Bank(u64),
        Dialogue(u64, String),
        NpcDialogue(u64, String, Vec<String>),
        DialogueOptions(u64, Vec<String>),
        QuestStage(u64, String, i32),
        AddItem(u64, u32, u32),
        RemoveItem(u64, u32, u32),
    }

    #[derive(Debug, Default)]
    struct RecordingSink {
        actions: Vec<RecordedRuntimeAction>,
        packets: Vec<Packet>,
        fail_on: Option<usize>,
    }

    impl RecordingSink {
        fn record(&mut self, action: RecordedRuntimeAction) -> Result<(), String> {
            let index = self.actions.len();
            if self.fail_on == Some(index) {
                return Err(format!("planned failure at action {index}"));
            }
            self.actions.push(action);
            Ok(())
        }
    }

    impl ContentRuntimeSink for RecordingSink {
        fn send_message(&mut self, player_id: u64, text: &str) -> Result<(), String> {
            self.record(RecordedRuntimeAction::Message(player_id, text.to_string()))
        }

        fn open_shop(&mut self, player_id: u64, shop_id: u32) -> Result<(), String> {
            self.record(RecordedRuntimeAction::Shop(player_id, shop_id))
        }

        fn open_bank(&mut self, player_id: u64) -> Result<(), String> {
            self.record(RecordedRuntimeAction::Bank(player_id))
        }

        fn start_dialogue(&mut self, player_id: u64, dialogue_id: &str) -> Result<(), String> {
            self.record(RecordedRuntimeAction::Dialogue(
                player_id,
                dialogue_id.to_string(),
            ))
        }

        fn send_npc_dialogue(
            &mut self,
            player_id: u64,
            npc_name: &str,
            lines: &[String],
        ) -> Result<(), String> {
            self.packets.extend(
                lines
                    .iter()
                    .map(|line| build_npc_message_packet(npc_name, line)),
            );
            self.record(RecordedRuntimeAction::NpcDialogue(
                player_id,
                npc_name.to_string(),
                lines.to_vec(),
            ))
        }

        fn show_dialogue_options(
            &mut self,
            player_id: u64,
            options: &[String],
        ) -> Result<(), String> {
            self.packets.push(build_option_menu_packet(options));
            self.record(RecordedRuntimeAction::DialogueOptions(
                player_id,
                options.to_vec(),
            ))
        }

        fn set_quest_stage(
            &mut self,
            player_id: u64,
            quest_id: &str,
            stage: i32,
        ) -> Result<(), String> {
            self.record(RecordedRuntimeAction::QuestStage(
                player_id,
                quest_id.to_string(),
                stage,
            ))
        }

        fn add_inventory_item(
            &mut self,
            player_id: u64,
            item_id: u32,
            amount: u32,
        ) -> Result<(), String> {
            self.record(RecordedRuntimeAction::AddItem(player_id, item_id, amount))
        }

        fn remove_inventory_item(
            &mut self,
            player_id: u64,
            item_id: u32,
            amount: u32,
        ) -> Result<(), String> {
            self.record(RecordedRuntimeAction::RemoveItem(
                player_id, item_id, amount,
            ))
        }
    }

    #[test]
    fn translates_each_content_effect_into_runtime_command() {
        let effects = vec![
            ContentEffect::message(7, "Hello."),
            ContentEffect::open_shop(7, 3),
            ContentEffect::open_bank(7),
            ContentEffect::start_dialogue(7, "authentic.dialogue"),
            ContentEffect::npc_dialogue(7, "Guide", ["Welcome to the world of runescape"]),
            ContentEffect::dialogue_options(7, ["Who are you?", "Where am I?"]),
            ContentEffect::set_quest_stage(7, "tutorial", 15),
            ContentEffect::give_item(7, 10, 2),
            ContentEffect::take_item(7, 20, 5),
        ];

        let plan = ContentRuntimePlan::from_effects(effects);

        assert_eq!(
            plan.commands(),
            &[
                ContentRuntimeCommand::SendMessage {
                    player_id: 7,
                    text: "Hello.".to_string(),
                },
                ContentRuntimeCommand::OpenShop {
                    player_id: 7,
                    shop_id: 3,
                },
                ContentRuntimeCommand::OpenBank { player_id: 7 },
                ContentRuntimeCommand::StartDialogue {
                    player_id: 7,
                    dialogue_id: "authentic.dialogue".to_string(),
                },
                ContentRuntimeCommand::SendNpcDialogue {
                    player_id: 7,
                    npc_name: "Guide".to_string(),
                    lines: vec!["Welcome to the world of runescape".to_string()],
                },
                ContentRuntimeCommand::ShowDialogueOptions {
                    player_id: 7,
                    options: vec!["Who are you?".to_string(), "Where am I?".to_string()],
                },
                ContentRuntimeCommand::SetQuestStage {
                    player_id: 7,
                    quest_id: "tutorial".to_string(),
                    stage: 15,
                },
                ContentRuntimeCommand::AddInventoryItem {
                    player_id: 7,
                    item_id: 10,
                    amount: 2,
                },
                ContentRuntimeCommand::RemoveInventoryItem {
                    player_id: 7,
                    item_id: 20,
                    amount: 5,
                },
            ]
        );
    }

    #[test]
    fn runtime_plan_preserves_effect_order() {
        let plan = ContentRuntimePlan::from_effects(vec![
            ContentEffect::message(1, "first"),
            ContentEffect::set_quest_stage(1, "tutorial", 10),
            ContentEffect::message(1, "second"),
        ]);

        assert_eq!(
            plan.into_commands(),
            vec![
                ContentRuntimeCommand::SendMessage {
                    player_id: 1,
                    text: "first".to_string(),
                },
                ContentRuntimeCommand::SetQuestStage {
                    player_id: 1,
                    quest_id: "tutorial".to_string(),
                    stage: 10,
                },
                ContentRuntimeCommand::SendMessage {
                    player_id: 1,
                    text: "second".to_string(),
                },
            ]
        );
    }

    #[test]
    fn runtime_plan_can_filter_commands_by_player() {
        let plan = ContentRuntimePlan::from_effects(vec![
            ContentEffect::message(1, "one"),
            ContentEffect::give_item(2, 10, 1),
            ContentEffect::take_item(1, 20, 1),
        ]);

        let player_one_commands = plan
            .commands_for_player(1)
            .cloned()
            .collect::<Vec<ContentRuntimeCommand>>();

        assert_eq!(plan.len(), 3);
        assert_eq!(
            player_one_commands,
            vec![
                ContentRuntimeCommand::SendMessage {
                    player_id: 1,
                    text: "one".to_string(),
                },
                ContentRuntimeCommand::RemoveInventoryItem {
                    player_id: 1,
                    item_id: 20,
                    amount: 1,
                },
            ]
        );
    }

    #[test]
    fn empty_effects_make_empty_runtime_plan() {
        let plan = ContentRuntimePlan::from_effects(Vec::new());

        assert!(plan.is_empty());
        assert_eq!(plan.commands(), &[]);
    }

    #[test]
    fn runtime_plan_can_be_created_from_registry_event() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let plan = ContentRuntimePlan::from_event(
            &registry,
            &ContentEvent::TalkNpc {
                player_id: 42,
                npc_id: GUIDE_STARTING_NPC_ID,
                npc_index: 7,
            },
        );

        assert_eq!(
            plan.commands(),
            &[
                ContentRuntimeCommand::StartDialogue {
                    player_id: 42,
                    dialogue_id: GUIDE_STARTING_DIALOGUE_ID.to_string(),
                },
                ContentRuntimeCommand::SendMessage {
                    player_id: 42,
                    text: "Welcome to the world of runescape".to_string(),
                },
                ContentRuntimeCommand::SetQuestStage {
                    player_id: 42,
                    quest_id: TUTORIAL_QUEST_ID.to_string(),
                    stage: 10,
                },
            ]
        );
    }

    #[test]
    fn runtime_plan_can_be_created_from_content_dialogue_menu_event() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let plan = ContentRuntimePlan::from_event(
            &registry,
            &ContentEvent::TalkNpc {
                player_id: 42,
                npc_id: COMMUNITY_INSTRUCTOR_NPC_ID,
                npc_index: 14,
            },
        );

        assert_eq!(
            plan.commands(),
            &[
                ContentRuntimeCommand::StartDialogue {
                    player_id: 42,
                    dialogue_id: COMMUNITY_INSTRUCTOR_DIALOGUE_ID.to_string(),
                },
                ContentRuntimeCommand::SendNpcDialogue {
                    player_id: 42,
                    npc_name: "Community Instructor".to_string(),
                    lines: vec![
                        "You're almost ready to go out into the main game area".to_string(),
                        "When you get out there".to_string(),
                        "You will be able to interact with thousands of other players".to_string(),
                    ],
                },
                ContentRuntimeCommand::ShowDialogueOptions {
                    player_id: 42,
                    options: vec![
                        "How can I communicate with other players?".to_string(),
                        "Are there rules on ingame behaviour?".to_string(),
                    ],
                },
            ]
        );
    }

    #[test]
    fn runtime_plan_applies_commands_to_sink_in_order() {
        let plan = ContentRuntimePlan::from_effects(vec![
            ContentEffect::message(7, "Hello."),
            ContentEffect::open_shop(7, 3),
            ContentEffect::open_bank(7),
            ContentEffect::start_dialogue(7, "authentic.dialogue"),
            ContentEffect::npc_dialogue(7, "Guide", ["Welcome to the world of runescape"]),
            ContentEffect::dialogue_options(7, ["Who are you?", "Where am I?"]),
            ContentEffect::set_quest_stage(7, "tutorial", 15),
            ContentEffect::give_item(7, 10, 2),
            ContentEffect::take_item(7, 20, 5),
        ]);
        let mut sink = RecordingSink::default();

        plan.apply_to(&mut sink).unwrap();

        assert_eq!(
            sink.actions,
            vec![
                RecordedRuntimeAction::Message(7, "Hello.".to_string()),
                RecordedRuntimeAction::Shop(7, 3),
                RecordedRuntimeAction::Bank(7),
                RecordedRuntimeAction::Dialogue(7, "authentic.dialogue".to_string()),
                RecordedRuntimeAction::NpcDialogue(
                    7,
                    "Guide".to_string(),
                    vec!["Welcome to the world of runescape".to_string()]
                ),
                RecordedRuntimeAction::DialogueOptions(
                    7,
                    vec!["Who are you?".to_string(), "Where am I?".to_string()]
                ),
                RecordedRuntimeAction::QuestStage(7, "tutorial".to_string(), 15),
                RecordedRuntimeAction::AddItem(7, 10, 2),
                RecordedRuntimeAction::RemoveItem(7, 20, 5),
            ]
        );
        assert_eq!(sink.packets.len(), 2);
        assert_eq!(sink.packets[0].opcode, ServerOpcode::NpcMessage as u8);
        assert_eq!(
            sink.packets[0].payload,
            b"Guide\0Welcome to the world of runescape\0".to_vec()
        );
        assert_eq!(sink.packets[1].opcode, ServerOpcode::DialogueOptions as u8);
        assert_eq!(
            sink.packets[1].payload,
            b"\x02Who are you?\0Where am I?\0".to_vec()
        );
    }

    #[test]
    fn runtime_plan_reports_first_failed_command_index() {
        let plan = ContentRuntimePlan::from_effects(vec![
            ContentEffect::message(7, "first"),
            ContentEffect::set_quest_stage(7, "tutorial", 15),
            ContentEffect::message(7, "after failure"),
        ]);
        let mut sink = RecordingSink {
            fail_on: Some(1),
            ..RecordingSink::default()
        };

        let error = plan.apply_to(&mut sink).unwrap_err();

        assert_eq!(
            error,
            ContentRuntimeError::CommandFailed {
                index: 1,
                reason: "planned failure at action 1".to_string(),
            }
        );
        assert_eq!(
            sink.actions,
            vec![RecordedRuntimeAction::Message(7, "first".to_string())]
        );
    }
}
