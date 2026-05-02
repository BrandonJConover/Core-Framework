//! Network protocol handling.
//! Defines packet structures, opcodes, and protocol encoding/decoding.

use std::io::{self, Read};

/// Protocol version.
pub const PROTOCOL_VERSION: u32 = 235;

/// Maximum packet size.
pub const MAX_PACKET_SIZE: usize = 5000;

/// Client to server opcodes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum ClientOpcode {
    /// Login request.
    Login = 0,
    /// Reconnect request.
    Reconnect = 1,
    /// Logout request.
    Logout = 2,
    /// Walk to point.
    WalkToPoint = 3,
    /// Walk to entity.
    WalkToEntity = 4,
    /// Player command.
    Command = 5,
    /// Chat message.
    Chat = 6,
    /// Private message.
    PrivateMessage = 7,
    /// Add friend.
    AddFriend = 8,
    /// Remove friend.
    RemoveFriend = 9,
    /// Add ignore.
    AddIgnore = 10,
    /// Remove ignore.
    RemoveIgnore = 11,
    /// Attack player.
    AttackPlayer = 12,
    /// Attack NPC.
    AttackNpc = 13,
    /// Cast on self.
    CastOnSelf = 14,
    /// Cast on player.
    CastOnPlayer = 15,
    /// Cast on NPC.
    CastOnNpc = 16,
    /// Cast on ground item.
    CastOnGroundItem = 17,
    /// Cast on inventory item.
    CastOnInventoryItem = 18,
    /// Cast on object.
    CastOnObject = 19,
    /// Cast on boundary.
    CastOnBoundary = 20,
    /// Use item with player.
    UseWithPlayer = 21,
    /// Use item with NPC.
    UseWithNpc = 22,
    /// Use item with ground item.
    UseWithGroundItem = 23,
    /// Use item with inventory item.
    UseWithInventoryItem = 24,
    /// Use item with object.
    UseWithObject = 25,
    /// Use item with boundary.
    UseWithBoundary = 26,
    /// Take ground item.
    TakeGroundItem = 27,
    /// Drop item.
    DropItem = 28,
    /// Equip item.
    EquipItem = 29,
    /// Unequip item.
    UnequipItem = 30,
    /// Object action primary.
    ObjectAction = 31,
    /// Object action secondary.
    ObjectActionSecondary = 32,
    /// Boundary action primary.
    BoundaryAction = 33,
    /// Boundary action secondary.
    BoundaryActionSecondary = 34,
    /// NPC talk.
    NpcTalk = 35,
    /// NPC action.
    NpcAction = 36,
    /// Trade request.
    TradeRequest = 37,
    /// Trade accept.
    TradeAccept = 38,
    /// Trade decline.
    TradeDecline = 39,
    /// Trade confirm.
    TradeConfirm = 40,
    /// Trade offer update.
    TradeOffer = 41,
    /// Duel request.
    DuelRequest = 42,
    /// Duel accept.
    DuelAccept = 43,
    /// Duel decline.
    DuelDecline = 44,
    /// Duel confirm.
    DuelConfirm = 45,
    /// Duel settings.
    DuelSettings = 46,
    /// Duel offer update.
    DuelOffer = 47,
    /// Prayer activate.
    PrayerActivate = 48,
    /// Prayer deactivate.
    PrayerDeactivate = 49,
    /// Bank deposit.
    BankDeposit = 50,
    /// Bank withdraw.
    BankWithdraw = 51,
    /// Bank close.
    BankClose = 52,
    /// Shop buy.
    ShopBuy = 53,
    /// Shop sell.
    ShopSell = 54,
    /// Shop close.
    ShopClose = 55,
    /// Dialogue option.
    DialogueOption = 56,
    /// Quest list.
    QuestList = 57,
    /// Settings privacy.
    SettingsPrivacy = 58,
    /// Settings game.
    SettingsGame = 59,
    /// Report abuse.
    ReportAbuse = 60,
    /// Sleep word answer.
    SleepWord = 61,
    /// Change appearance.
    ChangeAppearance = 62,
    /// Combat style.
    CombatStyle = 63,
    /// Ping/keepalive.
    Ping = 64,
    /// Unknown/invalid.
    Unknown = 255,
}

impl From<u8> for ClientOpcode {
    fn from(value: u8) -> Self {
        match value {
            0 => ClientOpcode::Login,
            1 => ClientOpcode::Reconnect,
            2 => ClientOpcode::Logout,
            3 => ClientOpcode::WalkToPoint,
            4 => ClientOpcode::WalkToEntity,
            5 => ClientOpcode::Command,
            6 => ClientOpcode::Chat,
            7 => ClientOpcode::PrivateMessage,
            8 => ClientOpcode::AddFriend,
            9 => ClientOpcode::RemoveFriend,
            10 => ClientOpcode::AddIgnore,
            11 => ClientOpcode::RemoveIgnore,
            12 => ClientOpcode::AttackPlayer,
            13 => ClientOpcode::AttackNpc,
            14 => ClientOpcode::CastOnSelf,
            15 => ClientOpcode::CastOnPlayer,
            16 => ClientOpcode::CastOnNpc,
            17 => ClientOpcode::CastOnGroundItem,
            18 => ClientOpcode::CastOnInventoryItem,
            19 => ClientOpcode::CastOnObject,
            20 => ClientOpcode::CastOnBoundary,
            21 => ClientOpcode::UseWithPlayer,
            22 => ClientOpcode::UseWithNpc,
            23 => ClientOpcode::UseWithGroundItem,
            24 => ClientOpcode::UseWithInventoryItem,
            25 => ClientOpcode::UseWithObject,
            26 => ClientOpcode::UseWithBoundary,
            27 => ClientOpcode::TakeGroundItem,
            28 => ClientOpcode::DropItem,
            29 => ClientOpcode::EquipItem,
            30 => ClientOpcode::UnequipItem,
            31 => ClientOpcode::ObjectAction,
            32 => ClientOpcode::ObjectActionSecondary,
            33 => ClientOpcode::BoundaryAction,
            34 => ClientOpcode::BoundaryActionSecondary,
            35 => ClientOpcode::NpcTalk,
            36 => ClientOpcode::NpcAction,
            37 => ClientOpcode::TradeRequest,
            38 => ClientOpcode::TradeAccept,
            39 => ClientOpcode::TradeDecline,
            40 => ClientOpcode::TradeConfirm,
            41 => ClientOpcode::TradeOffer,
            42 => ClientOpcode::DuelRequest,
            43 => ClientOpcode::DuelAccept,
            44 => ClientOpcode::DuelDecline,
            45 => ClientOpcode::DuelConfirm,
            46 => ClientOpcode::DuelSettings,
            47 => ClientOpcode::DuelOffer,
            48 => ClientOpcode::PrayerActivate,
            49 => ClientOpcode::PrayerDeactivate,
            50 => ClientOpcode::BankDeposit,
            51 => ClientOpcode::BankWithdraw,
            52 => ClientOpcode::BankClose,
            53 => ClientOpcode::ShopBuy,
            54 => ClientOpcode::ShopSell,
            55 => ClientOpcode::ShopClose,
            56 => ClientOpcode::DialogueOption,
            57 => ClientOpcode::QuestList,
            58 => ClientOpcode::SettingsPrivacy,
            59 => ClientOpcode::SettingsGame,
            60 => ClientOpcode::ReportAbuse,
            61 => ClientOpcode::SleepWord,
            62 => ClientOpcode::ChangeAppearance,
            63 => ClientOpcode::CombatStyle,
            64 => ClientOpcode::Ping,
            _ => ClientOpcode::Unknown,
        }
    }
}

/// Server to client opcodes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum ServerOpcode {
    /// Login response.
    LoginResponse = 0,
    /// Logout response.
    LogoutResponse = 1,
    /// Player update.
    PlayerUpdate = 2,
    /// Ground items update.
    GroundItemsUpdate = 3,
    /// Objects update.
    ObjectsUpdate = 4,
    /// Inventory update.
    InventoryUpdate = 5,
    /// Player position.
    PlayerPosition = 6,
    /// NPC update.
    NpcUpdate = 7,
    /// Boundaries update.
    BoundariesUpdate = 8,
    /// NPC message.
    NpcMessage = 9,
    /// Quest update.
    QuestUpdate = 10,
    /// World info.
    WorldInfo = 11,
    /// Stats update.
    StatsUpdate = 12,
    /// Equipment stats.
    EquipmentStats = 13,
    /// Death screen.
    DeathScreen = 14,
    /// Environment.
    Environment = 15,
    /// Character design.
    CharacterDesign = 16,
    /// Trade window open.
    TradeWindowOpen = 17,
    /// Trade other items.
    TradeOtherItems = 18,
    /// Trade close.
    TradeClose = 19,
    /// Trade update.
    TradeUpdate = 20,
    /// Shop open.
    ShopOpen = 21,
    /// Shop close.
    ShopClose = 22,
    /// Duel window open.
    DuelWindowOpen = 23,
    /// Duel settings.
    DuelSettings = 24,
    /// Duel close.
    DuelClose = 25,
    /// Duel update.
    DuelUpdate = 26,
    /// Bank open.
    BankOpen = 27,
    /// Bank close.
    BankClose = 28,
    /// Bank update.
    BankUpdate = 29,
    /// Experience update.
    ExperienceUpdate = 30,
    /// Dialogue options.
    DialogueOptions = 31,
    /// Message.
    Message = 32,
    /// Private message incoming.
    PrivateMessageIn = 33,
    /// Private message outgoing.
    PrivateMessageOut = 34,
    /// System update.
    SystemUpdate = 35,
    /// Teleport bubble.
    TeleportBubble = 36,
    /// Play sound.
    PlaySound = 37,
    /// Show sleep screen.
    SleepScreen = 38,
    /// Sleep result.
    SleepResult = 39,
    /// Friend list.
    FriendList = 40,
    /// Friend update.
    FriendUpdate = 41,
    /// Ignore list.
    IgnoreList = 42,
    /// Privacy settings.
    PrivacySettings = 43,
    /// Combat style.
    CombatStyleUpdate = 44,
    /// Fatigue update.
    FatigueUpdate = 45,
    /// Prayer status.
    PrayerStatus = 46,
    /// Options menu.
    OptionsMenu = 47,
    /// Server message.
    ServerMessage = 48,
    /// Unknown/invalid.
    Unknown = 255,
}

impl From<u8> for ServerOpcode {
    fn from(value: u8) -> Self {
        match value {
            0 => ServerOpcode::LoginResponse,
            1 => ServerOpcode::LogoutResponse,
            2 => ServerOpcode::PlayerUpdate,
            3 => ServerOpcode::GroundItemsUpdate,
            4 => ServerOpcode::ObjectsUpdate,
            5 => ServerOpcode::InventoryUpdate,
            6 => ServerOpcode::PlayerPosition,
            7 => ServerOpcode::NpcUpdate,
            8 => ServerOpcode::BoundariesUpdate,
            9 => ServerOpcode::NpcMessage,
            10 => ServerOpcode::QuestUpdate,
            11 => ServerOpcode::WorldInfo,
            12 => ServerOpcode::StatsUpdate,
            13 => ServerOpcode::EquipmentStats,
            14 => ServerOpcode::DeathScreen,
            15 => ServerOpcode::Environment,
            16 => ServerOpcode::CharacterDesign,
            17 => ServerOpcode::TradeWindowOpen,
            18 => ServerOpcode::TradeOtherItems,
            19 => ServerOpcode::TradeClose,
            20 => ServerOpcode::TradeUpdate,
            21 => ServerOpcode::ShopOpen,
            22 => ServerOpcode::ShopClose,
            23 => ServerOpcode::DuelWindowOpen,
            24 => ServerOpcode::DuelSettings,
            25 => ServerOpcode::DuelClose,
            26 => ServerOpcode::DuelUpdate,
            27 => ServerOpcode::BankOpen,
            28 => ServerOpcode::BankClose,
            29 => ServerOpcode::BankUpdate,
            30 => ServerOpcode::ExperienceUpdate,
            31 => ServerOpcode::DialogueOptions,
            32 => ServerOpcode::Message,
            33 => ServerOpcode::PrivateMessageIn,
            34 => ServerOpcode::PrivateMessageOut,
            35 => ServerOpcode::SystemUpdate,
            36 => ServerOpcode::TeleportBubble,
            37 => ServerOpcode::PlaySound,
            38 => ServerOpcode::SleepScreen,
            39 => ServerOpcode::SleepResult,
            40 => ServerOpcode::FriendList,
            41 => ServerOpcode::FriendUpdate,
            42 => ServerOpcode::IgnoreList,
            43 => ServerOpcode::PrivacySettings,
            44 => ServerOpcode::CombatStyleUpdate,
            45 => ServerOpcode::FatigueUpdate,
            46 => ServerOpcode::PrayerStatus,
            47 => ServerOpcode::OptionsMenu,
            48 => ServerOpcode::ServerMessage,
            _ => ServerOpcode::Unknown,
        }
    }
}

/// Packet structure.
#[derive(Debug, Clone)]
pub struct Packet {
    /// Packet opcode.
    pub opcode: u8,
    /// Packet payload.
    pub payload: Vec<u8>,
}

impl Packet {
    /// Create a new packet.
    pub fn new(opcode: u8) -> Self {
        Self {
            opcode,
            payload: Vec::new(),
        }
    }

    /// Create a packet with payload.
    pub fn with_payload(opcode: u8, payload: Vec<u8>) -> Self {
        Self { opcode, payload }
    }

    /// Get packet length.
    pub fn len(&self) -> usize {
        self.payload.len()
    }

    /// Check if packet is empty.
    pub fn is_empty(&self) -> bool {
        self.payload.is_empty()
    }

    /// Add a byte to the payload.
    pub fn add_byte(&mut self, value: u8) {
        self.payload.push(value);
    }

    /// Add a short (2 bytes, big-endian) to the payload.
    pub fn add_short(&mut self, value: u16) {
        self.payload.push((value >> 8) as u8);
        self.payload.push(value as u8);
    }

    /// Add an int (4 bytes, big-endian) to the payload.
    pub fn add_int(&mut self, value: u32) {
        self.payload.push((value >> 24) as u8);
        self.payload.push((value >> 16) as u8);
        self.payload.push((value >> 8) as u8);
        self.payload.push(value as u8);
    }

    /// Add a long (8 bytes, big-endian) to the payload.
    pub fn add_long(&mut self, value: u64) {
        self.payload.push((value >> 56) as u8);
        self.payload.push((value >> 48) as u8);
        self.payload.push((value >> 40) as u8);
        self.payload.push((value >> 32) as u8);
        self.payload.push((value >> 24) as u8);
        self.payload.push((value >> 16) as u8);
        self.payload.push((value >> 8) as u8);
        self.payload.push(value as u8);
    }

    /// Add bytes to the payload.
    pub fn add_bytes(&mut self, bytes: &[u8]) {
        self.payload.extend_from_slice(bytes);
    }

    /// Add a string to the payload (null-terminated).
    pub fn add_string(&mut self, s: &str) {
        self.payload.extend_from_slice(s.as_bytes());
        self.payload.push(0);
    }

    /// Encode the packet to bytes.
    pub fn encode(&self) -> Vec<u8> {
        let len = self.payload.len();
        let mut data = Vec::with_capacity(3 + len);

        // Length header (big-endian, includes opcode)
        if len >= 160 {
            data.push(((len / 256) + 160) as u8);
            data.push((len & 0xFF) as u8);
        } else {
            data.push(len as u8);
        }

        // Opcode
        data.push(self.opcode);

        // Payload
        data.extend_from_slice(&self.payload);

        data
    }
}

/// Packet reader for parsing incoming packets.
#[derive(Debug)]
pub struct PacketReader<'a> {
    data: &'a [u8],
    position: usize,
}

impl<'a> PacketReader<'a> {
    /// Create a new packet reader.
    pub fn new(data: &'a [u8]) -> Self {
        Self { data, position: 0 }
    }

    /// Get remaining bytes.
    pub fn remaining(&self) -> usize {
        self.data.len().saturating_sub(self.position)
    }

    /// Check if there are more bytes to read.
    pub fn has_remaining(&self) -> bool {
        self.position < self.data.len()
    }

    /// Read a single byte.
    pub fn read_byte(&mut self) -> io::Result<u8> {
        if self.position >= self.data.len() {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "No more data",
            ));
        }
        let value = self.data[self.position];
        self.position += 1;
        Ok(value)
    }

    /// Read a signed byte.
    pub fn read_signed_byte(&mut self) -> io::Result<i8> {
        Ok(self.read_byte()? as i8)
    }

    /// Read a short (2 bytes, big-endian).
    pub fn read_short(&mut self) -> io::Result<u16> {
        let high = self.read_byte()? as u16;
        let low = self.read_byte()? as u16;
        Ok((high << 8) | low)
    }

    /// Read a signed short.
    pub fn read_signed_short(&mut self) -> io::Result<i16> {
        Ok(self.read_short()? as i16)
    }

    /// Read an int (4 bytes, big-endian).
    pub fn read_int(&mut self) -> io::Result<u32> {
        let b1 = self.read_byte()? as u32;
        let b2 = self.read_byte()? as u32;
        let b3 = self.read_byte()? as u32;
        let b4 = self.read_byte()? as u32;
        Ok((b1 << 24) | (b2 << 16) | (b3 << 8) | b4)
    }

    /// Read a long (8 bytes, big-endian).
    pub fn read_long(&mut self) -> io::Result<u64> {
        let high = self.read_int()? as u64;
        let low = self.read_int()? as u64;
        Ok((high << 32) | low)
    }

    /// Read a null-terminated string.
    pub fn read_string(&mut self) -> io::Result<String> {
        let start = self.position;
        while self.position < self.data.len() && self.data[self.position] != 0 {
            self.position += 1;
        }
        let string = String::from_utf8_lossy(&self.data[start..self.position]).to_string();
        if self.position < self.data.len() {
            self.position += 1; // Skip null terminator
        }
        Ok(string)
    }

    /// Read remaining bytes.
    pub fn read_remaining(&mut self) -> Vec<u8> {
        let remaining = self.data[self.position..].to_vec();
        self.position = self.data.len();
        remaining
    }

    /// Read a specific number of bytes.
    pub fn read_bytes(&mut self, count: usize) -> io::Result<Vec<u8>> {
        if self.position + count > self.data.len() {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "Not enough data",
            ));
        }
        let bytes = self.data[self.position..self.position + count].to_vec();
        self.position += count;
        Ok(bytes)
    }

    /// Skip bytes.
    pub fn skip(&mut self, count: usize) {
        self.position = (self.position + count).min(self.data.len());
    }
}

/// Decode a packet from raw bytes.
pub fn decode_packet(data: &[u8]) -> io::Result<(Packet, usize)> {
    if data.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "No data",
        ));
    }

    // Parse length
    let (length, header_size) = if data[0] >= 160 {
        if data.len() < 2 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "Incomplete header",
            ));
        }
        let len = ((data[0] as usize - 160) * 256) + data[1] as usize;
        (len, 2)
    } else {
        (data[0] as usize, 1)
    };

    let total_size = header_size + 1 + length; // header + opcode + payload
    if data.len() < total_size {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "Incomplete packet",
        ));
    }

    let opcode = data[header_size];
    let payload = data[header_size + 1..header_size + 1 + length].to_vec();

    Ok((Packet::with_payload(opcode, payload), total_size))
}

/// Encode a username to the protocol format (base-37).
pub fn encode_username(username: &str) -> u64 {
    let mut hash: u64 = 0;
    for c in username.chars().take(12) {
        hash *= 37;
        let c = c.to_ascii_lowercase();
        if c >= 'a' && c <= 'z' {
            hash += (c as u64 - 'a' as u64) + 1;
        } else if c >= '0' && c <= '9' {
            hash += (c as u64 - '0' as u64) + 27;
        }
    }
    hash
}

/// Decode a username from protocol format (base-37).
pub fn decode_username(hash: u64) -> String {
    let mut hash = hash;
    let mut chars = Vec::new();

    while hash > 0 {
        let remainder = (hash % 37) as u8;
        hash /= 37;

        if remainder == 0 {
            chars.push(' ');
        } else if remainder <= 26 {
            chars.push((b'a' + remainder - 1) as char);
        } else {
            chars.push((b'0' + remainder - 27) as char);
        }
    }

    chars.reverse();
    chars.into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_packet_encoding() {
        let mut packet = Packet::new(5);
        packet.add_byte(1);
        packet.add_short(1000);
        packet.add_int(123456);

        let encoded = packet.encode();
        assert!(!encoded.is_empty());
        assert_eq!(encoded[0], 7); // Length = 1 + 2 + 4
    }

    #[test]
    fn test_packet_reader() {
        let data = vec![0x01, 0x02, 0x03, 0x04, 0x05];
        let mut reader = PacketReader::new(&data);

        assert_eq!(reader.read_byte().unwrap(), 0x01);
        assert_eq!(reader.read_short().unwrap(), 0x0203);
        assert_eq!(reader.remaining(), 2);
    }

    #[test]
    fn test_username_encoding() {
        let username = "testuser";
        let encoded = encode_username(username);
        let decoded = decode_username(encoded);
        assert_eq!(decoded, username);
    }

    #[test]
    fn test_opcode_conversion() {
        assert_eq!(ClientOpcode::from(0), ClientOpcode::Login);
        assert_eq!(ClientOpcode::from(6), ClientOpcode::Chat);
        assert_eq!(ClientOpcode::from(255), ClientOpcode::Unknown);
    }

    #[test]
    fn test_packet_decode() {
        // Create a simple packet: length=3, opcode=5, payload=[1, 2]
        let data = vec![3, 5, 1, 2];
        let (packet, consumed) = decode_packet(&data).unwrap();

        assert_eq!(packet.opcode, 5);
        assert_eq!(packet.payload, vec![1, 2]);
        assert_eq!(consumed, 4);
    }
}
