using System.Buffers;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Network;

/// <summary>
/// Represents a connected WebSocket game client.
/// Uses JSON protocol for web/mobile compatibility.
/// </summary>
public sealed class WebSocketClient : IGameClient
{
    private readonly WebSocket _webSocket;
    private readonly ILogger<WebSocketClient> _logger;
    private readonly SemaphoreSlim _sendLock = new(1, 1);
    private readonly CancellationTokenSource _cts = new();

    private bool _disposed;

    /// <inheritdoc />
    public Guid Id { get; } = Guid.NewGuid();

    /// <inheritdoc />
    public string RemoteAddress { get; }

    /// <inheritdoc />
    public Player? Player { get; set; }

    /// <inheritdoc />
    public bool IsConnected => _webSocket.State == WebSocketState.Open && !_disposed;

    /// <inheritdoc />
    public DateTime ConnectedAt { get; } = DateTime.UtcNow;

    /// <inheritdoc />
    public DateTime LastActivity { get; private set; } = DateTime.UtcNow;

    /// <inheritdoc />
    public bool IsWebClient => true;

    /// <inheritdoc />
    public event Func<IGameClient, Packet, Task>? PacketReceived;

    /// <inheritdoc />
    public event Func<IGameClient, Task>? Disconnected;

    public WebSocketClient(WebSocket webSocket, string remoteAddress, ILogger<WebSocketClient> logger)
    {
        _webSocket = webSocket;
        _logger = logger;
        RemoteAddress = remoteAddress;
    }

    /// <inheritdoc />
    public async Task StartReceivingAsync()
    {
        var buffer = ArrayPool<byte>.Shared.Rent(4096);
        try
        {
            while (!_cts.Token.IsCancellationRequested && _webSocket.State == WebSocketState.Open)
            {
                var result = await _webSocket.ReceiveAsync(
                    buffer.AsMemory(),
                    _cts.Token);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    _logger.LogDebug("WebSocket client {Id} requested close", Id);
                    break;
                }

                if (result.MessageType == WebSocketMessageType.Text)
                {
                    LastActivity = DateTime.UtcNow;
                    await ProcessJsonMessageAsync(buffer.AsMemory(0, result.Count));
                }
                else if (result.MessageType == WebSocketMessageType.Binary)
                {
                    LastActivity = DateTime.UtcNow;
                    await ProcessBinaryMessageAsync(buffer.AsMemory(0, result.Count));
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal cancellation
        }
        catch (WebSocketException ex)
        {
            _logger.LogDebug(ex, "WebSocket error for client {Id}", Id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error receiving from WebSocket client {Id}", Id);
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
            await OnDisconnectedAsync();
        }
    }

    /// <summary>
    /// Processes a JSON message from the web client.
    /// </summary>
    private async Task ProcessJsonMessageAsync(Memory<byte> data)
    {
        try
        {
            var json = Encoding.UTF8.GetString(data.Span);
            var message = JsonSerializer.Deserialize<WebSocketMessage>(json);

            if (message is null)
            {
                _logger.LogWarning("Received invalid JSON from client {Id}", Id);
                return;
            }

            // Convert JSON message to binary packet for handlers
            var packet = ConvertToPacket(message);
            if (packet is not null && PacketReceived is not null)
            {
                try
                {
                    await PacketReceived.Invoke(this, packet);
                }
                finally
                {
                    packet.Dispose();
                }
            }
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "JSON parse error from client {Id}", Id);
        }
    }

    /// <summary>
    /// Processes a binary message (standard RSC protocol).
    /// </summary>
    private async Task ProcessBinaryMessageAsync(Memory<byte> data)
    {
        if (data.Length < 1) return;

        var opcode = data.Span[0];
        var payload = data.Length > 1 ? data.Slice(1) : Memory<byte>.Empty;

        var packet = new Packet(opcode, payload.Span);
        try
        {
            if (PacketReceived is not null)
            {
                await PacketReceived.Invoke(this, packet);
            }
        }
        finally
        {
            packet.Dispose();
        }
    }

    /// <summary>
    /// Converts a JSON WebSocket message to a binary packet.
    /// </summary>
    private Packet? ConvertToPacket(WebSocketMessage message)
    {
        var packet = new Packet((byte)message.Op);

        switch ((OpcodeIn)message.Op)
        {
            case OpcodeIn.Login:
                // Login: { op: 0, username: "...", password: "...", version: 235 }
                packet.WriteByte(0); // Not reconnecting
                packet.WriteShort((short)(message.Version ?? 235));
                packet.WriteString(message.Username ?? "");
                packet.WriteString(message.Password ?? "");
                break;

            case OpcodeIn.Logout:
                // Logout: { op: 1 }
                break;

            case OpcodeIn.Ping:
                // Ping: { op: 67 }
                break;

            case OpcodeIn.WalkToPoint:
            case OpcodeIn.WalkToEntity:
                // Walk: { op: 16, x: 100, y: 500, path: [[x,y], ...] }
                if (message.Path is not null && message.Path.Count > 0)
                {
                    // Start point
                    packet.WriteShort((short)message.Path[0][0]);
                    packet.WriteShort((short)message.Path[0][1]);
                    packet.WriteByte((byte)(message.Path.Count - 1));

                    // Additional waypoints
                    for (var i = 1; i < message.Path.Count; i++)
                    {
                        packet.WriteByte((byte)(message.Path[i][0] - message.Path[0][0]));
                        packet.WriteByte((byte)(message.Path[i][1] - message.Path[0][1]));
                    }
                }
                break;

            case OpcodeIn.PublicChat:
                // Chat: { op: 216, message: "Hello!" }
                packet.WriteString(message.Message ?? "");
                break;

            case OpcodeIn.AttackNpc:
                // AttackNpc: { op: 190, npcIndex: 5 }
                packet.WriteShort((short)(message.NpcIndex ?? 0));
                break;

            case OpcodeIn.AttackPlayer:
                // AttackPlayer: { op: 171, playerIndex: 3 }
                packet.WriteShort((short)(message.PlayerIndex ?? 0));
                break;

            case OpcodeIn.TalkToNpc:
                // TalkToNpc: { op: 153, npcIndex: 5 }
                packet.WriteShort((short)(message.NpcIndex ?? 0));
                break;

            case OpcodeIn.UseItemOnObject:
                // UseItemOnObject: { op: 115, x: 100, y: 200, itemSlot: 3 }
                packet.WriteShort((short)(message.X ?? 0));
                packet.WriteShort((short)(message.Y ?? 0));
                packet.WriteShort((short)(message.ItemSlot ?? 0));
                break;

            case OpcodeIn.UseItem:
                // UseItem: { op: 91, itemSlot: 3 }
                packet.WriteShort((short)(message.ItemSlot ?? 0));
                break;

            case OpcodeIn.DropItem:
                // DropItem: { op: 246, itemSlot: 3 }
                packet.WriteShort((short)(message.ItemSlot ?? 0));
                break;

            case OpcodeIn.EquipItem:
                // EquipItem: { op: 169, itemSlot: 3 }
                packet.WriteShort((short)(message.ItemSlot ?? 0));
                break;

            case OpcodeIn.UnequipItem:
                // UnequipItem: { op: 170, itemSlot: 3 }
                packet.WriteShort((short)(message.ItemSlot ?? 0));
                break;

            case OpcodeIn.PickupItem:
                // PickupItem: { op: 247, x: 100, y: 200, itemId: 10 }
                packet.WriteShort((short)(message.X ?? 0));
                packet.WriteShort((short)(message.Y ?? 0));
                packet.WriteShort((short)(message.ItemId ?? 0));
                break;

            case OpcodeIn.ObjectAction1:
            case OpcodeIn.ObjectAction2:
                // ObjectAction: { op: 136, x: 100, y: 200 }
                packet.WriteShort((short)(message.X ?? 0));
                packet.WriteShort((short)(message.Y ?? 0));
                break;

            case OpcodeIn.CastOnSelf:
                // CastOnSelf: { op: 137, spellId: 12 }
                packet.WriteShort((short)(message.SpellId ?? 0));
                break;

            case OpcodeIn.CastOnNpc:
                // CastOnNpc: { op: 50, spellId: 12, npcIndex: 5 }
                packet.WriteShort((short)(message.SpellId ?? 0));
                packet.WriteShort((short)(message.NpcIndex ?? 0));
                break;

            case OpcodeIn.CastOnPlayer:
                // CastOnPlayer: { op: 229, spellId: 12, playerIndex: 3 }
                packet.WriteShort((short)(message.SpellId ?? 0));
                packet.WriteShort((short)(message.PlayerIndex ?? 0));
                break;

            default:
                _logger.LogDebug("Unhandled JSON opcode {Opcode} from client {Id}", message.Op, Id);
                packet.Dispose();
                return null;
        }

        return packet;
    }

    /// <inheritdoc />
    public async Task SendAsync(Packet packet)
    {
        if (!IsConnected) return;

        await _sendLock.WaitAsync();
        try
        {
            // Convert packet to JSON for web clients
            var jsonMessage = ConvertToJsonMessage(packet);
            var json = JsonSerializer.Serialize(jsonMessage);
            var bytes = Encoding.UTF8.GetBytes(json);

            await _webSocket.SendAsync(
                bytes.AsMemory(),
                WebSocketMessageType.Text,
                true,
                _cts.Token);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending to WebSocket client {Id}", Id);
        }
        finally
        {
            _sendLock.Release();
        }
    }

    /// <summary>
    /// Converts a binary packet to a JSON message for web clients.
    /// </summary>
    private WebSocketMessage ConvertToJsonMessage(Packet packet)
    {
        var message = new WebSocketMessage { Op = packet.Opcode };

        switch ((OpcodeOut)packet.Opcode)
        {
            case OpcodeOut.ServerMessage:
                message.Message = packet.ReadString();
                break;

            case OpcodeOut.PlayerStats:
                message.Stats = ReadPlayerStats(packet);
                break;

            case OpcodeOut.PlayerInventory:
                message.Inventory = ReadInventory(packet);
                break;

            case OpcodeOut.PlayerCoords:
                message.X = packet.ReadShort();
                message.Y = packet.ReadShort();
                break;

            case OpcodeOut.LoginResponse:
                message.LoginResult = packet.ReadByte();
                break;

            case OpcodeOut.Logout:
                // No additional data
                break;

            // Add more conversions as needed
            default:
                // For unhandled opcodes, include raw data as base64
                message.RawData = Convert.ToBase64String(packet.AsSpan());
                break;
        }

        return message;
    }

    private Dictionary<string, int[]> ReadPlayerStats(Packet packet)
    {
        var stats = new Dictionary<string, int[]>();
        var skills = new[] { "Attack", "Defense", "Strength", "Hits", "Ranged", "Prayer", "Magic",
                            "Cooking", "Woodcutting", "Fletching", "Fishing", "Firemaking", "Crafting",
                            "Smithing", "Mining", "Herblaw", "Agility", "Thieving" };

        var current = new int[skills.Length];
        var max = new int[skills.Length];
        var xp = new int[skills.Length];

        for (var i = 0; i < skills.Length; i++)
            current[i] = packet.ReadByte();
        for (var i = 0; i < skills.Length; i++)
            max[i] = packet.ReadByte();
        for (var i = 0; i < skills.Length; i++)
            xp[i] = packet.ReadInt();

        for (var i = 0; i < skills.Length; i++)
            stats[skills[i]] = new[] { current[i], max[i], xp[i] };

        return stats;
    }

    private List<Dictionary<string, object>> ReadInventory(Packet packet)
    {
        var inventory = new List<Dictionary<string, object>>();
        var count = packet.ReadByte();

        for (var i = 0; i < count; i++)
        {
            var id = packet.ReadShort();
            var equipped = (id & 32768) != 0;
            var stackable = (id & 32768) != 0;

            id &= 0x7FFF;
            var amount = stackable ? packet.ReadInt() : 1;

            inventory.Add(new Dictionary<string, object>
            {
                ["id"] = id,
                ["amount"] = amount,
                ["equipped"] = equipped
            });
        }

        return inventory;
    }

    private async Task OnDisconnectedAsync()
    {
        if (Disconnected is not null)
        {
            await Disconnected.Invoke(this);
        }
    }

    /// <inheritdoc />
    public async Task DisconnectAsync()
    {
        if (_disposed) return;

        try
        {
            _cts.Cancel();
            if (_webSocket.State == WebSocketState.Open)
            {
                await _webSocket.CloseAsync(
                    WebSocketCloseStatus.NormalClosure,
                    "Server disconnecting",
                    CancellationToken.None);
            }
        }
        catch
        {
            // Ignore close errors
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
            _webSocket.Dispose();
        }
        catch
        {
            // Ignore dispose errors
        }

        await Task.CompletedTask;
    }
}

/// <summary>
/// JSON message format for WebSocket communication.
/// </summary>
public class WebSocketMessage
{
    /// <summary>
    /// Opcode (same as RSC protocol).
    /// </summary>
    public int Op { get; set; }

    // Input fields
    public string? Username { get; set; }
    public string? Password { get; set; }
    public int? Version { get; set; }
    public string? Message { get; set; }
    public int? X { get; set; }
    public int? Y { get; set; }
    public int? NpcIndex { get; set; }
    public int? PlayerIndex { get; set; }
    public int? ItemSlot { get; set; }
    public int? ItemId { get; set; }
    public int? SpellId { get; set; }
    public List<int[]>? Path { get; set; }

    // Output fields
    public int? LoginResult { get; set; }
    public Dictionary<string, int[]>? Stats { get; set; }
    public List<Dictionary<string, object>>? Inventory { get; set; }
    public string? RawData { get; set; }
}
