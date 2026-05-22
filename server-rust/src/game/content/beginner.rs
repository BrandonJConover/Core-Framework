//! First compiled beginner/tutorial content slice.
//!
//! This mirrors the Java plugin shape as Rust triggers that return effects.
//! Runtime handlers can later translate these effects into dialogue packets,
//! tutorial cache/quest mutations, and messages.

use super::{
    ContentEffect, ContentEvent, ContentPlugin, ContentRegistry, ContentResult, ContentTrigger,
    TriggerKind,
};

pub const GUIDE_STARTING_NPC_ID: u32 = 476;
pub const COMBAT_INSTRUCTOR_NPC_ID: u32 = 474;
pub const FISHING_INSTRUCTOR_NPC_ID: u32 = 479;
pub const FINANCIAL_ADVISOR_NPC_ID: u32 = 480;
pub const MINING_INSTRUCTOR_NPC_ID: u32 = 482;
pub const CONTROLS_GUIDE_NPC_ID: u32 = 499;
pub const QUEST_ADVISOR_NPC_ID: u32 = 489;
pub const WILDERNESS_GUIDE_NPC_ID: u32 = 493;
pub const WOODEN_SHIELD_ITEM_ID: u32 = 4;
pub const BRONZE_LONG_SWORD_ITEM_ID: u32 = 70;
pub const NET_ITEM_ID: u32 = 376;
pub const TUTORIAL_QUEST_ID: &str = "tutorial";
pub const GUIDE_STARTING_DIALOGUE_ID: &str = "authentic.tutorial.guide_starting";
pub const COMBAT_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.combat_instructor";
pub const FISHING_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.fishing_instructor";
pub const FINANCIAL_ADVISOR_DIALOGUE_ID: &str = "authentic.tutorial.financial_advisor";
pub const MINING_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.mining_instructor";
pub const CONTROLS_GUIDE_DIALOGUE_ID: &str = "authentic.tutorial.controls_guide";
pub const QUEST_ADVISOR_DIALOGUE_ID: &str = "authentic.tutorial.quest_advisor";
pub const WILDERNESS_GUIDE_DIALOGUE_ID: &str = "authentic.tutorial.wilderness_guide";
pub const GUIDE_RECAP_COMMAND: u8 = 0;

#[derive(Debug, Default)]
pub struct BeginnerTutorialPlugin;

impl ContentPlugin for BeginnerTutorialPlugin {
    fn id(&self) -> &'static str {
        "authentic.tutorial.beginner"
    }

    fn register(&self, registry: &mut ContentRegistry) {
        registry.on_talk_npc(GUIDE_STARTING_NPC_ID, StartingGuideTalk);
        registry.on_npc_command(
            GUIDE_STARTING_NPC_ID,
            GUIDE_RECAP_COMMAND,
            StartingGuideRecap,
        );
        registry.on_talk_npc(COMBAT_INSTRUCTOR_NPC_ID, CombatInstructorTalk);
        registry.on_talk_npc(FISHING_INSTRUCTOR_NPC_ID, FishingInstructorTalk);
        registry.on_talk_npc(FINANCIAL_ADVISOR_NPC_ID, FinancialAdvisorTalk);
        registry.on_talk_npc(MINING_INSTRUCTOR_NPC_ID, MiningInstructorTalk);
        registry.on_talk_npc(CONTROLS_GUIDE_NPC_ID, ControlsGuideTalk);
        registry.on_talk_npc(QUEST_ADVISOR_NPC_ID, QuestAdvisorTalk);
        registry.on_talk_npc(WILDERNESS_GUIDE_NPC_ID, WildernessGuideTalk);
    }
}

#[derive(Debug)]
struct StartingGuideTalk;

impl ContentTrigger for StartingGuideTalk {
    fn name(&self) -> &'static str {
        "tutorial_starting_guide_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, GUIDE_STARTING_DIALOGUE_ID),
                    ContentEffect::message(player_id, "Welcome to the world of runescape"),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 10),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct StartingGuideRecap;

impl ContentTrigger for StartingGuideRecap {
    fn name(&self) -> &'static str {
        "tutorial_starting_guide_recap"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::NpcCommand
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::NpcCommand { .. } => {
                let player_id = event.player_id();
                vec![ContentEffect::message(
                    player_id,
                    "Speak to the guides and advisors on the island",
                )]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct CombatInstructorTalk;

impl ContentTrigger for CombatInstructorTalk {
    fn name(&self) -> &'static str {
        "tutorial_combat_instructor_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, COMBAT_INSTRUCTOR_DIALOGUE_ID),
                    ContentEffect::message(
                        player_id,
                        "The instructor gives you a sword and shield",
                    ),
                    ContentEffect::give_item(player_id, WOODEN_SHIELD_ITEM_ID, 1),
                    ContentEffect::give_item(player_id, BRONZE_LONG_SWORD_ITEM_ID, 1),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 16),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct FishingInstructorTalk;

impl ContentTrigger for FishingInstructorTalk {
    fn name(&self) -> &'static str {
        "tutorial_fishing_instructor_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, FISHING_INSTRUCTOR_DIALOGUE_ID),
                    ContentEffect::message(player_id, "Yes that's right, you're a smart one"),
                    ContentEffect::message(
                        player_id,
                        "the fishing instructor gives you a somewhat old looking net",
                    ),
                    ContentEffect::give_item(player_id, NET_ITEM_ID, 1),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 41),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct FinancialAdvisorTalk;

impl ContentTrigger for FinancialAdvisorTalk {
    fn name(&self) -> &'static str {
        "tutorial_financial_advisor_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, FINANCIAL_ADVISOR_DIALOGUE_ID),
                    ContentEffect::message(player_id, "Hello there"),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 40),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct MiningInstructorTalk;

impl ContentTrigger for MiningInstructorTalk {
    fn name(&self) -> &'static str {
        "tutorial_mining_instructor_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, MINING_INSTRUCTOR_DIALOGUE_ID),
                    ContentEffect::message(player_id, "hello I'm a veteran miner!"),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 49),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct ControlsGuideTalk;

impl ContentTrigger for ControlsGuideTalk {
    fn name(&self) -> &'static str {
        "tutorial_controls_guide_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, CONTROLS_GUIDE_DIALOGUE_ID),
                    ContentEffect::message(
                        player_id,
                        "Hello I'm here to tell you more about the game's controls",
                    ),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 15),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct QuestAdvisorTalk;

impl ContentTrigger for QuestAdvisorTalk {
    fn name(&self) -> &'static str {
        "tutorial_quest_advisor_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, QUEST_ADVISOR_DIALOGUE_ID),
                    ContentEffect::message(player_id, "Greetings traveller"),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 65),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct WildernessGuideTalk;

impl ContentTrigger for WildernessGuideTalk {
    fn name(&self) -> &'static str {
        "tutorial_wilderness_guide_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, WILDERNESS_GUIDE_DIALOGUE_ID),
                    ContentEffect::message(
                        player_id,
                        "Hi are you someone who likes to fight other players?",
                    ),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 70),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn beginner_plugin_registers_tutorial_triggers() {
        let mut registry = ContentRegistry::new();
        let plugin = BeginnerTutorialPlugin;

        plugin.register(&mut registry);

        assert_eq!(plugin.id(), "authentic.tutorial.beginner");
        assert_eq!(registry.count_for(TriggerKind::TalkNpc), 8);
        assert_eq!(registry.count_for(TriggerKind::NpcCommand), 1);
    }

    #[test]
    fn starting_guide_talk_returns_dialogue_message_and_stage_effects() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: GUIDE_STARTING_NPC_ID,
            npc_index: 7,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, GUIDE_STARTING_DIALOGUE_ID),
                ContentEffect::message(42, "Welcome to the world of runescape"),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 10),
            ]
        );
    }

    #[test]
    fn starting_guide_npc_command_returns_message_effect() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::NpcCommand {
            player_id: 42,
            npc_id: GUIDE_STARTING_NPC_ID,
            command: GUIDE_RECAP_COMMAND,
        });

        assert_eq!(
            effects,
            vec![ContentEffect::message(
                42,
                "Speak to the guides and advisors on the island",
            )]
        );
    }

    #[test]
    fn combat_instructor_talk_gives_equipment_and_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: COMBAT_INSTRUCTOR_NPC_ID,
            npc_index: 12,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, COMBAT_INSTRUCTOR_DIALOGUE_ID),
                ContentEffect::message(42, "The instructor gives you a sword and shield"),
                ContentEffect::give_item(42, WOODEN_SHIELD_ITEM_ID, 1),
                ContentEffect::give_item(42, BRONZE_LONG_SWORD_ITEM_ID, 1),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 16),
            ]
        );
    }

    #[test]
    fn fishing_instructor_talk_gives_net_and_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: FISHING_INSTRUCTOR_NPC_ID,
            npc_index: 13,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, FISHING_INSTRUCTOR_DIALOGUE_ID),
                ContentEffect::message(42, "Yes that's right, you're a smart one"),
                ContentEffect::message(
                    42,
                    "the fishing instructor gives you a somewhat old looking net",
                ),
                ContentEffect::give_item(42, NET_ITEM_ID, 1),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 41),
            ]
        );
    }

    #[test]
    fn financial_advisor_talk_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: FINANCIAL_ADVISOR_NPC_ID,
            npc_index: 9,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, FINANCIAL_ADVISOR_DIALOGUE_ID),
                ContentEffect::message(42, "Hello there"),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 40),
            ]
        );
    }

    #[test]
    fn mining_instructor_talk_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: MINING_INSTRUCTOR_NPC_ID,
            npc_index: 12,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, MINING_INSTRUCTOR_DIALOGUE_ID),
                ContentEffect::message(42, "hello I'm a veteran miner!"),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 49),
            ]
        );
    }

    #[test]
    fn controls_guide_talk_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: CONTROLS_GUIDE_NPC_ID,
            npc_index: 8,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, CONTROLS_GUIDE_DIALOGUE_ID),
                ContentEffect::message(
                    42,
                    "Hello I'm here to tell you more about the game's controls",
                ),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 15),
            ]
        );
    }

    #[test]
    fn quest_advisor_talk_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: QUEST_ADVISOR_NPC_ID,
            npc_index: 10,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, QUEST_ADVISOR_DIALOGUE_ID),
                ContentEffect::message(42, "Greetings traveller"),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 65),
            ]
        );
    }

    #[test]
    fn wilderness_guide_talk_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: WILDERNESS_GUIDE_NPC_ID,
            npc_index: 11,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, WILDERNESS_GUIDE_DIALOGUE_ID),
                ContentEffect::message(42, "Hi are you someone who likes to fight other players?"),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 70),
            ]
        );
    }
}
