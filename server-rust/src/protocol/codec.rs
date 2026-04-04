//! Tokio codec for RSC packet framing.

use super::{Packet, HEADER_SIZE, MAX_PACKET_SIZE};
use bytes::{Buf, BytesMut};
use std::io::{self, Error, ErrorKind};
use tokio_util::codec::{Decoder, Encoder};

/// RSC packet codec for tokio-util.
#[derive(Debug, Default)]
pub struct RscCodec {
    /// Whether encryption is enabled.
    encrypted: bool,
    /// ISAAC cipher for encryption (if enabled).
    cipher_key: Option<[u32; 4]>,
}

impl RscCodec {
    /// Create a new codec without encryption.
    pub fn new() -> Self {
        Self {
            encrypted: false,
            cipher_key: None,
        }
    }

    /// Create a new codec with ISAAC encryption.
    pub fn with_encryption(key: [u32; 4]) -> Self {
        Self {
            encrypted: true,
            cipher_key: Some(key),
        }
    }

    /// Enable encryption with the given key.
    pub fn set_encryption(&mut self, key: [u32; 4]) {
        self.encrypted = true;
        self.cipher_key = Some(key);
    }

    /// Disable encryption.
    pub fn disable_encryption(&mut self) {
        self.encrypted = false;
        self.cipher_key = None;
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

        // Read opcode and length
        let opcode = src[0];
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

        // Reserve space
        dst.reserve(HEADER_SIZE + payload_len);

        // Write header
        dst.extend_from_slice(&[item.opcode]);
        dst.extend_from_slice(&(payload_len as u16).to_be_bytes());

        // Write payload
        dst.extend_from_slice(&item.payload);

        Ok(())
    }
}

/// ISAAC cipher for RSC packet encryption.
/// This is a simplified implementation for demonstration.
#[derive(Debug, Clone)]
pub struct IsaacCipher {
    mm: [u32; 256],
    randrsl: [u32; 256],
    aa: u32,
    bb: u32,
    cc: u32,
    randcnt: usize,
}

impl IsaacCipher {
    /// Create a new ISAAC cipher with the given seed.
    pub fn new(seed: &[u32]) -> Self {
        let mut cipher = Self {
            mm: [0; 256],
            randrsl: [0; 256],
            aa: 0,
            bb: 0,
            cc: 0,
            randcnt: 0,
        };

        // Copy seed to randrsl
        for (i, &s) in seed.iter().enumerate() {
            if i >= 256 {
                break;
            }
            cipher.randrsl[i] = s;
        }

        cipher.randinit(true);
        cipher
    }

    /// Get the next random value.
    pub fn next(&mut self) -> u32 {
        if self.randcnt == 0 {
            self.isaac();
            self.randcnt = 256;
        }
        self.randcnt -= 1;
        self.randrsl[self.randcnt]
    }

    fn randinit(&mut self, flag: bool) {
        let mut a = 0x9e3779b9u32;
        let mut b = a;
        let mut c = a;
        let mut d = a;
        let mut e = a;
        let mut f = a;
        let mut g = a;
        let mut h = a;

        // Mix
        for _ in 0..4 {
            a ^= b << 11; d = d.wrapping_add(a); b = b.wrapping_add(c);
            b ^= c >> 2;  e = e.wrapping_add(b); c = c.wrapping_add(d);
            c ^= d << 8;  f = f.wrapping_add(c); d = d.wrapping_add(e);
            d ^= e >> 16; g = g.wrapping_add(d); e = e.wrapping_add(f);
            e ^= f << 10; h = h.wrapping_add(e); f = f.wrapping_add(g);
            f ^= g >> 4;  a = a.wrapping_add(f); g = g.wrapping_add(h);
            g ^= h << 8;  b = b.wrapping_add(g); h = h.wrapping_add(a);
            h ^= a >> 9;  c = c.wrapping_add(h); a = a.wrapping_add(b);
        }

        for i in (0..256).step_by(8) {
            if flag {
                a = a.wrapping_add(self.randrsl[i]);
                b = b.wrapping_add(self.randrsl[i + 1]);
                c = c.wrapping_add(self.randrsl[i + 2]);
                d = d.wrapping_add(self.randrsl[i + 3]);
                e = e.wrapping_add(self.randrsl[i + 4]);
                f = f.wrapping_add(self.randrsl[i + 5]);
                g = g.wrapping_add(self.randrsl[i + 6]);
                h = h.wrapping_add(self.randrsl[i + 7]);
            }

            a ^= b << 11; d = d.wrapping_add(a); b = b.wrapping_add(c);
            b ^= c >> 2;  e = e.wrapping_add(b); c = c.wrapping_add(d);
            c ^= d << 8;  f = f.wrapping_add(c); d = d.wrapping_add(e);
            d ^= e >> 16; g = g.wrapping_add(d); e = e.wrapping_add(f);
            e ^= f << 10; h = h.wrapping_add(e); f = f.wrapping_add(g);
            f ^= g >> 4;  a = a.wrapping_add(f); g = g.wrapping_add(h);
            g ^= h << 8;  b = b.wrapping_add(g); h = h.wrapping_add(a);
            h ^= a >> 9;  c = c.wrapping_add(h); a = a.wrapping_add(b);

            self.mm[i] = a;
            self.mm[i + 1] = b;
            self.mm[i + 2] = c;
            self.mm[i + 3] = d;
            self.mm[i + 4] = e;
            self.mm[i + 5] = f;
            self.mm[i + 6] = g;
            self.mm[i + 7] = h;
        }

        if flag {
            for i in (0..256).step_by(8) {
                a = a.wrapping_add(self.mm[i]);
                b = b.wrapping_add(self.mm[i + 1]);
                c = c.wrapping_add(self.mm[i + 2]);
                d = d.wrapping_add(self.mm[i + 3]);
                e = e.wrapping_add(self.mm[i + 4]);
                f = f.wrapping_add(self.mm[i + 5]);
                g = g.wrapping_add(self.mm[i + 6]);
                h = h.wrapping_add(self.mm[i + 7]);

                a ^= b << 11; d = d.wrapping_add(a); b = b.wrapping_add(c);
                b ^= c >> 2;  e = e.wrapping_add(b); c = c.wrapping_add(d);
                c ^= d << 8;  f = f.wrapping_add(c); d = d.wrapping_add(e);
                d ^= e >> 16; g = g.wrapping_add(d); e = e.wrapping_add(f);
                e ^= f << 10; h = h.wrapping_add(e); f = f.wrapping_add(g);
                f ^= g >> 4;  a = a.wrapping_add(f); g = g.wrapping_add(h);
                g ^= h << 8;  b = b.wrapping_add(g); h = h.wrapping_add(a);
                h ^= a >> 9;  c = c.wrapping_add(h); a = a.wrapping_add(b);

                self.mm[i] = a;
                self.mm[i + 1] = b;
                self.mm[i + 2] = c;
                self.mm[i + 3] = d;
                self.mm[i + 4] = e;
                self.mm[i + 5] = f;
                self.mm[i + 6] = g;
                self.mm[i + 7] = h;
            }
        }

        self.isaac();
        self.randcnt = 256;
    }

    fn isaac(&mut self) {
        self.cc = self.cc.wrapping_add(1);
        self.bb = self.bb.wrapping_add(self.cc);

        for i in 0..256 {
            let x = self.mm[i];
            self.aa = match i % 4 {
                0 => self.aa ^ (self.aa << 13),
                1 => self.aa ^ (self.aa >> 6),
                2 => self.aa ^ (self.aa << 2),
                _ => self.aa ^ (self.aa >> 16),
            };
            self.aa = self.mm[(i + 128) % 256].wrapping_add(self.aa);
            let y = self.mm[((x >> 2) as usize) % 256]
                .wrapping_add(self.aa)
                .wrapping_add(self.bb);
            self.mm[i] = y;
            self.bb = self.mm[((y >> 10) as usize) % 256].wrapping_add(x);
            self.randrsl[i] = self.bb;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_codec_roundtrip() {
        let mut codec = RscCodec::new();
        let mut buf = BytesMut::new();

        let packet = Packet::new(42, vec![1, 2, 3, 4, 5]);
        codec.encode(packet.clone(), &mut buf).unwrap();

        let decoded = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(decoded.opcode, 42);
        assert_eq!(decoded.payload.as_ref(), &[1, 2, 3, 4, 5]);
    }

    #[test]
    fn test_isaac_cipher() {
        let mut cipher = IsaacCipher::new(&[1, 2, 3, 4]);
        let first = cipher.next();
        let second = cipher.next();
        // Values should be different
        assert_ne!(first, second);
    }
}
