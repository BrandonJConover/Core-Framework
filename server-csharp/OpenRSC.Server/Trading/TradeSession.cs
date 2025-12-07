using OpenRSC.Server.Entities;
using OpenRSC.Server.Inventory;
using OpenRSC.Server.Items;

namespace OpenRSC.Server.Trading;

/// <summary>
/// Manages a trade session between two players.
/// </summary>
public sealed class TradeSession
{
    private readonly Player _player1;
    private readonly Player _player2;
    private readonly Container _offer1;
    private readonly Container _offer2;
    private bool _accepted1;
    private bool _accepted2;
    private bool _confirmed1;
    private bool _confirmed2;

    public Guid SessionId { get; } = Guid.NewGuid();
    public TradeState State { get; private set; } = TradeState.Offering;

    /// <summary>
    /// Gets the trade partner for a player.
    /// </summary>
    public Player GetPartner(Player player)
    {
        if (player == _player1) return _player2;
        if (player == _player2) return _player1;
        throw new InvalidOperationException("Player is not part of this trade.");
    }

    /// <summary>
    /// Gets the offer container for a player.
    /// </summary>
    public Container GetOffer(Player player)
    {
        if (player == _player1) return _offer1;
        if (player == _player2) return _offer2;
        throw new InvalidOperationException("Player is not part of this trade.");
    }

    /// <summary>
    /// Gets the partner's offer container for a player.
    /// </summary>
    public Container GetPartnerOffer(Player player)
    {
        if (player == _player1) return _offer2;
        if (player == _player2) return _offer1;
        throw new InvalidOperationException("Player is not part of this trade.");
    }

    public TradeSession(Player player1, Player player2)
    {
        _player1 = player1;
        _player2 = player2;
        _offer1 = new Container(12);
        _offer2 = new Container(12);
    }

    /// <summary>
    /// Adds an item to a player's offer.
    /// </summary>
    public TradeResult OfferItem(Player player, Item item)
    {
        if (State != TradeState.Offering)
            return TradeResult.Fail("Trade is no longer in offering state.");

        var offer = GetOffer(player);
        if (!offer.Add(item))
            return TradeResult.Fail("Trade offer is full.");

        // Reset acceptance when offers change
        ResetAcceptance();

        return TradeResult.Success;
    }

    /// <summary>
    /// Removes an item from a player's offer.
    /// </summary>
    public Item? WithdrawItem(Player player, int slot)
    {
        if (State != TradeState.Offering)
            return null;

        var offer = GetOffer(player);
        var item = offer.Remove(slot);

        if (item is not null)
        {
            ResetAcceptance();
        }

        return item;
    }

    /// <summary>
    /// Player accepts the current offers.
    /// </summary>
    public TradeResult Accept(Player player)
    {
        if (State == TradeState.Cancelled || State == TradeState.Completed)
            return TradeResult.Fail("Trade is no longer active.");

        if (player == _player1)
            _accepted1 = true;
        else if (player == _player2)
            _accepted2 = true;
        else
            return TradeResult.Fail("You are not part of this trade.");

        // Notify partner
        GetPartner(player).Message("The other player has accepted.");

        // Check if both accepted
        if (_accepted1 && _accepted2)
        {
            State = TradeState.Confirming;
            _player1.Message("Please confirm the trade.");
            _player2.Message("Please confirm the trade.");
        }

        return TradeResult.Success;
    }

    /// <summary>
    /// Player confirms the trade.
    /// </summary>
    public TradeResult Confirm(Player player)
    {
        if (State != TradeState.Confirming)
            return TradeResult.Fail("Trade is not in confirmation state.");

        if (player == _player1)
            _confirmed1 = true;
        else if (player == _player2)
            _confirmed2 = true;
        else
            return TradeResult.Fail("You are not part of this trade.");

        // Check if both confirmed
        if (_confirmed1 && _confirmed2)
        {
            return CompleteTrade();
        }

        GetPartner(player).Message("The other player has confirmed.");
        return TradeResult.Success;
    }

    /// <summary>
    /// Declines or cancels the trade.
    /// </summary>
    public void Decline(Player player)
    {
        if (State == TradeState.Completed)
            return;

        State = TradeState.Cancelled;

        // Return items to players
        ReturnItems(_player1, _offer1);
        ReturnItems(_player2, _offer2);

        _player1.Message("Trade declined.");
        _player2.Message("Trade declined.");
    }

    private TradeResult CompleteTrade()
    {
        // Validate both players have inventory space
        var space1Needed = _offer2.UsedSlots;
        var space2Needed = _offer1.UsedSlots;

        // Account for items being removed
        var free1 = _player1.Inventory.FreeSlots + _offer1.UsedSlots;
        var free2 = _player2.Inventory.FreeSlots + _offer2.UsedSlots;

        if (free1 < space1Needed)
        {
            State = TradeState.Cancelled;
            ReturnItems(_player1, _offer1);
            ReturnItems(_player2, _offer2);
            _player1.Message("You don't have enough inventory space.");
            _player2.Message("The other player doesn't have enough inventory space.");
            return TradeResult.Fail("Not enough inventory space.");
        }

        if (free2 < space2Needed)
        {
            State = TradeState.Cancelled;
            ReturnItems(_player1, _offer1);
            ReturnItems(_player2, _offer2);
            _player1.Message("The other player doesn't have enough inventory space.");
            _player2.Message("You don't have enough inventory space.");
            return TradeResult.Fail("Not enough inventory space.");
        }

        // Perform the swap
        TransferItems(_player1, _offer2);
        TransferItems(_player2, _offer1);

        State = TradeState.Completed;

        _player1.Message("Trade completed.");
        _player2.Message("Trade completed.");

        return TradeResult.Success;
    }

    private void ReturnItems(Player player, Container offer)
    {
        foreach (var item in offer.GetItems())
        {
            player.Inventory.Add(item);
        }
        offer.Clear();
    }

    private void TransferItems(Player player, Container offer)
    {
        foreach (var item in offer.GetItems())
        {
            player.Inventory.Add(item);
        }
        offer.Clear();
    }

    private void ResetAcceptance()
    {
        _accepted1 = false;
        _accepted2 = false;
        _confirmed1 = false;
        _confirmed2 = false;

        if (State == TradeState.Confirming)
        {
            State = TradeState.Offering;
        }
    }
}

/// <summary>
/// State of a trade session.
/// </summary>
public enum TradeState
{
    Offering,
    Confirming,
    Completed,
    Cancelled
}

/// <summary>
/// Result of a trade operation.
/// </summary>
public readonly record struct TradeResult(bool Success, string? Message = null)
{
    public static TradeResult Fail(string message) => new(false, message);
    public static readonly TradeResult Success = new(true);
}

/// <summary>
/// Manages all active trade sessions.
/// </summary>
public sealed class TradeManager
{
    private readonly Dictionary<Player, TradeSession> _activeTrades = new();
    private readonly Dictionary<Player, Player> _pendingRequests = new();

    /// <summary>
    /// Requests a trade with another player.
    /// </summary>
    public TradeResult RequestTrade(Player requester, Player target)
    {
        if (requester == target)
            return TradeResult.Fail("You can't trade with yourself.");

        if (_activeTrades.ContainsKey(requester))
            return TradeResult.Fail("You are already in a trade.");

        if (_activeTrades.ContainsKey(target))
            return TradeResult.Fail("That player is already trading.");

        // Check if target has already requested us
        if (_pendingRequests.TryGetValue(target, out var pendingTarget) && pendingTarget == requester)
        {
            // Both requested each other - start trade
            _pendingRequests.Remove(target);
            return StartTrade(requester, target);
        }

        // Add pending request
        _pendingRequests[requester] = target;
        target.Message($"{requester.Username} wishes to trade with you.");

        return TradeResult.Success;
    }

    /// <summary>
    /// Starts a trade session between two players.
    /// </summary>
    private TradeResult StartTrade(Player player1, Player player2)
    {
        var session = new TradeSession(player1, player2);
        _activeTrades[player1] = session;
        _activeTrades[player2] = session;

        player1.Message($"Trading with {player2.Username}.");
        player2.Message($"Trading with {player1.Username}.");

        // TODO: Send trade interface packets

        return TradeResult.Success;
    }

    /// <summary>
    /// Gets the active trade session for a player.
    /// </summary>
    public TradeSession? GetTrade(Player player)
    {
        return _activeTrades.TryGetValue(player, out var session) ? session : null;
    }

    /// <summary>
    /// Ends a trade session.
    /// </summary>
    public void EndTrade(Player player)
    {
        if (!_activeTrades.TryGetValue(player, out var session))
            return;

        var partner = session.GetPartner(player);

        _activeTrades.Remove(player);
        _activeTrades.Remove(partner);

        session.Decline(player);
    }

    /// <summary>
    /// Cancels a pending trade request.
    /// </summary>
    public void CancelRequest(Player player)
    {
        _pendingRequests.Remove(player);
    }
}
