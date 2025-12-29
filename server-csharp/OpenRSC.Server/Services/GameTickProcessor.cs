using System.Runtime.CompilerServices;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Npc;

namespace OpenRSC.Server.Services;

/// <summary>
/// Processes game ticks and updates world state.
/// Optimized for minimal allocations and overhead.
/// </summary>
public sealed class GameTickProcessor
{
    private readonly ILogger<GameTickProcessor> _logger;
    private readonly ServerSettings _serverSettings;
    private readonly IWorldService _worldService;
    private readonly NpcManager? _npcManager;
    private long _currentTick;

    // Aggression check interval (every 3 ticks to reduce overhead)
    private const int AggressionCheckInterval = 3;

    // NPC roaming probability (1 in 8 chance per tick)
    private const int RoamingChance = 8;

    public GameTickProcessor(
        ILogger<GameTickProcessor> logger,
        IOptions<ServerSettings> serverSettings,
        IWorldService worldService,
        NpcManager? npcManager = null)
    {
        _logger = logger;
        _serverSettings = serverSettings.Value;
        _worldService = worldService;
        _npcManager = npcManager;
    }

    /// <summary>
    /// Current game tick number.
    /// </summary>
    public long CurrentTick => _currentTick;

    /// <summary>
    /// Processes a single game tick (synchronous for performance).
    /// </summary>
    public void ProcessTick(CancellationToken cancellationToken = default)
    {
        Interlocked.Increment(ref _currentTick);

        try
        {
            // Process all players
            foreach (var player in _worldService.GetPlayers())
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                ProcessPlayerTick(player);
            }

            // Process all NPCs
            foreach (var npc in _worldService.GetNpcs())
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                ProcessNpcTick(npc);
            }

            // Process NPC respawns
            ProcessNpcRespawns();

            // Check for NPC aggression (less frequently for performance)
            if (_currentTick % AggressionCheckInterval == 0)
            {
                ProcessNpcAggression();
            }

            // Cleanup after all updates
            CleanupAfterUpdate();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing game tick {Tick}", _currentTick);
        }
    }

    /// <summary>
    /// Processes a single game tick (async wrapper for compatibility).
    /// </summary>
    public Task ProcessTickAsync(CancellationToken cancellationToken = default)
    {
        ProcessTick(cancellationToken);
        return Task.CompletedTask;
    }

    /// <summary>
    /// Processes a single player's tick.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void ProcessPlayerTick(Player player)
    {
        // Update player position
        player.UpdatePosition();

        // Execute walk-to actions
        ExecuteWalkToActions(player);

        // Process combat if engaged
        if (player.InCombat)
        {
            ProcessPlayerCombat(player);
        }

        // Process prayer drain (every tick while prayers are active)
        player.Prayers?.ProcessDrain();

        // Process fatigue recovery if not in combat
        if (!player.InCombat)
        {
            player.Fatigue?.ProcessRecovery();
        }
    }

    /// <summary>
    /// Processes player combat tick.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void ProcessPlayerCombat(Player player)
    {
        // Combat is handled through the CombatSystem
        // This just ensures combat state is properly maintained
        if (player.CombatTarget is { IsRemoved: true })
        {
            player.EndCombat();
        }
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
    /// Processes a single NPC's tick including AI, movement, and combat.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void ProcessNpcTick(Npc npc)
    {
        // Skip dead or removed NPCs
        if (npc.IsDead || npc.IsRemoved)
            return;

        // Process NPC combat if engaged
        if (npc.InCombat)
        {
            ProcessNpcCombat(npc);
            return; // Don't process AI while in combat
        }

        // Process AI behavior (handles patrol, aggression, etc.)
        npc.ProcessAI();

        // Random roaming for idle NPCs
        if (!npc.HasMoved && ShouldRoam())
        {
            npc.WalkRandom();
        }
    }

    /// <summary>
    /// Processes NPC combat tick.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void ProcessNpcCombat(Npc npc)
    {
        // Check if combat target is still valid
        if (npc.CombatTarget is null or { IsRemoved: true })
        {
            npc.EndCombat();

            // Return to spawn if too far
            if (npc.SpawnLocation.DistanceTo(npc.Location) > 10)
            {
                npc.ReturnToSpawn();
            }
            return;
        }

        // Check if target ran away (leash distance)
        if (npc.CombatTarget is Player player &&
            npc.Location.DistanceTo(player.Location) > 16)
        {
            npc.EndCombat();
            npc.ReturnToSpawn();

            if (_serverSettings.Debug)
            {
                _logger.LogDebug("NPC {NpcName} lost target (player ran)", npc.Name);
            }
        }
    }

    /// <summary>
    /// Processes NPC respawns.
    /// </summary>
    private void ProcessNpcRespawns()
    {
        if (_npcManager is not null)
        {
            _npcManager.ProcessRespawns(_serverSettings.GameTickMs);
        }
        else
        {
            // Fallback: process respawns directly
            foreach (var npc in _worldService.GetNpcs())
            {
                if (npc.IsDead && npc.CanRespawn(_serverSettings.GameTickMs))
                {
                    npc.Respawn();

                    if (_serverSettings.Debug)
                    {
                        _logger.LogDebug("Respawned NPC {NpcName} at {Location}",
                            npc.Name, npc.SpawnLocation);
                    }
                }
            }
        }
    }

    /// <summary>
    /// Processes NPC aggression - finds nearby players to attack.
    /// </summary>
    private void ProcessNpcAggression()
    {
        const int aggroRange = 5;

        foreach (var npc in _worldService.GetNpcs())
        {
            // Skip non-aggressive, dead, in-combat, or removed NPCs
            if (!npc.IsAggressive || npc.IsDead || npc.InCombat || npc.IsRemoved)
                continue;

            // Already has a target
            if (npc.AggroTarget is not null)
                continue;

            // Find nearby players to attack
            var nearbyPlayers = _worldService.GetPlayersInRange(npc.Location, aggroRange);

            foreach (var player in nearbyPlayers)
            {
                // Skip players in combat or with immunity
                if (player.InCombat || player.IsRemoved)
                    continue;

                // Check combat level difference (aggressive NPCs attack players within 2x their level)
                if (player.CombatLevel > npc.CombatLevel * 2)
                    continue;

                // Set aggro target and walk towards player
                npc.AggroTarget = player;
                npc.WalkTowards(player.Location);

                if (_serverSettings.Debug)
                {
                    _logger.LogDebug("NPC {NpcName} targeting player {PlayerName}",
                        npc.Name, player.Username);
                }

                break; // Only target one player
            }
        }
    }

    /// <summary>
    /// Determines if an NPC should attempt to roam this tick.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static bool ShouldRoam()
    {
        return Random.Shared.Next(RoamingChance) == 0;
    }

    /// <summary>
    /// Cleanup after all entities have been updated.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void CleanupAfterUpdate()
    {
        foreach (var player in _worldService.GetPlayers())
        {
            player.ResetAfterUpdate();
        }

        foreach (var npc in _worldService.GetNpcs())
        {
            npc.ResetAfterUpdate();
        }
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
