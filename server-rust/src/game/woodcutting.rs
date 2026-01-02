//! Woodcutting skill system.
//! Handles tree chopping, log types, and nest drops.

use std::collections::HashMap;
use tracing::{debug, info};

use super::entity::Position;

/// Types of trees that can be chopped.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TreeType {
    NormalTree,
    Oak,
    Willow,
    Maple,
    Yew,
    Magic,
}

impl TreeType {
    /// Get the log item ID for this tree type.
    pub fn log_id(&self) -> u32 {
        match self {
            TreeType::NormalTree => 14,
            TreeType::Oak => 632,
            TreeType::Willow => 633,
            TreeType::Maple => 634,
            TreeType::Yew => 635,
            TreeType::Magic => 636,
        }
    }

    /// Get required woodcutting level.
    pub fn required_level(&self) -> u8 {
        match self {
            TreeType::NormalTree => 1,
            TreeType::Oak => 15,
            TreeType::Willow => 30,
            TreeType::Maple => 45,
            TreeType::Yew => 60,
            TreeType::Magic => 75,
        }
    }

    /// Get woodcutting experience.
    pub fn experience(&self) -> u32 {
        match self {
            TreeType::NormalTree => 100,
            TreeType::Oak => 150,
            TreeType::Willow => 170,
            TreeType::Maple => 200,
            TreeType::Yew => 350,
            TreeType::Magic => 500,
        }
    }

    /// Get respawn time in game ticks.
    pub fn respawn_ticks(&self) -> u32 {
        match self {
            TreeType::NormalTree => 20,
            TreeType::Oak => 40,
            TreeType::Willow => 50,
            TreeType::Maple => 75,
            TreeType::Yew => 150,
            TreeType::Magic => 200,
        }
    }
}

/// Axe definitions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Axe {
    Bronze,
    Iron,
    Steel,
    Black,
    Mithril,
    Adamantite,
    Rune,
}

impl Axe {
    /// Get the item ID for this axe.
    pub fn item_id(&self) -> u32 {
        match self {
            Axe::Bronze => 87,
            Axe::Iron => 12,
            Axe::Steel => 88,
            Axe::Black => 428,
            Axe::Mithril => 203,
            Axe::Adamantite => 204,
            Axe::Rune => 405,
        }
    }

    /// Get the required woodcutting level.
    pub fn required_level(&self) -> u8 {
        match self {
            Axe::Bronze => 1,
            Axe::Iron => 1,
            Axe::Steel => 6,
            Axe::Black => 6,
            Axe::Mithril => 21,
            Axe::Adamantite => 31,
            Axe::Rune => 41,
        }
    }

    /// Get the chopping speed bonus (higher is faster).
    pub fn speed_bonus(&self) -> u8 {
        match self {
            Axe::Bronze => 1,
            Axe::Iron => 2,
            Axe::Steel => 3,
            Axe::Black => 3,
            Axe::Mithril => 4,
            Axe::Adamantite => 5,
            Axe::Rune => 6,
        }
    }
}

/// A tree that can be chopped.
#[derive(Debug, Clone)]
pub struct Tree {
    /// Position of the tree.
    pub position: Position,
    /// Type of tree.
    pub tree_type: TreeType,
    /// Object ID when full.
    pub full_id: u32,
    /// Object ID when stump.
    pub stump_id: u32,
    /// Current respawn timer (0 = available).
    pub respawn_timer: u32,
}

impl Tree {
    /// Create a new tree.
    pub fn new(position: Position, tree_type: TreeType, full_id: u32, stump_id: u32) -> Self {
        Self {
            position,
            tree_type,
            full_id,
            stump_id,
            respawn_timer: 0,
        }
    }

    /// Check if tree is available to chop.
    pub fn is_available(&self) -> bool {
        self.respawn_timer == 0
    }

    /// Fell the tree and start respawn timer.
    pub fn fell(&mut self) {
        self.respawn_timer = self.tree_type.respawn_ticks();
    }

    /// Tick the respawn timer.
    pub fn tick(&mut self) {
        if self.respawn_timer > 0 {
            self.respawn_timer -= 1;
        }
    }
}

/// Calculate woodcutting success chance.
pub fn calculate_chop_chance(
    woodcutting_level: u8,
    tree_level: u8,
    axe: Axe,
) -> f64 {
    let level_diff = woodcutting_level.saturating_sub(tree_level) as f64;
    let axe_bonus = axe.speed_bonus() as f64 * 0.05;
    let base_chance = 0.25 + (level_diff * 0.01) + axe_bonus;
    base_chance.clamp(0.1, 0.90)
}

/// Bird's nest types that can be found.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NestType {
    Empty,
    Ring,
    Egg,
    Seeds,
}

impl NestType {
    /// Get item ID for this nest type.
    pub fn item_id(&self) -> u32 {
        match self {
            NestType::Empty => 1022,
            NestType::Ring => 1022,
            NestType::Egg => 1022,
            NestType::Seeds => 1022,
        }
    }
}

/// Check if player finds a bird's nest while cutting.
pub fn check_nest_drop(woodcutting_level: u8) -> Option<NestType> {
    // Base nest chance is about 1/256
    let nest_chance = 256.0;
    if rand::random::<f64>() * nest_chance > 1.0 {
        return None;
    }

    // Random nest type
    let roll = rand::random::<u32>() % 100;
    if roll < 50 {
        Some(NestType::Empty)
    } else if roll < 75 {
        Some(NestType::Seeds)
    } else if roll < 90 {
        Some(NestType::Egg)
    } else {
        Some(NestType::Ring)
    }
}

/// Manager for woodcutting system.
#[derive(Debug, Default)]
pub struct WoodcuttingManager {
    /// Trees by position.
    trees: HashMap<(u16, u16), Tree>,
}

impl WoodcuttingManager {
    /// Create a new woodcutting manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a tree.
    pub fn register_tree(&mut self, tree: Tree) {
        let key = (tree.position.x, tree.position.y);
        self.trees.insert(key, tree);
    }

    /// Get tree at position.
    pub fn get_tree(&self, x: u16, y: u16) -> Option<&Tree> {
        self.trees.get(&(x, y))
    }

    /// Get mutable tree at position.
    pub fn get_tree_mut(&mut self, x: u16, y: u16) -> Option<&mut Tree> {
        self.trees.get_mut(&(x, y))
    }

    /// Tick all trees (update respawn timers).
    pub fn tick(&mut self) {
        for tree in self.trees.values_mut() {
            tree.tick();
        }
    }

    /// Get best usable axe from a list of available item IDs.
    pub fn best_axe(available_items: &[u32], woodcutting_level: u8) -> Option<Axe> {
        let axes = [
            Axe::Rune,
            Axe::Adamantite,
            Axe::Mithril,
            Axe::Black,
            Axe::Steel,
            Axe::Iron,
            Axe::Bronze,
        ];

        for axe in axes {
            if woodcutting_level >= axe.required_level() && available_items.contains(&axe.item_id()) {
                return Some(axe);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tree_levels() {
        assert_eq!(TreeType::NormalTree.required_level(), 1);
        assert_eq!(TreeType::Magic.required_level(), 75);
    }

    #[test]
    fn test_chop_chance() {
        // High level with rune axe = high chance
        let chance = calculate_chop_chance(99, 1, Axe::Rune);
        assert!(chance > 0.8);

        // Low level with bronze axe = low chance
        let chance2 = calculate_chop_chance(1, 1, Axe::Bronze);
        assert!(chance2 < 0.5);
    }

    #[test]
    fn test_tree_respawn() {
        let pos = Position { x: 100, y: 100, plane: 0 };
        let mut tree = Tree::new(pos, TreeType::Oak, 100, 101);

        assert!(tree.is_available());
        tree.fell();
        assert!(!tree.is_available());

        // Tick down respawn
        for _ in 0..40 {
            tree.tick();
        }
        assert!(tree.is_available());
    }
}
