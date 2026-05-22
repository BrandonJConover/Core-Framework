//! Compiled content plugin scaffolding.
//!
//! Java content is registered through plugin trigger classes. Rust parity uses
//! compiled modules instead: each module registers one or more typed triggers
//! at startup, and live handlers dispatch through this registry.

use std::collections::HashMap;

use super::entity::Position;

pub mod beginner;
pub mod runtime;

pub fn default_content_registry() -> ContentRegistry {
    let mut registry = ContentRegistry::new();
    beginner::BeginnerTutorialPlugin.register(&mut registry);
    registry
}

/// Stable trigger categories mirroring the Java plugin system at a coarse
/// level. Keep this list small until handlers wire real dispatch paths.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TriggerKind {
    TalkNpc,
    NpcCommand,
    UseObject,
    UseBoundary,
    UseItem,
    UseItemOnItem,
    UseItemOnNpc,
    UseItemOnObject,
    DialogueAnswer,
    EnterArea,
    KillNpc,
    Command,
}

/// Stable typed key used to route compiled content triggers before calling
/// their handler. `Any` preserves coarse kind-wide triggers while the specific
/// variants let dialogue and quest content avoid hand-filtering every event.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ContentTriggerKey {
    Any(TriggerKind),
    TalkNpc { npc_id: u32 },
    NpcCommand { npc_id: u32, command: u8 },
    UseObject { object_id: u32, command: u8 },
    UseBoundary { boundary_id: u32, command: u8 },
    UseItem { item_id: u32 },
    UseItemOnItem { item_id: u32, target_item_id: u32 },
    UseItemOnNpc { item_id: u32, npc_id: u32 },
    UseItemOnObject { item_id: u32, object_id: u32 },
    DialogueAnswer,
    EnterArea { area_id: u32 },
    KillNpc { npc_id: u32 },
    Command { command: String },
}

impl ContentTriggerKey {
    pub fn any(kind: TriggerKind) -> Self {
        Self::Any(kind)
    }

    pub fn kind(&self) -> TriggerKind {
        match self {
            Self::Any(kind) => *kind,
            Self::TalkNpc { .. } => TriggerKind::TalkNpc,
            Self::NpcCommand { .. } => TriggerKind::NpcCommand,
            Self::UseObject { .. } => TriggerKind::UseObject,
            Self::UseBoundary { .. } => TriggerKind::UseBoundary,
            Self::UseItem { .. } => TriggerKind::UseItem,
            Self::UseItemOnItem { .. } => TriggerKind::UseItemOnItem,
            Self::UseItemOnNpc { .. } => TriggerKind::UseItemOnNpc,
            Self::UseItemOnObject { .. } => TriggerKind::UseItemOnObject,
            Self::DialogueAnswer => TriggerKind::DialogueAnswer,
            Self::EnterArea { .. } => TriggerKind::EnterArea,
            Self::KillNpc { .. } => TriggerKind::KillNpc,
            Self::Command { .. } => TriggerKind::Command,
        }
    }
}

/// Typed content event passed to compiled plugin triggers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContentEvent {
    TalkNpc {
        player_id: u64,
        npc_id: u32,
        npc_index: u16,
    },
    NpcCommand {
        player_id: u64,
        npc_id: u32,
        command: u8,
    },
    UseObject {
        player_id: u64,
        object_id: u32,
        position: Position,
        command: u8,
    },
    UseBoundary {
        player_id: u64,
        boundary_id: u32,
        position: Position,
        command: u8,
    },
    UseItem {
        player_id: u64,
        item_id: u32,
        slot: usize,
    },
    UseItemOnItem {
        player_id: u64,
        item_id: u32,
        item_slot: usize,
        target_item_id: u32,
        target_slot: usize,
    },
    UseItemOnNpc {
        player_id: u64,
        item_id: u32,
        item_slot: usize,
        npc_id: u32,
        npc_index: u16,
    },
    UseItemOnObject {
        player_id: u64,
        item_id: u32,
        item_slot: usize,
        object_id: u32,
        position: Position,
    },
    DialogueAnswer {
        player_id: u64,
        option: i8,
    },
    EnterArea {
        player_id: u64,
        area_id: u32,
        position: Position,
    },
    KillNpc {
        player_id: u64,
        npc_id: u32,
    },
    Command {
        player_id: u64,
        command: String,
        args: Vec<String>,
    },
}

impl ContentEvent {
    pub fn player_id(&self) -> u64 {
        match self {
            Self::TalkNpc { player_id, .. }
            | Self::NpcCommand { player_id, .. }
            | Self::UseObject { player_id, .. }
            | Self::UseBoundary { player_id, .. }
            | Self::UseItem { player_id, .. }
            | Self::UseItemOnItem { player_id, .. }
            | Self::UseItemOnNpc { player_id, .. }
            | Self::UseItemOnObject { player_id, .. }
            | Self::DialogueAnswer { player_id, .. }
            | Self::EnterArea { player_id, .. }
            | Self::KillNpc { player_id, .. }
            | Self::Command { player_id, .. } => *player_id,
        }
    }

    pub fn kind(&self) -> TriggerKind {
        match self {
            Self::TalkNpc { .. } => TriggerKind::TalkNpc,
            Self::NpcCommand { .. } => TriggerKind::NpcCommand,
            Self::UseObject { .. } => TriggerKind::UseObject,
            Self::UseBoundary { .. } => TriggerKind::UseBoundary,
            Self::UseItem { .. } => TriggerKind::UseItem,
            Self::UseItemOnItem { .. } => TriggerKind::UseItemOnItem,
            Self::UseItemOnNpc { .. } => TriggerKind::UseItemOnNpc,
            Self::UseItemOnObject { .. } => TriggerKind::UseItemOnObject,
            Self::DialogueAnswer { .. } => TriggerKind::DialogueAnswer,
            Self::EnterArea { .. } => TriggerKind::EnterArea,
            Self::KillNpc { .. } => TriggerKind::KillNpc,
            Self::Command { .. } => TriggerKind::Command,
        }
    }

    pub fn trigger_key(&self) -> ContentTriggerKey {
        match self {
            Self::TalkNpc { npc_id, .. } => ContentTriggerKey::TalkNpc { npc_id: *npc_id },
            Self::NpcCommand {
                npc_id, command, ..
            } => ContentTriggerKey::NpcCommand {
                npc_id: *npc_id,
                command: *command,
            },
            Self::UseObject {
                object_id, command, ..
            } => ContentTriggerKey::UseObject {
                object_id: *object_id,
                command: *command,
            },
            Self::UseBoundary {
                boundary_id,
                command,
                ..
            } => ContentTriggerKey::UseBoundary {
                boundary_id: *boundary_id,
                command: *command,
            },
            Self::UseItem { item_id, .. } => ContentTriggerKey::UseItem { item_id: *item_id },
            Self::UseItemOnItem {
                item_id,
                target_item_id,
                ..
            } => ContentTriggerKey::UseItemOnItem {
                item_id: *item_id,
                target_item_id: *target_item_id,
            },
            Self::UseItemOnNpc {
                item_id, npc_id, ..
            } => ContentTriggerKey::UseItemOnNpc {
                item_id: *item_id,
                npc_id: *npc_id,
            },
            Self::UseItemOnObject {
                item_id, object_id, ..
            } => ContentTriggerKey::UseItemOnObject {
                item_id: *item_id,
                object_id: *object_id,
            },
            Self::DialogueAnswer { .. } => ContentTriggerKey::DialogueAnswer,
            Self::EnterArea { area_id, .. } => ContentTriggerKey::EnterArea { area_id: *area_id },
            Self::KillNpc { npc_id, .. } => ContentTriggerKey::KillNpc { npc_id: *npc_id },
            Self::Command { command, .. } => ContentTriggerKey::Command {
                command: command.to_ascii_lowercase(),
            },
        }
    }
}

/// Effects requested by content. Live handlers are responsible for translating
/// these into world/player mutations and packets.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContentEffect {
    Message {
        player_id: u64,
        text: String,
    },
    OpenShop {
        player_id: u64,
        shop_id: u32,
    },
    StartDialogue {
        player_id: u64,
        dialogue_id: String,
    },
    SetQuestStage {
        player_id: u64,
        quest_id: String,
        stage: i32,
    },
    GiveItem {
        player_id: u64,
        item_id: u32,
        amount: u32,
    },
    TakeItem {
        player_id: u64,
        item_id: u32,
        amount: u32,
    },
}

impl ContentEffect {
    pub fn message(player_id: u64, text: impl Into<String>) -> Self {
        Self::Message {
            player_id,
            text: text.into(),
        }
    }

    pub fn open_shop(player_id: u64, shop_id: u32) -> Self {
        Self::OpenShop { player_id, shop_id }
    }

    pub fn start_dialogue(player_id: u64, dialogue_id: impl Into<String>) -> Self {
        Self::StartDialogue {
            player_id,
            dialogue_id: dialogue_id.into(),
        }
    }

    pub fn set_quest_stage(player_id: u64, quest_id: impl Into<String>, stage: i32) -> Self {
        Self::SetQuestStage {
            player_id,
            quest_id: quest_id.into(),
            stage,
        }
    }

    pub fn give_item(player_id: u64, item_id: u32, amount: u32) -> Self {
        Self::GiveItem {
            player_id,
            item_id,
            amount,
        }
    }

    pub fn take_item(player_id: u64, item_id: u32, amount: u32) -> Self {
        Self::TakeItem {
            player_id,
            item_id,
            amount,
        }
    }
}

pub type ContentResult = Vec<ContentEffect>;

/// A compiled Rust content module. Modules register definitions and triggers
/// at startup; they should not own runtime player/world state directly.
pub trait ContentPlugin: Send + Sync + 'static {
    fn id(&self) -> &'static str;
    fn register(&self, registry: &mut ContentRegistry);
}

/// A compiled content module trigger.
pub trait ContentTrigger: Send + Sync {
    fn name(&self) -> &'static str;
    fn kind(&self) -> TriggerKind;
    fn handle(&self, event: &ContentEvent) -> ContentResult;
}

#[derive(Default)]
pub struct ContentRegistry {
    triggers: HashMap<ContentTriggerKey, Vec<Box<dyn ContentTrigger>>>,
}

impl ContentRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register<T>(&mut self, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::any(trigger.kind()), trigger);
    }

    pub fn register_for<T>(&mut self, key: ContentTriggerKey, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        assert_eq!(
            key.kind(),
            trigger.kind(),
            "content trigger key kind must match trigger kind"
        );
        self.triggers
            .entry(key)
            .or_default()
            .push(Box::new(trigger));
    }

    pub fn on_talk_npc<T>(&mut self, npc_id: u32, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::TalkNpc { npc_id }, trigger);
    }

    pub fn on_npc_command<T>(&mut self, npc_id: u32, command: u8, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::NpcCommand { npc_id, command }, trigger);
    }

    pub fn on_use_object<T>(&mut self, object_id: u32, command: u8, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::UseObject { object_id, command }, trigger);
    }

    pub fn on_use_boundary<T>(&mut self, boundary_id: u32, command: u8, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(
            ContentTriggerKey::UseBoundary {
                boundary_id,
                command,
            },
            trigger,
        );
    }

    pub fn on_use_item<T>(&mut self, item_id: u32, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::UseItem { item_id }, trigger);
    }

    pub fn on_use_item_on_item<T>(&mut self, item_id: u32, target_item_id: u32, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(
            ContentTriggerKey::UseItemOnItem {
                item_id,
                target_item_id,
            },
            trigger,
        );
    }

    pub fn on_use_item_on_npc<T>(&mut self, item_id: u32, npc_id: u32, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::UseItemOnNpc { item_id, npc_id }, trigger);
    }

    pub fn on_use_item_on_object<T>(&mut self, item_id: u32, object_id: u32, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(
            ContentTriggerKey::UseItemOnObject { item_id, object_id },
            trigger,
        );
    }

    pub fn on_dialogue_answer<T>(&mut self, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::DialogueAnswer, trigger);
    }

    pub fn on_enter_area<T>(&mut self, area_id: u32, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::EnterArea { area_id }, trigger);
    }

    pub fn on_kill_npc<T>(&mut self, npc_id: u32, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(ContentTriggerKey::KillNpc { npc_id }, trigger);
    }

    pub fn on_command<T>(&mut self, command: impl Into<String>, trigger: T)
    where
        T: ContentTrigger + 'static,
    {
        self.register_for(
            ContentTriggerKey::Command {
                command: command.into().to_ascii_lowercase(),
            },
            trigger,
        );
    }

    pub fn dispatch(&self, event: &ContentEvent) -> ContentResult {
        let mut effects = Vec::new();
        self.dispatch_key(&event.trigger_key(), event, &mut effects);
        self.dispatch_key(&ContentTriggerKey::any(event.kind()), event, &mut effects);
        effects
    }

    pub fn count_for(&self, kind: TriggerKind) -> usize {
        self.triggers
            .iter()
            .filter(|(key, _)| key.kind() == kind)
            .map(|(_, triggers)| triggers.len())
            .sum()
    }

    pub fn count_for_key(&self, key: &ContentTriggerKey) -> usize {
        self.triggers.get(key).map_or(0, Vec::len)
    }

    fn dispatch_key(
        &self,
        key: &ContentTriggerKey,
        event: &ContentEvent,
        effects: &mut ContentResult,
    ) {
        if let Some(triggers) = self.triggers.get(key) {
            effects.extend(triggers.iter().flat_map(|trigger| trigger.handle(event)));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct LumbridgeGuide;

    impl ContentTrigger for LumbridgeGuide {
        fn name(&self) -> &'static str {
            "lumbridge_guide"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::TalkNpc
        }

        fn handle(&self, event: &ContentEvent) -> ContentResult {
            match event {
                ContentEvent::TalkNpc {
                    player_id, npc_id, ..
                } if *npc_id == 1 => {
                    vec![ContentEffect::Message {
                        player_id: *player_id,
                        text: "Welcome to Lumbridge.".to_string(),
                    }]
                }
                _ => Vec::new(),
            }
        }
    }

    struct TalkNpcMessage(&'static str);

    impl ContentTrigger for TalkNpcMessage {
        fn name(&self) -> &'static str {
            "talk_npc_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::TalkNpc
        }

        fn handle(&self, event: &ContentEvent) -> ContentResult {
            match event {
                ContentEvent::TalkNpc { player_id, .. } => {
                    vec![ContentEffect::Message {
                        player_id: *player_id,
                        text: self.0.to_string(),
                    }]
                }
                _ => Vec::new(),
            }
        }
    }

    struct CommandMessage;

    impl ContentTrigger for CommandMessage {
        fn name(&self) -> &'static str {
            "command_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::Command
        }

        fn handle(&self, event: &ContentEvent) -> ContentResult {
            match event {
                ContentEvent::Command {
                    player_id, args, ..
                } => {
                    vec![ContentEffect::Message {
                        player_id: *player_id,
                        text: format!("quest args: {}", args.len()),
                    }]
                }
                _ => Vec::new(),
            }
        }
    }

    struct DialogueAnswerMessage;

    impl ContentTrigger for DialogueAnswerMessage {
        fn name(&self) -> &'static str {
            "dialogue_answer_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::DialogueAnswer
        }

        fn handle(&self, event: &ContentEvent) -> ContentResult {
            match event {
                ContentEvent::DialogueAnswer { player_id, option } => {
                    vec![ContentEffect::Message {
                        player_id: *player_id,
                        text: format!("selected option {option}"),
                    }]
                }
                _ => Vec::new(),
            }
        }
    }

    #[test]
    fn registry_dispatches_matching_trigger() {
        let mut registry = ContentRegistry::new();
        registry.register(LumbridgeGuide);

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: 1,
            npc_index: 7,
        });

        assert_eq!(registry.count_for(TriggerKind::TalkNpc), 1);
        assert_eq!(
            effects,
            vec![ContentEffect::Message {
                player_id: 42,
                text: "Welcome to Lumbridge.".to_string(),
            }]
        );
    }

    #[test]
    fn registry_dispatches_specific_typed_trigger_key() {
        let mut registry = ContentRegistry::new();
        registry.on_talk_npc(1, TalkNpcMessage("Hello, traveller."));

        let matching = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: 1,
            npc_index: 7,
        });
        let non_matching = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: 2,
            npc_index: 8,
        });

        assert_eq!(
            registry.count_for_key(&ContentTriggerKey::TalkNpc { npc_id: 1 }),
            1
        );
        assert_eq!(
            matching,
            vec![ContentEffect::Message {
                player_id: 42,
                text: "Hello, traveller.".to_string(),
            }]
        );
        assert!(non_matching.is_empty());
    }

    #[test]
    fn registry_dispatches_specific_then_kind_wide_triggers() {
        let mut registry = ContentRegistry::new();
        registry.on_talk_npc(1, TalkNpcMessage("Exact NPC trigger."));
        registry.register(TalkNpcMessage("Any NPC trigger."));

        let effects = registry.dispatch(&ContentEvent::TalkNpc {
            player_id: 42,
            npc_id: 1,
            npc_index: 7,
        });

        assert_eq!(
            effects,
            vec![
                ContentEffect::Message {
                    player_id: 42,
                    text: "Exact NPC trigger.".to_string(),
                },
                ContentEffect::Message {
                    player_id: 42,
                    text: "Any NPC trigger.".to_string(),
                },
            ]
        );
    }

    #[test]
    fn command_triggers_are_case_insensitive() {
        let mut registry = ContentRegistry::new();
        registry.on_command("Quest", CommandMessage);

        let effects = registry.dispatch(&ContentEvent::Command {
            player_id: 42,
            command: "QUEST".to_string(),
            args: vec!["cook".to_string()],
        });

        assert_eq!(
            effects,
            vec![ContentEffect::Message {
                player_id: 42,
                text: "quest args: 1".to_string(),
            }]
        );
    }

    #[test]
    fn registry_dispatches_dialogue_answer_trigger() {
        let mut registry = ContentRegistry::new();
        registry.on_dialogue_answer(DialogueAnswerMessage);

        let effects = registry.dispatch(&ContentEvent::DialogueAnswer {
            player_id: 42,
            option: 2,
        });

        assert_eq!(
            registry.count_for_key(&ContentTriggerKey::DialogueAnswer),
            1
        );
        assert_eq!(
            effects,
            vec![ContentEffect::Message {
                player_id: 42,
                text: "selected option 2".to_string(),
            }]
        );
    }

    #[test]
    #[should_panic(expected = "content trigger key kind must match trigger kind")]
    fn registry_rejects_mismatched_trigger_key_kind() {
        let mut registry = ContentRegistry::new();
        registry.register_for(
            ContentTriggerKey::UseItem { item_id: 10 },
            TalkNpcMessage("nope"),
        );
    }

    #[test]
    fn registry_ignores_unregistered_trigger_kind() {
        let registry = ContentRegistry::new();
        let effects = registry.dispatch(&ContentEvent::Command {
            player_id: 42,
            command: "online".to_string(),
            args: Vec::new(),
        });
        assert!(effects.is_empty());
    }

    struct BeginnerPlugin;

    impl ContentPlugin for BeginnerPlugin {
        fn id(&self) -> &'static str {
            "authentic.free.beginner"
        }

        fn register(&self, registry: &mut ContentRegistry) {
            registry.register(LumbridgeGuide);
        }
    }

    #[test]
    fn plugin_registers_its_triggers() {
        let mut registry = ContentRegistry::new();
        let plugin = BeginnerPlugin;
        plugin.register(&mut registry);

        assert_eq!(plugin.id(), "authentic.free.beginner");
        assert_eq!(registry.count_for(TriggerKind::TalkNpc), 1);
    }
}
