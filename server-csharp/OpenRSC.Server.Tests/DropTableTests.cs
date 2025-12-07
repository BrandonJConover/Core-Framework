using FluentAssertions;
using OpenRSC.Server.Drops;
using Xunit;

namespace OpenRSC.Server.Tests;

public class DropTableTests
{
    [Fact]
    public void DropEntry_GetDropRate_ReturnsCorrectRate()
    {
        var alwaysDrop = new DropEntry { ItemId = 1, ItemName = "Test", Rarity = DropRarity.Always };
        var commonDrop = new DropEntry { ItemId = 2, ItemName = "Test", Rarity = DropRarity.Common };
        var rareDrop = new DropEntry { ItemId = 3, ItemName = "Test", Rarity = DropRarity.Rare };

        alwaysDrop.GetDropRate().Should().Be(1.0);
        commonDrop.GetDropRate().Should().BeApproximately(0.25, 0.01);
        rareDrop.GetDropRate().Should().BeApproximately(0.0156, 0.001);
    }

    [Fact]
    public void DropEntry_CustomRate_OverridesRarity()
    {
        var drop = new DropEntry
        {
            ItemId = 1,
            ItemName = "Test",
            Rarity = DropRarity.Common,
            CustomRate = 0.5
        };

        drop.GetDropRate().Should().Be(0.5);
    }

    [Fact]
    public void DropEntry_GetAmount_ReturnsInRange()
    {
        var drop = new DropEntry
        {
            ItemId = 1,
            ItemName = "Test",
            MinAmount = 5,
            MaxAmount = 10
        };

        for (var i = 0; i < 100; i++)
        {
            var amount = drop.GetAmount();
            amount.Should().BeInRange(5, 10);
        }
    }

    [Fact]
    public void WeightedDropTable_Roll_ReturnsEntry()
    {
        var table = new WeightedDropTable { Name = "Test Table" }
            .Add(new DropEntry { ItemId = 1, ItemName = "Item1", Weight = 10 })
            .Add(new DropEntry { ItemId = 2, ItemName = "Item2", Weight = 5 });

        var counts = new Dictionary<int, int>();
        for (var i = 0; i < 1000; i++)
        {
            var drop = table.Roll();
            if (drop is not null)
            {
                counts[drop.ItemId] = counts.GetValueOrDefault(drop.ItemId, 0) + 1;
            }
        }

        // Higher weight item should appear more often
        counts.Should().ContainKey(1);
        counts.Should().ContainKey(2);
        counts[1].Should().BeGreaterThan(counts[2]);
    }

    [Fact]
    public void NpcDropTable_GenerateDrops_IncludesGuaranteed()
    {
        var table = new NpcDropTable { NpcId = 1, NpcName = "Test" }
            .AddGuaranteed(20, "Bones");

        var drops = table.GenerateDrops().ToList();

        drops.Should().ContainSingle(d => d.ItemId == 20);
    }

    [Fact]
    public void InMemoryDropTableRepository_GetDropTable_ReturnsTable()
    {
        var repo = new InMemoryDropTableRepository();

        var goblinTable = repo.GetDropTable(1); // Goblin

        goblinTable.Should().NotBeNull();
        goblinTable!.NpcName.Should().Be("Goblin");
    }

    [Fact]
    public void InMemoryDropTableRepository_GetDropTable_UnknownNpc_ReturnsNull()
    {
        var repo = new InMemoryDropTableRepository();

        var table = repo.GetDropTable(99999);

        table.Should().BeNull();
    }
}
