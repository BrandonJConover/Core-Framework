using Microsoft.Extensions.Options;
using OpenRSC.Server.Actions;
using OpenRSC.Server.Combat;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Fatigue;
using OpenRSC.Server.Inventory;
using OpenRSC.Server.Magic;
using OpenRSC.Server.Models;
using OpenRSC.Server.Network;
using OpenRSC.Server.Prayer;
using OpenRSC.Server.Services;
using OpenRSC.Server.Skills;
using OpenRSC.Server.Skilling;
using OpenRSC.Server.Social;

namespace OpenRSC.Server.Entities;

/// <summary>
/// Represents a player character in the game world.
/// </summary>
public class Player : Mob
{
    private readonly ServerSettings? _serverSettings;
    private readonly ActionRetrySettings? _actionRetrySettings;

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
    /// Whether the player is skulled (PvP penalty).
    /// </summary>
    public bool IsSkulled { get; set; }

    /// <summary>
    /// When the skull expires.
    /// </summary>
    public DateTime? SkullExpiry { get; set; }

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
    /// Player's skills and experience.
    /// </summary>
    public PlayerSkills Skills { get; }

    /// <summary>
    /// Player's inventory.
    /// </summary>
    public PlayerInventory Inventory { get; }

    /// <summary>
    /// Player's bank.
    /// </summary>
    public PlayerBank Bank { get; }

    /// <summary>
    /// Player's equipped items.
    /// </summary>
    public Equipment Equipment { get; }

    /// <summary>
    /// Player's spell casting system.
    /// </summary>
    public SpellCaster SpellCaster { get; }

    /// <summary>
    /// Player's active prayers.
    /// </summary>
    public PlayerPrayers Prayers { get; }

    /// <summary>
    /// Player's privacy settings.
    /// </summary>
    public PrivacySettings PrivacySettings { get; } = new();

    /// <summary>
    /// Player's social manager (friends/ignores).
    /// Initialized when WorldService is available.
    /// </summary>
    public SocialManager? Social { get; set; }

    /// <summary>
    /// The GameClient associated with this player.
    /// </summary>
    public GameClient? Client { get; private set; }

    /// <summary>
    /// Action sender for client packet communication.
    /// </summary>
    public ActionSender? ActionSender { get; private set; }

    /// <summary>
    /// Player's fatigue level (RSC-specific).
    /// </summary>
    public PlayerFatigue Fatigue { get; }

    /// <summary>
    /// Player's current prayer points.
    /// </summary>
    public int CurrentPrayerPoints { get; set; }

    /// <summary>
    /// Player's current skill action being performed.
    /// </summary>
    public SkillAction? CurrentAction { get; set; }

    /// <summary>
    /// Player's combat settings.
    /// </summary>
    public PlayerCombatSettings CombatSettings { get; } = new();

    /// <summary>
    /// Whether the player has admin privileges.
    /// </summary>
    public bool IsAdmin { get; set; }

    /// <summary>
    /// Whether the player is muted from chat.
    /// </summary>
    public bool IsMuted { get; set; }

    /// <summary>
    /// When the mute expires.
    /// </summary>
    public DateTime? MuteExpiry { get; set; }

    /// <summary>
    /// Last time the player ate food (for combat delays).
    /// </summary>
    public DateTime LastFoodTick { get; set; }

    /// <summary>
    /// Timestamp of last player activity.
    /// </summary>
    public DateTime LastActivity { get; private set; }

    /// <summary>
    /// Timestamp of last movement.
    /// </summary>
    public DateTime LastMoved { get; private set; }

    /// <summary>
    /// The player being followed, if any.
    /// </summary>
    public Player? FollowingTarget { get; private set; }

    /// <summary>
    /// Timestamp of last save.
    /// </summary>
    public DateTime LastSaveTime { get; set; }

    /// <summary>
    /// Whether the player's appearance has changed this tick (equipment change).
    /// </summary>
    public bool HasChangedAppearance { get; private set; }

    /// <summary>
    /// Gets the action retry settings for this player.
    /// </summary>
    public ActionRetrySettings ActionRetryConfig => _actionRetrySettings ?? new ActionRetrySettings();

    public override bool IsPlayer => true;
    public override bool IsNpc => false;

    /// <summary>
    /// Creates a player with full configuration (for DI).
    /// </summary>
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
        Skills = new PlayerSkills(this);
        Inventory = new PlayerInventory(this);
        Bank = new PlayerBank(this);
        Equipment = new Equipment(this);
        Prayers = new PlayerPrayers(this);
        SpellCaster = new SpellCaster(this);
        Fatigue = new PlayerFatigue(this);
        LastActivity = DateTime.UtcNow;
        LastMoved = DateTime.UtcNow;
        LastSaveTime = DateTime.UtcNow;
    }

    /// <summary>
    /// Creates a player without DI (for testing).
    /// </summary>
    public Player(string username, Point location)
        : base(location)
    {
        Username = username;
        UsernameHash = ComputeUsernameHash(username);
        WalkingQueue = new WalkingQueue(this);
        Skills = new PlayerSkills(this);
        Inventory = new PlayerInventory(this);
        Bank = new PlayerBank(this);
        Equipment = new Equipment(this);
        Prayers = new PlayerPrayers(this);
        SpellCaster = new SpellCaster(this);
        Fatigue = new PlayerFatigue(this);
        LastActivity = DateTime.UtcNow;
        LastMoved = DateTime.UtcNow;
        LastSaveTime = DateTime.UtcNow;
    }

    /// <summary>
    /// Sets the player's combat level.
    /// </summary>
    public void SetCombatLevel(int level)
    {
        CombatLevel = level;
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
    /// Associates a GameClient with this player and creates the ActionSender.
    /// </summary>
    public void SetClient(GameClient client)
    {
        Client = client;
        ActionSender = new ActionSender(client, this);
    }

    /// <summary>
    /// Disconnects the client from this player.
    /// </summary>
    public void ClearClient()
    {
        Client = null;
        ActionSender = null;
    }

    /// <summary>
    /// Sends a message to the player's chat.
    /// </summary>
    public void Message(string text)
    {
        _ = ActionSender?.SendMessageAsync(text);
    }

    /// <summary>
    /// Receives a private message from another player.
    /// </summary>
    public void ReceivePrivateMessage(long senderHash, int messageId, string message)
    {
        _ = ActionSender?.SendPrivateMessageAsync(senderHash, message);
    }

    /// <summary>
    /// Sends the player's inventory to the client.
    /// </summary>
    public void SendInventory()
    {
        _ = ActionSender?.SendInventoryAsync();
    }

    /// <summary>
    /// Sends the player's stats to the client.
    /// </summary>
    public void SendStats()
    {
        _ = ActionSender?.SendStatsAsync();
    }

    /// <summary>
    /// Sends equipment bonuses to the client.
    /// </summary>
    public void SendEquipmentBonuses()
    {
        _ = ActionSender?.SendEquipmentBonusesAsync();
    }

    /// <summary>
    /// Starts following another player.
    /// </summary>
    public void StartFollowing(Player target)
    {
        FollowingTarget = target;
        // Clear any current walk-to action
        SetWalkToAction(null);
    }

    /// <summary>
    /// Stops following any player.
    /// </summary>
    public void StopFollowing()
    {
        FollowingTarget = null;
    }

    /// <summary>
    /// Processes following logic during the tick.
    /// </summary>
    public void ProcessFollowing()
    {
        if (FollowingTarget is null || FollowingTarget.IsRemoved || !FollowingTarget.IsLoggedIn)
        {
            StopFollowing();
            return;
        }

        // Check if target is still in range
        var distance = Location.DistanceTo(FollowingTarget.Location);
        if (distance > 16)
        {
            Message("You've lost sight of your target.");
            StopFollowing();
            return;
        }

        // If already adjacent, don't move
        if (distance <= 1)
        {
            return;
        }

        // Add path to target's location
        WalkingQueue.Reset();

        // Simple pathfinding - move one step towards target
        var dx = Math.Sign(FollowingTarget.Location.X - Location.X);
        var dy = Math.Sign(FollowingTarget.Location.Y - Location.Y);

        var nextStep = new Point(Location.X + dx, Location.Y + dy);
        WalkingQueue.AddStep(nextStep);
    }

    /// <summary>
    /// Marks the player as logged in.
    /// </summary>
    public void Login()
    {
        IsLoggedIn = true;
        LastActivity = DateTime.UtcNow;
        Social?.OnLogin();
    }

    /// <summary>
    /// Logs out the player.
    /// </summary>
    public void Logout()
    {
        IsLoggedIn = false;
        Social?.OnLogout();
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
    /// Applies a skull to the player.
    /// </summary>
    public void ApplySkull(TimeSpan duration)
    {
        IsSkulled = true;
        SkullExpiry = DateTime.UtcNow + duration;
    }

    /// <summary>
    /// Removes the skull if expired.
    /// </summary>
    public void UpdateSkull()
    {
        if (IsSkulled && SkullExpiry.HasValue && DateTime.UtcNow >= SkullExpiry.Value)
        {
            IsSkulled = false;
            SkullExpiry = null;
        }
    }

    /// <summary>
    /// Clears the skull immediately (e.g., on death).
    /// </summary>
    public void ClearSkull()
    {
        IsSkulled = false;
        SkullExpiry = null;
    }

    /// <summary>
    /// Teleports the player to a new location.
    /// </summary>
    public void Teleport(Point destination)
    {
        WalkingQueue.Reset();
        Location = destination;
        HasMoved = true;
    }

    /// <summary>
    /// Resets player state after update cycle.
    /// </summary>
    public override void ResetAfterUpdate()
    {
        base.ResetAfterUpdate();
        HasChangedAppearance = false;
        UpdateSkull();
        Prayers.ProcessDrain();
    }

    /// <summary>
    /// Marks the player's appearance as changed (e.g., after equipping/unequipping).
    /// </summary>
    public void MarkAppearanceChanged()
    {
        HasChangedAppearance = true;
    }

    private static long ComputeUsernameHash(string username)
    {
        // Simple hash using polynomial rolling hash (base 37)
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
