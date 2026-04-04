using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Fish definitions for fishing.
/// </summary>
public sealed record FishDefinition
{
    public required int ItemId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required FishingMethod Method { get; init; }
    public required int BaitId { get; init; } // 0 if no bait needed
    public double CatchRate { get; init; } = 0.5;

    public static readonly IReadOnlyDictionary<int, FishDefinition> All = new Dictionary<int, FishDefinition>
    {
        // Net fishing
        [349] = new() { ItemId = 349, Name = "Shrimp", RequiredLevel = 1, Experience = 10, Method = FishingMethod.Net, BaitId = 0, CatchRate = 0.7 },
        [354] = new() { ItemId = 354, Name = "Anchovies", RequiredLevel = 15, Experience = 40, Method = FishingMethod.Net, BaitId = 0, CatchRate = 0.5 },

        // Bait fishing
        [351] = new() { ItemId = 351, Name = "Sardine", RequiredLevel = 5, Experience = 20, Method = FishingMethod.Bait, BaitId = 313, CatchRate = 0.65 },
        [355] = new() { ItemId = 355, Name = "Herring", RequiredLevel = 10, Experience = 30, Method = FishingMethod.Bait, BaitId = 313, CatchRate = 0.55 },
        [362] = new() { ItemId = 362, Name = "Pike", RequiredLevel = 25, Experience = 60, Method = FishingMethod.Bait, BaitId = 313, CatchRate = 0.4 },

        // Fly fishing
        [358] = new() { ItemId = 358, Name = "Trout", RequiredLevel = 20, Experience = 50, Method = FishingMethod.Fly, BaitId = 314, CatchRate = 0.5 },
        [359] = new() { ItemId = 359, Name = "Salmon", RequiredLevel = 30, Experience = 70, Method = FishingMethod.Fly, BaitId = 314, CatchRate = 0.4 },

        // Harpoon fishing
        [366] = new() { ItemId = 366, Name = "Tuna", RequiredLevel = 35, Experience = 80, Method = FishingMethod.Harpoon, BaitId = 0, CatchRate = 0.35 },
        [372] = new() { ItemId = 372, Name = "Swordfish", RequiredLevel = 50, Experience = 100, Method = FishingMethod.Harpoon, BaitId = 0, CatchRate = 0.25 },

        // Lobster pot
        [373] = new() { ItemId = 373, Name = "Lobster", RequiredLevel = 40, Experience = 90, Method = FishingMethod.Cage, BaitId = 0, CatchRate = 0.3 },

        // Shark
        [545] = new() { ItemId = 545, Name = "Shark", RequiredLevel = 76, Experience = 110, Method = FishingMethod.Harpoon, BaitId = 0, CatchRate = 0.15 }
    };
}

/// <summary>
/// Fishing methods/equipment.
/// </summary>
public enum FishingMethod
{
    Net,    // Small fishing net (Item 376)
    Bait,   // Fishing rod + bait (Item 377)
    Fly,    // Fly fishing rod + feathers (Item 378)
    Harpoon,// Harpoon (Item 379)
    Cage    // Lobster pot (Item 375)
}

/// <summary>
/// Fishing spot definition.
/// </summary>
public sealed record FishingSpot
{
    public required int ObjectId { get; init; }
    public required FishingMethod Method { get; init; }
    public required int[] AvailableFish { get; init; }
}

/// <summary>
/// Fishing action.
/// </summary>
public sealed class FishingAction : SkillAction
{
    private readonly FishDefinition _fish;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Fishing;

    public FishingAction(Player player, FishDefinition fish, IItemFactory itemFactory)
        : base(player, CalculateTicks(player, fish))
    {
        _fish = fish;
        _itemFactory = itemFactory;
    }

    private static int CalculateTicks(Player player, FishDefinition fish)
    {
        // Base 4 ticks, reduced by level
        var levelDiff = player.Skills.GetCurrentLevel(Skill.Fishing) - fish.RequiredLevel;
        return Math.Max(3, 5 - levelDiff / 10);
    }

    protected override void OnComplete()
    {
        // Check for success
        var level = Player.Skills.GetCurrentLevel(Skill.Fishing);
        var successChance = _fish.CatchRate + (level - _fish.RequiredLevel) * 0.01;

        if (Random.Shared.NextDouble() < successChance)
        {
            // Caught a fish!
            if (Player.Inventory.Add(_fish.ItemId, 1, _itemFactory))
            {
                Player.Skills.AddExperience(Skill.Fishing, _fish.Experience);
                Player.Message($"You catch a {_fish.Name.ToLower()}.");
            }
            else
            {
                Player.Message("Your inventory is full.");
                Cancel();
            }
        }
        else
        {
            Player.Message("You fail to catch anything.");
        }

        // Reset for next attempt if not cancelled
        if (!IsCancelled)
        {
            TicksRemaining = CalculateTicks(Player, _fish);
        }
    }

    public override bool CanContinue()
    {
        if (!base.CanContinue())
            return false;

        // Check for bait if needed
        if (_fish.BaitId > 0 && !Player.Inventory.HasItem(_fish.BaitId))
        {
            Player.Message("You've run out of bait.");
            return false;
        }

        return true;
    }
}

/// <summary>
/// Fishing skill manager.
/// </summary>
public static class FishingManager
{
    private static readonly Dictionary<FishingMethod, int> EquipmentIds = new()
    {
        [FishingMethod.Net] = 376,
        [FishingMethod.Bait] = 377,
        [FishingMethod.Fly] = 378,
        [FishingMethod.Harpoon] = 379,
        [FishingMethod.Cage] = 375
    };

    /// <summary>
    /// Attempts to start fishing.
    /// </summary>
    public static SkillActionResult StartFishing(Player player, FishingSpot spot, IItemFactory itemFactory)
    {
        // Check for equipment
        var equipmentId = EquipmentIds[spot.Method];
        if (!player.Inventory.HasItem(equipmentId))
        {
            return SkillActionResult.Fail($"You need a {GetEquipmentName(spot.Method)} to fish here.");
        }

        // Find the best fish the player can catch
        FishDefinition? bestFish = null;
        var fishingLevel = player.Skills.GetCurrentLevel(Skill.Fishing);

        foreach (var fishId in spot.AvailableFish)
        {
            if (!FishDefinition.All.TryGetValue(fishId, out var fish))
                continue;

            if (fish.RequiredLevel <= fishingLevel)
            {
                if (bestFish is null || fish.RequiredLevel > bestFish.RequiredLevel)
                {
                    bestFish = fish;
                }
            }
        }

        if (bestFish is null)
        {
            return SkillActionResult.Fail("Your fishing level is too low to fish here.");
        }

        // Check for bait
        if (bestFish.BaitId > 0 && !player.Inventory.HasItem(bestFish.BaitId))
        {
            return SkillActionResult.Fail("You don't have any bait.");
        }

        // Check inventory space
        if (player.Inventory.IsFull)
        {
            return SkillActionResult.Fail("Your inventory is full.");
        }

        player.Message($"You attempt to catch {bestFish.Name.ToLower()}...");
        return SkillActionResult.Ok(new FishingAction(player, bestFish, itemFactory));
    }

    private static string GetEquipmentName(FishingMethod method) => method switch
    {
        FishingMethod.Net => "small fishing net",
        FishingMethod.Bait => "fishing rod",
        FishingMethod.Fly => "fly fishing rod",
        FishingMethod.Harpoon => "harpoon",
        FishingMethod.Cage => "lobster pot",
        _ => "fishing equipment"
    };
}
