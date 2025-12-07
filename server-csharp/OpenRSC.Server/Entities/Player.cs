using Microsoft.Extensions.Options;
using OpenRSC.Server.Actions;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Entities;

/// <summary>
/// Represents a player character in the game world.
/// </summary>
public class Player : Mob
{
    private readonly ServerSettings _serverSettings;
    private readonly ActionRetrySettings _actionRetrySettings;

    /// <summary>
    /// Player's username.
    /// </summary>
    public string Username { get; }

    /// <summary>
    /// Hashed username for efficient lookups.
    /// </summary>
    public long UsernameHash { get; }

    /// <summary>
    /// Whether the player is currently logged in.
    /// </summary>
    public bool IsLoggedIn { get; private set; }

    /// <summary>
    /// The current walk-to action being executed.
    /// </summary>
    public WalkToAction? WalkToAction { get; private set; }

    /// <summary>
    /// The last successfully executed walk-to action.
    /// </summary>
    public WalkToAction? LastExecutedWalkToAction { get; private set; }

    /// <summary>
    /// Player's walking queue for pathfinding.
    /// </summary>
    public WalkingQueue WalkingQueue { get; }

    /// <summary>
    /// Timestamp of last player activity.
    /// </summary>
    public DateTime LastActivity { get; private set; }

    /// <summary>
    /// Timestamp of last movement.
    /// </summary>
    public DateTime LastMoved { get; private set; }

    /// <summary>
    /// Timestamp of last save.
    /// </summary>
    public DateTime LastSaveTime { get; set; }

    /// <summary>
    /// Gets the action retry settings for this player.
    /// </summary>
    public ActionRetrySettings ActionRetryConfig => _actionRetrySettings;

    public override bool IsPlayer => true;

    public Player(
        string username,
        Point location,
        IOptions<ServerSettings> serverSettings,
        IOptions<ActionRetrySettings> actionRetrySettings)
        : base(location)
    {
        Username = username;
        UsernameHash = ComputeUsernameHash(username);
        _serverSettings = serverSettings.Value;
        _actionRetrySettings = actionRetrySettings.Value;
        WalkingQueue = new WalkingQueue(this);
        LastActivity = DateTime.UtcNow;
        LastMoved = DateTime.UtcNow;
        LastSaveTime = DateTime.UtcNow;
    }

    /// <summary>
    /// Sets the current walk-to action.
    /// </summary>
    public void SetWalkToAction(WalkToAction? action)
    {
        WalkToAction = action;
    }

    /// <summary>
    /// Records the last executed walk-to action.
    /// </summary>
    public void SetLastExecutedWalkToAction(WalkToAction action)
    {
        LastExecutedWalkToAction = action;
    }

    /// <summary>
    /// Sends a message to the player's chat.
    /// </summary>
    public void Message(string text)
    {
        // TODO: Implement actual message sending via ActionSender
        Console.WriteLine($"[{Username}] {text}");
    }

    /// <summary>
    /// Marks the player as logged in.
    /// </summary>
    public void Login()
    {
        IsLoggedIn = true;
        LastActivity = DateTime.UtcNow;
    }

    /// <summary>
    /// Logs out the player.
    /// </summary>
    public void Logout()
    {
        IsLoggedIn = false;
    }

    /// <summary>
    /// Updates the player's position based on their walking queue.
    /// </summary>
    public void UpdatePosition()
    {
        var nextPoint = WalkingQueue.ProcessNextMovement();
        if (nextPoint.HasValue && nextPoint.Value != Location)
        {
            Location = nextPoint.Value;
            HasMoved = true;
            LastMoved = DateTime.UtcNow;
        }
    }

    /// <summary>
    /// Checks if the player is at/adjacent to a game object.
    /// </summary>
    public bool AtObject(GameObject gameObject)
    {
        // Simplified check - in real implementation, considers object bounds
        return Location.WithinRange(gameObject.Location, 1);
    }

    /// <summary>
    /// Resets player state after update cycle.
    /// </summary>
    public override void ResetAfterUpdate()
    {
        base.ResetAfterUpdate();
        // Additional player-specific reset logic
    }

    private static long ComputeUsernameHash(string username)
    {
        // Simple hash implementation - matches Java version
        var hash = 0L;
        foreach (var c in username.ToLowerInvariant())
        {
            hash = hash * 37 + c;
        }
        return hash;
    }
}

/// <summary>
/// Manages player movement pathfinding.
/// </summary>
public class WalkingQueue
{
    private readonly Player _player;
    private readonly Queue<Point> _path = new();

    public WalkingQueue(Player player)
    {
        _player = player;
    }

    /// <summary>
    /// Adds a waypoint to the walking path.
    /// </summary>
    public void AddStep(Point point)
    {
        if (_path.Count < 50) // Max path length
        {
            _path.Enqueue(point);
        }
    }

    /// <summary>
    /// Clears the current path.
    /// </summary>
    public void Reset()
    {
        _path.Clear();
    }

    /// <summary>
    /// Gets the next movement point without removing it.
    /// </summary>
    public Point GetNextMovement()
    {
        return _path.Count > 0 ? _path.Peek() : _player.Location;
    }

    /// <summary>
    /// Processes and returns the next movement, removing it from the queue.
    /// </summary>
    public Point? ProcessNextMovement()
    {
        return _path.Count > 0 ? _path.Dequeue() : null;
    }

    /// <summary>
    /// Whether there are pending movements.
    /// </summary>
    public bool HasPendingSteps => _path.Count > 0;
}
