using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;
using OpenRSC.Server.World;

namespace OpenRSC.Server.Death;

/// <summary>
/// Manages player death, item drops, and respawning.
/// </summary>
public sealed class DeathManager
{
    private readonly WorldMap _worldMap;
    private readonly Point _defaultRespawn = new(122, 648); // Lumbridge

    public DeathManager(WorldMap worldMap)
    {
        _worldMap = worldMap;
    }

    /// <summary>
    /// Handles player death.
    /// </summary>
    public DeathResult ProcessDeath(Player player, Mob? killer = null)
    {
        if (player.CurrentHitpoints > 0)
            return DeathResult.NotDead;

        // Calculate items to keep
        var itemsKept = player.Prayers.ItemsKeptOnDeath;

        // Get all items (inventory + equipment)
        var allItems = GetAllItems(player).ToList();

        // Sort by value to determine what to keep
        var sortedItems = allItems
            .OrderByDescending(i => i.Item.Definition.BasePrice * i.Item.Amount)
            .ToList();

        var keptItems = sortedItems.Take(itemsKept).ToList();
        var droppedItems = sortedItems.Skip(itemsKept).ToList();

        // Clear player inventory and equipment
        ClearPlayerItems(player);

        // Return kept items to inventory
        foreach (var kept in keptItems)
        {
            player.Inventory.Add(kept.Item);
        }

        // Drop items on ground
        var dropLocation = player.Location;
        foreach (var dropped in droppedItems)
        {
            var visibility = killer is Player killerPlayer
                ? killerPlayer
                : null;

            _worldMap.DropItem(
                dropped.Item.CatalogId,
                dropped.Item.Amount,
                dropLocation,
                visibility);
        }

        // Drop bones
        DropBones(dropLocation, killer as Player);

        // Reset player state
        ResetPlayer(player);

        // Teleport to respawn point
        var respawnPoint = GetRespawnPoint(player);
        player.Teleport(respawnPoint);

        // Send death packets to client
        SendDeathPackets(player, respawnPoint);

        player.Message("Oh dear, you are dead!");

        return new DeathResult(
            true,
            keptItems.Select(i => i.Item).ToList(),
            droppedItems.Select(i => i.Item).ToList(),
            respawnPoint);
    }

    private IEnumerable<(Item Item, ItemSource Source)> GetAllItems(Player player)
    {
        // Get inventory items
        foreach (var item in player.Inventory.GetItems())
        {
            yield return (item, ItemSource.Inventory);
        }

        // Get equipped items
        foreach (var (_, item) in player.Equipment.GetEquipped())
        {
            yield return (item, ItemSource.Equipment);
        }
    }

    private void ClearPlayerItems(Player player)
    {
        // Clear inventory
        for (var i = 0; i < 30; i++)
        {
            player.Inventory.Remove(i);
        }

        // Clear equipment
        player.Equipment.ClearAll();
    }

    private void DropBones(Point location, Player? killer)
    {
        const int bonesId = 20;
        _worldMap.DropItem(bonesId, 1, location, killer);
    }

    private void ResetPlayer(Player player)
    {
        // Restore hitpoints
        player.CurrentHitpoints = player.Skills.GetMaxLevel(Skills.Skill.Hits);

        // Clear combat
        player.EndCombat();

        // Deactivate prayers
        player.Prayers.DeactivateAll();
        player.Prayers.RestoreFully();

        // Clear skull
        player.IsSkulled = false;
        player.SkullExpiry = null;

        // Reset stats to normal
        foreach (Skills.Skill skill in Enum.GetValues<Skills.Skill>())
        {
            player.Skills.RestoreToMax(skill);
        }

        // Clear walking queue and current action
        player.WalkingQueue.Reset();
        player.CurrentAction = null;
        player.SetWalkToAction(null);
    }

    /// <summary>
    /// Sends death-related packets to the client.
    /// </summary>
    private void SendDeathPackets(Player player, Point respawnPoint)
    {
        // Send death notification
        _ = player.ActionSender?.SendDeathAsync();

        // Send teleport to respawn point
        _ = player.ActionSender?.SendTeleportAsync();

        // Send updated stats
        player.SendStats();

        // Send updated inventory
        player.SendInventory();

        // Send equipment bonuses
        player.SendEquipmentBonuses();
    }

    private Point GetRespawnPoint(Player player)
    {
        // Could check for special respawn points (Camelot, etc.)
        return _defaultRespawn;
    }

    /// <summary>
    /// Handles NPC death.
    /// </summary>
    public void ProcessNpcDeath(Npc npc, Player? killer)
    {
        if (npc.CurrentHitpoints > 0)
            return;

        var dropLocation = npc.Location;

        // Drop loot
        if (npc.Definition?.Drops is { } drops)
        {
            foreach (var drop in drops)
            {
                if (drop.Roll())
                {
                    var amount = drop.GetAmount();
                    _worldMap.DropItem(drop.ItemId, amount, dropLocation, killer);
                }
            }
        }

        // Always drop bones for attackable NPCs
        if (npc.IsAttackable)
        {
            DropBones(dropLocation, killer);
        }

        // Mark NPC as dead
        npc.Die();

        // Grant combat XP to killer
        if (killer is not null)
        {
            GrantCombatXp(killer, npc);
        }
    }

    private void GrantCombatXp(Player player, Npc npc)
    {
        // Base XP is related to NPC's max hitpoints
        var baseXp = npc.Definition?.Hitpoints ?? npc.MaxHitpoints;
        var combatXp = baseXp * 4;

        // Distribute based on combat style
        // Simplified - real implementation would track damage dealt
        var hitpointsXp = combatXp / 3;

        player.Skills.AddExperience(Skills.Skill.Hits, hitpointsXp);

        // Rest to primary combat skill (would depend on style)
        player.Skills.AddExperience(Skills.Skill.Attack, combatXp / 4);
        player.Skills.AddExperience(Skills.Skill.Strength, combatXp / 4);
        player.Skills.AddExperience(Skills.Skill.Defense, combatXp / 4);
    }
}

/// <summary>
/// Source of an item.
/// </summary>
public enum ItemSource
{
    Inventory,
    Equipment
}

/// <summary>
/// Result of processing death.
/// </summary>
public readonly record struct DeathResult(
    bool Died,
    IReadOnlyList<Item>? KeptItems = null,
    IReadOnlyList<Item>? DroppedItems = null,
    Point? RespawnLocation = null)
{
    public static readonly DeathResult NotDead = new(false);
}
