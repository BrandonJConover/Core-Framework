//! Tokio codec for RSC packet framing, with optional ISAAC opcode shuffling.
//!
//! The framing produced by this codec is the *simplified* 3-byte-header form
//! (opcode + u16 BE length) used by inauthentic / OpenRSC web clients — see
//! `RSCProtocolDecoder.java` and `RSCProtocolEncoderMain.java` in the Java
//! server (`authenticClient == -1` branch). The authentic mudclient framing
//! (variable 1/2-byte length, last-byte-of-payload-shuffled-into-header,
//! >= mudclient 183 with ISAAC) is handled at a higher layer; this codec
//! exposes the ISAAC bookkeeping so that layer can call `next_in()` /
//! `next_out()` for opcode shuffling on its own framing.
//!
//! ISAAC integration:
//! - `set_encryption(seed)` initialises *two* `IsaacCipher` instances, one
//!   for incoming packet opcodes, one for outgoing — exactly mirroring
//!   `ISAACContainer(in, out)` in `com.openrsc.server.net.rsc.ISAACContainer`.
//!   Both ciphers are seeded with the same 4-word key (the keys recovered
//!   from the RSA login block), as Java does at
//!   `LoginPacketHandler.java:231-235`.
//! - When encryption is enabled, `encode()` applies
//!   `(opcode + out.next_value()) & 0xFF` to the outgoing opcode byte and
//!   `decode()` applies `(byte - in.next_value()) & 0xFF` to the incoming
//!   opcode byte (matches `ISAACContainer.encodeOpcode` / `decodeOpcode`).

use super::{Packet, HEADER_SIZE, MAX_PACKET_SIZE};
use crate::protocol::isaac::IsaacCipher;
use bytes::{Buf, BytesMut};
use std::io::{self, Error, ErrorKind};
use tokio_util::codec::{Decoder, Encoder};

/// RSC packet codec for tokio-util.
#[derive(Debug)]
pub struct RscCodec {
    /// ISAAC cipher for decoding inbound opcodes (None when encryption is off).
    in_cipher: Option<IsaacCipher>,
    /// ISAAC cipher for encoding outbound opcodes (None when encryption is off).
    out_cipher: Option<IsaacCipher>,
}

impl Default for RscCodec {
    fn default() -> Self {
        Self::new()
    }
}

impl RscCodec {
    /// Create a new codec without encryption.
    pub fn new() -> Self {
        Self {
            in_cipher: None,
            out_cipher: None,
        }
    }

    /// Create a new codec with ISAAC encryption.
    ///
    /// `seed` is the 4-word ISAAC key recovered from the RSA login block
    /// (see `LoginPacketHandler.processLogin`, `loginInfo.keys`). Both the
    /// incoming and outgoing ciphers are initialised with the same key —
    /// matching Java's `ISAACContainer(in, out)` setup.
    pub fn with_encryption(seed: [u32; 4]) -> Self {
        Self {
            in_cipher: Some(IsaacCipher::new(seed)),
            out_cipher: Some(IsaacCipher::new(seed)),
        }
    }

    /// Enable encryption with the given key.
    pub fn set_encryption(&mut self, seed: [u32; 4]) {
        self.in_cipher = Some(IsaacCipher::new(seed));
        self.out_cipher = Some(IsaacCipher::new(seed));
    }

    /// Disable encryption.
    pub fn disable_encryption(&mut self) {
        self.in_cipher = None;
        self.out_cipher = None;
    }

    /// Whether encryption is currently enabled on this codec.
    pub fn is_encrypted(&self) -> bool {
        self.in_cipher.is_some()
    }

    /// Pull the next ISAAC stream word from the *incoming* cipher and apply
    /// it to a raw encoded opcode byte. Returns the decoded opcode.
    ///
    /// Mirrors Java `ISAACContainer.decodeOpcode(int)`:
    ///   `return (opcode - inCipher.getNextValue()) & 0xFF;`
    ///
    /// Exposed for higher-level framers that handle the authentic mudclient
    /// length encoding themselves; `decode()` calls this internally.
    pub fn decode_opcode(&mut self, encoded: u8) -> u8 {
        match self.in_cipher.as_mut() {
            Some(c) => ((encoded as i32 - c.next_value() as i32) & 0xFF) as u8,
            None => encoded,
        }
    }

    /// Pull the next ISAAC stream word from the *outgoing* cipher and apply
    /// it to a raw opcode. Returns the encoded opcode byte.
    ///
    /// Mirrors Java `ISAACContainer.encodeOpcode(int)`:
    ///   `return (opcode + outCipher.getNextValue()) & 0xFF;`
    pub fn encode_opcode(&mut self, opcode: u8) -> u8 {
        match self.out_cipher.as_mut() {
            Some(c) => opcode.wrapping_add((c.next_value() & 0xFF) as u8),
            None => opcode,
        }
    }
}

impl Decoder for RscCodec {
    type Item = Packet;
    type Error = io::Error;

    fn decode(&mut self, src: &mut BytesMut) -> Result<Option<Self::Item>, Self::Error> {
        // Need at least the header
        if src.len() < HEADER_SIZE {
            return Ok(None);
        }

        // Peek opcode and length without consuming.
        let raw_opcode = src[0];
        let length = u16::from_be_bytes([src[1], src[2]]) as usize;

        // Validate length
        if length > MAX_PACKET_SIZE {
            return Err(Error::new(
                ErrorKind::InvalidData,
                format!("Packet too large: {} bytes", length),
            ));
        }

        // Check if we have the full packet
        let total_len = HEADER_SIZE + length;
        if src.len() < total_len {
            // Reserve space for the full packet
            src.reserve(total_len - src.len());
            return Ok(None);
        }

        // Decode the opcode through ISAAC if encryption is on. Note: we only
        // advance the ISAAC stream after we've confirmed the full packet is
        // available, so partial reads don't desync the cipher.
        let opcode = self.decode_opcode(raw_opcode);

        // Extract the packet
        src.advance(HEADER_SIZE);
        let payload = src.split_to(length).freeze();

        Ok(Some(Packet { opcode, payload }))
    }
}

impl Encoder<Packet> for RscCodec {
    type Error = io::Error;

    fn encode(&mut self, item: Packet, dst: &mut BytesMut) -> Result<(), Self::Error> {
        let payload_len = item.payload.len();

        if payload_len > MAX_PACKET_SIZE {
            return Err(Error::new(
                ErrorKind::InvalidData,
                format!("Packet payload too large: {} bytes", payload_len),
            ));
        }

        // Apply ISAAC to the outgoing opcode if encryption is enabled.
        let opcode_byte = self.encode_opcode(item.opcode);

        // Reserve space
        dst.reserve(HEADER_SIZE + payload_len);

        // Write header
        dst.extend_from_slice(&[opcode_byte]);
        dst.extend_from_slice(&(payload_len as u16).to_be_bytes());

        // Write payload
        dst.extend_from_slice(&item.payload);

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_codec_roundtrip_plain() {
        let mut codec = RscCodec::new();
        let mut buf = BytesMut::new();

        let packet = Packet::new(42, vec![1, 2, 3, 4, 5]);
        codec.encode(packet.clone(), &mut buf).unwrap();

        let decoded = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(decoded.opcode, 42);
        assert_eq!(decoded.payload.as_ref(), &[1, 2, 3, 4, 5]);
    }

    /// With ISAAC enabled, encoding+decoding through a *paired* codec setup
    /// (server out -> client in, client out -> server in) must recover the
    /// original opcode. We simulate by using two codecs seeded identically:
    /// `server.encode_opcode` produces what the wire sees, then we feed it
    /// to `client.decode_opcode` and expect the original.
    #[test]
    fn test_isaac_opcode_shuffle_roundtrip() {
        let seed = [0x1234_5678, 0x9abc_def0, 0xfedc_ba98, 0x7654_3210];

        // Server's outgoing cipher pairs with client's incoming cipher
        // (both seeded the same — mirrors Java's ISAACContainer where in & out
        // are both fed the same login keys).
        let mut server = RscCodec::with_encryption(seed);
        let mut client = RscCodec::with_encryption(seed);

        for opcode in 0u8..=255 {
            let on_wire = server.encode_opcode(opcode);
            let recovered = client.decode_opcode(on_wire);
            assert_eq!(recovered, opcode, "ISAAC roundtrip failed at opcode {opcode}");
        }
    }

    /// Full encode/decode roundtrip with ISAAC: server encodes, "client"
    /// (a separately-seeded codec) decodes, and the opcode + payload are
    /// preserved.
    #[test]
    fn test_codec_full_roundtrip_with_encryption() {
        let seed = [11, 22, 33, 44];
        let mut server = RscCodec::with_encryption(seed);
        let mut client = RscCodec::with_encryption(seed);

        let mut buf = BytesMut::new();
        let packet = Packet::new(99, vec![0xAA, 0xBB, 0xCC]);
        server.encode(packet, &mut buf).unwrap();

        // The opcode byte on the wire should NOT be 99 (extremely unlikely).
        assert_ne!(buf[0], 99, "ISAAC didn't shuffle the opcode (or got unlucky)");

        let decoded = client.decode(&mut buf).unwrap().unwrap();
        assert_eq!(decoded.opcode, 99);
        assert_eq!(decoded.payload.as_ref(), &[0xAA, 0xBB, 0xCC]);
    }

    /// Disabling encryption mid-stream should make subsequent opcodes pass
    /// through unmodified.
    #[test]
    fn test_disable_encryption_makes_opcodes_passthrough() {
        let mut codec = RscCodec::with_encryption([1, 2, 3, 4]);
        codec.disable_encryption();
        assert!(!codec.is_encrypted());
        assert_eq!(codec.encode_opcode(77), 77);
        assert_eq!(codec.decode_opcode(77), 77);
    }
}
