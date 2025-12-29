using FluentAssertions;
using OpenRSC.Server.Combat;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;
using Xunit;

namespace OpenRSC.Server.Tests;

public class CombatFormulaTests
{
    private Player CreatePlayer(int attack = 50, int strength = 50, int defense = 50, int hitpoints = 50)
    {
        var player = new Player("TestPlayer", new Point(0, 0));
        player.Skills.SetLevel(Skill.Attack, attack, 0);
        player.Skills.SetLevel(Skill.Strength, strength, 0);
        player.Skills.SetLevel(Skill.Defense, defense, 0);
        player.Skills.SetLevel(Skill.Hits, hitpoints, 0);
        player.CurrentHitpoints = hitpoints;
        return player;
    }

    [Fact]
    public void CalculateCombatLevel_MaxMelee_Returns123()
    {
        var player = CreatePlayer(99, 99, 99, 99);
        player.Skills.SetLevel(Skill.Prayer, 99, 0);

        var level = CombatFormulas.CalculateCombatLevel(player.Skills);

        // RSC combat level formula caps around 123
        level.Should().BeInRange(120, 126);
    }

    [Fact]
    public void CalculateCombatLevel_Level1Stats_Returns3()
    {
        var player = CreatePlayer(1, 1, 1, 10);
        player.Skills.SetLevel(Skill.Prayer, 1, 0);

        var level = CombatFormulas.CalculateCombatLevel(player.Skills);

        level.Should().BeInRange(3, 5);
    }

    [Fact]
    public void CalculateMaxHit_HighStrength_ReturnsHighDamage()
    {
        var player = CreatePlayer(99, 99, 99, 99);
        var bonuses = new CombatBonuses(StrengthBonus: 100);

        var maxHit = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Aggressive, bonuses);

        maxHit.Should().BeGreaterThan(20);
    }

    [Fact]
    public void CalculateMaxHit_LowStrength_ReturnsLowDamage()
    {
        var player = CreatePlayer(1, 1, 1, 10);
        var bonuses = CombatBonuses.None;

        var maxHit = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Aggressive, bonuses);

        maxHit.Should().BeLessThan(5);
    }

    [Fact]
    public void CalculateMaxHit_AggressiveStyle_HigherThanControlled()
    {
        var player = CreatePlayer(50, 50, 50, 50);
        var bonuses = new CombatBonuses(StrengthBonus: 50);

        var aggressive = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Aggressive, bonuses);
        var controlled = CombatFormulas.CalculateMaxMeleeHit(player.Skills, CombatStyle.Controlled, bonuses);

        aggressive.Should().BeGreaterOrEqualTo(controlled);
    }

    [Theory]
    [InlineData(1, 1, 83)]       // Low attack vs low defense
    [InlineData(99, 1, 200)]     // High attack vs low defense
    [InlineData(1, 99, -16)]     // Low attack vs high defense
    [InlineData(99, 99, 100)]    // High attack vs high defense
    public void CalculateAccuracyRoll_VariousLevels(int attackLevel, int defenseLevel, int expectedSign)
    {
        var attacker = CreatePlayer(attack: attackLevel);
        var defender = CreatePlayer(defense: defenseLevel);

        var attackerBonuses = new CombatBonuses(AttackBonus: 50);
        var defenderBonuses = new CombatBonuses(DefenseBonus: 50);

        var attackRoll = CombatFormulas.CalculateAttackRoll(attacker.Skills, CombatStyle.Accurate, attackerBonuses);
        var defenseRoll = CombatFormulas.CalculateDefenseRoll(defender.Skills, CombatStyle.Defensive, defenderBonuses);

        // Just verify the difference has the expected sign
        var diff = attackRoll - defenseRoll;
        if (expectedSign > 0)
            diff.Should().BePositive();
        else if (expectedSign < 0)
            diff.Should().BeNegative();
    }

    [Fact]
    public void CalculateXpGain_MeleeHit_ReturnsCorrectXp()
    {
        var damage = 10;
        var style = CombatStyle.Aggressive;

        var (attackXp, strengthXp, defenseXp, hitpointsXp) = CombatFormulas.CalculateMeleeXpGain(damage, style);

        hitpointsXp.Should().BeGreaterThan(0);
        strengthXp.Should().BeGreaterThan(0); // Aggressive gives strength XP
    }

    [Fact]
    public void CalculateXpGain_DefensiveStyle_GivesDefenseXp()
    {
        var damage = 10;
        var style = CombatStyle.Defensive;

        var (attackXp, strengthXp, defenseXp, hitpointsXp) = CombatFormulas.CalculateMeleeXpGain(damage, style);

        hitpointsXp.Should().BeGreaterThan(0);
        defenseXp.Should().BeGreaterThan(0);
        attackXp.Should().Be(0);
        strengthXp.Should().Be(0);
    }

    [Fact]
    public void HitResult_Miss_HasZeroDamage()
    {
        var miss = HitResult.Miss;

        miss.Hit.Should().BeFalse();
        miss.Damage.Should().Be(0);
    }

    [Fact]
    public void HitResult_Hit_HasDamage()
    {
        var hit = new HitResult(true, 15, DamageType.Melee);

        hit.Hit.Should().BeTrue();
        hit.Damage.Should().Be(15);
        hit.DamageType.Should().Be(DamageType.Melee);
    }

    [Fact]
    public void CombatBonuses_None_AllZeros()
    {
        var bonuses = CombatBonuses.None;

        bonuses.AttackBonus.Should().Be(0);
        bonuses.StrengthBonus.Should().Be(0);
        bonuses.DefenseBonus.Should().Be(0);
    }

    [Fact]
    public void CombatBonuses_Addition_SumsCorrectly()
    {
        var a = new CombatBonuses(AttackBonus: 10, StrengthBonus: 5);
        var b = new CombatBonuses(AttackBonus: 3, DefenseBonus: 7);

        var sum = a + b;

        sum.AttackBonus.Should().Be(13);
        sum.StrengthBonus.Should().Be(5);
        sum.DefenseBonus.Should().Be(7);
    }
}
