namespace OpenRSC.Server.Database;

/// <summary>
/// Repository for player data persistence.
/// </summary>
public interface IPlayerRepository
{
    /// <summary>
    /// Loads a player by username.
    /// </summary>
    Task<PlayerData?> LoadPlayerAsync(string username);

    /// <summary>
    /// Saves player data.
    /// </summary>
    Task SavePlayerAsync(PlayerData player);

    /// <summary>
    /// Checks if a player exists.
    /// </summary>
    Task<bool> PlayerExistsAsync(string username);

    /// <summary>
    /// Creates a new player record.
    /// </summary>
    Task<bool> CreatePlayerAsync(PlayerData player, string passwordHash);

    /// <summary>
    /// Updates the player's login timestamp.
    /// </summary>
    Task UpdateLoginTimeAsync(string username);

    /// <summary>
    /// Gets the password hash for authentication.
    /// </summary>
    Task<string?> GetPasswordHashAsync(string username);
}

/// <summary>
/// Player data transfer object for persistence.
/// </summary>
public sealed class PlayerData
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public int X { get; set; }
    public int Y { get; set; }
    public int CombatLevel { get; set; }
    public int TotalLevel { get; set; }

    // Stats (19 skills including Runecraft)
    public int[] CurrentStats { get; set; } = new int[19];
    public int[] MaxStats { get; set; } = new int[19];
    public int[] Experience { get; set; } = new int[19];

    // Combat
    public int Hitpoints { get; set; }
    public int MaxHitpoints { get; set; }
    public int PrayerPoints { get; set; }

    // Misc
    public int Fatigue { get; set; }
    public int QuestPoints { get; set; }
    public bool IsMember { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime LastLogin { get; set; }
    public TimeSpan TotalPlayTime { get; set; }
}
