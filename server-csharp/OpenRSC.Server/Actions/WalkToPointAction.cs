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
