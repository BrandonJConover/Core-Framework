using System.Buffers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace OpenRSC.Server.Security;

/// <summary>
/// Data encryption service using AES-256-GCM for authenticated encryption.
/// Provides secure encryption for sensitive data at rest.
/// </summary>
public sealed class DataEncryption : IDisposable
{
    private const int KeySize = 32; // 256 bits
    private const int NonceSize = 12; // 96 bits (GCM standard)
    private const int TagSize = 16; // 128 bits

    private readonly byte[] _masterKey;
    private bool _disposed;

    /// <summary>
    /// Creates a new DataEncryption instance with the specified master key.
    /// </summary>
    /// <param name="masterKey">Base64-encoded 256-bit master key.</param>
    public DataEncryption(string masterKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(masterKey);

        _masterKey = Convert.FromBase64String(masterKey);

        if (_masterKey.Length != KeySize)
            throw new ArgumentException($"Master key must be {KeySize} bytes (256 bits)", nameof(masterKey));
    }

    /// <summary>
    /// Creates a new DataEncryption instance with the specified master key bytes.
    /// </summary>
    public DataEncryption(byte[] masterKey)
    {
        ArgumentNullException.ThrowIfNull(masterKey);

        if (masterKey.Length != KeySize)
            throw new ArgumentException($"Master key must be {KeySize} bytes (256 bits)", nameof(masterKey));

        _masterKey = new byte[KeySize];
        masterKey.CopyTo(_masterKey, 0);
    }

    /// <summary>
    /// Generates a new random 256-bit encryption key.
    /// </summary>
    public static string GenerateKey()
    {
        var key = RandomNumberGenerator.GetBytes(KeySize);
        return Convert.ToBase64String(key);
    }

    /// <summary>
    /// Derives a key from a password using Argon2id.
    /// </summary>
    public static byte[] DeriveKeyFromPassword(string password, byte[] salt)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(password);

        if (salt.Length < 16)
            throw new ArgumentException("Salt must be at least 16 bytes", nameof(salt));

        using var argon2 = new Konscious.Security.Cryptography.Argon2id(Encoding.UTF8.GetBytes(password))
        {
            Salt = salt,
            DegreeOfParallelism = 4,
            MemorySize = 65536, // 64 MB
            Iterations = 3
        };

        return argon2.GetBytes(KeySize);
    }

    #region String Encryption

    /// <summary>
    /// Encrypts a string using AES-256-GCM.
    /// Returns base64-encoded ciphertext with embedded nonce and tag.
    /// </summary>
    public string Encrypt(string plaintext)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(plaintext);

        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
        var encryptedBytes = EncryptBytes(plaintextBytes);
        return Convert.ToBase64String(encryptedBytes);
    }

    /// <summary>
    /// Decrypts a base64-encoded ciphertext string.
    /// </summary>
    public string Decrypt(string ciphertext)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentException.ThrowIfNullOrWhiteSpace(ciphertext);

        var ciphertextBytes = Convert.FromBase64String(ciphertext);
        var plaintextBytes = DecryptBytes(ciphertextBytes);
        return Encoding.UTF8.GetString(plaintextBytes);
    }

    /// <summary>
    /// Attempts to decrypt a ciphertext, returning null on failure.
    /// </summary>
    public string? TryDecrypt(string ciphertext)
    {
        try
        {
            return Decrypt(ciphertext);
        }
        catch
        {
            return null;
        }
    }

    #endregion

    #region Byte Array Encryption

    /// <summary>
    /// Encrypts bytes using AES-256-GCM.
    /// Returns ciphertext with embedded nonce and authentication tag.
    /// Format: [nonce (12 bytes)][tag (16 bytes)][ciphertext]
    /// </summary>
    public byte[] EncryptBytes(ReadOnlySpan<byte> plaintext)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        var nonce = RandomNumberGenerator.GetBytes(NonceSize);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[TagSize];

        using var aes = new AesGcm(_masterKey, TagSize);
        aes.Encrypt(nonce, plaintext, ciphertext, tag);

        // Combine: nonce + tag + ciphertext
        var result = new byte[NonceSize + TagSize + ciphertext.Length];
        nonce.CopyTo(result, 0);
        tag.CopyTo(result, NonceSize);
        ciphertext.CopyTo(result, NonceSize + TagSize);

        return result;
    }

    /// <summary>
    /// Decrypts bytes that were encrypted with EncryptBytes.
    /// </summary>
    public byte[] DecryptBytes(ReadOnlySpan<byte> encryptedData)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        if (encryptedData.Length < NonceSize + TagSize)
            throw new CryptographicException("Invalid encrypted data: too short");

        var nonce = encryptedData[..NonceSize];
        var tag = encryptedData.Slice(NonceSize, TagSize);
        var ciphertext = encryptedData[(NonceSize + TagSize)..];

        var plaintext = new byte[ciphertext.Length];

        using var aes = new AesGcm(_masterKey, TagSize);
        aes.Decrypt(nonce, ciphertext, tag, plaintext);

        return plaintext;
    }

    #endregion

    #region Object Encryption

    /// <summary>
    /// Encrypts an object by serializing to JSON then encrypting.
    /// </summary>
    public string EncryptObject<T>(T obj)
    {
        var json = JsonSerializer.Serialize(obj);
        return Encrypt(json);
    }

    /// <summary>
    /// Decrypts and deserializes an object.
    /// </summary>
    public T? DecryptObject<T>(string encryptedData)
    {
        var json = Decrypt(encryptedData);
        return JsonSerializer.Deserialize<T>(json);
    }

    #endregion

    #region Field-Level Encryption

    /// <summary>
    /// Creates a deterministic encryption of a value for use in database lookups.
    /// WARNING: Less secure than random IV encryption. Only use for fields that need searching.
    /// </summary>
    public string EncryptDeterministic(string plaintext)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(plaintext);

        // Derive a deterministic IV from the plaintext using HMAC
        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
        var nonce = DeriveNonce(plaintextBytes);

        var ciphertext = new byte[plaintextBytes.Length];
        var tag = new byte[TagSize];

        using var aes = new AesGcm(_masterKey, TagSize);
        aes.Encrypt(nonce, plaintextBytes, ciphertext, tag);

        var result = new byte[NonceSize + TagSize + ciphertext.Length];
        nonce.CopyTo(result, 0);
        tag.CopyTo(result, NonceSize);
        ciphertext.CopyTo(result, NonceSize + TagSize);

        return Convert.ToBase64String(result);
    }

    private byte[] DeriveNonce(byte[] data)
    {
        using var hmac = new HMACSHA256(_masterKey);
        var hash = hmac.ComputeHash(data);
        return hash[..NonceSize];
    }

    #endregion

    #region Secure Data Wrapper

    /// <summary>
    /// Creates a sealed envelope containing encrypted data with metadata.
    /// </summary>
    public SealedEnvelope Seal(string plaintext, string? context = null)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        var nonce = RandomNumberGenerator.GetBytes(NonceSize);
        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);

        // Include context in AAD (Additional Authenticated Data) if provided
        var aad = string.IsNullOrEmpty(context) ? [] : Encoding.UTF8.GetBytes(context);

        var ciphertext = new byte[plaintextBytes.Length];
        var tag = new byte[TagSize];

        using var aes = new AesGcm(_masterKey, TagSize);
        aes.Encrypt(nonce, plaintextBytes, ciphertext, tag, aad);

        return new SealedEnvelope
        {
            Version = 1,
            Algorithm = "AES-256-GCM",
            Nonce = Convert.ToBase64String(nonce),
            Tag = Convert.ToBase64String(tag),
            Ciphertext = Convert.ToBase64String(ciphertext),
            Context = context,
            CreatedAt = DateTime.UtcNow
        };
    }

    /// <summary>
    /// Opens a sealed envelope and returns the plaintext.
    /// </summary>
    public string Unseal(SealedEnvelope envelope)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(envelope);

        if (envelope.Version != 1 || envelope.Algorithm != "AES-256-GCM")
            throw new CryptographicException("Unsupported envelope version or algorithm");

        var nonce = Convert.FromBase64String(envelope.Nonce);
        var tag = Convert.FromBase64String(envelope.Tag);
        var ciphertext = Convert.FromBase64String(envelope.Ciphertext);
        var aad = string.IsNullOrEmpty(envelope.Context) ? [] : Encoding.UTF8.GetBytes(envelope.Context);

        var plaintext = new byte[ciphertext.Length];

        using var aes = new AesGcm(_masterKey, TagSize);
        aes.Decrypt(nonce, ciphertext, tag, plaintext, aad);

        return Encoding.UTF8.GetString(plaintext);
    }

    #endregion

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        // Securely clear the master key from memory
        CryptographicOperations.ZeroMemory(_masterKey);
    }
}

/// <summary>
/// A sealed envelope containing encrypted data with metadata.
/// Safe to serialize and store.
/// </summary>
public sealed class SealedEnvelope
{
    /// <summary>Envelope format version.</summary>
    public int Version { get; init; }

    /// <summary>Encryption algorithm used.</summary>
    public required string Algorithm { get; init; }

    /// <summary>Base64-encoded nonce/IV.</summary>
    public required string Nonce { get; init; }

    /// <summary>Base64-encoded authentication tag.</summary>
    public required string Tag { get; init; }

    /// <summary>Base64-encoded ciphertext.</summary>
    public required string Ciphertext { get; init; }

    /// <summary>Optional context string (used as AAD).</summary>
    public string? Context { get; init; }

    /// <summary>Timestamp when the envelope was created.</summary>
    public DateTime CreatedAt { get; init; }
}

/// <summary>
/// Extension methods for encrypting sensitive player data fields.
/// </summary>
public static class EncryptionExtensions
{
    private static DataEncryption? _instance;

    /// <summary>
    /// Initializes the global encryption instance.
    /// Call this at startup with your master key.
    /// </summary>
    public static void Initialize(string masterKey)
    {
        _instance?.Dispose();
        _instance = new DataEncryption(masterKey);
    }

    /// <summary>
    /// Encrypts a sensitive string value.
    /// </summary>
    public static string EncryptSensitive(this string value)
    {
        if (_instance is null)
            throw new InvalidOperationException("Encryption not initialized. Call EncryptionExtensions.Initialize() first.");

        return _instance.Encrypt(value);
    }

    /// <summary>
    /// Decrypts a sensitive string value.
    /// </summary>
    public static string DecryptSensitive(this string encryptedValue)
    {
        if (_instance is null)
            throw new InvalidOperationException("Encryption not initialized. Call EncryptionExtensions.Initialize() first.");

        return _instance.Decrypt(encryptedValue);
    }

    /// <summary>
    /// Attempts to decrypt a value, returning the original if decryption fails.
    /// Useful for migration scenarios.
    /// </summary>
    public static string DecryptOrOriginal(this string value)
    {
        if (_instance is null || string.IsNullOrEmpty(value))
            return value;

        try
        {
            return _instance.Decrypt(value);
        }
        catch
        {
            return value;
        }
    }
}

/// <summary>
/// Secure memory handling utilities.
/// </summary>
public static class SecureMemory
{
    /// <summary>
    /// Creates a secure string that is cleared when disposed.
    /// </summary>
    public static SecureBuffer<byte> RentSecure(int size)
    {
        return new SecureBuffer<byte>(size);
    }

    /// <summary>
    /// Securely compares two byte arrays in constant time.
    /// </summary>
    public static bool SecureEquals(ReadOnlySpan<byte> a, ReadOnlySpan<byte> b)
    {
        return CryptographicOperations.FixedTimeEquals(a, b);
    }
}

/// <summary>
/// A buffer that is securely cleared when disposed.
/// </summary>
public sealed class SecureBuffer<T> : IDisposable where T : struct
{
    private readonly T[] _buffer;
    private bool _disposed;

    public SecureBuffer(int size)
    {
        _buffer = ArrayPool<T>.Shared.Rent(size);
    }

    public Span<T> Span => _disposed
        ? throw new ObjectDisposedException(nameof(SecureBuffer<T>))
        : _buffer.AsSpan();

    public Memory<T> Memory => _disposed
        ? throw new ObjectDisposedException(nameof(SecureBuffer<T>))
        : _buffer.AsMemory();

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        // Clear and return to pool
        _buffer.AsSpan().Clear();
        ArrayPool<T>.Shared.Return(_buffer);
    }
}
