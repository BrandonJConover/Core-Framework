//! mudclient69 wire-byte → `OpcodeIn` table.
//!
//! Pure data port of the `toOpcodeEnum` switch block in
//! `server-java-modern/src/com/openrsc/server/net/rsc/parsers/impl/Payload69Parser.java`.
//!
//! mudclient69 shares the same opcode byte assignments as v38; the only
//! distinction in the Java server is in the payload parser (`parse()`),
//! not the byte-to-opcode mapping. We mirror this exactly.

#![allow(dead_code)]

use super::super::opcodes::OpcodeIn;

/// Returns the semantic opcode for a mudclient69 wire byte,
/// or `None` if the byte is unknown for this revision.
#[inline]
pub fn decode(byte: u8) -> Option<OpcodeIn> {
    // v69 has the same byte → opcode mapping as v38.
    super::v38::decode(byte)
}
