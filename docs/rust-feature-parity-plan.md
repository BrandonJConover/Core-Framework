# Rust Server Feature Parity Plan

## Current State Summary

The Rust server (~71 files, ~24,700 lines) has **strong foundations** — networking, protocol codec, database, security, and data structures for most game systems are in place. What's missing is the **integration layer**: the game loop, packet dispatch, entity update pipeline, world loading, and the wiring that turns standalone modules into a running game server.

This plan is organized into sequential phases. Each phase builds on the previous and ends with a testable milestone.

---

## Phase 1 — Game Loop & Entity Update Pipeline

**Goal:** A server that boots, ticks at 640ms, and can process a basic login → world entry → logout cycle.

### 1.1 Game Tick Loop
- Implement the core tick loop in `main.rs` / a new `game/game_loop.rs`
- 640ms tick cycle (configurable via `ServerConfig`)
- Per-tick phases: process incoming packets → run events → update game state → send outgoing packets
- Track tick number, tick duration metrics, and overflow warnings
- Wire into Tokio runtime with `tokio::time::interval`

### 1.2 Packet Dispatch System
- Create `network/packet_dispatch.rs` — maps `OpcodeIn` variants to handler functions
- Implement a `PacketHandler` trait with `fn handle(&self, session: &mut Session, packet: &Packet, world: &mut World)`
- Register all handlers in a dispatch table (HashMap<OpcodeIn, Box<dyn PacketHandler>>)
- Wire TCP/QUIC accept loops to push packets into a per-session inbound queue
- Drain inbound queues during the tick's "process packets" phase

### 1.3 Login / Logout Flow
- Implement `LoginHandler`: parse login packet (opcode 0, reconnect flag, client version, username, password, UID)
- Validate credentials against database (password hash verify)
- Create `Session` → assign `Player` → add to `World`
- Send login response byte, then `WorldInfo`, `PlayerStats`, `PlayerInventory`, `PlayerEquipment`, `FriendList`, `IgnoreList`, `QuestList`, `PlayerSettings`
- Implement `LogoutHandler` / `LogoutRequestHandler`: save player, remove from world, close session
- Handle reconnection flag

### 1.4 Entity Update Pipeline (GameStateUpdater)
- Implement `game/state_updater.rs` — the per-tick outbound update generator
- Update order: Players → Player Appearances → NPCs → NPC Appearances → GameObjects → WallObjects → GroundItems
- `PlayerPositionUpdate` packet: bit-packed coordinate encoding matching Java's `PayloadCustomGenerator`
- `NpcPositionUpdate` packet: bit-packed NPC coordinate encoding
- `PlayerAppearance` packet: send appearance data for players entering view
- Region-based visibility: only send updates for entities within the player's view area
- Known-player tracking per session (which entities the client already knows about)

### 1.5 Heartbeat & Keepalive
- Handle `Ping` (opcode 5) → respond with keepalive
- Session timeout tracking: disconnect after 5 minutes idle
- Idle warning message before timeout

**Milestone:** Can connect with a real client, see "Welcome to OpenRSC", stand in the world, and log out cleanly.

---

## Phase 2 — World, Movement & Collision

**Goal:** Players can walk around the world, see each other, and interact with the map.

### 2.1 World Data Loading
- Load tile/collision data from the existing game data files
- Implement `world/region.rs` — 64×64 tile regions with collision flags
- Load NPC spawn definitions from database/config
- Load game object spawn locations
- Load ground item spawn locations
- Load shop definitions

### 2.2 Collision System
- Port the 32 `CollisionFlag` types from Java
- `TileValue` struct with elevation, collision, and overlay data
- Collision checking: `can_walk(from, to)` considering walls, objects, water, etc.
- Diagonal movement blocking rules

### 2.3 Walking Queue & Movement
- Implement `game/walking_queue.rs` — per-entity step queue
- `WalkToPoint` handler (opcode 16): parse destination, compute path, enqueue steps
- `WalkToEntity` handler (opcode 17): path to entity, follow until adjacent
- Process one step per tick from the walking queue
- Movement cancels current action (combat retreat timer exception)
- Coordinate boundary validation

### 2.4 Player Follow
- `FollowPlayer` handler (opcode 41): set follow target
- Per-tick follow logic: recalculate path to target each tick
- Stop following on logout, teleport, or manual movement

### 2.5 Pathfinding Integration
- Wire the existing A* implementation into `WalkToEntity` for NPC/object interaction
- Path validation against collision map
- Max path length limits (prevent abuse)

### 2.6 Region-Based Entity Management
- Track which region each entity is in
- On region change, notify adjacent regions
- View area calculation for update pipeline (Phase 1.4)
- Efficient entity lookup by region for proximity checks

**Milestone:** Multiple players can connect, walk around, see each other moving, and collide with walls/objects correctly.

---

## Phase 3 — Chat, Social & Commands

**Goal:** Players can communicate and use basic commands.

### 3.1 Public Chat
- `ChatHandler` (opcode 30): parse message, sanitize, broadcast to nearby players
- Distance-limited chat (within view area)
- Message rate limiting
- Chat filtering / profanity filter

### 3.2 Private Messaging
- `PrivateMessage` handler (opcode 31): route to target player
- Online status checking
- Privacy settings respect (block PM from non-friends)
- PM logging to database

### 3.3 Friends & Ignore
- `AddFriend` / `RemoveFriend` / `AddIgnore` / `RemoveIgnore` handlers (opcodes 32-35)
- `FriendList` / `FriendUpdate` / `IgnoreList` outbound packets
- Online status notifications when friends log in/out
- Persist to database

### 3.4 Command System
- `CommandHandler` (opcode 200): parse `::command arg1 arg2` format
- Player commands: `::online`, `::wilderness`, etc.
- Staff permission levels: Moderator, Administrator, Developer
- Admin commands: teleport, spawn item, kick, ban, mute, etc.
- Command logging (database + optionally Discord)

### 3.5 Privacy Settings
- `PrivacySettingHandler` (opcode 141): block chat, PM, trade, duel
- `GameSettingHandler` (opcode 140): camera, sound, mouse button preferences
- Persist settings to database

### 3.6 Report Abuse
- `ReportHandler`: log player reports with reason, target, timestamp
- Store in database for staff review

**Milestone:** Players can chat, PM friends, use commands, and manage their social settings.

---

## Phase 4 — Combat System Integration

**Goal:** Full melee, ranged, and magic combat works between players and NPCs.

### 4.1 Combat Event Loop
- Create `game/combat_event.rs` — the actual combat tick processor
- Combat round: every 3 ticks (1920ms) for melee
- Attacker hits → calculate damage → apply damage → check death → award XP → next round
- Combat interlock: both participants locked until combat ends or retreat timer expires
- Retreat timer: 3 ticks after entering combat before you can walk away

### 4.2 Melee Combat
- `AttackPlayer` handler (opcode 40): initiate PvP
- `AttackNpc` handler (opcode 50): initiate PvE
- Wire existing `CombatCalculator` (max hit, hit chance, damage roll)
- Combat style bonuses (Controlled/Aggressive/Accurate/Defensive)
- `CombatStyleHandler`: switch style during combat
- `DamageUpdate` outbound: show hit splat on target
- XP distribution per style using existing `CombatExperience`

### 4.3 Ranged Combat
- Wire existing `ranged.rs` bow/arrow definitions
- Ranged attack events with projectile delay
- Ammunition consumption
- Ranged accuracy and strength calculations
- `BallProjectileEvent` / visual projectile packets

### 4.4 Magic Combat
- Wire existing `magic.rs` spell definitions
- `SpellHandler`: cast on NPC, player, self, inventory, ground, object
- Rune cost deduction from inventory
- Spell success/failure based on magic level
- Combat spells: damage, stat drain (Confuse, Weaken, Curse)
- Utility spells: alchemy, telegrab, superheat, enchant, bones to bananas
- Teleport spells: Varrock, Lumbridge, Falador, Camelot, Ardougne, Watchtower
- God spells: Saradomin Strike, Flames of Zamorak, Claws of Guthix
- Staff bonuses (elemental staves reduce rune costs)

### 4.5 Prayer Integration
- Wire existing `prayer.rs` into combat
- `PrayerHandler` (opcodes 90-91): activate/deactivate
- Prayer drain event: drain points per tick based on active prayers
- Combat bonuses from prayers (attack, strength, defense boosts)
- Special prayers: Protect Items, Paralyze Monster, Protect from Missiles
- Boss-specific prayer drains (Elvarg, KBD, Salarin, Shadow Spider)

### 4.6 Death & Respawn
- Player death: drop items (keep top 3, or 4 with Protect Items)
- `DeathScreen` outbound packet
- Respawn at Lumbridge (or configured respawn point)
- NPC death: trigger drop table, despawn, start respawn timer
- Death logging to database
- Skull system for PvP: lose all items on death if skulled

### 4.7 Poison System
- Wire existing `status_effect.rs` poison types
- Poison damage ticks (every ~20 ticks)
- NPC poison application on hit
- Poison cure via antipoison potions
- Poison wear-off over time

### 4.8 NPC Aggression
- Aggro radius checking per tick
- NPC attacks player if: NPC is aggressive, player is in range, player combat level < NPC level × 2
- Multi-combat zone rules
- Wilderness aggression rules

**Milestone:** Can fight NPCs and players with melee/ranged/magic, use prayers, die, respawn, and deal with poison.

---

## Phase 5 — Skills & Actions

**Goal:** All gathering, processing, and utility skills are playable.

### 5.1 Action System Integration
- Wire existing `action.rs` into the game loop
- Actions are interruptible (movement, combat, logout cancel current action)
- Action timing: tick-based delays per action type
- Tool requirement checking
- Resource requirement checking
- Success rate calculations

### 5.2 Mining
- Wire `mining.rs` definitions into object interaction handlers
- `UseObject` handler for rocks: check pickaxe, level, calculate success
- Ore extraction → add to inventory → deplete rock → start respawn timer
- Prospecting (examine rock)
- Experience award on success

### 5.3 Woodcutting
- Wire `woodcutting.rs` into object interaction
- Axe requirement checking
- Tree depletion and respawn
- Log types by tree type

### 5.4 Fishing
- Wire `fishing.rs` into NPC interaction (fishing spots are NPCs)
- Rod/net/harpoon/cage + bait requirements
- Fish by spot type
- Bait consumption

### 5.5 Cooking
- Wire `cooking.rs` into item-on-object interaction (fire, range)
- Cook/burn probability based on level
- Raw → cooked or burnt

### 5.6 Smithing
- Smelting: item-on-object (furnace) → ore to bars
- Smithing: item-on-object (anvil) → bars to equipment
- Wire `smithing.rs` bar/item definitions

### 5.7 Crafting
- Wire `crafting.rs` for leather, jewelry, pottery
- Item-on-item interactions
- Tool requirements (needle, chisel, etc.)

### 5.8 Fletching
- Wire `fletching.rs` for bow/arrow making
- Knife + log → unstrung bow
- Bow string + unstrung → strung bow
- Feather + shaft + arrowhead → arrows

### 5.9 Firemaking
- Wire `firemaking.rs` — tinderbox + logs → fire on ground
- Fire object spawns temporarily on tile
- Level requirements per log type

### 5.10 Herblore
- Wire `herblore.rs` — identify herbs, mix potions
- Unidentified herb → identified herb (level check)
- Herb + secondary ingredient → potion
- Potion effects: stat boosts, cures, etc.

### 5.11 Runecrafting
- Wire `runecrafting.rs` — essence + altar → runes
- Multiple rune production at higher levels
- Altar locations and talisman/tiara requirements

### 5.12 Thieving
- Wire `thieving.rs` — pickpocket NPCs, steal from stalls
- Success/failure based on level
- Stun on failure (damage + freeze)
- Guard aggression on failure

### 5.13 Agility
- Wire `agility.rs` — obstacle interaction
- Failure mechanics (fall damage)
- Course lap tracking
- Shortcut unlocks by level

### 5.14 Harvesting, Carpentry, Tailoring (Custom Skills)
- These are OpenRSC-custom skills not in original RSC
- Implement data definitions and handlers
- Harvesting: plant seeds → grow → harvest crops
- Carpentry: woodworking items from logs
- Tailoring: cloth-based armor/cosmetics

**Milestone:** All 27 skills are functional. Players can train, gain XP, and level up.

---

## Phase 6 — NPCs, Shops, Banking & Trading

**Goal:** Full NPC interaction, economy systems, and player-to-player trading.

### 6.1 NPC Dialogue System
- Wire existing `dialogue.rs` into `TalkToNpc` handler (opcode 51)
- Dialogue tree traversal: NPC say → player choices → conditions → actions
- `NpcDialogue` / `OptionDialogue` outbound packets
- `MenuReplyHandler`: player selects dialogue option
- Conditional branching (quest stage, items, skills)
- Dialogue actions: give/take items, start quests, open shops

### 6.2 NPC Behavior & AI
- Wire `npc.rs` into the game loop
- NPC wandering within spawn radius
- NPC combat AI: attack back when attacked, pursue fleeing players
- NPC respawn after death (configurable timer)
- NPC interaction types: talk, attack, use item, cast spell, secondary command

### 6.3 Shop System
- Wire `shop.rs` into NPC dialogue → "open shop"
- `OpenShop` outbound: send shop inventory and prices
- `ShopBuy` / `ShopSell` handlers (opcodes 130-133)
- Dynamic pricing based on stock levels
- Shop restock event (timed restocking)
- General store vs. specialist store behavior

### 6.4 Banking
- Wire `bank.rs` into object interaction (bank booth) and NPC dialogue
- `OpenBank` outbound: send full bank contents
- `BankDeposit` / `BankWithdraw` handlers (opcodes 120-123)
- `BankDepositAll` from inventory and equipment
- Bank capacity: 192 (members), 48 (F2P)
- Bank PIN system: set, verify, change, remove
- Bank presets: save/load equipment+inventory loadouts

### 6.5 Player Trading
- Wire `trade.rs` into `TradeRequest` handler (opcode 42)
- Two-stage confirmation: offer items → confirm → final confirm
- `OpenTrade` / `TradeOtherItems` outbound packets
- Item verification (can't offer items you don't have)
- Trade decline and cancellation
- Max 12 items per offer

### 6.6 Dueling
- Wire `duel.rs` into `DuelRequest` handler (opcode 43)
- Duel rules setup (allow prayer, magic, melee, ranged, items)
- Item stakes
- Duel arena location verification
- Win/loss outcome and reward distribution

### 6.7 Market / Auction House
- New `game/market.rs` — player-driven marketplace
- List items for sale with asking price
- Browse/search listings
- Buy listings → transfer items + gold
- Listing expiration and return
- Database persistence for listings

### 6.8 Ground Item Interaction
- `GroundItemTake` handler (opcode 70): walk to item, pick up
- `ItemDrop` handler (opcode 71): drop from inventory to ground
- `UseItemOnGroundItem` handler (opcode 72)
- Private visibility phase → public after timer → despawn after expiration

**Milestone:** Full economy loop works — kill NPCs for loot, sell to shops, trade with players, bank items, buy from auction house.

---

## Phase 7 — Quests & Content

**Goal:** Quest system is functional and supports the full quest catalog.

### 7.1 Quest Engine
- Wire `quest.rs` into the game loop
- Quest state machine: Not Started (0) → In Progress (1-254) → Completed (-1)
- Requirement checking: skill levels, quest completions, items, combat level
- Reward distribution: XP, quest points, items, coins, area access
- Quest journal UI updates

### 7.2 Quest Plugin Architecture
- Since Rust can't do Java-style runtime class loading, implement quest scripts as:
  - Option A: Compiled Rust modules registered at startup (fastest, requires recompile)
  - Option B: Lua/Rhai scripting engine for quest logic (hot-reloadable, slower)
  - Option C: Data-driven quest definitions in TOML/JSON with a generic quest executor
- Recommend **Option A for core quests + Option C for simple fetch/kill quests**
- Quest trigger system: talk to NPC, use item, enter area, kill NPC, etc.

### 7.3 Quest Content (52 Quests)
- Port each quest's logic from the Java plugin system
- Priority order: tutorial quests first, then short quests, then long quest chains
- Batch 1 (beginner): Cook's Assistant, Sheep Shearer, Doric's Quest, Imp Catcher, Romeo & Juliet, Goblin Diplomacy, Ernest the Chicken, Rune Mysteries
- Batch 2 (intermediate): Vampire Slayer, Demon Slayer, The Restless Ghost, Pirate's Treasure, Prince Ali Rescue, Shield of Arrav, The Knight's Sword, Witch's Potion, Witch's House
- Batch 3 (advanced): Dragon Slayer, Lost City, Hero's Quest, Underground Pass, Legends' Quest, etc.
- Remaining quests in subsequent batches

### 7.4 Achievement System Integration
- Wire `achievement.rs` event tracking into the game loop
- Achievement triggers: NPC kills, skill levels, quest completions, item pickups, area visits
- Progress tracking and notification
- Reward distribution on completion
- Achievement UI updates

### 7.5 Dialogue Content
- Port NPC dialogue trees from Java plugins
- Shopkeeper dialogues
- Quest NPC dialogues
- Random NPC flavor text

**Milestone:** Players can complete quests, earn quest points, unlock achievements, and interact with NPCs through full dialogue trees.

---

## Phase 8 — Special Mechanics & Minigames

**Goal:** All remaining game mechanics and content systems.

### 8.1 Appearance System
- `PlayerAppearanceUpdater` handler: change hair, body, legs, skin color
- Appearance screen on first login (character creation)
- Appearance update broadcasting to nearby players

### 8.2 Fatigue & Sleep
- Fatigue accumulation during skilling (max 150,000)
- At max fatigue, no more XP gain
- Sleep mechanic: sleeping bag / bed → sleep screen → enter CAPTCHA word → fatigue reset
- `SleepHandler`: CAPTCHA verification
- Sleep screen outbound packets

### 8.3 Ironman Mode
- Mode selection at character creation: Normal, Ironman, Hardcore Ironman, Ultimate Ironman
- Trading restrictions (can't trade with other players)
- Shop restrictions
- Hardcore: permadeath (revert to regular ironman on death)
- Ultimate: no banking

### 8.4 Item Use Handlers
- `ItemUseOnItem` handler (opcode 83): crafting, fletching, herblore combinations
- `ItemUseOnObject` handler (opcode 61): cooking on fire, smelting at furnace
- `ItemUseOnNpc` handler (opcode 52): quest items, feeding, etc.
- `ItemUseOnPlayer` handler: Christmas crackers, etc.
- `ItemCommand` handler: item-specific actions (eat food, drink potions, read scrolls)

### 8.5 Food & Potions
- Eating food: heal HP by food-specific amount, 3-tick eat delay
- Drinking potions: apply stat boost/effect, 3-tick drink delay
- Potion effects: attack boost, strength boost, defense boost, prayer restore, antipoison, etc.

### 8.6 Wilderness
- Wilderness level calculation from Y coordinate (existing in entity.rs)
- PvP combat level range based on wilderness level
- Skull system: attacking another player skulls you for 20 minutes
- Drop all items on death if skulled
- Wilderness boundary warnings

### 8.7 Tutorial Island
- Tutorial progression handler
- Skip tutorial option
- Tutorial-only area restrictions
- Tutorial NPC interactions

### 8.8 Minigames
- **Fishing Trawler**: cooperative boat minigame, crew coordination, fishing rewards
- **Combat Odyssey**: combat challenge tiers, task progression, XP rewards
- Minigame registration system
- Minigame-specific areas and rules

### 8.9 Daily/Hourly Events
- `DailyEvent`: daily reset tasks
- `HourlyEvent`: hourly maintenance
- `ShopRestockEvent`: periodic shop restocking
- `StatRestorationEvent`: gradual stat recovery
- `HolidayDropEvent`: special holiday item drops

### 8.10 NPC Kill Tracking
- Per-NPC kill count stored in database
- Kill count display
- Kill-count-gated content (if applicable)

**Milestone:** All special mechanics work — ironman mode, fatigue/sleep, wilderness PvP skulling, food/potions, tutorial, minigames.

---

## Phase 9 — Plugin / Content Extension System

**Goal:** Extendable content system so new game content can be added without modifying core server code.

### 9.1 Plugin Trait System
- Define a `Plugin` trait with lifecycle hooks: `on_load()`, `on_unload()`, `on_tick()`
- Define trigger traits matching Java's 52 trigger types:
  - `OnTalkNpc`, `OnAttackNpc`, `OnKillNpc`, `OnUseObject`, `OnUseItem`, `OnCommand`, etc.
- Plugin registry: HashMap<TriggerType, Vec<Box<dyn PluginTrigger>>>
- Plugin priority ordering

### 9.2 Content Script Engine (Optional)
- Embed Rhai or Lua scripting engine for hot-reloadable content
- Script bindings for: player state, inventory, dialogue, NPC, world
- Script-based quest definitions
- Script-based NPC behavior
- Script hot-reload via file watcher

### 9.3 Data-Driven Content
- TOML/JSON definitions for: items, NPCs, shops, drop tables, spawns
- External data file loading at startup
- Override system for per-world customization
- Validation on load

**Milestone:** New quests, NPCs, items, and shops can be added via configuration files or scripts without recompiling the server.

---

## Phase 10 — Infrastructure & Production Readiness

**Goal:** Observability, persistence reliability, and operational tooling.

### 10.1 Clan & Party System Integration
- Wire `clan.rs` into commands and packets
- Clan creation, invite, kick, rank management
- Clan chat channel
- Wire `party.rs` — party formation, XP sharing, loot sharing
- Party invite, leave, kick
- Clan/party outbound update packets

### 10.2 Discord Integration
- Discord bot for server status, player count
- Staff command logging to Discord channel
- Kill/death/rare drop announcements
- Watchlist notifications

### 10.3 Persistence Hardening
- Auto-save: save all online players every 30 seconds
- Crash recovery: detect unclean shutdown, restore from last auto-save
- Transaction safety: wrap multi-table updates in DB transactions
- Chat logging, trade logging, death logging, PM logging to database

### 10.4 Admin Tools
- Full admin command set: teleport, spawn, kick, ban, mute, possess, set stats, etc.
- Staff action audit logging
- Player lookup commands
- Server status commands (player count, uptime, tick health)

### 10.5 Configuration Parity
- Load world configs matching Java format (preservation.conf, openpk.conf, etc.)
- All 50+ configurable parameters: XP rates, wilderness rules, member content toggles, combat formulas, etc.
- Per-world feature flags

### 10.6 Metrics & Alerting
- Prometheus metrics: players online, tick duration, packets/sec, DB query latency
- OpenTelemetry traces for request flows
- Health check endpoints (live, ready, startup)
- Tick overflow alerting

### 10.7 Load Testing
- Simulated player bots for stress testing
- Benchmark: 2000 concurrent players at stable 640ms ticks
- Memory profiling and optimization
- Connection handling under load

**Milestone:** Server is production-ready with full observability, persistence guarantees, and operational tooling.

---

## Phase Summary & Rough Ordering

| Phase | Focus | Depends On |
|-------|-------|------------|
| 1 | Game loop, login, entity updates | — |
| 2 | World, movement, collision | Phase 1 |
| 3 | Chat, social, commands | Phase 1 |
| 4 | Combat (melee, ranged, magic, prayer) | Phase 2 |
| 5 | All 27 skills | Phase 2, 4 |
| 6 | NPCs, shops, banking, trading | Phase 2, 3 |
| 7 | Quests & achievements | Phase 5, 6 |
| 8 | Special mechanics & minigames | Phase 4, 5, 6 |
| 9 | Plugin / content extension | Phase 7 |
| 10 | Infrastructure & production | Phase 1-8 |

**Phases 3 and 4 can be worked in parallel.** Phases 5 and 6 can also overlap significantly.

---

## Key Design Decisions to Make

1. **Plugin system approach**: Compiled Rust traits vs. embedded scripting (Rhai/Lua) vs. data-driven TOML. Can do a hybrid — Rust for performance-critical plugins, scripts for content.

2. **World data format**: Load the existing Java game data files directly, or convert to a Rust-native format? Loading existing files means easier parity testing. Converting means cleaner code.

3. **Concurrency model**: Single-threaded game loop (like Java) with async I/O on separate threads, or try to parallelize the tick? Recommend single-threaded tick for correctness, matching Java behavior.

4. **Database**: Keep dual MySQL/SQLite support (already in place), or simplify to one? SQLite is great for dev, MySQL for production — keep both.

5. **Config format**: TOML (Rust-native) vs. HOCON (Java parity with .conf files)? Recommend TOML with a converter for existing .conf files.
