using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;

namespace OpenRSC.Server.Events;

/// <summary>
/// Manages and processes game events.
/// Thread-safe implementation for concurrent event submission.
/// </summary>
public sealed class EventManager
{
    private readonly ILogger<EventManager> _logger;
    private readonly ConcurrentDictionary<Guid, GameEvent> _events = new();
    private readonly ConcurrentQueue<GameEvent> _pendingAdd = new();
    private readonly ConcurrentQueue<Guid> _pendingRemove = new();

    public EventManager(ILogger<EventManager> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Number of active events.
    /// </summary>
    public int EventCount => _events.Count;

    /// <summary>
    /// Submits an event to be processed.
    /// </summary>
    public void Submit(GameEvent gameEvent)
    {
        _pendingAdd.Enqueue(gameEvent);
    }

    /// <summary>
    /// Submits a delayed action as a single event.
    /// </summary>
    public void SubmitDelayed(int delayTicks, Action action)
    {
        Submit(new SingleEvent(delayTicks, action));
    }

    /// <summary>
    /// Submits a delayed async action as a single event.
    /// </summary>
    public void SubmitDelayed(int delayTicks, Func<Task> action)
    {
        Submit(new SingleEvent(delayTicks, action));
    }

    /// <summary>
    /// Submits a repeating action.
    /// </summary>
    /// <returns>The event ID for later cancellation</returns>
    public Guid SubmitRepeating(int delayTicks, Func<bool> action)
    {
        var evt = new RepeatingEvent(delayTicks, action);
        Submit(evt);
        return evt.Id;
    }

    /// <summary>
    /// Cancels an event by ID.
    /// </summary>
    public void Cancel(Guid eventId)
    {
        _pendingRemove.Enqueue(eventId);
    }

    /// <summary>
    /// Processes all events for the current tick.
    /// </summary>
    public async Task ProcessTickAsync(long currentTick)
    {
        // Add pending events
        while (_pendingAdd.TryDequeue(out var evt))
        {
            _events.TryAdd(evt.Id, evt);
        }

        // Remove cancelled events
        while (_pendingRemove.TryDequeue(out var id))
        {
            if (_events.TryRemove(id, out var evt))
            {
                evt.Stop();
            }
        }

        // Process active events
        var completedEvents = new List<Guid>();

        foreach (var (id, evt) in _events)
        {
            if (!evt.IsRunning)
            {
                completedEvents.Add(id);
                continue;
            }

            if (evt.ShouldRun(currentTick))
            {
                try
                {
                    await evt.RunAsync(currentTick);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error executing event {EventId} ({Description})",
                        id, evt.Description);
                }

                if (!evt.IsRunning)
                {
                    completedEvents.Add(id);
                }
            }
        }

        // Clean up completed events
        foreach (var id in completedEvents)
        {
            _events.TryRemove(id, out _);
        }
    }

    /// <summary>
    /// Cancels all events.
    /// </summary>
    public void CancelAll()
    {
        foreach (var evt in _events.Values)
        {
            evt.Stop();
        }
        _events.Clear();
    }
}
