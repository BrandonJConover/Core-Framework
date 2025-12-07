namespace OpenRSC.Server.Events;

/// <summary>
/// Base class for all game events (delayed/recurring actions).
/// </summary>
public abstract class GameEvent
{
    private bool _running = true;
    private long _lastRunTick;

    /// <summary>
    /// Unique identifier for this event.
    /// </summary>
    public Guid Id { get; } = Guid.NewGuid();

    /// <summary>
    /// Delay in game ticks before first/next execution.
    /// </summary>
    public int DelayTicks { get; protected set; }

    /// <summary>
    /// Whether this event should repeat after execution.
    /// </summary>
    public bool Repeating { get; protected set; }

    /// <summary>
    /// Whether this event is still running.
    /// </summary>
    public bool IsRunning => _running;

    /// <summary>
    /// Description for debugging.
    /// </summary>
    public virtual string Description => GetType().Name;

    protected GameEvent(int delayTicks, bool repeating = false)
    {
        DelayTicks = delayTicks;
        Repeating = repeating;
    }

    /// <summary>
    /// Checks if the event should run on this tick.
    /// </summary>
    public bool ShouldRun(long currentTick)
    {
        if (!_running) return false;
        return currentTick - _lastRunTick >= DelayTicks;
    }

    /// <summary>
    /// Runs the event and updates state.
    /// </summary>
    public async Task RunAsync(long currentTick)
    {
        _lastRunTick = currentTick;

        try
        {
            await ExecuteAsync();
        }
        catch (Exception)
        {
            Stop();
            throw;
        }

        if (!Repeating)
        {
            Stop();
        }
    }

    /// <summary>
    /// Override to implement the event logic.
    /// </summary>
    protected abstract Task ExecuteAsync();

    /// <summary>
    /// Stops the event from running.
    /// </summary>
    public void Stop() => _running = false;

    /// <summary>
    /// Restarts the event.
    /// </summary>
    public void Restart() => _running = true;

    /// <summary>
    /// Updates the delay for recurring events.
    /// </summary>
    public void SetDelay(int ticks) => DelayTicks = ticks;
}

/// <summary>
/// A simple single-execution event.
/// </summary>
public sealed class SingleEvent : GameEvent
{
    private readonly Func<Task> _action;

    public SingleEvent(int delayTicks, Func<Task> action)
        : base(delayTicks, repeating: false)
    {
        _action = action;
    }

    public SingleEvent(int delayTicks, Action action)
        : this(delayTicks, () => { action(); return Task.CompletedTask; })
    {
    }

    protected override Task ExecuteAsync() => _action();
}

/// <summary>
/// A repeating event that runs at intervals.
/// </summary>
public sealed class RepeatingEvent : GameEvent
{
    private readonly Func<Task<bool>> _action;

    /// <summary>
    /// Creates a repeating event.
    /// </summary>
    /// <param name="delayTicks">Ticks between executions</param>
    /// <param name="action">Action that returns false to stop repeating</param>
    public RepeatingEvent(int delayTicks, Func<Task<bool>> action)
        : base(delayTicks, repeating: true)
    {
        _action = action;
    }

    public RepeatingEvent(int delayTicks, Func<bool> action)
        : this(delayTicks, () => Task.FromResult(action()))
    {
    }

    protected override async Task ExecuteAsync()
    {
        var shouldContinue = await _action();
        if (!shouldContinue)
        {
            Stop();
        }
    }
}
