namespace OpenRSC.Server.Npc;

/// <summary>
/// Represents the static definition of an NPC type.
/// </summary>
public sealed record NpcDefinition
{
    public required int Id { get; init; }
    public required string Name { get; init; }
    public string Description { get; init; } = string.Empty;
    public string Command { get; init; } = "Talk";

    /// <summary>
    /// Combat level (0 for non-combatants).
    /// </summary>
    public int CombatLevel { get; init; }

    /// <summary>
    /// Maximum hitpoints.
    /// </summary>
    public int Hitpoints { get; init; } = 1;

    /// <summary>
    /// Attack level.
    /// </summary>
    public int AttackLevel { get; init; } = 1;

    /// <summary>
    /// Defense level.
    /// </summary>
    public int DefenseLevel { get; init; } = 1;

    /// <summary>
    /// Strength level.
    /// </summary>
    public int StrengthLevel { get; init; } = 1;

    /// <summary>
    /// Maximum damage this NPC can deal.
    /// </summary>
    public int MaxHit { get; init; }

    /// <summary>
    /// Whether this NPC can be attacked.
    /// </summary>
    public bool IsAttackable { get; init; }

    /// <summary>
    /// Whether this NPC attacks players first.
    /// </summary>
    public bool IsAggressive { get; init; }

    /// <summary>
    /// Aggro range in tiles.
    /// </summary>
    public int AggroRange { get; init; } = 4;

    /// <summary>
    /// Ticks until NPC respawns after death.
    /// </summary>
    public int RespawnTicks { get; init; } = 50;

    /// <summary>
    /// Whether this NPC walks around.
    /// </summary>
    public bool CanRoam { get; init; } = true;

    /// <summary>
    /// Maximum tiles from spawn to roam.
    /// </summary>
    public int RoamDistance { get; init; } = 5;

    /// <summary>
    /// Sprite IDs for appearance.
    /// </summary>
    public int[] Sprites { get; init; } = Array.Empty<int>();

    /// <summary>
    /// Items dropped on death.
    /// </summary>
    public IReadOnlyList<NpcDrop> Drops { get; init; } = Array.Empty<NpcDrop>();

    /// <summary>
    /// Shop ID this NPC operates, if any.
    /// </summary>
    public int? ShopId { get; init; }

    /// <summary>
    /// Thieving level required to pickpocket this NPC.
    /// </summary>
    public int? ThievingLevel { get; init; }

    /// <summary>
    /// Defense bonus for combat calculations.
    /// </summary>
    public int DefenseBonus { get; init; }
}

/// <summary>
/// Represents a potential item drop from an NPC.
/// </summary>
public sealed record NpcDrop(
    int ItemId,
    int MinAmount,
    int MaxAmount,
    double DropRate)
{
    /// <summary>
    /// Rolls whether this drop should occur.
    /// </summary>
    public bool Roll() => Random.Shared.NextDouble() < DropRate;

    /// <summary>
    /// Gets the random amount within range.
    /// </summary>
    public int GetAmount() => Random.Shared.Next(MinAmount, MaxAmount + 1);
}

/// <summary>
/// Repository for NPC definitions.
/// </summary>
public interface INpcDefinitionRepository
{
    NpcDefinition? GetById(int npcId);
    NpcDefinition? GetByName(string name);
    IEnumerable<NpcDefinition> GetAll();
}
