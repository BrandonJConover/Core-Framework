using System.Buffers;
using System.IO.Compression;
using System.Runtime.CompilerServices;

namespace OpenRSC.Server.Network;

/// <summary>
/// High-performance packet compression using Brotli (best ratio) or GZip (fallback).
/// Optimized for game packets with minimal allocations.
/// </summary>
public static class PacketCompression
{
    /// <summary>
    /// Minimum packet size to consider for compression.
    /// Packets smaller than this are not worth compressing.
    /// </summary>
    public const int CompressionThreshold = 128;

    /// <summary>
    /// Compression flag bytes for protocol.
    /// </summary>
    public static class Flags
    {
        public const byte Uncompressed = 0x00;
        public const byte Compressed = 0x01;
        public const byte BatchCompressed = 0x02;
        public const byte BatchUncompressed = 0x03;
    }

    /// <summary>
    /// Compresses data using Brotli compression.
    /// Returns null if compression doesn't reduce size.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static byte[]? Compress(ReadOnlySpan<byte> data)
    {
        if (data.Length < CompressionThreshold)
            return null;

        // Estimate max compressed size
        var maxCompressedSize = BrotliEncoder.GetMaxCompressedLength(data.Length);
        var buffer = ArrayPool<byte>.Shared.Rent(maxCompressedSize + 4);

        try
        {
            // Write original size (big-endian) for decompression
            buffer[0] = (byte)(data.Length >> 24);
            buffer[1] = (byte)(data.Length >> 16);
            buffer[2] = (byte)(data.Length >> 8);
            buffer[3] = (byte)(data.Length & 0xFF);

            // Compress with quality level 4 (fast but decent ratio)
            if (BrotliEncoder.TryCompress(data, buffer.AsSpan(4), out var bytesWritten, 4, 22))
            {
                var totalSize = bytesWritten + 4;

                // Only use compression if it actually reduces size
                if (totalSize < data.Length)
                {
                    var result = new byte[totalSize];
                    buffer.AsSpan(0, totalSize).CopyTo(result);
                    return result;
                }
            }

            return null;
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }

    /// <summary>
    /// Decompresses Brotli-compressed data.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static byte[]? Decompress(ReadOnlySpan<byte> compressedData)
    {
        if (compressedData.Length < 4)
            return null;

        // Read original size (big-endian)
        var originalSize = (compressedData[0] << 24) |
                          (compressedData[1] << 16) |
                          (compressedData[2] << 8) |
                          compressedData[3];

        // Sanity check (max 1MB decompressed)
        if (originalSize <= 0 || originalSize > 1_048_576)
            return null;

        var result = new byte[originalSize];
        var compressed = compressedData[4..];

        if (BrotliDecoder.TryDecompress(compressed, result, out var bytesWritten) &&
            bytesWritten == originalSize)
        {
            return result;
        }

        return null;
    }

    /// <summary>
    /// Compresses multiple packets into a single batch.
    /// </summary>
    public static byte[]? CompressBatch(ReadOnlySpan<Packet> packets)
    {
        if (packets.Length == 0)
            return null;

        // Calculate total size
        var totalSize = 0;
        foreach (var packet in packets)
        {
            totalSize += 3 + packet.Length; // 2 bytes length + 1 byte opcode + payload
        }

        // Build combined data
        var combined = new byte[totalSize];
        var offset = 0;

        foreach (var packet in packets)
        {
            var frameLength = packet.Length + 1;
            combined[offset++] = (byte)(frameLength >> 8);
            combined[offset++] = (byte)(frameLength & 0xFF);
            combined[offset++] = packet.Opcode;
            packet.AsSpan().CopyTo(combined.AsSpan(offset));
            offset += packet.Length;
        }

        return Compress(combined);
    }
}
