//! Bank handler module for managing player banking interactions.
//!
//! Provides session tracking, bank PIN verification, packet building,
//! and deposit/withdraw orchestration on top of the core `Bank` type
//! defined in `super::bank`.

use std::collections::HashMap;
use tracing::{debug, info, warn};

use crate::protocol::opcodes::OpcodeOut;
use crate::protocol::{Packet, PacketBuilder, PacketReader};

use super::bank::{Bank, BankError};
use super::item::ItemId;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Maximum bank slots for members.
pub const MEMBER_BANK_CAPACITY: usize = 192;
/// Maximum bank slots for free-to-play accounts.
pub const F2P_BANK_CAPACITY: usize = 48;

// ---------------------------------------------------------------------------
// Player bank (wrapper with capacity semantics)
// ---------------------------------------------------------------------------

/// A player's bank storage, wrapping the core `Bank` with membership
/// awareness and convenience helpers.
#[derive(Debug, Clone)]
pub struct PlayerBank {
    /// The underlying bank storage.
    pub bank: Bank,
    /// Whether the owner is a member (affects capacity).
    pub is_member: bool,
}

impl PlayerBank {
    /// Create a new player bank.
    pub fn new(is_member: bool) -> Self {
        let capacity = if is_member {
            MEMBER_BANK_CAPACITY
        } else {
            F2P_BANK_CAPACITY
        };
        Self {
            bank: Bank::with_capacity(capacity),
            is_member,
        }
    }

    /// Deposit an item.
    pub fn deposit(&mut self, item_id: ItemId, amount: u32) -> Result<(), BankError> {
        self.bank.deposit(item_id.0, amount)
    }

    /// Withdraw an item, returning the actual amount withdrawn.
    pub fn withdraw(&mut self, item_id: ItemId, amount: u32) -> Result<u32, BankError> {
        self.bank.withdraw(item_id.0, amount)
    }

    /// Check whether the bank contains a given item.
    pub fn has_item(&self, item_id: ItemId) -> bool {
        self.bank.contains(item_id.0)
    }

    /// Get the quantity of a specific item.
    pub fn count(&self, item_id: ItemId) -> u32 {
        self.bank.get_amount(item_id.0)
    }

    /// Get all items as `(ItemId, amount)` pairs.
    pub fn items(&self) -> Vec<(ItemId, u32)> {
        self.bank
            .items()
            .iter()
            .map(|bi| (ItemId(bi.item_id), bi.amount))
            .collect()
    }

    /// Remaining free slots.
    pub fn free_slots(&self) -> usize {
        self.bank.free_slots()
    }

    /// Whether the bank is at capacity.
    pub fn is_full(&self) -> bool {
        self.bank.is_full()
    }
}

// ---------------------------------------------------------------------------
// Bank PIN
// ---------------------------------------------------------------------------

/// A bank PIN stored as a salted hash.
///
/// The hash is produced with SHA-256 over `salt ++ pin_digits` so the
/// raw PIN is never kept in memory after verification.
#[derive(Debug, Clone)]
pub struct BankPin {
    /// Hex-encoded SHA-256 hash.
    hash: String,
    /// Hex-encoded random salt.
    salt: String,
}

impl BankPin {
    /// Create a new bank PIN from raw digits (e.g. "1234").
    pub fn set_pin(pin: &str) -> Self {
        use sha2::{Digest, Sha256};

        let salt = generate_salt();
        let mut hasher = Sha256::new();
        hasher.update(salt.as_bytes());
        hasher.update(pin.as_bytes());
        let hash = hex::encode(hasher.finalize());

        Self { hash, salt }
    }

    /// Verify a candidate PIN against the stored hash.
    pub fn verify_pin(&self, candidate: &str) -> bool {
        use sha2::{Digest, Sha256};

        let mut hasher = Sha256::new();
        hasher.update(self.salt.as_bytes());
        hasher.update(candidate.as_bytes());
        let candidate_hash = hex::encode(hasher.finalize());

        constant_time_eq::constant_time_eq(self.hash.as_bytes(), candidate_hash.as_bytes())
    }
}

/// Generate a random 16-byte hex salt.
fn generate_salt() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let bytes: [u8; 16] = rng.gen();
    hex::encode(bytes)
}

// ---------------------------------------------------------------------------
// Bank session
// ---------------------------------------------------------------------------

/// Tracks whether a player has the bank interface open and PIN status.
#[derive(Debug, Clone)]
pub struct BankSession {
    /// Whether the bank interface is currently open.
    pub is_open: bool,
    /// Whether the player has verified their PIN this session.
    pub pin_verified: bool,
}

impl BankSession {
    fn new() -> Self {
        Self {
            is_open: false,
            pin_verified: false,
        }
    }
}

// ---------------------------------------------------------------------------
// Bank handler manager
// ---------------------------------------------------------------------------

/// Manages bank sessions, PIN state, and packet generation for all
/// connected players.
#[derive(Debug, Default)]
pub struct BankHandler {
    /// Active bank sessions keyed by player ID.
    sessions: HashMap<u64, BankSession>,
    /// Bank PINs keyed by player ID (only present if a PIN is set).
    pins: HashMap<u64, BankPin>,
}

/// Java bank deposit/withdraw request payload.
///
/// Custom v235 and v203 encode bank item movement as:
/// `item_id(u16) | amount(u32)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BankItemAmountRequest {
    pub item_id: ItemId,
    pub amount: u32,
}

impl BankItemAmountRequest {
    pub fn parse(packet: &Packet) -> Result<Self, BankHandlerError> {
        let mut reader = PacketReader::new(packet);
        let item_id = reader
            .read_short()
            .map_err(|_| BankHandlerError::MalformedPacket)?;
        let amount = reader
            .read_int()
            .map_err(|_| BankHandlerError::MalformedPacket)?;

        if reader.remaining() != 0 {
            return Err(BankHandlerError::MalformedPacket);
        }

        Ok(Self {
            item_id: ItemId(item_id as u32),
            amount,
        })
    }
}

impl BankHandler {
    pub fn new() -> Self {
        Self::default()
    }

    // -- PIN management ------------------------------------------------------

    /// Set (or replace) a bank PIN for a player.
    pub fn set_pin(&mut self, player_id: u64, pin: &str) {
        info!("Player {} set a bank PIN", player_id);
        self.pins.insert(player_id, BankPin::set_pin(pin));
    }

    /// Verify a player's bank PIN. Returns `true` if correct or if no
    /// PIN is set.
    pub fn verify_pin(&mut self, player_id: u64, candidate: &str) -> bool {
        match self.pins.get(&player_id) {
            Some(bp) => {
                let ok = bp.verify_pin(candidate);
                if ok {
                    if let Some(session) = self.sessions.get_mut(&player_id) {
                        session.pin_verified = true;
                    }
                    debug!("Player {} PIN verified", player_id);
                } else {
                    warn!("Player {} entered wrong PIN", player_id);
                }
                ok
            }
            None => true, // No PIN set -- always passes
        }
    }

    /// Remove a player's bank PIN.
    pub fn remove_pin(&mut self, player_id: u64) {
        self.pins.remove(&player_id);
        info!("Player {} removed bank PIN", player_id);
    }

    /// Check whether a player has a bank PIN configured.
    pub fn has_pin(&self, player_id: u64) -> bool {
        self.pins.contains_key(&player_id)
    }

    // -- Session management --------------------------------------------------

    /// Open the bank interface for a player.
    ///
    /// If the player has a PIN that hasn't been verified this session,
    /// returns an error requiring PIN entry first.
    pub fn open_bank(
        &mut self,
        player_id: u64,
        player_bank: &PlayerBank,
    ) -> Result<Vec<Packet>, BankHandlerError> {
        // Ensure a session record exists
        let session = self
            .sessions
            .entry(player_id)
            .or_insert_with(BankSession::new);

        // PIN gate
        if self.pins.contains_key(&player_id) && !session.pin_verified {
            return Err(BankHandlerError::PinRequired);
        }

        session.is_open = true;
        debug!(
            "Player {} opened bank ({} items)",
            player_id,
            player_bank.bank.slot_count()
        );

        Ok(vec![build_open_bank_packet(player_bank)])
    }

    /// Handle a deposit request.
    pub fn handle_deposit(
        &self,
        player_id: u64,
        _item_id: ItemId,
        _amount: u32,
    ) -> Result<(), BankHandlerError> {
        let session = self
            .sessions
            .get(&player_id)
            .ok_or(BankHandlerError::BankClosed)?;
        if !session.is_open {
            return Err(BankHandlerError::BankClosed);
        }
        // Actual item movement is handled by the caller (game engine) --
        // this method validates the session state only.
        Ok(())
    }

    /// Handle a withdraw request.
    pub fn handle_withdraw(
        &self,
        player_id: u64,
        _item_id: ItemId,
        _amount: u32,
    ) -> Result<(), BankHandlerError> {
        let session = self
            .sessions
            .get(&player_id)
            .ok_or(BankHandlerError::BankClosed)?;
        if !session.is_open {
            return Err(BankHandlerError::BankClosed);
        }
        Ok(())
    }

    /// Handle a "deposit all inventory" request.
    pub fn handle_deposit_all(&self, player_id: u64) -> Result<(), BankHandlerError> {
        let session = self
            .sessions
            .get(&player_id)
            .ok_or(BankHandlerError::BankClosed)?;
        if !session.is_open {
            return Err(BankHandlerError::BankClosed);
        }
        Ok(())
    }

    /// Close the bank interface for a player.
    pub fn close_bank(&mut self, player_id: u64) -> Vec<Packet> {
        if let Some(session) = self.sessions.get_mut(&player_id) {
            session.is_open = false;
            debug!("Player {} closed bank", player_id);
        }
        vec![build_close_bank_packet()]
    }

    /// Check whether a player currently has the bank open.
    pub fn has_bank_open(&self, player_id: u64) -> bool {
        self.sessions
            .get(&player_id)
            .map(|s| s.is_open)
            .unwrap_or(false)
    }

    /// Build a bank update packet for one slot.
    pub fn build_update(&self, slot: u8, item_id: ItemId, amount: u32) -> Packet {
        build_bank_update_packet(slot, item_id, amount)
    }

    /// Clean up session state when a player logs out.
    pub fn on_logout(&mut self, player_id: u64) {
        self.sessions.remove(&player_id);
    }
}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build the packet that opens the bank interface on the client.
///
/// Layout: opcode | slot_count(u8) | capacity(u8)
///   then for each slot: item_id(u16) | amount(unsigned-short-int)
pub fn build_open_bank_packet(player_bank: &PlayerBank) -> Packet {
    let items = player_bank.bank.items();
    let mut builder = PacketBuilder::new(OpcodeOut::OpenBank.wire())
        .write_byte(items.len().min(u8::MAX as usize) as u8)
        .write_byte(player_bank.bank.capacity().min(u8::MAX as usize) as u8);

    for item in items.iter().take(u8::MAX as usize) {
        builder = builder
            .write_short(item.item_id as u16)
            .write_unsigned_short_int(item.amount);
    }

    builder.build()
}

/// Build a bank-contents update packet for a single slot.
pub fn build_bank_update_packet(slot: u8, item_id: ItemId, amount: u32) -> Packet {
    PacketBuilder::new(OpcodeOut::SEND_BANK_UPDATE.wire())
        .write_byte(slot)
        .write_short(item_id.0 as u16)
        .write_unsigned_short_int(amount)
        .build()
}

/// Build the packet that closes the bank interface.
pub fn build_close_bank_packet() -> Packet {
    PacketBuilder::new(OpcodeOut::CloseInterface.wire()).build()
}

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

/// Errors that can occur during bank handler operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BankHandlerError {
    /// The bank interface is not open.
    BankClosed,
    /// A bank PIN must be entered first.
    PinRequired,
    /// Forwarded error from the underlying `Bank`.
    BankError(BankError),
    /// The client packet did not match the Java bank payload shape.
    MalformedPacket,
}

impl std::fmt::Display for BankHandlerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::BankClosed => write!(f, "Bank is not open"),
            Self::PinRequired => write!(f, "Bank PIN verification required"),
            Self::BankError(e) => write!(f, "Bank error: {}", e),
            Self::MalformedPacket => write!(f, "Malformed bank packet"),
        }
    }
}

impl std::error::Error for BankHandlerError {}

impl From<BankError> for BankHandlerError {
    fn from(e: BankError) -> Self {
        Self::BankError(e)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn make_player_bank() -> PlayerBank {
        let mut pb = PlayerBank::new(true);
        pb.deposit(ItemId(10), 1000).unwrap(); // 1000 coins
        pb.deposit(ItemId(66), 5).unwrap(); // 5 bronze swords
        pb
    }

    #[test]
    fn test_player_bank_basics() {
        let pb = make_player_bank();
        assert!(pb.has_item(ItemId(10)));
        assert_eq!(pb.count(ItemId(10)), 1000);
        assert_eq!(pb.count(ItemId(66)), 5);
        assert!(!pb.has_item(ItemId(999)));
    }

    #[test]
    fn test_player_bank_deposit_withdraw() {
        let mut pb = PlayerBank::new(false);
        assert_eq!(pb.bank.capacity(), F2P_BANK_CAPACITY);

        pb.deposit(ItemId(10), 50).unwrap();
        assert_eq!(pb.count(ItemId(10)), 50);

        let withdrawn = pb.withdraw(ItemId(10), 20).unwrap();
        assert_eq!(withdrawn, 20);
        assert_eq!(pb.count(ItemId(10)), 30);
    }

    #[test]
    fn test_member_vs_f2p_capacity() {
        let member_bank = PlayerBank::new(true);
        let f2p_bank = PlayerBank::new(false);
        assert_eq!(member_bank.bank.capacity(), MEMBER_BANK_CAPACITY);
        assert_eq!(f2p_bank.bank.capacity(), F2P_BANK_CAPACITY);
    }

    #[test]
    fn test_open_close_bank() {
        let mut handler = BankHandler::new();
        let pb = make_player_bank();

        let packets = handler.open_bank(1, &pb).unwrap();
        assert!(!packets.is_empty());
        assert!(handler.has_bank_open(1));

        let packets = handler.close_bank(1);
        assert!(!packets.is_empty());
        assert!(!handler.has_bank_open(1));
    }

    #[test]
    fn test_deposit_requires_open() {
        let handler = BankHandler::new();
        let result = handler.handle_deposit(1, ItemId(10), 5);
        assert!(matches!(result, Err(BankHandlerError::BankClosed)));
    }

    #[test]
    fn test_withdraw_requires_open() {
        let handler = BankHandler::new();
        let result = handler.handle_withdraw(1, ItemId(10), 5);
        assert!(matches!(result, Err(BankHandlerError::BankClosed)));
    }

    #[test]
    fn test_zero_amount_requests_are_valid_when_open() {
        let mut handler = BankHandler::new();
        let pb = make_player_bank();
        handler.open_bank(1, &pb).unwrap();

        assert_eq!(handler.handle_deposit(1, ItemId(10), 0), Ok(()));
        assert_eq!(handler.handle_withdraw(1, ItemId(10), 0), Ok(()));
    }

    #[test]
    fn test_deposit_all_requires_open() {
        let handler = BankHandler::new();
        let result = handler.handle_deposit_all(1);
        assert!(matches!(result, Err(BankHandlerError::BankClosed)));
    }

    #[test]
    fn test_bank_pin_set_and_verify() {
        let mut handler = BankHandler::new();

        handler.set_pin(1, "1234");
        assert!(handler.has_pin(1));

        assert!(handler.verify_pin(1, "1234"));
        assert!(!handler.verify_pin(1, "0000"));
    }

    #[test]
    fn test_bank_pin_blocks_open() {
        let mut handler = BankHandler::new();
        let pb = make_player_bank();

        handler.set_pin(1, "5678");

        // Should fail without PIN verification
        let result = handler.open_bank(1, &pb);
        assert!(matches!(result, Err(BankHandlerError::PinRequired)));

        // Verify PIN then retry
        assert!(handler.verify_pin(1, "5678"));
        let packets = handler.open_bank(1, &pb);
        assert!(packets.is_ok());
    }

    #[test]
    fn test_no_pin_allows_open() {
        let mut handler = BankHandler::new();
        let pb = make_player_bank();

        // No PIN set -- should open freely
        let packets = handler.open_bank(1, &pb);
        assert!(packets.is_ok());
    }

    #[test]
    fn test_remove_pin() {
        let mut handler = BankHandler::new();

        handler.set_pin(1, "1234");
        assert!(handler.has_pin(1));

        handler.remove_pin(1);
        assert!(!handler.has_pin(1));
    }

    #[test]
    fn test_bank_pin_struct_directly() {
        let pin = BankPin::set_pin("9999");
        assert!(pin.verify_pin("9999"));
        assert!(!pin.verify_pin("1111"));
    }

    #[test]
    fn test_logout_clears_session() {
        let mut handler = BankHandler::new();
        let pb = make_player_bank();

        handler.open_bank(1, &pb).unwrap();
        assert!(handler.has_bank_open(1));

        handler.on_logout(1);
        assert!(!handler.has_bank_open(1));
    }

    #[test]
    fn test_items_vec() {
        let pb = make_player_bank();
        let items = pb.items();
        assert_eq!(items.len(), 2);
        assert!(items.contains(&(ItemId(10), 1000)));
        assert!(items.contains(&(ItemId(66), 5)));
    }

    #[test]
    fn test_open_bank_packet_not_empty() {
        let pb = make_player_bank();
        let packet = build_open_bank_packet(&pb);
        assert!(!packet.is_empty());
        assert_eq!(packet.opcode, OpcodeOut::OpenBank.wire());
    }

    #[test]
    fn test_open_bank_packet_uses_java_amount_encoding() {
        let mut pb = PlayerBank::new(true);
        pb.deposit(ItemId(10), 32_767).unwrap();
        pb.deposit(ItemId(66), 32_768).unwrap();

        let packet = build_open_bank_packet(&pb);

        assert_eq!(packet.opcode, OpcodeOut::SEND_BANK_OPEN.wire());
        assert_eq!(
            packet.payload,
            vec![2, 192, 0, 10, 0x7f, 0xff, 0, 66, 0x80, 0x00, 0x80, 0x00,]
        );
    }

    #[test]
    fn test_bank_update_packet_is_single_slot_delta() {
        let packet = build_bank_update_packet(3, ItemId(10), 5);

        assert_eq!(packet.opcode, OpcodeOut::SEND_BANK_UPDATE.wire());
        assert_eq!(packet.payload, vec![3, 0, 10, 0, 5]);
    }

    #[test]
    fn test_bank_update_packet_uses_large_amount_encoding() {
        let packet = build_bank_update_packet(3, ItemId(10), 32_768);

        assert_eq!(packet.opcode, OpcodeOut::SEND_BANK_UPDATE.wire());
        assert_eq!(packet.payload, vec![3, 0, 10, 0x80, 0x00, 0x80, 0x00]);
    }

    #[test]
    fn test_close_bank_packet() {
        let packet = build_close_bank_packet();
        assert_eq!(packet.opcode, OpcodeOut::CloseInterface.wire());
    }

    #[test]
    fn test_parse_bank_item_amount_request() {
        let packet = PacketBuilder::new(23).write_short(10).write_int(5).build();

        let request = BankItemAmountRequest::parse(&packet).unwrap();
        assert_eq!(request.item_id, ItemId(10));
        assert_eq!(request.amount, 5);
    }

    #[test]
    fn test_parse_bank_item_amount_rejects_short_or_extra_payload() {
        let short_packet = Packet::new(23, vec![0, 10, 0]);
        assert!(matches!(
            BankItemAmountRequest::parse(&short_packet),
            Err(BankHandlerError::MalformedPacket)
        ));

        let extra_packet = Packet::new(23, vec![0, 10, 0, 0, 0, 5, 99]);
        assert!(matches!(
            BankItemAmountRequest::parse(&extra_packet),
            Err(BankHandlerError::MalformedPacket)
        ));
    }
}
