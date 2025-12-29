using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Inventory;

/// <summary>
/// Manages a player's equipped items.
/// </summary>
public sealed class Equipment
{
    private readonly Player _player;
    private readonly Dictionary<EquipmentSlot, Item> _equipped = new();

    /// <summary>
    /// Event raised when equipment changes.
    /// </summary>
    public event Action<EquipmentSlot, Item?, Item?>? EquipmentChanged;

    public Equipment(Player player)
    {
        _player = player;
    }

    /// <summary>
    /// Gets the item in a specific slot.
    /// </summary>
    public Item? GetSlot(EquipmentSlot slot)
    {
        return _equipped.TryGetValue(slot, out var item) ? item : null;
    }

    /// <summary>
    /// Gets all equipped items.
    /// </summary>
    public IEnumerable<(EquipmentSlot Slot, Item Item)> GetEquipped()
    {
        return _equipped.Select(kv => (kv.Key, kv.Value));
    }

    /// <summary>
    /// Equips an item from the inventory.
    /// </summary>
    public EquipResult Equip(Item item, PlayerInventory inventory)
    {
        if (item.Definition.EquipmentSlot is not { } slot)
            return EquipResult.Fail("This item cannot be equipped.");

        // Check requirements
        var requirementCheck = CheckRequirements(item.Definition);
        if (!requirementCheck.Success)
            return requirementCheck;

        // Get currently equipped item in that slot
        var previousItem = GetSlot(slot);

        // Equip the new item
        _equipped[slot] = item;

        // Raise event
        EquipmentChanged?.Invoke(slot, previousItem, item);

        // Update appearance/stats
        UpdateCombatBonuses();

        _player.Message($"You equip the {item.Definition.Name}.");

        return new EquipResult(true, UnequippedItem: previousItem);
    }

    /// <summary>
    /// Unequips an item from a slot.
    /// </summary>
    public EquipResult Unequip(EquipmentSlot slot, PlayerInventory inventory)
    {
        if (!_equipped.TryGetValue(slot, out var item))
            return EquipResult.Fail("Nothing equipped in that slot.");

        if (inventory.IsFull)
            return EquipResult.Fail("You don't have room in your inventory.");

        _equipped.Remove(slot);

        // Add to inventory
        inventory.Add(item);

        // Raise event
        EquipmentChanged?.Invoke(slot, item, null);

        // Update appearance/stats
        UpdateCombatBonuses();

        _player.Message($"You unequip the {item.Definition.Name}.");

        return new EquipResult(true);
    }

    /// <summary>
    /// Checks if the player meets requirements to equip an item.
    /// </summary>
    private EquipResult CheckRequirements(ItemDefinition definition)
    {
        foreach (var (skill, requiredLevel) in definition.Requirements)
        {
            var currentLevel = _player.Skills.GetMaxLevel(skill);
            if (currentLevel < requiredLevel)
            {
                return EquipResult.Fail(
                    $"You need {requiredLevel} {skill.GetDisplayName()} to equip this.");
            }
        }
        return new EquipResult(true);
    }

    /// <summary>
    /// Gets the total equipment bonuses.
    /// </summary>
    public EquipmentStats GetTotalBonuses()
    {
        var total = EquipmentStats.None;

        foreach (var item in _equipped.Values)
        {
            if (item.Definition.EquipmentStats is { } stats)
            {
                total += stats;
            }
        }

        return total;
    }

    /// <summary>
    /// Gets the weapon's attack style (for combat calculations).
    /// </summary>
    public AttackStyle GetWeaponStyle()
    {
        var weapon = GetSlot(EquipmentSlot.WeaponRight);
        if (weapon is null)
            return AttackStyle.Crush; // Unarmed is crush

        // Determine based on weapon type
        // This would typically come from weapon definitions
        return weapon.Definition.Name.ToLowerInvariant() switch
        {
            var n when n.Contains("sword") => AttackStyle.Slash,
            var n when n.Contains("dagger") => AttackStyle.Stab,
            var n when n.Contains("mace") => AttackStyle.Crush,
            var n when n.Contains("staff") => AttackStyle.Magic,
            var n when n.Contains("bow") => AttackStyle.Ranged,
            _ => AttackStyle.Slash
        };
    }

    /// <summary>
    /// Checks if a specific item is equipped.
    /// </summary>
    public bool HasEquipped(int catalogId)
    {
        return _equipped.Values.Any(i => i.CatalogId == catalogId);
    }

    /// <summary>
    /// Checks if any item is equipped in a slot.
    /// </summary>
    public bool HasItemInSlot(EquipmentSlot slot)
    {
        return _equipped.ContainsKey(slot);
    }

    private void UpdateCombatBonuses()
    {
        // TODO: Notify client of stat changes via ActionSender
        // Combat bonuses are recalculated when needed by GetTotalBonuses()
    }

    /// <summary>
    /// Clears all equipment (used on death).
    /// </summary>
    public IEnumerable<Item> ClearAll()
    {
        var items = _equipped.Values.ToList();
        _equipped.Clear();

        foreach (var slot in Enum.GetValues<EquipmentSlot>())
        {
            EquipmentChanged?.Invoke(slot, null, null);
        }

        UpdateCombatBonuses();

        return items;
    }
}

/// <summary>
/// Result of an equip/unequip operation.
/// </summary>
public readonly record struct EquipResult(
    bool Success,
    string? Message = null,
    Item? UnequippedItem = null)
{
    public static EquipResult Fail(string message) => new(false, message);

    public static implicit operator bool(EquipResult result) => result.Success;
}
