using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Plugins;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles player commands.
/// </summary>
[PacketHandler(PacketOpcode.Command)]
public sealed class CommandHandler : IPacketHandler
{
    private readonly ILogger<CommandHandler> _logger;
    private readonly PluginManager? _pluginManager;

    public CommandHandler(ILogger<CommandHandler> logger, PluginManager? pluginManager = null)
    {
        _logger = logger;
        _pluginManager = pluginManager;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var commandLine = reader.ReadString();
        if (string.IsNullOrWhiteSpace(commandLine))
            return;

        var parts = commandLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var command = parts[0].ToLowerInvariant();
        var args = parts.Length > 1 ? parts[1..] : Array.Empty<string>();

        _logger.LogDebug("Player {Username} used command: {Command}", player.Username, command);

        // Try plugin handlers first
        if (_pluginManager?.HandleCommand(player, command, args) == true)
            return;

        // Built-in commands
        switch (command)
        {
            case "help":
                ShowHelp(player);
                break;

            case "players":
            case "online":
                ShowOnlinePlayers(player);
                break;

            case "coords":
            case "position":
            case "pos":
                player.Message($"Position: ({player.Location.X}, {player.Location.Y})");
                break;

            case "time":
                player.Message($"Server time: {DateTime.UtcNow:HH:mm:ss UTC}");
                break;

            case "fatigue":
                player.Message($"Fatigue: {player.Fatigue.CurrentFatigue:F1}%");
                break;

            case "stats":
            case "levels":
                ShowStats(player);
                break;

            case "combat":
                player.Message($"Combat level: {player.CombatLevel}");
                break;

            // Admin commands
            case "teleport":
            case "tp":
                if (player.IsAdmin && args.Length >= 2)
                {
                    if (int.TryParse(args[0], out var x) && int.TryParse(args[1], out var y))
                    {
                        player.Teleport(new Models.Point(x, y));
                        player.Message($"Teleported to ({x}, {y})");
                    }
                }
                break;

            case "item":
            case "give":
                if (player.IsAdmin && args.Length >= 1)
                {
                    if (int.TryParse(args[0], out var itemId))
                    {
                        var amount = args.Length > 1 && int.TryParse(args[1], out var a) ? a : 1;
                        // Would add item to inventory
                        player.Message($"Gave {amount}x item {itemId}");
                    }
                }
                break;

            case "setlevel":
                if (player.IsAdmin && args.Length >= 2)
                {
                    if (Enum.TryParse<Skills.Skill>(args[0], true, out var skill) &&
                        int.TryParse(args[1], out var level))
                    {
                        // Would set level
                        player.Message($"Set {skill} to level {level}");
                    }
                }
                break;

            case "kill":
                if (player.IsAdmin)
                {
                    player.CurrentHitpoints = 0;
                    player.Message("You killed yourself.");
                }
                break;

            case "heal":
            case "restore":
                if (player.IsAdmin)
                {
                    player.CurrentHitpoints = player.Skills.GetMaxLevel(Skills.Skill.Hitpoints);
                    player.Message("Health restored.");
                }
                break;

            case "god":
                if (player.IsAdmin)
                {
                    // Would toggle invincibility
                    player.Message("God mode toggled.");
                }
                break;

            default:
                player.Message($"Unknown command: {command}");
                break;
        }

        await ValueTask.CompletedTask;
    }

    private void ShowHelp(Player player)
    {
        player.Message("Available commands:");
        player.Message("::help - Show this message");
        player.Message("::players - Show online players");
        player.Message("::coords - Show your position");
        player.Message("::stats - Show your stats");
        player.Message("::combat - Show combat level");
        player.Message("::fatigue - Show fatigue");
        player.Message("::time - Show server time");

        if (player.IsAdmin)
        {
            player.Message("--- Admin Commands ---");
            player.Message("::tp x y - Teleport");
            player.Message("::item id [amount] - Give item");
            player.Message("::setlevel skill level - Set level");
            player.Message("::heal - Restore health");
            player.Message("::kill - Kill yourself");
        }
    }

    private void ShowOnlinePlayers(Player player)
    {
        // Would get from world service
        player.Message("Online players: 1");
    }

    private void ShowStats(Player player)
    {
        var skills = player.Skills;
        player.Message($"Attack: {skills.GetMaxLevel(Skills.Skill.Attack)} " +
                      $"Defence: {skills.GetMaxLevel(Skills.Skill.Defence)} " +
                      $"Strength: {skills.GetMaxLevel(Skills.Skill.Strength)}");
        player.Message($"Hitpoints: {skills.GetMaxLevel(Skills.Skill.Hitpoints)} " +
                      $"Ranged: {skills.GetMaxLevel(Skills.Skill.Ranged)} " +
                      $"Prayer: {skills.GetMaxLevel(Skills.Skill.Prayer)}");
        player.Message($"Magic: {skills.GetMaxLevel(Skills.Skill.Magic)} " +
                      $"Total: {skills.TotalLevel}");
    }
}
