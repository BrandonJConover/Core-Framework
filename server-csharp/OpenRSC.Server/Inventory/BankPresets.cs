using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;

namespace OpenRSC.Server.Inventory;

/// <summary>
/// A saved bank preset configuration.
/// </summary>
public sealed class BankPreset
{
    public int PresetId { get; init; }
    public string Name { get; set; }
    public List<PresetItem> InventoryItems { get; } = new();
    public List<PresetEquipment> EquipmentItems { get; } = new();

    public BankPreset(int presetId, string name = "")
    {
        PresetId = presetId;
        Name = string.IsNullOrEmpty(name) ? $"Preset {presetId + 1}" : name;
    }

    /// <summary>
    /// Clears the preset.
    /// </summary>
    public void Clear()
    {
        InventoryItems.Clear();
        EquipmentItems.Clear();
    }
}

/// <summary>
/// An item in a preset.
/// </summary>
public sealed record PresetItem
{
    public required int ItemId { get; init; }
    public required int Amount { get; init; }
    public int? Slot { get; init; } // Specific inventory slot, or null for any
}

/// <summary>
/// Equipment item in a preset.
/// </summary>
public sealed record PresetEquipment
{
    public required int ItemId { get; init; }
    public required EquipmentSlot Slot { get; init; }
}

/// <summary>
/// Result of a preset operation.
/// </summary>
public readonly record struct PresetResult(bool Success, string? Message = null)
{
    public static PresetResult Fail(string message) => new(false, message);
    public static readonly PresetResult Ok = new(true);
}

/// <summary>
/// Manages bank presets for a player.
/// </summary>
public sealed class BankPresetManager
{
    private readonly Player _player;
    private readonly List<BankPreset> _presets = new();

    public const int MaxPresets = 10;

    public IReadOnlyList<BankPreset> Presets => _presets;

    public BankPresetManager(Player player)
    {
        _player = player;

        // Initialize empty presets
        for (var i = 0; i < MaxPresets; i++)
        {
            _presets.Add(new BankPreset(i));
        }
    }

    /// <summary>
    /// Gets a preset by index.
    /// </summary>
    public BankPreset? GetPreset(int index)
    {
        if (index < 0 || index >= _presets.Count)
            return null;

        return _presets[index];
    }

    /// <summary>
    /// Saves current inventory and equipment to a preset.
    /// </summary>
    public PresetResult SavePreset(int presetIndex, string? name = null)
    {
        var preset = GetPreset(presetIndex);
        if (preset is null)
            return PresetResult.Fail("Invalid preset slot.");

        preset.Clear();

        if (name is not null)
            preset.Name = name;

        // Save inventory
        var slot = 0;
        foreach (var item in _player.Inventory.GetItems())
        {
            preset.InventoryItems.Add(new PresetItem
            {
                ItemId = item.CatalogId,
                Amount = item.Amount,
                Slot = slot++
            });
        }

        // Save equipment
        foreach (var (equipSlot, item) in _player.Equipment.GetEquipped())
        {
            preset.EquipmentItems.Add(new PresetEquipment
            {
                ItemId = item.CatalogId,
                Slot = equipSlot
            });
        }

        _player.Message($"Preset '{preset.Name}' saved.");
        return PresetResult.Ok;
    }

    /// <summary>
    /// Loads a preset from bank.
    /// </summary>
    public PresetResult LoadPreset(int presetIndex, IItemFactory itemFactory)
    {
        var preset = GetPreset(presetIndex);
        if (preset is null)
            return PresetResult.Fail("Invalid preset slot.");

        if (preset.InventoryItems.Count == 0 && preset.EquipmentItems.Count == 0)
            return PresetResult.Fail("This preset is empty.");

        // Check if all items are available in bank
        var missingItems = new List<string>();

        foreach (var presetItem in preset.InventoryItems)
        {
            if (!_player.Bank.HasItem(presetItem.ItemId, presetItem.Amount))
            {
                missingItems.Add($"{presetItem.ItemId} x{presetItem.Amount}");
            }
        }

        foreach (var presetEquip in preset.EquipmentItems)
        {
            if (!_player.Bank.HasItem(presetEquip.ItemId))
            {
                missingItems.Add($"{presetEquip.ItemId}");
            }
        }

        if (missingItems.Count > 0)
        {
            return PresetResult.Fail("Some items are missing from your bank.");
        }

        // Deposit current inventory and equipment to bank
        DepositAll(itemFactory);

        // Withdraw preset items
        foreach (var presetItem in preset.InventoryItems)
        {
            var item = _player.Bank.WithdrawByItemId(presetItem.ItemId, presetItem.Amount, _player.Inventory);
            if (item is not null)
            {
                _player.Inventory.Add(item);
            }
        }

        // Withdraw and equip preset equipment
        foreach (var presetEquip in preset.EquipmentItems)
        {
            var item = _player.Bank.WithdrawByItemId(presetEquip.ItemId, 1, _player.Inventory);
            if (item is not null)
            {
                _player.Equipment.Equip(item, _player.Inventory);
            }
        }

        _player.Message($"Loaded preset '{preset.Name}'.");
        return PresetResult.Ok;
    }

    /// <summary>
    /// Deposits all inventory and equipment to bank.
    /// </summary>
    private void DepositAll(IItemFactory itemFactory)
    {
        // Deposit equipment first
        foreach (var slot in Enum.GetValues<EquipmentSlot>())
        {
            var item = _player.Equipment.Unequip(slot, _player.Inventory);
            if (item is not null)
            {
                _player.Bank.Deposit(item);
            }
        }

        // Deposit inventory
        var items = _player.Inventory.GetItems().ToList();
        foreach (var item in items)
        {
            _player.Inventory.Remove(item.CatalogId, item.Amount);
            _player.Bank.Deposit(item);
        }
    }

    /// <summary>
    /// Renames a preset.
    /// </summary>
    public PresetResult RenamePreset(int presetIndex, string newName)
    {
        var preset = GetPreset(presetIndex);
        if (preset is null)
            return PresetResult.Fail("Invalid preset slot.");

        if (string.IsNullOrWhiteSpace(newName))
            return PresetResult.Fail("Name cannot be empty.");

        if (newName.Length > 20)
            return PresetResult.Fail("Name is too long (max 20 characters).");

        preset.Name = newName;
        _player.Message($"Preset renamed to '{newName}'.");

        return PresetResult.Ok;
    }

    /// <summary>
    /// Clears a preset.
    /// </summary>
    public PresetResult ClearPreset(int presetIndex)
    {
        var preset = GetPreset(presetIndex);
        if (preset is null)
            return PresetResult.Fail("Invalid preset slot.");

        preset.Clear();
        preset.Name = $"Preset {presetIndex + 1}";

        _player.Message("Preset cleared.");
        return PresetResult.Ok;
    }

    /// <summary>
    /// Loads preset data (for persistence).
    /// </summary>
    public void LoadData(IEnumerable<BankPreset> presets)
    {
        foreach (var preset in presets)
        {
            if (preset.PresetId >= 0 && preset.PresetId < MaxPresets)
            {
                _presets[preset.PresetId] = preset;
            }
        }
    }

    /// <summary>
    /// Gets all presets for saving.
    /// </summary>
    public IEnumerable<BankPreset> GetAllPresets()
    {
        return _presets.Where(p => p.InventoryItems.Count > 0 || p.EquipmentItems.Count > 0);
    }
}

/// <summary>
/// Quick-deposit options.
/// </summary>
public static class BankQuickDeposit
{
    /// <summary>
    /// Deposits all inventory items.
    /// </summary>
    public static int DepositInventory(Player player)
    {
        var deposited = 0;
        var items = player.Inventory.GetItems().ToList();

        foreach (var item in items)
        {
            player.Inventory.Remove(item.CatalogId, item.Amount);
            player.Bank.Deposit(item);
            deposited++;
        }

        return deposited;
    }

    /// <summary>
    /// Deposits all equipment.
    /// </summary>
    public static int DepositEquipment(Player player)
    {
        var deposited = 0;

        foreach (var slot in Enum.GetValues<EquipmentSlot>())
        {
            var item = player.Equipment.Unequip(slot, player.Inventory);
            if (item is not null)
            {
                player.Bank.Deposit(item);
                deposited++;
            }
        }

        return deposited;
    }

    /// <summary>
    /// Deposits all loot (items obtained since last bank visit).
    /// Would need tracking mechanism.
    /// </summary>
    public static int DepositLoot(Player player, HashSet<int> lootItemIds)
    {
        var deposited = 0;
        var items = player.Inventory.GetItems().ToList();

        foreach (var item in items)
        {
            if (lootItemIds.Contains(item.CatalogId))
            {
                player.Inventory.Remove(item.CatalogId, item.Amount);
                player.Bank.Deposit(item);
                deposited++;
            }
        }

        return deposited;
    }
}
