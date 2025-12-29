using System.Buffers;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Network;

/// <summary>
/// Represents a connected WebSocket game client.
/// Uses JSON protocol for web/mobile compatibility.
/// Optimized for minimal allocations.
/// </summary>
public sealed class WebSocketClient : IGameClient
{
    private readonly WebSocket _webSocket;
    private readonly ILogger<WebSocketClient> _logger;
    private readonly SemaphoreSlim _sendLock = new(1, 1);
    private readonly CancellationTokenSource _cts = new();
    private readonly int _maxMessageSize;

    // Cached serializer options with source generation for performance
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = false
    };

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

    public WebSocketClient(WebSocket webSocket, string remoteAddress, ILogger<WebSocketClient> logger, int maxMessageSize = 65536)
    {
        _webSocket = webSocket;
        _logger = logger;
        _maxMessageSize = maxMessageSize;
        RemoteAddress = remoteAddress;
    }

    /// <inheritdoc />
    public async Task StartReceivingAsync()
    {
        var buffer = ArrayPool<byte>.Shared.Rent(4096);
        var messageBuffer = new MemoryStream();
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

                LastActivity = DateTime.UtcNow;

                // Accumulate message fragments
                messageBuffer.Write(buffer, 0, result.Count);

                // Check message size limit
                if (messageBuffer.Length > _maxMessageSize)
                {
                    _logger.LogWarning("WebSocket client {Id} exceeded max message size ({Size} > {Max})",
                        Id, messageBuffer.Length, _maxMessageSize);
                    break;
                }

                // Process complete message
                if (result.EndOfMessage)
                {
                    var messageData = messageBuffer.ToArray();
                    messageBuffer.SetLength(0); // Reset for next message

                    if (result.MessageType == WebSocketMessageType.Text)
                    {
                        await ProcessJsonMessageAsync(messageData);
                    }
                    else if (result.MessageType == WebSocketMessageType.Binary)
                    {
                        await ProcessBinaryMessageAsync(messageData);
                    }
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
            messageBuffer.Dispose();
            await OnDisconnectedAsync();
        }
    }

    /// <summary>
    /// Processes a JSON message from the web client.
    /// </summary>
    private async Task ProcessJsonMessageAsync(byte[] data)
    {
        try
        {
            // Use Utf8JsonReader for zero-allocation parsing where possible
            var reader = new Utf8JsonReader(data);
            var message = JsonSerializer.Deserialize<WebSocketMessage>(ref reader, JsonOptions);

            if (message is null)
            {
                _logger.LogWarning("Received invalid JSON from client {Id}", Id);
                return;
            }

            // Convert JSON message to binary packet for handlers
            using var packet = ConvertToPacket(message);
            if (packet is not null && PacketReceived is not null)
            {
                await PacketReceived.Invoke(this, packet);
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
    private async Task ProcessBinaryMessageAsync(byte[] data)
    {
        if (data.Length < 1) return;

        var opcode = data[0];
        ReadOnlySpan<byte> payload = data.Length > 1 ? data.AsSpan(1) : ReadOnlySpan<byte>.Empty;

        using var packet = new Packet(opcode, payload);
        if (PacketReceived is not null)
        {
            await PacketReceived.Invoke(this, packet);
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
                packet.WriteByte(0); // Not reconnecting
                packet.WriteShort((short)(message.Version ?? 235));
                packet.WriteString(message.Username ?? "");
                packet.WriteString(message.Password ?? "");
                break;

            case OpcodeIn.Logout:
            case OpcodeIn.Ping:
                // No payload needed
                break;

            case OpcodeIn.WalkToPoint:
            case OpcodeIn.WalkToEntity:
                if (message.Path is { Count: > 0 })
                {
                    packet.WriteShort((short)message.Path[0][0]);
                    packet.WriteShort((short)message.Path[0][1]);
                    packet.WriteByte((byte)(message.Path.Count - 1));

                    var startX = message.Path[0][0];
                    var startY = message.Path[0][1];
                    for (var i = 1; i < message.Path.Count; i++)
                    {
                        packet.WriteByte((byte)(message.Path[i][0] - startX));
                        packet.WriteByte((byte)(message.Path[i][1] - startY));
                    }
                }
                break;

            case OpcodeIn.PublicChat:
                packet.WriteString(message.Message ?? "");
                break;

            case OpcodeIn.AttackNpc:
            case OpcodeIn.TalkToNpc:
                packet.WriteShort((short)(message.NpcIndex ?? 0));
                break;

            case OpcodeIn.AttackPlayer:
                packet.WriteShort((short)(message.PlayerIndex ?? 0));
                break;

            case OpcodeIn.UseItemOnObject:
                packet.WriteShort((short)(message.X ?? 0));
                packet.WriteShort((short)(message.Y ?? 0));
                packet.WriteShort((short)(message.ItemSlot ?? 0));
                break;

            case OpcodeIn.UseItem:
            case OpcodeIn.DropItem:
            case OpcodeIn.EquipItem:
            case OpcodeIn.UnequipItem:
                packet.WriteShort((short)(message.ItemSlot ?? 0));
                break;

            case OpcodeIn.PickupItem:
                packet.WriteShort((short)(message.X ?? 0));
                packet.WriteShort((short)(message.Y ?? 0));
                packet.WriteShort((short)(message.ItemId ?? 0));
                break;

            case OpcodeIn.ObjectAction1:
            case OpcodeIn.ObjectAction2:
                packet.WriteShort((short)(message.X ?? 0));
                packet.WriteShort((short)(message.Y ?? 0));
                break;

            case OpcodeIn.CastOnSelf:
                packet.WriteShort((short)(message.SpellId ?? 0));
                break;

            case OpcodeIn.CastOnNpc:
                packet.WriteShort((short)(message.SpellId ?? 0));
                packet.WriteShort((short)(message.NpcIndex ?? 0));
                break;

            case OpcodeIn.CastOnPlayer:
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

        await _sendLock.WaitAsync(_cts.Token);
        try
        {
            // Convert packet to JSON message
            var jsonMessage = ConvertToJsonMessage(packet);

            // Use pooled buffer for serialization
            var buffer = ArrayPool<byte>.Shared.Rent(4096);
            try
            {
                using var stream = new MemoryStream(buffer);
                await JsonSerializer.SerializeAsync(stream, jsonMessage, JsonOptions, _cts.Token);

                var length = (int)stream.Position;
                await _webSocket.SendAsync(
                    buffer.AsMemory(0, length),
                    WebSocketMessageType.Text,
                    true,
                    _cts.Token);
            }
            finally
            {
                ArrayPool<byte>.Shared.Return(buffer);
            }
        }
        catch (OperationCanceledException)
        {
            // Normal cancellation during shutdown
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
    private static WebSocketMessage ConvertToJsonMessage(Packet packet)
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

            default:
                // For unhandled opcodes, include raw data as base64
                message.RawData = Convert.ToBase64String(packet.AsSpan());
                break;
        }

        return message;
    }

    private static readonly string[] SkillNames =
    {
        "Attack", "Defense", "Strength", "Hits", "Ranged", "Prayer", "Magic",
        "Cooking", "Woodcutting", "Fletching", "Fishing", "Firemaking", "Crafting",
        "Smithing", "Mining", "Herblaw", "Agility", "Thieving"
    };

    private static Dictionary<string, int[]> ReadPlayerStats(Packet packet)
    {
        var skillCount = SkillNames.Length;
        var stats = new Dictionary<string, int[]>(skillCount);

        // Read all current levels, then max levels, then XP
        Span<int> current = stackalloc int[skillCount];
        Span<int> max = stackalloc int[skillCount];
        Span<int> xp = stackalloc int[skillCount];

        for (var i = 0; i < skillCount; i++)
            current[i] = packet.ReadByte();
        for (var i = 0; i < skillCount; i++)
            max[i] = packet.ReadByte();
        for (var i = 0; i < skillCount; i++)
            xp[i] = packet.ReadInt();

        for (var i = 0; i < skillCount; i++)
            stats[SkillNames[i]] = new[] { current[i], max[i], xp[i] };

        return stats;
    }

    private static List<InventoryItem> ReadInventory(Packet packet)
    {
        var count = packet.ReadByte();
        var inventory = new List<InventoryItem>(count);

        for (var i = 0; i < count; i++)
        {
            var rawId = packet.ReadShort();
            var equipped = (rawId & 32768) != 0;
            var stackable = (rawId & 32768) != 0;

            var id = rawId & 0x7FFF;
            var amount = stackable ? packet.ReadInt() : 1;

            inventory.Add(new InventoryItem(id, amount, equipped));
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
            await _cts.CancelAsync();
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

        await _cts.CancelAsync();
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
/// Inventory item for JSON serialization.
/// </summary>
public readonly record struct InventoryItem(int Id, int Amount, bool Equipped);

/// <summary>
/// JSON message format for WebSocket communication.
/// Uses records for immutability and struct-like performance.
/// </summary>
public sealed class WebSocketMessage
{
    /// <summary>Opcode (same as RSC protocol).</summary>
    [JsonPropertyName("op")]
    public int Op { get; set; }

    // Authentication fields
    [JsonPropertyName("username")]
    public string? Username { get; set; }

    [JsonPropertyName("password")]
    public string? Password { get; set; }

    [JsonPropertyName("email")]
    public string? Email { get; set; }

    /// <summary>Authentication method: "password", "token", "google", "apple", "discord".</summary>
    [JsonPropertyName("authMethod")]
    public string? AuthMethod { get; set; }

    /// <summary>OAuth ID token (for Google/Apple Sign-In from mobile).</summary>
    [JsonPropertyName("idToken")]
    public string? IdToken { get; set; }

    /// <summary>OAuth authorization code (for web OAuth flow).</summary>
    [JsonPropertyName("authCode")]
    public string? AuthCode { get; set; }

    /// <summary>Refresh token for persistent login.</summary>
    [JsonPropertyName("refreshToken")]
    public string? RefreshToken { get; set; }

    /// <summary>Device ID for token binding (from keychain).</summary>
    [JsonPropertyName("deviceId")]
    public string? DeviceId { get; set; }

    /// <summary>Device name for session display.</summary>
    [JsonPropertyName("deviceName")]
    public string? DeviceName { get; set; }

    /// <summary>Platform: "ios", "android", "web".</summary>
    [JsonPropertyName("platform")]
    public string? Platform { get; set; }

    // Device fingerprinting fields
    /// <summary>Operating system version.</summary>
    [JsonPropertyName("osVersion")]
    public string? OsVersion { get; set; }

    /// <summary>Device model (iPhone14,2, Pixel 7, etc.).</summary>
    [JsonPropertyName("deviceModel")]
    public string? DeviceModel { get; set; }

    /// <summary>Device manufacturer.</summary>
    [JsonPropertyName("manufacturer")]
    public string? Manufacturer { get; set; }

    /// <summary>Browser name (for web).</summary>
    [JsonPropertyName("browser")]
    public string? Browser { get; set; }

    /// <summary>Browser version.</summary>
    [JsonPropertyName("browserVersion")]
    public string? BrowserVersion { get; set; }

    /// <summary>User agent string.</summary>
    [JsonPropertyName("userAgent")]
    public string? UserAgent { get; set; }

    /// <summary>Screen width.</summary>
    [JsonPropertyName("screenWidth")]
    public int? ScreenWidth { get; set; }

    /// <summary>Screen height.</summary>
    [JsonPropertyName("screenHeight")]
    public int? ScreenHeight { get; set; }

    /// <summary>Screen pixel density.</summary>
    [JsonPropertyName("pixelRatio")]
    public float? PixelRatio { get; set; }

    /// <summary>Device timezone.</summary>
    [JsonPropertyName("timezone")]
    public string? Timezone { get; set; }

    /// <summary>Device language.</summary>
    [JsonPropertyName("language")]
    public string? Language { get; set; }

    /// <summary>Number of CPU cores.</summary>
    [JsonPropertyName("cpuCores")]
    public int? CpuCores { get; set; }

    /// <summary>Device memory in GB.</summary>
    [JsonPropertyName("deviceMemory")]
    public int? DeviceMemory { get; set; }

    /// <summary>WebGL renderer (for web).</summary>
    [JsonPropertyName("webglRenderer")]
    public string? WebGLRenderer { get; set; }

    /// <summary>WebGL vendor (for web).</summary>
    [JsonPropertyName("webglVendor")]
    public string? WebGLVendor { get; set; }

    /// <summary>Canvas fingerprint hash (for web).</summary>
    [JsonPropertyName("canvasHash")]
    public string? CanvasHash { get; set; }

    /// <summary>Audio context fingerprint (for web).</summary>
    [JsonPropertyName("audioHash")]
    public string? AudioHash { get; set; }

    /// <summary>Installed fonts hash (for web).</summary>
    [JsonPropertyName("fontsHash")]
    public string? FontsHash { get; set; }

    /// <summary>iOS Vendor ID or Android ID.</summary>
    [JsonPropertyName("vendorId")]
    public string? VendorId { get; set; }

    /// <summary>App version.</summary>
    [JsonPropertyName("appVersion")]
    public string? AppVersion { get; set; }

    /// <summary>App build number.</summary>
    [JsonPropertyName("appBuild")]
    public string? AppBuild { get; set; }

    /// <summary>Whether device is jailbroken/rooted.</summary>
    [JsonPropertyName("isCompromised")]
    public bool? IsCompromised { get; set; }

    /// <summary>Whether running in emulator/simulator.</summary>
    [JsonPropertyName("isEmulator")]
    public bool? IsEmulator { get; set; }

    [JsonPropertyName("version")]
    public int? Version { get; set; }

    [JsonPropertyName("message")]
    public string? Message { get; set; }

    [JsonPropertyName("x")]
    public int? X { get; set; }

    [JsonPropertyName("y")]
    public int? Y { get; set; }

    [JsonPropertyName("npcIndex")]
    public int? NpcIndex { get; set; }

    [JsonPropertyName("playerIndex")]
    public int? PlayerIndex { get; set; }

    [JsonPropertyName("itemSlot")]
    public int? ItemSlot { get; set; }

    [JsonPropertyName("itemId")]
    public int? ItemId { get; set; }

    [JsonPropertyName("spellId")]
    public int? SpellId { get; set; }

    [JsonPropertyName("path")]
    public List<int[]>? Path { get; set; }

    // Output fields
    [JsonPropertyName("loginResult")]
    public int? LoginResult { get; set; }

    /// <summary>Access token for subsequent requests.</summary>
    [JsonPropertyName("accessToken")]
    public string? AccessToken { get; set; }

    /// <summary>New refresh token (when rotated).</summary>
    [JsonPropertyName("newRefreshToken")]
    public string? NewRefreshToken { get; set; }

    /// <summary>Token expiration in seconds.</summary>
    [JsonPropertyName("expiresIn")]
    public int? ExpiresIn { get; set; }

    /// <summary>Error message for failed operations.</summary>
    [JsonPropertyName("error")]
    public string? Error { get; set; }

    /// <summary>Error description.</summary>
    [JsonPropertyName("errorDescription")]
    public string? ErrorDescription { get; set; }

    // Device verification response fields
    /// <summary>Whether the device is recognized.</summary>
    [JsonPropertyName("isKnownDevice")]
    public bool? IsKnownDevice { get; set; }

    /// <summary>Whether the device is trusted.</summary>
    [JsonPropertyName("isTrustedDevice")]
    public bool? IsTrustedDevice { get; set; }

    /// <summary>Whether additional verification is required.</summary>
    [JsonPropertyName("requiresVerification")]
    public bool? RequiresVerification { get; set; }

    /// <summary>Device risk score (0-100).</summary>
    [JsonPropertyName("riskScore")]
    public int? RiskScore { get; set; }

    /// <summary>Registered device ID.</summary>
    [JsonPropertyName("registeredDeviceId")]
    public string? RegisteredDeviceId { get; set; }

    [JsonPropertyName("stats")]
    public Dictionary<string, int[]>? Stats { get; set; }

    [JsonPropertyName("inventory")]
    public List<InventoryItem>? Inventory { get; set; }

    [JsonPropertyName("rawData")]
    public string? RawData { get; set; }
}
