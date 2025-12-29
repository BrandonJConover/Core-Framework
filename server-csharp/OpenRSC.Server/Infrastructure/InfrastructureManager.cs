using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Database;
using OpenRSC.Server.Infrastructure.Observability;
using OpenRSC.Server.Infrastructure.ServiceDiscovery;

namespace OpenRSC.Server.Infrastructure;

/// <summary>
/// Central manager for all infrastructure components.
/// Provides unified lifecycle management and health monitoring.
/// </summary>
public sealed class InfrastructureManager : IHostedService, IDisposable
{
    private readonly ILogger<InfrastructureManager> _logger;
    private readonly ServerSettings _settings;
    private readonly IServiceProvider _serviceProvider;

    // Infrastructure components
    private readonly RedisCacheService? _redisCache;
    private readonly IServiceDiscovery? _serviceDiscovery;
    private readonly PrometheusMetricsService? _prometheusMetrics;

    private bool _isRunning;
    private readonly CancellationTokenSource _shutdownCts = new();

    public InfrastructureManager(
        ILogger<InfrastructureManager> logger,
        IOptions<ServerSettings> settings,
        IServiceProvider serviceProvider,
        RedisCacheService? redisCache = null,
        IServiceDiscovery? serviceDiscovery = null,
        PrometheusMetricsService? prometheusMetrics = null)
    {
        _logger = logger;
        _settings = settings.Value;
        _serviceProvider = serviceProvider;
        _redisCache = redisCache;
        _serviceDiscovery = serviceDiscovery;
        _prometheusMetrics = prometheusMetrics;
    }

    /// <summary>
    /// Gets whether the infrastructure is fully initialized and healthy.
    /// </summary>
    public bool IsHealthy => _isRunning && CheckComponentHealth();

    /// <summary>
    /// Gets the Redis cache service.
    /// </summary>
    public RedisCacheService? Redis => _redisCache;

    /// <summary>
    /// Gets the service discovery provider.
    /// </summary>
    public IServiceDiscovery? ServiceDiscovery => _serviceDiscovery;

    /// <summary>
    /// Gets the Prometheus metrics service.
    /// </summary>
    public PrometheusMetricsService? Metrics => _prometheusMetrics;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting infrastructure manager...");

        var components = new List<(string Name, Func<Task<bool>> StartFunc)>
        {
            ("Redis Cache", StartRedisAsync),
            ("Service Discovery", StartServiceDiscoveryAsync),
            ("Metrics", StartMetricsAsync)
        };

        foreach (var (name, startFunc) in components)
        {
            try
            {
                var success = await startFunc();
                if (success)
                {
                    _logger.LogInformation("✓ {Component} initialized", name);
                }
                else
                {
                    _logger.LogWarning("⚠ {Component} not configured or unavailable", name);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "✗ Failed to initialize {Component}", name);
            }
        }

        _isRunning = true;
        _logger.LogInformation("Infrastructure manager started");
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Stopping infrastructure manager...");

        _shutdownCts.Cancel();
        _isRunning = false;

        // Stop components in reverse order
        var tasks = new List<Task>();

        if (_serviceDiscovery != null)
        {
            _logger.LogDebug("Deregistering from service discovery...");
            // Deregistration handled by ServiceRegistrationHostedService
        }

        await Task.WhenAll(tasks);
        _logger.LogInformation("Infrastructure manager stopped");
    }

    /// <summary>
    /// Gets the health status of all infrastructure components.
    /// </summary>
    public InfrastructureHealth GetHealthStatus()
    {
        return new InfrastructureHealth
        {
            IsHealthy = IsHealthy,
            Components = new Dictionary<string, ComponentHealth>
            {
                ["redis"] = new ComponentHealth
                {
                    Name = "Redis Cache",
                    IsHealthy = _redisCache?.IsConnected ?? false,
                    Status = _redisCache?.IsConnected == true ? "Connected" : "Disconnected"
                },
                ["service_discovery"] = new ComponentHealth
                {
                    Name = "Service Discovery",
                    IsHealthy = _serviceDiscovery != null,
                    Status = _serviceDiscovery?.ProviderName ?? "Not configured"
                },
                ["metrics"] = new ComponentHealth
                {
                    Name = "Prometheus Metrics",
                    IsHealthy = _prometheusMetrics != null,
                    Status = _prometheusMetrics != null ? "Enabled" : "Disabled"
                }
            },
            Timestamp = DateTime.UtcNow
        };
    }

    /// <summary>
    /// Performs a comprehensive health check on all components.
    /// </summary>
    public async Task<bool> PerformHealthCheckAsync()
    {
        var healthy = true;

        // Check Redis
        if (_redisCache != null)
        {
            try
            {
                var testKey = $"health_check_{Guid.NewGuid():N}";
                await _redisCache.SetAsync(testKey, "ping", TimeSpan.FromSeconds(5));
                var result = await _redisCache.GetAsync<string>(testKey);
                await _redisCache.DeleteAsync(testKey);

                if (result != "ping")
                {
                    _logger.LogWarning("Redis health check failed: value mismatch");
                    healthy = false;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Redis health check failed");
                healthy = false;
            }
        }

        // Check service discovery
        if (_serviceDiscovery != null)
        {
            try
            {
                var services = await _serviceDiscovery.DiscoverAsync(_settings.Name);
                _logger.LogDebug("Service discovery health check: found {Count} instances", services.Count);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Service discovery health check failed");
                healthy = false;
            }
        }

        return healthy;
    }

    private bool CheckComponentHealth()
    {
        // Quick synchronous health check
        if (_redisCache != null && !_redisCache.IsConnected)
        {
            return false;
        }

        return true;
    }

    private Task<bool> StartRedisAsync()
    {
        return Task.FromResult(_redisCache?.IsConnected ?? false);
    }

    private Task<bool> StartServiceDiscoveryAsync()
    {
        return Task.FromResult(_serviceDiscovery != null);
    }

    private Task<bool> StartMetricsAsync()
    {
        return Task.FromResult(_prometheusMetrics != null);
    }

    public void Dispose()
    {
        _shutdownCts.Dispose();
    }
}

/// <summary>
/// Infrastructure health status.
/// </summary>
public sealed class InfrastructureHealth
{
    public bool IsHealthy { get; init; }
    public Dictionary<string, ComponentHealth> Components { get; init; } = new();
    public DateTime Timestamp { get; init; }
}

/// <summary>
/// Individual component health status.
/// </summary>
public sealed class ComponentHealth
{
    public required string Name { get; init; }
    public bool IsHealthy { get; init; }
    public string Status { get; init; } = "Unknown";
    public string? Message { get; init; }
    public Dictionary<string, object>? Metadata { get; init; }
}

/// <summary>
/// Extension methods for InfrastructureManager registration.
/// </summary>
public static class InfrastructureManagerExtensions
{
    /// <summary>
    /// Adds the InfrastructureManager to the service collection.
    /// </summary>
    public static IServiceCollection AddInfrastructureManager(this IServiceCollection services)
    {
        services.AddSingleton<InfrastructureManager>();
        services.AddHostedService(sp => sp.GetRequiredService<InfrastructureManager>());
        return services;
    }
}
