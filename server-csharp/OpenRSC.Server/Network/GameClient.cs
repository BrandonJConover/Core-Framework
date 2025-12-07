using System.Buffers;
using System.IO.Pipelines;
using System.Net.Sockets;
using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Network;

/// <summary>
/// Represents a connected game client.
/// Uses System.IO.Pipelines for high-performance async I/O.
/// </summary>
public sealed class GameClient : IAsyncDisposable
{
    private readonly Socket _socket;
    private readonly ILogger<GameClient> _logger;
    private readonly Pipe _receivePipe;
    private readonly SemaphoreSlim _sendLock = new(1, 1);
    private readonly CancellationTokenSource _cts = new();

    private bool _disposed;

    /// <summary>
    /// Unique client ID.
    /// </summary>
    public Guid Id { get; } = Guid.NewGuid();

    /// <summary>
    /// Remote endpoint address.
    /// </summary>
    public string RemoteAddress { get; }

    /// <summary>
    /// The player associated with this client (null if not logged in).
    /// </summary>
    public Player? Player { get; set; }

    /// <summary>
    /// Whether the client is currently connected.
    /// </summary>
    public bool IsConnected => _socket.Connected && !_disposed;

    /// <summary>
    /// Time of connection.
    /// </summary>
    public DateTime ConnectedAt { get; } = DateTime.UtcNow;

    /// <summary>
    /// Last activity timestamp.
    /// </summary>
    public DateTime LastActivity { get; private set; } = DateTime.UtcNow;

    /// <summary>
    /// Event raised when a packet is received.
    /// </summary>
    public event Func<GameClient, Packet, Task>? PacketReceived;

    /// <summary>
    /// Event raised when the client disconnects.
    /// </summary>
    public event Func<GameClient, Task>? Disconnected;

    public GameClient(Socket socket, ILogger<GameClient> logger)
    {
        _socket = socket;
        _logger = logger;
        _receivePipe = new Pipe();
        RemoteAddress = socket.RemoteEndPoint?.ToString() ?? "unknown";
    }

    /// <summary>
    /// Starts receiving data from the client.
    /// </summary>
    public async Task StartReceivingAsync()
    {
        var writing = FillPipeAsync();
        var reading = ReadPipeAsync();

        await Task.WhenAll(writing, reading);
    }

    /// <summary>
    /// Reads from socket and fills the pipe.
    /// </summary>
    private async Task FillPipeAsync()
    {
        const int minimumBufferSize = 512;
        var writer = _receivePipe.Writer;

        try
        {
            while (!_cts.Token.IsCancellationRequested)
            {
                var memory = writer.GetMemory(minimumBufferSize);
                var bytesRead = await _socket.ReceiveAsync(memory, SocketFlags.None, _cts.Token);

                if (bytesRead == 0)
                {
                    _logger.LogDebug("Client {Id} disconnected (received 0 bytes)", Id);
                    break;
                }

                LastActivity = DateTime.UtcNow;
                writer.Advance(bytesRead);

                var result = await writer.FlushAsync(_cts.Token);
                if (result.IsCompleted) break;
            }
        }
        catch (OperationCanceledException)
        {
            // Normal cancellation
        }
        catch (SocketException ex)
        {
            _logger.LogDebug(ex, "Socket error for client {Id}", Id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error receiving from client {Id}", Id);
        }
        finally
        {
            await writer.CompleteAsync();
            await OnDisconnectedAsync();
        }
    }

    /// <summary>
    /// Reads from the pipe and processes packets.
    /// </summary>
    private async Task ReadPipeAsync()
    {
        var reader = _receivePipe.Reader;

        try
        {
            while (!_cts.Token.IsCancellationRequested)
            {
                var result = await reader.ReadAsync(_cts.Token);
                var buffer = result.Buffer;

                while (TryReadPacket(ref buffer, out var packet))
                {
                    try
                    {
                        if (PacketReceived != null)
                        {
                            await PacketReceived.Invoke(this, packet);
                        }
                    }
                    finally
                    {
                        packet.Dispose();
                    }
                }

                reader.AdvanceTo(buffer.Start, buffer.End);

                if (result.IsCompleted) break;
            }
        }
        catch (OperationCanceledException)
        {
            // Normal cancellation
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing packets for client {Id}", Id);
        }
        finally
        {
            await reader.CompleteAsync();
        }
    }

    /// <summary>
    /// Tries to read a complete packet from the buffer.
    /// RSC packet format: [length:2][opcode:1][data:length-1]
    /// </summary>
    private static bool TryReadPacket(ref ReadOnlySequence<byte> buffer, out Packet packet)
    {
        packet = null!;

        // Need at least 2 bytes for length
        if (buffer.Length < 2)
            return false;

        // Read length (big-endian short)
        Span<byte> lengthBytes = stackalloc byte[2];
        buffer.Slice(0, 2).CopyTo(lengthBytes);
        var length = (lengthBytes[0] << 8) | lengthBytes[1];

        // Check if we have the complete packet
        if (buffer.Length < 2 + length)
            return false;

        // Read opcode
        var opcode = buffer.Slice(2, 1).First.Span[0];

        // Read payload
        var payloadLength = length - 1;
        Span<byte> payload = payloadLength <= 256
            ? stackalloc byte[payloadLength]
            : new byte[payloadLength];

        if (payloadLength > 0)
        {
            buffer.Slice(3, payloadLength).CopyTo(payload);
        }

        packet = new Packet(opcode, payload);
        buffer = buffer.Slice(2 + length);
        return true;
    }

    /// <summary>
    /// Sends a packet to the client.
    /// </summary>
    public async Task SendAsync(Packet packet)
    {
        if (!IsConnected) return;

        await _sendLock.WaitAsync();
        try
        {
            // Build frame: [length:2][opcode:1][data]
            var payloadLength = packet.Length;
            var frameLength = payloadLength + 1; // +1 for opcode
            var totalLength = frameLength + 2; // +2 for length prefix

            var frame = ArrayPool<byte>.Shared.Rent(totalLength);
            try
            {
                // Write length (big-endian)
                frame[0] = (byte)(frameLength >> 8);
                frame[1] = (byte)(frameLength & 0xFF);

                // Write opcode
                frame[2] = packet.Opcode;

                // Write payload
                packet.AsSpan().CopyTo(frame.AsSpan(3));

                await _socket.SendAsync(frame.AsMemory(0, totalLength), SocketFlags.None);
            }
            finally
            {
                ArrayPool<byte>.Shared.Return(frame);
            }
        }
        finally
        {
            _sendLock.Release();
        }
    }

    /// <summary>
    /// Sends multiple packets to the client.
    /// </summary>
    public async Task SendAsync(params Packet[] packets)
    {
        foreach (var packet in packets)
        {
            await SendAsync(packet);
        }
    }

    private async Task OnDisconnectedAsync()
    {
        if (Disconnected != null)
        {
            await Disconnected.Invoke(this);
        }
    }

    /// <summary>
    /// Disconnects the client.
    /// </summary>
    public async Task DisconnectAsync()
    {
        if (_disposed) return;

        try
        {
            _cts.Cancel();
            _socket.Shutdown(SocketShutdown.Both);
        }
        catch
        {
            // Ignore shutdown errors
        }

        await DisposeAsync();
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;

        _cts.Cancel();
        _cts.Dispose();
        _sendLock.Dispose();

        try
        {
            _socket.Close();
            _socket.Dispose();
        }
        catch
        {
            // Ignore close errors
        }

        await Task.CompletedTask;
    }
}
