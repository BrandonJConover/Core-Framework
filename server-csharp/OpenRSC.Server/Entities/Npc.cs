using OpenRSC.Server.Models;
using OpenRSC.Server.Npc;

namespace OpenRSC.Server.Entities;

/// <summary>
/// Represents a non-player character in the game world.
/// </summary>
public class Npc : Mob
{
    private readonly NpcDefinition? _definition;
    private Point _spawnLocation;
    private DateTime _deathTime;

    /// <summary>
    /// The NPC's definition/template (null for legacy NPCs without definitions).
    /// </summary>
    public NpcDefinition? Definition => _definition;

    /// <summary>
    /// NPC catalog ID.
    /// </summary>
    public int NpcId => _definition?.Id ?? Id;

    /// <summary>
    /// The NPC's definition ID (legacy support).
    /// </summary>
    public int Id { get; }

    /// <summary>
    /// Display name.
    /// </summary>
    public string Name => _definition?.Name ?? $"NPC({Id})";

    /// <summary>
    /// Original spawn location.
    /// </summary>
    public Point SpawnLocation => _spawnLocation;

    /// <summary>
    /// Whether this NPC is attackable.
    /// </summary>
    public bool IsAttackable => _definition?.IsAttackable ?? false;

    /// <summary>
    /// Whether this NPC is aggressive.
    /// </summary>
    public bool IsAggressive => _definition?.IsAggressive ?? false;

    /// <summary>
    /// Time in ticks until respawn.
    /// </summary>
    public int RespawnTicks => _definition?.RespawnTicks ?? 50;

    /// <summary>
    /// Whether this NPC is currently respawning.
    /// </summary>
    public bool IsRespawning { get; private set; }

    /// <summary>
    /// Whether this NPC is currently teleporting.
    /// </summary>
    public bool IsTeleporting { get; private set; }

    /// <summary>
    /// Time when this NPC will respawn.
    /// </summary>
    public DateTime? RespawnTime { get; private set; }

    /// <summary>
    /// Current AI behavior.
    /// </summary>
    public INpcBehavior? Behavior { get; set; }

    /// <summary>
    /// Whether the NPC is currently dead (waiting for respawn).
    /// </summary>
    public bool IsDead { get; private set; }

    /// <summary>
    /// Target player for aggressive NPCs.
    /// </summary>
    public Player? AggroTarget { get; set; }

    public override bool IsNpc => true;
    public override bool IsPlayer => false;

    /// <summary>
    /// Creates an NPC with full definition.
    /// </summary>
    public Npc(NpcDefinition definition, Point spawnLocation)
        : base(spawnLocation)
    {
        _definition = definition;
        Id = definition.Id;
        _spawnLocation = spawnLocation;
        CurrentHitpoints = definition.Hitpoints;
        MaxHitpoints = definition.Hitpoints;
        CombatLevel = definition.CombatLevel;
    }

    /// <summary>
    /// Creates an NPC with just an ID (legacy support).
    /// </summary>
    public Npc(int id, Point location) : base(location)
    {
        Id = id;
        _spawnLocation = location;
    }

    /// <summary>
    /// Sets the spawn location (for respawning).
    /// </summary>
    public void SetSpawnLocation(Point location)
    {
        _spawnLocation = location;
    }

    /// <summary>
    /// Processes the NPC's AI tick.
    /// </summary>
    public void ProcessAI()
    {
        if (IsDead || IsRemoved || InCombat)
            return;

        Behavior?.Execute(this);
    }

    /// <summary>
    /// Handles NPC death.
    /// </summary>
    public void Die()
    {
        IsDead = true;
        _deathTime = DateTime.UtcNow;
        EndCombat();

        // Hide the NPC
        IsRemoved = true;
    }

    /// <summary>
    /// Starts the respawn timer for this NPC.
    /// </summary>
    public void StartRespawn(TimeSpan delay)
    {
        IsRespawning = true;
        RespawnTime = DateTime.UtcNow + delay;
    }

    /// <summary>
    /// Completes the respawn, making the NPC active again.
    /// </summary>
    public void CompleteRespawn(Point? spawnLocation = null)
    {
        IsDead = false;
        IsRespawning = false;
        RespawnTime = null;
        Location = spawnLocation ?? _spawnLocation;
        CurrentHitpoints = _definition?.Hitpoints ?? MaxHitpoints;
        AggroTarget = null;
        IsRemoved = false;
    }

    /// <summary>
    /// Respawns the NPC at its spawn location.
    /// </summary>
    public void Respawn() => CompleteRespawn();

    /// <summary>
    /// Gets the time since death.
    /// </summary>
    public TimeSpan TimeSinceDeath => IsDead ? DateTime.UtcNow - _deathTime : TimeSpan.Zero;

    /// <summary>
    /// Checks if enough time has passed for respawn.
    /// </summary>
    public bool CanRespawn(int tickDurationMs)
    {
        if (!IsDead) return false;
        var respawnTimeMs = RespawnTicks * tickDurationMs;
        return TimeSinceDeath.TotalMilliseconds >= respawnTimeMs;
    }

    /// <summary>
    /// Walk towards a target location.
    /// </summary>
    public void WalkTowards(Point target, int maxDistance = 1)
    {
        if (Location == target)
            return;

        var dx = Math.Sign(target.X - Location.X);
        var dy = Math.Sign(target.Y - Location.Y);

        // Simple movement - should use pathfinding in production
        Location = new Point(Location.X + dx, Location.Y + dy);
        HasMoved = true;
    }

    /// <summary>
    /// Walk randomly within roaming distance.
    /// </summary>
    public void WalkRandom()
    {
        if (_definition is not null && !_definition.CanRoam)
            return;

        var roamDistance = _definition?.RoamDistance ?? 5;
        var dx = Random.Shared.Next(-1, 2);
        var dy = Random.Shared.Next(-1, 2);

        var newX = Location.X + dx;
        var newY = Location.Y + dy;

        // Check roaming bounds
        if (Math.Abs(newX - _spawnLocation.X) <= roamDistance &&
            Math.Abs(newY - _spawnLocation.Y) <= roamDistance)
        {
            Location = new Point(newX, newY);
            HasMoved = true;
        }
    }

    /// <summary>
    /// Return to spawn location.
    /// </summary>
    public void ReturnToSpawn()
    {
        WalkTowards(_spawnLocation);
    }

    /// <summary>
    /// Teleports the NPC to a new location.
    /// </summary>
    public void Teleport(Point destination)
    {
        IsTeleporting = true;
        Location = destination;
    }

    public override void ResetAfterUpdate()
    {
        base.ResetAfterUpdate();
        IsTeleporting = false;
    }
}
