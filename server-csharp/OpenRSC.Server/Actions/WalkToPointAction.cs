using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Actions;

/// <summary>
/// Action for walking to a specific point on the map.
/// </summary>
public abstract class WalkToPointAction : WalkToAction
{
    /// <summary>
    /// Required proximity radius to execute.
    /// </summary>
    public int Radius { get; }

    protected WalkToPointAction(Player player, Point location, int radius)
        : base(player, location)
    {
        Radius = radius;
    }

    protected override bool ShouldExecuteInternal()
    {
        return Player.Location.DistanceTo(Location) <= Radius;
    }

    public override string FailureMessage => "You are unable to reach that location.";
}

/// <summary>
/// Concrete implementation of WalkToPointAction that executes a delegate when the player reaches the location.
/// </summary>
public sealed class GenericWalkToPointAction : WalkToPointAction
{
    private readonly Action _action;

    public GenericWalkToPointAction(Player player, Point location, Action action, int radius = 0)
        : base(player, location, radius)
    {
        _action = action ?? throw new ArgumentNullException(nameof(action));
    }

    protected override void ExecuteInternal()
    {
        _action();
    }
}
