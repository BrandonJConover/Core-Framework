using System.Buffers;
using System.Net;
using System.Net.Quic;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace OpenRSC.Server.Infrastructure.Transport;

/// <summary>
/// QUIC transport settings.
/// </summary>
public sealed class QuicTransportSettings
{
    public const string SectionName = "QuicTransport";

    /// <summary>
    /// Enable QUIC transport.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// QUIC port number.
    /// </summary>
    public int Port { get; set; } = 43595;

    /// <summary>
    /// Path to TLS certificate (required for QUIC).
    /// </summary>
    public string CertificatePath { get; set; } = "";

    /// <summary>
    /// TLS certificate password.
    /// </summary>
    public string CertificatePassword { get; set; } = "";

    /// <summary>
    /// Maximum concurrent bidirectional streams per connection.
    /// </summary>
    public int MaxBidirectionalStreams { get; set; } = 100;

    /// <summary>
    /// Maximum concurrent unidirectional streams per connection.
    /// </summary>
    public int MaxUnidirectionalStreams { get; set; } = 100;

    /// <summary>
    /// Idle timeout in seconds.
    /// </summary>
    public int IdleTimeoutSeconds { get; set; } = 60;

    /// <summary>
    /// ALPN protocol name.
    /// </summary>
    public string AlpnProtocol { get; set; } = "openrsc-v1";

    /// <summary>
    /// Maximum inbound data per connection (bytes).
    /// </summary>
    public long MaxInboundDataPerConnection { get; set; } = 16 * 1024 * 1024; // 16MB

    /// <summary>
    /// Maximum inbound data per stream (bytes).
    /// </summary>
    public long MaxInboundDataPerStream { get; set; } = 4 * 1024 * 1024; // 4MB
}

/// <summary>
/// QUIC-based game transport server.
/// Provides low-latency, reliable communication with built-in TLS.
/// </summary>
public sealed class QuicTransportServer : BackgroundService
{
    private readonly ILogger<QuicTransportServer> _logger;
    private readonly QuicTransportSettings _settings;
    private readonly IServiceProvider _serviceProvider;
    private QuicListener? _listener;

    public QuicTransportServer(
        ILogger<QuicTransportServer> logger,
        IOptions<QuicTransportSettings> settings,
        IServiceProvider serviceProvider)
    {
        _logger = logger;
        _settings = settings.Value;
        _serviceProvider = serviceProvider;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_settings.Enabled)
        {
            _logger.LogInformation("QUIC transport is disabled");
            return;
        }

        if (!QuicListener.IsSupported)
        {
            _logger.LogWarning("QUIC is not supported on this platform. " +
                "Requires Windows 11/Server 2022 or Linux with libmsquic");
            return;
        }

        if (string.IsNullOrEmpty(_settings.CertificatePath))
        {
            _logger.LogWarning("QUIC requires a TLS certificate. Configure CertificatePath in settings");
            return;
        }

        try
        {
            var certificate = LoadCertificate();
            await StartListenerAsync(certificate, stoppingToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to start QUIC transport server");
        }
    }

    private async Task StartListenerAsync(X509Certificate2 certificate, CancellationToken stoppingToken)
    {
        var options = new QuicListenerOptions
        {
            ListenEndPoint = new IPEndPoint(IPAddress.Any, _settings.Port),
            ApplicationProtocols = [new SslApplicationProtocol(_settings.AlpnProtocol)],
            ConnectionOptionsCallback = (_, _, _) => ValueTask.FromResult(new QuicServerConnectionOptions
            {
                DefaultStreamErrorCode = 0,
                DefaultCloseErrorCode = 0,
                IdleTimeout = TimeSpan.FromSeconds(_settings.IdleTimeoutSeconds),
                MaxInboundBidirectionalStreams = _settings.MaxBidirectionalStreams,
                MaxInboundUnidirectionalStreams = _settings.MaxUnidirectionalStreams,
                ServerAuthenticationOptions = new SslServerAuthenticationOptions
                {
                    ServerCertificate = certificate,
                    ApplicationProtocols = [new SslApplicationProtocol(_settings.AlpnProtocol)]
                }
            })
        };

        _listener = await QuicListener.ListenAsync(options, stoppingToken);
        _logger.LogInformation("QUIC transport listening on port {Port}", _settings.Port);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var connection = await _listener.AcceptConnectionAsync(stoppingToken);
                _ = HandleConnectionAsync(connection, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error accepting QUIC connection");
            }
        }
    }

    private async Task HandleConnectionAsync(QuicConnection connection, CancellationToken stoppingToken)
    {
        var remoteEndpoint = connection.RemoteEndPoint;
        _logger.LogDebug("QUIC connection from {RemoteEndpoint}", remoteEndpoint);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var stream = await connection.AcceptInboundStreamAsync(stoppingToken);
                _ = HandleStreamAsync(connection, stream, stoppingToken);
            }
        }
        catch (QuicException ex) when (ex.QuicError == QuicError.ConnectionAborted)
        {
            _logger.LogDebug("QUIC connection closed: {RemoteEndpoint}", remoteEndpoint);
        }
        catch (OperationCanceledException)
        {
            // Expected during shutdown
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling QUIC connection from {RemoteEndpoint}", remoteEndpoint);
        }
        finally
        {
            await connection.DisposeAsync();
        }
    }

    private async Task HandleStreamAsync(
        QuicConnection connection,
        QuicStream stream,
        CancellationToken stoppingToken)
    {
        var buffer = ArrayPool<byte>.Shared.Rent(8192);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var bytesRead = await stream.ReadAsync(buffer, stoppingToken);
                if (bytesRead == 0) break;

                // Process the received data
                await ProcessPacketAsync(connection, stream, buffer.AsMemory(0, bytesRead), stoppingToken);
            }
        }
        catch (QuicException ex) when (ex.QuicError == QuicError.StreamAborted)
        {
            // Stream closed
        }
        catch (OperationCanceledException)
        {
            // Expected during shutdown
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling QUIC stream");
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
            await stream.DisposeAsync();
        }
    }

    private async Task ProcessPacketAsync(
        QuicConnection connection,
        QuicStream stream,
        Memory<byte> data,
        CancellationToken stoppingToken)
    {
        // Packet processing would be handled here
        // This integrates with the existing packet dispatcher
        _logger.LogTrace("Received {Bytes} bytes from {RemoteEndpoint}",
            data.Length, connection.RemoteEndPoint);

        // Echo for now - real implementation would dispatch to packet handlers
        await stream.WriteAsync(data, stoppingToken);
    }

    private X509Certificate2 LoadCertificate()
    {
        if (string.IsNullOrEmpty(_settings.CertificatePassword))
        {
            return new X509Certificate2(_settings.CertificatePath);
        }

        return new X509Certificate2(
            _settings.CertificatePath,
            _settings.CertificatePassword,
            X509KeyStorageFlags.MachineKeySet);
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_listener != null)
        {
            await _listener.DisposeAsync();
            _logger.LogInformation("QUIC transport stopped");
        }

        await base.StopAsync(cancellationToken);
    }
}

/// <summary>
/// QUIC client wrapper for game client connections.
/// </summary>
public sealed class QuicGameClient : IAsyncDisposable
{
    private readonly QuicConnection _connection;
    private readonly ILogger<QuicGameClient> _logger;
    private QuicStream? _gameStream;

    public QuicGameClient(QuicConnection connection, ILogger<QuicGameClient> logger)
    {
        _connection = connection;
        _logger = logger;
    }

    public static async Task<QuicGameClient> ConnectAsync(
        string host,
        int port,
        string alpnProtocol,
        ILogger<QuicGameClient> logger,
        CancellationToken cancellationToken = default)
    {
        var options = new QuicClientConnectionOptions
        {
            RemoteEndPoint = new DnsEndPoint(host, port),
            DefaultStreamErrorCode = 0,
            DefaultCloseErrorCode = 0,
            ClientAuthenticationOptions = new SslClientAuthenticationOptions
            {
                ApplicationProtocols = [new SslApplicationProtocol(alpnProtocol)],
                RemoteCertificateValidationCallback = (_, _, _, _) => true // Configure properly in production
            }
        };

        var connection = await QuicConnection.ConnectAsync(options, cancellationToken);
        return new QuicGameClient(connection, logger);
    }

    public async Task<QuicStream> OpenGameStreamAsync(CancellationToken cancellationToken = default)
    {
        _gameStream = await _connection.OpenOutboundStreamAsync(QuicStreamType.Bidirectional, cancellationToken);
        return _gameStream;
    }

    public async ValueTask SendAsync(ReadOnlyMemory<byte> data, CancellationToken cancellationToken = default)
    {
        if (_gameStream == null)
            throw new InvalidOperationException("Stream not opened. Call OpenGameStreamAsync first.");

        await _gameStream.WriteAsync(data, cancellationToken);
    }

    public async ValueTask<int> ReceiveAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        if (_gameStream == null)
            throw new InvalidOperationException("Stream not opened. Call OpenGameStreamAsync first.");

        return await _gameStream.ReadAsync(buffer, cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        if (_gameStream != null)
        {
            await _gameStream.DisposeAsync();
        }

        await _connection.DisposeAsync();
    }
}

/// <summary>
/// Extension methods for QUIC transport registration.
/// </summary>
public static class QuicTransportExtensions
{
    /// <summary>
    /// Adds QUIC transport services to the DI container.
    /// </summary>
    public static IServiceCollection AddQuicTransport(
        this IServiceCollection services,
        Action<QuicTransportSettings>? configure = null)
    {
        if (configure != null)
        {
            services.Configure(configure);
        }
        else
        {
            services.Configure<QuicTransportSettings>(_ => { });
        }

        services.AddHostedService<QuicTransportServer>();

        return services;
    }
}
