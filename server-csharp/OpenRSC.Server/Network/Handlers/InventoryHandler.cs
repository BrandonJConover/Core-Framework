using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.World;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles inventory-related packets (drop, use, equip, etc.).
/// </summary>
public sealed class InventoryHandler : IPacketHandler
{
    private readonly ILogger<InventoryHandler> _logger;
    private readonly WorldMap _worldMap;
    private readonly IItemDefinitionRepository _itemDefinitions;

    public int[] Opcodes => new[]
    {
        (int)OpcodeIn.DropItem,
        (int)OpcodeIn.UseItem,
        (int)OpcodeIn.UnequipItem,
        (int)OpcodeIn.WieldItem
    };

    public InventoryHandler(
        ILogger<InventoryHandler> logger,
        WorldMap worldMap,
        IItemDefinitionRepository itemDefinitions)
    {
        _logger = logger;
        _worldMap = worldMap;
        _itemDefinitions = itemDefinitions;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        switch ((OpcodeIn)packet.Opcode)
        {
            case OpcodeIn.DropItem:
                HandleDrop(player, packet);
                break;
            case OpcodeIn.UseItem:
                HandleUse(player, packet);
                break;
            case OpcodeIn.UnequipItem:
                HandleUnequip(player, packet);
                break;
            case OpcodeIn.WieldItem:
                HandleWield(player, packet);
                break;
        }

        await Task.CompletedTask;
    }

    private void HandleDrop(Player player, Packet packet)
    {
        var slot = packet.ReadShort();

        // Validate slot
        if (slot < 0 || slot >= 30)
        {
            _logger.LogWarning("{Username} tried to drop from invalid slot {Slot}",
                player.Username, slot);
            return;
        }

        // Get item from inventory
        var items = player.Inventory.GetItems().ToList();
        if (slot >= items.Count)
        {
            player.Message("Nothing to drop.");
            return;
        }

        var item = items[slot];
        var definition = _itemDefinitions.GetById(item.CatalogId);

        if (definition is null)
        {
            _logger.LogWarning("{Username} tried to drop unknown item {ItemId}",
                player.Username, item.CatalogId);
            return;
        }

        // Check if item is tradeable (can be dropped)
        if (!definition.IsTradeable)
        {
            player.Message("You can't drop that item.");
            return;
        }

        // Remove from inventory
        if (!player.Inventory.Remove(item.CatalogId, item.Amount))
        {
            player.Message("Failed to drop item.");
            return;
        }

        // Drop on ground
        _worldMap.DropItem(item.CatalogId, item.Amount, player.Location, player);

        // Send inventory update
        player.SendInventory();

        _logger.LogDebug("{Username} dropped {Amount}x {ItemName}",
            player.Username, item.Amount, definition.Name);
    }

    private void HandleUse(Player player, Packet packet)
    {
        var slot = packet.ReadShort();

        // Validate slot
        if (slot < 0 || slot >= 30)
        {
            return;
        }

        var items = player.Inventory.GetItems().ToList();
        if (slot >= items.Count)
        {
            return;
        }

        var item = items[slot];
        var definition = _itemDefinitions.GetById(item.CatalogId);

        if (definition is null)
        {
            return;
        }

        _logger.LogDebug("{Username} using {ItemName}", player.Username, definition.Name);

        // Handle item use based on type
        if (definition.IsEdible)
        {
            HandleEat(player, item, definition);
        }
        else if (definition.EquipmentSlot.HasValue)
        {
            // Wield/wear the item
            HandleWieldItem(player, item);
        }
        else
        {
            player.Message($"You can't use that right now.");
        }
    }

    private void HandleEat(Player player, Item item, ItemDefinition definition)
    {
        // Check combat delay
        var now = DateTime.UtcNow;
        if ((now - player.LastFoodTick).TotalMilliseconds < 1200)
        {
            return; // Still on cooldown
        }

        player.LastFoodTick = now;

        // Heal the player
        var healAmount = definition.HealAmount ?? 0;
        var currentHp = player.Skills.GetCurrentLevel(Skills.Skill.Hits);
        var maxHp = player.Skills.GetMaxLevel(Skills.Skill.Hits);

        if (currentHp >= maxHp)
        {
            player.Message("You don't need to eat that right now.");
            return;
        }

        var newHp = Math.Min(currentHp + healAmount, maxHp);
        player.Skills.SetCurrentLevel(Skills.Skill.Hits, newHp);
        player.CurrentHitpoints = newHp;

        // Remove food from inventory
        player.Inventory.Remove(item.CatalogId, 1);

        player.Message($"You eat the {definition.Name}.");
        player.SendInventory();

        // Send stat update
        _ = player.ActionSender?.SendStatUpdateAsync(Skills.Skill.Hits);

        _logger.LogDebug("{Username} ate {ItemName}, healed {Amount} HP",
            player.Username, definition.Name, healAmount);
    }

    private void HandleUnequip(Player player, Packet packet)
    {
        var slotIndex = packet.ReadByte();

        if (!Enum.IsDefined(typeof(Inventory.EquipmentSlot), (int)slotIndex))
        {
            return;
        }

        var slot = (Inventory.EquipmentSlot)slotIndex;
        var result = player.Equipment.Unequip(slot, player.Inventory);

        if (!result.Success)
        {
            player.Message(result.Message ?? "Unable to unequip.");
            return;
        }

        player.SendInventory();
        player.SendEquipmentBonuses();

        _logger.LogDebug("{Username} unequipped from slot {Slot}",
            player.Username, slot);
    }

    private void HandleWield(Player player, Packet packet)
    {
        var slot = packet.ReadShort();

        if (slot < 0 || slot >= 30)
        {
            return;
        }

        var items = player.Inventory.GetItems().ToList();
        if (slot >= items.Count)
        {
            return;
        }

        var item = items[slot];
        HandleWieldItem(player, item);
    }

    private void HandleWieldItem(Player player, Item item)
    {
        var definition = item.Definition;
        if (definition?.EquipmentSlot is null)
        {
            player.Message("You can't wield that.");
            return;
        }

        // Remove from inventory first
        player.Inventory.Remove(item.CatalogId, 1);

        // Try to equip
        var result = player.Equipment.Equip(item, player.Inventory);

        if (!result.Success)
        {
            // Put back in inventory
            player.Inventory.Add(item);
            player.Message(result.Message ?? "Unable to equip.");
            return;
        }

        // If there was a previously equipped item, it's already in inventory via the Equip method
        player.SendInventory();
        player.SendEquipmentBonuses();

        _logger.LogDebug("{Username} equipped {ItemName}",
            player.Username, definition.Name);
    }
}
