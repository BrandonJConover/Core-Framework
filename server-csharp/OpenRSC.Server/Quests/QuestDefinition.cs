namespace OpenRSC.Server.Quests;

/// <summary>
/// Represents a quest definition.
/// </summary>
public sealed record QuestDefinition
{
    public required int Id { get; init; }
    public required string Name { get; init; }
    public required string Description { get; init; }

    /// <summary>
    /// Quest points awarded on completion.
    /// </summary>
    public int QuestPoints { get; init; } = 1;

    /// <summary>
    /// Whether this is a members-only quest.
    /// </summary>
    public bool IsMembersOnly { get; init; }

    /// <summary>
    /// Skill requirements to start the quest.
    /// </summary>
    public IReadOnlyDictionary<Skills.Skill, int> SkillRequirements { get; init; }
        = new Dictionary<Skills.Skill, int>();

    /// <summary>
    /// Quest requirements (must complete these first).
    /// </summary>
    public IReadOnlyList<int> QuestRequirements { get; init; } = Array.Empty<int>();

    /// <summary>
    /// Items required to start.
    /// </summary>
    public IReadOnlyList<QuestItemRequirement> ItemRequirements { get; init; }
        = Array.Empty<QuestItemRequirement>();

    /// <summary>
    /// Combat level requirement.
    /// </summary>
    public int? CombatRequirement { get; init; }

    /// <summary>
    /// Quest stages/steps.
    /// </summary>
    public IReadOnlyList<QuestStage> Stages { get; init; } = Array.Empty<QuestStage>();

    /// <summary>
    /// Rewards given on completion.
    /// </summary>
    public QuestRewards Rewards { get; init; } = new();
}

/// <summary>
/// A stage/step within a quest.
/// </summary>
public sealed record QuestStage
{
    public required int StageId { get; init; }
    public required string Description { get; init; }
    public string? JournalEntry { get; init; }
}

/// <summary>
/// Item requirement for a quest.
/// </summary>
public sealed record QuestItemRequirement(int ItemId, int Amount, bool Consumed = false);

/// <summary>
/// Rewards for completing a quest.
/// </summary>
public sealed record QuestRewards
{
    /// <summary>
    /// Experience rewards by skill.
    /// </summary>
    public IReadOnlyDictionary<Skills.Skill, int> Experience { get; init; }
        = new Dictionary<Skills.Skill, int>();

    /// <summary>
    /// Item rewards.
    /// </summary>
    public IReadOnlyList<QuestItemReward> Items { get; init; } = Array.Empty<QuestItemReward>();

    /// <summary>
    /// Coins awarded.
    /// </summary>
    public int Coins { get; init; }

    /// <summary>
    /// Unlocks access to areas.
    /// </summary>
    public IReadOnlyList<string> AreaUnlocks { get; init; } = Array.Empty<string>();

    /// <summary>
    /// Unlocks ability to use items/equipment.
    /// </summary>
    public IReadOnlyList<int> ItemUnlocks { get; init; } = Array.Empty<int>();
}

/// <summary>
/// Item reward from a quest.
/// </summary>
public sealed record QuestItemReward(int ItemId, int Amount);

/// <summary>
/// Quest completion status.
/// </summary>
public enum QuestStatus
{
    NotStarted = 0,
    InProgress = 1,
    Completed = 2
}
