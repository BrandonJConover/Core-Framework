using System.Runtime.CompilerServices;
using System.Text.Json;
using dotnet_etcd;
using Etcdserverpb;
using Google.Protobuf;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace OpenRSC.Server.Infrastructure.ServiceDiscovery;

/// <summary>
/// etcd service discovery settings.
/// </summary>
public sealed class EtcdSettings
{
    public const string SectionName = "Etcd";

    /// <summary>
    /// Enable etcd service discovery.
    /// </summary>
    public bool Enabled { get; set; } = false;

    /// <summary>
    /// etcd server endpoints (comma-separated).
    /// </summary>
    public string Endpoints { get; set; } = "http://localhost:2379";

    /// <summary>
    /// Username for authentication.
    /// </summary>
    public string? Username { get; set; }

    /// <summary>
    /// Password for authentication.
    /// </summary>
    public string? Password { get; set; }

    /// <summary>
    /// CA certificate path for TLS.
    /// </summary>
    public string? CaCertPath { get; set; }

    /// <summary>
    /// Client certificate path for TLS.
    /// </summary>
    public string? ClientCertPath { get; set; }

    /// <summary>
    /// Client key path for TLS.
    /// </summary>
    public string? ClientKeyPath { get; set; }

    /// <summary>
    /// Key prefix for services.
    /// </summary>
    public string ServicePrefix { get; set; } = "/openrsc/services/";

    /// <summary>
    /// Key prefix for configuration.
    /// </summary>
    public string ConfigPrefix { get; set; } = "/openrsc/config/";

    /// <summary>
    /// Lease TTL in seconds for service registration.
    /// </summary>
    public int LeaseTtlSeconds { get; set; } = 30;
}

/// <summary>
/// etcd-based service discovery implementation.
/// </summary>
public sealed class EtcdServiceDiscovery : IServiceDiscovery, IDisposable
{
    private readonly EtcdClient _client;
    private readonly EtcdSettings _settings;
    private readonly ILogger<EtcdServiceDiscovery> _logger;
    private readonly Dictionary<string, long> _leases = new();
    private readonly CancellationTokenSource _keepAliveCts = new();

    public EtcdServiceDiscovery(
        IOptions<EtcdSettings> settings,
        ILogger<EtcdServiceDiscovery> logger)
    {
        _settings = settings.Value;
        _logger = logger;

        var endpoints = _settings.Endpoints
            .Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(e => e.Trim())
            .ToArray();

        _client = new EtcdClient(string.Join(",", endpoints));

        // Authenticate if credentials provided
        if (!string.IsNullOrEmpty(_settings.Username) && !string.IsNullOrEmpty(_settings.Password))
        {
            _client.Authenticate(new AuthenticateRequest
            {
                Name = _settings.Username,
                Password = _settings.Password
            });
        }
    }

    public string ProviderName => "etcd";

    public async Task RegisterAsync(ServiceRegistration registration, CancellationToken cancellationToken = default)
    {
        // Create a lease for the service registration
        var leaseResponse = await _client.LeaseGrantAsync(new LeaseGrantRequest
        {
            TTL = _settings.LeaseTtlSeconds
        }, cancellationToken: cancellationToken);

        var leaseId = leaseResponse.ID;
        _leases[registration.ServiceId] = leaseId;

        // Start keep-alive for the lease
        _ = KeepLeaseAliveAsync(leaseId, _keepAliveCts.Token);

        // Store service information
        var serviceKey = $"{_settings.ServicePrefix}{registration.ServiceName}/{registration.ServiceId}";
        var serviceData = JsonSerializer.Serialize(new EtcdServiceData
        {
            ServiceId = registration.ServiceId,
            ServiceName = registration.ServiceName,
            Address = registration.Address,
            Port = registration.Port,
            Tags = registration.Tags.ToList(),
            Meta = registration.Meta.ToDictionary(kvp => kvp.Key, kvp => kvp.Value)
        });

        await _client.PutAsync(new PutRequest
        {
            Key = ByteString.CopyFromUtf8(serviceKey),
            Value = ByteString.CopyFromUtf8(serviceData),
            Lease = leaseId
        }, cancellationToken: cancellationToken);

        _logger.LogInformation("Registered service {ServiceId} ({ServiceName}) at {Address}:{Port} with lease {LeaseId}",
            registration.ServiceId, registration.ServiceName, registration.Address, registration.Port, leaseId);
    }

    public async Task DeregisterAsync(string serviceId, CancellationToken cancellationToken = default)
    {
        // Revoke the lease if exists
        if (_leases.TryGetValue(serviceId, out var leaseId))
        {
            await _client.LeaseRevokeAsync(new LeaseRevokeRequest
            {
                ID = leaseId
            }, cancellationToken: cancellationToken);
            _leases.Remove(serviceId);
        }

        // Also explicitly delete the key
        var prefix = $"{_settings.ServicePrefix}";
        var range = await _client.GetRangeAsync(prefix, cancellationToken: cancellationToken);

        foreach (var kv in range.Kvs)
        {
            var key = kv.Key.ToStringUtf8();
            if (key.EndsWith($"/{serviceId}"))
            {
                await _client.DeleteAsync(key, cancellationToken: cancellationToken);
            }
        }

        _logger.LogInformation("Deregistered service {ServiceId}", serviceId);
    }

    public async Task<IReadOnlyList<ServiceInstance>> DiscoverAsync(
        string serviceName,
        CancellationToken cancellationToken = default)
    {
        var prefix = $"{_settings.ServicePrefix}{serviceName}/";
        var range = await _client.GetRangeAsync(prefix, cancellationToken: cancellationToken);

        var instances = new List<ServiceInstance>();

        foreach (var kv in range.Kvs)
        {
            try
            {
                var data = JsonSerializer.Deserialize<EtcdServiceData>(kv.Value.ToStringUtf8());
                if (data != null)
                {
                    instances.Add(new ServiceInstance
                    {
                        ServiceId = data.ServiceId,
                        ServiceName = data.ServiceName,
                        Address = data.Address,
                        Port = data.Port,
                        Tags = data.Tags,
                        Meta = data.Meta,
                        HealthStatus = ServiceHealthStatus.Passing // Assume passing if registered
                    });
                }
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Failed to deserialize service data for key {Key}", kv.Key.ToStringUtf8());
            }
        }

        return instances;
    }

    public async Task<ServiceInstance?> GetInstanceAsync(
        string serviceId,
        CancellationToken cancellationToken = default)
    {
        var prefix = _settings.ServicePrefix;
        var range = await _client.GetRangeAsync(prefix, cancellationToken: cancellationToken);

        foreach (var kv in range.Kvs)
        {
            var key = kv.Key.ToStringUtf8();
            if (key.EndsWith($"/{serviceId}"))
            {
                try
                {
                    var data = JsonSerializer.Deserialize<EtcdServiceData>(kv.Value.ToStringUtf8());
                    if (data != null)
                    {
                        return new ServiceInstance
                        {
                            ServiceId = data.ServiceId,
                            ServiceName = data.ServiceName,
                            Address = data.Address,
                            Port = data.Port,
                            Tags = data.Tags,
                            Meta = data.Meta,
                            HealthStatus = ServiceHealthStatus.Passing
                        };
                    }
                }
                catch (JsonException ex)
                {
                    _logger.LogWarning(ex, "Failed to deserialize service data for key {Key}", key);
                }
            }
        }

        return null;
    }

    public async Task<bool> SetKeyAsync(string key, string value, CancellationToken cancellationToken = default)
    {
        var fullKey = _settings.ConfigPrefix + key;
        await _client.PutAsync(fullKey, value, cancellationToken: cancellationToken);
        return true;
    }

    public async Task<string?> GetKeyAsync(string key, CancellationToken cancellationToken = default)
    {
        var fullKey = _settings.ConfigPrefix + key;
        var response = await _client.GetValAsync(fullKey, cancellationToken: cancellationToken);
        return string.IsNullOrEmpty(response) ? null : response;
    }

    public async Task<bool> DeleteKeyAsync(string key, CancellationToken cancellationToken = default)
    {
        var fullKey = _settings.ConfigPrefix + key;
        await _client.DeleteAsync(fullKey, cancellationToken: cancellationToken);
        return true;
    }

    public async IAsyncEnumerable<KeyValueChange> WatchKeyAsync(
        string key,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var fullKey = _settings.ConfigPrefix + key;

        await foreach (var response in _client.WatchAsync(fullKey, cancellationToken: cancellationToken))
        {
            foreach (var evt in response.Events)
            {
                var changeType = evt.Type switch
                {
                    Mvccpb.Event.Types.EventType.Put when evt.Kv.CreateRevision == evt.Kv.ModRevision => KeyValueChangeType.Created,
                    Mvccpb.Event.Types.EventType.Put => KeyValueChangeType.Updated,
                    Mvccpb.Event.Types.EventType.Delete => KeyValueChangeType.Deleted,
                    _ => KeyValueChangeType.Updated
                };

                yield return new KeyValueChange
                {
                    Key = key,
                    Value = evt.Type == Mvccpb.Event.Types.EventType.Delete
                        ? null
                        : evt.Kv.Value.ToStringUtf8(),
                    ChangeType = changeType,
                    Version = evt.Kv.ModRevision
                };
            }
        }
    }

    public async Task<bool> HealthCheckAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var status = await _client.StatusAsync(new StatusRequest(), cancellationToken: cancellationToken);
            return !string.IsNullOrEmpty(status.Version);
        }
        catch
        {
            return false;
        }
    }

    private async Task KeepLeaseAliveAsync(long leaseId, CancellationToken cancellationToken)
    {
        var keepAliveInterval = TimeSpan.FromSeconds(_settings.LeaseTtlSeconds / 3);

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(keepAliveInterval, cancellationToken);

                await _client.LeaseKeepAlive(new LeaseKeepAliveRequest
                {
                    ID = leaseId
                }, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to keep lease {LeaseId} alive", leaseId);
            }
        }
    }

    public void Dispose()
    {
        _keepAliveCts.Cancel();
        _keepAliveCts.Dispose();
        _client.Dispose();
    }

    private sealed class EtcdServiceData
    {
        public required string ServiceId { get; init; }
        public required string ServiceName { get; init; }
        public required string Address { get; init; }
        public required int Port { get; init; }
        public List<string> Tags { get; init; } = [];
        public Dictionary<string, string> Meta { get; init; } = new();
    }
}
