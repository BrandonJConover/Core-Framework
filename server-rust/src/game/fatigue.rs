//! Fatigue and Sleep system for RuneScape Classic.
//!
//! Players accumulate fatigue while skilling. Once fatigue reaches maximum,
//! no further experience can be gained until the player sleeps (via a sleeping
//! bag or bed) and correctly solves a CAPTCHA-style sleep word.

use super::protocol::{Packet, ServerOpcode};
use rand::Rng;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Maximum fatigue value (equivalent to 100% fatigue in the client).
pub const MAX_FATIGUE: u32 = 150_000;

/// Dictionary of simple words used for sleep CAPTCHA verification.
/// In authentic RSC the server sends a distorted image of the word; here we
/// keep a representative word list for the server-side answer generation.
pub const SLEEP_WORDS: &[&str] = &[
    "anchor", "apple", "arrow", "axe", "barrel", "basket", "battle", "bell",
    "bird", "blade", "blanket", "bone", "book", "bottle", "bridge", "bucket",
    "butter", "candle", "castle", "chain", "cheese", "chicken", "cloud",
    "cobweb", "coffin", "coin", "comb", "copper", "cotton", "crown", "crystal",
    "danger", "desert", "dragon", "eagle", "earth", "fence", "finger", "fire",
    "flower", "forest", "fountain", "garden", "ghost", "goblin", "gold",
    "grain", "hammer", "helmet", "horse", "island", "jewel", "jungle",
    "king", "knight", "ladder", "leather", "legend", "lemon", "light",
    "lizard", "magic", "market", "mirror", "monkey", "mountain", "mushroom",
    "nature", "needle", "ocean", "onion", "orange", "palace", "pirate",
    "poison", "prince", "pumpkin", "queen", "rabbit", "ranger", "river",
    "rocket", "saddle", "shadow", "shield", "silver", "spider", "spirit",
    "square", "stone", "storm", "stream", "summer", "sunset", "sword",
    "temple", "throne", "tower", "travel", "turtle", "valley", "village",
    "water", "window", "winter", "wizard",
];

// ---------------------------------------------------------------------------
// Fatigue calculation helpers
// ---------------------------------------------------------------------------

/// Calculate fatigue gained for a given amount of XP.
///
/// In RSC the fatigue increase is roughly `xp * 4`.
pub fn fatigue_for_xp(xp_gained: u32) -> u32 {
    xp_gained.saturating_mul(4)
}

// ---------------------------------------------------------------------------
// FatigueManager
// ---------------------------------------------------------------------------

/// Tracks a single player's fatigue level.
#[derive(Debug, Clone)]
pub struct FatigueManager {
    /// Current fatigue value in the range `[0, MAX_FATIGUE]`.
    fatigue: u32,
}

impl FatigueManager {
    /// Create a new manager starting at zero fatigue.
    pub fn new() -> Self {
        Self { fatigue: 0 }
    }

    /// Create a manager with a pre-existing fatigue value (e.g. loaded from DB).
    pub fn with_fatigue(fatigue: u32) -> Self {
        Self {
            fatigue: fatigue.min(MAX_FATIGUE),
        }
    }

    /// Current raw fatigue value.
    pub fn fatigue(&self) -> u32 {
        self.fatigue
    }

    /// Add fatigue from a skilling action.
    /// The value is clamped to `MAX_FATIGUE`.
    pub fn add_fatigue(&mut self, amount: u32) {
        self.fatigue = self.fatigue.saturating_add(amount).min(MAX_FATIGUE);
    }

    /// Returns `true` when fatigue is at the maximum — no more XP should be
    /// awarded until the player sleeps.
    pub fn is_maxed(&self) -> bool {
        self.fatigue >= MAX_FATIGUE
    }

    /// Reset fatigue to zero (called after a successful sleep).
    pub fn reset(&mut self) {
        self.fatigue = 0;
    }

    /// Fatigue expressed as a percentage in the range `[0.0, 100.0]`.
    pub fn get_percentage(&self) -> f32 {
        (self.fatigue as f32 / MAX_FATIGUE as f32) * 100.0
    }
}

impl Default for FatigueManager {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// SleepResult
// ---------------------------------------------------------------------------

/// Outcome of a sleep-word verification attempt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SleepResult {
    /// The answer was correct — fatigue has been reset.
    Success,
    /// The answer was incorrect.
    WrongAnswer,
    /// The player was not sleeping when the answer arrived.
    NotSleeping,
}

// ---------------------------------------------------------------------------
// SleepWordGenerator
// ---------------------------------------------------------------------------

/// Generates random sleep words for the CAPTCHA challenge.
pub struct SleepWordGenerator;

impl SleepWordGenerator {
    /// Pick a random word from the built-in dictionary.
    pub fn generate() -> String {
        let mut rng = rand::thread_rng();
        let index = rng.gen_range(0..SLEEP_WORDS.len());
        SLEEP_WORDS[index].to_string()
    }
}

// ---------------------------------------------------------------------------
// SleepHandler
// ---------------------------------------------------------------------------

/// Manages the sleep interaction for a single player.
///
/// When the player activates a sleeping bag or bed the server:
/// 1. Generates a random word.
/// 2. Sends the sleep-screen packet (client renders a distorted image).
/// 3. Waits for the player's answer.
/// 4. Verifies the answer and either resets fatigue or asks again.
#[derive(Debug, Clone)]
pub struct SleepHandler {
    /// Whether the player is currently on the sleep screen.
    sleeping: bool,
    /// The correct word the player must type.
    sleep_word: Option<String>,
}

impl SleepHandler {
    pub fn new() -> Self {
        Self {
            sleeping: false,
            sleep_word: None,
        }
    }

    /// Whether the player is currently sleeping (on the sleep screen).
    pub fn is_sleeping(&self) -> bool {
        self.sleeping
    }

    /// Begin the sleep interaction.
    ///
    /// Returns a packet that should be sent to the client to display the
    /// sleep screen with the CAPTCHA image word.
    pub fn start_sleep(&mut self) -> Packet {
        let word = SleepWordGenerator::generate();
        let packet = build_sleep_screen_packet(&word);
        self.sleeping = true;
        self.sleep_word = Some(word);
        packet
    }

    /// Verify the player's answer to the sleep CAPTCHA.
    ///
    /// On success the caller should reset fatigue via [`FatigueManager::reset`].
    pub fn verify_sleep(&mut self, answer: &str) -> SleepResult {
        if !self.sleeping {
            return SleepResult::NotSleeping;
        }

        let correct = self
            .sleep_word
            .as_ref()
            .map(|w| w.eq_ignore_ascii_case(answer.trim()))
            .unwrap_or(false);

        if correct {
            self.sleeping = false;
            self.sleep_word = None;
            SleepResult::Success
        } else {
            SleepResult::WrongAnswer
        }
    }

    /// Cancel the sleep (e.g. if the player moves or is attacked).
    pub fn cancel(&mut self) {
        self.sleeping = false;
        self.sleep_word = None;
    }
}

impl Default for SleepHandler {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build a `FatigueUpdate` packet that tells the client the player's current
/// fatigue level.
pub fn build_fatigue_packet(fatigue: u32) -> Packet {
    let mut packet = Packet::new(ServerOpcode::FatigueUpdate as u8);
    // Send fatigue as a short (scaled to 0-750 range the client expects).
    // RSC clients historically use a 0-750 scale.
    let scaled = ((fatigue as u64 * 750) / MAX_FATIGUE as u64) as u16;
    packet.add_short(scaled);
    packet
}

/// Build a `SleepScreen` packet containing the CAPTCHA word.
///
/// In a real implementation the payload would contain the rendered image bytes;
/// here we send the word length followed by the word bytes so the rest of the
/// pipeline can generate the image.
pub fn build_sleep_screen_packet(word: &str) -> Packet {
    let mut packet = Packet::new(ServerOpcode::SleepScreen as u8);
    // Image data placeholder — in production this would be the actual CAPTCHA
    // bitmap. For now we encode the word so the client-image generator can
    // produce a distorted rendering.
    packet.add_byte(word.len() as u8);
    packet.add_bytes(word.as_bytes());
    packet
}

/// Build a `SleepResult` packet indicating the sleep was successful.
pub fn build_sleep_success_packet() -> Packet {
    let mut packet = Packet::new(ServerOpcode::SleepResult as u8);
    // 0 = success
    packet.add_byte(0);
    packet
}

/// Build a `SleepResult` packet indicating the answer was wrong.
pub fn build_sleep_wrong_packet() -> Packet {
    let mut packet = Packet::new(ServerOpcode::SleepResult as u8);
    // 1 = incorrect answer
    packet.add_byte(1);
    packet
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // -- FatigueManager ----------------------------------------------------

    #[test]
    fn test_new_fatigue_is_zero() {
        let fm = FatigueManager::new();
        assert_eq!(fm.fatigue(), 0);
        assert!(!fm.is_maxed());
        assert_eq!(fm.get_percentage(), 0.0);
    }

    #[test]
    fn test_add_fatigue() {
        let mut fm = FatigueManager::new();
        fm.add_fatigue(50_000);
        assert_eq!(fm.fatigue(), 50_000);
        assert!(!fm.is_maxed());
    }

    #[test]
    fn test_fatigue_clamps_at_max() {
        let mut fm = FatigueManager::new();
        fm.add_fatigue(200_000);
        assert_eq!(fm.fatigue(), MAX_FATIGUE);
        assert!(fm.is_maxed());
    }

    #[test]
    fn test_fatigue_percentage() {
        let fm = FatigueManager::with_fatigue(75_000);
        let pct = fm.get_percentage();
        assert!((pct - 50.0).abs() < 0.01);
    }

    #[test]
    fn test_fatigue_reset() {
        let mut fm = FatigueManager::with_fatigue(100_000);
        fm.reset();
        assert_eq!(fm.fatigue(), 0);
        assert!(!fm.is_maxed());
    }

    #[test]
    fn test_with_fatigue_clamps() {
        let fm = FatigueManager::with_fatigue(999_999);
        assert_eq!(fm.fatigue(), MAX_FATIGUE);
    }

    // -- fatigue_for_xp ----------------------------------------------------

    #[test]
    fn test_fatigue_for_xp() {
        assert_eq!(fatigue_for_xp(0), 0);
        assert_eq!(fatigue_for_xp(10), 40);
        assert_eq!(fatigue_for_xp(100), 400);
    }

    #[test]
    fn test_fatigue_for_xp_no_overflow() {
        // Should saturate instead of overflowing.
        assert_eq!(fatigue_for_xp(u32::MAX), u32::MAX);
    }

    // -- SleepWordGenerator ------------------------------------------------

    #[test]
    fn test_sleep_word_generator_returns_known_word() {
        let word = SleepWordGenerator::generate();
        assert!(
            SLEEP_WORDS.contains(&word.as_str()),
            "Generated word '{}' not in dictionary",
            word
        );
    }

    // -- SleepHandler ------------------------------------------------------

    #[test]
    fn test_sleep_flow_success() {
        let mut handler = SleepHandler::new();
        assert!(!handler.is_sleeping());

        let _packet = handler.start_sleep();
        assert!(handler.is_sleeping());

        // Extract the correct word.
        let word = handler.sleep_word.clone().unwrap();

        let result = handler.verify_sleep(&word);
        assert_eq!(result, SleepResult::Success);
        assert!(!handler.is_sleeping());
    }

    #[test]
    fn test_sleep_flow_wrong_answer() {
        let mut handler = SleepHandler::new();
        let _packet = handler.start_sleep();

        let result = handler.verify_sleep("definitelywrong");
        assert_eq!(result, SleepResult::WrongAnswer);
        // Player is still sleeping — they can try again.
        assert!(handler.is_sleeping());
    }

    #[test]
    fn test_sleep_case_insensitive() {
        let mut handler = SleepHandler::new();
        let _packet = handler.start_sleep();

        let word = handler.sleep_word.clone().unwrap().to_uppercase();
        let result = handler.verify_sleep(&word);
        assert_eq!(result, SleepResult::Success);
    }

    #[test]
    fn test_verify_when_not_sleeping() {
        let mut handler = SleepHandler::new();
        let result = handler.verify_sleep("anything");
        assert_eq!(result, SleepResult::NotSleeping);
    }

    #[test]
    fn test_cancel_sleep() {
        let mut handler = SleepHandler::new();
        handler.start_sleep();
        assert!(handler.is_sleeping());

        handler.cancel();
        assert!(!handler.is_sleeping());
        assert!(handler.sleep_word.is_none());
    }

    // -- Packet builders ---------------------------------------------------

    #[test]
    fn test_build_fatigue_packet() {
        let packet = build_fatigue_packet(MAX_FATIGUE);
        assert_eq!(packet.opcode, ServerOpcode::FatigueUpdate as u8);
        // Payload should be a 2-byte short with value 750.
        assert_eq!(packet.payload.len(), 2);
        let value = ((packet.payload[0] as u16) << 8) | (packet.payload[1] as u16);
        assert_eq!(value, 750);
    }

    #[test]
    fn test_build_fatigue_packet_zero() {
        let packet = build_fatigue_packet(0);
        let value = ((packet.payload[0] as u16) << 8) | (packet.payload[1] as u16);
        assert_eq!(value, 0);
    }

    #[test]
    fn test_build_sleep_screen_packet() {
        let packet = build_sleep_screen_packet("sword");
        assert_eq!(packet.opcode, ServerOpcode::SleepScreen as u8);
        assert_eq!(packet.payload[0], 5); // word length
        assert_eq!(&packet.payload[1..], b"sword");
    }

    #[test]
    fn test_build_sleep_success_packet() {
        let packet = build_sleep_success_packet();
        assert_eq!(packet.opcode, ServerOpcode::SleepResult as u8);
        assert_eq!(packet.payload, vec![0]);
    }

    #[test]
    fn test_build_sleep_wrong_packet() {
        let packet = build_sleep_wrong_packet();
        assert_eq!(packet.opcode, ServerOpcode::SleepResult as u8);
        assert_eq!(packet.payload, vec![1]);
    }

    // -- Default impls -----------------------------------------------------

    #[test]
    fn test_fatigue_manager_default() {
        let fm = FatigueManager::default();
        assert_eq!(fm.fatigue(), 0);
    }

    #[test]
    fn test_sleep_handler_default() {
        let handler = SleepHandler::default();
        assert!(!handler.is_sleeping());
    }
}
dler.is_sleeping());
    }
}
