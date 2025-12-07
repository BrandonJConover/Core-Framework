using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Services;

/// <summary>
/// Processes game ticks and updates world state.
/// Modern equivalent of Java's GameStateUpdater.
/// </summary>
public sealed class GameTickProcessor
{
    private readonly ILogger<GameTickProcessor> _logger;
    private readonly ServerSettings _serverSettings;
    private readonly IWorldService _worldService;
    private long _currentTick;

    public GameTickProcessor(
        ILogger<GameTickProcessor> logger,
        IOptions<ServerSettings> serverSettings,
        IWorldService worldService)
    {
        _logger = logger;
        _serverSettings = serverSettings.Value;
        _worldService = worldService;
    }

    /// <summary>
    /// Current game tick number.
    /// </summary>
    public long CurrentTick => _currentTick;

    /// <summary>
    /// Processes a single game tick.
    /// </summary>
    public async Task ProcessTickAsync(CancellationToken cancellationToken = default)
    {
        Interlocked.Increment(ref _currentTick);

        try
        {
            // Process all players
            foreach (var player in _worldService.GetPlayers())
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                await ProcessPlayerTickAsync(player);
            }

            // Process all NPCs
            foreach (var npc in _worldService.GetNpcs())
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                ProcessNpcTick(npc);
            }

            // Cleanup after all updates
            await CleanupAfterUpdateAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing game tick {Tick}", _currentTick);
        }
    }

    /// <summary>
    /// Processes a single player's tick.
    /// </summary>
    private async Task ProcessPlayerTickAsync(Player player)
    {
        // Update player position
        player.UpdatePosition();

        // Execute walk-to actions
        ExecuteWalkToActions(player);

        // TODO: Process other player events (combat, skilling, etc.)

        await Task.CompletedTask;
    }

    /// <summary>
    /// Executes walk-to actions for a player, with retry logic.
    /// </summary>
    public void ExecuteWalkToActions(Player player)
    {
        var action = player.WalkToAction;
        if (action == null)
            return;

        if (action.ShouldExecute())
        {
            action.Execute();
        }
        else if (action.RetryEnabled)
        {
            // Action not ready to execute - handle retry logic
            HandleActionRetry(player);
        }
    }

    /// <summary>
    /// Handles the retry logic for walk-to actions that fail to execute.
    /// </summary>
    private void HandleActionRetry(Player player)
    {
        var action = player.WalkToAction;
        if (action == null || action.IsExecuted)
            return;

        var shouldContinue = action.OnAttemptFailed(_currentTick);

        if (!shouldContinue)
        {
            // Max retries exceeded - notify player and clear the action
            var failureMessage = action.FailureMessage;
            if (!string.IsNullOrEmpty(failureMessage))
            {
                player.Message(failureMessage);
            }

            player.SetWalkToAction(null);

            if (_serverSettings.Debug)
            {
                _logger.LogInformation(
                    "Action retry limit exceeded for player {Username} after {Attempts} attempts",
                    player.Username,
                    action.RetryAttempts);
            }
        }
    }

    /// <summary>
    /// Processes a single NPC's tick.
    /// </summary>
    private void ProcessNpcTick(Npc npc)
    {
        // TODO: Implement NPC AI, movement, respawn logic
    }

    /// <summary>
    /// Cleanup after all entities have been updated.
    /// </summary>
    private async Task CleanupAfterUpdateAsync()
    {
        foreach (var player in _worldService.GetPlayers())
        {
            player.ResetAfterUpdate();
        }

        foreach (var npc in _worldService.GetNpcs())
        {
            npc.ResetAfterUpdate();
        }

        await Task.CompletedTask;
    }

    /// <summary>
    /// Executes PID-less catching for PvP (second chance to catch players).
    /// </summary>
    public void ExecutePidlessCatching()
    {
        foreach (var player in _worldService.GetPlayers())
        {
            var action = player.WalkToAction;
            if (action?.IsPvPAttack == true && action.ShouldExecute())
            {
                action.Execute();
            }
        }
    }
}
