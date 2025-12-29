using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Database;
using OpenRSC.Server.Events;
using OpenRSC.Server.Infrastructure;
using OpenRSC.Server.Infrastructure.Configuration;
using OpenRSC.Server.Infrastructure.Http;
using OpenRSC.Server.Infrastructure.Observability;
using OpenRSC.Server.Network;
using OpenRSC.Server.Services;
using Serilog;

try
{
    // Create web application builder (for Kestrel support)
    var builder = WebApplication.CreateBuilder(args);

    // Add Azure App Configuration (must be done early for configuration refresh)
    var azureAppConfigSettings = new AzureAppConfigurationSettings();
    builder.Configuration.GetSection(AzureAppConfigurationSettings.SectionName).Bind(azureAppConfigSettings);

    if (azureAppConfigSettings.Enabled)
    {
        builder.Configuration.AddAzureAppConfiguration(azureAppConfigSettings);
    }

    // Add all modern infrastructure services (Serilog, serialization, QUIC, service discovery, etc.)
    builder.AddInfrastructureServices();

    Log.Information("Starting OpenRSC Server with modern infrastructure...");

    // Bind configuration sections
    builder.Services.Configure<ServerSettings>(
        builder.Configuration.GetSection(ServerSettings.SectionName));
    builder.Services.Configure<CombatSettings>(
        builder.Configuration.GetSection(CombatSettings.SectionName));
    builder.Services.Configure<ActionRetrySettings>(
        builder.Configuration.GetSection(ActionRetrySettings.SectionName));
    builder.Services.Configure<DatabaseSettings>(
        builder.Configuration.GetSection(DatabaseSettings.SectionName));
    builder.Services.Configure<SecuritySettings>(
        builder.Configuration.GetSection(SecuritySettings.SectionName));
    builder.Services.Configure<OAuthSettings>(
        builder.Configuration.GetSection(OAuthSettings.SectionName));
    builder.Services.Configure<AuthTokenSettings>(
        builder.Configuration.GetSection(AuthTokenSettings.SectionName));
    builder.Services.Configure<RedisSettings>(
        builder.Configuration.GetSection(RedisSettings.SectionName));
    builder.Services.Configure<DDoSProtectionSettings>(
        builder.Configuration.GetSection(DDoSProtectionSettings.SectionName));
    builder.Services.Configure<DeviceSettings>(
        builder.Configuration.GetSection(DeviceSettings.SectionName));

    // Register core services
    builder.Services.AddSingleton<IWorldService, WorldService>();
    builder.Services.AddSingleton<GameTickProcessor>();
    builder.Services.AddSingleton<EventManager>();

    // Register database services
    builder.Services.AddSingleton<IPlayerRepository, MySqlPlayerRepository>();

    // Register network services
    builder.Services.AddSingleton<PacketDispatcher>();

    // Register hosted services (order matters - network before game loop)
    builder.Services.AddHostedService<NetworkServer>();
    builder.Services.AddHostedService<WebSocketServer>(); // WebSocket support for web/mobile clients
    builder.Services.AddHostedService<GameServerHost>();

    // Build the application
    var app = builder.Build();

    // Configure the HTTP pipeline with infrastructure middleware
    app.UseInfrastructure();

    // Initialize packet handlers
    var packetDispatcher = app.Services.GetRequiredService<PacketDispatcher>();
    packetDispatcher.RegisterHandlers(typeof(Program).Assembly);

    // Log startup information
    var serverSettings = app.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<ServerSettings>>().Value;
    var httpSettings = new HttpServerSettings();
    app.Configuration.GetSection(HttpServerSettings.SectionName).Bind(httpSettings);

    Log.Information("Server initialized:");
    Log.Information("  - Game TCP port: {TcpPort}", serverSettings.ServerPort);
    Log.Information("  - WebSocket port: {WsPort}", serverSettings.WebSocketPort);

    if (httpSettings.Enabled)
    {
        Log.Information("  - HTTP API port: {HttpPort}", httpSettings.HttpPort);
        if (httpSettings.EnableHttps)
        {
            Log.Information("  - HTTPS API port: {HttpsPort} (HTTP/2, HTTP/3 enabled)", httpSettings.HttpsPort);
        }
    }

    var otelSettings = new OpenTelemetrySettings();
    app.Configuration.GetSection(OpenTelemetrySettings.SectionName).Bind(otelSettings);
    if (otelSettings.Enabled)
    {
        Log.Information("  - OpenTelemetry: Enabled (OTLP endpoint: {Endpoint})", otelSettings.OtlpEndpoint);
    }

    var prometheusSettings = new PrometheusSettings();
    app.Configuration.GetSection(PrometheusSettings.SectionName).Bind(prometheusSettings);
    if (prometheusSettings.Enabled)
    {
        Log.Information("  - Prometheus metrics: {Endpoint}", prometheusSettings.Endpoint);
    }

    // Run the application
    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Server terminated unexpectedly");
    throw;
}
finally
{
    await Log.CloseAndFlushAsync();
}
