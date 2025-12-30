using System.Buffers;
using MessagePack;
using OpenRSC.Server.Infrastructure.Serialization;

namespace OpenRSC.Server.Network;

/// <summary>
/// Protocol format for client-server communication.
/// </summary>
public enum ProtocolFormat
{
    /// <summary>
    /// Original RSC binary format - big-endian, custom packet structure.
    /// Compatible with legacy clients.
    /// </summary>
    RscBinary,

    /// <summary>
    /// MessagePack format - compact, cross-platform binary serialization.
    /// Recommended for modern clients.
    /// </summary>
    MessagePack
}

/// <summary>
/// Manages protocol negotiation and serialization for client connections.
/// Supports both RSC binary and MessagePack formats for backwards compatibility.
/// </summary>
public sealed class ProtocolAdapter
{
    private readonly MessagePackSerializerAdapter _messagePackSerializer;
    private readonly ILogger<ProtocolAdapter> _logger;

    /// <summary>
    /// Magic byte indicating MessagePack protocol.
    /// First byte of handshake determines protocol.
    /// </summary>
    public const byte MessagePackMagic = 0xC1; // MessagePack fixext marker

    /// <summary>
    /// Protocol version for MessagePack format.
    /// </summary>
    public const byte MessagePackVersion = 1;

    public ProtocolAdapter(ILogger<ProtocolAdapter> logger)
    {
        _messagePackSerializer = new MessagePackSerializerAdapter();
        _logger = logger;
    }

    /// <summary>
    /// Detects the protocol format from the first bytes of a connection.
    /// </summary>
    public ProtocolFormat DetectProtocol(ReadOnlySpan<byte> initialBytes)
    {
        if (initialBytes.Length == 0)
        {
            return ProtocolFormat.RscBinary; // Default to legacy
        }

        // Check for MessagePack magic byte
        if (initialBytes[0] == MessagePackMagic)
        {
            return ProtocolFormat.MessagePack;
        }

        // Legacy RSC clients send specific opcodes
        // First bytes are typically length (2 bytes big-endian) + opcode
        return ProtocolFormat.RscBinary;
    }

    /// <summary>
    /// Creates a packet encoder for the specified protocol.
    /// </summary>
    public IPacketEncoder CreateEncoder(ProtocolFormat format)
    {
        return format switch
        {
            ProtocolFormat.MessagePack => new MessagePackEncoder(_messagePackSerializer),
            ProtocolFormat.RscBinary => new RscBinaryEncoder(),
            _ => new RscBinaryEncoder()
        };
    }

    /// <summary>
    /// Creates a packet decoder for the specified protocol.
    /// </summary>
    public IPacketDecoder CreateDecoder(ProtocolFormat format)
    {
        return format switch
        {
            ProtocolFormat.MessagePack => new MessagePackDecoder(_messagePackSerializer),
            ProtocolFormat.RscBinary => new RscBinaryDecoder(),
            _ => new RscBinaryDecoder()
        };
    }
}

/// <summary>
/// Interface for encoding packets to wire format.
/// </summary>
public interface IPacketEncoder
{
    /// <summary>
    /// Gets the protocol format.
    /// </summary>
    ProtocolFormat Format { get; }

    /// <summary>
    /// Encodes a packet to bytes.
    /// </summary>
    byte[] Encode(Packet packet);

    /// <summary>
    /// Encodes a packet to the provided buffer.
    /// Returns the number of bytes written.
    /// </summary>
    int Encode(Packet packet, Span<byte> buffer);

    /// <summary>
    /// Encodes a typed message to bytes.
    /// </summary>
    byte[] Encode<T>(byte opcode, T message);
}

/// <summary>
/// Interface for decoding packets from wire format.
/// </summary>
public interface IPacketDecoder
{
    /// <summary>
    /// Gets the protocol format.
    /// </summary>
    ProtocolFormat Format { get; }

    /// <summary>
    /// Decodes bytes into a packet.
    /// </summary>
    Packet? Decode(ReadOnlySpan<byte> data);

    /// <summary>
    /// Decodes bytes into a typed message.
    /// </summary>
    T? DecodeAs<T>(ReadOnlySpan<byte> data);
}

/// <summary>
/// RSC binary format encoder.
/// Packet format: [length:2 bytes BE][opcode:1 byte][payload:variable]
/// </summary>
public sealed class RscBinaryEncoder : IPacketEncoder
{
    public ProtocolFormat Format => ProtocolFormat.RscBinary;

    public byte[] Encode(Packet packet)
    {
        var payload = packet.AsSpan();
        var totalLength = 2 + 1 + payload.Length; // length + opcode + payload
        var result = new byte[totalLength];

        // Write length (big-endian, includes opcode + payload)
        var packetLength = (ushort)(1 + payload.Length);
        result[0] = (byte)(packetLength >> 8);
        result[1] = (byte)(packetLength & 0xFF);

        // Write opcode
        result[2] = packet.Opcode;

        // Write payload
        payload.CopyTo(result.AsSpan(3));

        return result;
    }

    public int Encode(Packet packet, Span<byte> buffer)
    {
        var payload = packet.AsSpan();
        var totalLength = 2 + 1 + payload.Length;

        if (buffer.Length < totalLength)
        {
            throw new InvalidOperationException($"Buffer too small. Required: {totalLength}, Available: {buffer.Length}");
        }

        var packetLength = (ushort)(1 + payload.Length);
        buffer[0] = (byte)(packetLength >> 8);
        buffer[1] = (byte)(packetLength & 0xFF);
        buffer[2] = packet.Opcode;
        payload.CopyTo(buffer[3..]);

        return totalLength;
    }

    public byte[] Encode<T>(byte opcode, T message)
    {
        // For RSC binary, we need to serialize the message manually
        // This is typically done with the Packet builder
        throw new NotSupportedException("Use Packet class for RSC binary encoding");
    }
}

/// <summary>
/// RSC binary format decoder.
/// </summary>
public sealed class RscBinaryDecoder : IPacketDecoder
{
    public ProtocolFormat Format => ProtocolFormat.RscBinary;

    public Packet? Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < 3)
        {
            return null; // Not enough data
        }

        // Read length (big-endian)
        var length = (ushort)((data[0] << 8) | data[1]);

        if (data.Length < 2 + length)
        {
            return null; // Incomplete packet
        }

        // Read opcode
        var opcode = data[2];

        // Read payload
        var payload = data.Slice(3, length - 1);

        return new Packet(opcode, payload);
    }

    public T? DecodeAs<T>(ReadOnlySpan<byte> data)
    {
        throw new NotSupportedException("Use Packet class for RSC binary decoding");
    }
}

/// <summary>
/// MessagePack format encoder.
/// Packet format: [magic:1][version:1][opcode:1][length:4 LE][messagepack payload]
/// </summary>
public sealed class MessagePackEncoder : IPacketEncoder
{
    private readonly MessagePackSerializerAdapter _serializer;

    public MessagePackEncoder(MessagePackSerializerAdapter serializer)
    {
        _serializer = serializer;
    }

    public ProtocolFormat Format => ProtocolFormat.MessagePack;

    public byte[] Encode(Packet packet)
    {
        // Convert Packet to MessagePackPacket wrapper
        var wrapper = new MessagePackPacket
        {
            Opcode = packet.Opcode,
            Payload = packet.AsSpan().ToArray()
        };

        var serialized = _serializer.Serialize(wrapper);
        return CreateFrame(serialized);
    }

    public int Encode(Packet packet, Span<byte> buffer)
    {
        var encoded = Encode(packet);
        if (encoded.Length > buffer.Length)
        {
            throw new InvalidOperationException($"Buffer too small. Required: {encoded.Length}, Available: {buffer.Length}");
        }

        encoded.AsSpan().CopyTo(buffer);
        return encoded.Length;
    }

    public byte[] Encode<T>(byte opcode, T message)
    {
        var payload = _serializer.Serialize(message);

        var wrapper = new MessagePackPacket
        {
            Opcode = opcode,
            Payload = payload
        };

        var serialized = _serializer.Serialize(wrapper);
        return CreateFrame(serialized);
    }

    private static byte[] CreateFrame(byte[] payload)
    {
        var result = new byte[6 + payload.Length];
        result[0] = ProtocolAdapter.MessagePackMagic;
        result[1] = ProtocolAdapter.MessagePackVersion;
        result[2] = (byte)((payload.Length >> 24) & 0xFF);
        result[3] = (byte)((payload.Length >> 16) & 0xFF);
        result[4] = (byte)((payload.Length >> 8) & 0xFF);
        result[5] = (byte)(payload.Length & 0xFF);
        payload.CopyTo(result.AsSpan(6));
        return result;
    }
}

/// <summary>
/// MessagePack format decoder.
/// </summary>
public sealed class MessagePackDecoder : IPacketDecoder
{
    private readonly MessagePackSerializerAdapter _serializer;

    public MessagePackDecoder(MessagePackSerializerAdapter serializer)
    {
        _serializer = serializer;
    }

    public ProtocolFormat Format => ProtocolFormat.MessagePack;

    public Packet? Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < 6)
        {
            return null; // Not enough data for header
        }

        // Verify magic and version
        if (data[0] != ProtocolAdapter.MessagePackMagic)
        {
            return null;
        }

        // Read length (big-endian)
        var length = (data[2] << 24) | (data[3] << 16) | (data[4] << 8) | data[5];

        if (data.Length < 6 + length)
        {
            return null; // Incomplete packet
        }

        // Deserialize wrapper
        var payload = data.Slice(6, length);
        var wrapper = _serializer.Deserialize<MessagePackPacket>(payload);

        if (wrapper == null)
        {
            return null;
        }

        return new Packet(wrapper.Opcode, wrapper.Payload);
    }

    public T? DecodeAs<T>(ReadOnlySpan<byte> data)
    {
        if (data.Length < 6)
        {
            return default;
        }

        var length = (data[2] << 24) | (data[3] << 16) | (data[4] << 8) | data[5];
        var payload = data.Slice(6, length);
        var wrapper = _serializer.Deserialize<MessagePackPacket>(payload);

        if (wrapper == null)
        {
            return default;
        }

        return _serializer.Deserialize<T>(wrapper.Payload);
    }
}

/// <summary>
/// Wrapper for MessagePack packet format.
/// </summary>
[MessagePackObject]
public sealed class MessagePackPacket
{
    [Key(0)]
    public byte Opcode { get; set; }

    [Key(1)]
    public byte[] Payload { get; set; } = [];
}

/// <summary>
/// Client connection protocol state.
/// </summary>
public sealed class ClientProtocolState
{
    /// <summary>
    /// The negotiated protocol format.
    /// </summary>
    public ProtocolFormat Format { get; set; } = ProtocolFormat.RscBinary;

    /// <summary>
    /// The packet encoder for this client.
    /// </summary>
    public IPacketEncoder Encoder { get; set; } = new RscBinaryEncoder();

    /// <summary>
    /// The packet decoder for this client.
    /// </summary>
    public IPacketDecoder Decoder { get; set; } = new RscBinaryDecoder();

    /// <summary>
    /// Whether protocol has been negotiated.
    /// </summary>
    public bool IsNegotiated { get; set; }

    /// <summary>
    /// Client-reported protocol version.
    /// </summary>
    public int ProtocolVersion { get; set; }

    /// <summary>
    /// Whether the client supports compression.
    /// </summary>
    public bool SupportsCompression { get; set; }
}

/// <summary>
/// Extension methods for protocol adaptation.
/// </summary>
public static class ProtocolExtensions
{
    /// <summary>
    /// Encodes and sends a message using the client's protocol.
    /// </summary>
    public static byte[] EncodeForClient<T>(this ClientProtocolState state, byte opcode, T message)
    {
        if (state.Format == ProtocolFormat.MessagePack && state.Encoder is MessagePackEncoder mpEncoder)
        {
            return mpEncoder.Encode(opcode, message);
        }

        // For RSC binary, caller needs to build the packet manually
        throw new InvalidOperationException("Use Packet class for RSC binary protocol");
    }

    /// <summary>
    /// Decodes a message from the client's protocol.
    /// </summary>
    public static T? DecodeFromClient<T>(this ClientProtocolState state, ReadOnlySpan<byte> data)
    {
        if (state.Format == ProtocolFormat.MessagePack && state.Decoder is MessagePackDecoder mpDecoder)
        {
            return mpDecoder.DecodeAs<T>(data);
        }

        // For RSC binary, caller needs to read the packet manually
        throw new InvalidOperationException("Use Packet class for RSC binary protocol");
    }

    /// <summary>
    /// Adds protocol adapter services to the DI container.
    /// </summary>
    public static IServiceCollection AddProtocolAdapter(this IServiceCollection services)
    {
        services.AddSingleton<ProtocolAdapter>();
        return services;
    }
}
