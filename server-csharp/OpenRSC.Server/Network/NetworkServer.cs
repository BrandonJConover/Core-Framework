using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Network;

/// <summary>
/// TCP server that accepts client connections.
/// Runs as a background service with proper lifecycle management.
/// </summary>
public sealed class NetworkServer : BackgroundService
{
    private readonly ILogger<NetworkServer> _logger;
    private readonly ILoggerFactory _loggerFactory;
    private readonly ServerSettings _settings;
    private readonly IPacketHandler _packetHandler;

    private readonly ConcurrentDictionary<Guid, GameClient> _clients = new();
    private Socket? _listener;

    /// <summary>
    /// Number of currently connected clients.
    /// </summary>
    public int ConnectedClients => _clients.Count;

    /// <summary>
    /// Event raised when a client connects.
    /// </summary>
    public event Func<GameClient, Task>? ClientConnected;

    /// <summary>
    /// Event raised when a client disconnects.
    /// </summary>
    public event Func<GameClient, Task>? ClientDisconnected;

    public NetworkServer(
        ILogger<NetworkServer> logger,
        ILoggerFactory loggerFactory,
        IOptions<ServerSettings> settings,
        IPacketHandler packetHandler)
    {
        _logger = logger;
        _loggerFactory = loggerFactory;
        _settings = settings.Value;
        _packetHandler = packetHandler;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _listener = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        _listener.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);

        var endpoint = new IPEndPoint(IPAddress.Any, _settings.ServerPort);
        _listener.Bind(endpoint);
        _listener.Listen(100);

        _logger.LogInformation("Network server listening on port {Port}", _settings.ServerPort);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var socket = await _listener.AcceptAsync(stoppingToken);
                _ = HandleClientAsync(socket, stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("Network server shutting down...");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in network server accept loop");
        }
        finally
        {
            await DisconnectAllClientsAsync();
            _listener.Close();
        }
    }

    private async Task HandleClientAsync(Socket socket, CancellationToken cancellationToken)
    {
        var clientLogger = _loggerFactory.CreateLogger<GameClient>();
        var client = new GameClient(socket, clientLogger);

        // Check connection limits
        if (_clients.Count >= _settings.MaxPlayers)
        {
            _logger.LogWarning("Rejecting connection from {Address}: server full", client.RemoteAddress);
            await client.DisposeAsync();
            return;
        }

        // Register client
        if (!_clients.TryAdd(client.Id, client))
        {
            await client.DisposeAsync();
            return;
        }

        _logger.LogInformation("Client connected: {Id} from {Address}", client.Id, client.RemoteAddress);

        // Wire up events
        client.PacketReceived += async (c, packet) => await _packetHandler.HandlePacketAsync(c, packet);
        client.Disconnected += OnClientDisconnectedAsync;

        // Notify listeners
        if (ClientConnected != null)
        {
            await ClientConnected.Invoke(client);
        }

        // Start receiving
        await client.StartReceivingAsync();
    }

    private async Task OnClientDisconnectedAsync(GameClient client)
    {
        _clients.TryRemove(client.Id, out _);
        _logger.LogInformation("Client disconnected: {Id}", client.Id);

        if (ClientDisconnected != null)
        {
            await ClientDisconnected.Invoke(client);
        }

        await client.DisposeAsync();
    }

    /// <summary>
    /// Gets a client by ID.
    /// </summary>
    public GameClient? GetClient(Guid id)
    {
        return _clients.TryGetValue(id, out var client) ? client : null;
    }

    /// <summary>
    /// Gets all connected clients.
    /// </summary>
    public IEnumerable<GameClient> GetClients() => _clients.Values;

    /// <summary>
    /// Broadcasts a packet to all connected clients.
    /// </summary>
    public async Task BroadcastAsync(Packet packet)
    {
        var tasks = _clients.Values
            .Where(c => c.IsConnected)
            .Select(c => c.SendAsync(packet));

        await Task.WhenAll(tasks);
    }

    /// <summary>
    /// Disconnects all clients.
    /// </summary>
    private async Task DisconnectAllClientsAsync()
    {
        var tasks = _clients.Values.Select(c => c.DisconnectAsync());
        await Task.WhenAll(tasks);
        _clients.Clear();
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Stopping network server...");
        await DisconnectAllClientsAsync();
        await base.StopAsync(cancellationToken);
    }
}
