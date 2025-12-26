using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.World;

/// <summary>
/// Manages the entire game world map.
/// </summary>
public sealed class WorldMap
{
    private const int WorldWidth = 944;
    private const int WorldHeight = 3776;
    private const int RegionSize = 48;

    private readonly ILogger<WorldMap> _logger;
    private readonly ConcurrentDictionary<int, Region> _regions = new();

    /// <summary>
    /// World boundaries.
    /// </summary>
    public static Point WorldMin => new(0, 0);
    public static Point WorldMax => new(WorldWidth - 1, WorldHeight - 1);

    public WorldMap(ILogger<WorldMap> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Gets or creates a region for a location.
    /// </summary>
    public Region GetRegion(Point location)
    {
        var (regionX, regionY) = Region.GetRegionCoordinates(location);
        var regionId = regionX << 16 | regionY;

        return _regions.GetOrAdd(regionId, _ => new Region(regionX, regionY));
    }

    /// <summary>
    /// Gets a tile at a world coordinate.
    /// </summary>
    public Tile? GetTile(Point location)
    {
        if (!IsValidLocation(location))
            return null;

        return GetRegion(location).GetTile(location);
    }

    /// <summary>
    /// Checks if a location is within world bounds.
    /// </summary>
    public static bool IsValidLocation(Point location)
    {
        return location.X >= 0 && location.X < WorldWidth &&
               location.Y >= 0 && location.Y < WorldHeight;
    }

    /// <summary>
    /// Checks if movement between two tiles is valid.
    /// </summary>
    public bool CanMove(Point from, Point to)
    {
        if (!IsValidLocation(to))
            return false;

        var dx = to.X - from.X;
        var dy = to.Y - from.Y;

        // Can only move one tile at a time
        if (Math.Abs(dx) > 1 || Math.Abs(dy) > 1)
            return false;

        var direction = DirectionExtensions.FromDelta(dx, dy);
        if (direction is null)
            return false;

        // Check source tile allows exit
        var fromTile = GetTile(from);
        if (fromTile is null || !fromTile.CanTraverse(direction.Value))
            return false;

        // Check destination tile allows entry
        var toTile = GetTile(to);
        if (toTile is null || toTile.IsBlocked)
            return false;

        // Check diagonal movement doesn't clip corners
        if (dx != 0 && dy != 0)
        {
            var corner1 = GetTile(new Point(from.X + dx, from.Y));
            var corner2 = GetTile(new Point(from.X, from.Y + dy));

            if (corner1?.IsBlocked == true || corner2?.IsBlocked == true)
                return false;
        }

        return true;
    }

    /// <summary>
    /// Gets all regions within view distance of a point.
    /// </summary>
    public IEnumerable<Region> GetSurroundingRegions(Point center, int viewDistance = 16)
    {
        var minX = (center.X - viewDistance) / RegionSize;
        var maxX = (center.X + viewDistance) / RegionSize;
        var minY = (center.Y - viewDistance) / RegionSize;
        var maxY = (center.Y + viewDistance) / RegionSize;

        for (var rx = minX; rx <= maxX; rx++)
        {
            for (var ry = minY; ry <= maxY; ry++)
            {
                var regionId = rx << 16 | ry;
                if (_regions.TryGetValue(regionId, out var region))
                {
                    yield return region;
                }
            }
        }
    }

    /// <summary>
    /// Gets all players visible from a location.
    /// </summary>
    public IEnumerable<Player> GetVisiblePlayers(Point center, int viewDistance = 16)
    {
        return GetSurroundingRegions(center, viewDistance)
            .SelectMany(r => r.GetPlayersInView(center, viewDistance));
    }

    /// <summary>
    /// Gets all NPCs visible from a location.
    /// </summary>
    public IEnumerable<Npc> GetVisibleNpcs(Point center, int viewDistance = 16)
    {
        return GetSurroundingRegions(center, viewDistance)
            .SelectMany(r => r.GetNpcsInView(center, viewDistance));
    }

    /// <summary>
    /// Updates a player's region when they move.
    /// </summary>
    public void UpdatePlayerRegion(Player player, Point? previousLocation)
    {
        if (previousLocation is null)
        {
            GetRegion(player.Location).AddPlayer(player);
            return;
        }

        var oldRegion = GetRegion(previousLocation.Value);
        var newRegion = GetRegion(player.Location);

        if (oldRegion.RegionId != newRegion.RegionId)
        {
            oldRegion.RemovePlayer(player);
            newRegion.AddPlayer(player);
        }
    }

    /// <summary>
    /// Updates an NPC's region when they move.
    /// </summary>
    public void UpdateNpcRegion(Npc npc, Point previousLocation)
    {
        var oldRegion = GetRegion(previousLocation);
        var newRegion = GetRegion(npc.Location);

        if (oldRegion.RegionId != newRegion.RegionId)
        {
            oldRegion.RemoveNpc(npc);
            newRegion.AddNpc(npc);
        }
    }

    /// <summary>
    /// Registers a game object in the world.
    /// </summary>
    public void AddObject(GameObject obj)
    {
        GetRegion(obj.Location).AddObject(obj);
    }

    /// <summary>
    /// Removes a game object from the world.
    /// </summary>
    public void RemoveObject(GameObject obj)
    {
        GetRegion(obj.Location).RemoveObject(obj);
    }

    /// <summary>
    /// Drops an item on the ground.
    /// </summary>
    public void DropItem(int itemId, int amount, Point location, Player? droppedBy = null)
    {
        var groundItem = new GroundItem(itemId, amount, location, droppedBy);
        GetRegion(location).AddGroundItem(groundItem);
    }

    /// <summary>
    /// Cleans up expired ground items across all loaded regions.
    /// </summary>
    public void CleanupGroundItems()
    {
        foreach (var region in _regions.Values)
        {
            region.CleanupGroundItems();
        }
    }

    /// <summary>
    /// Attempts to pick up a ground item.
    /// </summary>
    /// <returns>The picked up item if successful, null otherwise.</returns>
    public GroundItem? TryPickupItem(int itemId, Point location, Player player)
    {
        return GetRegion(location).TryRemoveGroundItem(itemId, location, player);
    }

    /// <summary>
    /// Gets ground items at a specific location visible to a player.
    /// </summary>
    public IEnumerable<GroundItem> GetGroundItems(Point location, Player? player = null)
    {
        var items = GetRegion(location).GetGroundItems(location);
        if (player is null)
        {
            return items.Where(i => i.IsVisibleToAll);
        }
        return items.Where(i => i.IsVisibleToAll || i.DroppedBy?.UsernameHash == player.UsernameHash);
    }

    /// <summary>
    /// Gets loaded region count for monitoring.
    /// </summary>
    public int LoadedRegionCount => _regions.Count;
}
