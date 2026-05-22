package com.openrsc.server.net.api;

import java.security.SecureRandom;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Short-lived one-time login tickets for launcher -> game-client handoff.
 *
 * The launcher authenticates over HTTPS, requests a ticket for a canonical
 * username, then passes that ticket through the existing binary login flow in
 * the password slot. The game server verifies and consumes it during login,
 * which lets the browser bypass the legacy in-canvas username/password prompt
 * without teaching the C client a brand new auth protocol.
 */
public final class GameLoginTicketService {

    public static final long DEFAULT_LIFETIME_MS = 10L * 60_000L;
    public static final String PASSWORD_PREFIX = "t";
    private static final char[] TOKEN_ALPHABET =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".toCharArray();
    private static final int TOKEN_LENGTH = 16;

    private final SecureRandom secureRandom = new SecureRandom();
    private final ConcurrentHashMap<String, TicketRecord> tickets = new ConcurrentHashMap<>();

    public String issuePasswordToken(String username) {
        return issuePasswordToken(username, DEFAULT_LIFETIME_MS);
    }

    public String issuePasswordToken(String username, long lifetimeMs) {
        purgeExpired();
        String rawToken = nextToken();
        long expiresAtMs = System.currentTimeMillis() + Math.max(1_000L, lifetimeMs);
        tickets.put(rawToken, new TicketRecord(username, expiresAtMs));
        return PASSWORD_PREFIX + rawToken;
    }

    public boolean isValidPasswordToken(String username, String password) {
        String rawToken = extractRawToken(password);
        if (rawToken == null) {
            return false;
        }

        TicketRecord record = tickets.get(rawToken);
        if (record == null) {
            return false;
        }
        if (record.expiresAtMs < System.currentTimeMillis()) {
            tickets.remove(rawToken, record);
            return false;
        }
        return record.username.equals(username);
    }

    public boolean consumePasswordToken(String username, String password) {
        String rawToken = extractRawToken(password);
        if (rawToken == null) {
            return false;
        }

        TicketRecord record = tickets.get(rawToken);
        if (record == null) {
            return false;
        }
        if (record.expiresAtMs < System.currentTimeMillis()) {
            tickets.remove(rawToken, record);
            return false;
        }
        if (!record.username.equals(username)) {
            return false;
        }
        return tickets.remove(rawToken, record);
    }

    public long expiresInSeconds() {
        return DEFAULT_LIFETIME_MS / 1000L;
    }

    private void purgeExpired() {
        long now = System.currentTimeMillis();
        for (Map.Entry<String, TicketRecord> entry : tickets.entrySet()) {
            if (entry.getValue().expiresAtMs < now) {
                tickets.remove(entry.getKey(), entry.getValue());
            }
        }
    }

    private String extractRawToken(String password) {
        if (password == null || !password.startsWith(PASSWORD_PREFIX)) {
            return null;
        }
        String rawToken = password.substring(PASSWORD_PREFIX.length()).trim();
        return rawToken.isEmpty() ? null : rawToken;
    }

    private String nextToken() {
        char[] token = new char[TOKEN_LENGTH];
        for (int i = 0; i < token.length; i++) {
            token[i] = TOKEN_ALPHABET[secureRandom.nextInt(TOKEN_ALPHABET.length)];
        }
        return new String(token);
    }

    private record TicketRecord(String username, long expiresAtMs) {}
}
