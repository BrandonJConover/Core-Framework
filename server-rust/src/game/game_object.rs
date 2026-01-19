//! Game object system for world objects like doors, chests, and scenery.
//! Handles object definitions, state management, and interactions.

use std::collections::HashMap;
use tracing::{debug, info};

use super::entity::{EntityId, Position};

/// Object types in the game world.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObjectType {
    /// Standard scenery objects (trees, rocks, furnaces).
    Scenery,
    /// Boundary objects (doors, gates, walls).
    Boundary,
    /// Interactive ground decorations.
    GroundDecoration,
}

/// Object direction/orientation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObjectDirection {
    North,
    East,
    South,
    West,
}

impl ObjectDirection {
    /// Convert from numeric direction.
    pub fn from_value(value: u8) -> Self {
        match value % 4 {
            0 => ObjectDirection::North,
            1 => ObjectDirection::East,
            2 => ObjectDirection::South,
            _ => ObjectDirection::West,
        }
    }

    /// Get numeric value.
    pub fn value(&self) -> u8 {
        match self {
            ObjectDirection::North => 0,
            ObjectDirection::East => 1,
            ObjectDirection::South => 2,
            ObjectDirection::West => 3,
        }
    }
}

/// Object definition from data files.
#[derive(Debug, Clone)]
pub struct ObjectDef {
    /// Object ID.
    pub id: u32,
    /// Object name.
    pub name: String,
    /// Description when examined.
    pub description: String,
    /// Object type.
    pub object_type: ObjectType,
    /// Width in tiles.
    pub width: u8,
    /// Height in tiles.
    pub height: u8,
    /// Command options (e.g., "Open", "Mine", "Chop").
    pub commands: Vec<String>,
    /// Whether this blocks movement.
    pub blocks_movement: bool,
}

impl ObjectDef {
    /// Create a new object definition.
    pub fn new(id: u32, name: &str) -> Self {
        Self {
            id,
            name: name.to_string(),
            description: String::new(),
            object_type: ObjectType::Scenery,
            width: 1,
            height: 1,
            commands: Vec::new(),
            blocks_movement: true,
        }
    }

    /// Builder-style: set description.
    pub fn with_description(mut self, desc: &str) -> Self {
        self.description = desc.to_string();
        self
    }

    /// Builder-style: set type.
    pub fn with_type(mut self, obj_type: ObjectType) -> Self {
        self.object_type = obj_type;
        self
    }

    /// Builder-style: set dimensions.
    pub fn with_size(mut self, width: u8, height: u8) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    /// Builder-style: add command.
    pub fn with_command(mut self, cmd: &str) -> Self {
        self.commands.push(cmd.to_string());
        self
    }

    /// Builder-style: set walkable.
    pub fn walkable(mut self) -> Self {
        self.blocks_movement = false;
        self
    }
}

/// An instance of a game object in the world.
#[derive(Debug, Clone)]
pub struct GameObject {
    /// Unique instance ID.
    pub id: EntityId,
    /// Object definition ID.
    pub def_id: u32,
    /// World position.
    pub position: Position,
    /// Object direction.
    pub direction: ObjectDirection,
    /// Object type.
    pub object_type: ObjectType,
    /// Current state (for doors: open/closed, for mining: depleted/full).
    pub state: ObjectState,
    /// Tick when state should reset.
    pub reset_tick: Option<u64>,
}

/// Object state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObjectState {
    /// Default state.
    Default,
    /// Alternate state (door open, rock depleted, etc.).
    Alternate,
    /// Hidden/removed temporarily.
    Hidden,
}

impl GameObject {
    /// Create a new game object.
    pub fn new(
        id: EntityId,
        def_id: u32,
        position: Position,
        direction: ObjectDirection,
        object_type: ObjectType,
    ) -> Self {
        Self {
            id,
            def_id,
            position,
            direction,
            object_type,
            state: ObjectState::Default,
            reset_tick: None,
        }
    }

    /// Create a scenery object.
    pub fn scenery(id: EntityId, def_id: u32, position: Position, direction: ObjectDirection) -> Self {
        Self::new(id, def_id, position, direction, ObjectType::Scenery)
    }

    /// Create a boundary object.
    pub fn boundary(id: EntityId, def_id: u32, position: Position, direction: ObjectDirection) -> Self {
        Self::new(id, def_id, position, direction, ObjectType::Boundary)
    }

    /// Check if in default state.
    pub fn is_default(&self) -> bool {
        self.state == ObjectState::Default
    }

    /// Check if hidden.
    pub fn is_hidden(&self) -> bool {
        self.state == ObjectState::Hidden
    }

    /// Set to alternate state with reset timer.
    pub fn set_alternate(&mut self, reset_after_ticks: u64, current_tick: u64) {
        self.state = ObjectState::Alternate;
        self.reset_tick = Some(current_tick + reset_after_ticks);
    }

    /// Set to hidden state with reset timer.
    pub fn set_hidden(&mut self, reset_after_ticks: u64, current_tick: u64) {
        self.state = ObjectState::Hidden;
        self.reset_tick = Some(current_tick + reset_after_ticks);
    }

    /// Reset to default state.
    pub fn reset(&mut self) {
        self.state = ObjectState::Default;
        self.reset_tick = None;
    }

    /// Check if should reset this tick.
    pub fn should_reset(&self, current_tick: u64) -> bool {
        self.reset_tick.map(|t| current_tick >= t).unwrap_or(false)
    }

    /// Get location key for spatial indexing.
    pub fn location_key(&self) -> (u16, u16) {
        (self.position.x, self.position.y)
    }
}

/// Manager for game objects in the world.
#[derive(Debug, Default)]
pub struct GameObjectManager {
    /// All objects by ID.
    objects: HashMap<EntityId, GameObject>,
    /// Objects indexed by location.
    by_location: HashMap<(u16, u16), Vec<EntityId>>,
    /// Object definitions.
    definitions: HashMap<u32, ObjectDef>,
    /// Next entity ID.
    next_id: u32,
    /// Current tick.
    current_tick: u64,
}

impl GameObjectManager {
    /// Create a new game object manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Process a game tick.
    pub fn tick(&mut self) {
        self.current_tick += 1;

        // Reset objects that need resetting
        let current = self.current_tick;
        let to_reset: Vec<EntityId> = self
            .objects
            .iter()
            .filter(|(_, obj)| obj.should_reset(current))
            .map(|(id, _)| *id)
            .collect();

        for id in to_reset {
            if let Some(obj) = self.objects.get_mut(&id) {
                obj.reset();
                debug!("Reset object {} to default state", id.0);
            }
        }
    }

    /// Generate next entity ID.
    fn next_entity_id(&mut self) -> EntityId {
        self.next_id += 1;
        EntityId(self.next_id)
    }

    /// Register an object definition.
    pub fn register_definition(&mut self, def: ObjectDef) {
        self.definitions.insert(def.id, def);
    }

    /// Get an object definition.
    pub fn get_definition(&self, id: u32) -> Option<&ObjectDef> {
        self.definitions.get(&id)
    }

    /// Spawn a scenery object.
    pub fn spawn_scenery(
        &mut self,
        def_id: u32,
        position: Position,
        direction: ObjectDirection,
    ) -> EntityId {
        let id = self.next_entity_id();
        let obj = GameObject::scenery(id, def_id, position, direction);
        self.add_object(obj);
        id
    }

    /// Spawn a boundary object.
    pub fn spawn_boundary(
        &mut self,
        def_id: u32,
        position: Position,
        direction: ObjectDirection,
    ) -> EntityId {
        let id = self.next_entity_id();
        let obj = GameObject::boundary(id, def_id, position, direction);
        self.add_object(obj);
        id
    }

    /// Add an object to the manager.
    fn add_object(&mut self, obj: GameObject) {
        let id = obj.id;
        let loc = obj.location_key();

        self.objects.insert(id, obj);
        self.by_location.entry(loc).or_default().push(id);
    }

    /// Get an object by ID.
    pub fn get(&self, id: EntityId) -> Option<&GameObject> {
        self.objects.get(&id)
    }

    /// Get mutable object by ID.
    pub fn get_mut(&mut self, id: EntityId) -> Option<&mut GameObject> {
        self.objects.get_mut(&id)
    }

    /// Get objects at a location.
    pub fn at_location(&self, x: u16, y: u16) -> Vec<&GameObject> {
        self.by_location
            .get(&(x, y))
            .map(|ids| ids.iter().filter_map(|id| self.objects.get(id)).collect())
            .unwrap_or_default()
    }

    /// Get scenery at location.
    pub fn scenery_at(&self, x: u16, y: u16) -> Option<&GameObject> {
        self.at_location(x, y)
            .into_iter()
            .find(|obj| obj.object_type == ObjectType::Scenery && !obj.is_hidden())
    }

    /// Get boundary at location.
    pub fn boundary_at(&self, x: u16, y: u16) -> Option<&GameObject> {
        self.at_location(x, y)
            .into_iter()
            .find(|obj| obj.object_type == ObjectType::Boundary && !obj.is_hidden())
    }

    /// Remove an object.
    pub fn remove(&mut self, id: EntityId) -> Option<GameObject> {
        if let Some(obj) = self.objects.remove(&id) {
            let loc = obj.location_key();
            if let Some(ids) = self.by_location.get_mut(&loc) {
                ids.retain(|&i| i != id);
            }
            Some(obj)
        } else {
            None
        }
    }

    /// Replace an object with another.
    pub fn replace(&mut self, id: EntityId, new_def_id: u32) -> bool {
        if let Some(obj) = self.objects.get_mut(&id) {
            obj.def_id = new_def_id;
            true
        } else {
            false
        }
    }

    /// Get object count.
    pub fn count(&self) -> usize {
        self.objects.len()
    }

    /// Load default object definitions.
    pub fn load_defaults(&mut self) {
        // Trees
        self.register_definition(
            ObjectDef::new(0, "Tree")
                .with_description("A tree")
                .with_command("Chop")
                .with_size(1, 1),
        );

        self.register_definition(
            ObjectDef::new(1, "Oak tree")
                .with_description("An oak tree")
                .with_command("Chop")
                .with_size(1, 1),
        );

        self.register_definition(
            ObjectDef::new(2, "Willow tree")
                .with_description("A willow tree")
                .with_command("Chop")
                .with_size(1, 1),
        );

        // Rocks
        self.register_definition(
            ObjectDef::new(100, "Rocks")
                .with_description("A rocky outcrop")
                .with_command("Mine")
                .with_size(1, 1),
        );

        self.register_definition(
            ObjectDef::new(101, "Iron rocks")
                .with_description("Iron ore rocks")
                .with_command("Mine")
                .with_size(1, 1),
        );

        self.register_definition(
            ObjectDef::new(102, "Coal rocks")
                .with_description("Coal rocks")
                .with_command("Mine")
                .with_size(1, 1),
        );

        // Doors
        self.register_definition(
            ObjectDef::new(200, "Door")
                .with_description("A wooden door")
                .with_type(ObjectType::Boundary)
                .with_command("Open")
                .with_command("Close")
                .with_size(1, 1),
        );

        self.register_definition(
            ObjectDef::new(201, "Gate")
                .with_description("A gate")
                .with_type(ObjectType::Boundary)
                .with_command("Open")
                .with_command("Close")
                .with_size(1, 1),
        );

        // Furnaces and anvils
        self.register_definition(
            ObjectDef::new(300, "Furnace")
                .with_description("A furnace for smelting ore")
                .with_command("Use")
                .with_size(2, 2),
        );

        self.register_definition(
            ObjectDef::new(301, "Anvil")
                .with_description("An anvil for smithing")
                .with_command("Use")
                .with_size(1, 1),
        );

        // Banks
        self.register_definition(
            ObjectDef::new(400, "Bank booth")
                .with_description("A bank booth")
                .with_command("Use")
                .with_size(1, 1),
        );

        // Ladders and stairs
        self.register_definition(
            ObjectDef::new(500, "Ladder")
                .with_description("A ladder")
                .with_command("Climb-up")
                .with_command("Climb-down")
                .with_size(1, 1)
                .walkable(),
        );

        self.register_definition(
            ObjectDef::new(501, "Staircase")
                .with_description("A staircase")
                .with_command("Climb-up")
                .with_command("Climb-down")
                .with_size(2, 2),
        );

        info!("Loaded {} object definitions", self.definitions.len());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_game_object_creation() {
        let obj = GameObject::scenery(
            EntityId(1),
            0, // Tree
            Position { x: 100, y: 100, plane: 0 },
            ObjectDirection::North,
        );

        assert_eq!(obj.def_id, 0);
        assert!(obj.is_default());
        assert!(!obj.is_hidden());
    }

    #[test]
    fn test_object_state_change() {
        let mut obj = GameObject::scenery(
            EntityId(1),
            100, // Rock
            Position { x: 100, y: 100, plane: 0 },
            ObjectDirection::North,
        );

        // Deplete the rock
        obj.set_hidden(50, 0);
        assert!(obj.is_hidden());
        assert!(!obj.should_reset(49));
        assert!(obj.should_reset(50));

        // Reset
        obj.reset();
        assert!(obj.is_default());
    }

    #[test]
    fn test_object_manager() {
        let mut manager = GameObjectManager::new();
        manager.load_defaults();

        // Spawn a tree
        let id = manager.spawn_scenery(
            0, // Tree
            Position { x: 100, y: 100, plane: 0 },
            ObjectDirection::North,
        );

        assert_eq!(manager.count(), 1);
        assert!(manager.get(id).is_some());

        // Check location
        let objs = manager.at_location(100, 100);
        assert_eq!(objs.len(), 1);
    }
}
