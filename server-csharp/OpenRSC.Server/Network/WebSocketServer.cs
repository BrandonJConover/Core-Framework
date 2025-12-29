using System.Collections.Concurrent;
using System.Net;
using System.Net.WebSockets;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Network;

/// <summary>
/// WebSocket server for browser and mobile clients.
/// Runs as a background service with proper lifecycle management.
/// Implements security best practices for web connections.
/// </summary>
public sealed class WebSocketServer : BackgroundService
{
    private readonly ILogger<WebSocketServer> _logger;
    private readonly ILoggerFactory _loggerFactory;
    private readonly ServerSettings _settings;
    private readonly PacketDispatcher _packetDispatcher;

    private readonly ConcurrentDictionary<Guid, WebSocketClient> _clients = new();
    private readonly ConcurrentDictionary<string, int> _connectionsPerIp = new();
    private readonly HashSet<string> _allowedOrigins = new(StringComparer.OrdinalIgnoreCase);
    private HttpListener? _listener;

    /// <summary>
    /// Number of currently connected WebSocket clients.
    /// </summary>
    public int ConnectedClients => _clients.Count;

    /// <summary>
    /// Event raised when a client connects.
    /// </summary>
    public event Func<IGameClient, Task>? ClientConnected;

    /// <summary>
    /// Event raised when a client disconnects.
    /// </summary>
    public event Func<IGameClient, Task>? ClientDisconnected;

    public WebSocketServer(
        ILogger<WebSocketServer> logger,
        ILoggerFactory loggerFactory,
        IOptions<ServerSettings> settings,
        PacketDispatcher packetDispatcher)
    {
        _logger = logger;
        _loggerFactory = loggerFactory;
        _settings = settings.Value;
        _packetDispatcher = packetDispatcher;

        // Parse allowed origins
        ParseAllowedOrigins();
    }

    private void ParseAllowedOrigins()
    {
        var origins = _settings.WebSocketAllowedOrigins?.Trim() ?? "*";

        if (origins == "*")
        {
            _allowedOrigins.Add("*");
            return;
        }

        foreach (var origin in origins.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            _allowedOrigins.Add(origin.Trim());
        }

        _logger.LogInformation("WebSocket allowed origins: {Origins}",
            string.Join(", ", _allowedOrigins));
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_settings.EnableWebSockets)
        {
            _logger.LogInformation("WebSocket server disabled in configuration");
            return;
        }

        _listener = new HttpListener();

        // Support both HTTP and HTTPS if configured
        if (_settings.EnableSecureWebSockets && !string.IsNullOrEmpty(_settings.TlsCertificatePath))
        {
            _listener.Prefixes.Add($"https://+:{_settings.WebSocketPort}/");
            _logger.LogInformation("WebSocket server using secure connections (WSS)");
        }
        else
        {
            _listener.Prefixes.Add($"http://+:{_settings.WebSocketPort}/");
        }

        try
        {
            _listener.Start();
            _logger.LogInformation("WebSocket server listening on port {Port}", _settings.WebSocketPort);
            _logger.LogInformation("WebSocket endpoint: ws://localhost:{Port}/game", _settings.WebSocketPort);

            while (!stoppingToken.IsCancellationRequested)
            {
                var context = await _listener.GetContextAsync();

                if (context.Request.IsWebSocketRequest)
                {
                    _ = HandleWebSocketAsync(context, stoppingToken);
                }
                else
                {
                    await HandleHttpRequestAsync(context);
                }
            }
        }
        catch (HttpListenerException ex) when (ex.ErrorCode == 995)
        {
            _logger.LogInformation("WebSocket server shutting down...");
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("WebSocket server shutting down...");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in WebSocket server accept loop");
        }
        finally
        {
            await DisconnectAllClientsAsync();
            _listener?.Close();
        }
    }

    private async Task HandleHttpRequestAsync(HttpListenerContext context)
    {
        var response = context.Response;

        // Add security headers
        response.Headers.Add("X-Content-Type-Options", "nosniff");
        response.Headers.Add("X-Frame-Options", "DENY");
        response.Headers.Add("X-XSS-Protection", "1; mode=block");
        response.Headers.Add("Referrer-Policy", "strict-origin-when-cross-origin");
        response.ContentType = "text/html; charset=utf-8";

        var html = $@"<!DOCTYPE html>
<html>
<head>
    <title>OpenRSC WebSocket Server</title>
    <meta name=""viewport"" content=""width=device-width, initial-scale=1"">
    <meta charset=""utf-8"">
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; max-width: 600px; margin: 0 auto; background: #1a1a2e; color: #eee; }}
        h1 {{ color: #4CAF50; }}
        .status {{ background: #4CAF50; color: white; padding: 10px; border-radius: 5px; margin: 10px 0; }}
        .info {{ background: #16213e; padding: 15px; margin: 20px 0; border-radius: 5px; border: 1px solid #0f3460; }}
        code {{ background: #0f3460; padding: 2px 6px; border-radius: 3px; color: #e94560; }}
        pre {{ background: #0f3460; padding: 15px; border-radius: 5px; overflow-x: auto; }}
        pre code {{ background: none; padding: 0; }}
    </style>
</head>
<body>
    <h1>OpenRSC</h1>
    <div class=""status"">WebSocket Server Online</div>
    <div class=""info"">
        <h3>Connection Info</h3>
        <p><strong>WebSocket URL:</strong> <code>ws://[host]:{_settings.WebSocketPort}/game</code></p>
        <p><strong>Connected Players:</strong> {_clients.Count} / {_settings.MaxPlayers}</p>
    </div>
    <div class=""info"">
        <h3>Web Client Example</h3>
        <pre><code>const ws = new WebSocket('ws://localhost:{_settings.WebSocketPort}/game');

ws.onopen = () => {{
    console.log('Connected!');
    ws.send(JSON.stringify({{
        op: 0,
        username: 'player',
        password: 'password',
        version: 235
    }}));
}};

ws.onmessage = (event) => {{
    const msg = JSON.parse(event.data);
    console.log('Received:', msg);
}};</code></pre>
    </div>
</body>
</html>";

        var buffer = System.Text.Encoding.UTF8.GetBytes(html);
        response.ContentLength64 = buffer.Length;
        await response.OutputStream.WriteAsync(buffer);
        response.Close();
    }

    private async Task HandleWebSocketAsync(HttpListenerContext context, CancellationToken cancellationToken)
    {
        var remoteIp = GetClientIp(context);
        var origin = context.Request.Headers["Origin"] ?? "";

        // Security: Validate origin
        if (!ValidateOrigin(origin))
        {
            _logger.LogWarning("Rejecting WebSocket from {IP}: invalid origin '{Origin}'",
                remoteIp, origin);
            context.Response.StatusCode = 403;
            context.Response.Close();
            return;
        }

        // Security: Check connection limit per IP
        if (!CheckConnectionLimit(remoteIp))
        {
            _logger.LogWarning("Rejecting WebSocket from {IP}: too many connections",
                remoteIp);
            context.Response.StatusCode = 429; // Too Many Requests
            context.Response.Close();
            return;
        }

        // Security: Check total connection limit
        if (_clients.Count >= _settings.MaxPlayers)
        {
            _logger.LogWarning("Rejecting WebSocket from {IP}: server full",
                remoteIp);
            context.Response.StatusCode = 503; // Service Unavailable
            context.Response.Close();
            return;
        }

        WebSocketContext? wsContext;
        try
        {
            wsContext = await context.AcceptWebSocketAsync(
                subProtocol: null,
                receiveBufferSize: Math.Min(_settings.WebSocketMaxMessageSize, 65536),
                keepAliveInterval: TimeSpan.FromSeconds(30));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to accept WebSocket from {IP}", remoteIp);
            DecrementConnectionCount(remoteIp);
            context.Response.StatusCode = 500;
            context.Response.Close();
            return;
        }

        var clientLogger = _loggerFactory.CreateLogger<WebSocketClient>();
        var client = new WebSocketClient(wsContext.WebSocket, remoteIp, clientLogger);

        // Register client
        if (!_clients.TryAdd(client.Id, client))
        {
            DecrementConnectionCount(remoteIp);
            await client.DisposeAsync();
            return;
        }

        _logger.LogInformation("WebSocket client connected: {Id} from {IP} (origin: {Origin})",
            client.Id, remoteIp, origin);

        // Wire up events - pass the actual client to the packet handler
        client.PacketReceived += async (c, packet) => await _packetDispatcher.HandlePacketAsync(c, packet);
        client.Disconnected += async (c) =>
        {
            DecrementConnectionCount(remoteIp);
            await OnClientDisconnectedAsync(c);
        };

        // Notify listeners
        if (ClientConnected is not null)
        {
            await ClientConnected.Invoke(client);
        }

        // Start receiving with timeout
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(TimeSpan.FromHours(12)); // Max session length

        await client.StartReceivingAsync();
    }

    private string GetClientIp(HttpListenerContext context)
    {
        // Check for proxy headers (X-Forwarded-For, X-Real-IP)
        var forwardedFor = context.Request.Headers["X-Forwarded-For"];
        if (!string.IsNullOrEmpty(forwardedFor))
        {
            // Take the first IP in the chain (original client)
            var firstIp = forwardedFor.Split(',')[0].Trim();
            if (IPAddress.TryParse(firstIp, out _))
            {
                return firstIp;
            }
        }

        var realIp = context.Request.Headers["X-Real-IP"];
        if (!string.IsNullOrEmpty(realIp) && IPAddress.TryParse(realIp, out _))
        {
            return realIp;
        }

        return context.Request.RemoteEndPoint?.Address.ToString() ?? "unknown";
    }

    private bool ValidateOrigin(string origin)
    {
        // Allow all origins if configured with "*"
        if (_allowedOrigins.Contains("*"))
            return true;

        // Empty origin is allowed for non-browser clients
        if (string.IsNullOrEmpty(origin))
            return true;

        // Check against allowed origins
        if (Uri.TryCreate(origin, UriKind.Absolute, out var originUri))
        {
            var originHost = $"{originUri.Scheme}://{originUri.Host}";
            if (originUri.Port != 80 && originUri.Port != 443)
            {
                originHost += $":{originUri.Port}";
            }

            return _allowedOrigins.Contains(originHost) ||
                   _allowedOrigins.Contains(originUri.Host);
        }

        return _allowedOrigins.Contains(origin);
    }

    private bool CheckConnectionLimit(string ip)
    {
        var maxPerIp = _settings.WebSocketMaxConnectionsPerIp;
        if (maxPerIp <= 0) return true; // No limit

        var currentCount = _connectionsPerIp.AddOrUpdate(ip, 1, (_, count) => count + 1);
        return currentCount <= maxPerIp;
    }

    private void DecrementConnectionCount(string ip)
    {
        _connectionsPerIp.AddOrUpdate(ip, 0, (_, count) => Math.Max(0, count - 1));
    }

    private async Task OnClientDisconnectedAsync(IGameClient client)
    {
        if (client is WebSocketClient wsClient)
        {
            _clients.TryRemove(wsClient.Id, out _);
        }
        _logger.LogInformation("WebSocket client disconnected: {Id}", client.Id);

        if (ClientDisconnected is not null)
        {
            await ClientDisconnected.Invoke(client);
        }

        await client.DisposeAsync();
    }

    /// <summary>
    /// Gets a client by ID.
    /// </summary>
    public WebSocketClient? GetClient(Guid id) =>
        _clients.TryGetValue(id, out var client) ? client : null;

    /// <summary>
    /// Gets all connected WebSocket clients.
    /// </summary>
    public IEnumerable<WebSocketClient> GetClients() => _clients.Values;

    /// <summary>
    /// Broadcasts a packet to all connected WebSocket clients.
    /// </summary>
    public async Task BroadcastAsync(Packet packet)
    {
        var tasks = _clients.Values
            .Where(c => c.IsConnected)
            .Select(c => c.SendAsync(packet));

        await Task.WhenAll(tasks);
    }

    private async Task DisconnectAllClientsAsync()
    {
        var tasks = _clients.Values.Select(c => c.DisconnectAsync());
        await Task.WhenAll(tasks);
        _clients.Clear();
        _connectionsPerIp.Clear();
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Stopping WebSocket server...");
        await DisconnectAllClientsAsync();
        _listener?.Stop();
        await base.StopAsync(cancellationToken);
    }
}
