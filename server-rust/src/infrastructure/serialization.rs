use anyhow::Result;
use bytes::{Buf, BufMut, Bytes, BytesMut};
use std::io::Cursor;

/// Serialization format.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SerializationFormat {
    /// Original RSC binary format - legacy client compatibility.
    RscBinary,
    /// MessagePack - compact cross-platform binary format.
    MessagePack,
    /// JSON - human-readable format.
    Json,
    /// Bincode - fast Rust-native binary format.
    Bincode,
}

/// Trait for serializers.
/// Uses `serde_json::Value` for object-safe serialization/deserialization.
pub trait Serializer: Send + Sync {
    fn format(&self) -> SerializationFormat;
    fn serialize_value(&self, value: &serde_json::Value) -> Result<Vec<u8>>;
    fn deserialize_value(&self, data: &[u8]) -> Result<serde_json::Value>;
}

/// Factory for creating serializers.
pub struct SerializerFactory {
    default_format: SerializationFormat,
}

impl SerializerFactory {
    pub fn new() -> Self {
        Self {
            default_format: SerializationFormat::MessagePack,
        }
    }

    pub fn get(&self, format: SerializationFormat) -> Box<dyn Serializer> {
        match format {
            SerializationFormat::MessagePack => Box::new(MessagePackSerializer),
            SerializationFormat::Json => Box::new(JsonSerializer),
            SerializationFormat::Bincode => Box::new(BincodeSerializer),
            SerializationFormat::RscBinary => Box::new(RscBinarySerializer),
        }
    }

    pub fn default(&self) -> Box<dyn Serializer> {
        self.get(self.default_format)
    }

    pub fn set_default(&mut self, format: SerializationFormat) {
        self.default_format = format;
    }
}

impl Default for SerializerFactory {
    fn default() -> Self {
        Self::new()
    }
}

/// MessagePack serializer.
pub struct MessagePackSerializer;

impl Serializer for MessagePackSerializer {
    fn format(&self) -> SerializationFormat {
        SerializationFormat::MessagePack
    }

    fn serialize_value(&self, value: &serde_json::Value) -> Result<Vec<u8>> {
        Ok(rmp_serde::to_vec(value)?)
    }

    fn deserialize_value(&self, data: &[u8]) -> Result<serde_json::Value> {
        Ok(rmp_serde::from_slice(data)?)
    }
}

/// JSON serializer.
pub struct JsonSerializer;

impl Serializer for JsonSerializer {
    fn format(&self) -> SerializationFormat {
        SerializationFormat::Json
    }

    fn serialize_value(&self, value: &serde_json::Value) -> Result<Vec<u8>> {
        Ok(serde_json::to_vec(value)?)
    }

    fn deserialize_value(&self, data: &[u8]) -> Result<serde_json::Value> {
        Ok(serde_json::from_slice(data)?)
    }
}

/// Bincode serializer (fast Rust-native).
pub struct BincodeSerializer;

impl Serializer for BincodeSerializer {
    fn format(&self) -> SerializationFormat {
        SerializationFormat::Bincode
    }

    fn serialize_value(&self, value: &serde_json::Value) -> Result<Vec<u8>> {
        Ok(bincode::serialize(value)?)
    }

    fn deserialize_value(&self, data: &[u8]) -> Result<serde_json::Value> {
        Ok(bincode::deserialize(data)?)
    }
}

/// RSC binary serializer for legacy client compatibility.
pub struct RscBinarySerializer;

impl Serializer for RscBinarySerializer {
    fn format(&self) -> SerializationFormat {
        SerializationFormat::RscBinary
    }

    fn serialize_value(&self, _value: &serde_json::Value) -> Result<Vec<u8>> {
        // RSC binary uses a custom format, not generic serialization
        Err(anyhow::anyhow!("Use Packet struct for RSC binary serialization"))
    }

    fn deserialize_value(&self, _data: &[u8]) -> Result<serde_json::Value> {
        Err(anyhow::anyhow!("Use Packet struct for RSC binary deserialization"))
    }
}

/// Game packet for network transmission.
#[derive(Debug, Clone)]
pub struct Packet {
    pub opcode: u8,
    pub payload: Bytes,
}

impl Packet {
    pub fn new(opcode: u8, payload: impl Into<Bytes>) -> Self {
        Self {
            opcode,
            payload: payload.into(),
        }
    }

    /// Encode to RSC binary format: [length:2 BE][opcode:1][payload:variable]
    pub fn encode_rsc(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(3 + self.payload.len());
        let length = (1 + self.payload.len()) as u16;
        buf.put_u16(length);
        buf.put_u8(self.opcode);
        buf.put_slice(&self.payload);
        buf.freeze()
    }

    /// Decode from RSC binary format.
    pub fn decode_rsc(data: &[u8]) -> Result<Self> {
        if data.len() < 3 {
            return Err(anyhow::anyhow!("Packet too short"));
        }

        let mut cursor = Cursor::new(data);
        let length = cursor.get_u16() as usize;

        if data.len() < 2 + length {
            return Err(anyhow::anyhow!("Incomplete packet"));
        }

        let opcode = cursor.get_u8();
        let payload = Bytes::copy_from_slice(&data[3..2 + length]);

        Ok(Self { opcode, payload })
    }

    /// Encode to MessagePack format with protocol header.
    pub fn encode_msgpack(&self) -> Result<Bytes> {
        const MAGIC: u8 = 0xC1;
        const VERSION: u8 = 1;

        let wrapper = PacketWrapper {
            opcode: self.opcode,
            payload: self.payload.to_vec(),
        };

        let msgpack_data = rmp_serde::to_vec(&wrapper)?;

        let mut buf = BytesMut::with_capacity(6 + msgpack_data.len());
        buf.put_u8(MAGIC);
        buf.put_u8(VERSION);
        buf.put_u32(msgpack_data.len() as u32);
        buf.put_slice(&msgpack_data);

        Ok(buf.freeze())
    }

    /// Decode from MessagePack format.
    pub fn decode_msgpack(data: &[u8]) -> Result<Self> {
        if data.len() < 6 {
            return Err(anyhow::anyhow!("Packet too short"));
        }

        if data[0] != 0xC1 {
            return Err(anyhow::anyhow!("Invalid magic byte"));
        }

        let mut cursor = Cursor::new(&data[2..]);
        let length = cursor.get_u32() as usize;

        if data.len() < 6 + length {
            return Err(anyhow::anyhow!("Incomplete packet"));
        }

        let wrapper: PacketWrapper = rmp_serde::from_slice(&data[6..6 + length])?;

        Ok(Self {
            opcode: wrapper.opcode,
            payload: Bytes::from(wrapper.payload),
        })
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
struct PacketWrapper {
    opcode: u8,
    payload: Vec<u8>,
}

/// Protocol adapter for dual-protocol support.
pub struct ProtocolAdapter;

impl ProtocolAdapter {
    pub const MSGPACK_MAGIC: u8 = 0xC1;

    /// Detect protocol from initial bytes.
    pub fn detect_protocol(data: &[u8]) -> SerializationFormat {
        if data.is_empty() {
            return SerializationFormat::RscBinary;
        }

        if data[0] == Self::MSGPACK_MAGIC {
            SerializationFormat::MessagePack
        } else {
            SerializationFormat::RscBinary
        }
    }

    /// Encode packet using the specified format.
    pub fn encode(packet: &Packet, format: SerializationFormat) -> Result<Bytes> {
        match format {
            SerializationFormat::MessagePack => packet.encode_msgpack(),
            SerializationFormat::RscBinary => Ok(packet.encode_rsc()),
            _ => Err(anyhow::anyhow!("Unsupported protocol format")),
        }
    }

    /// Decode packet using the specified format.
    pub fn decode(data: &[u8], format: SerializationFormat) -> Result<Packet> {
        match format {
            SerializationFormat::MessagePack => Packet::decode_msgpack(data),
            SerializationFormat::RscBinary => Packet::decode_rsc(data),
            _ => Err(anyhow::anyhow!("Unsupported protocol format")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rsc_packet_roundtrip() {
        let packet = Packet::new(42, vec![1, 2, 3, 4, 5]);
        let encoded = packet.encode_rsc();
        let decoded = Packet::decode_rsc(&encoded).unwrap();

        assert_eq!(decoded.opcode, 42);
        assert_eq!(decoded.payload.as_ref(), &[1, 2, 3, 4, 5]);
    }

    #[test]
    fn test_msgpack_packet_roundtrip() {
        let packet = Packet::new(42, vec![1, 2, 3, 4, 5]);
        let encoded = packet.encode_msgpack().unwrap();
        let decoded = Packet::decode_msgpack(&encoded).unwrap();

        assert_eq!(decoded.opcode, 42);
        assert_eq!(decoded.payload.as_ref(), &[1, 2, 3, 4, 5]);
    }

    #[test]
    fn test_protocol_detection() {
        assert_eq!(ProtocolAdapter::detect_protocol(&[0xC1, 0x01]), SerializationFormat::MessagePack);
        assert_eq!(ProtocolAdapter::detect_protocol(&[0x00, 0x05]), SerializationFormat::RscBinary);
        assert_eq!(ProtocolAdapter::detect_protocol(&[]), SerializationFormat::RscBinary);
    }
}
