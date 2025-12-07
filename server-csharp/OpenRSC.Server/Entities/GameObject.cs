using OpenRSC.Server.Models;

namespace OpenRSC.Server.Entities;

/// <summary>
/// Represents a game object (scenery, boundary) in the world.
/// </summary>
public class GameObject : Entity
{
    /// <summary>
    /// The object's definition ID.
    /// </summary>
    public int Id { get; }

    /// <summary>
    /// Direction/rotation of the object.
    /// </summary>
    public int Direction { get; }

    /// <summary>
    /// Type of object (0 = scenery, 1 = boundary/wall).
    /// </summary>
    public int Type { get; }

    public GameObject(int id, Point location, int direction = 0, int type = 0)
        : base(location)
    {
        Id = id;
        Direction = direction;
        Type = type;
    }
}
