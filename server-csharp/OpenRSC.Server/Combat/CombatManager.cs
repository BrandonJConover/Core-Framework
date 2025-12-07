using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Events;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Combat;

/// <summary>
/// Manages combat encounters between entities.
/// </summary>
public sealed class CombatManager
{
    private readonly ILogger<CombatManager> _logger;
    private readonly EventManager _eventManager;
    private readonly Dictionary<Guid, CombatEncounter> _activeEncounters = new();

    public CombatManager(ILogger<CombatManager> logger, EventManager eventManager)
    {
        _logger = logger;
        _eventManager = eventManager;
    }

    /// <summary>
    /// Initiates combat between an attacker and defender.
    /// </summary>
    public CombatEncounter? StartCombat(Mob attacker, Mob defender)
    {
        // Validate combat can start
        if (attacker.InCombat || defender.InCombat)
        {
            _logger.LogDebug("Combat start failed: one participant already in combat");
            return null;
        }

        if (attacker.IsRemoved || defender.IsRemoved)
        {
            return null;
        }

        // Create encounter
        var encounter = new CombatEncounter(attacker, defender, _eventManager);

        // Set combat state
        attacker.SetCombat(defender);
        defender.SetCombat(attacker);

        _activeEncounters[encounter.Id] = encounter;

        // Start combat ticks
        encounter.Start();

        _logger.LogDebug("Combat started: {Attacker} vs {Defender}",
            GetMobName(attacker), GetMobName(defender));

        return encounter;
    }

    /// <summary>
    /// Ends a combat encounter.
    /// </summary>
    public void EndCombat(CombatEncounter encounter, CombatEndReason reason)
    {
        if (!_activeEncounters.Remove(encounter.Id))
            return;

        encounter.Stop();

        encounter.Attacker.EndCombat();
        encounter.Defender.EndCombat();

        _logger.LogDebug("Combat ended: {Reason}", reason);

        // Handle death if applicable
        if (reason == CombatEndReason.DefenderDied)
        {
            HandleDeath(encounter.Defender, encounter.Attacker);
        }
        else if (reason == CombatEndReason.AttackerDied)
        {
            HandleDeath(encounter.Attacker, encounter.Defender);
        }
    }

    /// <summary>
    /// Handles entity death.
    /// </summary>
    private void HandleDeath(Mob victim, Mob killer)
    {
        if (victim is Player player)
        {
            HandlePlayerDeath(player, killer);
        }
        else if (victim is Npc npc)
        {
            HandleNpcDeath(npc, killer);
        }
    }

    private void HandlePlayerDeath(Player player, Mob killer)
    {
        _logger.LogInformation("Player {Username} died", player.Username);

        // Reset combat stats
        player.Skills.Restore(Skill.Hits);

        // Teleport to respawn
        // TODO: Implement respawn location and item drop logic

        player.Message("Oh dear, you are dead!");
    }

    private void HandleNpcDeath(Npc npc, Mob killer)
    {
        npc.Remove();

        // TODO: Drop loot, respawn timer

        if (killer is Player player)
        {
            _logger.LogDebug("NPC {NpcId} killed by {Player}", npc.Id, player.Username);
        }
    }

    private static string GetMobName(Mob mob) => mob switch
    {
        Player p => p.Username,
        Npc n => $"NPC({n.Id})",
        _ => "Unknown"
    };
}

/// <summary>
/// Represents an active combat encounter.
/// </summary>
public sealed class CombatEncounter
{
    private readonly EventManager _eventManager;
    private Guid? _combatEventId;
    private int _round;

    public Guid Id { get; } = Guid.NewGuid();
    public Mob Attacker { get; }
    public Mob Defender { get; }
    public CombatStyle AttackerStyle { get; set; } = CombatStyle.Controlled;
    public DateTime StartTime { get; } = DateTime.UtcNow;
    public bool IsActive { get; private set; }

    public CombatEncounter(Mob attacker, Mob defender, EventManager eventManager)
    {
        Attacker = attacker;
        Defender = defender;
        _eventManager = eventManager;
    }

    /// <summary>
    /// Starts the combat tick loop.
    /// </summary>
    public void Start()
    {
        IsActive = true;
        _round = 0;

        // Combat ticks every 3 game ticks (1920ms at 640ms/tick)
        _combatEventId = _eventManager.SubmitRepeating(3, ProcessCombatRound);
    }

    /// <summary>
    /// Stops the combat.
    /// </summary>
    public void Stop()
    {
        IsActive = false;
        if (_combatEventId.HasValue)
        {
            _eventManager.Cancel(_combatEventId.Value);
        }
    }

    /// <summary>
    /// Processes a single combat round.
    /// </summary>
    private bool ProcessCombatRound()
    {
        if (!IsActive) return false;

        _round++;

        // Check if either participant is dead or removed
        if (Attacker.IsRemoved || Defender.IsRemoved)
        {
            return false;
        }

        // Alternate who attacks (attacker on odd rounds, defender on even)
        var (currentAttacker, currentDefender) = _round % 2 == 1
            ? (Attacker, Defender)
            : (Defender, Attacker);

        // Calculate and apply hit
        if (currentAttacker is Player playerAttacker)
        {
            var hit = CombatFormulas.CalculateMeleeHit(playerAttacker, currentDefender, AttackerStyle);
            ApplyHit(currentDefender, hit, playerAttacker);
        }
        else
        {
            // NPC attacking - simplified
            var damage = Random.Shared.Next(0, 5);
            var hit = new HitResult(damage, DamageType.Melee);
            ApplyHit(currentDefender, hit, null);
        }

        // Check for death
        var defenderHp = currentDefender is Player p
            ? p.Skills.GetCurrentLevel(Skill.Hits)
            : currentDefender.CurrentHitpoints;

        if (defenderHp <= 0)
        {
            return false; // End combat
        }

        return true; // Continue fighting
    }

    /// <summary>
    /// Applies a hit to a defender.
    /// </summary>
    private void ApplyHit(Mob defender, HitResult hit, Player? attacker)
    {
        if (!hit.IsHit) return;

        if (defender is Player player)
        {
            player.Skills.Drain(Skill.Hits, hit.Damage);
            player.Message($"You have been hit for {hit.Damage} damage.");
        }
        else
        {
            defender.TakeDamage(hit.Damage);
        }

        // Award combat XP to attacker
        if (attacker != null)
        {
            var xpGains = CombatFormulas.CalculateCombatExperience(hit.Damage, AttackerStyle, hit.Type);
            foreach (var (skill, amount) in xpGains)
            {
                attacker.Skills.AddExperience(skill, amount);
            }
        }
    }
}

/// <summary>
/// Reasons for combat ending.
/// </summary>
public enum CombatEndReason
{
    AttackerFled,
    DefenderFled,
    AttackerDied,
    DefenderDied,
    Timeout,
    Interrupted
}
