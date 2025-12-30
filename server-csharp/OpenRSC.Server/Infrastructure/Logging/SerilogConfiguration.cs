using Microsoft.Extensions.Configuration;
using Serilog;
using Serilog.Events;
using Serilog.Formatting.Compact;
using Serilog.Sinks.Grafana.Loki;

namespace OpenRSC.Server.Infrastructure.Logging;

/// <summary>
/// Enhanced Serilog configuration settings.
/// </summary>
public sealed class LoggingSettings
{
    public const string SectionName = "Logging";

    /// <summary>
    /// Minimum log level for console output.
    /// </summary>
    public string ConsoleMinimumLevel { get; set; } = "Information";

    /// <summary>
    /// Minimum log level for file output.
    /// </summary>
    public string FileMinimumLevel { get; set; } = "Debug";

    /// <summary>
    /// Enable async logging for better performance.
    /// </summary>
    public bool EnableAsync { get; set; } = true;

    /// <summary>
    /// Log file path pattern.
    /// </summary>
    public string LogFilePath { get; set; } = "logs/server-.log";

    /// <summary>
    /// Number of days to retain log files.
    /// </summary>
    public int RetainedFileCountLimit { get; set; } = 31;

    /// <summary>
    /// Maximum log file size in bytes.
    /// </summary>
    public long FileSizeLimitBytes { get; set; } = 100 * 1024 * 1024; // 100MB

    /// <summary>
    /// Enable JSON structured logs.
    /// </summary>
    public bool EnableJsonLogs { get; set; } = true;

    /// <summary>
    /// JSON log file path.
    /// </summary>
    public string JsonLogFilePath { get; set; } = "logs/server-.json";

    /// <summary>
    /// Enable Seq log server sink.
    /// </summary>
    public bool EnableSeq { get; set; } = false;

    /// <summary>
    /// Seq server URL.
    /// </summary>
    public string SeqServerUrl { get; set; } = "http://localhost:5341";

    /// <summary>
    /// Seq API key.
    /// </summary>
    public string SeqApiKey { get; set; } = "";

    /// <summary>
    /// Enable Grafana Loki sink.
    /// </summary>
    public bool EnableLoki { get; set; } = false;

    /// <summary>
    /// Grafana Loki push URL.
    /// </summary>
    public string LokiUrl { get; set; } = "http://localhost:3100";

    /// <summary>
    /// Loki labels to add to all logs.
    /// </summary>
    public Dictionary<string, string> LokiLabels { get; set; } = new()
    {
        ["app"] = "openrsc-server",
        ["environment"] = "development"
    };

    /// <summary>
    /// Enable environment enricher.
    /// </summary>
    public bool EnrichWithEnvironment { get; set; } = true;

    /// <summary>
    /// Enable thread enricher.
    /// </summary>
    public bool EnrichWithThread { get; set; } = true;

    /// <summary>
    /// Enable process enricher.
    /// </summary>
    public bool EnrichWithProcess { get; set; } = true;

    /// <summary>
    /// Application name for log enrichment.
    /// </summary>
    public string ApplicationName { get; set; } = "OpenRSC.Server";

    /// <summary>
    /// Environment name for log enrichment.
    /// </summary>
    public string EnvironmentName { get; set; } = "Development";
}

/// <summary>
/// Enhanced Serilog configuration builder.
/// </summary>
public static class SerilogConfigurationBuilder
{
    /// <summary>
    /// Creates an enhanced Serilog logger configuration.
    /// </summary>
    public static LoggerConfiguration CreateLoggerConfiguration(
        IConfiguration configuration,
        LoggingSettings? settings = null)
    {
        settings ??= new LoggingSettings();
        configuration.GetSection(LoggingSettings.SectionName).Bind(settings);

        var loggerConfig = new LoggerConfiguration()
            .MinimumLevel.Debug()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
            .MinimumLevel.Override("Microsoft.Hosting.Lifetime", LogEventLevel.Information)
            .MinimumLevel.Override("System", LogEventLevel.Warning);

        // Add enrichers
        loggerConfig = AddEnrichers(loggerConfig, settings);

        // Add sinks
        loggerConfig = AddSinks(loggerConfig, settings);

        return loggerConfig;
    }

    private static LoggerConfiguration AddEnrichers(
        LoggerConfiguration config,
        LoggingSettings settings)
    {
        config = config
            .Enrich.FromLogContext()
            .Enrich.WithProperty("Application", settings.ApplicationName)
            .Enrich.WithProperty("Environment", settings.EnvironmentName);

        if (settings.EnrichWithEnvironment)
        {
            config = config.Enrich.WithEnvironmentName();
        }

        if (settings.EnrichWithThread)
        {
            config = config.Enrich.WithThreadId();
        }

        if (settings.EnrichWithProcess)
        {
            config = config.Enrich.WithProcessId();
            config = config.Enrich.WithProcessName();
        }

        return config;
    }

    private static LoggerConfiguration AddSinks(
        LoggerConfiguration config,
        LoggingSettings settings)
    {
        // Console sink (always enabled)
        var consoleMinLevel = ParseLogLevel(settings.ConsoleMinimumLevel);
        config = config.WriteTo.Console(
            restrictedToMinimumLevel: consoleMinLevel,
            outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] [{SourceContext}] {Message:lj}{NewLine}{Exception}");

        // File sink - text format
        var fileMinLevel = ParseLogLevel(settings.FileMinimumLevel);
        if (settings.EnableAsync)
        {
            config = config.WriteTo.Async(a => a.File(
                path: settings.LogFilePath,
                rollingInterval: RollingInterval.Day,
                restrictedToMinimumLevel: fileMinLevel,
                fileSizeLimitBytes: settings.FileSizeLimitBytes,
                retainedFileCountLimit: settings.RetainedFileCountLimit,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{SourceContext}] {Message:lj}{NewLine}{Exception}"));
        }
        else
        {
            config = config.WriteTo.File(
                path: settings.LogFilePath,
                rollingInterval: RollingInterval.Day,
                restrictedToMinimumLevel: fileMinLevel,
                fileSizeLimitBytes: settings.FileSizeLimitBytes,
                retainedFileCountLimit: settings.RetainedFileCountLimit,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{SourceContext}] {Message:lj}{NewLine}{Exception}");
        }

        // JSON structured logs
        if (settings.EnableJsonLogs)
        {
            if (settings.EnableAsync)
            {
                config = config.WriteTo.Async(a => a.File(
                    formatter: new CompactJsonFormatter(),
                    path: settings.JsonLogFilePath,
                    rollingInterval: RollingInterval.Day,
                    fileSizeLimitBytes: settings.FileSizeLimitBytes,
                    retainedFileCountLimit: settings.RetainedFileCountLimit));
            }
            else
            {
                config = config.WriteTo.File(
                    formatter: new CompactJsonFormatter(),
                    path: settings.JsonLogFilePath,
                    rollingInterval: RollingInterval.Day,
                    fileSizeLimitBytes: settings.FileSizeLimitBytes,
                    retainedFileCountLimit: settings.RetainedFileCountLimit);
            }
        }

        // Seq sink
        if (settings.EnableSeq && !string.IsNullOrEmpty(settings.SeqServerUrl))
        {
            config = config.WriteTo.Seq(
                serverUrl: settings.SeqServerUrl,
                apiKey: string.IsNullOrEmpty(settings.SeqApiKey) ? null : settings.SeqApiKey,
                restrictedToMinimumLevel: LogEventLevel.Debug);
        }

        // Grafana Loki sink
        if (settings.EnableLoki && !string.IsNullOrEmpty(settings.LokiUrl))
        {
            var lokiLabels = settings.LokiLabels
                .Select(kvp => new LokiLabel { Key = kvp.Key, Value = kvp.Value })
                .ToArray();

            config = config.WriteTo.GrafanaLoki(
                uri: settings.LokiUrl,
                labels: lokiLabels,
                restrictedToMinimumLevel: LogEventLevel.Debug);
        }

        return config;
    }

    private static LogEventLevel ParseLogLevel(string level)
    {
        return level.ToLowerInvariant() switch
        {
            "verbose" or "trace" => LogEventLevel.Verbose,
            "debug" => LogEventLevel.Debug,
            "information" or "info" => LogEventLevel.Information,
            "warning" or "warn" => LogEventLevel.Warning,
            "error" => LogEventLevel.Error,
            "fatal" or "critical" => LogEventLevel.Fatal,
            _ => LogEventLevel.Information
        };
    }
}

/// <summary>
/// Log context extensions for structured logging.
/// </summary>
public static class LogContextExtensions
{
    /// <summary>
    /// Adds player context to log entries.
    /// </summary>
    public static IDisposable PushPlayerContext(string username, int playerId)
    {
        return Serilog.Context.LogContext.PushProperty("Username", username);
    }

    /// <summary>
    /// Adds client context to log entries.
    /// </summary>
    public static IDisposable PushClientContext(string clientId, string ipAddress)
    {
        var disposables = new List<IDisposable>
        {
            Serilog.Context.LogContext.PushProperty("ClientId", clientId),
            Serilog.Context.LogContext.PushProperty("IpAddress", ipAddress)
        };

        return new CompositeDisposable(disposables);
    }

    /// <summary>
    /// Adds operation context to log entries.
    /// </summary>
    public static IDisposable PushOperationContext(string operationName, string? correlationId = null)
    {
        var disposables = new List<IDisposable>
        {
            Serilog.Context.LogContext.PushProperty("Operation", operationName)
        };

        if (!string.IsNullOrEmpty(correlationId))
        {
            disposables.Add(Serilog.Context.LogContext.PushProperty("CorrelationId", correlationId));
        }

        return new CompositeDisposable(disposables);
    }

    private sealed class CompositeDisposable : IDisposable
    {
        private readonly IEnumerable<IDisposable> _disposables;

        public CompositeDisposable(IEnumerable<IDisposable> disposables)
        {
            _disposables = disposables;
        }

        public void Dispose()
        {
            foreach (var disposable in _disposables)
            {
                disposable.Dispose();
            }
        }
    }
}
