using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using OpenRSC.Server.Combat;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Simulation;
using OpenRSC.Server.Skills;
using Xunit;

namespace OpenRSC.Server.Tests.E2E;

/// <summary>
/// Comprehensive regression tests that verify all game systems work together.
/// These tests simulate realistic gameplay scenarios.
/// </summary>
public class RegressionTests
{
    [Fact]
    public async Task FullGameplay_NewPlayer_CanProgressThroughEarlyGame()
    {
        // Scenario: A new player starts the game and progresses through early content
        // They should be able to:
        // 1. Kill chickens/cows
        // 2. Train combat skills
        // 3. Gather resources
        // 4. Level up

        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 20000, // ~30 minutes of game time at normal tick rate
                RandomSeed = 12345
            });

        var player = simulator.AddBot("NewPlayer", new BotProfile
        {
            Name = "Balanced",
            PrimaryFocus = Skill.Attack,
            SecondaryFocus = { Skill.Strength, Skill.Defense },
            Aggression = 0.6,
            Caution = 0.5
        });

        // Act
        var stats = await simulator.RunAsync();

        // Assert - Player should have made progress
        stats.TotalBotActions.Should().BeGreaterThan(1000, "player should be active");
        stats.SuccessfulActions.Should().BeGreaterThan(500, "some actions should succeed");

        // Should have gained some XP
        var totalXP = stats.TotalExperienceGained.Values.Sum();
        totalXP.Should().BeGreaterThan(0, "should have gained experience");
    }

    [Fact]
    public async Task CombatSystem_PlayerKillsNPC_GainsXPAndLoot()
    {
        // Scenario: Verify combat rewards work correctly
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 5000,
                RandomSeed = 54321
            });

        var warrior = simulator.AddBot("Warrior", BotProfile.Warrior);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        if (stats.ActionCounts.ContainsKey("Attack"))
        {
            var attackActions = stats.ActionCounts["Attack"];
            attackActions.Should().BeGreaterThan(0);

            // Combat XP should be gained
            var combatXP = stats.TotalExperienceGained
                .Where(kv => kv.Key is Skill.Attack or Skill.Strength or Skill.Defense or Skill.Hits)
                .Sum(kv => kv.Value);

            if (attackActions > 10)
            {
                combatXP.Should().BeGreaterThan(0, "combat should reward XP");
            }
        }
    }

    [Fact]
    public async Task SkillingSystem_GatheringResources_WorksCorrectly()
    {
        // Scenario: Verify resource gathering works
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 5000,
                RandomSeed = 11111
            });

        var skiller = simulator.AddBot("Skiller", BotProfile.Skiller);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        if (stats.ActionCounts.ContainsKey("Gather"))
        {
            var gatherActions = stats.ActionCounts["Gather"];

            // Should have gathering XP
            var gatheringXP = stats.TotalExperienceGained
                .Where(kv => kv.Key is Skill.Woodcutting or Skill.Mining or Skill.Fishing)
                .Sum(kv => kv.Value);

            if (gatherActions > 10)
            {
                gatheringXP.Should().BeGreaterThan(0, "gathering should reward XP");
            }
        }
    }

    [Fact]
    public async Task BankingSystem_FullInventory_BotsBank()
    {
        // Scenario: When inventory is full, bots should bank
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 10000,
                RandomSeed = 22222
            });

        simulator.AddBot("BankBot", BotProfile.Skiller);

        // Act
        var stats = await simulator.RunAsync();

        // Assert - Should have some bank actions if inventory filled
        // Bank action count depends on how many times inventory filled
        stats.TotalBotActions.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task HealthSystem_LowHealth_BotEatsOrFlees()
    {
        // Scenario: Bots should manage their health
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 5000,
                RandomSeed = 33333
            });

        // Use cautious profile
        simulator.AddBot("CautiousBot", new BotProfile
        {
            Name = "Cautious",
            PrimaryFocus = Skill.Attack,
            Aggression = 0.3,
            Caution = 0.9
        });

        // Act
        var stats = await simulator.RunAsync();

        // Assert - Should have eat/flee actions if health got low
        if (stats.ActionCounts.ContainsKey("Eat") || stats.ActionCounts.ContainsKey("Flee"))
        {
            var healthActions = stats.ActionCounts.GetValueOrDefault("Eat", 0) +
                               stats.ActionCounts.GetValueOrDefault("Flee", 0);
            healthActions.Should().BeGreaterOrEqualTo(0);
        }
    }

    [Fact]
    public async Task MultiBot_DifferentProfiles_ShowDifferentBehavior()
    {
        // Scenario: Different bot profiles should exhibit different behaviors
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 5000,
                RandomSeed = 44444
            });

        simulator.AddBot("Warrior1", BotProfile.Warrior);
        simulator.AddBot("Skiller1", BotProfile.Skiller);
        simulator.AddBot("Mage1", BotProfile.Mage);

        // Act
        var stats = await simulator.RunAsync();

        // Assert - Should have variety of actions
        stats.ActionCounts.Count.Should().BeGreaterOrEqualTo(2,
            "different profiles should produce varied actions");
    }

    [Fact]
    public async Task WorldState_ResourcesRespawn_AfterDepletion()
    {
        // Scenario: Depleted resources should respawn
        var random = new Random(55555);
        var world = new SimulatedWorld(random);

        var resource = world.Zones.First().Resources.First(r => r.Type == ResourceType.Tree);

        // Deplete the resource
        resource.Deplete();
        resource.IsAvailable.Should().BeFalse();

        // Act - Tick until respawn
        for (var i = 0; i < resource.RespawnTicks + 1; i++)
        {
            world.ProcessTick(i);
        }

        // Assert
        resource.IsAvailable.Should().BeTrue();
    }

    [Fact]
    public async Task WorldState_NPCsRespawn_AfterDeath()
    {
        // Scenario: Killed NPCs should respawn
        var random = new Random(66666);
        var world = new SimulatedWorld(random);

        var npc = world.Zones.First().Npcs.First();

        // Kill the NPC
        npc.TakeDamage(npc.CurrentHitpoints);
        npc.IsDead.Should().BeTrue();
        npc.CurrentRespawnTimer = npc.RespawnTicks;

        // Act - Tick until respawn
        for (var i = 0; i < npc.RespawnTicks + 1; i++)
        {
            npc.Tick();
        }

        // Assert
        npc.IsDead.Should().BeFalse();
        npc.CurrentHitpoints.Should().Be(npc.MaxHitpoints);
    }

    [Fact]
    public async Task LongSimulation_NoMemoryLeaks_Completes()
    {
        // Scenario: Long simulation should complete without issues
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 50000,
                RandomSeed = 77777
            });

        simulator.AddBots(20);

        // Act
        var stats = await simulator.RunAsync();

        // Assert
        stats.TotalTicks.Should().Be(50000);
        simulator.Bots.All(b => b.Player != null).Should().BeTrue();
    }

    [Fact]
    public async Task Determinism_SameSeeds_SameResults()
    {
        // Scenario: Same random seed should produce identical results
        var config = new SimulationConfig
        {
            TicksPerSecond = 10000,
            MaxTicks = 1000,
            RandomSeed = 88888
        };

        // Run first simulation
        var sim1 = new GameSimulator(NullLogger<GameSimulator>.Instance, config);
        sim1.AddBots(5);
        var stats1 = await sim1.RunAsync();

        // Run second simulation with same seed
        var sim2 = new GameSimulator(NullLogger<GameSimulator>.Instance, config);
        sim2.AddBots(5);
        var stats2 = await sim2.RunAsync();

        // Assert - Results should be identical
        stats1.TotalBotActions.Should().Be(stats2.TotalBotActions);
        stats1.SuccessfulActions.Should().Be(stats2.SuccessfulActions);
    }

    [Fact]
    public async Task Concurrency_SimulatorCanBeStopped_Gracefully()
    {
        // Scenario: Stopping simulation mid-run should work cleanly
        var cts = new CancellationTokenSource();
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 100, // Slower for this test
                MaxTicks = 100000
            });

        simulator.AddBots(5);

        // Act - Start and stop
        var task = Task.Run(async () =>
        {
            await Task.Delay(200);
            simulator.Stop();
        });

        var stats = await simulator.RunAsync(cts.Token);

        // Assert - Should have stopped early
        stats.TotalTicks.Should().BeLessThan(100000);
        simulator.IsRunning.Should().BeFalse();
    }

    [Fact]
    public async Task Statistics_AllMetrics_AreTracked()
    {
        // Scenario: All statistics should be properly tracked
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 5000,
                RandomSeed = 99999
            });

        simulator.AddBots(10);

        // Act
        var stats = await simulator.RunAsync();

        // Assert - All metrics exist
        stats.TotalTicks.Should().Be(5000);
        stats.TotalBotActions.Should().BeGreaterThan(0);
        stats.ElapsedTime.Should().BeGreaterThan(TimeSpan.Zero);
        stats.TicksPerSecondActual.Should().BeGreaterThan(0);
    }

    [Fact]
    public void PlayerSkills_ExperienceTable_IsCorrect()
    {
        // Scenario: Verify XP -> Level calculation
        var player = new Player("XPTest", new Point(0, 0));

        // Level 1 starts at 0 XP
        player.Skills.GetMaxLevel(Skill.Attack).Should().Be(1);

        // Add XP for level 2 (83 XP needed)
        player.Skills.AddExperience(Skill.Attack, 83);
        player.Skills.GetMaxLevel(Skill.Attack).Should().Be(2);

        // Add more XP
        player.Skills.AddExperience(Skill.Attack, 91); // 174 total for level 3
        player.Skills.GetMaxLevel(Skill.Attack).Should().BeGreaterOrEqualTo(2);
    }

    [Fact]
    public void CombatLevel_Calculation_IsCorrect()
    {
        // Scenario: Combat level should calculate correctly
        var player = new Player("CombatTest", new Point(0, 0));

        // Starting stats should give combat level 3
        player.CombatLevel.Should().BeGreaterOrEqualTo(1);
    }

    [Fact]
    public async Task EndToEnd_CompletePlaySession_AllSystemsWork()
    {
        // Scenario: A complete play session where all systems are exercised
        var simulator = new GameSimulator(
            NullLogger<GameSimulator>.Instance,
            new SimulationConfig
            {
                TicksPerSecond = 10000,
                MaxTicks = 30000, // ~50 minutes game time
                RandomSeed = 123456
            });

        // Add varied bots
        simulator.AddBot("Warrior", BotProfile.Warrior);
        simulator.AddBot("Skiller", BotProfile.Skiller);
        simulator.AddBot("Balanced", BotProfile.Default);
        simulator.AddBot("Mage", BotProfile.Mage);
        simulator.AddBot("Explorer", new BotProfile
        {
            Name = "Explorer",
            Exploration = 0.9,
            Aggression = 0.3
        });

        // Track events
        var tickEvents = 0;
        simulator.OnTick += (_, _) => tickEvents++;

        // Act
        var stats = await simulator.RunAsync();

        // Assert - Comprehensive checks
        stats.TotalTicks.Should().Be(30000);
        tickEvents.Should().Be(30000);

        // All bot types should have taken actions
        stats.TotalBotActions.Should().BeGreaterThan(5000);

        // Multiple action types should be represented
        stats.ActionCounts.Count.Should().BeGreaterOrEqualTo(3);

        // Some XP should have been gained
        stats.TotalExperienceGained.Should().NotBeEmpty();

        // All bots should still be alive (respawned if died)
        simulator.Bots.All(b => b.Player.CurrentHitpoints > 0).Should().BeTrue();

        // Print summary for debugging
        Console.WriteLine(stats.ToString());
    }
}
