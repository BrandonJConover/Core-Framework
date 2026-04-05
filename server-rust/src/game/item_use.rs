//! Item Use Handler framework for "use item on X" interactions.
//!
//! Provides a dispatch system that routes item-use actions to registered
//! handlers based on (item, target) combinations.  Built-in handlers cover
//! eating food, drinking potions, burying bones, and reading scrolls.

use std::collections::HashMap;

use tracing::debug;

use super::consumables::{get_food_def, get_potion_def};
use super::entity::{EntityId, Position};
use super::player::SkillId;
use crate::protocol::{Packet, PacketBuilder};
use crate::protocol::opcodes::OpcodeOut;

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/// Outcome of an item-use action.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ItemUseResult {
    /// Action completed successfully.
    Success,
    /// No handler registered for this combination.
    NotHandled,
    /// Action failed with a human-readable reason.
    Failed(String),
    /// Player lacks the required skill level.
    RequiresLevel(SkillId, u8),
    /// Player is missing a required item.
    RequiresItem(u32),
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

/// Mutable context passed to every item-use handler so it can inspect the
/// player state and enqueue response packets / messages.
#[derive(Debug)]
pub struct ItemUseContext {
    /// ID of the player performing the action.
    pub player_id: u64,
    /// Player position at the time of the action.
    pub position: Position,
    /// Outgoing packets the handler wants sent to the client.
    pub packets_out: Vec<Packet>,
    /// Game messages to display to the player.
    pub messages: Vec<String>,
}

impl ItemUseContext {
    /// Create a new context for the given player.
    pub fn new(player_id: u64, position: Position) -> Self {
        Self {
            player_id,
            position,
            packets_out: Vec::new(),
            messages: Vec::new(),
        }
    }

    /// Convenience: push a server message packet and record the text.
    pub fn send_message(&mut self, text: &str) {
        self.messages.push(text.to_string());
        let packet = PacketBuilder::new(OpcodeOut::ServerMessage as u8)
            .write_string(text)
            .build();
        self.packets_out.push(packet);
    }
}

// ---------------------------------------------------------------------------
// Handler traits
// ---------------------------------------------------------------------------

/// Handler for using one inventory item on another.
pub trait ItemOnItemHandler: Send + Sync {
    fn handle(
        &self,
        item1_id: u32,
        item2_id: u32,
        context: &mut ItemUseContext,
    ) -> ItemUseResult;
}

/// Handler for using an inventory item on a game object.
pub trait ItemOnObjectHandler: Send + Sync {
    fn handle(
        &self,
        item_id: u32,
        object_id: u32,
        context: &mut ItemUseContext,
    ) -> ItemUseResult;
}

/// Handler for using an inventory item on an NPC.
pub trait ItemOnNpcHandler: Send + Sync {
    fn handle(
        &self,
        item_id: u32,
        npc_id: EntityId,
        context: &mut ItemUseContext,
    ) -> ItemUseResult;
}

/// Handler for using an inventory item on another player.
pub trait ItemOnPlayerHandler: Send + Sync {
    fn handle(
        &self,
        item_id: u32,
        target_id: u64,
        context: &mut ItemUseContext,
    ) -> ItemUseResult;
}

/// Handler for an "item command" (right-click action on an inventory item).
pub trait ItemCommandHandler: Send + Sync {
    fn handle(&self, item_id: u32, context: &mut ItemUseContext) -> ItemUseResult;
}

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

/// Central dispatcher that routes item-use actions to the appropriate handler.
pub struct ItemUseDispatcher {
    item_on_item: HashMap<(u32, u32), Box<dyn ItemOnItemHandler>>,
    item_on_object: HashMap<(u32, u32), Box<dyn ItemOnObjectHandler>>,
    item_on_npc: HashMap<(u32, u32), Box<dyn ItemOnNpcHandler>>,
    item_on_player: HashMap<u32, Box<dyn ItemOnPlayerHandler>>,
    item_command: HashMap<u32, Box<dyn ItemCommandHandler>>,
}

impl ItemUseDispatcher {
    /// Create an empty dispatcher with no handlers registered.
    pub fn new() -> Self {
        Self {
            item_on_item: HashMap::new(),
            item_on_object: HashMap::new(),
            item_on_npc: HashMap::new(),
            item_on_player: HashMap::new(),
            item_command: HashMap::new(),
        }
    }

    // -- registration -------------------------------------------------------

    /// Register a handler for using `item1` on `item2`.
    ///
    /// The key is stored with the smaller ID first so that (a, b) and (b, a)
    /// resolve to the same handler.
    pub fn register_item_on_item(
        &mut self,
        item1: u32,
        item2: u32,
        handler: impl ItemOnItemHandler + 'static,
    ) {
        let key = normalize_item_pair(item1, item2);
        debug!("Registered item-on-item handler: ({}, {})", key.0, key.1);
        self.item_on_item.insert(key, Box::new(handler));
    }

    /// Register a handler for using `item_id` on `object_id`.
    pub fn register_item_on_object(
        &mut self,
        item_id: u32,
        object_id: u32,
        handler: impl ItemOnObjectHandler + 'static,
    ) {
        debug!("Registered item-on-object handler: ({}, {})", item_id, object_id);
        self.item_on_object.insert((item_id, object_id), Box::new(handler));
    }

    /// Register a handler for using `item_id` on NPC with definition ID `npc_def_id`.
    pub fn register_item_on_npc(
        &mut self,
        item_id: u32,
        npc_def_id: u32,
        handler: impl ItemOnNpcHandler + 'static,
    ) {
        debug!("Registered item-on-npc handler: ({}, {})", item_id, npc_def_id);
        self.item_on_npc.insert((item_id, npc_def_id), Box::new(handler));
    }

    /// Register a handler for using `item_id` on another player.
    pub fn register_item_on_player(
        &mut self,
        item_id: u32,
        handler: impl ItemOnPlayerHandler + 'static,
    ) {
        debug!("Registered item-on-player handler: item {}", item_id);
        self.item_on_player.insert(item_id, Box::new(handler));
    }

    /// Register an item command handler (right-click action) for `item_id`.
    pub fn register_item_command(
        &mut self,
        item_id: u32,
        handler: impl ItemCommandHandler + 'static,
    ) {
        debug!("Registered item-command handler: item {}", item_id);
        self.item_command.insert(item_id, Box::new(handler));
    }

    // -- dispatch -----------------------------------------------------------

    /// Dispatch an "item on item" action.
    pub fn dispatch_item_on_item(
        &self,
        item1: u32,
        item2: u32,
        context: &mut ItemUseContext,
    ) -> ItemUseResult {
        let key = normalize_item_pair(item1, item2);
        match self.item_on_item.get(&key) {
            Some(handler) => handler.handle(item1, item2, context),
            None => ItemUseResult::NotHandled,
        }
    }

    /// Dispatch an "item on object" action.
    pub fn dispatch_item_on_object(
        &self,
        item_id: u32,
        object_id: u32,
        context: &mut ItemUseContext,
    ) -> ItemUseResult {
        match self.item_on_object.get(&(item_id, object_id)) {
            Some(handler) => handler.handle(item_id, object_id, context),
            None => ItemUseResult::NotHandled,
        }
    }

    /// Dispatch an "item on NPC" action.
    pub fn dispatch_item_on_npc(
        &self,
        item_id: u32,
        npc_def_id: u32,
        npc_id: EntityId,
        context: &mut ItemUseContext,
    ) -> ItemUseResult {
        match self.item_on_npc.get(&(item_id, npc_def_id)) {
            Some(handler) => handler.handle(item_id, npc_id, context),
            None => ItemUseResult::NotHandled,
        }
    }

    /// Dispatch an "item on player" action.
    pub fn dispatch_item_on_player(
        &self,
        item_id: u32,
        target_id: u64,
        context: &mut ItemUseContext,
    ) -> ItemUseResult {
        match self.item_on_player.get(&item_id) {
            Some(handler) => handler.handle(item_id, target_id, context),
            None => ItemUseResult::NotHandled,
        }
    }

    /// Dispatch an item command (right-click action).
    pub fn dispatch_item_command(
        &self,
        item_id: u32,
        context: &mut ItemUseContext,
    ) -> ItemUseResult {
        match self.item_command.get(&item_id) {
            Some(handler) => handler.handle(item_id, context),
            None => ItemUseResult::NotHandled,
        }
    }
}

impl Default for ItemUseDispatcher {
    fn default() -> Self {
        Self::new()
    }
}

/// Normalise an item pair so that (a, b) and (b, a) map to the same key.
fn normalize_item_pair(a: u32, b: u32) -> (u32, u32) {
    if a <= b { (a, b) } else { (b, a) }
}

// ---------------------------------------------------------------------------
// Built-in handlers
// ---------------------------------------------------------------------------

// -- Eat food ---------------------------------------------------------------

/// Item command handler for eating food items.
///
/// Delegates to `consumables::get_food_def` to determine whether the item is
/// edible and how much it heals.
pub struct EatFoodHandler;

impl ItemCommandHandler for EatFoodHandler {
    fn handle(&self, item_id: u32, context: &mut ItemUseContext) -> ItemUseResult {
        let food = match get_food_def(item_id) {
            Some(f) => f,
            None => return ItemUseResult::NotHandled,
        };

        context.send_message(&format!(
            "You eat the {}. It heals {} hitpoints.",
            food.name, food.heal_amount,
        ));

        ItemUseResult::Success
    }
}

// -- Drink potion -----------------------------------------------------------

/// Item command handler for drinking potions.
///
/// Resolves the potion definition via `consumables::get_potion_def` and
/// reports the dose consumed.
pub struct DrinkPotionHandler;

impl ItemCommandHandler for DrinkPotionHandler {
    fn handle(&self, item_id: u32, context: &mut ItemUseContext) -> ItemUseResult {
        let potion = match get_potion_def(item_id) {
            Some(p) => p,
            None => return ItemUseResult::NotHandled,
        };

        let dose = potion.dose_for_item(item_id).unwrap_or(0);
        let remaining = dose.saturating_sub(1);

        context.send_message(&format!(
            "You drink a dose of {}. {} dose{} remaining.",
            potion.name,
            remaining,
            if remaining == 1 { "" } else { "s" },
        ));

        ItemUseResult::Success
    }
}

// -- Bury bones -------------------------------------------------------------

/// Known bone item IDs and their prayer XP rewards.
const BONE_XP: &[(u32, u32)] = &[
    (20, 15),   // Normal bones
    (604, 30),  // Big bones
    (614, 72),  // Dragon bones
];

/// Item command handler for burying bones.
pub struct BuryBonesHandler;

impl BuryBonesHandler {
    /// Look up prayer XP for a bone item.
    fn bone_xp(item_id: u32) -> Option<u32> {
        BONE_XP.iter().find(|(id, _)| *id == item_id).map(|(_, xp)| *xp)
    }
}

impl ItemCommandHandler for BuryBonesHandler {
    fn handle(&self, item_id: u32, context: &mut ItemUseContext) -> ItemUseResult {
        let xp = match Self::bone_xp(item_id) {
            Some(xp) => xp,
            None => return ItemUseResult::NotHandled,
        };

        let bone_name = match item_id {
            20 => "Bones",
            604 => "Big Bones",
            614 => "Dragon Bones",
            _ => "Bones",
        };

        context.send_message(&format!(
            "You bury the {}. You receive {} prayer experience.",
            bone_name, xp,
        ));

        ItemUseResult::Success
    }
}

// -- Read scroll ------------------------------------------------------------

/// Mapping of scroll item IDs to their readable text.
const SCROLL_TEXTS: &[(u32, &str)] = &[
    (29, "You read the scroll. It crumbles to dust."),
    (30, "The scroll contains ancient wisdom about the land."),
];

/// Item command handler for reading scroll items.
pub struct ReadScrollHandler {
    texts: HashMap<u32, String>,
}

impl ReadScrollHandler {
    /// Create a handler pre-loaded with the default scroll texts.
    pub fn new() -> Self {
        let mut texts = HashMap::new();
        for &(id, text) in SCROLL_TEXTS {
            texts.insert(id, text.to_string());
        }
        Self { texts }
    }

    /// Register a custom scroll text for an item ID.
    pub fn add_scroll(&mut self, item_id: u32, text: impl Into<String>) {
        self.texts.insert(item_id, text.into());
    }
}

impl Default for ReadScrollHandler {
    fn default() -> Self {
        Self::new()
    }
}

impl ItemCommandHandler for ReadScrollHandler {
    fn handle(&self, item_id: u32, context: &mut ItemUseContext) -> ItemUseResult {
        match self.texts.get(&item_id) {
            Some(text) => {
                context.send_message(text);
                ItemUseResult::Success
            }
            None => ItemUseResult::NotHandled,
        }
    }
}

// ---------------------------------------------------------------------------
// Convenience: create a dispatcher pre-loaded with built-in handlers
// ---------------------------------------------------------------------------

/// Well-known food item IDs that the default dispatcher should register.
///
/// These are the same IDs listed in `consumables::FOOD_DEFS`.
const DEFAULT_FOOD_IDS: &[u32] = &[
    319, 320, 132, 140, 141, 346, 350, 355, 351, 362,
    364, 352, 354, 316, 367, 373, 546, 370, 369, 325,
    326, 327, 330, 333, 750, 257, 335, 336, 337, 228, 18,
];

/// Well-known potion dose item IDs that the default dispatcher should register.
///
/// These cover every dose variant listed in `consumables::POTION_DEFS`.
const DEFAULT_POTION_IDS: &[u32] = &[
    474, 475, 476, 477,   // Attack potion
    478, 479, 480, 481,   // Strength potion
    482, 483, 484, 485,   // Defense potion
    483, 484, 485, 486,   // Prayer potion
    487, 488, 489, 490,   // Antipoison
    491, 492, 493, 494,   // Super attack
    495, 496, 497, 498,   // Super strength
    499, 500, 501, 502,   // Super defense
    503, 504, 505, 506,   // Ranging potion
    507, 508, 509, 510,   // Magic potion
    511, 512, 513, 514,   // Antifire
];

/// Build a dispatcher with the built-in handlers already registered.
///
/// Registers `EatFoodHandler` and `DrinkPotionHandler` for every known food /
/// potion item ID, `BuryBonesHandler` for every known bone, and
/// `ReadScrollHandler` for the default scroll texts.
pub fn create_default_dispatcher() -> ItemUseDispatcher {
    let mut dispatcher = ItemUseDispatcher::new();

    // Register eat-food for all known food item IDs.
    for &id in DEFAULT_FOOD_IDS {
        dispatcher.register_item_command(id, EatFoodHandler);
    }

    // Register drink-potion for all known potion dose item IDs.
    for &id in DEFAULT_POTION_IDS {
        dispatcher.register_item_command(id, DrinkPotionHandler);
    }

    // Register bury-bones for all known bone IDs.
    for &(bone_id, _) in BONE_XP {
        dispatcher.register_item_command(bone_id, BuryBonesHandler);
    }

    // Register scroll-reading for all known scrolls.
    for &(scroll_id, _) in SCROLL_TEXTS {
        dispatcher.register_item_command(scroll_id, ReadScrollHandler::new());
    }

    dispatcher
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn test_context() -> ItemUseContext {
        ItemUseContext::new(1, Position::new(100, 200))
    }

    struct TestCombineHandler;
    impl ItemOnItemHandler for TestCombineHandler {
        fn handle(&self, item1_id: u32, item2_id: u32, context: &mut ItemUseContext) -> ItemUseResult {
            context.send_message(&format!("Combined {} with {}", item1_id, item2_id));
            ItemUseResult::Success
        }
    }

    struct TestObjectHandler;
    impl ItemOnObjectHandler for TestObjectHandler {
        fn handle(&self, item_id: u32, object_id: u32, context: &mut ItemUseContext) -> ItemUseResult {
            context.send_message(&format!("Used {} on object {}", item_id, object_id));
            ItemUseResult::Success
        }
    }

    struct TestNpcHandler;
    impl ItemOnNpcHandler for TestNpcHandler {
        fn handle(&self, item_id: u32, npc_id: EntityId, context: &mut ItemUseContext) -> ItemUseResult {
            context.send_message(&format!("Used {} on NPC {}", item_id, npc_id));
            ItemUseResult::Success
        }
    }

    struct TestPlayerHandler;
    impl ItemOnPlayerHandler for TestPlayerHandler {
        fn handle(&self, item_id: u32, target_id: u64, context: &mut ItemUseContext) -> ItemUseResult {
            context.send_message(&format!("Used {} on player {}", item_id, target_id));
            ItemUseResult::Success
        }
    }

    struct NeedLevelHandler;
    impl ItemCommandHandler for NeedLevelHandler {
        fn handle(&self, _item_id: u32, _context: &mut ItemUseContext) -> ItemUseResult {
            ItemUseResult::RequiresLevel(SkillId::Magic, 33)
        }
    }

    #[test]
    fn test_dispatch_item_on_item() {
        let mut d = ItemUseDispatcher::new();
        d.register_item_on_item(10, 20, TestCombineHandler);
        let mut ctx = test_context();
        let result = d.dispatch_item_on_item(10, 20, &mut ctx);
        assert_eq!(result, ItemUseResult::Success);
        assert_eq!(ctx.messages.len(), 1);
        assert!(ctx.messages[0].contains("Combined"));
    }

    #[test]
    fn test_dispatch_item_on_item_reversed() {
        let mut d = ItemUseDispatcher::new();
        d.register_item_on_item(10, 20, TestCombineHandler);
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_on_item(20, 10, &mut ctx), ItemUseResult::Success);
    }

    #[test]
    fn test_dispatch_item_on_item_miss() {
        let d = ItemUseDispatcher::new();
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_on_item(99, 100, &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_dispatch_item_on_object_hit() {
        let mut d = ItemUseDispatcher::new();
        d.register_item_on_object(50, 100, TestObjectHandler);
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_on_object(50, 100, &mut ctx), ItemUseResult::Success);
        assert!(ctx.messages[0].contains("object 100"));
    }

    #[test]
    fn test_dispatch_item_on_object_miss() {
        let d = ItemUseDispatcher::new();
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_on_object(50, 999, &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_dispatch_item_on_npc_hit() {
        let mut d = ItemUseDispatcher::new();
        d.register_item_on_npc(50, 10, TestNpcHandler);
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_on_npc(50, 10, EntityId(42), &mut ctx), ItemUseResult::Success);
        assert!(ctx.messages[0].contains("NPC 42"));
    }

    #[test]
    fn test_dispatch_item_on_npc_miss() {
        let d = ItemUseDispatcher::new();
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_on_npc(50, 10, EntityId(42), &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_dispatch_item_on_player_hit() {
        let mut d = ItemUseDispatcher::new();
        d.register_item_on_player(50, TestPlayerHandler);
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_on_player(50, 7, &mut ctx), ItemUseResult::Success);
        assert!(ctx.messages[0].contains("player 7"));
    }

    #[test]
    fn test_dispatch_item_on_player_miss() {
        let d = ItemUseDispatcher::new();
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_on_player(50, 7, &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_dispatch_item_command_hit() {
        let mut d = ItemUseDispatcher::new();
        d.register_item_command(50, NeedLevelHandler);
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_command(50, &mut ctx), ItemUseResult::RequiresLevel(SkillId::Magic, 33));
    }

    #[test]
    fn test_dispatch_item_command_miss() {
        let d = ItemUseDispatcher::new();
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_command(50, &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_eat_food_handler() {
        let handler = EatFoodHandler;
        let mut ctx = test_context();
        let result = handler.handle(316, &mut ctx);
        assert_eq!(result, ItemUseResult::Success);
        assert!(ctx.messages[0].contains("Lobster"));
        assert!(ctx.messages[0].contains("12"));
    }

    #[test]
    fn test_eat_food_not_food() {
        let handler = EatFoodHandler;
        let mut ctx = test_context();
        assert_eq!(handler.handle(99999, &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_drink_potion_handler() {
        let handler = DrinkPotionHandler;
        let mut ctx = test_context();
        let result = handler.handle(495, &mut ctx);
        assert_eq!(result, ItemUseResult::Success);
        assert!(ctx.messages[0].contains("Super Strength"));
        assert!(ctx.messages[0].contains("3 doses"));
    }

    #[test]
    fn test_drink_potion_not_potion() {
        let handler = DrinkPotionHandler;
        let mut ctx = test_context();
        assert_eq!(handler.handle(99999, &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_bury_bones_normal() {
        let handler = BuryBonesHandler;
        let mut ctx = test_context();
        assert_eq!(handler.handle(20, &mut ctx), ItemUseResult::Success);
        assert!(ctx.messages[0].contains("Bones"));
        assert!(ctx.messages[0].contains("15"));
    }

    #[test]
    fn test_bury_bones_big() {
        let handler = BuryBonesHandler;
        let mut ctx = test_context();
        assert_eq!(handler.handle(604, &mut ctx), ItemUseResult::Success);
        assert!(ctx.messages[0].contains("Big Bones"));
        assert!(ctx.messages[0].contains("30"));
    }

    #[test]
    fn test_bury_bones_dragon() {
        let handler = BuryBonesHandler;
        let mut ctx = test_context();
        assert_eq!(handler.handle(614, &mut ctx), ItemUseResult::Success);
        assert!(ctx.messages[0].contains("Dragon Bones"));
        assert!(ctx.messages[0].contains("72"));
    }

    #[test]
    fn test_bury_bones_not_bones() {
        let handler = BuryBonesHandler;
        let mut ctx = test_context();
        assert_eq!(handler.handle(99999, &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_read_scroll() {
        let handler = ReadScrollHandler::new();
        let mut ctx = test_context();
        assert_eq!(handler.handle(29, &mut ctx), ItemUseResult::Success);
        assert!(ctx.messages[0].contains("crumbles to dust"));
    }

    #[test]
    fn test_read_scroll_custom() {
        let mut handler = ReadScrollHandler::new();
        handler.add_scroll(999, "A mysterious prophecy reveals itself.");
        let mut ctx = test_context();
        assert_eq!(handler.handle(999, &mut ctx), ItemUseResult::Success);
        assert!(ctx.messages[0].contains("prophecy"));
    }

    #[test]
    fn test_read_scroll_not_scroll() {
        let handler = ReadScrollHandler::new();
        let mut ctx = test_context();
        assert_eq!(handler.handle(99999, &mut ctx), ItemUseResult::NotHandled);
    }

    #[test]
    fn test_context_send_message() {
        let mut ctx = test_context();
        ctx.send_message("Hello world");
        assert_eq!(ctx.messages.len(), 1);
        assert_eq!(ctx.messages[0], "Hello world");
        assert_eq!(ctx.packets_out.len(), 1);
        assert_eq!(ctx.packets_out[0].opcode, OpcodeOut::ServerMessage as u8);
    }

    #[test]
    fn test_normalize_pair() {
        assert_eq!(normalize_item_pair(10, 20), (10, 20));
        assert_eq!(normalize_item_pair(20, 10), (10, 20));
        assert_eq!(normalize_item_pair(5, 5), (5, 5));
    }

    #[test]
    fn test_default_dispatcher() {
        let d = ItemUseDispatcher::default();
        let mut ctx = test_context();
        assert_eq!(d.dispatch_item_command(1, &mut ctx), ItemUseResult::NotHandled);
    }
}
