using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Duel;

/// <summary>
/// Duel rule settings.
/// </summary>
[Flags]
public enum DuelRules
{
    None = 0,
    NoRetreat = 1 << 0,
    NoMagic = 1 << 1,
    NoPrayer = 1 << 2,
    NoWeapons = 1 << 3,
    NoRanged = 1 << 4,
    NoMelee = 1 << 5
}

/// <summary>
/// State of a duel session.
/// </summary>
public enum DuelState
{
    Requesting,
    Configuring,
    FirstConfirm,
    SecondConfirm,
    Fighting,
    Completed
}

/// <summary>
/// Result of a duel action.
/// </summary>
public readonly record struct DuelResult(bool Success, string? Message = null)
{
    public static DuelResult Fail(string message) => new(false, message);
    public static readonly DuelResult Ok = new(true);
}

/// <summary>
/// Manages a duel between two players.
/// </summary>
public sealed class DuelSession
{
    private readonly Player _player1;
    private readonly Player _player2;
    private readonly List<Item> _player1Stake = new();
    private readonly List<Item> _player2Stake = new();

    public DuelState State { get; private set; }
    public DuelRules Rules { get; private set; }

    public bool Player1Accepted { get; private set; }
    public bool Player2Accepted { get; private set; }
    public bool Player1Confirmed { get; private set; }
    public bool Player2Confirmed { get; private set; }

    public Player Player1 => _player1;
    public Player Player2 => _player2;
    public IReadOnlyList<Item> Player1Stake => _player1Stake;
    public IReadOnlyList<Item> Player2Stake => _player2Stake;

    public DuelSession(Player player1, Player player2)
    {
        _player1 = player1;
        _player2 = player2;
        State = DuelState.Configuring;
    }

    /// <summary>
    /// Gets the opponent of a player.
    /// </summary>
    public Player GetOpponent(Player player)
    {
        return player == _player1 ? _player2 : _player1;
    }

    /// <summary>
    /// Checks if player is part of this duel.
    /// </summary>
    public bool IsParticipant(Player player)
    {
        return player == _player1 || player == _player2;
    }

    /// <summary>
    /// Toggles a duel rule.
    /// </summary>
    public DuelResult ToggleRule(Player player, DuelRules rule)
    {
        if (State != DuelState.Configuring)
            return DuelResult.Fail("Cannot change rules now.");

        if (!IsParticipant(player))
            return DuelResult.Fail("You are not in this duel.");

        if (Rules.HasFlag(rule))
            Rules &= ~rule;
        else
            Rules |= rule;

        // Reset acceptance when rules change
        Player1Accepted = false;
        Player2Accepted = false;

        var opponent = GetOpponent(player);
        opponent.Message($"Duel rules have been modified.");

        return DuelResult.Ok;
    }

    /// <summary>
    /// Adds item to stake.
    /// </summary>
    public DuelResult AddStake(Player player, int itemId, int amount)
    {
        if (State != DuelState.Configuring)
            return DuelResult.Fail("Cannot modify stakes now.");

        if (!IsParticipant(player))
            return DuelResult.Fail("You are not in this duel.");

        if (!player.Inventory.HasItem(itemId, amount))
            return DuelResult.Fail("You don't have enough of that item.");

        var stake = player == _player1 ? _player1Stake : _player2Stake;

        // Check if already staked
        var existing = stake.FirstOrDefault(i => i.CatalogId == itemId);
        if (existing is not null)
        {
            // Would need to update amount
            return DuelResult.Fail("Item already staked.");
        }

        // Create stake item (would need item factory in real impl)
        var item = new Item(new ItemDefinition { Id = itemId, Name = "Staked Item", BasePrice = 0 }, amount);
        stake.Add(item);

        // Reset acceptance
        Player1Accepted = false;
        Player2Accepted = false;

        var opponent = GetOpponent(player);
        opponent.Message($"{player.Username} has modified their stake.");

        return DuelResult.Ok;
    }

    /// <summary>
    /// Removes item from stake.
    /// </summary>
    public DuelResult RemoveStake(Player player, int itemId)
    {
        if (State != DuelState.Configuring)
            return DuelResult.Fail("Cannot modify stakes now.");

        var stake = player == _player1 ? _player1Stake : _player2Stake;
        var item = stake.FirstOrDefault(i => i.CatalogId == itemId);

        if (item is null)
            return DuelResult.Fail("Item not in stake.");

        stake.Remove(item);

        Player1Accepted = false;
        Player2Accepted = false;

        return DuelResult.Ok;
    }

    /// <summary>
    /// Player accepts current rules and stakes.
    /// </summary>
    public DuelResult Accept(Player player)
    {
        if (State != DuelState.Configuring)
            return DuelResult.Fail("Cannot accept now.");

        if (player == _player1)
            Player1Accepted = true;
        else if (player == _player2)
            Player2Accepted = true;
        else
            return DuelResult.Fail("You are not in this duel.");

        var opponent = GetOpponent(player);
        opponent.Message($"{player.Username} has accepted the duel terms.");

        if (Player1Accepted && Player2Accepted)
        {
            State = DuelState.FirstConfirm;
            _player1.Message("Please confirm the duel.");
            _player2.Message("Please confirm the duel.");
        }

        return DuelResult.Ok;
    }

    /// <summary>
    /// Player confirms the duel (second screen).
    /// </summary>
    public DuelResult Confirm(Player player)
    {
        if (State != DuelState.FirstConfirm && State != DuelState.SecondConfirm)
            return DuelResult.Fail("Cannot confirm now.");

        if (player == _player1)
            Player1Confirmed = true;
        else if (player == _player2)
            Player2Confirmed = true;
        else
            return DuelResult.Fail("You are not in this duel.");

        if (Player1Confirmed && Player2Confirmed)
        {
            return StartDuel();
        }

        return DuelResult.Ok;
    }

    /// <summary>
    /// Starts the actual duel combat.
    /// </summary>
    private DuelResult StartDuel()
    {
        // Verify both players still have staked items
        foreach (var stake in _player1Stake)
        {
            if (!_player1.Inventory.HasItem(stake.CatalogId, stake.Amount))
            {
                Cancel("Player 1 no longer has the staked items.");
                return DuelResult.Fail("Duel cancelled - items removed.");
            }
        }

        foreach (var stake in _player2Stake)
        {
            if (!_player2.Inventory.HasItem(stake.CatalogId, stake.Amount))
            {
                Cancel("Player 2 no longer has the staked items.");
                return DuelResult.Fail("Duel cancelled - items removed.");
            }
        }

        // Remove staked items from inventories
        foreach (var stake in _player1Stake)
            _player1.Inventory.Remove(stake.CatalogId, stake.Amount);

        foreach (var stake in _player2Stake)
            _player2.Inventory.Remove(stake.CatalogId, stake.Amount);

        // Apply rules (unequip weapons if NoWeapons, etc.)
        ApplyDuelRules();

        State = DuelState.Fighting;

        _player1.Message("FIGHT!");
        _player2.Message("FIGHT!");

        // Start combat between players
        _player1.StartCombat(_player2);
        _player2.StartCombat(_player1);

        return DuelResult.Ok;
    }

    private void ApplyDuelRules()
    {
        if (Rules.HasFlag(DuelRules.NoWeapons))
        {
            // Would unequip weapons
            _player1.Message("Weapons have been removed for this duel.");
            _player2.Message("Weapons have been removed for this duel.");
        }

        if (Rules.HasFlag(DuelRules.NoPrayer))
        {
            _player1.Prayers.DeactivateAll();
            _player2.Prayers.DeactivateAll();
        }
    }

    /// <summary>
    /// Ends the duel with a winner.
    /// </summary>
    public void EndDuel(Player winner)
    {
        if (State != DuelState.Fighting)
            return;

        State = DuelState.Completed;

        var loser = GetOpponent(winner);

        // Winner gets all stakes
        foreach (var stake in _player1Stake)
            winner.Inventory.Add(stake);

        foreach (var stake in _player2Stake)
            winner.Inventory.Add(stake);

        winner.Message($"You have defeated {loser.Username}!");
        loser.Message($"You have been defeated by {winner.Username}!");

        // End combat
        winner.EndCombat();
        loser.EndCombat();

        // Restore loser hitpoints (duels don't kill)
        loser.CurrentHitpoints = loser.Skills.GetMaxLevel(Skills.Skill.Hitpoints);
    }

    /// <summary>
    /// Cancels the duel.
    /// </summary>
    public void Cancel(string? reason = null)
    {
        if (State == DuelState.Completed)
            return;

        // Return staked items if duel was in progress
        if (State == DuelState.Fighting)
        {
            foreach (var stake in _player1Stake)
                _player1.Inventory.Add(stake);

            foreach (var stake in _player2Stake)
                _player2.Inventory.Add(stake);
        }

        State = DuelState.Completed;

        var message = reason ?? "The duel has been cancelled.";
        _player1.Message(message);
        _player2.Message(message);

        _player1.EndCombat();
        _player2.EndCombat();
    }

    /// <summary>
    /// Checks if a rule is active.
    /// </summary>
    public bool HasRule(DuelRules rule) => Rules.HasFlag(rule);
}

/// <summary>
/// Manages duel requests and sessions.
/// </summary>
public sealed class DuelManager
{
    private readonly Dictionary<(Player, Player), DuelSession> _activeDuels = new();
    private readonly Dictionary<Player, Player> _pendingRequests = new();

    /// <summary>
    /// Sends a duel request to another player.
    /// </summary>
    public DuelResult RequestDuel(Player requester, Player target)
    {
        if (requester == target)
            return DuelResult.Fail("You can't duel yourself.");

        if (requester.InCombat)
            return DuelResult.Fail("You can't duel while in combat.");

        if (target.InCombat)
            return DuelResult.Fail("That player is in combat.");

        if (GetActiveDuel(requester) is not null)
            return DuelResult.Fail("You are already in a duel.");

        if (GetActiveDuel(target) is not null)
            return DuelResult.Fail("That player is already in a duel.");

        // Check if target already sent us a request
        if (_pendingRequests.TryGetValue(target, out var existingTarget) && existingTarget == requester)
        {
            // Accept the duel
            _pendingRequests.Remove(target);
            return StartDuelSession(target, requester);
        }

        // Send request
        _pendingRequests[requester] = target;

        target.Message($"{requester.Username} wishes to duel with you.");
        requester.Message($"Sending duel request to {target.Username}...");

        return DuelResult.Ok;
    }

    /// <summary>
    /// Starts a duel session between two players.
    /// </summary>
    private DuelResult StartDuelSession(Player player1, Player player2)
    {
        var session = new DuelSession(player1, player2);
        var key = GetDuelKey(player1, player2);
        _activeDuels[key] = session;

        player1.Message("Duel session started. Configure rules and stakes.");
        player2.Message("Duel session started. Configure rules and stakes.");

        return DuelResult.Ok;
    }

    /// <summary>
    /// Gets the active duel for a player.
    /// </summary>
    public DuelSession? GetActiveDuel(Player player)
    {
        foreach (var (key, session) in _activeDuels)
        {
            if (session.IsParticipant(player) && session.State != DuelState.Completed)
                return session;
        }
        return null;
    }

    /// <summary>
    /// Removes a completed duel.
    /// </summary>
    public void RemoveDuel(DuelSession session)
    {
        var key = GetDuelKey(session.Player1, session.Player2);
        _activeDuels.Remove(key);
    }

    /// <summary>
    /// Declines a duel request.
    /// </summary>
    public DuelResult DeclineRequest(Player decliner)
    {
        var requester = _pendingRequests
            .FirstOrDefault(kvp => kvp.Value == decliner)
            .Key;

        if (requester is null)
            return DuelResult.Fail("No pending duel requests.");

        _pendingRequests.Remove(requester);

        requester.Message($"{decliner.Username} has declined your duel request.");
        decliner.Message("You decline the duel request.");

        return DuelResult.Ok;
    }

    private static (Player, Player) GetDuelKey(Player p1, Player p2)
    {
        // Ensure consistent key ordering
        return p1.GetHashCode() < p2.GetHashCode() ? (p1, p2) : (p2, p1);
    }
}
