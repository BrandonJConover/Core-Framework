using OpenRSC.Server.Entities;
using OpenRSC.Server.Inventory;
using OpenRSC.Server.Items;
using OpenRSC.Server.Npc;
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
        var strengthBonus = GetStrengthBonus(player);

        // Prayer bonus
        var prayerMultiplier = GetStrengthPrayerMultiplier(player);

        // Style bonus
        var styleBonus = style switch
        {
            CombatStyle.Aggressive => 3,
            CombatStyle.Controlled => 1,
            _ => 0
        };

        // RSC formula: (strength + styleBonus) * (strengthBonus + 64) / 640
        var effectiveStrength = (int)((strengthLevel * prayerMultiplier) + styleBonus);
        var maxHit = (int)((effectiveStrength * (strengthBonus + 64.0)) / 640.0) + 1;

        return Math.Max(1, maxHit);
    }

    /// <summary>
    /// Calculates attack roll for accuracy.
    /// </summary>
    public static int CalculateAttackRoll(Player player, CombatStyle style)
    {
        var attackLevel = player.Skills.GetCurrentLevel(Skill.Attack);
        var attackBonus = GetAttackBonus(player, style);

        // Prayer bonus
        var prayerMultiplier = GetAttackPrayerMultiplier(player);

        var styleBonus = style switch
        {
            CombatStyle.Accurate => 3,
            CombatStyle.Controlled => 1,
            _ => 0
        };

        var effectiveAttack = (int)((attackLevel * prayerMultiplier) + styleBonus);
        return (int)(effectiveAttack * (attackBonus + 64.0));
    }

    /// <summary>
    /// Calculates defense roll.
    /// </summary>
    public static int CalculateDefenseRoll(Mob defender, CombatStyle attackStyle)
    {
        int defenseLevel;
        int defenseBonus;

        if (defender is Player player)
        {
            defenseLevel = player.Skills.GetCurrentLevel(Skill.Defense);
            defenseBonus = GetDefenseBonus(player, attackStyle);

            // Prayer bonus
            var prayerMultiplier = GetDefensePrayerMultiplier(player);
            defenseLevel = (int)(defenseLevel * prayerMultiplier);
        }
        else if (defender is Entities.Npc npc)
        {
            defenseLevel = GetNpcDefenseLevel(npc);
            defenseBonus = GetNpcDefenseBonus(npc, attackStyle);
        }
        else
        {
            defenseLevel = 1;
            defenseBonus = 0;
        }

        // Defender style bonus (assume defensive)
        var styleBonus = 3;

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
        var rangedBonus = player.Equipment.GetTotalBonuses().AttackRanged;

        // RSC ranged formula
        var effectiveRanged = rangedLevel + rangedBonus;
        var maxHit = (int)((effectiveRanged * (arrowStrength + 64.0)) / 640.0) + 1;

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

    #region Equipment Bonus Helpers

    /// <summary>
    /// Gets the strength bonus from equipment.
    /// </summary>
    private static int GetStrengthBonus(Player player)
    {
        return player.Equipment.GetTotalBonuses().Strength;
    }

    /// <summary>
    /// Gets the attack bonus based on weapon style.
    /// </summary>
    private static int GetAttackBonus(Player player, CombatStyle style)
    {
        var bonuses = player.Equipment.GetTotalBonuses();
        var weaponStyle = player.Equipment.GetWeaponStyle();

        return weaponStyle switch
        {
            AttackStyle.Stab => bonuses.AttackStab,
            AttackStyle.Slash => bonuses.AttackSlash,
            AttackStyle.Crush => bonuses.AttackCrush,
            AttackStyle.Magic => bonuses.AttackMagic,
            AttackStyle.Ranged => bonuses.AttackRanged,
            _ => bonuses.AttackSlash
        };
    }

    /// <summary>
    /// Gets the defense bonus based on attack style.
    /// </summary>
    private static int GetDefenseBonus(Player player, CombatStyle attackStyle)
    {
        var bonuses = player.Equipment.GetTotalBonuses();

        // Average of all defense bonuses for simplicity
        // In RSC, specific defense type depends on attacker's weapon
        return (bonuses.DefenseStab + bonuses.DefenseSlash + bonuses.DefenseCrush) / 3;
    }

    #endregion

    #region Prayer Multipliers

    private static double GetAttackPrayerMultiplier(Player player)
    {
        var prayers = player.Prayers;
        if (prayers.IsActive(Prayer.Prayer.IncredibleReflexes)) return 1.15;
        if (prayers.IsActive(Prayer.Prayer.ImprovedReflexes)) return 1.10;
        if (prayers.IsActive(Prayer.Prayer.ClarityOfThought)) return 1.05;
        return 1.0;
    }

    private static double GetStrengthPrayerMultiplier(Player player)
    {
        var prayers = player.Prayers;
        if (prayers.IsActive(Prayer.Prayer.UltimateStrength)) return 1.15;
        if (prayers.IsActive(Prayer.Prayer.SuperhumanStrength)) return 1.10;
        if (prayers.IsActive(Prayer.Prayer.BurstOfStrength)) return 1.05;
        return 1.0;
    }

    private static double GetDefensePrayerMultiplier(Player player)
    {
        var prayers = player.Prayers;
        if (prayers.IsActive(Prayer.Prayer.SteelSkin)) return 1.15;
        if (prayers.IsActive(Prayer.Prayer.RockSkin)) return 1.10;
        if (prayers.IsActive(Prayer.Prayer.ThickSkin)) return 1.05;
        return 1.0;
    }

    #endregion

    #region NPC Stats

    /// <summary>
    /// Gets NPC defense level from definition.
    /// </summary>
    private static int GetNpcDefenseLevel(Entities.Npc npc)
    {
        // Use NPC's combat level as a base for defense
        return npc.Definition?.DefenseLevel ?? npc.CombatLevel;
    }

    /// <summary>
    /// Gets NPC defense bonus based on attack type.
    /// </summary>
    private static int GetNpcDefenseBonus(Entities.Npc npc, CombatStyle attackStyle)
    {
        // NPCs typically have lower defense bonuses than players
        return npc.Definition?.DefenseBonus ?? 0;
    }

    #endregion
}
