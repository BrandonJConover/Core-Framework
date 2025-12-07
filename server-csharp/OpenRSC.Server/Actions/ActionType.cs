namespace OpenRSC.Server.Actions;

/// <summary>
/// Types of player actions for special handling.
/// </summary>
public enum ActionType
{
    /// <summary>
    /// Generic action type.
    /// </summary>
    Other,

    /// <summary>
    /// Melee or ranged attack action.
    /// </summary>
    Attack,

    /// <summary>
    /// Magic attack action.
    /// </summary>
    AttackMagic
}
