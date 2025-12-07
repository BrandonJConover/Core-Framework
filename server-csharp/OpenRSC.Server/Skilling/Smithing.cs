using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Types of metal for smithing.
/// </summary>
public enum MetalType
{
    Bronze,
    Iron,
    Steel,
    Mithril,
    Adamant,
    Rune
}

/// <summary>
/// Bar definition for smelting.
/// </summary>
public sealed record BarDefinition
{
    public required int BarId { get; init; }
    public required string Name { get; init; }
    public required MetalType Metal { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required IReadOnlyList<(int OreId, int Amount)> Ingredients { get; init; }
    public int CoalRequired => Ingredients.FirstOrDefault(i => i.OreId == 153).Amount;

    public static readonly IReadOnlyDictionary<MetalType, BarDefinition> All = new Dictionary<MetalType, BarDefinition>
    {
        [MetalType.Bronze] = new()
        {
            BarId = 169,
            Name = "Bronze bar",
            Metal = MetalType.Bronze,
            RequiredLevel = 1,
            Experience = 6,
            Ingredients = new[] { (202, 1), (203, 1) } // Copper + Tin
        },
        [MetalType.Iron] = new()
        {
            BarId = 170,
            Name = "Iron bar",
            Metal = MetalType.Iron,
            RequiredLevel = 15,
            Experience = 12,
            Ingredients = new[] { (151, 1) } // Iron ore
        },
        [MetalType.Steel] = new()
        {
            BarId = 171,
            Name = "Steel bar",
            Metal = MetalType.Steel,
            RequiredLevel = 30,
            Experience = 17,
            Ingredients = new[] { (151, 1), (153, 2) } // Iron + 2 Coal
        },
        [MetalType.Mithril] = new()
        {
            BarId = 173,
            Name = "Mithril bar",
            Metal = MetalType.Mithril,
            RequiredLevel = 50,
            Experience = 30,
            Ingredients = new[] { (152, 1), (153, 4) } // Mithril + 4 Coal
        },
        [MetalType.Adamant] = new()
        {
            BarId = 174,
            Name = "Adamant bar",
            Metal = MetalType.Adamant,
            RequiredLevel = 70,
            Experience = 37,
            Ingredients = new[] { (409, 1), (153, 6) } // Adamantite + 6 Coal
        },
        [MetalType.Rune] = new()
        {
            BarId = 408,
            Name = "Runite bar",
            Metal = MetalType.Rune,
            RequiredLevel = 85,
            Experience = 50,
            Ingredients = new[] { (410, 1), (153, 8) } // Runite + 8 Coal
        }
    };

    public static BarDefinition? GetByBarId(int barId)
    {
        return All.Values.FirstOrDefault(b => b.BarId == barId);
    }
}

/// <summary>
/// Smithable item category.
/// </summary>
public enum SmithingCategory
{
    Dagger,
    Axe,
    Mace,
    MediumHelm,
    ShortSword,
    Scimitar,
    LongSword,
    BattleAxe,
    ChainBody,
    KiteShield,
    TwoHandedSword,
    PlateLegs,
    PlateBody,
    FullHelm,
    SquareShield,
    Nails,
    DartTips,
    ArrowHeads
}

/// <summary>
/// Smithable item definition.
/// </summary>
public sealed record SmithableDefinition
{
    public required int ItemId { get; init; }
    public required string Name { get; init; }
    public required SmithingCategory Category { get; init; }
    public required MetalType Metal { get; init; }
    public required int BarsRequired { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public int Quantity { get; init; } = 1;

    /// <summary>
    /// Gets the smithing level for a metal type and category.
    /// </summary>
    public static int GetLevelForCategory(MetalType metal, SmithingCategory category)
    {
        var baseLevel = metal switch
        {
            MetalType.Bronze => 1,
            MetalType.Iron => 15,
            MetalType.Steel => 30,
            MetalType.Mithril => 50,
            MetalType.Adamant => 70,
            MetalType.Rune => 85,
            _ => 1
        };

        var categoryOffset = category switch
        {
            SmithingCategory.Dagger => 0,
            SmithingCategory.Axe => 1,
            SmithingCategory.Mace => 2,
            SmithingCategory.MediumHelm => 3,
            SmithingCategory.ShortSword => 4,
            SmithingCategory.Scimitar => 5,
            SmithingCategory.LongSword => 6,
            SmithingCategory.BattleAxe => 10,
            SmithingCategory.ChainBody => 11,
            SmithingCategory.KiteShield => 12,
            SmithingCategory.TwoHandedSword => 14,
            SmithingCategory.PlateLegs => 16,
            SmithingCategory.PlateBody => 18,
            SmithingCategory.FullHelm => 7,
            SmithingCategory.SquareShield => 8,
            _ => 0
        };

        return baseLevel + categoryOffset;
    }
}

/// <summary>
/// Smelting action.
/// </summary>
public sealed class SmeltingAction : SkillAction
{
    private readonly BarDefinition _bar;
    private readonly IItemFactory _itemFactory;
    private int _barsToSmelt;
    private int _smelted;

    public override Skill Skill => Skill.Smithing;

    public SmeltingAction(Player player, BarDefinition bar, IItemFactory itemFactory, int count = 1)
        : base(player, 4)
    {
        _bar = bar;
        _itemFactory = itemFactory;
        _barsToSmelt = count;
    }

    protected override void OnComplete()
    {
        // Check ingredients
        if (!HasIngredients())
        {
            Player.Message("You've run out of ore.");
            Cancel();
            return;
        }

        // Iron has 50% success rate without Ring of Forging
        if (_bar.Metal == MetalType.Iron && Random.Shared.NextDouble() > 0.5)
        {
            ConsumeIngredients();
            Player.Message("The iron ore is too impure and you fail to smelt it.");
        }
        else
        {
            ConsumeIngredients();
            Player.Inventory.Add(_bar.BarId, 1, _itemFactory);
            Player.Skills.AddExperience(Skill.Smithing, _bar.Experience);
            Player.Message($"You smelt a {_bar.Name.ToLower()}.");
            _smelted++;
        }

        _barsToSmelt--;

        if (_barsToSmelt > 0 && HasIngredients())
        {
            TicksRemaining = 4;
        }
        else if (_smelted > 1)
        {
            Player.Message($"You smelted {_smelted} bars.");
        }
    }

    private bool HasIngredients()
    {
        foreach (var (oreId, amount) in _bar.Ingredients)
        {
            if (!Player.Inventory.HasItem(oreId, amount))
                return false;
        }
        return true;
    }

    private void ConsumeIngredients()
    {
        foreach (var (oreId, amount) in _bar.Ingredients)
        {
            Player.Inventory.Remove(oreId, amount);
        }
    }
}

/// <summary>
/// Smithing (anvil) action.
/// </summary>
public sealed class SmithingAction : SkillAction
{
    private readonly SmithableDefinition _item;
    private readonly IItemFactory _itemFactory;
    private int _itemsToSmith;
    private int _smithed;

    public override Skill Skill => Skill.Smithing;

    public SmithingAction(Player player, SmithableDefinition item, IItemFactory itemFactory, int count = 1)
        : base(player, 3)
    {
        _item = item;
        _itemFactory = itemFactory;
        _itemsToSmith = count;
    }

    protected override void OnComplete()
    {
        var barDef = BarDefinition.All[_item.Metal];

        // Check for bars
        if (!Player.Inventory.HasItem(barDef.BarId, _item.BarsRequired))
        {
            Player.Message("You don't have enough bars.");
            Cancel();
            return;
        }

        // Check for hammer
        if (!Player.Inventory.HasItem(168)) // Hammer
        {
            Player.Message("You need a hammer to smith.");
            Cancel();
            return;
        }

        // Consume bars
        Player.Inventory.Remove(barDef.BarId, _item.BarsRequired);

        // Create item
        Player.Inventory.Add(_item.ItemId, _item.Quantity, _itemFactory);
        Player.Skills.AddExperience(Skill.Smithing, _item.Experience);
        Player.Message($"You make a {_item.Name.ToLower()}.");
        _smithed++;

        _itemsToSmith--;

        if (_itemsToSmith > 0 && Player.Inventory.HasItem(barDef.BarId, _item.BarsRequired))
        {
            TicksRemaining = 3;
        }
    }
}

/// <summary>
/// Smithing skill manager.
/// </summary>
public static class SmithingManager
{
    /// <summary>
    /// Attempts to smelt ore into bars.
    /// </summary>
    public static SkillActionResult StartSmelting(Player player, MetalType metal, IItemFactory itemFactory, int count = 1)
    {
        if (!BarDefinition.All.TryGetValue(metal, out var bar))
        {
            return SkillActionResult.Fail("Invalid bar type.");
        }

        // Check level
        var smithingLevel = player.Skills.GetCurrentLevel(Skill.Smithing);
        if (smithingLevel < bar.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {bar.RequiredLevel} Smithing to smelt {bar.Name.ToLower()}.");
        }

        // Check ingredients
        foreach (var (oreId, amount) in bar.Ingredients)
        {
            if (!player.Inventory.HasItem(oreId, amount))
            {
                return SkillActionResult.Fail("You don't have the required ore.");
            }
        }

        player.Message($"You begin smelting {bar.Name.ToLower()}...");
        return SkillActionResult.Ok(new SmeltingAction(player, bar, itemFactory, count));
    }

    /// <summary>
    /// Attempts to smith an item at an anvil.
    /// </summary>
    public static SkillActionResult StartSmithing(Player player, SmithableDefinition item, IItemFactory itemFactory, int count = 1)
    {
        // Check level
        var smithingLevel = player.Skills.GetCurrentLevel(Skill.Smithing);
        if (smithingLevel < item.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {item.RequiredLevel} Smithing to make a {item.Name.ToLower()}.");
        }

        // Check for hammer
        if (!player.Inventory.HasItem(168)) // Hammer item ID
        {
            return SkillActionResult.Fail("You need a hammer to smith.");
        }

        // Check for bars
        var barDef = BarDefinition.All[item.Metal];
        if (!player.Inventory.HasItem(barDef.BarId, item.BarsRequired))
        {
            return SkillActionResult.Fail($"You need {item.BarsRequired} {barDef.Name.ToLower()}(s) to make a {item.Name.ToLower()}.");
        }

        player.Message($"You begin smithing a {item.Name.ToLower()}...");
        return SkillActionResult.Ok(new SmithingAction(player, item, itemFactory, count));
    }
}
