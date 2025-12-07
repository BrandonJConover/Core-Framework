using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Log definition for firemaking.
/// </summary>
public sealed record FiremakingLogDefinition
{
    public required int LogId { get; init; }
    public required string Name { get; init; }
    public required int RequiredLevel { get; init; }
    public required int Experience { get; init; }
    public int BurnDuration { get; init; } = 100; // Ticks fire lasts

    public static readonly IReadOnlyDictionary<int, FiremakingLogDefinition> All = new Dictionary<int, FiremakingLogDefinition>
    {
        [14] = new() { LogId = 14, Name = "Logs", RequiredLevel = 1, Experience = 25, BurnDuration = 60 },
        [632] = new() { LogId = 632, Name = "Oak logs", RequiredLevel = 15, Experience = 37, BurnDuration = 90 },
        [633] = new() { LogId = 633, Name = "Willow logs", RequiredLevel = 30, Experience = 67, BurnDuration = 120 },
        [634] = new() { LogId = 634, Name = "Maple logs", RequiredLevel = 45, Experience = 100, BurnDuration = 150 },
        [635] = new() { LogId = 635, Name = "Yew logs", RequiredLevel = 60, Experience = 175, BurnDuration = 200 },
        [636] = new() { LogId = 636, Name = "Magic logs", RequiredLevel = 75, Experience = 250, BurnDuration = 300 }
    };
}

/// <summary>
/// Tinderbox item.
/// </summary>
public static class FiremakingItems
{
    public const int TinderboxId = 166;
    public const int FireObjectId = 97; // Fire object spawned
    public const int AshesId = 181;
}

/// <summary>
/// Firemaking action.
/// </summary>
public sealed class FiremakingAction : SkillAction
{
    private readonly FiremakingLogDefinition _log;
    private readonly Point _location;
    private readonly Action<Point, int, int>? _onFireLit; // Callback to spawn fire

    public override Skill Skill => Skill.Firemaking;

    public FiremakingAction(Player player, FiremakingLogDefinition log, Point location, Action<Point, int, int>? onFireLit = null)
        : base(player, CalculateTicks(player, log))
    {
        _log = log;
        _location = location;
        _onFireLit = onFireLit;
    }

    private static int CalculateTicks(Player player, FiremakingLogDefinition log)
    {
        var level = player.Skills.GetCurrentLevel(Skill.Firemaking);
        var levelDiff = level - log.RequiredLevel;
        return Math.Max(2, 4 - levelDiff / 20);
    }

    protected override void OnComplete()
    {
        var level = Player.Skills.GetCurrentLevel(Skill.Firemaking);
        var successChance = 0.5 + (level - _log.RequiredLevel) * 0.02;

        if (Random.Shared.NextDouble() < successChance)
        {
            // Successfully lit fire
            Player.Skills.AddExperience(Skill.Firemaking, _log.Experience);
            Player.Message("The fire catches and the logs begin to burn.");

            // Spawn fire object at location
            _onFireLit?.Invoke(_location, FiremakingItems.FireObjectId, _log.BurnDuration);

            // Move player west (standard firemaking behavior)
            MovePlayerFromFire();
        }
        else
        {
            Player.Message("You fail to light the logs.");
            // Retry - logs still consumed on failure in RSC
            TicksRemaining = CalculateTicks(Player, _log);
        }
    }

    private void MovePlayerFromFire()
    {
        // In RSC, players move west after lighting a fire
        var newLocation = new Point(_location.X - 1, _location.Y);
        Player.Location = newLocation;
    }

    protected override void OnTick()
    {
        if (TicksRemaining == 2)
        {
            Player.Message("You attempt to light the logs...");
        }
    }
}

/// <summary>
/// Firemaking skill manager.
/// </summary>
public static class FiremakingManager
{
    /// <summary>
    /// Attempts to light logs on fire.
    /// </summary>
    public static SkillActionResult StartFiremaking(
        Player player,
        int logId,
        Func<Point, bool>? canPlaceFire = null,
        Action<Point, int, int>? onFireLit = null)
    {
        // Check for tinderbox
        if (!player.Inventory.HasItem(FiremakingItems.TinderboxId))
        {
            return SkillActionResult.Fail("You need a tinderbox to light a fire.");
        }

        // Check for logs
        if (!player.Inventory.HasItem(logId))
        {
            return SkillActionResult.Fail("You don't have any logs to burn.");
        }

        if (!FiremakingLogDefinition.All.TryGetValue(logId, out var log))
        {
            return SkillActionResult.Fail("You cannot light these logs.");
        }

        var fmLevel = player.Skills.GetCurrentLevel(Skill.Firemaking);
        if (fmLevel < log.RequiredLevel)
        {
            return SkillActionResult.Fail($"You need level {log.RequiredLevel} Firemaking to light {log.Name.ToLower()}.");
        }

        // Check if fire can be placed at location
        var fireLocation = player.Location;
        if (canPlaceFire is not null && !canPlaceFire(fireLocation))
        {
            return SkillActionResult.Fail("You can't light a fire here.");
        }

        // Remove logs from inventory
        player.Inventory.Remove(logId, 1);

        player.Message("You attempt to light the logs...");
        return SkillActionResult.Ok(new FiremakingAction(player, log, fireLocation, onFireLit));
    }

    /// <summary>
    /// Uses tinderbox on logs (item on item).
    /// </summary>
    public static SkillActionResult UseTinderboxOnLogs(
        Player player,
        int logId,
        Func<Point, bool>? canPlaceFire = null,
        Action<Point, int, int>? onFireLit = null)
    {
        return StartFiremaking(player, logId, canPlaceFire, onFireLit);
    }
}

/// <summary>
/// Fire object that burns and eventually becomes ashes.
/// </summary>
public sealed class FireObject
{
    public Point Location { get; }
    public int RemainingTicks { get; private set; }

    public bool IsBurning => RemainingTicks > 0;

    public FireObject(Point location, int duration)
    {
        Location = location;
        RemainingTicks = duration;
    }

    /// <summary>
    /// Processes a tick.
    /// </summary>
    /// <returns>True if fire is still burning.</returns>
    public bool Tick()
    {
        if (RemainingTicks > 0)
        {
            RemainingTicks--;
        }
        return IsBurning;
    }
}
