using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;

namespace OpenRSC.Server.Shop;

/// <summary>
/// Manages all shops and player shop sessions.
/// </summary>
public sealed class ShopManager
{
    private readonly ILogger<ShopManager> _logger;
    private readonly IItemFactory _itemFactory;
    private readonly Dictionary<int, Shop> _shops = new();
    private readonly Dictionary<Player, Shop> _openShops = new();

    public ShopManager(ILogger<ShopManager> logger, IItemFactory itemFactory)
    {
        _logger = logger;
        _itemFactory = itemFactory;
    }

    /// <summary>
    /// Registers a shop.
    /// </summary>
    public void RegisterShop(ShopDefinition definition)
    {
        var shop = new Shop(definition);
        _shops[definition.Id] = shop;
        _logger.LogDebug("Registered shop: {ShopName} (ID: {ShopId})", definition.Name, definition.Id);
    }

    /// <summary>
    /// Gets a shop by ID.
    /// </summary>
    public Shop? GetShop(int shopId)
    {
        return _shops.TryGetValue(shopId, out var shop) ? shop : null;
    }

    /// <summary>
    /// Opens a shop for a player.
    /// </summary>
    public bool OpenShop(Player player, int shopId)
    {
        var shop = GetShop(shopId);
        if (shop is null)
        {
            _logger.LogWarning("Attempted to open non-existent shop {ShopId}", shopId);
            return false;
        }

        // Close any previously open shop
        CloseShop(player);

        _openShops[player] = shop;

        // Send shop interface to client
        SendShopInterface(player, shop);

        _logger.LogDebug("{Username} opened shop: {ShopName}", player.Username, shop.Name);
        return true;
    }

    /// <summary>
    /// Closes the shop for a player.
    /// </summary>
    public void CloseShop(Player player)
    {
        if (_openShops.Remove(player))
        {
            _ = player.ActionSender?.SendPacketAsync(
                new Network.Packet((byte)Network.OpcodeOut.HideShop));
        }
    }

    /// <summary>
    /// Gets the shop a player currently has open.
    /// </summary>
    public Shop? GetOpenShop(Player player)
    {
        return _openShops.TryGetValue(player, out var shop) ? shop : null;
    }

    /// <summary>
    /// Handles a player buying from a shop.
    /// </summary>
    public ShopResult BuyItem(Player player, int itemId, int amount)
    {
        var shop = GetOpenShop(player);
        if (shop is null)
            return ShopResult.Fail("You don't have a shop open.");

        var definition = _itemFactory.GetDefinition(itemId);
        if (definition is null)
            return ShopResult.Fail("Invalid item.");

        // Check if shop has item
        if (!shop.Stock.TryGetValue(itemId, out var stock) || stock.Amount < amount)
            return ShopResult.Fail("The shop doesn't have that many.");

        // Calculate total cost
        var priceEach = shop.GetBuyPrice(itemId, definition);
        var totalCost = priceEach * amount;

        // Check if player has enough coins
        const int coinsId = 10; // Coins item ID
        if (!player.Inventory.HasItem(coinsId, totalCost))
            return ShopResult.Fail("You don't have enough coins.");

        // Check inventory space
        if (player.Inventory.IsFull && !player.Inventory.HasItem(itemId))
            return ShopResult.Fail("Your inventory is full.");

        // Execute the purchase
        var buyResult = shop.Buy(itemId, amount);
        if (!buyResult.Success)
            return buyResult;

        // Remove coins from player
        player.Inventory.Remove(coinsId, totalCost);

        // Add item to player
        var item = _itemFactory.Create(itemId, amount);
        if (item is not null)
        {
            player.Inventory.Add(item);
        }

        // Send updates
        player.SendInventory();
        SendShopInterface(player, shop);

        _logger.LogDebug("{Username} bought {Amount}x {ItemName} for {Cost} coins",
            player.Username, amount, definition.Name, totalCost);

        return ShopResult.Success;
    }

    /// <summary>
    /// Handles a player selling to a shop.
    /// </summary>
    public ShopResult SellItem(Player player, int itemId, int amount)
    {
        var shop = GetOpenShop(player);
        if (shop is null)
            return ShopResult.Fail("You don't have a shop open.");

        var definition = _itemFactory.GetDefinition(itemId);
        if (definition is null)
            return ShopResult.Fail("Invalid item.");

        // Check if shop will buy this item
        if (!shop.WillBuy(itemId))
            return ShopResult.Fail("This shop doesn't buy that item.");

        // Check if player has the item
        if (!player.Inventory.HasItem(itemId, amount))
            return ShopResult.Fail("You don't have that many.");

        // Calculate payment
        var priceEach = shop.GetSellPrice(itemId, definition);
        var totalPayment = priceEach * amount;

        // Execute the sale
        var sellResult = shop.Sell(itemId, amount);
        if (!sellResult.Success)
            return sellResult;

        // Remove item from player
        player.Inventory.Remove(itemId, amount);

        // Add coins to player
        const int coinsId = 10;
        var coins = _itemFactory.Create(coinsId, totalPayment);
        if (coins is not null)
        {
            player.Inventory.Add(coins);
        }

        // Send updates
        player.SendInventory();
        SendShopInterface(player, shop);

        _logger.LogDebug("{Username} sold {Amount}x {ItemName} for {Payment} coins",
            player.Username, amount, definition.Name, totalPayment);

        return ShopResult.Success;
    }

    /// <summary>
    /// Sends the shop interface packet to the player.
    /// </summary>
    private void SendShopInterface(Player player, Shop shop)
    {
        var stockList = shop.GetStockList(_itemFactory).ToList();

        using var packet = new Network.Packet((byte)Network.OpcodeOut.ShowShop);

        // Shop info
        packet.WriteByte((byte)stockList.Count);
        packet.WriteByte(shop.IsGeneral ? (byte)1 : (byte)0);
        packet.WriteByte((byte)shop.SellMultiplier);
        packet.WriteByte((byte)shop.BuyMultiplier);

        // Stock items
        foreach (var (itemId, amount, price) in stockList)
        {
            packet.WriteShort((short)itemId);
            packet.WriteShort((short)amount);
            packet.WriteInt(price);
        }

        _ = player.ActionSender?.SendPacketAsync(packet);
    }

    /// <summary>
    /// Processes restocking for all shops.
    /// </summary>
    public void ProcessRestock()
    {
        foreach (var shop in _shops.Values)
        {
            shop.ProcessRestock();
        }
    }
}
