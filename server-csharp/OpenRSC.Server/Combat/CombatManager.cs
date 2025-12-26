using Microsoft.Extensions.Logging;
using OpenRSC.Server.Drops;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Events;
using OpenRSC.Server.Items;
using OpenRSC.Server.Models;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Combat;

/// <summary>
/// Manages combat encounters between entities.
/// </summary>
public sealed class CombatManager
{
    private readonly ILogger<CombatManager> _logger;
    private readonly EventManager _eventManager;
    private readonly DropService? _dropService;
    private readonly Dictionary<Guid, CombatEncounter> _activeEncounters = new();

    public CombatManager(
        ILogger<CombatManager> logger,
        EventManager eventManager,
        DropService? dropService = null)
    {
        _logger = logger;
        _eventManager = eventManager;
        _dropService = dropService;
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
        _logger.LogInformation("Player {Username} died to {Killer}", player.Username, GetMobName(killer));

        // Drop items on death
        var droppedItems = DropItemsOnDeath(player, killer);

        // Remove skull on death
        player.ClearSkull();

        // Send death notification
        _ = player.ActionSender?.SendDeathAsync();

        // Reset hitpoints
        player.Skills.Restore(Skill.Hits);

        // Teleport to respawn location
        var respawnLocation = GetRespawnLocation(player);
        player.MoveTo(respawnLocation);
        _ = player.ActionSender?.SendTeleportAsync();

        player.Message("Oh dear, you are dead!");

        // Log items dropped
        if (droppedItems.Count > 0)
        {
            _logger.LogDebug("Player {Username} dropped {Count} items on death",
                player.Username, droppedItems.Count);
        }

        // Award kill to player killer
        if (killer is Player killerPlayer)
        {
            killerPlayer.Message($"You have defeated {player.Username}!");
        }
    }

    /// <summary>
    /// Drops items on player death, keeping the 3 most valuable.
    /// </summary>
    private List<Item> DropItemsOnDeath(Player player, Mob killer)
    {
        var droppedItems = new List<Item>();
        var allItems = new List<Item>();

        // Collect all inventory items
        allItems.AddRange(player.Inventory.GetItems());

        // Collect all equipped items
        foreach (var (slot, item) in player.Equipment.GetEquipped())
        {
            allItems.Add(item);
        }

        if (allItems.Count == 0)
            return droppedItems;

        // Sort by value (highest first)
        allItems = allItems.OrderByDescending(i => i.Definition?.Value ?? 0).ToList();

        // Determine how many to keep (3 normally, 4 with Protect Item prayer)
        var keepCount = player.Prayers?.IsActive(Prayer.Prayer.ProtectItems) == true ? 4 : 3;

        // Items to keep (most valuable)
        var keptItems = allItems.Take(keepCount).ToList();

        // Items to drop
        var toDrop = allItems.Skip(keepCount).ToList();

        // Clear inventory and equipment
        player.Inventory.Clear();
        player.Equipment.ClearAll();

        // Re-add kept items to inventory
        foreach (var item in keptItems)
        {
            player.Inventory.Add(item);
        }

        // Drop remaining items at death location
        foreach (var item in toDrop)
        {
            droppedItems.Add(item);
            // Create ground item at player's location
            // The item is visible to the killer first
            var visibleTo = killer is Player p ? p : null;
            CreateGroundItem(player.Location, item, visibleTo);
        }

        // Update client
        _ = player.ActionSender?.SendInventoryAsync();

        return droppedItems;
    }

    /// <summary>
    /// Creates a ground item at the specified location.
    /// </summary>
    private void CreateGroundItem(Point location, Item item, Player? visibleTo)
    {
        // Ground items are created with visibility rules:
        // - First visible only to killer (if player)
        // - Then visible to everyone after ~60 seconds
        // - Despawn after ~180 seconds

        // This would integrate with the ground item manager
        _logger.LogDebug("Ground item created: {Item} at {Location}", item.Definition?.Name ?? "Unknown", location);
    }

    /// <summary>
    /// Gets the respawn location for a player.
    /// </summary>
    private static Point GetRespawnLocation(Player player)
    {
        // Default respawn in Lumbridge
        // Could be extended to support other respawn points
        return new Point(122, 647);
    }

    private void HandleNpcDeath(Npc npc, Mob killer)
    {
        _logger.LogInformation("NPC {NpcName} (ID: {NpcId}) killed by {Killer}",
            npc.Name, npc.NpcId, GetMobName(killer));

        var killerPlayer = killer as Player;

        // Generate and drop loot
        var drops = GenerateNpcDrops(npc);
        foreach (var item in drops)
        {
            CreateGroundItem(npc.Location, item, killerPlayer);

            if (killerPlayer is not null)
            {
                killerPlayer.Message($"Drop: {item.Definition?.Name ?? "Unknown"} x{item.Amount}");
            }
        }

        // Award combat experience for the kill
        if (killerPlayer is not null && npc.Definition is not null)
        {
            var killXp = CalculateNpcKillExperience(npc);
            killerPlayer.Skills.AddExperience(Skill.Hits, killXp);
            _logger.LogDebug("Player {Username} gained {Xp} hitpoints XP from killing {Npc}",
                killerPlayer.Username, killXp, npc.Name);
        }

        // Mark NPC as dead and start respawn timer
        npc.Die();

        // The NpcManager.ProcessRespawns() will handle actual respawning
        _logger.LogDebug("NPC {NpcName} will respawn in {Seconds} seconds",
            npc.Name, npc.Definition?.RespawnTime ?? 30);
    }

    /// <summary>
    /// Generates drops for an NPC.
    /// </summary>
    private IEnumerable<Item> GenerateNpcDrops(Npc npc)
    {
        if (_dropService is not null)
        {
            return _dropService.GenerateDrops(npc);
        }

        // Fallback: just bones
        return new List<Item>();
    }

    /// <summary>
    /// Calculates experience gained from killing an NPC.
    /// </summary>
    private static int CalculateNpcKillExperience(Npc npc)
    {
        // Experience based on NPC combat level and hitpoints
        var combatLevel = npc.CombatLevel;
        var hitpoints = npc.Definition?.Hitpoints ?? 10;

        // Formula: base XP + bonus for higher level NPCs
        return (hitpoints * 4) + (combatLevel * 2);
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
