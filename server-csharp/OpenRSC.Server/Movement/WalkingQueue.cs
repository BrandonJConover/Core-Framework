using OpenRSC.Server.Models;
using OpenRSC.Server.World;

namespace OpenRSC.Server.Movement;

/// <summary>
/// Manages a queue of movement steps for an entity.
/// </summary>
public sealed class WalkingQueue
{
    private readonly Queue<Point> _waypoints = new();
    private readonly int _maxSize;

    /// <summary>
    /// Whether the entity is currently running.
    /// </summary>
    public bool IsRunning { get; set; }

    /// <summary>
    /// Whether there are pending steps.
    /// </summary>
    public bool HasSteps => _waypoints.Count > 0;

    /// <summary>
    /// Number of pending steps.
    /// </summary>
    public int Count => _waypoints.Count;

    /// <summary>
    /// The final destination if any.
    /// </summary>
    public Point? Destination => _waypoints.Count > 0 ? _waypoints.Last() : null;

    public WalkingQueue(int maxSize = 50)
    {
        _maxSize = maxSize;
    }

    /// <summary>
    /// Adds a step to the queue.
    /// </summary>
    public void AddStep(Point point)
    {
        if (_waypoints.Count >= _maxSize)
            return;

        _waypoints.Enqueue(point);
    }

    /// <summary>
    /// Adds multiple steps to the queue.
    /// </summary>
    public void AddSteps(IEnumerable<Point> points)
    {
        foreach (var point in points)
        {
            if (_waypoints.Count >= _maxSize)
                break;
            _waypoints.Enqueue(point);
        }
    }

    /// <summary>
    /// Sets a path, replacing any existing steps.
    /// </summary>
    public void SetPath(Path path)
    {
        Reset();
        path.Skip(1); // Skip current position
        while (!path.IsComplete && _waypoints.Count < _maxSize)
        {
            var step = path.GetNextStep();
            if (step.HasValue)
                _waypoints.Enqueue(step.Value);
        }
    }

    /// <summary>
    /// Gets the next step to take.
    /// </summary>
    public Point? GetNextStep()
    {
        return _waypoints.TryDequeue(out var point) ? point : null;
    }

    /// <summary>
    /// Peeks at the next step without removing it.
    /// </summary>
    public Point? PeekNextStep()
    {
        return _waypoints.TryPeek(out var point) ? point : null;
    }

    /// <summary>
    /// Clears all pending steps.
    /// </summary>
    public void Reset()
    {
        _waypoints.Clear();
    }

    /// <summary>
    /// Processes movement for a tick, returning the new position(s).
    /// </summary>
    public MovementResult ProcessTick(Point currentPosition, Func<Point, Point, bool> canMove)
    {
        var positions = new List<Point>();
        var stepsToProcess = IsRunning ? 2 : 1;

        for (var i = 0; i < stepsToProcess && HasSteps; i++)
        {
            var next = PeekNextStep();
            if (!next.HasValue)
                break;

            // Validate movement
            if (!canMove(currentPosition, next.Value))
            {
                Reset(); // Clear queue on blocked path
                break;
            }

            GetNextStep(); // Actually consume the step
            currentPosition = next.Value;
            positions.Add(currentPosition);
        }

        return new MovementResult(positions);
    }
}

/// <summary>
/// Result of processing a movement tick.
/// </summary>
public readonly record struct MovementResult(IReadOnlyList<Point> Positions)
{
    public bool HasMovement => Positions.Count > 0;
    public bool DidRun => Positions.Count > 1;
    public Point? FinalPosition => Positions.Count > 0 ? Positions[^1] : null;

    public static MovementResult None => new(Array.Empty<Point>());
}

/// <summary>
/// Manages following another entity.
/// </summary>
public sealed class FollowingManager
{
    private readonly Pathfinder _pathfinder;
    private Entities.Mob? _target;
    private Point _lastTargetPosition;
    private int _recalculateDelay;

    public bool IsFollowing => _target is not null && !_target.IsRemoved;
    public Entities.Mob? Target => _target;

    public FollowingManager(Pathfinder pathfinder)
    {
        _pathfinder = pathfinder;
    }

    /// <summary>
    /// Starts following a target.
    /// </summary>
    public void Follow(Entities.Mob target)
    {
        _target = target;
        _lastTargetPosition = target.Location;
        _recalculateDelay = 0;
    }

    /// <summary>
    /// Stops following.
    /// </summary>
    public void StopFollowing()
    {
        _target = null;
    }

    /// <summary>
    /// Updates the following path if needed.
    /// </summary>
    public void Update(Point currentPosition, WalkingQueue walkingQueue)
    {
        if (_target is null || _target.IsRemoved)
        {
            _target = null;
            return;
        }

        // Reduce recalculation delay
        if (_recalculateDelay > 0)
        {
            _recalculateDelay--;
        }

        // Recalculate path if target moved significantly or delay expired
        var targetMoved = _target.Location != _lastTargetPosition;
        var needsRecalc = _recalculateDelay <= 0 ||
                          (targetMoved && !currentPosition.WithinRange(_target.Location, 1));

        if (needsRecalc)
        {
            _lastTargetPosition = _target.Location;
            _recalculateDelay = 3; // Don't recalculate every tick

            var path = _pathfinder.FindPathToRange(currentPosition, _target.Location, 1);
            if (path.Count > 1)
            {
                walkingQueue.Reset();
                walkingQueue.AddSteps(path.Skip(1)); // Skip current position
            }
        }
    }
}

/// <summary>
/// Direction utilities for movement.
/// </summary>
public static class MovementDirections
{
    /// <summary>
    /// Gets the direction sprites for movement.
    /// RSC uses specific sprite indices for directions.
    /// </summary>
    public static (int First, int Second) GetDirectionSprites(Point from, Point to)
    {
        var dx = Math.Sign(to.X - from.X);
        var dy = Math.Sign(to.Y - from.Y);

        return (dx, dy) switch
        {
            (0, 1) => (0, -1),   // North
            (1, 1) => (1, -1),   // NE
            (1, 0) => (2, -1),   // East
            (1, -1) => (3, -1),  // SE
            (0, -1) => (4, -1),  // South
            (-1, -1) => (5, -1), // SW
            (-1, 0) => (6, -1),  // West
            (-1, 1) => (7, -1),  // NW
            _ => (-1, -1)        // Stationary
        };
    }

    /// <summary>
    /// Gets the direction for running (two tiles).
    /// </summary>
    public static (int First, int Second) GetRunDirectionSprites(Point from, Point mid, Point to)
    {
        var first = GetDirectionSprites(from, mid);
        var second = GetDirectionSprites(mid, to);
        return (first.First, second.First);
    }
}
