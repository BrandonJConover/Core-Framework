using Microsoft.Extensions.Logging;
using OpenRSC.Server.Duel;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Services;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles all duel-related packets.
/// </summary>
public sealed class DuelHandler : IPacketHandler
{
    private readonly ILogger<DuelHandler> _logger;
    private readonly DuelManager _duelManager;
    private readonly WorldService _worldService;
    private readonly IItemDefinitionRepository _itemDefinitions;

    // Client lookup for packet sending
    private readonly Dictionary<Player, GameClient> _clientLookup = new();

    public int[] Opcodes => new[]
    {
        (int)OpcodeIn.DuelRequest,
        (int)OpcodeIn.DuelAccept,
        (int)OpcodeIn.DuelDecline,
        (int)OpcodeIn.DuelConfirm,
        (int)OpcodeIn.DuelUpdateOffer
    };

    // Duel update sub-opcodes
    private const byte SetStake = 1;
    private const byte RemoveStake = 2;
    private const byte ToggleRule = 3;

    public DuelHandler(
        ILogger<DuelHandler> logger,
        DuelManager duelManager,
        WorldService worldService,
        IItemDefinitionRepository itemDefinitions)
    {
        _logger = logger;
        _duelManager = duelManager;
        _worldService = worldService;
        _itemDefinitions = itemDefinitions;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        // Register client lookup
        _clientLookup[player] = client;

        switch ((OpcodeIn)packet.Opcode)
        {
            case OpcodeIn.DuelRequest:
                await HandleDuelRequestAsync(client, player, packet);
                break;
            case OpcodeIn.DuelAccept:
                await HandleDuelAcceptAsync(client, player);
                break;
            case OpcodeIn.DuelDecline:
                await HandleDuelDeclineAsync(client, player);
                break;
            case OpcodeIn.DuelConfirm:
                await HandleDuelConfirmAsync(client, player);
                break;
            case OpcodeIn.DuelUpdateOffer:
                await HandleDuelUpdateOfferAsync(client, player, packet);
                break;
        }
    }

    private async Task HandleDuelRequestAsync(GameClient client, Player player, Packet packet)
    {
        var targetIndex = packet.ReadShort();
        var target = _worldService.GetPlayer(targetIndex);

        if (target is null || target.IsRemoved)
        {
            await SendMessageAsync(client, "Unable to find player.");
            return;
        }

        // Check if in wilderness
        if (IsInWilderness(player.Location))
        {
            await SendMessageAsync(client, "You can't duel in the wilderness.");
            return;
        }

        // Check distance - must be within 5 tiles
        if (player.Location.DistanceTo(target.Location) > 5)
        {
            await SendMessageAsync(client, "You are too far away to duel.");
            return;
        }

        var result = _duelManager.RequestDuel(player, target);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to duel.");
            return;
        }

        // Check if duel session started (mutual request)
        var session = _duelManager.GetActiveDuel(player);
        if (session is not null && session.State == DuelState.Configuring)
        {
            // Send duel interface to both players
            await SendDuelInterfaceAsync(client, player, session);

            if (_clientLookup.TryGetValue(target, out var targetClient))
            {
                await SendDuelInterfaceAsync(targetClient, target, session);
            }
        }
        else
        {
            await SendMessageAsync(client, $"Sending duel request to {target.Username}...");
        }

        _logger.LogDebug("{Username} requested duel with {Target}",
            player.Username, target.Username);
    }

    private async Task HandleDuelAcceptAsync(GameClient client, Player player)
    {
        var session = _duelManager.GetActiveDuel(player);
        if (session is null)
        {
            await SendMessageAsync(client, "You are not in a duel.");
            return;
        }

        var result = session.Accept(player);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to accept duel.");
            return;
        }

        var opponent = session.GetOpponent(player);

        // If both accepted, move to first confirmation screen
        if (session.State == DuelState.FirstConfirm)
        {
            await SendDuelConfirmationAsync(client, player, session);

            if (_clientLookup.TryGetValue(opponent, out var opponentClient))
            {
                await SendDuelConfirmationAsync(opponentClient, opponent, session);
            }
        }
        else
        {
            // Send update to both players
            await SendDuelUpdateAsync(client, player, session);

            if (_clientLookup.TryGetValue(opponent, out var opponentClient))
            {
                await SendDuelUpdateAsync(opponentClient, opponent, session);
            }
        }
    }

    private async Task HandleDuelDeclineAsync(GameClient client, Player player)
    {
        var session = _duelManager.GetActiveDuel(player);
        if (session is null)
        {
            // Check for pending request to decline
            _duelManager.DeclineRequest(player);
            return;
        }

        var opponent = session.GetOpponent(player);

        session.Cancel("The duel has been declined.");

        // Close duel interfaces
        await SendCloseDuelInterfaceAsync(client);

        if (_clientLookup.TryGetValue(opponent, out var opponentClient))
        {
            await SendCloseDuelInterfaceAsync(opponentClient);
        }

        _duelManager.RemoveDuel(session);

        _logger.LogDebug("{Username} declined duel with {Opponent}",
            player.Username, opponent.Username);
    }

    private async Task HandleDuelConfirmAsync(GameClient client, Player player)
    {
        var session = _duelManager.GetActiveDuel(player);
        if (session is null)
        {
            await SendMessageAsync(client, "You are not in a duel.");
            return;
        }

        var result = session.Confirm(player);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to confirm duel.");
            await HandleDuelDeclineAsync(client, player);
            return;
        }

        // If duel started (fighting state)
        if (session.State == DuelState.Fighting)
        {
            var opponent = session.GetOpponent(player);

            // Close duel interfaces - combat begins
            await SendCloseDuelInterfaceAsync(client);

            if (_clientLookup.TryGetValue(opponent, out var opponentClient))
            {
                await SendCloseDuelInterfaceAsync(opponentClient);
            }

            // Teleport both players to duel arena
            await TeleportToDuelArenaAsync(client, player, opponent);

            _logger.LogInformation("Duel started between {Player1} and {Player2}",
                player.Username, opponent.Username);
        }
    }

    private async Task HandleDuelUpdateOfferAsync(GameClient client, Player player, Packet packet)
    {
        var session = _duelManager.GetActiveDuel(player);
        if (session is null)
        {
            await SendMessageAsync(client, "You are not in a duel.");
            return;
        }

        if (session.State != DuelState.Configuring)
        {
            await SendMessageAsync(client, "You can't modify the duel now.");
            return;
        }

        var updateType = packet.ReadByte();

        switch (updateType)
        {
            case SetStake:
                await HandleSetStakeAsync(client, player, session, packet);
                break;
            case RemoveStake:
                await HandleRemoveStakeAsync(client, player, session, packet);
                break;
            case ToggleRule:
                await HandleToggleRuleAsync(client, player, session, packet);
                break;
        }

        // Send updated duel info to both players
        var opponent = session.GetOpponent(player);
        await SendDuelUpdateAsync(client, player, session);

        if (_clientLookup.TryGetValue(opponent, out var opponentClient))
        {
            await SendDuelUpdateAsync(opponentClient, opponent, session);
        }
    }

    private async Task HandleSetStakeAsync(GameClient client, Player player, DuelSession session, Packet packet)
    {
        var itemId = packet.ReadShort();
        var amount = packet.ReadInt();

        // Validate the item exists in player's inventory
        if (!player.Inventory.HasItem(itemId, amount))
        {
            await SendMessageAsync(client, "You don't have enough of that item.");
            return;
        }

        var result = session.AddStake(player, itemId, amount);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to add stake.");
        }

        _logger.LogDebug("{Username} staked item {ItemId} x{Amount}",
            player.Username, itemId, amount);
    }

    private async Task HandleRemoveStakeAsync(GameClient client, Player player, DuelSession session, Packet packet)
    {
        var itemId = packet.ReadShort();

        var result = session.RemoveStake(player, itemId);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to remove stake.");
        }

        _logger.LogDebug("{Username} removed stake item {ItemId}",
            player.Username, itemId);
    }

    private async Task HandleToggleRuleAsync(GameClient client, Player player, DuelSession session, Packet packet)
    {
        var ruleId = packet.ReadByte();

        // Map rule ID to DuelRules enum
        var rule = ruleId switch
        {
            0 => DuelRules.NoRetreat,
            1 => DuelRules.NoMagic,
            2 => DuelRules.NoPrayer,
            3 => DuelRules.NoWeapons,
            4 => DuelRules.NoRanged,
            5 => DuelRules.NoMelee,
            _ => DuelRules.None
        };

        if (rule == DuelRules.None)
        {
            _logger.LogWarning("Invalid duel rule ID {RuleId} from {Username}",
                ruleId, player.Username);
            return;
        }

        var result = session.ToggleRule(player, rule);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to change rule.");
        }

        _logger.LogDebug("{Username} toggled duel rule {Rule}",
            player.Username, rule);
    }

    private static async Task SendMessageAsync(GameClient client, string message)
    {
        using var packet = PacketBuilder.ServerMessage(message);
        await client.SendAsync(packet);
    }

    private static async Task SendDuelInterfaceAsync(GameClient client, Player player, DuelSession session)
    {
        var opponent = session.GetOpponent(player);

        using var packet = new Packet((byte)OpcodeOut.DuelOpen);
        packet.WriteShort((short)opponent.Index);
        packet.WriteString(opponent.Username);
        packet.WriteShort((short)opponent.CombatLevel);

        await client.SendAsync(packet);
    }

    private static async Task SendDuelUpdateAsync(GameClient client, Player player, DuelSession session)
    {
        var myStake = player == session.Player1 ? session.Player1Stake : session.Player2Stake;
        var theirStake = player == session.Player1 ? session.Player2Stake : session.Player1Stake;

        using var packet = new Packet((byte)OpcodeOut.DuelUpdate);

        // Our stake
        packet.WriteByte((byte)myStake.Count);
        foreach (var item in myStake)
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        // Their stake
        packet.WriteByte((byte)theirStake.Count);
        foreach (var item in theirStake)
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        // Rules
        packet.WriteByte((byte)session.Rules);

        // Acceptance status
        packet.WriteByte(session.Player1Accepted ? (byte)1 : (byte)0);
        packet.WriteByte(session.Player2Accepted ? (byte)1 : (byte)0);

        await client.SendAsync(packet);
    }

    private static async Task SendDuelConfirmationAsync(GameClient client, Player player, DuelSession session)
    {
        var opponent = session.GetOpponent(player);
        var theirStake = player == session.Player1 ? session.Player2Stake : session.Player1Stake;

        using var packet = new Packet((byte)OpcodeOut.DuelConfirmation);
        packet.WriteString(opponent.Username);

        // Their stake
        packet.WriteByte((byte)theirStake.Count);
        foreach (var item in theirStake)
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        // Rules summary
        packet.WriteByte((byte)session.Rules);

        await client.SendAsync(packet);
    }

    private static async Task SendCloseDuelInterfaceAsync(GameClient client)
    {
        using var packet = new Packet((byte)OpcodeOut.DuelClose);
        await client.SendAsync(packet);
    }

    private async Task TeleportToDuelArenaAsync(GameClient client, Player player, Player opponent)
    {
        // Duel arena coordinates (typical RSC duel arena)
        const int arenaX = 216;
        const int arenaY = 463;

        // Teleport both players to opposite sides of arena
        player.Teleport(new Models.Point(arenaX - 2, arenaY));
        opponent.Teleport(new Models.Point(arenaX + 2, arenaY));

        // Send teleport packets
        await SendTeleportPacketAsync(client, player);

        if (_clientLookup.TryGetValue(opponent, out var opponentClient))
        {
            await SendTeleportPacketAsync(opponentClient, opponent);
        }
    }

    private static async Task SendTeleportPacketAsync(GameClient client, Player player)
    {
        using var packet = new Packet((byte)OpcodeOut.Teleport);
        packet.WriteShort((short)player.Location.X);
        packet.WriteShort((short)player.Location.Y);
        await client.SendAsync(packet);
    }

    private static bool IsInWilderness(Models.Point location)
    {
        // RSC wilderness starts at y coordinate 352 and above
        return location.Y >= 352;
    }

    /// <summary>
    /// Called when a duel ends (one player wins).
    /// </summary>
    public void OnDuelEnd(DuelSession session, Player winner)
    {
        session.EndDuel(winner);
        _duelManager.RemoveDuel(session);

        _logger.LogInformation("{Winner} won duel against {Loser}",
            winner.Username, session.GetOpponent(winner).Username);
    }
}
