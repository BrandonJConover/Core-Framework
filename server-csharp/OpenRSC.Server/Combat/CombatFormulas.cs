using OpenRSC.Server.Entities;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Combat;

/// <summary>
/// RSC combat formulas. Static utility class with pure functions.
/// </summary>
public static class CombatFormulas
{
    private static readonly Random Rng = Random.Shared;

    /// <summary>
    /// Calculates melee max hit.
    /// </summary>
    public static int CalculateMeleeMaxHit(Player player, CombatStyle style)
    {
        var strengthLevel = player.Skills.GetCurrentLevel(Skill.Strength);
        var strengthBonus = 0; // TODO: Get from equipment

        // Style bonus
        var styleBonus = style switch
        {
            CombatStyle.Aggressive => 3,
            CombatStyle.Controlled => 1,
            _ => 0
        };

        // RSC formula: (strength + styleBonus) * (strengthBonus + 64) / 640
        var effectiveStrength = strengthLevel + styleBonus;
        var maxHit = (int)((effectiveStrength * (strengthBonus + 64.0)) / 640.0) + 1;

        return Math.Max(1, maxHit);
    }

    /// <summary>
    /// Calculates attack roll for accuracy.
    /// </summary>
    public static int CalculateAttackRoll(Player player, CombatStyle style)
    {
        var attackLevel = player.Skills.GetCurrentLevel(Skill.Attack);
        var attackBonus = 0; // TODO: Get from equipment

        var styleBonus = style switch
        {
            CombatStyle.Accurate => 3,
            CombatStyle.Controlled => 1,
            _ => 0
        };

        var effectiveAttack = attackLevel + styleBonus;
        return (int)(effectiveAttack * (attackBonus + 64.0));
    }

    /// <summary>
    /// Calculates defense roll.
    /// </summary>
    public static int CalculateDefenseRoll(Mob defender, CombatStyle style)
    {
        int defenseLevel;
        int defenseBonus = 0;

        if (defender is Player player)
        {
            defenseLevel = player.Skills.GetCurrentLevel(Skill.Defense);
            // TODO: Get defense bonus from equipment
        }
        else if (defender is Npc npc)
        {
            defenseLevel = GetNpcDefenseLevel(npc.Id);
            defenseBonus = GetNpcDefenseBonus(npc.Id);
        }
        else
        {
            defenseLevel = 1;
        }

        var styleBonus = style switch
        {
            CombatStyle.Defensive => 3,
            CombatStyle.Controlled => 1,
            _ => 0
        };

        var effectiveDefense = defenseLevel + styleBonus;
        return (int)(effectiveDefense * (defenseBonus + 64.0));
    }

    /// <summary>
    /// Determines if an attack hits based on accuracy rolls.
    /// </summary>
    public static bool RollAccuracy(int attackRoll, int defenseRoll)
    {
        // RSC hit chance formula
        if (attackRoll < 1) attackRoll = 1;
        if (defenseRoll < 1) defenseRoll = 1;

        double hitChance;
        if (attackRoll > defenseRoll)
        {
            hitChance = 1.0 - (defenseRoll + 2.0) / (2.0 * (attackRoll + 1.0));
        }
        else
        {
            hitChance = attackRoll / (2.0 * (defenseRoll + 1.0));
        }

        return Rng.NextDouble() < hitChance;
    }

    /// <summary>
    /// Calculates melee damage for a hit.
    /// </summary>
    public static HitResult CalculateMeleeHit(Player attacker, Mob defender, CombatStyle style)
    {
        var attackRoll = CalculateAttackRoll(attacker, style);
        var defenseRoll = CalculateDefenseRoll(defender, style);

        if (!RollAccuracy(attackRoll, defenseRoll))
        {
            return HitResult.Miss;
        }

        var maxHit = CalculateMeleeMaxHit(attacker, style);
        var damage = Rng.Next(0, maxHit + 1);

        // Cap damage at defender's current HP
        if (defender is Player defPlayer)
        {
            damage = Math.Min(damage, defPlayer.Skills.GetCurrentLevel(Skill.Hits));
        }
        else
        {
            damage = Math.Min(damage, defender.CurrentHitpoints);
        }

        return new HitResult(damage, DamageType.Melee, damage == maxHit);
    }

    /// <summary>
    /// Calculates ranged max hit.
    /// </summary>
    public static int CalculateRangedMaxHit(Player player, int arrowStrength)
    {
        var rangedLevel = player.Skills.GetCurrentLevel(Skill.Ranged);

        // RSC ranged formula
        var maxHit = (int)((rangedLevel * (arrowStrength + 64.0)) / 640.0) + 1;

        return Math.Max(1, maxHit);
    }

    /// <summary>
    /// Calculates magic max hit for a spell.
    /// </summary>
    public static int CalculateMagicMaxHit(int spellBaseMax, int magicLevel)
    {
        // Magic in RSC uses spell-defined max hits
        return spellBaseMax;
    }

    /// <summary>
    /// Calculates experience gained from combat.
    /// </summary>
    public static (Skill skill, int amount)[] CalculateCombatExperience(
        int damage,
        CombatStyle style,
        DamageType damageType)
    {
        if (damage <= 0) return Array.Empty<(Skill, int)>();

        // Base XP is damage * 4
        var baseXp = damage * 4;

        return damageType switch
        {
            DamageType.Melee => style switch
            {
                CombatStyle.Aggressive => new[] { (Skill.Strength, baseXp), (Skill.Hits, baseXp / 4) },
                CombatStyle.Accurate => new[] { (Skill.Attack, baseXp), (Skill.Hits, baseXp / 4) },
                CombatStyle.Defensive => new[] { (Skill.Defense, baseXp), (Skill.Hits, baseXp / 4) },
                CombatStyle.Controlled => new[]
                {
                    (Skill.Attack, baseXp / 3),
                    (Skill.Strength, baseXp / 3),
                    (Skill.Defense, baseXp / 3),
                    (Skill.Hits, baseXp / 4)
                },
                _ => Array.Empty<(Skill, int)>()
            },
            DamageType.Ranged => new[] { (Skill.Ranged, baseXp), (Skill.Hits, baseXp / 4) },
            DamageType.Magic => new[] { (Skill.Magic, baseXp), (Skill.Hits, baseXp / 4) },
            _ => Array.Empty<(Skill, int)>()
        };
    }

    // NPC stat lookups - would normally come from definition files
    private static int GetNpcDefenseLevel(int npcId) => 1; // TODO: Load from definitions
    private static int GetNpcDefenseBonus(int npcId) => 0; // TODO: Load from definitions
}
