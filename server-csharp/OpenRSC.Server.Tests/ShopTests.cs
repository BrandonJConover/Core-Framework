using FluentAssertions;
using OpenRSC.Server.Items;
using OpenRSC.Server.Shop;
using Xunit;

namespace OpenRSC.Server.Tests;

public class ShopTests
{
    private static ShopDefinition CreateShopDef(bool isGeneral = false) => new()
    {
        Id = 1,
        Name = "Test Shop",
        IsGeneral = isGeneral,
        BuyPricePercent = 130,
        SellPricePercent = 40,
        InitialStock = new[]
        {
            new ShopItem(1, 10),
            new ShopItem(2, 5)
        }
    };

    private static ItemDefinition CreateItemDef(int id, int price = 100) => new()
    {
        Id = id,
        Name = $"Item {id}",
        BasePrice = price
    };

    [Fact]
    public void Shop_InitializesWithStock()
    {
        var shop = new Shop(CreateShopDef());

        shop.Stock.Should().HaveCount(2);
        shop.Stock[1].Amount.Should().Be(10);
        shop.Stock[2].Amount.Should().Be(5);
    }

    [Fact]
    public void GetBuyPrice_AppliesMarkup()
    {
        var shop = new Shop(CreateShopDef());
        var itemDef = CreateItemDef(1, 100);

        var price = shop.GetBuyPrice(1, itemDef);

        price.Should().Be(130); // 130% of 100
    }

    [Fact]
    public void GetBuyPrice_LowStock_IncreasesPrice()
    {
        var shop = new Shop(CreateShopDef());
        var itemDef = CreateItemDef(1, 100);

        // Reduce stock
        shop.Buy(1, 8); // Now only 2 of original 10

        var price = shop.GetBuyPrice(1, itemDef);

        price.Should().BeGreaterThan(130);
    }

    [Fact]
    public void GetSellPrice_AppliesMarkdown()
    {
        var shop = new Shop(CreateShopDef());
        var itemDef = CreateItemDef(1, 100);

        var price = shop.GetSellPrice(1, itemDef);

        price.Should().Be(40); // 40% of 100
    }

    [Fact]
    public void Buy_ReducesStock()
    {
        var shop = new Shop(CreateShopDef());

        var result = shop.Buy(1, 3);

        result.Success.Should().BeTrue();
        shop.Stock[1].Amount.Should().Be(7);
    }

    [Fact]
    public void Buy_InsufficientStock_Fails()
    {
        var shop = new Shop(CreateShopDef());

        var result = shop.Buy(1, 100);

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("stock");
    }

    [Fact]
    public void Buy_NonExistentItem_Fails()
    {
        var shop = new Shop(CreateShopDef());

        var result = shop.Buy(999, 1);

        result.Success.Should().BeFalse();
    }

    [Fact]
    public void Sell_ExistingItem_IncreasesStock()
    {
        var shop = new Shop(CreateShopDef());

        var result = shop.Sell(1, 5);

        result.Success.Should().BeTrue();
        shop.Stock[1].Amount.Should().Be(15);
    }

    [Fact]
    public void Sell_NewItemToGeneralStore_AddsToStock()
    {
        var shop = new Shop(CreateShopDef(isGeneral: true));

        var result = shop.Sell(99, 3);

        result.Success.Should().BeTrue();
        shop.Stock[99].Amount.Should().Be(3);
    }

    [Fact]
    public void Sell_NewItemToSpecializedShop_Fails()
    {
        var shop = new Shop(CreateShopDef(isGeneral: false));

        var result = shop.Sell(99, 3);

        result.Success.Should().BeFalse();
    }

    [Fact]
    public void WillBuy_StockedItem_ReturnsTrue()
    {
        var shop = new Shop(CreateShopDef());

        shop.WillBuy(1).Should().BeTrue();
    }

    [Fact]
    public void WillBuy_GeneralStore_ReturnsTrue()
    {
        var shop = new Shop(CreateShopDef(isGeneral: true));

        shop.WillBuy(999).Should().BeTrue();
    }

    [Fact]
    public void WillBuy_SpecializedShop_UnstockedItem_ReturnsFalse()
    {
        var shop = new Shop(CreateShopDef(isGeneral: false));

        shop.WillBuy(999).Should().BeFalse();
    }
}
