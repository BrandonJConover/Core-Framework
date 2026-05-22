//! Death & Respawn system for OpenRSC.
//!
//! Handles player death (PvP and PvE), item loss mechanics, skull system,
//! NPC death processing, drop generation, and death screen packets.

use std::collections::HashMap;

use tracing::{debug, info};

use super::entity::{EntityId, Position};
use super::item::ItemId;
use super::player::{Item, Player, SkillId};
use super::prayer::PrayerState;
use super::protocol::{Packet, ServerOpcode};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Default respawn location (Lumbridge).
pub const LUMBRIDGE_RESPAWN: Position = Position {
    x: 122,
    y: 647,
    plane: 0,
};

/// Duration of a player-kill skull in game ticks (~20 minutes at 640ms/tick).
pub const SKULL_DURATION_TICKS: u64 = 1875;

/// Number of items kept on death (unskulled, no Protect Items prayer).
const BASE_ITEMS_KEPT: usize = 3;

/// Extra item kept when Protect Items prayer is active.
const PROTECT_ITEMS_BONUS: usize = 1;

/// Delay in ticks before the death screen is dismissed (~3 seconds).
pub const DEATH_SCREEN_DELAY_TICKS: u32 = 5;

// ---------------------------------------------------------------------------
// DeathType
// ---------------------------------------------------------------------------

/// How the entity died.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeathType {
    /// Killed by another player.
    PvP,
    /// Killed by an NPC.
    PvE,
    /// Killed by poison damage.
    Poison,
    /// Any other cause (e.g. environmental, command).
    Other,
}

// ---------------------------------------------------------------------------
// DeathResult (player)
// ---------------------------------------------------------------------------

/// The outcome of processing a player death.
#[derive(Debug, Clone)]
pub struct DeathResult {
    /// Items the player keeps after death (id, amount).
    pub kept_items: Vec<(ItemId, u32)>,
    /// Items dropped on the ground (id, amount, position).
    pub dropped_items: Vec<(ItemId, u32, Position)>,
    /// Where the player will respawn.
    pub respawn_position: Position,
    /// Classification of the death.
    pub death_type: DeathType,
}

// ---------------------------------------------------------------------------
// NpcDeathResult
// ---------------------------------------------------------------------------

/// The outcome of processing an NPC death.
#[derive(Debug, Clone)]
pub struct NpcDeathResult {
    /// Items dropped by the NPC (id, amount).
    pub drops: Vec<(ItemId, u32)>,
    /// Ticks until the NPC respawns.
    pub respawn_delay_ticks: u32,
    /// XP awarded to the killer, keyed by skill.
    pub xp_reward: HashMap<SkillId, u32>,
}

// ---------------------------------------------------------------------------
// SkullManager
// ---------------------------------------------------------------------------

/// Tracks the player-kill skull and its expiry.
#[derive(Debug, Clone)]
pub struct SkullManager {
    /// Game tick at which the skull expires, or `None` if unskulled.
    pub skull_expires: Option<u64>,
}

impl SkullManager {
    /// Create a new manager with no skull.
    pub fn new() -> Self {
        Self {
            skull_expires: None,
        }
    }

    /// Apply a skull to the player (e.g. after attacking another player).
    /// The skull lasts for [`SKULL_DURATION_TICKS`] from `current_tick`.
    pub fn apply_skull(&mut self, current_tick: u64) {
        let new_expiry = current_tick + SKULL_DURATION_TICKS;
        // Extend the skull if already active; never shorten it.
        match self.skull_expires {
            Some(existing) if existing >= new_expiry => {}
            _ => {
                self.skull_expires = Some(new_expiry);
                debug!("Skull applied, expires at tick {}", new_expiry);
            }
        }
    }

    /// Returns `true` if the player currently has a skull.
    pub fn is_skulled(&self, current_tick: u64) -> bool {
        match self.skull_expires {
            Some(expiry) => current_tick < expiry,
            None => false,
        }
    }

    /// Tick-based update -- clear the skull once it has expired.
    pub fn tick(&mut self, current_tick: u64) {
        if let Some(expiry) = self.skull_expires {
            if current_tick >= expiry {
                self.skull_expires = None;
                debug!("Skull expired at tick {}", current_tick);
            }
        }
    }

    /// Immediately remove the skull (e.g. on death).
    pub fn clear(&mut self) {
        self.skull_expires = None;
    }
}

impl Default for SkullManager {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// DeathProcessor (player deaths)
// ---------------------------------------------------------------------------

/// Processes a player's death: determines kept/dropped items and respawn.
pub struct DeathProcessor;

impl DeathProcessor {
    /// Process a player death.
    ///
    /// * `player`       - mutable reference to the dying player
    /// * `killer`       - optional entity id of whoever killed the player
    /// * `death_type`   - how the player died
    /// * `skull_manager`- the player's skull state
    /// * `prayer_state` - the player's prayer state (checked for Protect Items)
    /// * `item_values`  - lookup closure that returns the value of an item id
    ///
    /// Returns a [`DeathResult`] describing what happens.
    pub fn process_player_death<F>(
        player: &mut Player,
        killer: Option<EntityId>,
        death_type: DeathType,
        skull_manager: &SkullManager,
        prayer_state: &PrayerState,
        item_values: F,
    ) -> DeathResult
    where
        F: Fn(u32) -> u32,
    {
        let death_pos = player.position;
        let current_tick = player.last_tick;
        let is_skulled = skull_manager.is_skulled(current_tick);
        let has_protect = prayer_state.has_protect_items();

        // Determine how many items to keep.
        let items_to_keep = if is_skulled {
            // Skulled: lose everything, unless Protect Items saves 1.
            if has_protect {
                1
            } else {
                0
            }
        } else {
            // Normal: keep 3 (or 4 with Protect Items).
            BASE_ITEMS_KEPT + if has_protect { PROTECT_ITEMS_BONUS } else { 0 }
        };

        // Gather every item the player is carrying (inventory + equipment).
        let all_items = Self::collect_all_items(player);

        // Sort descending by value so the most valuable items are kept first.
        let mut valued: Vec<(u32, u32, u32)> = all_items
            .iter()
            .map(|&(id, amount)| (id, amount, item_values(id)))
            .collect();
        valued.sort_by(|a, b| b.2.cmp(&a.2));

        let mut kept_items: Vec<(ItemId, u32)> = Vec::new();
        let mut dropped_items: Vec<(ItemId, u32, Position)> = Vec::new();
        let mut kept_count: usize = 0;

        for (id, amount, _value) in &valued {
            if kept_count < items_to_keep {
                // For stackable items we keep the entire stack as one "kept slot".
                kept_items.push((ItemId(*id), *amount));
                kept_count += 1;
            } else {
                dropped_items.push((ItemId(*id), *amount, death_pos));
            }
        }

        // Clear the player's inventory and equipment -- the caller is
        // responsible for adding the kept items back and spawning ground items.
        Self::clear_items(player);

        // Reset stats on death: restore hits to base level.
        player.skills.restore_all();
        player.in_combat = false;

        // Teleport to respawn location.
        let respawn_position = LUMBRIDGE_RESPAWN;
        player.position = respawn_position;

        info!(
            "Player {} died ({:?}) at {}, kept {} item(s), dropped {} item(s)",
            player.username,
            death_type,
            death_pos,
            kept_items.len(),
            dropped_items.len(),
        );

        DeathResult {
            kept_items,
            dropped_items,
            respawn_position,
            death_type,
        }
    }

    /// Collect all items from inventory and equipment into a flat vec of (item_id, amount).
    fn collect_all_items(player: &Player) -> Vec<(u32, u32)> {
        let mut items: Vec<(u32, u32)> = Vec::new();

        // Inventory items
        for slot in player.inventory.items() {
            if let Some(item) = slot {
                items.push((item.id, item.amount));
            }
        }

        // Equipped items (iterate over all known equipment slots)
        use super::player::EquipmentSlot;
        let slots = [
            EquipmentSlot::Head,
            EquipmentSlot::Cape,
            EquipmentSlot::Amulet,
            EquipmentSlot::Weapon,
            EquipmentSlot::Body,
            EquipmentSlot::Shield,
            EquipmentSlot::Legs,
            EquipmentSlot::Gloves,
            EquipmentSlot::Boots,
            EquipmentSlot::Ring,
        ];
        for slot in &slots {
            if let Some(item) = player.equipment.get(*slot) {
                items.push((item.id, item.amount));
            }
        }

        items
    }

    /// Remove all inventory and equipment items from the player.
    fn clear_items(player: &mut Player) {
        // Clear inventory by removing every occupied slot.
        // We iterate ids we find, then remove them.
        let inv_ids: Vec<(u32, u32)> = player
            .inventory
            .items()
            .iter()
            .filter_map(|s| s.as_ref().map(|i| (i.id, i.amount)))
            .collect();

        for (id, amount) in inv_ids {
            player.inventory.remove(id, amount);
        }

        // Unequip everything.
        use super::player::EquipmentSlot;
        let slots = [
            EquipmentSlot::Head,
            EquipmentSlot::Cape,
            EquipmentSlot::Amulet,
            EquipmentSlot::Weapon,
            EquipmentSlot::Body,
            EquipmentSlot::Shield,
            EquipmentSlot::Legs,
            EquipmentSlot::Gloves,
            EquipmentSlot::Boots,
            EquipmentSlot::Ring,
        ];
        for slot in &slots {
            player.equipment.unequip(*slot);
        }
    }
}

// ---------------------------------------------------------------------------
// NpcDeathProcessor
// ---------------------------------------------------------------------------

/// Processes NPC deaths: rolls drops, schedules respawn, awards XP.
pub struct NpcDeathProcessor;

impl NpcDeathProcessor {
    /// Process the death of an NPC.
    ///
    /// * `npc_id`       - the entity id of the dead NPC
    /// * `npc_def_id`   - the NPC definition id (for drop-table and respawn lookup)
    /// * `killer_id`    - the entity id of the player who landed the killing blow
    /// * `npc_hitpoints`- the NPC's max hitpoints (used for XP calculation)
    /// * `respawn_time` - respawn delay in ticks (from NpcDef)
    /// * `drop_rolls`   - pre-rolled drops as (item_id, amount) pairs
    ///
    /// Returns an [`NpcDeathResult`].
    pub fn process_npc_death(
        npc_id: EntityId,
        npc_def_id: u32,
        killer_id: EntityId,
        npc_hitpoints: u32,
        respawn_time: u32,
        drop_rolls: Vec<(u32, u32)>,
    ) -> NpcDeathResult {
        // Convert raw drops to ItemId tuples.
        let drops: Vec<(ItemId, u32)> = drop_rolls
            .into_iter()
            .map(|(id, amount)| (ItemId(id), amount))
            .collect();

        // Calculate combat XP reward based on NPC hitpoints.
        // RSC formula: total XP = hp * 4, split across combat skills.
        let total_xp = npc_hitpoints * 4;
        let mut xp_reward = HashMap::new();

        // Hits always gets 1/3 of total XP (the "shared" portion).
        let hits_xp = total_xp / 3;
        xp_reward.insert(SkillId::Hits, hits_xp);

        // Remaining 2/3 goes to the primary style skill.
        // The caller can re-distribute; by default we assign to Attack.
        let style_xp = total_xp - hits_xp;
        xp_reward.insert(SkillId::Attack, style_xp);

        info!(
            "NPC {} (def {}) killed by entity {}, {} drop(s), respawn in {} ticks",
            npc_id,
            npc_def_id,
            killer_id,
            drops.len(),
            respawn_time,
        );

        NpcDeathResult {
            drops,
            respawn_delay_ticks: respawn_time,
            xp_reward,
        }
    }

    /// Distribute the style XP portion according to the player's combat style.
    ///
    /// Call this after `process_npc_death` to split the generic `Attack` XP
    /// into the correct skill(s) for the player's active style.
    pub fn distribute_style_xp(result: &mut NpcDeathResult, style_skill: SkillId) {
        if let Some(attack_xp) = result.xp_reward.remove(&SkillId::Attack) {
            // If the style is "Controlled" the caller should split manually;
            // here we just reassign the full chunk to the requested skill.
            let existing = result.xp_reward.entry(style_skill).or_insert(0);
            *existing += attack_xp;
        }
    }
}

// ---------------------------------------------------------------------------
// Death screen packet
// ---------------------------------------------------------------------------

/// Build the server packet that tells the client to show the death screen.
pub fn build_death_screen_packet() -> Packet {
    Packet::new(ServerOpcode::DeathScreen as u8)
}

/// Build a server message packet for death-related text.
pub fn build_death_message_packet(message: &str) -> Packet {
    let mut packet = Packet::new(ServerOpcode::Message as u8);
    packet.add_string(message);
    packet
}

/// Build the teleport/position packet to move the player to the respawn point.
pub fn build_respawn_teleport_packet(position: &Position) -> Packet {
    let mut packet = Packet::new(ServerOpcode::PlayerPosition as u8);
    packet.add_short(position.x as u16);
    packet.add_short(position.y as u16);
    packet
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::super::player::Player;
    use super::super::prayer::PrayerState;
    use super::*;

    /// Helper: create a test player with some inventory items.
    fn make_test_player() -> Player {
        let mut p = Player::new(1, "testplayer".into());
        // Add items with varying "value" (we'll use item id as a proxy).
        p.inventory.add(Item::new(71, 1)); // Rune sword  (high value)
        p.inventory.add(Item::new(70, 1)); // Adamant sword
        p.inventory.add(Item::new(69, 1)); // Mithril sword
        p.inventory.add(Item::new(68, 1)); // Steel sword
        p.inventory.add(Item::new(67, 1)); // Iron sword
        p.inventory.add(Item::stackable(10, 500)); // 500 coins
        p
    }

    /// Trivial value function: use the item id as its value.
    fn value_fn(id: u32) -> u32 {
        id
    }

    // -- SkullManager tests -------------------------------------------------

    #[test]
    fn test_skull_apply_and_check() {
        let mut sm = SkullManager::new();
        assert!(!sm.is_skulled(0));

        sm.apply_skull(100);
        assert!(sm.is_skulled(100));
        assert!(sm.is_skulled(100 + SKULL_DURATION_TICKS - 1));
        assert!(!sm.is_skulled(100 + SKULL_DURATION_TICKS));
    }

    #[test]
    fn test_skull_tick_expiry() {
        let mut sm = SkullManager::new();
        sm.apply_skull(0);
        assert!(sm.is_skulled(0));

        sm.tick(SKULL_DURATION_TICKS);
        assert!(!sm.is_skulled(SKULL_DURATION_TICKS));
        assert!(sm.skull_expires.is_none());
    }

    #[test]
    fn test_skull_extend_not_shorten() {
        let mut sm = SkullManager::new();
        sm.apply_skull(100); // expires at 1975
        sm.apply_skull(50); // would expire at 1925 -- should NOT shorten
        assert_eq!(sm.skull_expires, Some(100 + SKULL_DURATION_TICKS));
    }

    #[test]
    fn test_skull_clear() {
        let mut sm = SkullManager::new();
        sm.apply_skull(0);
        sm.clear();
        assert!(!sm.is_skulled(0));
    }

    // -- DeathProcessor tests -----------------------------------------------

    #[test]
    fn test_unskulled_death_keeps_3() {
        let mut player = make_test_player();
        let skull = SkullManager::new(); // no skull
        let prayer = PrayerState::new(1); // no Protect Items

        let result = DeathProcessor::process_player_death(
            &mut player,
            None,
            DeathType::PvE,
            &skull,
            &prayer,
            value_fn,
        );

        assert_eq!(result.kept_items.len(), 3);
        assert_eq!(result.death_type, DeathType::PvE);
        assert_eq!(result.respawn_position, LUMBRIDGE_RESPAWN);

        // The three most valuable items (by id): 71, 70, 69
        let kept_ids: Vec<u32> = result.kept_items.iter().map(|(id, _)| id.0).collect();
        assert_eq!(kept_ids, vec![71, 70, 69]);

        // Everything else is dropped.
        assert_eq!(result.dropped_items.len(), 3);
    }

    #[test]
    fn test_unskulled_with_protect_items_keeps_4() {
        let mut player = make_test_player();
        let skull = SkullManager::new();
        let mut prayer = PrayerState::new(30);
        prayer
            .activate(super::super::prayer::PrayerId::ProtectItems, 30)
            .unwrap();

        let result = DeathProcessor::process_player_death(
            &mut player,
            None,
            DeathType::PvP,
            &skull,
            &prayer,
            value_fn,
        );

        assert_eq!(result.kept_items.len(), 4);
    }

    #[test]
    fn test_skulled_death_loses_all() {
        let mut player = make_test_player();
        let mut skull = SkullManager::new();
        skull.apply_skull(0);
        let prayer = PrayerState::new(1);

        // Ensure skull is active at tick 0 (player.last_tick).
        player.last_tick = 0;

        let result = DeathProcessor::process_player_death(
            &mut player,
            Some(EntityId(99)),
            DeathType::PvP,
            &skull,
            &prayer,
            value_fn,
        );

        assert!(result.kept_items.is_empty());
        assert_eq!(result.dropped_items.len(), 6);
    }

    #[test]
    fn test_skulled_with_protect_items_keeps_1() {
        let mut player = make_test_player();
        let mut skull = SkullManager::new();
        skull.apply_skull(0);
        let mut prayer = PrayerState::new(30);
        prayer
            .activate(super::super::prayer::PrayerId::ProtectItems, 30)
            .unwrap();
        player.last_tick = 0;

        let result = DeathProcessor::process_player_death(
            &mut player,
            Some(EntityId(99)),
            DeathType::PvP,
            &skull,
            &prayer,
            value_fn,
        );

        assert_eq!(result.kept_items.len(), 1);
        // Most valuable item kept
        assert_eq!(result.kept_items[0].0, ItemId(71));
    }

    #[test]
    fn test_death_resets_player_position() {
        let mut player = make_test_player();
        player.position = Position::new(300, 300);
        let skull = SkullManager::new();
        let prayer = PrayerState::new(1);

        let result = DeathProcessor::process_player_death(
            &mut player,
            None,
            DeathType::PvE,
            &skull,
            &prayer,
            value_fn,
        );

        assert_eq!(player.position, LUMBRIDGE_RESPAWN);
        assert_eq!(result.respawn_position, LUMBRIDGE_RESPAWN);
    }

    #[test]
    fn test_death_clears_combat_flag() {
        let mut player = make_test_player();
        player.in_combat = true;
        let skull = SkullManager::new();
        let prayer = PrayerState::new(1);

        let _result = DeathProcessor::process_player_death(
            &mut player,
            None,
            DeathType::Poison,
            &skull,
            &prayer,
            value_fn,
        );

        assert!(!player.in_combat);
    }

    #[test]
    fn test_empty_inventory_death() {
        let mut player = Player::new(2, "empty".into());
        let skull = SkullManager::new();
        let prayer = PrayerState::new(1);

        let result = DeathProcessor::process_player_death(
            &mut player,
            None,
            DeathType::Other,
            &skull,
            &prayer,
            value_fn,
        );

        assert!(result.kept_items.is_empty());
        assert!(result.dropped_items.is_empty());
    }

    // -- NpcDeathProcessor tests --------------------------------------------

    #[test]
    fn test_npc_death_basic() {
        let result = NpcDeathProcessor::process_npc_death(
            EntityId(100),
            62, // goblin def id
            EntityId(1),
            15,                     // hp
            100,                    // respawn time
            vec![(20, 1), (10, 5)], // bones + 5 coins
        );

        assert_eq!(result.drops.len(), 2);
        assert_eq!(result.drops[0], (ItemId(20), 1));
        assert_eq!(result.drops[1], (ItemId(10), 5));
        assert_eq!(result.respawn_delay_ticks, 100);

        // XP: total = 15 * 4 = 60.  Hits gets 20, Attack gets 40.
        assert_eq!(*result.xp_reward.get(&SkillId::Hits).unwrap(), 20);
        assert_eq!(*result.xp_reward.get(&SkillId::Attack).unwrap(), 40);
    }

    #[test]
    fn test_npc_death_style_xp_redistribution() {
        let mut result =
            NpcDeathProcessor::process_npc_death(EntityId(200), 184, EntityId(1), 90, 150, vec![]);

        // Redistribute to Strength.
        NpcDeathProcessor::distribute_style_xp(&mut result, SkillId::Strength);

        assert!(!result.xp_reward.contains_key(&SkillId::Attack));
        assert!(result.xp_reward.contains_key(&SkillId::Strength));
    }

    // -- Packet tests -------------------------------------------------------

    #[test]
    fn test_death_screen_packet() {
        let packet = build_death_screen_packet();
        assert_eq!(packet.opcode, ServerOpcode::DeathScreen as u8);
        assert!(packet.is_empty());
    }

    #[test]
    fn test_death_message_packet() {
        let packet = build_death_message_packet("Oh dear, you are dead!");
        assert_eq!(packet.opcode, ServerOpcode::Message as u8);
        assert!(!packet.is_empty());
    }

    #[test]
    fn test_respawn_teleport_packet() {
        let packet = build_respawn_teleport_packet(&LUMBRIDGE_RESPAWN);
        assert_eq!(packet.opcode, ServerOpcode::PlayerPosition as u8);
        // 2 shorts = 4 bytes
        assert_eq!(packet.len(), 4);
    }
}
