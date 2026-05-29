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
pub const BANK_ASSISTANT_NPC_ID: u32 = 485;
pub const COOKING_INSTRUCTOR_NPC_ID: u32 = 478;
pub const MINING_INSTRUCTOR_NPC_ID: u32 = 482;
pub const CONTROLS_GUIDE_NPC_ID: u32 = 499;
pub const QUEST_ADVISOR_NPC_ID: u32 = 489;
pub const WILDERNESS_GUIDE_NPC_ID: u32 = 493;
pub const MAGIC_INSTRUCTOR_NPC_ID: u32 = 494;
pub const COMMUNITY_INSTRUCTOR_NPC_ID: u32 = 496;
pub const FATIGUE_EXPERT_NPC_ID: u32 = 774;
pub const WOODEN_SHIELD_ITEM_ID: u32 = 4;
pub const BRONZE_LONG_SWORD_ITEM_ID: u32 = 70;
pub const NET_ITEM_ID: u32 = 376;
pub const RAW_RAT_MEAT_ITEM_ID: u32 = 503;
pub const TUTORIAL_QUEST_ID: &str = "tutorial";
pub const GUIDE_STARTING_DIALOGUE_ID: &str = "authentic.tutorial.guide_starting";
pub const COMBAT_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.combat_instructor";
pub const FISHING_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.fishing_instructor";
pub const FINANCIAL_ADVISOR_DIALOGUE_ID: &str = "authentic.tutorial.financial_advisor";
pub const BANK_ASSISTANT_DIALOGUE_ID: &str = "authentic.tutorial.bank_assistant";
pub const COOKING_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.cooking_instructor";
pub const MINING_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.mining_instructor";
pub const CONTROLS_GUIDE_DIALOGUE_ID: &str = "authentic.tutorial.controls_guide";
pub const QUEST_ADVISOR_DIALOGUE_ID: &str = "authentic.tutorial.quest_advisor";
pub const WILDERNESS_GUIDE_DIALOGUE_ID: &str = "authentic.tutorial.wilderness_guide";
pub const MAGIC_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.magic_instructor";
pub const COMMUNITY_INSTRUCTOR_DIALOGUE_ID: &str = "authentic.tutorial.community_instructor";
pub const FATIGUE_EXPERT_DIALOGUE_ID: &str = "authentic.tutorial.fatigue_expert";
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
        registry.on_talk_npc(BANK_ASSISTANT_NPC_ID, BankAssistantTalk);
        registry.on_dialogue_answer(BankAssistantAnswer);
        registry.on_talk_npc(COOKING_INSTRUCTOR_NPC_ID, CookingInstructorTalk);
        registry.on_talk_npc(MINING_INSTRUCTOR_NPC_ID, MiningInstructorTalk);
        registry.on_talk_npc(CONTROLS_GUIDE_NPC_ID, ControlsGuideTalk);
        registry.on_talk_npc(QUEST_ADVISOR_NPC_ID, QuestAdvisorTalk);
        registry.on_talk_npc(WILDERNESS_GUIDE_NPC_ID, WildernessGuideTalk);
        registry.on_talk_npc(MAGIC_INSTRUCTOR_NPC_ID, MagicInstructorTalk);
        registry.on_talk_npc(COMMUNITY_INSTRUCTOR_NPC_ID, CommunityInstructorTalk);
        registry.on_talk_npc(FATIGUE_EXPERT_NPC_ID, FatigueExpertTalk);
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
struct BankAssistantTalk;

impl ContentTrigger for BankAssistantTalk {
    fn name(&self) -> &'static str {
        "tutorial_bank_assistant_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, BANK_ASSISTANT_DIALOGUE_ID),
                    ContentEffect::npc_dialogue(
                        player_id,
                        "Bank assistant",
                        [
                            "Hello welcome to the bank of runescape",
                            "You can deposit your items in banks",
                            "This allows you to own much more equipment",
                            "Than can be fitted in your inventory",
                            "It will also keep your items safe",
                            "So you won't lose them when you die",
                            "You can withdraw deposited items from any bank in the world",
                        ],
                    ),
                    ContentEffect::dialogue_options(
                        player_id,
                        [
                            "Can I access my bank account please?",
                            "Okay thankyou for your help",
                        ],
                    ),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct BankAssistantAnswer;

impl ContentTrigger for BankAssistantAnswer {
    fn name(&self) -> &'static str {
        "tutorial_bank_assistant_answer"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::DialogueAnswer
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::DialogueAnswer {
                player_id,
                active_dialogue_id: Some(dialogue_id),
                option: 0,
            } if dialogue_id == BANK_ASSISTANT_DIALOGUE_ID => {
                vec![
                    ContentEffect::open_bank(*player_id),
                    ContentEffect::set_quest_stage(*player_id, TUTORIAL_QUEST_ID, 60),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct CookingInstructorTalk;

impl ContentTrigger for CookingInstructorTalk {
    fn name(&self) -> &'static str {
        "tutorial_cooking_instructor_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, COOKING_INSTRUCTOR_DIALOGUE_ID),
                    ContentEffect::npc_dialogue(
                        player_id,
                        "Cooking Instructor",
                        [
                            "looks like you've been fighting",
                            "If you get hurt in a fight",
                            "You will slowly heal",
                            "Eating food will heal you much more quickly",
                            "I'm here to show you some simple cooking",
                        ],
                    ),
                    ContentEffect::give_item(player_id, RAW_RAT_MEAT_ITEM_ID, 1),
                    ContentEffect::npc_dialogue(
                        player_id,
                        "Cooking Instructor",
                        ["First you need something to cook"],
                    ),
                    ContentEffect::message(player_id, "the instructor gives you a piece of meat"),
                    ContentEffect::npc_dialogue(
                        player_id,
                        "Cooking Instructor",
                        [
                            "ok cook it on the range",
                            "To use an item you are holding",
                            "Open your inventory and click on the item you wish to use",
                            "Then click on whatever you wish to use it on",
                            "In this case use it on the range",
                        ],
                    ),
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

#[derive(Debug)]
struct MagicInstructorTalk;

impl ContentTrigger for MagicInstructorTalk {
    fn name(&self) -> &'static str {
        "tutorial_magic_instructor_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, MAGIC_INSTRUCTOR_DIALOGUE_ID),
                    ContentEffect::npc_dialogue(
                        player_id,
                        "Magic Instructor",
                        [
                            "there's good magic potential in this one",
                            "Yes definitely something I can work with",
                        ],
                    ),
                    ContentEffect::dialogue_options(
                        player_id,
                        ["Hmm are you talking about me?", "teach me some magic"],
                    ),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct CommunityInstructorTalk;

impl ContentTrigger for CommunityInstructorTalk {
    fn name(&self) -> &'static str {
        "tutorial_community_instructor_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, COMMUNITY_INSTRUCTOR_DIALOGUE_ID),
                    ContentEffect::npc_dialogue(
                        player_id,
                        "Community Instructor",
                        [
                            "You're almost ready to go out into the main game area",
                            "When you get out there",
                            "You will be able to interact with thousands of other players",
                        ],
                    ),
                    ContentEffect::dialogue_options(
                        player_id,
                        [
                            "How can I communicate with other players?",
                            "Are there rules on ingame behaviour?",
                        ],
                    ),
                ]
            }
            _ => Vec::new(),
        }
    }
}

#[derive(Debug)]
struct FatigueExpertTalk;

impl ContentTrigger for FatigueExpertTalk {
    fn name(&self) -> &'static str {
        "tutorial_fatigue_expert_talk"
    }

    fn kind(&self) -> TriggerKind {
        TriggerKind::TalkNpc
    }

    fn handle(&self, event: &ContentEvent) -> ContentResult {
        match event {
            ContentEvent::TalkNpc { .. } => {
                let player_id = event.player_id();
                vec![
                    ContentEffect::start_dialogue(player_id, FATIGUE_EXPERT_DIALOGUE_ID),
                    ContentEffect::message(
                        player_id,
                        "Hi I'm feeling a little tired after all this learning",
                    ),
                    ContentEffect::npc_dialogue(
                        player_id,
                        "Fatigue expert",
                        [
                            "Yes when you use your skills you will slowly get fatigued",
                            "If you look on your stats menu you will see a fatigue stat",
                            "When your fatigue reaches 100 percent then you will be very tired",
                            "You won't be able to concentrate enough to gain experience in your skills",
                            "To reduce your fatigue you will need to go to sleep",
                            "Click on the bed to go sleep",
                            "Then follow the instructions to wake up",
                            "When you have done that talk to me again",
                        ],
                    ),
                    ContentEffect::set_quest_stage(player_id, TUTORIAL_QUEST_ID, 85),
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
        assert_eq!(registry.count_for(TriggerKind::TalkNpc), 13);
        assert_eq!(registry.count_for(TriggerKind::NpcCommand), 1);
        assert_eq!(registry.count_for(TriggerKind::DialogueAnswer), 1);
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
    fn bank_assistant_talk_explains_bank_and_prompts_for_access() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: BANK_ASSISTANT_NPC_ID,
            npc_index: 18,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, BANK_ASSISTANT_DIALOGUE_ID),
                ContentEffect::npc_dialogue(
                    42,
                    "Bank assistant",
                    [
                        "Hello welcome to the bank of runescape",
                        "You can deposit your items in banks",
                        "This allows you to own much more equipment",
                        "Than can be fitted in your inventory",
                        "It will also keep your items safe",
                        "So you won't lose them when you die",
                        "You can withdraw deposited items from any bank in the world",
                    ],
                ),
                ContentEffect::dialogue_options(
                    42,
                    [
                        "Can I access my bank account please?",
                        "Okay thankyou for your help",
                    ],
                ),
            ]
        );
    }

    #[test]
    fn bank_assistant_matching_dialogue_answer_opens_bank_and_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::DialogueAnswer {
            player_id: 42,
            active_dialogue_id: Some(BANK_ASSISTANT_DIALOGUE_ID.to_string()),
            option: 0,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::open_bank(42),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 60),
            ]
        );
    }

    #[test]
    fn bank_assistant_ignores_other_dialogue_answers() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let wrong_option = registry.dispatch(&ContentEvent::DialogueAnswer {
            player_id: 42,
            active_dialogue_id: Some(BANK_ASSISTANT_DIALOGUE_ID.to_string()),
            option: 1,
        });
        let wrong_dialogue = registry.dispatch(&ContentEvent::DialogueAnswer {
            player_id: 42,
            active_dialogue_id: Some(MAGIC_INSTRUCTOR_DIALOGUE_ID.to_string()),
            option: 0,
        });

        assert!(wrong_option.is_empty());
        assert!(wrong_dialogue.is_empty());
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
    fn cooking_instructor_talk_gives_meat_and_explains_cooking() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: COOKING_INSTRUCTOR_NPC_ID,
            npc_index: 15,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, COOKING_INSTRUCTOR_DIALOGUE_ID),
                ContentEffect::npc_dialogue(
                    42,
                    "Cooking Instructor",
                    [
                        "looks like you've been fighting",
                        "If you get hurt in a fight",
                        "You will slowly heal",
                        "Eating food will heal you much more quickly",
                        "I'm here to show you some simple cooking",
                    ],
                ),
                ContentEffect::give_item(42, RAW_RAT_MEAT_ITEM_ID, 1),
                ContentEffect::npc_dialogue(
                    42,
                    "Cooking Instructor",
                    ["First you need something to cook"],
                ),
                ContentEffect::message(42, "the instructor gives you a piece of meat"),
                ContentEffect::npc_dialogue(
                    42,
                    "Cooking Instructor",
                    [
                        "ok cook it on the range",
                        "To use an item you are holding",
                        "Open your inventory and click on the item you wish to use",
                        "Then click on whatever you wish to use it on",
                        "In this case use it on the range",
                    ],
                ),
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

    #[test]
    fn magic_instructor_talk_returns_intro_dialogue_and_menu_options() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: MAGIC_INSTRUCTOR_NPC_ID,
            npc_index: 17,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, MAGIC_INSTRUCTOR_DIALOGUE_ID),
                ContentEffect::npc_dialogue(
                    42,
                    "Magic Instructor",
                    [
                        "there's good magic potential in this one",
                        "Yes definitely something I can work with",
                    ],
                ),
                ContentEffect::dialogue_options(
                    42,
                    ["Hmm are you talking about me?", "teach me some magic"],
                ),
            ]
        );
    }

    #[test]
    fn community_instructor_talk_returns_intro_dialogue_and_menu_options() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: COMMUNITY_INSTRUCTOR_NPC_ID,
            npc_index: 14,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, COMMUNITY_INSTRUCTOR_DIALOGUE_ID),
                ContentEffect::npc_dialogue(
                    42,
                    "Community Instructor",
                    [
                        "You're almost ready to go out into the main game area",
                        "When you get out there",
                        "You will be able to interact with thousands of other players",
                    ],
                ),
                ContentEffect::dialogue_options(
                    42,
                    [
                        "How can I communicate with other players?",
                        "Are there rules on ingame behaviour?",
                    ],
                ),
            ]
        );
    }

    #[test]
    fn fatigue_expert_talk_explains_fatigue_and_advances_tutorial_stage() {
        let mut registry = ContentRegistry::new();
        BeginnerTutorialPlugin.register(&mut registry);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: FATIGUE_EXPERT_NPC_ID,
            npc_index: 16,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::start_dialogue(42, FATIGUE_EXPERT_DIALOGUE_ID),
                ContentEffect::message(42, "Hi I'm feeling a little tired after all this learning",),
                ContentEffect::npc_dialogue(
                    42,
                    "Fatigue expert",
                    [
                        "Yes when you use your skills you will slowly get fatigued",
                        "If you look on your stats menu you will see a fatigue stat",
                        "When your fatigue reaches 100 percent then you will be very tired",
                        "You won't be able to concentrate enough to gain experience in your skills",
                        "To reduce your fatigue you will need to go to sleep",
                        "Click on the bed to go sleep",
                        "Then follow the instructions to wake up",
                        "When you have done that talk to me again",
                    ],
                ),
                ContentEffect::set_quest_stage(42, TUTORIAL_QUEST_ID, 85),
            ]
        );
    }
}
