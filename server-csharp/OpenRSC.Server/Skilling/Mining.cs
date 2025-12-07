using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Ore definition for mining.
/// </summary>
public sealed record OreDefinition
{
    public required int OreId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int RespawnTicks { get; init; }
    public double SuccessRate { get; init; } = 0.5;

    public static readonly IReadOnlyDictionary<int, OreDefinition> All = new Dictionary<int, OreDefinition>
    {
        [150] = new() { OreId = 150, Name = "Clay", RequiredLevel = 1, Experience = 5, RespawnTicks = 2, SuccessRate = 0.9 },
        [202] = new() { OreId = 202, Name = "Copper ore", RequiredLevel = 1, Experience = 17, RespawnTicks = 4, SuccessRate = 0.8 },
        [203] = new() { OreId = 203, Name = "Tin ore", RequiredLevel = 1, Experience = 17, RespawnTicks = 4, SuccessRate = 0.8 },
        [151] = new() { OreId = 151, Name = "Iron ore", RequiredLevel = 15, Experience = 35, RespawnTicks = 9, SuccessRate = 0.6 },
        [155] = new() { OreId = 155, Name = "Silver ore", RequiredLevel = 20, Experience = 40, RespawnTicks = 100, SuccessRate = 0.5 },
        [153] = new() { OreId = 153, Name = "Coal", RequiredLevel = 30, Experience = 50, RespawnTicks = 50, SuccessRate = 0.45 },
        [154] = new() { OreId = 154, Name = "Gold ore", RequiredLevel = 40, Experience = 65, RespawnTicks = 100, SuccessRate = 0.4 },
        [152] = new() { OreId = 152, Name = "Mithril ore", RequiredLevel = 55, Experience = 80, RespawnTicks = 200, SuccessRate = 0.3 },
        [150] = new() { OreId = 409, Name = "Adamantite ore", RequiredLevel = 70, Experience = 95, RespawnTicks = 400, SuccessRate = 0.2 },
        [409] = new() { OreId = 409, Name = "Adamantite ore", RequiredLevel = 70, Experience = 95, RespawnTicks = 400, SuccessRate = 0.2 },
        [410] = new() { OreId = 410, Name = "Runite ore", RequiredLevel = 85, Experience = 125, RespawnTicks = 1200, SuccessRate = 0.1 }
    };
}

/// <summary>
/// Pickaxe definitions.
/// </summary>
public sealed record PickaxeDefinition
{
    public required int ItemId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int MiningBonus { get; init; }

    public static readonly IReadOnlyList<PickaxeDefinition> All = new List<PickaxeDefinition>
    {
        new() { ItemId = 156, Name = "Bronze pickaxe", RequiredLevel = 1, MiningBonus = 0 },
        new() { ItemId = 1258, Name = "Iron pickaxe", RequiredLevel = 1, MiningBonus = 1 },
        new() { ItemId = 1259, Name = "Steel pickaxe", RequiredLevel = 6, MiningBonus = 2 },
        new() { ItemId = 1260, Name = "Mithril pickaxe", RequiredLevel = 21, MiningBonus = 3 },
        new() { ItemId = 1261, Name = "Adamant pickaxe", RequiredLevel = 31, MiningBonus = 4 },
        new() { ItemId = 1262, Name = "Rune pickaxe", RequiredLevel = 41, MiningBonus = 5 }
    };

    /// <summary>
    /// Gets the best pickaxe a player can use.
    /// </summary>
    public static PickaxeDefinition? GetBestUsable(Player player)
    {
        var miningLevel = player.Skills.GetCurrentLevel(Skill.Mining);
        PickaxeDefinition? best = null;

        foreach (var pick in All.OrderByDescending(p => p.MiningBonus))
        {
            if (pick.RequiredLevel <= miningLevel &&
                player.Inventory.HasItem(pick.ItemId))
            {
                best = pick;
                break;
            }
        }

        return best;
    }
}

/// <summary>
/// Rock definition (world object with ore).
/// </summary>
public sealed record RockDefinition
{
    public required int FullObjectId { get; init; }
    public required int EmptyObjectId { get; init; }
    public required int OreId { get; init; }
}

/// <summary>
/// Mining action.
/// </summary>
public sealed class MiningAction : SkillAction
{
    private readonly OreDefinition _ore;
    private readonly PickaxeDefinition _pickaxe;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Mining;

    public MiningAction(Player player, OreDefinition ore, PickaxeDefinition pickaxe, IItemFactory itemFactory)
        : base(player, CalculateTicks(player, pickaxe))
    {
        _ore = ore;
        _pickaxe = pickaxe;
        _itemFactory = itemFactory;
    }

    private static int CalculateTicks(Player player, PickaxeDefinition pickaxe)
    {
        // Base 5 ticks, reduced by level and pickaxe
        var level = player.Skills.GetCurrentLevel(Skill.Mining);
        return Math.Max(2, 6 - level / 20 - pickaxe.MiningBonus);
    }

    protected override void OnComplete()
    {
        // Calculate success chance
        var level = Player.Skills.GetCurrentLevel(Skill.Mining);
        var successChance = _ore.SuccessRate + (level - _ore.RequiredLevel) * 0.01 + _pickaxe.MiningBonus * 0.05;

        if (Random.Shared.NextDouble() < successChance)
        {
            // Success!
            if (Player.Inventory.Add(_ore.OreId, 1, _itemFactory))
            {
                Player.Skills.AddExperience(Skill.Mining, _ore.Experience);
                Player.Message($"You mine some {_ore.Name.ToLower()}.");

                // Deplete the rock (handled externally)
            }
            else
            {
                Player.Message("Your inventory is full.");
                Cancel();
            }
        }
        else
        {
            Player.Message("You swing your pickaxe at the rock.");
            // Continue mining
            TicksRemaining = CalculateTicks(Player, _pickaxe);
        }
    }

    protected override void OnTick()
    {
        // Periodically show mining message
        if (TicksRemaining == 2)
        {
            Player.Message("You swing your pickaxe at the rock.");
        }
    }
}

/// <summary>
/// Mining skill manager.
/// </summary>
public static class MiningManager
{
    /// <summary>
    /// Attempts to mine a rock.
    /// </summary>
    public static SkillActionResult StartMining(Player player, int oreId, IItemFactory itemFactory)
    {
        if (!OreDefinition.All.TryGetValue(oreId, out var ore))
        {
            return SkillActionResult.Fail("This rock contains no ore.");
        }

        // Check level
        var miningLevel = player.Skills.GetCurrentLevel(Skill.Mining);
        if (miningLevel < ore.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {ore.RequiredLevel} Mining to mine {ore.Name.ToLower()}.");
        }

        // Check for pickaxe
        var pickaxe = PickaxeDefinition.GetBestUsable(player);
        if (pickaxe is null)
        {
            return SkillActionResult.Fail("You need a pickaxe to mine.");
        }

        // Check inventory space
        if (player.Inventory.IsFull)
        {
            return SkillActionResult.Fail("Your inventory is full.");
        }

        player.Message($"You begin mining the rock with your {pickaxe.Name.ToLower()}...");
        return SkillActionResult.Ok(new MiningAction(player, ore, pickaxe, itemFactory));
    }
}
