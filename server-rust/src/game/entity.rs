//! Entity module for game entities.
//! Defines common entity traits and types.

use serde::{Deserialize, Serialize};

/// Unique identifier for entities.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct EntityId(pub u64);

impl std::fmt::Display for EntityId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// 2D position in the game world.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Position {
    pub x: i32,
    pub y: i32,
}

impl Position {
    pub fn new(x: i32, y: i32) -> Self {
        Self { x, y }
    }

    /// Calculate distance to another position.
    pub fn distance_to(&self, other: &Position) -> f64 {
        let dx = (self.x - other.x) as f64;
        let dy = (self.y - other.y) as f64;
        (dx * dx + dy * dy).sqrt()
    }

    /// Check if within range of another position.
    pub fn in_range(&self, other: &Position, range: i32) -> bool {
        let dx = (self.x - other.x).abs();
        let dy = (self.y - other.y).abs();
        dx <= range && dy <= range
    }

    /// Check if this position is in wilderness.
    pub fn in_wilderness(&self) -> bool {
        // Wilderness boundary check (simplified)
        self.y >= 2304 && self.y <= 3000
    }

    /// Get wilderness level at this position.
    pub fn wilderness_level(&self) -> u32 {
        if !self.in_wilderness() {
            return 0;
        }
        // Calculate wilderness level based on y coordinate
        ((self.y - 2304) / 6 + 1) as u32
    }
}

impl std::fmt::Display for Position {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "({}, {})", self.x, self.y)
    }
}

/// Direction enum for entity facing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Direction {
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
    NorthWest,
}

impl Direction {
    /// Get direction from position offset.
    pub fn from_offset(dx: i32, dy: i32) -> Self {
        match (dx.signum(), dy.signum()) {
            (0, -1) => Direction::North,
            (1, -1) => Direction::NorthEast,
            (1, 0) => Direction::East,
            (1, 1) => Direction::SouthEast,
            (0, 1) => Direction::South,
            (-1, 1) => Direction::SouthWest,
            (-1, 0) => Direction::West,
            (-1, -1) => Direction::NorthWest,
            _ => Direction::South, // Default
        }
    }
}

/// Common entity trait.
pub trait Entity: Send + Sync {
    fn id(&self) -> EntityId;
    fn position(&self) -> Position;
    fn set_position(&mut self, pos: Position);
    fn direction(&self) -> Direction;
    fn is_visible(&self) -> bool;
}

/// Entity type enumeration.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EntityType {
    Player,
    Npc,
    GroundItem,
    GameObject,
}
