using System.Collections.Concurrent;
using System.Net;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Database;

namespace OpenRSC.Server.Security;

/// <summary>
/// Connection attempt tracking for an IP.
/// </summary>
public sealed class ConnectionTracker
{
    public int ConnectionCount { get; set; }
    public int FailedAttempts { get; set; }
    public long BytesReceived { get; set; }
    public long BytesSent { get; set; }
    public DateTime FirstSeen { get; set; } = DateTime.UtcNow;
    public DateTime LastSeen { get; set; } = DateTime.UtcNow;
    public DateTime WindowStart { get; set; } = DateTime.UtcNow;
    public int RequestsInWindow { get; set; }
    public int PenaltyScore { get; set; }
    public List<DateTime> RecentConnections { get; } = new();
}

/// <summary>
/// IP ban record.
/// </summary>
public sealed class IpBan
{
    public required string IpAddress { get; init; }
    public required string Reason { get; init; }
    public DateTime BannedAt { get; init; } = DateTime.UtcNow;
    public DateTime? ExpiresAt { get; init; }
    public bool IsPermanent => ExpiresAt is null;
    public int ViolationCount { get; init; }
    public string? BannedBy { get; init; }
}

/// <summary>
/// Result of a protection check.
/// </summary>
public sealed class ProtectionCheckResult
{
    public bool IsAllowed { get; init; }
    public bool IsBanned { get; init; }
    public bool IsRateLimited { get; init; }
    public bool IsSuspicious { get; init; }
    public string? BlockReason { get; init; }
    public int PenaltyScore { get; init; }
    public TimeSpan? RetryAfter { get; init; }
    public int RemainingRequests { get; init; }

    public static ProtectionCheckResult Allowed(int remaining = -1) => new()
    {
        IsAllowed = true,
        RemainingRequests = remaining
    };

    public static ProtectionCheckResult Banned(string reason, DateTime? expiresAt = null) => new()
    {
        IsAllowed = false,
        IsBanned = true,
        BlockReason = reason,
        RetryAfter = expiresAt.HasValue ? expiresAt.Value - DateTime.UtcNow : null
    };

    public static ProtectionCheckResult RateLimited(TimeSpan retryAfter, string reason) => new()
    {
        IsAllowed = false,
        IsRateLimited = true,
        BlockReason = reason,
        RetryAfter = retryAfter
    };

    public static ProtectionCheckResult Suspicious(int penaltyScore, string reason) => new()
    {
        IsAllowed = true,
        IsSuspicious = true,
        BlockReason = reason,
        PenaltyScore = penaltyScore
    };
}

/// <summary>
/// DDoS protection and rate limiting service.
/// Provides connection throttling, request limiting, and automatic IP banning.
/// </summary>
public sealed class DDoSProtectionService : IDisposable
{
    private readonly ILogger<DDoSProtectionService> _logger;
    private readonly DDoSProtectionSettings _settings;
    private readonly ISecurityAuditLogger _auditLogger;
    private readonly RedisCacheService? _redis;

    // In-memory tracking (use Redis for distributed)
    private readonly ConcurrentDictionary<string, ConnectionTracker> _ipTrackers = new();
    private readonly ConcurrentDictionary<string, IpBan> _bannedIps = new();
    private readonly HashSet<string> _whitelistedIps = new();
    private readonly HashSet<string> _whitelistedRanges = new();

    // Cleanup timer
    private readonly Timer _cleanupTimer;
    private bool _disposed;

    // Statistics
    private long _totalConnectionsBlocked;
    private long _totalRequestsBlocked;
    private long _totalIpsBanned;

    public DDoSProtectionService(
        ILogger<DDoSProtectionService> logger,
        IOptions<DDoSProtectionSettings> settings,
        ISecurityAuditLogger auditLogger,
        RedisCacheService? redis = null)
    {
        _logger = logger;
        _settings = settings.Value;
        _auditLogger = auditLogger;
        _redis = redis;

        // Parse whitelisted IPs
        if (!string.IsNullOrEmpty(_settings.WhitelistedIps))
        {
            foreach (var ip in _settings.WhitelistedIps.Split(',', StringSplitOptions.RemoveEmptyEntries))
            {
                var trimmed = ip.Trim();
                if (trimmed.Contains('/'))
                    _whitelistedRanges.Add(trimmed);
                else
                    _whitelistedIps.Add(trimmed);
            }
        }

        // Always whitelist localhost
        _whitelistedIps.Add("127.0.0.1");
        _whitelistedIps.Add("::1");

        // Start cleanup timer
        _cleanupTimer = new Timer(
            CleanupExpiredEntries,
            null,
            TimeSpan.FromMinutes(1),
            TimeSpan.FromMinutes(1));

        _logger.LogInformation("DDoS protection initialized - " +
            "Max {MaxConn}/IP, {MaxReq} req/sec, ban after {Violations} violations",
            _settings.MaxConnectionsPerIp,
            _settings.MaxRequestsPerSecond,
            _settings.ViolationsBeforeBan);
    }

    /// <summary>
    /// Checks if a new connection should be allowed.
    /// </summary>
    public async Task<ProtectionCheckResult> CheckConnectionAsync(string ipAddress)
    {
        if (!_settings.Enabled)
            return ProtectionCheckResult.Allowed();

        // Check whitelist
        if (IsWhitelisted(ipAddress))
            return ProtectionCheckResult.Allowed();

        // Check if banned
        var banCheck = await CheckBanAsync(ipAddress);
        if (!banCheck.IsAllowed)
            return banCheck;

        var tracker = GetOrCreateTracker(ipAddress);
        var now = DateTime.UtcNow;

        lock (tracker)
        {
            // Clean old connection records
            tracker.RecentConnections.RemoveAll(t => (now - t).TotalSeconds > _settings.ConnectionWindowSeconds);

            // Check connection rate
            if (tracker.RecentConnections.Count >= _settings.MaxConnectionsPerIp)
            {
                tracker.PenaltyScore += _settings.ConnectionViolationPenalty;
                Interlocked.Increment(ref _totalConnectionsBlocked);

                // Check if should ban
                if (tracker.PenaltyScore >= _settings.PenaltyThresholdForBan)
                {
                    _ = BanIpAsync(ipAddress,
                        $"Connection flood: {tracker.RecentConnections.Count} connections in {_settings.ConnectionWindowSeconds}s",
                        TimeSpan.FromMinutes(_settings.AutoBanDurationMinutes));
                }

                var retryAfter = TimeSpan.FromSeconds(_settings.ConnectionWindowSeconds);
                _logger.LogWarning("Connection rate limit exceeded for {IP}: {Count}/{Max}",
                    ipAddress, tracker.RecentConnections.Count, _settings.MaxConnectionsPerIp);

                return ProtectionCheckResult.RateLimited(retryAfter,
                    $"Too many connections. Max {_settings.MaxConnectionsPerIp} per {_settings.ConnectionWindowSeconds} seconds.");
            }

            // Record connection
            tracker.RecentConnections.Add(now);
            tracker.ConnectionCount++;
            tracker.LastSeen = now;
        }

        // Suspicious if approaching limit
        if (tracker.RecentConnections.Count > _settings.MaxConnectionsPerIp * 0.8)
        {
            return ProtectionCheckResult.Suspicious(tracker.PenaltyScore,
                "High connection rate");
        }

        return ProtectionCheckResult.Allowed(_settings.MaxConnectionsPerIp - tracker.RecentConnections.Count);
    }

    /// <summary>
    /// Checks if a request should be allowed (call per packet/message).
    /// </summary>
    public async Task<ProtectionCheckResult> CheckRequestAsync(string ipAddress, int payloadSize = 0)
    {
        if (!_settings.Enabled)
            return ProtectionCheckResult.Allowed();

        if (IsWhitelisted(ipAddress))
            return ProtectionCheckResult.Allowed();

        // Check if banned
        var banCheck = await CheckBanAsync(ipAddress);
        if (!banCheck.IsAllowed)
            return banCheck;

        var tracker = GetOrCreateTracker(ipAddress);
        var now = DateTime.UtcNow;

        lock (tracker)
        {
            // Reset window if expired
            if ((now - tracker.WindowStart).TotalSeconds >= 1)
            {
                tracker.WindowStart = now;
                tracker.RequestsInWindow = 0;
            }

            tracker.RequestsInWindow++;
            tracker.BytesReceived += payloadSize;
            tracker.LastSeen = now;

            // Check request rate
            if (tracker.RequestsInWindow > _settings.MaxRequestsPerSecond)
            {
                tracker.PenaltyScore += _settings.RequestViolationPenalty;
                Interlocked.Increment(ref _totalRequestsBlocked);

                if (tracker.PenaltyScore >= _settings.PenaltyThresholdForBan)
                {
                    _ = BanIpAsync(ipAddress,
                        $"Request flood: {tracker.RequestsInWindow} req/sec",
                        TimeSpan.FromMinutes(_settings.AutoBanDurationMinutes));
                }

                return ProtectionCheckResult.RateLimited(TimeSpan.FromSeconds(1),
                    $"Too many requests. Max {_settings.MaxRequestsPerSecond} per second.");
            }

            // Check bandwidth
            if (_settings.MaxBytesPerSecond > 0)
            {
                var bytesPerSecond = tracker.BytesReceived / Math.Max(1, (now - tracker.FirstSeen).TotalSeconds);
                if (bytesPerSecond > _settings.MaxBytesPerSecond)
                {
                    tracker.PenaltyScore += _settings.BandwidthViolationPenalty;

                    if (tracker.PenaltyScore >= _settings.PenaltyThresholdForBan)
                    {
                        _ = BanIpAsync(ipAddress,
                            $"Bandwidth abuse: {bytesPerSecond:N0} bytes/sec",
                            TimeSpan.FromMinutes(_settings.AutoBanDurationMinutes));
                    }

                    return ProtectionCheckResult.RateLimited(TimeSpan.FromSeconds(5),
                        "Bandwidth limit exceeded.");
                }
            }
        }

        return ProtectionCheckResult.Allowed(_settings.MaxRequestsPerSecond - tracker.RequestsInWindow);
    }

    /// <summary>
    /// Records a failed authentication attempt.
    /// </summary>
    public async Task RecordFailedAuthAsync(string ipAddress, string? username = null)
    {
        if (!_settings.Enabled || IsWhitelisted(ipAddress))
            return;

        var tracker = GetOrCreateTracker(ipAddress);

        lock (tracker)
        {
            tracker.FailedAttempts++;
            tracker.PenaltyScore += _settings.FailedAuthPenalty;
        }

        _logger.LogWarning("Failed auth from {IP} for user {User} - total failures: {Count}, penalty: {Penalty}",
            ipAddress, username ?? "unknown", tracker.FailedAttempts, tracker.PenaltyScore);

        // Auto-ban after too many failures
        if (tracker.FailedAttempts >= _settings.MaxFailedAuthAttempts)
        {
            await BanIpAsync(ipAddress,
                $"Too many failed authentication attempts ({tracker.FailedAttempts})",
                TimeSpan.FromMinutes(_settings.AuthBanDurationMinutes));
        }

        // Also use Redis rate limiting if available
        if (_redis?.IsConnected == true)
        {
            var key = $"auth_fail:{ipAddress}";
            var allowed = await _redis.CheckRateLimitAsync(key,
                _settings.MaxFailedAuthAttempts,
                TimeSpan.FromMinutes(15));

            if (!allowed)
            {
                await BanIpAsync(ipAddress,
                    "Authentication rate limit exceeded",
                    TimeSpan.FromMinutes(_settings.AuthBanDurationMinutes));
            }
        }
    }

    /// <summary>
    /// Records a successful authentication (reduces penalty).
    /// </summary>
    public void RecordSuccessfulAuth(string ipAddress)
    {
        if (!_settings.Enabled)
            return;

        var tracker = GetOrCreateTracker(ipAddress);

        lock (tracker)
        {
            tracker.FailedAttempts = 0;
            tracker.PenaltyScore = Math.Max(0, tracker.PenaltyScore - _settings.SuccessfulAuthBonus);
        }
    }

    /// <summary>
    /// Checks if an IP is banned.
    /// </summary>
    public async Task<ProtectionCheckResult> CheckBanAsync(string ipAddress)
    {
        // Check local cache
        if (_bannedIps.TryGetValue(ipAddress, out var ban))
        {
            if (ban.IsPermanent || ban.ExpiresAt > DateTime.UtcNow)
            {
                return ProtectionCheckResult.Banned(ban.Reason, ban.ExpiresAt);
            }

            // Ban expired, remove it
            _bannedIps.TryRemove(ipAddress, out _);
        }

        // Check Redis
        if (_redis?.IsConnected == true)
        {
            ban = await _redis.GetAsync<IpBan>($"ban:{ipAddress}");
            if (ban is not null)
            {
                if (ban.IsPermanent || ban.ExpiresAt > DateTime.UtcNow)
                {
                    _bannedIps[ipAddress] = ban; // Cache locally
                    return ProtectionCheckResult.Banned(ban.Reason, ban.ExpiresAt);
                }
            }
        }

        return ProtectionCheckResult.Allowed();
    }

    /// <summary>
    /// Bans an IP address.
    /// </summary>
    public async Task BanIpAsync(string ipAddress, string reason, TimeSpan? duration = null, string? bannedBy = null)
    {
        if (IsWhitelisted(ipAddress))
        {
            _logger.LogWarning("Attempted to ban whitelisted IP {IP}", ipAddress);
            return;
        }

        var existingViolations = 0;
        if (_bannedIps.TryGetValue(ipAddress, out var existingBan))
        {
            existingViolations = existingBan.ViolationCount;
        }

        var ban = new IpBan
        {
            IpAddress = ipAddress,
            Reason = reason,
            ExpiresAt = duration.HasValue ? DateTime.UtcNow.Add(duration.Value) : null,
            ViolationCount = existingViolations + 1,
            BannedBy = bannedBy ?? "DDoS Protection"
        };

        // Progressive ban duration for repeat offenders
        if (ban.ViolationCount > 1 && duration.HasValue)
        {
            var multiplier = Math.Min(ban.ViolationCount, 10);
            ban = ban with { ExpiresAt = DateTime.UtcNow.Add(duration.Value * multiplier) };
        }

        _bannedIps[ipAddress] = ban;
        Interlocked.Increment(ref _totalIpsBanned);

        // Store in Redis for distributed banning
        if (_redis?.IsConnected == true)
        {
            var ttl = ban.ExpiresAt.HasValue
                ? ban.ExpiresAt.Value - DateTime.UtcNow
                : TimeSpan.FromDays(365);
            await _redis.SetAsync($"ban:{ipAddress}", ban, ttl);
        }

        _auditLogger.Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.SuspiciousActivity,
            Severity = SecurityEventSeverity.Warning,
            IpAddress = ipAddress,
            Success = true,
            Message = $"IP banned: {reason}",
            Details = new Dictionary<string, object>
            {
                ["duration"] = duration?.ToString() ?? "permanent",
                ["violationCount"] = ban.ViolationCount,
                ["bannedBy"] = ban.BannedBy ?? "system"
            }
        });

        _logger.LogWarning("Banned IP {IP} for {Duration}: {Reason} (violation #{Count})",
            ipAddress,
            duration?.ToString() ?? "permanent",
            reason,
            ban.ViolationCount);
    }

    /// <summary>
    /// Unbans an IP address.
    /// </summary>
    public async Task<bool> UnbanIpAsync(string ipAddress)
    {
        var removed = _bannedIps.TryRemove(ipAddress, out _);

        if (_redis?.IsConnected == true)
        {
            await _redis.DeleteAsync($"ban:{ipAddress}");
        }

        if (removed)
        {
            _logger.LogInformation("Unbanned IP {IP}", ipAddress);
        }

        return removed;
    }

    /// <summary>
    /// Gets all currently banned IPs.
    /// </summary>
    public IReadOnlyList<IpBan> GetBannedIps()
    {
        return _bannedIps.Values
            .Where(b => b.IsPermanent || b.ExpiresAt > DateTime.UtcNow)
            .OrderByDescending(b => b.BannedAt)
            .ToList();
    }

    /// <summary>
    /// Adds an IP to the whitelist.
    /// </summary>
    public void WhitelistIp(string ipAddress)
    {
        _whitelistedIps.Add(ipAddress);
        _bannedIps.TryRemove(ipAddress, out _);
        _logger.LogInformation("Whitelisted IP {IP}", ipAddress);
    }

    /// <summary>
    /// Removes an IP from the whitelist.
    /// </summary>
    public void RemoveFromWhitelist(string ipAddress)
    {
        _whitelistedIps.Remove(ipAddress);
        _logger.LogInformation("Removed IP {IP} from whitelist", ipAddress);
    }

    /// <summary>
    /// Records a connection disconnect.
    /// </summary>
    public void RecordDisconnect(string ipAddress)
    {
        if (_ipTrackers.TryGetValue(ipAddress, out var tracker))
        {
            lock (tracker)
            {
                tracker.ConnectionCount = Math.Max(0, tracker.ConnectionCount - 1);
            }
        }
    }

    /// <summary>
    /// Gets protection statistics.
    /// </summary>
    public (long ConnectionsBlocked, long RequestsBlocked, long IpsBanned, int ActiveTrackers, int ActiveBans) GetStatistics()
    {
        return (
            _totalConnectionsBlocked,
            _totalRequestsBlocked,
            _totalIpsBanned,
            _ipTrackers.Count,
            _bannedIps.Count(b => b.Value.IsPermanent || b.Value.ExpiresAt > DateTime.UtcNow)
        );
    }

    #region Private Methods

    private bool IsWhitelisted(string ipAddress)
    {
        if (_whitelistedIps.Contains(ipAddress))
            return true;

        // Check CIDR ranges
        if (_whitelistedRanges.Count > 0 && IPAddress.TryParse(ipAddress, out var ip))
        {
            foreach (var range in _whitelistedRanges)
            {
                if (IsInCidrRange(ip, range))
                    return true;
            }
        }

        return false;
    }

    private static bool IsInCidrRange(IPAddress ip, string cidr)
    {
        try
        {
            var parts = cidr.Split('/');
            if (parts.Length != 2)
                return false;

            if (!IPAddress.TryParse(parts[0], out var networkAddress))
                return false;

            if (!int.TryParse(parts[1], out var prefixLength))
                return false;

            var ipBytes = ip.GetAddressBytes();
            var networkBytes = networkAddress.GetAddressBytes();

            if (ipBytes.Length != networkBytes.Length)
                return false;

            var bytesToCheck = prefixLength / 8;
            var remainingBits = prefixLength % 8;

            for (var i = 0; i < bytesToCheck; i++)
            {
                if (ipBytes[i] != networkBytes[i])
                    return false;
            }

            if (remainingBits > 0 && bytesToCheck < ipBytes.Length)
            {
                var mask = (byte)(0xFF << (8 - remainingBits));
                if ((ipBytes[bytesToCheck] & mask) != (networkBytes[bytesToCheck] & mask))
                    return false;
            }

            return true;
        }
        catch
        {
            return false;
        }
    }

    private ConnectionTracker GetOrCreateTracker(string ipAddress)
    {
        return _ipTrackers.GetOrAdd(ipAddress, _ => new ConnectionTracker());
    }

    private void CleanupExpiredEntries(object? state)
    {
        var now = DateTime.UtcNow;
        var expiredTrackers = new List<string>();
        var expiredBans = new List<string>();

        // Clean old trackers
        foreach (var (ip, tracker) in _ipTrackers)
        {
            if ((now - tracker.LastSeen).TotalMinutes > _settings.TrackerExpirationMinutes)
            {
                expiredTrackers.Add(ip);
            }
        }

        foreach (var ip in expiredTrackers)
        {
            _ipTrackers.TryRemove(ip, out _);
        }

        // Clean expired bans
        foreach (var (ip, ban) in _bannedIps)
        {
            if (!ban.IsPermanent && ban.ExpiresAt <= now)
            {
                expiredBans.Add(ip);
            }
        }

        foreach (var ip in expiredBans)
        {
            _bannedIps.TryRemove(ip, out _);
        }

        if (expiredTrackers.Count > 0 || expiredBans.Count > 0)
        {
            _logger.LogDebug("Cleaned up {Trackers} expired trackers and {Bans} expired bans",
                expiredTrackers.Count, expiredBans.Count);
        }
    }

    #endregion

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _cleanupTimer.Dispose();
    }
}
