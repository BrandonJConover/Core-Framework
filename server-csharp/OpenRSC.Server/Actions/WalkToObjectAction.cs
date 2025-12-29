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

/// <summary>
/// Concrete implementation of WalkToObjectAction that executes a delegate when the player reaches the object.
/// </summary>
public sealed class GenericWalkToObjectAction : WalkToObjectAction
{
    private readonly Action _action;

    public GenericWalkToObjectAction(Player player, GameObject gameObject, Action action)
        : base(player, gameObject)
    {
        _action = action ?? throw new ArgumentNullException(nameof(action));
    }

    protected override void ExecuteInternal()
    {
        _action();
    }
}
