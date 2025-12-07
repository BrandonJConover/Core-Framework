using FluentAssertions;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Fatigue;
using OpenRSC.Server.Models;
using Xunit;

namespace OpenRSC.Server.Tests;

public class FatigueTests
{
    private Player CreatePlayer() => new("TestPlayer", new Point(0, 0));

    [Fact]
    public void AddFatigue_IncreasesFatigue()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);

        fatigue.AddFatigue(100);

        fatigue.Current.Should().Be(400); // 100 XP * 4
    }

    [Fact]
    public void AddFatigue_CapsAtMax()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);

        fatigue.AddFatigue(1_000_000);

        fatigue.Current.Should().Be(PlayerFatigue.MaxFatigue);
        fatigue.IsExhausted.Should().BeTrue();
    }

    [Fact]
    public void Percentage_CalculatesCorrectly()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);

        fatigue.SetFatigue(375_000); // Half of max

        fatigue.Percentage.Should().BeApproximately(50.0, 0.1);
    }

    [Fact]
    public void CanGainXp_NotExhausted_ReturnsTrue()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);

        fatigue.CanGainXp().Should().BeTrue();
    }

    [Fact]
    public void CanGainXp_Exhausted_ReturnsFalse()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);
        fatigue.SetFatigue(PlayerFatigue.MaxFatigue);

        fatigue.CanGainXp().Should().BeFalse();
    }

    [Fact]
    public void StartSleeping_SetsSleepingState()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);
        fatigue.AddFatigue(100);

        var result = fatigue.StartSleeping(isBed: false);

        result.Success.Should().BeTrue();
        fatigue.IsSleeping.Should().BeTrue();
        fatigue.SleepWord.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public void StartSleeping_WhileInCombat_Fails()
    {
        var player = CreatePlayer();
        player.StartCombat(new Npc(1, new Point(1, 1)));
        var fatigue = new PlayerFatigue(player);
        fatigue.AddFatigue(100);

        var result = fatigue.StartSleeping(isBed: false);

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("combat");
    }

    [Fact]
    public void CompleteSleep_CorrectWord_ReducesFatigue()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);
        fatigue.SetFatigue(500_000);
        fatigue.StartSleeping(isBed: false);

        var word = fatigue.SleepWord!;
        var result = fatigue.CompleteSleep(word);

        result.Success.Should().BeTrue();
        fatigue.Current.Should().Be(0);
        fatigue.IsSleeping.Should().BeFalse();
    }

    [Fact]
    public void CompleteSleep_WrongWord_Fails()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);
        fatigue.SetFatigue(500_000);
        fatigue.StartSleeping(isBed: false);

        var result = fatigue.CompleteSleep("wrongword123");

        result.Success.Should().BeFalse();
        fatigue.IsSleeping.Should().BeTrue();
        fatigue.Current.Should().Be(500_000);
    }

    [Fact]
    public void CancelSleep_ClearsSleepingState()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);
        fatigue.AddFatigue(100);
        fatigue.StartSleeping(isBed: false);

        fatigue.CancelSleep();

        fatigue.IsSleeping.Should().BeFalse();
        fatigue.SleepWord.Should().BeNull();
    }

    [Fact]
    public void ReduceFatigue_ReducesByAmount()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);
        fatigue.SetFatigue(500_000);

        fatigue.ReduceFatigue(100_000);

        fatigue.Current.Should().Be(400_000);
    }

    [Fact]
    public void ReduceFatigue_DoesNotGoBelowZero()
    {
        var player = CreatePlayer();
        var fatigue = new PlayerFatigue(player);
        fatigue.SetFatigue(100);

        fatigue.ReduceFatigue(1000);

        fatigue.Current.Should().Be(0);
    }
}
