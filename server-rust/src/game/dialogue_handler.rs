//! Dialogue handler: wires the dialogue system into the game loop with packet handling.
//!
//! Provides [`DialogueSession`] for tracking per-player dialogue state,
//! [`DialogueHandler`] for managing all active sessions, and packet builders
//! that translate dialogue events into network packets the client understands.

use std::collections::HashMap;

use tracing::{debug, warn};

use super::dialogue::{
    Dialogue, DialogueAction, DialogueManager, DialogueNode, DialogueResult, DialogueState,
};
use super::entity::{EntityId, Position};
use super::protocol::{Packet, ServerOpcode};

// ---------------------------------------------------------------------------
// Dialogue actions (extended set used by the handler)
// ---------------------------------------------------------------------------

/// High-level side-effects that a dialogue node can trigger.
///
/// These are resolved by the game loop *after* the handler emits the
/// corresponding packets.  The existing [`DialogueAction`] in `dialogue.rs`
/// covers the data-model side; this enum adds handler-specific context
/// (e.g. the originating position for teleports).
#[derive(Debug, Clone, PartialEq)]
pub enum HandlerAction {
    /// Open a shop interface.
    OpenShop(u32),
    /// Give an item to the player.
    GiveItem { item_id: u32, amount: u32 },
    /// Take an item from the player.
    TakeItem { item_id: u32, amount: u32 },
    /// Set the player's quest stage.
    SetQuestStage { quest_id: u16, stage: u8 },
    /// Award experience.
    GiveXp { skill_id: u8, amount: u32 },
    /// Teleport the player.
    Teleport(Position),
    /// Open the bank interface.
    OpenBank,
    /// Start (unlock) a quest.
    StartQuest(u16),
}

impl HandlerAction {
    /// Try to convert from the core [`DialogueAction`].
    pub fn from_dialogue_action(action: &DialogueAction) -> Option<Self> {
        match action {
            DialogueAction::OpenShop(id) => Some(HandlerAction::OpenShop(*id)),
            DialogueAction::GiveItem { item_id, amount } => Some(HandlerAction::GiveItem {
                item_id: *item_id,
                amount: *amount,
            }),
            DialogueAction::TakeItem { item_id, amount } => Some(HandlerAction::TakeItem {
                item_id: *item_id,
                amount: *amount,
            }),
            DialogueAction::SetQuestStage { quest_id, stage } => {
                Some(HandlerAction::SetQuestStage {
                    quest_id: *quest_id,
                    stage: *stage,
                })
            }
            DialogueAction::GiveExperience { skill_id, amount } => {
                Some(HandlerAction::GiveXp {
                    skill_id: *skill_id,
                    amount: *amount,
                })
            }
            DialogueAction::Teleport { x, y } => Some(HandlerAction::Teleport(Position::new(
                *x as i32, *y as i32,
            ))),
            DialogueAction::OpenBank => Some(HandlerAction::OpenBank),
            DialogueAction::CompleteQuest(id) => Some(HandlerAction::StartQuest(*id)),
            _ => None,
        }
    }
}

// ---------------------------------------------------------------------------
// Dialogue session
// ---------------------------------------------------------------------------

/// Tracks the state of a single player's active dialogue with an NPC.
#[derive(Debug, Clone)]
pub struct DialogueSession {
    /// The NPC this player is talking to.
    pub npc_id: EntityId,
    /// Current node in the dialogue tree.
    pub current_node: String,
    /// Whether we are waiting for the player to pick a menu option.
    pub awaiting_response: bool,
    /// The dialogue tree driving this conversation.
    pub dialogue_tree: Dialogue,
    /// Name of the NPC (cached for packet building).
    pub npc_name: String,
    /// Underlying dialogue state (variables, pending messages, etc.).
    pub state: DialogueState,
}

impl DialogueSession {
    /// Create a new session for the given NPC and dialogue tree.
    pub fn new(npc_id: EntityId, npc_name: impl Into<String>, tree: Dialogue) -> Self {
        let start = tree.start_node.clone();
        let dialogue_id = tree.id;
        let npc_index = npc_id.0 as u32;
        Self {
            npc_id,
            current_node: start.clone(),
            awaiting_response: false,
            dialogue_tree: tree,
            npc_name: npc_name.into(),
            state: DialogueState::new(dialogue_id, npc_index, start),
        }
    }

    /// Advance to a different node.
    pub fn go_to_node(&mut self, node: impl Into<String>) {
        let node = node.into();
        self.current_node = node.clone();
        self.state.current_node = node;
        self.awaiting_response = false;
    }
}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build an *NPC message* packet.
///
/// Uses [`ServerOpcode::NpcMessage`] (opcode 9).
/// Payload: npc_name (null-terminated) + message (null-terminated).
pub fn build_npc_message_packet(npc_name: &str, message: &str) -> Packet {
    let mut packet = Packet::new(ServerOpcode::NpcMessage as u8);
    packet.add_string(npc_name);
    packet.add_string(message);
    packet
}

/// Build a *dialogue options* / menu packet.
///
/// Uses [`ServerOpcode::DialogueOptions`] (opcode 31).
/// Payload: option_count (byte) + each option (null-terminated string).
pub fn build_option_menu_packet(options: &[String]) -> Packet {
    let mut packet = Packet::new(ServerOpcode::DialogueOptions as u8);
    packet.add_byte(options.len() as u8);
    for option in options {
        packet.add_string(option);
    }
    packet
}

/// Build a *close dialogue* packet.
///
/// Reuses [`ServerOpcode::DialogueOptions`] with a zero-option count,
/// telling the client to dismiss any open dialogue UI.
pub fn build_close_dialogue_packet() -> Packet {
    let mut packet = Packet::new(ServerOpcode::DialogueOptions as u8);
    packet.add_byte(0);
    packet
}

// ---------------------------------------------------------------------------
// Result type returned by the handler
// ---------------------------------------------------------------------------

/// The outcome of processing a dialogue step.
///
/// Contains zero or more packets to send and zero or more side-effect actions
/// for the game loop to execute.
#[derive(Debug)]
pub struct DialogueOutput {
    /// Packets to send to the player.
    pub packets: Vec<Packet>,
    /// Side-effect actions to execute.
    pub actions: Vec<HandlerAction>,
}

impl DialogueOutput {
    fn new() -> Self {
        Self {
            packets: Vec::new(),
            actions: Vec::new(),
        }
    }

    fn with_packets(packets: Vec<Packet>) -> Self {
        Self {
            packets,
            actions: Vec::new(),
        }
    }
}

// ---------------------------------------------------------------------------
// Dialogue handler (manages all active sessions)
// ---------------------------------------------------------------------------

/// Manages every active player dialogue session and owns the shared
/// [`DialogueManager`] that holds all registered dialogue trees.
#[derive(Debug)]
pub struct DialogueHandler {
    /// Active sessions keyed by player id.
    sessions: HashMap<u64, DialogueSession>,
    /// The underlying dialogue registry.
    manager: DialogueManager,
}

impl DialogueHandler {
    // -- construction -------------------------------------------------------

    /// Create a handler with a fresh [`DialogueManager`] (loads defaults).
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
            manager: DialogueManager::new(),
        }
    }

    /// Create a handler with the supplied [`DialogueManager`].
    pub fn with_manager(manager: DialogueManager) -> Self {
        Self {
            sessions: HashMap::new(),
            manager,
        }
    }

    /// Access the underlying dialogue registry (e.g. to register new trees).
    pub fn manager_mut(&mut self) -> &mut DialogueManager {
        &mut self.manager
    }

    // -- queries ------------------------------------------------------------

    /// Whether the player is currently in a dialogue.
    pub fn is_in_dialogue(&self, player_id: u64) -> bool {
        self.sessions.contains_key(&player_id)
    }

    /// Get an immutable reference to a session (if any).
    pub fn get_session(&self, player_id: u64) -> Option<&DialogueSession> {
        self.sessions.get(&player_id)
    }

    // -- start / close ------------------------------------------------------

    /// Start a dialogue between a player and an NPC.
    ///
    /// Looks up the first dialogue tree registered for `npc_id`, creates a
    /// [`DialogueSession`], processes the start node, and returns the packets
    /// the client needs.
    pub fn start_dialogue(
        &mut self,
        player_id: u64,
        npc_id: EntityId,
        npc_name: &str,
    ) -> Result<DialogueOutput, String> {
        // Prevent starting a second dialogue while one is active.
        if self.is_in_dialogue(player_id) {
            return Err("Player is already in a dialogue".to_string());
        }

        let tree = self
            .manager
            .get_first_for_npc(npc_id.0 as u32)
            .cloned()
            .ok_or_else(|| format!("No dialogue found for NPC {}", npc_id))?;

        let session = DialogueSession::new(npc_id, npc_name, tree);
        self.sessions.insert(player_id, session);

        debug!(player_id, %npc_id, "Started dialogue");

        // Process the first node immediately so the player sees content.
        self.advance(player_id)
    }

    /// Start a dialogue from a specific [`Dialogue`] tree (not looked up by NPC).
    pub fn start_dialogue_with_tree(
        &mut self,
        player_id: u64,
        npc_id: EntityId,
        npc_name: &str,
        tree: Dialogue,
    ) -> Result<DialogueOutput, String> {
        if self.is_in_dialogue(player_id) {
            return Err("Player is already in a dialogue".to_string());
        }

        let session = DialogueSession::new(npc_id, npc_name, tree);
        self.sessions.insert(player_id, session);

        debug!(player_id, %npc_id, "Started dialogue (custom tree)");

        self.advance(player_id)
    }

    /// Forcibly close a player's dialogue, returning a close packet.
    pub fn close_dialogue(&mut self, player_id: u64) -> Vec<Packet> {
        if self.sessions.remove(&player_id).is_some() {
            debug!(player_id, "Closed dialogue");
            vec![build_close_dialogue_packet()]
        } else {
            Vec::new()
        }
    }

    // -- menu reply ---------------------------------------------------------

    /// Handle the player selecting an option from a dialogue menu.
    ///
    /// `option_index` is the zero-based index sent by the client
    /// (`ClientOpcode::DialogueOption`).
    pub fn handle_menu_reply(
        &mut self,
        player_id: u64,
        option_index: u8,
    ) -> Result<DialogueOutput, String> {
        // Validate session state.
        {
            let session = self
                .sessions
                .get(&player_id)
                .ok_or("Player is not in a dialogue")?;

            if !session.awaiting_response {
                return Err("Player is not awaiting a dialogue response".to_string());
            }
        }

        // Resolve the chosen option -> next node.
        let next_node = {
            let session = self.sessions.get(&player_id).unwrap();
            let dialogue_id = session.dialogue_tree.id;
            let current = &session.current_node;

            self.manager
                .select_option(dialogue_id, current, option_index as usize)
                .ok_or_else(|| {
                    format!(
                        "Invalid option index {} for node '{}'",
                        option_index, current
                    )
                })?
        };

        // Advance the session to the chosen node.
        {
            let session = self.sessions.get_mut(&player_id).unwrap();
            session.go_to_node(&next_node);
        }

        debug!(player_id, option_index, next_node = %next_node, "Handled menu reply");

        self.advance(player_id)
    }

    // -- internal: advance through nodes ------------------------------------

    /// Walk the dialogue tree from the session's current node, accumulating
    /// packets and actions, until we either need player input or the dialogue
    /// ends.
    fn advance(&mut self, player_id: u64) -> Result<DialogueOutput, String> {
        let mut output = DialogueOutput::new();

        // Cap iterations to prevent infinite loops in malformed trees.
        const MAX_STEPS: usize = 64;

        for _ in 0..MAX_STEPS {
            let (dialogue_id, current_node, npc_name) = {
                let session = match self.sessions.get(&player_id) {
                    Some(s) => s,
                    None => return Ok(output),
                };
                (
                    session.dialogue_tree.id,
                    session.current_node.clone(),
                    session.npc_name.clone(),
                )
            };

            let result = self.manager.process_node(dialogue_id, &current_node);

            match result {
                DialogueResult::NpcMessage(lines) => {
                    // Send each line as its own NPC message packet.
                    for line in &lines {
                        output
                            .packets
                            .push(build_npc_message_packet(&npc_name, line));
                    }
                    // NpcSay with no `next` -> end.
                    self.sessions.remove(&player_id);
                    output.packets.push(build_close_dialogue_packet());
                    return Ok(output);
                }
                DialogueResult::PlayerMessage(text) => {
                    output
                        .packets
                        .push(build_npc_message_packet(&npc_name, &text));
                    self.sessions.remove(&player_id);
                    output.packets.push(build_close_dialogue_packet());
                    return Ok(output);
                }
                DialogueResult::ShowOptions(options) => {
                    output.packets.push(build_option_menu_packet(&options));
                    if let Some(session) = self.sessions.get_mut(&player_id) {
                        session.awaiting_response = true;
                    }
                    return Ok(output);
                }
                DialogueResult::ExecuteAction(action) => {
                    // Convert to handler action.
                    if let Some(ha) = HandlerAction::from_dialogue_action(&action) {
                        output.actions.push(ha);
                    }

                    // Look up the `next` pointer on the Action node so we can
                    // continue walking the tree.
                    let next = {
                        let session = self.sessions.get(&player_id).unwrap();
                        let node = session.dialogue_tree.get_node(&current_node);
                        match node {
                            Some(DialogueNode::Action { next, .. }) => next.clone(),
                            _ => None,
                        }
                    };

                    match next {
                        Some(next_node) => {
                            let session = self.sessions.get_mut(&player_id).unwrap();
                            session.go_to_node(&next_node);
                            // Continue the loop to process the next node.
                        }
                        None => {
                            // Action with no successor -> end.
                            self.sessions.remove(&player_id);
                            output.packets.push(build_close_dialogue_packet());
                            return Ok(output);
                        }
                    }
                }
                DialogueResult::Continue(next_node) => {
                    // The process_node helper returned a "continue" because the
                    // NpcSay/PlayerSay node *has* a `next`.  We need to send
                    // the current node's text and then move on.
                    let text_packets = self.build_text_packets(dialogue_id, &current_node, &npc_name);
                    output.packets.extend(text_packets);

                    let session = self.sessions.get_mut(&player_id).unwrap();
                    session.go_to_node(&next_node);
                    // Continue the loop.
                }
                DialogueResult::End => {
                    self.sessions.remove(&player_id);
                    output.packets.push(build_close_dialogue_packet());
                    return Ok(output);
                }
                DialogueResult::Error(msg) => {
                    warn!(player_id, error = %msg, "Dialogue error");
                    self.sessions.remove(&player_id);
                    output.packets.push(build_close_dialogue_packet());
                    return Err(msg);
                }
            }
        }

        // Safety net: if we hit the step limit, close the dialogue.
        warn!(player_id, "Dialogue exceeded max steps, force-closing");
        self.sessions.remove(&player_id);
        output.packets.push(build_close_dialogue_packet());
        Ok(output)
    }

    /// Helper: given a node that is NpcSay or PlayerSay, build the
    /// corresponding text packet(s).
    fn build_text_packets(
        &self,
        dialogue_id: u32,
        node_name: &str,
        npc_name: &str,
    ) -> Vec<Packet> {
        let dialogue = match self.manager.get(dialogue_id) {
            Some(d) => d,
            None => return Vec::new(),
        };
        let node = match dialogue.get_node(node_name) {
            Some(n) => n,
            None => return Vec::new(),
        };

        match node {
            DialogueNode::NpcSay { text, .. } => text
                .iter()
                .map(|line| build_npc_message_packet(npc_name, line))
                .collect(),
            DialogueNode::PlayerSay { text, .. } => {
                vec![build_npc_message_packet(npc_name, text)]
            }
            _ => Vec::new(),
        }
    }
}

impl Default for DialogueHandler {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::dialogue::{Dialogue, DialogueAction, DialogueOption};
    use crate::game::entity::EntityId;

    /// Build a small dialogue tree used by multiple tests.
    fn sample_tree() -> Dialogue {
        Dialogue::new(100, 42, "start")
            .npc_say("start", vec!["Hello traveller!"], Some("menu"))
            .choice(
                "menu",
                vec![
                    DialogueOption::new("Tell me more.", "more_info"),
                    DialogueOption::new("Open shop.", "shop_action"),
                    DialogueOption::new("Goodbye.", "bye"),
                ],
            )
            .npc_say(
                "more_info",
                vec!["This is Lumbridge.", "Be careful out there."],
                Some("menu"),
            )
            .action("shop_action", DialogueAction::OpenShop(7), None)
            .npc_say("bye", vec!["Farewell!"], None)
            .end("end")
    }

    // -- packet builder tests -----------------------------------------------

    #[test]
    fn test_build_npc_message_packet() {
        let packet = build_npc_message_packet("Hans", "Hello!");
        assert_eq!(packet.opcode, ServerOpcode::NpcMessage as u8);
        // Payload should contain both null-terminated strings.
        assert!(packet.payload.len() > "Hans".len() + "Hello!".len());
        assert!(packet.payload.contains(&0)); // at least one null terminator
    }

    #[test]
    fn test_build_option_menu_packet() {
        let options = vec!["Option A".to_string(), "Option B".to_string()];
        let packet = build_option_menu_packet(&options);
        assert_eq!(packet.opcode, ServerOpcode::DialogueOptions as u8);
        assert_eq!(packet.payload[0], 2); // two options
    }

    #[test]
    fn test_build_close_dialogue_packet() {
        let packet = build_close_dialogue_packet();
        assert_eq!(packet.opcode, ServerOpcode::DialogueOptions as u8);
        assert_eq!(packet.payload[0], 0); // zero options = close
    }

    // -- session tests ------------------------------------------------------

    #[test]
    fn test_dialogue_session_creation() {
        let tree = sample_tree();
        let session = DialogueSession::new(EntityId(42), "TestNPC", tree);

        assert_eq!(session.npc_id, EntityId(42));
        assert_eq!(session.current_node, "start");
        assert!(!session.awaiting_response);
        assert_eq!(session.npc_name, "TestNPC");
    }

    #[test]
    fn test_dialogue_session_go_to_node() {
        let tree = sample_tree();
        let mut session = DialogueSession::new(EntityId(42), "TestNPC", tree);
        session.awaiting_response = true;

        session.go_to_node("menu");
        assert_eq!(session.current_node, "menu");
        assert!(!session.awaiting_response);
    }

    // -- handler: start dialogue --------------------------------------------

    #[test]
    fn test_start_dialogue_by_npc_id() {
        let mut handler = DialogueHandler::new();
        // NPC 0 ("Hans") has a default dialogue.
        let result = handler.start_dialogue(1, EntityId(0), "Hans");

        assert!(result.is_ok());
        let output = result.unwrap();
        // Should produce at least one NPC message packet.
        assert!(!output.packets.is_empty());
        // Player should now be in a dialogue.
        assert!(handler.is_in_dialogue(1));
    }

    #[test]
    fn test_start_dialogue_with_custom_tree() {
        let mut handler = DialogueHandler::new();
        let tree = sample_tree();
        let result = handler.start_dialogue_with_tree(1, EntityId(42), "Guide", tree);

        assert!(result.is_ok());
        let output = result.unwrap();
        assert!(!output.packets.is_empty());
        assert!(handler.is_in_dialogue(1));
    }

    #[test]
    fn test_start_dialogue_rejects_double_open() {
        let mut handler = DialogueHandler::new();
        let tree = sample_tree();
        handler
            .start_dialogue_with_tree(1, EntityId(42), "Guide", tree.clone())
            .unwrap();

        let result = handler.start_dialogue_with_tree(1, EntityId(42), "Guide", tree);
        assert!(result.is_err());
    }

    #[test]
    fn test_start_dialogue_missing_npc() {
        let mut handler = DialogueHandler::new();
        let result = handler.start_dialogue(1, EntityId(9999), "Ghost");
        assert!(result.is_err());
    }

    // -- handler: menu reply ------------------------------------------------

    #[test]
    fn test_handle_menu_reply_select_goodbye() {
        let mut handler = DialogueHandler::new();
        let tree = sample_tree();
        // Register the tree so the manager knows about it.
        handler.manager_mut().register(tree.clone());

        handler
            .start_dialogue_with_tree(1, EntityId(42), "Guide", tree)
            .unwrap();

        // The start node says "Hello traveller!" then advances to "menu" which
        // shows options.  The handler should be awaiting a response.
        assert!(handler.is_in_dialogue(1));
        let session = handler.get_session(1).unwrap();
        assert!(session.awaiting_response);

        // Select option 2 ("Goodbye.") -> "bye" node.
        let result = handler.handle_menu_reply(1, 2);
        assert!(result.is_ok());
        let output = result.unwrap();
        // "bye" is NpcSay with no next, so dialogue should close.
        assert!(!handler.is_in_dialogue(1));
        // Should have at least the farewell text + close packet.
        assert!(output.packets.len() >= 2);
    }

    #[test]
    fn test_handle_menu_reply_open_shop() {
        let mut handler = DialogueHandler::new();
        let tree = sample_tree();
        handler.manager_mut().register(tree.clone());

        handler
            .start_dialogue_with_tree(1, EntityId(42), "Guide", tree)
            .unwrap();

        // Select option 1 ("Open shop.") -> "shop_action" node.
        let result = handler.handle_menu_reply(1, 1);
        assert!(result.is_ok());
        let output = result.unwrap();
        // Should contain the OpenShop handler action.
        assert!(output
            .actions
            .iter()
            .any(|a| matches!(a, HandlerAction::OpenShop(7))));
        // Dialogue should be closed (action node has no next).
        assert!(!handler.is_in_dialogue(1));
    }

    #[test]
    fn test_handle_menu_reply_loops_back() {
        let mut handler = DialogueHandler::new();
        let tree = sample_tree();
        handler.manager_mut().register(tree.clone());

        handler
            .start_dialogue_with_tree(1, EntityId(42), "Guide", tree)
            .unwrap();

        // Select option 0 ("Tell me more.") -> "more_info", which loops back
        // to "menu".
        let result = handler.handle_menu_reply(1, 0);
        assert!(result.is_ok());
        let output = result.unwrap();
        // Should still be in dialogue and awaiting response (back at menu).
        assert!(handler.is_in_dialogue(1));
        let session = handler.get_session(1).unwrap();
        assert!(session.awaiting_response);
        assert_eq!(session.current_node, "menu");
        // Packets should include the "more_info" text.
        assert!(!output.packets.is_empty());
    }

    #[test]
    fn test_handle_menu_reply_not_in_dialogue() {
        let mut handler = DialogueHandler::new();
        let result = handler.handle_menu_reply(1, 0);
        assert!(result.is_err());
    }

    #[test]
    fn test_handle_menu_reply_invalid_index() {
        let mut handler = DialogueHandler::new();
        let tree = sample_tree();
        handler.manager_mut().register(tree.clone());

        handler
            .start_dialogue_with_tree(1, EntityId(42), "Guide", tree)
            .unwrap();

        // Option index 99 does not exist.
        let result = handler.handle_menu_reply(1, 99);
        assert!(result.is_err());
    }

    // -- handler: close dialogue --------------------------------------------

    #[test]
    fn test_close_dialogue() {
        let mut handler = DialogueHandler::new();
        let tree = sample_tree();
        handler
            .start_dialogue_with_tree(1, EntityId(42), "Guide", tree)
            .unwrap();

        assert!(handler.is_in_dialogue(1));
        let packets = handler.close_dialogue(1);
        assert!(!handler.is_in_dialogue(1));
        // Should return a close packet.
        assert_eq!(packets.len(), 1);
        assert_eq!(packets[0].opcode, ServerOpcode::DialogueOptions as u8);
        assert_eq!(packets[0].payload[0], 0);
    }

    #[test]
    fn test_close_dialogue_when_not_open() {
        let mut handler = DialogueHandler::new();
        let packets = handler.close_dialogue(1);
        assert!(packets.is_empty());
    }

    // -- handler action conversion ------------------------------------------

    #[test]
    fn test_handler_action_from_dialogue_action() {
        assert_eq!(
            HandlerAction::from_dialogue_action(&DialogueAction::OpenShop(5)),
            Some(HandlerAction::OpenShop(5)),
        );
        assert_eq!(
            HandlerAction::from_dialogue_action(&DialogueAction::GiveItem {
                item_id: 10,
                amount: 3,
            }),
            Some(HandlerAction::GiveItem {
                item_id: 10,
                amount: 3,
            }),
        );
        assert_eq!(
            HandlerAction::from_dialogue_action(&DialogueAction::OpenBank),
            Some(HandlerAction::OpenBank),
        );
        assert_eq!(
            HandlerAction::from_dialogue_action(&DialogueAction::Teleport { x: 100, y: 200 }),
            Some(HandlerAction::Teleport(Position::new(100, 200))),
        );
        // Unsupported mapping returns None.
        assert_eq!(
            HandlerAction::from_dialogue_action(&DialogueAction::HealPlayer),
            None,
        );
    }

    // -- is_in_dialogue -----------------------------------------------------

    #[test]
    fn test_is_in_dialogue() {
        let mut handler = DialogueHandler::new();
        assert!(!handler.is_in_dialogue(1));

        let tree = sample_tree();
        handler
            .start_dialogue_with_tree(1, EntityId(42), "Guide", tree)
            .unwrap();
        assert!(handler.is_in_dialogue(1));

        handler.close_dialogue(1);
        assert!(!handler.is_in_dialogue(1));
    }
}
