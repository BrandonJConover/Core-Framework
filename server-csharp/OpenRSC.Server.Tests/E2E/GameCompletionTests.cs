using FluentAssertions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using OpenRSC.Server.ML;
using OpenRSC.Server.Simulation;
using OpenRSC.Server.Skills;
using Xunit;
using Xunit.Abstractions;

namespace OpenRSC.Server.Tests.E2E;

/// <summary>
/// Tests for verifying bots can progress through the game and "beat" it.
/// These tests ensure all game systems work correctly together.
/// </summary>
public class GameCompletionTests
{
    private readonly ITestOutputHelper _output;
    private readonly ILogger<GameCompletionTrainer> _logger;

    public GameCompletionTests(ITestOutputHelper output)
    {
        _output = output;
        _logger = new TestLogger<GameCompletionTrainer>(output);
    }

    [Fact]
    public async Task Bots_CanMakeProgress_InSimulation()
    {
        // Arrange - Quick test to verify basic progress
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 50000,
                MaxTicks = 10000,
                RandomSeed = 12345
            });

        simulator.AddBot("TestWarrior", BotProfile.Warrior);
        simulator.AddBot("TestSkiller", BotProfile.Skiller);
        simulator.AddBot("TestMage", BotProfile.Mage);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        stats.TotalBotActions.Should().BeGreaterThan(0, "bots should take actions");
        stats.SuccessfulActions.Should().BeGreaterThan(0, "some actions should succeed");

        // Verify XP was gained
        var totalXP = stats.TotalExperienceGained.Values.Sum();
        totalXP.Should().BeGreaterThan(0, "bots should gain XP");

        _output.WriteLine($"Total actions: {stats.TotalBotActions}");
        _output.WriteLine($"Successful: {stats.SuccessfulActions}");
        _output.WriteLine($"Total XP: {totalXP}");
    }

    [Fact]
    public async Task Bots_CanProgressTowards_EasyCriteria()
    {
        // Arrange
        var criteria = GameCompletionCriteria.Easy;
        var trainer = new GameCompletionTrainer(
            _logger,
            criteria,
            seed: 42);

        var progressLogs = new List<string>();
        trainer.OnLog += (_, msg) => progressLogs.Add(msg);

        // Act - Run for a limited number of episodes
        var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var progress = await trainer.TrainUntilCompleteAsync(
            maxEpisodes: 10,
            cancellationToken: cts.Token);

        // Assert
        progress.TotalTicks.Should().BeGreaterThan(0);
        progress.CompletionPercent(criteria).Should().BeGreaterThan(0, "should make some progress");

        // Log results
        _output.WriteLine($"Completion: {progress.CompletionPercent(criteria):F1}%");
        _output.WriteLine($"Combat Level: {progress.CurrentCombatLevel}");
        _output.WriteLine($"Total Level: {progress.CurrentTotalLevel}");
        _output.WriteLine($"Kills: {progress.TotalKills}");
        _output.WriteLine($"Deaths: {progress.TotalDeaths}");
        _output.WriteLine($"Total XP: {progress.TotalXPGained:N0}");

        foreach (var log in progressLogs.TakeLast(10))
        {
            _output.WriteLine(log);
        }
    }

    [Fact]
    public async Task AllBotProfiles_AreValid()
    {
        // Arrange & Act - Test each profile type
        var profiles = new[]
        {
            BotProfile.Default,
            BotProfile.Warrior,
            BotProfile.Skiller,
            BotProfile.Mage
        };

        foreach (var profile in profiles)
        {
            var random = new Random(42);
            var world = new SimulatedWorld(random);
            var player = new SimulatedPlayer($"Test_{profile.Name}", world, random, profile);

            // Assert
            player.Should().NotBeNull();
            player.Player.Should().NotBeNull();
            player.Player.Skills.Should().NotBeNull();
            player.Profile.Should().Be(profile);

            _output.WriteLine($"Profile {profile.Name}: Primary={profile.PrimaryFocus}, Aggression={profile.Aggression}");
        }
    }

    [Fact]
    public async Task SimulatedWorld_HasAllRequiredContent()
    {
        // Arrange
        var random = new Random(42);
        var world = new SimulatedWorld(random);

        // Assert - Zones
        world.Zones.Should().NotBeEmpty();
        world.Zones.Should().Contain(z => z.Name == "Lumbridge");
        world.Zones.Should().Contain(z => z.Name == "Varrock");

        // Assert - Resources
        var allResources = world.Zones.SelectMany(z => z.Resources).ToList();
        allResources.Should().Contain(r => r.Type == ResourceType.Tree);
        allResources.Should().Contain(r => r.Type == ResourceType.Rock);
        allResources.Should().Contain(r => r.Type == ResourceType.FishingSpot);
        allResources.Should().Contain(r => r.Type == ResourceType.Bank);

        // Assert - NPCs
        var allNpcs = world.Zones.SelectMany(z => z.Npcs).ToList();
        allNpcs.Should().Contain(n => n.Name == "Chicken");
        allNpcs.Should().Contain(n => n.Name == "Cow");
        allNpcs.Should().Contain(n => n.Name == "Goblin");

        _output.WriteLine($"Zones: {world.Zones.Count}");
        _output.WriteLine($"Resources: {allResources.Count}");
        _output.WriteLine($"NPCs: {allNpcs.Count}");
    }

    [Fact]
    public async Task QLearningAgent_LearnsFromExperience()
    {
        // Arrange
        var random = new Random(42);
        var agent = new QLearningAgent(random);
        var state = new GameState
        {
            HealthPercent = 0.8,
            CombatLevel = 10,
            InCombat = false
        };
        var nextState = new GameState
        {
            HealthPercent = 0.9,
            CombatLevel = 10,
            InCombat = false
        };

        // Act - Train the agent
        for (var i = 0; i < 100; i++)
        {
            agent.Update(state, BotActionType.Attack, 5.0, nextState);
        }

        // Assert
        agent.TotalUpdates.Should().Be(100);
        agent.StatesExplored.Should().BeGreaterThan(0);

        // Q-value for attack should have increased
        var qValues = agent.GetQValues(state);
        qValues[BotActionType.Attack].Should().BeGreaterThan(0);

        _output.WriteLine($"Updates: {agent.TotalUpdates}");
        _output.WriteLine($"States: {agent.StatesExplored}");
        _output.WriteLine($"Attack Q-value: {qValues[BotActionType.Attack]:F3}");
    }

    [Fact]
    public void GameCompletionCriteria_AllLevels_AreValid()
    {
        // Test Easy
        var easy = GameCompletionCriteria.Easy;
        easy.TargetCombatLevel.Should().BeGreaterThan(0);
        easy.TargetTotalLevel.Should().BeGreaterThan(0);
        easy.RequiredSkillLevels.Should().NotBeEmpty();

        // Test Medium
        var medium = GameCompletionCriteria.Medium;
        medium.TargetCombatLevel.Should().BeGreaterThan(easy.TargetCombatLevel);
        medium.TargetTotalLevel.Should().BeGreaterThan(easy.TargetTotalLevel);

        // Test Hard
        var hard = GameCompletionCriteria.Hard;
        hard.TargetCombatLevel.Should().BeGreaterThan(medium.TargetCombatLevel);
        hard.TargetTotalLevel.Should().BeGreaterThan(medium.TargetTotalLevel);
    }

    /// <summary>
    /// Helper logger that outputs to xUnit test output.
    /// </summary>
    private class TestLogger<T> : ILogger<T>
    {
        private readonly ITestOutputHelper _output;

        public TestLogger(ITestOutputHelper output)
        {
            _output = output;
        }

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            try
            {
                _output.WriteLine($"[{logLevel}] {formatter(state, exception)}");
            }
            catch
            {
                // Ignore output errors during test cleanup
            }
        }
    }
}
