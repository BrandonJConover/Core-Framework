using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Ranged weapon type.
/// </summary>
public enum RangedWeaponType
{
    Bow,
    Crossbow,
    Thrown
}

/// <summary>
/// Ranged weapon definition.
/// </summary>
public sealed record RangedWeaponDefinition
{
    public required int ItemId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required RangedWeaponType Type { get; init; }
    public required int BaseStrength { get; init; }
    public int AttackSpeed { get; init; } = 4; // Ticks between attacks
    public int[]? RequiredAmmoIds { get; init; } // null for thrown weapons

    public static readonly IReadOnlyDictionary<int, RangedWeaponDefinition> All = new Dictionary<int, RangedWeaponDefinition>
    {
        // Shortbows
        [189] = new() { ItemId = 189, Name = "Shortbow", RequiredLevel = 1, Type = RangedWeaponType.Bow, BaseStrength = 5, AttackSpeed = 3, RequiredAmmoIds = new[] { 11, 638, 639, 640, 641, 642 } },
        [649] = new() { ItemId = 649, Name = "Oak shortbow", RequiredLevel = 5, Type = RangedWeaponType.Bow, BaseStrength = 10, AttackSpeed = 3, RequiredAmmoIds = new[] { 11, 638, 639, 640, 641, 642 } },
        [650] = new() { ItemId = 650, Name = "Willow shortbow", RequiredLevel = 20, Type = RangedWeaponType.Bow, BaseStrength = 15, AttackSpeed = 3, RequiredAmmoIds = new[] { 638, 639, 640, 641, 642 } },
        [651] = new() { ItemId = 651, Name = "Maple shortbow", RequiredLevel = 30, Type = RangedWeaponType.Bow, BaseStrength = 20, AttackSpeed = 3, RequiredAmmoIds = new[] { 639, 640, 641, 642 } },
        [652] = new() { ItemId = 652, Name = "Yew shortbow", RequiredLevel = 40, Type = RangedWeaponType.Bow, BaseStrength = 30, AttackSpeed = 3, RequiredAmmoIds = new[] { 640, 641, 642 } },
        [653] = new() { ItemId = 653, Name = "Magic shortbow", RequiredLevel = 50, Type = RangedWeaponType.Bow, BaseStrength = 40, AttackSpeed = 3, RequiredAmmoIds = new[] { 641, 642 } },

        // Longbows
        [188] = new() { ItemId = 188, Name = "Longbow", RequiredLevel = 1, Type = RangedWeaponType.Bow, BaseStrength = 6, AttackSpeed = 4, RequiredAmmoIds = new[] { 11, 638, 639, 640, 641, 642 } },
        [654] = new() { ItemId = 654, Name = "Oak longbow", RequiredLevel = 5, Type = RangedWeaponType.Bow, BaseStrength = 12, AttackSpeed = 4, RequiredAmmoIds = new[] { 11, 638, 639, 640, 641, 642 } },
        [655] = new() { ItemId = 655, Name = "Willow longbow", RequiredLevel = 20, Type = RangedWeaponType.Bow, BaseStrength = 18, AttackSpeed = 4, RequiredAmmoIds = new[] { 638, 639, 640, 641, 642 } },
        [656] = new() { ItemId = 656, Name = "Maple longbow", RequiredLevel = 30, Type = RangedWeaponType.Bow, BaseStrength = 24, AttackSpeed = 4, RequiredAmmoIds = new[] { 639, 640, 641, 642 } },
        [657] = new() { ItemId = 657, Name = "Yew longbow", RequiredLevel = 40, Type = RangedWeaponType.Bow, BaseStrength = 35, AttackSpeed = 4, RequiredAmmoIds = new[] { 640, 641, 642 } },
        [658] = new() { ItemId = 658, Name = "Magic longbow", RequiredLevel = 50, Type = RangedWeaponType.Bow, BaseStrength = 45, AttackSpeed = 4, RequiredAmmoIds = new[] { 641, 642 } },

        // Crossbows
        [59] = new() { ItemId = 59, Name = "Crossbow", RequiredLevel = 1, Type = RangedWeaponType.Crossbow, BaseStrength = 8, AttackSpeed = 5, RequiredAmmoIds = new[] { 786, 787, 788, 789, 790, 791 } },
        [60] = new() { ItemId = 60, Name = "Phoenix crossbow", RequiredLevel = 1, Type = RangedWeaponType.Crossbow, BaseStrength = 10, AttackSpeed = 5, RequiredAmmoIds = new[] { 786, 787, 788, 789, 790, 791 } },

        // Thrown weapons
        [1013] = new() { ItemId = 1013, Name = "Bronze throwing knife", RequiredLevel = 1, Type = RangedWeaponType.Thrown, BaseStrength = 2, AttackSpeed = 2 },
        [1014] = new() { ItemId = 1014, Name = "Iron throwing knife", RequiredLevel = 1, Type = RangedWeaponType.Thrown, BaseStrength = 4, AttackSpeed = 2 },
        [1015] = new() { ItemId = 1015, Name = "Steel throwing knife", RequiredLevel = 5, Type = RangedWeaponType.Thrown, BaseStrength = 7, AttackSpeed = 2 },
        [1016] = new() { ItemId = 1016, Name = "Mithril throwing knife", RequiredLevel = 20, Type = RangedWeaponType.Thrown, BaseStrength = 10, AttackSpeed = 2 },
        [1017] = new() { ItemId = 1017, Name = "Adamant throwing knife", RequiredLevel = 30, Type = RangedWeaponType.Thrown, BaseStrength = 14, AttackSpeed = 2 },
        [1018] = new() { ItemId = 1018, Name = "Rune throwing knife", RequiredLevel = 40, Type = RangedWeaponType.Thrown, BaseStrength = 18, AttackSpeed = 2 }
    };
}

/// <summary>
/// Ammo definition.
/// </summary>
public sealed record AmmoDefinition
{
    public required int ItemId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int RangedStrength { get; init; }
    public bool IsRetrievable { get; init; } = true;

    public static readonly IReadOnlyDictionary<int, AmmoDefinition> All = new Dictionary<int, AmmoDefinition>
    {
        // Arrows
        [11] = new() { ItemId = 11, Name = "Bronze arrows", RequiredLevel = 1, RangedStrength = 7 },
        [638] = new() { ItemId = 638, Name = "Iron arrows", RequiredLevel = 1, RangedStrength = 10 },
        [639] = new() { ItemId = 639, Name = "Steel arrows", RequiredLevel = 5, RangedStrength = 16 },
        [640] = new() { ItemId = 640, Name = "Mithril arrows", RequiredLevel = 20, RangedStrength = 22 },
        [641] = new() { ItemId = 641, Name = "Adamant arrows", RequiredLevel = 30, RangedStrength = 31 },
        [642] = new() { ItemId = 642, Name = "Rune arrows", RequiredLevel = 40, RangedStrength = 49 },

        // Bolts
        [786] = new() { ItemId = 786, Name = "Bronze bolts", RequiredLevel = 1, RangedStrength = 10 },
        [787] = new() { ItemId = 787, Name = "Iron bolts", RequiredLevel = 1, RangedStrength = 14 },
        [788] = new() { ItemId = 788, Name = "Steel bolts", RequiredLevel = 5, RangedStrength = 20 },
        [789] = new() { ItemId = 789, Name = "Mithril bolts", RequiredLevel = 20, RangedStrength = 27 },
        [790] = new() { ItemId = 790, Name = "Adamant bolts", RequiredLevel = 30, RangedStrength = 36 },
        [791] = new() { ItemId = 791, Name = "Rune bolts", RequiredLevel = 40, RangedStrength = 55 }
    };
}

/// <summary>
/// Ranged armour definition.
/// </summary>
public sealed record RangedArmourDefinition
{
    public required int ItemId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int RangedBonus { get; init; }
    public required int DefenceBonus { get; init; }
    public EquipmentSlot Slot { get; init; }

    public static readonly IReadOnlyList<RangedArmourDefinition> All = new List<RangedArmourDefinition>
    {
        // Leather
        new() { ItemId = 16, Name = "Leather gloves", RequiredLevel = 1, RangedBonus = 1, DefenceBonus = 1, Slot = EquipmentSlot.Hands },
        new() { ItemId = 17, Name = "Leather boots", RequiredLevel = 1, RangedBonus = 1, DefenceBonus = 1, Slot = EquipmentSlot.Feet },
        new() { ItemId = 15, Name = "Leather armour", RequiredLevel = 1, RangedBonus = 2, DefenceBonus = 4, Slot = EquipmentSlot.Body },

        // Studded leather
        new() { ItemId = 702, Name = "Studded body", RequiredLevel = 20, RangedBonus = 4, DefenceBonus = 15, Slot = EquipmentSlot.Body },
        new() { ItemId = 703, Name = "Studded chaps", RequiredLevel = 20, RangedBonus = 3, DefenceBonus = 10, Slot = EquipmentSlot.Legs },

        // Green dragonhide
        new() { ItemId = 796, Name = "Green d'hide vambs", RequiredLevel = 40, RangedBonus = 8, DefenceBonus = 4, Slot = EquipmentSlot.Hands },
        new() { ItemId = 797, Name = "Green d'hide chaps", RequiredLevel = 40, RangedBonus = 8, DefenceBonus = 18, Slot = EquipmentSlot.Legs },
        new() { ItemId = 798, Name = "Green d'hide body", RequiredLevel = 40, RangedBonus = 15, DefenceBonus = 25, Slot = EquipmentSlot.Body },

        // Blue dragonhide
        new() { ItemId = 1131, Name = "Blue d'hide vambs", RequiredLevel = 50, RangedBonus = 9, DefenceBonus = 5, Slot = EquipmentSlot.Hands },
        new() { ItemId = 1095, Name = "Blue d'hide chaps", RequiredLevel = 50, RangedBonus = 11, DefenceBonus = 22, Slot = EquipmentSlot.Legs },
        new() { ItemId = 1133, Name = "Blue d'hide body", RequiredLevel = 50, RangedBonus = 20, DefenceBonus = 30, Slot = EquipmentSlot.Body },

        // Red dragonhide
        new() { ItemId = 1129, Name = "Red d'hide vambs", RequiredLevel = 60, RangedBonus = 10, DefenceBonus = 6, Slot = EquipmentSlot.Hands },
        new() { ItemId = 1093, Name = "Red d'hide chaps", RequiredLevel = 60, RangedBonus = 14, DefenceBonus = 26, Slot = EquipmentSlot.Legs },
        new() { ItemId = 1127, Name = "Red d'hide body", RequiredLevel = 60, RangedBonus = 25, DefenceBonus = 35, Slot = EquipmentSlot.Body },

        // Black dragonhide
        new() { ItemId = 1135, Name = "Black d'hide vambs", RequiredLevel = 70, RangedBonus = 11, DefenceBonus = 7, Slot = EquipmentSlot.Hands },
        new() { ItemId = 1099, Name = "Black d'hide chaps", RequiredLevel = 70, RangedBonus = 17, DefenceBonus = 30, Slot = EquipmentSlot.Legs },
        new() { ItemId = 1137, Name = "Black d'hide body", RequiredLevel = 70, RangedBonus = 30, DefenceBonus = 40, Slot = EquipmentSlot.Body }
    };
}

/// <summary>
/// Ranged combat calculations.
/// </summary>
public static class RangedCombat
{
    /// <summary>
    /// Calculates ranged max hit.
    /// </summary>
    public static int CalculateMaxHit(Player player, RangedWeaponDefinition weapon, AmmoDefinition? ammo)
    {
        var rangedLevel = player.Skills.GetCurrentLevel(Skill.Ranged);
        var rangedStrength = weapon.BaseStrength;

        if (ammo is not null)
        {
            rangedStrength += ammo.RangedStrength;
        }

        // Base formula: (rangedLevel + rangedStrength) / 8
        var maxHit = (rangedLevel + rangedStrength) / 8;

        // Prayer bonus would be applied here

        return Math.Max(1, maxHit);
    }

    /// <summary>
    /// Calculates ranged accuracy.
    /// </summary>
    public static double CalculateAccuracy(Player attacker, Mob target, RangedWeaponDefinition weapon)
    {
        var rangedLevel = attacker.Skills.GetCurrentLevel(Skill.Ranged);
        var attackRoll = rangedLevel * 4 + weapon.BaseStrength;

        // Simplified defense calculation
        var defenceRoll = target.CombatLevel * 4 + 10;

        if (attackRoll > defenceRoll)
        {
            return 1.0 - (defenceRoll + 2.0) / (2.0 * (attackRoll + 1.0));
        }
        else
        {
            return attackRoll / (2.0 * (defenceRoll + 1.0));
        }
    }

    /// <summary>
    /// Gets ammo from player's equipment or inventory.
    /// </summary>
    public static AmmoDefinition? GetEquippedAmmo(Player player, RangedWeaponDefinition weapon)
    {
        if (weapon.Type == RangedWeaponType.Thrown)
        {
            // Thrown weapons use themselves as ammo
            return null;
        }

        // Check quiver slot
        var ammoItem = player.Equipment.GetItem(EquipmentSlot.Ammo);
        if (ammoItem is null)
            return null;

        if (!AmmoDefinition.All.TryGetValue(ammoItem.CatalogId, out var ammo))
            return null;

        // Check if ammo is compatible with weapon
        if (weapon.RequiredAmmoIds is not null && !weapon.RequiredAmmoIds.Contains(ammoItem.CatalogId))
            return null;

        return ammo;
    }

    /// <summary>
    /// Consumes ammo after an attack.
    /// </summary>
    public static void ConsumeAmmo(Player player, RangedWeaponDefinition weapon)
    {
        if (weapon.Type == RangedWeaponType.Thrown)
        {
            // Remove from equipment
            player.Equipment.RemoveAmount(EquipmentSlot.Weapon, 1);
        }
        else
        {
            // Remove from ammo slot
            player.Equipment.RemoveAmount(EquipmentSlot.Ammo, 1);
        }
    }

    /// <summary>
    /// Checks if player can range attack.
    /// </summary>
    public static (bool CanAttack, string? Error) CanRangedAttack(Player player)
    {
        var weapon = player.Equipment.GetItem(EquipmentSlot.Weapon);
        if (weapon is null)
            return (false, "You need a ranged weapon to attack.");

        if (!RangedWeaponDefinition.All.TryGetValue(weapon.CatalogId, out var weaponDef))
            return (false, "You are not wielding a ranged weapon.");

        var rangedLevel = player.Skills.GetCurrentLevel(Skill.Ranged);
        if (rangedLevel < weaponDef.RequiredLevel)
            return (false, $"You need level {weaponDef.RequiredLevel} Ranged to use this weapon.");

        if (weaponDef.Type != RangedWeaponType.Thrown)
        {
            var ammo = GetEquippedAmmo(player, weaponDef);
            if (ammo is null)
                return (false, "You have no ammo equipped.");

            if (rangedLevel < ammo.RequiredLevel)
                return (false, $"You need level {ammo.RequiredLevel} Ranged to use this ammo.");
        }
        else
        {
            // Check thrown weapon stack
            var amount = player.Equipment.GetAmount(EquipmentSlot.Weapon);
            if (amount <= 0)
                return (false, "You have no throwing weapons left.");
        }

        return (true, null);
    }

    /// <summary>
    /// Gets XP for a ranged hit.
    /// </summary>
    public static int GetXpForDamage(int damage)
    {
        // 4 XP per damage to Ranged, 1.33 to Hitpoints
        return damage * 4;
    }
}
