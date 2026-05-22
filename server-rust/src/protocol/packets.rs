//! Packet structures for RSC protocol.

use super::{Packet, PacketBuilder, PacketReader};
use crate::game::entity::Position;
use std::io::{self, Error, ErrorKind};

/// Login request packet.
#[derive(Debug, Clone)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
    pub client_version: u32,
    pub reconnecting: bool,
}

impl LoginRequest {
    pub fn decode(packet: &Packet) -> io::Result<Self> {
        let payload = packet.payload.as_ref();
        if payload.len() < 5 {
            return Err(Error::new(
                ErrorKind::UnexpectedEof,
                "login payload too short",
            ));
        }

        let mut offset = 0usize;
        let reconnecting = payload[offset] == 1;
        offset += 1;
        let client_version = u32::from_be_bytes([
            payload[offset],
            payload[offset + 1],
            payload[offset + 2],
            payload[offset + 3],
        ]);
        offset += 4;

        let username = read_login_string(payload, &mut offset)?;
        let password = if client_version >= 10010 && client_version != 10069 {
            read_custom_client_password(payload, &mut offset)?
        } else {
            read_login_string(payload, &mut offset)?
        };

        Ok(Self {
            username,
            password,
            client_version,
            reconnecting,
        })
    }
}

fn read_login_string(payload: &[u8], offset: &mut usize) -> io::Result<String> {
    let start = *offset;
    while *offset < payload.len() {
        let byte = payload[*offset];
        if byte == 0 || byte == 10 {
            let value = String::from_utf8_lossy(&payload[start..*offset]).to_string();
            *offset += 1;
            return Ok(value.trim().to_string());
        }
        *offset += 1;
    }
    Err(Error::new(
        ErrorKind::UnexpectedEof,
        "login string not terminated",
    ))
}

fn read_custom_client_password(payload: &[u8], offset: &mut usize) -> io::Result<String> {
    if payload.len() <= *offset {
        return Err(Error::new(
            ErrorKind::UnexpectedEof,
            "missing login encryption version",
        ));
    }

    let encryption_version = payload[*offset];
    *offset += 1;
    match encryption_version {
        0 => read_login_string(payload, offset),
        1 => {
            let password_block = read_rsa_block(payload, offset)?;
            let password_len = password_block.len().min(20);
            let password = String::from_utf8_lossy(&password_block[..password_len])
                .trim()
                .to_string();

            // The Java desktop client follows with an RSA-encrypted client
            // details block. Rust does not use it yet, but consuming it keeps
            // the read offset aligned with the Java LoginPacketHandler path.
            if payload.len() >= *offset + 2 {
                let _ = read_rsa_block(payload, offset)?;
            }

            Ok(password)
        }
        other => Err(Error::new(
            ErrorKind::InvalidData,
            format!("unsupported login encryption version {other}"),
        )),
    }
}

fn read_rsa_block(payload: &[u8], offset: &mut usize) -> io::Result<Vec<u8>> {
    if payload.len() < *offset + 2 {
        return Err(Error::new(
            ErrorKind::UnexpectedEof,
            "missing RSA block length",
        ));
    }
    let len = u16::from_be_bytes([payload[*offset], payload[*offset + 1]]) as usize;
    *offset += 2;
    if len == 0 || payload.len() < *offset + len {
        return Err(Error::new(
            ErrorKind::UnexpectedEof,
            "truncated RSA login block",
        ));
    }

    let ciphertext = &payload[*offset..*offset + len];
    *offset += len;
    let pem = include_str!("../../../server-java-modern/server.pem");
    crate::protocol::rsa::decrypt_rsa(ciphertext, pem)
        .map_err(|e| Error::new(ErrorKind::InvalidData, e.to_string()))
}

/// Login response packet.
#[derive(Debug, Clone, Copy)]
#[repr(u8)]
pub enum LoginResponse {
    Success = 0,
    InvalidCredentials = 1,
    AccountDisabled = 2,
    AlreadyLoggedIn = 3,
    ServerFull = 4,
    LoginServerOffline = 5,
    UpdateRequired = 6,
    IpBanned = 7,
    TooManyAttempts = 8,
}

impl LoginResponse {
    pub fn encode(self) -> Packet {
        PacketBuilder::new(0).write_byte(self as u8).build()
    }
}

/// Walk to point packet.
#[derive(Debug, Clone)]
pub struct WalkToPoint {
    pub start_x: u16,
    pub start_y: u16,
    pub waypoints: Vec<(i8, i8)>,
}

impl WalkToPoint {
    pub fn decode(packet: &Packet) -> io::Result<Self> {
        let mut reader = PacketReader::new(packet);
        let start_x = reader.read_short()?;
        let start_y = reader.read_short()?;

        let mut waypoints = Vec::new();
        while reader.has_remaining() {
            let dx = reader.read_sbyte()?;
            let dy = reader.read_sbyte()?;
            waypoints.push((dx, dy));
        }

        Ok(Self {
            start_x,
            start_y,
            waypoints,
        })
    }
}

/// Chat message packet.
#[derive(Debug, Clone)]
pub struct ChatMessage {
    pub message: String,
}

impl ChatMessage {
    pub fn decode(packet: &Packet) -> io::Result<Self> {
        let mut reader = PacketReader::new(packet);
        let message = reader.read_string()?;
        Ok(Self { message })
    }

    pub fn encode(sender_index: u16, message: &str) -> Packet {
        PacketBuilder::new(30)
            .write_short(sender_index)
            .write_string(message)
            .build()
    }
}

/// Server message packet.
#[derive(Debug, Clone)]
pub struct ServerMessage;

impl ServerMessage {
    pub fn encode(message: &str) -> Packet {
        PacketBuilder::new(32).write_string(message).build()
    }
}

/// Player stats update packet.
#[derive(Debug, Clone)]
pub struct PlayerStats {
    pub current_stats: [u8; 18],
    pub max_stats: [u8; 18],
    pub experience: [u32; 18],
}

impl PlayerStats {
    pub fn encode(&self) -> Packet {
        let mut builder = PacketBuilder::new(21);

        for &stat in &self.current_stats {
            builder = builder.write_byte(stat);
        }
        for &stat in &self.max_stats {
            builder = builder.write_byte(stat);
        }
        for &exp in &self.experience {
            builder = builder.write_int(exp);
        }

        builder.build()
    }
}

/// Inventory update packet.
#[derive(Debug, Clone)]
pub struct InventoryUpdate {
    pub items: Vec<InventoryItem>,
}

#[derive(Debug, Clone)]
pub struct InventoryItem {
    pub id: u16,
    pub amount: u32,
    pub equipped: bool,
}

impl InventoryUpdate {
    pub fn encode(&self) -> Packet {
        let mut builder = PacketBuilder::new(22).write_byte(self.items.len() as u8);

        for item in &self.items {
            let id_with_equip = if item.equipped {
                item.id | 0x8000
            } else {
                item.id
            };
            builder = builder.write_short(id_with_equip);

            // Stackable items have amount
            if item.amount > 1 {
                builder = builder.write_int(item.amount);
            }
        }

        builder.build()
    }
}

/// Position update for players in view.
#[derive(Debug, Clone)]
pub struct PlayerPositionUpdate {
    pub players: Vec<PlayerPosition>,
}

#[derive(Debug, Clone)]
pub struct PlayerPosition {
    pub index: u16,
    pub x: u16,
    pub y: u16,
    pub direction: u8,
}

impl PlayerPositionUpdate {
    pub fn encode(&self) -> Packet {
        let mut builder = PacketBuilder::new(10);

        for player in &self.players {
            builder = builder
                .write_short(player.index)
                .write_short(player.x)
                .write_short(player.y)
                .write_byte(player.direction);
        }

        builder.build()
    }
}

/// Damage update packet for combat.
#[derive(Debug, Clone)]
pub struct DamageUpdate {
    pub target_index: u16,
    pub damage: u8,
    pub current_hp: u8,
    pub max_hp: u8,
}

impl DamageUpdate {
    pub fn encode(&self) -> Packet {
        PacketBuilder::new(40)
            .write_short(self.target_index)
            .write_byte(self.damage)
            .write_byte(self.current_hp)
            .write_byte(self.max_hp)
            .build()
    }
}

/// Teleport packet.
#[derive(Debug, Clone)]
pub struct TeleportPacket {
    pub x: u16,
    pub y: u16,
    pub in_building: bool,
}

impl TeleportPacket {
    pub fn encode(&self) -> Packet {
        PacketBuilder::new(71)
            .write_short(self.x)
            .write_short(self.y)
            .write_byte(if self.in_building { 1 } else { 0 })
            .build()
    }
}

/// Experience update packet.
#[derive(Debug, Clone)]
pub struct ExperienceUpdate {
    pub skill_id: u8,
    pub experience: u32,
}

impl ExperienceUpdate {
    pub fn encode(&self) -> Packet {
        PacketBuilder::new(91)
            .write_byte(self.skill_id)
            .write_int(self.experience)
            .build()
    }
}

/// System update countdown packet.
#[derive(Debug, Clone)]
pub struct SystemUpdate {
    pub seconds_remaining: u16,
}

impl SystemUpdate {
    pub fn encode(&self) -> Packet {
        PacketBuilder::new(101)
            .write_short(self.seconds_remaining)
            .build()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use bytes::{BufMut, BytesMut};
    use rsa::BigUint;

    #[test]
    fn decodes_legacy_null_terminated_login() {
        let mut payload = BytesMut::new();
        payload.put_u8(0);
        payload.put_u32(177);
        payload.put_slice(b"alice");
        payload.put_u8(0);
        payload.put_slice(b"secret");
        payload.put_u8(0);

        let request = LoginRequest::decode(&Packet::new(0, payload.freeze())).unwrap();

        assert!(!request.reconnecting);
        assert_eq!(request.client_version, 177);
        assert_eq!(request.username, "alice");
        assert_eq!(request.password, "secret");
    }

    #[test]
    fn decodes_java_custom_rsa_password_login() {
        let mut payload = BytesMut::new();
        payload.put_u8(1);
        payload.put_u32(10010);
        payload.put_slice(b"alice");
        payload.put_u8(10);
        payload.put_u8(1);

        write_client_rsa_block(&mut payload, padded_login_password("secret").as_bytes());
        write_client_rsa_block(&mut payload, b"workspace/client");
        payload.put_u64(0x0102_0304_0506_0708);

        let request = LoginRequest::decode(&Packet::new(0, payload.freeze())).unwrap();

        assert!(request.reconnecting);
        assert_eq!(request.client_version, 10010);
        assert_eq!(request.username, "alice");
        assert_eq!(request.password, "secret");
    }

    fn padded_login_password(password: &str) -> String {
        let mut padded = String::with_capacity(20);
        for index in 0..20 {
            let Some(c) = password.chars().nth(index) else {
                padded.push(' ');
                continue;
            };
            padded.push(if c.is_ascii_alphanumeric() { c } else { '_' });
        }
        padded
    }

    fn write_client_rsa_block(payload: &mut BytesMut, plaintext: &[u8]) {
        let pem = include_str!("../../../server-java-modern/server.pem");
        let key = crate::protocol::rsa::RsaKey::from_pkcs8_pem(pem).unwrap();
        let encrypted = encrypt_like_java_client(plaintext, key.modulus());
        payload.put_u16(encrypted.len() as u16);
        payload.put_slice(&encrypted);
    }

    fn encrypt_like_java_client(plaintext: &[u8], modulus: &BigUint) -> Vec<u8> {
        let public_exponent = BigUint::from(65_537u32);
        let encrypted = BigUint::from_bytes_be(plaintext).modpow(&public_exponent, modulus);
        signed_positive_bytes(&encrypted)
    }

    fn signed_positive_bytes(value: &BigUint) -> Vec<u8> {
        if *value == BigUint::from(0u32) {
            return vec![0];
        }
        let mut bytes = value.to_bytes_be();
        if bytes[0] & 0x80 != 0 {
            bytes.insert(0, 0);
        }
        bytes
    }
}
