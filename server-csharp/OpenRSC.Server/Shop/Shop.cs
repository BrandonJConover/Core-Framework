using OpenRSC.Server.Items;

namespace OpenRSC.Server.Shop;

/// <summary>
/// Represents an NPC shop.
/// </summary>
public sealed class Shop
{
    private readonly ShopDefinition _definition;
    private readonly Dictionary<int, ShopStock> _stock = new();
    private DateTime _lastRestock;

    public int Id => _definition.Id;
    public string Name => _definition.Name;
    public bool IsGeneral => _definition.IsGeneral;
    public int BuyMultiplier => _definition.BuyPricePercent;
    public int SellMultiplier => _definition.SellPricePercent;

    /// <summary>
    /// Current stock items.
    /// </summary>
    public IReadOnlyDictionary<int, ShopStock> Stock => _stock;

    public Shop(ShopDefinition definition)
    {
        _definition = definition;
        InitializeStock();
        _lastRestock = DateTime.UtcNow;
    }

    private void InitializeStock()
    {
        foreach (var item in _definition.InitialStock)
        {
            _stock[item.ItemId] = new ShopStock(
                item.ItemId,
                item.Amount,
                item.Amount // Initial amount is also the base amount
            );
        }
    }

    /// <summary>
    /// Gets the buy price for an item (player buying from shop).
    /// </summary>
    public int GetBuyPrice(int itemId, ItemDefinition definition)
    {
        var basePrice = definition.BasePrice;

        // Price increases when stock is low
        if (_stock.TryGetValue(itemId, out var stock))
        {
            if (stock.Amount < stock.BaseAmount)
            {
                var shortage = stock.BaseAmount - stock.Amount;
                basePrice += (int)(basePrice * 0.03 * shortage);
            }
        }

        return Math.Max(1, basePrice * _definition.BuyPricePercent / 100);
    }

    /// <summary>
    /// Gets the sell price for an item (player selling to shop).
    /// </summary>
    public int GetSellPrice(int itemId, ItemDefinition definition)
    {
        var basePrice = definition.BasePrice;

        // Price decreases when shop has excess stock
        if (_stock.TryGetValue(itemId, out var stock))
        {
            var excess = Math.Max(0, stock.Amount - stock.BaseAmount);
            basePrice -= (int)(basePrice * 0.03 * excess);
        }

        var price = basePrice * _definition.SellPricePercent / 100;
        return Math.Max(1, price);
    }

    /// <summary>
    /// Checks if the shop will buy an item.
    /// </summary>
    public bool WillBuy(int itemId)
    {
        return _definition.IsGeneral || _stock.ContainsKey(itemId);
    }

    /// <summary>
    /// Attempts to buy an item from the shop.
    /// </summary>
    public ShopResult Buy(int itemId, int amount)
    {
        if (!_stock.TryGetValue(itemId, out var stock))
            return ShopResult.Fail("This shop doesn't sell that item.");

        if (stock.Amount < amount)
            return ShopResult.Fail("The shop doesn't have that many in stock.");

        stock.Amount -= amount;

        // Remove from stock if depleted and not a base item
        if (stock.Amount <= 0 && stock.BaseAmount <= 0)
            _stock.Remove(itemId);

        return ShopResult.Success;
    }

    /// <summary>
    /// Sells an item to the shop.
    /// </summary>
    public ShopResult Sell(int itemId, int amount)
    {
        if (!WillBuy(itemId))
            return ShopResult.Fail("This shop doesn't buy that item.");

        if (_stock.TryGetValue(itemId, out var stock))
        {
            stock.Amount += amount;
        }
        else
        {
            _stock[itemId] = new ShopStock(itemId, amount, 0);
        }

        return ShopResult.Success;
    }

    /// <summary>
    /// Processes restocking towards base amounts.
    /// </summary>
    public void ProcessRestock()
    {
        var now = DateTime.UtcNow;
        var elapsed = (now - _lastRestock).TotalSeconds;

        if (elapsed < _definition.RestockInterval)
            return;

        _lastRestock = now;

        foreach (var stock in _stock.Values.ToList())
        {
            if (stock.Amount < stock.BaseAmount)
            {
                // Restock towards base
                stock.Amount = Math.Min(stock.Amount + 1, stock.BaseAmount);
            }
            else if (stock.Amount > stock.BaseAmount && stock.BaseAmount > 0)
            {
                // Reduce excess stock
                stock.Amount--;
            }
            else if (stock.Amount > 0 && stock.BaseAmount == 0)
            {
                // Slowly remove player-sold items from general stores
                stock.Amount--;
                if (stock.Amount <= 0)
                    _stock.Remove(stock.ItemId);
            }
        }
    }

    /// <summary>
    /// Gets all items currently in stock.
    /// </summary>
    public IEnumerable<(int ItemId, int Amount, int Price)> GetStockList(IItemFactory itemFactory)
    {
        foreach (var stock in _stock.Values.Where(s => s.Amount > 0))
        {
            var definition = itemFactory.GetDefinition(stock.ItemId);
            if (definition is not null)
            {
                var price = GetBuyPrice(stock.ItemId, definition);
                yield return (stock.ItemId, stock.Amount, price);
            }
        }
    }
}

/// <summary>
/// Tracks stock of a single item in a shop.
/// </summary>
public sealed class ShopStock
{
    public int ItemId { get; }
    public int Amount { get; set; }
    public int BaseAmount { get; }

    public ShopStock(int itemId, int amount, int baseAmount)
    {
        ItemId = itemId;
        Amount = amount;
        BaseAmount = baseAmount;
    }
}

/// <summary>
/// Definition of a shop.
/// </summary>
public sealed record ShopDefinition
{
    public required int Id { get; init; }
    public required string Name { get; init; }
    public bool IsGeneral { get; init; }
    public int BuyPricePercent { get; init; } = 130; // 30% markup
    public int SellPricePercent { get; init; } = 40; // 60% markdown
    public int RestockInterval { get; init; } = 30; // seconds
    public IReadOnlyList<ShopItem> InitialStock { get; init; } = Array.Empty<ShopItem>();
}

/// <summary>
/// Initial stock item for a shop.
/// </summary>
public sealed record ShopItem(int ItemId, int Amount);

/// <summary>
/// Result of a shop operation.
/// </summary>
public readonly record struct ShopResult(bool Success, string? Message = null)
{
    public static ShopResult Fail(string message) => new(false, message);
    public static readonly ShopResult Success = new(true);
}
