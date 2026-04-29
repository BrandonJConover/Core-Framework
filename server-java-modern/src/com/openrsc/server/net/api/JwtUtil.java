package com.openrsc.server.net.api;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.auth0.jwt.interfaces.JWTVerifier;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermission;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.SecureRandom;
import java.util.Date;
import java.util.Set;

/**
 * HMAC256 JWT issuance + verification for the modern client REST API.
 *
 * Design notes:
 * - The signing secret is loaded from {@code .jwt-secret} on startup. If the
 *   file doesn't exist it's generated from SecureRandom and written with
 *   owner-only permissions (POSIX 0600 on Unix; on Windows the file is
 *   created without explicit ACL changes since Files.setPosixFilePermissions
 *   is unsupported). This means tokens DO survive a server restart, which
 *   matters for 24h lifetimes — operators don't have to bounce all clients
 *   on every server kick.
 * - Algorithm is HS256 (HMAC + SHA-256). Symmetric is sufficient because
 *   only this server issues + verifies tokens. If/when tokens need to be
 *   verified by a separate auth service, swap to RS256 with an RSA keypair.
 * - Default lifetime 24h. Override via {@link #generateToken(String, long)}.
 * - To force-rotate the secret (after a suspected compromise), simply delete
 *   the {@code .jwt-secret} file and restart the server. All existing tokens
 *   become invalid.
 *
 * Token claims:
 *   sub  : username (canonical lowercased form)
 *   iss  : server name (Server.getName())
 *   iat  : issued-at (now)
 *   exp  : expires-at (now + lifetime)
 */
public final class JwtUtil {

    private static final Logger LOGGER = LogManager.getLogger("OpenRSC");

    /** 24 hours in milliseconds. */
    public static final long DEFAULT_LIFETIME_MS = 24L * 60L * 60L * 1000L;

    /** Default location for the persisted secret. Relative to the server's
     *  working dir. Must be in .gitignore so it never lands in version control. */
    public static final Path DEFAULT_SECRET_PATH = Path.of(".jwt-secret");

    private final Algorithm algorithm;
    private final JWTVerifier verifier;
    private final String issuer;

    public JwtUtil(String issuer) {
        this(issuer, DEFAULT_SECRET_PATH);
    }

    public JwtUtil(String issuer, Path secretPath) {
        this.issuer = issuer;
        String secret = loadOrCreateSecret(secretPath);
        this.algorithm = Algorithm.HMAC256(secret);
        this.verifier = JWT.require(algorithm).withIssuer(issuer).build();
    }

    /**
     * Read the persisted secret from {@code path}, or generate + write a fresh
     * one if the file is missing/empty. Returned secret is the hex-encoded
     * 32-byte string.
     */
    private static String loadOrCreateSecret(Path path) {
        try {
            if (Files.exists(path) && Files.size(path) > 0) {
                String existing = Files.readString(path).trim();
                if (existing.length() >= 32) {
                    LOGGER.info("JwtUtil loaded persisted secret from {}", path);
                    return existing;
                }
                LOGGER.warn("JwtUtil secret file {} is too short ({} chars); regenerating",
                    path, existing.length());
            }
        } catch (IOException ioe) {
            LOGGER.warn("JwtUtil could not read secret file {}: {}; regenerating",
                path, ioe.getMessage());
        }

        // Generate fresh.
        byte[] secretBytes = new byte[32];
        new SecureRandom().nextBytes(secretBytes);
        StringBuilder hex = new StringBuilder(64);
        for (byte b : secretBytes) hex.append(String.format("%02x", b));
        String secret = hex.toString();

        try {
            Files.writeString(path, secret);
            // Restrict to owner-only on Unix — best-effort, Windows just falls through.
            try {
                Set<PosixFilePermission> ownerOnly = PosixFilePermissions.fromString("rw-------");
                Files.setPosixFilePermissions(path, ownerOnly);
            } catch (UnsupportedOperationException uoe) {
                // Non-POSIX filesystem; leave default ACLs.
            }
            LOGGER.info("JwtUtil generated new secret and wrote to {} (owner-only)", path);
        } catch (IOException ioe) {
            LOGGER.error("JwtUtil could not persist secret to {}: {}; tokens will not "
                + "survive restart this run", path, ioe.getMessage());
        }
        return secret;
    }

    /** Issue a token with the default 24h lifetime. */
    public String generateToken(String username) {
        return generateToken(username, DEFAULT_LIFETIME_MS);
    }

    /** Issue a token with a custom lifetime (ms). */
    public String generateToken(String username, long lifetimeMs) {
        long now = System.currentTimeMillis();
        return JWT.create()
            .withIssuer(issuer)
            .withSubject(username)
            .withIssuedAt(new Date(now))
            .withExpiresAt(new Date(now + lifetimeMs))
            .sign(algorithm);
    }

    /**
     * Verify a token and return its subject (the username). Returns null on
     * any failure: bad signature, expired, wrong issuer, malformed.
     */
    public String verifyAndGetUsername(String token) {
        try {
            DecodedJWT decoded = verifier.verify(token);
            return decoded.getSubject();
        } catch (JWTVerificationException e) {
            return null;
        }
    }

    /**
     * Verify a token and return its decoded claims. Returns null on any
     * verification failure (so callers can short-circuit to 401 without
     * caring why the token was rejected).
     */
    public Claims verify(String token) {
        try {
            DecodedJWT decoded = verifier.verify(token);
            long exp = decoded.getExpiresAt() != null ? decoded.getExpiresAt().getTime() : 0L;
            long iat = decoded.getIssuedAt() != null ? decoded.getIssuedAt().getTime() : 0L;
            return new Claims(decoded.getSubject(), exp, iat);
        } catch (JWTVerificationException e) {
            return null;
        }
    }

    /** Decoded claims surfaced to API endpoints. Hides the raw DecodedJWT
     *  (an external library type) behind our own DTO. */
    public record Claims(String username, long expiresAtMs, long issuedAtMs) {}
}
