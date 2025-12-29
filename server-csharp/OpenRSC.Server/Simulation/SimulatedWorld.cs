using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Simulation;

/// <summary>
/// Represents a resource node in the simulated world.
/// </summary>
public sealed class SimulatedResource
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public ResourceType Type { get; init; }
    public Point Location { get; init; }
    public int RequiredLevel { get; init; }
    public int BaseExperience { get; init; }
    public int RespawnTicks { get; init; } = 100;
    public int CurrentRespawnTimer { get; set; }
    public bool IsAvailable => CurrentRespawnTimer <= 0;

    public void Deplete()
    {
        CurrentRespawnTimer = RespawnTicks;
    }

    public void Tick()
    {
        if (CurrentRespawnTimer > 0)
            CurrentRespawnTimer--;
    }
}

/// <summary>
/// Types of resources in the world.
/// </summary>
public enum ResourceType
{
    Tree,
    Rock,
    FishingSpot,
    Furnace,
    Anvil,
    Altar,
    Bank
}

/// <summary>
/// Represents an NPC in the simulated world.
/// </summary>
public sealed class SimulatedNpc
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public int CombatLevel { get; init; }
    public Point Location { get; set; }
    public int MaxHitpoints { get; init; }
    public int CurrentHitpoints { get; set; }
    public bool IsDead => CurrentHitpoints <= 0;
    public int RespawnTicks { get; init; } = 50;
    public int CurrentRespawnTimer { get; set; }
    public bool IsAggressive { get; init; }
    public int AttackBonus { get; init; }
    public int DefenseBonus { get; init; }
    public int StrengthBonus { get; init; }
    public List<(int itemId, double chance)> DropTable { get; } = new();

    public void TakeDamage(int damage)
    {
        CurrentHitpoints = Math.Max(0, CurrentHitpoints - damage);
    }

    public void Respawn()
    {
        CurrentHitpoints = MaxHitpoints;
        CurrentRespawnTimer = 0;
    }

    public void Tick()
    {
        if (IsDead && CurrentRespawnTimer > 0)
        {
            CurrentRespawnTimer--;
            if (CurrentRespawnTimer <= 0)
            {
                Respawn();
            }
        }
    }
}

/// <summary>
/// A zone/area in the simulated world.
/// </summary>
public sealed class SimulatedZone
{
    public string Name { get; init; } = "";
    public Point MinBounds { get; init; }
    public Point MaxBounds { get; init; }
    public bool IsWilderness { get; init; }
    public int WildernessLevel { get; init; }
    public List<SimulatedResource> Resources { get; } = new();
    public List<SimulatedNpc> Npcs { get; } = new();
    public bool HasBank { get; init; }

    public bool Contains(Point p) =>
        p.X >= MinBounds.X && p.X <= MaxBounds.X &&
        p.Y >= MinBounds.Y && p.Y <= MaxBounds.Y;
}

/// <summary>
/// Simulated game world for testing without full server infrastructure.
/// </summary>
public sealed class SimulatedWorld
{
    private readonly Random _random;
    private readonly List<SimulatedPlayer> _players = new();
    private readonly List<SimulatedZone> _zones = new();
    private readonly Dictionary<Point, List<(int itemId, int amount)>> _groundItems = new();

    public IReadOnlyList<SimulatedPlayer> Players => _players;
    public IReadOnlyList<SimulatedZone> Zones => _zones;

    public SimulatedWorld(Random random)
    {
        _random = random;
        InitializeWorld();
    }

    private void InitializeWorld()
    {
        // Create Lumbridge area
        var lumbridge = new SimulatedZone
        {
            Name = "Lumbridge",
            MinBounds = new Point(100, 100),
            MaxBounds = new Point(200, 200),
            HasBank = true
        };

        // Add trees
        for (var i = 0; i < 10; i++)
        {
            lumbridge.Resources.Add(new SimulatedResource
            {
                Id = i,
                Name = "Tree",
                Type = ResourceType.Tree,
                Location = new Point(110 + i * 5, 120),
                RequiredLevel = 1,
                BaseExperience = 25,
                RespawnTicks = 30
            });
        }

        // Add copper/tin rocks
        for (var i = 0; i < 5; i++)
        {
            lumbridge.Resources.Add(new SimulatedResource
            {
                Id = 100 + i,
                Name = "Copper rock",
                Type = ResourceType.Rock,
                Location = new Point(150 + i * 3, 150),
                RequiredLevel = 1,
                BaseExperience = 17,
                RespawnTicks = 20
            });
            lumbridge.Resources.Add(new SimulatedResource
            {
                Id = 110 + i,
                Name = "Tin rock",
                Type = ResourceType.Rock,
                Location = new Point(150 + i * 3, 155),
                RequiredLevel = 1,
                BaseExperience = 17,
                RespawnTicks = 20
            });
        }

        // Add fishing spots
        lumbridge.Resources.Add(new SimulatedResource
        {
            Id = 200,
            Name = "Fishing spot",
            Type = ResourceType.FishingSpot,
            Location = new Point(180, 130),
            RequiredLevel = 1,
            BaseExperience = 10,
            RespawnTicks = 0 // Always available
        });

        // Add bank
        lumbridge.Resources.Add(new SimulatedResource
        {
            Id = 300,
            Name = "Bank",
            Type = ResourceType.Bank,
            Location = new Point(125, 125),
            RequiredLevel = 0,
            BaseExperience = 0
        });

        // Add NPCs (goblins, cows, chickens)
        for (var i = 0; i < 5; i++)
        {
            lumbridge.Npcs.Add(new SimulatedNpc
            {
                Id = i,
                Name = "Chicken",
                CombatLevel = 1,
                Location = new Point(130 + i * 2, 140),
                MaxHitpoints = 3,
                CurrentHitpoints = 3,
                RespawnTicks = 25,
                AttackBonus = 0,
                DefenseBonus = 0,
                StrengthBonus = 0,
                DropTable = { (526, 1.0), (314, 0.5) } // Bones, feathers
            });
        }

        for (var i = 0; i < 10; i++)
        {
            lumbridge.Npcs.Add(new SimulatedNpc
            {
                Id = 10 + i,
                Name = "Cow",
                CombatLevel = 2,
                Location = new Point(160 + i * 2, 170),
                MaxHitpoints = 8,
                CurrentHitpoints = 8,
                RespawnTicks = 30,
                AttackBonus = 1,
                DefenseBonus = 1,
                StrengthBonus = 1,
                DropTable = { (526, 1.0), (1739, 1.0), (2132, 0.3) } // Bones, cowhide, beef
            });
        }

        for (var i = 0; i < 5; i++)
        {
            lumbridge.Npcs.Add(new SimulatedNpc
            {
                Id = 20 + i,
                Name = "Goblin",
                CombatLevel = 5,
                Location = new Point(190 + i, 180),
                MaxHitpoints = 5,
                CurrentHitpoints = 5,
                RespawnTicks = 20,
                AttackBonus = 3,
                DefenseBonus = 2,
                StrengthBonus = 3,
                DropTable = { (526, 1.0), (995, 0.8) } // Bones, coins
            });
        }

        _zones.Add(lumbridge);

        // Create Varrock area (higher level)
        var varrock = new SimulatedZone
        {
            Name = "Varrock",
            MinBounds = new Point(200, 200),
            MaxBounds = new Point(350, 350),
            HasBank = true
        };

        // Iron rocks
        for (var i = 0; i < 5; i++)
        {
            varrock.Resources.Add(new SimulatedResource
            {
                Id = 500 + i,
                Name = "Iron rock",
                Type = ResourceType.Rock,
                Location = new Point(250 + i * 3, 250),
                RequiredLevel = 15,
                BaseExperience = 35,
                RespawnTicks = 15
            });
        }

        // Oak trees
        for (var i = 0; i < 5; i++)
        {
            varrock.Resources.Add(new SimulatedResource
            {
                Id = 600 + i,
                Name = "Oak tree",
                Type = ResourceType.Tree,
                Location = new Point(280 + i * 4, 220),
                RequiredLevel = 15,
                BaseExperience = 37,
                RespawnTicks = 45
            });
        }

        // Guards and dark wizards
        for (var i = 0; i < 5; i++)
        {
            varrock.Npcs.Add(new SimulatedNpc
            {
                Id = 100 + i,
                Name = "Guard",
                CombatLevel = 21,
                Location = new Point(220 + i * 5, 230),
                MaxHitpoints = 22,
                CurrentHitpoints = 22,
                RespawnTicks = 50,
                AttackBonus = 10,
                DefenseBonus = 15,
                StrengthBonus = 10,
                DropTable = { (526, 1.0), (995, 0.9) }
            });
        }

        _zones.Add(varrock);

        // Create Wilderness area
        var wilderness = new SimulatedZone
        {
            Name = "Wilderness",
            MinBounds = new Point(0, 400),
            MaxBounds = new Point(500, 600),
            IsWilderness = true,
            WildernessLevel = 20
        };

        // High-level resources
        for (var i = 0; i < 3; i++)
        {
            wilderness.Resources.Add(new SimulatedResource
            {
                Id = 700 + i,
                Name = "Runite rock",
                Type = ResourceType.Rock,
                Location = new Point(100 + i * 20, 500),
                RequiredLevel = 85,
                BaseExperience = 125,
                RespawnTicks = 1200
            });
        }

        // Dangerous NPCs
        for (var i = 0; i < 10; i++)
        {
            wilderness.Npcs.Add(new SimulatedNpc
            {
                Id = 200 + i,
                Name = "Greater Demon",
                CombatLevel = 92,
                Location = new Point(150 + i * 10, 450),
                MaxHitpoints = 87,
                CurrentHitpoints = 87,
                RespawnTicks = 60,
                IsAggressive = true,
                AttackBonus = 50,
                DefenseBonus = 40,
                StrengthBonus = 55,
                DropTable = { (532, 1.0), (995, 0.95), (1247, 0.01) } // Big bones, coins, rune sword
            });
        }

        _zones.Add(wilderness);
    }

    public void AddPlayer(SimulatedPlayer player)
    {
        _players.Add(player);
    }

    public void RemovePlayer(SimulatedPlayer player)
    {
        _players.Remove(player);
    }

    public SimulatedZone? GetZoneAt(Point location)
    {
        return _zones.FirstOrDefault(z => z.Contains(location));
    }

    public IEnumerable<SimulatedResource> GetNearbyResources(Point location, int range, ResourceType? type = null)
    {
        foreach (var zone in _zones)
        {
            foreach (var resource in zone.Resources)
            {
                if (resource.Location.WithinRange(location, range) &&
                    resource.IsAvailable &&
                    (type == null || resource.Type == type))
                {
                    yield return resource;
                }
            }
        }
    }

    public IEnumerable<SimulatedNpc> GetNearbyNpcs(Point location, int range, bool aliveOnly = true)
    {
        foreach (var zone in _zones)
        {
            foreach (var npc in zone.Npcs)
            {
                if (npc.Location.WithinRange(location, range) &&
                    (!aliveOnly || !npc.IsDead))
                {
                    yield return npc;
                }
            }
        }
    }

    public SimulatedResource? FindNearestBank(Point location)
    {
        return _zones
            .SelectMany(z => z.Resources)
            .Where(r => r.Type == ResourceType.Bank)
            .OrderBy(r => r.Location.DistanceTo(location))
            .FirstOrDefault();
    }

    public void DropItem(Point location, int itemId, int amount)
    {
        if (!_groundItems.ContainsKey(location))
            _groundItems[location] = new List<(int, int)>();
        _groundItems[location].Add((itemId, amount));
    }

    public List<(int itemId, int amount)> GetGroundItems(Point location)
    {
        return _groundItems.TryGetValue(location, out var items) ? items : new List<(int, int)>();
    }

    public void ProcessTick(int tick)
    {
        // Update all resources
        foreach (var zone in _zones)
        {
            foreach (var resource in zone.Resources)
            {
                resource.Tick();
            }

            foreach (var npc in zone.Npcs)
            {
                npc.Tick();
            }
        }

        // Decay ground items (simplified - remove after 100 ticks)
        if (tick % 100 == 0)
        {
            _groundItems.Clear();
        }
    }

    public void Reset()
    {
        _players.Clear();
        _groundItems.Clear();
        foreach (var zone in _zones)
        {
            foreach (var resource in zone.Resources)
            {
                resource.CurrentRespawnTimer = 0;
            }
            foreach (var npc in zone.Npcs)
            {
                npc.Respawn();
            }
        }
    }
}
