using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Quests;

/// <summary>
/// Manages a player's quest progress.
/// </summary>
public sealed class PlayerQuests
{
    private readonly Player _player;
    private readonly IQuestRepository _questRepository;
    private readonly Dictionary<int, QuestProgress> _progress = new();

    /// <summary>
    /// Total quest points earned.
    /// </summary>
    public int QuestPoints { get; private set; }

    /// <summary>
    /// Event raised when quest progress changes.
    /// </summary>
    public event Action<int, QuestStatus, int>? QuestProgressChanged;

    public PlayerQuests(Player player, IQuestRepository questRepository)
    {
        _player = player;
        _questRepository = questRepository;
    }

    /// <summary>
    /// Gets the status of a quest.
    /// </summary>
    public QuestStatus GetStatus(int questId)
    {
        return _progress.TryGetValue(questId, out var progress)
            ? progress.Status
            : QuestStatus.NotStarted;
    }

    /// <summary>
    /// Gets the current stage of a quest.
    /// </summary>
    public int GetStage(int questId)
    {
        return _progress.TryGetValue(questId, out var progress)
            ? progress.CurrentStage
            : 0;
    }

    /// <summary>
    /// Checks if a quest is completed.
    /// </summary>
    public bool IsCompleted(int questId) => GetStatus(questId) == QuestStatus.Completed;

    /// <summary>
    /// Checks if the player meets requirements to start a quest.
    /// </summary>
    public QuestRequirementResult CheckRequirements(int questId)
    {
        var quest = _questRepository.GetById(questId);
        if (quest is null)
            return QuestRequirementResult.Fail("Quest not found.");

        // Check skill requirements
        foreach (var (skill, level) in quest.SkillRequirements)
        {
            if (_player.Skills.GetMaxLevel(skill) < level)
            {
                return QuestRequirementResult.Fail(
                    $"You need level {level} {skill.GetDisplayName()} to start this quest.");
            }
        }

        // Check quest requirements
        foreach (var requiredQuestId in quest.QuestRequirements)
        {
            if (!IsCompleted(requiredQuestId))
            {
                var requiredQuest = _questRepository.GetById(requiredQuestId);
                return QuestRequirementResult.Fail(
                    $"You must complete {requiredQuest?.Name ?? "another quest"} first.");
            }
        }

        // Check combat level
        if (quest.CombatRequirement.HasValue && _player.CombatLevel < quest.CombatRequirement.Value)
        {
            return QuestRequirementResult.Fail(
                $"You need combat level {quest.CombatRequirement.Value} to start this quest.");
        }

        return QuestRequirementResult.Success;
    }

    /// <summary>
    /// Starts a quest.
    /// </summary>
    public QuestResult StartQuest(int questId)
    {
        var quest = _questRepository.GetById(questId);
        if (quest is null)
            return QuestResult.Fail("Quest not found.");

        if (GetStatus(questId) != QuestStatus.NotStarted)
            return QuestResult.Fail("You have already started this quest.");

        var requirements = CheckRequirements(questId);
        if (!requirements.Met)
            return QuestResult.Fail(requirements.Message!);

        _progress[questId] = new QuestProgress
        {
            QuestId = questId,
            Status = QuestStatus.InProgress,
            CurrentStage = 0,
            StartedAt = DateTime.UtcNow
        };

        QuestProgressChanged?.Invoke(questId, QuestStatus.InProgress, 0);
        _player.Message($"You have started the quest: {quest.Name}");

        return QuestResult.Success;
    }

    /// <summary>
    /// Advances to the next quest stage.
    /// </summary>
    public QuestResult AdvanceStage(int questId, int newStage)
    {
        if (!_progress.TryGetValue(questId, out var progress))
            return QuestResult.Fail("You haven't started this quest.");

        if (progress.Status == QuestStatus.Completed)
            return QuestResult.Fail("You have already completed this quest.");

        var quest = _questRepository.GetById(questId);
        if (quest is null)
            return QuestResult.Fail("Quest not found.");

        if (newStage <= progress.CurrentStage)
            return QuestResult.Fail("Invalid stage progression.");

        progress.CurrentStage = newStage;

        // Show journal entry if available
        var stage = quest.Stages.FirstOrDefault(s => s.StageId == newStage);
        if (stage?.JournalEntry is not null)
        {
            _player.Message(stage.JournalEntry);
        }

        QuestProgressChanged?.Invoke(questId, QuestStatus.InProgress, newStage);

        return QuestResult.Success;
    }

    /// <summary>
    /// Completes a quest and grants rewards.
    /// </summary>
    public QuestResult CompleteQuest(int questId, IItemFactory? itemFactory = null)
    {
        if (!_progress.TryGetValue(questId, out var progress))
            return QuestResult.Fail("You haven't started this quest.");

        if (progress.Status == QuestStatus.Completed)
            return QuestResult.Fail("You have already completed this quest.");

        var quest = _questRepository.GetById(questId);
        if (quest is null)
            return QuestResult.Fail("Quest not found.");

        // Mark as completed
        progress.Status = QuestStatus.Completed;
        progress.CompletedAt = DateTime.UtcNow;

        // Award quest points
        QuestPoints += quest.QuestPoints;

        // Grant rewards
        GrantRewards(quest.Rewards, itemFactory);

        _player.Message($"Congratulations! Quest complete: {quest.Name}");
        _player.Message($"You have earned {quest.QuestPoints} quest point(s).");

        QuestProgressChanged?.Invoke(questId, QuestStatus.Completed, progress.CurrentStage);

        return QuestResult.Success;
    }

    private void GrantRewards(QuestRewards rewards, IItemFactory? itemFactory)
    {
        // Grant experience
        foreach (var (skill, xp) in rewards.Experience)
        {
            _player.Skills.AddExperience(skill, xp);
            _player.Message($"You gain {xp} {skill.GetDisplayName()} experience.");
        }

        // Grant coins
        if (rewards.Coins > 0 && itemFactory is not null)
        {
            _player.Inventory.Add(10, rewards.Coins, itemFactory); // 10 = coins item ID
            _player.Message($"You receive {rewards.Coins} coins.");
        }

        // Grant items
        if (itemFactory is not null)
        {
            foreach (var itemReward in rewards.Items)
            {
                _player.Inventory.Add(itemReward.ItemId, itemReward.Amount, itemFactory);
            }
        }
    }

    /// <summary>
    /// Gets all quest progress.
    /// </summary>
    public IEnumerable<QuestProgress> GetAllProgress() => _progress.Values;

    /// <summary>
    /// Gets completed quest count.
    /// </summary>
    public int CompletedCount => _progress.Values.Count(p => p.Status == QuestStatus.Completed);

    /// <summary>
    /// Loads quest progress from saved data.
    /// </summary>
    public void Load(IEnumerable<QuestProgress> progress)
    {
        _progress.Clear();
        QuestPoints = 0;

        foreach (var p in progress)
        {
            _progress[p.QuestId] = p;
            if (p.Status == QuestStatus.Completed)
            {
                var quest = _questRepository.GetById(p.QuestId);
                if (quest is not null)
                {
                    QuestPoints += quest.QuestPoints;
                }
            }
        }
    }
}

/// <summary>
/// Tracks progress for a single quest.
/// </summary>
public sealed class QuestProgress
{
    public required int QuestId { get; init; }
    public QuestStatus Status { get; set; }
    public int CurrentStage { get; set; }
    public DateTime StartedAt { get; init; }
    public DateTime? CompletedAt { get; set; }
}

/// <summary>
/// Result of checking quest requirements.
/// </summary>
public readonly record struct QuestRequirementResult(bool Met, string? Message = null)
{
    public static QuestRequirementResult Fail(string message) => new(false, message);
    public static readonly QuestRequirementResult Success = new(true);
}

/// <summary>
/// Result of a quest operation.
/// </summary>
public readonly record struct QuestResult(bool Success, string? Message = null)
{
    public static QuestResult Fail(string message) => new(false, message);
    public static readonly QuestResult Success = new(true);
}

/// <summary>
/// Repository for quest definitions.
/// </summary>
public interface IQuestRepository
{
    QuestDefinition? GetById(int questId);
    IEnumerable<QuestDefinition> GetAll();
}
