using System.Diagnostics;
using System.Reflection;
using Microsoft.AspNetCore.Mvc;

namespace OpenRSC.Server.Infrastructure.Http;

/// <summary>
/// Extension methods for registering API endpoints.
/// </summary>
public static class ApiEndpoints
{
    /// <summary>
    /// Maps all REST API endpoints.
    /// </summary>
    public static WebApplication MapApiEndpoints(this WebApplication app)
    {
        // Server info endpoints
        app.MapServerInfoEndpoints();

        // Health check endpoints
        app.MapHealthCheckEndpoints();

        // Metrics endpoints (Prometheus format)
        app.MapPrometheusEndpoints();

        // Admin endpoints (requires API key)
        app.MapAdminEndpoints();

        // Game status endpoints
        app.MapGameStatusEndpoints();

        return app;
    }

    private static void MapServerInfoEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/server")
            .WithTags("Server");

        group.MapGet("/info", () =>
        {
            var assembly = Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version?.ToString() ?? "1.0.0";

            return Results.Ok(new ServerInfoResponse
            {
                Name = "OpenRSC Server",
                Version = version,
                StartTime = Process.GetCurrentProcess().StartTime.ToUniversalTime(),
                Uptime = DateTime.UtcNow - Process.GetCurrentProcess().StartTime.ToUniversalTime(),
                Environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production",
                DotNetVersion = Environment.Version.ToString(),
                OperatingSystem = Environment.OSVersion.ToString(),
                ProcessorCount = Environment.ProcessorCount
            });
        })
        .WithName("GetServerInfo")
        .WithDescription("Get server information and status")
        .Produces<ServerInfoResponse>();

        group.MapGet("/time", () =>
        {
            return Results.Ok(new
            {
                utc = DateTime.UtcNow,
                local = DateTime.Now,
                timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            });
        })
        .WithName("GetServerTime")
        .WithDescription("Get current server time");
    }

    private static void MapHealthCheckEndpoints(this WebApplication app)
    {
        // Standard health check endpoints are mapped via UseHealthChecks middleware
        // This adds additional diagnostic endpoints

        var group = app.MapGroup("/api/v1/health")
            .WithTags("Health");

        group.MapGet("/live", () => Results.Ok(new { status = "Healthy", timestamp = DateTime.UtcNow }))
            .WithName("LivenessProbe")
            .WithDescription("Kubernetes liveness probe");

        group.MapGet("/ready", (IServiceProvider services) =>
        {
            // Check if critical services are ready
            var isReady = true; // Add actual readiness checks here

            return isReady
                ? Results.Ok(new { status = "Ready", timestamp = DateTime.UtcNow })
                : Results.StatusCode(503);
        })
        .WithName("ReadinessProbe")
        .WithDescription("Kubernetes readiness probe");

        group.MapGet("/startup", () => Results.Ok(new { status = "Started", timestamp = DateTime.UtcNow }))
            .WithName("StartupProbe")
            .WithDescription("Kubernetes startup probe");
    }

    private static void MapPrometheusEndpoints(this WebApplication app)
    {
        // Prometheus metrics are exposed via OpenTelemetry middleware
        // at /metrics endpoint - configured separately
    }

    private static void MapAdminEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/admin")
            .WithTags("Admin")
            .RequireAuthorization("AdminApiKey");

        group.MapPost("/gc", () =>
        {
            var before = GC.GetTotalMemory(false);
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            var after = GC.GetTotalMemory(true);

            return Results.Ok(new
            {
                memoryBefore = before,
                memoryAfter = after,
                memoryFreed = before - after,
                timestamp = DateTime.UtcNow
            });
        })
        .WithName("ForceGarbageCollection")
        .WithDescription("Force garbage collection (admin only)");

        group.MapGet("/memory", () =>
        {
            var process = Process.GetCurrentProcess();

            return Results.Ok(new MemoryStatsResponse
            {
                WorkingSet = process.WorkingSet64,
                PrivateMemory = process.PrivateMemorySize64,
                VirtualMemory = process.VirtualMemorySize64,
                GcTotalMemory = GC.GetTotalMemory(false),
                Gen0Collections = GC.CollectionCount(0),
                Gen1Collections = GC.CollectionCount(1),
                Gen2Collections = GC.CollectionCount(2),
                Timestamp = DateTime.UtcNow
            });
        })
        .WithName("GetMemoryStats")
        .WithDescription("Get memory statistics (admin only)");

        group.MapGet("/threads", () =>
        {
            var process = Process.GetCurrentProcess();
            ThreadPool.GetAvailableThreads(out var workerThreads, out var completionPortThreads);
            ThreadPool.GetMaxThreads(out var maxWorkerThreads, out var maxCompletionPortThreads);
            ThreadPool.GetMinThreads(out var minWorkerThreads, out var minCompletionPortThreads);

            return Results.Ok(new
            {
                processThreads = process.Threads.Count,
                workerThreads = new
                {
                    available = workerThreads,
                    max = maxWorkerThreads,
                    min = minWorkerThreads,
                    inUse = maxWorkerThreads - workerThreads
                },
                completionPortThreads = new
                {
                    available = completionPortThreads,
                    max = maxCompletionPortThreads,
                    min = minCompletionPortThreads,
                    inUse = maxCompletionPortThreads - completionPortThreads
                },
                timestamp = DateTime.UtcNow
            });
        })
        .WithName("GetThreadStats")
        .WithDescription("Get thread pool statistics (admin only)");
    }

    private static void MapGameStatusEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/game")
            .WithTags("Game");

        group.MapGet("/status", (IServiceProvider services) =>
        {
            // These would be populated from actual game services
            return Results.Ok(new GameStatusResponse
            {
                PlayersOnline = 0, // Get from WorldService
                MaxPlayers = 2000,
                WorldNumber = 1,
                IsOnline = true,
                Uptime = DateTime.UtcNow - Process.GetCurrentProcess().StartTime.ToUniversalTime(),
                Timestamp = DateTime.UtcNow
            });
        })
        .WithName("GetGameStatus")
        .WithDescription("Get current game status");

        group.MapGet("/worlds", () =>
        {
            // Return list of available worlds
            return Results.Ok(new[]
            {
                new WorldInfoResponse
                {
                    WorldNumber = 1,
                    Name = "OpenRSC World 1",
                    Region = "US-East",
                    Players = 0,
                    MaxPlayers = 2000,
                    IsMembersOnly = true,
                    IsOnline = true
                }
            });
        })
        .WithName("GetWorlds")
        .WithDescription("Get list of available worlds");
    }
}

#region Response Models

public record ServerInfoResponse
{
    public required string Name { get; init; }
    public required string Version { get; init; }
    public required DateTime StartTime { get; init; }
    public required TimeSpan Uptime { get; init; }
    public required string Environment { get; init; }
    public required string DotNetVersion { get; init; }
    public required string OperatingSystem { get; init; }
    public required int ProcessorCount { get; init; }
}

public record MemoryStatsResponse
{
    public required long WorkingSet { get; init; }
    public required long PrivateMemory { get; init; }
    public required long VirtualMemory { get; init; }
    public required long GcTotalMemory { get; init; }
    public required int Gen0Collections { get; init; }
    public required int Gen1Collections { get; init; }
    public required int Gen2Collections { get; init; }
    public required DateTime Timestamp { get; init; }
}

public record GameStatusResponse
{
    public required int PlayersOnline { get; init; }
    public required int MaxPlayers { get; init; }
    public required int WorldNumber { get; init; }
    public required bool IsOnline { get; init; }
    public required TimeSpan Uptime { get; init; }
    public required DateTime Timestamp { get; init; }
}

public record WorldInfoResponse
{
    public required int WorldNumber { get; init; }
    public required string Name { get; init; }
    public required string Region { get; init; }
    public required int Players { get; init; }
    public required int MaxPlayers { get; init; }
    public required bool IsMembersOnly { get; init; }
    public required bool IsOnline { get; init; }
}

#endregion
