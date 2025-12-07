using OpenRSC.Server.Items;

namespace OpenRSC.Server.Inventory;

/// <summary>
/// Result of an inventory operation.
/// </summary>
public readonly record struct ContainerResult(bool Success, string? Message = null)
{
    public static readonly ContainerResult Ok = new(true);
    public static ContainerResult Fail(string message) => new(false, message);

    public static implicit operator bool(ContainerResult result) => result.Success;
}

/// <summary>
/// Generic container for items (inventory, bank, shop, etc.).
/// </summary>
public class Container
{
    private readonly Item?[] _slots;
    private readonly bool _allowStacking;

    /// <summary>
    /// Maximum number of slots in this container.
    /// </summary>
    public int Capacity => _slots.Length;

    /// <summary>
    /// Number of slots currently in use.
    /// </summary>
    public int UsedSlots => _slots.Count(s => s is not null);

    /// <summary>
    /// Number of empty slots.
    /// </summary>
    public int FreeSlots => Capacity - UsedSlots;

    /// <summary>
    /// Event raised when the container contents change.
    /// </summary>
    public event Action<ContainerChangedEventArgs>? ContentsChanged;

    public Container(int capacity, bool allowStacking = true)
    {
        if (capacity <= 0)
            throw new ArgumentOutOfRangeException(nameof(capacity));

        _slots = new Item?[capacity];
        _allowStacking = allowStacking;
    }

    /// <summary>
    /// Gets the item at a specific slot.
    /// </summary>
    public Item? GetSlot(int slot)
    {
        if (slot < 0 || slot >= Capacity)
            return null;
        return _slots[slot];
    }

    /// <summary>
    /// Gets all items in the container.
    /// </summary>
    public IEnumerable<Item> GetItems() => _slots.Where(s => s is not null)!;

    /// <summary>
    /// Gets all items with their slot indices.
    /// </summary>
    public IEnumerable<(int Slot, Item Item)> GetItemsWithSlots()
    {
        for (var i = 0; i < Capacity; i++)
        {
            if (_slots[i] is { } item)
                yield return (i, item);
        }
    }

    /// <summary>
    /// Adds an item to the container.
    /// </summary>
    public ContainerResult Add(Item item)
    {
        if (item is null)
            return ContainerResult.Fail("Invalid item");

        // Try to stack with existing items first
        if (_allowStacking && item.Definition.IsStackable)
        {
            for (var i = 0; i < Capacity; i++)
            {
                if (_slots[i]?.CatalogId == item.CatalogId)
                {
                    var overflow = _slots[i]!.AddToStack(item.Amount);
                    if (overflow == 0)
                    {
                        OnContentsChanged(i, ContainerChangeType.Updated);
                        return ContainerResult.Ok;
                    }
                    // Partial stack, continue to add rest
                    item.SetAmount(overflow);
                    OnContentsChanged(i, ContainerChangeType.Updated);
                }
            }
        }

        // Find empty slot
        var emptySlot = Array.IndexOf(_slots, null);
        if (emptySlot < 0)
            return ContainerResult.Fail("Not enough space");

        _slots[emptySlot] = item;
        OnContentsChanged(emptySlot, ContainerChangeType.Added);
        return ContainerResult.Ok;
    }

    /// <summary>
    /// Adds an item to a specific slot.
    /// </summary>
    public ContainerResult AddToSlot(int slot, Item item)
    {
        if (slot < 0 || slot >= Capacity)
            return ContainerResult.Fail("Invalid slot");

        if (_slots[slot] is not null)
            return ContainerResult.Fail("Slot is not empty");

        _slots[slot] = item;
        OnContentsChanged(slot, ContainerChangeType.Added);
        return ContainerResult.Ok;
    }

    /// <summary>
    /// Removes an item from a specific slot.
    /// </summary>
    public Item? Remove(int slot)
    {
        if (slot < 0 || slot >= Capacity)
            return null;

        var item = _slots[slot];
        if (item is null)
            return null;

        _slots[slot] = null;
        OnContentsChanged(slot, ContainerChangeType.Removed);
        return item;
    }

    /// <summary>
    /// Removes a specific amount of an item by catalog ID.
    /// </summary>
    public ContainerResult Remove(int catalogId, int amount)
    {
        if (amount <= 0)
            return ContainerResult.Fail("Invalid amount");

        var remaining = amount;

        for (var i = Capacity - 1; i >= 0 && remaining > 0; i--)
        {
            if (_slots[i]?.CatalogId != catalogId)
                continue;

            var item = _slots[i]!;
            if (item.Amount <= remaining)
            {
                remaining -= item.Amount;
                _slots[i] = null;
                OnContentsChanged(i, ContainerChangeType.Removed);
            }
            else
            {
                item.RemoveFromStack(remaining);
                remaining = 0;
                OnContentsChanged(i, ContainerChangeType.Updated);
            }
        }

        return remaining == 0
            ? ContainerResult.Ok
            : ContainerResult.Fail($"Only removed {amount - remaining} of {amount}");
    }

    /// <summary>
    /// Checks if the container has a specific amount of an item.
    /// </summary>
    public bool Contains(int catalogId, int amount = 1)
    {
        var total = 0;
        foreach (var item in _slots)
        {
            if (item?.CatalogId == catalogId)
            {
                total += item.Amount;
                if (total >= amount)
                    return true;
            }
        }
        return false;
    }

    /// <summary>
    /// Gets the total amount of a specific item.
    /// </summary>
    public int CountOf(int catalogId)
    {
        return _slots.Where(s => s?.CatalogId == catalogId).Sum(s => s!.Amount);
    }

    /// <summary>
    /// Swaps items between two slots.
    /// </summary>
    public ContainerResult Swap(int slotA, int slotB)
    {
        if (slotA < 0 || slotA >= Capacity || slotB < 0 || slotB >= Capacity)
            return ContainerResult.Fail("Invalid slot");

        (_slots[slotA], _slots[slotB]) = (_slots[slotB], _slots[slotA]);
        OnContentsChanged(slotA, ContainerChangeType.Swapped);
        OnContentsChanged(slotB, ContainerChangeType.Swapped);
        return ContainerResult.Ok;
    }

    /// <summary>
    /// Clears all items from the container.
    /// </summary>
    public void Clear()
    {
        Array.Clear(_slots);
        OnContentsChanged(-1, ContainerChangeType.Cleared);
    }

    /// <summary>
    /// Shifts items to remove gaps.
    /// </summary>
    public void Compact()
    {
        var items = _slots.Where(s => s is not null).ToArray();
        Array.Clear(_slots);

        for (var i = 0; i < items.Length; i++)
        {
            _slots[i] = items[i];
        }

        OnContentsChanged(-1, ContainerChangeType.Compacted);
    }

    protected virtual void OnContentsChanged(int slot, ContainerChangeType changeType)
    {
        ContentsChanged?.Invoke(new ContainerChangedEventArgs(this, slot, changeType));
    }
}

/// <summary>
/// Type of container change.
/// </summary>
public enum ContainerChangeType
{
    Added,
    Removed,
    Updated,
    Swapped,
    Cleared,
    Compacted
}

/// <summary>
/// Event args for container changes.
/// </summary>
public sealed class ContainerChangedEventArgs : EventArgs
{
    public Container Container { get; }
    public int Slot { get; }
    public ContainerChangeType ChangeType { get; }

    public ContainerChangedEventArgs(Container container, int slot, ContainerChangeType changeType)
    {
        Container = container;
        Slot = slot;
        ChangeType = changeType;
    }
}
