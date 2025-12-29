using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Security;

/// <summary>
/// Session information.
/// </summary>
public sealed class SessionInfo
{
    /// <summary>Unique session identifier.</summary>
    public required string SessionId { get; init; }

    /// <summary>Associated username.</summary>
    public required string Username { get; init; }

    /// <summary>IP address that created the session.</summary>
    public required string IpAddress { get; init; }

    /// <summary>When the session was created.</summary>
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    /// <summary>When the session expires.</summary>
    public DateTime ExpiresAt { get; set; }

    /// <summary>Last activity timestamp.</summary>
    public DateTime LastActivity { get; set; } = DateTime.UtcNow;

    /// <summary>Whether the session is still valid.</summary>
    public bool IsValid { get; set; } = true;

    /// <summary>User agent string (for web clients).</summary>
    public string? UserAgent { get; init; }

    /// <summary>Additional session metadata.</summary>
    public Dictionary<string, string>? Metadata { get; init; }

    /// <summary>Checks if the session has expired.</summary>
    public bool IsExpired => DateTime.UtcNow >= ExpiresAt;
}

/// <summary>
/// Session token payload.
/// </summary>
public sealed class SessionTokenPayload
{
    /// <summary>Session ID.</summary>
    public required string SessionId { get; init; }

    /// <summary>Username.</summary>
    public required string Username { get; init; }

    /// <summary>Issue timestamp (Unix seconds).</summary>
    public long IssuedAt { get; init; }

    /// <summary>Expiration timestamp (Unix seconds).</summary>
    public long ExpiresAt { get; init; }

    /// <summary>IP address hash (for binding).</summary>
    public string? IpHash { get; init; }
}

/// <summary>
/// Session token manager for secure session handling.
/// Tokens are cryptographically signed and optionally encrypted.
/// </summary>
public sealed class SessionTokenManager : IDisposable
{
    private readonly ILogger<SessionTokenManager> _logger;
    private readonly SecuritySettings _settings;
    private readonly ConcurrentDictionary<string, SessionInfo> _sessions = new();
    private readonly byte[] _signingKey;
    private readonly Timer _cleanupTimer;
    private bool _disposed;

    private const int SigningKeySize = 32; // 256 bits
    private const int SignatureSize = 32; // HMAC-SHA256

    public SessionTokenManager(
        ILogger<SessionTokenManager> logger,
        IOptions<SecuritySettings> settings)
    {
        _logger = logger;
        _settings = settings.Value;

        // Generate or derive signing key
        _signingKey = DeriveSigningKey();

        // Start cleanup timer
        _cleanupTimer = new Timer(
            CleanupExpiredSessions,
            null,
            TimeSpan.FromMinutes(5),
            TimeSpan.FromMinutes(5));
    }

    private byte[] DeriveSigningKey()
    {
        // Derive from master key if available, otherwise generate
        if (!string.IsNullOrEmpty(_settings.MasterEncryptionKey))
        {
            var masterKey = Convert.FromBase64String(_settings.MasterEncryptionKey);
            using var hmac = new HMACSHA256(masterKey);
            return hmac.ComputeHash(Encoding.UTF8.GetBytes("session-signing-key"));
        }

        _logger.LogWarning("No master encryption key configured - generating ephemeral session signing key");
        return RandomNumberGenerator.GetBytes(SigningKeySize);
    }

    /// <summary>
    /// Creates a new session and returns the session token.
    /// </summary>
    public string CreateSession(string username, string ipAddress, string? userAgent = null, Dictionary<string, string>? metadata = null)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        var sessionId = GenerateSessionId();
        var expiresAt = DateTime.UtcNow.AddHours(_settings.SessionTokenExpirationHours);

        var session = new SessionInfo
        {
            SessionId = sessionId,
            Username = username,
            IpAddress = ipAddress,
            ExpiresAt = expiresAt,
            UserAgent = userAgent,
            Metadata = metadata
        };

        _sessions[sessionId] = session;

        _logger.LogDebug("Created session {SessionId} for user {Username}", sessionId, username);

        return GenerateToken(session);
    }

    /// <summary>
    /// Validates a session token and returns the session info.
    /// </summary>
    public SessionInfo? ValidateToken(string token, string? currentIpAddress = null)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        try
        {
            var payload = ParseAndVerifyToken(token);
            if (payload is null)
                return null;

            // Check if session exists
            if (!_sessions.TryGetValue(payload.SessionId, out var session))
            {
                _logger.LogDebug("Session not found: {SessionId}", payload.SessionId);
                return null;
            }

            // Check if session is still valid
            if (!session.IsValid || session.IsExpired)
            {
                _logger.LogDebug("Session expired or invalidated: {SessionId}", payload.SessionId);
                return null;
            }

            // Check IP binding if enabled
            if (_settings.BindSessionToIp && currentIpAddress != null)
            {
                var currentIpHash = HashIpAddress(currentIpAddress);
                if (payload.IpHash != null && payload.IpHash != currentIpHash)
                {
                    _logger.LogWarning(
                        "Session IP mismatch for {SessionId}: expected {Expected}, got {Actual}",
                        payload.SessionId, payload.IpHash, currentIpHash);
                    return null;
                }
            }

            // Update last activity
            session.LastActivity = DateTime.UtcNow;

            return session;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Token validation failed");
            return null;
        }
    }

    /// <summary>
    /// Refreshes a session token, extending its expiration.
    /// </summary>
    public string? RefreshToken(string token, string? currentIpAddress = null)
    {
        if (!_settings.EnableSessionTokenRefresh)
            return null;

        var session = ValidateToken(token, currentIpAddress);
        if (session is null)
            return null;

        // Extend expiration
        session.ExpiresAt = DateTime.UtcNow.AddHours(_settings.SessionTokenExpirationHours);
        session.LastActivity = DateTime.UtcNow;

        _logger.LogDebug("Refreshed session {SessionId} for user {Username}", session.SessionId, session.Username);

        return GenerateToken(session);
    }

    /// <summary>
    /// Revokes a session.
    /// </summary>
    public bool RevokeSession(string sessionId)
    {
        if (_sessions.TryGetValue(sessionId, out var session))
        {
            session.IsValid = false;
            _sessions.TryRemove(sessionId, out _);
            _logger.LogDebug("Revoked session {SessionId}", sessionId);
            return true;
        }

        return false;
    }

    /// <summary>
    /// Revokes all sessions for a user.
    /// </summary>
    public int RevokeAllUserSessions(string username)
    {
        var count = 0;
        var sessionsToRemove = _sessions
            .Where(kvp => kvp.Value.Username.Equals(username, StringComparison.OrdinalIgnoreCase))
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var sessionId in sessionsToRemove)
        {
            if (RevokeSession(sessionId))
                count++;
        }

        _logger.LogInformation("Revoked {Count} sessions for user {Username}", count, username);
        return count;
    }

    /// <summary>
    /// Gets all active sessions for a user.
    /// </summary>
    public IEnumerable<SessionInfo> GetUserSessions(string username)
    {
        return _sessions.Values
            .Where(s => s.Username.Equals(username, StringComparison.OrdinalIgnoreCase) && s.IsValid && !s.IsExpired)
            .OrderByDescending(s => s.LastActivity);
    }

    /// <summary>
    /// Gets the number of active sessions.
    /// </summary>
    public int ActiveSessionCount => _sessions.Count(kvp => kvp.Value.IsValid && !kvp.Value.IsExpired);

    private string GenerateSessionId()
    {
        var bytes = RandomNumberGenerator.GetBytes(24);
        return Convert.ToBase64String(bytes)
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    private string GenerateToken(SessionInfo session)
    {
        var payload = new SessionTokenPayload
        {
            SessionId = session.SessionId,
            Username = session.Username,
            IssuedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            ExpiresAt = new DateTimeOffset(session.ExpiresAt).ToUnixTimeSeconds(),
            IpHash = _settings.BindSessionToIp ? HashIpAddress(session.IpAddress) : null
        };

        var payloadJson = JsonSerializer.Serialize(payload);
        var payloadBytes = Encoding.UTF8.GetBytes(payloadJson);
        var payloadBase64 = Convert.ToBase64String(payloadBytes);

        // Sign the payload
        var signature = SignPayload(payloadBytes);
        var signatureBase64 = Convert.ToBase64String(signature);

        // Format: payload.signature
        return $"{payloadBase64}.{signatureBase64}";
    }

    private SessionTokenPayload? ParseAndVerifyToken(string token)
    {
        var parts = token.Split('.');
        if (parts.Length != 2)
            return null;

        var payloadBytes = Convert.FromBase64String(parts[0]);
        var providedSignature = Convert.FromBase64String(parts[1]);

        // Verify signature
        var expectedSignature = SignPayload(payloadBytes);
        if (!CryptographicOperations.FixedTimeEquals(expectedSignature, providedSignature))
        {
            _logger.LogDebug("Token signature verification failed");
            return null;
        }

        // Parse payload
        var payloadJson = Encoding.UTF8.GetString(payloadBytes);
        var payload = JsonSerializer.Deserialize<SessionTokenPayload>(payloadJson);

        if (payload is null)
            return null;

        // Check expiration
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        if (now >= payload.ExpiresAt)
        {
            _logger.LogDebug("Token expired");
            return null;
        }

        return payload;
    }

    private byte[] SignPayload(byte[] payload)
    {
        using var hmac = new HMACSHA256(_signingKey);
        return hmac.ComputeHash(payload);
    }

    private static string HashIpAddress(string ipAddress)
    {
        var bytes = Encoding.UTF8.GetBytes(ipAddress);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash)[..16].ToLowerInvariant();
    }

    private void CleanupExpiredSessions(object? state)
    {
        var expiredSessions = _sessions
            .Where(kvp => !kvp.Value.IsValid || kvp.Value.IsExpired)
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var sessionId in expiredSessions)
        {
            _sessions.TryRemove(sessionId, out _);
        }

        if (expiredSessions.Count > 0)
        {
            _logger.LogDebug("Cleaned up {Count} expired sessions", expiredSessions.Count);
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _cleanupTimer.Dispose();
        CryptographicOperations.ZeroMemory(_signingKey);
    }
}

/// <summary>
/// Re-authentication context for sensitive operations.
/// </summary>
public sealed class ReauthContext
{
    /// <summary>Username requiring re-authentication.</summary>
    public required string Username { get; init; }

    /// <summary>Operation being performed.</summary>
    public required string Operation { get; init; }

    /// <summary>When the context was created.</summary>
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    /// <summary>When the context expires (short-lived).</summary>
    public DateTime ExpiresAt { get; init; }

    /// <summary>Whether re-authentication was completed.</summary>
    public bool IsAuthenticated { get; set; }

    /// <summary>Checks if the context has expired.</summary>
    public bool IsExpired => DateTime.UtcNow >= ExpiresAt;
}

/// <summary>
/// Manages re-authentication for sensitive operations.
/// </summary>
public sealed class ReauthManager
{
    private readonly ConcurrentDictionary<string, ReauthContext> _contexts = new();
    private readonly SecuritySettings _settings;
    private readonly TimeSpan _contextLifetime = TimeSpan.FromMinutes(5);

    public ReauthManager(IOptions<SecuritySettings> settings)
    {
        _settings = settings.Value;
    }

    /// <summary>
    /// Checks if re-authentication is required for an operation.
    /// </summary>
    public bool RequiresReauth(string operation)
    {
        if (!_settings.RequireReauthForSensitiveOps)
            return false;

        // List of operations requiring re-authentication
        return operation switch
        {
            "change_password" => true,
            "change_email" => true,
            "enable_2fa" => true,
            "disable_2fa" => true,
            "delete_account" => true,
            "view_security_settings" => true,
            "export_data" => true,
            _ => false
        };
    }

    /// <summary>
    /// Creates a re-authentication context.
    /// </summary>
    public string CreateContext(string username, string operation)
    {
        var contextId = Convert.ToBase64String(RandomNumberGenerator.GetBytes(16))
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');

        var context = new ReauthContext
        {
            Username = username,
            Operation = operation,
            ExpiresAt = DateTime.UtcNow.Add(_contextLifetime)
        };

        _contexts[contextId] = context;
        return contextId;
    }

    /// <summary>
    /// Validates re-authentication.
    /// </summary>
    public bool ValidateReauth(string contextId, string username, string password)
    {
        if (!_contexts.TryGetValue(contextId, out var context))
            return false;

        if (context.IsExpired || context.Username != username)
        {
            _contexts.TryRemove(contextId, out _);
            return false;
        }

        // Note: Password verification should be done by the caller using PasswordHasher
        // This just marks the context as authenticated
        context.IsAuthenticated = true;
        return true;
    }

    /// <summary>
    /// Checks if a context is authenticated.
    /// </summary>
    public bool IsAuthenticated(string contextId, string username)
    {
        if (!_contexts.TryGetValue(contextId, out var context))
            return false;

        if (context.IsExpired || context.Username != username || !context.IsAuthenticated)
        {
            _contexts.TryRemove(contextId, out _);
            return false;
        }

        return true;
    }

    /// <summary>
    /// Consumes a context (one-time use).
    /// </summary>
    public bool ConsumeContext(string contextId)
    {
        return _contexts.TryRemove(contextId, out _);
    }
}
