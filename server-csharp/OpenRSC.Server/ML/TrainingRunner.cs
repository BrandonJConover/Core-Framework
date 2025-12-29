using Microsoft.Extensions.Logging;
using OpenRSC.Server.Simulation;

namespace OpenRSC.Server.ML;

/// <summary>
/// Configuration for ML training.
/// </summary>
public sealed class TrainingConfig
{
    /// <summary>
    /// Number of training episodes to run.
    /// </summary>
    public int Episodes { get; init; } = 100;

    /// <summary>
    /// Maximum ticks per episode.
    /// </summary>
    public int TicksPerEpisode { get; init; } = 10_000;

    /// <summary>
    /// Number of bots to train simultaneously.
    /// </summary>
    public int BotCount { get; init; } = 10;

    /// <summary>
    /// Path to save/load Q-table.
    /// </summary>
    public string? QTablePath { get; init; }

    /// <summary>
    /// Whether to save checkpoints during training.
    /// </summary>
    public bool SaveCheckpoints { get; init; } = true;

    /// <summary>
    /// Checkpoint interval (episodes).
    /// </summary>
    public int CheckpointInterval { get; init; } = 10;

    /// <summary>
    /// Random seed for reproducibility.
    /// </summary>
    public int? RandomSeed { get; init; }

    /// <summary>
    /// Target ticks per second for training.
    /// </summary>
    public double TicksPerSecond { get; init; } = 1000;
}

/// <summary>
/// Results from a training run.
/// </summary>
public sealed class TrainingResult
{
    public int TotalEpisodes { get; set; }
    public int TotalTicks { get; set; }
    public TimeSpan TotalTime { get; set; }
    public List<EpisodeResult> Episodes { get; } = new();
    public double AverageReward => Episodes.Count > 0 ? Episodes.Average(e => e.TotalReward) : 0;
    public double BestReward => Episodes.Count > 0 ? Episodes.Max(e => e.TotalReward) : 0;
    public int TotalLevelUps { get; set; }
    public int TotalDeaths { get; set; }
    public int StatesExplored { get; set; }
    public double FinalEpsilon { get; set; }

    public override string ToString()
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("=== Training Results ===");
        sb.AppendLine($"Episodes: {TotalEpisodes}");
        sb.AppendLine($"Total Ticks: {TotalTicks:N0}");
        sb.AppendLine($"Total Time: {TotalTime.TotalMinutes:F1} minutes");
        sb.AppendLine($"Average Reward: {AverageReward:F2}");
        sb.AppendLine($"Best Reward: {BestReward:F2}");
        sb.AppendLine($"Total Level Ups: {TotalLevelUps}");
        sb.AppendLine($"Total Deaths: {TotalDeaths}");
        sb.AppendLine($"States Explored: {StatesExplored}");
        sb.AppendLine($"Final Epsilon: {FinalEpsilon:F4}");
        return sb.ToString();
    }
}

/// <summary>
/// Results from a single training episode.
/// </summary>
public sealed class EpisodeResult
{
    public int EpisodeNumber { get; init; }
    public int Ticks { get; init; }
    public double TotalReward { get; init; }
    public int LevelUps { get; init; }
    public int Deaths { get; init; }
    public int ActionsExecuted { get; init; }
    public Dictionary<string, int> ActionBreakdown { get; init; } = new();
}

/// <summary>
/// Runs ML training for bot behavior optimization.
/// </summary>
public sealed class TrainingRunner
{
    private readonly ILogger<TrainingRunner> _logger;
    private readonly TrainingConfig _config;
    private readonly Random _random;

    public event EventHandler<EpisodeResult>? OnEpisodeComplete;
    public event EventHandler<TrainingResult>? OnTrainingComplete;

    public TrainingRunner(ILogger<TrainingRunner> logger, TrainingConfig? config = null)
    {
        _logger = logger;
        _config = config ?? new TrainingConfig();
        _random = _config.RandomSeed.HasValue ? new Random(_config.RandomSeed.Value) : new Random();
    }

    /// <summary>
    /// Runs the full training process.
    /// </summary>
    public async Task<TrainingResult> RunAsync(CancellationToken cancellationToken = default)
    {
        var result = new TrainingResult();
        var startTime = DateTime.UtcNow;

        _logger.LogInformation("Starting ML training: {Episodes} episodes, {Bots} bots, {Ticks} ticks/episode",
            _config.Episodes, _config.BotCount, _config.TicksPerEpisode);

        // Shared Q-table across episodes (transfer learning)
        QLearningAgent? sharedAgent = null;
        if (!string.IsNullOrEmpty(_config.QTablePath) && File.Exists(_config.QTablePath))
        {
            _logger.LogInformation("Loading existing Q-table from {Path}", _config.QTablePath);
            sharedAgent = new QLearningAgent(_random);
            sharedAgent.LoadQTable(_config.QTablePath);
        }

        for (var episode = 0; episode < _config.Episodes && !cancellationToken.IsCancellationRequested; episode++)
        {
            var episodeResult = await RunEpisodeAsync(episode, sharedAgent, cancellationToken);
            result.Episodes.Add(episodeResult);
            result.TotalTicks += episodeResult.Ticks;
            result.TotalLevelUps += episodeResult.LevelUps;
            result.TotalDeaths += episodeResult.Deaths;

            OnEpisodeComplete?.Invoke(this, episodeResult);

            _logger.LogInformation(
                "Episode {Episode}/{Total}: Reward={Reward:F1}, LevelUps={Levels}, Deaths={Deaths}",
                episode + 1, _config.Episodes, episodeResult.TotalReward,
                episodeResult.LevelUps, episodeResult.Deaths);

            // Save checkpoint
            if (_config.SaveCheckpoints && !string.IsNullOrEmpty(_config.QTablePath) &&
                (episode + 1) % _config.CheckpointInterval == 0)
            {
                var checkpointPath = Path.Combine(
                    Path.GetDirectoryName(_config.QTablePath) ?? ".",
                    $"checkpoint_ep{episode + 1}_{Path.GetFileName(_config.QTablePath)}");
                sharedAgent?.SaveQTable(checkpointPath);
                _logger.LogDebug("Saved checkpoint to {Path}", checkpointPath);
            }
        }

        result.TotalEpisodes = _config.Episodes;
        result.TotalTime = DateTime.UtcNow - startTime;
        result.StatesExplored = sharedAgent?.StatesExplored ?? 0;
        result.FinalEpsilon = sharedAgent?.CurrentEpsilon ?? 0;

        // Save final Q-table
        if (!string.IsNullOrEmpty(_config.QTablePath) && sharedAgent != null)
        {
            sharedAgent.SaveQTable(_config.QTablePath);
            _logger.LogInformation("Saved final Q-table to {Path}", _config.QTablePath);
        }

        OnTrainingComplete?.Invoke(this, result);
        _logger.LogInformation("Training complete: {Result}", result);

        return result;
    }

    /// <summary>
    /// Runs a single training episode.
    /// </summary>
    private async Task<EpisodeResult> RunEpisodeAsync(
        int episodeNumber,
        QLearningAgent? sharedAgent,
        CancellationToken cancellationToken)
    {
        using var simulator = new GameSimulator(
            _logger as ILogger<GameSimulator> ?? Microsoft.Extensions.Logging.Abstractions.NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = _config.TicksPerSecond,
                MaxTicks = _config.TicksPerEpisode,
                RandomSeed = _config.RandomSeed.HasValue ? _config.RandomSeed.Value + episodeNumber : null,
                VerboseLogging = false,
                ProgressReportInterval = 5000
            });

        // Add bots with varied profiles
        simulator.AddBots(_config.BotCount, i =>
        {
            var profiles = new[] { BotProfile.Default, BotProfile.Skiller, BotProfile.Warrior, BotProfile.Mage };
            return profiles[i % profiles.Length];
        });

        // Run simulation
        var stats = await simulator.RunAsync(cancellationToken);

        return new EpisodeResult
        {
            EpisodeNumber = episodeNumber,
            Ticks = stats.TotalTicks,
            TotalReward = CalculateEpisodeReward(stats),
            LevelUps = stats.TotalLevelUps,
            Deaths = stats.TotalDeaths,
            ActionsExecuted = stats.TotalBotActions,
            ActionBreakdown = new Dictionary<string, int>(stats.ActionCounts)
        };
    }

    /// <summary>
    /// Calculates the overall reward for an episode.
    /// </summary>
    private double CalculateEpisodeReward(SimulationStats stats)
    {
        double reward = 0;

        // Reward for XP gained
        reward += stats.TotalExperienceGained.Values.Sum() * 0.001;

        // Reward for level ups
        reward += stats.TotalLevelUps * 10;

        // Reward for successful actions
        reward += stats.SuccessfulActions * 0.1;

        // Penalty for deaths
        reward -= stats.TotalDeaths * 50;

        // Penalty for failed actions
        reward -= stats.FailedActions * 0.05;

        return reward;
    }

    /// <summary>
    /// Evaluates a trained model without learning.
    /// </summary>
    public async Task<EpisodeResult> EvaluateAsync(
        string qTablePath,
        int ticks = 10_000,
        CancellationToken cancellationToken = default)
    {
        var agent = new QLearningAgent(_random);
        agent.LoadQTable(qTablePath);
        agent.SetHyperparameters(0, 0.95, 0); // No learning, no exploration

        using var simulator = new GameSimulator(
            _logger as ILogger<GameSimulator> ?? Microsoft.Extensions.Logging.Abstractions.NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = _config.TicksPerSecond,
                MaxTicks = ticks,
                VerboseLogging = false
            });

        simulator.AddBots(_config.BotCount);
        var stats = await simulator.RunAsync(cancellationToken);

        return new EpisodeResult
        {
            EpisodeNumber = -1,
            Ticks = stats.TotalTicks,
            TotalReward = CalculateEpisodeReward(stats),
            LevelUps = stats.TotalLevelUps,
            Deaths = stats.TotalDeaths,
            ActionsExecuted = stats.TotalBotActions,
            ActionBreakdown = new Dictionary<string, int>(stats.ActionCounts)
        };
    }
}

/// <summary>
/// Utility for running parameter sweeps to find optimal hyperparameters.
/// </summary>
public static class HyperparameterTuner
{
    /// <summary>
    /// Runs a grid search over hyperparameters.
    /// </summary>
    public static async Task<Dictionary<string, TrainingResult>> GridSearchAsync(
        ILogger logger,
        double[] learningRates,
        double[] discountFactors,
        double[] epsilons,
        CancellationToken cancellationToken = default)
    {
        var results = new Dictionary<string, TrainingResult>();

        foreach (var lr in learningRates)
        {
            foreach (var df in discountFactors)
            {
                foreach (var eps in epsilons)
                {
                    if (cancellationToken.IsCancellationRequested)
                        break;

                    var key = $"lr={lr}_df={df}_eps={eps}";
                    logger.LogInformation("Testing hyperparameters: {Key}", key);

                    var runner = new TrainingRunner(
                        logger as ILogger<TrainingRunner> ?? Microsoft.Extensions.Logging.Abstractions.NullLogger<TrainingRunner>.Instance,
                        new TrainingConfig
                        {
                            Episodes = 10, // Quick evaluation
                            TicksPerEpisode = 5000,
                            BotCount = 5
                        });

                    var result = await runner.RunAsync(cancellationToken);
                    results[key] = result;

                    logger.LogInformation("  Result: AvgReward={Avg:F2}, Best={Best:F2}",
                        result.AverageReward, result.BestReward);
                }
            }
        }

        // Find best configuration
        var best = results.OrderByDescending(r => r.Value.AverageReward).First();
        logger.LogInformation("Best configuration: {Key} with reward {Reward:F2}",
            best.Key, best.Value.AverageReward);

        return results;
    }
}
