namespace OpenRSC.Server.Infrastructure.ServiceDiscovery;

/// <summary>
/// Unified service discovery interface.
/// </summary>
public interface IServiceDiscovery
{
    /// <summary>
    /// Gets the service discovery provider name.
    /// </summary>
    string ProviderName { get; }

    /// <summary>
    /// Registers a service instance.
    /// </summary>
    Task RegisterAsync(ServiceRegistration registration, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deregisters a service instance.
    /// </summary>
    Task DeregisterAsync(string serviceId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Discovers service instances by name.
    /// </summary>
    Task<IReadOnlyList<ServiceInstance>> DiscoverAsync(string serviceName, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a specific service instance by ID.
    /// </summary>
    Task<ServiceInstance?> GetInstanceAsync(string serviceId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Sets a key-value pair.
    /// </summary>
    Task<bool> SetKeyAsync(string key, string value, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a value by key.
    /// </summary>
    Task<string?> GetKeyAsync(string key, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes a key.
    /// </summary>
    Task<bool> DeleteKeyAsync(string key, CancellationToken cancellationToken = default);

    /// <summary>
    /// Watches for changes to a key.
    /// </summary>
    IAsyncEnumerable<KeyValueChange> WatchKeyAsync(string key, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the health status of the service discovery provider.
    /// </summary>
    Task<bool> HealthCheckAsync(CancellationToken cancellationToken = default);
}

/// <summary>
/// Service registration information.
/// </summary>
public sealed record ServiceRegistration
{
    /// <summary>
    /// Unique service instance ID.
    /// </summary>
    public required string ServiceId { get; init; }

    /// <summary>
    /// Service name.
    /// </summary>
    public required string ServiceName { get; init; }

    /// <summary>
    /// Service host address.
    /// </summary>
    public required string Address { get; init; }

    /// <summary>
    /// Service port.
    /// </summary>
    public required int Port { get; init; }

    /// <summary>
    /// Service tags for filtering.
    /// </summary>
    public IReadOnlyList<string> Tags { get; init; } = [];

    /// <summary>
    /// Service metadata.
    /// </summary>
    public IReadOnlyDictionary<string, string> Meta { get; init; } = new Dictionary<string, string>();

    /// <summary>
    /// Health check configuration.
    /// </summary>
    public HealthCheckConfig? HealthCheck { get; init; }
}

/// <summary>
/// Health check configuration.
/// </summary>
public sealed record HealthCheckConfig
{
    /// <summary>
    /// HTTP health check endpoint.
    /// </summary>
    public string? HttpEndpoint { get; init; }

    /// <summary>
    /// Health check interval.
    /// </summary>
    public TimeSpan Interval { get; init; } = TimeSpan.FromSeconds(10);

    /// <summary>
    /// Health check timeout.
    /// </summary>
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(5);

    /// <summary>
    /// Deregister after being critical for this duration.
    /// </summary>
    public TimeSpan? DeregisterCriticalServiceAfter { get; init; }

    /// <summary>
    /// TCP health check address.
    /// </summary>
    public string? TcpAddress { get; init; }

    /// <summary>
    /// gRPC health check address.
    /// </summary>
    public string? GrpcAddress { get; init; }
}

/// <summary>
/// Service instance information.
/// </summary>
public sealed record ServiceInstance
{
    /// <summary>
    /// Unique service instance ID.
    /// </summary>
    public required string ServiceId { get; init; }

    /// <summary>
    /// Service name.
    /// </summary>
    public required string ServiceName { get; init; }

    /// <summary>
    /// Service host address.
    /// </summary>
    public required string Address { get; init; }

    /// <summary>
    /// Service port.
    /// </summary>
    public required int Port { get; init; }

    /// <summary>
    /// Service tags.
    /// </summary>
    public IReadOnlyList<string> Tags { get; init; } = [];

    /// <summary>
    /// Service metadata.
    /// </summary>
    public IReadOnlyDictionary<string, string> Meta { get; init; } = new Dictionary<string, string>();

    /// <summary>
    /// Current health status.
    /// </summary>
    public ServiceHealthStatus HealthStatus { get; init; } = ServiceHealthStatus.Unknown;
}

/// <summary>
/// Service health status.
/// </summary>
public enum ServiceHealthStatus
{
    Unknown,
    Passing,
    Warning,
    Critical
}

/// <summary>
/// Key-value change event.
/// </summary>
public sealed record KeyValueChange
{
    /// <summary>
    /// The key that changed.
    /// </summary>
    public required string Key { get; init; }

    /// <summary>
    /// The new value (null if deleted).
    /// </summary>
    public string? Value { get; init; }

    /// <summary>
    /// The type of change.
    /// </summary>
    public required KeyValueChangeType ChangeType { get; init; }

    /// <summary>
    /// Version/revision of the change.
    /// </summary>
    public long Version { get; init; }
}

/// <summary>
/// Key-value change type.
/// </summary>
public enum KeyValueChangeType
{
    Created,
    Updated,
    Deleted
}

/// <summary>
/// Service discovery provider type.
/// </summary>
public enum ServiceDiscoveryProvider
{
    None,
    Consul,
    Etcd
}
