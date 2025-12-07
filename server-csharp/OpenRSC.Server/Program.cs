using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenRSC.Server.Configuration;
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

    // Register services
    builder.Services.AddSingleton<IWorldService, WorldService>();
    builder.Services.AddSingleton<GameTickProcessor>();

    // Register the game server as a hosted service
    builder.Services.AddHostedService<GameServerHost>();

    // Build and run
    var host = builder.Build();
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
