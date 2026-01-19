//! Chat and messaging system.
//! Handles player chat, private messages, and system messages.

use std::collections::{HashMap, HashSet, VecDeque};
use std::time::Instant;
use tracing::{debug, info, warn};

/// Maximum message length.
pub const MAX_MESSAGE_LENGTH: usize = 80;

/// Chat message types.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageType {
    /// Regular public chat.
    Public,
    /// Private message.
    Private,
    /// Clan/guild chat.
    Clan,
    /// Party chat.
    Party,
    /// System/quest message.
    System,
    /// Trade/duel message.
    Trade,
    /// Global announcement.
    Global,
}

/// Chat message colors.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageColor {
    White,
    Cyan,
    Yellow,
    Red,
    Green,
    Orange,
    Magenta,
    Custom(u8, u8, u8),
}

impl MessageColor {
    /// Get RSC color code.
    pub fn code(&self) -> &'static str {
        match self {
            MessageColor::White => "@whi@",
            MessageColor::Cyan => "@cya@",
            MessageColor::Yellow => "@yel@",
            MessageColor::Red => "@red@",
            MessageColor::Green => "@gre@",
            MessageColor::Orange => "@ora@",
            MessageColor::Magenta => "@mag@",
            MessageColor::Custom(_, _, _) => "",
        }
    }
}

/// A chat message.
#[derive(Debug, Clone)]
pub struct ChatMessage {
    /// Message content.
    pub content: String,
    /// Message type.
    pub message_type: MessageType,
    /// Sender player ID (None for system).
    pub sender_id: Option<u64>,
    /// Sender username.
    pub sender_name: String,
    /// Target player ID (for private messages).
    pub target_id: Option<u64>,
    /// When the message was sent.
    pub timestamp: u64,
}

impl ChatMessage {
    /// Create a public chat message.
    pub fn public(sender_id: u64, sender_name: &str, content: &str, tick: u64) -> Self {
        Self {
            content: sanitize_message(content),
            message_type: MessageType::Public,
            sender_id: Some(sender_id),
            sender_name: sender_name.to_string(),
            target_id: None,
            timestamp: tick,
        }
    }

    /// Create a private message.
    pub fn private(
        sender_id: u64,
        sender_name: &str,
        target_id: u64,
        content: &str,
        tick: u64,
    ) -> Self {
        Self {
            content: sanitize_message(content),
            message_type: MessageType::Private,
            sender_id: Some(sender_id),
            sender_name: sender_name.to_string(),
            target_id: Some(target_id),
            timestamp: tick,
        }
    }

    /// Create a system message.
    pub fn system(content: &str, tick: u64) -> Self {
        Self {
            content: content.to_string(),
            message_type: MessageType::System,
            sender_id: None,
            sender_name: "System".to_string(),
            target_id: None,
            timestamp: tick,
        }
    }

    /// Create a global announcement.
    pub fn global(content: &str, tick: u64) -> Self {
        Self {
            content: content.to_string(),
            message_type: MessageType::Global,
            sender_id: None,
            sender_name: "Server".to_string(),
            target_id: None,
            timestamp: tick,
        }
    }
}

/// Sanitize a chat message.
fn sanitize_message(content: &str) -> String {
    let mut sanitized = String::with_capacity(content.len().min(MAX_MESSAGE_LENGTH));

    for ch in content.chars().take(MAX_MESSAGE_LENGTH) {
        if ch.is_ascii_graphic() || ch == ' ' {
            sanitized.push(ch);
        }
    }

    sanitized
}

/// Player's friend list.
#[derive(Debug, Clone, Default)]
pub struct FriendList {
    /// Friends by username hash.
    friends: HashSet<u64>,
    /// Maximum friends.
    max_friends: usize,
}

impl FriendList {
    /// Create a new friend list.
    pub fn new(max_friends: usize) -> Self {
        Self {
            friends: HashSet::new(),
            max_friends,
        }
    }

    /// Add a friend.
    pub fn add(&mut self, username_hash: u64) -> bool {
        if self.friends.len() >= self.max_friends {
            return false;
        }
        self.friends.insert(username_hash)
    }

    /// Remove a friend.
    pub fn remove(&mut self, username_hash: u64) -> bool {
        self.friends.remove(&username_hash)
    }

    /// Check if someone is a friend.
    pub fn contains(&self, username_hash: u64) -> bool {
        self.friends.contains(&username_hash)
    }

    /// Get all friends.
    pub fn all(&self) -> impl Iterator<Item = &u64> {
        self.friends.iter()
    }

    /// Get friend count.
    pub fn count(&self) -> usize {
        self.friends.len()
    }

    /// Check if full.
    pub fn is_full(&self) -> bool {
        self.friends.len() >= self.max_friends
    }
}

/// Player's ignore list.
#[derive(Debug, Clone, Default)]
pub struct IgnoreList {
    /// Ignored players by username hash.
    ignored: HashSet<u64>,
    /// Maximum ignored.
    max_ignored: usize,
}

impl IgnoreList {
    /// Create a new ignore list.
    pub fn new(max_ignored: usize) -> Self {
        Self {
            ignored: HashSet::new(),
            max_ignored,
        }
    }

    /// Add to ignore list.
    pub fn add(&mut self, username_hash: u64) -> bool {
        if self.ignored.len() >= self.max_ignored {
            return false;
        }
        self.ignored.insert(username_hash)
    }

    /// Remove from ignore list.
    pub fn remove(&mut self, username_hash: u64) -> bool {
        self.ignored.remove(&username_hash)
    }

    /// Check if someone is ignored.
    pub fn is_ignored(&self, username_hash: u64) -> bool {
        self.ignored.contains(&username_hash)
    }

    /// Get count.
    pub fn count(&self) -> usize {
        self.ignored.len()
    }
}

/// Privacy settings for a player.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PrivacySetting {
    /// Visible/accepts from everyone.
    Everyone,
    /// Visible/accepts from friends only.
    FriendsOnly,
    /// Hidden/accepts from no one.
    Nobody,
}

/// Player's privacy settings.
#[derive(Debug, Clone)]
pub struct PrivacySettings {
    /// Public chat setting.
    pub public_chat: PrivacySetting,
    /// Private message setting.
    pub private_chat: PrivacySetting,
    /// Trade request setting.
    pub trade_requests: PrivacySetting,
    /// Duel request setting.
    pub duel_requests: PrivacySetting,
}

impl Default for PrivacySettings {
    fn default() -> Self {
        Self {
            public_chat: PrivacySetting::Everyone,
            private_chat: PrivacySetting::Everyone,
            trade_requests: PrivacySetting::Everyone,
            duel_requests: PrivacySetting::Everyone,
        }
    }
}

impl PrivacySettings {
    /// Check if can receive private messages from a player.
    pub fn can_receive_pm(&self, sender_hash: u64, friends: &FriendList) -> bool {
        match self.private_chat {
            PrivacySetting::Everyone => true,
            PrivacySetting::FriendsOnly => friends.contains(sender_hash),
            PrivacySetting::Nobody => false,
        }
    }

    /// Check if can receive trade requests from a player.
    pub fn can_receive_trade(&self, sender_hash: u64, friends: &FriendList) -> bool {
        match self.trade_requests {
            PrivacySetting::Everyone => true,
            PrivacySetting::FriendsOnly => friends.contains(sender_hash),
            PrivacySetting::Nobody => false,
        }
    }
}

/// Chat manager for handling global chat state.
#[derive(Debug, Default)]
pub struct ChatManager {
    /// Recent global messages.
    global_messages: VecDeque<ChatMessage>,
    /// Maximum global message history.
    max_history: usize,
}

impl ChatManager {
    /// Create a new chat manager.
    pub fn new(max_history: usize) -> Self {
        Self {
            global_messages: VecDeque::new(),
            max_history,
        }
    }

    /// Add a global message.
    pub fn add_global(&mut self, message: ChatMessage) {
        if self.global_messages.len() >= self.max_history {
            self.global_messages.pop_front();
        }
        self.global_messages.push_back(message);
    }

    /// Get recent global messages.
    pub fn recent_global(&self, count: usize) -> Vec<&ChatMessage> {
        self.global_messages
            .iter()
            .rev()
            .take(count)
            .collect()
    }

    /// Broadcast announcement.
    pub fn announce(&mut self, content: &str, tick: u64) {
        let msg = ChatMessage::global(content, tick);
        info!("Global announcement: {}", content);
        self.add_global(msg);
    }
}

/// Chat spam filter state.
#[derive(Debug, Clone, Default)]
pub struct SpamFilter {
    /// Recent message hashes with timestamps.
    recent_messages: VecDeque<(u64, u64)>, // (message_hash, tick)
    /// Last message tick.
    last_message_tick: u64,
    /// Consecutive similar messages.
    repeat_count: u32,
    /// Muted until tick.
    muted_until: u64,
}

impl SpamFilter {
    /// Create a new spam filter.
    pub fn new() -> Self {
        Self::default()
    }

    /// Check if a message should be blocked.
    pub fn should_block(&mut self, message: &str, current_tick: u64) -> bool {
        // Check if muted
        if current_tick < self.muted_until {
            return true;
        }

        // Check rate limit (minimum 2 ticks between messages)
        if current_tick < self.last_message_tick + 2 {
            self.repeat_count += 1;
            if self.repeat_count > 5 {
                self.muted_until = current_tick + 100; // Mute for ~1 minute
                warn!("Player muted for spamming");
                return true;
            }
        } else {
            self.repeat_count = 0;
        }

        // Simple hash for duplicate detection
        let hash = message
            .bytes()
            .fold(0u64, |acc, b| acc.wrapping_mul(31).wrapping_add(b as u64));

        // Check for repeated messages
        let duplicate_count = self
            .recent_messages
            .iter()
            .filter(|(h, t)| *h == hash && current_tick - t < 50)
            .count();

        if duplicate_count >= 3 {
            self.muted_until = current_tick + 50;
            return true;
        }

        // Add to recent
        self.recent_messages.push_back((hash, current_tick));
        if self.recent_messages.len() > 10 {
            self.recent_messages.pop_front();
        }

        self.last_message_tick = current_tick;
        false
    }

    /// Check if currently muted.
    pub fn is_muted(&self, current_tick: u64) -> bool {
        current_tick < self.muted_until
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_friend_list() {
        let mut friends = FriendList::new(100);

        assert!(friends.add(12345));
        assert!(friends.contains(12345));
        assert!(!friends.contains(99999));

        assert!(friends.remove(12345));
        assert!(!friends.contains(12345));
    }

    #[test]
    fn test_ignore_list() {
        let mut ignore = IgnoreList::new(100);

        assert!(ignore.add(12345));
        assert!(ignore.is_ignored(12345));
        assert!(!ignore.is_ignored(99999));
    }

    #[test]
    fn test_spam_filter() {
        let mut filter = SpamFilter::new();

        // First message should pass
        assert!(!filter.should_block("Hello", 0));

        // Rapid messages should eventually block
        assert!(!filter.should_block("Hello", 1));
        assert!(!filter.should_block("Hello", 2));
        // After several rapid messages, should block
    }

    #[test]
    fn test_sanitize_message() {
        let result = sanitize_message("Hello World!");
        assert_eq!(result, "Hello World!");

        // Test truncation
        let long = "a".repeat(100);
        let result = sanitize_message(&long);
        assert_eq!(result.len(), MAX_MESSAGE_LENGTH);
    }
}
