using MemoryPack;

namespace OpenRSC.Server.Infrastructure.Serialization;

/// <summary>
/// MemoryPack serializer - fastest binary serialization for .NET.
/// Zero-allocation, AOT-friendly, and extremely fast.
/// </summary>
public sealed class MemoryPackSerializerAdapter : ISerializer
{
    public string FormatName => "MemoryPack";

    public byte[] Serialize<T>(T value)
    {
        return MemoryPackSerializer.Serialize(value);
    }

    public int Serialize<T>(T value, Span<byte> buffer)
    {
        var writer = new MemoryPackWriter<SpanBufferWriter>(new SpanBufferWriter(buffer));
        MemoryPackSerializer.Serialize(ref writer, value);
        return writer.WrittenCount;
    }

    public void Serialize<T>(T value, Stream stream)
    {
        MemoryPackSerializer.Serialize(stream, value);
    }

    public T? Deserialize<T>(ReadOnlySpan<byte> data)
    {
        return MemoryPackSerializer.Deserialize<T>(data);
    }

    public T? Deserialize<T>(Stream stream)
    {
        using var ms = new MemoryStream();
        stream.CopyTo(ms);
        return MemoryPackSerializer.Deserialize<T>(ms.ToArray());
    }

    public async ValueTask SerializeAsync<T>(T value, Stream stream, CancellationToken cancellationToken = default)
    {
        await MemoryPackSerializer.SerializeAsync(stream, value, cancellationToken: cancellationToken);
    }

    public async ValueTask<T?> DeserializeAsync<T>(Stream stream, CancellationToken cancellationToken = default)
    {
        return await MemoryPackSerializer.DeserializeAsync<T>(stream, cancellationToken: cancellationToken);
    }

    /// <summary>
    /// Internal buffer writer for span-based serialization.
    /// </summary>
    private ref struct SpanBufferWriter
    {
        private readonly Span<byte> _buffer;
        private int _position;

        public SpanBufferWriter(Span<byte> buffer)
        {
            _buffer = buffer;
            _position = 0;
        }

        public readonly int WrittenCount => _position;

        public Span<byte> GetSpan(int sizeHint)
        {
            if (_position + sizeHint > _buffer.Length)
                throw new InvalidOperationException("Buffer too small");
            return _buffer[_position..];
        }

        public void Advance(int count)
        {
            _position += count;
        }
    }
}

/// <summary>
/// MemoryPack formatter provider for custom types.
/// </summary>
public static class MemoryPackFormatters
{
    /// <summary>
    /// Registers custom formatters for game-specific types.
    /// Call this during application startup.
    /// </summary>
    public static void RegisterCustomFormatters()
    {
        // Custom formatters can be registered here for complex game types
        // MemoryPackFormatterProvider.Register<CustomType>(new CustomFormatter());
    }
}
