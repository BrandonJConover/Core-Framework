using FluentAssertions;
using OpenRSC.Server.Combat;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Npc;
using OpenRSC.Server.Skills;
using Xunit;

namespace OpenRSC.Server.Tests.Regression;

/// <summary>
/// Regression tests for the combat system.
/// These tests ensure combat mechanics remain consistent across updates.
/// </summary>
public class CombatSystemTests
{
    #region Combat Level Calculation

    [Theory]
    [InlineData(1, 1, 1, 10, 1, 3)] // Level 1 stats
    [InlineData(99, 99, 99, 99, 99, 123)] // Max melee
    [InlineData(40, 40, 40, 40, 40, 50)] // Mid-level
    public void CombatLevel_CalculatesCorrectly(
        int attack, int strength, int defense, int hitpoints, int prayer, int expectedLevel)
    {
        var player = CreatePlayerWithStats(attack, strength, defense, hitpoints, prayer);

        var combatLevel = CombatFormulas.CalculateCombatLevel(player.Skills);

        combatLevel.Should().BeInRange(expectedLevel - 2, expectedLevel + 2);
    }

    [Fact]
    public void CombatLevel_NeverExceeds126()
    {
        var player = CreatePlayerWithStats(99, 99, 99, 99, 99);
        player.Skills.SetLevel(Skill.Ranged, 99, 0);
        player.Skills.SetLevel(Skill.Magic, 99, 0);

        var combatLevel = CombatFormulas.CalculateCombatLevel(player.Skills);

        combatLevel.Should().BeLessOrEqualTo(126);
    }

    [Fact]
    public void CombatLevel_IsAtLeast3()
    {
        var player = CreatePlayerWithStats(1, 1, 1, 1, 1);

        var combatLevel = CombatFormulas.CalculateCombatLevel(player.Skills);

        combatLevel.Should().BeGreaterOrEqualTo(3);
    }

    #endregion

    #region Max Hit Calculation

    [Fact]
    public void MaxHit_IncreasesWithStrength()
    {
        var lowStr = CreatePlayerWithStats(50, 20, 50, 50, 1);
        var highStr = CreatePlayerWithStats(50, 80, 50, 50, 1);
        var bonuses = new CombatBonuses(StrengthBonus: 50);

        var lowHit = CombatFormulas.CalculateMaxMeleeHit(lowStr.Skills, CombatStyle.Aggressive, bonuses);
        var highHit = CombatFormulas.CalculateMaxMeleeHit(highStr.Skills, CombatStyle.Aggressive, bonuses);

        highHit.Should().BeGreaterThan(lowHit);
    }

    [Fact]
    public void MaxHit_IncreasesWithStrengthBonus()
    {
        var player = CreatePlayerWithStats(50, 50, 50, 50, 1);
        var lowBonus = new CombatBonuses(StrengthBonus: 10);
        var highBonus = new CombatBonuses(StrengthBonus: 100);

        var lowHit = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Aggressive, lowBonus);
        var highHit = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Aggressive, highBonus);

        highHit.Should().BeGreaterThan(lowHit);
    }

    [Fact]
    public void MaxHit_AggressiveStyleIsHighest()
    {
        var player = CreatePlayerWithStats(50, 50, 50, 50, 1);
        var bonuses = new CombatBonuses(StrengthBonus: 50);

        var aggressive = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Aggressive, bonuses);
        var accurate = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Accurate, bonuses);
        var defensive = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Defensive, bonuses);
        var controlled = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Controlled, bonuses);

        aggressive.Should().BeGreaterOrEqualTo(accurate);
        aggressive.Should().BeGreaterOrEqualTo(defensive);
        aggressive.Should().BeGreaterOrEqualTo(controlled);
    }

    [Fact]
    public void MaxHit_NeverNegative()
    {
        var player = CreatePlayerWithStats(1, 1, 1, 10, 1);
        var bonuses = CombatBonuses.None;

        var maxHit = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Accurate, bonuses);

        maxHit.Should().BeGreaterOrEqualTo(0);
    }

    #endregion

    #region Combat State

    [Fact]
    public void Combat_StartCombat_SetsInCombatState()
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        var npc = CreateNpc();

        player.StartCombat(npc);

        player.InCombat.Should().BeTrue();
        player.CombatTarget.Should().Be(npc);
    }

    [Fact]
    public void Combat_EndCombat_ClearsCombatState()
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        var npc = CreateNpc();
        player.StartCombat(npc);

        player.EndCombat();

        player.InCombat.Should().BeFalse();
        player.CombatTarget.Should().BeNull();
    }

    [Fact]
    public void Combat_ApplyDamage_ReducesHitpoints()
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        player.CurrentHitpoints = 50;
        player.MaxHitpoints = 50;

        player.ApplyDamage(10, null);

        player.CurrentHitpoints.Should().Be(40);
    }

    [Fact]
    public void Combat_ApplyDamage_DoesNotGoBelowZero()
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        player.CurrentHitpoints = 5;

        player.ApplyDamage(100, null);

        player.CurrentHitpoints.Should().Be(0);
    }

    #endregion

    #region XP Distribution

    [Fact]
    public void CombatXp_HitpointsXpAlwaysGranted()
    {
        var (_, _, _, hitpointsXp) = CombatFormulas.CalculateMeleeXpGain(10, CombatStyle.Accurate);

        hitpointsXp.Should().BePositive();
    }

    [Theory]
    [InlineData(CombatStyle.Accurate)]
    [InlineData(CombatStyle.Aggressive)]
    [InlineData(CombatStyle.Defensive)]
    [InlineData(CombatStyle.Controlled)]
    public void CombatXp_AllStylesGrantXp(CombatStyle style)
    {
        var (attackXp, strengthXp, defenseXp, hitpointsXp) = CombatFormulas.CalculateMeleeXpGain(10, style);

        var totalCombatXp = attackXp + strengthXp + defenseXp;
        totalCombatXp.Should().BePositive();
        hitpointsXp.Should().BePositive();
    }

    [Fact]
    public void CombatXp_ZeroDamage_NoXp()
    {
        var (attackXp, strengthXp, defenseXp, hitpointsXp) = CombatFormulas.CalculateMeleeXpGain(0, CombatStyle.Accurate);

        attackXp.Should().Be(0);
        strengthXp.Should().Be(0);
        defenseXp.Should().Be(0);
        hitpointsXp.Should().Be(0);
    }

    #endregion

    #region Hit Results

    [Fact]
    public void HitResult_Miss_HasZeroDamage()
    {
        var miss = HitResult.Miss;

        miss.Hit.Should().BeFalse();
        miss.Damage.Should().Be(0);
    }

    [Fact]
    public void HitResult_Hit_PreservesDamage()
    {
        var hit = new HitResult(true, 15, DamageType.Melee);

        hit.Hit.Should().BeTrue();
        hit.Damage.Should().Be(15);
        hit.DamageType.Should().Be(DamageType.Melee);
    }

    #endregion

    #region Helper Methods

    private static Player CreatePlayerWithStats(int attack, int strength, int defense, int hitpoints, int prayer)
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        player.Skills.SetLevel(Skill.Attack, attack, 0);
        player.Skills.SetLevel(Skill.Strength, strength, 0);
        player.Skills.SetLevel(Skill.Defense, defense, 0);
        player.Skills.SetLevel(Skill.Hitpoints, hitpoints, 0);
        player.Skills.SetLevel(Skill.Prayer, prayer, 0);
        player.CurrentHitpoints = hitpoints;
        return player;
    }

    private static Npc CreateNpc()
    {
        return new Npc(1, new Point(1, 1));
    }

    #endregion
}
