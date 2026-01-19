//! Party system.
//! Handles temporary player groups for activities like combat and quests.

use std::collections::{HashMap, HashSet};
use std::time::Instant;
use tracing::{info, warn};

/// Maximum party size.
pub const MAX_PARTY_SIZE: usize = 5;

/// Party loot distribution modes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LootMode {
    /// Free for all - anyone can pick up.
    FreeForAll,
    /// Round robin - rotates between members.
    RoundRobin,
    /// Leader decides who gets loot.
    LeaderDecides,
    /// Random member gets the loot.
    Random,
}

impl Default for LootMode {
    fn default() -> Self {
        LootMode::FreeForAll
    }
}

/// Party member info.
#[derive(Debug, Clone)]
pub struct PartyMember {
    /// Player ID.
    pub player_id: u64,
    /// Player name.
    pub name: String,
    /// Combat level.
    pub combat_level: u8,
    /// Current hitpoints.
    pub hitpoints: u16,
    /// Maximum hitpoints.
    pub max_hitpoints: u16,
    /// Whether player is the leader.
    pub is_leader: bool,
    /// When the player joined.
    pub joined_at: Instant,
}

impl PartyMember {
    /// Create a new party member.
    pub fn new(player_id: u64, name: String, combat_level: u8, max_hitpoints: u16) -> Self {
        Self {
            player_id,
            name,
            combat_level,
            hitpoints: max_hitpoints,
            max_hitpoints,
            is_leader: false,
            joined_at: Instant::now(),
        }
    }

    /// Create a party leader.
    pub fn leader(player_id: u64, name: String, combat_level: u8, max_hitpoints: u16) -> Self {
        let mut member = Self::new(player_id, name, combat_level, max_hitpoints);
        member.is_leader = true;
        member
    }

    /// Update health info.
    pub fn update_health(&mut self, current: u16, max: u16) {
        self.hitpoints = current;
        self.max_hitpoints = max;
    }

    /// Get health percentage.
    pub fn health_percent(&self) -> f64 {
        if self.max_hitpoints == 0 {
            return 0.0;
        }
        (self.hitpoints as f64 / self.max_hitpoints as f64) * 100.0
    }
}

/// A party of players.
#[derive(Debug)]
pub struct Party {
    /// Unique party ID.
    pub id: u64,
    /// Party members.
    members: HashMap<u64, PartyMember>,
    /// Pending invites (player_id -> invite time).
    pending_invites: HashMap<u64, Instant>,
    /// Loot distribution mode.
    pub loot_mode: LootMode,
    /// Current round robin index for loot.
    round_robin_index: usize,
    /// Creation time.
    pub created_at: Instant,
    /// Experience sharing enabled.
    pub share_exp: bool,
}

impl Party {
    /// Create a new party.
    pub fn new(
        id: u64,
        leader_id: u64,
        leader_name: String,
        combat_level: u8,
        max_hp: u16,
    ) -> Self {
        let mut members = HashMap::new();
        members.insert(
            leader_id,
            PartyMember::leader(leader_id, leader_name, combat_level, max_hp),
        );

        Self {
            id,
            members,
            pending_invites: HashMap::new(),
            loot_mode: LootMode::default(),
            round_robin_index: 0,
            created_at: Instant::now(),
            share_exp: false,
        }
    }

    /// Get party size.
    pub fn size(&self) -> usize {
        self.members.len()
    }

    /// Check if party is full.
    pub fn is_full(&self) -> bool {
        self.size() >= MAX_PARTY_SIZE
    }

    /// Get party leader.
    pub fn get_leader(&self) -> Option<&PartyMember> {
        self.members.values().find(|m| m.is_leader)
    }

    /// Get leader ID.
    pub fn leader_id(&self) -> Option<u64> {
        self.get_leader().map(|m| m.player_id)
    }

    /// Check if player is the leader.
    pub fn is_leader(&self, player_id: u64) -> bool {
        self.members
            .get(&player_id)
            .map(|m| m.is_leader)
            .unwrap_or(false)
    }

    /// Get member by ID.
    pub fn get_member(&self, player_id: u64) -> Option<&PartyMember> {
        self.members.get(&player_id)
    }

    /// Get mutable member by ID.
    pub fn get_member_mut(&mut self, player_id: u64) -> Option<&mut PartyMember> {
        self.members.get_mut(&player_id)
    }

    /// Check if player is a member.
    pub fn is_member(&self, player_id: u64) -> bool {
        self.members.contains_key(&player_id)
    }

    /// Add a pending invite.
    pub fn add_invite(&mut self, player_id: u64) -> Result<(), &'static str> {
        if self.is_full() {
            return Err("Party is full");
        }
        if self.is_member(player_id) {
            return Err("Player is already in the party");
        }
        self.pending_invites.insert(player_id, Instant::now());
        Ok(())
    }

    /// Check if player has pending invite.
    pub fn has_invite(&self, player_id: u64) -> bool {
        self.pending_invites.contains_key(&player_id)
    }

    /// Accept an invite.
    pub fn accept_invite(
        &mut self,
        player_id: u64,
        name: String,
        combat_level: u8,
        max_hp: u16,
    ) -> Result<(), &'static str> {
        if !self.has_invite(player_id) {
            return Err("No pending invite");
        }
        if self.is_full() {
            return Err("Party is full");
        }

        self.pending_invites.remove(&player_id);
        self.members.insert(
            player_id,
            PartyMember::new(player_id, name, combat_level, max_hp),
        );
        Ok(())
    }

    /// Decline an invite.
    pub fn decline_invite(&mut self, player_id: u64) {
        self.pending_invites.remove(&player_id);
    }

    /// Remove a member.
    pub fn remove_member(&mut self, player_id: u64) -> Result<(), &'static str> {
        if !self.is_member(player_id) {
            return Err("Player is not in the party");
        }

        let is_leader = self.is_leader(player_id);
        self.members.remove(&player_id);

        // If leader left and party still has members, promote next member
        if is_leader && !self.members.is_empty() {
            if let Some(new_leader) = self.members.values_mut().next() {
                new_leader.is_leader = true;
            }
        }

        Ok(())
    }

    /// Kick a member (leader only).
    pub fn kick_member(&mut self, kicker_id: u64, target_id: u64) -> Result<(), &'static str> {
        if !self.is_leader(kicker_id) {
            return Err("Only the leader can kick members");
        }
        if kicker_id == target_id {
            return Err("Cannot kick yourself");
        }
        self.remove_member(target_id)
    }

    /// Transfer leadership.
    pub fn transfer_leadership(
        &mut self,
        current_leader: u64,
        new_leader: u64,
    ) -> Result<(), &'static str> {
        if !self.is_leader(current_leader) {
            return Err("You are not the party leader");
        }
        if !self.is_member(new_leader) {
            return Err("Target is not a party member");
        }

        self.members.get_mut(&current_leader).unwrap().is_leader = false;
        self.members.get_mut(&new_leader).unwrap().is_leader = true;
        Ok(())
    }

    /// Get all member IDs.
    pub fn member_ids(&self) -> Vec<u64> {
        self.members.keys().copied().collect()
    }

    /// Get all members.
    pub fn members(&self) -> impl Iterator<Item = &PartyMember> {
        self.members.values()
    }

    /// Get next loot recipient (for round robin).
    pub fn next_loot_recipient(&mut self) -> Option<u64> {
        if self.members.is_empty() {
            return None;
        }

        match self.loot_mode {
            LootMode::FreeForAll => None,
            LootMode::LeaderDecides => self.leader_id(),
            LootMode::RoundRobin => {
                let ids: Vec<_> = self.members.keys().copied().collect();
                self.round_robin_index = (self.round_robin_index + 1) % ids.len();
                Some(ids[self.round_robin_index])
            }
            LootMode::Random => {
                let ids: Vec<_> = self.members.keys().copied().collect();
                let idx = rand::random::<usize>() % ids.len();
                Some(ids[idx])
            }
        }
    }

    /// Calculate average combat level.
    pub fn average_combat_level(&self) -> u8 {
        if self.members.is_empty() {
            return 0;
        }
        let total: u32 = self.members.values().map(|m| m.combat_level as u32).sum();
        (total / self.members.len() as u32) as u8
    }

    /// Clean up expired invites (older than 60 seconds).
    pub fn cleanup_invites(&mut self) {
        let now = Instant::now();
        self.pending_invites
            .retain(|_, time| now.duration_since(*time).as_secs() < 60);
    }
}

/// Manager for party system.
#[derive(Debug, Default)]
pub struct PartyManager {
    /// Parties by ID.
    parties: HashMap<u64, Party>,
    /// Player to party mapping.
    player_parties: HashMap<u64, u64>,
    /// Next party ID.
    next_id: u64,
}

impl PartyManager {
    /// Create a new party manager.
    pub fn new() -> Self {
        Self {
            parties: HashMap::new(),
            player_parties: HashMap::new(),
            next_id: 1,
        }
    }

    /// Create a new party.
    pub fn create_party(
        &mut self,
        leader_id: u64,
        leader_name: String,
        combat_level: u8,
        max_hp: u16,
    ) -> Result<u64, &'static str> {
        if self.player_parties.contains_key(&leader_id) {
            return Err("Player is already in a party");
        }

        let id = self.next_id;
        self.next_id += 1;

        let party = Party::new(id, leader_id, leader_name, combat_level, max_hp);
        self.parties.insert(id, party);
        self.player_parties.insert(leader_id, id);

        info!("Created party {}", id);
        Ok(id)
    }

    /// Get party by ID.
    pub fn get_party(&self, party_id: u64) -> Option<&Party> {
        self.parties.get(&party_id)
    }

    /// Get mutable party by ID.
    pub fn get_party_mut(&mut self, party_id: u64) -> Option<&mut Party> {
        self.parties.get_mut(&party_id)
    }

    /// Get player's party.
    pub fn get_player_party(&self, player_id: u64) -> Option<&Party> {
        self.player_parties
            .get(&player_id)
            .and_then(|id| self.parties.get(id))
    }

    /// Get player's party ID.
    pub fn get_player_party_id(&self, player_id: u64) -> Option<u64> {
        self.player_parties.get(&player_id).copied()
    }

    /// Invite a player to a party.
    pub fn invite_player(&mut self, inviter_id: u64, invitee_id: u64) -> Result<(), &'static str> {
        let party_id = self
            .player_parties
            .get(&inviter_id)
            .copied()
            .ok_or("You are not in a party")?;
        let party = self.parties.get_mut(&party_id).ok_or("Party not found")?;

        if !party.is_leader(inviter_id) {
            return Err("Only the leader can invite");
        }

        if self.player_parties.contains_key(&invitee_id) {
            return Err("Player is already in a party");
        }

        party.add_invite(invitee_id)
    }

    /// Accept a party invite.
    pub fn accept_invite(
        &mut self,
        player_id: u64,
        party_id: u64,
        name: String,
        combat_level: u8,
        max_hp: u16,
    ) -> Result<(), &'static str> {
        if self.player_parties.contains_key(&player_id) {
            return Err("Already in a party");
        }

        let party = self.parties.get_mut(&party_id).ok_or("Party not found")?;
        party.accept_invite(player_id, name, combat_level, max_hp)?;
        self.player_parties.insert(player_id, party_id);
        Ok(())
    }

    /// Leave a party.
    pub fn leave_party(&mut self, player_id: u64) -> Result<(), &'static str> {
        let party_id = self
            .player_parties
            .get(&player_id)
            .copied()
            .ok_or("Not in a party")?;
        let party = self.parties.get_mut(&party_id).ok_or("Party not found")?;

        party.remove_member(player_id)?;
        self.player_parties.remove(&player_id);

        // Disband if empty
        if party.size() == 0 {
            self.parties.remove(&party_id);
            info!("Party {} disbanded (empty)", party_id);
        }

        Ok(())
    }

    /// Disband a party.
    pub fn disband_party(&mut self, requester_id: u64) -> Result<(), &'static str> {
        let party_id = self
            .player_parties
            .get(&requester_id)
            .copied()
            .ok_or("Not in a party")?;
        let party = self.parties.get(&party_id).ok_or("Party not found")?;

        if !party.is_leader(requester_id) {
            return Err("Only the leader can disband");
        }

        // Remove all members
        let member_ids = party.member_ids();
        for id in member_ids {
            self.player_parties.remove(&id);
        }

        self.parties.remove(&party_id);
        info!("Party {} disbanded", party_id);
        Ok(())
    }

    /// Tick - cleanup expired invites.
    pub fn tick(&mut self) {
        for party in self.parties.values_mut() {
            party.cleanup_invites();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_party_creation() {
        let mut manager = PartyManager::new();
        let result = manager.create_party(1, "Leader".to_string(), 50, 99);
        assert!(result.is_ok());

        let party = manager.get_party(result.unwrap()).unwrap();
        assert_eq!(party.size(), 1);
        assert!(party.is_leader(1));
    }

    #[test]
    fn test_party_invite() {
        let mut manager = PartyManager::new();
        let party_id = manager
            .create_party(1, "Leader".to_string(), 50, 99)
            .unwrap();

        // Invite player 2
        assert!(manager.invite_player(1, 2).is_ok());

        // Accept invite
        assert!(manager
            .accept_invite(2, party_id, "Member".to_string(), 45, 90)
            .is_ok());

        let party = manager.get_party(party_id).unwrap();
        assert_eq!(party.size(), 2);
        assert!(party.is_member(2));
    }

    #[test]
    fn test_party_full() {
        let mut party = Party::new(1, 1, "Leader".to_string(), 50, 99);

        for i in 2..=MAX_PARTY_SIZE {
            party.add_invite(i as u64).unwrap();
            party
                .accept_invite(i as u64, format!("Member{}", i), 50, 99)
                .unwrap();
        }

        assert!(party.is_full());
        assert!(party.add_invite(100).is_err());
    }

    #[test]
    fn test_leadership_transfer() {
        let mut party = Party::new(1, 1, "Leader".to_string(), 50, 99);
        party.add_invite(2).unwrap();
        party
            .accept_invite(2, "Member".to_string(), 50, 99)
            .unwrap();

        assert!(party.transfer_leadership(1, 2).is_ok());
        assert!(party.is_leader(2));
        assert!(!party.is_leader(1));
    }
}
