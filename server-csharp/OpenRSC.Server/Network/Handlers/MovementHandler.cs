using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Services;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles player movement packets.
/// </summary>
public sealed class MovementHandler : IPacketHandler
{
    private const int OpWalkToEntity = 16;
    private const int OpWalkToPoint = 187;
    private const int OpWalkToAction = 246;

    private readonly ILogger<MovementHandler> _logger;
    private readonly WorldService _worldService;

    public int[] Opcodes => new[] { OpWalkToEntity, OpWalkToPoint, OpWalkToAction };

    public MovementHandler(ILogger<MovementHandler> logger, WorldService worldService)
    {
        _logger = logger;
        _worldService = worldService;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        // Read start coordinates
        var startX = packet.ReadShort();
        var startY = packet.ReadShort();

        // Clear any existing path
        player.WalkingQueue.Reset();

        // Read path waypoints
        var numWaypoints = (packet.Length - 4) / 2;
        var points = new List<Point>(numWaypoints + 1);
        points.Add(new Point(startX, startY));

        for (var i = 0; i < numWaypoints; i++)
        {
            var dx = packet.ReadSByte();
            var dy = packet.ReadSByte();
            points.Add(new Point(startX + dx, startY + dy));
        }

        // Validate path
        if (!ValidatePath(player, points))
        {
            _logger.LogWarning("Invalid path from {Username}", player.Username);
            return;
        }

        // Add path to walking queue
        foreach (var point in points.Skip(1)) // Skip starting point
        {
            player.WalkingQueue.AddStep(point);
        }

        // Cancel current action if moving manually
        if (packet.Opcode == OpWalkToPoint)
        {
            player.SetWalkToAction(null);
        }

        _logger.LogDebug("{Username} walking to {Destination} via {Count} waypoints",
            player.Username, points.Last(), points.Count);

        await Task.CompletedTask;
    }

    private bool ValidatePath(Player player, List<Point> points)
    {
        if (points.Count == 0)
            return false;

        // Validate starting point is near player
        var start = points[0];
        if (!player.Location.WithinRange(start, 16))
        {
            _logger.LogWarning("{Username} path start {Start} too far from location {Location}",
                player.Username, start, player.Location);
            return false;
        }

        // Validate path length
        if (points.Count > 50)
            return false;

        return true;
    }
}

/// <summary>
/// Handles player chat messages.
/// </summary>
public sealed class ChatHandler : IPacketHandler
{
    private const int OpChat = 216;

    private readonly ILogger<ChatHandler> _logger;
    private readonly WorldService _worldService;

    public int[] Opcodes => new[] { OpChat };

    public ChatHandler(ILogger<ChatHandler> logger, WorldService worldService)
    {
        _logger = logger;
        _worldService = worldService;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        var messageBytes = packet.ReadBytes(packet.Remaining);
        var message = DecodeMessage(messageBytes);

        if (string.IsNullOrWhiteSpace(message))
            return;

        // Filter profanity and validate
        message = FilterMessage(message);

        if (message.Length > 80)
            message = message[..80];

        _logger.LogDebug("{Username}: {Message}", player.Username, message);

        // Broadcast to nearby players
        await BroadcastChatAsync(player, message);
    }

    private static string DecodeMessage(byte[] data)
    {
        // RSC uses a custom encoding - simplified here
        var chars = new char[data.Length];
        for (var i = 0; i < data.Length; i++)
        {
            chars[i] = (char)(data[i] & 0x7F);
        }
        return new string(chars).Trim();
    }

    private static string FilterMessage(string message)
    {
        // Basic profanity filter - would use a proper word list
        return message
            .Replace("badword", "****")
            .Trim();
    }

    private async Task BroadcastChatAsync(Player speaker, string message)
    {
        // TODO: Send chat packet to all nearby players via ActionSender
        _logger.LogDebug("[Chat] {Username}: {Message}", speaker.Username, message);
        await Task.CompletedTask;
    }
}

/// <summary>
/// Handles player command messages (starting with ::).
/// </summary>
public sealed class CommandHandler : IPacketHandler
{
    private const int OpCommand = 38;

    private readonly ILogger<CommandHandler> _logger;
    private readonly Dictionary<string, Func<Player, string[], Task>> _commands = new();

    public int[] Opcodes => new[] { OpCommand };

    public CommandHandler(ILogger<CommandHandler> logger)
    {
        _logger = logger;
        RegisterCommands();
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        var commandLine = packet.ReadString();
        if (string.IsNullOrWhiteSpace(commandLine))
            return;

        var parts = commandLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
            return;

        var command = parts[0].ToLowerInvariant();
        var args = parts.Skip(1).ToArray();

        _logger.LogInformation("{Username} used command: {Command}", player.Username, commandLine);

        if (_commands.TryGetValue(command, out var handler))
        {
            try
            {
                await handler(player, args);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error executing command {Command}", command);
                player.Message("An error occurred executing that command.");
            }
        }
        else
        {
            player.Message("Unknown command.");
        }
    }

    private void RegisterCommands()
    {
        _commands["help"] = async (player, _) =>
        {
            player.Message("Available commands: help, coords, stats");
            await Task.CompletedTask;
        };

        _commands["coords"] = async (player, _) =>
        {
            player.Message($"Location: ({player.Location.X}, {player.Location.Y})");
            await Task.CompletedTask;
        };

        _commands["stats"] = async (player, _) =>
        {
            player.Message($"Total Level: {player.Skills.GetTotalLevel()}");
            player.Message($"Combat Level: {player.CombatLevel}");
            await Task.CompletedTask;
        };
    }
}
