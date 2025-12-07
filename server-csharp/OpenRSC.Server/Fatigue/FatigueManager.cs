using OpenRSC.Server.Entities;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Fatigue;

/// <summary>
/// Manages player fatigue (RSC-specific system).
/// Fatigue accumulates as players gain XP and must be reduced by sleeping.
/// </summary>
public sealed class PlayerFatigue
{
    private readonly Player _player;

    /// <summary>
    /// Current fatigue (0-750,000 representing 0-100%).
    /// </summary>
    public int Current { get; private set; }

    /// <summary>
    /// Maximum fatigue value.
    /// </summary>
    public const int MaxFatigue = 750_000;

    /// <summary>
    /// Fatigue percentage (0-100).
    /// </summary>
    public double Percentage => Current * 100.0 / MaxFatigue;

    /// <summary>
    /// Whether fatigue is at maximum.
    /// </summary>
    public bool IsExhausted => Current >= MaxFatigue;

    /// <summary>
    /// Whether the player is currently sleeping.
    /// </summary>
    public bool IsSleeping { get; private set; }

    /// <summary>
    /// Current sleep word for verification.
    /// </summary>
    public string? SleepWord { get; private set; }

    public PlayerFatigue(Player player)
    {
        _player = player;
    }

    /// <summary>
    /// Adds fatigue based on XP gained.
    /// </summary>
    public void AddFatigue(int xpGained)
    {
        // Fatigue rate: roughly 4 fatigue per XP
        var fatigueGain = xpGained * 4;
        Current = Math.Min(MaxFatigue, Current + fatigueGain);

        if (IsExhausted)
        {
            _player.Message("You are very tired. You should rest.");
        }
    }

    /// <summary>
    /// Checks if the player can gain XP (not too fatigued).
    /// </summary>
    public bool CanGainXp()
    {
        if (!IsExhausted)
            return true;

        _player.Message("You are too tired to gain experience. You should sleep.");
        return false;
    }

    /// <summary>
    /// Starts sleeping at a bed or sleeping bag.
    /// </summary>
    public FatigueResult StartSleeping(bool isBed)
    {
        if (IsSleeping)
            return FatigueResult.Fail("You are already sleeping.");

        if (_player.InCombat)
            return FatigueResult.Fail("You can't sleep while in combat!");

        if (Current == 0)
        {
            _player.Message("You aren't very tired.");
            return FatigueResult.Success; // Still allow it
        }

        IsSleeping = true;
        SleepWord = GenerateSleepWord();

        _player.Message("You start to rest...");
        _player.Message($"Enter the word: {SleepWord}");

        return FatigueResult.Success;
    }

    /// <summary>
    /// Attempts to complete sleeping with the entered word.
    /// </summary>
    public FatigueResult CompleteSleep(string enteredWord)
    {
        if (!IsSleeping)
            return FatigueResult.Fail("You are not sleeping.");

        if (!string.Equals(enteredWord, SleepWord, StringComparison.OrdinalIgnoreCase))
        {
            // Wrong word - generate new one
            SleepWord = GenerateSleepWord();
            _player.Message($"Incorrect! Try again: {SleepWord}");
            return FatigueResult.Fail("Incorrect word.");
        }

        // Success - reduce fatigue
        ReduceFatigue();

        IsSleeping = false;
        SleepWord = null;

        _player.Message("You wake up feeling refreshed!");
        return FatigueResult.Success;
    }

    /// <summary>
    /// Cancels sleeping.
    /// </summary>
    public void CancelSleep()
    {
        IsSleeping = false;
        SleepWord = null;
    }

    private void ReduceFatigue()
    {
        // Sleeping removes all fatigue
        Current = 0;
    }

    /// <summary>
    /// Reduces fatigue by a specific amount (e.g., from items).
    /// </summary>
    public void ReduceFatigue(int amount)
    {
        Current = Math.Max(0, Current - amount);
    }

    /// <summary>
    /// Sets fatigue directly (for loading).
    /// </summary>
    public void SetFatigue(int value)
    {
        Current = Math.Clamp(value, 0, MaxFatigue);
    }

    private static string GenerateSleepWord()
    {
        // Generate a simple word to type (RSC-style CAPTCHA)
        var words = new[]
        {
            "apple", "bread", "chair", "dance", "eagle",
            "flame", "grape", "honey", "ivory", "joker",
            "knife", "lemon", "mouse", "noble", "ocean",
            "piano", "queen", "river", "storm", "tiger",
            "umbra", "viper", "water", "xenon", "youth", "zebra"
        };

        return words[Random.Shared.Next(words.Length)];
    }
}

/// <summary>
/// Result of a fatigue operation.
/// </summary>
public readonly record struct FatigueResult(bool Success, string? Message = null)
{
    public static FatigueResult Fail(string message) => new(false, message);
    public static readonly FatigueResult Success = new(true);
}

/// <summary>
/// Sleeping bag item handler.
/// </summary>
public static class SleepingBagHandler
{
    private const int SleepingBagId = 1263;

    /// <summary>
    /// Uses a sleeping bag.
    /// </summary>
    public static FatigueResult UseSleepingBag(Player player)
    {
        if (!player.Inventory.HasItem(SleepingBagId))
        {
            return FatigueResult.Fail("You don't have a sleeping bag.");
        }

        return player.Fatigue.StartSleeping(isBed: false);
    }
}

/// <summary>
/// Extension to integrate fatigue with skill XP.
/// </summary>
public static class FatigueSkillExtensions
{
    /// <summary>
    /// Adds experience with fatigue consideration.
    /// </summary>
    public static int AddExperienceWithFatigue(this PlayerSkills skills, Skill skill, int amount, PlayerFatigue fatigue)
    {
        if (!fatigue.CanGainXp())
        {
            return 0; // No XP gained due to fatigue
        }

        var actualXp = skills.AddExperience(skill, amount);

        if (actualXp > 0)
        {
            fatigue.AddFatigue(actualXp);
        }

        return actualXp;
    }
}
