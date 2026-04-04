using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// NPC pickpocket definition.
/// </summary>
public sealed record PickpocketDefinition
{
    public required int NpcId { get; init; }
    public required string NpcName { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int StunDamage { get; init; }
    public required int StunTicks { get; init; }
    public required IReadOnlyList<LootEntry> Loot { get; init; }

    public static readonly IReadOnlyDictionary<int, PickpocketDefinition> All = new Dictionary<int, PickpocketDefinition>
    {
        [1] = new()
        {
            NpcId = 1, NpcName = "Man", RequiredLevel = 1, Experience = 8,
            StunDamage = 1, StunTicks = 5,
            Loot = new[] { new LootEntry(10, "Coins", 3, 1, 10) }
        },
        [2] = new()
        {
            NpcId = 2, NpcName = "Farmer", RequiredLevel = 10, Experience = 14,
            StunDamage = 1, StunTicks = 5,
            Loot = new[] { new LootEntry(10, "Coins", 9, 1, 20), new LootEntry(150, "Potato seed", 1, 1, 3) }
        },
        [18] = new()
        {
            NpcId = 18, NpcName = "Warrior", RequiredLevel = 25, Experience = 26,
            StunDamage = 2, StunTicks = 5,
            Loot = new[] { new LootEntry(10, "Coins", 18, 10, 50) }
        },
        [21] = new()
        {
            NpcId = 21, NpcName = "Rogue", RequiredLevel = 32, Experience = 35,
            StunDamage = 2, StunTicks = 6,
            Loot = new[]
            {
                new LootEntry(10, "Coins", 25, 20, 80),
                new LootEntry(42, "Air rune", 8, 5, 10),
                new LootEntry(714, "Lockpick", 1, 1, 1)
            }
        },
        [66] = new()
        {
            NpcId = 66, NpcName = "Guard", RequiredLevel = 40, Experience = 46,
            StunDamage = 2, StunTicks = 5,
            Loot = new[] { new LootEntry(10, "Coins", 30, 20, 60) }
        },
        [187] = new()
        {
            NpcId = 187, NpcName = "Knight", RequiredLevel = 55, Experience = 84,
            StunDamage = 3, StunTicks = 5,
            Loot = new[] { new LootEntry(10, "Coins", 50, 40, 100) }
        },
        [365] = new()
        {
            NpcId = 365, NpcName = "Paladin", RequiredLevel = 70, Experience = 151,
            StunDamage = 3, StunTicks = 5,
            Loot = new[]
            {
                new LootEntry(10, "Coins", 80, 60, 150),
                new LootEntry(41, "Chaos rune", 2, 1, 3)
            }
        },
        [322] = new()
        {
            NpcId = 322, NpcName = "Hero", RequiredLevel = 80, Experience = 275,
            StunDamage = 4, StunTicks = 6,
            Loot = new[]
            {
                new LootEntry(10, "Coins", 200, 100, 400),
                new LootEntry(41, "Blood rune", 2, 1, 2),
                new LootEntry(161, "Fire orb", 1, 1, 1)
            }
        }
    };
}

/// <summary>
/// Loot entry for thieving.
/// </summary>
public sealed record LootEntry(int ItemId, string ItemName, int Weight, int MinAmount, int MaxAmount)
{
    public int GetAmount() => MinAmount == MaxAmount ? MinAmount : Random.Shared.Next(MinAmount, MaxAmount + 1);
}

/// <summary>
/// Stall definition for stealing from stalls.
/// </summary>
public sealed record StallDefinition
{
    public required int ObjectId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int RespawnTicks { get; init; }
    public required IReadOnlyList<LootEntry> Loot { get; init; }

    public static readonly IReadOnlyDictionary<int, StallDefinition> All = new Dictionary<int, StallDefinition>
    {
        [322] = new()
        {
            ObjectId = 322, Name = "Baker's stall", RequiredLevel = 5, Experience = 16, RespawnTicks = 5,
            Loot = new[] { new LootEntry(138, "Bread", 3, 1, 1), new LootEntry(330, "Cake", 1, 1, 1) }
        },
        [323] = new()
        {
            ObjectId = 323, Name = "Tea stall", RequiredLevel = 5, Experience = 16, RespawnTicks = 7,
            Loot = new[] { new LootEntry(739, "Cup of tea", 1, 1, 1) }
        },
        [324] = new()
        {
            ObjectId = 324, Name = "Silk stall", RequiredLevel = 20, Experience = 24, RespawnTicks = 8,
            Loot = new[] { new LootEntry(200, "Silk", 1, 1, 1) }
        },
        [325] = new()
        {
            ObjectId = 325, Name = "Fur stall", RequiredLevel = 35, Experience = 36, RespawnTicks = 15,
            Loot = new[] { new LootEntry(146, "Grey wolf fur", 1, 1, 1) }
        },
        [326] = new()
        {
            ObjectId = 326, Name = "Silver stall", RequiredLevel = 50, Experience = 54, RespawnTicks = 30,
            Loot = new[] { new LootEntry(383, "Silver bar", 1, 1, 1) }
        },
        [327] = new()
        {
            ObjectId = 327, Name = "Spice stall", RequiredLevel = 65, Experience = 81, RespawnTicks = 80,
            Loot = new[] { new LootEntry(707, "Spice", 1, 1, 1) }
        },
        [328] = new()
        {
            ObjectId = 328, Name = "Gem stall", RequiredLevel = 75, Experience = 160, RespawnTicks = 180,
            Loot = new[]
            {
                new LootEntry(160, "Uncut sapphire", 3, 1, 1),
                new LootEntry(159, "Uncut emerald", 2, 1, 1),
                new LootEntry(158, "Uncut ruby", 1, 1, 1)
            }
        }
    };
}

/// <summary>
/// Chest definition for lockpicking.
/// </summary>
public sealed record ChestDefinition
{
    public required int ObjectId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int RespawnTicks { get; init; }
    public bool RequiresLockpick { get; init; } = true;
    public required IReadOnlyList<LootEntry> Loot { get; init; }

    public static readonly IReadOnlyDictionary<int, ChestDefinition> All = new Dictionary<int, ChestDefinition>
    {
        [334] = new()
        {
            ObjectId = 334, Name = "10 coin chest", RequiredLevel = 13, Experience = 7, RespawnTicks = 15,
            RequiresLockpick = false,
            Loot = new[] { new LootEntry(10, "Coins", 1, 10, 10) }
        },
        [335] = new()
        {
            ObjectId = 335, Name = "Nature rune chest", RequiredLevel = 28, Experience = 25, RespawnTicks = 25,
            Loot = new[] { new LootEntry(40, "Nature rune", 1, 3, 3) }
        },
        [336] = new()
        {
            ObjectId = 336, Name = "50 coin chest", RequiredLevel = 43, Experience = 125, RespawnTicks = 100,
            Loot = new[] { new LootEntry(10, "Coins", 1, 50, 50) }
        },
        [337] = new()
        {
            ObjectId = 337, Name = "Blood rune chest", RequiredLevel = 59, Experience = 250, RespawnTicks = 250,
            Loot = new[] { new LootEntry(619, "Blood rune", 1, 2, 2) }
        }
    };
}

/// <summary>
/// Thieving items.
/// </summary>
public static class ThievingItems
{
    public const int Lockpick = 714;
}

/// <summary>
/// Pickpocket action.
/// </summary>
public sealed class PickpocketAction : SkillAction
{
    private readonly PickpocketDefinition _target;
    private readonly Npc _npc;
    private readonly IItemFactory _itemFactory;

    public override Skill Skill => Skill.Thieving;

    public PickpocketAction(Player player, PickpocketDefinition target, Npc npc, IItemFactory itemFactory)
        : base(player, 2)
    {
        _target = target;
        _npc = npc;
        _itemFactory = itemFactory;
    }

    protected override void OnComplete()
    {
        var level = Player.Skills.GetCurrentLevel(Skill.Thieving);
        var successChance = CalculateSuccessChance(level);

        if (Random.Shared.NextDouble() < successChance)
        {
            // Success
            var loot = SelectLoot();
            var amount = loot.GetAmount();

            if (Player.Inventory.Add(loot.ItemId, amount, _itemFactory))
            {
                Player.Skills.AddExperience(Skill.Thieving, _target.Experience);
                Player.Message($"You pick the {_target.NpcName.ToLower()}'s pocket.");
            }
            else
            {
                Player.Message("Your inventory is full.");
            }
        }
        else
        {
            // Stunned
            Player.Message($"You fail to pick the {_target.NpcName.ToLower()}'s pocket.");
            Player.Message("You have been stunned!");
            Player.Damage(_target.StunDamage);
            Player.Stun(_target.StunTicks);

            // NPC might turn aggressive
            _npc.ForceChat("What do you think you're doing?");
        }
    }

    private double CalculateSuccessChance(int level)
    {
        var levelDiff = level - _target.RequiredLevel;
        var baseChance = 0.5 + levelDiff * 0.02;
        return Math.Clamp(baseChance, 0.2, 0.95);
    }

    private LootEntry SelectLoot()
    {
        var totalWeight = _target.Loot.Sum(l => l.Weight);
        var roll = Random.Shared.Next(totalWeight);
        var cumulative = 0;

        foreach (var loot in _target.Loot)
        {
            cumulative += loot.Weight;
            if (roll < cumulative)
                return loot;
        }

        return _target.Loot[^1];
    }
}

/// <summary>
/// Stall stealing action.
/// </summary>
public sealed class StealFromStallAction : SkillAction
{
    private readonly StallDefinition _stall;
    private readonly IItemFactory _itemFactory;
    private readonly Action? _onSuccess; // Callback to deplete stall

    public override Skill Skill => Skill.Thieving;

    public StealFromStallAction(Player player, StallDefinition stall, IItemFactory itemFactory, Action? onSuccess = null)
        : base(player, 2)
    {
        _stall = stall;
        _itemFactory = itemFactory;
        _onSuccess = onSuccess;
    }

    protected override void OnComplete()
    {
        var loot = SelectLoot();
        var amount = loot.GetAmount();

        if (Player.Inventory.Add(loot.ItemId, amount, _itemFactory))
        {
            Player.Skills.AddExperience(Skill.Thieving, _stall.Experience);
            Player.Message($"You steal from the {_stall.Name.ToLower()}.");
            _onSuccess?.Invoke();
        }
        else
        {
            Player.Message("Your inventory is full.");
        }
    }

    private LootEntry SelectLoot()
    {
        var totalWeight = _stall.Loot.Sum(l => l.Weight);
        var roll = Random.Shared.Next(totalWeight);
        var cumulative = 0;

        foreach (var loot in _stall.Loot)
        {
            cumulative += loot.Weight;
            if (roll < cumulative)
                return loot;
        }

        return _stall.Loot[^1];
    }
}

/// <summary>
/// Chest lockpicking action.
/// </summary>
public sealed class LockpickChestAction : SkillAction
{
    private readonly ChestDefinition _chest;
    private readonly IItemFactory _itemFactory;
    private readonly Action? _onSuccess;

    public override Skill Skill => Skill.Thieving;

    public LockpickChestAction(Player player, ChestDefinition chest, IItemFactory itemFactory, Action? onSuccess = null)
        : base(player, 3)
    {
        _chest = chest;
        _itemFactory = itemFactory;
        _onSuccess = onSuccess;
    }

    protected override void OnComplete()
    {
        var level = Player.Skills.GetCurrentLevel(Skill.Thieving);
        var successChance = 0.6 + (level - _chest.RequiredLevel) * 0.02;

        if (Random.Shared.NextDouble() < successChance)
        {
            foreach (var loot in _chest.Loot)
            {
                var amount = loot.GetAmount();
                Player.Inventory.Add(loot.ItemId, amount, _itemFactory);
            }

            Player.Skills.AddExperience(Skill.Thieving, _chest.Experience);
            Player.Message("You successfully pick the lock.");
            _onSuccess?.Invoke();
        }
        else
        {
            Player.Message("You fail to pick the lock.");
            // Possible trap damage
            if (Random.Shared.NextDouble() < 0.3)
            {
                Player.Message("You triggered a trap!");
                Player.Damage(Random.Shared.Next(1, 4));
            }
        }
    }
}

/// <summary>
/// Thieving skill manager.
/// </summary>
public static class ThievingManager
{
    /// <summary>
    /// Attempts to pickpocket an NPC.
    /// </summary>
    public static SkillActionResult Pickpocket(Player player, Npc npc, IItemFactory itemFactory)
    {
        if (!PickpocketDefinition.All.TryGetValue(npc.NpcId, out var target))
            return SkillActionResult.Fail("You can't pickpocket this NPC.");

        var level = player.Skills.GetCurrentLevel(Skill.Thieving);
        if (level < target.RequiredLevel)
            return SkillActionResult.Fail($"You need level {target.RequiredLevel} Thieving to pickpocket {target.NpcName.ToLower()}s.");

        if (player.Inventory.IsFull)
            return SkillActionResult.Fail("Your inventory is full.");

        if (player.IsStunned)
            return SkillActionResult.Fail("You are still stunned.");

        player.Message($"You attempt to pick the {target.NpcName.ToLower()}'s pocket...");
        return SkillActionResult.Ok(new PickpocketAction(player, target, npc, itemFactory));
    }

    /// <summary>
    /// Attempts to steal from a stall.
    /// </summary>
    public static SkillActionResult StealFromStall(Player player, int objectId, IItemFactory itemFactory, Action? onSuccess = null)
    {
        if (!StallDefinition.All.TryGetValue(objectId, out var stall))
            return SkillActionResult.Fail("You can't steal from this.");

        var level = player.Skills.GetCurrentLevel(Skill.Thieving);
        if (level < stall.RequiredLevel)
            return SkillActionResult.Fail($"You need level {stall.RequiredLevel} Thieving to steal from {stall.Name.ToLower()}.");

        if (player.Inventory.IsFull)
            return SkillActionResult.Fail("Your inventory is full.");

        player.Message($"You attempt to steal from the {stall.Name.ToLower()}...");
        return SkillActionResult.Ok(new StealFromStallAction(player, stall, itemFactory, onSuccess));
    }

    /// <summary>
    /// Attempts to lockpick a chest.
    /// </summary>
    public static SkillActionResult LockpickChest(Player player, int objectId, IItemFactory itemFactory, Action? onSuccess = null)
    {
        if (!ChestDefinition.All.TryGetValue(objectId, out var chest))
            return SkillActionResult.Fail("You can't lockpick this.");

        var level = player.Skills.GetCurrentLevel(Skill.Thieving);
        if (level < chest.RequiredLevel)
            return SkillActionResult.Fail($"You need level {chest.RequiredLevel} Thieving to pick this lock.");

        if (chest.RequiresLockpick && !player.Inventory.HasItem(ThievingItems.Lockpick))
            return SkillActionResult.Fail("You need a lockpick.");

        if (player.Inventory.IsFull)
            return SkillActionResult.Fail("Your inventory is full.");

        player.Message("You attempt to pick the lock...");
        return SkillActionResult.Ok(new LockpickChestAction(player, chest, itemFactory, onSuccess));
    }
}
