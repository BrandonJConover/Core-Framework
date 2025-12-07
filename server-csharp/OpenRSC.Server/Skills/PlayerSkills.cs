using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Skills;

/// <summary>
/// Manages player skill levels and experience.
/// </summary>
public sealed class PlayerSkills
{
    private readonly Player _player;
    private const int SkillCount = 19;
    private readonly int[] _currentLevels = new int[SkillCount];
    private readonly int[] _maxLevels = new int[SkillCount];
    private readonly int[] _experience = new int[SkillCount];

    /// <summary>
    /// Event raised when experience is gained.
    /// </summary>
    public event Action<Skill, int, int>? ExperienceGained;

    /// <summary>
    /// Event raised when a level is gained.
    /// </summary>
    public event Action<Skill, int>? LevelGained;

    public PlayerSkills(Player player)
    {
        _player = player;

        // Initialize with default levels
        for (var i = 0; i < SkillCount; i++)
        {
            _currentLevels[i] = 1;
            _maxLevels[i] = 1;
            _experience[i] = 0;
        }

        // Hitpoints starts at 10
        _currentLevels[(int)Skill.Hits] = 10;
        _maxLevels[(int)Skill.Hits] = 10;
        _experience[(int)Skill.Hits] = SkillExtensions.LevelToExperience(10);
    }

    /// <summary>
    /// Gets the current (boosted/drained) level for a skill.
    /// </summary>
    public int GetCurrentLevel(Skill skill) => _currentLevels[(int)skill];

    /// <summary>
    /// Gets the maximum (base) level for a skill.
    /// </summary>
    public int GetMaxLevel(Skill skill) => _maxLevels[(int)skill];

    /// <summary>
    /// Gets the experience for a skill.
    /// </summary>
    public int GetExperience(Skill skill) => _experience[(int)skill];

    /// <summary>
    /// Gets all current levels.
    /// </summary>
    public int[] GetCurrentLevels() => _currentLevels.ToArray();

    /// <summary>
    /// Gets all max levels.
    /// </summary>
    public int[] GetMaxLevels() => _maxLevels.ToArray();

    /// <summary>
    /// Gets all experience values.
    /// </summary>
    public int[] GetExperience() => _experience.ToArray();

    /// <summary>
    /// Adds experience to a skill.
    /// </summary>
    /// <returns>The amount of experience actually added (may be capped)</returns>
    public int AddExperience(Skill skill, int amount, double multiplier = 1.0)
    {
        if (amount <= 0) return 0;

        var skillIndex = (int)skill;
        var actualAmount = (int)(amount * multiplier);
        var oldExp = _experience[skillIndex];
        var oldLevel = _maxLevels[skillIndex];

        // Cap at max experience (around 200M for level 99)
        const int maxExperience = 200_000_000;
        _experience[skillIndex] = Math.Min(maxExperience, oldExp + actualAmount);

        var newLevel = SkillExtensions.ExperienceToLevel(_experience[skillIndex]);

        // Check for level up
        if (newLevel > oldLevel)
        {
            _maxLevels[skillIndex] = newLevel;
            _currentLevels[skillIndex] = newLevel;

            for (var level = oldLevel + 1; level <= newLevel; level++)
            {
                LevelGained?.Invoke(skill, level);
                _player.Message($"Congratulations! You advanced a {skill.GetDisplayName()} level! You are now level {level}.");
            }

            // Update combat level if it's a combat skill
            if (skill.IsCombatSkill())
            {
                UpdateCombatLevel();
            }
        }

        ExperienceGained?.Invoke(skill, actualAmount, _experience[skillIndex]);

        return actualAmount;
    }

    /// <summary>
    /// Sets the current level (for boosts/drains).
    /// </summary>
    public void SetCurrentLevel(Skill skill, int level)
    {
        _currentLevels[(int)skill] = Math.Max(0, level);
    }

    /// <summary>
    /// Sets both the level and experience for a skill directly.
    /// Used primarily for testing and character loading.
    /// </summary>
    public void SetLevel(Skill skill, int level, int experience)
    {
        var index = (int)skill;
        _maxLevels[index] = Math.Clamp(level, 1, 99);
        _currentLevels[index] = _maxLevels[index];
        _experience[index] = experience;

        if (skill.IsCombatSkill())
        {
            UpdateCombatLevel();
        }
    }

    /// <summary>
    /// Boosts a skill by a flat amount.
    /// </summary>
    public void Boost(Skill skill, int amount)
    {
        var index = (int)skill;
        _currentLevels[index] = Math.Min(_maxLevels[index] + amount, _currentLevels[index] + amount);
    }

    /// <summary>
    /// Boosts a skill by a flat amount (alias for Boost).
    /// </summary>
    public void BoostLevel(Skill skill, int amount) => Boost(skill, amount);

    /// <summary>
    /// Drains a skill by a flat amount.
    /// </summary>
    public void Drain(Skill skill, int amount)
    {
        var index = (int)skill;
        _currentLevels[index] = Math.Max(0, _currentLevels[index] - amount);
    }

    /// <summary>
    /// Drains a skill by a flat amount (alias for Drain).
    /// </summary>
    public void DrainLevel(Skill skill, int amount) => Drain(skill, amount);

    /// <summary>
    /// Restores a skill to its max level.
    /// </summary>
    public void Restore(Skill skill)
    {
        _currentLevels[(int)skill] = _maxLevels[(int)skill];
    }

    /// <summary>
    /// Restores a skill to its max level (alias for Restore).
    /// </summary>
    public void RestoreToMax(Skill skill) => Restore(skill);

    /// <summary>
    /// Restores all skills to their max levels.
    /// </summary>
    public void RestoreAll()
    {
        for (var i = 0; i < SkillCount; i++)
        {
            _currentLevels[i] = _maxLevels[i];
        }
    }

    /// <summary>
    /// Calculates and updates the player's combat level.
    /// </summary>
    public void UpdateCombatLevel()
    {
        var attack = _maxLevels[(int)Skill.Attack];
        var defense = _maxLevels[(int)Skill.Defense];
        var strength = _maxLevels[(int)Skill.Strength];
        var hits = _maxLevels[(int)Skill.Hits];
        var ranged = _maxLevels[(int)Skill.Ranged];
        var prayer = _maxLevels[(int)Skill.Prayer];
        var magic = _maxLevels[(int)Skill.Magic];

        // RSC combat formula
        var melee = attack + strength;
        var range = ranged * 1.5;
        var mage = magic * 1.5;

        var highest = Math.Max(melee, Math.Max(range, mage));

        var combatLevel = (int)((defense + hits + prayer / 8.0 + highest / 4.0) / 4.0);

        // Minimum combat level is 3
        _player.SetCombatLevel(Math.Max(3, combatLevel));
    }

    /// <summary>
    /// Gets the total level (sum of all max levels).
    /// </summary>
    public int GetTotalLevel()
    {
        var total = 0;
        for (var i = 0; i < SkillCount; i++)
        {
            total += _maxLevels[i];
        }
        return total;
    }

    /// <summary>
    /// Total level property for convenience.
    /// </summary>
    public int TotalLevel => GetTotalLevel();

    /// <summary>
    /// Gets the total experience across all skills.
    /// </summary>
    public long TotalExperience
    {
        get
        {
            long total = 0;
            for (var i = 0; i < SkillCount; i++)
            {
                total += _experience[i];
            }
            return total;
        }
    }

    /// <summary>
    /// Loads skill data from saved values.
    /// </summary>
    public void Load(int[] currentLevels, int[] maxLevels, int[] experience)
    {
        Array.Copy(currentLevels, _currentLevels, Math.Min(currentLevels.Length, SkillCount));
        Array.Copy(maxLevels, _maxLevels, Math.Min(maxLevels.Length, SkillCount));
        Array.Copy(experience, _experience, Math.Min(experience.Length, SkillCount));

        UpdateCombatLevel();
    }
}
