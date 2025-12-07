using Microsoft.Extensions.Logging;
using OpenRSC.Server.Combat;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Services;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles combat-related packets.
/// </summary>
[PacketHandler(PacketOpcode.AttackNpc)]
public sealed class AttackNpcHandler : IPacketHandler
{
    private readonly ILogger<AttackNpcHandler> _logger;
    private readonly INpcManager _npcManager;
    private readonly CombatManager _combatManager;

    public AttackNpcHandler(
        ILogger<AttackNpcHandler> logger,
        INpcManager npcManager,
        CombatManager combatManager)
    {
        _logger = logger;
        _npcManager = npcManager;
        _combatManager = combatManager;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var npcIndex = reader.ReadInt16();
        var npc = _npcManager.GetNpc(npcIndex);

        if (npc is null)
        {
            player.Message("That NPC doesn't exist.");
            return;
        }

        if (npc.IsDead)
        {
            player.Message("That NPC is already dead.");
            return;
        }

        if (!player.Location.WithinRange(npc.Location, 1))
        {
            // Would queue walk action first
            player.Message("You need to get closer.");
            return;
        }

        _logger.LogDebug("Player {Username} attacking NPC {NpcId}", player.Username, npc.NpcId);

        _combatManager.InitiateCombat(player, npc);

        await ValueTask.CompletedTask;
    }
}

/// <summary>
/// Handles player attack packets.
/// </summary>
[PacketHandler(PacketOpcode.AttackPlayer)]
public sealed class AttackPlayerHandler : IPacketHandler
{
    private readonly ILogger<AttackPlayerHandler> _logger;
    private readonly WorldService _worldService;
    private readonly CombatManager _combatManager;
    private readonly Wilderness.WildernessManager _wildernessManager;

    public AttackPlayerHandler(
        ILogger<AttackPlayerHandler> logger,
        WorldService worldService,
        CombatManager combatManager,
        Wilderness.WildernessManager wildernessManager)
    {
        _logger = logger;
        _worldService = worldService;
        _combatManager = combatManager;
        _wildernessManager = wildernessManager;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var targetIndex = reader.ReadInt16();
        var target = _worldService.GetPlayer(targetIndex);

        if (target is null)
        {
            player.Message("That player doesn't exist.");
            return;
        }

        if (target == player)
        {
            player.Message("You can't attack yourself.");
            return;
        }

        // Check wilderness rules
        var attackResult = Wilderness.WildernessManager.CanAttack(player, target);
        if (!attackResult.Success)
        {
            player.Message(attackResult.Message!);
            return;
        }

        if (!player.Location.WithinRange(target.Location, 1))
        {
            player.Message("You need to get closer.");
            return;
        }

        _logger.LogDebug("Player {Username} attacking player {Target}", player.Username, target.Username);

        // Apply skull if attacking first
        _wildernessManager.ApplySkull(player, target);

        _combatManager.InitiateCombat(player, target);

        await ValueTask.CompletedTask;
    }
}

/// <summary>
/// Handles combat style selection.
/// </summary>
[PacketHandler(PacketOpcode.CombatStyle)]
public sealed class CombatStyleHandler : IPacketHandler
{
    private readonly ILogger<CombatStyleHandler> _logger;

    public CombatStyleHandler(ILogger<CombatStyleHandler> logger)
    {
        _logger = logger;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var style = reader.ReadByte();

        if (style > 3)
        {
            _logger.LogWarning("Player {Username} sent invalid combat style {Style}", player.Username, style);
            return;
        }

        player.CombatSettings.Style = (CombatStyle)style;
        _logger.LogDebug("Player {Username} changed combat style to {Style}", player.Username, player.CombatSettings.Style);

        await ValueTask.CompletedTask;
    }
}

/// <summary>
/// Handles prayer activation/deactivation.
/// </summary>
[PacketHandler(PacketOpcode.PrayerToggle)]
public sealed class PrayerToggleHandler : IPacketHandler
{
    private readonly ILogger<PrayerToggleHandler> _logger;

    public PrayerToggleHandler(ILogger<PrayerToggleHandler> logger)
    {
        _logger = logger;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var prayerId = reader.ReadByte();
        var activate = reader.ReadByte() == 1;

        if (activate)
        {
            var result = player.Prayers.Activate(prayerId);
            if (!result.Success)
            {
                player.Message(result.Message!);
            }
        }
        else
        {
            player.Prayers.Deactivate(prayerId);
        }

        _logger.LogDebug("Player {Username} {Action} prayer {PrayerId}",
            player.Username, activate ? "activated" : "deactivated", prayerId);

        await ValueTask.CompletedTask;
    }
}

/// <summary>
/// Handles spell casting.
/// </summary>
[PacketHandler(PacketOpcode.CastSpell)]
public sealed class CastSpellHandler : IPacketHandler
{
    private readonly ILogger<CastSpellHandler> _logger;
    private readonly INpcManager _npcManager;
    private readonly WorldService _worldService;

    public CastSpellHandler(
        ILogger<CastSpellHandler> logger,
        INpcManager npcManager,
        WorldService worldService)
    {
        _logger = logger;
        _npcManager = npcManager;
        _worldService = worldService;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var spellId = reader.ReadInt16();
        var targetType = reader.ReadByte();

        switch (targetType)
        {
            case 0: // Self
                CastOnSelf(player, spellId);
                break;

            case 1: // NPC
                var npcIndex = reader.ReadInt16();
                var npc = _npcManager.GetNpc(npcIndex);
                if (npc is not null)
                {
                    CastOnNpc(player, spellId, npc);
                }
                break;

            case 2: // Player
                var playerIndex = reader.ReadInt16();
                var target = _worldService.GetPlayer(playerIndex);
                if (target is not null)
                {
                    CastOnPlayer(player, spellId, target);
                }
                break;

            case 3: // Ground
                var x = reader.ReadInt16();
                var y = reader.ReadInt16();
                CastOnGround(player, spellId, x, y);
                break;

            case 4: // Item
                var itemSlot = reader.ReadInt16();
                CastOnItem(player, spellId, itemSlot);
                break;
        }

        await ValueTask.CompletedTask;
    }

    private void CastOnSelf(Player player, int spellId)
    {
        _logger.LogDebug("Player {Username} casting spell {SpellId} on self", player.Username, spellId);
        // Would use spell casting system
    }

    private void CastOnNpc(Player player, int spellId, Npc target)
    {
        _logger.LogDebug("Player {Username} casting spell {SpellId} on NPC {NpcId}",
            player.Username, spellId, target.NpcId);
        // Would use spell casting system
    }

    private void CastOnPlayer(Player player, int spellId, Player target)
    {
        _logger.LogDebug("Player {Username} casting spell {SpellId} on player {Target}",
            player.Username, spellId, target.Username);
        // Would check wilderness rules for combat spells
    }

    private void CastOnGround(Player player, int spellId, int x, int y)
    {
        _logger.LogDebug("Player {Username} casting spell {SpellId} at ({X}, {Y})",
            player.Username, spellId, x, y);
        // Would use spell casting system
    }

    private void CastOnItem(Player player, int spellId, int slot)
    {
        _logger.LogDebug("Player {Username} casting spell {SpellId} on item slot {Slot}",
            player.Username, spellId, slot);
        // High alchemy, enchanting, etc.
    }
}

/// <summary>
/// Handles eating food.
/// </summary>
[PacketHandler(PacketOpcode.EatFood)]
public sealed class EatFoodHandler : IPacketHandler
{
    private readonly ILogger<EatFoodHandler> _logger;

    public EatFoodHandler(ILogger<EatFoodHandler> logger)
    {
        _logger = logger;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var slot = reader.ReadInt16();
        var item = player.Inventory.GetItemAt(slot);

        if (item is null)
        {
            player.Message("Nothing to eat.");
            return;
        }

        // Would check food definitions and heal
        var healAmount = GetHealAmount(item.CatalogId);
        if (healAmount <= 0)
        {
            player.Message("You can't eat that.");
            return;
        }

        // Remove food
        player.Inventory.RemoveAt(slot);

        // Heal
        var currentHp = player.CurrentHitpoints;
        var maxHp = player.Skills.GetMaxLevel(Skills.Skill.Hits);
        player.CurrentHitpoints = Math.Min(maxHp, currentHp + healAmount);

        player.Message($"You eat the {item.Definition.Name.ToLower()}.");

        // Reset combat timer
        player.LastFoodTick = DateTime.UtcNow;

        _logger.LogDebug("Player {Username} ate food, healed {Amount}", player.Username, healAmount);

        await ValueTask.CompletedTask;
    }

    private int GetHealAmount(int itemId) => itemId switch
    {
        // Example food healing values
        138 => 4,   // Bread
        330 => 4,   // Cake
        132 => 3,   // Meat
        349 => 1,   // Anchovies
        350 => 3,   // Shrimp
        351 => 3,   // Sardine
        352 => 4,   // Salmon
        353 => 5,   // Trout
        354 => 6,   // Pike
        355 => 6,   // Herring
        356 => 7,   // Tuna
        357 => 9,   // Lobster
        358 => 11,  // Swordfish
        359 => 14,  // Shark
        370 => 22,  // Manta ray
        _ => 0
    };
}
