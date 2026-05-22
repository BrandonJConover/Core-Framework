//! Per-revision wire-byte → `OpcodeIn` dispatch.
//!
//! Each authentic mudclient revision uses a different mapping from
//! the on-the-wire opcode byte to its semantic meaning. This is the
//! Rust analog of `Payload<rev>Parser.opcodes<rev>.put(...)` static
//! initialization blocks in the Java server.
//!
//! Mapped revisions:
//!  * 38  — very early RSC (F2P era, pre-duel/banking)
//!  * 69  — same byte-table as v38; payload parsing differs
//!  * 115 — adds duel, banking, prayer, account-security packets
//!  * 177 — adds NPC_COMMAND, SLEEPWORD, REPORT_ABUSE, new WALK_TO_POINT byte
//!  * 201 — final pre-banking-trap protocol (mudclient201, 2004-12-13)
//!  * 203 — final pre-2009 retro-revival protocol (mudclient203/204)
//!  * 235 — retro-revival post-2009; uses RSC175 Security Settings (conflict bytes)
//!
//! Source of truth:
//! `server-java-modern/src/com/openrsc/server/net/rsc/parsers/impl/Payload<rev>Parser.java`

#![allow(dead_code)]

use super::opcodes::OpcodeIn;

pub mod v115;
pub mod v177;
pub mod v201;
pub mod v203;
pub mod v235;
pub mod v38;
pub mod v69;

/// Authentic RSC client protocol revisions recognised by the server.
///
/// The numeric value is the mudclient revision, but is opaque to the
/// dispatcher; selection happens by enum identity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ProtocolVersion {
    /// mudclient38 (very early RSC).
    V38,
    /// mudclient69 (early-mid RSC; same byte table as V38).
    V69,
    /// mudclient115 (mid-era RSC; adds duel/banking/prayer).
    V115,
    /// mudclient177 (adds NPC_COMMAND, sleepword, account-management opcodes).
    V177,
    /// mudclient201 — last pre-banking-trap protocol.
    V201,
    /// mudclient203 / mudclient204 — final pre-2009 retro-revival protocol.
    V203,
    /// Retro-revival mudclient235 (post-2009; conflict bytes via SecuritySettings).
    V235,
}

impl ProtocolVersion {
    /// Returns the integer revision number used in the login handshake.
    pub fn revision(self) -> u32 {
        match self {
            Self::V38 => 38,
            Self::V69 => 69,
            Self::V115 => 115,
            Self::V177 => 177,
            Self::V201 => 201,
            Self::V203 => 203,
            Self::V235 => 235,
        }
    }

    /// Attempt to construct a [`ProtocolVersion`] from a revision integer.
    pub fn from_revision(n: u32) -> Option<Self> {
        Some(match n {
            38 => Self::V38,
            69 => Self::V69,
            115 => Self::V115,
            177 => Self::V177,
            201 => Self::V201,
            203 | 204 => Self::V203,
            235 => Self::V235,
            _ => return None,
        })
    }
}

/// Translate an on-the-wire opcode byte for the given protocol revision
/// into a semantic [`OpcodeIn`] variant.
///
/// Returns `None` if the byte is not mapped for the given revision.
///
/// For v235 conflict bytes (4, 8, 197, 247) this applies the **static**
/// (logged-in) resolution. Use [`decode_opcode_with_context`] when you
/// have live session state for accurate disambiguation.
#[inline]
pub fn decode_opcode(version: ProtocolVersion, byte: u8) -> Option<OpcodeIn> {
    match version {
        ProtocolVersion::V38 => v38::decode(byte),
        ProtocolVersion::V69 => v69::decode(byte),
        ProtocolVersion::V115 => v115::decode(byte),
        ProtocolVersion::V177 => v177::decode(byte),
        ProtocolVersion::V201 => v201::decode(byte),
        ProtocolVersion::V203 => v203::decode(byte),
        ProtocolVersion::V235 => v235::decode(byte),
    }
}

/// Like [`decode_opcode`] but with runtime context for v235 conflict-byte
/// disambiguation. For all other revisions, context is ignored.
///
/// * `is_logged_in`  — whether the session is in `LoggedIn` state
/// * `packet_len`    — payload byte count (needed for byte 247)
/// * `duel_active`   — whether the player is currently in a duel
#[inline]
pub fn decode_opcode_with_context(
    version: ProtocolVersion,
    byte: u8,
    is_logged_in: bool,
    packet_len: usize,
    duel_active: bool,
) -> Option<OpcodeIn> {
    if version == ProtocolVersion::V235 {
        v235::decode_with_context(byte, is_logged_in, packet_len, duel_active)
    } else {
        decode_opcode(version, byte)
    }
}
