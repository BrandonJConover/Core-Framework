//! Duel system for player vs player stakes.
//! Handles duel requests, rules, stakes, and combat resolution.

use std::collections::HashMap;
use tracing::{debug, info};

use super::item::ItemId;

/// Duel settings/rules.
#[derive(Debug, Clone, Default)]
pub struct DuelRules {
    /// No retreating allowed.
    pub no_retreat: bool,
    /// No magic allowed.
    pub no_magic: bool,
    /// No prayer allowed.
    pub no_prayer: bool,
    /// No weapons allowed.
    pub no_weapons: bool,
    /// No ranged allowed.
    pub no_ranged: bool,
}

impl DuelRules {
    /// Create default rules (all allowed).
    pub fn new() -> Self {
        Self::default()
    }

    /// Toggle a rule by index.
    pub fn toggle(&mut self, index: u8) {
        match index {
            0 => self.no_retreat = !self.no_retreat,
            1 => self.no_magic = !self.no_magic,
            2 => self.no_prayer = !self.no_prayer,
            3 => self.no_weapons = !self.no_weapons,
            4 => self.no_ranged = !self.no_ranged,
            _ => {}
        }
    }

    /// Set a specific rule.
    pub fn set(&mut self, index: u8, value: bool) {
        match index {
            0 => self.no_retreat = value,
            1 => self.no_magic = value,
            2 => self.no_prayer = value,
            3 => self.no_weapons = value,
            4 => self.no_ranged = value,
            _ => {}
        }
    }

    /// Check if rules match another set.
    pub fn matches(&self, other: &DuelRules) -> bool {
        self.no_retreat == other.no_retreat
            && self.no_magic == other.no_magic
            && self.no_prayer == other.no_prayer
            && self.no_weapons == other.no_weapons
            && self.no_ranged == other.no_ranged
    }
}

/// Item staked in a duel.
#[derive(Debug, Clone)]
pub struct StakedItem {
    pub item_id: ItemId,
    pub amount: u32,
}

impl StakedItem {
    pub fn new(item_id: ItemId, amount: u32) -> Self {
        Self { item_id, amount }
    }
}

/// Duel state machine.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DuelState {
    /// No active duel.
    None,
    /// Duel request sent, waiting for response.
    RequestSent,
    /// Duel request received, can accept.
    RequestReceived,
    /// Negotiating stakes and rules.
    Negotiating,
    /// Player has accepted current terms.
    Accepted,
    /// Both accepted, duel is active.
    Active,
    /// Duel finished, determining winner.
    Finished,
}

/// A duel session between two players.
#[derive(Debug, Clone)]
pub struct DuelSession {
    /// First player ID.
    pub player1_id: u64,
    /// Second player ID.
    pub player2_id: u64,
    /// Player 1's state.
    pub player1_state: DuelState,
    /// Player 2's state.
    pub player2_state: DuelState,
    /// Player 1's staked items.
    pub player1_stakes: Vec<StakedItem>,
    /// Player 2's staked items.
    pub player2_stakes: Vec<StakedItem>,
    /// Duel rules.
    pub rules: DuelRules,
    /// Whether player 1 accepted rules.
    pub player1_accepted_rules: bool,
    /// Whether player 2 accepted rules.
    pub player2_accepted_rules: bool,
    /// Winner player ID (after duel ends).
    pub winner_id: Option<u64>,
    /// Tick when duel started.
    pub start_tick: u64,
}

impl DuelSession {
    /// Create a new duel session.
    pub fn new(player1_id: u64, player2_id: u64, current_tick: u64) -> Self {
        Self {
            player1_id,
            player2_id,
            player1_state: DuelState::Negotiating,
            player2_state: DuelState::Negotiating,
            player1_stakes: Vec::new(),
            player2_stakes: Vec::new(),
            rules: DuelRules::new(),
            player1_accepted_rules: false,
            player2_accepted_rules: false,
            winner_id: None,
            start_tick: current_tick,
        }
    }

    /// Get player state.
    pub fn get_state(&self, player_id: u64) -> DuelState {
        if player_id == self.player1_id {
            self.player1_state
        } else if player_id == self.player2_id {
            self.player2_state
        } else {
            DuelState::None
        }
    }

    /// Set player state.
    pub fn set_state(&mut self, player_id: u64, state: DuelState) {
        if player_id == self.player1_id {
            self.player1_state = state;
        } else if player_id == self.player2_id {
            self.player2_state = state;
        }
    }

    /// Get opponent ID.
    pub fn get_opponent(&self, player_id: u64) -> Option<u64> {
        if player_id == self.player1_id {
            Some(self.player2_id)
        } else if player_id == self.player2_id {
            Some(self.player1_id)
        } else {
            None
        }
    }

    /// Add stake for a player.
    pub fn add_stake(&mut self, player_id: u64, item: StakedItem) {
        // Reset accepted states when stakes change
        self.player1_accepted_rules = false;
        self.player2_accepted_rules = false;

        if player_id == self.player1_id {
            self.player1_stakes.push(item);
        } else if player_id == self.player2_id {
            self.player2_stakes.push(item);
        }
    }

    /// Clear stakes for a player.
    pub fn clear_stakes(&mut self, player_id: u64) {
        self.player1_accepted_rules = false;
        self.player2_accepted_rules = false;

        if player_id == self.player1_id {
            self.player1_stakes.clear();
        } else if player_id == self.player2_id {
            self.player2_stakes.clear();
        }
    }

    /// Get stakes for a player.
    pub fn get_stakes(&self, player_id: u64) -> &[StakedItem] {
        if player_id == self.player1_id {
            &self.player1_stakes
        } else if player_id == self.player2_id {
            &self.player2_stakes
        } else {
            &[]
        }
    }

    /// Get opponent's stakes.
    pub fn get_opponent_stakes(&self, player_id: u64) -> &[StakedItem] {
        if player_id == self.player1_id {
            &self.player2_stakes
        } else if player_id == self.player2_id {
            &self.player1_stakes
        } else {
            &[]
        }
    }

    /// Toggle a rule.
    pub fn toggle_rule(&mut self, index: u8) {
        self.rules.toggle(index);
        self.player1_accepted_rules = false;
        self.player2_accepted_rules = false;
    }

    /// Accept current terms.
    pub fn accept(&mut self, player_id: u64) {
        if player_id == self.player1_id {
            self.player1_accepted_rules = true;
            self.player1_state = DuelState::Accepted;
        } else if player_id == self.player2_id {
            self.player2_accepted_rules = true;
            self.player2_state = DuelState::Accepted;
        }
    }

    /// Check if both players accepted.
    pub fn both_accepted(&self) -> bool {
        self.player1_accepted_rules && self.player2_accepted_rules
    }

    /// Start the duel combat.
    pub fn start_combat(&mut self) {
        self.player1_state = DuelState::Active;
        self.player2_state = DuelState::Active;
        info!(
            "Duel started between {} and {}",
            self.player1_id, self.player2_id
        );
    }

    /// End the duel with a winner.
    pub fn end(&mut self, winner_id: u64) {
        self.winner_id = Some(winner_id);
        self.player1_state = DuelState::Finished;
        self.player2_state = DuelState::Finished;
        info!("Duel ended, winner: {}", winner_id);
    }

    /// Get all stakes to award to winner.
    pub fn all_stakes(&self) -> Vec<StakedItem> {
        let mut all = Vec::new();
        all.extend(self.player1_stakes.clone());
        all.extend(self.player2_stakes.clone());
        all
    }

    /// Check if duel is active.
    pub fn is_active(&self) -> bool {
        self.player1_state == DuelState::Active && self.player2_state == DuelState::Active
    }

    /// Check if player is in this duel.
    pub fn contains_player(&self, player_id: u64) -> bool {
        player_id == self.player1_id || player_id == self.player2_id
    }
}

/// Manager for all duels.
#[derive(Debug, Default)]
pub struct DuelManager {
    /// Active duel sessions by player ID.
    sessions: HashMap<u64, DuelSession>,
    /// Pending duel requests (requester -> target).
    pending_requests: HashMap<u64, u64>,
}

impl DuelManager {
    /// Create a new duel manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Send a duel request.
    pub fn request_duel(&mut self, requester_id: u64, target_id: u64) -> DuelResult {
        // Check if either player is already in a duel
        if self.sessions.contains_key(&requester_id) {
            return DuelResult::AlreadyDueling;
        }
        if self.sessions.contains_key(&target_id) {
            return DuelResult::TargetBusy;
        }

        // Check for cross-request (target also requested this player)
        if self.pending_requests.get(&target_id) == Some(&requester_id) {
            // Both requested each other, start negotiation
            self.pending_requests.remove(&target_id);
            return self.start_negotiation(requester_id, target_id, 0);
        }

        // Add pending request
        self.pending_requests.insert(requester_id, target_id);
        debug!("Duel request: {} -> {}", requester_id, target_id);
        DuelResult::RequestSent
    }

    /// Accept a duel request.
    pub fn accept_request(
        &mut self,
        player_id: u64,
        requester_id: u64,
        current_tick: u64,
    ) -> DuelResult {
        // Check if there's a pending request from requester to player
        if self.pending_requests.get(&requester_id) != Some(&player_id) {
            return DuelResult::NoRequest;
        }

        self.pending_requests.remove(&requester_id);
        self.start_negotiation(requester_id, player_id, current_tick)
    }

    /// Decline a duel request.
    pub fn decline_request(&mut self, player_id: u64, requester_id: u64) -> DuelResult {
        if self.pending_requests.get(&requester_id) == Some(&player_id) {
            self.pending_requests.remove(&requester_id);
            DuelResult::Declined
        } else {
            DuelResult::NoRequest
        }
    }

    /// Start negotiation phase.
    fn start_negotiation(
        &mut self,
        player1_id: u64,
        player2_id: u64,
        current_tick: u64,
    ) -> DuelResult {
        let session = DuelSession::new(player1_id, player2_id, current_tick);

        self.sessions.insert(player1_id, session.clone());
        self.sessions.insert(player2_id, session);

        info!("Duel negotiation started: {} vs {}", player1_id, player2_id);
        DuelResult::NegotiationStarted
    }

    /// Get session for a player.
    pub fn get_session(&self, player_id: u64) -> Option<&DuelSession> {
        self.sessions.get(&player_id)
    }

    /// Get mutable session for a player.
    pub fn get_session_mut(&mut self, player_id: u64) -> Option<&mut DuelSession> {
        self.sessions.get_mut(&player_id)
    }

    /// Accept current duel terms.
    pub fn accept_terms(&mut self, player_id: u64) -> DuelResult {
        // Need to update both player's copies of the session
        let (opponent_id, should_start) = {
            if let Some(session) = self.sessions.get_mut(&player_id) {
                session.accept(player_id);
                let opponent = session.get_opponent(player_id).unwrap();
                let should_start = session.both_accepted();
                (opponent, should_start)
            } else {
                return DuelResult::NotInDuel;
            }
        };

        // Sync to opponent's session copy
        if let Some(opponent_session) = self.sessions.get_mut(&opponent_id) {
            opponent_session.accept(player_id);
            if should_start {
                opponent_session.start_combat();
            }
        }

        if should_start {
            if let Some(session) = self.sessions.get_mut(&player_id) {
                session.start_combat();
            }
            DuelResult::DuelStarted
        } else {
            DuelResult::Accepted
        }
    }

    /// End a duel with winner.
    pub fn end_duel(&mut self, player_id: u64, winner_id: u64) -> Option<DuelSession> {
        let session = self.sessions.get(&player_id)?.clone();
        let opponent_id = session.get_opponent(player_id)?;

        // Remove both players' sessions
        self.sessions.remove(&player_id);
        let mut final_session = self.sessions.remove(&opponent_id)?;

        final_session.end(winner_id);
        Some(final_session)
    }

    /// Cancel/abort a duel.
    pub fn cancel_duel(&mut self, player_id: u64) -> DuelResult {
        if let Some(session) = self.sessions.remove(&player_id) {
            if let Some(opponent_id) = session.get_opponent(player_id) {
                self.sessions.remove(&opponent_id);
            }
            DuelResult::Cancelled
        } else {
            // Check for pending request
            if self.pending_requests.remove(&player_id).is_some() {
                DuelResult::Cancelled
            } else {
                DuelResult::NotInDuel
            }
        }
    }

    /// Check if player has pending request.
    pub fn has_request_from(&self, player_id: u64, requester_id: u64) -> bool {
        self.pending_requests.get(&requester_id) == Some(&player_id)
    }
}

/// Result of duel operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DuelResult {
    /// Duel request sent.
    RequestSent,
    /// Duel negotiation started.
    NegotiationStarted,
    /// Player already in a duel.
    AlreadyDueling,
    /// Target is busy.
    TargetBusy,
    /// No pending request.
    NoRequest,
    /// Request declined.
    Declined,
    /// Terms accepted by one player.
    Accepted,
    /// Duel combat started.
    DuelStarted,
    /// Duel cancelled.
    Cancelled,
    /// Player not in duel.
    NotInDuel,
    /// Duel finished.
    Finished,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_duel_request() {
        let mut manager = DuelManager::new();

        // Player 1 requests duel with player 2
        let result = manager.request_duel(1, 2);
        assert_eq!(result, DuelResult::RequestSent);

        // Player 2 accepts
        let result = manager.accept_request(2, 1, 0);
        assert_eq!(result, DuelResult::NegotiationStarted);

        // Both should have sessions
        assert!(manager.get_session(1).is_some());
        assert!(manager.get_session(2).is_some());
    }

    #[test]
    fn test_cross_request() {
        let mut manager = DuelManager::new();

        // Both players request each other
        manager.request_duel(1, 2);
        let result = manager.request_duel(2, 1);

        // Should automatically start negotiation
        assert_eq!(result, DuelResult::NegotiationStarted);
    }

    #[test]
    fn test_duel_terms() {
        let mut manager = DuelManager::new();

        manager.request_duel(1, 2);
        manager.accept_request(2, 1, 0);

        // Add stakes
        if let Some(session) = manager.get_session_mut(1) {
            session.add_stake(1, StakedItem::new(ItemId(10), 1000));
        }

        // Accept terms
        manager.accept_terms(1);
        assert_eq!(
            manager.get_session(1).unwrap().player1_state,
            DuelState::Accepted
        );

        // Player 2 accepts - duel should start
        let result = manager.accept_terms(2);
        assert_eq!(result, DuelResult::DuelStarted);
    }

    #[test]
    fn test_duel_rules() {
        let mut rules = DuelRules::new();

        assert!(!rules.no_retreat);
        rules.toggle(0);
        assert!(rules.no_retreat);

        rules.set(1, true);
        assert!(rules.no_magic);
    }
}
