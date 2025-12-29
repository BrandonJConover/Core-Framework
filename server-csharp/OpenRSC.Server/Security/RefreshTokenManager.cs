using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Database;

namespace OpenRSC.Server.Security;

/// <summary>
/// Refresh token data.
/// </summary>
public sealed class RefreshToken
{
    /// <summary>Unique token identifier.</summary>
    public required string TokenId { get; init; }

    /// <summary>The actual token value (hashed in storage).</summary>
    public required string TokenHash { get; init; }

    /// <summary>Associated username.</summary>
    public required string Username { get; init; }

    /// <summary>Device identifier for token binding.</summary>
    public string? DeviceId { get; init; }

    /// <summary>Device name for display.</summary>
    public string? DeviceName { get; init; }

    /// <summary>Platform (iOS, Android, Web).</summary>
    public string? Platform { get; init; }

    /// <summary>IP address that created the token.</summary>
    public string? IpAddress { get; init; }

    /// <summary>When the token was created.</summary>
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    /// <summary>When the token expires.</summary>
    public DateTime ExpiresAt { get; init; }

    /// <summary>When the token was last used.</summary>
    public DateTime LastUsedAt { get; set; } = DateTime.UtcNow;

    /// <summary>Whether the token has been revoked.</summary>
    public bool IsRevoked { get; set; }

    /// <summary>Reason for revocation.</summary>
    public string? RevokedReason { get; set; }

    /// <summary>When the token was revoked.</summary>
    public DateTime? RevokedAt { get; set; }

    /// <summary>Token that replaced this one (for rotation).</summary>
    public string? ReplacedByTokenId { get; set; }
}

/// <summary>
/// Access token response for clients.
/// </summary>
public sealed class TokenResponse
{
    /// <summary>Access token for API calls.</summary>
    public required string AccessToken { get; init; }

    /// <summary>Token type (always "Bearer").</summary>
    public string TokenType { get; init; } = "Bearer";

    /// <summary>Access token expiration in seconds.</summary>
    public int ExpiresIn { get; init; }

    /// <summary>Refresh token for getting new access tokens.</summary>
    public string? RefreshToken { get; init; }

    /// <summary>Refresh token expiration timestamp (Unix seconds).</summary>
    public long? RefreshTokenExpiresAt { get; init; }

    /// <summary>Username associated with the tokens.</summary>
    public string? Username { get; init; }

    /// <summary>Session ID for the connection.</summary>
    public string? SessionId { get; init; }
}

/// <summary>
/// Manages refresh tokens for persistent authentication.
/// Supports secure storage in iOS Keychain / Android Keystore.
/// </summary>
public sealed class RefreshTokenManager : IDisposable
{
    private readonly ILogger<RefreshTokenManager> _logger;
    private readonly AuthTokenSettings _settings;
    private readonly SecuritySettings _securitySettings;
    private readonly SessionTokenManager _sessionManager;
    private readonly RedisCacheService? _redis;

    // In-memory storage (use Redis in production)
    private readonly ConcurrentDictionary<string, RefreshToken> _tokens = new();
    private readonly ConcurrentDictionary<string, HashSet<string>> _userTokens = new();

    private readonly byte[] _signingKey;
    private readonly Timer _cleanupTimer;
    private bool _disposed;

    public RefreshTokenManager(
        ILogger<RefreshTokenManager> logger,
        IOptions<AuthTokenSettings> settings,
        IOptions<SecuritySettings> securitySettings,
        SessionTokenManager sessionManager,
        RedisCacheService? redis = null)
    {
        _logger = logger;
        _settings = settings.Value;
        _securitySettings = securitySettings.Value;
        _sessionManager = sessionManager;
        _redis = redis;

        // Derive signing key
        _signingKey = DeriveSigningKey();

        // Start cleanup timer
        _cleanupTimer = new Timer(
            CleanupExpiredTokens,
            null,
            TimeSpan.FromHours(1),
            TimeSpan.FromHours(1));
    }

    private byte[] DeriveSigningKey()
    {
        if (!string.IsNullOrEmpty(_securitySettings.MasterEncryptionKey))
        {
            var masterKey = Convert.FromBase64String(_securitySettings.MasterEncryptionKey);
            using var hmac = new HMACSHA256(masterKey);
            return hmac.ComputeHash(Encoding.UTF8.GetBytes("refresh-token-signing"));
        }

        _logger.LogWarning("No master key configured - using ephemeral refresh token signing key");
        return RandomNumberGenerator.GetBytes(32);
    }

    /// <summary>
    /// Creates a new token pair (access + refresh) for a user.
    /// </summary>
    public async Task<TokenResponse> CreateTokenPairAsync(
        string username,
        string? deviceId = null,
        string? deviceName = null,
        string? platform = null,
        string? ipAddress = null)
    {
        // Create session (access token)
        var sessionToken = _sessionManager.CreateSession(username, ipAddress ?? "unknown");

        if (!_settings.EnableRefreshTokens)
        {
            return new TokenResponse
            {
                AccessToken = sessionToken,
                ExpiresIn = _settings.AccessTokenLifetimeMinutes * 60,
                Username = username
            };
        }

        // Generate refresh token
        var refreshTokenValue = GenerateRefreshToken();
        var tokenId = GenerateTokenId();
        var tokenHash = HashToken(refreshTokenValue);

        var refreshToken = new RefreshToken
        {
            TokenId = tokenId,
            TokenHash = tokenHash,
            Username = username,
            DeviceId = deviceId,
            DeviceName = deviceName,
            Platform = platform,
            IpAddress = ipAddress,
            ExpiresAt = DateTime.UtcNow.AddDays(_settings.RefreshTokenLifetimeDays)
        };

        // Store token
        await StoreRefreshTokenAsync(refreshToken);

        // Enforce max tokens per user
        await EnforceMaxTokensAsync(username);

        _logger.LogDebug("Created token pair for {Username} on {Platform}", username, platform ?? "unknown");

        return new TokenResponse
        {
            AccessToken = sessionToken,
            ExpiresIn = _settings.AccessTokenLifetimeMinutes * 60,
            RefreshToken = $"{tokenId}.{refreshTokenValue}",
            RefreshTokenExpiresAt = new DateTimeOffset(refreshToken.ExpiresAt).ToUnixTimeSeconds(),
            Username = username
        };
    }

    /// <summary>
    /// Refreshes an access token using a refresh token.
    /// </summary>
    public async Task<TokenResponse?> RefreshAccessTokenAsync(
        string refreshToken,
        string? ipAddress = null)
    {
        if (!_settings.EnableRefreshTokens)
            return null;

        // Parse token
        var parts = refreshToken.Split('.');
        if (parts.Length != 2)
        {
            _logger.LogWarning("Invalid refresh token format");
            return null;
        }

        var tokenId = parts[0];
        var tokenValue = parts[1];
        var tokenHash = HashToken(tokenValue);

        // Retrieve token
        var storedToken = await GetRefreshTokenAsync(tokenId);
        if (storedToken is null)
        {
            _logger.LogWarning("Refresh token not found: {TokenId}", tokenId);
            return null;
        }

        // Validate token
        if (storedToken.IsRevoked)
        {
            _logger.LogWarning("Attempted use of revoked refresh token: {TokenId}", tokenId);

            // Possible token theft - revoke all user tokens
            if (storedToken.ReplacedByTokenId != null)
            {
                _logger.LogWarning("Detected reuse of rotated token - revoking all tokens for {Username}",
                    storedToken.Username);
                await RevokeAllUserTokensAsync(storedToken.Username, "Suspected token theft");
            }

            return null;
        }

        if (storedToken.TokenHash != tokenHash)
        {
            _logger.LogWarning("Refresh token hash mismatch: {TokenId}", tokenId);
            return null;
        }

        if (DateTime.UtcNow >= storedToken.ExpiresAt)
        {
            _logger.LogDebug("Refresh token expired: {TokenId}", tokenId);
            await RevokeRefreshTokenAsync(tokenId, "Expired");
            return null;
        }

        // Create new access token
        var newSessionToken = _sessionManager.CreateSession(storedToken.Username, ipAddress ?? "unknown");

        TokenResponse response;

        if (_settings.RotateRefreshTokens)
        {
            // Rotate: create new refresh token and revoke old one
            var newTokenValue = GenerateRefreshToken();
            var newTokenId = GenerateTokenId();
            var newTokenHash = HashToken(newTokenValue);

            var newRefreshToken = new RefreshToken
            {
                TokenId = newTokenId,
                TokenHash = newTokenHash,
                Username = storedToken.Username,
                DeviceId = storedToken.DeviceId,
                DeviceName = storedToken.DeviceName,
                Platform = storedToken.Platform,
                IpAddress = ipAddress ?? storedToken.IpAddress,
                ExpiresAt = DateTime.UtcNow.AddDays(_settings.RefreshTokenLifetimeDays)
            };

            // Mark old token as replaced
            storedToken.IsRevoked = true;
            storedToken.RevokedAt = DateTime.UtcNow;
            storedToken.RevokedReason = "Rotated";
            storedToken.ReplacedByTokenId = newTokenId;
            await UpdateRefreshTokenAsync(storedToken);

            // Store new token
            await StoreRefreshTokenAsync(newRefreshToken);

            response = new TokenResponse
            {
                AccessToken = newSessionToken,
                ExpiresIn = _settings.AccessTokenLifetimeMinutes * 60,
                RefreshToken = $"{newTokenId}.{newTokenValue}",
                RefreshTokenExpiresAt = new DateTimeOffset(newRefreshToken.ExpiresAt).ToUnixTimeSeconds(),
                Username = storedToken.Username
            };

            _logger.LogDebug("Rotated refresh token for {Username}", storedToken.Username);
        }
        else
        {
            // Update last used
            storedToken.LastUsedAt = DateTime.UtcNow;
            await UpdateRefreshTokenAsync(storedToken);

            response = new TokenResponse
            {
                AccessToken = newSessionToken,
                ExpiresIn = _settings.AccessTokenLifetimeMinutes * 60,
                RefreshToken = refreshToken, // Return same token
                RefreshTokenExpiresAt = new DateTimeOffset(storedToken.ExpiresAt).ToUnixTimeSeconds(),
                Username = storedToken.Username
            };
        }

        return response;
    }

    /// <summary>
    /// Revokes a specific refresh token.
    /// </summary>
    public async Task<bool> RevokeRefreshTokenAsync(string tokenId, string? reason = null)
    {
        var token = await GetRefreshTokenAsync(tokenId);
        if (token is null)
            return false;

        token.IsRevoked = true;
        token.RevokedAt = DateTime.UtcNow;
        token.RevokedReason = reason ?? "User requested";

        await UpdateRefreshTokenAsync(token);

        _logger.LogInformation("Revoked refresh token {TokenId} for {Username}: {Reason}",
            tokenId, token.Username, reason);

        return true;
    }

    /// <summary>
    /// Revokes all refresh tokens for a user.
    /// </summary>
    public async Task<int> RevokeAllUserTokensAsync(string username, string? reason = null)
    {
        var count = 0;

        if (_userTokens.TryGetValue(username.ToLowerInvariant(), out var tokenIds))
        {
            foreach (var tokenId in tokenIds.ToList())
            {
                if (await RevokeRefreshTokenAsync(tokenId, reason))
                    count++;
            }
        }

        // Also revoke sessions
        _sessionManager.RevokeAllUserSessions(username);

        _logger.LogInformation("Revoked {Count} refresh tokens for {Username}", count, username);
        return count;
    }

    /// <summary>
    /// Gets all active refresh tokens for a user.
    /// </summary>
    public async Task<List<RefreshToken>> GetUserTokensAsync(string username)
    {
        var tokens = new List<RefreshToken>();

        if (_userTokens.TryGetValue(username.ToLowerInvariant(), out var tokenIds))
        {
            foreach (var tokenId in tokenIds)
            {
                var token = await GetRefreshTokenAsync(tokenId);
                if (token is not null && !token.IsRevoked && token.ExpiresAt > DateTime.UtcNow)
                {
                    tokens.Add(token);
                }
            }
        }

        return tokens.OrderByDescending(t => t.LastUsedAt).ToList();
    }

    #region Storage

    private async Task StoreRefreshTokenAsync(RefreshToken token)
    {
        var key = token.Username.ToLowerInvariant();

        _tokens[token.TokenId] = token;

        _userTokens.AddOrUpdate(
            key,
            _ => [token.TokenId],
            (_, set) => { set.Add(token.TokenId); return set; });

        // Store in Redis if available
        if (_redis?.IsConnected == true)
        {
            await _redis.SetAsync($"refresh_token:{token.TokenId}", token,
                TimeSpan.FromDays(_settings.RefreshTokenLifetimeDays + 1));
        }
    }

    private async Task<RefreshToken?> GetRefreshTokenAsync(string tokenId)
    {
        if (_tokens.TryGetValue(tokenId, out var token))
            return token;

        // Try Redis
        if (_redis?.IsConnected == true)
        {
            token = await _redis.GetAsync<RefreshToken>($"refresh_token:{tokenId}");
            if (token is not null)
            {
                _tokens[tokenId] = token;
            }
        }

        return token;
    }

    private async Task UpdateRefreshTokenAsync(RefreshToken token)
    {
        _tokens[token.TokenId] = token;

        if (_redis?.IsConnected == true)
        {
            await _redis.SetAsync($"refresh_token:{token.TokenId}", token,
                TimeSpan.FromDays(_settings.RefreshTokenLifetimeDays + 1));
        }
    }

    private async Task EnforceMaxTokensAsync(string username)
    {
        var key = username.ToLowerInvariant();

        if (!_userTokens.TryGetValue(key, out var tokenIds))
            return;

        if (tokenIds.Count <= _settings.MaxRefreshTokensPerUser)
            return;

        // Get all tokens and sort by last used
        var tokens = new List<RefreshToken>();
        foreach (var tokenId in tokenIds)
        {
            var token = await GetRefreshTokenAsync(tokenId);
            if (token is not null && !token.IsRevoked)
            {
                tokens.Add(token);
            }
        }

        // Revoke oldest tokens
        var toRevoke = tokens
            .OrderBy(t => t.LastUsedAt)
            .Take(tokens.Count - _settings.MaxRefreshTokensPerUser);

        foreach (var token in toRevoke)
        {
            await RevokeRefreshTokenAsync(token.TokenId, "Max tokens exceeded");
        }
    }

    #endregion

    #region Helpers

    private static string GenerateRefreshToken()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    private static string GenerateTokenId()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(16))
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    private string HashToken(string token)
    {
        using var hmac = new HMACSHA256(_signingKey);
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(token));
        return Convert.ToBase64String(hash);
    }

    private void CleanupExpiredTokens(object? state)
    {
        var now = DateTime.UtcNow;
        var expiredIds = _tokens
            .Where(kvp => kvp.Value.ExpiresAt < now || kvp.Value.IsRevoked)
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var tokenId in expiredIds)
        {
            if (_tokens.TryRemove(tokenId, out var token))
            {
                var key = token.Username.ToLowerInvariant();
                if (_userTokens.TryGetValue(key, out var userTokenIds))
                {
                    userTokenIds.Remove(tokenId);
                }
            }
        }

        if (expiredIds.Count > 0)
        {
            _logger.LogDebug("Cleaned up {Count} expired/revoked refresh tokens", expiredIds.Count);
        }
    }

    #endregion

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _cleanupTimer.Dispose();
        CryptographicOperations.ZeroMemory(_signingKey);
    }
}
