using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;

namespace OpenRSC.Server.Inventory;

/// <summary>
/// Manages a player's inventory with RSC-specific constraints.
/// </summary>
public sealed class PlayerInventory
{
    private const int MaxSlots = 30;

    private readonly Player _player;
    private readonly Container _container;

    /// <summary>
    /// Gets the underlying container.
    /// </summary>
    public Container Container => _container;

    /// <summary>
    /// Number of free slots.
    /// </summary>
    public int FreeSlots => _container.FreeSlots;

    /// <summary>
    /// Whether the inventory is full.
    /// </summary>
    public bool IsFull => _container.FreeSlots == 0;

    public PlayerInventory(Player player)
    {
        _player = player;
        _container = new Container(MaxSlots);
        _container.ContentsChanged += OnContentsChanged;
    }

    /// <summary>
    /// Attempts to add an item to the inventory.
    /// </summary>
    public bool Add(Item item)
    {
        var result = _container.Add(item);
        if (!result)
        {
            _player.Message("You don't have room for that in your inventory.");
        }
        return result;
    }

    /// <summary>
    /// Attempts to add an item by catalog ID.
    /// </summary>
    public bool Add(int catalogId, int amount, IItemFactory itemFactory)
    {
        var item = itemFactory.TryCreate(catalogId, amount);
        if (item is null)
            return false;
        return Add(item);
    }

    /// <summary>
    /// Removes an item from a specific slot.
    /// </summary>
    public Item? Remove(int slot) => _container.Remove(slot);

    /// <summary>
    /// Removes a specific amount of an item by catalog ID.
    /// </summary>
    public bool Remove(int catalogId, int amount)
    {
        return _container.Remove(catalogId, amount);
    }

    /// <summary>
    /// Gets the item at a slot.
    /// </summary>
    public Item? GetSlot(int slot) => _container.GetSlot(slot);

    /// <summary>
    /// Checks if the player has an item.
    /// </summary>
    public bool HasItem(int catalogId, int amount = 1)
    {
        return _container.Contains(catalogId, amount);
    }

    /// <summary>
    /// Gets the count of a specific item.
    /// </summary>
    public int CountOf(int catalogId) => _container.CountOf(catalogId);

    /// <summary>
    /// Swaps two inventory slots.
    /// </summary>
    public void Swap(int slotA, int slotB)
    {
        _container.Swap(slotA, slotB);
    }

    /// <summary>
    /// Gets all items in the inventory.
    /// </summary>
    public IEnumerable<Item> GetItems() => _container.GetItems();

    /// <summary>
    /// Finds the first slot containing a specific item.
    /// </summary>
    public int? FindSlot(int catalogId)
    {
        for (var i = 0; i < MaxSlots; i++)
        {
            if (_container.GetSlot(i)?.CatalogId == catalogId)
                return i;
        }
        return null;
    }

    /// <summary>
    /// Checks if there's space for an item (considering stacking).
    /// </summary>
    public bool HasSpaceFor(int catalogId, int amount, IItemFactory itemFactory)
    {
        var definition = itemFactory.GetDefinition(catalogId);
        if (definition is null)
            return false;

        if (definition.IsStackable)
        {
            // Stackable items can fit if we have the item or have space
            return HasItem(catalogId) || !IsFull;
        }

        // Non-stackable needs enough slots
        return FreeSlots >= amount;
    }

    private void OnContentsChanged(ContainerChangedEventArgs args)
    {
        // TODO: Send inventory update packets to client
        // Inventory change tracking handled by event system
    }
}

/// <summary>
/// Manages a player's bank storage.
/// </summary>
public sealed class PlayerBank
{
    private const int MaxSlots = 192;

    private readonly Player _player;
    private readonly Container _container;

    public Container Container => _container;
    public int UsedSlots => _container.UsedSlots;
    public int FreeSlots => _container.FreeSlots;

    public PlayerBank(Player player)
    {
        _player = player;
        _container = new Container(MaxSlots, allowStacking: true);
    }

    /// <summary>
    /// Deposits an item from inventory to bank.
    /// </summary>
    public bool Deposit(Item item)
    {
        var result = _container.Add(item);
        if (!result)
        {
            _player.Message("Your bank is full.");
        }
        return result;
    }

    /// <summary>
    /// Withdraws an item from bank to inventory.
    /// </summary>
    public Item? Withdraw(int slot, int amount, PlayerInventory inventory)
    {
        var item = _container.GetSlot(slot);
        if (item is null)
            return null;

        if (!inventory.HasSpaceFor(item.CatalogId, amount, null!)) // TODO: Pass item factory
        {
            _player.Message("You don't have room in your inventory.");
            return null;
        }

        if (item.Amount <= amount)
        {
            return _container.Remove(slot);
        }

        // Partial withdrawal
        item.RemoveFromStack(amount);
        return new Item(item.Definition, amount);
    }

    /// <summary>
    /// Gets the item at a slot.
    /// </summary>
    public Item? GetSlot(int slot) => _container.GetSlot(slot);

    /// <summary>
    /// Checks if the bank contains an item.
    /// </summary>
    public bool HasItem(int catalogId, int amount = 1) => _container.Contains(catalogId, amount);

    /// <summary>
    /// Gets all banked items.
    /// </summary>
    public IEnumerable<Item> GetItems() => _container.GetItems();
}
