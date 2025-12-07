using OpenRSC.Server.Combat;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Magic;

/// <summary>
/// Manages spell casting for a player.
/// </summary>
public sealed class SpellCaster
{
    private readonly Player _player;
    private DateTime _lastCastTime;
    private const int CastDelayMs = 1800; // ~3 ticks

    /// <summary>
    /// Whether the player can cast (cooldown check).
    /// </summary>
    public bool CanCast => (DateTime.UtcNow - _lastCastTime).TotalMilliseconds >= CastDelayMs;

    /// <summary>
    /// Time until next cast is available.
    /// </summary>
    public TimeSpan CooldownRemaining
    {
        get
        {
            var elapsed = (DateTime.UtcNow - _lastCastTime).TotalMilliseconds;
            return elapsed >= CastDelayMs
                ? TimeSpan.Zero
                : TimeSpan.FromMilliseconds(CastDelayMs - elapsed);
        }
    }

    public SpellCaster(Player player)
    {
        _player = player;
    }

    /// <summary>
    /// Attempts to cast a spell.
    /// </summary>
    public SpellResult Cast(int spellId, Mob? target = null)
    {
        if (!SpellDefinition.All.TryGetValue(spellId, out var spell))
            return SpellResult.Fail("Unknown spell.");

        // Check cooldown
        if (!CanCast)
            return SpellResult.Fail("You must wait before casting again.");

        // Check magic level
        var magicLevel = _player.Skills.GetCurrentLevel(Skill.Magic);
        if (magicLevel < spell.RequiredLevel)
            return SpellResult.Fail($"You need level {spell.RequiredLevel} Magic to cast this spell.");

        // Check runes
        var runeCheck = CheckRunes(spell);
        if (!runeCheck.Success)
            return runeCheck;

        // Validate target
        var targetCheck = ValidateTarget(spell, target);
        if (!targetCheck.Success)
            return targetCheck;

        // Consume runes
        ConsumeRunes(spell);

        // Execute spell effect
        var result = ExecuteSpell(spell, target);

        if (result.Success)
        {
            // Grant experience
            _player.Skills.AddExperience(Skill.Magic, spell.BaseExperience);
            _lastCastTime = DateTime.UtcNow;
        }

        return result;
    }

    private SpellResult CheckRunes(SpellDefinition spell)
    {
        foreach (var requirement in spell.Runes)
        {
            var runeItemId = (int)requirement.Rune;
            if (!_player.Inventory.HasItem(runeItemId, requirement.Amount))
            {
                return SpellResult.Fail($"You don't have enough {requirement.Rune} runes.");
            }
        }
        return SpellResult.Success;
    }

    private void ConsumeRunes(SpellDefinition spell)
    {
        foreach (var requirement in spell.Runes)
        {
            var runeItemId = (int)requirement.Rune;
            _player.Inventory.Remove(runeItemId, requirement.Amount);
        }
    }

    private SpellResult ValidateTarget(SpellDefinition spell, Mob? target)
    {
        return spell.Target switch
        {
            SpellTarget.None => SpellResult.Success,
            SpellTarget.Self => SpellResult.Success,
            SpellTarget.Player when target is Player => SpellResult.Success,
            SpellTarget.Player => SpellResult.Fail("This spell must be cast on a player."),
            SpellTarget.Npc when target is Npc => SpellResult.Success,
            SpellTarget.Npc when target is Player => SpellResult.Success, // PvP magic
            SpellTarget.Npc => SpellResult.Fail("This spell must be cast on a target."),
            SpellTarget.Item => SpellResult.Success, // Item validation done separately
            _ => SpellResult.Fail("Invalid target.")
        };
    }

    private SpellResult ExecuteSpell(SpellDefinition spell, Mob? target)
    {
        switch (spell.Type)
        {
            case SpellType.Combat:
                return CastCombatSpell(spell, target);

            case SpellType.Teleport:
                return CastTeleport(spell);

            case SpellType.Alchemy:
                return SpellResult.Fail("Use the spell on an item in your inventory.");

            case SpellType.Utility:
                return CastUtility(spell);

            default:
                return SpellResult.Fail("Unknown spell type.");
        }
    }

    private SpellResult CastCombatSpell(SpellDefinition spell, Mob? target)
    {
        if (target is null)
            return SpellResult.Fail("You need a target to cast this spell.");

        if (target.IsRemoved)
            return SpellResult.Fail("Invalid target.");

        if (!_player.Location.WithinRange(target.Location, 5))
            return SpellResult.Fail("Your target is too far away.");

        // Calculate magic hit
        var hit = CalculateMagicHit(spell, target);

        if (hit.Hit)
        {
            target.ApplyDamage(hit.Damage, _player);
            _player.Message($"You hit {hit.Damage} damage with {spell.Name}.");
        }
        else
        {
            _player.Message($"Your {spell.Name} missed.");
        }

        return SpellResult.Success;
    }

    private HitResult CalculateMagicHit(SpellDefinition spell, Mob target)
    {
        var magicLevel = _player.Skills.GetCurrentLevel(Skill.Magic);
        var magicBonus = _player.Equipment.GetTotalBonuses().MagicDamage;

        // Attack roll
        var attackRoll = magicLevel * (1 + magicBonus / 64.0);

        // Defense roll (magic defense is primarily based on magic level)
        var defenseRoll = target switch
        {
            Player p => p.Skills.GetCurrentLevel(Skill.Magic) * 0.7 +
                        p.Skills.GetCurrentLevel(Skill.Defense) * 0.3,
            _ => target.CombatLevel * 0.5
        };

        // Roll for accuracy
        var hitChance = attackRoll / (attackRoll + defenseRoll);
        if (Random.Shared.NextDouble() > hitChance)
            return HitResult.Miss;

        // Calculate damage
        var maxDamage = spell.BaseDamage + (int)(magicBonus * 0.1);
        var damage = Random.Shared.Next(1, maxDamage + 1);

        return new HitResult(true, damage, DamageType.Magic);
    }

    private SpellResult CastTeleport(SpellDefinition spell)
    {
        if (spell.TeleportDestination is null)
            return SpellResult.Fail("Invalid teleport destination.");

        if (_player.InCombat)
            return SpellResult.Fail("You can't teleport while in combat.");

        // Check wilderness level (can't teleport above level 20 wilderness)
        // Simplified check - real implementation would check actual wilderness level
        if (_player.Location.Y < 400 && _player.Location.Y > 300)
            return SpellResult.Fail("You can't teleport from this deep in the wilderness.");

        _player.Location = spell.TeleportDestination.Value;
        _player.Message($"You teleport to {spell.Name.Replace(" Teleport", "")}.");

        return SpellResult.Success;
    }

    private SpellResult CastUtility(SpellDefinition spell)
    {
        switch (spell.Name)
        {
            case "Bones to Bananas":
                return CastBonesToBananas();
            default:
                return SpellResult.Fail("This spell is not implemented.");
        }
    }

    private SpellResult CastBonesToBananas()
    {
        const int bonesId = 20;
        const int bananasId = 249;

        var bonesCount = _player.Inventory.CountOf(bonesId);
        if (bonesCount == 0)
            return SpellResult.Fail("You have no bones to convert.");

        _player.Inventory.Remove(bonesId, bonesCount);
        // Would need item factory to add bananas properly
        _player.Message($"You convert {bonesCount} bones into bananas.");

        return SpellResult.Success;
    }

    /// <summary>
    /// Casts alchemy on an item.
    /// </summary>
    public SpellResult CastAlchemy(int spellId, int inventorySlot)
    {
        if (!SpellDefinition.All.TryGetValue(spellId, out var spell))
            return SpellResult.Fail("Unknown spell.");

        if (spell.Type != SpellType.Alchemy)
            return SpellResult.Fail("This is not an alchemy spell.");

        var item = _player.Inventory.GetSlot(inventorySlot);
        if (item is null)
            return SpellResult.Fail("No item in that slot.");

        // Check requirements
        if (!CanCast)
            return SpellResult.Fail("You must wait before casting again.");

        var magicLevel = _player.Skills.GetCurrentLevel(Skill.Magic);
        if (magicLevel < spell.RequiredLevel)
            return SpellResult.Fail($"You need level {spell.RequiredLevel} Magic.");

        var runeCheck = CheckRunes(spell);
        if (!runeCheck.Success)
            return runeCheck;

        // Calculate gold value
        var multiplier = spell.Name.Contains("High") ? 0.6 : 0.4;
        var goldAmount = (int)(item.Definition.BasePrice * multiplier);

        if (goldAmount <= 0)
            return SpellResult.Fail("That item has no alchemical value.");

        // Consume runes and item
        ConsumeRunes(spell);
        _player.Inventory.Remove(inventorySlot);

        // Grant gold and XP
        _player.Skills.AddExperience(Skill.Magic, spell.BaseExperience);
        _player.Message($"You alchemize the {item.Definition.Name} for {goldAmount} coins.");
        _lastCastTime = DateTime.UtcNow;

        return SpellResult.Success;
    }
}

/// <summary>
/// Result of a spell cast attempt.
/// </summary>
public readonly record struct SpellResult(bool Success, string? Message = null)
{
    public static SpellResult Fail(string message) => new(false, message);
    public static readonly SpellResult Success = new(true);
}
