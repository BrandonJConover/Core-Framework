using FluentAssertions;
using OpenRSC.Server.Magic;
using Xunit;

namespace OpenRSC.Server.Tests;

public class MagicTests
{
    [Fact]
    public void SpellDefinition_WindStrike_HasCorrectProperties()
    {
        var spell = SpellDefinition.All[0];

        spell.Name.Should().Be("Wind Strike");
        spell.RequiredLevel.Should().Be(1);
        spell.Type.Should().Be(SpellType.Combat);
        spell.BaseDamage.Should().Be(2);
    }

    [Fact]
    public void SpellDefinition_VarrockTeleport_HasDestination()
    {
        var spell = SpellDefinition.All[12];

        spell.Name.Should().Be("Varrock Teleport");
        spell.Type.Should().Be(SpellType.Teleport);
        spell.TeleportDestination.Should().NotBeNull();
        spell.TeleportDestination!.Value.X.Should().Be(122);
    }

    [Fact]
    public void SpellDefinition_AllSpells_HaveRunes()
    {
        foreach (var spell in SpellDefinition.All.Values)
        {
            spell.Runes.Should().NotBeEmpty($"{spell.Name} should have rune requirements");
        }
    }

    [Fact]
    public void SpellDefinition_CombatSpells_HaveDamage()
    {
        var combatSpells = SpellDefinition.All.Values
            .Where(s => s.Type == SpellType.Combat);

        foreach (var spell in combatSpells)
        {
            spell.BaseDamage.Should().BePositive($"{spell.Name} should have base damage");
        }
    }

    [Fact]
    public void SpellDefinition_TeleportSpells_HaveDestinations()
    {
        var teleportSpells = SpellDefinition.All.Values
            .Where(s => s.Type == SpellType.Teleport);

        foreach (var spell in teleportSpells)
        {
            spell.TeleportDestination.Should().NotBeNull($"{spell.Name} should have destination");
        }
    }

    [Fact]
    public void SpellDefinition_HigherSpells_RequireHigherLevels()
    {
        var combatSpells = SpellDefinition.All.Values
            .Where(s => s.Type == SpellType.Combat)
            .OrderBy(s => s.Id)
            .ToList();

        for (var i = 1; i < combatSpells.Count; i++)
        {
            combatSpells[i].RequiredLevel.Should()
                .BeGreaterOrEqualTo(combatSpells[i - 1].RequiredLevel);
        }
    }

    [Fact]
    public void RuneType_HasCorrectItemIds()
    {
        // Verify rune types map to correct item IDs
        ((int)RuneType.Air).Should().Be(33);
        ((int)RuneType.Fire).Should().Be(31);
        ((int)RuneType.Water).Should().Be(32);
        ((int)RuneType.Earth).Should().Be(34);
    }
}
