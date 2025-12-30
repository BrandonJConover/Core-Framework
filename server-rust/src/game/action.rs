//! Action system for timed player activities.
//!
//! This module provides a framework for handling timed actions like
//! mining, fishing, cooking, and other skill-based activities.

use std::time::{Duration, Instant};
use serde::{Deserialize, Serialize};

/// Result of an action execution.
#[derive(Debug, Clone)]
pub enum ActionResult {
    /// Action completed successfully with optional rewards.
    Success { experience: u32, item_id: Option<u32>, amount: u32 },
    /// Action failed (e.g., rock depleted, fish escaped).
    Failed { reason: String },
    /// Action is still in progress.
    InProgress,
    /// Action was interrupted (e.g., player moved).
    Interrupted,
    /// Action requires more resources (e.g., no bait).
    RequiresResources { resource_id: u32 },
}

/// Types of actions that can be performed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ActionType {
    // Gathering skills
    Mining,
    Fishing,
    Woodcutting,

    // Production skills
    Cooking,
    Smithing,
    Crafting,
    Fletching,
    Runecrafting,
    Firemaking,

    // Combat actions
    Attacking,
    Blocking,

    // Other actions
    Thieving,
    Prayer,
    Herblaw,
    Eating,
    Drinking,
    Banking,
    Trading,
}

/// Configuration for an action.
#[derive(Debug, Clone)]
pub struct ActionConfig {
    pub action_type: ActionType,
    pub base_duration_ticks: u32,
    pub interruptible: bool,
    pub requires_tool: Option<u32>,
    pub skill_id: Option<u32>,
    pub level_required: u32,
    pub experience_reward: u32,
    pub success_rate: f32,
}

impl ActionConfig {
    pub fn new(action_type: ActionType) -> Self {
        Self {
            action_type,
            base_duration_ticks: 4,
            interruptible: true,
            requires_tool: None,
            skill_id: None,
            level_required: 1,
            experience_reward: 0,
            success_rate: 1.0,
        }
    }

    pub fn with_duration(mut self, ticks: u32) -> Self {
        self.base_duration_ticks = ticks;
        self
    }

    pub fn with_tool(mut self, tool_id: u32) -> Self {
        self.requires_tool = Some(tool_id);
        self
    }

    pub fn with_skill(mut self, skill_id: u32, level: u32) -> Self {
        self.skill_id = Some(skill_id);
        self.level_required = level;
        self
    }

    pub fn with_experience(mut self, exp: u32) -> Self {
        self.experience_reward = exp;
        self
    }

    pub fn with_success_rate(mut self, rate: f32) -> Self {
        self.success_rate = rate.clamp(0.0, 1.0);
        self
    }

    pub fn non_interruptible(mut self) -> Self {
        self.interruptible = false;
        self
    }
}

/// State of a currently running action.
#[derive(Debug, Clone)]
pub enum ActionState {
    Idle,
    Starting,
    Running {
        started_tick: u64,
        duration_ticks: u32
    },
    Completing,
    Cancelled,
}

/// A player's current action.
#[derive(Debug)]
pub struct Action {
    pub config: ActionConfig,
    pub state: ActionState,
    pub target_id: Option<u32>,
    pub target_position: Option<(u16, u16)>,
    pub repeat: bool,
    pub started_at: Instant,
}

impl Action {
    pub fn new(config: ActionConfig) -> Self {
        Self {
            config,
            state: ActionState::Idle,
            target_id: None,
            target_position: None,
            repeat: false,
            started_at: Instant::now(),
        }
    }

    pub fn with_target(mut self, target_id: u32) -> Self {
        self.target_id = Some(target_id);
        self
    }

    pub fn with_position(mut self, x: u16, y: u16) -> Self {
        self.target_position = Some((x, y));
        self
    }

    pub fn with_repeat(mut self) -> Self {
        self.repeat = true;
        self
    }

    /// Start the action.
    pub fn start(&mut self, current_tick: u64) {
        self.state = ActionState::Running {
            started_tick: current_tick,
            duration_ticks: self.config.base_duration_ticks,
        };
        self.started_at = Instant::now();
    }

    /// Cancel the action.
    pub fn cancel(&mut self) {
        self.state = ActionState::Cancelled;
    }

    /// Check if action is interruptible.
    pub fn is_interruptible(&self) -> bool {
        self.config.interruptible
    }

    /// Check if action is currently running.
    pub fn is_running(&self) -> bool {
        matches!(self.state, ActionState::Running { .. } | ActionState::Starting)
    }

    /// Check if action is complete based on current tick.
    pub fn is_complete(&self, current_tick: u64) -> bool {
        match self.state {
            ActionState::Running { started_tick, duration_ticks } => {
                current_tick >= started_tick + duration_ticks as u64
            }
            ActionState::Completing | ActionState::Cancelled => true,
            _ => false,
        }
    }

    /// Get remaining ticks until completion.
    pub fn remaining_ticks(&self, current_tick: u64) -> u32 {
        match self.state {
            ActionState::Running { started_tick, duration_ticks } => {
                let end_tick = started_tick + duration_ticks as u64;
                if current_tick >= end_tick {
                    0
                } else {
                    (end_tick - current_tick) as u32
                }
            }
            _ => 0,
        }
    }
}

/// Manager for player actions.
#[derive(Debug, Default)]
pub struct ActionQueue {
    current_action: Option<Action>,
    queued_action: Option<Action>,
}

impl ActionQueue {
    pub fn new() -> Self {
        Self {
            current_action: None,
            queued_action: None,
        }
    }

    /// Set a new action, potentially interrupting the current one.
    pub fn set_action(&mut self, action: Action) -> Result<(), &'static str> {
        if let Some(current) = &self.current_action {
            if !current.is_interruptible() {
                return Err("Current action cannot be interrupted");
            }
        }
        self.current_action = Some(action);
        Ok(())
    }

    /// Queue an action to run after the current one.
    pub fn queue_action(&mut self, action: Action) {
        self.queued_action = Some(action);
    }

    /// Get the current action.
    pub fn current(&self) -> Option<&Action> {
        self.current_action.as_ref()
    }

    /// Get a mutable reference to the current action.
    pub fn current_mut(&mut self) -> Option<&mut Action> {
        self.current_action.as_mut()
    }

    /// Cancel the current action if interruptible.
    pub fn cancel_current(&mut self) -> bool {
        if let Some(action) = &mut self.current_action {
            if action.is_interruptible() {
                action.cancel();
                self.current_action = None;
                return true;
            }
        }
        false
    }

    /// Process the action queue for a tick.
    pub fn tick(&mut self, current_tick: u64) -> Option<ActionResult> {
        let mut result = None;

        if let Some(action) = &self.current_action {
            if action.is_complete(current_tick) {
                // Action completed - calculate result
                result = Some(ActionResult::Success {
                    experience: action.config.experience_reward,
                    item_id: None,
                    amount: 1,
                });
            }
        }

        // If action completed, advance queue
        if result.is_some() {
            let repeat = self.current_action.as_ref().map(|a| a.repeat).unwrap_or(false);

            if repeat {
                // Restart the same action
                if let Some(action) = &mut self.current_action {
                    action.start(current_tick);
                }
            } else if self.queued_action.is_some() {
                // Move queued action to current
                self.current_action = self.queued_action.take();
                if let Some(action) = &mut self.current_action {
                    action.start(current_tick);
                }
            } else {
                // No more actions
                self.current_action = None;
            }
        }

        result
    }

    /// Check if any action is in progress.
    pub fn is_busy(&self) -> bool {
        self.current_action.as_ref().map(|a| a.is_running()).unwrap_or(false)
    }

    /// Clear all actions.
    pub fn clear(&mut self) {
        self.current_action = None;
        self.queued_action = None;
    }
}

/// Mining action configuration.
pub mod mining {
    use super::*;

    pub const TIN_ORE: u32 = 202;
    pub const COPPER_ORE: u32 = 203;
    pub const IRON_ORE: u32 = 204;
    pub const COAL: u32 = 205;
    pub const MITHRIL_ORE: u32 = 206;
    pub const ADAMANTITE_ORE: u32 = 207;
    pub const RUNITE_ORE: u32 = 208;

    pub fn create_mining_action(ore_type: u32, player_level: u32) -> Action {
        let (duration, exp, level_req) = match ore_type {
            TIN_ORE | COPPER_ORE => (4, 35, 1),
            IRON_ORE => (5, 70, 15),
            COAL => (6, 100, 30),
            MITHRIL_ORE => (7, 160, 55),
            ADAMANTITE_ORE => (8, 190, 70),
            RUNITE_ORE => (10, 250, 85),
            _ => (4, 35, 1),
        };

        let config = ActionConfig::new(ActionType::Mining)
            .with_duration(duration)
            .with_skill(14, level_req) // Mining skill ID
            .with_experience(exp)
            .with_success_rate(calculate_success_rate(player_level, level_req));

        Action::new(config).with_repeat()
    }

    fn calculate_success_rate(player_level: u32, required_level: u32) -> f32 {
        let diff = player_level.saturating_sub(required_level);
        (0.5 + (diff as f32 * 0.02)).min(0.95)
    }
}

/// Fishing action configuration.
pub mod fishing {
    use super::*;

    pub const SHRIMP: u32 = 349;
    pub const SARDINE: u32 = 350;
    pub const TROUT: u32 = 351;
    pub const SALMON: u32 = 352;
    pub const LOBSTER: u32 = 372;
    pub const SWORDFISH: u32 = 369;
    pub const SHARK: u32 = 545;

    pub fn create_fishing_action(fish_type: u32, player_level: u32) -> Action {
        let (duration, exp, level_req) = match fish_type {
            SHRIMP => (4, 20, 1),
            SARDINE => (4, 40, 5),
            TROUT => (5, 100, 20),
            SALMON => (5, 140, 30),
            LOBSTER => (6, 180, 40),
            SWORDFISH => (7, 200, 50),
            SHARK => (8, 220, 76),
            _ => (4, 20, 1),
        };

        let config = ActionConfig::new(ActionType::Fishing)
            .with_duration(duration)
            .with_skill(10, level_req) // Fishing skill ID
            .with_experience(exp)
            .with_success_rate(0.7);

        Action::new(config).with_repeat()
    }
}

/// Cooking action configuration.
pub mod cooking {
    use super::*;

    pub fn create_cooking_action(raw_item: u32, player_level: u32) -> Action {
        let (duration, exp, level_req, burn_level) = match raw_item {
            349 => (3, 60, 1, 34),   // Shrimp
            351 => (4, 140, 15, 50), // Trout
            372 => (4, 240, 40, 74), // Lobster
            369 => (4, 280, 45, 86), // Swordfish
            _ => (3, 60, 1, 99),
        };

        let burn_rate = if player_level >= burn_level {
            0.0
        } else {
            0.5 - ((player_level as f32 - level_req as f32) / (burn_level as f32 - level_req as f32) * 0.5)
        };

        let config = ActionConfig::new(ActionType::Cooking)
            .with_duration(duration)
            .with_skill(7, level_req) // Cooking skill ID
            .with_experience(exp)
            .with_success_rate(1.0 - burn_rate);

        Action::new(config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_action_creation() {
        let config = ActionConfig::new(ActionType::Mining)
            .with_duration(5)
            .with_experience(70);

        assert_eq!(config.base_duration_ticks, 5);
        assert_eq!(config.experience_reward, 70);
    }

    #[test]
    fn test_action_queue() {
        let mut queue = ActionQueue::new();
        assert!(!queue.is_busy());

        let config = ActionConfig::new(ActionType::Mining).with_duration(3);
        let mut action = Action::new(config);
        action.start(0);

        queue.set_action(action).unwrap();
        assert!(queue.is_busy());
    }

    #[test]
    fn test_action_completion() {
        let config = ActionConfig::new(ActionType::Mining).with_duration(3);
        let mut action = Action::new(config);

        action.start(0);
        assert!(!action.is_complete(0));
        assert!(!action.is_complete(2));
        assert!(action.is_complete(3));
        assert!(action.is_complete(5));
    }
}
