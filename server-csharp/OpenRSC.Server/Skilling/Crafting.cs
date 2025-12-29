using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Crafting categories.
/// </summary>
public enum CraftingCategory
{
    Leather,
    Gem,
    Pottery,
    Spinning,
    Jewelry,
    Glass
}

/// <summary>
/// Leather crafting definition.
/// </summary>
public sealed record LeatherDefinition
{
    public required int ProductId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int LeatherRequired { get; init; }
    public int ThreadRequired { get; init; } = 1;

    public static readonly IReadOnlyList<LeatherDefinition> All = new List<LeatherDefinition>
    {
        new() { ProductId = 16, Name = "Leather gloves", RequiredLevel = 1, Experience = 13, LeatherRequired = 1 },
        new() { ProductId = 17, Name = "Leather boots", RequiredLevel = 7, Experience = 16, LeatherRequired = 1 },
        new() { ProductId = 15, Name = "Leather armour", RequiredLevel = 14, Experience = 25, LeatherRequired = 1 },
        new() { ProductId = 191, Name = "Hardleather body", RequiredLevel = 28, Experience = 35, LeatherRequired = 1 },
        // Dragonhide
        new() { ProductId = 796, Name = "Green d'hide vambs", RequiredLevel = 57, Experience = 62, LeatherRequired = 1 },
        new() { ProductId = 797, Name = "Green d'hide chaps", RequiredLevel = 60, Experience = 124, LeatherRequired = 2 },
        new() { ProductId = 798, Name = "Green d'hide body", RequiredLevel = 63, Experience = 186, LeatherRequired = 3 }
    };
}

/// <summary>
/// Gem cutting definition.
/// </summary>
public sealed record GemDefinition
{
    public required int UncutId { get; init; }
    public required int CutId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }

    public static readonly IReadOnlyDictionary<int, GemDefinition> All = new Dictionary<int, GemDefinition>
    {
        [160] = new() { UncutId = 160, CutId = 164, Name = "Opal", RequiredLevel = 1, Experience = 15 },
        [159] = new() { UncutId = 159, CutId = 163, Name = "Jade", RequiredLevel = 13, Experience = 20 },
        [158] = new() { UncutId = 158, CutId = 162, Name = "Red topaz", RequiredLevel = 16, Experience = 25 },
        [157] = new() { UncutId = 157, CutId = 161, Name = "Sapphire", RequiredLevel = 20, Experience = 50 },
        [156] = new() { UncutId = 156, CutId = 165, Name = "Emerald", RequiredLevel = 27, Experience = 67 },
        [155] = new() { UncutId = 155, CutId = 166, Name = "Ruby", RequiredLevel = 63, Experience = 85 },
        [154] = new() { UncutId = 154, CutId = 167, Name = "Diamond", RequiredLevel = 43, Experience = 107 },
        [153] = new() { UncutId = 153, CutId = 168, Name = "Dragonstone", RequiredLevel = 55, Experience = 137 }
    };
}

/// <summary>
/// Jewelry crafting definition.
/// </summary>
public sealed record JewelryDefinition
{
    public required int ProductId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int GoldBarRequired { get; init; }
    public int GemRequired { get; init; } = 0;
    public int MouldRequired { get; init; }

    public static readonly IReadOnlyList<JewelryDefinition> Rings = new List<JewelryDefinition>
    {
        new() { ProductId = 283, Name = "Gold ring", RequiredLevel = 5, Experience = 15, GoldBarRequired = 1, MouldRequired = 293 },
        new() { ProductId = 284, Name = "Sapphire ring", RequiredLevel = 20, Experience = 40, GoldBarRequired = 1, GemRequired = 161, MouldRequired = 293 },
        new() { ProductId = 285, Name = "Emerald ring", RequiredLevel = 27, Experience = 55, GoldBarRequired = 1, GemRequired = 165, MouldRequired = 293 },
        new() { ProductId = 286, Name = "Ruby ring", RequiredLevel = 34, Experience = 70, GoldBarRequired = 1, GemRequired = 166, MouldRequired = 293 },
        new() { ProductId = 287, Name = "Diamond ring", RequiredLevel = 43, Experience = 85, GoldBarRequired = 1, GemRequired = 167, MouldRequired = 293 },
        new() { ProductId = 288, Name = "Dragonstone ring", RequiredLevel = 55, Experience = 100, GoldBarRequired = 1, GemRequired = 168, MouldRequired = 293 }
    };

    public static readonly IReadOnlyList<JewelryDefinition> Necklaces = new List<JewelryDefinition>
    {
        new() { ProductId = 50, Name = "Gold necklace", RequiredLevel = 6, Experience = 20, GoldBarRequired = 1, MouldRequired = 294 },
        new() { ProductId = 51, Name = "Sapphire necklace", RequiredLevel = 22, Experience = 55, GoldBarRequired = 1, GemRequired = 161, MouldRequired = 294 },
        new() { ProductId = 52, Name = "Emerald necklace", RequiredLevel = 29, Experience = 60, GoldBarRequired = 1, GemRequired = 165, MouldRequired = 294 },
        new() { ProductId = 53, Name = "Ruby necklace", RequiredLevel = 40, Experience = 75, GoldBarRequired = 1, GemRequired = 166, MouldRequired = 294 },
        new() { ProductId = 54, Name = "Diamond necklace", RequiredLevel = 56, Experience = 90, GoldBarRequired = 1, GemRequired = 167, MouldRequired = 294 },
        new() { ProductId = 55, Name = "Dragonstone necklace", RequiredLevel = 72, Experience = 105, GoldBarRequired = 1, GemRequired = 168, MouldRequired = 294 }
    };

    public static readonly IReadOnlyList<JewelryDefinition> Amulets = new List<JewelryDefinition>
    {
        new() { ProductId = 302, Name = "Gold amulet (u)", RequiredLevel = 8, Experience = 30, GoldBarRequired = 1, MouldRequired = 295 },
        new() { ProductId = 303, Name = "Sapphire amulet (u)", RequiredLevel = 24, Experience = 65, GoldBarRequired = 1, GemRequired = 161, MouldRequired = 295 },
        new() { ProductId = 304, Name = "Emerald amulet (u)", RequiredLevel = 31, Experience = 70, GoldBarRequired = 1, GemRequired = 165, MouldRequired = 295 },
        new() { ProductId = 305, Name = "Ruby amulet (u)", RequiredLevel = 50, Experience = 85, GoldBarRequired = 1, GemRequired = 166, MouldRequired = 295 },
        new() { ProductId = 306, Name = "Diamond amulet (u)", RequiredLevel = 70, Experience = 100, GoldBarRequired = 1, GemRequired = 167, MouldRequired = 295 },
        new() { ProductId = 307, Name = "Dragonstone amulet (u)", RequiredLevel = 80, Experience = 150, GoldBarRequired = 1, GemRequired = 168, MouldRequired = 295 }
    };
}

/// <summary>
/// Spinning definition.
/// </summary>
public sealed record SpinningDefinition
{
    public required int InputId { get; init; }
    public required int OutputId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }

    public static readonly IReadOnlyDictionary<int, SpinningDefinition> All = new Dictionary<int, SpinningDefinition>
    {
        [145] = new() { InputId = 145, OutputId = 207, Name = "Wool", RequiredLevel = 1, Experience = 2 }, // Wool -> Ball of wool
        [675] = new() { InputId = 675, OutputId = 676, Name = "Flax", RequiredLevel = 10, Experience = 15 } // Flax -> Bowstring
    };
}

/// <summary>
/// Crafting items.
/// </summary>
public static class CraftingItems
{
    public const int Chisel = 167;
    public const int Needle = 39;
    public const int Thread = 43;
    public const int Leather = 148;
    public const int HardLeather = 149;
    public const int GreenDragonhide = 1065;
    public const int GoldBar = 172;
    public const int RingMould = 293;
    public const int NecklaceMould = 294;
    public const int AmuletMould = 295;
}

/// <summary>
/// Gem cutting action.
/// </summary>
public sealed class GemCuttingAction : SkillAction
{
    private readonly GemDefinition _gem;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Crafting;

    public GemCuttingAction(Player player, GemDefinition gem, IItemFactory itemFactory)
        : base(player, 3) // 3 ticks to cut
    {
        _gem = gem;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        // Remove uncut gem
        if (Player.Inventory.Remove(_gem.UncutId, 1))
        {
            // Add cut gem
            if (Player.Inventory.Add(_gem.CutId, 1, _itemFactory))
            {
                Player.Skills.AddExperience(Skill.Crafting, _gem.Experience);
                Player.Message($"You cut the {_gem.Name.ToLower()}.");
            }
        }
    }
}

/// <summary>
/// Leather crafting action.
/// </summary>
public sealed class LeatherCraftingAction : SkillAction
{
    private readonly LeatherDefinition _item;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Crafting;

    public LeatherCraftingAction(Player player, LeatherDefinition item, IItemFactory itemFactory)
        : base(player, 4)
    {
        _item = item;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        // Check and remove materials
        if (!Player.Inventory.HasItem(CraftingItems.Leather, _item.LeatherRequired))
        {
            Player.Message("You don't have enough leather.");
            Cancel();
            return;
        }

        if (_item.ThreadRequired > 0 && !Player.Inventory.HasItem(CraftingItems.Thread))
        {
            Player.Message("You need a needle and thread.");
            Cancel();
            return;
        }

        Player.Inventory.Remove(CraftingItems.Leather, _item.LeatherRequired);

        if (Player.Inventory.Add(_item.ProductId, 1, _itemFactory))
        {
            Player.Skills.AddExperience(Skill.Crafting, _item.Experience);
            Player.Message($"You make {_item.Name.ToLower()}.");
        }
    }
}

/// <summary>
/// Spinning action.
/// </summary>
public sealed class SpinningAction : SkillAction
{
    private readonly SpinningDefinition _item;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Crafting;

    public SpinningAction(Player player, SpinningDefinition item, IItemFactory itemFactory)
        : base(player, 3)
    {
        _item = item;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        if (Player.Inventory.Remove(_item.InputId, 1))
        {
            if (Player.Inventory.Add(_item.OutputId, 1, _itemFactory))
            {
                Player.Skills.AddExperience(Skill.Crafting, _item.Experience);
                Player.Message($"You spin the {_item.Name.ToLower()}.");
            }
        }
    }
}

/// <summary>
/// Crafting skill manager.
/// </summary>
public static class CraftingManager
{
    /// <summary>
    /// Attempts to cut a gem.
    /// </summary>
    public static SkillActionResult CutGem(Player player, int uncutGemId, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(CraftingItems.Chisel))
        {
            return SkillActionResult.Fail("You need a chisel to cut gems.");
        }

        if (!player.Inventory.HasItem(uncutGemId))
        {
            return SkillActionResult.Fail("You don't have that gem.");
        }

        if (!GemDefinition.All.TryGetValue(uncutGemId, out var gem))
        {
            return SkillActionResult.Fail("You cannot cut this.");
        }

        var level = player.Skills.GetCurrentLevel(Skill.Crafting);
        if (level < gem.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {gem.RequiredLevel} Crafting to cut {gem.Name.ToLower()}s.");
        }

        player.Message($"You begin cutting the {gem.Name.ToLower()}...");
        return SkillActionResult.Ok(new GemCuttingAction(player, gem, itemFactory));
    }

    /// <summary>
    /// Attempts to craft leather item.
    /// </summary>
    public static SkillActionResult CraftLeather(Player player, int productId, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(CraftingItems.Needle))
        {
            return SkillActionResult.Fail("You need a needle to work leather.");
        }

        var item = LeatherDefinition.All.FirstOrDefault(l => l.ProductId == productId);
        if (item is null)
        {
            return SkillActionResult.Fail("You cannot craft that.");
        }

        var level = player.Skills.GetCurrentLevel(Skill.Crafting);
        if (level < item.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {item.RequiredLevel} Crafting to make {item.Name.ToLower()}.");
        }

        if (!player.Inventory.HasItem(CraftingItems.Leather, item.LeatherRequired))
        {
            return SkillActionResult.Fail("You don't have enough leather.");
        }

        player.Message($"You begin crafting {item.Name.ToLower()}...");
        return SkillActionResult.Ok(new LeatherCraftingAction(player, item, itemFactory));
    }

    /// <summary>
    /// Attempts to spin materials.
    /// </summary>
    public static SkillActionResult Spin(Player player, int inputId, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(inputId))
        {
            return SkillActionResult.Fail("You don't have anything to spin.");
        }

        if (!SpinningDefinition.All.TryGetValue(inputId, out var item))
        {
            return SkillActionResult.Fail("You cannot spin this.");
        }

        var level = player.Skills.GetCurrentLevel(Skill.Crafting);
        if (level < item.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {item.RequiredLevel} Crafting to spin {item.Name.ToLower()}.");
        }

        player.Message($"You begin spinning the {item.Name.ToLower()}...");
        return SkillActionResult.Ok(new SpinningAction(player, item, itemFactory));
    }
}
