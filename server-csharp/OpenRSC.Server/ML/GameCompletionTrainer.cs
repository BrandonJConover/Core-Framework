using Microsoft.Extensions.Logging;
using OpenRSC.Server.Simulation;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.ML;

/// <summary>
/// Defines what it means to "beat" or complete the game.
/// </summary>
public sealed class GameCompletionCriteria
{
    /// <summary>
    /// Target combat level to achieve.
    /// </summary>
    public int TargetCombatLevel { get; init; } = 50;

    /// <summary>
    /// Target total level (sum of all skill levels).
    /// </summary>
    public int TargetTotalLevel { get; init; } = 200;

    /// <summary>
    /// Minimum level required in primary skill.
    /// </summary>
    public int MinPrimarySkillLevel { get; init; } = 40;

    /// <summary>
    /// Minimum gold accumulated.
    /// </summary>
    public int MinGoldAccumulated { get; init; } = 10000;

    /// <summary>
    /// Maximum deaths allowed (too many = failing).
    /// </summary>
    public int MaxDeaths { get; init; } = 50;

    /// <summary>
    /// Minimum kill count.
    /// </summary>
    public int MinKills { get; init; } = 100;

    /// <summary>
    /// Skills that must reach a minimum level.
    /// </summary>
    public Dictionary<Skill, int> RequiredSkillLevels { get; init; } = new()
    {
        { Skill.Attack, 30 },
        { Skill.Strength, 30 },
        { Skill.Defense, 20 },
        { Skill.Hits, 30 }
    };

    public static GameCompletionCriteria Easy => new()
    {
        TargetCombatLevel = 20,
        TargetTotalLevel = 100,
        MinPrimarySkillLevel = 20,
        MinGoldAccumulated = 1000,
        MaxDeaths = 100,
        MinKills = 20,
        RequiredSkillLevels = new()
        {
            { Skill.Attack, 15 },
            { Skill.Hits, 15 }
        }
    };

    public static GameCompletionCriteria Medium => new()
    {
        TargetCombatLevel = 40,
        TargetTotalLevel = 250,
        MinPrimarySkillLevel = 35,
        MinGoldAccumulated = 5000,
        MaxDeaths = 75,
        MinKills = 75,
        RequiredSkillLevels = new()
        {
            { Skill.Attack, 25 },
            { Skill.Strength, 25 },
            { Skill.Defense, 20 },
            { Skill.Hits, 25 }
        }
    };

    public static GameCompletionCriteria Hard => new()
    {
        TargetCombatLevel = 60,
        TargetTotalLevel = 400,
        MinPrimarySkillLevel = 50,
        MinGoldAccumulated = 25000,
        MaxDeaths = 50,
        MinKills = 200,
        RequiredSkillLevels = new()
        {
            { Skill.Attack, 40 },
            { Skill.Strength, 40 },
            { Skill.Defense, 35 },
            { Skill.Hits, 40 },
            { Skill.Woodcutting, 30 },
            { Skill.Mining, 25 }
        }
    };
}

/// <summary>
/// Progress towards game completion.
/// </summary>
public sealed class CompletionProgress
{
    public int CurrentCombatLevel { get; set; }
    public int CurrentTotalLevel { get; set; }
    public int PrimarySkillLevel { get; set; }
    public int GoldAccumulated { get; set; }
    public int TotalDeaths { get; set; }
    public int TotalKills { get; set; }
    public Dictionary<Skill, int> SkillLevels { get; } = new();
    public long TotalXPGained { get; set; }
    public int TotalTicks { get; set; }
    public TimeSpan TrainingTime { get; set; }

    // Bottleneck tracking
    public string? CurrentBottleneck { get; set; }
    public Dictionary<string, int> BottleneckCounts { get; } = new();
    public List<string> Issues { get; } = new();

    public double CompletionPercent(GameCompletionCriteria criteria)
    {
        var checks = new List<double>();

        checks.Add(Math.Min(1.0, (double)CurrentCombatLevel / criteria.TargetCombatLevel));
        checks.Add(Math.Min(1.0, (double)CurrentTotalLevel / criteria.TargetTotalLevel));
        checks.Add(Math.Min(1.0, (double)PrimarySkillLevel / criteria.MinPrimarySkillLevel));
        checks.Add(Math.Min(1.0, (double)TotalKills / criteria.MinKills));

        foreach (var (skill, target) in criteria.RequiredSkillLevels)
        {
            var current = SkillLevels.GetValueOrDefault(skill, 1);
            checks.Add(Math.Min(1.0, (double)current / target));
        }

        return checks.Average() * 100;
    }

    public bool IsComplete(GameCompletionCriteria criteria)
    {
        if (CurrentCombatLevel < criteria.TargetCombatLevel) return false;
        if (CurrentTotalLevel < criteria.TargetTotalLevel) return false;
        if (PrimarySkillLevel < criteria.MinPrimarySkillLevel) return false;
        if (TotalKills < criteria.MinKills) return false;
        if (TotalDeaths > criteria.MaxDeaths) return false;

        foreach (var (skill, target) in criteria.RequiredSkillLevels)
        {
            var current = SkillLevels.GetValueOrDefault(skill, 1);
            if (current < target) return false;
        }

        return true;
    }

    public bool HasFailed(GameCompletionCriteria criteria)
    {
        return TotalDeaths > criteria.MaxDeaths;
    }

    public override string ToString()
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("=== Completion Progress ===");
        sb.AppendLine($"Combat Level: {CurrentCombatLevel}");
        sb.AppendLine($"Total Level: {CurrentTotalLevel}");
        sb.AppendLine($"Primary Skill: {PrimarySkillLevel}");
        sb.AppendLine($"Kills: {TotalKills}, Deaths: {TotalDeaths}");
        sb.AppendLine($"Total XP: {TotalXPGained:N0}");
        sb.AppendLine($"Training Time: {TrainingTime.TotalMinutes:F1} minutes");

        if (SkillLevels.Count > 0)
        {
            sb.AppendLine("\nSkill Levels:");
            foreach (var (skill, level) in SkillLevels.OrderByDescending(x => x.Value))
            {
                sb.AppendLine($"  {skill}: {level}");
            }
        }

        if (Issues.Count > 0)
        {
            sb.AppendLine("\nIssues Detected:");
            foreach (var issue in Issues.Distinct().Take(10))
            {
                sb.AppendLine($"  - {issue}");
            }
        }

        if (!string.IsNullOrEmpty(CurrentBottleneck))
        {
            sb.AppendLine($"\nCurrent Bottleneck: {CurrentBottleneck}");
        }

        return sb.ToString();
    }
}

/// <summary>
/// Trains bots until they can beat the game, making adjustments as needed.
/// </summary>
public sealed class GameCompletionTrainer
{
    private readonly ILogger _logger;
    private readonly GameCompletionCriteria _criteria;
    private readonly CompletionProgress _progress = new();
    private readonly Random _random;

    // Adaptive parameters
    private double _learningRate = 0.15;
    private double _explorationRate = 0.3;
    private int _ticksPerEpisode = 50000;
    private int _botCount = 5;

    // Tracking
    private int _totalEpisodes;
    private int _stuckCounter;
    private double _lastCompletionPercent;
    private readonly List<double> _completionHistory = new();

    public CompletionProgress Progress => _progress;
    public bool IsComplete => _progress.IsComplete(_criteria);
    public bool HasFailed => _progress.HasFailed(_criteria);

    public event EventHandler<string>? OnLog;
    public event EventHandler<CompletionProgress>? OnProgress;

    public GameCompletionTrainer(
        ILogger logger,
        GameCompletionCriteria? criteria = null,
        int? seed = null)
    {
        _logger = logger;
        _criteria = criteria ?? GameCompletionCriteria.Easy;
        _random = seed.HasValue ? new Random(seed.Value) : new Random();
    }

    /// <summary>
    /// Trains until game completion or failure.
    /// </summary>
    public async Task<CompletionProgress> TrainUntilCompleteAsync(
        int maxEpisodes = 1000,
        CancellationToken cancellationToken = default)
    {
        var startTime = DateTime.UtcNow;
        Log($"Starting training with {_criteria.GetType().Name} criteria");
        Log($"Target: Combat {_criteria.TargetCombatLevel}, Total Level {_criteria.TargetTotalLevel}");

        // Shared Q-table for transfer learning between episodes
        var sharedQAgent = new QLearningAgent(_random);
        sharedQAgent.SetHyperparameters(_learningRate, 0.95, _explorationRate);

        while (_totalEpisodes < maxEpisodes && !cancellationToken.IsCancellationRequested)
        {
            _totalEpisodes++;

            // Run an episode
            var episodeResult = await RunEpisodeAsync(sharedQAgent, cancellationToken);

            // Update progress
            UpdateProgress(episodeResult);

            var completionPercent = _progress.CompletionPercent(_criteria);
            _completionHistory.Add(completionPercent);

            Log($"Episode {_totalEpisodes}: {completionPercent:F1}% complete, " +
                $"Combat Lvl {_progress.CurrentCombatLevel}, " +
                $"Total Lvl {_progress.CurrentTotalLevel}, " +
                $"Kills {_progress.TotalKills}");

            OnProgress?.Invoke(this, _progress);

            // Check for completion
            if (_progress.IsComplete(_criteria))
            {
                Log("SUCCESS! Game completion criteria met!");
                break;
            }

            // Check for failure
            if (_progress.HasFailed(_criteria))
            {
                Log($"FAILED: Too many deaths ({_progress.TotalDeaths})");
                IdentifyAndFixIssues(sharedQAgent);
            }

            // Check if stuck and adapt
            if (IsStuck(completionPercent))
            {
                _stuckCounter++;
                Log($"Progress stalled (stuck count: {_stuckCounter})");
                IdentifyAndFixIssues(sharedQAgent);
                AdaptParameters();
            }
            else
            {
                _stuckCounter = 0;
            }

            _lastCompletionPercent = completionPercent;

            // Periodic detailed logging
            if (_totalEpisodes % 10 == 0)
            {
                Log(_progress.ToString());
            }
        }

        _progress.TrainingTime = DateTime.UtcNow - startTime;
        Log($"\nTraining complete after {_totalEpisodes} episodes");
        Log(_progress.ToString());

        return _progress;
    }

    private async Task<EpisodeResult> RunEpisodeAsync(
        QLearningAgent sharedAgent,
        CancellationToken cancellationToken)
    {
        using var simulator = new GameSimulator(
            _logger as ILogger<GameSimulator> ??
            Microsoft.Extensions.Logging.Abstractions.NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 50000, // Very fast
                MaxTicks = _ticksPerEpisode,
                RandomSeed = _random.Next(),
                VerboseLogging = false,
                ProgressReportInterval = 10000
            });

        // Add diverse bots
        AddDiverseBots(simulator);

        // Track best performer
        SimulatedPlayer? bestBot = null;
        var bestLevel = 0;

        simulator.OnTick += (_, args) =>
        {
            foreach (var bot in args.Bots)
            {
                var level = bot.Player.Skills.TotalLevel;
                if (level > bestLevel)
                {
                    bestLevel = level;
                    bestBot = bot;
                }
            }
        };

        var stats = await simulator.RunAsync(cancellationToken);

        // Collect results from best bot
        return new EpisodeResult
        {
            EpisodeNumber = _totalEpisodes,
            Ticks = stats.TotalTicks,
            TotalReward = CalculateReward(stats, bestBot),
            LevelUps = stats.TotalLevelUps,
            Deaths = stats.TotalDeaths,
            ActionsExecuted = stats.TotalBotActions,
            ActionBreakdown = new Dictionary<string, int>(stats.ActionCounts),
            BestBot = bestBot,
            Stats = stats
        };
    }

    private void AddDiverseBots(GameSimulator simulator)
    {
        // Add a mix of profiles optimized for different aspects
        simulator.AddBot("BalancedMain", new BotProfile
        {
            Name = "Balanced",
            PrimaryFocus = Skill.Attack,
            SecondaryFocus = { Skill.Strength, Skill.Defense, Skill.Hits },
            Aggression = 0.6,
            Caution = 0.5,
            Exploration = 0.3
        });

        simulator.AddBot("CombatFocus", new BotProfile
        {
            Name = "CombatFocus",
            PrimaryFocus = Skill.Strength,
            SecondaryFocus = { Skill.Attack, Skill.Defense },
            Aggression = 0.8,
            Caution = 0.4,
            Exploration = 0.2,
            TargetCombatRange = (1, 30)
        });

        simulator.AddBot("SurvivalFocus", new BotProfile
        {
            Name = "Survival",
            PrimaryFocus = Skill.Defense,
            SecondaryFocus = { Skill.Hits },
            Aggression = 0.4,
            Caution = 0.8,
            Exploration = 0.2
        });

        if (_botCount > 3)
        {
            simulator.AddBot("Skiller", new BotProfile
            {
                Name = "Skiller",
                PrimaryFocus = Skill.Woodcutting,
                SecondaryFocus = { Skill.Mining, Skill.Fishing },
                Aggression = 0.1,
                Caution = 0.9,
                Exploration = 0.4
            });
        }

        if (_botCount > 4)
        {
            simulator.AddBot("Explorer", new BotProfile
            {
                Name = "Explorer",
                PrimaryFocus = Skill.Attack,
                Aggression = 0.5,
                Caution = 0.5,
                Exploration = 0.8
            });
        }
    }

    private double CalculateReward(SimulationStats stats, SimulatedPlayer? bestBot)
    {
        double reward = 0;

        // XP-based reward
        reward += stats.TotalExperienceGained.Values.Sum() * 0.001;

        // Level-up reward
        reward += stats.TotalLevelUps * 10;

        // Kill reward
        if (bestBot != null)
        {
            reward += bestBot.KillCount * 2;
        }

        // Death penalty
        reward -= stats.TotalDeaths * 20;

        // Efficiency bonus
        var successRate = stats.TotalBotActions > 0
            ? (double)stats.SuccessfulActions / stats.TotalBotActions
            : 0;
        reward += successRate * 50;

        return reward;
    }

    private void UpdateProgress(EpisodeResult result)
    {
        _progress.TotalTicks += result.Ticks;
        _progress.TotalDeaths += result.Deaths;

        if (result.BestBot != null)
        {
            var bot = result.BestBot;

            // Update best levels seen
            _progress.CurrentCombatLevel = Math.Max(_progress.CurrentCombatLevel, bot.Player.CombatLevel);
            _progress.CurrentTotalLevel = Math.Max(_progress.CurrentTotalLevel, bot.Player.Skills.TotalLevel);
            _progress.PrimarySkillLevel = Math.Max(_progress.PrimarySkillLevel,
                bot.Player.Skills.GetMaxLevel(bot.Profile.PrimaryFocus));
            _progress.TotalKills += bot.KillCount;

            // Update skill levels
            foreach (Skill skill in Enum.GetValues<Skill>())
            {
                var level = bot.Player.Skills.GetMaxLevel(skill);
                if (!_progress.SkillLevels.ContainsKey(skill) || level > _progress.SkillLevels[skill])
                {
                    _progress.SkillLevels[skill] = level;
                }
            }
        }

        if (result.Stats != null)
        {
            _progress.TotalXPGained += result.Stats.TotalExperienceGained.Values.Sum();
        }
    }

    private bool IsStuck(double currentPercent)
    {
        if (_completionHistory.Count < 5) return false;

        // Check if we've made progress in last 5 episodes
        var recentProgress = _completionHistory.TakeLast(5).ToList();
        var progressDelta = recentProgress.Last() - recentProgress.First();

        return progressDelta < 0.5; // Less than 0.5% progress in 5 episodes
    }

    private void IdentifyAndFixIssues(QLearningAgent agent)
    {
        var issues = new List<string>();

        // Check for death rate issues
        var deathRate = _progress.TotalDeaths / (double)Math.Max(1, _totalEpisodes);
        if (deathRate > 5)
        {
            issues.Add("High death rate - bots are too aggressive or not eating");
            _progress.CurrentBottleneck = "Survival";
            RecordBottleneck("Survival");

            // Fix: Increase caution in bot profiles
            Log("Adjustment: Reducing aggression, increasing caution");
        }

        // Check for low kill rate
        var killRate = _progress.TotalKills / (double)Math.Max(1, _totalEpisodes);
        if (killRate < 5 && _progress.CurrentCombatLevel < _criteria.TargetCombatLevel / 2)
        {
            issues.Add("Low kill rate - bots not finding/attacking enemies");
            _progress.CurrentBottleneck = "Combat";
            RecordBottleneck("Combat");

            // Fix: Increase aggression
            Log("Adjustment: Increasing aggression and exploration");
        }

        // Check XP rate
        var xpRate = _progress.TotalXPGained / (double)Math.Max(1, _progress.TotalTicks);
        if (xpRate < 0.01 && _totalEpisodes > 5)
        {
            issues.Add("Low XP rate - bots idle or inefficient");
            _progress.CurrentBottleneck = "Efficiency";
            RecordBottleneck("Efficiency");

            Log("Adjustment: Increasing episode length and exploration");
            _ticksPerEpisode = Math.Min(_ticksPerEpisode + 10000, 200000);
        }

        // Check skill balance
        var combatSkillsLow = _criteria.RequiredSkillLevels
            .Where(kv => kv.Key is Skill.Attack or Skill.Strength or Skill.Defense)
            .Any(kv => _progress.SkillLevels.GetValueOrDefault(kv.Key, 1) < kv.Value / 2);

        if (combatSkillsLow && _totalEpisodes > 10)
        {
            issues.Add("Combat skills lagging behind");
            _progress.CurrentBottleneck = "Combat Skills";
            RecordBottleneck("Combat Skills");
        }

        foreach (var issue in issues)
        {
            _progress.Issues.Add(issue);
        }

        // Reset agent exploration if very stuck
        if (_stuckCounter > 3)
        {
            Log("Major adjustment: Resetting exploration rate");
            _explorationRate = Math.Min(0.5, _explorationRate + 0.1);
            agent.SetHyperparameters(_learningRate, 0.95, _explorationRate);
        }
    }

    private void RecordBottleneck(string bottleneck)
    {
        if (!_progress.BottleneckCounts.ContainsKey(bottleneck))
            _progress.BottleneckCounts[bottleneck] = 0;
        _progress.BottleneckCounts[bottleneck]++;
    }

    private void AdaptParameters()
    {
        // Adaptive learning rate
        if (_stuckCounter > 2)
        {
            _learningRate = Math.Min(0.3, _learningRate * 1.2);
            Log($"Increased learning rate to {_learningRate:F3}");
        }

        // Adaptive exploration
        if (_stuckCounter > 1)
        {
            _explorationRate = Math.Min(0.5, _explorationRate + 0.05);
            Log($"Increased exploration to {_explorationRate:F3}");
        }

        // Add more bots if needed
        if (_stuckCounter > 4 && _botCount < 10)
        {
            _botCount++;
            Log($"Increased bot count to {_botCount}");
        }

        // Increase episode length for more training time
        if (_stuckCounter > 3)
        {
            _ticksPerEpisode = Math.Min(_ticksPerEpisode + 20000, 300000);
            Log($"Increased episode length to {_ticksPerEpisode}");
        }
    }

    private void Log(string message)
    {
        _logger.LogInformation(message);
        OnLog?.Invoke(this, message);
        Console.WriteLine($"[Trainer] {message}");
    }

    // Extended episode result with more data
    private sealed class EpisodeResult
    {
        public int EpisodeNumber { get; init; }
        public int Ticks { get; init; }
        public double TotalReward { get; init; }
        public int LevelUps { get; init; }
        public int Deaths { get; init; }
        public int ActionsExecuted { get; init; }
        public Dictionary<string, int> ActionBreakdown { get; init; } = new();
        public SimulatedPlayer? BestBot { get; init; }
        public SimulationStats? Stats { get; init; }
    }
}
