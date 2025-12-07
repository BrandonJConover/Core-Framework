using System.Diagnostics;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Services;

/// <summary>
/// Background service that runs the main game loop.
/// Uses modern .NET hosting patterns for lifecycle management.
/// </summary>
public sealed class GameServerHost : BackgroundService
{
    private readonly ILogger<GameServerHost> _logger;
    private readonly ServerSettings _settings;
    private readonly GameTickProcessor _tickProcessor;
    private readonly CombatSettings _combatSettings;

    private DateTime _serverStartTime;
    private long _totalTicksProcessed;

    public GameServerHost(
        ILogger<GameServerHost> logger,
        IOptions<ServerSettings> settings,
        IOptions<CombatSettings> combatSettings,
        GameTickProcessor tickProcessor)
    {
        _logger = logger;
        _settings = settings.Value;
        _combatSettings = combatSettings.Value;
        _tickProcessor = tickProcessor;
    }

    /// <summary>
    /// Server start time.
    /// </summary>
    public DateTime ServerStartTime => _serverStartTime;

    /// <summary>
    /// Total ticks processed since server start.
    /// </summary>
    public long TotalTicksProcessed => _totalTicksProcessed;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _serverStartTime = DateTime.UtcNow;
        _logger.LogInformation("Starting {ServerName} server...", _settings.ServerName);

        var tickInterval = TimeSpan.FromMilliseconds(_settings.GameTickMs);
        var stopwatch = Stopwatch.StartNew();

        while (!stoppingToken.IsCancellationRequested)
        {
            var tickStart = stopwatch.Elapsed;

            try
            {
                await _tickProcessor.ProcessTickAsync(stoppingToken);
                Interlocked.Increment(ref _totalTicksProcessed);

                // PID-less catching for PvP if enabled
                if (_combatSettings.PidlessCatching)
                {
                    _tickProcessor.ExecutePidlessCatching();
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "Error in game tick {Tick}", _totalTicksProcessed);
            }

            // Calculate time spent and sleep for remainder of tick
            var tickDuration = stopwatch.Elapsed - tickStart;
            var sleepTime = tickInterval - tickDuration;

            if (sleepTime > TimeSpan.Zero)
            {
                await Task.Delay(sleepTime, stoppingToken);
            }
            else if (_settings.Debug)
            {
                _logger.LogWarning(
                    "Tick {Tick} took {Duration}ms (over budget by {Over}ms)",
                    _totalTicksProcessed,
                    tickDuration.TotalMilliseconds,
                    -sleepTime.TotalMilliseconds);
            }
        }

        _logger.LogInformation("Server shutting down after {Ticks} ticks", _totalTicksProcessed);
    }
}
