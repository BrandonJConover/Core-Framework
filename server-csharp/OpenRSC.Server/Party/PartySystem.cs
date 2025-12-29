using System.Collections.Concurrent;
using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Party;

/// <summary>
/// Party member role.
/// </summary>
public enum PartyRole
{
    Member,
    Leader
}

/// <summary>
/// Loot distribution mode.
/// </summary>
public enum LootMode
{
    FreeForAll,
    RoundRobin,
    Random,
    LeaderDecides
}

/// <summary>
/// Experience sharing mode.
/// </summary>
public enum XpShareMode
{
    None,
    Equal,
    ByDamage
}

/// <summary>
/// Party settings.
/// </summary>
public sealed class PartySettings
{
    public LootMode LootMode { get; set; } = LootMode.FreeForAll;
    public XpShareMode XpShareMode { get; set; } = XpShareMode.None;
    public bool AllowInvites { get; set; } = true;
    public int MaxMembers { get; set; } = 5;
}

/// <summary>
/// A party member.
/// </summary>
public sealed class PartyMember
{
    public required Player Player { get; init; }
    public PartyRole Role { get; set; }
    public DateTime JoinedAt { get; init; }

    public static PartyMember Create(Player player, PartyRole role = PartyRole.Member)
    {
        return new PartyMember
        {
            Player = player,
            Role = role,
            JoinedAt = DateTime.UtcNow
        };
    }
}

/// <summary>
/// Result of a party operation.
/// </summary>
public readonly record struct PartyResult(bool Success, string? Message = null)
{
    public static PartyResult Fail(string message) => new(false, message);
    public static readonly PartyResult Ok = new(true);
}

/// <summary>
/// Represents a player party.
/// </summary>
public sealed class Party
{
    private readonly List<PartyMember> _members = new();
    private int _roundRobinIndex;

    public Guid Id { get; } = Guid.NewGuid();
    public PartySettings Settings { get; } = new();
    public IReadOnlyList<PartyMember> Members => _members;
    public int MemberCount => _members.Count;

    public PartyMember? Leader => _members.FirstOrDefault(m => m.Role == PartyRole.Leader);

    public Party(Player leader)
    {
        _members.Add(PartyMember.Create(leader, PartyRole.Leader));
    }

    /// <summary>
    /// Gets a member by player.
    /// </summary>
    public PartyMember? GetMember(Player player)
    {
        return _members.FirstOrDefault(m => m.Player == player);
    }

    /// <summary>
    /// Checks if player is in party.
    /// </summary>
    public bool IsMember(Player player)
    {
        return GetMember(player) is not null;
    }

    /// <summary>
    /// Checks if player is the leader.
    /// </summary>
    public bool IsLeader(Player player)
    {
        return GetMember(player)?.Role == PartyRole.Leader;
    }

    /// <summary>
    /// Adds a player to the party.
    /// </summary>
    public PartyResult AddMember(Player player)
    {
        if (IsMember(player))
            return PartyResult.Fail("Player is already in the party.");

        if (_members.Count >= Settings.MaxMembers)
            return PartyResult.Fail("Party is full.");

        _members.Add(PartyMember.Create(player));
        BroadcastMessage($"{player.Username} has joined the party!");

        return PartyResult.Ok;
    }

    /// <summary>
    /// Removes a player from the party.
    /// </summary>
    public PartyResult RemoveMember(Player player)
    {
        var member = GetMember(player);
        if (member is null)
            return PartyResult.Fail("Player is not in the party.");

        if (member.Role == PartyRole.Leader && _members.Count > 1)
        {
            // Transfer leadership to next member
            var newLeader = _members.First(m => m != member);
            newLeader.Role = PartyRole.Leader;
            BroadcastMessage($"{newLeader.Player.Username} is now the party leader.");
        }

        _members.Remove(member);
        BroadcastMessage($"{player.Username} has left the party.");

        return PartyResult.Ok;
    }

    /// <summary>
    /// Transfers leadership to another member.
    /// </summary>
    public PartyResult TransferLeadership(Player currentLeader, Player newLeader)
    {
        var current = GetMember(currentLeader);
        var target = GetMember(newLeader);

        if (current?.Role != PartyRole.Leader)
            return PartyResult.Fail("Only the leader can transfer leadership.");

        if (target is null)
            return PartyResult.Fail("Target is not in the party.");

        current.Role = PartyRole.Member;
        target.Role = PartyRole.Leader;

        BroadcastMessage($"{newLeader.Username} is now the party leader!");

        return PartyResult.Ok;
    }

    /// <summary>
    /// Gets the next player for round-robin loot.
    /// </summary>
    public Player GetNextLootRecipient()
    {
        if (_members.Count == 0)
            throw new InvalidOperationException("Party has no members.");

        var member = _members[_roundRobinIndex % _members.Count];
        _roundRobinIndex++;
        return member.Player;
    }

    /// <summary>
    /// Distributes XP to party members.
    /// </summary>
    public void DistributeXp(int totalXp, Skills.Skill skill, Dictionary<Player, int>? damageDealt = null)
    {
        switch (Settings.XpShareMode)
        {
            case XpShareMode.None:
                // XP goes to whoever earned it (handled externally)
                break;

            case XpShareMode.Equal:
                var xpPerMember = totalXp / _members.Count;
                foreach (var member in _members)
                {
                    member.Player.Skills.AddExperience(skill, xpPerMember);
                }
                break;

            case XpShareMode.ByDamage:
                if (damageDealt is not null)
                {
                    var totalDamage = damageDealt.Values.Sum();
                    if (totalDamage > 0)
                    {
                        foreach (var (player, damage) in damageDealt)
                        {
                            if (IsMember(player))
                            {
                                var xpShare = (int)(totalXp * ((double)damage / totalDamage));
                                player.Skills.AddExperience(skill, xpShare);
                            }
                        }
                    }
                }
                break;
        }
    }

    /// <summary>
    /// Broadcasts a message to all party members.
    /// </summary>
    public void BroadcastMessage(string message)
    {
        foreach (var member in _members)
        {
            member.Player.Message($"[Party] {message}");
        }
    }

    /// <summary>
    /// Gets all players within range of a location.
    /// </summary>
    public IEnumerable<Player> GetMembersInRange(Models.Point location, int range)
    {
        return _members
            .Where(m => m.Player.Location.WithinRange(location, range))
            .Select(m => m.Player);
    }
}

/// <summary>
/// Party invite.
/// </summary>
public sealed class PartyInvite
{
    public required Party Party { get; init; }
    public required Player Inviter { get; init; }
    public required Player Target { get; init; }
    public DateTime ExpiresAt { get; init; }

    public bool IsExpired => DateTime.UtcNow > ExpiresAt;
}

/// <summary>
/// Manages all parties.
/// </summary>
public sealed class PartyManager
{
    private readonly ConcurrentDictionary<Guid, Party> _parties = new();
    private readonly ConcurrentDictionary<Player, Guid> _playerParties = new();
    private readonly ConcurrentDictionary<Player, PartyInvite> _pendingInvites = new();

    /// <summary>
    /// Creates a new party.
    /// </summary>
    public PartyResult CreateParty(Player leader)
    {
        if (_playerParties.ContainsKey(leader))
            return PartyResult.Fail("You are already in a party.");

        var party = new Party(leader);
        _parties[party.Id] = party;
        _playerParties[leader] = party.Id;

        leader.Message("You have created a party.");

        return PartyResult.Ok;
    }

    /// <summary>
    /// Gets a player's party.
    /// </summary>
    public Party? GetPlayerParty(Player player)
    {
        if (_playerParties.TryGetValue(player, out var partyId))
        {
            return _parties.GetValueOrDefault(partyId);
        }
        return null;
    }

    /// <summary>
    /// Invites a player to a party.
    /// </summary>
    public PartyResult InvitePlayer(Player inviter, Player target)
    {
        var party = GetPlayerParty(inviter);
        if (party is null)
        {
            // Create party first
            var createResult = CreateParty(inviter);
            if (!createResult.Success)
                return createResult;

            party = GetPlayerParty(inviter)!;
        }

        if (!party.IsLeader(inviter) && !party.Settings.AllowInvites)
            return PartyResult.Fail("Only the leader can invite players.");

        if (GetPlayerParty(target) is not null)
            return PartyResult.Fail("That player is already in a party.");

        if (_pendingInvites.ContainsKey(target))
            return PartyResult.Fail("That player already has a pending invite.");

        var invite = new PartyInvite
        {
            Party = party,
            Inviter = inviter,
            Target = target,
            ExpiresAt = DateTime.UtcNow.AddMinutes(2)
        };

        _pendingInvites[target] = invite;

        target.Message($"{inviter.Username} has invited you to join their party. Type /partyaccept to join.");
        inviter.Message($"Party invite sent to {target.Username}.");

        return PartyResult.Ok;
    }

    /// <summary>
    /// Accepts a party invite.
    /// </summary>
    public PartyResult AcceptInvite(Player player)
    {
        if (!_pendingInvites.TryRemove(player, out var invite))
            return PartyResult.Fail("You don't have a pending party invite.");

        if (invite.IsExpired)
            return PartyResult.Fail("The invite has expired.");

        var result = invite.Party.AddMember(player);
        if (result.Success)
        {
            _playerParties[player] = invite.Party.Id;
        }

        return result;
    }

    /// <summary>
    /// Declines a party invite.
    /// </summary>
    public PartyResult DeclineInvite(Player player)
    {
        if (!_pendingInvites.TryRemove(player, out var invite))
            return PartyResult.Fail("You don't have a pending party invite.");

        invite.Inviter.Message($"{player.Username} has declined your party invite.");
        player.Message("You decline the party invite.");

        return PartyResult.Ok;
    }

    /// <summary>
    /// Player leaves their party.
    /// </summary>
    public PartyResult LeaveParty(Player player)
    {
        var party = GetPlayerParty(player);
        if (party is null)
            return PartyResult.Fail("You are not in a party.");

        var result = party.RemoveMember(player);
        if (result.Success)
        {
            _playerParties.TryRemove(player, out _);

            // Disband if empty
            if (party.MemberCount == 0)
            {
                _parties.TryRemove(party.Id, out _);
            }

            player.Message("You have left the party.");
        }

        return result;
    }

    /// <summary>
    /// Kicks a player from a party.
    /// </summary>
    public PartyResult KickMember(Player kicker, Player target)
    {
        var party = GetPlayerParty(kicker);
        if (party is null)
            return PartyResult.Fail("You are not in a party.");

        if (!party.IsLeader(kicker))
            return PartyResult.Fail("Only the party leader can kick members.");

        if (kicker == target)
            return PartyResult.Fail("You cannot kick yourself.");

        var result = party.RemoveMember(target);
        if (result.Success)
        {
            _playerParties.TryRemove(target, out _);
            target.Message("You have been kicked from the party.");
        }

        return result;
    }

    /// <summary>
    /// Disbands a party.
    /// </summary>
    public PartyResult DisbandParty(Player leader)
    {
        var party = GetPlayerParty(leader);
        if (party is null)
            return PartyResult.Fail("You are not in a party.");

        if (!party.IsLeader(leader))
            return PartyResult.Fail("Only the party leader can disband the party.");

        party.BroadcastMessage("The party has been disbanded.");

        foreach (var member in party.Members)
        {
            _playerParties.TryRemove(member.Player, out _);
        }

        _parties.TryRemove(party.Id, out _);

        return PartyResult.Ok;
    }

    /// <summary>
    /// Handles player logout.
    /// </summary>
    public void OnPlayerLogout(Player player)
    {
        LeaveParty(player);
        _pendingInvites.TryRemove(player, out _);
    }
}
