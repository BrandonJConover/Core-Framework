using Microsoft.Extensions.Logging;
using OpenRSC.Server.ML;
using OpenRSC.Server.Simulation;
using OpenRSC.Server.Skills;

// Configure logging
using var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddConsole();
    builder.SetMinimumLevel(LogLevel.Information);
});

var logger = loggerFactory.CreateLogger<GameCompletionTrainer>();

Console.WriteLine("===========================================");
Console.WriteLine("  OpenRSC Bot Training Runner");
Console.WriteLine("===========================================");
Console.WriteLine();

// Parse arguments
var difficulty = args.Length > 0 ? args[0].ToLower() : "easy";
var maxEpisodes = args.Length > 1 ? int.Parse(args[1]) : 50;

var criteria = difficulty switch
{
    "medium" => GameCompletionCriteria.Medium,
    "hard" => GameCompletionCriteria.Hard,
    _ => GameCompletionCriteria.Easy
};

Console.WriteLine($"Difficulty: {difficulty}");
Console.WriteLine($"Target Combat Level: {criteria.TargetCombatLevel}");
Console.WriteLine($"Target Total Level: {criteria.TargetTotalLevel}");
Console.WriteLine($"Max Episodes: {maxEpisodes}");
Console.WriteLine();

// Create trainer
var trainer = new GameCompletionTrainer(logger, criteria, seed: 42);

// Subscribe to progress events
trainer.OnLog += (_, msg) => Console.WriteLine($"[LOG] {msg}");
trainer.OnProgress += (_, progress) =>
{
    Console.WriteLine($"  Progress: {progress.CompletionPercent(criteria):F1}% | " +
                     $"Combat: {progress.CurrentCombatLevel} | " +
                     $"Total: {progress.CurrentTotalLevel} | " +
                     $"Kills: {progress.TotalKills} | " +
                     $"Deaths: {progress.TotalDeaths}");
};

Console.WriteLine("Starting training...");
Console.WriteLine();

var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    Console.WriteLine("\nStopping training...");
    cts.Cancel();
};

try
{
    var startTime = DateTime.Now;
    var result = await trainer.TrainUntilCompleteAsync(maxEpisodes, cts.Token);
    var elapsed = DateTime.Now - startTime;

    Console.WriteLine();
    Console.WriteLine("===========================================");
    Console.WriteLine("  Training Results");
    Console.WriteLine("===========================================");
    Console.WriteLine();
    Console.WriteLine(result.ToString());
    Console.WriteLine($"Time Elapsed: {elapsed.TotalMinutes:F1} minutes");
    Console.WriteLine();

    if (result.IsComplete(criteria))
    {
        Console.WriteLine("SUCCESS! Bots successfully beat the game!");
        Console.WriteLine($"Final Combat Level: {result.CurrentCombatLevel}");
        Console.WriteLine($"Final Total Level: {result.CurrentTotalLevel}");
        return 0;
    }
    else if (result.HasFailed(criteria))
    {
        Console.WriteLine("FAILED: Too many deaths");
        return 1;
    }
    else
    {
        Console.WriteLine($"Training stopped at {result.CompletionPercent(criteria):F1}% completion");
        Console.WriteLine("Run with more episodes to continue training.");
        return 2;
    }
}
catch (OperationCanceledException)
{
    Console.WriteLine("Training cancelled by user.");
    return 3;
}
