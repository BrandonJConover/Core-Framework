using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace OpenRSC.Server.Security;

/// <summary>
/// Security utilities for password hashing, input validation, and sanitization.
/// </summary>
public static partial class SecurityUtils
{
    private const int SaltSize = 16; // 128 bits
    private const int HashSize = 32; // 256 bits
    private const int Iterations = 100000; // PBKDF2 iterations

    #region Password Hashing

    /// <summary>
    /// Hashes a password using PBKDF2-SHA256.
    /// Returns a string in format: iterations:salt:hash (all base64)
    /// </summary>
    public static string HashPassword(string password)
    {
        if (string.IsNullOrEmpty(password))
            throw new ArgumentException("Password cannot be empty", nameof(password));

        // Generate salt
        var salt = RandomNumberGenerator.GetBytes(SaltSize);

        // Hash password
        var hash = Rfc2898DeriveBytes.Pbkdf2(
            password,
            salt,
            Iterations,
            HashAlgorithmName.SHA256,
            HashSize);

        // Combine into storable format
        return $"{Iterations}:{Convert.ToBase64String(salt)}:{Convert.ToBase64String(hash)}";
    }

    /// <summary>
    /// Verifies a password against a stored hash.
    /// </summary>
    public static bool VerifyPassword(string password, string storedHash)
    {
        if (string.IsNullOrEmpty(password) || string.IsNullOrEmpty(storedHash))
            return false;

        try
        {
            var parts = storedHash.Split(':');
            if (parts.Length != 3)
                return false;

            var iterations = int.Parse(parts[0]);
            var salt = Convert.FromBase64String(parts[1]);
            var hash = Convert.FromBase64String(parts[2]);

            // Compute hash with same parameters
            var computedHash = Rfc2898DeriveBytes.Pbkdf2(
                password,
                salt,
                iterations,
                HashAlgorithmName.SHA256,
                hash.Length);

            // Constant-time comparison to prevent timing attacks
            return CryptographicOperations.FixedTimeEquals(hash, computedHash);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Checks if a stored hash needs to be upgraded (e.g., more iterations).
    /// </summary>
    public static bool NeedsRehash(string storedHash)
    {
        if (string.IsNullOrEmpty(storedHash))
            return true;

        try
        {
            var parts = storedHash.Split(':');
            if (parts.Length != 3)
                return true;

            var iterations = int.Parse(parts[0]);
            return iterations < Iterations;
        }
        catch
        {
            return true;
        }
    }

    #endregion

    #region Input Validation

    /// <summary>
    /// Validates a username. Returns null if valid, error message if invalid.
    /// </summary>
    public static string? ValidateUsername(string? username)
    {
        if (string.IsNullOrWhiteSpace(username))
            return "Username is required";

        if (username.Length < 1 || username.Length > 12)
            return "Username must be 1-12 characters";

        if (!UsernameRegex().IsMatch(username))
            return "Username can only contain letters, numbers, and underscores";

        // Check for reserved/banned patterns
        var lower = username.ToLowerInvariant();
        if (lower.Contains("admin") || lower.Contains("mod") ||
            lower.Contains("staff") || lower.Contains("jagex"))
            return "Username contains reserved words";

        return null;
    }

    /// <summary>
    /// Validates a password. Returns null if valid, error message if invalid.
    /// </summary>
    public static string? ValidatePassword(string? password)
    {
        if (string.IsNullOrEmpty(password))
            return "Password is required";

        if (password.Length < 5)
            return "Password must be at least 5 characters";

        if (password.Length > 20)
            return "Password must be at most 20 characters";

        return null;
    }

    /// <summary>
    /// Sanitizes chat message input.
    /// </summary>
    public static string SanitizeChatMessage(string? message, int maxLength = 80)
    {
        if (string.IsNullOrEmpty(message))
            return string.Empty;

        // Truncate to max length
        if (message.Length > maxLength)
            message = message[..maxLength];

        // Remove control characters
        var sb = new StringBuilder(message.Length);
        foreach (var c in message)
        {
            if (c >= 32 && c < 127) // ASCII printable characters
            {
                sb.Append(c);
            }
        }

        return sb.ToString().Trim();
    }

    /// <summary>
    /// Validates a command input for safety.
    /// </summary>
    public static bool IsCommandSafe(string command)
    {
        if (string.IsNullOrWhiteSpace(command))
            return false;

        // Block potential injection patterns
        if (command.Contains("..") || command.Contains("//") ||
            command.Contains(";") || command.Contains("'") ||
            command.Contains("\"") || command.Contains("`"))
            return false;

        return true;
    }

    #endregion

    #region IP Validation

    /// <summary>
    /// Validates an IP address format.
    /// </summary>
    public static bool IsValidIpAddress(string? ip)
    {
        if (string.IsNullOrEmpty(ip))
            return false;

        return System.Net.IPAddress.TryParse(ip, out _);
    }

    /// <summary>
    /// Checks if an IP is in a private/local range.
    /// </summary>
    public static bool IsPrivateIp(string ip)
    {
        if (!System.Net.IPAddress.TryParse(ip, out var address))
            return false;

        var bytes = address.GetAddressBytes();
        return bytes[0] switch
        {
            10 => true, // 10.0.0.0/8
            127 => true, // 127.0.0.0/8 (loopback)
            172 when bytes[1] >= 16 && bytes[1] <= 31 => true, // 172.16.0.0/12
            192 when bytes[1] == 168 => true, // 192.168.0.0/16
            _ => false
        };
    }

    #endregion

    #region Path and Identifier Validation

    /// <summary>
    /// Validates a file path to prevent path traversal attacks.
    /// Ensures the resolved path is within the allowed base directory.
    /// </summary>
    /// <param name="basePath">The allowed base directory</param>
    /// <param name="filePath">The relative file path to validate</param>
    /// <returns>The validated canonical path</returns>
    /// <exception cref="IOException">If path traversal is detected</exception>
    public static string ValidatePath(string basePath, string filePath)
    {
        var baseDir = Path.GetFullPath(basePath);
        var targetPath = Path.GetFullPath(Path.Combine(baseDir, filePath));

        if (!targetPath.StartsWith(baseDir, StringComparison.OrdinalIgnoreCase))
        {
            throw new IOException($"Path traversal attempt detected: {filePath}");
        }

        return targetPath;
    }

    /// <summary>
    /// Validates and sanitizes a SQL identifier (table name, column name, prefix).
    /// Only allows alphanumeric characters and underscores.
    /// </summary>
    /// <param name="identifier">The identifier to validate</param>
    /// <returns>The validated identifier</returns>
    /// <exception cref="ArgumentException">If the identifier is invalid</exception>
    public static string ValidateSqlIdentifier(string identifier)
    {
        if (string.IsNullOrEmpty(identifier))
        {
            return string.Empty;
        }

        if (identifier.Length > 64)
        {
            throw new ArgumentException("Identifier too long: max 64 characters");
        }

        if (!SqlIdentifierRegex().IsMatch(identifier))
        {
            throw new ArgumentException($"Invalid SQL identifier: {identifier}. Only alphanumeric characters and underscores are allowed.");
        }

        return identifier;
    }

    /// <summary>
    /// Safely validates a table prefix for use in SQL queries.
    /// </summary>
    public static string SafeTablePrefix(string prefix)
    {
        if (string.IsNullOrEmpty(prefix))
        {
            return string.Empty;
        }

        var basePrefix = prefix.EndsWith("_") ? prefix[..^1] : prefix;
        ValidateSqlIdentifier(basePrefix);
        return prefix;
    }

    [GeneratedRegex("^[a-zA-Z_][a-zA-Z0-9_]*$")]
    private static partial Regex SqlIdentifierRegex();

    #endregion

    #region Rate Limiting Helpers

    /// <summary>
    /// Generates a secure random token.
    /// </summary>
    public static string GenerateSecureToken(int length = 32)
    {
        var bytes = RandomNumberGenerator.GetBytes(length);
        return Convert.ToBase64String(bytes)
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    /// <summary>
    /// Generates a username hash for privacy-preserving logging.
    /// </summary>
    public static string HashUsername(string username)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(username.ToLowerInvariant()));
        return Convert.ToHexString(bytes)[..16].ToLowerInvariant();
    }

    #endregion

    [GeneratedRegex("^[a-zA-Z0-9_]+$")]
    private static partial Regex UsernameRegex();
}

/// <summary>
/// Security event types for audit logging.
/// </summary>
public enum SecurityEventType
{
    LoginSuccess,
    LoginFailed,
    LoginBlocked,
    PasswordChanged,
    AccountLocked,
    SuspiciousActivity,
    RateLimitExceeded,
    InvalidInput
}

/// <summary>
/// Security event for audit logging.
/// </summary>
public readonly record struct SecurityEvent(
    SecurityEventType Type,
    string? Username,
    string? IpAddress,
    string? Details,
    DateTime Timestamp)
{
    public static SecurityEvent Create(SecurityEventType type, string? username = null,
        string? ip = null, string? details = null)
    {
        return new SecurityEvent(type, username, ip, details, DateTime.UtcNow);
    }
}
