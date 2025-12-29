using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Wilderness;

/// <summary>
/// Wilderness zone types.
/// </summary>
public enum WildernessZone
{
    Safe,           // Not in wilderness
    SingleCombat,   // Single combat zone
    MultiCombat     // Multi-combat zone
}

/// <summary>
/// Wilderness boundaries and configuration.
/// </summary>
public static class WildernessBounds
{
    // RSC Wilderness boundaries (approximate)
    public const int WildernessMinX = 48;
    public const int WildernessMaxX = 334;
    public const int WildernessStartY = 392;
    public const int WildernessMaxY = 1000;

    // Wilderness level increments every 6 tiles north
    public const int TilesPerLevel = 6;

    // Combat level difference allowed per wilderness level
    public const int CombatLevelPerWildLevel = 1;

    /// <summary>
    /// Multi-combat zones.
    /// </summary>
    public static readonly IReadOnlyList<(Point Min, Point Max)> MultiCombatZones = new[]
    {
        // Example zones
        (new Point(200, 500), new Point(250, 550)), // Deep wilderness multi
        (new Point(280, 600), new Point(320, 700)), // Mage bank area
    };
}

/// <summary>
/// Manages wilderness mechanics.
/// </summary>
public sealed class WildernessManager
{
    /// <summary>
    /// Checks if a location is in the wilderness.
    /// </summary>
    public static bool IsInWilderness(Point location)
    {
        return location.X >= WildernessBounds.WildernessMinX &&
               location.X <= WildernessBounds.WildernessMaxX &&
               location.Y >= WildernessBounds.WildernessStartY &&
               location.Y <= WildernessBounds.WildernessMaxY;
    }

    /// <summary>
    /// Gets the wilderness level at a location.
    /// </summary>
    public static int GetWildernessLevel(Point location)
    {
        if (!IsInWilderness(location))
            return 0;

        var tilesNorth = location.Y - WildernessBounds.WildernessStartY;
        return Math.Max(1, tilesNorth / WildernessBounds.TilesPerLevel + 1);
    }

    /// <summary>
    /// Gets the combat level range for attacking at a wilderness level.
    /// </summary>
    public static (int Min, int Max) GetCombatLevelRange(int playerCombatLevel, int wildernessLevel)
    {
        var range = wildernessLevel * WildernessBounds.CombatLevelPerWildLevel;
        return (
            Math.Max(3, playerCombatLevel - range),
            Math.Min(126, playerCombatLevel + range)
        );
    }

    /// <summary>
    /// Checks if a player can attack another player based on wilderness rules.
    /// </summary>
    public static WildernessAttackResult CanAttack(Player attacker, Player target)
    {
        // Check attacker is in wilderness
        if (!IsInWilderness(attacker.Location))
        {
            return WildernessAttackResult.Fail("You can only attack other players in the wilderness.");
        }

        // Check target is in wilderness
        if (!IsInWilderness(target.Location))
        {
            return WildernessAttackResult.Fail("Your target is not in the wilderness.");
        }

        // Get wilderness levels
        var attackerWildLevel = GetWildernessLevel(attacker.Location);
        var targetWildLevel = GetWildernessLevel(target.Location);

        // Use the lower wilderness level
        var effectiveWildLevel = Math.Min(attackerWildLevel, targetWildLevel);

        // Check combat level range
        var attackerCombat = attacker.CombatLevel;
        var targetCombat = target.CombatLevel;
        var (minLevel, maxLevel) = GetCombatLevelRange(attackerCombat, effectiveWildLevel);

        if (targetCombat < minLevel || targetCombat > maxLevel)
        {
            return WildernessAttackResult.Fail(
                $"Your opponent's combat level must be between {minLevel} and {maxLevel} to attack here.");
        }

        // Check if in multi-combat zone for multi-way combat
        var attackerZone = GetZone(attacker.Location);
        var targetZone = GetZone(target.Location);

        if (attackerZone != WildernessZone.MultiCombat && targetZone != WildernessZone.MultiCombat)
        {
            // Single combat - check if either is already in combat
            if (target.InCombat && target.CombatTarget != attacker)
            {
                return WildernessAttackResult.Fail("Your opponent is already in combat.");
            }
        }

        return WildernessAttackResult.Ok;
    }

    /// <summary>
    /// Gets the wilderness zone type for a location.
    /// </summary>
    public static WildernessZone GetZone(Point location)
    {
        if (!IsInWilderness(location))
            return WildernessZone.Safe;

        foreach (var (min, max) in WildernessBounds.MultiCombatZones)
        {
            if (location.X >= min.X && location.X <= max.X &&
                location.Y >= min.Y && location.Y <= max.Y)
            {
                return WildernessZone.MultiCombat;
            }
        }

        return WildernessZone.SingleCombat;
    }

    /// <summary>
    /// Gets wilderness information for display.
    /// </summary>
    public static WildernessInfo GetInfo(Point location)
    {
        if (!IsInWilderness(location))
        {
            return new WildernessInfo(false, 0, WildernessZone.Safe);
        }

        return new WildernessInfo(
            true,
            GetWildernessLevel(location),
            GetZone(location)
        );
    }

    /// <summary>
    /// Handles player entering wilderness.
    /// </summary>
    public void OnEnterWilderness(Player player)
    {
        var level = GetWildernessLevel(player.Location);
        var zone = GetZone(player.Location);

        player.Message($"Warning! You are entering level {level} wilderness.");

        if (zone == WildernessZone.MultiCombat)
        {
            player.Message("This is a multi-combat zone.");
        }
    }

    /// <summary>
    /// Handles player leaving wilderness.
    /// </summary>
    public void OnLeaveWilderness(Player player)
    {
        player.Message("You have left the wilderness.");
    }

    /// <summary>
    /// Updates player wilderness status on movement.
    /// </summary>
    public void OnPlayerMove(Player player, Point oldLocation, Point newLocation)
    {
        var wasInWild = IsInWilderness(oldLocation);
        var isInWild = IsInWilderness(newLocation);

        if (!wasInWild && isInWild)
        {
            OnEnterWilderness(player);
        }
        else if (wasInWild && !isInWild)
        {
            OnLeaveWilderness(player);
        }
        else if (wasInWild && isInWild)
        {
            // Check for level change
            var oldLevel = GetWildernessLevel(oldLocation);
            var newLevel = GetWildernessLevel(newLocation);

            if (newLevel > oldLevel)
            {
                player.Message($"Wilderness level: {newLevel}");
            }

            // Check for zone change
            var oldZone = GetZone(oldLocation);
            var newZone = GetZone(newLocation);

            if (oldZone != newZone)
            {
                if (newZone == WildernessZone.MultiCombat)
                {
                    player.Message("You have entered a multi-combat zone.");
                }
                else if (oldZone == WildernessZone.MultiCombat)
                {
                    player.Message("You have left the multi-combat zone.");
                }
            }
        }
    }

    /// <summary>
    /// Applies skull to player for attacking.
    /// </summary>
    public void ApplySkull(Player attacker, Player target)
    {
        // Don't skull if target already skulled or if retaliating
        if (attacker.IsSkulled)
            return;

        if (target.InCombat && target.CombatTarget == attacker)
            return; // Retaliating doesn't skull

        attacker.IsSkulled = true;
        attacker.SkullExpiry = DateTime.UtcNow.AddMinutes(20);
        attacker.Message("You have been skulled for attacking first!");
    }

    /// <summary>
    /// Updates skull timer.
    /// </summary>
    public void UpdateSkull(Player player)
    {
        if (!player.IsSkulled)
            return;

        if (player.SkullExpiry.HasValue && DateTime.UtcNow >= player.SkullExpiry.Value)
        {
            player.IsSkulled = false;
            player.SkullExpiry = null;
            player.Message("Your skull has disappeared.");
        }
    }
}

/// <summary>
/// Result of a wilderness attack check.
/// </summary>
public readonly record struct WildernessAttackResult(bool Success, string? Message = null)
{
    public static WildernessAttackResult Fail(string message) => new(false, message);
    public static readonly WildernessAttackResult Ok = new(true);
}

/// <summary>
/// Wilderness information for a location.
/// </summary>
public readonly record struct WildernessInfo(
    bool InWilderness,
    int Level,
    WildernessZone Zone
);

/// <summary>
/// Handles wilderness teleport restrictions.
/// </summary>
public static class WildernessTeleportRules
{
    public const int MaxTeleportLevel = 20;

    /// <summary>
    /// Checks if teleportation is allowed at a location.
    /// </summary>
    public static bool CanTeleport(Point location)
    {
        if (!WildernessManager.IsInWilderness(location))
            return true;

        var level = WildernessManager.GetWildernessLevel(location);
        return level <= MaxTeleportLevel;
    }

    /// <summary>
    /// Gets the reason teleportation is blocked.
    /// </summary>
    public static string GetTeleblockReason(Point location)
    {
        var level = WildernessManager.GetWildernessLevel(location);
        return $"You cannot teleport above level {MaxTeleportLevel} wilderness. Current level: {level}";
    }
}

/// <summary>
/// Hot zones with bonus drop rates.
/// </summary>
public static class WildernessHotZones
{
    private static readonly Dictionary<(Point Min, Point Max), double> HotZones = new()
    {
        // Example hot zones with bonus drop rate multipliers
        [(new Point(200, 520), new Point(230, 540))] = 1.5,  // 50% bonus
        [(new Point(280, 620), new Point(300, 650))] = 2.0   // 100% bonus
    };

    /// <summary>
    /// Gets the drop rate multiplier for a location.
    /// </summary>
    public static double GetDropMultiplier(Point location)
    {
        foreach (var ((min, max), multiplier) in HotZones)
        {
            if (location.X >= min.X && location.X <= max.X &&
                location.Y >= min.Y && location.Y <= max.Y)
            {
                return multiplier;
            }
        }
        return 1.0;
    }

    /// <summary>
    /// Checks if location is a hot zone.
    /// </summary>
    public static bool IsHotZone(Point location)
    {
        return GetDropMultiplier(location) > 1.0;
    }
}
