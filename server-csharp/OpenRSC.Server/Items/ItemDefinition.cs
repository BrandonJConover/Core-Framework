namespace OpenRSC.Server.Items;

/// <summary>
/// Represents the static definition/template of an item type.
/// </summary>
public sealed record ItemDefinition
{
    public required int Id { get; init; }
    public required string Name { get; init; }
    public string Description { get; init; } = string.Empty;
    public string Command { get; init; } = "Use";
    public int BasePrice { get; init; }
    public bool IsStackable { get; init; }
    public bool IsMembers { get; init; }
    public bool IsWearable { get; init; }
    public bool IsQuestItem { get; init; }
    public bool IsTradeable { get; init; } = true;
    public int SpriteId { get; init; }

    /// <summary>
    /// Equipment slot this item occupies when worn.
    /// </summary>
    public EquipmentSlot? EquipmentSlot { get; init; }

    /// <summary>
    /// Combat bonuses when equipped.
    /// </summary>
    public EquipmentStats? EquipmentStats { get; init; }

    /// <summary>
    /// Skill requirements to equip.
    /// </summary>
    public IReadOnlyDictionary<Skills.Skill, int> Requirements { get; init; }
        = new Dictionary<Skills.Skill, int>();
}

/// <summary>
/// Equipment slot types.
/// </summary>
public enum EquipmentSlot
{
    Head = 0,
    Cape = 1,
    Amulet = 2,
    WeaponRight = 3,
    Body = 4,
    WeaponLeft = 5,
    Legs = 7,
    Hands = 9,
    Feet = 10,
    Ring = 12,
    Ammunition = 13
}

/// <summary>
/// Combat stats provided by equipment.
/// </summary>
public readonly record struct EquipmentStats(
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
    int PrayerBonus,
    int RangedStrength,
    int MagicDamage)
{
    public static readonly EquipmentStats None = new();

    /// <summary>
    /// Gets total attack bonus for a specific style.
    /// </summary>
    public int GetAttackBonus(AttackStyle style) => style switch
    {
        AttackStyle.Stab => AttackStab,
        AttackStyle.Slash => AttackSlash,
        AttackStyle.Crush => AttackCrush,
        AttackStyle.Magic => AttackMagic,
        AttackStyle.Ranged => AttackRanged,
        _ => 0
    };

    /// <summary>
    /// Gets total defense bonus for a specific style.
    /// </summary>
    public int GetDefenseBonus(AttackStyle style) => style switch
    {
        AttackStyle.Stab => DefenseStab,
        AttackStyle.Slash => DefenseSlash,
        AttackStyle.Crush => DefenseCrush,
        AttackStyle.Magic => DefenseMagic,
        AttackStyle.Ranged => DefenseRanged,
        _ => 0
    };

    /// <summary>
    /// Combines two equipment stats by adding their values.
    /// </summary>
    public static EquipmentStats operator +(EquipmentStats a, EquipmentStats b) => new(
        a.AttackStab + b.AttackStab,
        a.AttackSlash + b.AttackSlash,
        a.AttackCrush + b.AttackCrush,
        a.AttackMagic + b.AttackMagic,
        a.AttackRanged + b.AttackRanged,
        a.DefenseStab + b.DefenseStab,
        a.DefenseSlash + b.DefenseSlash,
        a.DefenseCrush + b.DefenseCrush,
        a.DefenseMagic + b.DefenseMagic,
        a.DefenseRanged + b.DefenseRanged,
        a.StrengthBonus + b.StrengthBonus,
        a.PrayerBonus + b.PrayerBonus,
        a.RangedStrength + b.RangedStrength,
        a.MagicDamage + b.MagicDamage
    );
}

/// <summary>
/// Attack style for combat bonuses.
/// </summary>
public enum AttackStyle
{
    Stab,
    Slash,
    Crush,
    Magic,
    Ranged
}
