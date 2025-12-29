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
    /// Direction/rotation of the object (0-3).
    /// </summary>
    public int Direction { get; set; }

    /// <summary>
    /// Type of object (0 = scenery, 1 = boundary/wall).
    /// </summary>
    public int Type { get; }

    /// <summary>
    /// Whether this object blocks movement.
    /// </summary>
    public bool IsBlocking { get; set; }

    /// <summary>
    /// Whether this object has been removed from the world.
    /// </summary>
    public bool IsRemoved { get; private set; }

    /// <summary>
    /// Object width in tiles.
    /// </summary>
    public int Width { get; init; } = 1;

    /// <summary>
    /// Object height in tiles.
    /// </summary>
    public int Height { get; init; } = 1;

    /// <summary>
    /// Whether this is a boundary object (door, gate, etc.).
    /// </summary>
    public bool IsBoundary => Type == 1;

    public GameObject(int id, Point location, int direction = 0, int type = 0)
        : base(location)
    {
        Id = id;
        Direction = direction;
        Type = type;
    }

    /// <summary>
    /// Marks the object as removed.
    /// </summary>
    public void Remove()
    {
        IsRemoved = true;
    }

    /// <summary>
    /// Restores a removed object.
    /// </summary>
    public void Restore()
    {
        IsRemoved = false;
    }

    /// <summary>
    /// Gets all tiles occupied by this object.
    /// </summary>
    public IEnumerable<Point> GetOccupiedTiles()
    {
        for (var dx = 0; dx < Width; dx++)
        {
            for (var dy = 0; dy < Height; dy++)
            {
                yield return new Point(Location.X + dx, Location.Y + dy);
            }
        }
    }

    /// <summary>
    /// Checks if a point is within this object's bounds.
    /// </summary>
    public bool Contains(Point point)
    {
        return point.X >= Location.X && point.X < Location.X + Width &&
               point.Y >= Location.Y && point.Y < Location.Y + Height;
    }
}
