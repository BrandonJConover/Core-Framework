package com.openrsc.server.infrastructure.cache;

import redis.clients.jedis.JedisPool;
import redis.clients.jedis.JedisPoolConfig;
import redis.clients.jedis.Jedis;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.time.Duration;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Function;

/**
 * Redis-based distributed cache and session store.
 * Provides high-performance caching for player data, sessions, and game state.
 */
public class RedisCache implements AutoCloseable {
    private static final Logger LOGGER = LogManager.getLogger(RedisCache.class);

    private final JedisPool jedisPool;
    private final String keyPrefix;
    private final int defaultTtlSeconds;
    private volatile boolean connected;

    public RedisCache(RedisCacheConfig config) {
        this.keyPrefix = config.keyPrefix();
        this.defaultTtlSeconds = config.defaultTtlSeconds();

        JedisPoolConfig poolConfig = new JedisPoolConfig();
        poolConfig.setMaxTotal(config.maxPoolSize());
        poolConfig.setMaxIdle(config.maxIdle());
        poolConfig.setMinIdle(config.minIdle());
        poolConfig.setTestOnBorrow(true);
        poolConfig.setTestOnReturn(true);
        poolConfig.setTestWhileIdle(true);
        poolConfig.setBlockWhenExhausted(true);
        poolConfig.setMaxWait(Duration.ofMillis(config.connectionTimeoutMs()));

        if (config.password() != null && !config.password().isEmpty()) {
            this.jedisPool = new JedisPool(poolConfig, config.host(), config.port(),
                config.connectionTimeoutMs(), config.password(), config.database());
        } else {
            this.jedisPool = new JedisPool(poolConfig, config.host(), config.port(),
                config.connectionTimeoutMs());
        }

        // Test connection
        try (Jedis jedis = jedisPool.getResource()) {
            jedis.ping();
            connected = true;
            LOGGER.info("Connected to Redis at {}:{}", config.host(), config.port());
        } catch (Exception e) {
            connected = false;
            LOGGER.error("Failed to connect to Redis: {}", e.getMessage());
        }
    }

    /**
     * Gets a value from the cache.
     */
    public Optional<String> get(String key) {
        if (!connected) return Optional.empty();

        try (Jedis jedis = jedisPool.getResource()) {
            String value = jedis.get(prefixKey(key));
            return Optional.ofNullable(value);
        } catch (Exception e) {
            LOGGER.warn("Redis GET failed for key {}: {}", key, e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Gets a value or computes it if absent.
     */
    public String getOrCompute(String key, Function<String, String> computeFunction, int ttlSeconds) {
        return get(key).orElseGet(() -> {
            String value = computeFunction.apply(key);
            set(key, value, ttlSeconds);
            return value;
        });
    }

    /**
     * Sets a value in the cache with the default TTL.
     */
    public boolean set(String key, String value) {
        return set(key, value, defaultTtlSeconds);
    }

    /**
     * Sets a value in the cache with a specific TTL.
     */
    public boolean set(String key, String value, int ttlSeconds) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            if (ttlSeconds > 0) {
                jedis.setex(prefixKey(key), ttlSeconds, value);
            } else {
                jedis.set(prefixKey(key), value);
            }
            return true;
        } catch (Exception e) {
            LOGGER.warn("Redis SET failed for key {}: {}", key, e.getMessage());
            return false;
        }
    }

    /**
     * Sets a value only if it doesn't exist.
     */
    public boolean setIfAbsent(String key, String value, int ttlSeconds) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            long result = jedis.setnx(prefixKey(key), value);
            if (result == 1 && ttlSeconds > 0) {
                jedis.expire(prefixKey(key), ttlSeconds);
            }
            return result == 1;
        } catch (Exception e) {
            LOGGER.warn("Redis SETNX failed for key {}: {}", key, e.getMessage());
            return false;
        }
    }

    /**
     * Deletes a key from the cache.
     */
    public boolean delete(String key) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            jedis.del(prefixKey(key));
            return true;
        } catch (Exception e) {
            LOGGER.warn("Redis DEL failed for key {}: {}", key, e.getMessage());
            return false;
        }
    }

    /**
     * Checks if a key exists.
     */
    public boolean exists(String key) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.exists(prefixKey(key));
        } catch (Exception e) {
            LOGGER.warn("Redis EXISTS failed for key {}: {}", key, e.getMessage());
            return false;
        }
    }

    /**
     * Gets multiple hash fields.
     */
    public Map<String, String> hgetAll(String key) {
        if (!connected) return Map.of();

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.hgetAll(prefixKey(key));
        } catch (Exception e) {
            LOGGER.warn("Redis HGETALL failed for key {}: {}", key, e.getMessage());
            return Map.of();
        }
    }

    /**
     * Sets multiple hash fields.
     */
    public boolean hset(String key, Map<String, String> fields) {
        if (!connected || fields.isEmpty()) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            jedis.hset(prefixKey(key), fields);
            return true;
        } catch (Exception e) {
            LOGGER.warn("Redis HSET failed for key {}: {}", key, e.getMessage());
            return false;
        }
    }

    /**
     * Increments a counter.
     */
    public long increment(String key) {
        if (!connected) return 0;

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.incr(prefixKey(key));
        } catch (Exception e) {
            LOGGER.warn("Redis INCR failed for key {}: {}", key, e.getMessage());
            return 0;
        }
    }

    /**
     * Adds to a set.
     */
    public long sadd(String key, String... members) {
        if (!connected) return 0;

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.sadd(prefixKey(key), members);
        } catch (Exception e) {
            LOGGER.warn("Redis SADD failed for key {}: {}", key, e.getMessage());
            return 0;
        }
    }

    /**
     * Gets all members of a set.
     */
    public Set<String> smembers(String key) {
        if (!connected) return Set.of();

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.smembers(prefixKey(key));
        } catch (Exception e) {
            LOGGER.warn("Redis SMEMBERS failed for key {}: {}", key, e.getMessage());
            return Set.of();
        }
    }

    /**
     * Publishes a message to a channel.
     */
    public long publish(String channel, String message) {
        if (!connected) return 0;

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.publish(prefixKey(channel), message);
        } catch (Exception e) {
            LOGGER.warn("Redis PUBLISH failed for channel {}: {}", channel, e.getMessage());
            return 0;
        }
    }

    /**
     * Sets the TTL on a key.
     */
    public boolean expire(String key, int seconds) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            jedis.expire(prefixKey(key), seconds);
            return true;
        } catch (Exception e) {
            LOGGER.warn("Redis EXPIRE failed for key {}: {}", key, e.getMessage());
            return false;
        }
    }

    // ==================== LEADERBOARD OPERATIONS ====================

    /**
     * Updates a player's score in a leaderboard.
     */
    public boolean updateLeaderboard(String leaderboard, String member, double score) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            jedis.zadd(prefixKey("leaderboard:" + leaderboard), score, member);
            return true;
        } catch (Exception e) {
            LOGGER.warn("Redis ZADD failed for leaderboard {}: {}", leaderboard, e.getMessage());
            return false;
        }
    }

    /**
     * Gets the top N players from a leaderboard.
     */
    public java.util.List<LeaderboardEntry> getLeaderboardTop(String leaderboard, int count) {
        if (!connected) return java.util.List.of();

        try (Jedis jedis = jedisPool.getResource()) {
            var entries = jedis.zrevrangeWithScores(prefixKey("leaderboard:" + leaderboard), 0, count - 1);
            java.util.List<LeaderboardEntry> result = new java.util.ArrayList<>();
            int rank = 1;
            for (var entry : entries) {
                result.add(new LeaderboardEntry(entry.getElement(), entry.getScore(), rank++));
            }
            return result;
        } catch (Exception e) {
            LOGGER.warn("Redis ZREVRANGE failed for leaderboard {}: {}", leaderboard, e.getMessage());
            return java.util.List.of();
        }
    }

    /**
     * Gets a player's rank in a leaderboard (1-indexed).
     */
    public Optional<Long> getLeaderboardRank(String leaderboard, String member) {
        if (!connected) return Optional.empty();

        try (Jedis jedis = jedisPool.getResource()) {
            Long rank = jedis.zrevrank(prefixKey("leaderboard:" + leaderboard), member);
            return rank != null ? Optional.of(rank + 1) : Optional.empty();
        } catch (Exception e) {
            LOGGER.warn("Redis ZREVRANK failed for leaderboard {}: {}", leaderboard, e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Gets a player's score in a leaderboard.
     */
    public Optional<Double> getLeaderboardScore(String leaderboard, String member) {
        if (!connected) return Optional.empty();

        try (Jedis jedis = jedisPool.getResource()) {
            Double score = jedis.zscore(prefixKey("leaderboard:" + leaderboard), member);
            return Optional.ofNullable(score);
        } catch (Exception e) {
            LOGGER.warn("Redis ZSCORE failed for leaderboard {}: {}", leaderboard, e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Increments a player's score in a leaderboard.
     */
    public double incrementLeaderboardScore(String leaderboard, String member, double increment) {
        if (!connected) return 0;

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.zincrby(prefixKey("leaderboard:" + leaderboard), increment, member);
        } catch (Exception e) {
            LOGGER.warn("Redis ZINCRBY failed for leaderboard {}: {}", leaderboard, e.getMessage());
            return 0;
        }
    }

    // ==================== RATE LIMITING ====================

    /**
     * Checks and increments a rate limit counter.
     * Returns true if under limit, false if rate limited.
     */
    public boolean checkRateLimit(String key, int maxRequests, int windowSeconds) {
        if (!connected) return true; // Allow if Redis unavailable

        String fullKey = prefixKey("ratelimit:" + key);
        try (Jedis jedis = jedisPool.getResource()) {
            long current = jedis.incr(fullKey);
            if (current == 1) {
                jedis.expire(fullKey, windowSeconds);
            }
            return current <= maxRequests;
        } catch (Exception e) {
            LOGGER.warn("Redis rate limit check failed for {}: {}", key, e.getMessage());
            return true; // Allow on error
        }
    }

    /**
     * Gets the remaining rate limit quota.
     */
    public int getRateLimitRemaining(String key, int maxRequests) {
        if (!connected) return maxRequests;

        try (Jedis jedis = jedisPool.getResource()) {
            String value = jedis.get(prefixKey("ratelimit:" + key));
            if (value == null) return maxRequests;
            int current = Integer.parseInt(value);
            return Math.max(0, maxRequests - current);
        } catch (Exception e) {
            return maxRequests;
        }
    }

    /**
     * Resets a rate limit counter.
     */
    public boolean resetRateLimit(String key) {
        return delete("ratelimit:" + key);
    }

    // ==================== ONLINE PLAYER TRACKING ====================

    /**
     * Sets a player as online on a specific server.
     */
    public boolean setPlayerOnline(String username, String serverId) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            jedis.sadd(prefixKey("online:all"), username);
            jedis.hset(prefixKey("online:servers"), username, serverId);
            return true;
        } catch (Exception e) {
            LOGGER.warn("Redis failed to set player online: {}", e.getMessage());
            return false;
        }
    }

    /**
     * Sets a player as offline.
     */
    public boolean setPlayerOffline(String username) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            jedis.srem(prefixKey("online:all"), username);
            jedis.hdel(prefixKey("online:servers"), username);
            return true;
        } catch (Exception e) {
            LOGGER.warn("Redis failed to set player offline: {}", e.getMessage());
            return false;
        }
    }

    /**
     * Checks if a player is online.
     */
    public boolean isPlayerOnline(String username) {
        if (!connected) return false;

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.sismember(prefixKey("online:all"), username);
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Gets the count of online players.
     */
    public long getOnlinePlayerCount() {
        if (!connected) return 0;

        try (Jedis jedis = jedisPool.getResource()) {
            return jedis.scard(prefixKey("online:all"));
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * Gets which server a player is on.
     */
    public Optional<String> getPlayerServer(String username) {
        if (!connected) return Optional.empty();

        try (Jedis jedis = jedisPool.getResource()) {
            String server = jedis.hget(prefixKey("online:servers"), username);
            return Optional.ofNullable(server);
        } catch (Exception e) {
            return Optional.empty();
        }
    }

    /**
     * Checks if connected to Redis.
     */
    public boolean isConnected() {
        return connected;
    }

    /**
     * Performs a health check.
     */
    public boolean healthCheck() {
        try (Jedis jedis = jedisPool.getResource()) {
            return "PONG".equals(jedis.ping());
        } catch (Exception e) {
            connected = false;
            return false;
        }
    }

    private String prefixKey(String key) {
        return keyPrefix + key;
    }

    @Override
    public void close() {
        if (jedisPool != null && !jedisPool.isClosed()) {
            jedisPool.close();
            LOGGER.info("Redis connection pool closed");
        }
    }

    /**
     * Leaderboard entry record.
     */
    public record LeaderboardEntry(String member, double score, int rank) {}

    /**
     * Redis configuration record.
     */
    public record RedisCacheConfig(
        String host,
        int port,
        String password,
        int database,
        String keyPrefix,
        int defaultTtlSeconds,
        int maxPoolSize,
        int maxIdle,
        int minIdle,
        int connectionTimeoutMs
    ) {
        public static RedisCacheConfig defaults() {
            return new RedisCacheConfig(
                "localhost", 6379, null, 0,
                "openrsc:", 300, 50, 20, 5, 2000
            );
        }
    }
}
