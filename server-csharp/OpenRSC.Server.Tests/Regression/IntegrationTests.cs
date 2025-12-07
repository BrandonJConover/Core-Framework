using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Inventory;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;
using OpenRSC.Server.Prayer;
using OpenRSC.Server.Skills;
using OpenRSC.Server.World;
using Xunit;

namespace OpenRSC.Server.Tests.Regression;

/// <summary>
/// Integration tests that verify multiple systems work together correctly.
/// These tests catch regressions from changes affecting system interactions.
/// </summary>
public class IntegrationTests
{
    #region Combat + Skills Integration

    [Fact]
    public void Combat_DealingDamage_GrantsXpToAllRelevantSkills()
    {
        var player = new Player("Test", new Point(0, 0));
        var initialAttackXp = player.Skills.GetExperience(Skill.Attack);
        var initialHpXp = player.Skills.GetExperience(Skill.Hitpoints);

        // Simulate combat XP distribution
        var damage = 10;
        var (attackXp, _, _, hpXp) = Combat.CombatFormulas.CalculateMeleeXpGain(damage, Combat.CombatStyle.Accurate);
        player.Skills.AddExperience(Skill.Attack, attackXp);
        player.Skills.AddExperience(Skill.Hitpoints, hpXp);

        player.Skills.GetExperience(Skill.Attack).Should().BeGreaterThan(initialAttackXp);
        player.Skills.GetExperience(Skill.Hitpoints).Should().BeGreaterThan(initialHpXp);
    }

    [Fact]
    public void Combat_TakingDamage_ReducesHitpointsButNotMaxLevel()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Hitpoints, 50, 100000);
        player.CurrentHitpoints = 50;

        player.ApplyDamage(20, null);

        player.CurrentHitpoints.Should().Be(30);
        player.Skills.GetMaxLevel(Skill.Hitpoints).Should().Be(50);
    }

    #endregion

    #region Prayer + Combat Integration

    [Fact]
    public void Prayer_StrengthBoost_AffectsCombatCalculations()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Strength, 50, 100000);
        player.Skills.SetLevel(Skill.Prayer, 40, 50000);

        var noPrayerMultiplier = player.Prayers.GetStrengthMultiplier();
        noPrayerMultiplier.Should().Be(1.0);

        player.Prayers.Activate(PrayerType.UltimateStrength);

        var withPrayerMultiplier = player.Prayers.GetStrengthMultiplier();
        withPrayerMultiplier.Should().BeGreaterThan(1.0);
    }

    [Fact]
    public void Prayer_ItemsKeptOnDeath_ChangesWithSkull()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Prayer, 30, 30000);

        var normalKept = player.Prayers.ItemsKeptOnDeath;
        normalKept.Should().Be(3);

        player.IsSkulled = true;
        var skulledKept = player.Prayers.ItemsKeptOnDeath;
        skulledKept.Should().Be(0);

        player.Prayers.Activate(PrayerType.ProtectItems);
        var skulledWithProtect = player.Prayers.ItemsKeptOnDeath;
        skulledWithProtect.Should().Be(1);
    }

    #endregion

    #region Inventory + Equipment Integration

    [Fact]
    public void Equipment_Unequip_ReturnsItemToInventory()
    {
        var player = new Player("Test", new Point(0, 0));

        // Create an equippable item
        var def = new ItemDefinition
        {
            Id = 100,
            Name = "Bronze Sword",
            EquipmentSlot = EquipmentSlot.WeaponRight,
            IsWearable = true,
            BasePrice = 100
        };
        var item = new Item(def);

        // Equip it
        player.Equipment.Equip(item, player.Inventory);

        // Verify equipped
        player.Equipment.HasItemInSlot(EquipmentSlot.WeaponRight).Should().BeTrue();

        // Unequip
        player.Equipment.Unequip(EquipmentSlot.WeaponRight, player.Inventory);

        // Verify in inventory
        player.Equipment.HasItemInSlot(EquipmentSlot.WeaponRight).Should().BeFalse();
        player.Inventory.HasItem(100).Should().BeTrue();
    }

    #endregion

    #region Skills + Fatigue Integration

    [Fact]
    public void Skills_XpGain_IncreasesFatigue()
    {
        var player = new Player("Test", new Point(0, 0));
        var initialFatigue = player.Fatigue.Current;

        // Use the extension method that adds fatigue
        player.Skills.AddExperienceWithFatigue(Skill.Attack, 100, player.Fatigue);

        player.Fatigue.Current.Should().BeGreaterThan(initialFatigue);
    }

    [Fact]
    public void Skills_WhenExhausted_NoXpGained()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Fatigue.SetFatigue(Fatigue.PlayerFatigue.MaxFatigue);
        var initialXp = player.Skills.GetExperience(Skill.Attack);

        var gained = player.Skills.AddExperienceWithFatigue(Skill.Attack, 100, player.Fatigue);

        gained.Should().Be(0);
        player.Skills.GetExperience(Skill.Attack).Should().Be(initialXp);
    }

    #endregion

    #region Movement + World Integration

    [Fact]
    public void Player_Movement_UpdatesRegion()
    {
        var worldMap = new WorldMap(NullLogger<WorldMap>.Instance);
        var player = new Player("Test", new Point(10, 10));

        // Add to initial region
        worldMap.UpdatePlayerRegion(player, null);
        var initialRegion = worldMap.GetRegion(player.Location);
        initialRegion.Players.Should().Contain(player);

        // Move to different region
        var oldLocation = player.Location;
        player.Location = new Point(100, 100);
        worldMap.UpdatePlayerRegion(player, oldLocation);

        var newRegion = worldMap.GetRegion(player.Location);
        newRegion.Players.Should().Contain(player);

        // Verify removed from old region if different
        if (initialRegion.RegionId != newRegion.RegionId)
        {
            initialRegion.Players.Should().NotContain(player);
        }
    }

    #endregion

    #region Complete Player Workflow Tests

    [Fact]
    public void PlayerWorkflow_Login_GainXp_Logout()
    {
        var player = new Player("Test", new Point(100, 100));

        // Login
        player.Login();
        player.IsLoggedIn.Should().BeTrue();

        // Train a skill
        var initialLevel = player.Skills.GetMaxLevel(Skill.Attack);
        player.Skills.AddExperience(Skill.Attack, 10000);
        player.Skills.GetMaxLevel(Skill.Attack).Should().BeGreaterThan(initialLevel);

        // Logout
        player.Logout();
        player.IsLoggedIn.Should().BeFalse();

        // State should persist
        player.Skills.GetMaxLevel(Skill.Attack).Should().BeGreaterThan(initialLevel);
    }

    [Fact]
    public void PlayerWorkflow_Combat_Death_Respawn()
    {
        var player = new Player("Test", new Point(100, 100));
        player.Skills.SetLevel(Skill.Hitpoints, 50, 100000);
        player.CurrentHitpoints = 50;
        player.MaxHitpoints = 50;

        var npc = new Npc(1, new Point(101, 100));

        // Enter combat
        player.StartCombat(npc);
        player.InCombat.Should().BeTrue();

        // Take fatal damage
        player.ApplyDamage(50, npc);
        player.CurrentHitpoints.Should().Be(0);

        // End combat on death
        player.EndCombat();
        player.InCombat.Should().BeFalse();

        // Respawn (simulated)
        player.CurrentHitpoints = player.Skills.GetMaxLevel(Skill.Hitpoints);
        player.CurrentHitpoints.Should().Be(50);
    }

    [Fact]
    public void PlayerWorkflow_AddItems_TradeAway_InventoryEmpty()
    {
        var player = new Player("Test", new Point(0, 0));
        var def = new ItemDefinition { Id = 1, Name = "Test Item", BasePrice = 100 };

        // Add items
        player.Inventory.Add(new Item(def));
        player.Inventory.Add(new Item(def));
        player.Inventory.HasItem(1).Should().BeTrue();
        player.Inventory.CountOf(1).Should().Be(2);

        // Remove items (trade simulation)
        player.Inventory.Remove(1, 2);

        player.Inventory.HasItem(1).Should().BeFalse();
        player.Inventory.FreeSlots.Should().Be(30);
    }

    #endregion

    #region Edge Cases

    [Fact]
    public void EdgeCase_MaxLevelPlayer_CanStillPlay()
    {
        var player = new Player("Test", new Point(0, 0));

        // Max out all skills
        foreach (Skill skill in Enum.GetValues<Skill>())
        {
            player.Skills.SetLevel(skill, 99, 13034431);
        }

        // Player should still function
        player.Skills.GetTotalLevel().Should().Be(99 * Enum.GetValues<Skill>().Length);
        player.CurrentHitpoints = 99;
        player.ApplyDamage(10, null);
        player.CurrentHitpoints.Should().Be(89);
    }

    [Fact]
    public void EdgeCase_EmptyInventory_AllOperationsWork()
    {
        var player = new Player("Test", new Point(0, 0));

        // All operations on empty inventory should handle gracefully
        player.Inventory.HasItem(1).Should().BeFalse();
        player.Inventory.CountOf(1).Should().Be(0);
        player.Inventory.GetSlot(0).Should().BeNull();
        player.Inventory.Remove(0).Should().BeNull();
        player.Inventory.Remove(1, 1).Should().BeFalse();
    }

    [Fact]
    public void EdgeCase_ZeroHitpoints_NoNegativeHealth()
    {
        var player = new Player("Test", new Point(0, 0));
        player.CurrentHitpoints = 10;

        player.ApplyDamage(100, null);

        player.CurrentHitpoints.Should().Be(0);
        player.CurrentHitpoints.Should().BeGreaterOrEqualTo(0);
    }

    [Fact]
    public void EdgeCase_MultipleSystemsUpdating_NoConflicts()
    {
        var player = new Player("Test", new Point(0, 0));
        player.Skills.SetLevel(Skill.Prayer, 40, 50000);

        // Activate prayers
        player.Prayers.Activate(PrayerType.ThickSkin);
        player.Prayers.Activate(PrayerType.BurstOfStrength);

        // Take damage during prayer
        player.CurrentHitpoints = 50;
        player.ApplyDamage(10, null);

        // Update tick
        player.ResetAfterUpdate();

        // Everything should still work
        player.CurrentHitpoints.Should().Be(40);
        player.Prayers.HasActivePrayers.Should().BeTrue();
    }

    #endregion
}
