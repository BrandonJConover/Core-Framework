namespace OpenRSC.Server.Configuration;

/// <summary>
/// Server configuration settings. Uses the Options pattern for DI.
/// </summary>
public sealed class ServerSettings
{
    public const string SectionName = "Server";

    /// <summary>
    /// Server name displayed to players.
    /// </summary>
    public string ServerName { get; set; } = "OpenRSC";

    /// <summary>
    /// Welcome message shown on login.
    /// </summary>
    public string WelcomeText { get; set; } = "Welcome to OpenRSC!";

    /// <summary>
    /// Game tick duration in milliseconds.
    /// </summary>
    public int GameTickMs { get; set; } = 640;

    /// <summary>
    /// Walking tick duration in milliseconds.
    /// </summary>
    public int WalkingTickMs { get; set; } = 640;

    /// <summary>
    /// Maximum number of players allowed on the server.
    /// </summary>
    public int MaxPlayers { get; set; } = 2000;

    /// <summary>
    /// Server port for TCP connections.
    /// </summary>
    public int ServerPort { get; set; } = 43594;

    /// <summary>
    /// WebSocket port for browser clients.
    /// </summary>
    public int WebSocketPort { get; set; } = 43494;

    /// <summary>
    /// Enable WebSocket connections.
    /// </summary>
    public bool EnableWebSockets { get; set; } = true;

    /// <summary>
    /// Idle timeout in milliseconds before player is logged out.
    /// </summary>
    public int IdleTimeoutMs { get; set; } = 300000;

    /// <summary>
    /// Auto-save interval in milliseconds.
    /// </summary>
    public int AutoSaveIntervalMs { get; set; } = 30000;

    /// <summary>
    /// Whether this is a members-only world.
    /// </summary>
    public bool MembersWorld { get; set; } = true;

    /// <summary>
    /// World number for this server instance.
    /// </summary>
    public int WorldNumber { get; set; } = 1;

    /// <summary>
    /// Enable debug logging.
    /// </summary>
    public bool Debug { get; set; }

    /// <summary>
    /// Enable TLS encryption for client connections.
    /// </summary>
    public bool EnableTls { get; set; }

    /// <summary>
    /// Path to TLS certificate file (PFX format).
    /// </summary>
    public string TlsCertificatePath { get; set; } = "";

    /// <summary>
    /// Password for TLS certificate.
    /// </summary>
    public string TlsCertificatePassword { get; set; } = "";

    /// <summary>
    /// Enable packet compression for large packets.
    /// </summary>
    public bool EnableCompression { get; set; } = true;

    /// <summary>
    /// Minimum packet size for compression (bytes).
    /// </summary>
    public int CompressionThreshold { get; set; } = 128;

    /// <summary>
    /// Enable rate limiting for packet spam protection.
    /// </summary>
    public bool EnableRateLimiting { get; set; } = true;

    /// <summary>
    /// Maximum packets per second per client.
    /// </summary>
    public int RateLimitPacketsPerSecond { get; set; } = 100;

    /// <summary>
    /// Heartbeat interval in milliseconds.
    /// </summary>
    public int HeartbeatIntervalMs { get; set; } = 30000;

    /// <summary>
    /// Allowed origins for WebSocket CORS (comma-separated, or * for all).
    /// </summary>
    public string WebSocketAllowedOrigins { get; set; } = "*";

    /// <summary>
    /// Maximum WebSocket message size in bytes (default 64KB).
    /// </summary>
    public int WebSocketMaxMessageSize { get; set; } = 65536;

    /// <summary>
    /// WebSocket connection timeout in seconds.
    /// </summary>
    public int WebSocketConnectionTimeoutSeconds { get; set; } = 30;

    /// <summary>
    /// Maximum WebSocket connections per IP address.
    /// </summary>
    public int WebSocketMaxConnectionsPerIp { get; set; } = 5;

    /// <summary>
    /// Enable WebSocket Secure (WSS) - requires TLS certificate.
    /// </summary>
    public bool EnableSecureWebSockets { get; set; }
}

/// <summary>
/// Combat-related settings.
/// </summary>
public sealed class CombatSettings
{
    public const string SectionName = "Combat";

    /// <summary>
    /// Combat experience rate multiplier.
    /// </summary>
    public double CombatExpRate { get; set; } = 1.0;

    /// <summary>
    /// Wilderness experience boost percentage.
    /// </summary>
    public double WildernessBoost { get; set; } = 0.0;

    /// <summary>
    /// Skull experience boost percentage.
    /// </summary>
    public double SkullBoost { get; set; } = 0.0;

    /// <summary>
    /// Enable PID-less catching for PvP.
    /// </summary>
    public bool PidlessCatching { get; set; }

    /// <summary>
    /// PvM catching distance.
    /// </summary>
    public int PvmCatchingDistance { get; set; } = 1;

    /// <summary>
    /// PvP catching distance.
    /// </summary>
    public int PvpCatchingDistance { get; set; } = 1;

    /// <summary>
    /// Spell casting range.
    /// </summary>
    public int SpellRangeDistance { get; set; } = 4;
}

/// <summary>
/// Action retry settings for improved UX.
/// </summary>
public sealed class ActionRetrySettings
{
    public const string SectionName = "ActionRetry";

    /// <summary>
    /// Whether action retry is enabled globally.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Maximum number of retry attempts before action fails.
    /// </summary>
    public int MaxRetries { get; set; } = 10;
}

/// <summary>
/// Database connection settings.
/// </summary>
public sealed class DatabaseSettings
{
    public const string SectionName = "Database";

    /// <summary>
    /// Database connection string.
    /// </summary>
    public string ConnectionString { get; set; } = "Server=localhost;Database=openrsc;User=root;Password=;";

    /// <summary>
    /// Table prefix for all database tables.
    /// </summary>
    public string TablePrefix { get; set; } = "";
}
