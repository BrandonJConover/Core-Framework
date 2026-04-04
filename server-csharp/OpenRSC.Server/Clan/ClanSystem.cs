using System.Collections.Concurrent;
using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Clan;

/// <summary>
/// Clan member rank.
/// </summary>
public enum ClanRank
{
    Member = 0,
    Corporal = 1,
    Sergeant = 2,
    Lieutenant = 3,
    Captain = 4,
    General = 5,
    Leader = 6
}

/// <summary>
/// Clan permissions based on rank.
/// </summary>
[Flags]
public enum ClanPermission
{
    None = 0,
    Invite = 1 << 0,
    Kick = 1 << 1,
    EditMotd = 1 << 2,
    EditRanks = 1 << 3,
    AllowGuests = 1 << 4,
    ManageSettings = 1 << 5,
    DisbandClan = 1 << 6
}

/// <summary>
/// Clan member information.
/// </summary>
public sealed class ClanMember
{
    public required long PlayerId { get; init; }
    public required string Username { get; set; }
    public ClanRank Rank { get; set; }
    public DateTime JoinDate { get; init; }
    public DateTime LastSeen { get; set; }
    public bool IsOnline { get; set; }

    public static ClanMember Create(Player player, ClanRank rank = ClanRank.Member)
    {
        return new ClanMember
        {
            PlayerId = player.UsernameHash,
            Username = player.Username,
            Rank = rank,
            JoinDate = DateTime.UtcNow,
            LastSeen = DateTime.UtcNow,
            IsOnline = true
        };
    }
}

/// <summary>
/// Clan settings.
/// </summary>
public sealed class ClanSettings
{
    public ClanRank MinRankToInvite { get; set; } = ClanRank.Lieutenant;
    public ClanRank MinRankToKick { get; set; } = ClanRank.Captain;
    public ClanRank MinRankToEditMotd { get; set; } = ClanRank.General;
    public bool AllowGuests { get; set; } = true;
    public bool IsRecruiting { get; set; } = true;

    public static readonly IReadOnlyDictionary<ClanRank, ClanPermission> DefaultPermissions = new Dictionary<ClanRank, ClanPermission>
    {
        [ClanRank.Member] = ClanPermission.None,
        [ClanRank.Corporal] = ClanPermission.None,
        [ClanRank.Sergeant] = ClanPermission.AllowGuests,
        [ClanRank.Lieutenant] = ClanPermission.Invite | ClanPermission.AllowGuests,
        [ClanRank.Captain] = ClanPermission.Invite | ClanPermission.Kick | ClanPermission.AllowGuests,
        [ClanRank.General] = ClanPermission.Invite | ClanPermission.Kick | ClanPermission.EditMotd | ClanPermission.EditRanks | ClanPermission.AllowGuests | ClanPermission.ManageSettings,
        [ClanRank.Leader] = ClanPermission.Invite | ClanPermission.Kick | ClanPermission.EditMotd | ClanPermission.EditRanks | ClanPermission.AllowGuests | ClanPermission.ManageSettings | ClanPermission.DisbandClan
    };
}

/// <summary>
/// Represents a clan.
/// </summary>
public sealed class Clan
{
    private readonly List<ClanMember> _members = new();
    private readonly HashSet<long> _bannedPlayers = new();

    public int Id { get; init; }
    public string Name { get; set; }
    public string Tag { get; set; }
    public string? Motd { get; set; }
    public long LeaderId { get; private set; }
    public DateTime CreatedDate { get; init; }
    public ClanSettings Settings { get; } = new();

    public IReadOnlyList<ClanMember> Members => _members;
    public int MemberCount => _members.Count;
    public int OnlineCount => _members.Count(m => m.IsOnline);

    public Clan(int id, string name, string tag, Player leader)
    {
        Id = id;
        Name = name;
        Tag = tag;
        LeaderId = leader.UsernameHash;
        CreatedDate = DateTime.UtcNow;

        // Add leader as first member
        _members.Add(ClanMember.Create(leader, ClanRank.Leader));
    }

    /// <summary>
    /// Gets a member by player ID.
    /// </summary>
    public ClanMember? GetMember(long playerId)
    {
        return _members.FirstOrDefault(m => m.PlayerId == playerId);
    }

    /// <summary>
    /// Gets a member by player.
    /// </summary>
    public ClanMember? GetMember(Player player)
    {
        return GetMember(player.UsernameHash);
    }

    /// <summary>
    /// Checks if player is a member.
    /// </summary>
    public bool IsMember(Player player)
    {
        return GetMember(player) is not null;
    }

    /// <summary>
    /// Checks if player is banned.
    /// </summary>
    public bool IsBanned(Player player)
    {
        return _bannedPlayers.Contains(player.UsernameHash);
    }

    /// <summary>
    /// Adds a member to the clan.
    /// </summary>
    public ClanResult AddMember(Player player, ClanRank rank = ClanRank.Member)
    {
        if (IsMember(player))
            return ClanResult.Fail("Player is already a member.");

        if (IsBanned(player))
            return ClanResult.Fail("Player is banned from this clan.");

        _members.Add(ClanMember.Create(player, rank));
        BroadcastMessage($"{player.Username} has joined the clan!");

        return ClanResult.Ok;
    }

    /// <summary>
    /// Removes a member from the clan.
    /// </summary>
    public ClanResult RemoveMember(Player player, bool isBan = false)
    {
        var member = GetMember(player);
        if (member is null)
            return ClanResult.Fail("Player is not a member.");

        if (member.Rank == ClanRank.Leader)
            return ClanResult.Fail("Cannot remove the clan leader.");

        _members.Remove(member);

        if (isBan)
        {
            _bannedPlayers.Add(player.UsernameHash);
            BroadcastMessage($"{player.Username} has been banned from the clan.");
        }
        else
        {
            BroadcastMessage($"{player.Username} has left the clan.");
        }

        return ClanResult.Ok;
    }

    /// <summary>
    /// Sets a member's rank.
    /// </summary>
    public ClanResult SetRank(Player player, ClanRank newRank)
    {
        var member = GetMember(player);
        if (member is null)
            return ClanResult.Fail("Player is not a member.");

        if (newRank == ClanRank.Leader)
            return ClanResult.Fail("Use TransferLeadership to change leaders.");

        var oldRank = member.Rank;
        member.Rank = newRank;

        BroadcastMessage($"{player.Username} has been promoted from {oldRank} to {newRank}.");

        return ClanResult.Ok;
    }

    /// <summary>
    /// Transfers leadership to another member.
    /// </summary>
    public ClanResult TransferLeadership(Player currentLeader, Player newLeader)
    {
        var current = GetMember(currentLeader);
        var target = GetMember(newLeader);

        if (current?.Rank != ClanRank.Leader)
            return ClanResult.Fail("Only the leader can transfer leadership.");

        if (target is null)
            return ClanResult.Fail("Target is not a member.");

        current.Rank = ClanRank.General;
        target.Rank = ClanRank.Leader;
        LeaderId = newLeader.UsernameHash;

        BroadcastMessage($"{newLeader.Username} is now the clan leader!");

        return ClanResult.Ok;
    }

    /// <summary>
    /// Unbans a player.
    /// </summary>
    public ClanResult Unban(long playerId)
    {
        if (_bannedPlayers.Remove(playerId))
            return ClanResult.Ok;

        return ClanResult.Fail("Player is not banned.");
    }

    /// <summary>
    /// Checks if a member has a permission.
    /// </summary>
    public bool HasPermission(Player player, ClanPermission permission)
    {
        var member = GetMember(player);
        if (member is null)
            return false;

        var rankPermissions = ClanSettings.DefaultPermissions.GetValueOrDefault(member.Rank, ClanPermission.None);
        return rankPermissions.HasFlag(permission);
    }

    /// <summary>
    /// Broadcasts a message to all online members.
    /// </summary>
    public void BroadcastMessage(string message)
    {
        foreach (var member in _members.Where(m => m.IsOnline))
        {
            // Would send to player - need player reference
        }
    }

    /// <summary>
    /// Updates member online status.
    /// </summary>
    public void SetMemberOnline(Player player, bool online)
    {
        var member = GetMember(player);
        if (member is not null)
        {
            member.IsOnline = online;
            member.LastSeen = DateTime.UtcNow;
        }
    }
}

/// <summary>
/// Result of a clan operation.
/// </summary>
public readonly record struct ClanResult(bool Success, string? Message = null)
{
    public static ClanResult Fail(string message) => new(false, message);
    public static readonly ClanResult Ok = new(true);
}

/// <summary>
/// Clan invite.
/// </summary>
public sealed class ClanInvite
{
    public required Clan Clan { get; init; }
    public required Player Inviter { get; init; }
    public required Player Target { get; init; }
    public DateTime ExpiresAt { get; init; }

    public bool IsExpired => DateTime.UtcNow > ExpiresAt;
}

/// <summary>
/// Manages all clans.
/// </summary>
public sealed class ClanManager
{
    private readonly ConcurrentDictionary<int, Clan> _clans = new();
    private readonly ConcurrentDictionary<long, int> _playerClans = new(); // PlayerId -> ClanId
    private readonly ConcurrentDictionary<long, ClanInvite> _pendingInvites = new();
    private int _nextClanId = 1;

    /// <summary>
    /// Creates a new clan.
    /// </summary>
    public ClanResult CreateClan(Player leader, string name, string tag)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length < 3 || name.Length > 20)
            return ClanResult.Fail("Clan name must be between 3 and 20 characters.");

        if (string.IsNullOrWhiteSpace(tag) || tag.Length < 2 || tag.Length > 5)
            return ClanResult.Fail("Clan tag must be between 2 and 5 characters.");

        if (_playerClans.ContainsKey(leader.UsernameHash))
            return ClanResult.Fail("You are already in a clan.");

        if (_clans.Values.Any(c => c.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
            return ClanResult.Fail("A clan with that name already exists.");

        if (_clans.Values.Any(c => c.Tag.Equals(tag, StringComparison.OrdinalIgnoreCase)))
            return ClanResult.Fail("A clan with that tag already exists.");

        var clanId = Interlocked.Increment(ref _nextClanId);
        var clan = new Clan(clanId, name, tag, leader);

        _clans[clanId] = clan;
        _playerClans[leader.UsernameHash] = clanId;

        leader.Message($"You have created the clan '{name}' [{tag}]!");

        return ClanResult.Ok;
    }

    /// <summary>
    /// Disbands a clan.
    /// </summary>
    public ClanResult DisbandClan(Player leader)
    {
        var clan = GetPlayerClan(leader);
        if (clan is null)
            return ClanResult.Fail("You are not in a clan.");

        if (!clan.HasPermission(leader, ClanPermission.DisbandClan))
            return ClanResult.Fail("You don't have permission to disband the clan.");

        // Remove all members
        foreach (var member in clan.Members)
        {
            _playerClans.TryRemove(member.PlayerId, out _);
        }

        _clans.TryRemove(clan.Id, out _);

        return ClanResult.Ok;
    }

    /// <summary>
    /// Gets the clan a player is in.
    /// </summary>
    public Clan? GetPlayerClan(Player player)
    {
        if (_playerClans.TryGetValue(player.UsernameHash, out var clanId))
        {
            return _clans.GetValueOrDefault(clanId);
        }
        return null;
    }

    /// <summary>
    /// Invites a player to a clan.
    /// </summary>
    public ClanResult InvitePlayer(Player inviter, Player target)
    {
        var clan = GetPlayerClan(inviter);
        if (clan is null)
            return ClanResult.Fail("You are not in a clan.");

        if (!clan.HasPermission(inviter, ClanPermission.Invite))
            return ClanResult.Fail("You don't have permission to invite players.");

        if (GetPlayerClan(target) is not null)
            return ClanResult.Fail("That player is already in a clan.");

        if (clan.IsBanned(target))
            return ClanResult.Fail("That player is banned from your clan.");

        if (_pendingInvites.ContainsKey(target.UsernameHash))
            return ClanResult.Fail("That player already has a pending invite.");

        var invite = new ClanInvite
        {
            Clan = clan,
            Inviter = inviter,
            Target = target,
            ExpiresAt = DateTime.UtcNow.AddMinutes(5)
        };

        _pendingInvites[target.UsernameHash] = invite;

        target.Message($"{inviter.Username} has invited you to join '{clan.Name}'. Type /clanaccept to join.");
        inviter.Message($"Clan invite sent to {target.Username}.");

        return ClanResult.Ok;
    }

    /// <summary>
    /// Accepts a clan invite.
    /// </summary>
    public ClanResult AcceptInvite(Player player)
    {
        if (!_pendingInvites.TryRemove(player.UsernameHash, out var invite))
            return ClanResult.Fail("You don't have a pending clan invite.");

        if (invite.IsExpired)
            return ClanResult.Fail("The invite has expired.");

        var result = invite.Clan.AddMember(player);
        if (result.Success)
        {
            _playerClans[player.UsernameHash] = invite.Clan.Id;
        }

        return result;
    }

    /// <summary>
    /// Declines a clan invite.
    /// </summary>
    public ClanResult DeclineInvite(Player player)
    {
        if (!_pendingInvites.TryRemove(player.UsernameHash, out var invite))
            return ClanResult.Fail("You don't have a pending clan invite.");

        invite.Inviter.Message($"{player.Username} has declined your clan invite.");
        player.Message("You decline the clan invite.");

        return ClanResult.Ok;
    }

    /// <summary>
    /// Player leaves their clan.
    /// </summary>
    public ClanResult LeaveClan(Player player)
    {
        var clan = GetPlayerClan(player);
        if (clan is null)
            return ClanResult.Fail("You are not in a clan.");

        var member = clan.GetMember(player);
        if (member?.Rank == ClanRank.Leader)
            return ClanResult.Fail("Leaders must transfer leadership or disband the clan.");

        var result = clan.RemoveMember(player);
        if (result.Success)
        {
            _playerClans.TryRemove(player.UsernameHash, out _);
            player.Message($"You have left {clan.Name}.");
        }

        return result;
    }

    /// <summary>
    /// Kicks a player from a clan.
    /// </summary>
    public ClanResult KickMember(Player kicker, Player target)
    {
        var clan = GetPlayerClan(kicker);
        if (clan is null)
            return ClanResult.Fail("You are not in a clan.");

        if (!clan.HasPermission(kicker, ClanPermission.Kick))
            return ClanResult.Fail("You don't have permission to kick members.");

        var kickerMember = clan.GetMember(kicker);
        var targetMember = clan.GetMember(target);

        if (targetMember is null)
            return ClanResult.Fail("That player is not in your clan.");

        if (targetMember.Rank >= kickerMember!.Rank)
            return ClanResult.Fail("You cannot kick someone of equal or higher rank.");

        var result = clan.RemoveMember(target, isBan: false);
        if (result.Success)
        {
            _playerClans.TryRemove(target.UsernameHash, out _);
            target.Message($"You have been kicked from {clan.Name}.");
        }

        return result;
    }

    /// <summary>
    /// Gets a clan by name.
    /// </summary>
    public Clan? GetClanByName(string name)
    {
        return _clans.Values.FirstOrDefault(c => c.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Handles player login.
    /// </summary>
    public void OnPlayerLogin(Player player)
    {
        var clan = GetPlayerClan(player);
        clan?.SetMemberOnline(player, true);
    }

    /// <summary>
    /// Handles player logout.
    /// </summary>
    public void OnPlayerLogout(Player player)
    {
        var clan = GetPlayerClan(player);
        clan?.SetMemberOnline(player, false);
    }
}
