using Microsoft.Extensions.Options;

namespace OpenRSC.Server.Infrastructure.Serialization;

/// <summary>
/// Factory for creating and managing serializers.
/// </summary>
public sealed class SerializerFactory : ISerializerFactory
{
    private readonly Dictionary<SerializationFormat, ISerializer> _serializers;
    private readonly SerializationSettings _settings;

    public SerializerFactory(IOptions<SerializationSettings> settings)
    {
        _settings = settings.Value;
        _serializers = new Dictionary<SerializationFormat, ISerializer>
        {
            [SerializationFormat.MemoryPack] = new MemoryPackSerializerAdapter(),
            [SerializationFormat.MessagePack] = new MessagePackSerializerAdapter(),
            [SerializationFormat.FlatBuffers] = new FlatBuffersSerializerAdapter(),
            [SerializationFormat.Json] = new JsonSerializerAdapter()
        };
    }

    /// <inheritdoc />
    public ISerializer GetSerializer(SerializationFormat format)
    {
        if (_serializers.TryGetValue(format, out var serializer))
            return serializer;

        throw new ArgumentException($"Unknown serialization format: {format}", nameof(format));
    }

    /// <inheritdoc />
    public ISerializer Default => GetSerializer(_settings.DefaultFormat);

    /// <summary>
    /// Gets the MemoryPack serializer (fastest for .NET-to-.NET).
    /// </summary>
    public ISerializer MemoryPack => GetSerializer(SerializationFormat.MemoryPack);

    /// <summary>
    /// Gets the MessagePack serializer (compact, cross-platform).
    /// </summary>
    public ISerializer MessagePack => GetSerializer(SerializationFormat.MessagePack);

    /// <summary>
    /// Gets the FlatBuffers serializer (zero-copy for large data).
    /// </summary>
    public ISerializer FlatBuffers => GetSerializer(SerializationFormat.FlatBuffers);

    /// <summary>
    /// Gets the JSON serializer (human-readable).
    /// </summary>
    public ISerializer Json => GetSerializer(SerializationFormat.Json);
}

/// <summary>
/// Serialization configuration settings.
/// </summary>
public sealed class SerializationSettings
{
    public const string SectionName = "Serialization";

    /// <summary>
    /// Default serialization format.
    /// </summary>
    public SerializationFormat DefaultFormat { get; set; } = SerializationFormat.MessagePack;

    /// <summary>
    /// Use MemoryPack for internal server-to-server communication.
    /// </summary>
    public bool UseMemoryPackForInternal { get; set; } = true;

    /// <summary>
    /// Use MessagePack for client communication.
    /// </summary>
    public bool UseMessagePackForClients { get; set; } = true;

    /// <summary>
    /// Enable LZ4 compression for MessagePack.
    /// </summary>
    public bool EnableMessagePackCompression { get; set; } = true;

    /// <summary>
    /// Minimum payload size for compression (bytes).
    /// </summary>
    public int CompressionThreshold { get; set; } = 256;
}

/// <summary>
/// Extension methods for serialization service registration.
/// </summary>
public static class SerializationServiceExtensions
{
    /// <summary>
    /// Adds serialization services to the DI container.
    /// </summary>
    public static IServiceCollection AddSerializationServices(
        this IServiceCollection services,
        Action<SerializationSettings>? configure = null)
    {
        if (configure != null)
        {
            services.Configure(configure);
        }
        else
        {
            services.Configure<SerializationSettings>(_ => { });
        }

        services.AddSingleton<ISerializerFactory, SerializerFactory>();
        services.AddSingleton<ISerializer>(sp => sp.GetRequiredService<ISerializerFactory>().Default);

        // Initialize MessagePack resolvers
        MessagePackResolverConfig.Initialize();

        return services;
    }
}
