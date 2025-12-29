// Game logic module placeholder
// This would contain game-specific logic like player management, world state, etc.

pub struct GameWorld {
    pub name: String,
    pub max_players: u32,
}

impl GameWorld {
    pub fn new(name: String, max_players: u32) -> Self {
        Self { name, max_players }
    }
}
