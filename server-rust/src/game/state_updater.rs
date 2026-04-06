//! Per-tick outbound update generator for the RSC binary protocol.
//!
//! Builds bit-packed position and appearance update packets that tell each
//! client which players, NPCs, game-objects, and ground-items are visible
//! and how they have changed since the previous tick.
//!
//! Update order per tick:
//!   1. Player positions
//!   2. Player appearances
//!   3. NPC positions
//!   4. NPC appearances
//!   5. Game-objects
//!   6. Ground-items

use std::collections::HashSet;

use super::entity::{Direction, EntityId, Position};
use super::game_object::{GameObject, ObjectType};
use super::ground_item::GroundItem;
use super::item::ItemId;
use super::protocol::{Packet, ServerOpcode};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Entities within this Chebyshev distance are considered "in view".
const VIEW_DISTANCE: i32 = 16;

/// Maximum number of known players the client can track at once.
const MAX_KNOWN_PLAYERS: usize = 255;

/// Maximum number of known NPCs the client can track at once.
const MAX_KNOWN_NPCS: usize = 255;

// ---------------------------------------------------------------------------
// Direction helpers
// ---------------------------------------------------------------------------

/// Encode a `Direction` to the 3-bit wire value used by the RSC protocol.
fn direction_to_bits(dir: Direction) -> u32 {
    match dir {
        Direction::North => 0,
        Direction::NorthWest => 1,
        Direction::West => 2,
        Direction::SouthWest => 3,
        Direction::South => 4,
        Direction::SouthEast => 5,
        Direction::East => 6,
        Direction::NorthEast => 7,
    }
}

// ---------------------------------------------------------------------------
// Update-type constants (2 bits)
// ---------------------------------------------------------------------------

/// Entity has not changed since last tick.
const UPDATE_NONE: u32 = 0;
/// Entity moved (walked).
const UPDATE_MOVED: u32 = 1;
/// Entity appeared in or was removed from the view area.
const UPDATE_APPEARED_OR_REMOVED: u32 = 2;
/// Entity appearance data changed (equipment, skull, etc.).
const UPDATE_APPEARANCE: u32 = 3;

// ---------------------------------------------------------------------------
// Lightweight snapshot types
// ---------------------------------------------------------------------------

/// Read-only snapshot of a player taken at the start of the tick.
#[derive(Debug, Clone)]
pub struct PlayerSnapshot {
    pub entity_id: EntityId,
    /// Server-wide unique player index (fits in 16 bits).
    pub player_index: u16,
    pub position: Position,
    pub direction: Direction,
    /// Set if the player moved this tick.
    pub moved_this_tick: bool,
    /// Set if an appearance-level property changed since last broadcast.
    pub appearance_changed: bool,
    /// Pre-built appearance byte blob (see `appearance::build_appearance_data`).
    pub appearance_data: Vec<u8>,
}

/// Read-only snapshot of an NPC taken at the start of the tick.
#[derive(Debug, Clone)]
pub struct NpcSnapshot {
    pub entity_id: EntityId,
    /// NPC server index.
    pub npc_index: u16,
    /// Definition id (used by client to look up sprites/stats).
    pub def_id: u32,
    pub position: Position,
    pub direction: Direction,
    /// Set if the NPC moved this tick.
    pub moved_this_tick: bool,
    /// Set if the NPC is removed (dead / despawning).
    pub removed: bool,
}

/// Snapshot of a game-object for the update packet.
#[derive(Debug, Clone)]
pub struct GameObjectSnapshot {
    pub def_id: u32,
    pub position: Position,
    pub direction: u8,
    pub object_type: ObjectType,
}

impl GameObjectSnapshot {
    pub fn from_game_object(obj: &GameObject) -> Self {
        Self {
            def_id: obj.def_id,
            position: obj.position,
            direction: obj.direction.value(),
            object_type: obj.object_type,
        }
    }
}

/// Snapshot of a ground-item for the update packet.
#[derive(Debug, Clone)]
pub struct GroundItemSnapshot {
    pub item_id: ItemId,
    pub amount: u32,
    pub position: Position,
}

impl GroundItemSnapshot {
    pub fn from_ground_item(item: &GroundItem) -> Self {
        Self {
            item_id: item.item_id,
            amount: item.amount,
            position: item.position,
        }
    }
}

// ---------------------------------------------------------------------------
// KnownEntityList
// ---------------------------------------------------------------------------

/// Tracks which entities a particular client already knows about so that
/// we only send "appeared" once and "removed" when they leave the view area.
#[derive(Debug, Clone)]
pub struct KnownEntityList {
    ids: HashSet<EntityId>,
    capacity: usize,
}

impl KnownEntityList {
    /// Create a new list with the given capacity cap.
    pub fn new(capacity: usize) -> Self {
        Self {
            ids: HashSet::with_capacity(capacity),
            capacity,
        }
    }

    /// Create a player-sized known list.
    pub fn for_players() -> Self {
        Self::new(MAX_KNOWN_PLAYERS)
    }

    /// Create an NPC-sized known list.
    pub fn for_npcs() -> Self {
        Self::new(MAX_KNOWN_NPCS)
    }

    /// Returns `true` if the entity is already tracked by the client.
    pub fn contains(&self, id: EntityId) -> bool {
        self.ids.contains(&id)
    }

    /// Track a new entity.  Returns `false` if at capacity.
    pub fn add(&mut self, id: EntityId) -> bool {
        if self.ids.len() >= self.capacity {
            return false;
        }
        self.ids.insert(id)
    }

    /// Stop tracking an entity.
    pub fn remove(&mut self, id: EntityId) -> bool {
        self.ids.remove(&id)
    }

    /// Number of currently tracked entities.
    pub fn len(&self) -> usize {
        self.ids.len()
    }

    /// Whether the list is empty.
    pub fn is_empty(&self) -> bool {
        self.ids.is_empty()
    }

    /// Iterate over currently tracked entity ids.
    pub fn iter(&self) -> impl Iterator<Item = &EntityId> {
        self.ids.iter()
    }

    /// Remove all entries.
    pub fn clear(&mut self) {
        self.ids.clear();
    }
}

// ---------------------------------------------------------------------------
// BitWriter  (self-contained, protocol-oriented)
// ---------------------------------------------------------------------------

/// Writes individual bits into an expanding byte buffer.
///
/// Bits are written MSB-first within each byte, matching the RSC client's
/// bit-stream reader.
#[derive(Debug, Clone)]
pub struct BitWriter {
    buf: Vec<u8>,
    bit_pos: usize,
}

impl BitWriter {
    /// Create a new writer with pre-allocated capacity (in bytes).
    pub fn new(capacity: usize) -> Self {
        let mut buf = Vec::with_capacity(capacity);
        buf.push(0);
        Self { buf, bit_pos: 0 }
    }

    /// Write `num_bits` (1..=32) from the low bits of `value`.
    pub fn write_bits(&mut self, value: u32, num_bits: u32) {
        debug_assert!(num_bits >= 1 && num_bits <= 32);
        for i in (0..num_bits).rev() {
            let bit = (value >> i) & 1;
            let byte_idx = self.bit_pos / 8;
            let bit_idx = 7 - (self.bit_pos % 8);

            // Grow buffer if needed
            while byte_idx >= self.buf.len() {
                self.buf.push(0);
            }

            if bit == 1 {
                self.buf[byte_idx] |= 1 << bit_idx;
            }
            self.bit_pos += 1;
        }
    }

    /// Total bits written so far.
    pub fn bit_position(&self) -> usize {
        self.bit_pos
    }

    /// Consume the writer and return the byte buffer (padded to a full byte
    /// with trailing zeroes).
    pub fn finish(self) -> Vec<u8> {
        let byte_len = (self.bit_pos + 7) / 8;
        let mut buf = self.buf;
        buf.truncate(byte_len);
        buf
    }
}

// ---------------------------------------------------------------------------
// GameStateUpdater
// ---------------------------------------------------------------------------

/// Generates per-tick outbound packets for a single player.
///
/// The caller is expected to invoke [`generate_updates`] once per game tick
/// for every online player, passing the world-state snapshots collected at
/// the top of the tick.
pub struct GameStateUpdater;

impl GameStateUpdater {
    /// Build all outbound update packets for `player_pos` this tick.
    ///
    /// Returns a `Vec<Packet>` in the canonical send order:
    ///   1. Player position update
    ///   2. Player appearance update (only when there are new/changed players)
    ///   3. NPC position update
    ///   4. NPC appearance update (only when there are new/changed NPCs)
    ///   5. Game-objects update
    ///   6. Ground-items update
    pub fn generate_updates(
        player_id: EntityId,
        player_pos: Position,
        known_players: &mut KnownEntityList,
        known_npcs: &mut KnownEntityList,
        all_players: &[PlayerSnapshot],
        all_npcs: &[NpcSnapshot],
        nearby_objects: &[GameObjectSnapshot],
        nearby_ground_items: &[GroundItemSnapshot],
    ) -> Vec<Packet> {
        let mut packets = Vec::with_capacity(6);

        // --- 1. Player position update ---
        let (player_pos_pkt, players_needing_appearance) = Self::build_player_position_update(
            player_id,
            player_pos,
            known_players,
            all_players,
        );
        packets.push(player_pos_pkt);

        // --- 2. Player appearance update ---
        if !players_needing_appearance.is_empty() {
            if let Some(pkt) =
                Self::build_player_appearance_update(&players_needing_appearance, all_players)
            {
                packets.push(pkt);
            }
        }

        // --- 3. NPC position update ---
        let (npc_pos_pkt, npcs_needing_appearance) =
            Self::build_npc_position_update(player_pos, known_npcs, all_npcs);
        packets.push(npc_pos_pkt);

        // --- 4. NPC appearance update ---
        if !npcs_needing_appearance.is_empty() {
            if let Some(pkt) =
                Self::build_npc_appearance_update(&npcs_needing_appearance, all_npcs)
            {
                packets.push(pkt);
            }
        }

        // --- 5. Game-objects ---
        if !nearby_objects.is_empty() {
            packets.push(Self::build_objects_update(player_pos, nearby_objects));
        }

        // --- 6. Ground-items ---
        if !nearby_ground_items.is_empty() {
            packets.push(Self::build_ground_items_update(player_pos, nearby_ground_items));
        }

        packets
    }

    // -----------------------------------------------------------------------
    // Player position packet  (ServerOpcode::PlayerPosition = 6)
    // -----------------------------------------------------------------------

    /// Encode a player-position update packet.
    ///
    /// Wire layout (bit-packed):
    ///   - 11 bits: this player's X
    ///   - 13 bits: this player's Y
    ///   -  4 bits: this player's direction
    ///   -  8 bits: number of known players being updated
    ///   Per known player already tracked:
    ///     -  2 bits: update type
    ///     If UPDATE_MOVED:
    ///       -  3 bits: direction
    ///       -  1 bit:  1 (moved flag)
    ///     If UPDATE_APPEARED_OR_REMOVED:
    ///       (removed -- we simply stop tracking; no extra bits)
    ///     If UPDATE_APPEARANCE:
    ///       -  3 bits: direction
    ///       -  1 bit:  0 (not moved)
    ///   Per newly visible player:
    ///     - 16 bits: server player index
    ///     - 11 bits: X offset from this player + VIEW_DISTANCE (unsigned)
    ///     - 13 bits: Y offset from this player + VIEW_DISTANCE (unsigned)
    ///     -  4 bits: direction
    ///
    /// Returns the packet **and** a list of entity-ids whose appearance data
    /// the client needs (new players + players whose appearance changed).
    fn build_player_position_update(
        self_id: EntityId,
        self_pos: Position,
        known: &mut KnownEntityList,
        all: &[PlayerSnapshot],
    ) -> (Packet, Vec<EntityId>) {
        let mut bw = BitWriter::new(512);
        let mut appearance_needed: Vec<EntityId> = Vec::new();

        // --- Header: this player's own position ---
        bw.write_bits(self_pos.x as u32 & 0x7FF, 11);
        bw.write_bits(self_pos.y as u32 & 0x1FFF, 13);
        // Find own direction in snapshot
        let self_dir = all
            .iter()
            .find(|p| p.entity_id == self_id)
            .map(|p| direction_to_bits(p.direction))
            .unwrap_or(4); // South fallback
        bw.write_bits(self_dir, 4);

        // --- Existing known players ---
        // We need to first figure out updates for currently known players,
        // then count them so we can write the 8-bit count.
        //
        // Gather updates: (entity_id, update_type, direction)
        struct KnownUpdate {
            id: EntityId,
            update: u32,
            dir: u32,
            moved: bool,
        }

        let current_known: Vec<EntityId> = known.iter().copied().collect();
        let mut known_updates: Vec<KnownUpdate> = Vec::with_capacity(current_known.len());
        let mut to_remove: Vec<EntityId> = Vec::new();

        for eid in &current_known {
            if *eid == self_id {
                continue; // skip self
            }
            match all.iter().find(|p| p.entity_id == *eid) {
                Some(snap) => {
                    if !in_view(self_pos, snap.position) {
                        // Went out of range -> remove
                        to_remove.push(*eid);
                        known_updates.push(KnownUpdate {
                            id: *eid,
                            update: UPDATE_APPEARED_OR_REMOVED,
                            dir: 0,
                            moved: false,
                        });
                    } else if snap.appearance_changed {
                        appearance_needed.push(*eid);
                        known_updates.push(KnownUpdate {
                            id: *eid,
                            update: UPDATE_APPEARANCE,
                            dir: direction_to_bits(snap.direction),
                            moved: false,
                        });
                    } else if snap.moved_this_tick {
                        known_updates.push(KnownUpdate {
                            id: *eid,
                            update: UPDATE_MOVED,
                            dir: direction_to_bits(snap.direction),
                            moved: true,
                        });
                    } else {
                        known_updates.push(KnownUpdate {
                            id: *eid,
                            update: UPDATE_NONE,
                            dir: 0,
                            moved: false,
                        });
                    }
                }
                None => {
                    // Player logged off -> remove
                    to_remove.push(*eid);
                    known_updates.push(KnownUpdate {
                        id: *eid,
                        update: UPDATE_APPEARED_OR_REMOVED,
                        dir: 0,
                        moved: false,
                    });
                }
            }
        }

        // Actually remove them from the known set
        for eid in &to_remove {
            known.remove(*eid);
        }

        // Write known-player count (8 bits)
        bw.write_bits(known_updates.len() as u32, 8);

        // Write per-known-player update bits
        for ku in &known_updates {
            bw.write_bits(ku.update, 2);
            match ku.update {
                UPDATE_MOVED => {
                    bw.write_bits(ku.dir, 3);
                    bw.write_bits(1, 1); // moved=1
                }
                UPDATE_APPEARANCE => {
                    bw.write_bits(ku.dir, 3);
                    bw.write_bits(0, 1); // moved=0
                }
                UPDATE_APPEARED_OR_REMOVED | UPDATE_NONE => {
                    // No additional bits for removed or no-change
                }
                _ => {}
            }
        }

        // --- Newly visible players ---
        for snap in all {
            if snap.entity_id == self_id {
                continue;
            }
            if known.contains(snap.entity_id) {
                continue; // already tracked
            }
            if !in_view(self_pos, snap.position) {
                continue;
            }
            if !known.add(snap.entity_id) {
                break; // at capacity
            }

            appearance_needed.push(snap.entity_id);

            bw.write_bits(snap.player_index as u32, 16);

            // Offsets are encoded as unsigned values relative to view distance
            let dx = (snap.position.x - self_pos.x + VIEW_DISTANCE) as u32;
            let dy = (snap.position.y - self_pos.y + VIEW_DISTANCE) as u32;
            bw.write_bits(dx & 0x7FF, 11);
            bw.write_bits(dy & 0x1FFF, 13);
            bw.write_bits(direction_to_bits(snap.direction), 4);
        }

        let payload = bw.finish();
        let pkt = Packet::with_payload(ServerOpcode::PlayerPosition as u8, payload);

        (pkt, appearance_needed)
    }

    // -----------------------------------------------------------------------
    // Player appearance packet  (ServerOpcode::PlayerUpdate = 2)
    // -----------------------------------------------------------------------

    /// Build the player-appearance update packet.
    ///
    /// Wire layout (byte-oriented after the opcode):
    ///   - 2 bytes (big-endian): number of entries
    ///   Per entry:
    ///     - 2 bytes: player server index
    ///     - 2 bytes: length of appearance blob
    ///     - N bytes: appearance blob (see `appearance::build_appearance_data`)
    fn build_player_appearance_update(
        needed: &[EntityId],
        all: &[PlayerSnapshot],
    ) -> Option<Packet> {
        if needed.is_empty() {
            return None;
        }

        let mut payload: Vec<u8> = Vec::with_capacity(256);

        // Entry count (2 bytes)
        let count = needed.len().min(u16::MAX as usize) as u16;
        payload.push((count >> 8) as u8);
        payload.push(count as u8);

        for eid in needed.iter().take(count as usize) {
            if let Some(snap) = all.iter().find(|p| p.entity_id == *eid) {
                // Player index
                payload.push((snap.player_index >> 8) as u8);
                payload.push(snap.player_index as u8);

                // Appearance data length + blob
                let alen = snap.appearance_data.len().min(u16::MAX as usize) as u16;
                payload.push((alen >> 8) as u8);
                payload.push(alen as u8);
                payload.extend_from_slice(&snap.appearance_data[..alen as usize]);
            }
        }

        Some(Packet::with_payload(
            ServerOpcode::PlayerUpdate as u8,
            payload,
        ))
    }

    // -----------------------------------------------------------------------
    // NPC position packet  (ServerOpcode::NpcUpdate = 7)
    // -----------------------------------------------------------------------

    /// Build the NPC position update packet.
    ///
    /// Wire layout (bit-packed):
    ///   -  8 bits: number of known NPCs being updated
    ///   Per known NPC:
    ///     -  2 bits: update type
    ///     If UPDATE_MOVED:
    ///       -  3 bits: direction
    ///       -  1 bit:  1 (moved)
    ///     If UPDATE_APPEARED_OR_REMOVED:
    ///       (no extra bits -- removed)
    ///     If UPDATE_APPEARANCE:
    ///       -  3 bits: direction
    ///       -  1 bit:  0 (not moved)
    ///   Per newly visible NPC:
    ///     - 16 bits: NPC server index
    ///     - 11 bits: X offset + VIEW_DISTANCE
    ///     - 13 bits: Y offset + VIEW_DISTANCE
    ///     -  4 bits: direction
    ///     - 16 bits: NPC definition ID
    fn build_npc_position_update(
        self_pos: Position,
        known: &mut KnownEntityList,
        all: &[NpcSnapshot],
    ) -> (Packet, Vec<EntityId>) {
        let mut bw = BitWriter::new(512);
        let mut appearance_needed: Vec<EntityId> = Vec::new();

        struct KnownNpcUpdate {
            update: u32,
            dir: u32,
        }

        let current_known: Vec<EntityId> = known.iter().copied().collect();
        let mut known_updates: Vec<KnownNpcUpdate> = Vec::with_capacity(current_known.len());
        let mut to_remove: Vec<EntityId> = Vec::new();

        for eid in &current_known {
            match all.iter().find(|n| n.entity_id == *eid) {
                Some(snap) => {
                    if !in_view(self_pos, snap.position) || snap.removed {
                        to_remove.push(*eid);
                        known_updates.push(KnownNpcUpdate {
                            update: UPDATE_APPEARED_OR_REMOVED,
                            dir: 0,
                        });
                    } else if snap.moved_this_tick {
                        known_updates.push(KnownNpcUpdate {
                            update: UPDATE_MOVED,
                            dir: direction_to_bits(snap.direction),
                        });
                    } else {
                        known_updates.push(KnownNpcUpdate {
                            update: UPDATE_NONE,
                            dir: 0,
                        });
                    }
                }
                None => {
                    to_remove.push(*eid);
                    known_updates.push(KnownNpcUpdate {
                        update: UPDATE_APPEARED_OR_REMOVED,
                        dir: 0,
                    });
                }
            }
        }

        for eid in &to_remove {
            known.remove(*eid);
        }

        // Known NPC count
        bw.write_bits(known_updates.len() as u32, 8);

        for ku in &known_updates {
            bw.write_bits(ku.update, 2);
            match ku.update {
                UPDATE_MOVED => {
                    bw.write_bits(ku.dir, 3);
                    bw.write_bits(1, 1);
                }
                UPDATE_APPEARANCE => {
                    bw.write_bits(ku.dir, 3);
                    bw.write_bits(0, 1);
                }
                UPDATE_APPEARED_OR_REMOVED | UPDATE_NONE => {}
                _ => {}
            }
        }

        // Newly visible NPCs
        for snap in all {
            if known.contains(snap.entity_id) {
                continue;
            }
            if snap.removed {
                continue;
            }
            if !in_view(self_pos, snap.position) {
                continue;
            }
            if !known.add(snap.entity_id) {
                break; // at capacity
            }

            appearance_needed.push(snap.entity_id);

            bw.write_bits(snap.npc_index as u32, 16);

            let dx = (snap.position.x - self_pos.x + VIEW_DISTANCE) as u32;
            let dy = (snap.position.y - self_pos.y + VIEW_DISTANCE) as u32;
            bw.write_bits(dx & 0x7FF, 11);
            bw.write_bits(dy & 0x1FFF, 13);
            bw.write_bits(direction_to_bits(snap.direction), 4);
            bw.write_bits(snap.def_id & 0xFFFF, 16);
        }

        let payload = bw.finish();
        let pkt = Packet::with_payload(ServerOpcode::NpcUpdate as u8, payload);

        (pkt, appearance_needed)
    }

    // -----------------------------------------------------------------------
    // NPC appearance packet  (ServerOpcode::NpcMessage = 9)
    // -----------------------------------------------------------------------

    /// Build an NPC appearance/message update packet.
    ///
    /// For each NPC whose appearance the client does not yet know:
    ///   - 2 bytes: NPC server index
    ///   - 2 bytes: definition ID
    fn build_npc_appearance_update(
        needed: &[EntityId],
        all: &[NpcSnapshot],
    ) -> Option<Packet> {
        if needed.is_empty() {
            return None;
        }

        let mut payload: Vec<u8> = Vec::with_capacity(needed.len() * 4);
        let count = needed.len().min(u16::MAX as usize) as u16;
        payload.push((count >> 8) as u8);
        payload.push(count as u8);

        for eid in needed.iter().take(count as usize) {
            if let Some(snap) = all.iter().find(|n| n.entity_id == *eid) {
                payload.push((snap.npc_index >> 8) as u8);
                payload.push(snap.npc_index as u8);
                let def = snap.def_id as u16;
                payload.push((def >> 8) as u8);
                payload.push(def as u8);
            }
        }

        Some(Packet::with_payload(
            ServerOpcode::NpcMessage as u8,
            payload,
        ))
    }

    // -----------------------------------------------------------------------
    // Game-objects update  (ServerOpcode::ObjectsUpdate = 4)
    // -----------------------------------------------------------------------

    /// Build the game-object update packet for objects near the player.
    ///
    /// Wire layout (byte-oriented):
    ///   Per visible object:
    ///     - 2 bytes: object definition ID
    ///     - 2 bytes: X position
    ///     - 2 bytes: Y position
    ///     - 1 byte:  direction
    fn build_objects_update(self_pos: Position, objects: &[GameObjectSnapshot]) -> Packet {
        let mut payload: Vec<u8> = Vec::with_capacity(objects.len() * 7);

        for obj in objects {
            if !in_view(self_pos, obj.position) {
                continue;
            }
            let id = obj.def_id as u16;
            payload.push((id >> 8) as u8);
            payload.push(id as u8);

            let x = obj.position.x as u16;
            payload.push((x >> 8) as u8);
            payload.push(x as u8);

            let y = obj.position.y as u16;
            payload.push((y >> 8) as u8);
            payload.push(y as u8);

            payload.push(obj.direction);
        }

        Packet::with_payload(ServerOpcode::ObjectsUpdate as u8, payload)
    }

    // -----------------------------------------------------------------------
    // Ground-items update  (ServerOpcode::GroundItemsUpdate = 3)
    // -----------------------------------------------------------------------

    /// Build the ground-item update packet for items near the player.
    ///
    /// Wire layout (byte-oriented):
    ///   Per visible item:
    ///     - 2 bytes: item catalogue ID
    ///     - 2 bytes: X position
    ///     - 2 bytes: Y position
    fn build_ground_items_update(
        self_pos: Position,
        items: &[GroundItemSnapshot],
    ) -> Packet {
        let mut payload: Vec<u8> = Vec::with_capacity(items.len() * 6);

        for item in items {
            if !in_view(self_pos, item.position) {
                continue;
            }
            let id = item.item_id.0 as u16;
            payload.push((id >> 8) as u8);
            payload.push(id as u8);

            let x = item.position.x as u16;
            payload.push((x >> 8) as u8);
            payload.push(x as u8);

            let y = item.position.y as u16;
            payload.push((y >> 8) as u8);
            payload.push(y as u8);
        }

        Packet::with_payload(ServerOpcode::GroundItemsUpdate as u8, payload)
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns `true` when `target` is within the view area of `origin`.
fn in_view(origin: Position, target: Position) -> bool {
    let dx = (target.x - origin.x).abs();
    let dy = (target.y - origin.y).abs();
    dx <= VIEW_DISTANCE && dy <= VIEW_DISTANCE
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_in_view() {
        let a = Position::new(100, 100);
        assert!(in_view(a, Position::new(116, 100)));
        assert!(!in_view(a, Position::new(117, 100)));
        assert!(in_view(a, Position::new(100, 84)));
        assert!(!in_view(a, Position::new(100, 83)));
    }

    #[test]
    fn test_known_entity_list() {
        let mut list = KnownEntityList::new(3);
        assert!(list.is_empty());

        assert!(list.add(EntityId(1)));
        assert!(list.add(EntityId(2)));
        assert!(list.add(EntityId(3)));
        assert!(!list.add(EntityId(4))); // at capacity

        assert_eq!(list.len(), 3);
        assert!(list.contains(EntityId(2)));

        assert!(list.remove(EntityId(2)));
        assert!(!list.contains(EntityId(2)));
        assert_eq!(list.len(), 2);

        // Now we can add again
        assert!(list.add(EntityId(4)));
    }

    #[test]
    fn test_bitwriter_basic() {
        let mut bw = BitWriter::new(4);
        bw.write_bits(0b110, 3);
        bw.write_bits(0b01, 2);
        // bits: 1 1 0 0 1 ... padded
        let bytes = bw.finish();
        assert_eq!(bytes.len(), 1);
        // 11001 000 => 0xC8
        assert_eq!(bytes[0], 0b1100_1000);
    }

    #[test]
    fn test_bitwriter_cross_byte() {
        let mut bw = BitWriter::new(4);
        bw.write_bits(0xFF, 8);
        bw.write_bits(0b1010, 4);
        let bytes = bw.finish();
        assert_eq!(bytes.len(), 2);
        assert_eq!(bytes[0], 0xFF);
        assert_eq!(bytes[1], 0b1010_0000);
    }

    #[test]
    fn test_direction_encoding() {
        assert_eq!(direction_to_bits(Direction::North), 0);
        assert_eq!(direction_to_bits(Direction::South), 4);
        assert_eq!(direction_to_bits(Direction::East), 6);
        assert_eq!(direction_to_bits(Direction::West), 2);
    }

    #[test]
    fn test_player_position_update_empty() {
        let self_id = EntityId(1);
        let self_pos = Position::new(100, 200);
        let mut known = KnownEntityList::for_players();

        let self_snap = PlayerSnapshot {
            entity_id: self_id,
            player_index: 0,
            position: self_pos,
            direction: Direction::South,
            moved_this_tick: false,
            appearance_changed: false,
            appearance_data: vec![],
        };

        let (pkt, appearances) = GameStateUpdater::build_player_position_update(
            self_id,
            self_pos,
            &mut known,
            &[self_snap],
        );

        assert_eq!(pkt.opcode, ServerOpcode::PlayerPosition as u8);
        assert!(!pkt.payload.is_empty());
        // No other players => no appearances needed
        assert!(appearances.is_empty());
    }

    #[test]
    fn test_player_position_update_with_nearby() {
        let self_id = EntityId(1);
        let self_pos = Position::new(100, 200);
        let mut known = KnownEntityList::for_players();

        let self_snap = PlayerSnapshot {
            entity_id: self_id,
            player_index: 0,
            position: self_pos,
            direction: Direction::South,
            moved_this_tick: false,
            appearance_changed: false,
            appearance_data: vec![],
        };

        let other_snap = PlayerSnapshot {
            entity_id: EntityId(2),
            player_index: 1,
            position: Position::new(105, 205),
            direction: Direction::North,
            moved_this_tick: false,
            appearance_changed: false,
            appearance_data: vec![1, 2, 3],
        };

        let (pkt, appearances) = GameStateUpdater::build_player_position_update(
            self_id,
            self_pos,
            &mut known,
            &[self_snap, other_snap],
        );

        assert_eq!(pkt.opcode, ServerOpcode::PlayerPosition as u8);
        // Other player should appear -> needs appearance
        assert_eq!(appearances.len(), 1);
        assert_eq!(appearances[0], EntityId(2));
        // Known list should now track the other player
        assert!(known.contains(EntityId(2)));
    }

    #[test]
    fn test_npc_position_update_new_npc() {
        let self_pos = Position::new(100, 200);
        let mut known = KnownEntityList::for_npcs();

        let npc = NpcSnapshot {
            entity_id: EntityId(10),
            npc_index: 0,
            def_id: 21, // Rat
            position: Position::new(105, 200),
            direction: Direction::East,
            moved_this_tick: false,
            removed: false,
        };

        let (pkt, appearances) =
            GameStateUpdater::build_npc_position_update(self_pos, &mut known, &[npc]);

        assert_eq!(pkt.opcode, ServerOpcode::NpcUpdate as u8);
        assert_eq!(appearances.len(), 1);
        assert!(known.contains(EntityId(10)));
    }

    #[test]
    fn test_npc_removal_when_out_of_view() {
        let self_pos = Position::new(100, 200);
        let mut known = KnownEntityList::for_npcs();
        known.add(EntityId(10));

        let npc = NpcSnapshot {
            entity_id: EntityId(10),
            npc_index: 0,
            def_id: 21,
            position: Position::new(200, 200), // far away
            direction: Direction::East,
            moved_this_tick: false,
            removed: false,
        };

        let (pkt, _) =
            GameStateUpdater::build_npc_position_update(self_pos, &mut known, &[npc]);

        assert_eq!(pkt.opcode, ServerOpcode::NpcUpdate as u8);
        // Should have been removed from known list
        assert!(!known.contains(EntityId(10)));
    }

    #[test]
    fn test_objects_update_packet() {
        let self_pos = Position::new(100, 100);
        let objects = vec![
            GameObjectSnapshot {
                def_id: 0,
                position: Position::new(105, 105),
                direction: 0,
                object_type: ObjectType::Scenery,
            },
            GameObjectSnapshot {
                def_id: 200,
                position: Position::new(300, 300), // out of view
                direction: 1,
                object_type: ObjectType::Boundary,
            },
        ];

        let pkt = GameStateUpdater::build_objects_update(self_pos, &objects);
        assert_eq!(pkt.opcode, ServerOpcode::ObjectsUpdate as u8);
        // Only the first object should be included (7 bytes per object)
        assert_eq!(pkt.payload.len(), 7);
    }

    #[test]
    fn test_ground_items_update_packet() {
        let self_pos = Position::new(100, 100);
        let items = vec![GroundItemSnapshot {
            item_id: ItemId(10),
            amount: 5,
            position: Position::new(102, 98),
        }];

        let pkt = GameStateUpdater::build_ground_items_update(self_pos, &items);
        assert_eq!(pkt.opcode, ServerOpcode::GroundItemsUpdate as u8);
        // 6 bytes per item
        assert_eq!(pkt.payload.len(), 6);
    }

    #[test]
    fn test_generate_updates_full() {
        let self_id = EntityId(1);
        let self_pos = Position::new(100, 200);
        let mut known_p = KnownEntityList::for_players();
        let mut known_n = KnownEntityList::for_npcs();

        let self_snap = PlayerSnapshot {
            entity_id: self_id,
            player_index: 0,
            position: self_pos,
            direction: Direction::South,
            moved_this_tick: false,
            appearance_changed: false,
            appearance_data: vec![],
        };

        let packets = GameStateUpdater::generate_updates(
            self_id,
            self_pos,
            &mut known_p,
            &mut known_n,
            &[self_snap],
            &[],
            &[],
            &[],
        );

        // Should have at minimum: player position + NPC position
        assert!(packets.len() >= 2);
        assert_eq!(packets[0].opcode, ServerOpcode::PlayerPosition as u8);
        assert_eq!(packets[1].opcode, ServerOpcode::NpcUpdate as u8);
    }
}
