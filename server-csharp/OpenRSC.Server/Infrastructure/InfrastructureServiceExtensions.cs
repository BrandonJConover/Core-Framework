using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using OpenRSC.Server.Infrastructure.Configuration;
using OpenRSC.Server.Infrastructure.Http;
using OpenRSC.Server.Infrastructure.Logging;
using OpenRSC.Server.Infrastructure.Observability;
using OpenRSC.Server.Infrastructure.Serialization;
using OpenRSC.Server.Infrastructure.ServiceDiscovery;
using OpenRSC.Server.Infrastructure.Transport;
using OpenRSC.Server.Network;
using Serilog;
using System.Text.Json;

namespace OpenRSC.Server.Infrastructure;

/// <summary>
/// Extension methods for registering all infrastructure services.
/// </summary>
public static class InfrastructureServiceExtensions
{
    /// <summary>
    /// Adds all modern infrastructure services to the DI container.
    /// </summary>
    public static WebApplicationBuilder AddInfrastructureServices(this WebApplicationBuilder builder)
    {
        var configuration = builder.Configuration;
        var services = builder.Services;

        // Configure enhanced Serilog
        ConfigureSerilog(builder, configuration);

        // Add serialization services
        services.AddSerializationServices(options =>
        {
            configuration.GetSection(SerializationSettings.SectionName).Bind(options);
        });

        // Add protocol adapter for dual-protocol support
        services.AddProtocolAdapter();

        // Add health checks
        AddHealthChecks(services, configuration);

        // Add HTTP server configuration
        var httpSettings = new HttpServerSettings();
        configuration.GetSection(HttpServerSettings.SectionName).Bind(httpSettings);

        if (httpSettings.Enabled)
        {
            builder.ConfigureKestrel(httpSettings);
            services.Configure<HttpServerSettings>(configuration.GetSection(HttpServerSettings.SectionName));

            // Add CORS
            services.AddCors(options =>
            {
                options.AddDefaultPolicy(policy =>
                {
                    var origins = httpSettings.CorsOrigins.Split(',', StringSplitOptions.RemoveEmptyEntries);
                    if (origins.Contains("*"))
                    {
                        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
                    }
                    else
                    {
                        policy.WithOrigins(origins).AllowAnyMethod().AllowAnyHeader();
                    }
                });
            });

            // Add authorization for admin endpoints
            if (!string.IsNullOrEmpty(httpSettings.AdminApiKey))
            {
                services.AddAuthorization(options =>
                {
                    options.AddPolicy("AdminApiKey", policy =>
                        policy.AddRequirements(new ApiKeyRequirement(httpSettings.AdminApiKey)));
                });
                services.AddSingleton<IAuthorizationHandler, ApiKeyAuthorizationHandler>();
            }
            else
            {
                // No API key configured - admin endpoints disabled
                services.AddAuthorization();
            }

            services.AddEndpointsApiExplorer();
        }

        // Add QUIC transport
        var quicSettings = new QuicTransportSettings();
        configuration.GetSection(QuicTransportSettings.SectionName).Bind(quicSettings);

        if (quicSettings.Enabled)
        {
            services.AddQuicTransport(options =>
            {
                configuration.GetSection(QuicTransportSettings.SectionName).Bind(options);
            });
        }

        // Add service discovery
        var sdSettings = new ServiceDiscoverySettings();
        configuration.GetSection(ServiceDiscoverySettings.SectionName).Bind(sdSettings);

        if (sdSettings.Enabled)
        {
            services.Configure<ConsulSettings>(configuration.GetSection(ConsulSettings.SectionName));
            services.Configure<EtcdSettings>(configuration.GetSection(EtcdSettings.SectionName));
            services.AddServiceDiscovery(options =>
            {
                configuration.GetSection(ServiceDiscoverySettings.SectionName).Bind(options);
            });
        }

        // Add Azure App Configuration services
        var azureAppConfigSettings = new AzureAppConfigurationSettings();
        configuration.GetSection(AzureAppConfigurationSettings.SectionName).Bind(azureAppConfigSettings);

        if (azureAppConfigSettings.Enabled)
        {
            services.AddAzureAppConfigurationServices();
        }

        // Add OpenTelemetry
        var otelSettings = new OpenTelemetrySettings();
        configuration.GetSection(OpenTelemetrySettings.SectionName).Bind(otelSettings);

        if (otelSettings.Enabled)
        {
            services.AddOpenTelemetryObservability(configuration);
        }

        // Add Prometheus metrics
        var prometheusSettings = new PrometheusSettings();
        configuration.GetSection(PrometheusSettings.SectionName).Bind(prometheusSettings);

        if (prometheusSettings.Enabled)
        {
            services.AddPrometheusMetrics(configuration);
        }

        // Add Application Insights
        var appInsightsSettings = new ApplicationInsightsSettings();
        configuration.GetSection(ApplicationInsightsSettings.SectionName).Bind(appInsightsSettings);

        if (appInsightsSettings.Enabled)
        {
            services.AddApplicationInsights(configuration);
        }

        return builder;
    }

    /// <summary>
    /// Configures the HTTP pipeline with infrastructure middleware.
    /// </summary>
    public static WebApplication UseInfrastructure(this WebApplication app)
    {
        var configuration = app.Configuration;

        // Azure App Configuration refresh
        var azureAppConfigSettings = new AzureAppConfigurationSettings();
        configuration.GetSection(AzureAppConfigurationSettings.SectionName).Bind(azureAppConfigSettings);

        if (azureAppConfigSettings.Enabled)
        {
            app.UseAzureAppConfigurationRefresh(azureAppConfigSettings);
        }

        // CORS
        app.UseCors();

        // Authorization
        app.UseAuthorization();

        // Health checks
        app.MapHealthChecks("/health", new HealthCheckOptions
        {
            ResponseWriter = WriteHealthCheckResponse
        });

        app.MapHealthChecks("/health/ready", new HealthCheckOptions
        {
            Predicate = check => check.Tags.Contains("ready"),
            ResponseWriter = WriteHealthCheckResponse
        });

        app.MapHealthChecks("/health/live", new HealthCheckOptions
        {
            Predicate = _ => false, // Liveness just returns 200
            ResponseWriter = WriteHealthCheckResponse
        });

        // Prometheus metrics endpoint
        var prometheusSettings = new PrometheusSettings();
        configuration.GetSection(PrometheusSettings.SectionName).Bind(prometheusSettings);

        if (prometheusSettings.Enabled)
        {
            app.UsePrometheusMetrics(prometheusSettings);
        }

        // API endpoints
        var httpSettings = new HttpServerSettings();
        configuration.GetSection(HttpServerSettings.SectionName).Bind(httpSettings);

        if (httpSettings.Enabled)
        {
            app.MapApiEndpoints();
        }

        return app;
    }

    private static void ConfigureSerilog(WebApplicationBuilder builder, IConfiguration configuration)
    {
        var loggingSettings = new LoggingSettings();
        configuration.GetSection(LoggingSettings.SectionName).Bind(loggingSettings);

        var loggerConfig = SerilogConfigurationBuilder.CreateLoggerConfiguration(configuration, loggingSettings);

        Log.Logger = loggerConfig.CreateLogger();
        builder.Host.UseSerilog();
    }

    private static void AddHealthChecks(IServiceCollection services, IConfiguration configuration)
    {
        var healthChecksBuilder = services.AddHealthChecks();

        // Add database health check based on provider
        var dbProvider = configuration.GetValue<string>("Database:Provider") ?? "MySQL";

        switch (dbProvider.ToLowerInvariant())
        {
            case "postgresql":
            case "postgres":
                var pgConnectionString = configuration.GetValue<string>("Database:ConnectionString");
                if (!string.IsNullOrEmpty(pgConnectionString))
                {
                    healthChecksBuilder.AddNpgSql(pgConnectionString, name: "database", tags: ["ready"]);
                }
                break;

            case "mysql":
                var mysqlConnectionString = configuration.GetValue<string>("Database:ConnectionString");
                if (!string.IsNullOrEmpty(mysqlConnectionString))
                {
                    healthChecksBuilder.AddMySql(mysqlConnectionString, name: "database", tags: ["ready"]);
                }
                break;
        }

        // Add Redis health check
        var redisEnabled = configuration.GetValue<bool>("Redis:Enabled");
        if (redisEnabled)
        {
            var redisConnectionString = configuration.GetValue<string>("Redis:ConnectionString") ?? "localhost:6379";
            healthChecksBuilder.AddRedis(redisConnectionString, name: "redis", tags: ["ready"]);
        }

        // Add Consul health check
        var consulEnabled = configuration.GetValue<bool>("Consul:Enabled");
        if (consulEnabled)
        {
            var consulAddress = configuration.GetValue<string>("Consul:Address") ?? "http://localhost:8500";
            healthChecksBuilder.AddConsul(options =>
            {
                options.HostName = new Uri(consulAddress).Host;
                options.Port = new Uri(consulAddress).Port;
            }, name: "consul", tags: ["ready"]);
        }
    }

    private static async Task WriteHealthCheckResponse(HttpContext context, HealthReport report)
    {
        context.Response.ContentType = "application/json";

        var response = new
        {
            status = report.Status.ToString(),
            totalDuration = report.TotalDuration.TotalMilliseconds,
            entries = report.Entries.Select(e => new
            {
                name = e.Key,
                status = e.Value.Status.ToString(),
                duration = e.Value.Duration.TotalMilliseconds,
                description = e.Value.Description,
                exception = e.Value.Exception?.Message,
                data = e.Value.Data
            })
        };

        await context.Response.WriteAsync(JsonSerializer.Serialize(response, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true
        }));
    }
}

/// <summary>
/// API key authorization requirement.
/// </summary>
public class ApiKeyRequirement : IAuthorizationRequirement
{
    public string ApiKey { get; }

    public ApiKeyRequirement(string apiKey)
    {
        ApiKey = apiKey;
    }
}

/// <summary>
/// API key authorization handler.
/// </summary>
public class ApiKeyAuthorizationHandler : AuthorizationHandler<ApiKeyRequirement>
{
    private const string ApiKeyHeaderName = "X-Api-Key";

    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        ApiKeyRequirement requirement)
    {
        if (context.Resource is HttpContext httpContext)
        {
            var apiKey = httpContext.Request.Headers[ApiKeyHeaderName].FirstOrDefault();

            if (!string.IsNullOrEmpty(apiKey) && apiKey == requirement.ApiKey)
            {
                context.Succeed(requirement);
            }
        }

        return Task.CompletedTask;
    }
}
