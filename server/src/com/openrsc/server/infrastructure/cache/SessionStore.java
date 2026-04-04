package com.openrsc.server.infrastructure.cache;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/**
 * Distributed session store backed by Redis.
 * Manages player sessions for authentication and state persistence.
 */
public class SessionStore {
    private static final Logger LOGGER = LogManager.getLogger(SessionStore.class);
    private static final String SESSION_PREFIX = "session:";
    private static final String USER_SESSION_PREFIX = "user_session:";

    private final RedisCache cache;
    private final Gson gson;
    private final int sessionTtlSeconds;

    public SessionStore(RedisCache cache, int sessionTtlSeconds) {
        this.cache = cache;
        this.sessionTtlSeconds = sessionTtlSeconds;
        this.gson = new GsonBuilder()
            .setDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ")
            .create();
    }

    /**
     * Creates a new session for a user.
     */
    public Session createSession(long userId, String username, String ipAddress, String deviceId) {
        String sessionId = generateSessionId();
        Session session = new Session(
            sessionId,
            userId,
            username,
            ipAddress,
            deviceId,
            Instant.now(),
            Instant.now().plusSeconds(sessionTtlSeconds)
        );

        // Store session by ID
        cache.set(SESSION_PREFIX + sessionId, gson.toJson(session), sessionTtlSeconds);

        // Store session ID by user (for session management)
        cache.sadd(USER_SESSION_PREFIX + userId, sessionId);
        cache.expire(USER_SESSION_PREFIX + userId, sessionTtlSeconds);

        LOGGER.debug("Created session {} for user {}", sessionId, username);
        return session;
    }

    /**
     * Gets a session by ID.
     */
    public Optional<Session> getSession(String sessionId) {
        return cache.get(SESSION_PREFIX + sessionId)
            .map(json -> gson.fromJson(json, Session.class));
    }

    /**
     * Validates a session and refreshes its TTL.
     */
    public boolean validateAndRefresh(String sessionId) {
        Optional<Session> session = getSession(sessionId);
        if (session.isEmpty()) {
            return false;
        }

        Session s = session.get();
        if (Instant.now().isAfter(s.expiresAt())) {
            invalidateSession(sessionId);
            return false;
        }

        // Refresh TTL
        cache.expire(SESSION_PREFIX + sessionId, sessionTtlSeconds);
        cache.expire(USER_SESSION_PREFIX + s.userId(), sessionTtlSeconds);

        return true;
    }

    /**
     * Invalidates a specific session.
     */
    public void invalidateSession(String sessionId) {
        getSession(sessionId).ifPresent(session -> {
            cache.delete(SESSION_PREFIX + sessionId);
            LOGGER.debug("Invalidated session {} for user {}", sessionId, session.username());
        });
    }

    /**
     * Invalidates all sessions for a user.
     */
    public void invalidateAllSessions(long userId) {
        cache.smembers(USER_SESSION_PREFIX + userId).forEach(sessionId -> {
            cache.delete(SESSION_PREFIX + sessionId);
        });
        cache.delete(USER_SESSION_PREFIX + userId);
        LOGGER.debug("Invalidated all sessions for user {}", userId);
    }

    /**
     * Gets the count of active sessions for a user.
     */
    public int getActiveSessionCount(long userId) {
        return cache.smembers(USER_SESSION_PREFIX + userId).size();
    }

    /**
     * Updates session with additional data.
     */
    public void updateSession(String sessionId, String key, String value) {
        getSession(sessionId).ifPresent(session -> {
            cache.hset(SESSION_PREFIX + sessionId + ":data", java.util.Map.of(key, value));
            cache.expire(SESSION_PREFIX + sessionId + ":data", sessionTtlSeconds);
        });
    }

    /**
     * Gets session data.
     */
    public Optional<String> getSessionData(String sessionId, String key) {
        var data = cache.hgetAll(SESSION_PREFIX + sessionId + ":data");
        return Optional.ofNullable(data.get(key));
    }

    private String generateSessionId() {
        return UUID.randomUUID().toString().replace("-", "");
    }

    /**
     * Session record.
     */
    public record Session(
        String sessionId,
        long userId,
        String username,
        String ipAddress,
        String deviceId,
        Instant createdAt,
        Instant expiresAt
    ) {}
}
