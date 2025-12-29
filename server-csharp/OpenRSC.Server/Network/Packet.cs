using System.Buffers;
using System.Buffers.Binary;
using System.Text;

namespace OpenRSC.Server.Network;

/// <summary>
/// Represents a network packet with read/write capabilities.
/// Uses modern Span<T> and Memory<T> for zero-allocation operations where possible.
/// </summary>
public sealed class Packet : IDisposable
{
    private byte[] _buffer;
    private int _position;
    private int _length;
    private bool _disposed;

    /// <summary>
    /// The packet opcode.
    /// </summary>
    public byte Opcode { get; set; }

    /// <summary>
    /// Current read/write position.
    /// </summary>
    public int Position => _position;

    /// <summary>
    /// Length of valid data in the packet.
    /// </summary>
    public int Length => _length;

    /// <summary>
    /// Remaining bytes to read.
    /// </summary>
    public int Remaining => _length - _position;

    /// <summary>
    /// Creates an empty packet for writing.
    /// </summary>
    public Packet(byte opcode, int initialCapacity = 256)
    {
        Opcode = opcode;
        _buffer = ArrayPool<byte>.Shared.Rent(initialCapacity);
        _position = 0;
        _length = 0;
    }

    /// <summary>
    /// Creates a packet from received data for reading.
    /// </summary>
    public Packet(byte opcode, ReadOnlySpan<byte> data)
    {
        Opcode = opcode;
        _buffer = ArrayPool<byte>.Shared.Rent(data.Length);
        data.CopyTo(_buffer);
        _position = 0;
        _length = data.Length;
    }

    #region Write Operations

    /// <summary>
    /// Ensures the buffer has enough capacity.
    /// </summary>
    private void EnsureCapacity(int additionalBytes)
    {
        var required = _length + additionalBytes;
        if (required <= _buffer.Length) return;

        var newSize = Math.Max(_buffer.Length * 2, required);
        var newBuffer = ArrayPool<byte>.Shared.Rent(newSize);
        _buffer.AsSpan(0, _length).CopyTo(newBuffer);
        ArrayPool<byte>.Shared.Return(_buffer);
        _buffer = newBuffer;
    }

    public Packet WriteByte(byte value)
    {
        EnsureCapacity(1);
        _buffer[_length++] = value;
        return this;
    }

    public Packet WriteSByte(sbyte value) => WriteByte((byte)value);

    public Packet WriteShort(short value)
    {
        EnsureCapacity(2);
        BinaryPrimitives.WriteInt16BigEndian(_buffer.AsSpan(_length), value);
        _length += 2;
        return this;
    }

    public Packet WriteUShort(ushort value) => WriteShort((short)value);

    public Packet WriteInt(int value)
    {
        EnsureCapacity(4);
        BinaryPrimitives.WriteInt32BigEndian(_buffer.AsSpan(_length), value);
        _length += 4;
        return this;
    }

    public Packet WriteLong(long value)
    {
        EnsureCapacity(8);
        BinaryPrimitives.WriteInt64BigEndian(_buffer.AsSpan(_length), value);
        _length += 8;
        return this;
    }

    public Packet WriteBytes(ReadOnlySpan<byte> data)
    {
        EnsureCapacity(data.Length);
        data.CopyTo(_buffer.AsSpan(_length));
        _length += data.Length;
        return this;
    }

    public Packet WriteString(string value)
    {
        var bytes = Encoding.ASCII.GetBytes(value);
        WriteBytes(bytes);
        WriteByte(0); // Null terminator
        return this;
    }

    /// <summary>
    /// Writes a string using RSC's compressed format.
    /// </summary>
    public Packet WriteRscString(string value)
    {
        // RSC uses a custom encoding - simplified ASCII for now
        return WriteString(value);
    }

    #endregion

    #region Read Operations

    public byte ReadByte()
    {
        if (_position >= _length)
            throw new InvalidOperationException("End of packet reached");
        return _buffer[_position++];
    }

    public sbyte ReadSByte() => (sbyte)ReadByte();

    public short ReadShort()
    {
        if (_position + 2 > _length)
            throw new InvalidOperationException("End of packet reached");
        var value = BinaryPrimitives.ReadInt16BigEndian(_buffer.AsSpan(_position));
        _position += 2;
        return value;
    }

    public ushort ReadUShort() => (ushort)ReadShort();

    public int ReadInt()
    {
        if (_position + 4 > _length)
            throw new InvalidOperationException("End of packet reached");
        var value = BinaryPrimitives.ReadInt32BigEndian(_buffer.AsSpan(_position));
        _position += 4;
        return value;
    }

    public long ReadLong()
    {
        if (_position + 8 > _length)
            throw new InvalidOperationException("End of packet reached");
        var value = BinaryPrimitives.ReadInt64BigEndian(_buffer.AsSpan(_position));
        _position += 8;
        return value;
    }

    public byte[] ReadBytes(int count)
    {
        if (_position + count > _length)
            throw new InvalidOperationException("End of packet reached");
        var data = new byte[count];
        _buffer.AsSpan(_position, count).CopyTo(data);
        _position += count;
        return data;
    }

    public string ReadString()
    {
        var start = _position;
        while (_position < _length && _buffer[_position] != 0)
            _position++;

        var str = Encoding.ASCII.GetString(_buffer, start, _position - start);
        if (_position < _length) _position++; // Skip null terminator
        return str;
    }

    #endregion

    /// <summary>
    /// Gets the packet data as a span.
    /// </summary>
    public ReadOnlySpan<byte> AsSpan() => _buffer.AsSpan(0, _length);

    /// <summary>
    /// Gets the packet data as a memory.
    /// </summary>
    public ReadOnlyMemory<byte> AsMemory() => _buffer.AsMemory(0, _length);

    /// <summary>
    /// Resets the read position.
    /// </summary>
    public void ResetPosition() => _position = 0;

    public void Dispose()
    {
        if (_disposed) return;
        ArrayPool<byte>.Shared.Return(_buffer);
        _buffer = null!;
        _disposed = true;
    }
}

/// <summary>
/// Builder for creating packets with fluent API.
/// </summary>
public static class PacketBuilder
{
    public static Packet Create(OpcodeOut opcode) => new((byte)opcode);

    public static Packet ServerMessage(string message)
    {
        return Create(OpcodeOut.ServerMessage)
            .WriteString(message);
    }

    public static Packet Logout()
    {
        return Create(OpcodeOut.Logout);
    }

    public static Packet PlayerStats(int[] stats, int[] maxStats, int[] experience)
    {
        var packet = Create(OpcodeOut.PlayerStats);
        for (var i = 0; i < stats.Length; i++)
        {
            packet.WriteByte((byte)stats[i]);
        }
        for (var i = 0; i < maxStats.Length; i++)
        {
            packet.WriteByte((byte)maxStats[i]);
        }
        for (var i = 0; i < experience.Length; i++)
        {
            packet.WriteInt(experience[i]);
        }
        return packet;
    }
}
