using System.Runtime.CompilerServices;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Services;

/// <summary>
/// Provides path validation utilities for movement and combat.
/// Implements line-of-sight checks and path validation.
/// </summary>
public static class PathValidation
{
    /// <summary>
    /// Tile flags for collision detection.
    /// </summary>
    [Flags]
    public enum TileFlags
    {
        None = 0,
        BlockedNorth = 1 << 0,
        BlockedEast = 1 << 1,
        BlockedSouth = 1 << 2,
        BlockedWest = 1 << 3,
        BlockedNorthEast = 1 << 4,
        BlockedNorthWest = 1 << 5,
        BlockedSouthEast = 1 << 6,
        BlockedSouthWest = 1 << 7,
        FullBlock = 1 << 8,
        Water = 1 << 9,
        ProjectileBlocking = 1 << 10
    }

    /// <summary>
    /// Checks if two points are adjacent and path is valid.
    /// </summary>
    /// <param name="from">Starting point</param>
    /// <param name="to">Target point</param>
    /// <param name="ignoreProjectile">Whether to use projectile (loose) path checking</param>
    /// <param name="checkDiagonalBlocking">Whether to check diagonal blocking</param>
    /// <param name="context">Optional pathfinding context for tile data</param>
    /// <returns>True if path is valid</returns>
    public static bool CheckAdjacentDistance(
        Point from,
        Point to,
        bool ignoreProjectile,
        bool checkDiagonalBlocking,
        IPathfindingContext? context = null)
    {
        var dx = to.X - from.X;
        var dy = to.Y - from.Y;
        var absDx = Math.Abs(dx);
        var absDy = Math.Abs(dy);

        // Must be within 1 tile
        if (absDx > 1 || absDy > 1)
            return false;

        // Same tile is always valid
        if (absDx == 0 && absDy == 0)
            return true;

        // If no context provided, use simplified check
        if (context is null)
        {
            return true;
        }

        // Check if destination is walkable
        if (!context.IsTileWalkable(to))
            return false;

        var tileFlags = (TileFlags)context.GetTileFlags(from);

        // For projectile-based actions, only check projectile blocking
        if (ignoreProjectile)
        {
            return !tileFlags.HasFlag(TileFlags.ProjectileBlocking);
        }

        // Cardinal movement checks
        if (absDx == 0 || absDy == 0)
        {
            return IsCardinalMovementAllowed(tileFlags, dx, dy);
        }

        // Diagonal movement checks
        if (checkDiagonalBlocking && absDx == 1 && absDy == 1)
        {
            return IsDiagonalMovementAllowed(from, to, dx, dy, context);
        }

        return true;
    }

    /// <summary>
    /// Checks if cardinal (N/E/S/W) movement is allowed.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static bool IsCardinalMovementAllowed(TileFlags flags, int dx, int dy)
    {
        if (dx > 0 && flags.HasFlag(TileFlags.BlockedEast)) return false;
        if (dx < 0 && flags.HasFlag(TileFlags.BlockedWest)) return false;
        if (dy > 0 && flags.HasFlag(TileFlags.BlockedNorth)) return false;
        if (dy < 0 && flags.HasFlag(TileFlags.BlockedSouth)) return false;
        return true;
    }

    /// <summary>
    /// Checks if diagonal movement is allowed (checks both intermediate tiles).
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static bool IsDiagonalMovementAllowed(
        Point from, Point to,
        int dx, int dy,
        IPathfindingContext context)
    {
        // For diagonal movement, check that we can move through the intermediate tiles
        var horizontal = new Point(from.X + dx, from.Y);
        var vertical = new Point(from.X, from.Y + dy);

        // Must be able to walk through at least one intermediate tile
        var canMoveHorizontalFirst = context.IsTileWalkable(horizontal);
        var canMoveVerticalFirst = context.IsTileWalkable(vertical);

        if (!canMoveHorizontalFirst && !canMoveVerticalFirst)
            return false;

        // Check destination tile flags for diagonal blocking
        var destFlags = (TileFlags)context.GetTileFlags(to);

        if (dx > 0 && dy > 0 && destFlags.HasFlag(TileFlags.BlockedSouthWest)) return false;
        if (dx > 0 && dy < 0 && destFlags.HasFlag(TileFlags.BlockedNorthWest)) return false;
        if (dx < 0 && dy > 0 && destFlags.HasFlag(TileFlags.BlockedSouthEast)) return false;
        if (dx < 0 && dy < 0 && destFlags.HasFlag(TileFlags.BlockedNorthEast)) return false;

        return true;
    }

    /// <summary>
    /// Validates a complete path between two points using Bresenham line algorithm.
    /// </summary>
    public static bool ValidatePath(Point from, Point to, IPathfindingContext? context = null)
    {
        // Same point is always valid
        if (from == to)
            return true;

        // If no context, use simple distance check
        if (context is null)
            return from.DistanceTo(to) <= 50;

        // Use Bresenham's line algorithm for line-of-sight check
        return HasLineOfSight(from, to, context, checkProjectileBlocking: false);
    }

    /// <summary>
    /// Checks line-of-sight between two points using Bresenham's algorithm.
    /// </summary>
    public static bool HasLineOfSight(
        Point from,
        Point to,
        IPathfindingContext context,
        bool checkProjectileBlocking = true)
    {
        var x0 = from.X;
        var y0 = from.Y;
        var x1 = to.X;
        var y1 = to.Y;

        var dx = Math.Abs(x1 - x0);
        var dy = Math.Abs(y1 - y0);
        var sx = x0 < x1 ? 1 : -1;
        var sy = y0 < y1 ? 1 : -1;
        var err = dx - dy;

        while (true)
        {
            // Skip the starting point
            if (x0 != from.X || y0 != from.Y)
            {
                var current = new Point(x0, y0);

                if (!context.IsTileWalkable(current))
                    return false;

                if (checkProjectileBlocking)
                {
                    var flags = (TileFlags)context.GetTileFlags(current);
                    if (flags.HasFlag(TileFlags.ProjectileBlocking))
                        return false;
                }
            }

            if (x0 == x1 && y0 == y1)
                break;

            var e2 = 2 * err;
            if (e2 > -dy)
            {
                err -= dy;
                x0 += sx;
            }
            if (e2 < dx)
            {
                err += dx;
                y0 += sy;
            }
        }

        return true;
    }

    /// <summary>
    /// Checks if a projectile can reach from source to target.
    /// </summary>
    public static bool CanProjectileReach(Point from, Point to, IPathfindingContext context, int maxRange = 10)
    {
        if (from.DistanceTo(to) > maxRange)
            return false;

        return HasLineOfSight(from, to, context, checkProjectileBlocking: true);
    }

    /// <summary>
    /// Finds the closest walkable tile to the target within range.
    /// </summary>
    public static Point? FindClosestWalkableTile(
        Point target,
        Point from,
        IPathfindingContext context,
        int maxSearchRadius = 3)
    {
        if (context.IsTileWalkable(target))
            return target;

        Point? closest = null;
        var closestDistance = double.MaxValue;

        for (var dx = -maxSearchRadius; dx <= maxSearchRadius; dx++)
        {
            for (var dy = -maxSearchRadius; dy <= maxSearchRadius; dy++)
            {
                var candidate = new Point(target.X + dx, target.Y + dy);

                if (!context.IsTileWalkable(candidate))
                    continue;

                var distance = from.DistanceTo(candidate);
                if (distance < closestDistance)
                {
                    closestDistance = distance;
                    closest = candidate;
                }
            }
        }

        return closest;
    }

    /// <summary>
    /// Gets the direction from one point to another.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static int GetDirection(Point from, Point to)
    {
        var dx = Math.Sign(to.X - from.X);
        var dy = Math.Sign(to.Y - from.Y);

        // RSC uses a specific direction encoding
        return (dx, dy) switch
        {
            (0, 1) => 0,   // North
            (1, 1) => 1,   // NorthEast
            (1, 0) => 2,   // East
            (1, -1) => 3,  // SouthEast
            (0, -1) => 4,  // South
            (-1, -1) => 5, // SouthWest
            (-1, 0) => 6,  // West
            (-1, 1) => 7,  // NorthWest
            _ => -1        // Same tile or invalid
        };
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

/// <summary>
/// Simple pathfinding context that uses a walkability delegate.
/// </summary>
public sealed class SimplePathfindingContext : IPathfindingContext
{
    private readonly Func<Point, bool> _walkabilityCheck;
    private readonly Func<Point, int>? _flagsCheck;

    public SimplePathfindingContext(
        Func<Point, bool> walkabilityCheck,
        Func<Point, int>? flagsCheck = null)
    {
        _walkabilityCheck = walkabilityCheck;
        _flagsCheck = flagsCheck;
    }

    public bool IsTileWalkable(Point point) => _walkabilityCheck(point);
    public int GetTileFlags(Point point) => _flagsCheck?.Invoke(point) ?? 0;
}
