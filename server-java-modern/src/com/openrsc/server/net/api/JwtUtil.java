package com.openrsc.server.net.api;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.auth0.jwt.interfaces.JWTVerifier;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.security.SecureRandom;
import java.util.Date;

/**
 * HMAC256 JWT issuance + verification for the modern client REST API.
 *
 * Design notes:
 * - The signing secret is generated at server start with SecureRandom and
 *   held in memory only. Tokens DO NOT survive a server restart — clients
 *   are expected to re-authenticate after server downtime. This is fine
 *   for a 24h token lifetime and avoids the operational concerns of
 *   persisting a long-lived secret to disk.
 * - Algorithm is HS256 (HMAC + SHA-256). Symmetric is sufficient because
 *   only this server issues + verifies tokens. If/when tokens need to be
 *   verified by a separate auth service, swap to RS256 with an RSA keypair.
 * - Default lifetime 24h. Override via {@link #generateToken(String, long)}.
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

    private final Algorithm algorithm;
    private final JWTVerifier verifier;
    private final String issuer;

    public JwtUtil(String issuer) {
        this.issuer = issuer;
        // 32 random bytes -> hex string used as the HMAC secret. SecureRandom is
        // seeded from /dev/urandom on Linux/Mac, so this is cryptographically
        // strong as long as the JVM hasn't been compromised.
        byte[] secretBytes = new byte[32];
        new SecureRandom().nextBytes(secretBytes);
        StringBuilder hex = new StringBuilder(64);
        for (byte b : secretBytes) hex.append(String.format("%02x", b));
        this.algorithm = Algorithm.HMAC256(hex.toString());
        this.verifier = JWT.require(algorithm).withIssuer(issuer).build();
        LOGGER.info("JwtUtil initialised (secret rotates on every server restart)");
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
}
