using OpenRSC.Server.Entities;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Prayer;

/// <summary>
/// Manages a player's active prayers and prayer points.
/// </summary>
public sealed class PlayerPrayers
{
    private readonly Player _player;
    private readonly HashSet<PrayerType> _activePrayers = new();
    private DateTime _lastDrainTime;
    private double _drainAccumulator;

    /// <summary>
    /// Event raised when prayers change.
    /// </summary>
    public event Action<PrayerType, bool>? PrayerChanged;

    /// <summary>
    /// Current prayer points (0 to max).
    /// </summary>
    public int CurrentPoints { get; private set; }

    /// <summary>
    /// Maximum prayer points based on prayer level.
    /// </summary>
    public int MaxPoints => _player.Skills.GetMaxLevel(Skill.Prayer);

    /// <summary>
    /// Whether any prayers are active.
    /// </summary>
    public bool HasActivePrayers => _activePrayers.Count > 0;

    /// <summary>
    /// Currently active prayers.
    /// </summary>
    public IReadOnlySet<PrayerType> ActivePrayers => _activePrayers;

    public PlayerPrayers(Player player)
    {
        _player = player;
        CurrentPoints = MaxPoints;
        _lastDrainTime = DateTime.UtcNow;
    }

    /// <summary>
    /// Activates a prayer.
    /// </summary>
    public PrayerResult Activate(PrayerType prayer)
    {
        if (_activePrayers.Contains(prayer))
            return PrayerResult.AlreadyActive;

        var definition = PrayerDefinition.All[prayer];

        // Check level requirement
        if (_player.Skills.GetMaxLevel(Skill.Prayer) < definition.RequiredLevel)
        {
            return PrayerResult.Fail($"You need level {definition.RequiredLevel} Prayer to use {definition.Name}.");
        }

        // Check prayer points
        if (CurrentPoints <= 0)
        {
            return PrayerResult.Fail("You have run out of prayer points.");
        }

        // Deactivate conflicting prayers
        foreach (var conflict in definition.ConflictsWith)
        {
            if (_activePrayers.Contains(conflict))
            {
                Deactivate(conflict);
            }
        }

        _activePrayers.Add(prayer);
        PrayerChanged?.Invoke(prayer, true);

        return PrayerResult.Success;
    }

    /// <summary>
    /// Deactivates a prayer.
    /// </summary>
    public void Deactivate(PrayerType prayer)
    {
        if (_activePrayers.Remove(prayer))
        {
            PrayerChanged?.Invoke(prayer, false);
        }
    }

    /// <summary>
    /// Toggles a prayer on/off.
    /// </summary>
    public PrayerResult Toggle(PrayerType prayer)
    {
        return _activePrayers.Contains(prayer)
            ? DeactivateAndSucceed(prayer)
            : Activate(prayer);
    }

    private PrayerResult DeactivateAndSucceed(PrayerType prayer)
    {
        Deactivate(prayer);
        return PrayerResult.Success;
    }

    /// <summary>
    /// Deactivates all prayers.
    /// </summary>
    public void DeactivateAll()
    {
        foreach (var prayer in _activePrayers.ToList())
        {
            Deactivate(prayer);
        }
    }

    /// <summary>
    /// Checks if a prayer is active.
    /// </summary>
    public bool IsActive(PrayerType prayer) => _activePrayers.Contains(prayer);

    /// <summary>
    /// Processes prayer drain for this tick.
    /// </summary>
    public void ProcessDrain()
    {
        if (!HasActivePrayers)
            return;

        var now = DateTime.UtcNow;
        var elapsed = (now - _lastDrainTime).TotalMinutes;
        _lastDrainTime = now;

        // Calculate total drain rate
        var totalDrainRate = 0;
        foreach (var prayer in _activePrayers)
        {
            totalDrainRate += PrayerDefinition.All[prayer].DrainRate;
        }

        // Apply prayer bonus from equipment (reduces drain)
        var prayerBonus = _player.Equipment.GetTotalBonuses().PrayerBonus;
        var drainMultiplier = 1.0 / (1.0 + prayerBonus / 30.0);

        _drainAccumulator += totalDrainRate * elapsed * drainMultiplier;

        // Drain whole points
        var pointsToDrain = (int)_drainAccumulator;
        if (pointsToDrain > 0)
        {
            _drainAccumulator -= pointsToDrain;
            DrainPoints(pointsToDrain);
        }
    }

    /// <summary>
    /// Drains prayer points.
    /// </summary>
    public void DrainPoints(int amount)
    {
        CurrentPoints = Math.Max(0, CurrentPoints - amount);

        if (CurrentPoints <= 0)
        {
            DeactivateAll();
            _player.Message("You have run out of prayer points.");
        }
    }

    /// <summary>
    /// Restores prayer points.
    /// </summary>
    public void RestorePoints(int amount)
    {
        CurrentPoints = Math.Min(MaxPoints, CurrentPoints + amount);
    }

    /// <summary>
    /// Fully restores prayer points.
    /// </summary>
    public void RestoreFully()
    {
        CurrentPoints = MaxPoints;
    }

    /// <summary>
    /// Gets the combined attack multiplier from prayers.
    /// </summary>
    public double GetAttackMultiplier()
    {
        var multiplier = 1.0;
        foreach (var prayer in _activePrayers)
        {
            multiplier *= PrayerDefinition.All[prayer].AttackMultiplier;
        }
        return multiplier;
    }

    /// <summary>
    /// Gets the combined strength multiplier from prayers.
    /// </summary>
    public double GetStrengthMultiplier()
    {
        var multiplier = 1.0;
        foreach (var prayer in _activePrayers)
        {
            multiplier *= PrayerDefinition.All[prayer].StrengthMultiplier;
        }
        return multiplier;
    }

    /// <summary>
    /// Gets the combined defense multiplier from prayers.
    /// </summary>
    public double GetDefenseMultiplier()
    {
        var multiplier = 1.0;
        foreach (var prayer in _activePrayers)
        {
            multiplier *= PrayerDefinition.All[prayer].DefenseMultiplier;
        }
        return multiplier;
    }

    /// <summary>
    /// Whether rapid restore is active.
    /// </summary>
    public bool HasRapidRestore => _activePrayers.Any(p => PrayerDefinition.All[p].RapidRestore);

    /// <summary>
    /// Whether rapid heal is active.
    /// </summary>
    public bool HasRapidHeal => _activePrayers.Any(p => PrayerDefinition.All[p].RapidHeal);

    /// <summary>
    /// Whether protect items is active.
    /// </summary>
    public bool HasProtectItems => _activePrayers.Any(p => PrayerDefinition.All[p].ProtectItem);

    /// <summary>
    /// Number of items kept on death (3 normally, 4 with protect items, 0 if skulled).
    /// </summary>
    public int ItemsKeptOnDeath
    {
        get
        {
            if (_player.IsSkulled)
                return HasProtectItems ? 1 : 0;
            return HasProtectItems ? 4 : 3;
        }
    }
}

/// <summary>
/// Result of a prayer operation.
/// </summary>
public readonly record struct PrayerResult(bool Success, string? Message = null)
{
    public static PrayerResult Fail(string message) => new(false, message);
    public static readonly PrayerResult AlreadyActive = new(true);
    public static readonly PrayerResult Success = new(true);

    public static implicit operator bool(PrayerResult result) => result.Success;
}
