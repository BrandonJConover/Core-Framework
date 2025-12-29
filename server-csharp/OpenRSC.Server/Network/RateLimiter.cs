using System.Collections.Concurrent;

namespace OpenRSC.Server.Network;

/// <summary>
/// Token bucket rate limiter for packet throttling.
/// Prevents DDoS and spam attacks.
/// </summary>
public sealed class RateLimiter
{
    private readonly ConcurrentDictionary<Guid, TokenBucket> _buckets = new();
    private readonly int _tokensPerSecond;
    private readonly int _bucketSize;

    /// <summary>
    /// Creates a rate limiter with specified limits.
    /// </summary>
    /// <param name="tokensPerSecond">Refill rate (packets allowed per second).</param>
    /// <param name="bucketSize">Maximum burst capacity.</param>
    public RateLimiter(int tokensPerSecond = 100, int bucketSize = 200)
    {
        _tokensPerSecond = tokensPerSecond;
        _bucketSize = bucketSize;
    }

    /// <summary>
    /// Checks if a request is allowed for the given client.
    /// Returns true if allowed, false if rate limited.
    /// </summary>
    public bool IsAllowed(Guid clientId, int tokenCost = 1)
    {
        var bucket = _buckets.GetOrAdd(clientId, _ => new TokenBucket(_bucketSize, _tokensPerSecond));
        return bucket.TryConsume(tokenCost);
    }

    /// <summary>
    /// Gets the number of tokens remaining for a client.
    /// </summary>
    public int GetRemainingTokens(Guid clientId)
    {
        if (_buckets.TryGetValue(clientId, out var bucket))
            return bucket.AvailableTokens;

        return _bucketSize;
    }

    /// <summary>
    /// Removes a client's bucket (on disconnect).
    /// </summary>
    public void RemoveClient(Guid clientId)
    {
        _buckets.TryRemove(clientId, out _);
    }

    /// <summary>
    /// Cleans up stale buckets for disconnected clients.
    /// </summary>
    public void Cleanup(IEnumerable<Guid> activeClientIds)
    {
        var activeSet = activeClientIds.ToHashSet();
        var toRemove = _buckets.Keys.Where(id => !activeSet.Contains(id)).ToList();

        foreach (var id in toRemove)
        {
            _buckets.TryRemove(id, out _);
        }
    }

    private sealed class TokenBucket
    {
        private readonly int _maxTokens;
        private readonly double _refillRate;
        private double _tokens;
        private long _lastRefillTicks;
        private readonly Lock _lock = new();

        public TokenBucket(int maxTokens, int tokensPerSecond)
        {
            _maxTokens = maxTokens;
            _refillRate = tokensPerSecond;
            _tokens = maxTokens;
            _lastRefillTicks = DateTime.UtcNow.Ticks;
        }

        public int AvailableTokens
        {
            get
            {
                lock (_lock)
                {
                    Refill();
                    return (int)_tokens;
                }
            }
        }

        public bool TryConsume(int tokens)
        {
            lock (_lock)
            {
                Refill();

                if (_tokens >= tokens)
                {
                    _tokens -= tokens;
                    return true;
                }

                return false;
            }
        }

        private void Refill()
        {
            var now = DateTime.UtcNow.Ticks;
            var elapsedSeconds = (now - _lastRefillTicks) / (double)TimeSpan.TicksPerSecond;

            if (elapsedSeconds > 0)
            {
                _tokens = Math.Min(_maxTokens, _tokens + elapsedSeconds * _refillRate);
                _lastRefillTicks = now;
            }
        }
    }
}

/// <summary>
/// Per-opcode rate limiter for fine-grained control.
/// Different opcodes can have different rate limits.
/// </summary>
public sealed class OpcodeRateLimiter
{
    private readonly ConcurrentDictionary<(Guid ClientId, byte Opcode), DateTime> _lastRequest = new();
    private readonly Dictionary<byte, TimeSpan> _opcodeCooldowns;

    /// <summary>
    /// Default cooldown for opcodes not explicitly configured.
    /// </summary>
    public TimeSpan DefaultCooldown { get; init; } = TimeSpan.FromMilliseconds(100);

    public OpcodeRateLimiter()
    {
        // Configure specific opcode cooldowns (in milliseconds)
        _opcodeCooldowns = new Dictionary<byte, TimeSpan>
        {
            // Login/Logout - longer cooldown
            [0] = TimeSpan.FromSeconds(1),   // Login
            [1] = TimeSpan.FromSeconds(1),   // Logout

            // Chat - prevent spam
            [145] = TimeSpan.FromMilliseconds(600),  // Public chat
            [190] = TimeSpan.FromMilliseconds(600),  // Private message

            // Movement - high frequency allowed
            [255] = TimeSpan.Zero,  // Walk
            [254] = TimeSpan.Zero,  // Walk (alt)

            // Actions - moderate cooldown
            [136] = TimeSpan.FromMilliseconds(300),  // Object action
            [155] = TimeSpan.FromMilliseconds(300),  // NPC action
        };
    }

    /// <summary>
    /// Checks if an opcode is allowed for the given client.
    /// </summary>
    public bool IsAllowed(Guid clientId, byte opcode)
    {
        var key = (clientId, opcode);
        var cooldown = _opcodeCooldowns.GetValueOrDefault(opcode, DefaultCooldown);

        if (cooldown == TimeSpan.Zero)
            return true;

        var now = DateTime.UtcNow;

        if (_lastRequest.TryGetValue(key, out var lastTime))
        {
            if (now - lastTime < cooldown)
                return false;
        }

        _lastRequest[key] = now;
        return true;
    }

    /// <summary>
    /// Removes a client's rate limit entries.
    /// </summary>
    public void RemoveClient(Guid clientId)
    {
        var keysToRemove = _lastRequest.Keys.Where(k => k.ClientId == clientId).ToList();
        foreach (var key in keysToRemove)
        {
            _lastRequest.TryRemove(key, out _);
        }
    }
}
