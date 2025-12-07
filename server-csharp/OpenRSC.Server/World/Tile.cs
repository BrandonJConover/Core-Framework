using OpenRSC.Server.Models;

namespace OpenRSC.Server.World;

/// <summary>
/// Represents a single tile in the game world.
/// </summary>
public sealed class Tile
{
    /// <summary>
    /// Tile position.
    /// </summary>
    public Point Location { get; }

    /// <summary>
    /// Terrain/ground type.
    /// </summary>
    public TerrainType Terrain { get; set; }

    /// <summary>
    /// Traversal flags indicating what can pass through.
    /// </summary>
    public TraversalFlags Flags { get; set; }

    /// <summary>
    /// Elevation level (0-3 in RSC).
    /// </summary>
    public int Elevation { get; set; }

    /// <summary>
    /// Ground overlay ID.
    /// </summary>
    public int OverlayId { get; set; }

    /// <summary>
    /// Whether this tile is indoors.
    /// </summary>
    public bool IsIndoors => Elevation > 0;

    /// <summary>
    /// Whether this tile blocks movement.
    /// </summary>
    public bool IsBlocked => Flags.HasFlag(TraversalFlags.FullBlock);

    public Tile(Point location)
    {
        Location = location;
        Terrain = TerrainType.Grass;
        Flags = TraversalFlags.None;
    }

    /// <summary>
    /// Checks if movement is allowed in a direction.
    /// </summary>
    public bool CanTraverse(Direction direction)
    {
        if (Flags.HasFlag(TraversalFlags.FullBlock))
            return false;

        return direction switch
        {
            Direction.North => !Flags.HasFlag(TraversalFlags.BlockNorth),
            Direction.South => !Flags.HasFlag(TraversalFlags.BlockSouth),
            Direction.East => !Flags.HasFlag(TraversalFlags.BlockEast),
            Direction.West => !Flags.HasFlag(TraversalFlags.BlockWest),
            Direction.NorthEast => !Flags.HasFlag(TraversalFlags.BlockNorth) &&
                                   !Flags.HasFlag(TraversalFlags.BlockEast),
            Direction.NorthWest => !Flags.HasFlag(TraversalFlags.BlockNorth) &&
                                   !Flags.HasFlag(TraversalFlags.BlockWest),
            Direction.SouthEast => !Flags.HasFlag(TraversalFlags.BlockSouth) &&
                                   !Flags.HasFlag(TraversalFlags.BlockEast),
            Direction.SouthWest => !Flags.HasFlag(TraversalFlags.BlockSouth) &&
                                   !Flags.HasFlag(TraversalFlags.BlockWest),
            _ => true
        };
    }

    /// <summary>
    /// Adds a blocking flag.
    /// </summary>
    public void AddBlock(TraversalFlags flag)
    {
        Flags |= flag;
    }

    /// <summary>
    /// Removes a blocking flag.
    /// </summary>
    public void RemoveBlock(TraversalFlags flag)
    {
        Flags &= ~flag;
    }
}

/// <summary>
/// Terrain/ground types.
/// </summary>
public enum TerrainType
{
    Grass,
    Path,
    Dirt,
    Sand,
    Water,
    Lava,
    Ice,
    Rock,
    Wood
}

/// <summary>
/// Movement direction.
/// </summary>
public enum Direction
{
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
    NorthWest
}

/// <summary>
/// Flags for tile traversal.
/// </summary>
[Flags]
public enum TraversalFlags
{
    None = 0,
    BlockNorth = 1 << 0,
    BlockSouth = 1 << 1,
    BlockEast = 1 << 2,
    BlockWest = 1 << 3,
    FullBlock = 1 << 4,
    ProjectileBlock = 1 << 5,
    WaterBlock = 1 << 6
}

/// <summary>
/// Extension methods for directions.
/// </summary>
public static class DirectionExtensions
{
    /// <summary>
    /// Gets the delta X for a direction.
    /// </summary>
    public static int GetDeltaX(this Direction direction) => direction switch
    {
        Direction.East or Direction.NorthEast or Direction.SouthEast => 1,
        Direction.West or Direction.NorthWest or Direction.SouthWest => -1,
        _ => 0
    };

    /// <summary>
    /// Gets the delta Y for a direction.
    /// </summary>
    public static int GetDeltaY(this Direction direction) => direction switch
    {
        Direction.North or Direction.NorthEast or Direction.NorthWest => 1,
        Direction.South or Direction.SouthEast or Direction.SouthWest => -1,
        _ => 0
    };

    /// <summary>
    /// Gets the opposite direction.
    /// </summary>
    public static Direction Opposite(this Direction direction) => direction switch
    {
        Direction.North => Direction.South,
        Direction.South => Direction.North,
        Direction.East => Direction.West,
        Direction.West => Direction.East,
        Direction.NorthEast => Direction.SouthWest,
        Direction.SouthWest => Direction.NorthEast,
        Direction.NorthWest => Direction.SouthEast,
        Direction.SouthEast => Direction.NorthWest,
        _ => direction
    };

    /// <summary>
    /// Calculates direction between two points.
    /// </summary>
    public static Direction? FromDelta(int dx, int dy)
    {
        return (dx, dy) switch
        {
            (0, 1) => Direction.North,
            (0, -1) => Direction.South,
            (1, 0) => Direction.East,
            (-1, 0) => Direction.West,
            (1, 1) => Direction.NorthEast,
            (-1, 1) => Direction.NorthWest,
            (1, -1) => Direction.SouthEast,
            (-1, -1) => Direction.SouthWest,
            _ => null
        };
    }
}
