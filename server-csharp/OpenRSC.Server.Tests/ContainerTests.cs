using FluentAssertions;
using OpenRSC.Server.Inventory;
using OpenRSC.Server.Items;
using Xunit;

namespace OpenRSC.Server.Tests;

public class ContainerTests
{
    private static ItemDefinition CreateDefinition(int id, bool stackable = false) => new()
    {
        Id = id,
        Name = $"Item {id}",
        IsStackable = stackable,
        BasePrice = 100
    };

    [Fact]
    public void Add_NonStackable_UsesNewSlot()
    {
        var container = new Container(10);
        var item = new Item(CreateDefinition(1));

        var result = container.Add(item);

        result.Success.Should().BeTrue();
        container.UsedSlots.Should().Be(1);
        container.GetSlot(0).Should().Be(item);
    }

    [Fact]
    public void Add_Stackable_StacksWithExisting()
    {
        var container = new Container(10);
        var def = CreateDefinition(1, stackable: true);
        container.Add(new Item(def, 5));
        container.Add(new Item(def, 3));

        container.UsedSlots.Should().Be(1);
        container.GetSlot(0)!.Amount.Should().Be(8);
    }

    [Fact]
    public void Add_FullContainer_Fails()
    {
        var container = new Container(2);
        container.Add(new Item(CreateDefinition(1)));
        container.Add(new Item(CreateDefinition(2)));

        var result = container.Add(new Item(CreateDefinition(3)));

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("space");
    }

    [Fact]
    public void Remove_BySlot_ReturnsItem()
    {
        var container = new Container(10);
        var item = new Item(CreateDefinition(1));
        container.Add(item);

        var removed = container.Remove(0);

        removed.Should().Be(item);
        container.UsedSlots.Should().Be(0);
    }

    [Fact]
    public void Remove_ByCatalogId_RemovesCorrectAmount()
    {
        var container = new Container(10);
        var def = CreateDefinition(1, stackable: true);
        container.Add(new Item(def, 10));

        var result = container.Remove(1, 5);

        result.Success.Should().BeTrue();
        container.GetSlot(0)!.Amount.Should().Be(5);
    }

    [Fact]
    public void Contains_ExistingItem_ReturnsTrue()
    {
        var container = new Container(10);
        container.Add(new Item(CreateDefinition(42), 1));

        container.Contains(42).Should().BeTrue();
        container.Contains(99).Should().BeFalse();
    }

    [Fact]
    public void CountOf_ReturnsTotal()
    {
        var container = new Container(10);
        var def = CreateDefinition(1, stackable: true);
        container.Add(new Item(def, 5));
        container.Add(new Item(CreateDefinition(2)));

        container.CountOf(1).Should().Be(5);
        container.CountOf(2).Should().Be(1);
        container.CountOf(99).Should().Be(0);
    }

    [Fact]
    public void Swap_ExchangesSlots()
    {
        var container = new Container(10);
        var item1 = new Item(CreateDefinition(1));
        var item2 = new Item(CreateDefinition(2));
        container.AddToSlot(0, item1);
        container.AddToSlot(5, item2);

        container.Swap(0, 5);

        container.GetSlot(0).Should().Be(item2);
        container.GetSlot(5).Should().Be(item1);
    }

    [Fact]
    public void Clear_RemovesAllItems()
    {
        var container = new Container(10);
        container.Add(new Item(CreateDefinition(1)));
        container.Add(new Item(CreateDefinition(2)));

        container.Clear();

        container.UsedSlots.Should().Be(0);
        container.FreeSlots.Should().Be(10);
    }

    [Fact]
    public void Compact_RemovesGaps()
    {
        var container = new Container(10);
        container.AddToSlot(0, new Item(CreateDefinition(1)));
        container.AddToSlot(5, new Item(CreateDefinition(2)));
        container.AddToSlot(9, new Item(CreateDefinition(3)));

        container.Compact();

        container.GetSlot(0)!.CatalogId.Should().Be(1);
        container.GetSlot(1)!.CatalogId.Should().Be(2);
        container.GetSlot(2)!.CatalogId.Should().Be(3);
        container.GetSlot(3).Should().BeNull();
    }

    [Fact]
    public void ContentsChanged_RaisesOnAdd()
    {
        var container = new Container(10);
        var eventRaised = false;
        container.ContentsChanged += args =>
        {
            eventRaised = true;
            args.ChangeType.Should().Be(ContainerChangeType.Added);
        };

        container.Add(new Item(CreateDefinition(1)));

        eventRaised.Should().BeTrue();
    }
}
