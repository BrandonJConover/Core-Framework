using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Agility obstacle definition.
/// </summary>
public sealed record ObstacleDefinition
{
    public required int ObjectId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public required int Ticks { get; init; }
    public Point? Destination { get; init; }
    public int FailDamage { get; init; }
    public double BaseSuccessRate { get; init; } = 1.0; // Some obstacles can't fail
}

/// <summary>
/// Agility course definition.
/// </summary>
public sealed record AgilityCourseDefinition
{
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required IReadOnlyList<CourseObstacle> Obstacles { get; init; }
    public required int CompletionBonus { get; init; } // Bonus XP for completing full course

    public static readonly IReadOnlyDictionary<string, AgilityCourseDefinition> All = new Dictionary<string, AgilityCourseDefinition>
    {
        ["gnome"] = new()
        {
            Name = "Gnome Stronghold Course",
            RequiredLevel = 1,
            CompletionBonus = 39,
            Obstacles = new[]
            {
                new CourseObstacle(1, "Log balance", 1, 7, 4, 0.95),
                new CourseObstacle(2, "Obstacle net", 1, 7, 3, 1.0),
                new CourseObstacle(3, "Tree branch", 1, 5, 2, 1.0),
                new CourseObstacle(4, "Balancing rope", 1, 7, 4, 0.9),
                new CourseObstacle(5, "Tree branch down", 1, 5, 2, 1.0),
                new CourseObstacle(6, "Obstacle net", 1, 7, 3, 1.0),
                new CourseObstacle(7, "Obstacle pipe", 1, 7, 4, 1.0)
            }
        },
        ["barbarian"] = new()
        {
            Name = "Barbarian Outpost Course",
            RequiredLevel = 35,
            CompletionBonus = 139,
            Obstacles = new[]
            {
                new CourseObstacle(1, "Rope swing", 35, 22, 3, 0.85),
                new CourseObstacle(2, "Log balance", 35, 13, 5, 0.9),
                new CourseObstacle(3, "Obstacle net", 35, 8, 3, 1.0),
                new CourseObstacle(4, "Ledge", 35, 22, 4, 0.9),
                new CourseObstacle(5, "Crumbling wall", 35, 17, 3, 0.95)
            }
        },
        ["wilderness"] = new()
        {
            Name = "Wilderness Course",
            RequiredLevel = 52,
            CompletionBonus = 499,
            Obstacles = new[]
            {
                new CourseObstacle(1, "Obstacle pipe", 52, 12, 4, 0.9),
                new CourseObstacle(2, "Ropeswing", 52, 20, 3, 0.8),
                new CourseObstacle(3, "Stepping stone", 52, 20, 5, 0.85),
                new CourseObstacle(4, "Log balance", 52, 20, 5, 0.85),
                new CourseObstacle(5, "Rocks", 52, 0, 3, 1.0) // Finish
            }
        }
    };
}

/// <summary>
/// A single obstacle in a course.
/// </summary>
public sealed record CourseObstacle(
    int Sequence,
    string Name,
    int RequiredLevel,
    int Experience,
    int Ticks,
    double SuccessRate,
    int FailDamage = 2
);

/// <summary>
/// Shortcut definition.
/// </summary>
public sealed record ShortcutDefinition
{
    public required int ObjectId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required Point StartLocation { get; init; }
    public required Point EndLocation { get; init; }
    public int Ticks { get; init; } = 2;

    public static readonly IReadOnlyList<ShortcutDefinition> All = new List<ShortcutDefinition>
    {
        new() { ObjectId = 100, Name = "Underwall tunnel", RequiredLevel = 16, StartLocation = new Point(3067, 3261), EndLocation = new Point(3067, 3264) },
        new() { ObjectId = 101, Name = "Stepping stones", RequiredLevel = 31, StartLocation = new Point(2516, 3592), EndLocation = new Point(2516, 3598) },
        new() { ObjectId = 102, Name = "Pipe squeeze", RequiredLevel = 46, StartLocation = new Point(2575, 9867), EndLocation = new Point(2575, 9876) },
        new() { ObjectId = 103, Name = "Crevice", RequiredLevel = 63, StartLocation = new Point(2769, 9556), EndLocation = new Point(2769, 9561) },
        new() { ObjectId = 104, Name = "Rocks", RequiredLevel = 73, StartLocation = new Point(2427, 3435), EndLocation = new Point(2427, 3432) },
    };
}

/// <summary>
/// Tracks a player's progress through an agility course.
/// </summary>
public sealed class CourseProgress
{
    public string CourseName { get; init; }
    public int CurrentObstacle { get; private set; }
    public int TotalObstacles { get; init; }
    public DateTime StartedAt { get; init; }

    public bool IsComplete => CurrentObstacle >= TotalObstacles;

    public CourseProgress(string courseName, int totalObstacles)
    {
        CourseName = courseName;
        TotalObstacles = totalObstacles;
        CurrentObstacle = 0;
        StartedAt = DateTime.UtcNow;
    }

    public void CompleteObstacle()
    {
        CurrentObstacle++;
    }

    public void Reset()
    {
        CurrentObstacle = 0;
    }
}

/// <summary>
/// Agility obstacle action.
/// </summary>
public sealed class AgilityObstacleAction : SkillAction
{
    private readonly CourseObstacle _obstacle;
    private readonly CourseProgress? _courseProgress;
    private readonly AgilityCourseDefinition? _course;
    private readonly Point? _destination;
    private readonly Action<bool>? _onComplete; // Callback with success/failure

    public override Skill Skill => Skill.Agility;

    public AgilityObstacleAction(
        Player player,
        CourseObstacle obstacle,
        CourseProgress? progress = null,
        AgilityCourseDefinition? course = null,
        Point? destination = null,
        Action<bool>? onComplete = null)
        : base(player, obstacle.Ticks)
    {
        _obstacle = obstacle;
        _courseProgress = progress;
        _course = course;
        _destination = destination;
        _onComplete = onComplete;
    }

    protected override void OnComplete()
    {
        var level = Player.Skills.GetCurrentLevel(Skill.Agility);
        var successChance = CalculateSuccessChance(level);

        if (Random.Shared.NextDouble() < successChance)
        {
            // Success
            Player.Skills.AddExperience(Skill.Agility, _obstacle.Experience);

            if (_destination.HasValue)
            {
                Player.Location = _destination.Value;
            }

            _courseProgress?.CompleteObstacle();

            // Check for course completion bonus
            if (_courseProgress?.IsComplete == true && _course is not null)
            {
                Player.Skills.AddExperience(Skill.Agility, _course.CompletionBonus);
                Player.Message($"You completed the {_course.Name}!");
                _courseProgress.Reset();
            }

            _onComplete?.Invoke(true);
        }
        else
        {
            // Failure
            Player.Message("You slip and fall!");
            Player.Damage(_obstacle.FailDamage);

            _courseProgress?.Reset();
            _onComplete?.Invoke(false);
        }
    }

    private double CalculateSuccessChance(int level)
    {
        if (_obstacle.SuccessRate >= 1.0)
            return 1.0;

        var levelBonus = (level - _obstacle.RequiredLevel) * 0.005;
        return Math.Min(0.99, _obstacle.SuccessRate + levelBonus);
    }

    protected override void OnTick()
    {
        // Show animation message
        if (TicksRemaining == _obstacle.Ticks - 1)
        {
            Player.Message($"You attempt the {_obstacle.Name.ToLower()}...");
        }
    }
}

/// <summary>
/// Shortcut action.
/// </summary>
public sealed class ShortcutAction : SkillAction
{
    private readonly ShortcutDefinition _shortcut;

    public override Skill Skill => Skill.Agility;

    public ShortcutAction(Player player, ShortcutDefinition shortcut)
        : base(player, shortcut.Ticks)
    {
        _shortcut = shortcut;
    }

    protected override void OnComplete()
    {
        Player.Location = _shortcut.EndLocation;
        Player.Message($"You pass through the {_shortcut.Name.ToLower()}.");
    }
}

/// <summary>
/// Agility skill manager.
/// </summary>
public static class AgilityManager
{
    private static readonly Dictionary<Player, CourseProgress> _courseProgress = new();

    /// <summary>
    /// Attempts an agility obstacle.
    /// </summary>
    public static SkillActionResult AttemptObstacle(
        Player player,
        string courseName,
        int obstacleSequence,
        Point? destination = null,
        Action<bool>? onComplete = null)
    {
        if (!AgilityCourseDefinition.All.TryGetValue(courseName, out var course))
            return SkillActionResult.Fail("Unknown agility course.");

        var level = player.Skills.GetCurrentLevel(Skill.Agility);
        if (level < course.RequiredLevel)
            return SkillActionResult.Fail($"You need level {course.RequiredLevel} Agility for this course.");

        var obstacle = course.Obstacles.FirstOrDefault(o => o.Sequence == obstacleSequence);
        if (obstacle is null)
            return SkillActionResult.Fail("Invalid obstacle.");

        // Get or create course progress
        if (!_courseProgress.TryGetValue(player, out var progress) || progress.CourseName != courseName)
        {
            progress = new CourseProgress(courseName, course.Obstacles.Count);
            _courseProgress[player] = progress;
        }

        // Check if doing obstacles in order
        if (obstacleSequence != progress.CurrentObstacle + 1)
        {
            progress.Reset();
        }

        return SkillActionResult.Ok(new AgilityObstacleAction(player, obstacle, progress, course, destination, onComplete));
    }

    /// <summary>
    /// Attempts to use a shortcut.
    /// </summary>
    public static SkillActionResult UseShortcut(Player player, int objectId)
    {
        var shortcut = ShortcutDefinition.All.FirstOrDefault(s => s.ObjectId == objectId);
        if (shortcut is null)
            return SkillActionResult.Fail("This is not a shortcut.");

        var level = player.Skills.GetCurrentLevel(Skill.Agility);
        if (level < shortcut.RequiredLevel)
            return SkillActionResult.Fail($"You need level {shortcut.RequiredLevel} Agility to use this shortcut.");

        player.Message($"You use the {shortcut.Name.ToLower()}...");
        return SkillActionResult.Ok(new ShortcutAction(player, shortcut));
    }

    /// <summary>
    /// Clears course progress for a player (e.g., on logout).
    /// </summary>
    public static void ClearProgress(Player player)
    {
        _courseProgress.Remove(player);
    }

    /// <summary>
    /// Gets run energy restoration rate based on agility level.
    /// </summary>
    public static double GetEnergyRestorationRate(int agilityLevel)
    {
        // Higher agility = faster energy recovery
        return 1.0 + agilityLevel * 0.01;
    }

    /// <summary>
    /// Gets weight reduction from graceful outfit pieces.
    /// </summary>
    public static int GetGracefulWeightReduction(Player player)
    {
        // Would check for graceful outfit pieces
        return 0;
    }
}
