using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Services;

/// <summary>
/// Manages the game world state including players, NPCs, and objects.
/// Thread-safe implementation using concurrent collections.
/// </summary>
public sealed class WorldService : IWorldService
{
    private readonly ILogger<WorldService> _logger;
    private readonly ServerSettings _settings;

    private readonly ConcurrentDictionary<int, Player> _players = new();
    private readonly ConcurrentDictionary<long, Player> _playersByHash = new();
    private readonly ConcurrentDictionary<int, Npc> _npcs = new();
    private readonly ConcurrentDictionary<Point, List<GameObject>> _objects = new();

    private int _nextPlayerIndex;

    public WorldService(
        ILogger<WorldService> logger,
        IOptions<ServerSettings> settings)
    {
        _logger = logger;
        _settings = settings.Value;
    }

    public IEnumerable<Player> GetPlayers() => _players.Values;

    public IEnumerable<Npc> GetNpcs() => _npcs.Values;

    public Player? GetPlayer(string username)
    {
        var hash = ComputeUsernameHash(username);
        return GetPlayer(hash);
    }

    public Player? GetPlayer(long usernameHash)
    {
        return _playersByHash.TryGetValue(usernameHash, out var player) ? player : null;
    }

    public Player? GetPlayer(int index)
    {
        return _players.TryGetValue(index, out var player) ? player : null;
    }

    public bool RegisterPlayer(Player player)
    {
        if (_players.Count >= _settings.MaxPlayers)
        {
            _logger.LogWarning("Cannot register player {Username}: server full", player.Username);
            return false;
        }

        if (_players.TryAdd(player.Index, player) &&
            _playersByHash.TryAdd(player.UsernameHash, player))
        {
            _logger.LogInformation("Player {Username} registered (index: {Index})",
                player.Username, player.Index);
            return true;
        }

        // Rollback if partial add
        _players.TryRemove(player.Index, out _);
        _playersByHash.TryRemove(player.UsernameHash, out _);
        return false;
    }

    public bool UnregisterPlayer(Player player)
    {
        var removed = _players.TryRemove(player.Index, out _) &&
                     _playersByHash.TryRemove(player.UsernameHash, out _);

        if (removed)
        {
            _logger.LogInformation("Player {Username} unregistered", player.Username);
        }

        return removed;
    }

    public bool RegisterNpc(Npc npc)
    {
        return _npcs.TryAdd(npc.Index, npc);
    }

    public bool UnregisterNpc(Npc npc)
    {
        return _npcs.TryRemove(npc.Index, out _);
    }

    public IEnumerable<GameObject> GetObjectsAt(Point location)
    {
        return _objects.TryGetValue(location, out var objects)
            ? objects
            : Enumerable.Empty<GameObject>();
    }

    public IEnumerable<Npc> GetNpcsInRange(Point location, int radius)
    {
        return _npcs.Values.Where(npc =>
            !npc.IsRemoved &&
            !npc.IsRespawning &&
            npc.Location.WithinRange(location, radius));
    }

    public IEnumerable<Player> GetPlayersInRange(Point location, int radius)
    {
        return _players.Values.Where(player =>
            player.IsLoggedIn &&
            !player.IsRemoved &&
            player.Location.WithinRange(location, radius));
    }

    /// <summary>
    /// Adds a game object to the world.
    /// </summary>
    public void AddObject(GameObject gameObject)
    {
        _objects.AddOrUpdate(
            gameObject.Location,
            _ => new List<GameObject> { gameObject },
            (_, list) =>
            {
                list.Add(gameObject);
                return list;
            });
    }

    /// <summary>
    /// Removes a game object from the world.
    /// </summary>
    public void RemoveObject(GameObject gameObject)
    {
        if (_objects.TryGetValue(gameObject.Location, out var list))
        {
            list.Remove(gameObject);
            if (list.Count == 0)
            {
                _objects.TryRemove(gameObject.Location, out _);
            }
        }
    }

    private static long ComputeUsernameHash(string username)
    {
        var hash = 0L;
        foreach (var c in username.ToLowerInvariant())
        {
            hash = hash * 37 + c;
        }
        return hash;
    }
}
