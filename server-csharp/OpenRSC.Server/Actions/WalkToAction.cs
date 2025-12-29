using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Actions;

/// <summary>
/// Base class for all walk-to actions. Players walk to a target location
/// and then execute an action when they arrive.
/// </summary>
public abstract class WalkToAction
{
    private volatile bool _executed;
    private int _retryAttempts;
    private long _lastAttemptTick;

    /// <summary>
    /// The player performing this action.
    /// </summary>
    public Player Player { get; }

    /// <summary>
    /// Target location for this action.
    /// </summary>
    public Point Location { get; }

    /// <summary>
    /// Maximum number of retry attempts.
    /// </summary>
    public int MaxRetries { get; set; }

    /// <summary>
    /// Whether retry is enabled for this action.
    /// </summary>
    public bool RetryEnabled { get; set; }

    protected WalkToAction(Player player, Point location)
    {
        Player = player;
        Location = location;
        _executed = false;
        _retryAttempts = 0;
        _lastAttemptTick = 0;
        MaxRetries = player.ActionRetryConfig.MaxRetries;
        RetryEnabled = player.ActionRetryConfig.Enabled;
    }

    /// <summary>
    /// Executes the action if conditions are met.
    /// </summary>
    public void Execute()
    {
        ExecuteInternal();
        FinishExecution();
    }

    /// <summary>
    /// Marks the action as executed and records it.
    /// </summary>
    protected void FinishExecution()
    {
        IsExecuted = true;
        Player.SetLastExecutedWalkToAction(this);
    }

    /// <summary>
    /// Checks if this action should execute on this tick.
    /// </summary>
    public bool ShouldExecute() => !IsExecuted && ShouldExecuteInternal();

    /// <summary>
    /// Override to implement the actual action logic.
    /// </summary>
    protected abstract void ExecuteInternal();

    /// <summary>
    /// Override to implement the condition check for execution.
    /// </summary>
    protected abstract bool ShouldExecuteInternal();

    /// <summary>
    /// Whether this action has been executed.
    /// </summary>
    public bool IsExecuted
    {
        get => _executed;
        private set => _executed = value;
    }

    /// <summary>
    /// Whether this is a PvP attack action.
    /// </summary>
    public virtual bool IsPvPAttack => false;

    #region Retry Mechanism

    /// <summary>
    /// Called when ShouldExecute returns false. Increments attempt counter.
    /// </summary>
    /// <param name="currentTick">The current game tick</param>
    /// <returns>True if action should be retried, false if max retries exceeded</returns>
    public bool OnAttemptFailed(long currentTick)
    {
        if (!RetryEnabled)
            return false;

        _lastAttemptTick = currentTick;
        _retryAttempts++;
        return _retryAttempts < MaxRetries;
    }

    /// <summary>
    /// Checks if this action has exceeded its retry limit.
    /// </summary>
    public bool HasExceededRetryLimit => RetryEnabled && _retryAttempts >= MaxRetries;

    /// <summary>
    /// Gets the number of retry attempts made.
    /// </summary>
    public int RetryAttempts => _retryAttempts;

    /// <summary>
    /// Gets the last tick when an attempt was made.
    /// </summary>
    public long LastAttemptTick => _lastAttemptTick;

    /// <summary>
    /// Resets the retry counter.
    /// </summary>
    public void ResetRetryAttempts() => _retryAttempts = 0;

    /// <summary>
    /// Gets the failure message when max retries are exceeded.
    /// Override in subclasses for custom messages.
    /// </summary>
    public virtual string FailureMessage => "You are unable to reach your target.";

    #endregion
}
