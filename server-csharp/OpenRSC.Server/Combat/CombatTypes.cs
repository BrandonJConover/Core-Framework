namespace OpenRSC.Server.Combat;

/// <summary>
/// Combat styles available in RSC.
/// </summary>
public enum CombatStyle
{
    /// <summary>Controlled - balanced XP across attack/strength/defense</summary>
    Controlled = 0,

    /// <summary>Aggressive - strength XP focus</summary>
    Aggressive = 1,

    /// <summary>Accurate - attack XP focus</summary>
    Accurate = 2,

    /// <summary>Defensive - defense XP focus</summary>
    Defensive = 3
}

/// <summary>
/// Types of combat damage.
/// </summary>
public enum DamageType
{
    Melee,
    Ranged,
    Magic,
    Poison,
    Disease,
    Reflected  // Ring of recoil, etc.
}

/// <summary>
/// Represents a combat hit result. Immutable value object.
/// </summary>
public readonly record struct HitResult(
    int Damage,
    DamageType Type,
    bool IsCritical = false,
    bool IsBlocked = false)
{
    public static HitResult Miss => new(0, DamageType.Melee, false, true);
    public static HitResult Blocked => new(0, DamageType.Melee, false, true);

    public bool IsHit => Damage > 0 && !IsBlocked;
}

/// <summary>
/// Combat bonuses from equipment. Immutable value object.
/// </summary>
public readonly record struct CombatBonuses(
    int AttackStab,
    int AttackSlash,
    int AttackCrush,
    int AttackMagic,
    int AttackRanged,
    int DefenseStab,
    int DefenseSlash,
    int DefenseCrush,
    int DefenseMagic,
    int DefenseRanged,
    int StrengthBonus,
    int PrayerBonus)
{
    public static CombatBonuses Empty => new();

    public int TotalAttack => AttackStab + AttackSlash + AttackCrush;
    public int TotalDefense => DefenseStab + DefenseSlash + DefenseCrush;
}

/// <summary>
/// Player combat settings and preferences.
/// </summary>
public sealed class PlayerCombatSettings
{
    /// <summary>
    /// The current combat style.
    /// </summary>
    public CombatStyle Style { get; set; } = CombatStyle.Controlled;

    /// <summary>
    /// Whether auto-retaliate is enabled.
    /// </summary>
    public bool AutoRetaliate { get; set; } = true;

    /// <summary>
    /// Whether skull is visible.
    /// </summary>
    public bool ShowSkull { get; set; } = true;
}
