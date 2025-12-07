using OpenRSC.Server.Models;
using OpenRSC.Server.Simulation;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Simulation;

/// <summary>
/// The decision-making brain for a simulated bot.
/// Uses a combination of rule-based logic and Q-learning for adaptive behavior.
/// </summary>
public sealed class BotBrain
{
    private readonly SimulatedPlayer _player;
    private readonly SimulatedWorld _world;
    private readonly Random _random;
    private readonly QLearningAgent _qAgent;

    // State tracking for learning
    private GameState _lastState;
    private BotActionType _lastAction;
    private double _lastReward;
    private int _ticksSinceLastDecision;

    public BotBrain(SimulatedPlayer player, SimulatedWorld world, Random random)
    {
        _player = player;
        _world = world;
        _random = random;
        _qAgent = new QLearningAgent(random);
        _lastState = GetCurrentState();
    }

    /// <summary>
    /// Decides the next action for the bot.
    /// </summary>
    public BotAction? DecideNextAction(int currentTick)
    {
        _ticksSinceLastDecision++;

        // Get current state
        var currentState = GetCurrentState();

        // Calculate reward from last action
        var reward = CalculateReward(currentState);

        // Update Q-values based on previous action
        if (_lastAction != BotActionType.Idle)
        {
            _qAgent.Update(_lastState, _lastAction, reward, currentState);
        }

        // Emergency actions (rule-based, always take precedence)
        var emergencyAction = GetEmergencyAction(currentState);
        if (emergencyAction != null)
        {
            _lastState = currentState;
            _lastAction = emergencyAction.Type;
            _ticksSinceLastDecision = 0;
            return emergencyAction;
        }

        // Use Q-learning to select action
        var action = _qAgent.SelectAction(currentState, _player.Profile);

        // Convert action type to actual action
        var botAction = CreateAction(action, currentState);

        _lastState = currentState;
        _lastAction = action;
        _lastReward = reward;
        _ticksSinceLastDecision = 0;

        return botAction;
    }

    /// <summary>
    /// Gets the current game state for the bot.
    /// </summary>
    private GameState GetCurrentState()
    {
        var zone = _world.GetZoneAt(_player.Player.Location);
        var nearbyNpcs = _world.GetNearbyNpcs(_player.Player.Location, 15).ToList();
        var nearbyResources = _world.GetNearbyResources(_player.Player.Location, 15).ToList();

        return new GameState
        {
            HealthPercent = (double)_player.Player.CurrentHitpoints / Math.Max(1, _player.Player.MaxHitpoints),
            InventoryFullness = (double)_player.InventorySlots / SimulatedPlayer.MaxInventorySlots,
            FoodCount = _player.FoodCount,
            InCombat = _player.HasCombatTarget,
            NearbyEnemyCount = nearbyNpcs.Count(n => n.IsAggressive || n.CombatLevel <= _player.Player.CombatLevel + 5),
            NearbyResourceCount = nearbyResources.Count,
            IsInWilderness = zone?.IsWilderness ?? false,
            NearBank = _world.FindNearestBank(_player.Player.Location)?.Location.WithinRange(_player.Player.Location, 10) ?? false,
            CombatLevel = _player.Player.CombatLevel,
            TotalLevel = _player.Player.Skills.TotalLevel,
            PrimarySkillLevel = _player.Player.Skills.GetMaxLevel(_player.Profile.PrimaryFocus)
        };
    }

    /// <summary>
    /// Calculates the reward based on state changes.
    /// </summary>
    private double CalculateReward(GameState currentState)
    {
        double reward = 0;

        // Reward for staying alive
        if (_player.Player.CurrentHitpoints > 0)
            reward += 0.1;
        else
            reward -= 10; // Heavy penalty for death

        // Reward for level ups
        if (currentState.TotalLevel > _lastState.TotalLevel)
            reward += 5 * (currentState.TotalLevel - _lastState.TotalLevel);

        // Reward for kills
        reward += _player.KillCount * 0.5;

        // Small reward for gaining XP in primary skill
        if (currentState.PrimarySkillLevel > _lastState.PrimarySkillLevel)
            reward += 2;

        // Penalty for full inventory (need to bank)
        if (currentState.InventoryFullness > 0.9)
            reward -= 0.5;

        // Reward for being efficient (not idle too long)
        if (_ticksSinceLastDecision > 10)
            reward -= 0.1 * (_ticksSinceLastDecision - 10);

        // Penalty for low health
        if (currentState.HealthPercent < 0.3)
            reward -= 1;

        return reward;
    }

    /// <summary>
    /// Gets emergency actions that override normal decision making.
    /// </summary>
    private BotAction? GetEmergencyAction(GameState state)
    {
        // Critical health - eat or flee
        if (state.HealthPercent < 0.2)
        {
            if (_player.FoodCount > 0)
                return BotAction.Eat;
            else
                return new BotAction { Type = BotActionType.Flee };
        }

        // Low health in wilderness - flee
        if (state.IsInWilderness && state.HealthPercent < 0.5 && !_player.Profile.WillEnterWilderness)
        {
            return new BotAction { Type = BotActionType.Flee };
        }

        // Full inventory - go bank
        if (state.InventoryFullness >= 1.0)
        {
            return BotAction.Bank;
        }

        return null;
    }

    /// <summary>
    /// Creates a concrete action from an action type.
    /// </summary>
    private BotAction CreateAction(BotActionType actionType, GameState state)
    {
        switch (actionType)
        {
            case BotActionType.Attack:
                var target = FindBestCombatTarget();
                if (target != null)
                    return BotAction.Attack(target);
                return BotAction.Idle;

            case BotActionType.Gather:
                var resource = FindBestResource();
                if (resource != null)
                    return BotAction.Gather(resource);
                return BotAction.Idle;

            case BotActionType.Bank:
                return BotAction.Bank;

            case BotActionType.Eat:
                if (_player.FoodCount > 0)
                    return BotAction.Eat;
                return BotAction.Bank;

            case BotActionType.Train:
                return BotAction.Train(_player.Profile.PrimaryFocus);

            case BotActionType.Walk:
                var destination = FindExplorationTarget();
                return BotAction.Walk(destination);

            case BotActionType.Flee:
                return new BotAction { Type = BotActionType.Flee };

            default:
                return BotAction.Idle;
        }
    }

    private SimulatedNpc? FindBestCombatTarget()
    {
        var combatLevel = _player.Player.CombatLevel;
        var (minLevel, maxLevel) = _player.Profile.TargetCombatRange;

        return _world.GetNearbyNpcs(_player.Player.Location, 20)
            .Where(n => n.CombatLevel >= minLevel && n.CombatLevel <= maxLevel)
            .Where(n => n.CombatLevel <= combatLevel + 5) // Don't attack too strong
            .OrderBy(n => n.CombatLevel)
            .ThenBy(n => n.Location.DistanceTo(_player.Player.Location))
            .FirstOrDefault();
    }

    private SimulatedResource? FindBestResource()
    {
        var skill = _player.Profile.PrimaryFocus;
        var resourceType = skill switch
        {
            Skill.Woodcutting => ResourceType.Tree,
            Skill.Mining => ResourceType.Rock,
            Skill.Fishing => ResourceType.FishingSpot,
            _ => (ResourceType?)null
        };

        if (!resourceType.HasValue)
        {
            // For combat skills, find any resource
            return _world.GetNearbyResources(_player.Player.Location, 30)
                .Where(r => _player.Player.Skills.GetMaxLevel(Skill.Woodcutting) >= r.RequiredLevel ||
                           _player.Player.Skills.GetMaxLevel(Skill.Mining) >= r.RequiredLevel)
                .OrderBy(r => r.Location.DistanceTo(_player.Player.Location))
                .FirstOrDefault();
        }

        var skillLevel = _player.Player.Skills.GetMaxLevel(skill);
        return _world.GetNearbyResources(_player.Player.Location, 30, resourceType.Value)
            .Where(r => skillLevel >= r.RequiredLevel)
            .OrderByDescending(r => r.BaseExperience)
            .ThenBy(r => r.Location.DistanceTo(_player.Player.Location))
            .FirstOrDefault();
    }

    private Point FindExplorationTarget()
    {
        // Find zones we haven't explored much
        var currentZone = _world.GetZoneAt(_player.Player.Location);

        foreach (var zone in _world.Zones)
        {
            if (zone == currentZone) continue;
            if (zone.IsWilderness && !_player.Profile.WillEnterWilderness) continue;

            // Move towards this zone
            var centerX = (zone.MinBounds.X + zone.MaxBounds.X) / 2;
            var centerY = (zone.MinBounds.Y + zone.MaxBounds.Y) / 2;
            return new Point(centerX, centerY);
        }

        // Random walk within current zone
        if (currentZone != null)
        {
            return new Point(
                _random.Next(currentZone.MinBounds.X, currentZone.MaxBounds.X),
                _random.Next(currentZone.MinBounds.Y, currentZone.MaxBounds.Y)
            );
        }

        return _player.SpawnPoint;
    }

    /// <summary>
    /// Gets the current Q-values for analysis.
    /// </summary>
    public Dictionary<BotActionType, double> GetQValues(GameState state)
    {
        return _qAgent.GetQValues(state);
    }

    /// <summary>
    /// Saves the learned Q-table.
    /// </summary>
    public void SaveLearning(string path)
    {
        _qAgent.SaveQTable(path);
    }

    /// <summary>
    /// Loads a previously learned Q-table.
    /// </summary>
    public void LoadLearning(string path)
    {
        _qAgent.LoadQTable(path);
    }
}

/// <summary>
/// Represents the current game state for ML decision making.
/// </summary>
public readonly struct GameState : IEquatable<GameState>
{
    public double HealthPercent { get; init; }
    public double InventoryFullness { get; init; }
    public int FoodCount { get; init; }
    public bool InCombat { get; init; }
    public int NearbyEnemyCount { get; init; }
    public int NearbyResourceCount { get; init; }
    public bool IsInWilderness { get; init; }
    public bool NearBank { get; init; }
    public int CombatLevel { get; init; }
    public int TotalLevel { get; init; }
    public int PrimarySkillLevel { get; init; }

    /// <summary>
    /// Discretizes the state for Q-table lookup.
    /// </summary>
    public string ToStateKey()
    {
        var healthBucket = (int)(HealthPercent * 4); // 0-4
        var invBucket = (int)(InventoryFullness * 3); // 0-3
        var foodBucket = Math.Min(FoodCount, 3); // 0-3
        var enemyBucket = Math.Min(NearbyEnemyCount, 3); // 0-3
        var resourceBucket = Math.Min(NearbyResourceCount, 3); // 0-3
        var levelBucket = Math.Min(CombatLevel / 10, 10); // 0-10

        return $"{healthBucket}_{invBucket}_{foodBucket}_{(InCombat ? 1 : 0)}_{enemyBucket}_{resourceBucket}_{(IsInWilderness ? 1 : 0)}_{(NearBank ? 1 : 0)}_{levelBucket}";
    }

    public bool Equals(GameState other) => ToStateKey() == other.ToStateKey();
    public override bool Equals(object? obj) => obj is GameState state && Equals(state);
    public override int GetHashCode() => ToStateKey().GetHashCode();
}
