//! Trading system for player-to-player item trades.
//!
//! Implements a secure two-stage confirmation trading system.

use std::collections::HashMap;
use std::time::{Duration, Instant};
use serde::{Deserialize, Serialize};
use tracing::{info, warn, debug};

/// Item in a trade offer.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TradeItem {
    pub item_id: u32,
    pub amount: u32,
    pub noted: bool,
}

/// State of a trade session.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TradeState {
    /// Trade request sent, waiting for response.
    Requesting,
    /// Both players in trade screen, modifying offers.
    InProgress,
    /// First stage confirmation (reviewing offers).
    Confirming,
    /// Second stage confirmation (final accept).
    FinalConfirm,
    /// Trade completed successfully.
    Completed,
    /// Trade was declined or cancelled.
    Cancelled,
}

/// A trade session between two players.
#[derive(Debug)]
pub struct TradeSession {
    pub id: u64,
    pub player1_id: u64,
    pub player2_id: u64,
    pub player1_offer: Vec<TradeItem>,
    pub player2_offer: Vec<TradeItem>,
    pub player1_accepted: bool,
    pub player2_accepted: bool,
    pub player1_confirmed: bool,
    pub player2_confirmed: bool,
    pub state: TradeState,
    pub created_at: Instant,
    pub last_modified: Instant,
}

impl TradeSession {
    pub fn new(id: u64, initiator_id: u64, target_id: u64) -> Self {
        let now = Instant::now();
        Self {
            id,
            player1_id: initiator_id,
            player2_id: target_id,
            player1_offer: Vec::new(),
            player2_offer: Vec::new(),
            player1_accepted: false,
            player2_accepted: false,
            player1_confirmed: false,
            player2_confirmed: false,
            state: TradeState::Requesting,
            created_at: now,
            last_modified: now,
        }
    }

    /// Accept the trade request (move from Requesting to InProgress).
    pub fn accept_request(&mut self) -> Result<(), TradeError> {
        if self.state != TradeState::Requesting {
            return Err(TradeError::InvalidState);
        }
        self.state = TradeState::InProgress;
        self.last_modified = Instant::now();
        Ok(())
    }

    /// Add an item to a player's offer.
    pub fn add_item(&mut self, player_id: u64, item: TradeItem) -> Result<(), TradeError> {
        if self.state != TradeState::InProgress {
            return Err(TradeError::InvalidState);
        }

        // Reset confirmations when offer changes
        self.player1_accepted = false;
        self.player2_accepted = false;
        self.last_modified = Instant::now();

        let offer = if player_id == self.player1_id {
            &mut self.player1_offer
        } else if player_id == self.player2_id {
            &mut self.player2_offer
        } else {
            return Err(TradeError::NotInTrade);
        };

        // Check if same item already in offer (stack if possible)
        if let Some(existing) = offer.iter_mut().find(|i| i.item_id == item.item_id && i.noted == item.noted) {
            existing.amount = existing.amount.saturating_add(item.amount);
        } else {
            if offer.len() >= 12 {
                return Err(TradeError::OfferFull);
            }
            offer.push(item);
        }

        Ok(())
    }

    /// Remove an item from a player's offer.
    pub fn remove_item(&mut self, player_id: u64, item_id: u32, amount: u32) -> Result<TradeItem, TradeError> {
        if self.state != TradeState::InProgress {
            return Err(TradeError::InvalidState);
        }

        // Reset confirmations when offer changes
        self.player1_accepted = false;
        self.player2_accepted = false;
        self.last_modified = Instant::now();

        let offer = if player_id == self.player1_id {
            &mut self.player1_offer
        } else if player_id == self.player2_id {
            &mut self.player2_offer
        } else {
            return Err(TradeError::NotInTrade);
        };

        let pos = offer.iter().position(|i| i.item_id == item_id)
            .ok_or(TradeError::ItemNotInOffer)?;

        let item = &mut offer[pos];
        if amount >= item.amount {
            Ok(offer.remove(pos))
        } else {
            item.amount -= amount;
            Ok(TradeItem {
                item_id,
                amount,
                noted: item.noted,
            })
        }
    }

    /// Player accepts their current offer (first stage).
    pub fn accept(&mut self, player_id: u64) -> Result<bool, TradeError> {
        if self.state != TradeState::InProgress {
            return Err(TradeError::InvalidState);
        }

        self.last_modified = Instant::now();

        if player_id == self.player1_id {
            self.player1_accepted = true;
        } else if player_id == self.player2_id {
            self.player2_accepted = true;
        } else {
            return Err(TradeError::NotInTrade);
        }

        // If both accepted, move to confirmation
        if self.player1_accepted && self.player2_accepted {
            self.state = TradeState::Confirming;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Player confirms the trade (second stage).
    pub fn confirm(&mut self, player_id: u64) -> Result<bool, TradeError> {
        if self.state != TradeState::Confirming {
            return Err(TradeError::InvalidState);
        }

        self.last_modified = Instant::now();

        if player_id == self.player1_id {
            self.player1_confirmed = true;
        } else if player_id == self.player2_id {
            self.player2_confirmed = true;
        } else {
            return Err(TradeError::NotInTrade);
        }

        // If both confirmed, trade is complete
        if self.player1_confirmed && self.player2_confirmed {
            self.state = TradeState::Completed;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Decline the trade.
    pub fn decline(&mut self, player_id: u64) -> Result<(), TradeError> {
        if !self.is_participant(player_id) {
            return Err(TradeError::NotInTrade);
        }

        if self.state == TradeState::Completed || self.state == TradeState::Cancelled {
            return Err(TradeError::InvalidState);
        }

        self.state = TradeState::Cancelled;
        self.last_modified = Instant::now();
        Ok(())
    }

    /// Check if a player is part of this trade.
    pub fn is_participant(&self, player_id: u64) -> bool {
        player_id == self.player1_id || player_id == self.player2_id
    }

    /// Get the other player in the trade.
    pub fn other_player(&self, player_id: u64) -> Option<u64> {
        if player_id == self.player1_id {
            Some(self.player2_id)
        } else if player_id == self.player2_id {
            Some(self.player1_id)
        } else {
            None
        }
    }

    /// Get a player's offer.
    pub fn get_offer(&self, player_id: u64) -> Option<&[TradeItem]> {
        if player_id == self.player1_id {
            Some(&self.player1_offer)
        } else if player_id == self.player2_id {
            Some(&self.player2_offer)
        } else {
            None
        }
    }

    /// Check if trade has timed out.
    pub fn is_timed_out(&self) -> bool {
        match self.state {
            TradeState::Requesting => self.created_at.elapsed() > Duration::from_secs(60),
            TradeState::InProgress | TradeState::Confirming => {
                self.last_modified.elapsed() > Duration::from_secs(180)
            }
            _ => false,
        }
    }
}

/// Trade-related errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TradeError {
    InvalidState,
    NotInTrade,
    AlreadyTrading,
    PlayerNotFound,
    TooFarAway,
    OfferFull,
    ItemNotInOffer,
    InsufficientItems,
    InventoryFull,
    Cancelled,
    TimedOut,
}

impl std::fmt::Display for TradeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidState => write!(f, "Invalid trade state"),
            Self::NotInTrade => write!(f, "Not in a trade"),
            Self::AlreadyTrading => write!(f, "Already in a trade"),
            Self::PlayerNotFound => write!(f, "Player not found"),
            Self::TooFarAway => write!(f, "Player is too far away"),
            Self::OfferFull => write!(f, "Trade offer is full"),
            Self::ItemNotInOffer => write!(f, "Item not in offer"),
            Self::InsufficientItems => write!(f, "Insufficient items"),
            Self::InventoryFull => write!(f, "Inventory is full"),
            Self::Cancelled => write!(f, "Trade was cancelled"),
            Self::TimedOut => write!(f, "Trade timed out"),
        }
    }
}

impl std::error::Error for TradeError {}

/// Manager for all active trade sessions.
#[derive(Debug, Default)]
pub struct TradeManager {
    sessions: HashMap<u64, TradeSession>,
    player_trades: HashMap<u64, u64>, // player_id -> session_id
    next_session_id: u64,
}

impl TradeManager {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
            player_trades: HashMap::new(),
            next_session_id: 1,
        }
    }

    /// Request a trade with another player.
    pub fn request_trade(&mut self, initiator_id: u64, target_id: u64) -> Result<u64, TradeError> {
        // Check if either player is already trading
        if self.player_trades.contains_key(&initiator_id) {
            return Err(TradeError::AlreadyTrading);
        }
        if self.player_trades.contains_key(&target_id) {
            return Err(TradeError::AlreadyTrading);
        }

        let session_id = self.next_session_id;
        self.next_session_id += 1;

        let session = TradeSession::new(session_id, initiator_id, target_id);
        self.sessions.insert(session_id, session);
        self.player_trades.insert(initiator_id, session_id);

        info!("Trade session {} created: {} -> {}", session_id, initiator_id, target_id);
        Ok(session_id)
    }

    /// Accept a pending trade request.
    pub fn accept_trade(&mut self, player_id: u64, initiator_id: u64) -> Result<u64, TradeError> {
        let session_id = self.player_trades.get(&initiator_id)
            .copied()
            .ok_or(TradeError::NotInTrade)?;

        let session = self.sessions.get_mut(&session_id)
            .ok_or(TradeError::NotInTrade)?;

        if session.player2_id != player_id {
            return Err(TradeError::NotInTrade);
        }

        session.accept_request()?;
        self.player_trades.insert(player_id, session_id);

        info!("Trade session {} accepted by {}", session_id, player_id);
        Ok(session_id)
    }

    /// Decline or cancel a trade.
    pub fn decline_trade(&mut self, player_id: u64) -> Result<u64, TradeError> {
        let session_id = self.player_trades.get(&player_id)
            .copied()
            .ok_or(TradeError::NotInTrade)?;

        let session = self.sessions.get_mut(&session_id)
            .ok_or(TradeError::NotInTrade)?;

        let other_player = session.other_player(player_id);
        session.decline(player_id)?;

        // Clean up
        self.player_trades.remove(&player_id);
        if let Some(other) = other_player {
            self.player_trades.remove(&other);
        }

        info!("Trade session {} declined by {}", session_id, player_id);
        Ok(session_id)
    }

    /// Get a player's current trade session.
    pub fn get_session(&self, player_id: u64) -> Option<&TradeSession> {
        let session_id = self.player_trades.get(&player_id)?;
        self.sessions.get(session_id)
    }

    /// Get a mutable reference to a player's trade session.
    pub fn get_session_mut(&mut self, player_id: u64) -> Option<&mut TradeSession> {
        let session_id = self.player_trades.get(&player_id)?;
        self.sessions.get_mut(session_id)
    }

    /// Process a completed trade, returning items to swap.
    pub fn complete_trade(&mut self, session_id: u64) -> Option<(u64, Vec<TradeItem>, u64, Vec<TradeItem>)> {
        let session = self.sessions.remove(&session_id)?;

        if session.state != TradeState::Completed {
            return None;
        }

        // Clean up player mappings
        self.player_trades.remove(&session.player1_id);
        self.player_trades.remove(&session.player2_id);

        info!("Trade session {} completed successfully", session_id);

        Some((
            session.player1_id,
            session.player2_offer, // Player 1 receives player 2's items
            session.player2_id,
            session.player1_offer, // Player 2 receives player 1's items
        ))
    }

    /// Clean up timed-out trade sessions.
    pub fn cleanup_expired(&mut self) {
        let expired: Vec<u64> = self.sessions.iter()
            .filter(|(_, s)| s.is_timed_out())
            .map(|(id, _)| *id)
            .collect();

        for session_id in expired {
            if let Some(session) = self.sessions.remove(&session_id) {
                self.player_trades.remove(&session.player1_id);
                self.player_trades.remove(&session.player2_id);
                debug!("Cleaned up expired trade session {}", session_id);
            }
        }
    }

    /// Check if a player is in an active trade.
    pub fn is_trading(&self, player_id: u64) -> bool {
        self.player_trades.contains_key(&player_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_trade_request() {
        let mut manager = TradeManager::new();

        let session_id = manager.request_trade(1, 2).unwrap();
        assert!(manager.is_trading(1));
        assert!(!manager.is_trading(2)); // Not accepted yet
    }

    #[test]
    fn test_trade_accept() {
        let mut manager = TradeManager::new();

        manager.request_trade(1, 2).unwrap();
        manager.accept_trade(2, 1).unwrap();

        assert!(manager.is_trading(1));
        assert!(manager.is_trading(2));
    }

    #[test]
    fn test_trade_flow() {
        let mut manager = TradeManager::new();

        // Request and accept
        manager.request_trade(1, 2).unwrap();
        manager.accept_trade(2, 1).unwrap();

        // Add items
        let session = manager.get_session_mut(1).unwrap();
        session.add_item(1, TradeItem { item_id: 100, amount: 5, noted: false }).unwrap();
        session.add_item(2, TradeItem { item_id: 200, amount: 10, noted: false }).unwrap();

        // First stage accept
        let session = manager.get_session_mut(1).unwrap();
        assert!(!session.accept(1).unwrap());
        assert!(session.accept(2).unwrap());
        assert_eq!(session.state, TradeState::Confirming);

        // Final confirm
        let session = manager.get_session_mut(1).unwrap();
        assert!(!session.confirm(1).unwrap());
        assert!(session.confirm(2).unwrap());
        assert_eq!(session.state, TradeState::Completed);
    }

    #[test]
    fn test_trade_decline() {
        let mut manager = TradeManager::new();

        manager.request_trade(1, 2).unwrap();
        manager.accept_trade(2, 1).unwrap();

        manager.decline_trade(1).unwrap();

        assert!(!manager.is_trading(1));
        assert!(!manager.is_trading(2));
    }
}
