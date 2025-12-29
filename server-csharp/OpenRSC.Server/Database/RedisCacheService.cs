using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using StackExchange.Redis;

namespace OpenRSC.Server.Database;

/// <summary>
/// Redis cache service for high-performance caching.
/// Used for sessions, leaderboards, rate limiting, and player data caching.
/// </summary>
public sealed class RedisCacheService : IAsyncDisposable
{
    private readonly ILogger<RedisCacheService> _logger;
    private readonly RedisSettings _settings;
    private readonly ConnectionMultiplexer? _redis;
    private readonly IDatabase? _db;
    private bool _disposed;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public RedisCacheService(
        ILogger<RedisCacheService> logger,
        IOptions<RedisSettings> settings)
    {
        _logger = logger;
        _settings = settings.Value;

        if (!_settings.Enabled)
        {
            _logger.LogInformation("Redis caching is disabled");
            return;
        }

        try
        {
            var config = ConfigurationOptions.Parse(_settings.ConnectionString);
            config.DefaultDatabase = _settings.Database;
            config.AbortOnConnectFail = false;
            config.ConnectRetry = 3;
            config.ConnectTimeout = 5000;

            if (!string.IsNullOrEmpty(_settings.Password))
            {
                config.Password = _settings.Password;
            }

            _redis = ConnectionMultiplexer.Connect(config);
            _db = _redis.GetDatabase();

            _logger.LogInformation("Connected to Redis at {Endpoint}", _settings.ConnectionString);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to connect to Redis - caching will be disabled");
        }
    }

    /// <summary>
    /// Whether Redis is available and connected.
    /// </summary>
    public bool IsConnected => _redis?.IsConnected ?? false;

    #region Basic Operations

    /// <summary>
    /// Gets a value from cache.
    /// </summary>
    public async Task<T?> GetAsync<T>(string key)
    {
        if (_db is null) return default;

        try
        {
            var value = await _db.StringGetAsync(PrefixKey(key));
            if (value.IsNullOrEmpty)
                return default;

            return JsonSerializer.Deserialize<T>(value!, JsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis GET failed for key {Key}", key);
            return default;
        }
    }

    /// <summary>
    /// Sets a value in cache with optional expiration.
    /// </summary>
    public async Task<bool> SetAsync<T>(string key, T value, TimeSpan? expiration = null)
    {
        if (_db is null) return false;

        try
        {
            var json = JsonSerializer.Serialize(value, JsonOptions);
            var exp = expiration ?? TimeSpan.FromSeconds(_settings.DefaultExpirationSeconds);
            return await _db.StringSetAsync(PrefixKey(key), json, exp);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis SET failed for key {Key}", key);
            return false;
        }
    }

    /// <summary>
    /// Deletes a key from cache.
    /// </summary>
    public async Task<bool> DeleteAsync(string key)
    {
        if (_db is null) return false;

        try
        {
            return await _db.KeyDeleteAsync(PrefixKey(key));
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis DELETE failed for key {Key}", key);
            return false;
        }
    }

    /// <summary>
    /// Checks if a key exists.
    /// </summary>
    public async Task<bool> ExistsAsync(string key)
    {
        if (_db is null) return false;

        try
        {
            return await _db.KeyExistsAsync(PrefixKey(key));
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis EXISTS failed for key {Key}", key);
            return false;
        }
    }

    /// <summary>
    /// Sets expiration on a key.
    /// </summary>
    public async Task<bool> ExpireAsync(string key, TimeSpan expiration)
    {
        if (_db is null) return false;

        try
        {
            return await _db.KeyExpireAsync(PrefixKey(key), expiration);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis EXPIRE failed for key {Key}", key);
            return false;
        }
    }

    #endregion

    #region Player Cache

    /// <summary>
    /// Caches player data for quick access.
    /// </summary>
    public Task<bool> CachePlayerAsync(string username, object playerData)
    {
        return SetAsync($"player:{username.ToLowerInvariant()}", playerData,
            TimeSpan.FromMinutes(30));
    }

    /// <summary>
    /// Gets cached player data.
    /// </summary>
    public Task<T?> GetCachedPlayerAsync<T>(string username)
    {
        return GetAsync<T>($"player:{username.ToLowerInvariant()}");
    }

    /// <summary>
    /// Invalidates player cache.
    /// </summary>
    public Task<bool> InvalidatePlayerCacheAsync(string username)
    {
        return DeleteAsync($"player:{username.ToLowerInvariant()}");
    }

    #endregion

    #region Session Management

    /// <summary>
    /// Stores a session in Redis.
    /// </summary>
    public Task<bool> SetSessionAsync(string sessionId, object sessionData)
    {
        return SetAsync($"session:{sessionId}", sessionData,
            TimeSpan.FromSeconds(_settings.SessionExpirationSeconds));
    }

    /// <summary>
    /// Gets a session from Redis.
    /// </summary>
    public Task<T?> GetSessionAsync<T>(string sessionId)
    {
        return GetAsync<T>($"session:{sessionId}");
    }

    /// <summary>
    /// Deletes a session.
    /// </summary>
    public Task<bool> DeleteSessionAsync(string sessionId)
    {
        return DeleteAsync($"session:{sessionId}");
    }

    /// <summary>
    /// Refreshes session expiration.
    /// </summary>
    public Task<bool> RefreshSessionAsync(string sessionId)
    {
        return ExpireAsync($"session:{sessionId}",
            TimeSpan.FromSeconds(_settings.SessionExpirationSeconds));
    }

    #endregion

    #region Leaderboards

    /// <summary>
    /// Updates a player's score in a leaderboard.
    /// </summary>
    public async Task<bool> UpdateLeaderboardAsync(string leaderboard, string username, double score)
    {
        if (_db is null) return false;

        try
        {
            await _db.SortedSetAddAsync(PrefixKey($"leaderboard:{leaderboard}"), username, score);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis ZADD failed for leaderboard {Leaderboard}", leaderboard);
            return false;
        }
    }

    /// <summary>
    /// Gets the top players from a leaderboard.
    /// </summary>
    public async Task<List<(string Username, double Score)>> GetLeaderboardAsync(string leaderboard, int count = 10)
    {
        if (_db is null) return [];

        try
        {
            var entries = await _db.SortedSetRangeByRankWithScoresAsync(
                PrefixKey($"leaderboard:{leaderboard}"),
                0, count - 1,
                Order.Descending);

            return entries.Select(e => (e.Element.ToString(), e.Score)).ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis ZRANGE failed for leaderboard {Leaderboard}", leaderboard);
            return [];
        }
    }

    /// <summary>
    /// Gets a player's rank in a leaderboard.
    /// </summary>
    public async Task<long?> GetLeaderboardRankAsync(string leaderboard, string username)
    {
        if (_db is null) return null;

        try
        {
            var rank = await _db.SortedSetRankAsync(
                PrefixKey($"leaderboard:{leaderboard}"),
                username,
                Order.Descending);

            return rank.HasValue ? rank.Value + 1 : null; // 1-indexed
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis ZRANK failed for leaderboard {Leaderboard}", leaderboard);
            return null;
        }
    }

    #endregion

    #region Rate Limiting

    /// <summary>
    /// Checks and increments a rate limit counter.
    /// Returns true if under limit, false if rate limited.
    /// </summary>
    public async Task<bool> CheckRateLimitAsync(string key, int maxRequests, TimeSpan window)
    {
        if (_db is null) return true; // Allow if Redis unavailable

        try
        {
            var fullKey = PrefixKey($"ratelimit:{key}");
            var current = await _db.StringIncrementAsync(fullKey);

            if (current == 1)
            {
                await _db.KeyExpireAsync(fullKey, window);
            }

            return current <= maxRequests;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis rate limit check failed for {Key}", key);
            return true; // Allow on error
        }
    }

    /// <summary>
    /// Gets remaining rate limit quota.
    /// </summary>
    public async Task<int> GetRateLimitRemainingAsync(string key, int maxRequests)
    {
        if (_db is null) return maxRequests;

        try
        {
            var value = await _db.StringGetAsync(PrefixKey($"ratelimit:{key}"));
            if (value.IsNullOrEmpty)
                return maxRequests;

            var current = (int)value;
            return Math.Max(0, maxRequests - current);
        }
        catch
        {
            return maxRequests;
        }
    }

    #endregion

    #region Online Players

    /// <summary>
    /// Adds a player to the online set.
    /// </summary>
    public async Task<bool> SetPlayerOnlineAsync(string username, string serverId)
    {
        if (_db is null) return false;

        try
        {
            await _db.SetAddAsync(PrefixKey("online:all"), username);
            await _db.HashSetAsync(PrefixKey("online:servers"), username, serverId);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis failed to set player online: {Username}", username);
            return false;
        }
    }

    /// <summary>
    /// Removes a player from the online set.
    /// </summary>
    public async Task<bool> SetPlayerOfflineAsync(string username)
    {
        if (_db is null) return false;

        try
        {
            await _db.SetRemoveAsync(PrefixKey("online:all"), username);
            await _db.HashDeleteAsync(PrefixKey("online:servers"), username);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis failed to set player offline: {Username}", username);
            return false;
        }
    }

    /// <summary>
    /// Checks if a player is online.
    /// </summary>
    public async Task<bool> IsPlayerOnlineAsync(string username)
    {
        if (_db is null) return false;

        try
        {
            return await _db.SetContainsAsync(PrefixKey("online:all"), username);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Gets the count of online players.
    /// </summary>
    public async Task<long> GetOnlineCountAsync()
    {
        if (_db is null) return 0;

        try
        {
            return await _db.SetLengthAsync(PrefixKey("online:all"));
        }
        catch
        {
            return 0;
        }
    }

    /// <summary>
    /// Gets which server a player is on.
    /// </summary>
    public async Task<string?> GetPlayerServerAsync(string username)
    {
        if (_db is null) return null;

        try
        {
            var value = await _db.HashGetAsync(PrefixKey("online:servers"), username);
            return value.IsNullOrEmpty ? null : value.ToString();
        }
        catch
        {
            return null;
        }
    }

    #endregion

    #region Pub/Sub

    /// <summary>
    /// Publishes a message to a channel.
    /// </summary>
    public async Task<long> PublishAsync(string channel, string message)
    {
        if (_redis is null) return 0;

        try
        {
            var sub = _redis.GetSubscriber();
            return await sub.PublishAsync(RedisChannel.Literal(PrefixKey(channel)), message);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis PUBLISH failed for channel {Channel}", channel);
            return 0;
        }
    }

    /// <summary>
    /// Subscribes to a channel.
    /// </summary>
    public async Task SubscribeAsync(string channel, Action<string, string> handler)
    {
        if (_redis is null) return;

        try
        {
            var sub = _redis.GetSubscriber();
            await sub.SubscribeAsync(RedisChannel.Literal(PrefixKey(channel)), (ch, msg) =>
            {
                handler(ch.ToString(), msg.ToString());
            });

            _logger.LogDebug("Subscribed to Redis channel: {Channel}", channel);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis SUBSCRIBE failed for channel {Channel}", channel);
        }
    }

    #endregion

    private string PrefixKey(string key) => $"{_settings.KeyPrefix}{key}";

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;

        if (_redis is not null)
        {
            await _redis.CloseAsync();
            _redis.Dispose();
        }
    }
}
