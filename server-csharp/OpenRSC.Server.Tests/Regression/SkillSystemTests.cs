using FluentAssertions;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;
using Xunit;

namespace OpenRSC.Server.Tests.Regression;

/// <summary>
/// Regression tests for the skill system.
/// These tests ensure XP and leveling mechanics remain consistent.
/// </summary>
public class SkillSystemTests
{
    #region XP to Level Conversion

    [Theory]
    [InlineData(0, 1)]
    [InlineData(82, 1)]
    [InlineData(83, 2)]
    [InlineData(174, 2)]
    [InlineData(175, 3)]
    [InlineData(13034430, 98)]
    [InlineData(13034431, 99)]
    public void XpToLevel_CalculatesCorrectly(int xp, int expectedLevel)
    {
        var player = new Player("Test", new Point(0, 0));

        player.Skills.SetLevel(Skill.Attack, 1, xp);

        player.Skills.GetMaxLevel(Skill.Attack).Should().Be(expectedLevel);
    }

    [Fact]
    public void XpToLevel_CapsAt99()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Skills.SetLevel(Skill.Attack, 1, 200_000_000);

        player.Skills.GetMaxLevel(Skill.Attack).Should().Be(99);
    }

    [Fact]
    public void XpToLevel_NeverBelowOne()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Skills.SetLevel(Skill.Attack, 1, -1000);

        player.Skills.GetMaxLevel(Skill.Attack).Should().BeGreaterOrEqualTo(1);
    }

    #endregion

    #region Adding Experience

    [Fact]
    public void AddExperience_IncreasesXp()
    {
        var player = new Player("Test", new Point(0, 0));
        var initialXp = player.Skills.GetExperience(Skill.Attack);

        player.Skills.AddExperience(Skill.Attack, 100);

        player.Skills.GetExperience(Skill.Attack).Should().Be(initialXp + 100);
    }

    [Fact]
    public void AddExperience_TriggersLevelUp()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Skills.AddExperience(Skill.Attack, 100);

        player.Skills.GetMaxLevel(Skill.Attack).Should().Be(2);
    }

    [Fact]
    public void AddExperience_UpdatesCurrentLevel()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Skills.AddExperience(Skill.Attack, 100);

        player.Skills.GetCurrentLevel(Skill.Attack).Should().Be(2);
    }

    [Fact]
    public void AddExperience_ReturnsActualXpGained()
    {
        var player = new Player("Test", new Point(0, 0));

        var gained = player.Skills.AddExperience(Skill.Attack, 100);

        gained.Should().Be(100);
    }

    [Fact]
    public void AddExperience_CapsAtMaxXp()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Attack, 99, 200_000_000);

        var gained = player.Skills.AddExperience(Skill.Attack, 100);

        gained.Should().Be(0);
    }

    [Fact]
    public void AddExperience_WithMultiplier_AppliesCorrectly()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Skills.AddExperience(Skill.Attack, 100, multiplier: 2.0);

        player.Skills.GetExperience(Skill.Attack).Should().Be(200);
    }

    #endregion

    #region Current vs Max Level

    [Fact]
    public void CurrentLevel_CanBeBoosted()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Attack, 50, 100000);

        player.Skills.BoostLevel(Skill.Attack, 5);

        player.Skills.GetCurrentLevel(Skill.Attack).Should().Be(55);
        player.Skills.GetMaxLevel(Skill.Attack).Should().Be(50);
    }

    [Fact]
    public void CurrentLevel_CanBeDrained()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Attack, 50, 100000);

        player.Skills.DrainLevel(Skill.Attack, 10);

        player.Skills.GetCurrentLevel(Skill.Attack).Should().Be(40);
        player.Skills.GetMaxLevel(Skill.Attack).Should().Be(50);
    }

    [Fact]
    public void CurrentLevel_DrainDoesNotGoBelowZero()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Attack, 10, 1000);

        player.Skills.DrainLevel(Skill.Attack, 100);

        player.Skills.GetCurrentLevel(Skill.Attack).Should().Be(0);
    }

    [Fact]
    public void RestoreToMax_RestoresCurrentToMax()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Attack, 50, 100000);
        player.Skills.DrainLevel(Skill.Attack, 20);

        player.Skills.RestoreToMax(Skill.Attack);

        player.Skills.GetCurrentLevel(Skill.Attack).Should().Be(50);
    }

    #endregion

    #region Total Level

    [Fact]
    public void TotalLevel_SumsAllSkills()
    {
        var player = new Player("Test", new Point(0, 0));

        // Default skills: Most at 1, Hitpoints at 10
        var totalLevel = player.Skills.GetTotalLevel();

        totalLevel.Should().BeGreaterOrEqualTo(18); // Minimum with default skills
    }

    [Fact]
    public void TotalLevel_UpdatesOnLevelUp()
    {
        var player = new Player("Test", new Point(0, 0));
        var initialTotal = player.Skills.GetTotalLevel();

        player.Skills.AddExperience(Skill.Attack, 1000);

        player.Skills.GetTotalLevel().Should().BeGreaterThan(initialTotal);
    }

    #endregion

    #region Hitpoints Special Case

    [Fact]
    public void Hitpoints_StartsAt10()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Skills.GetMaxLevel(Skill.Hitpoints).Should().Be(10);
        player.Skills.GetCurrentLevel(Skill.Hitpoints).Should().Be(10);
    }

    [Fact]
    public void Hitpoints_LevelUpIncreasesMax()
    {
        var player = new Player("Test", new Point(0, 0));

        player.Skills.AddExperience(Skill.Hitpoints, 1200); // Enough for level 11

        player.Skills.GetMaxLevel(Skill.Hitpoints).Should().Be(11);
    }

    #endregion

    #region All Skills Iteration

    [Fact]
    public void AllSkills_CanBeIterated()
    {
        var player = new Player("Test", new Point(0, 0));

        foreach (Skill skill in Enum.GetValues<Skill>())
        {
            var level = player.Skills.GetMaxLevel(skill);
            level.Should().BeGreaterOrEqualTo(1);
        }
    }

    [Fact]
    public void AllSkills_CanGainXp()
    {
        var player = new Player("Test", new Point(0, 0));

        foreach (Skill skill in Enum.GetValues<Skill>())
        {
            var initialXp = player.Skills.GetExperience(skill);
            player.Skills.AddExperience(skill, 10);
            player.Skills.GetExperience(skill).Should().Be(initialXp + 10);
        }
    }

    #endregion
}
