using Azure.Monitor.OpenTelemetry.AspNetCore;
using Azure.Monitor.OpenTelemetry.Exporter;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;

namespace OpenRSC.Server.Infrastructure.Observability;

/// <summary>
/// Azure Application Insights configuration settings.
/// </summary>
public sealed class ApplicationInsightsSettings
{
    public const string SectionName = "ApplicationInsights";

    /// <summary>
    /// Enable Application Insights.
    /// </summary>
    public bool Enabled { get; set; } = false;

    /// <summary>
    /// Application Insights connection string.
    /// </summary>
    public string ConnectionString { get; set; } = "";

    /// <summary>
    /// Cloud role name for distributed tracing.
    /// </summary>
    public string CloudRoleName { get; set; } = "openrsc-server";

    /// <summary>
    /// Cloud role instance (defaults to machine name).
    /// </summary>
    public string? CloudRoleInstance { get; set; }

    /// <summary>
    /// Enable live metrics stream.
    /// </summary>
    public bool EnableLiveMetrics { get; set; } = true;

    /// <summary>
    /// Enable adaptive sampling.
    /// </summary>
    public bool EnableAdaptiveSampling { get; set; } = true;

    /// <summary>
    /// Sampling percentage (0-100) when adaptive sampling is disabled.
    /// </summary>
    public double SamplingPercentage { get; set; } = 100;

    /// <summary>
    /// Enable dependency tracking.
    /// </summary>
    public bool EnableDependencyTracking { get; set; } = true;

    /// <summary>
    /// Enable request tracking.
    /// </summary>
    public bool EnableRequestTracking { get; set; } = true;

    /// <summary>
    /// Enable exception tracking.
    /// </summary>
    public bool EnableExceptionTracking { get; set; } = true;

    /// <summary>
    /// Enable performance counters.
    /// </summary>
    public bool EnablePerformanceCounters { get; set; } = true;

    /// <summary>
    /// Flush telemetry on shutdown timeout in seconds.
    /// </summary>
    public int FlushTimeoutSeconds { get; set; } = 5;

    /// <summary>
    /// Custom properties to add to all telemetry.
    /// </summary>
    public Dictionary<string, string> CustomProperties { get; set; } = new();
}

/// <summary>
/// Extension methods for Application Insights configuration.
/// </summary>
public static class ApplicationInsightsExtensions
{
    /// <summary>
    /// Adds Azure Application Insights to the service collection.
    /// </summary>
    public static IServiceCollection AddApplicationInsights(
        this IServiceCollection services,
        IConfiguration configuration,
        Action<ApplicationInsightsSettings>? configure = null)
    {
        var settings = new ApplicationInsightsSettings();
        configuration.GetSection(ApplicationInsightsSettings.SectionName).Bind(settings);
        configure?.Invoke(settings);

        if (!settings.Enabled || string.IsNullOrEmpty(settings.ConnectionString))
        {
            return services;
        }

        // Use the Azure Monitor OpenTelemetry distribution
        services.AddOpenTelemetry()
            .UseAzureMonitor(options =>
            {
                options.ConnectionString = settings.ConnectionString;

                // Configure sampling
                if (!settings.EnableAdaptiveSampling)
                {
                    options.SamplingRatio = (float)(settings.SamplingPercentage / 100.0);
                }
            });

        return services;
    }

    /// <summary>
    /// Adds Azure Monitor exporter to tracing.
    /// </summary>
    public static TracerProviderBuilder AddAzureMonitorExporter(
        this TracerProviderBuilder builder,
        ApplicationInsightsSettings settings)
    {
        if (!settings.Enabled || string.IsNullOrEmpty(settings.ConnectionString))
        {
            return builder;
        }

        builder.AddAzureMonitorTraceExporter(options =>
        {
            options.ConnectionString = settings.ConnectionString;
        });

        return builder;
    }

    /// <summary>
    /// Adds Azure Monitor exporter to metrics.
    /// </summary>
    public static MeterProviderBuilder AddAzureMonitorExporter(
        this MeterProviderBuilder builder,
        ApplicationInsightsSettings settings)
    {
        if (!settings.Enabled || string.IsNullOrEmpty(settings.ConnectionString))
        {
            return builder;
        }

        builder.AddAzureMonitorMetricExporter(options =>
        {
            options.ConnectionString = settings.ConnectionString;
        });

        return builder;
    }
}

/// <summary>
/// Application Insights telemetry helper for custom events and metrics.
/// </summary>
public sealed class ApplicationInsightsTelemetry
{
    private readonly ApplicationInsightsSettings _settings;
    private readonly ILogger<ApplicationInsightsTelemetry> _logger;

    public ApplicationInsightsTelemetry(
        IOptions<ApplicationInsightsSettings> settings,
        ILogger<ApplicationInsightsTelemetry> logger)
    {
        _settings = settings.Value;
        _logger = logger;
    }

    /// <summary>
    /// Tracks a custom event.
    /// </summary>
    public void TrackEvent(string eventName, Dictionary<string, string>? properties = null)
    {
        if (!_settings.Enabled) return;

        var activity = GameActivitySource.StartActivity($"event.{eventName}");
        if (activity != null)
        {
            if (properties != null)
            {
                foreach (var prop in properties)
                {
                    activity.SetTag(prop.Key, prop.Value);
                }
            }
            activity.Dispose();
        }

        _logger.LogDebug("Tracked event: {EventName}", eventName);
    }

    /// <summary>
    /// Tracks a custom metric.
    /// </summary>
    public void TrackMetric(string metricName, double value, Dictionary<string, string>? properties = null)
    {
        if (!_settings.Enabled) return;

        _logger.LogDebug("Tracked metric: {MetricName} = {Value}", metricName, value);
    }

    /// <summary>
    /// Tracks an exception.
    /// </summary>
    public void TrackException(Exception exception, Dictionary<string, string>? properties = null)
    {
        if (!_settings.Enabled) return;

        var activity = System.Diagnostics.Activity.Current;
        if (activity != null)
        {
            activity.SetStatus(System.Diagnostics.ActivityStatusCode.Error, exception.Message);
            activity.RecordException(exception);
        }

        _logger.LogError(exception, "Tracked exception");
    }

    /// <summary>
    /// Tracks a player login event.
    /// </summary>
    public void TrackPlayerLogin(string username, bool success, string? failureReason = null)
    {
        var properties = new Dictionary<string, string>
        {
            ["username"] = username,
            ["success"] = success.ToString(),
        };

        if (!success && !string.IsNullOrEmpty(failureReason))
        {
            properties["failureReason"] = failureReason;
        }

        TrackEvent("PlayerLogin", properties);
    }

    /// <summary>
    /// Tracks a player logout event.
    /// </summary>
    public void TrackPlayerLogout(string username, string reason)
    {
        TrackEvent("PlayerLogout", new Dictionary<string, string>
        {
            ["username"] = username,
            ["reason"] = reason
        });
    }

    /// <summary>
    /// Tracks a player action.
    /// </summary>
    public void TrackPlayerAction(string username, string action, Dictionary<string, string>? additionalProperties = null)
    {
        var properties = new Dictionary<string, string>
        {
            ["username"] = username,
            ["action"] = action
        };

        if (additionalProperties != null)
        {
            foreach (var prop in additionalProperties)
            {
                properties[prop.Key] = prop.Value;
            }
        }

        TrackEvent($"PlayerAction.{action}", properties);
    }
}
