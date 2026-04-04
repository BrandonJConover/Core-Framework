using System.Runtime.CompilerServices;
using System.Text;
using Consul;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace OpenRSC.Server.Infrastructure.ServiceDiscovery;

/// <summary>
/// Consul service discovery settings.
/// </summary>
public sealed class ConsulSettings
{
    public const string SectionName = "Consul";

    /// <summary>
    /// Enable Consul service discovery.
    /// </summary>
    public bool Enabled { get; set; } = false;

    /// <summary>
    /// Consul server address.
    /// </summary>
    public string Address { get; set; } = "http://localhost:8500";

    /// <summary>
    /// Consul datacenter.
    /// </summary>
    public string Datacenter { get; set; } = "dc1";

    /// <summary>
    /// ACL token for authentication.
    /// </summary>
    public string? Token { get; set; }

    /// <summary>
    /// Wait time for blocking queries.
    /// </summary>
    public int WaitTimeSeconds { get; set; } = 300;

    /// <summary>
    /// Key-value prefix for this application.
    /// </summary>
    public string KeyPrefix { get; set; } = "openrsc/";
}

/// <summary>
/// Consul-based service discovery implementation.
/// </summary>
public sealed class ConsulServiceDiscovery : IServiceDiscovery, IDisposable
{
    private readonly ConsulClient _client;
    private readonly ConsulSettings _settings;
    private readonly ILogger<ConsulServiceDiscovery> _logger;

    public ConsulServiceDiscovery(
        IOptions<ConsulSettings> settings,
        ILogger<ConsulServiceDiscovery> logger)
    {
        _settings = settings.Value;
        _logger = logger;

        _client = new ConsulClient(config =>
        {
            config.Address = new Uri(_settings.Address);
            config.Datacenter = _settings.Datacenter;

            if (!string.IsNullOrEmpty(_settings.Token))
            {
                config.Token = _settings.Token;
            }

            config.WaitTime = TimeSpan.FromSeconds(_settings.WaitTimeSeconds);
        });
    }

    public string ProviderName => "Consul";

    public async Task RegisterAsync(ServiceRegistration registration, CancellationToken cancellationToken = default)
    {
        var serviceRegistration = new AgentServiceRegistration
        {
            ID = registration.ServiceId,
            Name = registration.ServiceName,
            Address = registration.Address,
            Port = registration.Port,
            Tags = registration.Tags.ToArray(),
            Meta = registration.Meta.ToDictionary(kvp => kvp.Key, kvp => kvp.Value)
        };

        if (registration.HealthCheck != null)
        {
            serviceRegistration.Check = CreateHealthCheck(registration.ServiceId, registration.HealthCheck);
        }

        var result = await _client.Agent.ServiceRegister(serviceRegistration, cancellationToken);

        if (result.StatusCode != System.Net.HttpStatusCode.OK)
        {
            _logger.LogError("Failed to register service {ServiceId}: {StatusCode}",
                registration.ServiceId, result.StatusCode);
            throw new ServiceDiscoveryException($"Failed to register service: {result.StatusCode}");
        }

        _logger.LogInformation("Registered service {ServiceId} ({ServiceName}) at {Address}:{Port}",
            registration.ServiceId, registration.ServiceName, registration.Address, registration.Port);
    }

    public async Task DeregisterAsync(string serviceId, CancellationToken cancellationToken = default)
    {
        var result = await _client.Agent.ServiceDeregister(serviceId, cancellationToken);

        if (result.StatusCode != System.Net.HttpStatusCode.OK)
        {
            _logger.LogError("Failed to deregister service {ServiceId}: {StatusCode}",
                serviceId, result.StatusCode);
            throw new ServiceDiscoveryException($"Failed to deregister service: {result.StatusCode}");
        }

        _logger.LogInformation("Deregistered service {ServiceId}", serviceId);
    }

    public async Task<IReadOnlyList<ServiceInstance>> DiscoverAsync(
        string serviceName,
        CancellationToken cancellationToken = default)
    {
        var result = await _client.Health.Service(serviceName, tag: null, passingOnly: true, cancellationToken);

        return result.Response
            .Select(entry => new ServiceInstance
            {
                ServiceId = entry.Service.ID,
                ServiceName = entry.Service.Service,
                Address = entry.Service.Address,
                Port = entry.Service.Port,
                Tags = entry.Service.Tags,
                Meta = entry.Service.Meta,
                HealthStatus = MapHealthStatus(entry.Checks)
            })
            .ToList();
    }

    public async Task<ServiceInstance?> GetInstanceAsync(
        string serviceId,
        CancellationToken cancellationToken = default)
    {
        var result = await _client.Agent.Services(cancellationToken);

        if (result.Response.TryGetValue(serviceId, out var service))
        {
            return new ServiceInstance
            {
                ServiceId = service.ID,
                ServiceName = service.Service,
                Address = service.Address,
                Port = service.Port,
                Tags = service.Tags,
                Meta = service.Meta,
                HealthStatus = ServiceHealthStatus.Unknown
            };
        }

        return null;
    }

    public async Task<bool> SetKeyAsync(string key, string value, CancellationToken cancellationToken = default)
    {
        var fullKey = _settings.KeyPrefix + key;
        var kvPair = new KVPair(fullKey)
        {
            Value = Encoding.UTF8.GetBytes(value)
        };

        var result = await _client.KV.Put(kvPair, cancellationToken);
        return result.Response;
    }

    public async Task<string?> GetKeyAsync(string key, CancellationToken cancellationToken = default)
    {
        var fullKey = _settings.KeyPrefix + key;
        var result = await _client.KV.Get(fullKey, cancellationToken);

        if (result.Response?.Value == null)
        {
            return null;
        }

        return Encoding.UTF8.GetString(result.Response.Value);
    }

    public async Task<bool> DeleteKeyAsync(string key, CancellationToken cancellationToken = default)
    {
        var fullKey = _settings.KeyPrefix + key;
        var result = await _client.KV.Delete(fullKey, cancellationToken);
        return result.Response;
    }

    public async IAsyncEnumerable<KeyValueChange> WatchKeyAsync(
        string key,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var fullKey = _settings.KeyPrefix + key;
        ulong lastIndex = 0;
        string? lastValue = null;

        while (!cancellationToken.IsCancellationRequested)
        {
            var options = new QueryOptions
            {
                WaitIndex = lastIndex,
                WaitTime = TimeSpan.FromSeconds(_settings.WaitTimeSeconds)
            };

            var result = await _client.KV.Get(fullKey, options, cancellationToken);

            if (result.LastIndex > lastIndex)
            {
                lastIndex = result.LastIndex;

                if (result.Response?.Value == null)
                {
                    if (lastValue != null)
                    {
                        yield return new KeyValueChange
                        {
                            Key = key,
                            Value = null,
                            ChangeType = KeyValueChangeType.Deleted,
                            Version = (long)lastIndex
                        };
                        lastValue = null;
                    }
                }
                else
                {
                    var newValue = Encoding.UTF8.GetString(result.Response.Value);
                    if (newValue != lastValue)
                    {
                        var changeType = lastValue == null
                            ? KeyValueChangeType.Created
                            : KeyValueChangeType.Updated;

                        yield return new KeyValueChange
                        {
                            Key = key,
                            Value = newValue,
                            ChangeType = changeType,
                            Version = (long)lastIndex
                        };
                        lastValue = newValue;
                    }
                }
            }
        }
    }

    public async Task<bool> HealthCheckAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var result = await _client.Status.Leader(cancellationToken);
            return !string.IsNullOrEmpty(result.Response);
        }
        catch
        {
            return false;
        }
    }

    private static AgentServiceCheck CreateHealthCheck(string serviceId, HealthCheckConfig config)
    {
        var check = new AgentServiceCheck
        {
            Interval = config.Interval,
            Timeout = config.Timeout
        };

        if (!string.IsNullOrEmpty(config.HttpEndpoint))
        {
            check.HTTP = config.HttpEndpoint;
        }
        else if (!string.IsNullOrEmpty(config.TcpAddress))
        {
            check.TCP = config.TcpAddress;
        }
        else if (!string.IsNullOrEmpty(config.GrpcAddress))
        {
            check.GRPC = config.GrpcAddress;
        }

        if (config.DeregisterCriticalServiceAfter.HasValue)
        {
            check.DeregisterCriticalServiceAfter = config.DeregisterCriticalServiceAfter.Value;
        }

        return check;
    }

    private static ServiceHealthStatus MapHealthStatus(HealthCheck[] checks)
    {
        if (checks.Length == 0)
            return ServiceHealthStatus.Unknown;

        if (checks.All(c => c.Status == HealthStatus.Passing))
            return ServiceHealthStatus.Passing;

        if (checks.Any(c => c.Status == HealthStatus.Critical))
            return ServiceHealthStatus.Critical;

        if (checks.Any(c => c.Status == HealthStatus.Warning))
            return ServiceHealthStatus.Warning;

        return ServiceHealthStatus.Unknown;
    }

    public void Dispose()
    {
        _client.Dispose();
    }
}

/// <summary>
/// Exception thrown when service discovery operations fail.
/// </summary>
public class ServiceDiscoveryException : Exception
{
    public ServiceDiscoveryException(string message) : base(message)
    {
    }

    public ServiceDiscoveryException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
