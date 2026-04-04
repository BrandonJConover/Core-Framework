using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace OpenRSC.Server.Infrastructure.ServiceDiscovery;

/// <summary>
/// Service discovery configuration settings.
/// </summary>
public sealed class ServiceDiscoverySettings
{
    public const string SectionName = "ServiceDiscovery";

    /// <summary>
    /// Enable service discovery.
    /// </summary>
    public bool Enabled { get; set; } = false;

    /// <summary>
    /// Service discovery provider (Consul or Etcd).
    /// </summary>
    public ServiceDiscoveryProvider Provider { get; set; } = ServiceDiscoveryProvider.None;

    /// <summary>
    /// Service name for this instance.
    /// </summary>
    public string ServiceName { get; set; } = "openrsc-server";

    /// <summary>
    /// Unique instance ID (auto-generated if empty).
    /// </summary>
    public string InstanceId { get; set; } = "";

    /// <summary>
    /// Service address (auto-detected if empty).
    /// </summary>
    public string Address { get; set; } = "";

    /// <summary>
    /// Health check HTTP endpoint.
    /// </summary>
    public string HealthCheckEndpoint { get; set; } = "/health";

    /// <summary>
    /// Health check interval in seconds.
    /// </summary>
    public int HealthCheckIntervalSeconds { get; set; } = 10;

    /// <summary>
    /// Tags for service filtering.
    /// </summary>
    public List<string> Tags { get; set; } = ["game", "openrsc"];

    /// <summary>
    /// Metadata for service instance.
    /// </summary>
    public Dictionary<string, string> Metadata { get; set; } = new();
}

/// <summary>
/// Factory for creating service discovery providers.
/// </summary>
public sealed class ServiceDiscoveryFactory
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ServiceDiscoverySettings _settings;

    public ServiceDiscoveryFactory(
        IServiceProvider serviceProvider,
        IOptions<ServiceDiscoverySettings> settings)
    {
        _serviceProvider = serviceProvider;
        _settings = settings.Value;
    }

    /// <summary>
    /// Creates the configured service discovery provider.
    /// </summary>
    public IServiceDiscovery? Create()
    {
        if (!_settings.Enabled)
        {
            return null;
        }

        return _settings.Provider switch
        {
            ServiceDiscoveryProvider.Consul => _serviceProvider.GetService<ConsulServiceDiscovery>(),
            ServiceDiscoveryProvider.Etcd => _serviceProvider.GetService<EtcdServiceDiscovery>(),
            _ => null
        };
    }
}

/// <summary>
/// Hosted service that registers the game server with service discovery on startup.
/// </summary>
public sealed class ServiceRegistrationHostedService : IHostedService
{
    private readonly IServiceDiscovery? _serviceDiscovery;
    private readonly ServiceDiscoverySettings _settings;
    private readonly ILogger<ServiceRegistrationHostedService> _logger;
    private string? _serviceId;

    public ServiceRegistrationHostedService(
        ServiceDiscoveryFactory factory,
        IOptions<ServiceDiscoverySettings> settings,
        ILogger<ServiceRegistrationHostedService> logger)
    {
        _serviceDiscovery = factory.Create();
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (_serviceDiscovery == null || !_settings.Enabled)
        {
            _logger.LogInformation("Service discovery is disabled");
            return;
        }

        try
        {
            _serviceId = string.IsNullOrEmpty(_settings.InstanceId)
                ? $"{_settings.ServiceName}-{Environment.MachineName}-{Guid.NewGuid():N}"
                : _settings.InstanceId;

            var address = string.IsNullOrEmpty(_settings.Address)
                ? GetLocalIpAddress()
                : _settings.Address;

            var registration = new ServiceRegistration
            {
                ServiceId = _serviceId,
                ServiceName = _settings.ServiceName,
                Address = address,
                Port = 43594, // Should come from ServerSettings
                Tags = _settings.Tags,
                Meta = _settings.Metadata,
                HealthCheck = new HealthCheckConfig
                {
                    HttpEndpoint = $"http://{address}:8080{_settings.HealthCheckEndpoint}",
                    Interval = TimeSpan.FromSeconds(_settings.HealthCheckIntervalSeconds),
                    Timeout = TimeSpan.FromSeconds(5),
                    DeregisterCriticalServiceAfter = TimeSpan.FromMinutes(1)
                }
            };

            await _serviceDiscovery.RegisterAsync(registration, cancellationToken);

            _logger.LogInformation("Registered with {Provider} as {ServiceId}",
                _serviceDiscovery.ProviderName, _serviceId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to register with service discovery");
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_serviceDiscovery == null || string.IsNullOrEmpty(_serviceId))
        {
            return;
        }

        try
        {
            await _serviceDiscovery.DeregisterAsync(_serviceId, cancellationToken);
            _logger.LogInformation("Deregistered from {Provider}", _serviceDiscovery.ProviderName);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to deregister from service discovery");
        }
    }

    private static string GetLocalIpAddress()
    {
        try
        {
            var host = System.Net.Dns.GetHostEntry(System.Net.Dns.GetHostName());
            foreach (var ip in host.AddressList)
            {
                if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                {
                    return ip.ToString();
                }
            }
        }
        catch
        {
            // Ignore
        }

        return "127.0.0.1";
    }
}

/// <summary>
/// Extension methods for service discovery registration.
/// </summary>
public static class ServiceDiscoveryExtensions
{
    /// <summary>
    /// Adds service discovery services to the DI container.
    /// </summary>
    public static IServiceCollection AddServiceDiscovery(
        this IServiceCollection services,
        Action<ServiceDiscoverySettings>? configure = null)
    {
        if (configure != null)
        {
            services.Configure(configure);
        }
        else
        {
            services.Configure<ServiceDiscoverySettings>(_ => { });
        }

        // Register provider-specific services
        services.Configure<ConsulSettings>(_ => { });
        services.Configure<EtcdSettings>(_ => { });

        services.AddSingleton<ConsulServiceDiscovery>();
        services.AddSingleton<EtcdServiceDiscovery>();
        services.AddSingleton<ServiceDiscoveryFactory>();

        // Register the IServiceDiscovery interface
        services.AddSingleton<IServiceDiscovery>(sp =>
        {
            var factory = sp.GetRequiredService<ServiceDiscoveryFactory>();
            return factory.Create()!;
        });

        // Register hosted service for automatic registration
        services.AddHostedService<ServiceRegistrationHostedService>();

        return services;
    }
}
