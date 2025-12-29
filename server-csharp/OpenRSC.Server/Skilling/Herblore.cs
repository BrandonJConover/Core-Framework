using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Herb definition.
/// </summary>
public sealed record HerbDefinition
{
    public required int GrimyId { get; init; }
    public required int CleanId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int CleanExperience { get; init; }

    public static readonly IReadOnlyDictionary<int, HerbDefinition> All = new Dictionary<int, HerbDefinition>
    {
        [165] = new() { GrimyId = 165, CleanId = 444, Name = "Guam", RequiredLevel = 3, CleanExperience = 2 },
        [435] = new() { GrimyId = 435, CleanId = 445, Name = "Marrentill", RequiredLevel = 5, CleanExperience = 3 },
        [436] = new() { GrimyId = 436, CleanId = 446, Name = "Tarromin", RequiredLevel = 11, CleanExperience = 5 },
        [437] = new() { GrimyId = 437, CleanId = 447, Name = "Harralander", RequiredLevel = 20, CleanExperience = 6 },
        [438] = new() { GrimyId = 438, CleanId = 448, Name = "Ranarr", RequiredLevel = 25, CleanExperience = 7 },
        [439] = new() { GrimyId = 439, CleanId = 449, Name = "Irit", RequiredLevel = 40, CleanExperience = 8 },
        [440] = new() { GrimyId = 440, CleanId = 450, Name = "Avantoe", RequiredLevel = 48, CleanExperience = 10 },
        [441] = new() { GrimyId = 441, CleanId = 451, Name = "Kwuarm", RequiredLevel = 54, CleanExperience = 11 },
        [442] = new() { GrimyId = 442, CleanId = 452, Name = "Cadantine", RequiredLevel = 65, CleanExperience = 12 },
        [443] = new() { GrimyId = 443, CleanId = 453, Name = "Dwarf weed", RequiredLevel = 70, CleanExperience = 13 },
        [468] = new() { GrimyId = 468, CleanId = 469, Name = "Torstol", RequiredLevel = 75, CleanExperience = 15 }
    };
}

/// <summary>
/// Potion definition.
/// </summary>
public sealed record PotionDefinition
{
    public required int UnfinishedId { get; init; }
    public required int FinishedId { get; init; }
    public required string Name { get; init; }
    public required int HerbId { get; init; }
    public required int SecondaryId { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }

    public static readonly IReadOnlyList<PotionDefinition> All = new List<PotionDefinition>
    {
        // Attack potions
        new() { UnfinishedId = 454, FinishedId = 474, Name = "Attack potion", HerbId = 444, SecondaryId = 270, RequiredLevel = 3, Experience = 25 },
        // Strength potions
        new() { UnfinishedId = 455, FinishedId = 475, Name = "Strength potion", HerbId = 445, SecondaryId = 220, RequiredLevel = 12, Experience = 50 },
        // Defence potions
        new() { UnfinishedId = 456, FinishedId = 476, Name = "Defence potion", HerbId = 448, SecondaryId = 239, RequiredLevel = 30, Experience = 75 },
        // Prayer potions
        new() { UnfinishedId = 457, FinishedId = 483, Name = "Prayer potion", HerbId = 448, SecondaryId = 469, RequiredLevel = 38, Experience = 87 },
        // Super attack
        new() { UnfinishedId = 458, FinishedId = 486, Name = "Super attack", HerbId = 449, SecondaryId = 270, RequiredLevel = 45, Experience = 100 },
        // Super strength
        new() { UnfinishedId = 459, FinishedId = 487, Name = "Super strength", HerbId = 451, SecondaryId = 220, RequiredLevel = 55, Experience = 125 },
        // Super defence
        new() { UnfinishedId = 460, FinishedId = 488, Name = "Super defence", HerbId = 452, SecondaryId = 239, RequiredLevel = 66, Experience = 150 },
        // Ranging potion
        new() { UnfinishedId = 461, FinishedId = 498, Name = "Ranging potion", HerbId = 453, SecondaryId = 501, RequiredLevel = 72, Experience = 162 }
    };
}

/// <summary>
/// Herblore items.
/// </summary>
public static class HerbloreItems
{
    public const int Vial = 464;
    public const int VialOfWater = 465;
    public const int Pestle = 466;
    public const int EyeOfNewt = 270;
    public const int LimpwurtRoot = 220;
    public const int WhiteBerries = 239;
    public const int SnapeGrass = 469;
    public const int WineBerries = 501;
}

/// <summary>
/// Herb cleaning action.
/// </summary>
public sealed class HerbCleaningAction : SkillAction
{
    private readonly HerbDefinition _herb;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Herblaw;

    public HerbCleaningAction(Player player, HerbDefinition herb, IItemFactory itemFactory)
        : base(player, 2)
    {
        _herb = herb;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        if (Player.Inventory.Remove(_herb.GrimyId, 1))
        {
            if (Player.Inventory.Add(_herb.CleanId, 1, _itemFactory))
            {
                Player.Skills.AddExperience(Skill.Herblaw, _herb.CleanExperience);
                Player.Message($"You clean the {_herb.Name.ToLower()}.");
            }
        }
    }
}

/// <summary>
/// Unfinished potion making action.
/// </summary>
public sealed class UnfinishedPotionAction : SkillAction
{
    private readonly PotionDefinition _potion;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Herblaw;

    public UnfinishedPotionAction(Player player, PotionDefinition potion, IItemFactory itemFactory)
        : base(player, 2)
    {
        _potion = potion;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        // Remove vial of water and herb
        if (!Player.Inventory.Remove(HerbloreItems.VialOfWater, 1))
        {
            Player.Message("You need a vial of water.");
            Cancel();
            return;
        }

        if (!Player.Inventory.Remove(_potion.HerbId, 1))
        {
            // Return the vial
            Player.Inventory.Add(HerbloreItems.VialOfWater, 1, _itemFactory);
            Player.Message("You don't have the required herb.");
            Cancel();
            return;
        }

        if (Player.Inventory.Add(_potion.UnfinishedId, 1, _itemFactory))
        {
            Player.Message($"You add the herb to the vial.");
        }
    }
}

/// <summary>
/// Finished potion making action.
/// </summary>
public sealed class FinishedPotionAction : SkillAction
{
    private readonly PotionDefinition _potion;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Herblaw;

    public FinishedPotionAction(Player player, PotionDefinition potion, IItemFactory itemFactory)
        : base(player, 3)
    {
        _potion = potion;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        if (!Player.Inventory.Remove(_potion.UnfinishedId, 1))
        {
            Player.Message("You need an unfinished potion.");
            Cancel();
            return;
        }

        if (!Player.Inventory.Remove(_potion.SecondaryId, 1))
        {
            Player.Inventory.Add(_potion.UnfinishedId, 1, _itemFactory);
            Player.Message("You don't have the required secondary ingredient.");
            Cancel();
            return;
        }

        if (Player.Inventory.Add(_potion.FinishedId, 1, _itemFactory))
        {
            Player.Skills.AddExperience(Skill.Herblaw, _potion.Experience);
            Player.Message($"You make a {_potion.Name.ToLower()}.");
        }
    }
}

/// <summary>
/// Herblore skill manager.
/// </summary>
public static class HerbloreManager
{
    /// <summary>
    /// Cleans a grimy herb.
    /// </summary>
    public static SkillActionResult CleanHerb(Player player, int grimyHerbId, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(grimyHerbId))
            return SkillActionResult.Fail("You don't have that herb.");

        if (!HerbDefinition.All.TryGetValue(grimyHerbId, out var herb))
            return SkillActionResult.Fail("This is not a grimy herb.");

        var level = player.Skills.GetCurrentLevel(Skill.Herblaw);
        if (level < herb.RequiredLevel)
            return SkillActionResult.Fail($"You need level {herb.RequiredLevel} Herblore to clean {herb.Name.ToLower()}.");

        return SkillActionResult.Ok(new HerbCleaningAction(player, herb, itemFactory));
    }

    /// <summary>
    /// Makes an unfinished potion.
    /// </summary>
    public static SkillActionResult MakeUnfinishedPotion(Player player, int herbId, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(HerbloreItems.VialOfWater))
            return SkillActionResult.Fail("You need a vial of water.");

        if (!player.Inventory.HasItem(herbId))
            return SkillActionResult.Fail("You don't have that herb.");

        var potion = PotionDefinition.All.FirstOrDefault(p => p.HerbId == herbId);
        if (potion is null)
            return SkillActionResult.Fail("You cannot make a potion with that herb.");

        var level = player.Skills.GetCurrentLevel(Skill.Herblaw);
        if (level < potion.RequiredLevel)
            return SkillActionResult.Fail($"You need level {potion.RequiredLevel} Herblore to make {potion.Name.ToLower()}.");

        player.Message("You add the herb to the vial...");
        return SkillActionResult.Ok(new UnfinishedPotionAction(player, potion, itemFactory));
    }

    /// <summary>
    /// Finishes a potion.
    /// </summary>
    public static SkillActionResult FinishPotion(Player player, int unfinishedId, int secondaryId, IItemFactory itemFactory)
    {
        if (!player.Inventory.HasItem(unfinishedId))
            return SkillActionResult.Fail("You don't have an unfinished potion.");

        if (!player.Inventory.HasItem(secondaryId))
            return SkillActionResult.Fail("You don't have the secondary ingredient.");

        var potion = PotionDefinition.All.FirstOrDefault(p => p.UnfinishedId == unfinishedId && p.SecondaryId == secondaryId);
        if (potion is null)
            return SkillActionResult.Fail("These ingredients don't make a potion.");

        var level = player.Skills.GetCurrentLevel(Skill.Herblaw);
        if (level < potion.RequiredLevel)
            return SkillActionResult.Fail($"You need level {potion.RequiredLevel} Herblore to make {potion.Name.ToLower()}.");

        player.Message("You add the secondary ingredient...");
        return SkillActionResult.Ok(new FinishedPotionAction(player, potion, itemFactory));
    }
}
