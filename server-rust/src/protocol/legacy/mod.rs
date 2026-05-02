//! Per-revision wire-byte → `OpcodeIn` dispatch.
//!
//! Each authentic mudclient revision uses a different mapping from
//! the on-the-wire opcode byte to its semantic meaning. This is the
//! Rust analog of `Payload<rev>Parser.opcodes<rev>.put(...)` static
//! initialization blocks in the Java server.
//!
//! Currently mapped:
//!  * 201 — final pre-banking-trap protocol (mudclient201, 2004-12-13)
//!  * 203 — final pre-2009 retro-revival protocol (mudclient203/204)
//!
//! Older revisions (V38, V69, V115, V235) are declared but not yet
//! populated; they fall through to `None` until ported.
//!
//! Source of truth:
//! `server-java-modern/src/com/openrsc/server/net/rsc/parsers/impl/Payload<rev>Parser.java`

#![allow(dead_code)]

use super::opcodes::OpcodeIn;

pub mod v201;
pub mod v203;

/// Authentic RSC client protocol revisions recognised by the server.
///
/// The numeric value is the mudclient revision, but is opaque to the
/// dispatcher; selection happens by enum identity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ProtocolVersion {
    /// mudclient38 (very early RSC; not yet ported).
    V38,
    /// mudclient69 (early-mid RSC; not yet ported).
    V69,
    /// mudclient115 (mid-era RSC; not yet ported).
    V115,
    /// mudclient201 — last pre-banking-trap protocol.
    V201,
    /// mudclient203 / mudclient204 — final pre-2009 retro-revival protocol.
    V203,
    /// Retro-revival mudclient235 (post-2009; not yet ported).
    V235,
}

/// Translate an on-the-wire opcode byte for the given protocol revision
/// into a semantic [`OpcodeIn`] variant.
///
/// Returns `None` if the byte is not mapped for the given revision, or
/// if the revision's table has not yet been ported from Java.
#[inline]
pub fn decode_opcode(version: ProtocolVersion, byte: u8) -> Option<OpcodeIn> {
    match version {
        ProtocolVersion::V201 => v201::decode(byte),
        ProtocolVersion::V203 => v203::decode(byte),
        // Not yet ported. Falls through deliberately rather than
        // silently mis-routing. See Payload38Parser, Payload69Parser,
        // Payload115Parser, Payload235Parser in the Java tree for the
        // authoritative tables when these are filled in.
        ProtocolVersion::V38
        | ProtocolVersion::V69
        | ProtocolVersion::V115
        | ProtocolVersion::V235 => None,
    }
}
