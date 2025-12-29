using FluentAssertions;
using Moq;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Inventory;
using OpenRSC.Server.Models;
using OpenRSC.Server.Prayer;
using OpenRSC.Server.Skills;
using Xunit;

namespace OpenRSC.Server.Tests;

public class PrayerTests
{
    private Player CreatePlayer(int prayerLevel = 99)
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        // Set prayer level
        player.Skills.SetLevel(Skill.Prayer, prayerLevel, GetExperienceForLevel(prayerLevel));
        return player;
    }

    private static int GetExperienceForLevel(int level)
    {
        // RSC experience formula approximation
        var total = 0;
        for (var i = 1; i < level; i++)
        {
            total += (int)(i + 300 * Math.Pow(2, i / 7.0));
        }
        return total / 4;
    }

    [Fact]
    public void Activate_ValidPrayer_Succeeds()
    {
        var player = CreatePlayer(10);
        var prayers = new PlayerPrayers(player);

        var result = prayers.Activate(PrayerType.ThickSkin);

        result.Success.Should().BeTrue();
        prayers.IsActive(PrayerType.ThickSkin).Should().BeTrue();
    }

    [Fact]
    public void Activate_InsufficientLevel_Fails()
    {
        var player = CreatePlayer(5);
        var prayers = new PlayerPrayers(player);

        var result = prayers.Activate(PrayerType.RockSkin); // Requires 10

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("level 10");
    }

    [Fact]
    public void Activate_ConflictingPrayer_DeactivatesOld()
    {
        var player = CreatePlayer(30);
        var prayers = new PlayerPrayers(player);

        prayers.Activate(PrayerType.ThickSkin);
        prayers.Activate(PrayerType.RockSkin);

        prayers.IsActive(PrayerType.ThickSkin).Should().BeFalse();
        prayers.IsActive(PrayerType.RockSkin).Should().BeTrue();
    }

    [Fact]
    public void Deactivate_ActivePrayer_Succeeds()
    {
        var player = CreatePlayer(10);
        var prayers = new PlayerPrayers(player);
        prayers.Activate(PrayerType.ThickSkin);

        prayers.Deactivate(PrayerType.ThickSkin);

        prayers.IsActive(PrayerType.ThickSkin).Should().BeFalse();
    }

    [Fact]
    public void Toggle_Toggles()
    {
        var player = CreatePlayer(10);
        var prayers = new PlayerPrayers(player);

        prayers.Toggle(PrayerType.ThickSkin);
        prayers.IsActive(PrayerType.ThickSkin).Should().BeTrue();

        prayers.Toggle(PrayerType.ThickSkin);
        prayers.IsActive(PrayerType.ThickSkin).Should().BeFalse();
    }

    [Fact]
    public void DeactivateAll_DeactivatesAllPrayers()
    {
        var player = CreatePlayer(40);
        var prayers = new PlayerPrayers(player);
        prayers.Activate(PrayerType.ThickSkin);
        prayers.Activate(PrayerType.BurstOfStrength);
        prayers.Activate(PrayerType.RapidHeal);

        prayers.DeactivateAll();

        prayers.HasActivePrayers.Should().BeFalse();
    }

    [Fact]
    public void GetStrengthMultiplier_WithUltimateStrength_Returns115Percent()
    {
        var player = CreatePlayer(35);
        var prayers = new PlayerPrayers(player);
        prayers.Activate(PrayerType.UltimateStrength);

        var multiplier = prayers.GetStrengthMultiplier();

        multiplier.Should().BeApproximately(1.15, 0.01);
    }

    [Fact]
    public void GetDefenseMultiplier_WithSteelSkin_Returns115Percent()
    {
        var player = CreatePlayer(30);
        var prayers = new PlayerPrayers(player);
        prayers.Activate(PrayerType.SteelSkin);

        var multiplier = prayers.GetDefenseMultiplier();

        multiplier.Should().BeApproximately(1.15, 0.01);
    }

    [Fact]
    public void DrainPoints_ReducesPoints()
    {
        var player = CreatePlayer(50);
        var prayers = new PlayerPrayers(player);

        prayers.DrainPoints(10);

        prayers.CurrentPoints.Should().Be(40);
    }

    [Fact]
    public void DrainPoints_ToZero_DeactivatesAllPrayers()
    {
        var player = CreatePlayer(10);
        var prayers = new PlayerPrayers(player);
        prayers.Activate(PrayerType.ThickSkin);

        prayers.DrainPoints(100);

        prayers.CurrentPoints.Should().Be(0);
        prayers.HasActivePrayers.Should().BeFalse();
    }

    [Fact]
    public void RestorePoints_IncreasesPoints()
    {
        var player = CreatePlayer(50);
        var prayers = new PlayerPrayers(player);
        prayers.DrainPoints(30);

        prayers.RestorePoints(10);

        prayers.CurrentPoints.Should().Be(30);
    }

    [Fact]
    public void RestorePoints_DoesNotExceedMax()
    {
        var player = CreatePlayer(50);
        var prayers = new PlayerPrayers(player);

        prayers.RestorePoints(100);

        prayers.CurrentPoints.Should().Be(50);
    }

    [Fact]
    public void ItemsKeptOnDeath_Normal_Returns3()
    {
        var player = CreatePlayer(10);
        player.IsSkulled = false;
        var prayers = new PlayerPrayers(player);

        prayers.ItemsKeptOnDeath.Should().Be(3);
    }

    [Fact]
    public void ItemsKeptOnDeath_WithProtectItems_Returns4()
    {
        var player = CreatePlayer(30);
        player.IsSkulled = false;
        var prayers = new PlayerPrayers(player);
        prayers.Activate(PrayerType.ProtectItems);

        prayers.ItemsKeptOnDeath.Should().Be(4);
    }

    [Fact]
    public void ItemsKeptOnDeath_Skulled_Returns0()
    {
        var player = CreatePlayer(10);
        player.IsSkulled = true;
        var prayers = new PlayerPrayers(player);

        prayers.ItemsKeptOnDeath.Should().Be(0);
    }

    [Fact]
    public void ItemsKeptOnDeath_SkulledWithProtect_Returns1()
    {
        var player = CreatePlayer(30);
        player.IsSkulled = true;
        var prayers = new PlayerPrayers(player);
        prayers.Activate(PrayerType.ProtectItems);

        prayers.ItemsKeptOnDeath.Should().Be(1);
    }
}
