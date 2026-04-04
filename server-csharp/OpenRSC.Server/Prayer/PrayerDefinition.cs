namespace OpenRSC.Server.Prayer;

/// <summary>
/// All prayers available in RSC.
/// </summary>
public enum PrayerType
{
    ThickSkin = 0,
    BurstOfStrength = 1,
    ClarityOfThought = 2,
    RockSkin = 3,
    SuperhumanStrength = 4,
    ImprovedReflexes = 5,
    RapidRestore = 6,
    RapidHeal = 7,
    ProtectItems = 8,
    SteelSkin = 9,
    UltimateStrength = 10,
    IncredibleReflexes = 11,
    Paralyze = 12,
    ProtectFromMissiles = 13
}

/// <summary>
/// Static prayer definition data.
/// </summary>
public sealed record PrayerDefinition
{
    public required PrayerType Type { get; init; }
    public required string Name { get; init; }
    public required string Description { get; init; }
    public required int RequiredLevel { get; init; }
    public required int DrainRate { get; init; } // Points per minute

    /// <summary>
    /// Defense bonus multiplier (1.0 = no bonus).
    /// </summary>
    public double DefenseMultiplier { get; init; } = 1.0;

    /// <summary>
    /// Strength bonus multiplier.
    /// </summary>
    public double StrengthMultiplier { get; init; } = 1.0;

    /// <summary>
    /// Attack bonus multiplier.
    /// </summary>
    public double AttackMultiplier { get; init; } = 1.0;

    /// <summary>
    /// Whether this prayer restores stats faster.
    /// </summary>
    public bool RapidRestore { get; init; }

    /// <summary>
    /// Whether this prayer restores HP faster.
    /// </summary>
    public bool RapidHeal { get; init; }

    /// <summary>
    /// Whether this prayer protects an extra item on death.
    /// </summary>
    public bool ProtectItem { get; init; }

    /// <summary>
    /// Prayers that conflict (can't be active together).
    /// </summary>
    public PrayerType[] ConflictsWith { get; init; } = Array.Empty<PrayerType>();

    /// <summary>
    /// All prayer definitions.
    /// </summary>
    public static readonly IReadOnlyDictionary<PrayerType, PrayerDefinition> All = new Dictionary<PrayerType, PrayerDefinition>
    {
        [PrayerType.ThickSkin] = new()
        {
            Type = PrayerType.ThickSkin,
            Name = "Thick Skin",
            Description = "Increases your defense by 5%",
            RequiredLevel = 1,
            DrainRate = 5,
            DefenseMultiplier = 1.05,
            ConflictsWith = new[] { PrayerType.RockSkin, PrayerType.SteelSkin }
        },
        [PrayerType.BurstOfStrength] = new()
        {
            Type = PrayerType.BurstOfStrength,
            Name = "Burst of Strength",
            Description = "Increases your strength by 5%",
            RequiredLevel = 4,
            DrainRate = 5,
            StrengthMultiplier = 1.05,
            ConflictsWith = new[] { PrayerType.SuperhumanStrength, PrayerType.UltimateStrength }
        },
        [PrayerType.ClarityOfThought] = new()
        {
            Type = PrayerType.ClarityOfThought,
            Name = "Clarity of Thought",
            Description = "Increases your attack by 5%",
            RequiredLevel = 7,
            DrainRate = 5,
            AttackMultiplier = 1.05,
            ConflictsWith = new[] { PrayerType.ImprovedReflexes, PrayerType.IncredibleReflexes }
        },
        [PrayerType.RockSkin] = new()
        {
            Type = PrayerType.RockSkin,
            Name = "Rock Skin",
            Description = "Increases your defense by 10%",
            RequiredLevel = 10,
            DrainRate = 10,
            DefenseMultiplier = 1.10,
            ConflictsWith = new[] { PrayerType.ThickSkin, PrayerType.SteelSkin }
        },
        [PrayerType.SuperhumanStrength] = new()
        {
            Type = PrayerType.SuperhumanStrength,
            Name = "Superhuman Strength",
            Description = "Increases your strength by 10%",
            RequiredLevel = 13,
            DrainRate = 10,
            StrengthMultiplier = 1.10,
            ConflictsWith = new[] { PrayerType.BurstOfStrength, PrayerType.UltimateStrength }
        },
        [PrayerType.ImprovedReflexes] = new()
        {
            Type = PrayerType.ImprovedReflexes,
            Name = "Improved Reflexes",
            Description = "Increases your attack by 10%",
            RequiredLevel = 16,
            DrainRate = 10,
            AttackMultiplier = 1.10,
            ConflictsWith = new[] { PrayerType.ClarityOfThought, PrayerType.IncredibleReflexes }
        },
        [PrayerType.RapidRestore] = new()
        {
            Type = PrayerType.RapidRestore,
            Name = "Rapid Restore",
            Description = "2x restore rate for all stats except hits",
            RequiredLevel = 19,
            DrainRate = 5,
            RapidRestore = true
        },
        [PrayerType.RapidHeal] = new()
        {
            Type = PrayerType.RapidHeal,
            Name = "Rapid Heal",
            Description = "2x restore rate for hitpoints",
            RequiredLevel = 22,
            DrainRate = 5,
            RapidHeal = true
        },
        [PrayerType.ProtectItems] = new()
        {
            Type = PrayerType.ProtectItems,
            Name = "Protect Items",
            Description = "Keep 1 extra item if you die",
            RequiredLevel = 25,
            DrainRate = 5,
            ProtectItem = true
        },
        [PrayerType.SteelSkin] = new()
        {
            Type = PrayerType.SteelSkin,
            Name = "Steel Skin",
            Description = "Increases your defense by 15%",
            RequiredLevel = 28,
            DrainRate = 20,
            DefenseMultiplier = 1.15,
            ConflictsWith = new[] { PrayerType.ThickSkin, PrayerType.RockSkin }
        },
        [PrayerType.UltimateStrength] = new()
        {
            Type = PrayerType.UltimateStrength,
            Name = "Ultimate Strength",
            Description = "Increases your strength by 15%",
            RequiredLevel = 31,
            DrainRate = 20,
            StrengthMultiplier = 1.15,
            ConflictsWith = new[] { PrayerType.BurstOfStrength, PrayerType.SuperhumanStrength }
        },
        [PrayerType.IncredibleReflexes] = new()
        {
            Type = PrayerType.IncredibleReflexes,
            Name = "Incredible Reflexes",
            Description = "Increases your attack by 15%",
            RequiredLevel = 34,
            DrainRate = 20,
            AttackMultiplier = 1.15,
            ConflictsWith = new[] { PrayerType.ClarityOfThought, PrayerType.ImprovedReflexes }
        },
        [PrayerType.Paralyze] = new()
        {
            Type = PrayerType.Paralyze,
            Name = "Paralyze Monster",
            Description = "Monsters can't move when fighting you",
            RequiredLevel = 37,
            DrainRate = 30
        },
        [PrayerType.ProtectFromMissiles] = new()
        {
            Type = PrayerType.ProtectFromMissiles,
            Name = "Protect from Missiles",
            Description = "Protection from ranged attacks",
            RequiredLevel = 40,
            DrainRate = 30
        }
    };
}
