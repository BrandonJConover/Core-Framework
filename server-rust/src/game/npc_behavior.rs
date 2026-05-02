//! NPC behavior and AI processing for each game tick.
//!
//! Handles NPC state machines including idle wandering, aggression checks,
//! combat engagement, death, and respawning. Designed to be driven by the
//! game loop once per tick.

use super::entity::{EntityId, Position};
use super::npc::{NpcCombatState, NpcDef, NpcManager};
use rand::Rng;
use std::collections::HashMap;
use tracing::{debug, trace};

/// High-level behavioral state for an NPC.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NpcState {
    /// Standing still, waiting for the next wander interval.
    Idle,
    /// Actively wandering within spawn radius.
    Wandering,
    /// Engaged in melee combat with a target.
    InCombat { target_id: u64 },
    /// Dead, waiting for respawn timer.
    Dead { death_tick: u64 },
    /// Respawn timer elapsed, about to reappear.
    Respawning { respawn_at: u64 },
    /// Returning to spawn point after straying too far.
    ReturningToSpawn,
}

/// Per-NPC behavior data tracked alongside the core `Npc` struct.
#[derive(Debug)]
pub struct NpcBehavior {
    /// Current behavioral state.
    pub state: NpcState,
    /// Definition id — used to look up aggro flag, combat level, etc.
    pub def_id: u32,
    /// Spawn origin — used for return-to-spawn checks.
    pub spawn_position: Position,
    /// Maximum tiles from spawn before the NPC turns back.
    pub wander_radius: u32,
    /// How many ticks between wander steps while idle.
    pub wander_interval: u32,
    /// Tick on which the NPC last moved.
    pub last_move_tick: u64,
    /// Aggro scanning radius (tiles).
    pub aggro_radius: u32,
    /// Number of ticks the NPC must wait after death before respawning.
    pub respawn_delay: u32,
    /// Whether this NPC is aggressive.
    pub aggressive: bool,
    /// The NPC's combat level (cached from definition).
    pub combat_level: u32,
}

impl NpcBehavior {
    /// Build behavior data from a definition and spawn position.
    pub fn from_def(def: &NpcDef, spawn_position: Position) -> Self {
        Self {
            state: NpcState::Idle,
            def_id: def.id,
            spawn_position,
            wander_radius: def.wander_radius,
            wander_interval: 3,
            last_move_tick: 0,
            aggro_radius: if def.aggressive { 4 } else { 0 },
            respawn_delay: def.respawn_time,
            aggressive: def.aggressive,
            combat_level: def.combat_level,
        }
    }
}

/// Lightweight snapshot of a nearby player used for aggro checks.
/// The caller is responsible for populating this each tick.
#[derive(Debug, Clone)]
pub struct NearbyPlayer {
    pub entity_id: u64,
    pub position: Position,
    pub combat_level: u32,
    pub in_combat: bool,
}

/// Processes NPC behavior each game tick.
///
/// This sits as a companion to `NpcManager`: the manager owns the canonical
/// NPC data while `NpcBehaviorProcessor` owns the AI layer that drives it.
pub struct NpcBehaviorProcessor {
    /// Behavior data keyed by the same `EntityId` used in `NpcManager`.
    behaviors: HashMap<EntityId, NpcBehavior>,
}

impl NpcBehaviorProcessor {
    pub fn new() -> Self {
        Self {
            behaviors: HashMap::new(),
        }
    }

    /// Register behavior for a newly spawned NPC.
    pub fn register(&mut self, entity_id: EntityId, def: &NpcDef, spawn_pos: Position) {
        let behavior = NpcBehavior::from_def(def, spawn_pos);
        self.behaviors.insert(entity_id, behavior);
        debug!("Registered behavior for NPC {:?} (def {})", entity_id, def.id);
    }

    /// Remove behavior tracking when an NPC is permanently despawned.
    pub fn unregister(&mut self, entity_id: EntityId) {
        self.behaviors.remove(&entity_id);
    }

    /// Get the current state of an NPC.
    pub fn state(&self, entity_id: EntityId) -> Option<NpcState> {
        self.behaviors.get(&entity_id).map(|b| b.state)
    }

    /// Main per-tick entry point.
    ///
    /// `nearby_players` maps each NPC entity id to the list of players that
    /// are close enough to matter (within aggro/interaction range). The caller
    /// should build this from the world's spatial index or region data.
    pub fn process_tick(
        &mut self,
        npc_manager: &mut NpcManager,
        current_tick: u64,
        nearby_players: &HashMap<EntityId, Vec<NearbyPlayer>>,
    ) -> Vec<BehaviorEvent> {
        let mut events = Vec::new();
        let entity_ids: Vec<EntityId> = self.behaviors.keys().copied().collect();

        for entity_id in entity_ids {
            let Some(behavior) = self.behaviors.get_mut(&entity_id) else {
                continue;
            };
            let Some(npc) = npc_manager.get_mut(entity_id) else {
                continue;
            };

            let players = nearby_players.get(&entity_id);

            match behavior.state {
                NpcState::Idle | NpcState::Wandering => {
                    // Sync from NpcManager — if the combat system killed us
                    // externally, transition to Dead.
                    if npc.is_dead() {
                        if let NpcCombatState::Dead { death_tick } = npc.combat_state {
                            behavior.state = NpcState::Dead { death_tick };
                            events.push(BehaviorEvent::Died { entity_id });
                            continue;
                        }
                    }

                    // --- Aggro check (before wander so aggressive NPCs
                    //     prioritise attacking over strolling) ---
                    if behavior.aggressive {
                        if let Some(target) = pick_aggro_target(behavior, npc.position, players)
                        {
                            behavior.state = NpcState::InCombat {
                                target_id: target.entity_id,
                            };
                            npc.start_combat(target.entity_id, current_tick);
                            events.push(BehaviorEvent::Aggroed {
                                entity_id,
                                target_id: target.entity_id,
                            });
                            continue;
                        }
                    }

                    // --- Return to spawn if too far ---
                    let dist_to_spawn = chebyshev(npc.position, behavior.spawn_position);
                    if dist_to_spawn > behavior.wander_radius {
                        behavior.state = NpcState::ReturningToSpawn;
                        continue;
                    }

                    // --- Wander ---
                    if current_tick >= behavior.last_move_tick + behavior.wander_interval as u64 {
                        if try_wander(npc, behavior) {
                            behavior.last_move_tick = current_tick;
                            behavior.state = NpcState::Wandering;
                        } else {
                            behavior.state = NpcState::Idle;
                        }
                    }
                }

                NpcState::InCombat { target_id } => {
                    // Check if we died during combat.
                    if npc.is_dead() {
                        if let NpcCombatState::Dead { death_tick } = npc.combat_state {
                            behavior.state = NpcState::Dead { death_tick };
                            events.push(BehaviorEvent::Died { entity_id });
                            continue;
                        }
                    }

                    // Check if the target fled (no longer nearby or in combat with us).
                    let target_present = players
                        .map(|ps| ps.iter().any(|p| p.entity_id == target_id))
                        .unwrap_or(false);

                    if !target_present {
                        npc.end_combat();
                        behavior.state = NpcState::ReturningToSpawn;
                        events.push(BehaviorEvent::TargetLost {
                            entity_id,
                            target_id,
                        });
                    }
                    // Otherwise stay engaged — actual hit resolution is handled
                    // by the combat module.
                }

                NpcState::Dead { death_tick } => {
                    let respawn_at = death_tick + behavior.respawn_delay as u64;
                    if current_tick >= respawn_at {
                        behavior.state = NpcState::Respawning { respawn_at };
                    }
                }

                NpcState::Respawning { .. } => {
                    npc.respawn();
                    behavior.state = NpcState::Idle;
                    behavior.last_move_tick = current_tick;
                    events.push(BehaviorEvent::Respawned { entity_id });
                }

                NpcState::ReturningToSpawn => {
                    let moved = npc.move_towards(behavior.spawn_position);
                    behavior.last_move_tick = current_tick;

                    if !moved || npc.position == behavior.spawn_position {
                        // Arrived back at spawn.
                        behavior.state = NpcState::Idle;
                        trace!("NPC {:?} returned to spawn", entity_id);
                    }
                }
            }
        }

        events
    }

    /// Forcibly set an NPC into combat (e.g. player initiated the attack).
    pub fn enter_combat(&mut self, entity_id: EntityId, target_id: u64) {
        if let Some(behavior) = self.behaviors.get_mut(&entity_id) {
            behavior.state = NpcState::InCombat { target_id };
        }
    }

    /// Notify the behavior layer that combat ended (retreat, etc.).
    pub fn exit_combat(&mut self, entity_id: EntityId) {
        if let Some(behavior) = self.behaviors.get_mut(&entity_id) {
            behavior.state = NpcState::ReturningToSpawn;
        }
    }

    /// Number of tracked NPCs.
    pub fn count(&self) -> usize {
        self.behaviors.len()
    }
}

// ---------------------------------------------------------------------------
// Events emitted during tick processing
// ---------------------------------------------------------------------------

/// Events produced by tick processing so the game loop can react
/// (e.g. send combat initiation packets, play death animation).
#[derive(Debug, Clone)]
pub enum BehaviorEvent {
    /// An aggressive NPC targeted a player.
    Aggroed { entity_id: EntityId, target_id: u64 },
    /// NPC's combat target left the area.
    TargetLost { entity_id: EntityId, target_id: u64 },
    /// NPC died (transitioned to Dead state).
    Died { entity_id: EntityId },
    /// NPC respawned after death timer.
    Respawned { entity_id: EntityId },
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

/// Chebyshev (chessboard) distance — the metric RSC uses for interaction range.
fn chebyshev(a: Position, b: Position) -> u32 {
    let dx = (a.x - b.x).unsigned_abs();
    let dy = (a.y - b.y).unsigned_abs();
    dx.max(dy)
}

/// Pick the best aggro target from the nearby player list.
///
/// RSC rule: aggressive NPCs only auto-attack players whose combat level is
/// less than twice the NPC's combat level. Among eligible targets the closest
/// player is chosen.
fn pick_aggro_target(
    behavior: &NpcBehavior,
    npc_pos: Position,
    players: Option<&Vec<NearbyPlayer>>,
) -> Option<NearbyPlayer> {
    let players = players?;
    let threshold = behavior.combat_level * 2;

    players
        .iter()
        .filter(|p| !p.in_combat)
        .filter(|p| p.combat_level < threshold)
        .filter(|p| chebyshev(npc_pos, p.position) <= behavior.aggro_radius)
        .min_by_key(|p| chebyshev(npc_pos, p.position))
        .cloned()
}

/// Attempt a single random wander step, respecting spawn radius.
/// Returns `true` if the NPC actually moved.
fn try_wander(
    npc: &mut super::npc::Npc,
    behavior: &NpcBehavior,
) -> bool {
    let mut rng = rand::thread_rng();

    // 50 % chance to stand still — gives NPCs a natural idle cadence.
    if rng.gen_bool(0.5) {
        return false;
    }

    let dx: i32 = rng.gen_range(-1..=1);
    let dy: i32 = rng.gen_range(-1..=1);
    if dx == 0 && dy == 0 {
        return false;
    }

    let new_x = npc.position.x + dx;
    let new_y = npc.position.y + dy;

    // Stay within wander radius of spawn.
    let spawn_dx = (new_x - behavior.spawn_position.x).unsigned_abs();
    let spawn_dy = (new_y - behavior.spawn_position.y).unsigned_abs();
    if spawn_dx > behavior.wander_radius || spawn_dy > behavior.wander_radius {
        return false;
    }

    npc.position = Position::new(new_x, new_y);
    true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::entity::EntityId;
    use crate::game::npc::{NpcDef, NpcManager};

    fn make_manager_and_processor() -> (NpcManager, NpcBehaviorProcessor) {
        let manager = NpcManager::new();
        let processor = NpcBehaviorProcessor::new();
        (manager, processor)
    }

    #[test]
    fn test_idle_npc_wanders() {
        let (mut mgr, mut proc) = make_manager_and_processor();

        let def = NpcDef::new(1, "Man").with_combat(2, 7, 1, 1, 1);
        let spawn = Position::new(100, 100);
        let eid = mgr.spawn(1, spawn).unwrap();
        proc.register(eid, &def, spawn);

        // Run several ticks; NPC should stay within wander radius.
        let empty: HashMap<EntityId, Vec<NearbyPlayer>> = HashMap::new();
        for tick in 0..50 {
            proc.process_tick(&mut mgr, tick, &empty);
        }

        let npc = mgr.get(eid).unwrap();
        let dist = chebyshev(npc.position, spawn);
        assert!(
            dist <= def.wander_radius,
            "NPC wandered {} tiles from spawn (max {})",
            dist,
            def.wander_radius
        );
    }

    #[test]
    fn test_aggressive_npc_aggros() {
        let (mut mgr, mut proc) = make_manager_and_processor();

        let def = NpcDef::new(62, "Goblin")
            .with_combat(7, 15, 5, 5, 5)
            .aggressive();
        let spawn = Position::new(100, 100);
        let eid = mgr.spawn(62, spawn).unwrap();
        proc.register(eid, &def, spawn);

        let mut nearby = HashMap::new();
        nearby.insert(
            eid,
            vec![NearbyPlayer {
                entity_id: 999,
                position: Position::new(102, 100),
                combat_level: 5, // < 7 * 2 = 14
                in_combat: false,
            }],
        );

        let events = proc.process_tick(&mut mgr, 10, &nearby);

        assert!(
            events.iter().any(|e| matches!(e, BehaviorEvent::Aggroed { .. })),
            "Expected an Aggroed event"
        );
        assert_eq!(
            proc.state(eid),
            Some(NpcState::InCombat { target_id: 999 })
        );
    }

    #[test]
    fn test_no_aggro_high_level_player() {
        let (mut mgr, mut proc) = make_manager_and_processor();

        let def = NpcDef::new(62, "Goblin")
            .with_combat(7, 15, 5, 5, 5)
            .aggressive();
        let spawn = Position::new(100, 100);
        let eid = mgr.spawn(62, spawn).unwrap();
        proc.register(eid, &def, spawn);

        let mut nearby = HashMap::new();
        nearby.insert(
            eid,
            vec![NearbyPlayer {
                entity_id: 999,
                position: Position::new(102, 100),
                combat_level: 50, // >= 7 * 2 = 14, not eligible
                in_combat: false,
            }],
        );

        let events = proc.process_tick(&mut mgr, 10, &nearby);

        assert!(
            !events.iter().any(|e| matches!(e, BehaviorEvent::Aggroed { .. })),
            "High-level player should not be aggroed"
        );
    }

    #[test]
    fn test_death_and_respawn() {
        let (mut mgr, mut proc) = make_manager_and_processor();

        let def = NpcDef::new(21, "Rat").with_combat(2, 5, 1, 1, 1);
        let spawn = Position::new(100, 100);
        let eid = mgr.spawn(21, spawn).unwrap();
        proc.register(eid, &def, spawn);

        // Kill the NPC at tick 10.
        let npc = mgr.get_mut(eid).unwrap();
        npc.apply_damage(100, 10);

        let empty: HashMap<EntityId, Vec<NearbyPlayer>> = HashMap::new();

        // Process the death.
        let events = proc.process_tick(&mut mgr, 10, &empty);
        assert!(events.iter().any(|e| matches!(e, BehaviorEvent::Died { .. })));

        // Advance past respawn delay (default 100 ticks).
        for tick in 11..112 {
            proc.process_tick(&mut mgr, tick, &empty);
        }

        let npc = mgr.get(eid).unwrap();
        assert_eq!(npc.current_hp, npc.max_hp, "NPC should have respawned at full HP");
        assert_eq!(npc.position, spawn, "NPC should respawn at original position");
    }

    #[test]
    fn test_return_to_spawn() {
        let (mut mgr, mut proc) = make_manager_and_processor();

        let def = NpcDef::new(1, "Man").with_combat(2, 7, 1, 1, 1);
        let spawn = Position::new(100, 100);
        let eid = mgr.spawn(1, spawn).unwrap();
        proc.register(eid, &def, spawn);

        // Manually push the NPC far from spawn.
        let npc = mgr.get_mut(eid).unwrap();
        npc.position = Position::new(120, 120); // 20 tiles away, well past radius 5

        let empty: HashMap<EntityId, Vec<NearbyPlayer>> = HashMap::new();

        // Process a tick — should trigger ReturningToSpawn.
        proc.process_tick(&mut mgr, 1, &empty);
        assert_eq!(proc.state(eid), Some(NpcState::ReturningToSpawn));

        // Run enough ticks for the NPC to walk back.
        for tick in 2..50 {
            proc.process_tick(&mut mgr, tick, &empty);
        }

        let npc = mgr.get(eid).unwrap();
        let dist = chebyshev(npc.position, spawn);
        assert!(dist <= 1, "NPC should have returned near spawn (dist={})", dist);
    }

    #[test]
    fn test_target_lost_returns_to_spawn() {
        let (mut mgr, mut proc) = make_manager_and_processor();

        let def = NpcDef::new(62, "Goblin")
            .with_combat(7, 15, 5, 5, 5)
            .aggressive();
        let spawn = Position::new(100, 100);
        let eid = mgr.spawn(62, spawn).unwrap();
        proc.register(eid, &def, spawn);

        // Force into combat state.
        proc.enter_combat(eid, 999);
        let npc = mgr.get_mut(eid).unwrap();
        npc.start_combat(999, 10);

        // Tick with no nearby players — target fled.
        let empty: HashMap<EntityId, Vec<NearbyPlayer>> = HashMap::new();
        let events = proc.process_tick(&mut mgr, 11, &empty);

        assert!(events.iter().any(|e| matches!(e, BehaviorEvent::TargetLost { .. })));
        assert_eq!(proc.state(eid), Some(NpcState::ReturningToSpawn));
    }
}
