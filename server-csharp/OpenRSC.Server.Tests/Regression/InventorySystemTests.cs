using FluentAssertions;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Inventory;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;
using Xunit;

namespace OpenRSC.Server.Tests.Regression;

/// <summary>
/// Regression tests for inventory and item systems.
/// These tests ensure item management remains consistent.
/// </summary>
public class InventorySystemTests
{
    private static ItemDefinition CreateItemDef(int id, bool stackable = false, int price = 100) => new()
    {
        Id = id,
        Name = $"Item {id}",
        IsStackable = stackable,
        BasePrice = price
    };

    #region Container Basics

    [Fact]
    public void Container_HasCorrectCapacity()
    {
        var container = new Container(30);

        container.Capacity.Should().Be(30);
        container.FreeSlots.Should().Be(30);
        container.UsedSlots.Should().Be(0);
    }

    [Fact]
    public void Container_Add_OccupiesSlot()
    {
        var container = new Container(30);
        var item = new Item(CreateItemDef(1));

        container.Add(item);

        container.UsedSlots.Should().Be(1);
        container.FreeSlots.Should().Be(29);
    }

    [Fact]
    public void Container_Add_PlacesInFirstEmptySlot()
    {
        var container = new Container(30);
        var item = new Item(CreateItemDef(1));

        container.Add(item);

        container.GetSlot(0).Should().Be(item);
        container.GetSlot(1).Should().BeNull();
    }

    [Fact]
    public void Container_Add_WhenFull_Fails()
    {
        var container = new Container(2);
        container.Add(new Item(CreateItemDef(1)));
        container.Add(new Item(CreateItemDef(2)));

        var result = container.Add(new Item(CreateItemDef(3)));

        result.Success.Should().BeFalse();
    }

    #endregion

    #region Stackable Items

    [Fact]
    public void Stackable_Add_StacksWithExisting()
    {
        var container = new Container(30);
        var def = CreateItemDef(1, stackable: true);

        container.Add(new Item(def, 5));
        container.Add(new Item(def, 3));

        container.UsedSlots.Should().Be(1);
        container.GetSlot(0)!.Amount.Should().Be(8);
    }

    [Fact]
    public void Stackable_Add_DoesNotStackDifferentItems()
    {
        var container = new Container(30);
        var def1 = CreateItemDef(1, stackable: true);
        var def2 = CreateItemDef(2, stackable: true);

        container.Add(new Item(def1, 5));
        container.Add(new Item(def2, 3));

        container.UsedSlots.Should().Be(2);
    }

    [Fact]
    public void NonStackable_Add_UsesNewSlots()
    {
        var container = new Container(30);
        var def = CreateItemDef(1, stackable: false);

        container.Add(new Item(def));
        container.Add(new Item(def));

        container.UsedSlots.Should().Be(2);
    }

    #endregion

    #region Remove Operations

    [Fact]
    public void Remove_BySlot_ReturnsItem()
    {
        var container = new Container(30);
        var item = new Item(CreateItemDef(1));
        container.Add(item);

        var removed = container.Remove(0);

        removed.Should().Be(item);
        container.UsedSlots.Should().Be(0);
    }

    [Fact]
    public void Remove_BySlot_EmptySlot_ReturnsNull()
    {
        var container = new Container(30);

        var removed = container.Remove(0);

        removed.Should().BeNull();
    }

    [Fact]
    public void Remove_ByCatalogId_RemovesCorrectAmount()
    {
        var container = new Container(30);
        var def = CreateItemDef(1, stackable: true);
        container.Add(new Item(def, 10));

        var result = container.Remove(1, 5);

        result.Success.Should().BeTrue();
        container.GetSlot(0)!.Amount.Should().Be(5);
    }

    [Fact]
    public void Remove_ByCatalogId_ExactAmount_RemovesItem()
    {
        var container = new Container(30);
        var def = CreateItemDef(1, stackable: true);
        container.Add(new Item(def, 10));

        container.Remove(1, 10);

        container.UsedSlots.Should().Be(0);
    }

    [Fact]
    public void Remove_ByCatalogId_MoreThanAvailable_Fails()
    {
        var container = new Container(30);
        var def = CreateItemDef(1, stackable: true);
        container.Add(new Item(def, 5));

        var result = container.Remove(1, 10);

        result.Success.Should().BeFalse();
    }

    #endregion

    #region Contains and Count

    [Fact]
    public void Contains_ExistingItem_ReturnsTrue()
    {
        var container = new Container(30);
        container.Add(new Item(CreateItemDef(42)));

        container.Contains(42).Should().BeTrue();
    }

    [Fact]
    public void Contains_NonExistingItem_ReturnsFalse()
    {
        var container = new Container(30);

        container.Contains(42).Should().BeFalse();
    }

    [Fact]
    public void Contains_WithAmount_ChecksQuantity()
    {
        var container = new Container(30);
        var def = CreateItemDef(1, stackable: true);
        container.Add(new Item(def, 5));

        container.Contains(1, 5).Should().BeTrue();
        container.Contains(1, 6).Should().BeFalse();
    }

    [Fact]
    public void CountOf_ReturnsTotalAmount()
    {
        var container = new Container(30);
        var def = CreateItemDef(1, stackable: true);
        container.Add(new Item(def, 10));

        container.CountOf(1).Should().Be(10);
    }

    [Fact]
    public void CountOf_NonExistingItem_ReturnsZero()
    {
        var container = new Container(30);

        container.CountOf(999).Should().Be(0);
    }

    #endregion

    #region Swap Operations

    [Fact]
    public void Swap_ExchangesItems()
    {
        var container = new Container(30);
        var item1 = new Item(CreateItemDef(1));
        var item2 = new Item(CreateItemDef(2));
        container.AddToSlot(0, item1);
        container.AddToSlot(5, item2);

        container.Swap(0, 5);

        container.GetSlot(0).Should().Be(item2);
        container.GetSlot(5).Should().Be(item1);
    }

    [Fact]
    public void Swap_WithEmpty_Works()
    {
        var container = new Container(30);
        var item = new Item(CreateItemDef(1));
        container.AddToSlot(0, item);

        container.Swap(0, 10);

        container.GetSlot(0).Should().BeNull();
        container.GetSlot(10).Should().Be(item);
    }

    #endregion

    #region Clear and Compact

    [Fact]
    public void Clear_RemovesAllItems()
    {
        var container = new Container(30);
        container.Add(new Item(CreateItemDef(1)));
        container.Add(new Item(CreateItemDef(2)));
        container.Add(new Item(CreateItemDef(3)));

        container.Clear();

        container.UsedSlots.Should().Be(0);
    }

    [Fact]
    public void Compact_RemovesGaps()
    {
        var container = new Container(30);
        container.AddToSlot(0, new Item(CreateItemDef(1)));
        container.AddToSlot(5, new Item(CreateItemDef(2)));
        container.AddToSlot(10, new Item(CreateItemDef(3)));

        container.Compact();

        container.GetSlot(0)!.CatalogId.Should().Be(1);
        container.GetSlot(1)!.CatalogId.Should().Be(2);
        container.GetSlot(2)!.CatalogId.Should().Be(3);
        container.GetSlot(3).Should().BeNull();
    }

    #endregion

    #region Player Inventory Constraints

    [Fact]
    public void PlayerInventory_Has30Slots()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Inventory.FreeSlots.Should().Be(30);
    }

    [Fact]
    public void PlayerBank_Has192Slots()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Bank.FreeSlots.Should().Be(192);
    }

    #endregion

    #region Events

    [Fact]
    public void Container_Add_RaisesContentsChanged()
    {
        var container = new Container(30);
        var eventRaised = false;
        container.ContentsChanged += _ => eventRaised = true;

        container.Add(new Item(CreateItemDef(1)));

        eventRaised.Should().BeTrue();
    }

    [Fact]
    public void Container_Remove_RaisesContentsChanged()
    {
        var container = new Container(30);
        container.Add(new Item(CreateItemDef(1)));

        var eventRaised = false;
        container.ContentsChanged += _ => eventRaised = true;

        container.Remove(0);

        eventRaised.Should().BeTrue();
    }

    #endregion
}
