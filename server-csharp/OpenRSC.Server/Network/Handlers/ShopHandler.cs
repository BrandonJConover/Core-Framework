using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Shop;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles shop-related packets.
/// </summary>
public sealed class ShopHandler : IPacketHandler
{
    private readonly ILogger<ShopHandler> _logger;
    private readonly ShopManager _shopManager;

    public int[] Opcodes => new[]
    {
        (int)OpcodeIn.ShopClose,
        (int)OpcodeIn.ShopBuy,
        (int)OpcodeIn.ShopSell
    };

    public ShopHandler(ILogger<ShopHandler> logger, ShopManager shopManager)
    {
        _logger = logger;
        _shopManager = shopManager;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        switch ((OpcodeIn)packet.Opcode)
        {
            case OpcodeIn.ShopClose:
                HandleClose(player);
                break;
            case OpcodeIn.ShopBuy:
                await HandleBuyAsync(player, packet);
                break;
            case OpcodeIn.ShopSell:
                await HandleSellAsync(player, packet);
                break;
        }
    }

    private void HandleClose(Player player)
    {
        _shopManager.CloseShop(player);
        _logger.LogDebug("{Username} closed shop", player.Username);
    }

    private async Task HandleBuyAsync(Player player, Packet packet)
    {
        var itemId = packet.ReadShort();
        var amount = packet.ReadShort();

        if (amount <= 0 || amount > 100)
        {
            player.Message("Invalid amount.");
            return;
        }

        var result = _shopManager.BuyItem(player, itemId, amount);
        if (!result.Success)
        {
            player.Message(result.Message ?? "Unable to buy item.");
        }

        await Task.CompletedTask;
    }

    private async Task HandleSellAsync(Player player, Packet packet)
    {
        var itemId = packet.ReadShort();
        var amount = packet.ReadShort();

        if (amount <= 0 || amount > 100)
        {
            player.Message("Invalid amount.");
            return;
        }

        var result = _shopManager.SellItem(player, itemId, amount);
        if (!result.Success)
        {
            player.Message(result.Message ?? "Unable to sell item.");
        }

        await Task.CompletedTask;
    }
}
