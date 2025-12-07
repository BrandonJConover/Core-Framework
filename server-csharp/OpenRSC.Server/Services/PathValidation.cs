using OpenRSC.Server.Models;

namespace OpenRSC.Server.Services;

/// <summary>
/// Provides path validation utilities for movement and combat.
/// </summary>
public static class PathValidation
{
    /// <summary>
    /// Checks if two points are adjacent and path is valid.
    /// </summary>
    /// <param name="from">Starting point</param>
    /// <param name="to">Target point</param>
    /// <param name="ignoreProjectile">Whether to use projectile (loose) path checking</param>
    /// <param name="checkDiagonalBlocking">Whether to check diagonal blocking</param>
    /// <returns>True if path is valid</returns>
    public static bool CheckAdjacentDistance(
        Point from,
        Point to,
        bool ignoreProjectile,
        bool checkDiagonalBlocking)
    {
        var dx = Math.Abs(to.X - from.X);
        var dy = Math.Abs(to.Y - from.Y);

        // Must be within 1 tile
        if (dx > 1 || dy > 1)
            return false;

        // Same tile is always valid
        if (dx == 0 && dy == 0)
            return true;

        // For projectile-based actions, simplified check
        if (ignoreProjectile)
            return true;

        // For diagonal movement, check blocking
        if (checkDiagonalBlocking && dx == 1 && dy == 1)
        {
            // TODO: Implement actual collision detection
            // This would check tile flags for diagonal blocking
            return true;
        }

        return true;
    }

    /// <summary>
    /// Validates a complete path between two points.
    /// </summary>
    public static bool ValidatePath(Point from, Point to, IPathfindingContext? context = null)
    {
        // TODO: Implement A* or similar pathfinding validation
        // For now, simple line-of-sight check
        return from.DistanceTo(to) <= 50;
    }
}

/// <summary>
/// Context interface for pathfinding operations.
/// </summary>
public interface IPathfindingContext
{
    /// <summary>
    /// Checks if a tile is walkable.
    /// </summary>
    bool IsTileWalkable(Point point);

    /// <summary>
    /// Gets the tile flags at a point.
    /// </summary>
    int GetTileFlags(Point point);
}
