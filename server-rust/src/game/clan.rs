//! Clan system.
//! Handles player clans, ranks, and clan management.

use std::collections::HashMap;
use std::time::Instant;
use tracing::info;

/// Clan ranks.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ClanRank {
    /// Regular member.
    Member,
    /// Corporal - can invite.
    Corporal,
    /// Sergeant - can kick members.
    Sergeant,
    /// Lieutenant - can manage ranks.
    Lieutenant,
    /// Captain - can manage most settings.
    Captain,
    /// General - second in command.
    General,
    /// Leader - full control.
    Leader,
}

impl ClanRank {
    /// Check if rank can invite new members.
    pub fn can_invite(&self) -> bool {
        *self >= ClanRank::Corporal
    }

    /// Check if rank can kick members.
    pub fn can_kick(&self) -> bool {
        *self >= ClanRank::Sergeant
    }

    /// Check if rank can change member ranks.
    pub fn can_change_ranks(&self) -> bool {
        *self >= ClanRank::Lieutenant
    }

    /// Check if rank can change clan settings.
    pub fn can_change_settings(&self) -> bool {
        *self >= ClanRank::Captain
    }

    /// Get display name.
    pub fn display_name(&self) -> &'static str {
        match self {
            ClanRank::Member => "Member",
            ClanRank::Corporal => "Corporal",
            ClanRank::Sergeant => "Sergeant",
            ClanRank::Lieutenant => "Lieutenant",
            ClanRank::Captain => "Captain",
            ClanRank::General => "General",
            ClanRank::Leader => "Leader",
        }
    }
}

/// Clan member info.
#[derive(Debug, Clone)]
pub struct ClanMember {
    /// Player ID.
    pub player_id: u64,
    /// Player name.
    pub name: String,
    /// Rank in the clan.
    pub rank: ClanRank,
    /// When the player joined.
    pub joined_at: Instant,
    /// Whether player is currently online.
    pub online: bool,
}

impl ClanMember {
    /// Create a new clan member.
    pub fn new(player_id: u64, name: String, rank: ClanRank) -> Self {
        Self {
            player_id,
            name,
            rank,
            joined_at: Instant::now(),
            online: true,
        }
    }
}

/// Clan settings.
#[derive(Debug, Clone)]
pub struct ClanSettings {
    /// Minimum rank to join clan chat.
    pub chat_rank: ClanRank,
    /// Minimum rank to kick members.
    pub kick_rank: ClanRank,
    /// Minimum rank to invite.
    pub invite_rank: ClanRank,
    /// Allow guests in chat.
    pub allow_guests: bool,
}

impl Default for ClanSettings {
    fn default() -> Self {
        Self {
            chat_rank: ClanRank::Member,
            kick_rank: ClanRank::Sergeant,
            invite_rank: ClanRank::Corporal,
            allow_guests: true,
        }
    }
}

/// A clan organization.
#[derive(Debug)]
pub struct Clan {
    /// Unique clan ID.
    pub id: u64,
    /// Clan name.
    pub name: String,
    /// Clan tag (short identifier).
    pub tag: String,
    /// Clan members.
    members: HashMap<u64, ClanMember>,
    /// Pending invites (player_id -> inviter_id).
    pending_invites: HashMap<u64, u64>,
    /// Clan settings.
    pub settings: ClanSettings,
    /// Creation time.
    pub created_at: Instant,
    /// Message of the day.
    pub motd: Option<String>,
}

impl Clan {
    /// Create a new clan.
    pub fn new(id: u64, name: String, tag: String, leader_id: u64, leader_name: String) -> Self {
        let mut members = HashMap::new();
        members.insert(
            leader_id,
            ClanMember::new(leader_id, leader_name, ClanRank::Leader),
        );

        Self {
            id,
            name,
            tag,
            members,
            pending_invites: HashMap::new(),
            settings: ClanSettings::default(),
            created_at: Instant::now(),
            motd: None,
        }
    }

    /// Get member count.
    pub fn member_count(&self) -> usize {
        self.members.len()
    }

    /// Get online member count.
    pub fn online_count(&self) -> usize {
        self.members.values().filter(|m| m.online).count()
    }

    /// Get a member by ID.
    pub fn get_member(&self, player_id: u64) -> Option<&ClanMember> {
        self.members.get(&player_id)
    }

    /// Get a mutable member by ID.
    pub fn get_member_mut(&mut self, player_id: u64) -> Option<&mut ClanMember> {
        self.members.get_mut(&player_id)
    }

    /// Check if player is a member.
    pub fn is_member(&self, player_id: u64) -> bool {
        self.members.contains_key(&player_id)
    }

    /// Get clan leader.
    pub fn get_leader(&self) -> Option<&ClanMember> {
        self.members.values().find(|m| m.rank == ClanRank::Leader)
    }

    /// Add a new member.
    pub fn add_member(&mut self, player_id: u64, name: String) -> Result<(), &'static str> {
        if self.members.contains_key(&player_id) {
            return Err("Player is already a member");
        }

        self.members.insert(
            player_id,
            ClanMember::new(player_id, name, ClanRank::Member),
        );
        self.pending_invites.remove(&player_id);
        Ok(())
    }

    /// Remove a member.
    pub fn remove_member(&mut self, player_id: u64) -> Result<(), &'static str> {
        let member = self
            .members
            .get(&player_id)
            .ok_or("Player is not a member")?;

        if member.rank == ClanRank::Leader {
            return Err("Cannot remove the clan leader");
        }

        self.members.remove(&player_id);
        Ok(())
    }

    /// Set member rank.
    pub fn set_rank(&mut self, player_id: u64, new_rank: ClanRank) -> Result<(), &'static str> {
        let member = self
            .members
            .get_mut(&player_id)
            .ok_or("Player is not a member")?;

        if member.rank == ClanRank::Leader && new_rank != ClanRank::Leader {
            return Err("Cannot demote the clan leader");
        }

        member.rank = new_rank;
        Ok(())
    }

    /// Transfer leadership.
    pub fn transfer_leadership(
        &mut self,
        current_leader: u64,
        new_leader: u64,
    ) -> Result<(), &'static str> {
        // Verify current leader
        let leader = self
            .members
            .get(&current_leader)
            .ok_or("Current leader not found")?;
        if leader.rank != ClanRank::Leader {
            return Err("Player is not the clan leader");
        }

        // Verify new leader is a member
        if !self.members.contains_key(&new_leader) {
            return Err("New leader must be a clan member");
        }

        // Demote old leader
        self.members.get_mut(&current_leader).unwrap().rank = ClanRank::General;

        // Promote new leader
        self.members.get_mut(&new_leader).unwrap().rank = ClanRank::Leader;

        Ok(())
    }

    /// Add pending invite.
    pub fn add_invite(&mut self, player_id: u64, inviter_id: u64) {
        self.pending_invites.insert(player_id, inviter_id);
    }

    /// Check if player has pending invite.
    pub fn has_invite(&self, player_id: u64) -> bool {
        self.pending_invites.contains_key(&player_id)
    }

    /// Remove pending invite.
    pub fn remove_invite(&mut self, player_id: u64) {
        self.pending_invites.remove(&player_id);
    }

    /// Set player online status.
    pub fn set_online(&mut self, player_id: u64, online: bool) {
        if let Some(member) = self.members.get_mut(&player_id) {
            member.online = online;
        }
    }

    /// Get all members.
    pub fn members(&self) -> impl Iterator<Item = &ClanMember> {
        self.members.values()
    }

    /// Get members sorted by rank.
    pub fn members_by_rank(&self) -> Vec<&ClanMember> {
        let mut members: Vec<_> = self.members.values().collect();
        members.sort_by(|a, b| b.rank.cmp(&a.rank));
        members
    }
}

/// Manager for clan system.
#[derive(Debug, Default)]
pub struct ClanManager {
    /// Clans by ID.
    clans: HashMap<u64, Clan>,
    /// Player to clan mapping.
    player_clans: HashMap<u64, u64>,
    /// Next clan ID.
    next_id: u64,
}

impl ClanManager {
    /// Create a new clan manager.
    pub fn new() -> Self {
        Self {
            clans: HashMap::new(),
            player_clans: HashMap::new(),
            next_id: 1,
        }
    }

    /// Create a new clan.
    pub fn create_clan(
        &mut self,
        name: String,
        tag: String,
        leader_id: u64,
        leader_name: String,
    ) -> Result<u64, &'static str> {
        // Check if player is already in a clan
        if self.player_clans.contains_key(&leader_id) {
            return Err("Player is already in a clan");
        }

        // Check for duplicate name
        if self.clans.values().any(|c| c.name == name) {
            return Err("Clan name already exists");
        }

        let id = self.next_id;
        self.next_id += 1;

        let clan = Clan::new(id, name, tag, leader_id, leader_name);
        self.clans.insert(id, clan);
        self.player_clans.insert(leader_id, id);

        info!(
            "Created clan {} with ID {}",
            self.clans.get(&id).unwrap().name,
            id
        );
        Ok(id)
    }

    /// Get clan by ID.
    pub fn get_clan(&self, clan_id: u64) -> Option<&Clan> {
        self.clans.get(&clan_id)
    }

    /// Get mutable clan by ID.
    pub fn get_clan_mut(&mut self, clan_id: u64) -> Option<&mut Clan> {
        self.clans.get_mut(&clan_id)
    }

    /// Get player's clan.
    pub fn get_player_clan(&self, player_id: u64) -> Option<&Clan> {
        self.player_clans
            .get(&player_id)
            .and_then(|id| self.clans.get(id))
    }

    /// Get player's clan ID.
    pub fn get_player_clan_id(&self, player_id: u64) -> Option<u64> {
        self.player_clans.get(&player_id).copied()
    }

    /// Join a clan.
    pub fn join_clan(
        &mut self,
        player_id: u64,
        player_name: String,
        clan_id: u64,
    ) -> Result<(), &'static str> {
        if self.player_clans.contains_key(&player_id) {
            return Err("Player is already in a clan");
        }

        let clan = self.clans.get_mut(&clan_id).ok_or("Clan not found")?;

        if !clan.has_invite(player_id) {
            return Err("Player does not have an invite");
        }

        clan.add_member(player_id, player_name)?;
        self.player_clans.insert(player_id, clan_id);
        Ok(())
    }

    /// Leave a clan.
    pub fn leave_clan(&mut self, player_id: u64) -> Result<(), &'static str> {
        let clan_id = self
            .player_clans
            .get(&player_id)
            .copied()
            .ok_or("Player is not in a clan")?;
        let clan = self.clans.get_mut(&clan_id).ok_or("Clan not found")?;

        clan.remove_member(player_id)?;
        self.player_clans.remove(&player_id);

        // Check if clan is now empty
        if clan.member_count() == 0 {
            self.clans.remove(&clan_id);
            info!("Clan {} disbanded (no members)", clan_id);
        }

        Ok(())
    }

    /// Disband a clan.
    pub fn disband_clan(&mut self, clan_id: u64, requester_id: u64) -> Result<(), &'static str> {
        let clan = self.clans.get(&clan_id).ok_or("Clan not found")?;

        // Only leader can disband
        let leader = clan.get_leader().ok_or("No leader found")?;
        if leader.player_id != requester_id {
            return Err("Only the leader can disband the clan");
        }

        // Remove all members from player_clans
        let member_ids: Vec<_> = clan.members().map(|m| m.player_id).collect();
        for id in member_ids {
            self.player_clans.remove(&id);
        }

        self.clans.remove(&clan_id);
        info!("Clan {} disbanded", clan_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clan_creation() {
        let mut manager = ClanManager::new();
        let result = manager.create_clan(
            "Test Clan".to_string(),
            "TC".to_string(),
            1,
            "Leader".to_string(),
        );
        assert!(result.is_ok());

        let clan = manager.get_clan(result.unwrap()).unwrap();
        assert_eq!(clan.name, "Test Clan");
        assert_eq!(clan.member_count(), 1);
    }

    #[test]
    fn test_clan_ranks() {
        assert!(ClanRank::Leader > ClanRank::General);
        assert!(ClanRank::General > ClanRank::Member);
        assert!(ClanRank::Corporal.can_invite());
        assert!(!ClanRank::Member.can_invite());
    }

    #[test]
    fn test_member_management() {
        let mut clan = Clan::new(
            1,
            "Test".to_string(),
            "T".to_string(),
            1,
            "Leader".to_string(),
        );

        // Add member
        assert!(clan.add_member(2, "Member".to_string()).is_ok());
        assert_eq!(clan.member_count(), 2);

        // Cannot add duplicate
        assert!(clan.add_member(2, "Member".to_string()).is_err());

        // Remove member
        assert!(clan.remove_member(2).is_ok());
        assert_eq!(clan.member_count(), 1);

        // Cannot remove leader
        assert!(clan.remove_member(1).is_err());
    }
}
