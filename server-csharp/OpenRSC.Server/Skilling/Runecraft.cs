using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Rune definitions.
/// </summary>
public sealed record RuneDefinition
{
    public required int RuneId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public int MultiplierLevel { get; init; } = 99; // Level for 2x runes

    public static readonly IReadOnlyDictionary<int, RuneDefinition> All = new Dictionary<int, RuneDefinition>
    {
        [33] = new() { RuneId = 33, Name = "Air rune", RequiredLevel = 1, Experience = 5, MultiplierLevel = 11 },
        [35] = new() { RuneId = 35, Name = "Mind rune", RequiredLevel = 2, Experience = 5, MultiplierLevel = 14 },
        [32] = new() { RuneId = 32, Name = "Water rune", RequiredLevel = 5, Experience = 6, MultiplierLevel = 19 },
        [34] = new() { RuneId = 34, Name = "Earth rune", RequiredLevel = 9, Experience = 6, MultiplierLevel = 26 },
        [31] = new() { RuneId = 31, Name = "Fire rune", RequiredLevel = 14, Experience = 7, MultiplierLevel = 35 },
        [36] = new() { RuneId = 36, Name = "Body rune", RequiredLevel = 20, Experience = 7, MultiplierLevel = 46 },
        [46] = new() { RuneId = 46, Name = "Cosmic rune", RequiredLevel = 27, Experience = 8, MultiplierLevel = 59 },
        [40] = new() { RuneId = 40, Name = "Chaos rune", RequiredLevel = 35, Experience = 8, MultiplierLevel = 74 },
        [42] = new() { RuneId = 42, Name = "Nature rune", RequiredLevel = 44, Experience = 9, MultiplierLevel = 91 },
        [38] = new() { RuneId = 38, Name = "Law rune", RequiredLevel = 54, Experience = 9, MultiplierLevel = 99 },
        [41] = new() { RuneId = 41, Name = "Death rune", RequiredLevel = 65, Experience = 10, MultiplierLevel = 99 },
        [619] = new() { RuneId = 619, Name = "Blood rune", RequiredLevel = 77, Experience = 10, MultiplierLevel = 99 }
    };
}

/// <summary>
/// Altar definitions.
/// </summary>
public sealed record AltarDefinition
{
    public required int AltarId { get; init; }
    public required int RuneId { get; init; }
    public required Point Location { get; init; }
    public required string Name { get; init; }

    public static readonly IReadOnlyDictionary<int, AltarDefinition> All = new Dictionary<int, AltarDefinition>
    {
        [1190] = new() { AltarId = 1190, RuneId = 33, Location = new Point(2841, 4829), Name = "Air altar" },
        [1191] = new() { AltarId = 1191, RuneId = 35, Location = new Point(2793, 4828), Name = "Mind altar" },
        [1192] = new() { AltarId = 1192, RuneId = 32, Location = new Point(2726, 4832), Name = "Water altar" },
        [1193] = new() { AltarId = 1193, RuneId = 34, Location = new Point(2655, 4830), Name = "Earth altar" },
        [1194] = new() { AltarId = 1194, RuneId = 31, Location = new Point(2574, 4849), Name = "Fire altar" },
        [1195] = new() { AltarId = 1195, RuneId = 36, Location = new Point(2521, 4834), Name = "Body altar" },
        [1196] = new() { AltarId = 1196, RuneId = 46, Location = new Point(2162, 4833), Name = "Cosmic altar" },
        [1197] = new() { AltarId = 1197, RuneId = 40, Location = new Point(2281, 4837), Name = "Chaos altar" },
        [1198] = new() { AltarId = 1198, RuneId = 42, Location = new Point(2400, 4835), Name = "Nature altar" },
        [1199] = new() { AltarId = 1199, RuneId = 38, Location = new Point(2464, 4818), Name = "Law altar" },
        [1200] = new() { AltarId = 1200, RuneId = 41, Location = new Point(2208, 4830), Name = "Death altar" }
    };
}

/// <summary>
/// Runecrafting items.
/// </summary>
public static class RunecraftItems
{
    public const int RuneEssence = 1436;
    public const int PureEssence = 7936;
    public const int AirTalisman = 1438;
    public const int MindTalisman = 1448;
    public const int WaterTalisman = 1444;
    public const int EarthTalisman = 1440;
    public const int FireTalisman = 1442;
    public const int BodyTalisman = 1446;
    public const int CosmicTalisman = 1454;
    public const int ChaosTalisman = 1452;
    public const int NatureTalisman = 1462;
    public const int LawTalisman = 1458;
    public const int DeathTalisman = 1456;

    /// <summary>
    /// Checks if essence can be used for a rune.
    /// </summary>
    public static bool CanUseEssence(int essenceId, RuneDefinition rune)
    {
        // Pure essence required for runes above body
        if (rune.RequiredLevel > 20)
        {
            return essenceId == PureEssence;
        }

        return essenceId == RuneEssence || essenceId == PureEssence;
    }
}

/// <summary>
/// Runecrafting action.
/// </summary>
public sealed class RunecraftingAction : SkillAction
{
    private readonly RuneDefinition _rune;
    private readonly int _essenceCount;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Runecraft;

    public RunecraftingAction(Player player, RuneDefinition rune, int essenceCount, IItemFactory itemFactory)
        : base(player, 3)
    {
        _rune = rune;
        _essenceCount = essenceCount;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        // Calculate rune multiplier based on level
        var level = Player.Skills.GetCurrentLevel(Skill.Runecraft);
        var multiplier = CalculateMultiplier(level);
        var runesPerEssence = multiplier;

        // Remove essence
        var essenceRemoved = 0;
        var pureCount = Player.Inventory.CountOf(RunecraftItems.PureEssence);
        var normalCount = Player.Inventory.CountOf(RunecraftItems.RuneEssence);

        // Prefer pure essence for higher runes
        if (_rune.RequiredLevel > 20)
        {
            var toRemove = Math.Min(pureCount, _essenceCount);
            Player.Inventory.Remove(RunecraftItems.PureEssence, toRemove);
            essenceRemoved = toRemove;
        }
        else
        {
            // Use normal essence first
            var normalToRemove = Math.Min(normalCount, _essenceCount);
            Player.Inventory.Remove(RunecraftItems.RuneEssence, normalToRemove);
            essenceRemoved = normalToRemove;

            if (essenceRemoved < _essenceCount)
            {
                var pureToRemove = Math.Min(pureCount, _essenceCount - essenceRemoved);
                Player.Inventory.Remove(RunecraftItems.PureEssence, pureToRemove);
                essenceRemoved += pureToRemove;
            }
        }

        if (essenceRemoved == 0)
        {
            Player.Message("You don't have any essence.");
            Cancel();
            return;
        }

        // Create runes
        var runesCreated = essenceRemoved * runesPerEssence;
        Player.Inventory.Add(_rune.RuneId, runesCreated, _itemFactory);

        // Grant experience
        var experience = essenceRemoved * _rune.Experience;
        Player.Skills.AddExperience(Skill.Runecraft, experience);

        Player.Message($"You craft {runesCreated} {_rune.Name.ToLower()}s.");
    }

    private int CalculateMultiplier(int level)
    {
        if (level < _rune.MultiplierLevel)
            return 1;

        // Calculate how many times the multiplier threshold has been passed
        var levelsAbove = level - _rune.MultiplierLevel;
        var additionalMultiplier = levelsAbove / (_rune.MultiplierLevel - _rune.RequiredLevel + 1);

        return 2 + additionalMultiplier;
    }
}

/// <summary>
/// Runecrafting skill manager.
/// </summary>
public static class RunecraftingManager
{
    /// <summary>
    /// Attempts to craft runes at an altar.
    /// </summary>
    public static SkillActionResult CraftRunes(Player player, int altarId, IItemFactory itemFactory)
    {
        if (!AltarDefinition.All.TryGetValue(altarId, out var altar))
            return SkillActionResult.Fail("This is not a runecrafting altar.");

        if (!RuneDefinition.All.TryGetValue(altar.RuneId, out var rune))
            return SkillActionResult.Fail("Unknown rune type.");

        var level = player.Skills.GetCurrentLevel(Skill.Runecraft);
        if (level < rune.RequiredLevel)
            return SkillActionResult.Fail($"You need level {rune.RequiredLevel} Runecraft to craft {rune.Name.ToLower()}s.");

        // Count available essence
        var essenceCount = CountUsableEssence(player, rune);
        if (essenceCount == 0)
        {
            if (rune.RequiredLevel > 20)
                return SkillActionResult.Fail("You need pure essence to craft this rune.");
            else
                return SkillActionResult.Fail("You need rune essence to craft runes.");
        }

        player.Message($"You bind the temple's power into {rune.Name.ToLower()}s...");
        return SkillActionResult.Ok(new RunecraftingAction(player, rune, essenceCount, itemFactory));
    }

    private static int CountUsableEssence(Player player, RuneDefinition rune)
    {
        var pureCount = player.Inventory.CountOf(RunecraftItems.PureEssence);

        if (rune.RequiredLevel > 20)
        {
            return pureCount;
        }

        var normalCount = player.Inventory.CountOf(RunecraftItems.RuneEssence);
        return normalCount + pureCount;
    }

    /// <summary>
    /// Uses a talisman on a mysterious ruins to enter.
    /// </summary>
    public static bool CanEnterAltar(Player player, int talismanId, int ruinsId)
    {
        // Check if player has the matching talisman
        if (!player.Inventory.HasItem(talismanId))
            return false;

        // Would check if talisman matches ruins
        return true;
    }
}

/// <summary>
/// Pouch for holding extra essence.
/// </summary>
public sealed class RunecraftPouch
{
    public int PouchId { get; init; }
    public string Name { get; init; }
    public int Capacity { get; init; }
    public int RequiredLevel { get; init; }
    public int CurrentAmount { get; private set; }
    public int Degradation { get; private set; }
    public int MaxDegradation { get; init; }

    public bool IsFull => CurrentAmount >= Capacity;
    public bool IsEmpty => CurrentAmount == 0;
    public bool IsDegraded => Degradation >= MaxDegradation;

    public RunecraftPouch(int pouchId, string name, int capacity, int requiredLevel, int maxDegradation)
    {
        PouchId = pouchId;
        Name = name;
        Capacity = capacity;
        RequiredLevel = requiredLevel;
        MaxDegradation = maxDegradation;
    }

    /// <summary>
    /// Fills the pouch with essence.
    /// </summary>
    public int Fill(Player player)
    {
        if (IsFull || IsDegraded)
            return 0;

        var space = Capacity - CurrentAmount;
        var available = player.Inventory.CountOf(RunecraftItems.PureEssence) +
                       player.Inventory.CountOf(RunecraftItems.RuneEssence);

        var toStore = Math.Min(space, available);

        if (toStore > 0)
        {
            // Remove from inventory
            var pureRemoved = Math.Min(player.Inventory.CountOf(RunecraftItems.PureEssence), toStore);
            player.Inventory.Remove(RunecraftItems.PureEssence, pureRemoved);

            var remaining = toStore - pureRemoved;
            if (remaining > 0)
            {
                player.Inventory.Remove(RunecraftItems.RuneEssence, remaining);
            }

            CurrentAmount += toStore;
        }

        return toStore;
    }

    /// <summary>
    /// Empties the pouch.
    /// </summary>
    public int Empty(Player player, IItemFactory itemFactory)
    {
        if (IsEmpty)
            return 0;

        var space = 30 - player.Inventory.UsedSlots;
        var toReturn = Math.Min(CurrentAmount, space);

        if (toReturn > 0)
        {
            player.Inventory.Add(RunecraftItems.PureEssence, toReturn, itemFactory);
            CurrentAmount -= toReturn;
            Degradation++;
        }

        return toReturn;
    }

    /// <summary>
    /// Repairs the pouch.
    /// </summary>
    public void Repair()
    {
        Degradation = 0;
    }

    public static readonly IReadOnlyList<RunecraftPouch> PouchTypes = new List<RunecraftPouch>
    {
        new(5509, "Small pouch", 3, 1, 45),
        new(5510, "Medium pouch", 6, 25, 30),
        new(5512, "Large pouch", 9, 50, 20),
        new(5514, "Giant pouch", 12, 75, 10)
    };
}
