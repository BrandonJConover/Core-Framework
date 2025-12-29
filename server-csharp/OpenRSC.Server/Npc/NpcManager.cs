using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Npc;

/// <summary>
/// Manages all NPCs in the game world.
/// </summary>
public sealed class NpcManager
{
    private readonly ILogger<NpcManager> _logger;
    private readonly INpcDefinitionRepository _definitions;
    private readonly ConcurrentDictionary<int, Entities.Npc> _npcs = new();
    private readonly List<NpcSpawn> _spawns = new();
    private int _nextNpcIndex;

    /// <summary>
    /// Gets all active NPCs.
    /// </summary>
    public IEnumerable<Entities.Npc> ActiveNpcs => _npcs.Values.Where(n => !n.IsRemoved);

    /// <summary>
    /// Gets all NPCs (including dead ones).
    /// </summary>
    public IEnumerable<Entities.Npc> AllNpcs => _npcs.Values;

    public NpcManager(ILogger<NpcManager> logger, INpcDefinitionRepository definitions)
    {
        _logger = logger;
        _definitions = definitions;
    }

    /// <summary>
    /// Registers a spawn point for NPCs.
    /// </summary>
    public void RegisterSpawn(NpcSpawn spawn)
    {
        _spawns.Add(spawn);
    }

    /// <summary>
    /// Spawns all registered NPCs.
    /// </summary>
    public void SpawnAll()
    {
        foreach (var spawn in _spawns)
        {
            SpawnNpc(spawn);
        }

        _logger.LogInformation("Spawned {Count} NPCs", _npcs.Count);
    }

    /// <summary>
    /// Spawns an NPC from a spawn definition.
    /// </summary>
    public Entities.Npc? SpawnNpc(NpcSpawn spawn)
    {
        var definition = _definitions.GetById(spawn.NpcId);
        if (definition is null)
        {
            _logger.LogWarning("Unknown NPC ID {NpcId} in spawn", spawn.NpcId);
            return null;
        }

        var npc = new Entities.Npc(definition, spawn.Location);
        var index = Interlocked.Increment(ref _nextNpcIndex);
        npc.Index = index;

        // Assign behavior
        npc.Behavior = CreateBehavior(definition, spawn);

        _npcs[index] = npc;

        _logger.LogDebug("Spawned NPC {Name} at {Location}", definition.Name, spawn.Location);

        return npc;
    }

    /// <summary>
    /// Gets an NPC by index.
    /// </summary>
    public Entities.Npc? GetNpc(int index)
    {
        return _npcs.TryGetValue(index, out var npc) ? npc : null;
    }

    /// <summary>
    /// Gets NPCs in a region.
    /// </summary>
    public IEnumerable<Entities.Npc> GetNpcsInRange(Point center, int radius)
    {
        return ActiveNpcs.Where(n => n.Location.WithinRange(center, radius));
    }

    /// <summary>
    /// Gets NPCs at a specific location.
    /// </summary>
    public IEnumerable<Entities.Npc> GetNpcsAt(Point location)
    {
        return ActiveNpcs.Where(n => n.Location == location);
    }

    /// <summary>
    /// Processes all NPC AI.
    /// </summary>
    public void ProcessAI()
    {
        foreach (var npc in ActiveNpcs)
        {
            try
            {
                npc.ProcessAI();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing AI for NPC {NpcId}", npc.NpcId);
            }
        }
    }

    /// <summary>
    /// Processes respawns for dead NPCs.
    /// </summary>
    public void ProcessRespawns(int tickDurationMs)
    {
        foreach (var npc in _npcs.Values.Where(n => n.IsDead))
        {
            if (npc.CanRespawn(tickDurationMs))
            {
                npc.Respawn();
                _logger.LogDebug("Respawned NPC {Name}", npc.Name);
            }
        }
    }

    /// <summary>
    /// Removes an NPC permanently.
    /// </summary>
    public void RemoveNpc(int index)
    {
        if (_npcs.TryRemove(index, out var npc))
        {
            npc.Remove();
            _logger.LogDebug("Removed NPC {Name}", npc.Name);
        }
    }

    private INpcBehavior CreateBehavior(NpcDefinition definition, NpcSpawn spawn)
    {
        INpcBehavior baseBehavior;

        if (spawn.PatrolPoints.Length > 0)
        {
            baseBehavior = new PatrolBehavior(spawn.PatrolPoints);
        }
        else if (definition.IsAggressive)
        {
            baseBehavior = new AggressiveBehavior(FindNearbyPlayers);
        }
        else if (definition.Command.Equals("Shop", StringComparison.OrdinalIgnoreCase))
        {
            baseBehavior = new ShopkeeperBehavior();
        }
        else
        {
            baseBehavior = new PassiveBehavior();
        }

        // Wrap with retreating behavior for attackable NPCs
        if (definition.IsAttackable && !definition.Name.Contains("boss", StringComparison.OrdinalIgnoreCase))
        {
            return new RetreatingBehavior(baseBehavior);
        }

        return baseBehavior;
    }

    private IEnumerable<Player> FindNearbyPlayers(Entities.Npc npc)
    {
        // This would be injected from the world service in a real implementation
        // For now, return empty
        return Enumerable.Empty<Player>();
    }
}

/// <summary>
/// Defines an NPC spawn point.
/// </summary>
public sealed record NpcSpawn(
    int NpcId,
    Point Location,
    Point[] PatrolPoints = null!)
{
    public Point[] PatrolPoints { get; init; } = PatrolPoints ?? Array.Empty<Point>();
}
