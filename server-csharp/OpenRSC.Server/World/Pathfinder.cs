using OpenRSC.Server.Models;

namespace OpenRSC.Server.World;

/// <summary>
/// A* pathfinding algorithm for the game world.
/// </summary>
public sealed class Pathfinder
{
    private readonly WorldMap _worldMap;
    private readonly int _maxSearchDistance;

    public Pathfinder(WorldMap worldMap, int maxSearchDistance = 100)
    {
        _worldMap = worldMap;
        _maxSearchDistance = maxSearchDistance;
    }

    /// <summary>
    /// Finds a path between two points using A*.
    /// </summary>
    /// <returns>List of points from start to end, or empty if no path found.</returns>
    public List<Point> FindPath(Point start, Point end)
    {
        if (start == end)
            return new List<Point> { start };

        if (!WorldMap.IsValidLocation(end))
            return new List<Point>();

        var openSet = new PriorityQueue<PathNode, int>();
        var closedSet = new HashSet<Point>();
        var cameFrom = new Dictionary<Point, Point>();
        var gScore = new Dictionary<Point, int> { [start] = 0 };

        var startNode = new PathNode(start, 0, Heuristic(start, end));
        openSet.Enqueue(startNode, startNode.FScore);

        while (openSet.Count > 0)
        {
            var current = openSet.Dequeue();

            if (current.Position == end)
                return ReconstructPath(cameFrom, end);

            if (closedSet.Contains(current.Position))
                continue;

            closedSet.Add(current.Position);

            // Check if we've searched too far
            if (current.GScore > _maxSearchDistance)
                continue;

            foreach (var neighbor in GetNeighbors(current.Position))
            {
                if (closedSet.Contains(neighbor))
                    continue;

                if (!_worldMap.CanMove(current.Position, neighbor))
                    continue;

                var tentativeGScore = gScore[current.Position] + MovementCost(current.Position, neighbor);

                if (!gScore.TryGetValue(neighbor, out var currentGScore) || tentativeGScore < currentGScore)
                {
                    cameFrom[neighbor] = current.Position;
                    gScore[neighbor] = tentativeGScore;

                    var fScore = tentativeGScore + Heuristic(neighbor, end);
                    openSet.Enqueue(new PathNode(neighbor, tentativeGScore, fScore), fScore);
                }
            }
        }

        // No path found - return partial path to closest point
        return FindPartialPath(start, end, cameFrom, gScore);
    }

    /// <summary>
    /// Finds a path that gets as close as possible to the target.
    /// </summary>
    public List<Point> FindPathToRange(Point start, Point end, int range)
    {
        if (start.WithinRange(end, range))
            return new List<Point> { start };

        // Find points within range of target
        var candidates = new List<(Point Point, int Distance)>();
        for (var dx = -range; dx <= range; dx++)
        {
            for (var dy = -range; dy <= range; dy++)
            {
                var candidate = new Point(end.X + dx, end.Y + dy);
                if (candidate.WithinRange(end, range) && WorldMap.IsValidLocation(candidate))
                {
                    var dist = (int)start.DistanceTo(candidate);
                    candidates.Add((candidate, dist));
                }
            }
        }

        // Sort by distance to start and try each
        foreach (var (candidate, _) in candidates.OrderBy(c => c.Distance))
        {
            var path = FindPath(start, candidate);
            if (path.Count > 0)
                return path;
        }

        return new List<Point>();
    }

    private static IEnumerable<Point> GetNeighbors(Point point)
    {
        // 8-directional movement
        yield return new Point(point.X, point.Y + 1);     // North
        yield return new Point(point.X, point.Y - 1);     // South
        yield return new Point(point.X + 1, point.Y);     // East
        yield return new Point(point.X - 1, point.Y);     // West
        yield return new Point(point.X + 1, point.Y + 1); // NE
        yield return new Point(point.X - 1, point.Y + 1); // NW
        yield return new Point(point.X + 1, point.Y - 1); // SE
        yield return new Point(point.X - 1, point.Y - 1); // SW
    }

    private static int Heuristic(Point a, Point b)
    {
        // Chebyshev distance (allows diagonal movement)
        return Math.Max(Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));
    }

    private static int MovementCost(Point from, Point to)
    {
        // Diagonal movement costs slightly more (approximation of sqrt(2))
        var dx = Math.Abs(to.X - from.X);
        var dy = Math.Abs(to.Y - from.Y);
        return dx + dy > 1 ? 14 : 10; // 14 ≈ 10 * sqrt(2)
    }

    private static List<Point> ReconstructPath(Dictionary<Point, Point> cameFrom, Point current)
    {
        var path = new List<Point> { current };
        while (cameFrom.TryGetValue(current, out var previous))
        {
            path.Add(previous);
            current = previous;
        }
        path.Reverse();
        return path;
    }

    private List<Point> FindPartialPath(Point start, Point end, Dictionary<Point, Point> cameFrom, Dictionary<Point, int> gScore)
    {
        // Find the explored point closest to the destination
        Point? closest = null;
        var closestDistance = int.MaxValue;

        foreach (var point in gScore.Keys)
        {
            var dist = (int)point.DistanceTo(end);
            if (dist < closestDistance)
            {
                closestDistance = dist;
                closest = point;
            }
        }

        if (closest.HasValue && closest.Value != start)
            return ReconstructPath(cameFrom, closest.Value);

        return new List<Point>();
    }

    private readonly record struct PathNode(Point Position, int GScore, int FScore);
}

/// <summary>
/// Represents a computed path with utilities.
/// </summary>
public sealed class Path
{
    private readonly List<Point> _points;
    private int _currentIndex;

    public IReadOnlyList<Point> Points => _points;
    public int Length => _points.Count;
    public bool IsComplete => _currentIndex >= _points.Count;
    public Point? Destination => _points.Count > 0 ? _points[^1] : null;
    public Point? Current => _currentIndex < _points.Count ? _points[_currentIndex] : null;
    public int RemainingSteps => Math.Max(0, _points.Count - _currentIndex);

    public Path(List<Point> points)
    {
        _points = points;
        _currentIndex = 0;
    }

    public static Path Empty => new(new List<Point>());

    /// <summary>
    /// Gets the next point in the path and advances.
    /// </summary>
    public Point? GetNextStep()
    {
        if (_currentIndex >= _points.Count)
            return null;

        return _points[_currentIndex++];
    }

    /// <summary>
    /// Peeks at the next point without advancing.
    /// </summary>
    public Point? PeekNextStep()
    {
        return _currentIndex < _points.Count ? _points[_currentIndex] : null;
    }

    /// <summary>
    /// Resets path to beginning.
    /// </summary>
    public void Reset()
    {
        _currentIndex = 0;
    }

    /// <summary>
    /// Skips the first N steps (useful when starting mid-path).
    /// </summary>
    public void Skip(int steps)
    {
        _currentIndex = Math.Min(_currentIndex + steps, _points.Count);
    }
}
