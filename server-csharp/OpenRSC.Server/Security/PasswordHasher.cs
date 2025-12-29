using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Konscious.Security.Cryptography;

namespace OpenRSC.Server.Security;

/// <summary>
/// Password hashing algorithm options.
/// </summary>
public enum PasswordHashAlgorithm
{
    /// <summary>Argon2id - recommended, most secure against GPU/ASIC attacks.</summary>
    Argon2id,

    /// <summary>PBKDF2-SHA512 - .NET native fallback, still secure.</summary>
    Pbkdf2Sha512
}

/// <summary>
/// Password complexity requirements.
/// </summary>
public sealed class PasswordPolicy
{
    /// <summary>Minimum password length.</summary>
    public int MinLength { get; init; } = 8;

    /// <summary>Maximum password length.</summary>
    public int MaxLength { get; init; } = 128;

    /// <summary>Require at least one uppercase letter.</summary>
    public bool RequireUppercase { get; init; } = true;

    /// <summary>Require at least one lowercase letter.</summary>
    public bool RequireLowercase { get; init; } = true;

    /// <summary>Require at least one digit.</summary>
    public bool RequireDigit { get; init; } = true;

    /// <summary>Require at least one special character.</summary>
    public bool RequireSpecialChar { get; init; } = true;

    /// <summary>List of common passwords to reject.</summary>
    public bool RejectCommonPasswords { get; init; } = true;

    /// <summary>Reject passwords containing the username.</summary>
    public bool RejectUsernameInPassword { get; init; } = true;

    /// <summary>Default secure policy.</summary>
    public static PasswordPolicy Secure => new();

    /// <summary>Legacy/relaxed policy for older accounts.</summary>
    public static PasswordPolicy Legacy => new()
    {
        MinLength = 5,
        RequireUppercase = false,
        RequireLowercase = false,
        RequireDigit = false,
        RequireSpecialChar = false,
        RejectCommonPasswords = false,
        RejectUsernameInPassword = false
    };
}

/// <summary>
/// Result of password validation.
/// </summary>
public sealed class PasswordValidationResult
{
    public bool IsValid { get; init; }
    public List<string> Errors { get; init; } = [];

    public static PasswordValidationResult Success => new() { IsValid = true };

    public static PasswordValidationResult Failure(params string[] errors) => new()
    {
        IsValid = false,
        Errors = [.. errors]
    };
}

/// <summary>
/// Secure password hashing with support for multiple algorithms.
/// Supports Argon2id (preferred) and PBKDF2-SHA512 (fallback).
/// </summary>
public static partial class PasswordHasher
{
    // Argon2id parameters (OWASP recommendations)
    private const int Argon2SaltSize = 16;
    private const int Argon2HashSize = 32;
    private const int Argon2DegreeOfParallelism = 4;
    private const int Argon2MemorySize = 65536; // 64 MB
    private const int Argon2Iterations = 3;

    // PBKDF2 parameters
    private const int Pbkdf2SaltSize = 16;
    private const int Pbkdf2HashSize = 32;
    private const int Pbkdf2Iterations = 100_000;
    private const int Pbkdf2MinIterations = 10_000;

    // Common weak passwords to reject
    private static readonly HashSet<string> CommonPasswords = new(StringComparer.OrdinalIgnoreCase)
    {
        "password", "123456", "12345678", "qwerty", "abc123", "monkey", "1234567",
        "letmein", "trustno1", "dragon", "baseball", "iloveyou", "master", "sunshine",
        "ashley", "bailey", "passw0rd", "shadow", "123123", "654321", "superman",
        "qazwsx", "michael", "football", "password1", "password123", "welcome",
        "jesus", "ninja", "mustang", "password2", "amanda", "jordan", "harley"
    };

    /// <summary>
    /// The preferred algorithm to use for new password hashes.
    /// </summary>
    public static PasswordHashAlgorithm PreferredAlgorithm { get; set; } = PasswordHashAlgorithm.Argon2id;

    #region Password Hashing

    /// <summary>
    /// Hashes a password using the preferred algorithm.
    /// </summary>
    public static string HashPassword(string password)
    {
        return HashPassword(password, PreferredAlgorithm);
    }

    /// <summary>
    /// Hashes a password using the specified algorithm.
    /// </summary>
    public static string HashPassword(string password, PasswordHashAlgorithm algorithm)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(password);

        return algorithm switch
        {
            PasswordHashAlgorithm.Argon2id => HashWithArgon2id(password),
            PasswordHashAlgorithm.Pbkdf2Sha512 => HashWithPbkdf2(password),
            _ => throw new ArgumentOutOfRangeException(nameof(algorithm))
        };
    }

    private static string HashWithArgon2id(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(Argon2SaltSize);
        var passwordBytes = Encoding.UTF8.GetBytes(password);

        using var argon2 = new Argon2id(passwordBytes)
        {
            Salt = salt,
            DegreeOfParallelism = Argon2DegreeOfParallelism,
            MemorySize = Argon2MemorySize,
            Iterations = Argon2Iterations
        };

        var hash = argon2.GetBytes(Argon2HashSize);

        // Format: $argon2id$v=19$m=65536,t=3,p=4$salt$hash
        return $"$argon2id$v=19$m={Argon2MemorySize},t={Argon2Iterations},p={Argon2DegreeOfParallelism}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }

    private static string HashWithPbkdf2(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(Pbkdf2SaltSize);

        var hash = Rfc2898DeriveBytes.Pbkdf2(
            password: Encoding.UTF8.GetBytes(password),
            salt: salt,
            iterations: Pbkdf2Iterations,
            hashAlgorithm: HashAlgorithmName.SHA512,
            outputLength: Pbkdf2HashSize);

        return $"$pbkdf2-sha512${Pbkdf2Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }

    #endregion

    #region Password Verification

    /// <summary>
    /// Verifies a password against a stored hash.
    /// Automatically detects the algorithm from the hash format.
    /// </summary>
    public static bool VerifyPassword(string password, string storedHash)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(password);
        ArgumentException.ThrowIfNullOrWhiteSpace(storedHash);

        try
        {
            if (storedHash.StartsWith("$argon2id$"))
                return VerifyArgon2id(password, storedHash);

            if (storedHash.StartsWith("$pbkdf2-sha512$"))
                return VerifyPbkdf2(password, storedHash);

            return false;
        }
        catch
        {
            return false;
        }
    }

    private static bool VerifyArgon2id(string password, string storedHash)
    {
        // Parse: $argon2id$v=19$m=65536,t=3,p=4$salt$hash
        var parts = storedHash.Split('$', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 5 || parts[0] != "argon2id")
            return false;

        // Parse parameters
        var paramMatch = Argon2ParamsRegex().Match(parts[2]);
        if (!paramMatch.Success)
            return false;

        var memorySize = int.Parse(paramMatch.Groups["m"].Value);
        var iterations = int.Parse(paramMatch.Groups["t"].Value);
        var parallelism = int.Parse(paramMatch.Groups["p"].Value);

        // Security: Validate minimum parameters
        if (memorySize < 16384 || iterations < 1 || parallelism < 1)
            return false;

        var salt = Convert.FromBase64String(parts[3]);
        var expectedHash = Convert.FromBase64String(parts[4]);

        var passwordBytes = Encoding.UTF8.GetBytes(password);

        using var argon2 = new Argon2id(passwordBytes)
        {
            Salt = salt,
            DegreeOfParallelism = parallelism,
            MemorySize = memorySize,
            Iterations = iterations
        };

        var computedHash = argon2.GetBytes(expectedHash.Length);

        return CryptographicOperations.FixedTimeEquals(computedHash, expectedHash);
    }

    private static bool VerifyPbkdf2(string password, string storedHash)
    {
        var parts = storedHash.Split('$', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 4 || parts[0] != "pbkdf2-sha512")
            return false;

        var iterations = int.Parse(parts[1]);

        // Security: Reject hashes with too few iterations
        if (iterations < Pbkdf2MinIterations)
            return false;

        var salt = Convert.FromBase64String(parts[2]);
        var expectedHash = Convert.FromBase64String(parts[3]);

        var computedHash = Rfc2898DeriveBytes.Pbkdf2(
            password: Encoding.UTF8.GetBytes(password),
            salt: salt,
            iterations: iterations,
            hashAlgorithm: HashAlgorithmName.SHA512,
            outputLength: expectedHash.Length);

        return CryptographicOperations.FixedTimeEquals(computedHash, expectedHash);
    }

    #endregion

    #region Hash Upgrade Detection

    /// <summary>
    /// Checks if a password hash needs to be upgraded to a more secure algorithm or parameters.
    /// </summary>
    public static bool NeedsRehash(string storedHash)
    {
        if (string.IsNullOrEmpty(storedHash))
            return true;

        try
        {
            // Upgrade PBKDF2 to Argon2id
            if (storedHash.StartsWith("$pbkdf2-sha512$") && PreferredAlgorithm == PasswordHashAlgorithm.Argon2id)
                return true;

            // Check PBKDF2 iterations
            if (storedHash.StartsWith("$pbkdf2-sha512$"))
            {
                var parts = storedHash.Split('$', StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length == 4)
                {
                    var iterations = int.Parse(parts[1]);
                    if (iterations < Pbkdf2Iterations)
                        return true;
                }
            }

            // Check Argon2id parameters
            if (storedHash.StartsWith("$argon2id$"))
            {
                var parts = storedHash.Split('$', StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length == 5)
                {
                    var paramMatch = Argon2ParamsRegex().Match(parts[2]);
                    if (paramMatch.Success)
                    {
                        var memorySize = int.Parse(paramMatch.Groups["m"].Value);
                        var iterations = int.Parse(paramMatch.Groups["t"].Value);

                        // Upgrade if using weaker parameters
                        if (memorySize < Argon2MemorySize || iterations < Argon2Iterations)
                            return true;
                    }
                }
            }

            return false;
        }
        catch
        {
            return true;
        }
    }

    /// <summary>
    /// Gets the algorithm used for a stored hash.
    /// </summary>
    public static PasswordHashAlgorithm? GetAlgorithm(string storedHash)
    {
        if (string.IsNullOrEmpty(storedHash))
            return null;

        if (storedHash.StartsWith("$argon2id$"))
            return PasswordHashAlgorithm.Argon2id;

        if (storedHash.StartsWith("$pbkdf2-sha512$"))
            return PasswordHashAlgorithm.Pbkdf2Sha512;

        return null;
    }

    #endregion

    #region Password Validation

    /// <summary>
    /// Validates a password against the specified policy.
    /// </summary>
    public static PasswordValidationResult ValidatePassword(string password, PasswordPolicy? policy = null, string? username = null)
    {
        policy ??= PasswordPolicy.Secure;
        var errors = new List<string>();

        if (string.IsNullOrEmpty(password))
        {
            errors.Add("Password is required");
            return PasswordValidationResult.Failure([.. errors]);
        }

        if (password.Length < policy.MinLength)
            errors.Add($"Password must be at least {policy.MinLength} characters");

        if (password.Length > policy.MaxLength)
            errors.Add($"Password must be at most {policy.MaxLength} characters");

        if (policy.RequireUppercase && !password.Any(char.IsUpper))
            errors.Add("Password must contain at least one uppercase letter");

        if (policy.RequireLowercase && !password.Any(char.IsLower))
            errors.Add("Password must contain at least one lowercase letter");

        if (policy.RequireDigit && !password.Any(char.IsDigit))
            errors.Add("Password must contain at least one digit");

        if (policy.RequireSpecialChar && !SpecialCharRegex().IsMatch(password))
            errors.Add("Password must contain at least one special character (!@#$%^&*...)");

        if (policy.RejectCommonPasswords && CommonPasswords.Contains(password))
            errors.Add("Password is too common and easily guessable");

        if (policy.RejectUsernameInPassword && !string.IsNullOrEmpty(username) &&
            password.Contains(username, StringComparison.OrdinalIgnoreCase))
            errors.Add("Password cannot contain your username");

        return errors.Count == 0
            ? PasswordValidationResult.Success
            : PasswordValidationResult.Failure([.. errors]);
    }

    /// <summary>
    /// Estimates password strength on a scale of 0-100.
    /// </summary>
    public static int EstimateStrength(string password)
    {
        if (string.IsNullOrEmpty(password))
            return 0;

        var score = 0;

        // Length scoring
        score += Math.Min(password.Length * 4, 40);

        // Character variety
        if (password.Any(char.IsUpper)) score += 10;
        if (password.Any(char.IsLower)) score += 10;
        if (password.Any(char.IsDigit)) score += 10;
        if (SpecialCharRegex().IsMatch(password)) score += 15;

        // Bonus for mixed case and symbols together
        if (password.Any(char.IsUpper) && password.Any(char.IsLower) &&
            password.Any(char.IsDigit) && SpecialCharRegex().IsMatch(password))
            score += 15;

        // Penalty for common patterns
        if (CommonPasswords.Contains(password)) score -= 50;
        if (SequentialCharsRegex().IsMatch(password)) score -= 10;
        if (RepeatedCharsRegex().IsMatch(password)) score -= 10;

        return Math.Clamp(score, 0, 100);
    }

    #endregion

    [GeneratedRegex(@"m=(?<m>\d+),t=(?<t>\d+),p=(?<p>\d+)")]
    private static partial Regex Argon2ParamsRegex();

    [GeneratedRegex(@"[!@#$%^&*()_+\-=\[\]{};':""\\|,.<>\/?]")]
    private static partial Regex SpecialCharRegex();

    [GeneratedRegex(@"(012|123|234|345|456|567|678|789|890|abc|bcd|cde|def|efg|fgh|ghi|hij|ijk|jkl|klm|lmn|mno|nop|opq|pqr|qrs|rst|stu|tuv|uvw|vwx|wxy|xyz)", RegexOptions.IgnoreCase)]
    private static partial Regex SequentialCharsRegex();

    [GeneratedRegex(@"(.)\1{2,}")]
    private static partial Regex RepeatedCharsRegex();
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
