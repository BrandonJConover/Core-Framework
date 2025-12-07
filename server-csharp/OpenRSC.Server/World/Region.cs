using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.World;

/// <summary>
/// Represents a region/chunk of the world map.
/// </summary>
public sealed class Region
{
    private const int RegionSize = 48;

    private readonly Tile[,] _tiles;
    private readonly List<Player> _players = new();
    private readonly List<Npc> _npcs = new();
    private readonly List<GameObject> _objects = new();
    private readonly List<GroundItem> _groundItems = new();
    private readonly object _lock = new();

    /// <summary>
    /// Region X coordinate (region units, not tiles).
    /// </summary>
    public int RegionX { get; }

    /// <summary>
    /// Region Y coordinate (region units, not tiles).
    /// </summary>
    public int RegionY { get; }

    /// <summary>
    /// Unique region identifier.
    /// </summary>
    public int RegionId => RegionX << 16 | RegionY;

    /// <summary>
    /// Top-left tile coordinate.
    /// </summary>
    public Point Origin => new(RegionX * RegionSize, RegionY * RegionSize);

    /// <summary>
    /// Players currently in this region.
    /// </summary>
    public IReadOnlyList<Player> Players
    {
        get
        {
            lock (_lock) return _players.ToList();
        }
    }

    /// <summary>
    /// NPCs currently in this region.
    /// </summary>
    public IReadOnlyList<Npc> Npcs
    {
        get
        {
            lock (_lock) return _npcs.ToList();
        }
    }

    /// <summary>
    /// Game objects in this region.
    /// </summary>
    public IReadOnlyList<GameObject> Objects
    {
        get
        {
            lock (_lock) return _objects.ToList();
        }
    }

    public Region(int regionX, int regionY)
    {
        RegionX = regionX;
        RegionY = regionY;
        _tiles = new Tile[RegionSize, RegionSize];

        // Initialize all tiles
        var origin = Origin;
        for (var x = 0; x < RegionSize; x++)
        {
            for (var y = 0; y < RegionSize; y++)
            {
                _tiles[x, y] = new Tile(new Point(origin.X + x, origin.Y + y));
            }
        }
    }

    /// <summary>
    /// Gets a tile at world coordinates.
    /// </summary>
    public Tile? GetTile(Point location)
    {
        var localX = location.X - Origin.X;
        var localY = location.Y - Origin.Y;

        if (localX < 0 || localX >= RegionSize || localY < 0 || localY >= RegionSize)
            return null;

        return _tiles[localX, localY];
    }

    /// <summary>
    /// Checks if a world coordinate is within this region.
    /// </summary>
    public bool Contains(Point location)
    {
        var localX = location.X - Origin.X;
        var localY = location.Y - Origin.Y;
        return localX >= 0 && localX < RegionSize && localY >= 0 && localY < RegionSize;
    }

    /// <summary>
    /// Adds a player to this region.
    /// </summary>
    public void AddPlayer(Player player)
    {
        lock (_lock)
        {
            if (!_players.Contains(player))
                _players.Add(player);
        }
    }

    /// <summary>
    /// Removes a player from this region.
    /// </summary>
    public void RemovePlayer(Player player)
    {
        lock (_lock)
        {
            _players.Remove(player);
        }
    }

    /// <summary>
    /// Adds an NPC to this region.
    /// </summary>
    public void AddNpc(Npc npc)
    {
        lock (_lock)
        {
            if (!_npcs.Contains(npc))
                _npcs.Add(npc);
        }
    }

    /// <summary>
    /// Removes an NPC from this region.
    /// </summary>
    public void RemoveNpc(Npc npc)
    {
        lock (_lock)
        {
            _npcs.Remove(npc);
        }
    }

    /// <summary>
    /// Adds a game object to this region.
    /// </summary>
    public void AddObject(GameObject obj)
    {
        lock (_lock)
        {
            _objects.Add(obj);

            // Update tile blocking
            var tile = GetTile(obj.Location);
            if (tile is not null && obj.IsBlocking)
            {
                tile.AddBlock(TraversalFlags.FullBlock);
            }
        }
    }

    /// <summary>
    /// Removes a game object from this region.
    /// </summary>
    public void RemoveObject(GameObject obj)
    {
        lock (_lock)
        {
            _objects.Remove(obj);

            // Update tile blocking
            var tile = GetTile(obj.Location);
            if (tile is not null && obj.IsBlocking)
            {
                tile.RemoveBlock(TraversalFlags.FullBlock);
            }
        }
    }

    /// <summary>
    /// Adds a ground item to this region.
    /// </summary>
    public void AddGroundItem(GroundItem item)
    {
        lock (_lock)
        {
            _groundItems.Add(item);
        }
    }

    /// <summary>
    /// Gets ground items at a location.
    /// </summary>
    public IEnumerable<GroundItem> GetGroundItems(Point location)
    {
        lock (_lock)
        {
            return _groundItems.Where(i => i.Location == location && !i.IsExpired).ToList();
        }
    }

    /// <summary>
    /// Removes expired ground items.
    /// </summary>
    public void CleanupGroundItems()
    {
        lock (_lock)
        {
            _groundItems.RemoveAll(i => i.IsExpired);
        }
    }

    /// <summary>
    /// Gets players within view distance of a point.
    /// </summary>
    public IEnumerable<Player> GetPlayersInView(Point center, int viewDistance = 16)
    {
        lock (_lock)
        {
            return _players.Where(p => p.Location.WithinRange(center, viewDistance)).ToList();
        }
    }

    /// <summary>
    /// Gets NPCs within view distance of a point.
    /// </summary>
    public IEnumerable<Npc> GetNpcsInView(Point center, int viewDistance = 16)
    {
        lock (_lock)
        {
            return _npcs.Where(n => n.Location.WithinRange(center, viewDistance) && !n.IsRemoved).ToList();
        }
    }

    /// <summary>
    /// Calculates the region coordinates for a world point.
    /// </summary>
    public static (int RegionX, int RegionY) GetRegionCoordinates(Point location)
    {
        return (location.X / RegionSize, location.Y / RegionSize);
    }
}

/// <summary>
/// Represents an item on the ground.
/// </summary>
public sealed class GroundItem
{
    public int ItemId { get; }
    public int Amount { get; }
    public Point Location { get; }
    public Player? DroppedBy { get; }
    public DateTime SpawnTime { get; }
    public TimeSpan VisibilityDelay { get; init; } = TimeSpan.FromMinutes(1);
    public TimeSpan DespawnTime { get; init; } = TimeSpan.FromMinutes(3);

    public bool IsExpired => DateTime.UtcNow - SpawnTime > DespawnTime;
    public bool IsVisibleToAll => DateTime.UtcNow - SpawnTime > VisibilityDelay || DroppedBy is null;

    public GroundItem(int itemId, int amount, Point location, Player? droppedBy = null)
    {
        ItemId = itemId;
        Amount = amount;
        Location = location;
        DroppedBy = droppedBy;
        SpawnTime = DateTime.UtcNow;
    }

    public bool IsVisibleTo(Player player)
    {
        if (IsVisibleToAll) return true;
        return DroppedBy == player;
    }
}
