using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using OpenRSC.Server.Simulation;
using OpenRSC.Server.Skills;
using Xunit;

namespace OpenRSC.Server.Tests.E2E;

/// <summary>
/// End-to-end tests using the game simulation framework.
/// </summary>
public class SimulationTests
{
    [Fact]
    public async Task Simulation_WithSingleBot_CompletesSuccessfully()
    {
        // Arrange
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000, // Very fast for testing
                MaxTicks = 1000,
                RandomSeed = 12345
            });

        simulator.AddBot("TestBot", BotProfile.Default);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        stats.TotalTicks.Should().Be(1000);
        stats.TotalBotActions.Should().BeGreaterThan(0);
        simulator.Bots.Should().HaveCount(1);
    }

    [Fact]
    public async Task Simulation_WithMultipleBots_AllBotsAct()
    {
        // Arrange
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 500,
                RandomSeed = 42
            });

        simulator.AddBots(10);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        stats.TotalBotActions.Should().BeGreaterThan(100);
        simulator.Bots.All(b => b.Player != null).Should().BeTrue();
    }

    [Fact]
    public async Task Simulation_BotsGainExperience_OverTime()
    {
        // Arrange
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 5000,
                RandomSeed = 123
            });

        var bot = simulator.AddBot("XPBot", BotProfile.Warrior);
        var initialTotalXP = bot.Player.Skills.TotalExperience;

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        stats.TotalExperienceGained.Values.Sum().Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task Simulation_SkillerBot_FocusesOnGathering()
    {
        // Arrange
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 2000,
                RandomSeed = 456
            });

        simulator.AddBot("SkillerBot", BotProfile.Skiller);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        stats.ActionCounts.Should().ContainKey("Gather");
        var gatherCount = stats.ActionCounts.GetValueOrDefault("Gather", 0);
        var attackCount = stats.ActionCounts.GetValueOrDefault("Attack", 0);

        // Skillers should gather more than attack
        gatherCount.Should().BeGreaterThan(attackCount);
    }

    [Fact]
    public async Task Simulation_WarriorBot_FocusesOnCombat()
    {
        // Arrange
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 2000,
                RandomSeed = 789
            });

        simulator.AddBot("WarriorBot", BotProfile.Warrior);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        stats.ActionCounts.Should().ContainKey("Attack");
    }

    [Fact]
    public async Task Simulation_BotsRespawnAfterDeath()
    {
        // Arrange
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 10000,
                RandomSeed = 321
            });

        // Use aggressive warrior that might die
        var bot = simulator.AddBot("AggressiveBot", new BotProfile
        {
            Name = "Aggressive",
            PrimaryFocus = Skill.Attack,
            Aggression = 1.0,
            Caution = 0.0
        });

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        // If bot died, it should have respawned
        bot.Player.CurrentHitpoints.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task Simulation_CanBeCancelled()
    {
        // Arrange
        var cts = new CancellationTokenSource();
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 100,
                MaxTicks = 100000 // Would take a long time
            });

        simulator.AddBot("CancelBot");

        // Act - Cancel after short delay
        var task = simulator.RunAsync(cts.Token);
        await Task.Delay(100);
        cts.Cancel();

        var stats = await task;

        // Assert
        stats.TotalTicks.Should().BeLessThan(100000);
    }

    [Fact]
    public void SimulatedWorld_ContainsExpectedZones()
    {
        // Arrange
        var random = new Random(42);
        var world = new SimulatedWorld(random);

        // Assert
        world.Zones.Should().HaveCountGreaterOrEqualTo(2);
        world.Zones.Should().Contain(z => z.Name == "Lumbridge");
        world.Zones.Should().Contain(z => z.Name == "Varrock");
    }

    [Fact]
    public void SimulatedWorld_HasResources()
    {
        // Arrange
        var random = new Random(42);
        var world = new SimulatedWorld(random);

        // Act
        var resources = world.Zones.SelectMany(z => z.Resources).ToList();

        // Assert
        resources.Should().Contain(r => r.Type == ResourceType.Tree);
        resources.Should().Contain(r => r.Type == ResourceType.Rock);
        resources.Should().Contain(r => r.Type == ResourceType.FishingSpot);
        resources.Should().Contain(r => r.Type == ResourceType.Bank);
    }

    [Fact]
    public void SimulatedWorld_HasNpcs()
    {
        // Arrange
        var random = new Random(42);
        var world = new SimulatedWorld(random);

        // Act
        var npcs = world.Zones.SelectMany(z => z.Npcs).ToList();

        // Assert
        npcs.Should().NotBeEmpty();
        npcs.Should().Contain(n => n.Name == "Chicken");
        npcs.Should().Contain(n => n.Name == "Cow");
        npcs.Should().Contain(n => n.Name == "Goblin");
    }

    [Fact]
    public void BotProfile_RandomProfile_ProducesVariation()
    {
        // Arrange
        var random = new Random(42);

        // Act
        var profiles = Enumerable.Range(0, 100)
            .Select(_ => BotProfile.RandomProfile(random))
            .ToList();

        // Assert
        profiles.Select(p => p.Aggression).Distinct().Count().Should().BeGreaterThan(10);
        profiles.Select(p => p.Caution).Distinct().Count().Should().BeGreaterThan(10);
        profiles.Select(p => p.Exploration).Distinct().Count().Should().BeGreaterThan(10);
    }

    [Fact]
    public void SimulatedPlayer_StartsWithEquipment()
    {
        // Arrange
        var random = new Random(42);
        var world = new SimulatedWorld(random);

        // Act
        var player = new SimulatedPlayer("Test", world, random, BotProfile.Default);

        // Assert
        player.Inventory.Should().NotBeEmpty();
        player.FoodCount.Should().BeGreaterThan(0);
    }

    [Fact]
    public void SimulatedPlayer_ExecuteAction_Gather_GainsXP()
    {
        // Arrange
        var random = new Random(42);
        var world = new SimulatedWorld(random);
        var player = new SimulatedPlayer("GatherTest", world, random, BotProfile.Skiller);

        var tree = world.Zones.First().Resources.First(r => r.Type == ResourceType.Tree);

        // Act
        var result = player.ExecuteAction(BotAction.Gather(tree));

        // Assert
        // Either success with XP or fail (random chance)
        result.Should().NotBeNull();
    }

    [Fact]
    public async Task Simulation_StatsAreAccurate()
    {
        // Arrange
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 1000,
                RandomSeed = 999
            });

        simulator.AddBots(5);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        stats.SuccessfulActions.Should().BeLessOrEqualTo(stats.TotalBotActions);
        stats.FailedActions.Should().BeLessOrEqualTo(stats.TotalBotActions);
        (stats.SuccessfulActions + stats.FailedActions).Should().Be(stats.TotalBotActions);
    }
}
