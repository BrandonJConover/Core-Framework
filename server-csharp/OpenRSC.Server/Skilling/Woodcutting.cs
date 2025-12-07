using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Tree/Log definition for woodcutting.
/// </summary>
public sealed record TreeDefinition
{
    public required int LogId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int RespawnTicks { get; init; }
    public double SuccessRate { get; init; } = 0.5;

    public static readonly IReadOnlyDictionary<int, TreeDefinition> All = new Dictionary<int, TreeDefinition>
    {
        [14] = new() { LogId = 14, Name = "Tree", RequiredLevel = 1, Experience = 25, RespawnTicks = 30, SuccessRate = 0.9 },
        [632] = new() { LogId = 632, Name = "Oak tree", RequiredLevel = 15, Experience = 37, RespawnTicks = 60, SuccessRate = 0.7 },
        [633] = new() { LogId = 633, Name = "Willow tree", RequiredLevel = 30, Experience = 67, RespawnTicks = 90, SuccessRate = 0.55 },
        [634] = new() { LogId = 634, Name = "Maple tree", RequiredLevel = 45, Experience = 100, RespawnTicks = 120, SuccessRate = 0.4 },
        [635] = new() { LogId = 635, Name = "Yew tree", RequiredLevel = 60, Experience = 175, RespawnTicks = 180, SuccessRate = 0.25 },
        [636] = new() { LogId = 636, Name = "Magic tree", RequiredLevel = 75, Experience = 250, RespawnTicks = 300, SuccessRate = 0.1 }
    };
}

/// <summary>
/// Log item IDs mapping.
/// </summary>
public static class LogIds
{
    public const int Logs = 14;
    public const int OakLogs = 632;
    public const int WillowLogs = 633;
    public const int MapleLogs = 634;
    public const int YewLogs = 635;
    public const int MagicLogs = 636;
}

/// <summary>
/// Axe definitions.
/// </summary>
public sealed record AxeDefinition
{
    public required int ItemId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int WoodcuttingBonus { get; init; }

    public static readonly IReadOnlyList<AxeDefinition> All = new List<AxeDefinition>
    {
        new() { ItemId = 87, Name = "Bronze axe", RequiredLevel = 1, WoodcuttingBonus = 0 },
        new() { ItemId = 12, Name = "Iron axe", RequiredLevel = 1, WoodcuttingBonus = 1 },
        new() { ItemId = 88, Name = "Steel axe", RequiredLevel = 6, WoodcuttingBonus = 2 },
        new() { ItemId = 203, Name = "Black axe", RequiredLevel = 6, WoodcuttingBonus = 2 },
        new() { ItemId = 428, Name = "Mithril axe", RequiredLevel = 21, WoodcuttingBonus = 3 },
        new() { ItemId = 429, Name = "Adamant axe", RequiredLevel = 31, WoodcuttingBonus = 4 },
        new() { ItemId = 405, Name = "Rune axe", RequiredLevel = 41, WoodcuttingBonus = 5 }
    };

    /// <summary>
    /// Gets the best axe a player can use.
    /// </summary>
    public static AxeDefinition? GetBestUsable(Player player)
    {
        var wcLevel = player.Skills.GetCurrentLevel(Skill.Woodcutting);
        AxeDefinition? best = null;

        foreach (var axe in All.OrderByDescending(a => a.WoodcuttingBonus))
        {
            if (axe.RequiredLevel <= wcLevel &&
                (player.Inventory.HasItem(axe.ItemId) || player.Equipment.HasItem(axe.ItemId)))
            {
                best = axe;
                break;
            }
        }

        return best;
    }
}

/// <summary>
/// Tree object definition.
/// </summary>
public sealed record TreeObjectDefinition
{
    public required int FullObjectId { get; init; }
    public required int StumpObjectId { get; init; }
    public required int LogId { get; init; }
}

/// <summary>
/// Woodcutting action.
/// </summary>
public sealed class WoodcuttingAction : SkillAction
{
    private readonly TreeDefinition _tree;
    private readonly AxeDefinition _axe;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Woodcutting;

    public WoodcuttingAction(Player player, TreeDefinition tree, AxeDefinition axe, IItemFactory itemFactory)
        : base(player, CalculateTicks(player, axe))
    {
        _tree = tree;
        _axe = axe;
        _itemFactory = itemFactory;
    }

    private static int CalculateTicks(Player player, AxeDefinition axe)
    {
        // Base 4 ticks, reduced by level and axe
        var level = player.Skills.GetCurrentLevel(Skill.Woodcutting);
        return Math.Max(2, 5 - level / 25 - axe.WoodcuttingBonus);
    }

    protected override void OnComplete()
    {
        var level = Player.Skills.GetCurrentLevel(Skill.Woodcutting);
        var successChance = _tree.SuccessRate + (level - _tree.RequiredLevel) * 0.01 + _axe.WoodcuttingBonus * 0.05;

        if (Random.Shared.NextDouble() < successChance)
        {
            if (Player.Inventory.Add(_tree.LogId, 1, _itemFactory))
            {
                Player.Skills.AddExperience(Skill.Woodcutting, _tree.Experience);
                Player.Message($"You get some {GetLogName(_tree.LogId)}.");

                // Check for bird's nest (rare drop)
                if (Random.Shared.NextDouble() < 0.003)
                {
                    DropBirdsNest();
                }
            }
            else
            {
                Player.Message("Your inventory is full.");
                Cancel();
            }
        }
        else
        {
            Player.Message("You swing your axe at the tree.");
            TicksRemaining = CalculateTicks(Player, _axe);
        }
    }

    private string GetLogName(int logId) => logId switch
    {
        LogIds.Logs => "logs",
        LogIds.OakLogs => "oak logs",
        LogIds.WillowLogs => "willow logs",
        LogIds.MapleLogs => "maple logs",
        LogIds.YewLogs => "yew logs",
        LogIds.MagicLogs => "magic logs",
        _ => "logs"
    };

    private void DropBirdsNest()
    {
        const int birdsNestId = 1362; // Example ID
        Player.Message("A bird's nest falls out of the tree!");
        // Would drop to ground - handled by world system
    }

    protected override void OnTick()
    {
        if (TicksRemaining == 2)
        {
            Player.Message("You swing your axe at the tree.");
        }
    }
}

/// <summary>
/// Woodcutting skill manager.
/// </summary>
public static class WoodcuttingManager
{
    /// <summary>
    /// Attempts to chop a tree.
    /// </summary>
    public static SkillActionResult StartWoodcutting(Player player, int logId, IItemFactory itemFactory)
    {
        if (!TreeDefinition.All.TryGetValue(logId, out var tree))
        {
            return SkillActionResult.Fail("You cannot chop down this tree.");
        }

        var wcLevel = player.Skills.GetCurrentLevel(Skill.Woodcutting);
        if (wcLevel < tree.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {tree.RequiredLevel} Woodcutting to chop down this tree.");
        }

        var axe = AxeDefinition.GetBestUsable(player);
        if (axe is null)
        {
            return SkillActionResult.Fail("You need an axe to chop down trees.");
        }

        if (player.Inventory.IsFull)
        {
            return SkillActionResult.Fail("Your inventory is full.");
        }

        player.Message($"You begin chopping the tree with your {axe.Name.ToLower()}...");
        return SkillActionResult.Ok(new WoodcuttingAction(player, tree, axe, itemFactory));
    }
}
