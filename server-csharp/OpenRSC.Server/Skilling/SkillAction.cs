using OpenRSC.Server.Entities;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Skilling;

/// <summary>
/// Base class for repeatable skill actions.
/// </summary>
public abstract class SkillAction
{
    protected readonly Player Player;
    protected int TicksRemaining;
    protected bool IsCancelled;

    /// <summary>
    /// The skill this action trains.
    /// </summary>
    public abstract Skill Skill { get; }

    /// <summary>
    /// Whether the action is complete.
    /// </summary>
    public bool IsComplete => IsCancelled || TicksRemaining <= 0;

    protected SkillAction(Player player, int ticks)
    {
        Player = player;
        TicksRemaining = ticks;
    }

    /// <summary>
    /// Cancels the action.
    /// </summary>
    public void Cancel()
    {
        IsCancelled = true;
    }

    /// <summary>
    /// Processes one tick of the action.
    /// </summary>
    public void ProcessTick()
    {
        if (IsComplete)
            return;

        TicksRemaining--;

        if (TicksRemaining <= 0)
        {
            OnComplete();
        }
        else
        {
            OnTick();
        }
    }

    /// <summary>
    /// Called when the action completes successfully.
    /// </summary>
    protected abstract void OnComplete();

    /// <summary>
    /// Called each tick during the action.
    /// </summary>
    protected virtual void OnTick() { }

    /// <summary>
    /// Checks if the player meets requirements to continue.
    /// </summary>
    public virtual bool CanContinue() => !IsCancelled;
}

/// <summary>
/// Result of attempting a skill action.
/// </summary>
public readonly record struct SkillActionResult(bool Success, string? Message = null, SkillAction? Action = null)
{
    public static SkillActionResult Fail(string message) => new(false, message);
    public static SkillActionResult Ok(SkillAction action) => new(true, Action: action);
}
