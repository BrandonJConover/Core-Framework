using OpenRSC.Server.Models;

namespace OpenRSC.Server.Entities;

/// <summary>
/// Base class for all game entities (players, NPCs, items, objects).
/// </summary>
public abstract class Entity
{
    private static int _nextIndex;

    /// <summary>
    /// Unique index for this entity in the world.
    /// </summary>
    public int Index { get; }

    /// <summary>
    /// Current location of the entity.
    /// </summary>
    public Point Location { get; protected set; }

    /// <summary>
    /// Whether this entity has been removed from the world.
    /// </summary>
    public bool IsRemoved { get; protected set; }

    protected Entity(Point location)
    {
        Index = Interlocked.Increment(ref _nextIndex);
        Location = location;
    }

    /// <summary>
    /// Checks if this entity is a player.
    /// </summary>
    public virtual bool IsPlayer => false;

    /// <summary>
    /// Checks if this entity is an NPC.
    /// </summary>
    public virtual bool IsNpc => false;

    /// <summary>
    /// Marks this entity as removed from the world.
    /// </summary>
    public virtual void Remove()
    {
        IsRemoved = true;
    }

    /// <summary>
    /// Checks if this entity is within range of another entity.
    /// </summary>
    public bool WithinRange(Entity other, int radius)
        => Location.WithinRange(other.Location, radius);
}
