using Microsoft.Extensions.Logging;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.World;

/// <summary>
/// Loads map data from files.
/// </summary>
public sealed class MapLoader
{
    private readonly ILogger<MapLoader> _logger;
    private readonly WorldMap _worldMap;

    public MapLoader(ILogger<MapLoader> logger, WorldMap worldMap)
    {
        _logger = logger;
        _worldMap = worldMap;
    }

    /// <summary>
    /// Loads all map data from the specified directory.
    /// </summary>
    public async Task LoadAsync(string dataPath)
    {
        _logger.LogInformation("Loading map data from {Path}", dataPath);

        var landscapePath = Path.Combine(dataPath, "landscape");
        if (Directory.Exists(landscapePath))
        {
            await LoadLandscapeAsync(landscapePath);
        }

        var locationsPath = Path.Combine(dataPath, "locations");
        if (Directory.Exists(locationsPath))
        {
            await LoadLocationsAsync(locationsPath);
        }

        _logger.LogInformation("Map data loaded. {RegionCount} regions active",
            _worldMap.LoadedRegionCount);
    }

    /// <summary>
    /// Loads landscape/terrain data.
    /// </summary>
    private async Task LoadLandscapeAsync(string path)
    {
        var files = Directory.GetFiles(path, "*.hei");

        foreach (var file in files)
        {
            try
            {
                await LoadLandscapeFileAsync(file);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to load landscape file {File}", file);
            }
        }

        _logger.LogDebug("Loaded {Count} landscape files", files.Length);
    }

    private async Task LoadLandscapeFileAsync(string filePath)
    {
        var fileName = Path.GetFileNameWithoutExtension(filePath);

        // Parse region coordinates from filename (e.g., "h0x50y50")
        if (!TryParseRegionFromFileName(fileName, out var regionX, out var regionY))
            return;

        var data = await File.ReadAllBytesAsync(filePath);
        var region = _worldMap.GetRegion(new Point(regionX * 48, regionY * 48));

        // Load height/terrain data
        // RSC landscape format: 48x48 tiles, 1 byte elevation per tile
        var index = 0;
        for (var y = 0; y < 48 && index < data.Length; y++)
        {
            for (var x = 0; x < 48 && index < data.Length; x++)
            {
                var tile = region.GetTile(new Point(regionX * 48 + x, regionY * 48 + y));
                if (tile is not null)
                {
                    tile.Elevation = data[index] & 0x0F;
                }
                index++;
            }
        }
    }

    /// <summary>
    /// Loads object/location data.
    /// </summary>
    private async Task LoadLocationsAsync(string path)
    {
        var objectsFile = Path.Combine(path, "loc.dat");
        if (File.Exists(objectsFile))
        {
            await LoadObjectsAsync(objectsFile);
        }

        var wallsFile = Path.Combine(path, "walls.dat");
        if (File.Exists(wallsFile))
        {
            await LoadWallsAsync(wallsFile);
        }
    }

    private async Task LoadObjectsAsync(string filePath)
    {
        var data = await File.ReadAllBytesAsync(filePath);
        var objectCount = 0;

        // RSC object format: x(2), y(2), id(2), direction(1)
        var offset = 0;
        while (offset + 6 < data.Length)
        {
            var x = ReadShort(data, offset);
            var y = ReadShort(data, offset + 2);
            var id = ReadShort(data, offset + 4);
            var direction = data[offset + 6];

            var location = new Point(x, y);
            if (WorldMap.IsValidLocation(location))
            {
                var gameObject = new Entities.GameObject(id, location)
                {
                    Direction = direction,
                    IsBlocking = true // TODO: Look up from definition
                };
                _worldMap.AddObject(gameObject);
                objectCount++;
            }

            offset += 7;
        }

        _logger.LogDebug("Loaded {Count} game objects", objectCount);
    }

    private async Task LoadWallsAsync(string filePath)
    {
        var data = await File.ReadAllBytesAsync(filePath);
        var wallCount = 0;

        // RSC wall format: x(2), y(2), direction(1), id(2)
        var offset = 0;
        while (offset + 6 < data.Length)
        {
            var x = ReadShort(data, offset);
            var y = ReadShort(data, offset + 2);
            var direction = data[offset + 4];
            var id = ReadShort(data, offset + 5);

            var location = new Point(x, y);
            if (WorldMap.IsValidLocation(location))
            {
                var tile = _worldMap.GetTile(location);
                if (tile is not null)
                {
                    // Add blocking based on wall direction
                    var blockFlag = direction switch
                    {
                        0 => TraversalFlags.BlockNorth,
                        1 => TraversalFlags.BlockEast,
                        2 => TraversalFlags.BlockSouth,
                        3 => TraversalFlags.BlockWest,
                        _ => TraversalFlags.None
                    };
                    tile.AddBlock(blockFlag);
                    wallCount++;
                }
            }

            offset += 7;
        }

        _logger.LogDebug("Loaded {Count} walls", wallCount);
    }

    private static bool TryParseRegionFromFileName(string fileName, out int regionX, out int regionY)
    {
        regionX = regionY = 0;

        // Format: h0x{X}y{Y}
        if (!fileName.StartsWith("h"))
            return false;

        var xIndex = fileName.IndexOf('x');
        var yIndex = fileName.IndexOf('y');

        if (xIndex < 0 || yIndex < 0 || yIndex <= xIndex)
            return false;

        var xStr = fileName.Substring(xIndex + 1, yIndex - xIndex - 1);
        var yStr = fileName.Substring(yIndex + 1);

        return int.TryParse(xStr, out regionX) && int.TryParse(yStr, out regionY);
    }

    private static short ReadShort(byte[] data, int offset)
    {
        return (short)((data[offset] << 8) | data[offset + 1]);
    }
}

/// <summary>
/// Loads object definitions.
/// </summary>
public sealed class ObjectDefinitionLoader
{
    private readonly ILogger<ObjectDefinitionLoader> _logger;
    private readonly Dictionary<int, ObjectDefinition> _definitions = new();

    public ObjectDefinitionLoader(ILogger<ObjectDefinitionLoader> logger)
    {
        _logger = logger;
    }

    public async Task LoadAsync(string filePath)
    {
        if (!File.Exists(filePath))
        {
            _logger.LogWarning("Object definitions file not found: {Path}", filePath);
            return;
        }

        var lines = await File.ReadAllLinesAsync(filePath);
        foreach (var line in lines.Where(l => !string.IsNullOrWhiteSpace(l) && !l.StartsWith("#")))
        {
            try
            {
                var def = ParseDefinition(line);
                if (def is not null)
                {
                    _definitions[def.Id] = def;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to parse object definition: {Line}", line);
            }
        }

        _logger.LogInformation("Loaded {Count} object definitions", _definitions.Count);
    }

    public ObjectDefinition? GetById(int id)
    {
        return _definitions.TryGetValue(id, out var def) ? def : null;
    }

    private static ObjectDefinition? ParseDefinition(string line)
    {
        var parts = line.Split('\t');
        if (parts.Length < 4)
            return null;

        return new ObjectDefinition
        {
            Id = int.Parse(parts[0]),
            Name = parts[1],
            Description = parts[2],
            Command1 = parts[3],
            Command2 = parts.Length > 4 ? parts[4] : null,
            Width = parts.Length > 5 ? int.Parse(parts[5]) : 1,
            Height = parts.Length > 6 ? int.Parse(parts[6]) : 1,
            IsBlocking = parts.Length > 7 && parts[7] == "1"
        };
    }
}

/// <summary>
/// Definition of a game object type.
/// </summary>
public sealed record ObjectDefinition
{
    public required int Id { get; init; }
    public required string Name { get; init; }
    public string Description { get; init; } = string.Empty;
    public string? Command1 { get; init; }
    public string? Command2 { get; init; }
    public int Width { get; init; } = 1;
    public int Height { get; init; } = 1;
    public bool IsBlocking { get; init; }
}
