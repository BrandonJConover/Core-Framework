//! Agility skill system.
//! Handles obstacle courses and shortcuts.

use std::collections::HashMap;

use super::entity::Position;

/// Obstacle types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ObstacleType {
    /// Balance across a log.
    BalanceLog,
    /// Climb over a wall.
    ClimbWall,
    /// Swing across a rope.
    SwingRope,
    /// Jump across a gap.
    JumpGap,
    /// Crawl through a pipe.
    CrawlPipe,
    /// Cross stepping stones.
    SteppingStones,
    /// Climb a net.
    ClimbNet,
    /// Walk across a tightrope.
    Tightrope,
    /// Vault over a barrier.
    Vault,
}

impl ObstacleType {
    /// Get base failure chance.
    pub fn base_failure_chance(&self) -> f64 {
        match self {
            ObstacleType::BalanceLog => 0.15,
            ObstacleType::ClimbWall => 0.10,
            ObstacleType::SwingRope => 0.20,
            ObstacleType::JumpGap => 0.25,
            ObstacleType::CrawlPipe => 0.05,
            ObstacleType::SteppingStones => 0.20,
            ObstacleType::ClimbNet => 0.10,
            ObstacleType::Tightrope => 0.30,
            ObstacleType::Vault => 0.15,
        }
    }

    /// Get animation ticks.
    pub fn animation_ticks(&self) -> u32 {
        match self {
            ObstacleType::BalanceLog => 4,
            ObstacleType::ClimbWall => 3,
            ObstacleType::SwingRope => 2,
            ObstacleType::JumpGap => 2,
            ObstacleType::CrawlPipe => 5,
            ObstacleType::SteppingStones => 6,
            ObstacleType::ClimbNet => 3,
            ObstacleType::Tightrope => 5,
            ObstacleType::Vault => 2,
        }
    }
}

/// An obstacle in an agility course.
#[derive(Debug, Clone)]
pub struct Obstacle {
    /// Object ID.
    pub object_id: u32,
    /// Position.
    pub position: Position,
    /// Obstacle type.
    pub obstacle_type: ObstacleType,
    /// Required agility level.
    pub required_level: u8,
    /// Experience gained.
    pub experience: u32,
    /// Destination after completing.
    pub destination: Position,
    /// Damage on failure (0 = no damage).
    pub fail_damage: u8,
}

impl Obstacle {
    /// Create a new obstacle.
    pub fn new(
        object_id: u32,
        position: Position,
        obstacle_type: ObstacleType,
        required_level: u8,
        experience: u32,
        destination: Position,
    ) -> Self {
        Self {
            object_id,
            position,
            obstacle_type,
            required_level,
            experience,
            destination,
            fail_damage: 0,
        }
    }

    /// Set fail damage.
    pub fn with_fail_damage(mut self, damage: u8) -> Self {
        self.fail_damage = damage;
        self
    }
}

/// Agility course definitions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AgilityCourse {
    GnomeStronghold,
    BarbarianOutpost,
    WildernessAgility,
}

impl AgilityCourse {
    /// Get required agility level.
    pub fn required_level(&self) -> u8 {
        match self {
            AgilityCourse::GnomeStronghold => 1,
            AgilityCourse::BarbarianOutpost => 35,
            AgilityCourse::WildernessAgility => 52,
        }
    }

    /// Get completion bonus experience.
    pub fn completion_bonus(&self) -> u32 {
        match self {
            AgilityCourse::GnomeStronghold => 195,
            AgilityCourse::BarbarianOutpost => 282,
            AgilityCourse::WildernessAgility => 571,
        }
    }

    /// Get number of obstacles.
    pub fn obstacle_count(&self) -> u8 {
        match self {
            AgilityCourse::GnomeStronghold => 7,
            AgilityCourse::BarbarianOutpost => 6,
            AgilityCourse::WildernessAgility => 6,
        }
    }
}

/// Shortcut types.
#[derive(Debug, Clone)]
pub struct Shortcut {
    /// Object ID.
    pub object_id: u32,
    /// Position.
    pub position: Position,
    /// Required agility level.
    pub required_level: u8,
    /// Destination position.
    pub destination: Position,
    /// Description.
    pub description: String,
}

impl Shortcut {
    /// Create a new shortcut.
    pub fn new(
        object_id: u32,
        position: Position,
        required_level: u8,
        destination: Position,
        description: &str,
    ) -> Self {
        Self {
            object_id,
            position,
            required_level,
            destination,
            description: description.to_string(),
        }
    }
}

/// Calculate obstacle success chance.
pub fn calculate_obstacle_chance(
    agility_level: u8,
    required_level: u8,
    obstacle_type: ObstacleType,
) -> f64 {
    let level_diff = agility_level.saturating_sub(required_level) as f64;
    let base_fail = obstacle_type.base_failure_chance();
    let fail_reduction = level_diff * 0.01; // 1% less failure per level
    let fail_chance = (base_fail - fail_reduction).clamp(0.01, base_fail);
    1.0 - fail_chance
}

/// Manager for agility system.
#[derive(Debug, Default)]
pub struct AgilityManager {
    /// Obstacles by object ID.
    obstacles: HashMap<u32, Obstacle>,
    /// Shortcuts by object ID.
    shortcuts: HashMap<u32, Shortcut>,
    /// Player course progress (player_id -> obstacles completed).
    course_progress: HashMap<u64, Vec<u32>>,
}

impl AgilityManager {
    /// Create a new agility manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register an obstacle.
    pub fn register_obstacle(&mut self, obstacle: Obstacle) {
        self.obstacles.insert(obstacle.object_id, obstacle);
    }

    /// Register a shortcut.
    pub fn register_shortcut(&mut self, shortcut: Shortcut) {
        self.shortcuts.insert(shortcut.object_id, shortcut);
    }

    /// Get obstacle by object ID.
    pub fn get_obstacle(&self, object_id: u32) -> Option<&Obstacle> {
        self.obstacles.get(&object_id)
    }

    /// Get shortcut by object ID.
    pub fn get_shortcut(&self, object_id: u32) -> Option<&Shortcut> {
        self.shortcuts.get(&object_id)
    }

    /// Check if player can use obstacle.
    pub fn can_use_obstacle(&self, agility_level: u8, obstacle: &Obstacle) -> bool {
        agility_level >= obstacle.required_level
    }

    /// Check if player can use shortcut.
    pub fn can_use_shortcut(&self, agility_level: u8, shortcut: &Shortcut) -> bool {
        agility_level >= shortcut.required_level
    }

    /// Record obstacle completion for course tracking.
    pub fn record_obstacle_completion(&mut self, player_id: u64, obstacle_id: u32) {
        self.course_progress
            .entry(player_id)
            .or_insert_with(Vec::new)
            .push(obstacle_id);
    }

    /// Check if player completed a full course lap.
    pub fn check_course_completion(&mut self, player_id: u64, course: AgilityCourse) -> bool {
        let required = course.obstacle_count() as usize;
        if let Some(progress) = self.course_progress.get(&player_id) {
            if progress.len() >= required {
                // Clear progress and return true
                self.course_progress.remove(&player_id);
                return true;
            }
        }
        false
    }

    /// Reset player's course progress.
    pub fn reset_progress(&mut self, player_id: u64) {
        self.course_progress.remove(&player_id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_course_levels() {
        assert_eq!(AgilityCourse::GnomeStronghold.required_level(), 1);
        assert_eq!(AgilityCourse::WildernessAgility.required_level(), 52);
    }

    #[test]
    fn test_obstacle_chance() {
        // At required level with tightrope (high failure)
        let chance = calculate_obstacle_chance(1, 1, ObstacleType::Tightrope);
        assert!((chance - 0.70).abs() < 0.01);

        // Well above required level
        let chance2 = calculate_obstacle_chance(50, 1, ObstacleType::Tightrope);
        assert!(chance2 > 0.9);
    }

    #[test]
    fn test_agility_manager() {
        let mut manager = AgilityManager::new();

        let pos = Position {
            x: 100,
            y: 100,
            plane: 0,
        };
        let dest = Position {
            x: 105,
            y: 100,
            plane: 0,
        };
        let obstacle = Obstacle::new(1, pos, ObstacleType::BalanceLog, 1, 30, dest);

        manager.register_obstacle(obstacle);
        assert!(manager.get_obstacle(1).is_some());
    }
}
