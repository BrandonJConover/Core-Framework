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

    /// <summary>
    /// Trust proxy headers (X-Forwarded-For, X-Real-IP) for client IP detection.
    /// Only enable when behind a trusted reverse proxy.
    /// </summary>
    public bool TrustProxyHeaders { get; set; }

    /// <summary>
    /// Trusted proxy IP addresses (comma-separated).
    /// When set, proxy headers are only trusted from these IPs.
    /// </summary>
    public string TrustedProxyIps { get; set; } = "";
}

/// <summary>
/// Security-related settings for encryption, authentication, and auditing.
/// </summary>
public sealed class SecuritySettings
{
    public const string SectionName = "Security";

    /// <summary>
    /// Master encryption key for data at rest (base64, 256-bit).
    /// Generate with: DataEncryption.GenerateKey()
    /// </summary>
    public string MasterEncryptionKey { get; set; } = "";

    /// <summary>
    /// Enable encryption for sensitive player data at rest.
    /// </summary>
    public bool EncryptSensitiveData { get; set; } = true;

    /// <summary>
    /// Password hashing algorithm to use (Argon2id or Pbkdf2Sha512).
    /// </summary>
    public string PasswordHashAlgorithm { get; set; } = "Argon2id";

    /// <summary>
    /// Enforce strong password requirements for new accounts.
    /// </summary>
    public bool EnforceStrongPasswords { get; set; } = true;

    /// <summary>
    /// Minimum password length.
    /// </summary>
    public int MinPasswordLength { get; set; } = 8;

    /// <summary>
    /// Require uppercase letters in passwords.
    /// </summary>
    public bool RequirePasswordUppercase { get; set; } = true;

    /// <summary>
    /// Require lowercase letters in passwords.
    /// </summary>
    public bool RequirePasswordLowercase { get; set; } = true;

    /// <summary>
    /// Require digits in passwords.
    /// </summary>
    public bool RequirePasswordDigit { get; set; } = true;

    /// <summary>
    /// Require special characters in passwords.
    /// </summary>
    public bool RequirePasswordSpecialChar { get; set; } = true;

    /// <summary>
    /// Reject common/weak passwords.
    /// </summary>
    public bool RejectCommonPasswords { get; set; } = true;

    /// <summary>
    /// Maximum failed login attempts before account lockout.
    /// </summary>
    public int MaxFailedLoginAttempts { get; set; } = 5;

    /// <summary>
    /// Account lockout duration in minutes.
    /// </summary>
    public int AccountLockoutMinutes { get; set; } = 15;

    /// <summary>
    /// Enable security audit logging.
    /// </summary>
    public bool EnableSecurityAuditLog { get; set; } = true;

    /// <summary>
    /// Path to security audit log file.
    /// </summary>
    public string SecurityAuditLogPath { get; set; } = "logs/security-audit.log";

    /// <summary>
    /// Session token expiration in hours.
    /// </summary>
    public int SessionTokenExpirationHours { get; set; } = 24;

    /// <summary>
    /// Enable session token refresh.
    /// </summary>
    public bool EnableSessionTokenRefresh { get; set; } = true;

    /// <summary>
    /// Require re-authentication for sensitive operations.
    /// </summary>
    public bool RequireReauthForSensitiveOps { get; set; } = true;

    /// <summary>
    /// Enable IP-based session binding (more secure but may cause issues with dynamic IPs).
    /// </summary>
    public bool BindSessionToIp { get; set; } = false;
}

/// <summary>
/// OAuth and external authentication settings.
/// </summary>
public sealed class OAuthSettings
{
    public const string SectionName = "OAuth";

    /// <summary>
    /// Enable OAuth authentication.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Enable Google Sign-In.
    /// </summary>
    public bool EnableGoogle { get; set; } = true;

    /// <summary>
    /// Google OAuth Client ID.
    /// </summary>
    public string GoogleClientId { get; set; } = "";

    /// <summary>
    /// Google OAuth Client Secret.
    /// </summary>
    public string GoogleClientSecret { get; set; } = "";

    /// <summary>
    /// Enable Apple Sign-In.
    /// </summary>
    public bool EnableApple { get; set; } = false;

    /// <summary>
    /// Apple Services ID.
    /// </summary>
    public string AppleServicesId { get; set; } = "";

    /// <summary>
    /// Apple Team ID.
    /// </summary>
    public string AppleTeamId { get; set; } = "";

    /// <summary>
    /// Apple Key ID.
    /// </summary>
    public string AppleKeyId { get; set; } = "";

    /// <summary>
    /// Path to Apple private key file.
    /// </summary>
    public string ApplePrivateKeyPath { get; set; } = "";

    /// <summary>
    /// Enable Discord login.
    /// </summary>
    public bool EnableDiscord { get; set; } = false;

    /// <summary>
    /// Discord OAuth Client ID.
    /// </summary>
    public string DiscordClientId { get; set; } = "";

    /// <summary>
    /// Discord OAuth Client Secret.
    /// </summary>
    public string DiscordClientSecret { get; set; } = "";

    /// <summary>
    /// OAuth callback URL base (e.g., https://game.example.com/auth).
    /// </summary>
    public string CallbackUrlBase { get; set; } = "";

    /// <summary>
    /// Allow account linking (connect OAuth to existing username/password account).
    /// </summary>
    public bool AllowAccountLinking { get; set; } = true;

    /// <summary>
    /// Require email verification for new OAuth accounts.
    /// </summary>
    public bool RequireEmailVerification { get; set; } = false;

    /// <summary>
    /// Auto-generate username from OAuth profile if not provided.
    /// </summary>
    public bool AutoGenerateUsername { get; set; } = true;
}

/// <summary>
/// Authentication token settings for mobile/keychain support.
/// </summary>
public sealed class AuthTokenSettings
{
    public const string SectionName = "AuthToken";

    /// <summary>
    /// Enable refresh tokens for persistent login.
    /// </summary>
    public bool EnableRefreshTokens { get; set; } = true;

    /// <summary>
    /// Access token lifetime in minutes.
    /// </summary>
    public int AccessTokenLifetimeMinutes { get; set; } = 60;

    /// <summary>
    /// Refresh token lifetime in days.
    /// </summary>
    public int RefreshTokenLifetimeDays { get; set; } = 30;

    /// <summary>
    /// Maximum refresh tokens per user (revokes oldest when exceeded).
    /// </summary>
    public int MaxRefreshTokensPerUser { get; set; } = 5;

    /// <summary>
    /// Rotate refresh token on use (more secure, but breaks concurrent sessions).
    /// </summary>
    public bool RotateRefreshTokens { get; set; } = true;

    /// <summary>
    /// Revoke all tokens on password change.
    /// </summary>
    public bool RevokeTokensOnPasswordChange { get; set; } = true;

    /// <summary>
    /// Bind refresh tokens to device fingerprint.
    /// </summary>
    public bool BindToDevice { get; set; } = false;
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
    /// Database provider: PostgreSQL, MySQL, SQLite.
    /// </summary>
    public string Provider { get; set; } = "PostgreSQL";

    /// <summary>
    /// Database connection string.
    /// </summary>
    public string ConnectionString { get; set; } = "Host=localhost;Database=openrsc;Username=openrsc;Password=openrsc";

    /// <summary>
    /// Table prefix for all database tables.
    /// </summary>
    public string TablePrefix { get; set; } = "";

    /// <summary>
    /// Connection pool minimum size.
    /// </summary>
    public int MinPoolSize { get; set; } = 5;

    /// <summary>
    /// Connection pool maximum size.
    /// </summary>
    public int MaxPoolSize { get; set; } = 100;

    /// <summary>
    /// Command timeout in seconds.
    /// </summary>
    public int CommandTimeoutSeconds { get; set; } = 30;

    /// <summary>
    /// Enable query logging for debugging.
    /// </summary>
    public bool EnableQueryLogging { get; set; } = false;
}

/// <summary>
/// Device fingerprinting and management settings.
/// </summary>
public sealed class DeviceSettings
{
    public const string SectionName = "Device";

    /// <summary>
    /// Enable device fingerprinting.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Maximum devices per user account.
    /// </summary>
    public int MaxDevicesPerUser { get; set; } = 10;

    /// <summary>
    /// Risk score added for new/unrecognized devices.
    /// </summary>
    public int NewDeviceRiskScore { get; set; } = 25;

    /// <summary>
    /// Risk score threshold requiring additional verification.
    /// </summary>
    public int VerificationThreshold { get; set; } = 50;

    /// <summary>
    /// Automatically register new devices on successful login.
    /// </summary>
    public bool AutoRegisterDevices { get; set; } = true;

    /// <summary>
    /// Block logins from jailbroken/rooted devices.
    /// </summary>
    public bool BlockCompromisedDevices { get; set; } = false;

    /// <summary>
    /// Block logins from emulators/simulators.
    /// </summary>
    public bool BlockEmulators { get; set; } = false;

    /// <summary>
    /// Notify user via email when new device logs in.
    /// </summary>
    public bool NotifyNewDevice { get; set; } = true;

    /// <summary>
    /// Days to retain inactive device records.
    /// </summary>
    public int DeviceRetentionDays { get; set; } = 365;
}

/// <summary>
/// Redis cache settings.
/// </summary>
public sealed class RedisSettings
{
    public const string SectionName = "Redis";

    /// <summary>
    /// Enable Redis caching.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Redis connection string.
    /// </summary>
    public string ConnectionString { get; set; } = "localhost:6379";

    /// <summary>
    /// Redis password (if required).
    /// </summary>
    public string? Password { get; set; }

    /// <summary>
    /// Default database index (0-15).
    /// </summary>
    public int Database { get; set; } = 0;

    /// <summary>
    /// Key prefix for all keys.
    /// </summary>
    public string KeyPrefix { get; set; } = "openrsc:";

    /// <summary>
    /// Default cache expiration in seconds.
    /// </summary>
    public int DefaultExpirationSeconds { get; set; } = 300;

    /// <summary>
    /// Session cache expiration in seconds.
    /// </summary>
    public int SessionExpirationSeconds { get; set; } = 86400; // 24 hours

    /// <summary>
    /// Enable connection pooling.
    /// </summary>
    public bool UseConnectionPooling { get; set; } = true;
}

/// <summary>
/// DDoS protection and rate limiting settings.
/// </summary>
public sealed class DDoSProtectionSettings
{
    public const string SectionName = "DDoSProtection";

    /// <summary>
    /// Enable DDoS protection.
    /// </summary>
    public bool Enabled { get; set; } = true;

    // Connection rate limiting
    /// <summary>
    /// Maximum new connections per IP within the connection window.
    /// </summary>
    public int MaxConnectionsPerIp { get; set; } = 10;

    /// <summary>
    /// Time window in seconds for connection rate limiting.
    /// </summary>
    public int ConnectionWindowSeconds { get; set; } = 60;

    // Request rate limiting
    /// <summary>
    /// Maximum requests per second per IP.
    /// </summary>
    public int MaxRequestsPerSecond { get; set; } = 100;

    /// <summary>
    /// Maximum bytes per second per IP (0 = unlimited).
    /// </summary>
    public long MaxBytesPerSecond { get; set; } = 102400; // 100 KB/s

    // Authentication protection
    /// <summary>
    /// Maximum failed authentication attempts before temp ban.
    /// </summary>
    public int MaxFailedAuthAttempts { get; set; } = 5;

    /// <summary>
    /// Duration of auth failure ban in minutes.
    /// </summary>
    public int AuthBanDurationMinutes { get; set; } = 15;

    // Penalty system
    /// <summary>
    /// Penalty points added per connection violation.
    /// </summary>
    public int ConnectionViolationPenalty { get; set; } = 10;

    /// <summary>
    /// Penalty points added per request violation.
    /// </summary>
    public int RequestViolationPenalty { get; set; } = 5;

    /// <summary>
    /// Penalty points added per bandwidth violation.
    /// </summary>
    public int BandwidthViolationPenalty { get; set; } = 15;

    /// <summary>
    /// Penalty points added per failed auth attempt.
    /// </summary>
    public int FailedAuthPenalty { get; set; } = 20;

    /// <summary>
    /// Penalty points removed on successful auth.
    /// </summary>
    public int SuccessfulAuthBonus { get; set; } = 10;

    /// <summary>
    /// Penalty threshold that triggers automatic ban.
    /// </summary>
    public int PenaltyThresholdForBan { get; set; } = 100;

    /// <summary>
    /// Number of violations before automatic ban.
    /// </summary>
    public int ViolationsBeforeBan { get; set; } = 3;

    // Ban durations
    /// <summary>
    /// Duration of automatic bans in minutes.
    /// </summary>
    public int AutoBanDurationMinutes { get; set; } = 30;

    // Maintenance
    /// <summary>
    /// Minutes before inactive IP trackers are cleaned up.
    /// </summary>
    public int TrackerExpirationMinutes { get; set; } = 30;

    /// <summary>
    /// Comma-separated list of whitelisted IPs or CIDR ranges.
    /// </summary>
    public string WhitelistedIps { get; set; } = "";

    // SYN flood protection
    /// <summary>
    /// Maximum pending (half-open) connections per IP.
    /// </summary>
    public int MaxPendingConnectionsPerIp { get; set; } = 5;

    /// <summary>
    /// Timeout for pending connections in seconds.
    /// </summary>
    public int PendingConnectionTimeoutSeconds { get; set; } = 10;
}
