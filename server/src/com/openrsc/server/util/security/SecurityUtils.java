package com.openrsc.server.util.security;

import java.io.File;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.regex.Pattern;

/**
 * Security utilities for the OpenRSC server.
 * Provides secure implementations for common security-sensitive operations.
 */
public final class SecurityUtils {

    // Pattern for valid SQL identifiers (alphanumeric and underscore only)
    private static final Pattern VALID_IDENTIFIER_PATTERN = Pattern.compile("^[a-zA-Z_][a-zA-Z0-9_]*$");

    // Maximum table prefix length
    private static final int MAX_IDENTIFIER_LENGTH = 64;

    private SecurityUtils() {
        // Prevent instantiation
    }

    /**
     * Validates and sanitizes a SQL identifier (table name, column name, prefix).
     * Only allows alphanumeric characters and underscores.
     *
     * @param identifier The identifier to validate
     * @return The validated identifier
     * @throws IllegalArgumentException if the identifier is invalid
     */
    public static String validateSqlIdentifier(String identifier) {
        if (identifier == null || identifier.isEmpty()) {
            return "";
        }

        if (identifier.length() > MAX_IDENTIFIER_LENGTH) {
            throw new IllegalArgumentException("Identifier too long: max " + MAX_IDENTIFIER_LENGTH + " characters");
        }

        if (!VALID_IDENTIFIER_PATTERN.matcher(identifier).matches()) {
            throw new IllegalArgumentException("Invalid SQL identifier: " + identifier +
                ". Only alphanumeric characters and underscores are allowed.");
        }

        return identifier;
    }

    /**
     * Safely escapes a table prefix for use in SQL queries.
     * This should be used when table prefixes cannot be parameterized.
     *
     * @param prefix The table prefix
     * @return The safe table prefix (without trailing underscore)
     */
    public static String safeTablePrefix(String prefix) {
        if (prefix == null || prefix.isEmpty()) {
            return "";
        }

        // Remove any trailing underscore for validation
        String basePrefix = prefix.endsWith("_") ? prefix.substring(0, prefix.length() - 1) : prefix;

        // Validate the prefix
        validateSqlIdentifier(basePrefix);

        // Return the original (with trailing underscore if present)
        return prefix;
    }

    /**
     * Performs a constant-time comparison of two byte arrays.
     * This prevents timing attacks by always comparing all bytes.
     *
     * @param a First byte array
     * @param b Second byte array
     * @return true if arrays are equal, false otherwise
     */
    public static boolean constantTimeEquals(byte[] a, byte[] b) {
        if (a == null || b == null) {
            return a == b;
        }

        return MessageDigest.isEqual(a, b);
    }

    /**
     * Performs a constant-time comparison of two strings.
     * This prevents timing attacks by always comparing all characters.
     *
     * @param a First string
     * @param b Second string
     * @return true if strings are equal, false otherwise
     */
    public static boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) {
            return a == b;
        }

        byte[] aBytes = a.getBytes();
        byte[] bBytes = b.getBytes();

        return MessageDigest.isEqual(aBytes, bBytes);
    }

    /**
     * Validates a file path to prevent path traversal attacks.
     * Ensures the resolved path is within the allowed base directory.
     *
     * @param basePath The allowed base directory
     * @param filePath The relative file path to validate
     * @return The validated canonical path
     * @throws IOException if path traversal is detected or file operations fail
     */
    public static String validatePath(String basePath, String filePath) throws IOException {
        File baseDir = new File(basePath).getCanonicalFile();
        File targetFile = new File(baseDir, filePath).getCanonicalFile();

        // Ensure the target is within the base directory
        if (!targetFile.getPath().startsWith(baseDir.getPath())) {
            throw new IOException("Path traversal attempt detected: " + filePath);
        }

        return targetFile.getPath();
    }

    /**
     * Validates a file path to prevent path traversal attacks.
     * Returns a validated File object.
     *
     * @param baseDir The allowed base directory
     * @param filePath The relative file path to validate
     * @return The validated File object
     * @throws IOException if path traversal is detected
     */
    public static File validatePath(File baseDir, String filePath) throws IOException {
        File canonicalBase = baseDir.getCanonicalFile();
        File targetFile = new File(canonicalBase, filePath).getCanonicalFile();

        if (!targetFile.getPath().startsWith(canonicalBase.getPath())) {
            throw new IOException("Path traversal attempt detected: " + filePath);
        }

        return targetFile;
    }

    /**
     * Generates a secure random token.
     *
     * @param length The length of the token in bytes
     * @return A hex-encoded secure random token
     */
    public static String generateSecureToken(int length) {
        SecureRandom secureRandom = new SecureRandom();
        byte[] bytes = new byte[length];
        secureRandom.nextBytes(bytes);
        return bytesToHex(bytes);
    }

    /**
     * Converts bytes to hexadecimal string.
     */
    private static String bytesToHex(byte[] bytes) {
        var sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append("%02x".formatted(b));
        }
        return sb.toString();
    }

    /**
     * Sanitizes user input to prevent injection attacks.
     * Removes or escapes potentially dangerous characters.
     *
     * @param input The user input to sanitize
     * @param maxLength Maximum allowed length
     * @return Sanitized input
     */
    public static String sanitizeInput(String input, int maxLength) {
        if (input == null) {
            return "";
        }

        // Truncate to max length
        String sanitized = input.length() > maxLength ? input.substring(0, maxLength) : input;

        // Remove null bytes and other control characters
        sanitized = sanitized.replaceAll("[\u0000-\u001F\u007F]", "");

        // Remove potential SQL injection characters in user-facing content
        // (This is for display purposes; actual queries should use parameterization)
        sanitized = sanitized.replace("'", "''");

        return sanitized;
    }

    /**
     * Validates a username according to security requirements.
     *
     * @param username The username to validate
     * @return true if valid, false otherwise
     */
    public static boolean isValidUsername(String username) {
        if (username == null || username.isEmpty()) {
            return false;
        }

        // Length check
        if (username.length() < 2 || username.length() > 12) {
            return false;
        }

        // Only allow alphanumeric characters and underscores
        if (!Pattern.matches("^[a-zA-Z0-9_ ]+$", username)) {
            return false;
        }

        // No leading/trailing spaces
        if (!username.equals(username.trim())) {
            return false;
        }

        return true;
    }

    /**
     * Rate limiter key generation for IP-based limiting.
     *
     * @param ip The IP address
     * @param action The action being rate-limited
     * @return A key suitable for rate limiting storage
     */
    public static String generateRateLimitKey(String ip, String action) {
        // Validate IP format
        if (ip == null || ip.isEmpty()) {
            throw new IllegalArgumentException("IP address cannot be null or empty");
        }

        // Sanitize action name
        String safeAction = action.replaceAll("[^a-zA-Z0-9_]", "");

        return "rate:" + safeAction + ":" + ip;
    }
}
