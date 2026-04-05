//! Poison system for OpenRSC.
//! Handles poison application, tick-based damage, damage reduction over time, and curing.

use crate::protocol::opcodes::OpcodeOut;
use crate::protocol::{Packet, PacketBuilder};

/// Damage interval in game ticks (~12.8 seconds at 640ms per tick).
const POISON_TICK_INTERVAL: u64 = 20;

/// Number of consecutive hits at the same damage before reducing by 1.
const HITS_PER_DAMAGE_LEVEL: u8 = 4;

/// Maximum distance (tiles) for follow before auto-stop.
const MAX_FOLLOW_RANGE: i32 = 16;

// ---------------------------------------------------------------------------
// PoisonSource
// ---------------------------------------------------------------------------

/// Describes where a poison originated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PoisonSource {
    /// Poison from an NPC attack (e.g. poison spiders, KBD).
    NpcAttack {
        npc_id: u32,
        base_damage: u8,
    },
    /// Poison from a player's poisoned weapon.
    PlayerWeapon {
        weapon_id: u32,
        base_damage: u8,
    },
}

impl PoisonSource {
    /// Base damage for the source.
    pub fn base_damage(&self) -> u8 {
        match self {
            PoisonSource::NpcAttack { base_damage, .. } => *base_damage,
            PoisonSource::PlayerWeapon { base_damage, .. } => *base_damage,
        }
    }
}

/// Well-known poisonous NPCs and their base poison damage values.
pub mod known_npcs {
    use super::PoisonSource;

    /// Poison spider — base damage 6.
    pub const POISON_SPIDER: PoisonSource = PoisonSource::NpcAttack {
        npc_id: 292,
        base_damage: 6,
    };

    /// King Black Dragon — base damage 12.
    pub const KING_BLACK_DRAGON: PoisonSource = PoisonSource::NpcAttack {
        npc_id: 477,
        base_damage: 12,
    };

    /// Tribesman — base damage 4.
    pub const TRIBESMAN: PoisonSource = PoisonSource::NpcAttack {
        npc_id: 180,
        base_damage: 4,
    };

    /// Poison scorpion — base damage 3.
    pub const POISON_SCORPION: PoisonSource = PoisonSource::NpcAttack {
        npc_id: 293,
        base_damage: 3,
    };
}

// ---------------------------------------------------------------------------
// PoisonState
// ---------------------------------------------------------------------------

/// Snapshot of the poison status of an entity.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PoisonState {
    /// Whether the entity is currently poisoned.
    pub poisoned: bool,
    /// Current poison hit damage (decreases over time).
    pub poison_damage: u8,
    /// The game tick at which the next poison damage fires.
    pub next_poison_tick: u64,
}

impl Default for PoisonState {
    fn default() -> Self {
        Self {
            poisoned: false,
            poison_damage: 0,
            next_poison_tick: 0,
        }
    }
}

// ---------------------------------------------------------------------------
// PoisonManager
// ---------------------------------------------------------------------------

/// Manages the poison lifecycle for a single entity.
#[derive(Debug, Clone)]
pub struct PoisonManager {
    /// Current poison state.
    state: PoisonState,
    /// How many hits have been dealt at the current damage level.
    /// Resets to 0 each time the damage is reduced.
    hits_at_current_damage: u8,
    /// Optional record of the source that applied the poison.
    source: Option<PoisonSource>,
}

impl Default for PoisonManager {
    fn default() -> Self {
        Self {
            state: PoisonState::default(),
            hits_at_current_damage: 0,
            source: None,
        }
    }
}

impl PoisonManager {
    /// Create a new, unpoisoned manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Apply poison with the given initial damage starting at `current_tick`.
    ///
    /// If the entity is already poisoned with equal or greater damage the call
    /// is ignored (stronger poison cannot be downgraded).
    pub fn apply_poison(&mut self, initial_damage: u8, current_tick: u64) {
        if initial_damage == 0 {
            return;
        }
        // Only apply if not already poisoned with equal or higher damage.
        if self.state.poisoned && self.state.poison_damage >= initial_damage {
            return;
        }
        self.state.poisoned = true;
        self.state.poison_damage = initial_damage;
        self.state.next_poison_tick = current_tick + POISON_TICK_INTERVAL;
        self.hits_at_current_damage = 0;
        self.source = None;
    }

    /// Apply poison from a known source.
    pub fn apply_from_source(&mut self, source: PoisonSource, current_tick: u64) {
        let damage = source.base_damage();
        if damage == 0 {
            return;
        }
        if self.state.poisoned && self.state.poison_damage >= damage {
            return;
        }
        self.state.poisoned = true;
        self.state.poison_damage = damage;
        self.state.next_poison_tick = current_tick + POISON_TICK_INTERVAL;
        self.hits_at_current_damage = 0;
        self.source = Some(source);
    }

    /// Cure the poison entirely (e.g. drinking antipoison).
    pub fn cure_poison(&mut self) {
        self.state.poisoned = false;
        self.state.poison_damage = 0;
        self.state.next_poison_tick = 0;
        self.hits_at_current_damage = 0;
        self.source = None;
    }

    /// Process a game tick.
    ///
    /// Returns `Some(damage)` when a poison hit fires this tick, or `None`
    /// otherwise. Automatically handles the damage-reduction schedule:
    /// every [`HITS_PER_DAMAGE_LEVEL`] hits the damage decreases by 1.
    /// When damage reaches 0 the entity is cured.
    pub fn tick(&mut self, current_tick: u64) -> Option<u8> {
        if !self.state.poisoned {
            return None;
        }

        if current_tick < self.state.next_poison_tick {
            return None;
        }

        // Fire poison damage.
        let damage = self.state.poison_damage;
        self.hits_at_current_damage += 1;

        // Schedule the next tick.
        self.state.next_poison_tick = current_tick + POISON_TICK_INTERVAL;

        // Every HITS_PER_DAMAGE_LEVEL hits, reduce the damage by 1.
        if self.hits_at_current_damage >= HITS_PER_DAMAGE_LEVEL {
            self.hits_at_current_damage = 0;
            self.state.poison_damage = self.state.poison_damage.saturating_sub(1);

            // Poison wears off when damage reaches 0.
            if self.state.poison_damage == 0 {
                self.cure_poison();
            }
        }

        Some(damage)
    }

    /// Whether the entity is currently poisoned.
    pub fn is_poisoned(&self) -> bool {
        self.state.poisoned
    }

    /// Read-only access to the current state snapshot.
    pub fn state(&self) -> &PoisonState {
        &self.state
    }

    /// The source that applied the current poison, if tracked.
    pub fn source(&self) -> Option<&PoisonSource> {
        self.source.as_ref()
    }
}

// ---------------------------------------------------------------------------
// Packet helpers
// ---------------------------------------------------------------------------

/// Server-message opcode used for the poison-indicator packet.
/// In the RSC protocol this is typically sent as a server message.
const POISON_INDICATOR_OPCODE: u8 = OpcodeOut::ServerMessage as u8;

/// Build a packet that tells the client to show or hide the poison indicator.
///
/// The original RSC protocol encodes this as a server message with a special
/// prefix so the client can toggle the green overlay.
pub fn build_poison_indicator_packet(poisoned: bool) -> Packet {
    PacketBuilder::new(POISON_INDICATOR_OPCODE)
        .write_byte(if poisoned { 1 } else { 0 })
        .build()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apply_poison() {
        let mut mgr = PoisonManager::new();
        assert!(!mgr.is_poisoned());

        mgr.apply_poison(6, 100);
        assert!(mgr.is_poisoned());
        assert_eq!(mgr.state().poison_damage, 6);
        assert_eq!(mgr.state().next_poison_tick, 120);
    }

    #[test]
    fn test_zero_damage_ignored() {
        let mut mgr = PoisonManager::new();
        mgr.apply_poison(0, 50);
        assert!(!mgr.is_poisoned());
    }

    #[test]
    fn test_stronger_poison_replaces() {
        let mut mgr = PoisonManager::new();
        mgr.apply_poison(4, 10);
        assert_eq!(mgr.state().poison_damage, 4);

        // Higher damage should replace.
        mgr.apply_poison(8, 20);
        assert_eq!(mgr.state().poison_damage, 8);
        assert_eq!(mgr.state().next_poison_tick, 40);
    }

    #[test]
    fn test_weaker_poison_does_not_replace() {
        let mut mgr = PoisonManager::new();
        mgr.apply_poison(8, 10);

        mgr.apply_poison(4, 50);
        // Should still be 8.
        assert_eq!(mgr.state().poison_damage, 8);
        assert_eq!(mgr.state().next_poison_tick, 30);
    }

    #[test]
    fn test_cure_poison() {
        let mut mgr = PoisonManager::new();
        mgr.apply_poison(6, 100);
        assert!(mgr.is_poisoned());

        mgr.cure_poison();
        assert!(!mgr.is_poisoned());
        assert_eq!(mgr.state().poison_damage, 0);
    }

    #[test]
    fn test_tick_no_damage_before_interval() {
        let mut mgr = PoisonManager::new();
        mgr.apply_poison(6, 100);

        // Ticks before the scheduled poison tick should return None.
        assert_eq!(mgr.tick(110), None);
        assert_eq!(mgr.tick(119), None);
    }

    #[test]
    fn test_tick_fires_at_interval() {
        let mut mgr = PoisonManager::new();
        mgr.apply_poison(6, 100);

        let dmg = mgr.tick(120);
        assert_eq!(dmg, Some(6));
        // Next tick should be 20 ticks later.
        assert_eq!(mgr.state().next_poison_tick, 140);
    }

    #[test]
    fn test_damage_reduction_over_time() {
        let mut mgr = PoisonManager::new();
        mgr.apply_poison(6, 0);

        // Damage pattern: 6,6,6,6 -> 5,5,5,5 -> 4,4,4,4 -> ...
        let mut tick = POISON_TICK_INTERVAL;
        let mut expected_damages: Vec<u8> = Vec::new();

        // Collect all damage values until cured.
        loop {
            match mgr.tick(tick) {
                Some(d) => expected_damages.push(d),
                None if !mgr.is_poisoned() => break,
                None => {}
            }
            tick += POISON_TICK_INTERVAL;
            // Safety: break after 200 iterations to avoid infinite loop in test.
            if expected_damages.len() > 200 {
                panic!("poison never ended");
            }
        }

        // Verify the pattern: 4 hits at each level from 6 down to 1.
        // Total hits = 4 * 6 = 24.
        assert_eq!(expected_damages.len(), 24);

        for level in 1u8..=6 {
            let damage = 7 - level; // 6,5,4,3,2,1
            let start = ((level - 1) as usize) * 4;
            for i in 0..4 {
                assert_eq!(
                    expected_damages[start + i], damage,
                    "hit {} should deal {} damage",
                    start + i,
                    damage
                );
            }
        }

        assert!(!mgr.is_poisoned());
    }

    #[test]
    fn test_apply_from_source() {
        let mut mgr = PoisonManager::new();
        mgr.apply_from_source(known_npcs::POISON_SPIDER, 50);
        assert!(mgr.is_poisoned());
        assert_eq!(mgr.state().poison_damage, 6);
        assert!(matches!(
            mgr.source(),
            Some(PoisonSource::NpcAttack { npc_id: 292, .. })
        ));
    }

    #[test]
    fn test_known_npc_damage_values() {
        assert_eq!(known_npcs::POISON_SPIDER.base_damage(), 6);
        assert_eq!(known_npcs::KING_BLACK_DRAGON.base_damage(), 12);
        assert_eq!(known_npcs::TRIBESMAN.base_damage(), 4);
        assert_eq!(known_npcs::POISON_SCORPION.base_damage(), 3);
    }

    #[test]
    fn test_build_poison_indicator_packet() {
        let pkt = build_poison_indicator_packet(true);
        assert_eq!(pkt.opcode, OpcodeOut::ServerMessage as u8);
        assert!(!pkt.is_empty());

        let pkt_off = build_poison_indicator_packet(false);
        assert_eq!(pkt_off.opcode, OpcodeOut::ServerMessage as u8);
    }

    #[test]
    fn test_tick_on_unpoisoned_returns_none() {
        let mut mgr = PoisonManager::new();
        assert_eq!(mgr.tick(500), None);
    }

    #[test]
    fn test_cure_during_cycle_resets_hits_counter() {
        let mut mgr = PoisonManager::new();
        mgr.apply_poison(6, 0);

        // Fire two hits.
        assert_eq!(mgr.tick(20), Some(6));
        assert_eq!(mgr.tick(40), Some(6));

        // Cure and re-apply.
        mgr.cure_poison();
        mgr.apply_poison(3, 50);
        assert_eq!(mgr.state().poison_damage, 3);

        // Should start a fresh cycle of 4 hits at damage 3.
        assert_eq!(mgr.tick(70), Some(3));
        assert_eq!(mgr.tick(90), Some(3));
        assert_eq!(mgr.tick(110), Some(3));
        assert_eq!(mgr.tick(130), Some(3));
        // Now damage drops to 2.
        assert_eq!(mgr.state().poison_damage, 2);
    }
}
