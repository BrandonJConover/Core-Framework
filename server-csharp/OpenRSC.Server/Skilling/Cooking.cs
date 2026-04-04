using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Cookable item definition.
/// </summary>
public sealed record CookableDefinition
{
    public required int RawItemId { get; init; }
    public required int CookedItemId { get; init; }
    public required int BurntItemId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int StopBurnLevel { get; init; } // Level at which you stop burning
    public bool RequiresRange { get; init; } // Some items need a range, not fire

    public static readonly IReadOnlyDictionary<int, CookableDefinition> All = new Dictionary<int, CookableDefinition>
    {
        // Fish
        [349] = new() { RawItemId = 349, CookedItemId = 350, BurntItemId = 357, Name = "Shrimp", RequiredLevel = 1, Experience = 30, StopBurnLevel = 34 },
        [354] = new() { RawItemId = 354, CookedItemId = 319, BurntItemId = 357, Name = "Anchovies", RequiredLevel = 1, Experience = 30, StopBurnLevel = 34 },
        [351] = new() { RawItemId = 351, CookedItemId = 352, BurntItemId = 357, Name = "Sardine", RequiredLevel = 1, Experience = 40, StopBurnLevel = 38 },
        [355] = new() { RawItemId = 355, CookedItemId = 356, BurntItemId = 357, Name = "Herring", RequiredLevel = 5, Experience = 50, StopBurnLevel = 41 },
        [358] = new() { RawItemId = 358, CookedItemId = 359, BurntItemId = 360, Name = "Trout", RequiredLevel = 15, Experience = 70, StopBurnLevel = 49 },
        [362] = new() { RawItemId = 362, CookedItemId = 363, BurntItemId = 364, Name = "Pike", RequiredLevel = 20, Experience = 80, StopBurnLevel = 52 },
        [359] = new() { RawItemId = 359, CookedItemId = 360, BurntItemId = 361, Name = "Salmon", RequiredLevel = 25, Experience = 90, StopBurnLevel = 58 },
        [366] = new() { RawItemId = 366, CookedItemId = 367, BurntItemId = 368, Name = "Tuna", RequiredLevel = 30, Experience = 100, StopBurnLevel = 63 },
        [373] = new() { RawItemId = 373, CookedItemId = 374, BurntItemId = 375, Name = "Lobster", RequiredLevel = 40, Experience = 120, StopBurnLevel = 74 },
        [372] = new() { RawItemId = 372, CookedItemId = 370, BurntItemId = 371, Name = "Swordfish", RequiredLevel = 45, Experience = 140, StopBurnLevel = 86 },
        [545] = new() { RawItemId = 545, CookedItemId = 546, BurntItemId = 547, Name = "Shark", RequiredLevel = 80, Experience = 210, StopBurnLevel = 99 },

        // Meat
        [133] = new() { RawItemId = 133, CookedItemId = 132, BurntItemId = 134, Name = "Meat", RequiredLevel = 1, Experience = 30, StopBurnLevel = 31 },
        [503] = new() { RawItemId = 503, CookedItemId = 504, BurntItemId = 134, Name = "Chicken", RequiredLevel = 1, Experience = 30, StopBurnLevel = 31 },

        // Bread
        [136] = new() { RawItemId = 136, CookedItemId = 137, BurntItemId = 138, Name = "Bread", RequiredLevel = 1, Experience = 40, StopBurnLevel = 34, RequiresRange = true },

        // Pies
        [254] = new() { RawItemId = 254, CookedItemId = 257, BurntItemId = 258, Name = "Meat Pie", RequiredLevel = 20, Experience = 110, StopBurnLevel = 50, RequiresRange = true },
        [259] = new() { RawItemId = 259, CookedItemId = 261, BurntItemId = 262, Name = "Apple Pie", RequiredLevel = 30, Experience = 130, StopBurnLevel = 60, RequiresRange = true },
    };

    /// <summary>
    /// Gets a cookable by raw item ID.
    /// </summary>
    public static CookableDefinition? GetByRawId(int rawItemId)
    {
        return All.TryGetValue(rawItemId, out var def) ? def : null;
    }
}

/// <summary>
/// Cooking action.
/// </summary>
public sealed class CookingAction : SkillAction
{
    private readonly CookableDefinition _cookable;
    private readonly IItemFactory _itemFactory;
    private readonly bool _isRange;
    private int _itemsToCook;
    private int _cooked;
    private int _burnt;

    public override Skill Skill => Skill.Cooking;

    public CookingAction(Player player, CookableDefinition cookable, IItemFactory itemFactory, bool isRange, int count = 1)
        : base(player, 4) // 4 ticks per cook
    {
        _cookable = cookable;
        _itemFactory = itemFactory;
        _isRange = isRange;
        _itemsToCook = count;
    }

    protected override void OnComplete()
    {
        // Check if we still have the raw item
        if (!Player.Inventory.HasItem(_cookable.RawItemId))
        {
            Cancel();
            ShowResults();
            return;
        }

        // Calculate burn chance
        var level = Player.Skills.GetCurrentLevel(Skill.Cooking);
        var burnChance = CalculateBurnChance(level);

        // Ranges reduce burn chance
        if (_isRange)
            burnChance *= 0.9;

        // Remove raw item
        Player.Inventory.Remove(_cookable.RawItemId, 1);

        if (Random.Shared.NextDouble() < burnChance)
        {
            // Burnt!
            Player.Inventory.Add(_cookable.BurntItemId, 1, _itemFactory);
            Player.Message($"You accidentally burn the {_cookable.Name.ToLower()}.");
            _burnt++;
        }
        else
        {
            // Success!
            Player.Inventory.Add(_cookable.CookedItemId, 1, _itemFactory);
            Player.Skills.AddExperience(Skill.Cooking, _cookable.Experience);
            Player.Message($"You cook the {_cookable.Name.ToLower()}.");
            _cooked++;
        }

        _itemsToCook--;

        // Continue cooking if more to do
        if (_itemsToCook > 0 && Player.Inventory.HasItem(_cookable.RawItemId))
        {
            TicksRemaining = 4;
        }
        else
        {
            ShowResults();
        }
    }

    private double CalculateBurnChance(int level)
    {
        if (level >= _cookable.StopBurnLevel)
            return 0;

        var range = _cookable.StopBurnLevel - _cookable.RequiredLevel;
        var progress = level - _cookable.RequiredLevel;

        // Linear decrease from ~50% to 0%
        return 0.5 * (1 - (double)progress / range);
    }

    private void ShowResults()
    {
        if (_cooked + _burnt > 1)
        {
            Player.Message($"You cooked {_cooked} and burnt {_burnt} {_cookable.Name.ToLower()}.");
        }
    }

    public override bool CanContinue()
    {
        if (!base.CanContinue())
            return false;

        if (!Player.Inventory.HasItem(_cookable.RawItemId))
        {
            Player.Message("You have nothing left to cook.");
            return false;
        }

        return true;
    }
}

/// <summary>
/// Cooking skill manager.
/// </summary>
public static class CookingManager
{
    /// <summary>
    /// Attempts to cook an item.
    /// </summary>
    public static SkillActionResult StartCooking(Player player, int rawItemId, IItemFactory itemFactory, bool isRange, int count = 1)
    {
        var cookable = CookableDefinition.GetByRawId(rawItemId);
        if (cookable is null)
        {
            return SkillActionResult.Fail("You can't cook that.");
        }

        // Check level
        var cookingLevel = player.Skills.GetCurrentLevel(Skill.Cooking);
        if (cookingLevel < cookable.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {cookable.RequiredLevel} Cooking to cook {cookable.Name.ToLower()}.");
        }

        // Check if it requires a range
        if (cookable.RequiresRange && !isRange)
        {
            return SkillActionResult.Fail($"You need to cook {cookable.Name.ToLower()} on a range.");
        }

        // Clamp count to available items
        var available = player.Inventory.CountOf(rawItemId);
        count = Math.Min(count, available);

        if (count <= 0)
        {
            return SkillActionResult.Fail("You don't have any to cook.");
        }

        player.Message($"You begin cooking the {cookable.Name.ToLower()}...");
        return SkillActionResult.Ok(new CookingAction(player, cookable, itemFactory, isRange, count));
    }
}
