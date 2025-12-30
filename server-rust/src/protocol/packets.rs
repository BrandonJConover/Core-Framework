//! Packet structures for RSC protocol.

use super::{PacketBuilder, PacketReader, Packet};
use crate::game::entity::Position;
use std::io;

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
        let mut reader = PacketReader::new(packet);
        let reconnecting = reader.read_byte()? == 1;
        let client_version = reader.read_int()?;
        let username = reader.read_string()?;
        let password = reader.read_string()?;

        Ok(Self {
            username,
            password,
            client_version,
            reconnecting,
        })
    }
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
        PacketBuilder::new(0)
            .write_byte(self as u8)
            .build()
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
        PacketBuilder::new(32)
            .write_string(message)
            .build()
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
        let mut builder = PacketBuilder::new(22)
            .write_byte(self.items.len() as u8);

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
