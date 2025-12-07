namespace OpenRSC.Server.Skills;

/// <summary>
/// Enumeration of all skills in the game.
/// </summary>
public enum Skill
{
    Attack = 0,
    Defense = 1,
    Strength = 2,
    Hits = 3,
    Ranged = 4,
    Prayer = 5,
    Magic = 6,
    Cooking = 7,
    Woodcutting = 8,
    Fletching = 9,
    Fishing = 10,
    Firemaking = 11,
    Crafting = 12,
    Smithing = 13,
    Mining = 14,
    Herblaw = 15,
    Agility = 16,
    Thieving = 17
}

/// <summary>
/// Extension methods for skill calculations.
/// </summary>
public static class SkillExtensions
{
    /// <summary>
    /// Experience table for levels 1-99.
    /// </summary>
    private static readonly int[] ExperienceTable = GenerateExperienceTable();

    private static int[] GenerateExperienceTable()
    {
        var table = new int[100];
        var total = 0;

        for (var level = 1; level < 100; level++)
        {
            table[level] = total;
            var diff = (int)(level + 300 * Math.Pow(2, level / 7.0));
            total += diff / 4;
        }

        return table;
    }

    /// <summary>
    /// Gets the level for a given experience amount.
    /// </summary>
    public static int ExperienceToLevel(int experience)
    {
        for (var level = 98; level >= 1; level--)
        {
            if (experience >= ExperienceTable[level])
                return level;
        }
        return 1;
    }

    /// <summary>
    /// Gets the experience required for a given level.
    /// </summary>
    public static int LevelToExperience(int level)
    {
        if (level < 1) return 0;
        if (level > 99) level = 99;
        return ExperienceTable[level];
    }

    /// <summary>
    /// Gets the experience remaining until next level.
    /// </summary>
    public static int ExperienceToNextLevel(int currentExperience)
    {
        var currentLevel = ExperienceToLevel(currentExperience);
        if (currentLevel >= 99) return 0;

        return ExperienceTable[currentLevel + 1] - currentExperience;
    }

    /// <summary>
    /// Checks if the skill is a combat skill.
    /// </summary>
    public static bool IsCombatSkill(this Skill skill) => skill switch
    {
        Skill.Attack or Skill.Defense or Skill.Strength or
        Skill.Hits or Skill.Ranged or Skill.Prayer or Skill.Magic => true,
        _ => false
    };

    /// <summary>
    /// Gets the display name for a skill.
    /// </summary>
    public static string GetDisplayName(this Skill skill) => skill switch
    {
        Skill.Hits => "Hitpoints",
        Skill.Woodcutting => "Woodcut",
        Skill.Herblaw => "Herblore",
        _ => skill.ToString()
    };
}
