using OpenTelemetry.Metrics;

namespace OpenRSC.Server.Infrastructure.Observability;

/// <summary>
/// Prometheus configuration settings.
/// </summary>
public sealed class PrometheusSettings
{
    public const string SectionName = "Prometheus";

    /// <summary>
    /// Enable Prometheus metrics exporter.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Prometheus metrics endpoint path.
    /// </summary>
    public string Endpoint { get; set; } = "/metrics";

    /// <summary>
    /// Scrape response caching duration in milliseconds.
    /// </summary>
    public int ScrapeResponseCacheDurationMilliseconds { get; set; } = 300;

    /// <summary>
    /// Include runtime metrics (GC, thread pool, etc.).
    /// </summary>
    public bool IncludeRuntimeMetrics { get; set; } = true;

    /// <summary>
    /// Include ASP.NET Core metrics.
    /// </summary>
    public bool IncludeAspNetCoreMetrics { get; set; } = true;

    /// <summary>
    /// Include HTTP client metrics.
    /// </summary>
    public bool IncludeHttpClientMetrics { get; set; } = true;

    /// <summary>
    /// Enable OpenMetrics format (Prometheus 2.x).
    /// </summary>
    public bool UseOpenMetricsFormat { get; set; } = true;
}

/// <summary>
/// Extension methods for Prometheus configuration.
/// </summary>
public static class PrometheusExtensions
{
    /// <summary>
    /// Adds Prometheus metrics exporter to the metrics builder.
    /// </summary>
    public static MeterProviderBuilder AddPrometheusExporter(
        this MeterProviderBuilder builder,
        PrometheusSettings settings)
    {
        if (!settings.Enabled)
        {
            return builder;
        }

        builder.AddPrometheusExporter(options =>
        {
            options.ScrapeResponseCacheDurationMilliseconds = settings.ScrapeResponseCacheDurationMilliseconds;
        });

        return builder;
    }

    /// <summary>
    /// Adds Prometheus metrics services to the service collection.
    /// </summary>
    public static IServiceCollection AddPrometheusMetrics(
        this IServiceCollection services,
        IConfiguration configuration,
        Action<PrometheusSettings>? configure = null)
    {
        var settings = new PrometheusSettings();
        configuration.GetSection(PrometheusSettings.SectionName).Bind(settings);
        configure?.Invoke(settings);

        if (!settings.Enabled)
        {
            return services;
        }

        services.AddOpenTelemetry()
            .WithMetrics(metrics =>
            {
                // Add game metrics
                metrics.AddMeter(GameMetrics.MeterName);

                // Runtime metrics
                if (settings.IncludeRuntimeMetrics)
                {
                    metrics.AddRuntimeInstrumentation();
                }

                // ASP.NET Core metrics
                if (settings.IncludeAspNetCoreMetrics)
                {
                    metrics.AddAspNetCoreInstrumentation();
                }

                // HTTP client metrics
                if (settings.IncludeHttpClientMetrics)
                {
                    metrics.AddHttpClientInstrumentation();
                }

                // Prometheus exporter
                metrics.AddPrometheusExporter(options =>
                {
                    options.ScrapeResponseCacheDurationMilliseconds = settings.ScrapeResponseCacheDurationMilliseconds;
                });
            });

        return services;
    }

    /// <summary>
    /// Maps the Prometheus metrics endpoint.
    /// </summary>
    public static WebApplication UsePrometheusMetrics(
        this WebApplication app,
        PrometheusSettings? settings = null)
    {
        settings ??= new PrometheusSettings();
        app.Configuration.GetSection(PrometheusSettings.SectionName).Bind(settings);

        if (!settings.Enabled)
        {
            return app;
        }

        app.MapPrometheusScrapingEndpoint(settings.Endpoint);

        return app;
    }
}

/// <summary>
/// Custom Prometheus metrics collector for game-specific metrics.
/// </summary>
public sealed class GamePrometheusCollector
{
    private readonly GameMetrics _gameMetrics;

    public GamePrometheusCollector(GameMetrics gameMetrics)
    {
        _gameMetrics = gameMetrics;
    }

    /// <summary>
    /// Updates game metrics from the world state.
    /// This should be called periodically (e.g., every game tick).
    /// </summary>
    public void UpdateMetrics(int playersOnline, int npcsActive)
    {
        _gameMetrics.SetPlayersOnline(playersOnline);
        _gameMetrics.SetNpcsActive(npcsActive);
    }
}

/// <summary>
/// Grafana dashboard configuration helper.
/// </summary>
public static class GrafanaDashboardHelper
{
    /// <summary>
    /// Gets a sample Grafana dashboard JSON for OpenRSC metrics.
    /// </summary>
    public static string GetSampleDashboardJson()
    {
        return """
        {
          "annotations": { "list": [] },
          "editable": true,
          "fiscalYearStartMonth": 0,
          "graphTooltip": 0,
          "id": null,
          "links": [],
          "liveNow": false,
          "panels": [
            {
              "title": "Players Online",
              "type": "stat",
              "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
              "targets": [
                {
                  "expr": "openrsc_players_online",
                  "legendFormat": "Players"
                }
              ]
            },
            {
              "title": "NPCs Active",
              "type": "stat",
              "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
              "targets": [
                {
                  "expr": "openrsc_npcs_active",
                  "legendFormat": "NPCs"
                }
              ]
            },
            {
              "title": "Memory Usage",
              "type": "gauge",
              "gridPos": { "h": 4, "w": 6, "x": 12, "y": 0 },
              "targets": [
                {
                  "expr": "openrsc_memory_usage / 1024 / 1024",
                  "legendFormat": "MB"
                }
              ]
            },
            {
              "title": "Packets Per Second",
              "type": "timeseries",
              "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
              "targets": [
                {
                  "expr": "rate(openrsc_packets_received_total[1m])",
                  "legendFormat": "Received"
                },
                {
                  "expr": "rate(openrsc_packets_sent_total[1m])",
                  "legendFormat": "Sent"
                }
              ]
            },
            {
              "title": "Login Activity",
              "type": "timeseries",
              "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
              "targets": [
                {
                  "expr": "rate(openrsc_login_successes_total[5m])",
                  "legendFormat": "Successes"
                },
                {
                  "expr": "rate(openrsc_login_failures_total[5m])",
                  "legendFormat": "Failures"
                }
              ]
            },
            {
              "title": "Packet Processing Time",
              "type": "heatmap",
              "gridPos": { "h": 8, "w": 12, "x": 0, "y": 12 },
              "targets": [
                {
                  "expr": "histogram_quantile(0.99, rate(openrsc_packet_processing_time_bucket[5m]))",
                  "legendFormat": "p99"
                }
              ]
            },
            {
              "title": "Game Tick Duration",
              "type": "timeseries",
              "gridPos": { "h": 8, "w": 12, "x": 12, "y": 12 },
              "targets": [
                {
                  "expr": "histogram_quantile(0.50, rate(openrsc_game_tick_duration_bucket[5m]))",
                  "legendFormat": "p50"
                },
                {
                  "expr": "histogram_quantile(0.95, rate(openrsc_game_tick_duration_bucket[5m]))",
                  "legendFormat": "p95"
                },
                {
                  "expr": "histogram_quantile(0.99, rate(openrsc_game_tick_duration_bucket[5m]))",
                  "legendFormat": "p99"
                }
              ]
            }
          ],
          "refresh": "5s",
          "schemaVersion": 38,
          "style": "dark",
          "tags": ["openrsc", "game"],
          "templating": { "list": [] },
          "time": { "from": "now-1h", "to": "now" },
          "timepicker": {},
          "timezone": "",
          "title": "OpenRSC Server Dashboard",
          "uid": "openrsc-server",
          "version": 1,
          "weekStart": ""
        }
        """;
    }
}
