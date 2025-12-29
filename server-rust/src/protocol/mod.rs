//! Protocol module for RSC packet handling.
//! Defines packet structures, opcodes, and encoding/decoding.

pub mod codec;
pub mod opcodes;
pub mod packets;

use bytes::{Buf, BufMut, Bytes, BytesMut};
use std::io::{self, Error, ErrorKind};

/// Maximum packet size (64KB).
pub const MAX_PACKET_SIZE: usize = 65535;

/// Packet header size (opcode + length).
pub const HEADER_SIZE: usize = 3;

/// Represents a raw packet with opcode and payload.
#[derive(Debug, Clone)]
pub struct Packet {
    pub opcode: u8,
    pub payload: Bytes,
}

impl Packet {
    /// Create a new packet with the given opcode and payload.
    pub fn new(opcode: u8, payload: impl Into<Bytes>) -> Self {
        Self {
            opcode,
            payload: payload.into(),
        }
    }

    /// Create an empty packet with just an opcode.
    pub fn empty(opcode: u8) -> Self {
        Self {
            opcode,
            payload: Bytes::new(),
        }
    }

    /// Get the total length of the packet (header + payload).
    pub fn len(&self) -> usize {
        HEADER_SIZE + self.payload.len()
    }

    /// Check if the packet payload is empty.
    pub fn is_empty(&self) -> bool {
        self.payload.is_empty()
    }

    /// Encode the packet to bytes.
    pub fn encode(&self) -> BytesMut {
        let mut buf = BytesMut::with_capacity(self.len());
        buf.put_u8(self.opcode);
        buf.put_u16(self.payload.len() as u16);
        buf.put_slice(&self.payload);
        buf
    }

    /// Decode a packet from bytes.
    pub fn decode(buf: &mut BytesMut) -> io::Result<Option<Self>> {
        if buf.len() < HEADER_SIZE {
            return Ok(None);
        }

        let opcode = buf[0];
        let length = u16::from_be_bytes([buf[1], buf[2]]) as usize;

        if length > MAX_PACKET_SIZE {
            return Err(Error::new(
                ErrorKind::InvalidData,
                format!("Packet too large: {} bytes", length),
            ));
        }

        let total_len = HEADER_SIZE + length;
        if buf.len() < total_len {
            return Ok(None);
        }

        buf.advance(HEADER_SIZE);
        let payload = buf.split_to(length).freeze();

        Ok(Some(Self { opcode, payload }))
    }
}

/// Packet builder for constructing outgoing packets.
#[derive(Debug)]
pub struct PacketBuilder {
    opcode: u8,
    buffer: BytesMut,
}

impl PacketBuilder {
    /// Create a new packet builder with the given opcode.
    pub fn new(opcode: u8) -> Self {
        Self {
            opcode,
            buffer: BytesMut::with_capacity(256),
        }
    }

    /// Write a single byte.
    pub fn write_byte(mut self, value: u8) -> Self {
        self.buffer.put_u8(value);
        self
    }

    /// Write a signed byte.
    pub fn write_sbyte(mut self, value: i8) -> Self {
        self.buffer.put_i8(value);
        self
    }

    /// Write a short (2 bytes, big-endian).
    pub fn write_short(mut self, value: u16) -> Self {
        self.buffer.put_u16(value);
        self
    }

    /// Write a signed short (2 bytes, big-endian).
    pub fn write_sshort(mut self, value: i16) -> Self {
        self.buffer.put_i16(value);
        self
    }

    /// Write an int (4 bytes, big-endian).
    pub fn write_int(mut self, value: u32) -> Self {
        self.buffer.put_u32(value);
        self
    }

    /// Write a signed int (4 bytes, big-endian).
    pub fn write_sint(mut self, value: i32) -> Self {
        self.buffer.put_i32(value);
        self
    }

    /// Write a long (8 bytes, big-endian).
    pub fn write_long(mut self, value: u64) -> Self {
        self.buffer.put_u64(value);
        self
    }

    /// Write raw bytes.
    pub fn write_bytes(mut self, bytes: &[u8]) -> Self {
        self.buffer.put_slice(bytes);
        self
    }

    /// Write an RSC-style string (null-terminated).
    pub fn write_string(mut self, s: &str) -> Self {
        self.buffer.put_slice(s.as_bytes());
        self.buffer.put_u8(0);
        self
    }

    /// Build the final packet.
    pub fn build(self) -> Packet {
        Packet::new(self.opcode, self.buffer.freeze())
    }
}

/// Packet reader for parsing incoming packets.
#[derive(Debug)]
pub struct PacketReader {
    buffer: Bytes,
    position: usize,
}

impl PacketReader {
    /// Create a new packet reader from a packet.
    pub fn new(packet: &Packet) -> Self {
        Self {
            buffer: packet.payload.clone(),
            position: 0,
        }
    }

    /// Get remaining bytes to read.
    pub fn remaining(&self) -> usize {
        self.buffer.len() - self.position
    }

    /// Check if there are more bytes to read.
    pub fn has_remaining(&self) -> bool {
        self.remaining() > 0
    }

    /// Read a single byte.
    pub fn read_byte(&mut self) -> io::Result<u8> {
        if self.remaining() < 1 {
            return Err(Error::new(ErrorKind::UnexpectedEof, "Not enough bytes"));
        }
        let value = self.buffer[self.position];
        self.position += 1;
        Ok(value)
    }

    /// Read a signed byte.
    pub fn read_sbyte(&mut self) -> io::Result<i8> {
        self.read_byte().map(|b| b as i8)
    }

    /// Read a short (2 bytes, big-endian).
    pub fn read_short(&mut self) -> io::Result<u16> {
        if self.remaining() < 2 {
            return Err(Error::new(ErrorKind::UnexpectedEof, "Not enough bytes"));
        }
        let value = u16::from_be_bytes([
            self.buffer[self.position],
            self.buffer[self.position + 1],
        ]);
        self.position += 2;
        Ok(value)
    }

    /// Read a signed short (2 bytes, big-endian).
    pub fn read_sshort(&mut self) -> io::Result<i16> {
        self.read_short().map(|s| s as i16)
    }

    /// Read an int (4 bytes, big-endian).
    pub fn read_int(&mut self) -> io::Result<u32> {
        if self.remaining() < 4 {
            return Err(Error::new(ErrorKind::UnexpectedEof, "Not enough bytes"));
        }
        let value = u32::from_be_bytes([
            self.buffer[self.position],
            self.buffer[self.position + 1],
            self.buffer[self.position + 2],
            self.buffer[self.position + 3],
        ]);
        self.position += 4;
        Ok(value)
    }

    /// Read a signed int (4 bytes, big-endian).
    pub fn read_sint(&mut self) -> io::Result<i32> {
        self.read_int().map(|i| i as i32)
    }

    /// Read a long (8 bytes, big-endian).
    pub fn read_long(&mut self) -> io::Result<u64> {
        if self.remaining() < 8 {
            return Err(Error::new(ErrorKind::UnexpectedEof, "Not enough bytes"));
        }
        let value = u64::from_be_bytes([
            self.buffer[self.position],
            self.buffer[self.position + 1],
            self.buffer[self.position + 2],
            self.buffer[self.position + 3],
            self.buffer[self.position + 4],
            self.buffer[self.position + 5],
            self.buffer[self.position + 6],
            self.buffer[self.position + 7],
        ]);
        self.position += 8;
        Ok(value)
    }

    /// Read an RSC-style string (null-terminated).
    pub fn read_string(&mut self) -> io::Result<String> {
        let start = self.position;
        while self.position < self.buffer.len() {
            if self.buffer[self.position] == 0 {
                let s = String::from_utf8_lossy(&self.buffer[start..self.position]).to_string();
                self.position += 1; // Skip null terminator
                return Ok(s);
            }
            self.position += 1;
        }
        Err(Error::new(ErrorKind::UnexpectedEof, "String not terminated"))
    }

    /// Read n bytes as a slice.
    pub fn read_bytes(&mut self, n: usize) -> io::Result<Bytes> {
        if self.remaining() < n {
            return Err(Error::new(ErrorKind::UnexpectedEof, "Not enough bytes"));
        }
        let bytes = self.buffer.slice(self.position..self.position + n);
        self.position += n;
        Ok(bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_packet_encode_decode() {
        let packet = PacketBuilder::new(1)
            .write_byte(42)
            .write_short(1000)
            .write_string("test")
            .build();

        let mut encoded = packet.encode();
        let decoded = Packet::decode(&mut encoded).unwrap().unwrap();

        assert_eq!(decoded.opcode, 1);

        let mut reader = PacketReader::new(&decoded);
        assert_eq!(reader.read_byte().unwrap(), 42);
        assert_eq!(reader.read_short().unwrap(), 1000);
        assert_eq!(reader.read_string().unwrap(), "test");
    }
}
