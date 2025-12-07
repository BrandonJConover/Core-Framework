using System.Collections.Concurrent;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Achievement;

/// <summary>
/// Achievement category.
/// </summary>
public enum AchievementCategory
{
    Combat,
    Skilling,
    Quests,
    Exploration,
    Social,
    Wealth,
    Minigames,
    Special
}

/// <summary>
/// Achievement difficulty tier.
/// </summary>
public enum AchievementTier
{
    Easy,
    Medium,
    Hard,
    Elite,
    Master
}

/// <summary>
/// Type of achievement task.
/// </summary>
public enum AchievementTaskType
{
    ReachLevel,
    GainExperience,
    KillNpc,
    KillPlayer,
    CompleteQuest,
    VisitLocation,
    ObtainItem,
    EquipItem,
    UseItem,
    EarnGold,
    SpendGold,
    TradeComplete,
    JoinClan,
    Custom
}

/// <summary>
/// Defines a task within an achievement.
/// </summary>
public sealed record AchievementTask
{
    public required int Id { get; init; }
    public required string Description { get; init; }
    public required AchievementTaskType Type { get; init; }
    public int TargetValue { get; init; } = 1;
    public int? TargetId { get; init; } // NPC ID, Item ID, Quest ID, etc.
    public Skill? TargetSkill { get; init; }

    public static AchievementTask ReachLevel(int id, Skill skill, int level)
    {
        return new AchievementTask
        {
            Id = id,
            Description = $"Reach level {level} in {skill}",
            Type = AchievementTaskType.ReachLevel,
            TargetSkill = skill,
            TargetValue = level
        };
    }

    public static AchievementTask KillNpc(int id, int npcId, string npcName, int count = 1)
    {
        return new AchievementTask
        {
            Id = id,
            Description = count == 1 ? $"Kill a {npcName}" : $"Kill {count} {npcName}s",
            Type = AchievementTaskType.KillNpc,
            TargetId = npcId,
            TargetValue = count
        };
    }

    public static AchievementTask ObtainItem(int id, int itemId, string itemName, int count = 1)
    {
        return new AchievementTask
        {
            Id = id,
            Description = count == 1 ? $"Obtain a {itemName}" : $"Obtain {count} {itemName}s",
            Type = AchievementTaskType.ObtainItem,
            TargetId = itemId,
            TargetValue = count
        };
    }
}

/// <summary>
/// Reward for completing an achievement.
/// </summary>
public sealed record AchievementReward
{
    public int? ItemId { get; init; }
    public int ItemAmount { get; init; } = 1;
    public int? Gold { get; init; }
    public Dictionary<Skill, int>? Experience { get; init; }
    public int QuestPoints { get; init; }
    public string? UnlockTitle { get; init; }
}

/// <summary>
/// Defines an achievement.
/// </summary>
public sealed record AchievementDefinition
{
    public required int Id { get; init; }
    public required string Name { get; init; }
    public required string Description { get; init; }
    public required AchievementCategory Category { get; init; }
    public required AchievementTier Tier { get; init; }
    public required IReadOnlyList<AchievementTask> Tasks { get; init; }
    public AchievementReward? Reward { get; init; }
    public int[]? Prerequisites { get; init; } // Other achievement IDs
    public bool IsHidden { get; init; }

    public int Points => Tier switch
    {
        AchievementTier.Easy => 5,
        AchievementTier.Medium => 10,
        AchievementTier.Hard => 25,
        AchievementTier.Elite => 50,
        AchievementTier.Master => 100,
        _ => 0
    };
}

/// <summary>
/// Progress on an achievement.
/// </summary>
public sealed class AchievementProgress
{
    public int AchievementId { get; init; }
    public Dictionary<int, int> TaskProgress { get; } = new(); // TaskId -> Progress
    public bool IsComplete { get; set; }
    public DateTime? CompletedAt { get; set; }

    public int GetTaskProgress(int taskId)
    {
        return TaskProgress.GetValueOrDefault(taskId, 0);
    }

    public void SetTaskProgress(int taskId, int progress)
    {
        TaskProgress[taskId] = progress;
    }

    public void IncrementTaskProgress(int taskId, int amount = 1)
    {
        TaskProgress[taskId] = TaskProgress.GetValueOrDefault(taskId, 0) + amount;
    }
}

/// <summary>
/// Player's achievement progress tracking.
/// </summary>
public sealed class PlayerAchievements
{
    private readonly Player _player;
    private readonly IAchievementRepository _repository;
    private readonly Dictionary<int, AchievementProgress> _progress = new();
    private readonly HashSet<int> _completedIds = new();

    public int TotalPoints { get; private set; }
    public int CompletedCount => _completedIds.Count;
    public IReadOnlySet<int> CompletedAchievements => _completedIds;

    public PlayerAchievements(Player player, IAchievementRepository repository)
    {
        _player = player;
        _repository = repository;
    }

    /// <summary>
    /// Gets progress for an achievement.
    /// </summary>
    public AchievementProgress? GetProgress(int achievementId)
    {
        return _progress.GetValueOrDefault(achievementId);
    }

    /// <summary>
    /// Checks if an achievement is completed.
    /// </summary>
    public bool IsCompleted(int achievementId)
    {
        return _completedIds.Contains(achievementId);
    }

    /// <summary>
    /// Checks if all prerequisites are met.
    /// </summary>
    public bool MeetsPrerequisites(AchievementDefinition achievement)
    {
        if (achievement.Prerequisites is null)
            return true;

        return achievement.Prerequisites.All(IsCompleted);
    }

    /// <summary>
    /// Updates progress for a task.
    /// </summary>
    public void UpdateProgress(AchievementTaskType type, int? targetId = null, Skill? skill = null, int amount = 1)
    {
        foreach (var achievement in _repository.GetAll())
        {
            if (IsCompleted(achievement.Id))
                continue;

            if (!MeetsPrerequisites(achievement))
                continue;

            var progress = _progress.GetOrAdd(achievement.Id, () => new AchievementProgress { AchievementId = achievement.Id });

            var updated = false;
            foreach (var task in achievement.Tasks)
            {
                if (task.Type != type)
                    continue;

                if (targetId.HasValue && task.TargetId != targetId)
                    continue;

                if (skill.HasValue && task.TargetSkill != skill)
                    continue;

                progress.IncrementTaskProgress(task.Id, amount);
                updated = true;
            }

            if (updated)
            {
                CheckCompletion(achievement, progress);
            }
        }
    }

    /// <summary>
    /// Updates level-based progress.
    /// </summary>
    public void OnLevelUp(Skill skill, int newLevel)
    {
        foreach (var achievement in _repository.GetAll())
        {
            if (IsCompleted(achievement.Id))
                continue;

            var progress = _progress.GetOrAdd(achievement.Id, () => new AchievementProgress { AchievementId = achievement.Id });

            foreach (var task in achievement.Tasks)
            {
                if (task.Type == AchievementTaskType.ReachLevel && task.TargetSkill == skill)
                {
                    progress.SetTaskProgress(task.Id, newLevel);
                }
            }

            CheckCompletion(achievement, progress);
        }
    }

    private void CheckCompletion(AchievementDefinition achievement, AchievementProgress progress)
    {
        if (progress.IsComplete)
            return;

        var allComplete = achievement.Tasks.All(task =>
            progress.GetTaskProgress(task.Id) >= task.TargetValue);

        if (allComplete)
        {
            CompleteAchievement(achievement, progress);
        }
    }

    private void CompleteAchievement(AchievementDefinition achievement, AchievementProgress progress)
    {
        progress.IsComplete = true;
        progress.CompletedAt = DateTime.UtcNow;
        _completedIds.Add(achievement.Id);
        TotalPoints += achievement.Points;

        _player.Message($"Achievement complete: {achievement.Name}!");

        // Grant rewards
        if (achievement.Reward is { } reward)
        {
            GrantReward(reward);
        }
    }

    private void GrantReward(AchievementReward reward)
    {
        if (reward.Gold.HasValue)
        {
            // Would add gold
            _player.Message($"You receive {reward.Gold} gold!");
        }

        if (reward.ItemId.HasValue)
        {
            // Would add item
            _player.Message($"You receive an item!");
        }

        if (reward.Experience is not null)
        {
            foreach (var (skill, xp) in reward.Experience)
            {
                _player.Skills.AddExperience(skill, xp);
                _player.Message($"You gain {xp} {skill} experience!");
            }
        }

        if (reward.UnlockTitle is not null)
        {
            _player.Message($"You have unlocked the title: {reward.UnlockTitle}!");
        }
    }

    /// <summary>
    /// Loads achievement progress.
    /// </summary>
    public void Load(IEnumerable<AchievementProgress> progress)
    {
        foreach (var p in progress)
        {
            _progress[p.AchievementId] = p;
            if (p.IsComplete)
            {
                _completedIds.Add(p.AchievementId);
                var def = _repository.GetById(p.AchievementId);
                if (def is not null)
                {
                    TotalPoints += def.Points;
                }
            }
        }
    }

    /// <summary>
    /// Gets all progress for saving.
    /// </summary>
    public IEnumerable<AchievementProgress> GetAllProgress()
    {
        return _progress.Values;
    }
}

/// <summary>
/// Repository for achievement definitions.
/// </summary>
public interface IAchievementRepository
{
    AchievementDefinition? GetById(int id);
    IEnumerable<AchievementDefinition> GetAll();
    IEnumerable<AchievementDefinition> GetByCategory(AchievementCategory category);
}

/// <summary>
/// In-memory achievement repository.
/// </summary>
public sealed class InMemoryAchievementRepository : IAchievementRepository
{
    private readonly Dictionary<int, AchievementDefinition> _achievements = new();

    public InMemoryAchievementRepository()
    {
        InitializeDefaultAchievements();
    }

    private void InitializeDefaultAchievements()
    {
        // Combat achievements
        Add(new AchievementDefinition
        {
            Id = 1,
            Name = "First Blood",
            Description = "Kill your first enemy",
            Category = AchievementCategory.Combat,
            Tier = AchievementTier.Easy,
            Tasks = new[] { AchievementTask.KillNpc(1, 0, "enemy") }
        });

        Add(new AchievementDefinition
        {
            Id = 2,
            Name = "Dragon Slayer",
            Description = "Slay 100 dragons",
            Category = AchievementCategory.Combat,
            Tier = AchievementTier.Hard,
            Tasks = new[] { AchievementTask.KillNpc(1, 201, "dragon", 100) },
            Reward = new AchievementReward
            {
                Experience = new Dictionary<Skill, int> { [Skill.Attack] = 10000 }
            }
        });

        // Skilling achievements
        Add(new AchievementDefinition
        {
            Id = 10,
            Name = "Apprentice Miner",
            Description = "Reach level 30 Mining",
            Category = AchievementCategory.Skilling,
            Tier = AchievementTier.Easy,
            Tasks = new[] { AchievementTask.ReachLevel(1, Skill.Mining, 30) }
        });

        Add(new AchievementDefinition
        {
            Id = 11,
            Name = "Master Miner",
            Description = "Reach level 99 Mining",
            Category = AchievementCategory.Skilling,
            Tier = AchievementTier.Master,
            Tasks = new[] { AchievementTask.ReachLevel(1, Skill.Mining, 99) },
            Prerequisites = new[] { 10 },
            Reward = new AchievementReward
            {
                UnlockTitle = "Master Miner"
            }
        });

        Add(new AchievementDefinition
        {
            Id = 20,
            Name = "Total Level 500",
            Description = "Achieve a total level of 500",
            Category = AchievementCategory.Skilling,
            Tier = AchievementTier.Medium,
            Tasks = new[]
            {
                new AchievementTask
                {
                    Id = 1,
                    Description = "Reach total level 500",
                    Type = AchievementTaskType.Custom,
                    TargetValue = 500
                }
            }
        });

        // Wealth achievements
        Add(new AchievementDefinition
        {
            Id = 100,
            Name = "First Fortune",
            Description = "Earn 10,000 gold",
            Category = AchievementCategory.Wealth,
            Tier = AchievementTier.Easy,
            Tasks = new[]
            {
                new AchievementTask
                {
                    Id = 1,
                    Description = "Earn 10,000 gold",
                    Type = AchievementTaskType.EarnGold,
                    TargetValue = 10000
                }
            }
        });

        Add(new AchievementDefinition
        {
            Id = 101,
            Name = "Millionaire",
            Description = "Earn 1,000,000 gold",
            Category = AchievementCategory.Wealth,
            Tier = AchievementTier.Hard,
            Prerequisites = new[] { 100 },
            Tasks = new[]
            {
                new AchievementTask
                {
                    Id = 1,
                    Description = "Earn 1,000,000 gold",
                    Type = AchievementTaskType.EarnGold,
                    TargetValue = 1000000
                }
            },
            Reward = new AchievementReward
            {
                UnlockTitle = "Millionaire"
            }
        });
    }

    private void Add(AchievementDefinition achievement)
    {
        _achievements[achievement.Id] = achievement;
    }

    public AchievementDefinition? GetById(int id)
    {
        return _achievements.GetValueOrDefault(id);
    }

    public IEnumerable<AchievementDefinition> GetAll()
    {
        return _achievements.Values;
    }

    public IEnumerable<AchievementDefinition> GetByCategory(AchievementCategory category)
    {
        return _achievements.Values.Where(a => a.Category == category);
    }
}

/// <summary>
/// Extension helper.
/// </summary>
internal static class DictionaryExtensions
{
    public static TValue GetOrAdd<TKey, TValue>(this Dictionary<TKey, TValue> dict, TKey key, Func<TValue> factory)
        where TKey : notnull
    {
        if (!dict.TryGetValue(key, out var value))
        {
            value = factory();
            dict[key] = value;
        }
        return value;
    }
}
