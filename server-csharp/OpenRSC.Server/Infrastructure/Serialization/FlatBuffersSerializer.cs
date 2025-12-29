using System.Buffers;
using Google.FlatBuffers;

namespace OpenRSC.Server.Infrastructure.Serialization;

/// <summary>
/// FlatBuffers serializer - zero-copy serialization for performance-critical scenarios.
/// Best for large data structures that need direct memory access without deserialization.
/// </summary>
/// <remarks>
/// FlatBuffers requires schema-generated code. This adapter provides a bridge
/// for types that implement IFlatBufferSerializable.
/// </remarks>
public sealed class FlatBuffersSerializerAdapter : ISerializer
{
    private readonly ArrayPool<byte> _arrayPool;

    public FlatBuffersSerializerAdapter() : this(ArrayPool<byte>.Shared)
    {
    }

    public FlatBuffersSerializerAdapter(ArrayPool<byte> arrayPool)
    {
        _arrayPool = arrayPool;
    }

    public string FormatName => "FlatBuffers";

    public byte[] Serialize<T>(T value)
    {
        if (value is IFlatBufferSerializable serializable)
        {
            var builder = new FlatBufferBuilder(256);
            var offset = serializable.Serialize(builder);
            builder.Finish(offset.Value);
            return builder.SizedByteArray();
        }

        throw new NotSupportedException(
            $"Type {typeof(T).Name} must implement IFlatBufferSerializable for FlatBuffers serialization");
    }

    public int Serialize<T>(T value, Span<byte> buffer)
    {
        var data = Serialize(value);
        if (data.Length > buffer.Length)
            throw new InvalidOperationException($"Buffer too small. Required: {data.Length}, Available: {buffer.Length}");

        data.AsSpan().CopyTo(buffer);
        return data.Length;
    }

    public void Serialize<T>(T value, Stream stream)
    {
        var data = Serialize(value);
        stream.Write(data, 0, data.Length);
    }

    public T? Deserialize<T>(ReadOnlySpan<byte> data)
    {
        if (!typeof(IFlatBufferDeserializable<T>).IsAssignableFrom(typeof(T)))
        {
            throw new NotSupportedException(
                $"Type {typeof(T).Name} must implement IFlatBufferDeserializable<T> for FlatBuffers deserialization");
        }

        var buffer = new ByteBuffer(data.ToArray());
        return FlatBufferDeserializer<T>.Deserialize(buffer);
    }

    public T? Deserialize<T>(Stream stream)
    {
        using var ms = new MemoryStream();
        stream.CopyTo(ms);
        return Deserialize<T>(ms.ToArray());
    }

    public async ValueTask SerializeAsync<T>(T value, Stream stream, CancellationToken cancellationToken = default)
    {
        var data = Serialize(value);
        await stream.WriteAsync(data, cancellationToken);
    }

    public async ValueTask<T?> DeserializeAsync<T>(Stream stream, CancellationToken cancellationToken = default)
    {
        using var ms = new MemoryStream();
        await stream.CopyToAsync(ms, cancellationToken);
        return Deserialize<T>(ms.ToArray());
    }
}

/// <summary>
/// Interface for types that can be serialized to FlatBuffers.
/// </summary>
public interface IFlatBufferSerializable
{
    /// <summary>
    /// Serializes this object to a FlatBuffer.
    /// </summary>
    Offset<TTable> Serialize<TTable>(FlatBufferBuilder builder) where TTable : struct;
}

/// <summary>
/// Interface for types that can be deserialized from FlatBuffers.
/// </summary>
public interface IFlatBufferDeserializable<out T>
{
    /// <summary>
    /// Deserializes from a FlatBuffer.
    /// </summary>
    static abstract T Deserialize(ByteBuffer buffer);
}

/// <summary>
/// Helper class for FlatBuffer deserialization.
/// </summary>
public static class FlatBufferDeserializer<T>
{
    private static Func<ByteBuffer, T>? _deserializer;

    /// <summary>
    /// Registers a deserializer for type T.
    /// </summary>
    public static void Register(Func<ByteBuffer, T> deserializer)
    {
        _deserializer = deserializer;
    }

    /// <summary>
    /// Deserializes a FlatBuffer to type T.
    /// </summary>
    public static T Deserialize(ByteBuffer buffer)
    {
        if (_deserializer == null)
            throw new InvalidOperationException($"No deserializer registered for type {typeof(T).Name}");

        return _deserializer(buffer);
    }
}

/// <summary>
/// FlatBuffer builder pool for reducing allocations.
/// </summary>
public sealed class FlatBufferBuilderPool
{
    private readonly ArrayPool<FlatBufferBuilder> _pool;
    private readonly int _initialSize;

    public FlatBufferBuilderPool(int initialSize = 1024)
    {
        _initialSize = initialSize;
        _pool = ArrayPool<FlatBufferBuilder>.Create();
    }

    /// <summary>
    /// Rents a FlatBufferBuilder from the pool.
    /// </summary>
    public FlatBufferBuilder Rent()
    {
        return new FlatBufferBuilder(_initialSize);
    }

    /// <summary>
    /// Returns a FlatBufferBuilder to the pool.
    /// </summary>
    public void Return(FlatBufferBuilder builder)
    {
        builder.Clear();
    }
}
