namespace OpenRSC.Server.Items;

/// <summary>
/// Represents an item instance in the game world or inventory.
/// </summary>
public sealed class Item : IEquatable<Item>
{
    /// <summary>
    /// The item definition/template.
    /// </summary>
    public ItemDefinition Definition { get; }

    /// <summary>
    /// Item catalog ID.
    /// </summary>
    public int CatalogId => Definition.Id;

    /// <summary>
    /// Stack amount for stackable items, or 1 for non-stackable.
    /// </summary>
    public int Amount { get; private set; }

    /// <summary>
    /// Whether this item is noted.
    /// </summary>
    public bool IsNoted { get; init; }

    /// <summary>
    /// Unique identifier for this specific item instance (for tracking).
    /// </summary>
    public Guid InstanceId { get; } = Guid.NewGuid();

    public Item(ItemDefinition definition, int amount = 1)
    {
        Definition = definition ?? throw new ArgumentNullException(nameof(definition));
        Amount = definition.IsStackable ? Math.Max(1, amount) : 1;
    }

    /// <summary>
    /// Creates a copy of this item.
    /// </summary>
    public Item Clone() => new(Definition, Amount) { IsNoted = IsNoted };

    /// <summary>
    /// Adds to the stack amount (for stackable items).
    /// </summary>
    /// <returns>The overflow amount that couldn't be added.</returns>
    public int AddToStack(int amount)
    {
        if (!Definition.IsStackable || amount <= 0)
            return amount;

        var available = int.MaxValue - Amount;
        var toAdd = Math.Min(amount, available);
        Amount += toAdd;
        return amount - toAdd;
    }

    /// <summary>
    /// Removes from the stack amount.
    /// </summary>
    /// <returns>True if successful, false if not enough.</returns>
    public bool RemoveFromStack(int amount)
    {
        if (amount <= 0 || amount > Amount)
            return false;

        Amount -= amount;
        return true;
    }

    /// <summary>
    /// Sets the exact stack amount.
    /// </summary>
    public void SetAmount(int amount)
    {
        Amount = Math.Max(0, amount);
    }

    public bool Equals(Item? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return InstanceId == other.InstanceId;
    }

    public override bool Equals(object? obj) => Equals(obj as Item);
    public override int GetHashCode() => InstanceId.GetHashCode();

    public override string ToString() =>
        Definition.IsStackable ? $"{Definition.Name} x{Amount}" : Definition.Name;
}

/// <summary>
/// Factory for creating items from definitions.
/// </summary>
public interface IItemFactory
{
    Item Create(int catalogId, int amount = 1);
    Item? TryCreate(int catalogId, int amount = 1);
    ItemDefinition? GetDefinition(int catalogId);
}

/// <summary>
/// Default item factory implementation.
/// </summary>
public sealed class ItemFactory : IItemFactory
{
    private readonly IItemDefinitionRepository _repository;

    public ItemFactory(IItemDefinitionRepository repository)
    {
        _repository = repository;
    }

    public Item Create(int catalogId, int amount = 1)
    {
        var definition = _repository.GetById(catalogId)
            ?? throw new InvalidOperationException($"No item definition found for catalog ID {catalogId}");
        return new Item(definition, amount);
    }

    public Item? TryCreate(int catalogId, int amount = 1)
    {
        var definition = _repository.GetById(catalogId);
        return definition is null ? null : new Item(definition, amount);
    }

    public ItemDefinition? GetDefinition(int catalogId) => _repository.GetById(catalogId);
}

/// <summary>
/// Repository for item definitions.
/// </summary>
public interface IItemDefinitionRepository
{
    ItemDefinition? GetById(int catalogId);
    ItemDefinition? GetByName(string name);
    IEnumerable<ItemDefinition> GetAll();
}
