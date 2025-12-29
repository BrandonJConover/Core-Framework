using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.World;

namespace OpenRSC.Server.Services;

/// <summary>
/// Handles object and boundary interactions.
/// </summary>
public sealed class ObjectInteractionService
{
    private readonly ILogger<ObjectInteractionService> _logger;
    private readonly IWorldService _worldService;
    private readonly ObjectDefinitionLoader _objectDefinitions;

    // Known object types by name patterns
    private static readonly HashSet<string> DoorKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        "door", "gate", "fence", "cell"
    };

    private static readonly HashSet<string> LadderKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        "ladder", "stairs", "staircase"
    };

    private static readonly HashSet<string> BankKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        "bank booth", "bank chest", "banker"
    };

    public ObjectInteractionService(
        ILogger<ObjectInteractionService> logger,
        IWorldService worldService,
        ObjectDefinitionLoader objectDefinitions)
    {
        _logger = logger;
        _worldService = worldService;
        _objectDefinitions = objectDefinitions;
    }

    /// <summary>
    /// Handles interaction with an object.
    /// </summary>
    public async Task HandleObjectInteractionAsync(
        Player player,
        Point location,
        bool isBoundary,
        bool isSecondAction)
    {
        // Get objects at the location
        var objects = _worldService.GetObjectsAt(location).ToList();

        if (objects.Count == 0)
        {
            player.Message("There's nothing there.");
            return;
        }

        var gameObject = objects.First();
        var definition = _objectDefinitions.GetById(gameObject.DefinitionId);

        if (definition is null)
        {
            player.Message("You can't interact with that.");
            return;
        }

        var commandName = isSecondAction ? definition.Command2 : definition.Command1;
        var objectName = definition.Name.ToLowerInvariant();

        _logger.LogDebug("Object interaction: {ObjectName} ({Id}) - Command: {Command}",
            definition.Name, definition.Id, commandName ?? "none");

        // Handle based on object type
        if (IsDoor(objectName, commandName))
        {
            await HandleDoorAsync(player, gameObject, definition, isSecondAction);
        }
        else if (IsLadder(objectName, commandName))
        {
            await HandleLadderAsync(player, gameObject, definition, isSecondAction);
        }
        else if (IsBank(objectName, commandName))
        {
            await HandleBankAsync(player);
        }
        else if (commandName?.Equals("mine", StringComparison.OrdinalIgnoreCase) == true)
        {
            HandleMining(player, gameObject, definition);
        }
        else if (commandName?.Equals("chop", StringComparison.OrdinalIgnoreCase) == true)
        {
            HandleWoodcutting(player, gameObject, definition);
        }
        else if (commandName?.Equals("fish", StringComparison.OrdinalIgnoreCase) == true)
        {
            HandleFishing(player, gameObject, definition);
        }
        else if (commandName?.Equals("examine", StringComparison.OrdinalIgnoreCase) == true ||
                 isSecondAction && definition.Command2 is null)
        {
            player.Message(definition.Description);
        }
        else
        {
            // Generic interaction
            player.Message($"You interact with the {definition.Name}.");
        }
    }

    private static bool IsDoor(string objectName, string? command)
    {
        if (command?.Equals("open", StringComparison.OrdinalIgnoreCase) == true ||
            command?.Equals("close", StringComparison.OrdinalIgnoreCase) == true)
            return true;

        return DoorKeywords.Any(k => objectName.Contains(k, StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsLadder(string objectName, string? command)
    {
        if (command?.Equals("climb-up", StringComparison.OrdinalIgnoreCase) == true ||
            command?.Equals("climb-down", StringComparison.OrdinalIgnoreCase) == true ||
            command?.Equals("climb", StringComparison.OrdinalIgnoreCase) == true)
            return true;

        return LadderKeywords.Any(k => objectName.Contains(k, StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsBank(string objectName, string? command)
    {
        return BankKeywords.Any(k => objectName.Contains(k, StringComparison.OrdinalIgnoreCase)) ||
               command?.Equals("use", StringComparison.OrdinalIgnoreCase) == true &&
               objectName.Contains("bank", StringComparison.OrdinalIgnoreCase);
    }

    private async Task HandleDoorAsync(Player player, GameObject gameObject, ObjectDefinition definition, bool isSecondAction)
    {
        var command = isSecondAction ? definition.Command2 : definition.Command1;

        if (command?.Equals("open", StringComparison.OrdinalIgnoreCase) == true)
        {
            // Check if door requires a key or quest
            if (definition.Name.Contains("locked", StringComparison.OrdinalIgnoreCase))
            {
                player.Message("The door is locked.");
                return;
            }

            // Open the door - move player through
            player.Message("You open the door.");

            // Move player to the other side
            var direction = GetDoorDirection(player.Location, gameObject.Location);
            var newLocation = player.Location + direction;
            player.MoveTo(newLocation);

            await Task.CompletedTask;
        }
        else if (command?.Equals("close", StringComparison.OrdinalIgnoreCase) == true)
        {
            player.Message("You close the door.");
        }
        else
        {
            player.Message("You can't do that with this door.");
        }
    }

    private async Task HandleLadderAsync(Player player, GameObject gameObject, ObjectDefinition definition, bool isSecondAction)
    {
        var command = isSecondAction ? definition.Command2 : definition.Command1;

        if (command?.Contains("up", StringComparison.OrdinalIgnoreCase) == true)
        {
            // Climb up - increase Y coordinate (in RSC, going up increases Y)
            var newLocation = new Point(player.Location.X, player.Location.Y - 944);
            player.Message("You climb up the ladder.");
            player.MoveTo(newLocation);
            _ = player.ActionSender?.SendTeleportAsync();
        }
        else if (command?.Contains("down", StringComparison.OrdinalIgnoreCase) == true)
        {
            // Climb down - decrease Y coordinate
            var newLocation = new Point(player.Location.X, player.Location.Y + 944);
            player.Message("You climb down the ladder.");
            player.MoveTo(newLocation);
            _ = player.ActionSender?.SendTeleportAsync();
        }
        else
        {
            // Generic climb
            player.Message("You climb the ladder.");
        }

        await Task.CompletedTask;
    }

    private async Task HandleBankAsync(Player player)
    {
        player.Message("Welcome to the bank.");
        _ = player.ActionSender?.SendOpenBankAsync();
        await Task.CompletedTask;
    }

    private void HandleMining(Player player, GameObject gameObject, ObjectDefinition definition)
    {
        // Would start mining action
        player.Message($"You swing your pickaxe at the {definition.Name}.");
        // player.SetSkillAction(new MiningAction(player, gameObject));
    }

    private void HandleWoodcutting(Player player, GameObject gameObject, ObjectDefinition definition)
    {
        // Would start woodcutting action
        player.Message($"You swing your axe at the {definition.Name}.");
        // player.SetSkillAction(new WoodcuttingAction(player, gameObject));
    }

    private void HandleFishing(Player player, GameObject gameObject, ObjectDefinition definition)
    {
        // Would start fishing action
        player.Message($"You attempt to catch some fish.");
        // player.SetSkillAction(new FishingAction(player, gameObject));
    }

    private static Point GetDoorDirection(Point playerPos, Point doorPos)
    {
        var dx = doorPos.X - playerPos.X;
        var dy = doorPos.Y - playerPos.Y;

        // Return normalized direction to walk through the door
        return new Point(Math.Sign(dx), Math.Sign(dy));
    }
}
