using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Npc;

/// <summary>
/// Interface for NPC AI behaviors.
/// </summary>
public interface INpcBehavior
{
    /// <summary>
    /// Executes the behavior logic for one tick.
    /// </summary>
    void Execute(Entities.Npc npc);
}

/// <summary>
/// Basic passive NPC that just wanders around.
/// </summary>
public sealed class PassiveBehavior : INpcBehavior
{
    private const int WanderChance = 20; // 1 in 20 chance to move each tick

    public void Execute(Entities.Npc npc)
    {
        if (npc.InCombat || npc.IsDead)
            return;

        // Random chance to wander
        if (Random.Shared.Next(WanderChance) == 0)
        {
            npc.WalkRandom();
        }
    }
}

/// <summary>
/// Aggressive NPC that attacks nearby players.
/// </summary>
public sealed class AggressiveBehavior : INpcBehavior
{
    private readonly Func<Entities.Npc, IEnumerable<Player>> _playerFinder;
    private const int WanderChance = 10;

    public AggressiveBehavior(Func<Entities.Npc, IEnumerable<Player>> playerFinder)
    {
        _playerFinder = playerFinder;
    }

    public void Execute(Entities.Npc npc)
    {
        if (npc.InCombat || npc.IsDead)
            return;

        // Already has a target - chase them
        if (npc.AggroTarget is { } target && !target.IsRemoved && !target.InCombat)
        {
            if (npc.Location.WithinRange(target.Location, 1))
            {
                // In range - initiate combat (handled by combat manager)
                return;
            }

            npc.WalkTowards(target.Location);
            return;
        }

        // Find new target
        var players = _playerFinder(npc);
        var potentialTarget = players
            .Where(p => !p.InCombat && p.CombatLevel < npc.CombatLevel * 2)
            .Where(p => npc.Location.WithinRange(p.Location, npc.Definition.AggroRange))
            .OrderBy(p => npc.Location.DistanceTo(p.Location))
            .FirstOrDefault();

        if (potentialTarget is not null)
        {
            npc.AggroTarget = potentialTarget;
            return;
        }

        // No target - wander or return to spawn
        if (!npc.Location.WithinRange(npc.SpawnLocation, npc.Definition.RoamDistance))
        {
            npc.ReturnToSpawn();
        }
        else if (Random.Shared.Next(WanderChance) == 0)
        {
            npc.WalkRandom();
        }
    }
}

/// <summary>
/// Shopkeeper NPC that stays in place.
/// </summary>
public sealed class ShopkeeperBehavior : INpcBehavior
{
    public void Execute(Entities.Npc npc)
    {
        // Shopkeepers don't move or attack
        // They just stand there waiting for players to interact
    }
}

/// <summary>
/// Guard NPC that patrols between points.
/// </summary>
public sealed class PatrolBehavior : INpcBehavior
{
    private readonly Models.Point[] _waypoints;
    private int _currentWaypointIndex;
    private int _waitTicks;

    public PatrolBehavior(params Models.Point[] waypoints)
    {
        if (waypoints.Length < 2)
            throw new ArgumentException("Patrol requires at least 2 waypoints");
        _waypoints = waypoints;
    }

    public void Execute(Entities.Npc npc)
    {
        if (npc.InCombat || npc.IsDead)
            return;

        if (_waitTicks > 0)
        {
            _waitTicks--;
            return;
        }

        var target = _waypoints[_currentWaypointIndex];

        if (npc.Location == target)
        {
            // Reached waypoint - move to next
            _currentWaypointIndex = (_currentWaypointIndex + 1) % _waypoints.Length;
            _waitTicks = 3; // Wait a few ticks at each waypoint
            return;
        }

        npc.WalkTowards(target);
    }
}

/// <summary>
/// Retreating NPC that flees when low on health.
/// </summary>
public sealed class RetreatingBehavior : INpcBehavior
{
    private readonly INpcBehavior _normalBehavior;
    private readonly double _fleeThreshold;

    public RetreatingBehavior(INpcBehavior normalBehavior, double fleeThreshold = 0.2)
    {
        _normalBehavior = normalBehavior;
        _fleeThreshold = fleeThreshold;
    }

    public void Execute(Entities.Npc npc)
    {
        if (npc.IsDead)
            return;

        var healthPercent = (double)npc.CurrentHitpoints / npc.Definition.Hitpoints;

        if (healthPercent <= _fleeThreshold && npc.InCombat)
        {
            // Try to flee - walk away from combat opponent
            if (npc.CombatTarget is { } opponent)
            {
                var dx = npc.Location.X - opponent.Location.X;
                var dy = npc.Location.Y - opponent.Location.Y;

                var fleeX = npc.Location.X + Math.Sign(dx);
                var fleeY = npc.Location.Y + Math.Sign(dy);

                npc.WalkTowards(new Models.Point(fleeX, fleeY), 0);
            }
            return;
        }

        _normalBehavior.Execute(npc);
    }
}
