//! Wilderness mechanics for RuneScape Classic.
//!
//! The Wilderness is the PvP zone in the northern part of the game world.
//! Players who venture in can attack (and be attacked by) other players
//! within a combat level range determined by the wilderness level at their
//! current position.

use super::entity::Position;
use super::protocol::{Packet, ServerOpcode};

// ---------------------------------------------------------------------------
// Boundary constants
// ---------------------------------------------------------------------------

/// Y coordinate where the Wilderness begins.
pub const WILDERNESS_START_Y: i32 = 2304;

/// Y coordinate where the Wilderness ends.
pub const WILDERNESS_END_Y: i32 = 3000;

/// Multi-combat zone rectangles `(min_x, min_y, max_x, max_y)`.
///
/// Inside these areas multiple players may attack a single target at the same
/// time.  Coordinates are inclusive.
pub const MULTI_COMBAT_ZONES: &[(i32, i32, i32, i32)] = &[
    // Greater Demons area (deep wilderness)
    (208, 2688, 240, 2736),
    // Mage Arena bank surroundings
    (216, 2880, 248, 2928),
    // Chaos Temple area
    (264, 2568, 296, 2616),
    // Lava Maze vicinity
    (224, 2760, 272, 2808),
    // Dark Warriors' Fortress
    (264, 2400, 312, 2448),
];

// ---------------------------------------------------------------------------
// WildernessBoundary
// ---------------------------------------------------------------------------

/// Utility namespace for wilderness boundary queries.
pub struct WildernessBoundary;

impl WildernessBoundary {
    /// The Y coordinate at which the wilderness begins.
    pub const START_Y: i32 = WILDERNESS_START_Y;

    /// The Y coordinate at which the wilderness ends.
    pub const END_Y: i32 = WILDERNESS_END_Y;

    /// Check whether a position falls inside a multi-combat zone.
    pub fn is_multi_combat(pos: &Position) -> bool {
        for &(min_x, min_y, max_x, max_y) in MULTI_COMBAT_ZONES {
            if pos.x >= min_x && pos.x <= max_x && pos.y >= min_y && pos.y <= max_y {
                return true;
            }
        }
        false
    }
}

// ---------------------------------------------------------------------------
// WildernessManager
// ---------------------------------------------------------------------------

/// Core wilderness logic — boundary detection, level calculation, and PvP
/// eligibility checks.
pub struct WildernessManager;

impl WildernessManager {
    /// Returns `true` if the given position is inside the Wilderness.
    pub fn is_in_wilderness(pos: &Position) -> bool {
        pos.y >= WILDERNESS_START_Y && pos.y <= WILDERNESS_END_Y
    }

    /// Wilderness level at a position.
    ///
    /// Returns `0` when the position is outside the Wilderness.
    /// Inside, the level increases by 1 for every 6 tiles north of the
    /// boundary (starting at level 1).
    pub fn wilderness_level(pos: &Position) -> u32 {
        if !Self::is_in_wilderness(pos) {
            return 0;
        }
        ((pos.y - WILDERNESS_START_Y) / 6 + 1) as u32
    }

    /// Check whether an attacker may attack a target given both combat levels
    /// and the current wilderness level.
    ///
    /// The rule: the absolute combat level difference must be **at most** the
    /// wilderness level.
    pub fn can_attack(attacker_combat: u32, target_combat: u32, wilderness_level: u32) -> bool {
        let diff = (attacker_combat as i64 - target_combat as i64).unsigned_abs() as u32;
        diff <= wilderness_level
    }

    /// Build a human-readable warning message for the given wilderness level.
    pub fn get_warning_message(level: u32) -> String {
        if level == 0 {
            return "You are not in the Wilderness.".to_string();
        }
        format!(
            "Warning! You are in level-{} Wilderness. Players within {} combat \
             level{} of you can attack.",
            level,
            level,
            if level == 1 { "" } else { "s" }
        )
    }
}

// ---------------------------------------------------------------------------
// Skull integration
// ---------------------------------------------------------------------------

/// Skull duration in game ticks (approximately 20 minutes at 600 ms/tick).
pub const SKULL_DURATION_TICKS: u64 = 2000;

/// Per-player skull state.
///
/// A player becomes "skulled" when they initiate an attack against another
/// player in the Wilderness. While skulled the player drops **all** items on
/// death instead of keeping three.
#[derive(Debug, Clone)]
pub struct SkullManager {
    /// Whether the player is currently skulled.
    skulled: bool,
    /// Game tick at which the skull expires.
    skull_expires_tick: u64,
    /// The ID of the last player this player attacked first (used to
    /// determine retaliation vs. initiation).
    last_attacked_player: Option<u64>,
}

impl SkullManager {
    pub fn new() -> Self {
        Self {
            skulled: false,
            skull_expires_tick: 0,
            last_attacked_player: None,
        }
    }

    /// Whether the player currently has a skull.
    pub fn is_skulled(&self) -> bool {
        self.skulled
    }

    /// Apply a skull to the player.
    pub fn apply_skull(&mut self, current_tick: u64) {
        self.skulled = true;
        self.skull_expires_tick = current_tick + SKULL_DURATION_TICKS;
    }

    /// Tick the skull timer — call once per game tick.
    pub fn tick(&mut self, current_tick: u64) {
        if self.skulled && current_tick >= self.skull_expires_tick {
            self.skulled = false;
            self.last_attacked_player = None;
        }
    }

    /// Remove the skull immediately (e.g. admin command).
    pub fn remove_skull(&mut self) {
        self.skulled = false;
        self.skull_expires_tick = 0;
        self.last_attacked_player = None;
    }

    /// Record that this player initiated an attack against `target_id`.
    pub fn record_attack(&mut self, target_id: u64) {
        self.last_attacked_player = Some(target_id);
    }

    /// The last player this player attacked first.
    pub fn last_attacked(&self) -> Option<u64> {
        self.last_attacked_player
    }
}

impl Default for SkullManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Determine whether `attacker_id` should receive a skull for attacking
/// `target_id`.
///
/// The rule: a player is skulled when they **initiate** combat against another
/// player in the Wilderness. If the target attacked the attacker first (i.e.
/// the attacker is retaliating), no skull is applied.
///
/// `target_last_attacked` should be the value of
/// `target_skull_manager.last_attacked()`.
pub fn should_skull(attacker_id: u64, target_id: u64, target_last_attacked: Option<u64>) -> bool {
    // If the target previously attacked the current attacker, the current
    // attacker is merely retaliating — no skull.
    if let Some(last) = target_last_attacked {
        if last == attacker_id {
            return false;
        }
    }
    // Otherwise, the attacker is initiating — skull them.
    true
}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build a `ServerMessage` packet containing a wilderness warning.
pub fn build_wilderness_warning_packet(level: u32) -> Packet {
    let message = WildernessManager::get_warning_message(level);
    let mut packet = Packet::new(ServerOpcode::ServerMessage as u8);
    packet.add_string(&message);
    packet
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // -- Wilderness boundary detection --------------------------------------

    #[test]
    fn test_outside_wilderness() {
        let pos = Position::new(100, 500);
        assert!(!WildernessManager::is_in_wilderness(&pos));
        assert_eq!(WildernessManager::wilderness_level(&pos), 0);
    }

    #[test]
    fn test_at_wilderness_start() {
        let pos = Position::new(100, WILDERNESS_START_Y);
        assert!(WildernessManager::is_in_wilderness(&pos));
        assert_eq!(WildernessManager::wilderness_level(&pos), 1);
    }

    #[test]
    fn test_at_wilderness_end() {
        let pos = Position::new(100, WILDERNESS_END_Y);
        assert!(WildernessManager::is_in_wilderness(&pos));
    }

    #[test]
    fn test_above_wilderness() {
        let pos = Position::new(100, WILDERNESS_END_Y + 1);
        assert!(!WildernessManager::is_in_wilderness(&pos));
        assert_eq!(WildernessManager::wilderness_level(&pos), 0);
    }

    #[test]
    fn test_below_wilderness() {
        let pos = Position::new(100, WILDERNESS_START_Y - 1);
        assert!(!WildernessManager::is_in_wilderness(&pos));
    }

    // -- Wilderness level calculation ---------------------------------------

    #[test]
    fn test_wilderness_level_increments() {
        // Level 1 at Y = 2304
        assert_eq!(
            WildernessManager::wilderness_level(&Position::new(0, 2304)),
            1
        );
        // Level 1 for Y in [2304, 2309]
        assert_eq!(
            WildernessManager::wilderness_level(&Position::new(0, 2309)),
            1
        );
        // Level 2 at Y = 2310
        assert_eq!(
            WildernessManager::wilderness_level(&Position::new(0, 2310)),
            2
        );
        // Level 10 at Y = 2304 + 9*6 = 2358
        assert_eq!(
            WildernessManager::wilderness_level(&Position::new(0, 2358)),
            10
        );
    }

    #[test]
    fn test_wilderness_level_deep() {
        // Y = 2904 => (2904 - 2304) / 6 + 1 = 100 + 1 = 101
        assert_eq!(
            WildernessManager::wilderness_level(&Position::new(0, 2904)),
            101
        );
    }

    // -- Combat range checks ------------------------------------------------

    #[test]
    fn test_can_attack_same_level() {
        assert!(WildernessManager::can_attack(50, 50, 1));
    }

    #[test]
    fn test_can_attack_within_range() {
        // Wilderness level 5 allows combat diff up to 5.
        assert!(WildernessManager::can_attack(50, 55, 5));
        assert!(WildernessManager::can_attack(55, 50, 5));
    }

    #[test]
    fn test_cannot_attack_out_of_range() {
        assert!(!WildernessManager::can_attack(50, 56, 5));
        assert!(!WildernessManager::can_attack(56, 50, 5));
    }

    #[test]
    fn test_can_attack_level_1_wilderness() {
        assert!(WildernessManager::can_attack(30, 31, 1));
        assert!(WildernessManager::can_attack(31, 30, 1));
        assert!(!WildernessManager::can_attack(30, 32, 1));
    }

    #[test]
    fn test_can_attack_zero_wilderness() {
        // Wilderness level 0 means only exact same combat level could match,
        // but in practice this is outside the wilderness so combat shouldn't
        // happen — the caller checks `is_in_wilderness` first.
        assert!(WildernessManager::can_attack(50, 50, 0));
        assert!(!WildernessManager::can_attack(50, 51, 0));
    }

    // -- Warning messages ---------------------------------------------------

    #[test]
    fn test_warning_message_level_0() {
        let msg = WildernessManager::get_warning_message(0);
        assert_eq!(msg, "You are not in the Wilderness.");
    }

    #[test]
    fn test_warning_message_level_1() {
        let msg = WildernessManager::get_warning_message(1);
        assert!(msg.contains("level-1"));
        assert!(msg.contains("1 combat level "));
    }

    #[test]
    fn test_warning_message_level_5() {
        let msg = WildernessManager::get_warning_message(5);
        assert!(msg.contains("level-5"));
        assert!(msg.contains("5 combat levels"));
    }

    // -- Multi-combat zones -------------------------------------------------

    #[test]
    fn test_multi_combat_inside() {
        // Inside the Greater Demons area (208, 2688, 240, 2736).
        let pos = Position::new(220, 2700);
        assert!(WildernessBoundary::is_multi_combat(&pos));
    }

    #[test]
    fn test_multi_combat_outside() {
        let pos = Position::new(100, 2500);
        assert!(!WildernessBoundary::is_multi_combat(&pos));
    }

    #[test]
    fn test_multi_combat_boundary_inclusive() {
        // Exact corner of the Greater Demons zone.
        let pos = Position::new(208, 2688);
        assert!(WildernessBoundary::is_multi_combat(&pos));

        let pos = Position::new(240, 2736);
        assert!(WildernessBoundary::is_multi_combat(&pos));
    }

    // -- Skull integration --------------------------------------------------

    #[test]
    fn test_should_skull_initiate() {
        // Attacker initiates — target has not previously attacked attacker.
        assert!(should_skull(1, 2, None));
    }

    #[test]
    fn test_should_not_skull_retaliation() {
        // Target previously attacked the attacker => retaliation, no skull.
        assert!(!should_skull(1, 2, Some(1)));
    }

    #[test]
    fn test_should_skull_different_target() {
        // Target attacked someone else, not the current attacker.
        assert!(should_skull(1, 2, Some(3)));
    }

    // -- SkullManager -------------------------------------------------------

    #[test]
    fn test_skull_manager_new() {
        let sm = SkullManager::new();
        assert!(!sm.is_skulled());
        assert!(sm.last_attacked().is_none());
    }

    #[test]
    fn test_skull_apply_and_expire() {
        let mut sm = SkullManager::new();
        sm.apply_skull(100);
        assert!(sm.is_skulled());

        // Before expiry.
        sm.tick(100 + SKULL_DURATION_TICKS - 1);
        assert!(sm.is_skulled());

        // At expiry.
        sm.tick(100 + SKULL_DURATION_TICKS);
        assert!(!sm.is_skulled());
    }

    #[test]
    fn test_skull_remove() {
        let mut sm = SkullManager::new();
        sm.apply_skull(0);
        assert!(sm.is_skulled());

        sm.remove_skull();
        assert!(!sm.is_skulled());
    }

    #[test]
    fn test_skull_record_attack() {
        let mut sm = SkullManager::new();
        sm.record_attack(42);
        assert_eq!(sm.last_attacked(), Some(42));
    }

    #[test]
    fn test_skull_manager_default() {
        let sm = SkullManager::default();
        assert!(!sm.is_skulled());
    }

    // -- Packet builders ----------------------------------------------------

    #[test]
    fn test_wilderness_warning_packet() {
        let packet = build_wilderness_warning_packet(5);
        assert_eq!(packet.opcode, ServerOpcode::ServerMessage as u8);
        // Payload should contain the warning message as a null-terminated string.
        assert!(!packet.payload.is_empty());
        // Last byte should be the null terminator from add_string.
        assert_eq!(*packet.payload.last().unwrap(), 0);
    }

    #[test]
    fn test_wilderness_warning_packet_level_0() {
        let packet = build_wilderness_warning_packet(0);
        let msg_bytes = &packet.payload[..packet.payload.len() - 1]; // strip null
        let msg = std::str::from_utf8(msg_bytes).unwrap();
        assert_eq!(msg, "You are not in the Wilderness.");
    }

    // -- WildernessBoundary constants ---------------------------------------

    #[test]
    fn test_boundary_constants() {
        assert_eq!(WildernessBoundary::START_Y, 2304);
        assert_eq!(WildernessBoundary::END_Y, 3000);
    }
}
