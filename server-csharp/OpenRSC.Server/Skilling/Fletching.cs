using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Arrow definition.
/// </summary>
public sealed record ArrowDefinition
{
    public required int ArrowId { get; init; }
    public required string Name { get; init; }
    public required int ShaftId { get; init; }
    public required int TipId { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }

    public static readonly IReadOnlyList<ArrowDefinition> All = new List<ArrowDefinition>
    {
        new() { ArrowId = 11, ShaftId = 280, TipId = 39, Name = "Bronze arrows", RequiredLevel = 1, Experience = 1 },
        new() { ArrowId = 638, ShaftId = 280, TipId = 40, Name = "Iron arrows", RequiredLevel = 15, Experience = 2 },
        new() { ArrowId = 639, ShaftId = 280, TipId = 41, Name = "Steel arrows", RequiredLevel = 30, Experience = 5 },
        new() { ArrowId = 640, ShaftId = 280, TipId = 42, Name = "Mithril arrows", RequiredLevel = 45, Experience = 7 },
        new() { ArrowId = 641, ShaftId = 280, TipId = 43, Name = "Adamant arrows", RequiredLevel = 60, Experience = 10 },
        new() { ArrowId = 642, ShaftId = 280, TipId = 44, Name = "Rune arrows", RequiredLevel = 75, Experience = 12 }
    };
}

/// <summary>
/// Bow definition.
/// </summary>
public sealed record BowDefinition
{
    public required int UnstrungId { get; init; }
    public required int StrungId { get; init; }
    public required string Name { get; init; }
    public required int LogId { get; init; }
    public required int RequiredLevel { get; init; }
    public required int CuttingExperience { get; init; }
    public required int StringingExperience { get; init; }
    public bool IsLongbow { get; init; }

    public static readonly IReadOnlyList<BowDefinition> All = new List<BowDefinition>
    {
        // Shortbows
        new() { UnstrungId = 277, StrungId = 189, Name = "Shortbow", LogId = 14, RequiredLevel = 5, CuttingExperience = 5, StringingExperience = 5, IsLongbow = false },
        new() { UnstrungId = 658, StrungId = 649, Name = "Oak shortbow", LogId = 632, RequiredLevel = 20, CuttingExperience = 16, StringingExperience = 16, IsLongbow = false },
        new() { UnstrungId = 659, StrungId = 650, Name = "Willow shortbow", LogId = 633, RequiredLevel = 35, CuttingExperience = 33, StringingExperience = 33, IsLongbow = false },
        new() { UnstrungId = 660, StrungId = 651, Name = "Maple shortbow", LogId = 634, RequiredLevel = 50, CuttingExperience = 50, StringingExperience = 50, IsLongbow = false },
        new() { UnstrungId = 661, StrungId = 652, Name = "Yew shortbow", LogId = 635, RequiredLevel = 65, CuttingExperience = 67, StringingExperience = 67, IsLongbow = false },
        new() { UnstrungId = 662, StrungId = 653, Name = "Magic shortbow", LogId = 636, RequiredLevel = 80, CuttingExperience = 83, StringingExperience = 83, IsLongbow = false },
        // Longbows
        new() { UnstrungId = 278, StrungId = 188, Name = "Longbow", LogId = 14, RequiredLevel = 10, CuttingExperience = 10, StringingExperience = 10, IsLongbow = true },
        new() { UnstrungId = 663, StrungId = 654, Name = "Oak longbow", LogId = 632, RequiredLevel = 25, CuttingExperience = 25, StringingExperience = 25, IsLongbow = true },
        new() { UnstrungId = 664, StrungId = 655, Name = "Willow longbow", LogId = 633, RequiredLevel = 40, CuttingExperience = 41, StringingExperience = 41, IsLongbow = true },
        new() { UnstrungId = 665, StrungId = 656, Name = "Maple longbow", LogId = 634, RequiredLevel = 55, CuttingExperience = 58, StringingExperience = 58, IsLongbow = true },
        new() { UnstrungId = 666, StrungId = 657, Name = "Yew longbow", LogId = 635, RequiredLevel = 70, CuttingExperience = 75, StringingExperience = 75, IsLongbow = true },
        new() { UnstrungId = 667, StrungId = 658, Name = "Magic longbow", LogId = 636, RequiredLevel = 85, CuttingExperience = 91, StringingExperience = 91, IsLongbow = true }
    };
}

/// <summary>
/// Crossbow bolt definition.
/// </summary>
public sealed record BoltDefinition
{
    public required int BoltId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }

    public static readonly IReadOnlyList<BoltDefinition> All = new List<BoltDefinition>
    {
        new() { BoltId = 786, Name = "Bronze bolts", RequiredLevel = 9, Experience = 0 },
        new() { BoltId = 787, Name = "Iron bolts", RequiredLevel = 39, Experience = 0 },
        new() { BoltId = 788, Name = "Steel bolts", RequiredLevel = 46, Experience = 0 },
        new() { BoltId = 789, Name = "Mithril bolts", RequiredLevel = 54, Experience = 0 },
        new() { BoltId = 790, Name = "Adamant bolts", RequiredLevel = 61, Experience = 0 },
        new() { BoltId = 791, Name = "Rune bolts", RequiredLevel = 69, Experience = 0 }
    };
}

/// <summary>
/// Fletching items.
/// </summary>
public static class FletchingItems
{
    public const int Knife = 13;
    public const int Feather = 381;
    public const int Bowstring = 676;
    public const int ArrowShaft = 280;
}

/// <summary>
/// Arrow shaft cutting action.
/// </summary>
public sealed class CutArrowShaftsAction : SkillAction
{
    private readonly int _logId;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Fletching;

    public CutArrowShaftsAction(Player player, int logId, IItemFactory itemFactory)
        : base(player, 3)
    {
        _logId = logId;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        if (Player.Inventory.Remove(_logId, 1))
        {
            // Logs give 15 arrow shafts
            Player.Inventory.Add(FletchingItems.ArrowShaft, 15, _itemFactory);
            Player.Skills.AddExperience(Skill.Fletching, 5);
            Player.Message("You carefully cut the wood into arrow shafts.");
        }
    }
}

/// <summary>
/// Feathering arrows action.
/// </summary>
public sealed class FeatherArrowsAction : SkillAction
{
    private readonly IItemFactory _itemFactory;
    private readonly int _amount;

    public override Skill Skill => Skill.Fletching;

    public FeatherArrowsAction(Player player, IItemFactory itemFactory, int amount)
        : base(player, 2)
    {
        _itemFactory = itemFactory;
        _amount = amount;
    }

    protected override void OnComplete()
    {
        var shafts = Player.Inventory.CountOf(FletchingItems.ArrowShaft);
        var feathers = Player.Inventory.CountOf(FletchingItems.Feather);
        var toMake = Math.Min(Math.Min(shafts, feathers), _amount);

        if (toMake > 0)
        {
            Player.Inventory.Remove(FletchingItems.ArrowShaft, toMake);
            Player.Inventory.Remove(FletchingItems.Feather, toMake);

            const int headlessArrowId = 279;
            Player.Inventory.Add(headlessArrowId, toMake, _itemFactory);
            Player.Skills.AddExperience(Skill.Fletching, toMake);
            Player.Message($"You attach feathers to {toMake} arrow shafts.");
        }
    }
}

/// <summary>
/// Attaching arrowheads action.
/// </summary>
public sealed class AttachArrowheadsAction : SkillAction
{
    private readonly ArrowDefinition _arrow;
    private readonly IItemFactory _itemFactory;
    private readonly int _amount;

    public override Skill Skill => Skill.Fletching;

    public AttachArrowheadsAction(Player player, ArrowDefinition arrow, IItemFactory itemFactory, int amount)
        : base(player, 2)
    {
        _arrow = arrow;
        _itemFactory = itemFactory;
        _amount = amount;
    }

    protected override void OnComplete()
    {
        const int headlessArrowId = 279;
        var headless = Player.Inventory.CountOf(headlessArrowId);
        var tips = Player.Inventory.CountOf(_arrow.TipId);
        var toMake = Math.Min(Math.Min(headless, tips), _amount);

        if (toMake > 0)
        {
            Player.Inventory.Remove(headlessArrowId, toMake);
            Player.Inventory.Remove(_arrow.TipId, toMake);
            Player.Inventory.Add(_arrow.ArrowId, toMake, _itemFactory);
            Player.Skills.AddExperience(Skill.Fletching, toMake * _arrow.Experience);
            Player.Message($"You attach the arrowheads to make {toMake} {_arrow.Name.ToLower()}.");
        }
    }
}

/// <summary>
/// Bow cutting action.
/// </summary>
public sealed class CutBowAction : SkillAction
{
    private readonly BowDefinition _bow;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Fletching;

    public CutBowAction(Player player, BowDefinition bow, IItemFactory itemFactory)
        : base(player, 3)
    {
        _bow = bow;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        if (Player.Inventory.Remove(_bow.LogId, 1))
        {
            Player.Inventory.Add(_bow.UnstrungId, 1, _itemFactory);
            Player.Skills.AddExperience(Skill.Fletching, _bow.CuttingExperience);
            Player.Message($"You carefully cut the wood into an unstrung {_bow.Name.ToLower()}.");
        }
    }
}

/// <summary>
/// Bow stringing action.
/// </summary>
public sealed class StringBowAction : SkillAction
{
    private readonly BowDefinition _bow;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Fletching;

    public StringBowAction(Player player, BowDefinition bow, IItemFactory itemFactory)
        : base(player, 2)
    {
        _bow = bow;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        if (Player.Inventory.Remove(_bow.UnstrungId, 1) &&
            Player.Inventory.Remove(FletchingItems.Bowstring, 1))
        {
            Player.Inventory.Add(_bow.StrungId, 1, _itemFactory);
            Player.Skills.AddExperience(Skill.Fletching, _bow.StringingExperience);
            Player.Message($"You string the bow.");
        }
    }
}

/// <summary>
/// Fletching skill manager.
/// </summary>
public static class FletchingManager
{
    /// <summary>
    /// Cuts arrow shafts from logs.
    /// </summary>
    public static SkillActionResult CutArrowShafts(Player player, int logId, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(FletchingItems.Knife))
            return SkillActionResult.Fail("You need a knife to cut logs.");

        if (!player.Inventory.HasItem(logId))
            return SkillActionResult.Fail("You don't have any logs.");

        player.Message("You begin cutting the logs...");
        return SkillActionResult.Ok(new CutArrowShaftsAction(player, logId, itemFactory));
    }

    /// <summary>
    /// Feathers arrow shafts.
    /// </summary>
    public static SkillActionResult FeatherArrows(Player player, IItemFactory itemFactory, int amount = 10)
    {
        if (!player.Inventory.HasItem(FletchingItems.ArrowShaft))
            return SkillActionResult.Fail("You don't have any arrow shafts.");

        if (!player.Inventory.HasItem(FletchingItems.Feather))
            return SkillActionResult.Fail("You don't have any feathers.");

        player.Message("You begin attaching feathers...");
        return SkillActionResult.Ok(new FeatherArrowsAction(player, itemFactory, amount));
    }

    /// <summary>
    /// Attaches arrowheads to headless arrows.
    /// </summary>
    public static SkillActionResult AttachArrowheads(Player player, int tipId, IItemFactory itemFactory, int amount = 10)
    {
        var arrow = ArrowDefinition.All.FirstOrDefault(a => a.TipId == tipId);
        if (arrow is null)
            return SkillActionResult.Fail("Those are not arrowheads.");

        var level = player.Skills.GetCurrentLevel(Skill.Fletching);
        if (level < arrow.RequiredLevel)
            return SkillActionResult.Fail($"You need level {arrow.RequiredLevel} Fletching to make {arrow.Name.ToLower()}.");

        const int headlessArrowId = 279;
        if (!player.Inventory.HasItem(headlessArrowId))
            return SkillActionResult.Fail("You don't have any headless arrows.");

        if (!player.Inventory.HasItem(tipId))
            return SkillActionResult.Fail("You don't have any arrowheads.");

        player.Message("You begin attaching the arrowheads...");
        return SkillActionResult.Ok(new AttachArrowheadsAction(player, arrow, itemFactory, amount));
    }

    /// <summary>
    /// Cuts an unstrung bow from logs.
    /// </summary>
    public static SkillActionResult CutBow(Player player, int logId, bool longbow, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(FletchingItems.Knife))
            return SkillActionResult.Fail("You need a knife to cut bows.");

        if (!player.Inventory.HasItem(logId))
            return SkillActionResult.Fail("You don't have any logs.");

        var bow = BowDefinition.All.FirstOrDefault(b => b.LogId == logId && b.IsLongbow == longbow);
        if (bow is null)
            return SkillActionResult.Fail("You can't make that bow from these logs.");

        var level = player.Skills.GetCurrentLevel(Skill.Fletching);
        if (level < bow.RequiredLevel)
            return SkillActionResult.Fail($"You need level {bow.RequiredLevel} Fletching to make a {bow.Name.ToLower()}.");

        player.Message("You begin cutting the bow...");
        return SkillActionResult.Ok(new CutBowAction(player, bow, itemFactory));
    }

    /// <summary>
    /// Strings a bow.
    /// </summary>
    public static SkillActionResult StringBow(Player player, int unstrungId, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(FletchingItems.Bowstring))
            return SkillActionResult.Fail("You need a bowstring.");

        if (!player.Inventory.HasItem(unstrungId))
            return SkillActionResult.Fail("You don't have that bow.");

        var bow = BowDefinition.All.FirstOrDefault(b => b.UnstrungId == unstrungId);
        if (bow is null)
            return SkillActionResult.Fail("This is not a bow.");

        var level = player.Skills.GetCurrentLevel(Skill.Fletching);
        if (level < bow.RequiredLevel)
            return SkillActionResult.Fail($"You need level {bow.RequiredLevel} Fletching to string this bow.");

        player.Message("You begin stringing the bow...");
        return SkillActionResult.Ok(new StringBowAction(player, bow, itemFactory));
    }
}
