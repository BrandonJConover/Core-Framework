//! NPC (Non-Player Character) system for game entities.
//!
//! Implements NPC spawning, combat AI, pathfinding, and drop tables.

use super::entity::{Direction, EntityId, Position};
use super::combat::CombatStyle;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Instant;
use tracing::debug;

/// NPC definition containing stats and behavior.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NpcDef {
    pub id: u32,
    pub name: String,
    pub description: String,
    pub combat_level: u32,
    pub hitpoints: u32,
    pub attack_level: u32,
    pub strength_level: u32,
    pub defense_level: u32,
    pub attackable: bool,
    pub aggressive: bool,
    pub respawn_time: u32, // In game ticks
    pub wander_radius: u32,
}

impl NpcDef {
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            description: String::new(),
            combat_level: 1,
            hitpoints: 10,
            attack_level: 1,
            strength_level: 1,
            defense_level: 1,
            attackable: true,
            aggressive: false,
            respawn_time: 100, // ~60 seconds
            wander_radius: 5,
        }
    }

    pub fn with_combat(mut self, combat_level: u32, hp: u32, atk: u32, str: u32, def: u32) -> Self {
        self.combat_level = combat_level;
        self.hitpoints = hp;
        self.attack_level = atk;
        self.strength_level = str;
        self.defense_level = def;
        self
    }

    pub fn aggressive(mut self) -> Self {
        self.aggressive = true;
        self
    }

    pub fn non_attackable(mut self) -> Self {
        self.attackable = false;
        self
    }
}

/// State of an NPC in combat.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NpcCombatState {
    Idle,
    InCombat { target_id: u64, last_attack_tick: u64 },
    Fleeing,
    Dead { death_tick: u64 },
    Respawning { respawn_tick: u64 },
}

/// An NPC instance in the game world.
#[derive(Debug)]
pub struct Npc {
    pub entity_id: EntityId,
    pub def_id: u32,
    pub position: Position,
    pub spawn_position: Position,
    pub direction: Direction,
    pub current_hp: u32,
    pub max_hp: u32,
    pub combat_state: NpcCombatState,
    pub last_movement_tick: u64,
    pub removed: bool,
}

impl Npc {
    pub fn new(entity_id: EntityId, def: &NpcDef, spawn_pos: Position) -> Self {
        Self {
            entity_id,
            def_id: def.id,
            position: spawn_pos,
            spawn_position: spawn_pos,
            direction: Direction::South,
            current_hp: def.hitpoints,
            max_hp: def.hitpoints,
            combat_state: NpcCombatState::Idle,
            last_movement_tick: 0,
            removed: false,
        }
    }

    /// Check if NPC is in combat.
    pub fn is_in_combat(&self) -> bool {
        matches!(self.combat_state, NpcCombatState::InCombat { .. })
    }

    /// Check if NPC is dead.
    pub fn is_dead(&self) -> bool {
        matches!(self.combat_state, NpcCombatState::Dead { .. })
    }

    /// Check if NPC is respawning.
    pub fn is_respawning(&self) -> bool {
        matches!(self.combat_state, NpcCombatState::Respawning { .. })
    }

    /// Start combat with a player.
    pub fn start_combat(&mut self, player_id: u64, current_tick: u64) {
        self.combat_state = NpcCombatState::InCombat {
            target_id: player_id,
            last_attack_tick: current_tick,
        };
        debug!("NPC {} started combat with player {}", self.entity_id.0, player_id);
    }

    /// End combat.
    pub fn end_combat(&mut self) {
        self.combat_state = NpcCombatState::Idle;
        debug!("NPC {} ended combat", self.entity_id.0);
    }

    /// Apply damage to NPC.
    pub fn apply_damage(&mut self, damage: u32, current_tick: u64) -> bool {
        if damage >= self.current_hp {
            self.current_hp = 0;
            self.combat_state = NpcCombatState::Dead { death_tick: current_tick };
            debug!("NPC {} died", self.entity_id.0);
            return true;
        }

        self.current_hp -= damage;
        false
    }

    /// Respawn the NPC.
    pub fn respawn(&mut self) {
        self.position = self.spawn_position;
        self.current_hp = self.max_hp;
        self.combat_state = NpcCombatState::Idle;
        self.removed = false;
        debug!("NPC {} respawned at {:?}", self.entity_id.0, self.spawn_position);
    }

    /// Get distance to a position.
    pub fn distance_to(&self, pos: Position) -> u32 {
        let dx = (self.position.x as i32 - pos.x as i32).unsigned_abs();
        let dy = (self.position.y as i32 - pos.y as i32).unsigned_abs();
        dx.max(dy)
    }

    /// Move towards a position.
    pub fn move_towards(&mut self, target: Position) -> bool {
        let dx = target.x as i32 - self.position.x as i32;
        let dy = target.y as i32 - self.position.y as i32;

        if dx == 0 && dy == 0 {
            return false;
        }

        let new_x = if dx > 0 {
            self.position.x + 1
        } else if dx < 0 {
            self.position.x.saturating_sub(1)
        } else {
            self.position.x
        };

        let new_y = if dy > 0 {
            self.position.y + 1
        } else if dy < 0 {
            self.position.y.saturating_sub(1)
        } else {
            self.position.y
        };

        // Update direction
        self.direction = match (dx.signum(), dy.signum()) {
            (0, -1) => Direction::North,
            (1, -1) => Direction::NorthEast,
            (1, 0) => Direction::East,
            (1, 1) => Direction::SouthEast,
            (0, 1) => Direction::South,
            (-1, 1) => Direction::SouthWest,
            (-1, 0) => Direction::West,
            (-1, -1) => Direction::NorthWest,
            _ => self.direction,
        };

        self.position = Position::new(new_x, new_y);
        true
    }

    /// Random wander movement.
    pub fn wander(&mut self, wander_radius: u32) -> bool {
        use rand::Rng;
        let mut rng = rand::thread_rng();

        // 50% chance to not move
        if rng.gen_bool(0.5) {
            return false;
        }

        // Random direction
        let dx: i32 = rng.gen_range(-1..=1);
        let dy: i32 = rng.gen_range(-1..=1);

        if dx == 0 && dy == 0 {
            return false;
        }

        let new_x = (self.position.x as i32 + dx).max(0) as u16;
        let new_y = (self.position.y as i32 + dy).max(0) as u16;

        // Check within wander radius
        let spawn_dx = (new_x as i32 - self.spawn_position.x as i32).unsigned_abs();
        let spawn_dy = (new_y as i32 - self.spawn_position.y as i32).unsigned_abs();

        if spawn_dx > wander_radius || spawn_dy > wander_radius {
            return false;
        }

        self.position = Position::new(new_x, new_y);
        true
    }
}

/// Drop table entry for NPC loot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DropEntry {
    pub item_id: u32,
    pub min_amount: u32,
    pub max_amount: u32,
    pub weight: u32,
    pub noted: bool,
}

impl DropEntry {
    pub fn new(item_id: u32, amount: u32, weight: u32) -> Self {
        Self {
            item_id,
            min_amount: amount,
            max_amount: amount,
            weight,
            noted: false,
        }
    }

    pub fn range(item_id: u32, min: u32, max: u32, weight: u32) -> Self {
        Self {
            item_id,
            min_amount: min,
            max_amount: max,
            weight,
            noted: false,
        }
    }

    pub fn noted(mut self) -> Self {
        self.noted = true;
        self
    }

    /// Roll the amount for this drop.
    pub fn roll_amount(&self) -> u32 {
        if self.min_amount == self.max_amount {
            self.min_amount
        } else {
            use rand::Rng;
            rand::thread_rng().gen_range(self.min_amount..=self.max_amount)
        }
    }
}

/// Drop table for an NPC.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DropTable {
    pub always_drops: Vec<DropEntry>,
    pub variable_drops: Vec<DropEntry>,
    pub total_weight: u32,
}

impl DropTable {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a drop that always happens.
    pub fn add_always(&mut self, entry: DropEntry) {
        self.always_drops.push(entry);
    }

    /// Add a variable drop with weight.
    pub fn add_drop(&mut self, entry: DropEntry) {
        self.total_weight += entry.weight;
        self.variable_drops.push(entry);
    }

    /// Roll for drops.
    pub fn roll(&self) -> Vec<(u32, u32, bool)> {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let mut drops = Vec::new();

        // Always drops
        for entry in &self.always_drops {
            drops.push((entry.item_id, entry.roll_amount(), entry.noted));
        }

        // Variable drops
        if self.total_weight > 0 && !self.variable_drops.is_empty() {
            let roll = rng.gen_range(0..self.total_weight);
            let mut cumulative = 0;

            for entry in &self.variable_drops {
                cumulative += entry.weight;
                if roll < cumulative {
                    drops.push((entry.item_id, entry.roll_amount(), entry.noted));
                    break;
                }
            }
        }

        drops
    }
}

/// Manager for all NPCs in the game.
#[derive(Debug, Default)]
pub struct NpcManager {
    npcs: HashMap<EntityId, Npc>,
    npc_definitions: HashMap<u32, NpcDef>,
    drop_tables: HashMap<u32, DropTable>,
    next_entity_id: u64,
}

impl NpcManager {
    pub fn new() -> Self {
        let mut manager = Self::default();
        manager.next_entity_id = 1;
        manager.load_definitions();
        manager
    }

    fn load_definitions(&mut self) {
        // Sample NPC definitions
        self.add_definition(NpcDef::new(1, "Man")
            .with_combat(2, 7, 1, 1, 1));

        self.add_definition(NpcDef::new(2, "Woman")
            .with_combat(2, 7, 1, 1, 1));

        self.add_definition(NpcDef::new(21, "Rat")
            .with_combat(2, 5, 1, 1, 1));

        self.add_definition(NpcDef::new(62, "Goblin")
            .with_combat(7, 15, 5, 5, 5)
            .aggressive());

        self.add_definition(NpcDef::new(66, "Skeleton")
            .with_combat(21, 25, 18, 18, 18)
            .aggressive());

        self.add_definition(NpcDef::new(68, "Zombie")
            .with_combat(24, 30, 20, 20, 20)
            .aggressive());

        self.add_definition(NpcDef::new(93, "Black Knight")
            .with_combat(46, 55, 42, 42, 42)
            .aggressive());

        self.add_definition(NpcDef::new(184, "Lesser Demon")
            .with_combat(79, 90, 70, 70, 70)
            .aggressive());

        self.add_definition(NpcDef::new(135, "Greater Demon")
            .with_combat(87, 100, 80, 80, 80)
            .aggressive());

        self.add_definition(NpcDef::new(95, "Banker")
            .non_attackable());
    }

    /// Add an NPC definition.
    pub fn add_definition(&mut self, def: NpcDef) {
        self.npc_definitions.insert(def.id, def);
    }

    /// Get an NPC definition.
    pub fn get_definition(&self, id: u32) -> Option<&NpcDef> {
        self.npc_definitions.get(&id)
    }

    /// Set drop table for an NPC.
    pub fn set_drop_table(&mut self, npc_id: u32, table: DropTable) {
        self.drop_tables.insert(npc_id, table);
    }

    /// Get drop table for an NPC.
    pub fn get_drop_table(&self, npc_id: u32) -> Option<&DropTable> {
        self.drop_tables.get(&npc_id)
    }

    /// Spawn an NPC.
    pub fn spawn(&mut self, def_id: u32, position: Position) -> Option<EntityId> {
        let def = self.npc_definitions.get(&def_id)?;

        let entity_id = EntityId(self.next_entity_id);
        self.next_entity_id += 1;

        let npc = Npc::new(entity_id, def, position);
        self.npcs.insert(entity_id, npc);

        debug!("Spawned NPC {} ({}) at {:?}", def.name, def_id, position);
        Some(entity_id)
    }

    /// Get an NPC by entity ID.
    pub fn get(&self, entity_id: EntityId) -> Option<&Npc> {
        self.npcs.get(&entity_id)
    }

    /// Get a mutable NPC by entity ID.
    pub fn get_mut(&mut self, entity_id: EntityId) -> Option<&mut Npc> {
        self.npcs.get_mut(&entity_id)
    }

    /// Remove an NPC.
    pub fn remove(&mut self, entity_id: EntityId) {
        self.npcs.remove(&entity_id);
    }

    /// Get all NPCs.
    pub fn all(&self) -> impl Iterator<Item = &Npc> {
        self.npcs.values()
    }

    /// Get all NPCs mutably.
    pub fn all_mut(&mut self) -> impl Iterator<Item = &mut Npc> {
        self.npcs.values_mut()
    }

    /// Get NPCs near a position.
    pub fn near(&self, pos: Position, radius: u32) -> Vec<EntityId> {
        self.npcs.iter()
            .filter(|(_, npc)| npc.distance_to(pos) <= radius && !npc.is_dead())
            .map(|(id, _)| *id)
            .collect()
    }

    /// Process NPC tick.
    pub fn tick(&mut self, current_tick: u64) {
        let respawn_npcs: Vec<EntityId> = self.npcs.iter()
            .filter_map(|(id, npc)| {
                if let NpcCombatState::Dead { death_tick } = npc.combat_state {
                    let def = self.npc_definitions.get(&npc.def_id)?;
                    if current_tick >= death_tick + def.respawn_time as u64 {
                        return Some(*id);
                    }
                }
                None
            })
            .collect();

        // Respawn dead NPCs
        for id in respawn_npcs {
            if let Some(npc) = self.npcs.get_mut(&id) {
                npc.respawn();
            }
        }

        // Wander idle NPCs
        for npc in self.npcs.values_mut() {
            if matches!(npc.combat_state, NpcCombatState::Idle) {
                if current_tick > npc.last_movement_tick + 3 {
                    let def = self.npc_definitions.get(&npc.def_id);
                    let radius = def.map(|d| d.wander_radius).unwrap_or(5);
                    npc.wander(radius);
                    npc.last_movement_tick = current_tick;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_npc_spawn() {
        let mut manager = NpcManager::new();
        let entity_id = manager.spawn(1, Position::new(100, 100)).unwrap();

        let npc = manager.get(entity_id).unwrap();
        assert_eq!(npc.def_id, 1);
        assert_eq!(npc.position.x, 100);
    }

    #[test]
    fn test_npc_damage() {
        let mut manager = NpcManager::new();
        let entity_id = manager.spawn(21, Position::new(100, 100)).unwrap(); // Rat

        let npc = manager.get_mut(entity_id).unwrap();
        let died = npc.apply_damage(3, 0);
        assert!(!died);
        assert_eq!(npc.current_hp, 2);

        let died = npc.apply_damage(10, 1);
        assert!(died);
        assert!(npc.is_dead());
    }

    #[test]
    fn test_drop_table() {
        let mut table = DropTable::new();
        table.add_always(DropEntry::new(526, 1, 100)); // Bones
        table.add_drop(DropEntry::range(10, 1, 5, 50)); // Coins

        let drops = table.roll();
        assert!(!drops.is_empty());
        assert_eq!(drops[0].0, 526); // Always get bones
    }
}
