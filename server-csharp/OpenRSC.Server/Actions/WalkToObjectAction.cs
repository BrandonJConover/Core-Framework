using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Actions;

/// <summary>
/// Action for walking to and interacting with a game object.
/// </summary>
public abstract class WalkToObjectAction : WalkToAction
{
    /// <summary>
    /// The target game object for this action.
    /// </summary>
    public GameObject TargetObject { get; }

    protected WalkToObjectAction(Player player, GameObject gameObject)
        : base(player, gameObject.Location)
    {
        TargetObject = gameObject;
    }

    protected override bool ShouldExecuteInternal()
    {
        return Player.AtObject(TargetObject);
    }

    public override string FailureMessage => "You are unable to reach the object.";
}
