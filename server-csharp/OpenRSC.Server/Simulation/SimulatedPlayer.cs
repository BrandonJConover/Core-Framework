using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Simulation;

/// <summary>
/// Profile that defines a bot's behavior and goals.
/// </summary>
public sealed class BotProfile
{
    public string Name { get; init; } = "Default";

    /// <summary>
    /// Primary skill focus (what the bot prefers to train).
    /// </summary>
    public Skill PrimaryFocus { get; init; } = Skill.Attack;

    /// <summary>
    /// Secondary skills to train.
    /// </summary>
    public List<Skill> SecondaryFocus { get; init; } = new();

    /// <summary>
    /// How aggressive is the bot in combat (0-1).
    /// </summary>
    public double Aggression { get; init; } = 0.5;

    /// <summary>
    /// How cautious is the bot about health (0-1).
    /// Higher means banks/eats food more often.
    /// </summary>
    public double Caution { get; init; } = 0.5;

    /// <summary>
    /// Exploration tendency (0-1).
    /// Higher means more likely to move to new areas.
    /// </summary>
    public double Exploration { get; init; } = 0.3;

    /// <summary>
    /// Target combat level range (min, max).
    /// </summary>
    public (int min, int max) TargetCombatRange { get; init; } = (1, 50);

    /// <summary>
    /// Whether the bot will enter the wilderness.
    /// </summary>
    public bool WillEnterWilderness { get; init; } = false;

    /// <summary>
    /// Preferred action when idle.
    /// </summary>
    public BotIdleAction IdleAction { get; init; } = BotIdleAction.TrainPrimary;

    public static BotProfile Default => new()
    {
        Name = "Balanced",
        PrimaryFocus = Skill.Attack,
        SecondaryFocus = { Skill.Strength, Skill.Defense },
        Aggression = 0.5,
        Caution = 0.5,
        Exploration = 0.3
    };

    public static BotProfile Skiller => new()
    {
        Name = "Skiller",
        PrimaryFocus = Skill.Woodcutting,
        SecondaryFocus = { Skill.Mining, Skill.Fishing, Skill.Cooking },
        Aggression = 0.0,
        Caution = 1.0,
        Exploration = 0.5,
        TargetCombatRange = (3, 3)
    };

    public static BotProfile Warrior => new()
    {
        Name = "Warrior",
        PrimaryFocus = Skill.Attack,
        SecondaryFocus = { Skill.Strength, Skill.Defense, Skill.Hits },
        Aggression = 0.8,
        Caution = 0.3,
        Exploration = 0.4
    };

    public static BotProfile Mage => new()
    {
        Name = "Mage",
        PrimaryFocus = Skill.Magic,
        SecondaryFocus = { Skill.Prayer },
        Aggression = 0.6,
        Caution = 0.7,
        Exploration = 0.3
    };

    public static BotProfile RandomProfile(Random random)
    {
        var profiles = new[] { Default, Skiller, Warrior, Mage };
        var baseProfile = profiles[random.Next(profiles.Length)];

        return new BotProfile
        {
            Name = baseProfile.Name + "_Random",
            PrimaryFocus = baseProfile.PrimaryFocus,
            SecondaryFocus = baseProfile.SecondaryFocus,
            Aggression = Math.Clamp(baseProfile.Aggression + (random.NextDouble() - 0.5) * 0.4, 0, 1),
            Caution = Math.Clamp(baseProfile.Caution + (random.NextDouble() - 0.5) * 0.4, 0, 1),
            Exploration = Math.Clamp(baseProfile.Exploration + (random.NextDouble() - 0.5) * 0.4, 0, 1),
            TargetCombatRange = baseProfile.TargetCombatRange,
            WillEnterWilderness = random.NextDouble() < 0.1,
            IdleAction = baseProfile.IdleAction
        };
    }
}

public enum BotIdleAction
{
    TrainPrimary,
    TrainSecondary,
    Combat,
    Bank,
    Wander
}

/// <summary>
/// An action the bot can take.
/// </summary>
public sealed class BotAction
{
    public BotActionType Type { get; init; }
    public object? Target { get; init; }
    public int Priority { get; init; }
    public int EstimatedTicks { get; init; } = 1;

    public static BotAction Idle => new() { Type = BotActionType.Idle };
    public static BotAction Walk(Point target) => new() { Type = BotActionType.Walk, Target = target };
    public static BotAction Attack(SimulatedNpc npc) => new() { Type = BotActionType.Attack, Target = npc };
    public static BotAction Gather(SimulatedResource resource) => new() { Type = BotActionType.Gather, Target = resource };
    public static BotAction Bank => new() { Type = BotActionType.Bank };
    public static BotAction Eat => new() { Type = BotActionType.Eat };
    public static BotAction Train(Skill skill) => new() { Type = BotActionType.Train, Target = skill };
}

public enum BotActionType
{
    Idle,
    Walk,
    Attack,
    Gather,
    Bank,
    Eat,
    Train,
    Flee,
    PickupItem
}

/// <summary>
/// Result of executing an action.
/// </summary>
public sealed class ActionResult
{
    public bool Success { get; init; }
    public string? Message { get; init; }
    public Skill Skill { get; init; }
    public int ExperienceGained { get; init; }
    public bool LeveledUp { get; init; }
    public int DamageDealt { get; init; }
    public int DamageTaken { get; init; }

    public static ActionResult Succeeded(Skill skill = Skill.Attack, int xp = 0, bool levelUp = false) =>
        new() { Success = true, Skill = skill, ExperienceGained = xp, LeveledUp = levelUp };

    public static ActionResult Failed(string message) =>
        new() { Success = false, Message = message };
}

/// <summary>
/// A simulated player (bot) for testing.
/// </summary>
public sealed class SimulatedPlayer
{
    private readonly SimulatedWorld _world;
    private readonly Random _random;
    private readonly BotBrain _brain;

    private BotAction? _currentAction;
    private int _actionTicksRemaining;
    private SimulatedNpc? _combatTarget;
    private int _combatCooldown;

    public string Name { get; }
    public Player Player { get; }
    public BotProfile Profile { get; }
    public Point SpawnPoint { get; }

    // Simplified inventory for simulation
    public Dictionary<int, int> Inventory { get; } = new();
    public int InventorySlots => Inventory.Count;
    public const int MaxInventorySlots = 30;
    public int FoodCount { get; private set; } = 10;

    // Combat stats
    public int KillCount { get; private set; }
    public int DeathCount { get; private set; }

    public SimulatedPlayer(string name, SimulatedWorld world, Random random, BotProfile profile)
    {
        Name = name;
        _world = world;
        _random = random;
        Profile = profile;
        SpawnPoint = new Point(125, 125); // Lumbridge

        // Create underlying player entity
        Player = new Player(name, SpawnPoint);
        Player.CurrentHitpoints = 10;
        Player.MaxHitpoints = 10;

        // Initialize with starter equipment
        InitializeStarterGear();

        _brain = new BotBrain(this, world, random);
    }

    private void InitializeStarterGear()
    {
        // Give starter items
        Inventory[1351] = 1; // Bronze axe
        Inventory[1265] = 1; // Bronze pickaxe
        Inventory[995] = 25; // Coins
        FoodCount = 5;
    }

    public BotAction? DecideAction(int currentTick)
    {
        // If we have an ongoing action, continue it
        if (_currentAction != null && _actionTicksRemaining > 0)
        {
            return null;
        }

        // Let the brain decide
        return _brain.DecideNextAction(currentTick);
    }

    public ActionResult ExecuteAction(BotAction action)
    {
        _currentAction = action;

        switch (action.Type)
        {
            case BotActionType.Idle:
                _actionTicksRemaining = 1;
                return ActionResult.Succeeded();

            case BotActionType.Walk:
                return ExecuteWalk((Point)action.Target!);

            case BotActionType.Attack:
                return ExecuteAttack((SimulatedNpc)action.Target!);

            case BotActionType.Gather:
                return ExecuteGather((SimulatedResource)action.Target!);

            case BotActionType.Bank:
                return ExecuteBank();

            case BotActionType.Eat:
                return ExecuteEat();

            case BotActionType.Train:
                return ExecuteTrain((Skill)action.Target!);

            case BotActionType.Flee:
                return ExecuteFlee();

            default:
                return ActionResult.Failed($"Unknown action type: {action.Type}");
        }
    }

    private ActionResult ExecuteWalk(Point target)
    {
        var distance = Player.Location.DistanceTo(target);
        _actionTicksRemaining = (int)Math.Ceiling(distance);
        Player.Location = target;
        return ActionResult.Succeeded();
    }

    private ActionResult ExecuteAttack(SimulatedNpc npc)
    {
        if (npc.IsDead)
            return ActionResult.Failed("Target is dead");

        if (_combatCooldown > 0)
        {
            _combatCooldown--;
            return ActionResult.Failed("Combat on cooldown");
        }

        _combatTarget = npc;
        _actionTicksRemaining = 4; // Combat tick rate
        _combatCooldown = 4;

        // Calculate hit
        var attackLevel = Player.Skills.GetMaxLevel(Skill.Attack);
        var strengthLevel = Player.Skills.GetMaxLevel(Skill.Strength);
        var defenseLevel = npc.DefenseBonus;

        var hitChance = 0.5 + (attackLevel - defenseLevel) * 0.02;
        hitChance = Math.Clamp(hitChance, 0.1, 0.95);

        int damage = 0;
        int xpGained = 0;
        bool leveledUp = false;

        if (_random.NextDouble() < hitChance)
        {
            var maxHit = 1 + strengthLevel / 4;
            damage = _random.Next(1, maxHit + 1);
            npc.TakeDamage(damage);

            // Award XP
            xpGained = damage * 4;
            var oldLevel = Player.Skills.GetMaxLevel(Skill.Attack);
            Player.Skills.AddExperience(Skill.Attack, xpGained);
            Player.Skills.AddExperience(Skill.Hits, xpGained / 3);
            leveledUp = Player.Skills.GetMaxLevel(Skill.Attack) > oldLevel;

            if (npc.IsDead)
            {
                KillCount++;
                npc.CurrentRespawnTimer = npc.RespawnTicks;

                // Handle drops
                foreach (var (itemId, chance) in npc.DropTable)
                {
                    if (_random.NextDouble() < chance)
                    {
                        if (InventorySlots < MaxInventorySlots)
                        {
                            if (!Inventory.ContainsKey(itemId))
                                Inventory[itemId] = 0;
                            Inventory[itemId]++;
                        }
                    }
                }
            }
        }

        // NPC retaliation
        if (!npc.IsDead && _random.NextDouble() < 0.4)
        {
            var npcDamage = _random.Next(0, npc.StrengthBonus / 2 + 1);
            Player.CurrentHitpoints -= npcDamage;
        }

        return new ActionResult
        {
            Success = true,
            Skill = Skill.Attack,
            ExperienceGained = xpGained,
            LeveledUp = leveledUp,
            DamageDealt = damage
        };
    }

    private ActionResult ExecuteGather(SimulatedResource resource)
    {
        if (!resource.IsAvailable)
            return ActionResult.Failed("Resource not available");

        if (InventorySlots >= MaxInventorySlots)
            return ActionResult.Failed("Inventory full");

        var skill = resource.Type switch
        {
            ResourceType.Tree => Skill.Woodcutting,
            ResourceType.Rock => Skill.Mining,
            ResourceType.FishingSpot => Skill.Fishing,
            _ => Skill.Attack
        };

        var level = Player.Skills.GetMaxLevel(skill);
        if (level < resource.RequiredLevel)
            return ActionResult.Failed($"Need {skill} level {resource.RequiredLevel}");

        // Success chance based on level
        var successChance = 0.3 + (level - resource.RequiredLevel) * 0.05;
        successChance = Math.Clamp(successChance, 0.2, 0.9);

        _actionTicksRemaining = 4;

        if (_random.NextDouble() < successChance)
        {
            var xp = resource.BaseExperience;
            var oldLevel = Player.Skills.GetMaxLevel(skill);
            Player.Skills.AddExperience(skill, xp);
            var leveledUp = Player.Skills.GetMaxLevel(skill) > oldLevel;

            // Add item (simplified)
            var itemId = resource.Type switch
            {
                ResourceType.Tree => 1511, // Logs
                ResourceType.Rock => 436, // Copper ore
                ResourceType.FishingSpot => 317, // Shrimp
                _ => 1
            };

            if (!Inventory.ContainsKey(itemId))
                Inventory[itemId] = 0;
            Inventory[itemId]++;

            resource.Deplete();

            return new ActionResult
            {
                Success = true,
                Skill = skill,
                ExperienceGained = xp,
                LeveledUp = leveledUp
            };
        }

        return ActionResult.Succeeded(skill);
    }

    private ActionResult ExecuteBank()
    {
        var bank = _world.FindNearestBank(Player.Location);
        if (bank == null)
            return ActionResult.Failed("No bank nearby");

        if (!bank.Location.WithinRange(Player.Location, 5))
        {
            Player.Location = bank.Location;
        }

        // Deposit all items (simplified)
        Inventory.Clear();
        FoodCount = 10; // Withdraw food

        _actionTicksRemaining = 3;
        return ActionResult.Succeeded();
    }

    private ActionResult ExecuteEat()
    {
        if (FoodCount <= 0)
            return ActionResult.Failed("No food");

        FoodCount--;
        var healAmount = 4;
        Player.CurrentHitpoints = Math.Min(Player.MaxHitpoints, Player.CurrentHitpoints + healAmount);
        _actionTicksRemaining = 3;

        return ActionResult.Succeeded();
    }

    private ActionResult ExecuteTrain(Skill skill)
    {
        // Find appropriate resource/target for the skill
        var resourceType = skill switch
        {
            Skill.Woodcutting => ResourceType.Tree,
            Skill.Mining => ResourceType.Rock,
            Skill.Fishing => ResourceType.FishingSpot,
            _ => (ResourceType?)null
        };

        if (resourceType.HasValue)
        {
            var resource = _world.GetNearbyResources(Player.Location, 50, resourceType.Value)
                .FirstOrDefault(r => Player.Skills.GetMaxLevel(skill) >= r.RequiredLevel);

            if (resource != null)
            {
                return ExecuteGather(resource);
            }
        }

        // Combat skills
        if (skill is Skill.Attack or Skill.Strength or Skill.Defense or Skill.Hits)
        {
            var npc = _world.GetNearbyNpcs(Player.Location, 20)
                .Where(n => n.CombatLevel <= Player.CombatLevel + 5)
                .FirstOrDefault();

            if (npc != null)
            {
                return ExecuteAttack(npc);
            }
        }

        return ActionResult.Failed($"No training target for {skill}");
    }

    private ActionResult ExecuteFlee()
    {
        _combatTarget = null;
        var bank = _world.FindNearestBank(Player.Location);
        if (bank != null)
        {
            Player.Location = bank.Location;
        }
        else
        {
            Player.Location = SpawnPoint;
        }
        return ActionResult.Succeeded();
    }

    public void ProcessCurrentAction()
    {
        if (_actionTicksRemaining > 0)
        {
            _actionTicksRemaining--;
        }

        if (_combatCooldown > 0)
        {
            _combatCooldown--;
        }

        // Update combat
        if (_combatTarget != null && !_combatTarget.IsDead)
        {
            // Continue fighting
        }
        else
        {
            _combatTarget = null;
        }
    }

    public void HandleDeath()
    {
        DeathCount++;
        Player.CurrentHitpoints = Player.MaxHitpoints;
        Player.Location = SpawnPoint;
        Inventory.Clear();
        FoodCount = 5;
        _combatTarget = null;
        _currentAction = null;
    }

    public bool NeedsFood => (double)Player.CurrentHitpoints / Player.MaxHitpoints < 0.3;
    public bool InventoryFull => InventorySlots >= MaxInventorySlots;
    public bool HasCombatTarget => _combatTarget != null && !_combatTarget.IsDead;
}
