using System.Collections.Frozen;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Magic;

/// <summary>
/// Types of spells.
/// </summary>
public enum SpellType
{
    Combat,
    Teleport,
    Enchantment,
    Alchemy,
    Utility
}

/// <summary>
/// Target type for spells.
/// </summary>
public enum SpellTarget
{
    None,
    Self,
    Player,
    Npc,
    Item,
    Object,
    Ground
}

/// <summary>
/// Represents a rune requirement.
/// </summary>
public readonly record struct RuneRequirement(RuneType Rune, int Amount);

/// <summary>
/// Types of runes in RSC.
/// </summary>
public enum RuneType
{
    Air = 33,
    Water = 32,
    Earth = 34,
    Fire = 31,
    Mind = 35,
    Body = 36,
    Cosmic = 46,
    Chaos = 41,
    Nature = 40,
    Law = 42,
    Death = 38,
    Blood = 619
}

/// <summary>
/// Definition of a spell.
/// </summary>
public sealed record SpellDefinition
{
    public required int Id { get; init; }
    public required string Name { get; init; }
    public required string Description { get; init; }
    public required int RequiredLevel { get; init; }
    public required SpellType Type { get; init; }
    public required SpellTarget Target { get; init; }

    /// <summary>
    /// Rune requirements.
    /// </summary>
    public IReadOnlyList<RuneRequirement> Runes { get; init; } = Array.Empty<RuneRequirement>();

    /// <summary>
    /// Base experience for casting.
    /// </summary>
    public int BaseExperience { get; init; }

    /// <summary>
    /// Base max damage for combat spells.
    /// </summary>
    public int BaseDamage { get; init; }

    /// <summary>
    /// Teleport destination (for teleport spells).
    /// </summary>
    public Models.Point? TeleportDestination { get; init; }

    /// <summary>
    /// Whether this spell is members only.
    /// </summary>
    public bool IsMembersOnly { get; init; }

    /// <summary>
    /// All spell definitions (frozen for optimal lookup performance).
    /// </summary>
    public static readonly FrozenDictionary<int, SpellDefinition> All = CreateSpells();

    private static FrozenDictionary<int, SpellDefinition> CreateSpells()
    {
        var spells = new Dictionary<int, SpellDefinition>();

        // Combat spells (Strike series)
        AddSpell(spells, 0, "Wind Strike", SpellType.Combat, 1, 5,
            new[] { new RuneRequirement(RuneType.Air, 1), new RuneRequirement(RuneType.Mind, 1) },
            damage: 2);

        AddSpell(spells, 1, "Water Strike", SpellType.Combat, 5, 7,
            new[] { new RuneRequirement(RuneType.Water, 1), new RuneRequirement(RuneType.Air, 1), new RuneRequirement(RuneType.Mind, 1) },
            damage: 4);

        AddSpell(spells, 2, "Earth Strike", SpellType.Combat, 9, 9,
            new[] { new RuneRequirement(RuneType.Earth, 2), new RuneRequirement(RuneType.Air, 1), new RuneRequirement(RuneType.Mind, 1) },
            damage: 6);

        AddSpell(spells, 3, "Fire Strike", SpellType.Combat, 13, 11,
            new[] { new RuneRequirement(RuneType.Fire, 3), new RuneRequirement(RuneType.Air, 2), new RuneRequirement(RuneType.Mind, 1) },
            damage: 8);

        // Bolt series
        AddSpell(spells, 4, "Wind Bolt", SpellType.Combat, 17, 13,
            new[] { new RuneRequirement(RuneType.Air, 2), new RuneRequirement(RuneType.Chaos, 1) },
            damage: 9);

        AddSpell(spells, 5, "Water Bolt", SpellType.Combat, 23, 16,
            new[] { new RuneRequirement(RuneType.Water, 2), new RuneRequirement(RuneType.Air, 2), new RuneRequirement(RuneType.Chaos, 1) },
            damage: 10);

        AddSpell(spells, 6, "Earth Bolt", SpellType.Combat, 29, 19,
            new[] { new RuneRequirement(RuneType.Earth, 3), new RuneRequirement(RuneType.Air, 2), new RuneRequirement(RuneType.Chaos, 1) },
            damage: 11);

        AddSpell(spells, 7, "Fire Bolt", SpellType.Combat, 35, 22,
            new[] { new RuneRequirement(RuneType.Fire, 4), new RuneRequirement(RuneType.Air, 3), new RuneRequirement(RuneType.Chaos, 1) },
            damage: 12);

        // Blast series
        AddSpell(spells, 8, "Wind Blast", SpellType.Combat, 41, 25,
            new[] { new RuneRequirement(RuneType.Air, 3), new RuneRequirement(RuneType.Death, 1) },
            damage: 13);

        AddSpell(spells, 9, "Water Blast", SpellType.Combat, 47, 28,
            new[] { new RuneRequirement(RuneType.Water, 3), new RuneRequirement(RuneType.Air, 3), new RuneRequirement(RuneType.Death, 1) },
            damage: 14);

        AddSpell(spells, 10, "Earth Blast", SpellType.Combat, 53, 31,
            new[] { new RuneRequirement(RuneType.Earth, 4), new RuneRequirement(RuneType.Air, 3), new RuneRequirement(RuneType.Death, 1) },
            damage: 15);

        AddSpell(spells, 11, "Fire Blast", SpellType.Combat, 59, 34,
            new[] { new RuneRequirement(RuneType.Fire, 5), new RuneRequirement(RuneType.Air, 4), new RuneRequirement(RuneType.Death, 1) },
            damage: 16);

        // Teleport spells
        AddTeleport(spells, 12, "Varrock Teleport", 25, 35,
            new[] { new RuneRequirement(RuneType.Fire, 1), new RuneRequirement(RuneType.Air, 3), new RuneRequirement(RuneType.Law, 1) },
            new Models.Point(122, 509));

        AddTeleport(spells, 13, "Lumbridge Teleport", 31, 41,
            new[] { new RuneRequirement(RuneType.Earth, 1), new RuneRequirement(RuneType.Air, 3), new RuneRequirement(RuneType.Law, 1) },
            new Models.Point(120, 648));

        AddTeleport(spells, 14, "Falador Teleport", 37, 47,
            new[] { new RuneRequirement(RuneType.Water, 1), new RuneRequirement(RuneType.Air, 3), new RuneRequirement(RuneType.Law, 1) },
            new Models.Point(312, 552));

        AddTeleport(spells, 15, "Camelot Teleport", 45, 55,
            new[] { new RuneRequirement(RuneType.Air, 5), new RuneRequirement(RuneType.Law, 1) },
            new Models.Point(465, 456), membersOnly: true);

        // Alchemy spells
        AddSpell(spells, 20, "Low Level Alchemy", SpellType.Alchemy, 21, 21,
            new[] { new RuneRequirement(RuneType.Fire, 3), new RuneRequirement(RuneType.Nature, 1) },
            target: SpellTarget.Item);

        AddSpell(spells, 21, "High Level Alchemy", SpellType.Alchemy, 55, 65,
            new[] { new RuneRequirement(RuneType.Fire, 5), new RuneRequirement(RuneType.Nature, 1) },
            target: SpellTarget.Item);

        // Utility spells
        AddSpell(spells, 30, "Bones to Bananas", SpellType.Utility, 15, 25,
            new[] { new RuneRequirement(RuneType.Earth, 2), new RuneRequirement(RuneType.Water, 2), new RuneRequirement(RuneType.Nature, 1) },
            target: SpellTarget.Self);

        AddSpell(spells, 31, "Superheat Item", SpellType.Utility, 43, 53,
            new[] { new RuneRequirement(RuneType.Fire, 4), new RuneRequirement(RuneType.Nature, 1) },
            target: SpellTarget.Item);

        return spells.ToFrozenDictionary();
    }

    private static void AddSpell(Dictionary<int, SpellDefinition> spells, int id, string name,
        SpellType type, int level, int xp, RuneRequirement[] runes,
        int damage = 0, SpellTarget target = SpellTarget.Npc, bool membersOnly = false)
    {
        spells[id] = new SpellDefinition
        {
            Id = id,
            Name = name,
            Description = $"Cast {name}",
            RequiredLevel = level,
            Type = type,
            Target = target,
            Runes = runes,
            BaseExperience = xp,
            BaseDamage = damage,
            IsMembersOnly = membersOnly
        };
    }

    private static void AddTeleport(Dictionary<int, SpellDefinition> spells, int id, string name,
        int level, int xp, RuneRequirement[] runes, Models.Point destination, bool membersOnly = false)
    {
        spells[id] = new SpellDefinition
        {
            Id = id,
            Name = name,
            Description = $"Teleport to {name.Replace(" Teleport", "")}",
            RequiredLevel = level,
            Type = SpellType.Teleport,
            Target = SpellTarget.Self,
            Runes = runes,
            BaseExperience = xp,
            TeleportDestination = destination,
            IsMembersOnly = membersOnly
        };
    }
}
