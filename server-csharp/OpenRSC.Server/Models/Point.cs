namespace OpenRSC.Server.Models;

/// <summary>
/// Represents a 2D coordinate in the game world.
/// Using a readonly record struct for value semantics and immutability.
/// </summary>
public readonly record struct Point(int X, int Y)
{
    /// <summary>
    /// Calculates the Pythagorean distance to another point.
    /// </summary>
    public double DistanceTo(Point other)
    {
        var dx = X - other.X;
        var dy = Y - other.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    /// <summary>
    /// Checks if this point is within a specified range of another point.
    /// </summary>
    public bool WithinRange(Point other, int radius)
        => DistanceTo(other) <= radius;

    /// <summary>
    /// Checks if this point is within specified bounds.
    /// </summary>
    public bool InBounds(int minX, int minY, int maxX, int maxY)
        => X >= minX && X <= maxX && Y >= minY && Y <= maxY;

    /// <summary>
    /// Returns a new point translated by the specified offsets.
    /// </summary>
    public Point Translate(int dx, int dy) => new(X + dx, Y + dy);

    public override string ToString() => $"({X}, {Y})";
}
