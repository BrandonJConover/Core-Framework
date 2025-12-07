using OpenRSC.Server.Entities;
using OpenRSC.Server.Services;

namespace OpenRSC.Server.Actions;

/// <summary>
/// Action for walking to and interacting with a mobile entity (player or NPC).
/// </summary>
public abstract class WalkToMobAction : WalkToAction
{
    /// <summary>
    /// The target mob for this action.
    /// </summary>
    public Mob TargetMob { get; }

    /// <summary>
    /// Required proximity radius to execute.
    /// </summary>
    public int Radius { get; }

    /// <summary>
    /// Whether projectile path validation should be ignored.
    /// </summary>
    public bool IgnoreProjectileAllowed { get; }

    /// <summary>
    /// The type of action being performed.
    /// </summary>
    public ActionType ActionType { get; }

    protected WalkToMobAction(
        Player player,
        Mob mob,
        int radius = 1,
        bool ignoreProjectileAllowed = true,
        ActionType actionType = ActionType.Other)
        : base(player, mob.Location)
    {
        TargetMob = mob;
        Radius = radius;
        IgnoreProjectileAllowed = ignoreProjectileAllowed;
        ActionType = actionType;
    }

    protected override bool ShouldExecuteInternal()
    {
        // Get the point to check (next movement for projectile-allowed, current for others)
        var checkedPoint = IgnoreProjectileAllowed
            ? Player.WalkingQueue.GetNextMovement()
            : Player.Location;

        // Check if path is valid and within range
        var pathingCheckPassed = PathValidation.CheckAdjacentDistance(
            checkedPoint,
            TargetMob.Location,
            IgnoreProjectileAllowed,
            !IgnoreProjectileAllowed);

        var canExecute = checkedPoint.WithinRange(TargetMob.Location, Radius) && pathingCheckPassed;

        // Magic attack handling - only clear immediately if retry is disabled
        if (ActionType == ActionType.AttackMagic && Player.InCombat && !canExecute)
        {
            if (!RetryEnabled)
            {
                // Legacy behavior: clear action immediately if retry is disabled
                Player.SetWalkToAction(null);
            }
            // If retry is enabled, let GameStateUpdater handle the retry logic
        }

        return canExecute;
    }

    public override bool IsPvPAttack =>
        TargetMob.IsPlayer && (ActionType == ActionType.Attack || ActionType == ActionType.AttackMagic);

    public override string FailureMessage => ActionType switch
    {
        ActionType.Attack or ActionType.AttackMagic => "You are unable to reach your target to attack.",
        _ => $"You are unable to reach the {(TargetMob.IsPlayer ? "player" : "NPC")}."
    };
}
