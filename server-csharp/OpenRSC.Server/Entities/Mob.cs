using OpenRSC.Server.Models;

namespace OpenRSC.Server.Entities;

/// <summary>
/// Base class for mobile entities (Players and NPCs) that can move and engage in combat.
/// </summary>
public abstract class Mob : Entity
{
    /// <summary>
    /// The direction the mob is facing (0-11, where 8-9 are combat stances).
    /// </summary>
    public int Sprite { get; protected set; }

    /// <summary>
    /// Current hitpoints.
    /// </summary>
    public int CurrentHitpoints { get; protected set; }

    /// <summary>
    /// Maximum hitpoints.
    /// </summary>
    public int MaxHitpoints { get; protected set; }

    /// <summary>
    /// Combat level of this mob.
    /// </summary>
    public int CombatLevel { get; protected set; }

    /// <summary>
    /// Whether this mob is currently in combat.
    /// </summary>
    public bool InCombat { get; protected set; }

    /// <summary>
    /// The current combat opponent, if any.
    /// </summary>
    public Mob? Opponent { get; protected set; }

    /// <summary>
    /// Whether this mob is currently busy (performing an action).
    /// </summary>
    public bool IsBusy { get; protected set; }

    /// <summary>
    /// Whether this mob has moved this tick.
    /// </summary>
    public bool HasMoved { get; protected set; }

    /// <summary>
    /// Whether the mob's sprite has changed this tick.
    /// </summary>
    public bool SpriteChanged { get; protected set; }

    protected Mob(Point location) : base(location)
    {
    }

    /// <summary>
    /// Engages this mob in combat with an opponent.
    /// </summary>
    public virtual void SetCombat(Mob opponent)
    {
        InCombat = true;
        Opponent = opponent;
        IsBusy = true;
    }

    /// <summary>
    /// Ends combat for this mob.
    /// </summary>
    public virtual void EndCombat()
    {
        InCombat = false;
        Opponent = null;
        IsBusy = false;
    }

    /// <summary>
    /// Applies damage to this mob.
    /// </summary>
    public virtual void TakeDamage(int damage)
    {
        CurrentHitpoints = Math.Max(0, CurrentHitpoints - damage);
    }

    /// <summary>
    /// Heals this mob by the specified amount.
    /// </summary>
    public virtual void Heal(int amount)
    {
        CurrentHitpoints = Math.Min(MaxHitpoints, CurrentHitpoints + amount);
    }

    /// <summary>
    /// Resets per-tick state after update cycle.
    /// </summary>
    public virtual void ResetAfterUpdate()
    {
        HasMoved = false;
        SpriteChanged = false;
    }
}
