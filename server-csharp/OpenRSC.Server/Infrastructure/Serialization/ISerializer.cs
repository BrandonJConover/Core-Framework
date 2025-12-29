namespace OpenRSC.Server.Infrastructure.Serialization;

/// <summary>
/// Unified serialization interface supporting multiple formats.
/// </summary>
public interface ISerializer
{
    /// <summary>
    /// Gets the serialization format name.
    /// </summary>
    string FormatName { get; }

    /// <summary>
    /// Serializes an object to a byte array.
    /// </summary>
    byte[] Serialize<T>(T value);

    /// <summary>
    /// Serializes an object to the provided buffer.
    /// </summary>
    int Serialize<T>(T value, Span<byte> buffer);

    /// <summary>
    /// Serializes an object to a stream.
    /// </summary>
    void Serialize<T>(T value, Stream stream);

    /// <summary>
    /// Deserializes a byte array to an object.
    /// </summary>
    T? Deserialize<T>(ReadOnlySpan<byte> data);

    /// <summary>
    /// Deserializes from a stream to an object.
    /// </summary>
    T? Deserialize<T>(Stream stream);

    /// <summary>
    /// Asynchronously serializes an object to a stream.
    /// </summary>
    ValueTask SerializeAsync<T>(T value, Stream stream, CancellationToken cancellationToken = default);

    /// <summary>
    /// Asynchronously deserializes from a stream to an object.
    /// </summary>
    ValueTask<T?> DeserializeAsync<T>(Stream stream, CancellationToken cancellationToken = default);
}

/// <summary>
/// Serialization format enumeration.
/// </summary>
public enum SerializationFormat
{
    /// <summary>
    /// MemoryPack - fastest binary serialization for .NET
    /// </summary>
    MemoryPack,

    /// <summary>
    /// MessagePack - compact binary format, cross-platform
    /// </summary>
    MessagePack,

    /// <summary>
    /// FlatBuffers - zero-copy serialization for large data
    /// </summary>
    FlatBuffers,

    /// <summary>
    /// JSON - human-readable, for debugging and APIs
    /// </summary>
    Json
}

/// <summary>
/// Factory for creating serializers based on format.
/// </summary>
public interface ISerializerFactory
{
    /// <summary>
    /// Gets a serializer for the specified format.
    /// </summary>
    ISerializer GetSerializer(SerializationFormat format);

    /// <summary>
    /// Gets the default serializer.
    /// </summary>
    ISerializer Default { get; }
}
