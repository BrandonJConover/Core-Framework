using System.Diagnostics;
using System.Diagnostics.Metrics;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace OpenRSC.Server.Infrastructure.Observability;

/// <summary>
/// OpenTelemetry configuration settings.
/// </summary>
public sealed class OpenTelemetrySettings
{
    public const string SectionName = "OpenTelemetry";

    /// <summary>
    /// Enable OpenTelemetry.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Service name for telemetry.
    /// </summary>
    public string ServiceName { get; set; } = "openrsc-server";

    /// <summary>
    /// Service version.
    /// </summary>
    public string ServiceVersion { get; set; } = "1.0.0";

    /// <summary>
    /// Service instance ID.
    /// </summary>
    public string? ServiceInstanceId { get; set; }

    /// <summary>
    /// Environment name.
    /// </summary>
    public string Environment { get; set; } = "development";

    /// <summary>
    /// Enable tracing.
    /// </summary>
    public bool EnableTracing { get; set; } = true;

    /// <summary>
    /// Enable metrics.
    /// </summary>
    public bool EnableMetrics { get; set; } = true;

    /// <summary>
    /// Enable console exporter for debugging.
    /// </summary>
    public bool EnableConsoleExporter { get; set; } = false;

    /// <summary>
    /// Enable OTLP exporter.
    /// </summary>
    public bool EnableOtlpExporter { get; set; } = true;

    /// <summary>
    /// OTLP exporter endpoint.
    /// </summary>
    public string OtlpEndpoint { get; set; } = "http://localhost:4317";

    /// <summary>
    /// OTLP exporter protocol (grpc or http).
    /// </summary>
    public string OtlpProtocol { get; set; } = "grpc";

    /// <summary>
    /// Trace sampling ratio (0.0 to 1.0).
    /// </summary>
    public double TraceSamplingRatio { get; set; } = 1.0;

    /// <summary>
    /// Enable ASP.NET Core instrumentation.
    /// </summary>
    public bool InstrumentAspNetCore { get; set; } = true;

    /// <summary>
    /// Enable HTTP client instrumentation.
    /// </summary>
    public bool InstrumentHttpClient { get; set; } = true;

    /// <summary>
    /// Enable runtime metrics.
    /// </summary>
    public bool EnableRuntimeMetrics { get; set; } = true;

    /// <summary>
    /// Metrics export interval in seconds.
    /// </summary>
    public int MetricsExportIntervalSeconds { get; set; } = 15;

    /// <summary>
    /// Additional resource attributes.
    /// </summary>
    public Dictionary<string, string> ResourceAttributes { get; set; } = new();
}

/// <summary>
/// OpenTelemetry extension methods for service configuration.
/// </summary>
public static class OpenTelemetryExtensions
{
    /// <summary>
    /// Adds OpenTelemetry tracing and metrics to the service collection.
    /// </summary>
    public static IServiceCollection AddOpenTelemetryObservability(
        this IServiceCollection services,
        IConfiguration configuration,
        Action<OpenTelemetrySettings>? configure = null)
    {
        var settings = new OpenTelemetrySettings();
        configuration.GetSection(OpenTelemetrySettings.SectionName).Bind(settings);
        configure?.Invoke(settings);

        if (!settings.Enabled)
        {
            return services;
        }

        // Build resource
        var resourceBuilder = ResourceBuilder.CreateDefault()
            .AddService(
                serviceName: settings.ServiceName,
                serviceVersion: settings.ServiceVersion,
                serviceInstanceId: settings.ServiceInstanceId ?? Environment.MachineName)
            .AddAttributes(new Dictionary<string, object>
            {
                ["deployment.environment"] = settings.Environment,
                ["host.name"] = Environment.MachineName,
                ["process.pid"] = Environment.ProcessId
            });

        // Add custom attributes
        foreach (var attr in settings.ResourceAttributes)
        {
            resourceBuilder.AddAttributes(new Dictionary<string, object> { [attr.Key] = attr.Value });
        }

        // Register game metrics
        services.AddSingleton<GameMetrics>();

        // Configure OpenTelemetry
        var otelBuilder = services.AddOpenTelemetry();

        otelBuilder.ConfigureResource(resource => resource
            .AddService(settings.ServiceName, settings.ServiceVersion)
            .AddAttributes(settings.ResourceAttributes.ToDictionary(kvp => kvp.Key, kvp => (object)kvp.Value)));

        // Add tracing
        if (settings.EnableTracing)
        {
            otelBuilder.WithTracing(tracing =>
            {
                tracing.SetResourceBuilder(resourceBuilder);

                // Add game activity source
                tracing.AddSource(GameActivitySource.Name);

                // ASP.NET Core instrumentation
                if (settings.InstrumentAspNetCore)
                {
                    tracing.AddAspNetCoreInstrumentation(options =>
                    {
                        options.RecordException = true;
                        options.Filter = context =>
                        {
                            // Filter out health check endpoints
                            var path = context.Request.Path.Value;
                            return path == null ||
                                   (!path.Contains("/health") && !path.Contains("/metrics"));
                        };
                    });
                }

                // HTTP client instrumentation
                if (settings.InstrumentHttpClient)
                {
                    tracing.AddHttpClientInstrumentation(options =>
                    {
                        options.RecordException = true;
                    });
                }

                // Set sampler
                if (settings.TraceSamplingRatio < 1.0)
                {
                    tracing.SetSampler(new TraceIdRatioBasedSampler(settings.TraceSamplingRatio));
                }

                // Add exporters
                if (settings.EnableConsoleExporter)
                {
                    tracing.AddConsoleExporter();
                }

                if (settings.EnableOtlpExporter)
                {
                    tracing.AddOtlpExporter(options =>
                    {
                        options.Endpoint = new Uri(settings.OtlpEndpoint);
                        options.Protocol = settings.OtlpProtocol.ToLowerInvariant() == "grpc"
                            ? OtlpExportProtocol.Grpc
                            : OtlpExportProtocol.HttpProtobuf;
                    });
                }
            });
        }

        // Add metrics
        if (settings.EnableMetrics)
        {
            otelBuilder.WithMetrics(metrics =>
            {
                metrics.SetResourceBuilder(resourceBuilder);

                // Add game metrics
                metrics.AddMeter(GameMetrics.MeterName);

                // ASP.NET Core instrumentation
                if (settings.InstrumentAspNetCore)
                {
                    metrics.AddAspNetCoreInstrumentation();
                }

                // HTTP client instrumentation
                if (settings.InstrumentHttpClient)
                {
                    metrics.AddHttpClientInstrumentation();
                }

                // Runtime metrics
                if (settings.EnableRuntimeMetrics)
                {
                    metrics.AddRuntimeInstrumentation();
                }

                // Add exporters
                if (settings.EnableConsoleExporter)
                {
                    metrics.AddConsoleExporter((_, readerOptions) =>
                    {
                        readerOptions.PeriodicExportingMetricReaderOptions.ExportIntervalMilliseconds =
                            settings.MetricsExportIntervalSeconds * 1000;
                    });
                }

                if (settings.EnableOtlpExporter)
                {
                    metrics.AddOtlpExporter((options, readerOptions) =>
                    {
                        options.Endpoint = new Uri(settings.OtlpEndpoint);
                        options.Protocol = settings.OtlpProtocol.ToLowerInvariant() == "grpc"
                            ? OtlpExportProtocol.Grpc
                            : OtlpExportProtocol.HttpProtobuf;
                        readerOptions.PeriodicExportingMetricReaderOptions.ExportIntervalMilliseconds =
                            settings.MetricsExportIntervalSeconds * 1000;
                    });
                }
            });
        }

        return services;
    }
}

/// <summary>
/// Activity source for game-specific tracing.
/// </summary>
public static class GameActivitySource
{
    public const string Name = "OpenRSC.Server";

    private static readonly ActivitySource _source = new(Name, "1.0.0");

    /// <summary>
    /// Starts a new activity for a game operation.
    /// </summary>
    public static Activity? StartActivity(string name, ActivityKind kind = ActivityKind.Internal)
    {
        return _source.StartActivity(name, kind);
    }

    /// <summary>
    /// Starts a packet processing activity.
    /// </summary>
    public static Activity? StartPacketActivity(string opcode, string? clientId = null)
    {
        var activity = _source.StartActivity($"packet.{opcode}", ActivityKind.Server);
        if (activity != null && clientId != null)
        {
            activity.SetTag("client.id", clientId);
        }
        return activity;
    }

    /// <summary>
    /// Starts a player action activity.
    /// </summary>
    public static Activity? StartPlayerActivity(string action, string? username = null)
    {
        var activity = _source.StartActivity($"player.{action}", ActivityKind.Internal);
        if (activity != null && username != null)
        {
            activity.SetTag("player.username", username);
        }
        return activity;
    }

    /// <summary>
    /// Starts a database operation activity.
    /// </summary>
    public static Activity? StartDatabaseActivity(string operation, string? table = null)
    {
        var activity = _source.StartActivity($"db.{operation}", ActivityKind.Client);
        if (activity != null)
        {
            activity.SetTag("db.system", "mysql");
            if (table != null)
            {
                activity.SetTag("db.table", table);
            }
        }
        return activity;
    }
}

/// <summary>
/// Game-specific metrics using OpenTelemetry.
/// </summary>
public sealed class GameMetrics
{
    public const string MeterName = "OpenRSC.Server";

    private readonly Meter _meter;
    private readonly Counter<long> _packetsReceived;
    private readonly Counter<long> _packetsSent;
    private readonly Counter<long> _loginAttempts;
    private readonly Counter<long> _loginSuccesses;
    private readonly Counter<long> _loginFailures;
    private readonly Histogram<double> _packetProcessingTime;
    private readonly Histogram<double> _gameTickDuration;
    private readonly ObservableGauge<int> _playersOnline;
    private readonly ObservableGauge<int> _npcsActive;
    private readonly ObservableGauge<long> _memoryUsage;

    private int _currentPlayersOnline;
    private int _currentNpcsActive;

    public GameMetrics()
    {
        _meter = new Meter(MeterName, "1.0.0");

        // Counters
        _packetsReceived = _meter.CreateCounter<long>(
            "openrsc.packets.received",
            "packets",
            "Total packets received from clients");

        _packetsSent = _meter.CreateCounter<long>(
            "openrsc.packets.sent",
            "packets",
            "Total packets sent to clients");

        _loginAttempts = _meter.CreateCounter<long>(
            "openrsc.login.attempts",
            "attempts",
            "Total login attempts");

        _loginSuccesses = _meter.CreateCounter<long>(
            "openrsc.login.successes",
            "logins",
            "Total successful logins");

        _loginFailures = _meter.CreateCounter<long>(
            "openrsc.login.failures",
            "failures",
            "Total failed login attempts");

        // Histograms
        _packetProcessingTime = _meter.CreateHistogram<double>(
            "openrsc.packet.processing_time",
            "ms",
            "Packet processing time in milliseconds");

        _gameTickDuration = _meter.CreateHistogram<double>(
            "openrsc.game_tick.duration",
            "ms",
            "Game tick duration in milliseconds");

        // Observable gauges
        _playersOnline = _meter.CreateObservableGauge(
            "openrsc.players.online",
            () => _currentPlayersOnline,
            "players",
            "Current number of players online");

        _npcsActive = _meter.CreateObservableGauge(
            "openrsc.npcs.active",
            () => _currentNpcsActive,
            "npcs",
            "Current number of active NPCs");

        _memoryUsage = _meter.CreateObservableGauge(
            "openrsc.memory.usage",
            () => GC.GetTotalMemory(false),
            "bytes",
            "Current memory usage in bytes");
    }

    public void RecordPacketReceived(string opcode)
    {
        _packetsReceived.Add(1, new KeyValuePair<string, object?>("opcode", opcode));
    }

    public void RecordPacketSent(string opcode)
    {
        _packetsSent.Add(1, new KeyValuePair<string, object?>("opcode", opcode));
    }

    public void RecordLoginAttempt(bool success, string? reason = null)
    {
        _loginAttempts.Add(1);
        if (success)
        {
            _loginSuccesses.Add(1);
        }
        else
        {
            _loginFailures.Add(1, new KeyValuePair<string, object?>("reason", reason ?? "unknown"));
        }
    }

    public void RecordPacketProcessingTime(double milliseconds, string opcode)
    {
        _packetProcessingTime.Record(milliseconds, new KeyValuePair<string, object?>("opcode", opcode));
    }

    public void RecordGameTickDuration(double milliseconds)
    {
        _gameTickDuration.Record(milliseconds);
    }

    public void SetPlayersOnline(int count)
    {
        _currentPlayersOnline = count;
    }

    public void SetNpcsActive(int count)
    {
        _currentNpcsActive = count;
    }
}
