using System.Collections.Concurrent;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Network;

/// <summary>
/// Manages heartbeat/keepalive for all connected clients.
/// Detects and disconnects dead connections.
/// </summary>
public sealed class HeartbeatManager : BackgroundService
{
    private readonly ILogger<HeartbeatManager> _logger;
    private readonly NetworkServer _networkServer;
    private readonly ServerSettings _settings;

    private readonly ConcurrentDictionary<Guid, HeartbeatInfo> _heartbeats = new();

    /// <summary>
    /// Interval between heartbeat checks.
    /// </summary>
    public TimeSpan HeartbeatInterval { get; init; } = TimeSpan.FromSeconds(30);

    /// <summary>
    /// Maximum time without activity before considering connection dead.
    /// </summary>
    public TimeSpan DeadConnectionTimeout { get; init; } = TimeSpan.FromSeconds(90);

    /// <summary>
    /// Ping opcode to send to clients.
    /// </summary>
    private const byte PingOpcode = 67; // Server ping

    public HeartbeatManager(
        ILogger<HeartbeatManager> logger,
        NetworkServer networkServer,
        IOptions<ServerSettings> settings)
    {
        _logger = logger;
        _networkServer = networkServer;
        _settings = settings.Value;

        // Use idle timeout from settings if available
        if (_settings.IdleTimeoutMs > 0)
        {
            DeadConnectionTimeout = TimeSpan.FromMilliseconds(_settings.IdleTimeoutMs);
        }

        // Subscribe to client events
        _networkServer.ClientConnected += OnClientConnected;
        _networkServer.ClientDisconnected += OnClientDisconnected;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Heartbeat manager started (interval: {Interval}s, timeout: {Timeout}s)",
            HeartbeatInterval.TotalSeconds, DeadConnectionTimeout.TotalSeconds);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(HeartbeatInterval, stoppingToken);
                await CheckHeartbeatsAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in heartbeat check");
            }
        }
    }

    private async Task CheckHeartbeatsAsync(CancellationToken cancellationToken)
    {
        var now = DateTime.UtcNow;
        var deadClients = new List<GameClient>();

        foreach (var client in _networkServer.GetClients())
        {
            if (cancellationToken.IsCancellationRequested)
                break;

            // Check if client has been inactive too long
            var timeSinceActivity = now - client.LastActivity;

            if (timeSinceActivity > DeadConnectionTimeout)
            {
                _logger.LogInformation("Client {Id} timed out (no activity for {Seconds}s)",
                    client.Id, timeSinceActivity.TotalSeconds);
                deadClients.Add(client);
                continue;
            }

            // Send ping if approaching timeout
            if (timeSinceActivity > HeartbeatInterval)
            {
                try
                {
                    await SendPingAsync(client);
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Failed to send ping to client {Id}", client.Id);
                    deadClients.Add(client);
                }
            }
        }

        // Disconnect dead clients
        foreach (var client in deadClients)
        {
            try
            {
                await client.DisconnectAsync();
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Error disconnecting dead client {Id}", client.Id);
            }
        }

        if (deadClients.Count > 0)
        {
            _logger.LogInformation("Disconnected {Count} dead clients", deadClients.Count);
        }
    }

    private async Task SendPingAsync(GameClient client)
    {
        using var packet = new Packet(PingOpcode);
        packet.WriteLong(DateTime.UtcNow.Ticks); // Timestamp for RTT calculation
        await client.SendAsync(packet);

        if (_heartbeats.TryGetValue(client.Id, out var info))
        {
            info.LastPingSent = DateTime.UtcNow;
            info.PendingPings++;
        }
    }

    /// <summary>
    /// Records a pong response from a client.
    /// </summary>
    public void RecordPong(Guid clientId, long sentTimestamp)
    {
        if (_heartbeats.TryGetValue(clientId, out var info))
        {
            var rtt = DateTime.UtcNow.Ticks - sentTimestamp;
            info.LastPongReceived = DateTime.UtcNow;
            info.PendingPings = 0;
            info.LastRttTicks = rtt;

            // Update running average
            if (info.AverageRttTicks == 0)
                info.AverageRttTicks = rtt;
            else
                info.AverageRttTicks = (info.AverageRttTicks * 0.8 + rtt * 0.2);
        }
    }

    /// <summary>
    /// Gets the average RTT for a client in milliseconds.
    /// </summary>
    public double GetAverageRttMs(Guid clientId)
    {
        if (_heartbeats.TryGetValue(clientId, out var info))
            return info.AverageRttTicks / TimeSpan.TicksPerMillisecond;

        return 0;
    }

    /// <summary>
    /// Gets network metrics for a client.
    /// </summary>
    public NetworkMetrics? GetMetrics(Guid clientId)
    {
        if (!_heartbeats.TryGetValue(clientId, out var info))
            return null;

        return new NetworkMetrics
        {
            ClientId = clientId,
            AverageRttMs = info.AverageRttTicks / TimeSpan.TicksPerMillisecond,
            LastRttMs = info.LastRttTicks / TimeSpan.TicksPerMillisecond,
            PendingPings = info.PendingPings,
            LastPingSent = info.LastPingSent,
            LastPongReceived = info.LastPongReceived
        };
    }

    private Task OnClientConnected(GameClient client)
    {
        _heartbeats[client.Id] = new HeartbeatInfo
        {
            ConnectedAt = DateTime.UtcNow
        };
        return Task.CompletedTask;
    }

    private Task OnClientDisconnected(GameClient client)
    {
        _heartbeats.TryRemove(client.Id, out _);
        return Task.CompletedTask;
    }

    private sealed class HeartbeatInfo
    {
        public DateTime ConnectedAt { get; init; }
        public DateTime LastPingSent { get; set; }
        public DateTime LastPongReceived { get; set; }
        public int PendingPings { get; set; }
        public double LastRttTicks { get; set; }
        public double AverageRttTicks { get; set; }
    }
}

/// <summary>
/// Network metrics for a client connection.
/// </summary>
public sealed record NetworkMetrics
{
    public required Guid ClientId { get; init; }
    public double AverageRttMs { get; init; }
    public double LastRttMs { get; init; }
    public int PendingPings { get; init; }
    public DateTime LastPingSent { get; init; }
    public DateTime LastPongReceived { get; init; }
}
