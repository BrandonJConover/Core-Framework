using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Services;
using OpenRSC.Server.Trading;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles all trading-related packets.
/// </summary>
public sealed class TradeHandler : IPacketHandler
{
    private readonly ILogger<TradeHandler> _logger;
    private readonly TradeManager _tradeManager;
    private readonly WorldService _worldService;
    private readonly IItemDefinitionRepository _itemDefinitions;

    // Client lookup for packet sending
    private readonly Dictionary<Player, GameClient> _clientLookup = new();

    public int[] Opcodes => new[]
    {
        (int)OpcodeIn.TradeRequest,
        (int)OpcodeIn.TradeAccept,
        (int)OpcodeIn.TradeDecline,
        (int)OpcodeIn.TradeConfirm,
        (int)OpcodeIn.TradeUpdateOffer
    };

    public TradeHandler(
        ILogger<TradeHandler> logger,
        TradeManager tradeManager,
        WorldService worldService,
        IItemDefinitionRepository itemDefinitions)
    {
        _logger = logger;
        _tradeManager = tradeManager;
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
            case OpcodeIn.TradeRequest:
                await HandleTradeRequestAsync(client, player, packet);
                break;
            case OpcodeIn.TradeAccept:
                await HandleTradeAcceptAsync(client, player);
                break;
            case OpcodeIn.TradeDecline:
                await HandleTradeDeclineAsync(client, player);
                break;
            case OpcodeIn.TradeConfirm:
                await HandleTradeConfirmAsync(client, player);
                break;
            case OpcodeIn.TradeUpdateOffer:
                await HandleTradeUpdateOfferAsync(client, player, packet);
                break;
        }
    }

    private async Task HandleTradeRequestAsync(GameClient client, Player player, Packet packet)
    {
        var targetIndex = packet.ReadShort();
        var target = _worldService.GetPlayer(targetIndex);

        if (target is null || target.IsRemoved)
        {
            await SendMessageAsync(client, "Unable to find player.");
            return;
        }

        if (player.InCombat)
        {
            await SendMessageAsync(client, "You can't trade while in combat.");
            return;
        }

        if (target.InCombat)
        {
            await SendMessageAsync(client, "That player is busy.");
            return;
        }

        // Check distance - must be within 5 tiles
        if (player.Location.DistanceTo(target.Location) > 5)
        {
            await SendMessageAsync(client, "You are too far away to trade.");
            return;
        }

        var result = _tradeManager.RequestTrade(player, target);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to trade.");
            return;
        }

        // Check if trade session started (mutual request)
        var session = _tradeManager.GetTrade(player);
        if (session is not null)
        {
            // Send trade interface to both players
            var partner = session.GetPartner(player);
            await SendTradeInterfaceAsync(client, player, session);

            if (_clientLookup.TryGetValue(partner, out var partnerClient))
            {
                await SendTradeInterfaceAsync(partnerClient, partner, session);
            }
        }
        else
        {
            await SendMessageAsync(client, $"Sending trade request to {target.Username}...");
        }

        _logger.LogDebug("{Username} requested trade with {Target}",
            player.Username, target.Username);
    }

    private async Task HandleTradeAcceptAsync(GameClient client, Player player)
    {
        var session = _tradeManager.GetTrade(player);
        if (session is null)
        {
            await SendMessageAsync(client, "You are not in a trade.");
            return;
        }

        var result = session.Accept(player);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to accept trade.");
            return;
        }

        var partner = session.GetPartner(player);

        // If both accepted, move to confirmation screen
        if (session.State == TradeState.Confirming)
        {
            await SendTradeConfirmationAsync(client, player, session);

            if (_clientLookup.TryGetValue(partner, out var partnerClient))
            {
                await SendTradeConfirmationAsync(partnerClient, partner, session);
            }
        }
        else
        {
            // Send update to both players
            await SendTradeUpdateAsync(client, player, session);

            if (_clientLookup.TryGetValue(partner, out var partnerClient))
            {
                await SendTradeUpdateAsync(partnerClient, partner, session);
            }
        }
    }

    private async Task HandleTradeDeclineAsync(GameClient client, Player player)
    {
        var session = _tradeManager.GetTrade(player);
        if (session is null)
            return;

        var partner = session.GetPartner(player);

        _tradeManager.EndTrade(player);

        // Close trade interfaces
        await SendCloseTradeInterfaceAsync(client);

        if (_clientLookup.TryGetValue(partner, out var partnerClient))
        {
            await SendCloseTradeInterfaceAsync(partnerClient);
        }

        _logger.LogDebug("{Username} declined trade with {Partner}",
            player.Username, partner.Username);
    }

    private async Task HandleTradeConfirmAsync(GameClient client, Player player)
    {
        var session = _tradeManager.GetTrade(player);
        if (session is null)
        {
            await SendMessageAsync(client, "You are not in a trade.");
            return;
        }

        var result = session.Confirm(player);
        if (!result.Success)
        {
            await SendMessageAsync(client, result.Message ?? "Unable to confirm trade.");
            return;
        }

        // If trade completed successfully
        if (session.State == TradeState.Completed)
        {
            var partner = session.GetPartner(player);

            // Close trade interfaces
            await SendCloseTradeInterfaceAsync(client);
            await SendInventoryUpdateAsync(client, player);

            if (_clientLookup.TryGetValue(partner, out var partnerClient))
            {
                await SendCloseTradeInterfaceAsync(partnerClient);
                await SendInventoryUpdateAsync(partnerClient, partner);
            }

            _tradeManager.EndTrade(player);

            _logger.LogInformation("Trade completed between {Player1} and {Player2}",
                player.Username, partner.Username);
        }
    }

    private async Task HandleTradeUpdateOfferAsync(GameClient client, Player player, Packet packet)
    {
        var session = _tradeManager.GetTrade(player);
        if (session is null)
        {
            await SendMessageAsync(client, "You are not in a trade.");
            return;
        }

        if (session.State != TradeState.Offering)
        {
            await SendMessageAsync(client, "You can't modify offers now.");
            return;
        }

        // Read the update type and data
        var itemCount = packet.ReadByte();

        // Process each item being offered
        for (var i = 0; i < itemCount; i++)
        {
            var itemId = packet.ReadShort();
            var amount = packet.ReadInt();

            // Validate player has the item
            if (!player.Inventory.HasItem(itemId, amount))
            {
                await SendMessageAsync(client, "You don't have enough of that item.");
                await HandleTradeDeclineAsync(client, player);
                return;
            }

            // Create item for offer
            var definition = _itemDefinitions.GetById(itemId);
            if (definition is null)
            {
                _logger.LogWarning("Invalid item ID {ItemId} in trade offer from {Username}",
                    itemId, player.Username);
                continue;
            }

            var item = new Item(definition, amount);
            var offerResult = session.OfferItem(player, item);

            if (!offerResult.Success)
            {
                await SendMessageAsync(client, offerResult.Message ?? "Unable to offer item.");
                break;
            }
        }

        // Send updated offer to both players
        var partner = session.GetPartner(player);
        await SendTradeUpdateAsync(client, player, session);

        if (_clientLookup.TryGetValue(partner, out var partnerClient))
        {
            await SendTradeUpdateAsync(partnerClient, partner, session);
        }

        _logger.LogDebug("{Username} updated trade offer ({Count} items)",
            player.Username, itemCount);
    }

    private static async Task SendMessageAsync(GameClient client, string message)
    {
        using var packet = PacketBuilder.ServerMessage(message);
        await client.SendAsync(packet);
    }

    private static async Task SendTradeInterfaceAsync(GameClient client, Player player, TradeSession session)
    {
        var partner = session.GetPartner(player);

        using var packet = new Packet((byte)OpcodeOut.TradeOpen);
        packet.WriteShort((short)partner.Index);

        await client.SendAsync(packet);
    }

    private static async Task SendTradeUpdateAsync(GameClient client, Player player, TradeSession session)
    {
        var offer = session.GetOffer(player);
        var partnerOffer = session.GetPartnerOffer(player);

        // Send our offer update
        using var ourOfferPacket = new Packet((byte)OpcodeOut.TradeOwnOffer);
        ourOfferPacket.WriteByte((byte)offer.UsedSlots);
        foreach (var item in offer.GetItems())
        {
            ourOfferPacket.WriteShort((short)item.CatalogId);
            ourOfferPacket.WriteInt(item.Amount);
        }
        await client.SendAsync(ourOfferPacket);

        // Send partner's offer update
        using var partnerOfferPacket = new Packet((byte)OpcodeOut.TradeOtherOffer);
        partnerOfferPacket.WriteByte((byte)partnerOffer.UsedSlots);
        foreach (var item in partnerOffer.GetItems())
        {
            partnerOfferPacket.WriteShort((short)item.CatalogId);
            partnerOfferPacket.WriteInt(item.Amount);
        }
        await client.SendAsync(partnerOfferPacket);
    }

    private static async Task SendTradeConfirmationAsync(GameClient client, Player player, TradeSession session)
    {
        var partnerOffer = session.GetPartnerOffer(player);
        var partner = session.GetPartner(player);

        using var packet = new Packet((byte)OpcodeOut.TradeConfirmation);
        packet.WriteString(partner.Username);
        packet.WriteByte((byte)partnerOffer.UsedSlots);

        foreach (var item in partnerOffer.GetItems())
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        await client.SendAsync(packet);
    }

    private static async Task SendCloseTradeInterfaceAsync(GameClient client)
    {
        using var packet = new Packet((byte)OpcodeOut.TradeClose);
        await client.SendAsync(packet);
    }

    private static async Task SendInventoryUpdateAsync(GameClient client, Player player)
    {
        // Send inventory update packet
        using var packet = new Packet((byte)OpcodeOut.PlayerInventory);

        var items = player.Inventory.GetItems();
        packet.WriteByte((byte)items.Count());

        foreach (var item in items)
        {
            var idWithEquip = item.IsEquipped ? item.CatalogId + 32768 : item.CatalogId;
            if (item.Definition?.IsStackable == true)
            {
                packet.WriteShort((short)(idWithEquip + 32768));
                packet.WriteInt(item.Amount);
            }
            else
            {
                packet.WriteShort((short)idWithEquip);
            }
        }

        await client.SendAsync(packet);
    }
}
