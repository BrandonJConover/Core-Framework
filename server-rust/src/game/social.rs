//! Social system module for friends list, ignore list, and privacy controls.
//! Handles friend/ignore management, online status notifications, and PM filtering.

use crate::protocol::opcodes::OpcodeOut;
use crate::protocol::{Packet, PacketBuilder};
use crate::session::SessionManager;

/// Maximum number of friends a player can have.
const MAX_FRIENDS: usize = 200;

/// Maximum number of ignored players.
const MAX_IGNORES: usize = 100;

/// Friends list for a player.
#[derive(Debug, Default, Clone)]
pub struct FriendsList {
    friends: Vec<String>,
}

impl FriendsList {
    pub fn new() -> Self {
        Self {
            friends: Vec::new(),
        }
    }

    /// Add a friend by username. Returns false if the list is full or already added.
    pub fn add_friend(&mut self, username: &str) -> bool {
        if self.friends.len() >= MAX_FRIENDS {
            return false;
        }
        let lower = username.to_lowercase();
        if self.friends.iter().any(|f| f.to_lowercase() == lower) {
            return false;
        }
        self.friends.push(username.to_string());
        true
    }

    /// Remove a friend by username. Returns true if the friend was found and removed.
    pub fn remove_friend(&mut self, username: &str) -> bool {
        let lower = username.to_lowercase();
        let before = self.friends.len();
        self.friends.retain(|f| f.to_lowercase() != lower);
        self.friends.len() < before
    }

    /// Check if a username is on the friends list.
    pub fn is_friend(&self, username: &str) -> bool {
        let lower = username.to_lowercase();
        self.friends.iter().any(|f| f.to_lowercase() == lower)
    }

    /// Get the full friends list.
    pub fn friends_list(&self) -> &[String] {
        &self.friends
    }
}

/// Ignore list for a player.
#[derive(Debug, Default, Clone)]
pub struct IgnoreList {
    ignored: Vec<String>,
}

impl IgnoreList {
    pub fn new() -> Self {
        Self {
            ignored: Vec::new(),
        }
    }

    /// Add a player to the ignore list. Returns false if full or already ignored.
    pub fn add_ignore(&mut self, username: &str) -> bool {
        if self.ignored.len() >= MAX_IGNORES {
            return false;
        }
        let lower = username.to_lowercase();
        if self.ignored.iter().any(|i| i.to_lowercase() == lower) {
            return false;
        }
        self.ignored.push(username.to_string());
        true
    }

    /// Remove a player from the ignore list. Returns true if found and removed.
    pub fn remove_ignore(&mut self, username: &str) -> bool {
        let lower = username.to_lowercase();
        let before = self.ignored.len();
        self.ignored.retain(|i| i.to_lowercase() != lower);
        self.ignored.len() < before
    }

    /// Check if a username is on the ignore list.
    pub fn is_ignored(&self, username: &str) -> bool {
        let lower = username.to_lowercase();
        self.ignored.iter().any(|i| i.to_lowercase() == lower)
    }

    /// Get the full ignore list.
    pub fn ignored_list(&self) -> &[String] {
        &self.ignored
    }
}

/// Privacy settings relevant to social interactions.
#[derive(Debug, Clone, Copy)]
pub struct PrivacySettings {
    pub block_private: bool,
    pub block_trade: bool,
    pub block_duel: bool,
}

impl Default for PrivacySettings {
    fn default() -> Self {
        Self {
            block_private: false,
            block_trade: false,
            block_duel: false,
        }
    }
}

/// Social manager handling friend notifications and privacy enforcement.
pub struct SocialManager;

impl SocialManager {
    /// Send the full friend list with online status to a session.
    /// `online_checker` resolves whether each friend username is currently online.
    pub async fn send_friend_list<F>(
        session: &crate::session::Session,
        friends: &FriendsList,
        online_checker: F,
    ) where
        F: Fn(&str) -> bool,
    {
        let entries: Vec<(String, bool)> = friends
            .friends_list()
            .iter()
            .map(|name| (name.clone(), online_checker(name)))
            .collect();

        let packet = build_friend_list_packet(&entries);
        let _ = session.send(packet).await;
    }

    /// Notify all online friends that a player has logged in.
    pub async fn notify_friends_login(
        username: &str,
        friends: &FriendsList,
        session_manager: &SessionManager,
    ) {
        let packet = build_friend_update_packet(username, true);
        Self::send_to_friends_who_have_us(username, friends, session_manager, packet).await;
    }

    /// Notify all online friends that a player has logged out.
    pub async fn notify_friends_logout(
        username: &str,
        friends: &FriendsList,
        session_manager: &SessionManager,
    ) {
        let packet = build_friend_update_packet(username, false);
        Self::send_to_friends_who_have_us(username, friends, session_manager, packet).await;
    }

    /// Send a packet to each friend who is online and has `username` on their friend list.
    async fn send_to_friends_who_have_us(
        _username: &str,
        friends: &FriendsList,
        session_manager: &SessionManager,
        packet: Packet,
    ) {
        for friend_name in friends.friends_list() {
            if let Some(friend_session) = session_manager.get_session_by_username(friend_name) {
                let session = friend_session.read().await;
                let _ = session.send(packet.clone()).await;
            }
        }
    }

    /// Check whether `sender` is allowed to send a private message to `recipient`.
    /// Returns true if the message should be delivered.
    pub fn can_message(
        sender: &str,
        _recipient: &str,
        recipient_ignore_list: &IgnoreList,
        recipient_friends: &FriendsList,
        recipient_settings: &PrivacySettings,
    ) -> bool {
        // Blocked if sender is on the recipient's ignore list.
        if recipient_ignore_list.is_ignored(sender) {
            return false;
        }
        // If recipient has private messages blocked, only friends can message them.
        if recipient_settings.block_private && !recipient_friends.is_friend(sender) {
            return false;
        }
        true
    }

    /// Check whether a trade request is allowed.
    pub fn can_trade(
        sender: &str,
        recipient_ignore_list: &IgnoreList,
        recipient_settings: &PrivacySettings,
    ) -> bool {
        if recipient_ignore_list.is_ignored(sender) {
            return false;
        }
        !recipient_settings.block_trade
    }

    /// Check whether a duel request is allowed.
    pub fn can_duel(
        sender: &str,
        recipient_ignore_list: &IgnoreList,
        recipient_settings: &PrivacySettings,
    ) -> bool {
        if recipient_ignore_list.is_ignored(sender) {
            return false;
        }
        !recipient_settings.block_duel
    }
}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build the full friend list packet. Each entry is a name + online flag.
pub fn build_friend_list_packet(friends: &[(String, bool)]) -> Packet {
    let mut builder = PacketBuilder::new(OpcodeOut::FriendList.into())
        .write_short(friends.len() as u16);

    for (name, online) in friends {
        builder = builder
            .write_string(name)
            .write_byte(if *online { 1 } else { 0 });
    }

    builder.build()
}

/// Build a single friend status update packet.
pub fn build_friend_update_packet(username: &str, online: bool) -> Packet {
    PacketBuilder::new(OpcodeOut::FriendUpdate.into())
        .write_string(username)
        .write_byte(if online { 1 } else { 0 })
        .build()
}

/// Build the full ignore list packet.
pub fn build_ignore_list_packet(ignored: &[String]) -> Packet {
    let mut builder = PacketBuilder::new(OpcodeOut::IgnoreList.into())
        .write_short(ignored.len() as u16);

    for name in ignored {
        builder = builder.write_string(name);
    }

    builder.build()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::PacketReader;

    // -- FriendsList tests --------------------------------------------------

    #[test]
    fn test_add_and_check_friend() {
        let mut fl = FriendsList::new();
        assert!(fl.add_friend("Alice"));
        assert!(fl.is_friend("alice")); // case-insensitive
        assert!(fl.is_friend("Alice"));
    }

    #[test]
    fn test_add_duplicate_friend() {
        let mut fl = FriendsList::new();
        assert!(fl.add_friend("Alice"));
        assert!(!fl.add_friend("alice")); // duplicate
    }

    #[test]
    fn test_remove_friend() {
        let mut fl = FriendsList::new();
        fl.add_friend("Bob");
        assert!(fl.remove_friend("bob"));
        assert!(!fl.is_friend("Bob"));
        assert!(!fl.remove_friend("Bob")); // already removed
    }

    #[test]
    fn test_friends_list_capacity() {
        let mut fl = FriendsList::new();
        for i in 0..MAX_FRIENDS {
            assert!(fl.add_friend(&format!("user{}", i)));
        }
        assert!(!fl.add_friend("overflow"));
        assert_eq!(fl.friends_list().len(), MAX_FRIENDS);
    }

    // -- IgnoreList tests ---------------------------------------------------

    #[test]
    fn test_add_and_check_ignore() {
        let mut il = IgnoreList::new();
        assert!(il.add_ignore("Troll"));
        assert!(il.is_ignored("troll"));
    }

    #[test]
    fn test_add_duplicate_ignore() {
        let mut il = IgnoreList::new();
        assert!(il.add_ignore("Troll"));
        assert!(!il.add_ignore("TROLL"));
    }

    #[test]
    fn test_remove_ignore() {
        let mut il = IgnoreList::new();
        il.add_ignore("Spammer");
        assert!(il.remove_ignore("spammer"));
        assert!(!il.is_ignored("Spammer"));
    }

    #[test]
    fn test_ignore_list_capacity() {
        let mut il = IgnoreList::new();
        for i in 0..MAX_IGNORES {
            assert!(il.add_ignore(&format!("bad{}", i)));
        }
        assert!(!il.add_ignore("overflow"));
        assert_eq!(il.ignored_list().len(), MAX_IGNORES);
    }

    // -- Privacy / messaging tests ------------------------------------------

    #[test]
    fn test_can_message_allowed() {
        let il = IgnoreList::new();
        let fl = FriendsList::new();
        let ps = PrivacySettings::default();
        assert!(SocialManager::can_message("Sender", "Recipient", &il, &fl, &ps));
    }

    #[test]
    fn test_can_message_blocked_by_ignore() {
        let mut il = IgnoreList::new();
        il.add_ignore("Sender");
        let fl = FriendsList::new();
        let ps = PrivacySettings::default();
        assert!(!SocialManager::can_message("Sender", "Recipient", &il, &fl, &ps));
    }

    #[test]
    fn test_can_message_blocked_by_privacy() {
        let il = IgnoreList::new();
        let fl = FriendsList::new();
        let ps = PrivacySettings {
            block_private: true,
            ..Default::default()
        };
        assert!(!SocialManager::can_message("Stranger", "Recipient", &il, &fl, &ps));
    }

    #[test]
    fn test_can_message_friend_bypasses_privacy() {
        let il = IgnoreList::new();
        let mut fl = FriendsList::new();
        fl.add_friend("TrustedFriend");
        let ps = PrivacySettings {
            block_private: true,
            ..Default::default()
        };
        assert!(SocialManager::can_message("TrustedFriend", "Recipient", &il, &fl, &ps));
    }

    #[test]
    fn test_can_trade_blocked() {
        let mut il = IgnoreList::new();
        il.add_ignore("Scammer");
        let ps = PrivacySettings::default();
        assert!(!SocialManager::can_trade("Scammer", &il, &ps));
    }

    #[test]
    fn test_can_trade_blocked_by_setting() {
        let il = IgnoreList::new();
        let ps = PrivacySettings {
            block_trade: true,
            ..Default::default()
        };
        assert!(!SocialManager::can_trade("Anyone", &il, &ps));
    }

    #[test]
    fn test_can_duel_blocked() {
        let il = IgnoreList::new();
        let ps = PrivacySettings {
            block_duel: true,
            ..Default::default()
        };
        assert!(!SocialManager::can_duel("Challenger", &il, &ps));
    }

    // -- Packet builder tests -----------------------------------------------

    #[test]
    fn test_friend_list_packet() {
        let friends = vec![
            ("Alice".to_string(), true),
            ("Bob".to_string(), false),
        ];
        let packet = build_friend_list_packet(&friends);
        assert_eq!(packet.opcode, OpcodeOut::FriendList as u8);

        let mut reader = PacketReader::new(&packet);
        let count = reader.read_short().unwrap();
        assert_eq!(count, 2);

        assert_eq!(reader.read_string().unwrap(), "Alice");
        assert_eq!(reader.read_byte().unwrap(), 1);
        assert_eq!(reader.read_string().unwrap(), "Bob");
        assert_eq!(reader.read_byte().unwrap(), 0);
    }

    #[test]
    fn test_friend_update_packet() {
        let packet = build_friend_update_packet("Charlie", true);
        assert_eq!(packet.opcode, OpcodeOut::FriendUpdate as u8);

        let mut reader = PacketReader::new(&packet);
        assert_eq!(reader.read_string().unwrap(), "Charlie");
        assert_eq!(reader.read_byte().unwrap(), 1);
    }

    #[test]
    fn test_ignore_list_packet() {
        let ignored = vec!["Troll".to_string(), "Spammer".to_string()];
        let packet = build_ignore_list_packet(&ignored);
        assert_eq!(packet.opcode, OpcodeOut::IgnoreList as u8);

        let mut reader = PacketReader::new(&packet);
        let count = reader.read_short().unwrap();
        assert_eq!(count, 2);
        assert_eq!(reader.read_string().unwrap(), "Troll");
        assert_eq!(reader.read_string().unwrap(), "Spammer");
    }
}
