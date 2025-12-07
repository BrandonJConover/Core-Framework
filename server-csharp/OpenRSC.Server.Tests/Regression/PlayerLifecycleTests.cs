using FluentAssertions;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;
using Xunit;

namespace OpenRSC.Server.Tests.Regression;

/// <summary>
/// Regression tests for player lifecycle operations.
/// These tests ensure core player functionality remains stable across updates.
/// </summary>
public class PlayerLifecycleTests
{
    #region Player Creation

    [Fact]
    public void Player_Creation_InitializesAllSystems()
    {
        // Arrange & Act
        var player = new Player("TestPlayer", new Point(100, 100));

        // Assert - All systems should be initialized
        player.Username.Should().Be("TestPlayer");
        player.UsernameHash.Should().NotBe(0);
        player.Location.Should().Be(new Point(100, 100));
        player.Skills.Should().NotBeNull();
        player.Inventory.Should().NotBeNull();
        player.Bank.Should().NotBeNull();
        player.Equipment.Should().NotBeNull();
        player.Prayers.Should().NotBeNull();
        player.Fatigue.Should().NotBeNull();
        player.WalkingQueue.Should().NotBeNull();
        player.PrivacySettings.Should().NotBeNull();
    }

    [Fact]
    public void Player_Creation_HasDefaultSkillLevels()
    {
        // Arrange & Act
        var player = new Player("TestPlayer", new Point(0, 0));

        // Assert - All skills should start at level 1 except Hitpoints at 10
        player.Skills.GetCurrentLevel(Skill.Attack).Should().Be(1);
        player.Skills.GetCurrentLevel(Skill.Defense).Should().Be(1);
        player.Skills.GetCurrentLevel(Skill.Strength).Should().Be(1);
        player.Skills.GetCurrentLevel(Skill.Hits).Should().Be(10);
        player.Skills.GetCurrentLevel(Skill.Prayer).Should().Be(1);
        player.Skills.GetCurrentLevel(Skill.Magic).Should().Be(1);
        player.Skills.GetCurrentLevel(Skill.Cooking).Should().Be(1);
        player.Skills.GetCurrentLevel(Skill.Fishing).Should().Be(1);
        player.Skills.GetCurrentLevel(Skill.Mining).Should().Be(1);
        player.Skills.GetCurrentLevel(Skill.Smithing).Should().Be(1);
    }

    [Fact]
    public void Player_Creation_HasEmptyInventory()
    {
        var player = new Player("TestPlayer", new Point(0, 0));

        player.Inventory.FreeSlots.Should().Be(30);
        player.Inventory.IsFull.Should().BeFalse();
    }

    [Fact]
    public void Player_Creation_HasNoFatigue()
    {
        var player = new Player("TestPlayer", new Point(0, 0));

        player.Fatigue.Current.Should().Be(0);
        player.Fatigue.IsExhausted.Should().BeFalse();
    }

    [Fact]
    public void Player_Creation_IsNotInCombat()
    {
        var player = new Player("TestPlayer", new Point(0, 0));

        player.InCombat.Should().BeFalse();
        player.CombatTarget.Should().BeNull();
    }

    [Fact]
    public void Player_Creation_IsNotSkulled()
    {
        var player = new Player("TestPlayer", new Point(0, 0));

        player.IsSkulled.Should().BeFalse();
        player.SkullExpiry.Should().BeNull();
    }

    #endregion

    #region Login/Logout

    [Fact]
    public void Player_Login_SetsLoggedInState()
    {
        var player = new Player("TestPlayer", new Point(0, 0));

        player.Login();

        player.IsLoggedIn.Should().BeTrue();
        player.LastActivity.Should().BeCloseTo(DateTime.UtcNow, TimeSpan.FromSeconds(1));
    }

    [Fact]
    public void Player_Logout_ClearsLoggedInState()
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        player.Login();

        player.Logout();

        player.IsLoggedIn.Should().BeFalse();
    }

    [Fact]
    public void Player_MultipleLogins_DoNotCorruptState()
    {
        var player = new Player("TestPlayer", new Point(0, 0));

        player.Login();
        player.Login();
        player.Login();

        player.IsLoggedIn.Should().BeTrue();
    }

    #endregion

    #region Username Hashing

    [Fact]
    public void Player_UsernameHash_IsConsistent()
    {
        var player1 = new Player("TestPlayer", new Point(0, 0));
        var player2 = new Player("TestPlayer", new Point(100, 100));

        player1.UsernameHash.Should().Be(player2.UsernameHash);
    }

    [Fact]
    public void Player_UsernameHash_IsCaseInsensitive()
    {
        var player1 = new Player("TestPlayer", new Point(0, 0));
        var player2 = new Player("testplayer", new Point(0, 0));
        var player3 = new Player("TESTPLAYER", new Point(0, 0));

        player1.UsernameHash.Should().Be(player2.UsernameHash);
        player2.UsernameHash.Should().Be(player3.UsernameHash);
    }

    [Fact]
    public void Player_UsernameHash_DifferentNamesHaveDifferentHashes()
    {
        var player1 = new Player("Player1", new Point(0, 0));
        var player2 = new Player("Player2", new Point(0, 0));

        player1.UsernameHash.Should().NotBe(player2.UsernameHash);
    }

    #endregion

    #region State Reset

    [Fact]
    public void Player_ResetAfterUpdate_ClearsMovementFlag()
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        player.HasMoved = true;

        player.ResetAfterUpdate();

        player.HasMoved.Should().BeFalse();
    }

    [Fact]
    public void Player_ResetAfterUpdate_UpdatesSkullExpiry()
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        player.ApplySkull(TimeSpan.FromMilliseconds(1));
        Thread.Sleep(10);

        player.ResetAfterUpdate();

        player.IsSkulled.Should().BeFalse();
    }

    #endregion
}
