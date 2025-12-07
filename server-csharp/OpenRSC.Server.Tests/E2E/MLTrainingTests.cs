using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using OpenRSC.Server.ML;
using OpenRSC.Server.Simulation;
using Xunit;

namespace OpenRSC.Server.Tests.E2E;

/// <summary>
/// Tests for the ML training system.
/// </summary>
public class MLTrainingTests
{
    [Fact]
    public void QLearningAgent_SelectsAction()
    {
        // Arrange
        var random = new Random(42);
        var agent = new QLearningAgent(random);
        var state = new GameState
        {
            HealthPercent = 0.8,
            InventoryFullness = 0.3,
            FoodCount = 5,
            InCombat = false,
            NearbyEnemyCount = 2,
            NearbyResourceCount = 3,
            IsInWilderness = false,
            NearBank = false,
            CombatLevel = 10,
            TotalLevel = 50,
            PrimarySkillLevel = 15
        };

        // Act
        var action = agent.SelectAction(state, BotProfile.Default);

        // Assert
        action.Should().BeOneOf(
            BotActionType.Idle,
            BotActionType.Attack,
            BotActionType.Gather,
            BotActionType.Bank,
            BotActionType.Eat,
            BotActionType.Train,
            BotActionType.Walk,
            BotActionType.Flee
        );
    }

    [Fact]
    public void QLearningAgent_UpdatesQValues()
    {
        // Arrange
        var random = new Random(42);
        var agent = new QLearningAgent(random);
        var state = new GameState { HealthPercent = 0.5, CombatLevel = 10 };
        var nextState = new GameState { HealthPercent = 0.6, CombatLevel = 10 };

        // Get initial Q-values
        var initialQ = agent.GetQValues(state)[BotActionType.Attack];

        // Act
        agent.Update(state, BotActionType.Attack, 10.0, nextState);

        // Assert
        var newQ = agent.GetQValues(state)[BotActionType.Attack];
        newQ.Should().NotBe(initialQ);
        agent.TotalUpdates.Should().Be(1);
    }

    [Fact]
    public void QLearningAgent_EpsilonDecaysOverTime()
    {
        // Arrange
        var random = new Random(42);
        var agent = new QLearningAgent(random);
        var initialEpsilon = agent.CurrentEpsilon;
        var state = new GameState { HealthPercent = 0.5 };
        var nextState = new GameState { HealthPercent = 0.6 };

        // Act - Multiple updates
        for (var i = 0; i < 1000; i++)
        {
            agent.Update(state, BotActionType.Train, 1.0, nextState);
        }

        // Assert
        agent.CurrentEpsilon.Should().BeLessThan(initialEpsilon);
    }

    [Fact]
    public void QLearningAgent_SaveAndLoad_PreservesState()
    {
        // Arrange
        var random = new Random(42);
        var agent1 = new QLearningAgent(random);
        var state = new GameState { HealthPercent = 0.5, CombatLevel = 20 };
        var nextState = new GameState { HealthPercent = 0.6, CombatLevel = 20 };

        // Train
        for (var i = 0; i < 100; i++)
        {
            agent1.Update(state, BotActionType.Attack, 5.0, nextState);
        }

        var tempPath = Path.GetTempFileName();

        try
        {
            // Act
            agent1.SaveQTable(tempPath);
            var agent2 = new QLearningAgent(random);
            agent2.LoadQTable(tempPath);

            // Assert
            var q1 = agent1.GetQValues(state)[BotActionType.Attack];
            var q2 = agent2.GetQValues(state)[BotActionType.Attack];
            q2.Should().BeApproximately(q1, 0.001);
        }
        finally
        {
            File.Delete(tempPath);
        }
    }

    [Fact]
    public void GameState_ToStateKey_IsDeterministic()
    {
        // Arrange
        var state1 = new GameState
        {
            HealthPercent = 0.75,
            InventoryFullness = 0.5,
            FoodCount = 3,
            InCombat = true,
            NearbyEnemyCount = 2,
            CombatLevel = 25
        };

        var state2 = new GameState
        {
            HealthPercent = 0.75,
            InventoryFullness = 0.5,
            FoodCount = 3,
            InCombat = true,
            NearbyEnemyCount = 2,
            CombatLevel = 25
        };

        // Act
        var key1 = state1.ToStateKey();
        var key2 = state2.ToStateKey();

        // Assert
        key1.Should().Be(key2);
    }

    [Fact]
    public void GameState_DifferentStates_DifferentKeys()
    {
        // Arrange
        var state1 = new GameState { HealthPercent = 0.9, CombatLevel = 10 };
        var state2 = new GameState { HealthPercent = 0.1, CombatLevel = 10 };

        // Act
        var key1 = state1.ToStateKey();
        var key2 = state2.ToStateKey();

        // Assert
        key1.Should().NotBe(key2);
    }

    [Fact]
    public void BotBrain_MakesDecisions()
    {
        // Arrange
        var random = new Random(42);
        var world = new SimulatedWorld(random);
        var player = new SimulatedPlayer("BrainTest", world, random, BotProfile.Default);

        // Act
        var action = player.DecideAction(currentTick: 1);

        // Assert
        action.Should().NotBeNull();
    }

    [Fact]
    public void BotBrain_RespondsToLowHealth()
    {
        // Arrange
        var random = new Random(42);
        var world = new SimulatedWorld(random);
        var player = new SimulatedPlayer("LowHealthBot", world, random, new BotProfile
        {
            Name = "Cautious",
            Caution = 1.0
        });

        // Reduce health
        player.Player.CurrentHitpoints = 1;

        // Act
        var action = player.DecideAction(currentTick: 1);

        // Assert - Should eat or flee when very low health
        action.Should().NotBeNull();
        action!.Type.Should().BeOneOf(BotActionType.Eat, BotActionType.Flee, BotActionType.Idle);
    }

    [Fact]
    public async Task TrainingRunner_CompletesEpisode()
    {
        // Arrange
        var runner = new TrainingRunner(
            NullLogger<TrainingRunner>.Instance,
            new TrainingConfig
            {
                Episodes = 1,
                TicksPerEpisode = 500,
                BotCount = 3,
                RandomSeed = 42,
                TicksPerSecond = 10000
            });

        // Act
        var result = await runner.RunAsync();

        // Assert
        result.TotalEpisodes.Should().Be(1);
        result.Episodes.Should().HaveCount(1);
        result.Episodes[0].Ticks.Should().Be(500);
    }

    [Fact]
    public async Task TrainingRunner_MultipleEpisodes_ShowsProgress()
    {
        // Arrange
        var episodeResults = new List<EpisodeResult>();
        var runner = new TrainingRunner(
            NullLogger<TrainingRunner>.Instance,
            new TrainingConfig
            {
                Episodes = 3,
                TicksPerEpisode = 200,
                BotCount = 2,
                RandomSeed = 123,
                TicksPerSecond = 10000
            });

        runner.OnEpisodeComplete += (_, result) => episodeResults.Add(result);

        // Act
        var finalResult = await runner.RunAsync();

        // Assert
        finalResult.TotalEpisodes.Should().Be(3);
        episodeResults.Should().HaveCount(3);
    }

    [Fact]
    public void ReplayBuffer_StoresExperiences()
    {
        // Arrange
        var random = new Random(42);
        var buffer = new ReplayBuffer(100, random);
        var state = new GameState { HealthPercent = 0.5 };

        // Act
        for (var i = 0; i < 50; i++)
        {
            buffer.Add(new Experience(state, BotActionType.Attack, 1.0, state, false));
        }

        // Assert
        buffer.Count.Should().Be(50);
    }

    [Fact]
    public void ReplayBuffer_Samples_ReturnRequestedCount()
    {
        // Arrange
        var random = new Random(42);
        var buffer = new ReplayBuffer(100, random);
        var state = new GameState { HealthPercent = 0.5 };

        for (var i = 0; i < 50; i++)
        {
            buffer.Add(new Experience(state, BotActionType.Attack, 1.0, state, false));
        }

        // Act
        var samples = buffer.Sample(10);

        // Assert
        samples.Should().HaveCount(10);
    }

    [Fact]
    public void NeuralNetworkAgent_ProducesOutput()
    {
        // Arrange
        var random = new Random(42);
        var agent = new NeuralNetworkAgent(random);
        var state = new GameState
        {
            HealthPercent = 0.8,
            InventoryFullness = 0.3,
            CombatLevel = 15
        };

        // Act
        var action = agent.SelectAction(state);

        // Assert
        action.Should().BeOneOf(
            BotActionType.Idle,
            BotActionType.Attack,
            BotActionType.Gather,
            BotActionType.Bank,
            BotActionType.Eat,
            BotActionType.Train,
            BotActionType.Walk,
            BotActionType.Flee
        );
    }

    [Fact]
    public void NeuralNetworkAgent_StateToInput_CorrectDimensions()
    {
        // Arrange
        var random = new Random(42);
        var agent = new NeuralNetworkAgent(random);
        var state = new GameState { HealthPercent = 0.5, CombatLevel = 10 };

        // Act
        var input = agent.StateToInput(state);

        // Assert
        input.Should().HaveCount(11);
        input.Should().AllSatisfy(v => v.Should().BeInRange(-1, 2)); // Normalized values
    }
}
