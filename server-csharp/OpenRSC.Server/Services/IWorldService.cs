using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Services;

/// <summary>
/// Interface for world management operations.
/// </summary>
public interface IWorldService
{
    /// <summary>
    /// Gets all online players.
    /// </summary>
    IEnumerable<Player> GetPlayers();

    /// <summary>
    /// Gets all active NPCs.
    /// </summary>
    IEnumerable<Npc> GetNpcs();

    /// <summary>
    /// Gets a player by username.
    /// </summary>
    Player? GetPlayer(string username);

    /// <summary>
    /// Gets a player by username hash.
    /// </summary>
    Player? GetPlayer(long usernameHash);

    /// <summary>
    /// Gets a player by index.
    /// </summary>
    Player? GetPlayer(int index);

    /// <summary>
    /// Registers a player in the world.
    /// </summary>
    bool RegisterPlayer(Player player);

    /// <summary>
    /// Unregisters a player from the world.
    /// </summary>
    bool UnregisterPlayer(Player player);

    /// <summary>
    /// Registers an NPC in the world.
    /// </summary>
    bool RegisterNpc(Npc npc);

    /// <summary>
    /// Unregisters an NPC from the world.
    /// </summary>
    bool UnregisterNpc(Npc npc);

    /// <summary>
    /// Gets game objects at a specific location.
    /// </summary>
    IEnumerable<GameObject> GetObjectsAt(Point location);

    /// <summary>
    /// Gets NPCs within a radius of a location.
    /// </summary>
    IEnumerable<Npc> GetNpcsInRange(Point location, int radius);

    /// <summary>
    /// Gets players within a radius of a location.
    /// </summary>
    IEnumerable<Player> GetPlayersInRange(Point location, int radius);
}
