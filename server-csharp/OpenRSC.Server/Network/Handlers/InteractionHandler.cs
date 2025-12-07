using Microsoft.Extensions.Logging;
using OpenRSC.Server.Actions;
using OpenRSC.Server.Combat;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Npc;
using OpenRSC.Server.Services;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles NPC interaction packets.
/// </summary>
public sealed class NpcInteractionHandler : IPacketHandler
{
    private const int OpNpcTalk = 153;
    private const int OpNpcAttack = 190;
    private const int OpNpcCommand = 202;

    private readonly ILogger<NpcInteractionHandler> _logger;
    private readonly WorldService _worldService;
    private readonly NpcManager _npcManager;
    private readonly CombatManager _combatManager;

    public int[] Opcodes => new[] { OpNpcTalk, OpNpcAttack, OpNpcCommand };

    public NpcInteractionHandler(
        ILogger<NpcInteractionHandler> logger,
        WorldService worldService,
        NpcManager npcManager,
        CombatManager combatManager)
    {
        _logger = logger;
        _worldService = worldService;
        _npcManager = npcManager;
        _combatManager = combatManager;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        var npcIndex = packet.ReadShort();
        var npc = _npcManager.GetNpc(npcIndex);

        if (npc is null || npc.IsRemoved)
        {
            _logger.LogWarning("{Username} tried to interact with invalid NPC {Index}",
                player.Username, npcIndex);
            return;
        }

        switch (packet.Opcode)
        {
            case OpNpcTalk:
                await HandleTalkAsync(player, npc);
                break;
            case OpNpcAttack:
                await HandleAttackAsync(player, npc);
                break;
            case OpNpcCommand:
                await HandleCommandAsync(player, npc);
                break;
        }
    }

    private async Task HandleTalkAsync(Player player, Entities.Npc npc)
    {
        // Create walk-to action for talking
        var action = new WalkToMobAction(player, npc)
        {
            ExecuteAction = () =>
            {
                _logger.LogDebug("{Username} talking to {Npc}", player.Username, npc.Name);
                // TODO: Start dialogue
                player.Message($"The {npc.Name} doesn't want to talk right now.");
            }
        };

        player.SetWalkToAction(action);
        await Task.CompletedTask;
    }

    private async Task HandleAttackAsync(Player player, Entities.Npc npc)
    {
        if (!npc.IsAttackable)
        {
            player.Message("You can't attack that.");
            return;
        }

        if (npc.InCombat)
        {
            player.Message("Someone is already fighting that.");
            return;
        }

        // Create walk-to action for attacking
        var action = new WalkToMobAction(player, npc)
        {
            ExecuteAction = () =>
            {
                var encounter = _combatManager.StartCombat(player, npc);
                if (encounter is null)
                {
                    player.Message("You can't attack right now.");
                }
            }
        };

        player.SetWalkToAction(action);
        await Task.CompletedTask;
    }

    private async Task HandleCommandAsync(Player player, Entities.Npc npc)
    {
        var command = npc.Definition?.Command ?? "Talk";

        var action = new WalkToMobAction(player, npc)
        {
            ExecuteAction = () =>
            {
                _logger.LogDebug("{Username} using {Command} on {Npc}",
                    player.Username, command, npc.Name);

                // Handle different commands
                switch (command.ToLowerInvariant())
                {
                    case "shop":
                        // TODO: Open shop interface
                        player.Message($"The {npc.Name}'s shop is currently closed.");
                        break;
                    case "pickpocket":
                        // TODO: Thieving skill check
                        player.Message($"You attempt to pickpocket the {npc.Name}...");
                        break;
                    default:
                        player.Message($"Nothing interesting happens.");
                        break;
                }
            }
        };

        player.SetWalkToAction(action);
        await Task.CompletedTask;
    }
}

/// <summary>
/// Handles object interaction packets.
/// </summary>
public sealed class ObjectInteractionHandler : IPacketHandler
{
    private const int OpObjectAction1 = 136;
    private const int OpObjectAction2 = 79;
    private const int OpBoundaryAction1 = 14;
    private const int OpBoundaryAction2 = 127;

    private readonly ILogger<ObjectInteractionHandler> _logger;
    private readonly WorldService _worldService;

    public int[] Opcodes => new[] { OpObjectAction1, OpObjectAction2, OpBoundaryAction1, OpBoundaryAction2 };

    public ObjectInteractionHandler(ILogger<ObjectInteractionHandler> logger, WorldService worldService)
    {
        _logger = logger;
        _worldService = worldService;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        var x = packet.ReadShort();
        var y = packet.ReadShort();
        var location = new Point(x, y);

        var isBoundary = packet.Opcode is OpBoundaryAction1 or OpBoundaryAction2;
        var isSecondAction = packet.Opcode is OpObjectAction2 or OpBoundaryAction2;

        _logger.LogDebug("{Username} interacting with {Type} at {Location}, action={Action}",
            player.Username,
            isBoundary ? "boundary" : "object",
            location,
            isSecondAction ? 2 : 1);

        // Create walk-to-object action
        var gameObject = new GameObject(0, location); // TODO: Look up actual object
        var action = new WalkToObjectAction(player, gameObject)
        {
            ExecuteAction = () => HandleObjectAction(player, location, isBoundary, isSecondAction)
        };

        player.SetWalkToAction(action);
        await Task.CompletedTask;
    }

    private void HandleObjectAction(Player player, Point location, bool isBoundary, bool isSecondAction)
    {
        // TODO: Look up object definition and execute appropriate action
        if (isBoundary)
        {
            // Door/gate interactions
            player.Message("The door is locked.");
        }
        else
        {
            // Regular object interactions
            player.Message("Nothing interesting happens.");
        }
    }
}

/// <summary>
/// Handles ground item interaction packets.
/// </summary>
public sealed class GroundItemHandler : IPacketHandler
{
    private const int OpPickupItem = 247;
    private const int OpExamineItem = 181;

    private readonly ILogger<GroundItemHandler> _logger;

    public int[] Opcodes => new[] { OpPickupItem, OpExamineItem };

    public GroundItemHandler(ILogger<GroundItemHandler> logger)
    {
        _logger = logger;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        var x = packet.ReadShort();
        var y = packet.ReadShort();
        var itemId = packet.ReadShort();
        var location = new Point(x, y);

        if (packet.Opcode == OpExamineItem)
        {
            // TODO: Look up item definition and send examine message
            player.Message("A useful item.");
            return;
        }

        // Pickup action
        var action = new WalkToPointAction(player, location)
        {
            ExecuteAction = () =>
            {
                _logger.LogDebug("{Username} picking up item {ItemId} at {Location}",
                    player.Username, itemId, location);

                // TODO: Actually pick up the item
                player.Message("You pick up the item.");
            }
        };

        player.SetWalkToAction(action);
        await Task.CompletedTask;
    }
}

/// <summary>
/// Handles player vs player interaction packets.
/// </summary>
public sealed class PlayerInteractionHandler : IPacketHandler
{
    private const int OpAttackPlayer = 171;
    private const int OpFollowPlayer = 165;
    private const int OpTradePlayer = 142;
    private const int OpDuelPlayer = 103;

    private readonly ILogger<PlayerInteractionHandler> _logger;
    private readonly WorldService _worldService;
    private readonly CombatManager _combatManager;

    public int[] Opcodes => new[] { OpAttackPlayer, OpFollowPlayer, OpTradePlayer, OpDuelPlayer };

    public PlayerInteractionHandler(
        ILogger<PlayerInteractionHandler> logger,
        WorldService worldService,
        CombatManager combatManager)
    {
        _logger = logger;
        _worldService = worldService;
        _combatManager = combatManager;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        var targetIndex = packet.ReadShort();
        var target = _worldService.GetPlayer(targetIndex);

        if (target is null || target.IsRemoved)
        {
            _logger.LogWarning("{Username} tried to interact with invalid player {Index}",
                player.Username, targetIndex);
            return;
        }

        switch (packet.Opcode)
        {
            case OpAttackPlayer:
                await HandleAttackAsync(player, target);
                break;
            case OpFollowPlayer:
                await HandleFollowAsync(player, target);
                break;
            case OpTradePlayer:
                await HandleTradeAsync(player, target);
                break;
            case OpDuelPlayer:
                await HandleDuelAsync(player, target);
                break;
        }
    }

    private async Task HandleAttackAsync(Player player, Player target)
    {
        // TODO: Check wilderness rules, combat levels, etc.
        if (target.InCombat)
        {
            player.Message("That player is already in combat.");
            return;
        }

        var action = new WalkToMobAction(player, target)
        {
            ExecuteAction = () =>
            {
                var encounter = _combatManager.StartCombat(player, target);
                if (encounter is null)
                {
                    player.Message("You can't attack that player.");
                }
            }
        };

        player.SetWalkToAction(action);
        await Task.CompletedTask;
    }

    private async Task HandleFollowAsync(Player player, Player target)
    {
        _logger.LogDebug("{Username} following {Target}", player.Username, target.Username);
        // TODO: Implement following
        await Task.CompletedTask;
    }

    private async Task HandleTradeAsync(Player player, Player target)
    {
        _logger.LogDebug("{Username} requesting trade with {Target}", player.Username, target.Username);
        target.Message($"{player.Username} wishes to trade with you.");
        // TODO: Implement trading
        await Task.CompletedTask;
    }

    private async Task HandleDuelAsync(Player player, Player target)
    {
        _logger.LogDebug("{Username} requesting duel with {Target}", player.Username, target.Username);
        target.Message($"{player.Username} wishes to duel with you.");
        // TODO: Implement dueling
        await Task.CompletedTask;
    }
}
