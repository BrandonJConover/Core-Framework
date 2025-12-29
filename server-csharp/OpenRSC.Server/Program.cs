using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Database;
using OpenRSC.Server.Events;
using OpenRSC.Server.Network;
using OpenRSC.Server.Services;
using Serilog;

// Configure Serilog
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console(
        outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
    .WriteTo.File("logs/server-.log",
        rollingInterval: RollingInterval.Day,
        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {Message:lj}{NewLine}{Exception}")
    .CreateLogger();

try
{
    Log.Information("Starting OpenRSC Server...");

    var builder = Host.CreateApplicationBuilder(args);

    // Configure services
    builder.Services.AddSerilog();

    // Bind configuration sections
    builder.Services.Configure<ServerSettings>(
        builder.Configuration.GetSection(ServerSettings.SectionName));
    builder.Services.Configure<CombatSettings>(
        builder.Configuration.GetSection(CombatSettings.SectionName));
    builder.Services.Configure<ActionRetrySettings>(
        builder.Configuration.GetSection(ActionRetrySettings.SectionName));
    builder.Services.Configure<DatabaseSettings>(
        builder.Configuration.GetSection(DatabaseSettings.SectionName));

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

    // Build and run
    var host = builder.Build();

    // Initialize packet handlers
    var packetDispatcher = host.Services.GetRequiredService<PacketDispatcher>();
    packetDispatcher.RegisterHandlers(typeof(Program).Assembly);

    Log.Information("Server initialized - TCP port {TcpPort}, WebSocket port {WsPort}",
        host.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<ServerSettings>>().Value.ServerPort,
        host.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<ServerSettings>>().Value.WebSocketPort);

    await host.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Server terminated unexpectedly");
}
finally
{
    await Log.CloseAndFlushAsync();
}
