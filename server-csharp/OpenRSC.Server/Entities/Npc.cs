using OpenRSC.Server.Models;

namespace OpenRSC.Server.Entities;

/// <summary>
/// Represents a non-player character in the game world.
/// </summary>
public class Npc : Mob
{
    /// <summary>
    /// The NPC's definition ID.
    /// </summary>
    public int Id { get; }

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

    public override bool IsNpc => true;

    public Npc(int id, Point location) : base(location)
    {
        Id = id;
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
    public void CompleteRespawn(Point spawnLocation)
    {
        IsRespawning = false;
        RespawnTime = null;
        Location = spawnLocation;
        CurrentHitpoints = MaxHitpoints;
        IsRemoved = false;
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
