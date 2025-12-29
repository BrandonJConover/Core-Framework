using FluentAssertions;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Wilderness;
using Xunit;

namespace OpenRSC.Server.Tests;

public class WildernessTests
{
    [Theory]
    [InlineData(100, 300, false)] // Below wilderness start
    [InlineData(100, 392, true)]  // At wilderness start
    [InlineData(100, 500, true)]  // In wilderness
    [InlineData(10, 500, false)]  // X too low
    [InlineData(400, 500, false)] // X too high
    public void IsInWilderness_ChecksBoundsCorrectly(int x, int y, bool expected)
    {
        var location = new Point(x, y);

        var result = WildernessManager.IsInWilderness(location);

        result.Should().Be(expected);
    }

    [Theory]
    [InlineData(100, 392, 1)]   // Just entered
    [InlineData(100, 397, 1)]   // Still level 1
    [InlineData(100, 398, 2)]   // Level 2
    [InlineData(100, 450, 10)]  // Deeper wilderness
    public void GetWildernessLevel_CalculatesCorrectly(int x, int y, int expectedLevel)
    {
        var location = new Point(x, y);

        var level = WildernessManager.GetWildernessLevel(location);

        level.Should().Be(expectedLevel);
    }

    [Fact]
    public void GetWildernessLevel_OutsideWilderness_ReturnsZero()
    {
        var location = new Point(100, 100);

        var level = WildernessManager.GetWildernessLevel(location);

        level.Should().Be(0);
    }

    [Theory]
    [InlineData(50, 1, 49, 51)]   // Level 1: ±1
    [InlineData(50, 5, 45, 55)]   // Level 5: ±5
    [InlineData(50, 10, 40, 60)]  // Level 10: ±10
    [InlineData(10, 20, 3, 30)]   // Low combat: min clamped to 3
    [InlineData(120, 20, 100, 126)] // High combat: max clamped to 126
    public void GetCombatLevelRange_CalculatesCorrectly(int combatLevel, int wildLevel, int expectedMin, int expectedMax)
    {
        var (min, max) = WildernessManager.GetCombatLevelRange(combatLevel, wildLevel);

        min.Should().Be(expectedMin);
        max.Should().Be(expectedMax);
    }

    [Fact]
    public void CanAttack_OutsideWilderness_Fails()
    {
        var attacker = new Player("Attacker", new Point(100, 100));
        var target = new Player("Target", new Point(100, 100));

        var result = WildernessManager.CanAttack(attacker, target);

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("wilderness");
    }

    [Fact]
    public void CanAttack_SimilarCombatLevels_Succeeds()
    {
        var attacker = new Player("Attacker", new Point(100, 400));
        var target = new Player("Target", new Point(100, 400));

        var result = WildernessManager.CanAttack(attacker, target);

        result.Success.Should().BeTrue();
    }

    [Fact]
    public void GetInfo_ReturnsCorrectInfo()
    {
        var location = new Point(100, 450);

        var info = WildernessManager.GetInfo(location);

        info.InWilderness.Should().BeTrue();
        info.Level.Should().BeGreaterThan(0);
        info.Zone.Should().Be(WildernessZone.SingleCombat);
    }

    [Fact]
    public void TeleportRules_AllowsTeleport_BelowLevel20()
    {
        var location = new Point(100, 400); // Around level 2

        var canTeleport = WildernessTeleportRules.CanTeleport(location);

        canTeleport.Should().BeTrue();
    }

    [Fact]
    public void TeleportRules_BlocksTeleport_AboveLevel20()
    {
        var location = new Point(100, 600); // Deep wilderness

        var canTeleport = WildernessTeleportRules.CanTeleport(location);

        canTeleport.Should().BeFalse();
    }
}
