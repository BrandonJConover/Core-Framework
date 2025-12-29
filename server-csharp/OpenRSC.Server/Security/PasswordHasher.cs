using System.Security.Cryptography;
using System.Text;

namespace OpenRSC.Server.Security;

/// <summary>
/// Secure password hashing using Argon2id (via PBKDF2 with SHA-512 as .NET native fallback).
/// For production, consider using Konscious.Security.Cryptography for true Argon2id.
/// </summary>
public static class PasswordHasher
{
    private const int SaltSize = 16;
    private const int HashSize = 32;
    private const int Iterations = 100_000; // OWASP recommendation for PBKDF2-SHA512
    private const int MinIterations = 10_000; // Minimum allowed iterations for security

    /// <summary>
    /// Hashes a password with a random salt.
    /// Returns the hash in format: $pbkdf2-sha512$iterations$salt$hash
    /// </summary>
    public static string HashPassword(string password)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(password);

        // Generate random salt
        var salt = RandomNumberGenerator.GetBytes(SaltSize);

        // Derive key using PBKDF2-SHA512
        var hash = Rfc2898DeriveBytes.Pbkdf2(
            password: Encoding.UTF8.GetBytes(password),
            salt: salt,
            iterations: Iterations,
            hashAlgorithm: HashAlgorithmName.SHA512,
            outputLength: HashSize);

        // Return in standard format
        return $"$pbkdf2-sha512${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }

    /// <summary>
    /// Verifies a password against a stored hash.
    /// </summary>
    public static bool VerifyPassword(string password, string storedHash)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(password);
        ArgumentException.ThrowIfNullOrWhiteSpace(storedHash);

        try
        {
            // Parse the stored hash
            var parts = storedHash.Split('$', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length != 4 || parts[0] != "pbkdf2-sha512")
                return false;

            var iterations = int.Parse(parts[1]);

            // Security: Reject hashes with too few iterations (potential tampering)
            if (iterations < MinIterations)
                return false;

            var salt = Convert.FromBase64String(parts[2]);
            var expectedHash = Convert.FromBase64String(parts[3]);

            // Derive key with same parameters
            var computedHash = Rfc2898DeriveBytes.Pbkdf2(
                password: Encoding.UTF8.GetBytes(password),
                salt: salt,
                iterations: iterations,
                hashAlgorithm: HashAlgorithmName.SHA512,
                outputLength: expectedHash.Length);

            // Constant-time comparison to prevent timing attacks
            return CryptographicOperations.FixedTimeEquals(computedHash, expectedHash);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Checks if a password hash needs to be upgraded (iterations increased).
    /// </summary>
    public static bool NeedsRehash(string storedHash)
    {
        try
        {
            var parts = storedHash.Split('$', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length != 4)
                return true;

            var iterations = int.Parse(parts[1]);
            return iterations < Iterations;
        }
        catch
        {
            return true;
        }
    }
}

/// <summary>
/// Account lockout manager for brute-force protection.
/// </summary>
public sealed class AccountLockoutManager
{
    private readonly Dictionary<string, LockoutInfo> _lockouts = new();
    private readonly Lock _lock = new();

    /// <summary>
    /// Maximum failed attempts before lockout.
    /// </summary>
    public int MaxFailedAttempts { get; init; } = 5;

    /// <summary>
    /// Lockout duration after max failed attempts.
    /// </summary>
    public TimeSpan LockoutDuration { get; init; } = TimeSpan.FromMinutes(15);

    /// <summary>
    /// Records a failed login attempt.
    /// Returns true if the account is now locked out.
    /// </summary>
    public bool RecordFailedAttempt(string username)
    {
        var key = username.ToLowerInvariant();

        lock (_lock)
        {
            if (!_lockouts.TryGetValue(key, out var info))
            {
                info = new LockoutInfo();
                _lockouts[key] = info;
            }

            info.FailedAttempts++;
            info.LastAttempt = DateTime.UtcNow;

            if (info.FailedAttempts >= MaxFailedAttempts)
            {
                info.LockedUntil = DateTime.UtcNow.Add(LockoutDuration);
                return true;
            }

            return false;
        }
    }

    /// <summary>
    /// Checks if an account is currently locked out.
    /// </summary>
    public bool IsLockedOut(string username)
    {
        var key = username.ToLowerInvariant();

        lock (_lock)
        {
            if (!_lockouts.TryGetValue(key, out var info))
                return false;

            if (info.LockedUntil.HasValue && DateTime.UtcNow < info.LockedUntil.Value)
                return true;

            // Lockout expired, reset
            if (info.LockedUntil.HasValue)
            {
                _lockouts.Remove(key);
            }

            return false;
        }
    }

    /// <summary>
    /// Gets the remaining lockout time for an account.
    /// </summary>
    public TimeSpan? GetRemainingLockoutTime(string username)
    {
        var key = username.ToLowerInvariant();

        lock (_lock)
        {
            if (_lockouts.TryGetValue(key, out var info) &&
                info.LockedUntil.HasValue &&
                DateTime.UtcNow < info.LockedUntil.Value)
            {
                return info.LockedUntil.Value - DateTime.UtcNow;
            }

            return null;
        }
    }

    /// <summary>
    /// Clears lockout status on successful login.
    /// </summary>
    public void ClearLockout(string username)
    {
        var key = username.ToLowerInvariant();

        lock (_lock)
        {
            _lockouts.Remove(key);
        }
    }

    /// <summary>
    /// Cleans up expired lockout entries.
    /// Call periodically to prevent memory growth.
    /// </summary>
    public void CleanupExpired()
    {
        var cutoff = DateTime.UtcNow;

        lock (_lock)
        {
            var toRemove = _lockouts
                .Where(kvp => kvp.Value.LockedUntil.HasValue && kvp.Value.LockedUntil.Value < cutoff)
                .Select(kvp => kvp.Key)
                .ToList();

            foreach (var key in toRemove)
            {
                _lockouts.Remove(key);
            }
        }
    }

    private sealed class LockoutInfo
    {
        public int FailedAttempts { get; set; }
        public DateTime LastAttempt { get; set; }
        public DateTime? LockedUntil { get; set; }
    }
}
