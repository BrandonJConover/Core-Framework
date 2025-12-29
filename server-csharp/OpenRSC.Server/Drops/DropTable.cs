using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;

namespace OpenRSC.Server.Drops;

/// <summary>
/// Rarity tier for drops.
/// </summary>
public enum DropRarity
{
    Always,     // 1/1 (100%)
    Common,     // 1/4 (25%)
    Uncommon,   // 1/16 (6.25%)
    Rare,       // 1/64 (1.56%)
    VeryRare,   // 1/256 (0.39%)
    SuperRare,  // 1/1024 (0.098%)
    UltraRare   // 1/4096 (0.024%)
}

/// <summary>
/// A single drop entry.
/// </summary>
public sealed record DropEntry
{
    public required int ItemId { get; init; }
    public required string ItemName { get; init; }
    public int MinAmount { get; init; } = 1;
    public int MaxAmount { get; init; } = 1;
    public int Weight { get; init; } = 1;
    public DropRarity Rarity { get; init; } = DropRarity.Common;
    public double? CustomRate { get; init; } // Override rarity with custom rate

    /// <summary>
    /// Gets the drop rate (0-1).
    /// </summary>
    public double GetDropRate()
    {
        if (CustomRate.HasValue)
            return CustomRate.Value;

        return Rarity switch
        {
            DropRarity.Always => 1.0,
            DropRarity.Common => 0.25,
            DropRarity.Uncommon => 0.0625,
            DropRarity.Rare => 0.0156,
            DropRarity.VeryRare => 0.0039,
            DropRarity.SuperRare => 0.00098,
            DropRarity.UltraRare => 0.00024,
            _ => 0
        };
    }

    /// <summary>
    /// Rolls for this drop.
    /// </summary>
    public bool Roll()
    {
        return Random.Shared.NextDouble() < GetDropRate();
    }

    /// <summary>
    /// Gets the amount to drop.
    /// </summary>
    public int GetAmount()
    {
        if (MinAmount == MaxAmount)
            return MinAmount;

        return Random.Shared.Next(MinAmount, MaxAmount + 1);
    }
}

/// <summary>
/// A weighted table of drops (one is selected).
/// </summary>
public sealed class WeightedDropTable
{
    private readonly List<DropEntry> _entries = new();
    private int _totalWeight;

    public string Name { get; init; } = "Unnamed";
    public IReadOnlyList<DropEntry> Entries => _entries;

    /// <summary>
    /// Adds an entry to the table.
    /// </summary>
    public WeightedDropTable Add(DropEntry entry)
    {
        _entries.Add(entry);
        _totalWeight += entry.Weight;
        return this;
    }

    /// <summary>
    /// Rolls the table and returns a drop.
    /// </summary>
    public DropEntry? Roll()
    {
        if (_entries.Count == 0 || _totalWeight <= 0)
            return null;

        var roll = Random.Shared.Next(_totalWeight);
        var cumulative = 0;

        foreach (var entry in _entries)
        {
            cumulative += entry.Weight;
            if (roll < cumulative)
                return entry;
        }

        return _entries[^1];
    }
}

/// <summary>
/// A complete drop table for an NPC.
/// </summary>
public sealed class NpcDropTable
{
    private readonly List<DropEntry> _guaranteedDrops = new();
    private readonly List<DropEntry> _mainDrops = new();
    private readonly List<WeightedDropTable> _rareTables = new();

    public int NpcId { get; init; }
    public string NpcName { get; init; } = "Unknown";

    /// <summary>
    /// Adds a guaranteed drop (always drops).
    /// </summary>
    public NpcDropTable AddGuaranteed(int itemId, string name, int minAmount = 1, int maxAmount = 1)
    {
        _guaranteedDrops.Add(new DropEntry
        {
            ItemId = itemId,
            ItemName = name,
            MinAmount = minAmount,
            MaxAmount = maxAmount,
            Rarity = DropRarity.Always
        });
        return this;
    }

    /// <summary>
    /// Adds a main drop.
    /// </summary>
    public NpcDropTable AddDrop(int itemId, string name, DropRarity rarity, int minAmount = 1, int maxAmount = 1)
    {
        _mainDrops.Add(new DropEntry
        {
            ItemId = itemId,
            ItemName = name,
            MinAmount = minAmount,
            MaxAmount = maxAmount,
            Rarity = rarity
        });
        return this;
    }

    /// <summary>
    /// Adds a rare drop table.
    /// </summary>
    public NpcDropTable AddRareTable(WeightedDropTable table)
    {
        _rareTables.Add(table);
        return this;
    }

    /// <summary>
    /// Generates drops for this NPC.
    /// </summary>
    public IEnumerable<(int ItemId, int Amount)> GenerateDrops()
    {
        // Guaranteed drops always happen
        foreach (var drop in _guaranteedDrops)
        {
            yield return (drop.ItemId, drop.GetAmount());
        }

        // Roll main drops
        foreach (var drop in _mainDrops)
        {
            if (drop.Roll())
            {
                yield return (drop.ItemId, drop.GetAmount());
            }
        }

        // Roll rare tables
        foreach (var table in _rareTables)
        {
            var drop = table.Roll();
            if (drop is not null && drop.Roll())
            {
                yield return (drop.ItemId, drop.GetAmount());
            }
        }
    }
}

/// <summary>
/// Repository for NPC drop tables.
/// </summary>
public interface IDropTableRepository
{
    NpcDropTable? GetDropTable(int npcId);
    void RegisterDropTable(NpcDropTable table);
}

/// <summary>
/// In-memory drop table repository.
/// </summary>
public sealed class InMemoryDropTableRepository : IDropTableRepository
{
    private readonly Dictionary<int, NpcDropTable> _tables = new();

    public InMemoryDropTableRepository()
    {
        InitializeDefaultTables();
    }

    private void InitializeDefaultTables()
    {
        // Goblin drops
        RegisterDropTable(new NpcDropTable { NpcId = 1, NpcName = "Goblin" }
            .AddGuaranteed(20, "Bones")
            .AddDrop(10, "Bronze sword", DropRarity.Common)
            .AddDrop(4, "Coins", DropRarity.Common, 1, 5)
            .AddDrop(155, "Cabbage", DropRarity.Uncommon)
        );

        // Guard drops
        RegisterDropTable(new NpcDropTable { NpcId = 65, NpcName = "Guard" }
            .AddGuaranteed(20, "Bones")
            .AddDrop(4, "Coins", DropRarity.Common, 10, 30)
            .AddDrop(71, "Iron sword", DropRarity.Uncommon)
        );

        // Lesser demon drops
        RegisterDropTable(new NpcDropTable { NpcId = 82, NpcName = "Lesser Demon" }
            .AddGuaranteed(20, "Bones")
            .AddDrop(4, "Coins", DropRarity.Common, 50, 200)
            .AddDrop(397, "Rune med helm", DropRarity.Rare)
            .AddDrop(112, "Fire runes", DropRarity.Common, 5, 20)
            .AddDrop(41, "Death runes", DropRarity.Uncommon, 1, 5)
        );

        // Greater demon drops
        RegisterDropTable(new NpcDropTable { NpcId = 87, NpcName = "Greater Demon" }
            .AddGuaranteed(20, "Bones")
            .AddDrop(4, "Coins", DropRarity.Common, 100, 500)
            .AddDrop(398, "Rune full helm", DropRarity.VeryRare)
            .AddDrop(399, "Rune battleaxe", DropRarity.VeryRare)
            .AddDrop(41, "Death runes", DropRarity.Uncommon, 5, 15)
            .AddDrop(42, "Blood runes", DropRarity.Rare, 1, 5)
        );

        // King Black Dragon
        var kbdRareTable = new WeightedDropTable { Name = "KBD Rare" }
            .Add(new DropEntry { ItemId = 1277, ItemName = "Dragon med helm", Weight = 1, Rarity = DropRarity.SuperRare })
            .Add(new DropEntry { ItemId = 594, ItemName = "Dragon axe", Weight = 1, Rarity = DropRarity.SuperRare });

        RegisterDropTable(new NpcDropTable { NpcId = 201, NpcName = "King Black Dragon" }
            .AddGuaranteed(814, "Dragon bones")
            .AddGuaranteed(1092, "Black dragonhide", 1, 2)
            .AddDrop(4, "Coins", DropRarity.Common, 500, 2000)
            .AddDrop(42, "Blood runes", DropRarity.Common, 10, 30)
            .AddDrop(619, "Runite bar", DropRarity.Uncommon, 1, 3)
            .AddRareTable(kbdRareTable)
        );
    }

    public NpcDropTable? GetDropTable(int npcId)
    {
        return _tables.GetValueOrDefault(npcId);
    }

    public void RegisterDropTable(NpcDropTable table)
    {
        _tables[table.NpcId] = table;
    }
}

/// <summary>
/// Service for handling NPC drops.
/// </summary>
public sealed class DropService
{
    private readonly IDropTableRepository _repository;
    private readonly IItemFactory _itemFactory;

    public DropService(IDropTableRepository repository, IItemFactory itemFactory)
    {
        _repository = repository;
        _itemFactory = itemFactory;
    }

    /// <summary>
    /// Generates drops for an NPC death.
    /// </summary>
    public IEnumerable<Item> GenerateDrops(Npc npc)
    {
        var table = _repository.GetDropTable(npc.NpcId);
        if (table is null)
        {
            // Default: just bones
            yield return _itemFactory.Create(20); // Bones
            yield break;
        }

        foreach (var (itemId, amount) in table.GenerateDrops())
        {
            yield return _itemFactory.Create(itemId, amount);
        }
    }

    /// <summary>
    /// Generates drops for a player death (lost items).
    /// </summary>
    public IEnumerable<Item> GetLostItemsOnDeath(Player player, int itemsKept)
    {
        var allItems = new List<Item>();

        // Collect all items from inventory
        foreach (var item in player.Inventory.GetItems())
        {
            allItems.Add(item);
        }

        // Collect all equipped items
        foreach (var (_, item) in player.Equipment.GetEquipped())
        {
            allItems.Add(item);
        }

        // Sort by value descending
        var sorted = allItems
            .OrderByDescending(i => i.Definition.BasePrice * i.Amount)
            .ToList();

        // Skip kept items, return lost items
        return sorted.Skip(itemsKept);
    }
}
