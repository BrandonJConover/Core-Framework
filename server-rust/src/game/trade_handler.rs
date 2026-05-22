//! Trade handler wiring for player-to-player item trading.
//!
//! Builds on the core [`TradeSession`](super::trade::TradeSession) and
//! [`TradeManager`](super::trade::TradeManager) types, adding packet
//! construction and a high-level handler that returns ready-to-send packets.

use std::collections::HashMap;

use tracing::{debug, info, warn};

use super::item::ItemId;
use super::trade::{TradeError, TradeItem, TradeManager, TradeState};
use crate::protocol::opcodes::OpcodeOut;
use crate::protocol::{Packet, PacketBuilder};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Maximum number of distinct item stacks per side of a trade.
const MAX_OFFER_SLOTS: usize = 12;

// ---------------------------------------------------------------------------
// Per-player trade session view
// ---------------------------------------------------------------------------

/// Lightweight per-player view of an active trade used by the handler layer.
#[derive(Debug, Clone)]
pub struct TradeSession {
    /// The partner player ID.
    pub partner_id: u64,
    /// Items this player has offered: (item_id, amount).
    pub offered_items: Vec<(ItemId, u32)>,
    /// Current trade state.
    pub state: TradeHandlerState,
    /// Whether this player has accepted the current screen.
    pub accepted: bool,
}

/// Trade state as exposed by the handler layer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TradeHandlerState {
    /// A request has been sent but not yet accepted.
    Requesting,
    /// Both players are in the offer screen.
    Offering,
    /// First confirmation screen (review).
    FirstConfirm,
    /// Second confirmation screen (final).
    SecondConfirm,
    /// Trade completed successfully.
    Completed,
    /// Trade was declined or cancelled.
    Declined,
}

impl From<TradeState> for TradeHandlerState {
    fn from(s: TradeState) -> Self {
        match s {
            TradeState::Requesting => TradeHandlerState::Requesting,
            TradeState::InProgress => TradeHandlerState::Offering,
            TradeState::Confirming => TradeHandlerState::FirstConfirm,
            TradeState::FinalConfirm => TradeHandlerState::SecondConfirm,
            TradeState::Completed => TradeHandlerState::Completed,
            TradeState::Cancelled => TradeHandlerState::Declined,
        }
    }
}

// ---------------------------------------------------------------------------
// Trade handler (high-level manager producing packets)
// ---------------------------------------------------------------------------

/// High-level trade handler that wraps [`TradeManager`] and produces outgoing
/// [`Packet`]s for every trade action.
#[derive(Debug)]
pub struct TradeHandler {
    /// The underlying trade-session manager.
    manager: TradeManager,
    /// Player-ID -> handler-level session snapshot.
    active_trades: HashMap<u64, TradeSession>,
    /// Pending requests: target_id -> requester_id.
    pending_requests: HashMap<u64, u64>,
}

impl Default for TradeHandler {
    fn default() -> Self {
        Self::new()
    }
}

impl TradeHandler {
    pub fn new() -> Self {
        Self {
            manager: TradeManager::new(),
            active_trades: HashMap::new(),
            pending_requests: HashMap::new(),
        }
    }

    // -- actions ---------------------------------------------------------

    /// Player `requester_id` requests a trade with `target_id`.
    ///
    /// Returns packets to send: element 0 is for the requester, element 1 is
    /// for the target.
    pub fn request_trade(
        &mut self,
        requester_id: u64,
        target_id: u64,
    ) -> Result<Vec<Packet>, TradeError> {
        // Prevent double-trading at the handler level.
        if self.active_trades.contains_key(&requester_id) {
            return Err(TradeError::AlreadyTrading);
        }
        if self.active_trades.contains_key(&target_id) {
            return Err(TradeError::AlreadyTrading);
        }

        // Check for a cross-request (target already requested us).
        if self.pending_requests.get(&requester_id) == Some(&target_id) {
            // Treat this as an implicit accept from both sides.
            return self.accept_trade(requester_id);
        }

        // Delegate to the core manager.
        self.manager.request_trade(requester_id, target_id)?;
        self.pending_requests.insert(target_id, requester_id);

        info!("Trade request: {} -> {}", requester_id, target_id);

        let mut packets = Vec::new();
        packets.push(build_server_message("Sending trade request..."));
        packets.push(build_trade_request_packet(requester_id));
        Ok(packets)
    }

    /// Player `player_id` accepts the pending trade request aimed at them.
    pub fn accept_trade(&mut self, player_id: u64) -> Result<Vec<Packet>, TradeError> {
        let requester_id = self
            .pending_requests
            .remove(&player_id)
            .ok_or(TradeError::NotInTrade)?;

        // Accept in core manager.
        self.manager.accept_trade(player_id, requester_id)?;

        // Create handler-level sessions.
        self.active_trades.insert(
            requester_id,
            TradeSession {
                partner_id: player_id,
                offered_items: Vec::new(),
                state: TradeHandlerState::Offering,
                accepted: false,
            },
        );
        self.active_trades.insert(
            player_id,
            TradeSession {
                partner_id: requester_id,
                offered_items: Vec::new(),
                state: TradeHandlerState::Offering,
                accepted: false,
            },
        );

        info!("Trade accepted: {} <-> {}", requester_id, player_id);

        let mut packets = Vec::new();
        // Open trade window for requester and acceptor.
        packets.push(build_open_trade_packet(player_id));
        packets.push(build_open_trade_packet(requester_id));
        Ok(packets)
    }

    /// Player offers an item in the trade window.
    pub fn offer_item(
        &mut self,
        player_id: u64,
        item_id: ItemId,
        amount: u32,
    ) -> Result<Vec<Packet>, TradeError> {
        let session = self
            .active_trades
            .get(&player_id)
            .ok_or(TradeError::NotInTrade)?;

        if session.state != TradeHandlerState::Offering {
            return Err(TradeError::InvalidState);
        }

        // Enforce max offer slots.
        let current_count = session.offered_items.len();
        let already_has = session.offered_items.iter().any(|(id, _)| *id == item_id);
        if !already_has && current_count >= MAX_OFFER_SLOTS {
            return Err(TradeError::OfferFull);
        }

        let partner_id = session.partner_id;

        // Apply to core manager session.
        let core_session = self
            .manager
            .get_session_mut(player_id)
            .ok_or(TradeError::NotInTrade)?;
        core_session.add_item(
            player_id,
            TradeItem {
                item_id: item_id.0,
                amount,
                noted: false,
            },
        )?;

        // Update handler-level snapshot.
        let handler_session = self
            .active_trades
            .get_mut(&player_id)
            .ok_or(TradeError::NotInTrade)?;
        if let Some(entry) = handler_session
            .offered_items
            .iter_mut()
            .find(|(id, _)| *id == item_id)
        {
            entry.1 = entry.1.saturating_add(amount);
        } else {
            handler_session.offered_items.push((item_id, amount));
        }
        handler_session.accepted = false;

        // Reset partner acceptance.
        if let Some(partner) = self.active_trades.get_mut(&partner_id) {
            partner.accepted = false;
        }

        debug!(
            "Player {} offered {} x {} in trade",
            player_id, amount, item_id.0
        );

        let my_offer = self.get_offer_list(player_id);
        let mut packets = Vec::new();
        packets.push(build_trade_update_packet(player_id, &my_offer));
        packets.push(build_trade_other_items_packet(partner_id, &my_offer));
        Ok(packets)
    }

    /// Player removes an offered item (or reduces its amount).
    pub fn remove_offer(
        &mut self,
        player_id: u64,
        item_id: ItemId,
        amount: u32,
    ) -> Result<Vec<Packet>, TradeError> {
        let session = self
            .active_trades
            .get(&player_id)
            .ok_or(TradeError::NotInTrade)?;

        if session.state != TradeHandlerState::Offering {
            return Err(TradeError::InvalidState);
        }

        let partner_id = session.partner_id;

        // Core manager removal.
        let core_session = self
            .manager
            .get_session_mut(player_id)
            .ok_or(TradeError::NotInTrade)?;
        core_session.remove_item(player_id, item_id.0, amount)?;

        // Handler-level update.
        let handler_session = self
            .active_trades
            .get_mut(&player_id)
            .ok_or(TradeError::NotInTrade)?;
        if let Some(pos) = handler_session
            .offered_items
            .iter()
            .position(|(id, _)| *id == item_id)
        {
            let entry = &mut handler_session.offered_items[pos];
            if amount >= entry.1 {
                handler_session.offered_items.remove(pos);
            } else {
                entry.1 -= amount;
            }
        }
        handler_session.accepted = false;

        if let Some(partner) = self.active_trades.get_mut(&partner_id) {
            partner.accepted = false;
        }

        let my_offer = self.get_offer_list(player_id);
        let mut packets = Vec::new();
        packets.push(build_trade_update_packet(player_id, &my_offer));
        packets.push(build_trade_other_items_packet(partner_id, &my_offer));
        Ok(packets)
    }

    /// Player presses the confirm / accept button.
    ///
    /// On the first press from both players the state advances to FirstConfirm,
    /// and on the second press from both it advances to SecondConfirm ->
    /// Completed.
    pub fn confirm_trade(&mut self, player_id: u64) -> Result<Vec<Packet>, TradeError> {
        let session = self
            .active_trades
            .get(&player_id)
            .ok_or(TradeError::NotInTrade)?;

        let partner_id = session.partner_id;

        match session.state {
            TradeHandlerState::Offering => {
                // First accept press -- move to FirstConfirm once both press.
                let core_session = self
                    .manager
                    .get_session_mut(player_id)
                    .ok_or(TradeError::NotInTrade)?;
                let both_accepted = core_session.accept(player_id)?;

                self.active_trades
                    .get_mut(&player_id)
                    .ok_or(TradeError::NotInTrade)?
                    .accepted = true;

                if both_accepted {
                    // Both accepted -- transition to first confirm screen.
                    self.set_state(player_id, TradeHandlerState::FirstConfirm);
                    self.set_state(partner_id, TradeHandlerState::FirstConfirm);

                    let my_offer = self.get_offer_list(player_id);
                    let partner_offer = self.get_offer_list(partner_id);

                    let mut packets = Vec::new();
                    packets.push(build_trade_confirm_packet(
                        player_id,
                        &my_offer,
                        &partner_offer,
                    ));
                    packets.push(build_trade_confirm_packet(
                        partner_id,
                        &partner_offer,
                        &my_offer,
                    ));
                    Ok(packets)
                } else {
                    Ok(vec![build_server_message("Waiting for other player...")])
                }
            }
            TradeHandlerState::FirstConfirm => {
                // Second (final) confirm press.
                let core_session = self
                    .manager
                    .get_session_mut(player_id)
                    .ok_or(TradeError::NotInTrade)?;
                let both_confirmed = core_session.confirm(player_id)?;

                self.active_trades
                    .get_mut(&player_id)
                    .ok_or(TradeError::NotInTrade)?
                    .accepted = true;

                if both_confirmed {
                    // Execute the swap.
                    self.execute_trade(player_id, partner_id)?;

                    let mut packets = Vec::new();
                    packets.push(build_trade_close_packet(player_id));
                    packets.push(build_trade_close_packet(partner_id));
                    packets.push(build_server_message("Trade completed!"));
                    Ok(packets)
                } else {
                    Ok(vec![build_server_message(
                        "Waiting for other player to confirm...",
                    )])
                }
            }
            _ => Err(TradeError::InvalidState),
        }
    }

    /// Player declines or closes the trade window.
    pub fn decline_trade(&mut self, player_id: u64) -> Result<Vec<Packet>, TradeError> {
        let session = self
            .active_trades
            .get(&player_id)
            .ok_or(TradeError::NotInTrade)?;
        let partner_id = session.partner_id;

        // Core manager cleanup.
        let _ = self.manager.decline_trade(player_id);

        // Handler cleanup.
        self.active_trades.remove(&player_id);
        self.active_trades.remove(&partner_id);
        self.pending_requests.remove(&player_id);
        self.pending_requests.remove(&partner_id);

        info!("Trade declined by {}", player_id);

        let mut packets = Vec::new();
        packets.push(build_trade_close_packet(player_id));
        packets.push(build_trade_close_packet(partner_id));
        packets.push(build_server_message("Trade declined."));
        Ok(packets)
    }

    /// Actually execute the item swap (called internally when both confirm).
    fn execute_trade(&mut self, player1: u64, player2: u64) -> Result<(), TradeError> {
        // Retrieve the session_id so we can call complete_trade.
        let session = self
            .manager
            .get_session(player1)
            .ok_or(TradeError::NotInTrade)?;
        let session_id = session.id;

        if let Some((p1, p1_receives, p2, p2_receives)) = self.manager.complete_trade(session_id) {
            info!(
                "Trade executed: {} receives {} items, {} receives {} items",
                p1,
                p1_receives.len(),
                p2,
                p2_receives.len()
            );
        }

        // Clean up handler-level state.
        self.active_trades.remove(&player1);
        self.active_trades.remove(&player2);

        Ok(())
    }

    // -- queries ---------------------------------------------------------

    /// Check whether a player is currently in an active trade.
    pub fn is_trading(&self, player_id: u64) -> bool {
        self.active_trades.contains_key(&player_id)
    }

    /// Check whether a pending request exists for `target_id`.
    pub fn has_pending_request(&self, target_id: u64) -> bool {
        self.pending_requests.contains_key(&target_id)
    }

    /// Get the handler-level session for a player.
    pub fn get_session(&self, player_id: u64) -> Option<&TradeSession> {
        self.active_trades.get(&player_id)
    }

    /// Clean up expired trade sessions.
    pub fn cleanup_expired(&mut self) {
        self.manager.cleanup_expired();
        // Remove handler sessions whose core session is gone.
        let stale: Vec<u64> = self
            .active_trades
            .keys()
            .filter(|id| !self.manager.is_trading(**id))
            .copied()
            .collect();
        for id in stale {
            self.active_trades.remove(&id);
        }
    }

    // -- helpers ---------------------------------------------------------

    fn get_offer_list(&self, player_id: u64) -> Vec<(ItemId, u32)> {
        self.active_trades
            .get(&player_id)
            .map(|s| s.offered_items.clone())
            .unwrap_or_default()
    }

    fn set_state(&mut self, player_id: u64, state: TradeHandlerState) {
        if let Some(s) = self.active_trades.get_mut(&player_id) {
            s.state = state;
            s.accepted = false;
        }
    }
}

// ---------------------------------------------------------------------------
// Packet builders
// ---------------------------------------------------------------------------

/// Build a "trade request received" notification for the target player.
fn build_trade_request_packet(requester_id: u64) -> Packet {
    PacketBuilder::new(OpcodeOut::SEND_SERVER_MESSAGE.into())
        .write_string(&format!(
            "@que@Player {} wishes to trade with you.",
            requester_id
        ))
        .build()
}

/// Build the packet that opens the trade window for a player.
fn build_open_trade_packet(partner_id: u64) -> Packet {
    PacketBuilder::new(OpcodeOut::SEND_TRADE_WINDOW.into())
        .write_long(partner_id)
        .build()
}

/// Build a trade-update packet showing the player's own current offer.
fn build_trade_update_packet(_for_player: u64, items: &[(ItemId, u32)]) -> Packet {
    let mut builder =
        PacketBuilder::new(OpcodeOut::SEND_TRADE_WINDOW.into()).write_byte(items.len() as u8);

    for (item_id, amount) in items {
        builder = builder.write_short(item_id.0 as u16).write_int(*amount);
    }

    builder.build()
}

/// Build a packet showing the *other* player's current offer.
fn build_trade_other_items_packet(_for_player: u64, items: &[(ItemId, u32)]) -> Packet {
    let mut builder =
        PacketBuilder::new(OpcodeOut::SEND_TRADE_OTHER_ITEMS.into()).write_byte(items.len() as u8);

    for (item_id, amount) in items {
        builder = builder.write_short(item_id.0 as u16).write_int(*amount);
    }

    builder.build()
}

/// Build the first-stage confirmation screen showing both offers.
fn build_trade_confirm_packet(
    _for_player: u64,
    my_items: &[(ItemId, u32)],
    their_items: &[(ItemId, u32)],
) -> Packet {
    let mut builder = PacketBuilder::new(OpcodeOut::SEND_TRADE_OPEN_CONFIRM.into())
        .write_byte(my_items.len() as u8);

    for (item_id, amount) in my_items {
        builder = builder.write_short(item_id.0 as u16).write_int(*amount);
    }

    builder = builder.write_byte(their_items.len() as u8);
    for (item_id, amount) in their_items {
        builder = builder.write_short(item_id.0 as u16).write_int(*amount);
    }

    builder.build()
}

/// Build a trade-close packet telling the client to close the window.
fn build_trade_close_packet(_for_player: u64) -> Packet {
    PacketBuilder::new(OpcodeOut::SEND_TRADE_CLOSE.into()).build()
}

/// Build a simple server message.
fn build_server_message(msg: &str) -> Packet {
    PacketBuilder::new(OpcodeOut::SEND_SERVER_MESSAGE.into())
        .write_string(msg)
        .build()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_request_and_accept_trade() {
        let mut handler = TradeHandler::new();

        let req_packets = handler.request_trade(1, 2).unwrap();
        assert_eq!(req_packets.len(), 2);
        assert!(handler.has_pending_request(2));

        let acc_packets = handler.accept_trade(2).unwrap();
        assert_eq!(acc_packets.len(), 2);
        assert!(handler.is_trading(1));
        assert!(handler.is_trading(2));
    }

    #[test]
    fn test_double_trade_rejected() {
        let mut handler = TradeHandler::new();
        handler.request_trade(1, 2).unwrap();
        handler.accept_trade(2).unwrap();

        let result = handler.request_trade(1, 3);
        assert_eq!(result.unwrap_err(), TradeError::AlreadyTrading);
    }

    #[test]
    fn test_offer_item() {
        let mut handler = TradeHandler::new();
        handler.request_trade(1, 2).unwrap();
        handler.accept_trade(2).unwrap();

        let packets = handler.offer_item(1, ItemId(100), 5).unwrap();
        assert_eq!(packets.len(), 2);

        let session = handler.get_session(1).unwrap();
        assert_eq!(session.offered_items.len(), 1);
        assert_eq!(session.offered_items[0], (ItemId(100), 5));
    }

    #[test]
    fn test_offer_max_slots() {
        let mut handler = TradeHandler::new();
        handler.request_trade(1, 2).unwrap();
        handler.accept_trade(2).unwrap();

        for i in 0..MAX_OFFER_SLOTS {
            handler.offer_item(1, ItemId(i as u32), 1).unwrap();
        }

        let result = handler.offer_item(1, ItemId(999), 1);
        assert_eq!(result.unwrap_err(), TradeError::OfferFull);
    }

    #[test]
    fn test_stacking_same_item() {
        let mut handler = TradeHandler::new();
        handler.request_trade(1, 2).unwrap();
        handler.accept_trade(2).unwrap();

        handler.offer_item(1, ItemId(100), 5).unwrap();
        handler.offer_item(1, ItemId(100), 3).unwrap();

        let session = handler.get_session(1).unwrap();
        assert_eq!(session.offered_items.len(), 1);
        assert_eq!(session.offered_items[0], (ItemId(100), 8));
    }

    #[test]
    fn test_remove_offer() {
        let mut handler = TradeHandler::new();
        handler.request_trade(1, 2).unwrap();
        handler.accept_trade(2).unwrap();

        handler.offer_item(1, ItemId(100), 10).unwrap();
        handler.remove_offer(1, ItemId(100), 4).unwrap();

        let session = handler.get_session(1).unwrap();
        assert_eq!(session.offered_items[0], (ItemId(100), 6));
    }

    #[test]
    fn test_confirm_trade_flow() {
        let mut handler = TradeHandler::new();
        handler.request_trade(1, 2).unwrap();
        handler.accept_trade(2).unwrap();

        handler.offer_item(1, ItemId(100), 5).unwrap();
        handler.offer_item(2, ItemId(200), 10).unwrap();

        // First accept from player 1 -- waiting.
        let packets = handler.confirm_trade(1).unwrap();
        assert_eq!(packets.len(), 1); // "Waiting..." message

        // First accept from player 2 -- moves to FirstConfirm.
        let packets = handler.confirm_trade(2).unwrap();
        assert_eq!(packets.len(), 2); // confirm packets for both players

        // Second confirm from player 1 -- waiting.
        let packets = handler.confirm_trade(1).unwrap();
        assert_eq!(packets.len(), 1);

        // Second confirm from player 2 -- trade completes.
        let packets = handler.confirm_trade(2).unwrap();
        assert_eq!(packets.len(), 3); // close + close + message

        assert!(!handler.is_trading(1));
        assert!(!handler.is_trading(2));
    }

    #[test]
    fn test_decline_trade() {
        let mut handler = TradeHandler::new();
        handler.request_trade(1, 2).unwrap();
        handler.accept_trade(2).unwrap();

        let packets = handler.decline_trade(1).unwrap();
        assert_eq!(packets.len(), 3);

        assert!(!handler.is_trading(1));
        assert!(!handler.is_trading(2));
    }

    #[test]
    fn test_cross_request_auto_accepts() {
        let mut handler = TradeHandler::new();

        handler.request_trade(1, 2).unwrap();
        // Player 2 now requests player 1 -- should auto-accept.
        let packets = handler.request_trade(2, 1).unwrap();
        assert_eq!(packets.len(), 2);
        assert!(handler.is_trading(1));
        assert!(handler.is_trading(2));
    }
}
