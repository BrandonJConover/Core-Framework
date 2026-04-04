using Azure.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Configuration.AzureAppConfiguration;

namespace OpenRSC.Server.Infrastructure.Configuration;

/// <summary>
/// Azure App Configuration settings.
/// </summary>
public sealed class AzureAppConfigurationSettings
{
    public const string SectionName = "AzureAppConfiguration";

    /// <summary>
    /// Enable Azure App Configuration.
    /// </summary>
    public bool Enabled { get; set; } = false;

    /// <summary>
    /// Azure App Configuration endpoint URL.
    /// </summary>
    public string Endpoint { get; set; } = "";

    /// <summary>
    /// Connection string (alternative to Endpoint + Managed Identity).
    /// </summary>
    public string? ConnectionString { get; set; }

    /// <summary>
    /// Use Managed Identity for authentication (requires Endpoint).
    /// </summary>
    public bool UseManagedIdentity { get; set; } = true;

    /// <summary>
    /// Label filter for configuration values.
    /// </summary>
    public string Label { get; set; } = "";

    /// <summary>
    /// Key filter prefix.
    /// </summary>
    public string KeyPrefix { get; set; } = "OpenRSC:";

    /// <summary>
    /// Enable dynamic configuration refresh.
    /// </summary>
    public bool EnableRefresh { get; set; } = true;

    /// <summary>
    /// Sentinel key for triggering refresh.
    /// </summary>
    public string SentinelKey { get; set; } = "OpenRSC:Sentinel";

    /// <summary>
    /// Cache expiration for configuration values in seconds.
    /// </summary>
    public int CacheExpirationSeconds { get; set; } = 30;

    /// <summary>
    /// Enable feature flags.
    /// </summary>
    public bool EnableFeatureFlags { get; set; } = true;

    /// <summary>
    /// Feature flag prefix.
    /// </summary>
    public string FeatureFlagPrefix { get; set; } = ".appconfig.featureflag/";

    /// <summary>
    /// Enable Key Vault references.
    /// </summary>
    public bool EnableKeyVaultReferences { get; set; } = true;
}

/// <summary>
/// Extension methods for Azure App Configuration.
/// </summary>
public static class AzureAppConfigurationExtensions
{
    private static IConfigurationRefresher? _refresher;

    /// <summary>
    /// Adds Azure App Configuration to the configuration builder.
    /// </summary>
    public static IConfigurationBuilder AddAzureAppConfiguration(
        this IConfigurationBuilder builder,
        AzureAppConfigurationSettings? settings = null)
    {
        // Read settings from existing configuration first
        var tempConfig = builder.Build();
        settings ??= new AzureAppConfigurationSettings();
        tempConfig.GetSection(AzureAppConfigurationSettings.SectionName).Bind(settings);

        if (!settings.Enabled)
        {
            return builder;
        }

        builder.AddAzureAppConfiguration(options =>
        {
            // Configure connection
            if (!string.IsNullOrEmpty(settings.ConnectionString))
            {
                options.Connect(settings.ConnectionString);
            }
            else if (!string.IsNullOrEmpty(settings.Endpoint))
            {
                if (settings.UseManagedIdentity)
                {
                    options.Connect(new Uri(settings.Endpoint), new DefaultAzureCredential());
                }
                else
                {
                    throw new InvalidOperationException(
                        "Azure App Configuration requires either a ConnectionString or UseManagedIdentity=true with Endpoint");
                }
            }
            else
            {
                throw new InvalidOperationException(
                    "Azure App Configuration requires either an Endpoint or ConnectionString");
            }

            // Configure key selection
            var label = string.IsNullOrEmpty(settings.Label) ? LabelFilter.Null : settings.Label;

            options.Select($"{settings.KeyPrefix}*", label)
                   .TrimKeyPrefix(settings.KeyPrefix);

            // Configure refresh
            if (settings.EnableRefresh)
            {
                options.ConfigureRefresh(refresh =>
                {
                    refresh.Register(settings.SentinelKey, label, refreshAll: true)
                           .SetCacheExpiration(TimeSpan.FromSeconds(settings.CacheExpirationSeconds));
                });
            }

            // Configure feature flags
            if (settings.EnableFeatureFlags)
            {
                options.UseFeatureFlags(featureFlags =>
                {
                    featureFlags.SetRefreshInterval(TimeSpan.FromSeconds(settings.CacheExpirationSeconds));
                    featureFlags.Label = label;
                });
            }

            // Configure Key Vault references
            if (settings.EnableKeyVaultReferences)
            {
                options.ConfigureKeyVault(kv =>
                {
                    kv.SetCredential(new DefaultAzureCredential());
                });
            }

            // Store refresher for later use
            _refresher = options.GetRefresher();
        });

        return builder;
    }

    /// <summary>
    /// Gets the configuration refresher for manual refresh operations.
    /// </summary>
    public static IConfigurationRefresher? GetRefresher() => _refresher;

    /// <summary>
    /// Adds Azure App Configuration middleware services.
    /// </summary>
    public static IServiceCollection AddAzureAppConfigurationServices(
        this IServiceCollection services)
    {
        services.AddAzureAppConfiguration();
        return services;
    }

    /// <summary>
    /// Uses Azure App Configuration middleware for automatic refresh.
    /// </summary>
    public static WebApplication UseAzureAppConfigurationRefresh(
        this WebApplication app,
        AzureAppConfigurationSettings? settings = null)
    {
        settings ??= new AzureAppConfigurationSettings();
        app.Configuration.GetSection(AzureAppConfigurationSettings.SectionName).Bind(settings);

        if (settings.Enabled && settings.EnableRefresh)
        {
            app.UseAzureAppConfiguration();
        }

        return app;
    }
}

/// <summary>
/// Configuration change watcher for Azure App Configuration.
/// </summary>
public sealed class ConfigurationChangeWatcher : IDisposable
{
    private readonly IConfigurationRefresher? _refresher;
    private readonly Timer? _timer;
    private readonly ILogger<ConfigurationChangeWatcher> _logger;

    public ConfigurationChangeWatcher(
        AzureAppConfigurationSettings settings,
        ILogger<ConfigurationChangeWatcher> logger)
    {
        _logger = logger;
        _refresher = AzureAppConfigurationExtensions.GetRefresher();

        if (_refresher != null && settings.EnableRefresh)
        {
            _timer = new Timer(
                async _ => await RefreshAsync(),
                null,
                TimeSpan.FromSeconds(settings.CacheExpirationSeconds),
                TimeSpan.FromSeconds(settings.CacheExpirationSeconds));
        }
    }

    /// <summary>
    /// Event raised when configuration changes are detected.
    /// </summary>
    public event EventHandler<ConfigurationChangedEventArgs>? ConfigurationChanged;

    private async Task RefreshAsync()
    {
        if (_refresher == null) return;

        try
        {
            var refreshed = await _refresher.TryRefreshAsync();
            if (refreshed)
            {
                _logger.LogInformation("Configuration refreshed from Azure App Configuration");
                ConfigurationChanged?.Invoke(this, new ConfigurationChangedEventArgs());
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to refresh configuration from Azure App Configuration");
        }
    }

    public void Dispose()
    {
        _timer?.Dispose();
    }
}

/// <summary>
/// Event args for configuration change events.
/// </summary>
public sealed class ConfigurationChangedEventArgs : EventArgs
{
    /// <summary>
    /// The time when the configuration change was detected.
    /// </summary>
    public DateTime Timestamp { get; } = DateTime.UtcNow;
}
