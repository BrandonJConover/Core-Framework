//! Game event and minigame system.
//! Handles scheduled events, holiday drops, and minigame instances.

use std::collections::{HashMap, HashSet};
use tracing::{debug, info, warn};

use super::entity::Position;
use super::item::ItemId;

/// Event types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EventType {
    /// Holiday drop event (items spawn in world).
    HolidayDrop,
    /// Double experience event.
    DoubleXp,
    /// PvP tournament.
    Tournament,
    /// Treasure hunt.
    TreasureHunt,
    /// Boss spawn event.
    BossSpawn,
    /// Community gathering.
    CommunityEvent,
    /// Custom server event.
    Custom,
}

/// Event state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventState {
    /// Scheduled but not yet started.
    Scheduled,
    /// Currently active.
    Active,
    /// Event has ended.
    Ended,
    /// Event was cancelled.
    Cancelled,
}

/// A game event definition.
#[derive(Debug, Clone)]
pub struct GameEvent {
    /// Unique event ID.
    pub id: u32,
    /// Event name.
    pub name: String,
    /// Event type.
    pub event_type: EventType,
    /// Current state.
    pub state: EventState,
    /// When the event starts (game tick).
    pub start_tick: u64,
    /// When the event ends (game tick).
    pub end_tick: u64,
    /// Event-specific data.
    pub data: EventData,
    /// Participating player IDs.
    pub participants: HashSet<u64>,
    /// Announcement message.
    pub announcement: String,
}

impl GameEvent {
    /// Create a new event.
    pub fn new(
        id: u32,
        name: &str,
        event_type: EventType,
        start_tick: u64,
        duration_ticks: u64,
    ) -> Self {
        Self {
            id,
            name: name.to_string(),
            event_type,
            state: EventState::Scheduled,
            start_tick,
            end_tick: start_tick + duration_ticks,
            data: EventData::None,
            participants: HashSet::new(),
            announcement: String::new(),
        }
    }

    /// Set announcement message.
    pub fn with_announcement(mut self, msg: &str) -> Self {
        self.announcement = msg.to_string();
        self
    }

    /// Set event data.
    pub fn with_data(mut self, data: EventData) -> Self {
        self.data = data;
        self
    }

    /// Check if event should start.
    pub fn should_start(&self, current_tick: u64) -> bool {
        self.state == EventState::Scheduled && current_tick >= self.start_tick
    }

    /// Check if event should end.
    pub fn should_end(&self, current_tick: u64) -> bool {
        self.state == EventState::Active && current_tick >= self.end_tick
    }

    /// Start the event.
    pub fn start(&mut self) {
        self.state = EventState::Active;
        info!("Event '{}' started", self.name);
    }

    /// End the event.
    pub fn end(&mut self) {
        self.state = EventState::Ended;
        info!("Event '{}' ended", self.name);
    }

    /// Cancel the event.
    pub fn cancel(&mut self) {
        self.state = EventState::Cancelled;
        info!("Event '{}' cancelled", self.name);
    }

    /// Add a participant.
    pub fn add_participant(&mut self, player_id: u64) {
        self.participants.insert(player_id);
    }

    /// Remove a participant.
    pub fn remove_participant(&mut self, player_id: u64) {
        self.participants.remove(&player_id);
    }

    /// Get participant count.
    pub fn participant_count(&self) -> usize {
        self.participants.len()
    }

    /// Check if player is participating.
    pub fn is_participant(&self, player_id: u64) -> bool {
        self.participants.contains(&player_id)
    }

    /// Check if event is active.
    pub fn is_active(&self) -> bool {
        self.state == EventState::Active
    }
}

/// Event-specific data.
#[derive(Debug, Clone)]
pub enum EventData {
    /// No additional data.
    None,
    /// Holiday drop data.
    HolidayDrop {
        items: Vec<ItemId>,
        locations: Vec<Position>,
        interval_ticks: u32,
    },
    /// Double XP data.
    DoubleXp {
        multiplier: f32,
        skills: Option<Vec<u8>>, // None = all skills
    },
    /// Tournament data.
    Tournament {
        bracket: Vec<(u64, u64)>, // (player1, player2) matchups
        current_round: u32,
        prize_pool: Vec<ItemId>,
    },
    /// Boss spawn data.
    BossSpawn {
        npc_id: u32,
        spawn_location: Position,
        health_multiplier: f32,
    },
    /// Custom event data.
    Custom { key: String, value: String },
}

/// Holiday drop configuration.
#[derive(Debug, Clone)]
pub struct HolidayDropConfig {
    /// Items to drop.
    pub items: Vec<ItemId>,
    /// Possible drop locations.
    pub locations: Vec<Position>,
    /// Ticks between drops.
    pub interval_ticks: u32,
    /// Ticks since last drop.
    pub last_drop_tick: u64,
}

impl HolidayDropConfig {
    /// Create a new holiday drop config.
    pub fn new(items: Vec<ItemId>, locations: Vec<Position>, interval_ticks: u32) -> Self {
        Self {
            items,
            locations,
            interval_ticks,
            last_drop_tick: 0,
        }
    }

    /// Check if should drop.
    pub fn should_drop(&self, current_tick: u64) -> bool {
        current_tick >= self.last_drop_tick + self.interval_ticks as u64
    }

    /// Get next drop item (random).
    pub fn get_random_item(&self) -> Option<ItemId> {
        if self.items.is_empty() {
            return None;
        }
        let idx = rand::random::<usize>() % self.items.len();
        Some(self.items[idx])
    }

    /// Get random location.
    pub fn get_random_location(&self) -> Option<Position> {
        if self.locations.is_empty() {
            return None;
        }
        let idx = rand::random::<usize>() % self.locations.len();
        Some(self.locations[idx])
    }
}

/// Minigame types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MinigameType {
    /// Fight Pits style last-man-standing.
    FightPits,
    /// Fishing competition.
    FishingCompetition,
    /// Party room balloon drop.
    PartyRoom,
    /// Clan wars.
    ClanWars,
    /// Custom minigame.
    Custom,
}

/// Minigame state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MinigameState {
    /// Waiting for players.
    Waiting,
    /// Countdown to start.
    Starting,
    /// Game in progress.
    InProgress,
    /// Game finished.
    Finished,
}

/// A minigame instance.
#[derive(Debug, Clone)]
pub struct Minigame {
    /// Instance ID.
    pub id: u32,
    /// Minigame type.
    pub game_type: MinigameType,
    /// Current state.
    pub state: MinigameState,
    /// Players in the minigame.
    pub players: HashSet<u64>,
    /// Minimum players required.
    pub min_players: usize,
    /// Maximum players allowed.
    pub max_players: usize,
    /// Game-specific score/data.
    pub scores: HashMap<u64, i32>,
    /// Start tick (when game began).
    pub start_tick: Option<u64>,
    /// Time limit in ticks (None = no limit).
    pub time_limit: Option<u64>,
}

impl Minigame {
    /// Create a new minigame.
    pub fn new(id: u32, game_type: MinigameType, min_players: usize, max_players: usize) -> Self {
        Self {
            id,
            game_type,
            state: MinigameState::Waiting,
            players: HashSet::new(),
            min_players,
            max_players,
            scores: HashMap::new(),
            start_tick: None,
            time_limit: None,
        }
    }

    /// Add a player to the minigame.
    pub fn join(&mut self, player_id: u64) -> bool {
        if self.players.len() >= self.max_players {
            return false;
        }
        if self.state != MinigameState::Waiting && self.state != MinigameState::Starting {
            return false;
        }
        self.players.insert(player_id);
        self.scores.insert(player_id, 0);
        debug!("Player {} joined minigame {}", player_id, self.id);
        true
    }

    /// Remove a player from the minigame.
    pub fn leave(&mut self, player_id: u64) {
        self.players.remove(&player_id);
        self.scores.remove(&player_id);
        debug!("Player {} left minigame {}", player_id, self.id);
    }

    /// Check if can start (enough players).
    pub fn can_start(&self) -> bool {
        self.players.len() >= self.min_players
    }

    /// Start countdown.
    pub fn start_countdown(&mut self) {
        if self.can_start() {
            self.state = MinigameState::Starting;
        }
    }

    /// Begin the game.
    pub fn begin(&mut self, current_tick: u64) {
        self.state = MinigameState::InProgress;
        self.start_tick = Some(current_tick);
        info!(
            "Minigame {} started with {} players",
            self.id,
            self.players.len()
        );
    }

    /// Update a player's score.
    pub fn add_score(&mut self, player_id: u64, points: i32) {
        if let Some(score) = self.scores.get_mut(&player_id) {
            *score += points;
        }
    }

    /// Get player's score.
    pub fn get_score(&self, player_id: u64) -> i32 {
        *self.scores.get(&player_id).unwrap_or(&0)
    }

    /// Get winner (highest score).
    pub fn get_winner(&self) -> Option<u64> {
        self.scores
            .iter()
            .max_by_key(|(_, score)| *score)
            .map(|(id, _)| *id)
    }

    /// End the game.
    pub fn finish(&mut self) {
        self.state = MinigameState::Finished;
        info!("Minigame {} finished", self.id);
    }

    /// Check if time limit exceeded.
    pub fn is_time_up(&self, current_tick: u64) -> bool {
        if let (Some(start), Some(limit)) = (self.start_tick, self.time_limit) {
            current_tick >= start + limit
        } else {
            false
        }
    }

    /// Get remaining players count.
    pub fn player_count(&self) -> usize {
        self.players.len()
    }
}

/// Manager for events and minigames.
#[derive(Debug, Default)]
pub struct EventManager {
    /// Active and scheduled events.
    events: HashMap<u32, GameEvent>,
    /// Active minigames.
    minigames: HashMap<u32, Minigame>,
    /// Next event ID.
    next_event_id: u32,
    /// Next minigame ID.
    next_minigame_id: u32,
    /// Current game tick.
    current_tick: u64,
}

impl EventManager {
    /// Create a new event manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Process a game tick.
    pub fn tick(&mut self) {
        self.current_tick += 1;

        // Process events
        let events_to_start: Vec<u32> = self
            .events
            .iter()
            .filter(|(_, e)| e.should_start(self.current_tick))
            .map(|(id, _)| *id)
            .collect();

        for id in events_to_start {
            if let Some(event) = self.events.get_mut(&id) {
                event.start();
            }
        }

        let events_to_end: Vec<u32> = self
            .events
            .iter()
            .filter(|(_, e)| e.should_end(self.current_tick))
            .map(|(id, _)| *id)
            .collect();

        for id in events_to_end {
            if let Some(event) = self.events.get_mut(&id) {
                event.end();
            }
        }

        // Process minigames
        let minigames_to_finish: Vec<u32> = self
            .minigames
            .iter()
            .filter(|(_, m)| {
                m.state == MinigameState::InProgress
                    && (m.is_time_up(self.current_tick) || m.player_count() <= 1)
            })
            .map(|(id, _)| *id)
            .collect();

        for id in minigames_to_finish {
            if let Some(game) = self.minigames.get_mut(&id) {
                game.finish();
            }
        }
    }

    /// Schedule a new event.
    pub fn schedule_event(
        &mut self,
        name: &str,
        event_type: EventType,
        delay_ticks: u64,
        duration_ticks: u64,
    ) -> u32 {
        self.next_event_id += 1;
        let id = self.next_event_id;

        let event = GameEvent::new(
            id,
            name,
            event_type,
            self.current_tick + delay_ticks,
            duration_ticks,
        );

        self.events.insert(id, event);
        info!("Scheduled event '{}' (ID: {})", name, id);
        id
    }

    /// Get an event by ID.
    pub fn get_event(&self, id: u32) -> Option<&GameEvent> {
        self.events.get(&id)
    }

    /// Get mutable event by ID.
    pub fn get_event_mut(&mut self, id: u32) -> Option<&mut GameEvent> {
        self.events.get_mut(&id)
    }

    /// Get all active events.
    pub fn active_events(&self) -> Vec<&GameEvent> {
        self.events.values().filter(|e| e.is_active()).collect()
    }

    /// Cancel an event.
    pub fn cancel_event(&mut self, id: u32) {
        if let Some(event) = self.events.get_mut(&id) {
            event.cancel();
        }
    }

    /// Create a new minigame instance.
    pub fn create_minigame(
        &mut self,
        game_type: MinigameType,
        min_players: usize,
        max_players: usize,
    ) -> u32 {
        self.next_minigame_id += 1;
        let id = self.next_minigame_id;

        let game = Minigame::new(id, game_type, min_players, max_players);
        self.minigames.insert(id, game);
        info!("Created minigame instance (ID: {})", id);
        id
    }

    /// Get a minigame by ID.
    pub fn get_minigame(&self, id: u32) -> Option<&Minigame> {
        self.minigames.get(&id)
    }

    /// Get mutable minigame by ID.
    pub fn get_minigame_mut(&mut self, id: u32) -> Option<&mut Minigame> {
        self.minigames.get_mut(&id)
    }

    /// Remove finished minigames.
    pub fn cleanup_finished(&mut self) {
        self.minigames
            .retain(|_, game| game.state != MinigameState::Finished);
        self.events.retain(|_, event| {
            event.state != EventState::Ended && event.state != EventState::Cancelled
        });
    }

    /// Check if double XP is active.
    pub fn is_double_xp_active(&self) -> Option<f32> {
        for event in self.events.values() {
            if event.is_active() && event.event_type == EventType::DoubleXp {
                if let EventData::DoubleXp { multiplier, .. } = &event.data {
                    return Some(*multiplier);
                }
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_lifecycle() {
        let mut event = GameEvent::new(1, "Test Event", EventType::DoubleXp, 10, 100);

        assert_eq!(event.state, EventState::Scheduled);
        assert!(!event.should_start(5));
        assert!(event.should_start(10));

        event.start();
        assert!(event.is_active());

        assert!(!event.should_end(50));
        assert!(event.should_end(110));

        event.end();
        assert_eq!(event.state, EventState::Ended);
    }

    #[test]
    fn test_minigame() {
        let mut game = Minigame::new(1, MinigameType::FightPits, 2, 10);

        assert!(game.join(1));
        assert!(game.join(2));
        assert!(game.can_start());

        game.begin(0);
        assert_eq!(game.state, MinigameState::InProgress);

        game.add_score(1, 5);
        game.add_score(2, 3);

        assert_eq!(game.get_score(1), 5);
        assert_eq!(game.get_winner(), Some(1));
    }

    #[test]
    fn test_event_manager() {
        let mut manager = EventManager::new();

        let id = manager.schedule_event("Double XP Weekend", EventType::DoubleXp, 0, 100);

        // Should start immediately
        manager.tick();

        let event = manager.get_event(id).unwrap();
        assert!(event.is_active());

        // Fast forward
        for _ in 0..100 {
            manager.tick();
        }

        let event = manager.get_event(id).unwrap();
        assert_eq!(event.state, EventState::Ended);
    }
}
