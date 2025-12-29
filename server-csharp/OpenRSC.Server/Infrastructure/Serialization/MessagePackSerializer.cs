using MessagePack;
using MessagePack.Resolvers;

namespace OpenRSC.Server.Infrastructure.Serialization;

/// <summary>
/// MessagePack serializer - compact binary format with cross-platform support.
/// Ideal for network communication and data persistence.
/// </summary>
public sealed class MessagePackSerializerAdapter : ISerializer
{
    private readonly MessagePackSerializerOptions _options;

    public MessagePackSerializerAdapter() : this(CreateDefaultOptions())
    {
    }

    public MessagePackSerializerAdapter(MessagePackSerializerOptions options)
    {
        _options = options;
    }

    public string FormatName => "MessagePack";

    public byte[] Serialize<T>(T value)
    {
        return MessagePack.MessagePackSerializer.Serialize(value, _options);
    }

    public int Serialize<T>(T value, Span<byte> buffer)
    {
        var data = MessagePack.MessagePackSerializer.Serialize(value, _options);
        if (data.Length > buffer.Length)
            throw new InvalidOperationException($"Buffer too small. Required: {data.Length}, Available: {buffer.Length}");

        data.AsSpan().CopyTo(buffer);
        return data.Length;
    }

    public void Serialize<T>(T value, Stream stream)
    {
        MessagePack.MessagePackSerializer.Serialize(stream, value, _options);
    }

    public T? Deserialize<T>(ReadOnlySpan<byte> data)
    {
        return MessagePack.MessagePackSerializer.Deserialize<T>(new ReadOnlyMemory<byte>(data.ToArray()), _options);
    }

    public T? Deserialize<T>(Stream stream)
    {
        return MessagePack.MessagePackSerializer.Deserialize<T>(stream, _options);
    }

    public async ValueTask SerializeAsync<T>(T value, Stream stream, CancellationToken cancellationToken = default)
    {
        await MessagePack.MessagePackSerializer.SerializeAsync(stream, value, _options, cancellationToken);
    }

    public async ValueTask<T?> DeserializeAsync<T>(Stream stream, CancellationToken cancellationToken = default)
    {
        return await MessagePack.MessagePackSerializer.DeserializeAsync<T>(stream, _options, cancellationToken);
    }

    /// <summary>
    /// Creates default MessagePack options optimized for game server use.
    /// </summary>
    private static MessagePackSerializerOptions CreateDefaultOptions()
    {
        // Use composite resolver with standard + contractless for flexibility
        var resolver = CompositeResolver.Create(
            StandardResolver.Instance,
            ContractlessStandardResolver.Instance
        );

        return MessagePackSerializerOptions.Standard
            .WithResolver(resolver)
            .WithSecurity(MessagePackSecurity.UntrustedData) // Safe for network data
            .WithCompression(MessagePackCompression.Lz4BlockArray); // Fast compression
    }

    /// <summary>
    /// Creates options with LZ4 compression for large payloads.
    /// </summary>
    public static MessagePackSerializerOptions CreateCompressedOptions()
    {
        return CreateDefaultOptions()
            .WithCompression(MessagePackCompression.Lz4BlockArray);
    }

    /// <summary>
    /// Creates options without compression for small packets.
    /// </summary>
    public static MessagePackSerializerOptions CreateUncompressedOptions()
    {
        return CreateDefaultOptions()
            .WithCompression(MessagePackCompression.None);
    }
}

/// <summary>
/// MessagePack resolver configuration for game types.
/// </summary>
public static class MessagePackResolverConfig
{
    private static bool _initialized;
    private static readonly object _lock = new();

    /// <summary>
    /// Initializes MessagePack with game-specific resolvers.
    /// Call this once during application startup.
    /// </summary>
    public static void Initialize()
    {
        if (_initialized) return;

        lock (_lock)
        {
            if (_initialized) return;

            // Register composite resolver for all game types
            var resolver = CompositeResolver.Create(
                // Add custom game type resolvers here
                StandardResolver.Instance,
                ContractlessStandardResolver.Instance
            );

            MessagePackSerializerOptions.Standard.WithResolver(resolver);
            _initialized = true;
        }
    }
}
