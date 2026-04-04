using System.Collections.Concurrent;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Minigames;

/// <summary>
/// Fishing Trawler game state.
/// </summary>
public enum TrawlerState
{
    Waiting,
    InProgress,
    Returning,
    Finished
}

/// <summary>
/// Fishing Trawler configuration.
/// </summary>
public static class TrawlerConfig
{
    public const int MinPlayers = 1;
    public const int MaxPlayers = 10;
    public const int RequiredFishingLevel = 15;
    public const int GameDurationTicks = 600; // ~10 minutes
    public const int WaitDurationTicks = 100; // ~1.5 minutes between games
    public const int LeakChanceTicks = 10;   // Check for leaks every 10 ticks
    public const int MaxLeaks = 10;
    public const int MaxWater = 100;
    public const int WaterPerLeak = 5;
    public const int BailAmount = 10;
}

/// <summary>
/// A leak on the trawler.
/// </summary>
public sealed class TrawlerLeak
{
    public int Id { get; init; }
    public Point Location { get; init; }
    public bool IsRepaired { get; set; }

    public TrawlerLeak(int id, Point location)
    {
        Id = id;
        Location = location;
        IsRepaired = false;
    }
}

/// <summary>
/// Player's contribution to a trawler game.
/// </summary>
public sealed class TrawlerContribution
{
    public Player Player { get; init; }
    public int LeaksRepaired { get; set; }
    public int WaterBailed { get; set; }
    public int NetsFilled { get; set; }

    public TrawlerContribution(Player player)
    {
        Player = player;
    }

    public int GetActivityScore()
    {
        return LeaksRepaired * 3 + WaterBailed + NetsFilled * 2;
    }
}

/// <summary>
/// Represents a Fishing Trawler game instance.
/// </summary>
public sealed class FishingTrawlerGame
{
    private readonly List<TrawlerLeak> _leaks = new();
    private readonly Dictionary<Player, TrawlerContribution> _contributions = new();
    private int _nextLeakId;

    public Guid GameId { get; } = Guid.NewGuid();
    public TrawlerState State { get; private set; } = TrawlerState.Waiting;
    public int WaterLevel { get; private set; }
    public int TicksRemaining { get; private set; }
    public int NetStatus { get; private set; } = 100; // 0-100, degrades over time

    public IReadOnlyList<TrawlerLeak> Leaks => _leaks;
    public IReadOnlyCollection<Player> Players => _contributions.Keys;
    public int PlayerCount => _contributions.Count;
    public bool IsFull => PlayerCount >= TrawlerConfig.MaxPlayers;
    public bool IsSinking => WaterLevel >= TrawlerConfig.MaxWater;

    /// <summary>
    /// Adds a player to the game.
    /// </summary>
    public TrawlerResult JoinGame(Player player)
    {
        if (State != TrawlerState.Waiting)
            return TrawlerResult.Fail("The game has already started.");

        if (IsFull)
            return TrawlerResult.Fail("The trawler is full.");

        var fishingLevel = player.Skills.GetCurrentLevel(Skill.Fishing);
        if (fishingLevel < TrawlerConfig.RequiredFishingLevel)
            return TrawlerResult.Fail($"You need level {TrawlerConfig.RequiredFishingLevel} Fishing to play.");

        if (_contributions.ContainsKey(player))
            return TrawlerResult.Fail("You are already on the trawler.");

        _contributions[player] = new TrawlerContribution(player);
        player.Message("You board the fishing trawler.");
        BroadcastMessage($"{player.Username} has joined the trawler.");

        return TrawlerResult.Ok;
    }

    /// <summary>
    /// Removes a player from the game.
    /// </summary>
    public void LeaveGame(Player player)
    {
        if (_contributions.Remove(player))
        {
            player.Message("You leave the fishing trawler.");
            BroadcastMessage($"{player.Username} has left the trawler.");
        }
    }

    /// <summary>
    /// Starts the game.
    /// </summary>
    public TrawlerResult StartGame()
    {
        if (State != TrawlerState.Waiting)
            return TrawlerResult.Fail("Game already in progress.");

        if (PlayerCount < TrawlerConfig.MinPlayers)
            return TrawlerResult.Fail($"Need at least {TrawlerConfig.MinPlayers} players to start.");

        State = TrawlerState.InProgress;
        TicksRemaining = TrawlerConfig.GameDurationTicks;
        WaterLevel = 0;
        NetStatus = 100;
        _leaks.Clear();

        BroadcastMessage("The trawler sets sail!");

        return TrawlerResult.Ok;
    }

    /// <summary>
    /// Processes a game tick.
    /// </summary>
    public void ProcessTick()
    {
        if (State != TrawlerState.InProgress)
            return;

        TicksRemaining--;

        // Check for new leaks
        if (TicksRemaining % TrawlerConfig.LeakChanceTicks == 0)
        {
            TrySpawnLeak();
        }

        // Water increases from leaks
        var activeLeaks = _leaks.Count(l => !l.IsRepaired);
        WaterLevel += activeLeaks * TrawlerConfig.WaterPerLeak / 10;

        // Net degrades
        if (Random.Shared.NextDouble() < 0.1)
        {
            NetStatus = Math.Max(0, NetStatus - 1);
        }

        // Check for sinking
        if (IsSinking)
        {
            EndGame(false);
            return;
        }

        // Check for time up
        if (TicksRemaining <= 0)
        {
            State = TrawlerState.Returning;
            BroadcastMessage("The trawler is returning to port!");
            // Would trigger return in 20 ticks
        }
    }

    private void TrySpawnLeak()
    {
        if (_leaks.Count(l => !l.IsRepaired) >= TrawlerConfig.MaxLeaks)
            return;

        if (Random.Shared.NextDouble() < 0.3)
        {
            var leak = new TrawlerLeak(_nextLeakId++, GetRandomLeakLocation());
            _leaks.Add(leak);
            BroadcastMessage("A leak has sprung! Quick, repair it!");
        }
    }

    private Point GetRandomLeakLocation()
    {
        // Random position on the trawler deck
        return new Point(Random.Shared.Next(10), Random.Shared.Next(5));
    }

    /// <summary>
    /// Player repairs a leak.
    /// </summary>
    public TrawlerResult RepairLeak(Player player, int leakId)
    {
        if (State != TrawlerState.InProgress)
            return TrawlerResult.Fail("The game is not in progress.");

        if (!_contributions.TryGetValue(player, out var contribution))
            return TrawlerResult.Fail("You are not on the trawler.");

        var leak = _leaks.FirstOrDefault(l => l.Id == leakId);
        if (leak is null)
            return TrawlerResult.Fail("That leak doesn't exist.");

        if (leak.IsRepaired)
            return TrawlerResult.Fail("That leak is already repaired.");

        // Check for swamp paste
        const int swampPasteId = 1101;
        if (!player.Inventory.HasItem(swampPasteId))
            return TrawlerResult.Fail("You need swamp paste to repair leaks.");

        player.Inventory.Remove(swampPasteId, 1);
        leak.IsRepaired = true;
        contribution.LeaksRepaired++;

        player.Message("You repair the leak.");
        return TrawlerResult.Ok;
    }

    /// <summary>
    /// Player bails water.
    /// </summary>
    public TrawlerResult BailWater(Player player)
    {
        if (State != TrawlerState.InProgress)
            return TrawlerResult.Fail("The game is not in progress.");

        if (!_contributions.TryGetValue(player, out var contribution))
            return TrawlerResult.Fail("You are not on the trawler.");

        if (WaterLevel <= 0)
            return TrawlerResult.Fail("There's no water to bail.");

        // Check for bailing bucket
        const int bailingBucketId = 1100;
        if (!player.Inventory.HasItem(bailingBucketId))
            return TrawlerResult.Fail("You need a bailing bucket.");

        WaterLevel = Math.Max(0, WaterLevel - TrawlerConfig.BailAmount);
        contribution.WaterBailed += TrawlerConfig.BailAmount;

        player.Message("You bail some water.");
        return TrawlerResult.Ok;
    }

    /// <summary>
    /// Player fills the net.
    /// </summary>
    public TrawlerResult FillNet(Player player)
    {
        if (State != TrawlerState.InProgress)
            return TrawlerResult.Fail("The game is not in progress.");

        if (!_contributions.TryGetValue(player, out var contribution))
            return TrawlerResult.Fail("You are not on the trawler.");

        if (NetStatus >= 100)
            return TrawlerResult.Fail("The net is already full.");

        // Check for rope
        const int ropeId = 237;
        if (!player.Inventory.HasItem(ropeId))
            return TrawlerResult.Fail("You need rope to fill the net.");

        NetStatus = Math.Min(100, NetStatus + 10);
        contribution.NetsFilled++;

        player.Message("You add to the net.");
        return TrawlerResult.Ok;
    }

    /// <summary>
    /// Ends the game.
    /// </summary>
    public void EndGame(bool success)
    {
        State = TrawlerState.Finished;

        if (success)
        {
            BroadcastMessage("The trawler has returned safely!");
            DistributeRewards();
        }
        else
        {
            BroadcastMessage("The trawler has sunk!");
            // Players are teleported to shore with no rewards
        }
    }

    private void DistributeRewards()
    {
        foreach (var (player, contribution) in _contributions)
        {
            var score = contribution.GetActivityScore();
            if (score < 5)
            {
                player.Message("You didn't contribute enough to receive any fish.");
                continue;
            }

            var fishingLevel = player.Skills.GetCurrentLevel(Skill.Fishing);
            var rewards = GenerateRewards(fishingLevel, score);

            foreach (var (itemId, amount) in rewards)
            {
                // Would add to reward container
                player.Message($"You receive {amount} fish!");
            }

            // Grant XP
            var xp = score * 5 + fishingLevel * 2;
            player.Skills.AddExperience(Skill.Fishing, xp);
        }
    }

    private IEnumerable<(int ItemId, int Amount)> GenerateRewards(int fishingLevel, int score)
    {
        var fishCount = score / 5 + Random.Shared.Next(3);

        // Higher level = better fish
        if (fishingLevel >= 50 && Random.Shared.NextDouble() < 0.1)
        {
            yield return (370, 1); // Manta ray
        }
        if (fishingLevel >= 44 && Random.Shared.NextDouble() < 0.2)
        {
            yield return (367, Random.Shared.Next(1, 4)); // Shark
        }
        if (fishingLevel >= 40 && Random.Shared.NextDouble() < 0.3)
        {
            yield return (364, Random.Shared.Next(1, 5)); // Lobster
        }
        if (fishingLevel >= 30)
        {
            yield return (359, Random.Shared.Next(1, 5)); // Tuna
        }
        if (fishingLevel >= 20)
        {
            yield return (356, Random.Shared.Next(2, 6)); // Trout
        }
        yield return (349, Random.Shared.Next(1, 4)); // Anchovies
    }

    private void BroadcastMessage(string message)
    {
        foreach (var player in Players)
        {
            player.Message($"[Trawler] {message}");
        }
    }
}

/// <summary>
/// Result of a trawler operation.
/// </summary>
public readonly record struct TrawlerResult(bool Success, string? Message = null)
{
    public static TrawlerResult Fail(string message) => new(false, message);
    public static readonly TrawlerResult Ok = new(true);
}

/// <summary>
/// Manages Fishing Trawler minigame instances.
/// </summary>
public sealed class FishingTrawlerManager
{
    private readonly ConcurrentDictionary<Guid, FishingTrawlerGame> _games = new();
    private FishingTrawlerGame? _waitingGame;

    /// <summary>
    /// Gets or creates a waiting game for players to join.
    /// </summary>
    public FishingTrawlerGame GetOrCreateWaitingGame()
    {
        if (_waitingGame is null || _waitingGame.State != TrawlerState.Waiting)
        {
            _waitingGame = new FishingTrawlerGame();
            _games[_waitingGame.GameId] = _waitingGame;
        }
        return _waitingGame;
    }

    /// <summary>
    /// Processes all active games.
    /// </summary>
    public void ProcessTick()
    {
        foreach (var game in _games.Values)
        {
            if (game.State == TrawlerState.InProgress)
            {
                game.ProcessTick();
            }
            else if (game.State == TrawlerState.Finished)
            {
                // Clean up finished games after delay
                _games.TryRemove(game.GameId, out _);
            }
        }
    }

    /// <summary>
    /// Gets a player's current game.
    /// </summary>
    public FishingTrawlerGame? GetPlayerGame(Player player)
    {
        return _games.Values.FirstOrDefault(g => g.Players.Contains(player));
    }
}
