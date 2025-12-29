using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Services;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Simulation;

/// <summary>
/// Configuration for game simulation.
/// </summary>
public sealed class SimulationConfig
{
    /// <summary>
    /// Number of game ticks per second (normal is ~1.5 for 640ms tick).
    /// Set higher for accelerated simulation.
    /// </summary>
    public double TicksPerSecond { get; init; } = 100;

    /// <summary>
    /// Maximum ticks to run before stopping.
    /// </summary>
    public int MaxTicks { get; init; } = 100_000;

    /// <summary>
    /// Random seed for reproducible simulations.
    /// </summary>
    public int? RandomSeed { get; init; }

    /// <summary>
    /// Whether to log detailed tick information.
    /// </summary>
    public bool VerboseLogging { get; init; } = false;

    /// <summary>
    /// Interval for progress reporting.
    /// </summary>
    public int ProgressReportInterval { get; init; } = 1000;
}

/// <summary>
/// Statistics collected during simulation.
/// </summary>
public sealed class SimulationStats
{
    public int TotalTicks { get; set; }
    public int TotalBotActions { get; set; }
    public int SuccessfulActions { get; set; }
    public int FailedActions { get; set; }
    public TimeSpan ElapsedTime { get; set; }
    public Dictionary<string, int> ActionCounts { get; } = new();
    public Dictionary<Skill, long> TotalExperienceGained { get; } = new();
    public int TotalLevelUps { get; set; }
    public int TotalDeaths { get; set; }
    public int TotalItemsCollected { get; set; }
    public double TicksPerSecondActual { get; set; }

    public void RecordAction(string actionType, bool success)
    {
        TotalBotActions++;
        if (success) SuccessfulActions++;
        else FailedActions++;

        if (!ActionCounts.ContainsKey(actionType))
            ActionCounts[actionType] = 0;
        ActionCounts[actionType]++;
    }

    public void RecordExperience(Skill skill, int amount)
    {
        if (!TotalExperienceGained.ContainsKey(skill))
            TotalExperienceGained[skill] = 0;
        TotalExperienceGained[skill] += amount;
    }

    public override string ToString()
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("=== Simulation Statistics ===");
        sb.AppendLine($"Total Ticks: {TotalTicks:N0}");
        sb.AppendLine($"Elapsed Time: {ElapsedTime.TotalSeconds:F2}s");
        sb.AppendLine($"Actual TPS: {TicksPerSecondActual:F1}");
        sb.AppendLine($"Total Actions: {TotalBotActions:N0}");
        sb.AppendLine($"Success Rate: {(TotalBotActions > 0 ? (double)SuccessfulActions / TotalBotActions * 100 : 0):F1}%");
        sb.AppendLine($"Total Level Ups: {TotalLevelUps}");
        sb.AppendLine($"Total Deaths: {TotalDeaths}");

        if (ActionCounts.Count > 0)
        {
            sb.AppendLine("\nAction Breakdown:");
            foreach (var (action, count) in ActionCounts.OrderByDescending(x => x.Value))
            {
                sb.AppendLine($"  {action}: {count:N0}");
            }
        }

        if (TotalExperienceGained.Count > 0)
        {
            sb.AppendLine("\nExperience Gained:");
            foreach (var (skill, xp) in TotalExperienceGained.OrderByDescending(x => x.Value))
            {
                sb.AppendLine($"  {skill}: {xp:N0}");
            }
        }

        return sb.ToString();
    }
}

/// <summary>
/// Event raised during simulation for monitoring.
/// </summary>
public sealed class SimulationTickEventArgs : EventArgs
{
    public int TickNumber { get; init; }
    public IReadOnlyList<SimulatedPlayer> Bots { get; init; } = Array.Empty<SimulatedPlayer>();
    public SimulationStats Stats { get; init; } = new();
}

/// <summary>
/// High-speed game simulation harness for testing and ML training.
/// Runs the game loop without network overhead.
/// </summary>
public sealed class GameSimulator : IDisposable
{
    private readonly ILogger<GameSimulator> _logger;
    private readonly SimulationConfig _config;
    private readonly Random _random;
    private readonly List<SimulatedPlayer> _bots = new();
    private readonly SimulationStats _stats = new();
    private readonly SimulatedWorld _world;

    private int _currentTick;
    private bool _isRunning;
    private CancellationTokenSource? _cts;

    public event EventHandler<SimulationTickEventArgs>? OnTick;
    public event EventHandler<SimulationStats>? OnComplete;

    public IReadOnlyList<SimulatedPlayer> Bots => _bots;
    public SimulationStats Stats => _stats;
    public SimulatedWorld World => _world;
    public int CurrentTick => _currentTick;
    public bool IsRunning => _isRunning;

    public GameSimulator(ILogger<GameSimulator> logger, SimulationConfig? config = null)
    {
        _logger = logger;
        _config = config ?? new SimulationConfig();
        _random = _config.RandomSeed.HasValue
            ? new Random(_config.RandomSeed.Value)
            : new Random();
        _world = new SimulatedWorld(_random);
    }

    /// <summary>
    /// Adds a bot to the simulation.
    /// </summary>
    public SimulatedPlayer AddBot(string name, BotProfile? profile = null)
    {
        var bot = new SimulatedPlayer(name, _world, _random, profile ?? BotProfile.Default);
        _bots.Add(bot);
        _world.AddPlayer(bot);
        _logger.LogDebug("Added bot {Name} with profile {Profile}", name, bot.Profile.Name);
        return bot;
    }

    /// <summary>
    /// Adds multiple bots with random profiles.
    /// </summary>
    public void AddBots(int count, Func<int, BotProfile>? profileFactory = null)
    {
        for (var i = 0; i < count; i++)
        {
            var profile = profileFactory?.Invoke(i) ?? BotProfile.RandomProfile(_random);
            AddBot($"Bot_{i:D4}", profile);
        }
        _logger.LogInformation("Added {Count} bots to simulation", count);
    }

    /// <summary>
    /// Runs the simulation synchronously.
    /// </summary>
    public SimulationStats Run(CancellationToken cancellationToken = default)
    {
        return RunAsync(cancellationToken).GetAwaiter().GetResult();
    }

    /// <summary>
    /// Runs the simulation asynchronously.
    /// </summary>
    public async Task<SimulationStats> RunAsync(CancellationToken cancellationToken = default)
    {
        if (_isRunning)
            throw new InvalidOperationException("Simulation is already running");

        _isRunning = true;
        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _currentTick = 0;

        var startTime = DateTime.UtcNow;
        var tickInterval = TimeSpan.FromSeconds(1.0 / _config.TicksPerSecond);

        _logger.LogInformation("Starting simulation with {BotCount} bots, target {TPS} TPS",
            _bots.Count, _config.TicksPerSecond);

        try
        {
            while (_currentTick < _config.MaxTicks && !_cts.Token.IsCancellationRequested)
            {
                var tickStart = DateTime.UtcNow;

                // Process one game tick
                ProcessTick();
                _currentTick++;
                _stats.TotalTicks = _currentTick;

                // Progress reporting
                if (_config.VerboseLogging || _currentTick % _config.ProgressReportInterval == 0)
                {
                    var elapsed = DateTime.UtcNow - startTime;
                    _stats.ElapsedTime = elapsed;
                    _stats.TicksPerSecondActual = _currentTick / elapsed.TotalSeconds;

                    if (_currentTick % _config.ProgressReportInterval == 0)
                    {
                        _logger.LogInformation("Tick {Tick}/{Max} ({Percent:F1}%) - {TPS:F0} TPS",
                            _currentTick, _config.MaxTicks,
                            (double)_currentTick / _config.MaxTicks * 100,
                            _stats.TicksPerSecondActual);
                    }
                }

                // Raise tick event
                OnTick?.Invoke(this, new SimulationTickEventArgs
                {
                    TickNumber = _currentTick,
                    Bots = _bots,
                    Stats = _stats
                });

                // Throttle if running faster than target
                var tickDuration = DateTime.UtcNow - tickStart;
                if (tickDuration < tickInterval)
                {
                    await Task.Delay(tickInterval - tickDuration, _cts.Token);
                }
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("Simulation cancelled at tick {Tick}", _currentTick);
        }
        finally
        {
            _isRunning = false;
            _stats.ElapsedTime = DateTime.UtcNow - startTime;
            _stats.TicksPerSecondActual = _currentTick / _stats.ElapsedTime.TotalSeconds;
        }

        _logger.LogInformation("Simulation complete: {Stats}", _stats);
        OnComplete?.Invoke(this, _stats);
        return _stats;
    }

    /// <summary>
    /// Processes a single game tick.
    /// </summary>
    private void ProcessTick()
    {
        // Update world state
        _world.ProcessTick(_currentTick);

        // Process each bot
        foreach (var bot in _bots)
        {
            if (bot.Player.IsDead)
            {
                // Handle respawn
                bot.HandleDeath();
                _stats.TotalDeaths++;
                continue;
            }

            // Let bot decide and execute action
            var action = bot.DecideAction(_currentTick);
            if (action != null)
            {
                var result = bot.ExecuteAction(action);
                _stats.RecordAction(action.Type.ToString(), result.Success);

                if (result.ExperienceGained > 0)
                {
                    _stats.RecordExperience(result.Skill, result.ExperienceGained);
                }

                if (result.LeveledUp)
                {
                    _stats.TotalLevelUps++;
                }
            }

            // Process bot's current action if any
            bot.ProcessCurrentAction();
        }
    }

    /// <summary>
    /// Stops the running simulation.
    /// </summary>
    public void Stop()
    {
        _cts?.Cancel();
    }

    /// <summary>
    /// Resets the simulation state.
    /// </summary>
    public void Reset()
    {
        if (_isRunning)
            throw new InvalidOperationException("Cannot reset while running");

        _currentTick = 0;
        _bots.Clear();
        _world.Reset();
    }

    public void Dispose()
    {
        _cts?.Dispose();
    }
}
