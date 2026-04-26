# Elixir/OTP Game Server Implementation Plan

## Why Elixir for an MMORPG

The BEAM VM (Erlang's runtime) was designed for telecom switches — millions of concurrent connections, soft real-time guarantees, fault tolerance, and hot code upgrades. An MMORPG server has nearly identical requirements:

| BEAM Strength | MMORPG Mapping |
|---------------|----------------|
| Lightweight processes (2KB each) | One process per player, NPC, game object |
| Supervision trees | Crash one player's process, others unaffected |
| Message passing | Entity-to-entity communication (combat, trade, chat) |
| Hot code reload | Deploy content patches without kicking players |
| Distribution | Multi-node clustering for world sharding |
| ETS (in-memory tables) | Shared world state (map, items, collision) |
| GenServer state machines | Player states, NPC AI, combat rounds, quest progress |
| :timer + Process.send_after | Game tick scheduling, delayed events, respawn timers |

---

## Architecture Overview

```
                    ┌─────────────────────────────────┐
                    │         Application Root         │
                    │       (Application module)       │
                    └──────────────┬──────────────────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            │                      │                      │
   ┌────────▼────────┐   ┌────────▼────────┐   ┌────────▼────────┐
   │  NetworkSupervisor│   │  WorldSupervisor │   │ InfraSupervisor │
   │  (TCP/QUIC/WS)   │   │  (Game State)    │   │ (DB/Cache/Metrics)│
   └────────┬─────────┘   └────────┬─────────┘   └────────┬────────┘
            │                      │                      │
   ┌────────▼────────┐   ┌────────▼────────┐   ┌────────▼────────┐
   │ ConnectionPool   │   │  RegionSupervisor│   │  Repo (Ecto)    │
   │ (Ranch/ThousandIsland)│ │  ├─ Region_1_1  │   │  Redis (Redix)  │
   │                  │   │  ├─ Region_1_2  │   │  Metrics (Telemetry)│
   └────────┬─────────┘   │  └─ ...         │   │  Discord Bot    │
            │              └────────┬────────┘   └─────────────────┘
   ┌────────▼────────┐            │
   │ Session processes│   ┌───────▼────────┐
   │ (one per conn)  │   │ Entity processes │
   └─────────────────┘   │ ├─ Player_1     │
                          │ ├─ Player_2     │
                          │ ├─ Npc_42       │
                          │ ├─ Shop_7       │
                          │ └─ ...          │
                          └─────────────────┘
```

---

## Project Setup

### Tech Stack

| Component | Library | Purpose |
|-----------|---------|---------|
| Framework | Phoenix (optional) or bare OTP | Web dashboard, REST API, WebSocket |
| TCP Server | ThousandIsland or Ranch | Raw TCP socket handling |
| Database | Ecto + ecto_sql | MariaDB/SQLite persistence |
| Cache | Redix or Nebulex | Redis-backed session/cache |
| Metrics | Telemetry + PromEx | Prometheus-compatible metrics |
| Tracing | OpentelemetryAPI | Distributed tracing |
| Config | Config + runtime.exs | Per-environment configuration |
| Testing | ExUnit + Mox | Unit/integration testing |
| Binary Protocol | custom (bitstring matching) | RSC packet codec |

### Project Structure

```
openrsc_server/
├── mix.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   └── runtime.exs          # World-specific config loading
├── lib/
│   ├── openrsc/
│   │   ├── application.ex    # OTP Application entry
│   │   ├── network/
│   │   │   ├── tcp_server.ex         # ThousandIsland TCP acceptor
│   │   │   ├── quic_server.ex        # QUIC transport (if available)
│   │   │   ├── websocket_handler.ex  # WebSocket via Bandit/Cowboy
│   │   │   ├── session.ex            # Per-connection GenServer
│   │   │   └── protocol/
│   │   │       ├── codec.ex          # Packet encode/decode
│   │   │       ├── opcodes.ex        # Opcode definitions
│   │   │       └── packets.ex        # Packet struct definitions
│   │   ├── world/
│   │   │   ├── world.ex              # World GenServer (tick loop)
│   │   │   ├── region.ex             # Region GenServer (spatial)
│   │   │   ├── region_supervisor.ex  # DynamicSupervisor for regions
│   │   │   ├── collision.ex          # Collision map (ETS)
│   │   │   ├── pathfinding.ex        # A* pathfinding
│   │   │   └── tile.ex               # Tile/collision flag definitions
│   │   ├── entity/
│   │   │   ├── player.ex             # Player GenServer
│   │   │   ├── npc.ex                # NPC GenServer
│   │   │   ├── game_object.ex        # Game object process
│   │   │   ├── ground_item.ex        # Ground item process (self-expiring)
│   │   │   ├── entity.ex             # Shared entity behavior
│   │   │   └── entity_supervisor.ex  # DynamicSupervisor for entities
│   │   ├── game/
│   │   │   ├── combat.ex             # Combat GenServer (per-fight)
│   │   │   ├── combat_formula.ex     # Damage calculations
│   │   │   ├── skills/
│   │   │   │   ├── mining.ex
│   │   │   │   ├── fishing.ex
│   │   │   │   ├── woodcutting.ex
│   │   │   │   ├── cooking.ex
│   │   │   │   ├── smithing.ex
│   │   │   │   ├── crafting.ex
│   │   │   │   ├── fletching.ex
│   │   │   │   ├── firemaking.ex
│   │   │   │   ├── herblore.ex
│   │   │   │   ├── runecrafting.ex
│   │   │   │   ├── thieving.ex
│   │   │   │   ├── agility.ex
│   │   │   │   ├── prayer.ex
│   │   │   │   ├── magic.ex
│   │   │   │   └── ranged.ex
│   │   │   ├── trade.ex              # Trade session GenServer
│   │   │   ├── duel.ex               # Duel session GenServer
│   │   │   ├── shop.ex               # Shop GenServer (per-shop)
│   │   │   ├── bank.ex               # Bank operations
│   │   │   ├── quest.ex              # Quest state machine
│   │   │   ├── achievement.ex        # Achievement tracker
│   │   │   ├── dialogue.ex           # Dialogue tree executor
│   │   │   ├── clan.ex               # Clan GenServer
│   │   │   ├── party.ex              # Party GenServer
│   │   │   └── market.ex             # Auction house GenServer
│   │   ├── content/
│   │   │   ├── item_defs.ex          # Item definitions (ETS table)
│   │   │   ├── npc_defs.ex           # NPC definitions (ETS table)
│   │   │   ├── object_defs.ex        # Object definitions (ETS table)
│   │   │   ├── drop_tables.ex        # Drop table definitions
│   │   │   ├── spell_defs.ex         # Spell definitions
│   │   │   └── quest_defs.ex         # Quest definitions
│   │   ├── plugin/
│   │   │   ├── plugin.ex             # Plugin behavior definition
│   │   │   ├── plugin_registry.ex    # Plugin dispatch (Registry)
│   │   │   └── triggers.ex           # Trigger type definitions
│   │   ├── auth/
│   │   │   ├── authenticator.ex      # Login/password verification
│   │   │   ├── account.ex            # Account creation/management
│   │   │   └── security.ex           # Rate limiting, IP bans
│   │   └── infra/
│   │       ├── repo.ex               # Ecto Repo
│   │       ├── cache.ex              # Redis/Nebulex cache
│   │       ├── metrics.ex            # Telemetry metrics
│   │       └── discord.ex            # Discord bot integration
│   └── openrsc_web/                  # Optional Phoenix web dashboard
│       ├── router.ex
│       ├── controllers/
│       └── live/                     # LiveView admin dashboard
├── priv/
│   ├── repo/migrations/              # Ecto migrations
│   └── game_data/                    # Static game data files
└── test/
    ├── openrsc/
    └── test_helper.exs
```

---

## Phase 1 — OTP Foundation & Network Layer

**Goal:** Accept TCP connections, decode/encode RSC packets, manage sessions.

### 1.1 Mix Project Setup
- `mix new openrsc_server --sup` with umbrella or flat structure
- Add dependencies: thousand_island, ecto_sql, myxql, redix, telemetry, jason
- Configure Ecto repo for MariaDB + SQLite
- Set up config/runtime.exs for world-specific settings

### 1.2 Binary Protocol Codec
- Elixir's **binary pattern matching** is perfect for RSC packets:
```elixir
# This is where Elixir truly shines for game servers
def decode_packet(<<length::16, opcode::8, payload::binary-size(length - 1)>>) do
  %Packet{opcode: opcode, payload: payload}
end

def decode_login(<<0, reconnect::8, version::32, rest::binary>>) do
  [username, rest] = String.split(rest, "\n", parts: 2)
  [password, <<uid::64>>] = String.split(rest, "\n", parts: 2)
  %LoginRequest{reconnect: reconnect, version: version,
                username: username, password: password, uid: uid}
end
```
- Define all OpcodeIn / OpcodeOut as module attributes or enums
- Packet builder with iolist accumulation (zero-copy where possible)

### 1.3 TCP Server
- ThousandIsland acceptor with custom Handler module
- On connect: spawn a `Session` GenServer, link to connection process
- On data: decode packets, send to Session process via `GenServer.cast`
- On disconnect: notify Session, trigger logout/save

### 1.4 Session GenServer
```elixir
defmodule OpenRSC.Network.Session do
  use GenServer

  defstruct [:socket, :state, :player_pid, :last_activity, :ip_address]

  # States: :connected -> :authenticating -> :logged_in -> :disconnecting
  def handle_cast({:packet, %Packet{opcode: @login}}, %{state: :connected} = session) do
    # Authenticate, load player, transition state
  end

  def handle_cast({:packet, %Packet{opcode: @heartbeat}}, session) do
    {:noreply, %{session | last_activity: System.monotonic_time()}}
  end
end
```

### 1.5 Application Supervision Tree
```elixir
children = [
  OpenRSC.Repo,                          # Database
  {OpenRSC.Infra.Cache, []},             # Redis
  {OpenRSC.World.World, []},             # World state + tick loop
  {OpenRSC.World.RegionSupervisor, []},  # Regions
  {OpenRSC.Entity.EntitySupervisor, []}, # Players, NPCs
  {OpenRSC.Network.TcpServer, port: 43594},
  {OpenRSC.Network.WebSocketServer, port: 43494}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

**Milestone:** Client connects, sends login, gets authenticated, enters world process.

---

## Phase 2 — World Tick & Entity Model

**Goal:** Game world ticks at 640ms, entities exist as supervised processes.

### 2.1 World GenServer (Tick Loop)
```elixir
defmodule OpenRSC.World.World do
  use GenServer

  def init(_) do
    schedule_tick()
    {:ok, %WorldState{tick: 0, start_time: System.monotonic_time()}}
  end

  def handle_info(:tick, state) do
    new_state = state
    |> process_events()
    |> update_entities()
    |> send_updates()
    |> advance_tick()

    schedule_tick()
    {:noreply, new_state}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, 640)
end
```

### 2.2 Player as GenServer
- Each player is a supervised GenServer process
- State holds: position, skills, inventory, equipment, quest progress, settings
- Receives messages from Session (incoming packets) and World (tick updates)
- Handles its own state transitions (idle, walking, in combat, skilling, trading)
- **Key Elixir advantage**: player crash only kills that player's process — supervisor restarts it, other players unaffected

```elixir
defmodule OpenRSC.Entity.Player do
  use GenServer

  defstruct [:username, :position, :skills, :inventory, :equipment,
             :quest_progress, :friends, :settings, :combat_state,
             :walking_queue, :current_action, :session_pid]

  def handle_cast({:walk_to, destination}, player) do
    path = OpenRSC.World.Pathfinding.find_path(player.position, destination)
    {:noreply, %{player | walking_queue: path}}
  end

  def handle_info(:tick, player) do
    player
    |> process_walking_queue()
    |> process_current_action()
    |> process_combat()
    |> drain_prayer()
    |> tick_poison()
    |> send_updates_to_session()
    {:noreply, player}
  end
end
```

### 2.3 NPC as GenServer
- Each NPC is a supervised process
- Wander behavior, aggro checking, combat AI
- Respawn via `Process.send_after(self(), :respawn, respawn_time)`
- Drop loot on death, then go dormant until respawn

### 2.4 Region GenServer
- Each 64×64 region is a process
- Tracks which entities are in the region
- Handles spatial queries: "who is near position X?"
- Entity enter/leave notifications
- ETS table for collision data (read-heavy, shared across processes)

### 2.5 Collision via ETS
```elixir
# Load once at startup, read from any process — zero-copy, lock-free reads
:ets.new(:collision_map, [:set, :public, :named_table, read_concurrency: true])

# Check walkability from any process without message passing
def walkable?(x, y) do
  case :ets.lookup(:collision_map, {x, y}) do
    [{_, flags}] -> band(flags, @blocked) == 0
    [] -> true
  end
end
```

**Milestone:** World ticks, player/NPC processes run, entities move between regions.

---

## Phase 3 — Combat as Process Interaction

**Goal:** Combat works as message passing between entity processes.

### 3.1 Combat as Transient GenServer
- When Player A attacks Player B, spawn a `Combat` GenServer
- Combat process orchestrates rounds: schedules `Process.send_after(self(), :round, 1920)`
- Each round: calculate hit → send damage message to defender → check death
- Combat process terminates when fight ends

```elixir
defmodule OpenRSC.Game.Combat do
  use GenServer, restart: :transient

  def init({attacker_pid, defender_pid, style}) do
    schedule_round()
    {:ok, %{attacker: attacker_pid, defender: defender_pid,
            style: style, round: 0}}
  end

  def handle_info(:round, state) do
    attacker_stats = GenServer.call(state.attacker, :get_combat_stats)
    defender_stats = GenServer.call(state.defender, :get_combat_stats)

    damage = CombatFormula.calculate_damage(attacker_stats, defender_stats, state.style)
    GenServer.cast(state.defender, {:take_damage, damage, state.attacker})
    GenServer.cast(state.attacker, {:deal_damage, damage, state.defender})

    schedule_round()
    {:noreply, %{state | round: state.round + 1}}
  end
end
```

### 3.2 Prayer / Magic / Ranged
- Same message-passing model
- Prayer: Player process drains its own prayer points per tick
- Magic: spell cast → check runes → spawn projectile delay → apply effect
- Ranged: similar to magic with ammo consumption

### 3.3 Death Handling
- Player receives `{:take_damage, damage}` → HP ≤ 0 → trigger death
- Death: drop items, notify combat process, broadcast death animation
- Respawn: `Process.send_after(self(), :respawn, 3000)` → reset position, restore HP
- NPC death: calculate drops, spawn ground items, schedule respawn

**Milestone:** Full combat between players and NPCs with all three styles.

---

## Phase 4 — Skills, Economy, Social

**Goal:** All skills, shops, banking, trading, chat.

### 4.1 Skills as Behavior Modules
- Each skill implements an `OpenRSC.Game.Skill` behaviour
- Skills don't need their own processes — they're functions called within the Player process
- Action scheduling: player sets `current_action`, processed each tick

```elixir
defmodule OpenRSC.Game.Skills.Mining do
  @behaviour OpenRSC.Game.Skill

  def attempt(%Player{} = player, rock_id) do
    with {:ok, ore_def} <- get_ore_def(rock_id),
         {:ok, pickaxe} <- find_best_pickaxe(player),
         :ok <- check_level(player, ore_def),
         :ok <- check_inventory_space(player) do
      {:ok, %Action{type: :mining, target: rock_id, delay: calculate_delay(player, ore_def, pickaxe)}}
    end
  end

  def complete(%Player{} = player, %Action{target: rock_id}) do
    if success?(player, rock_id) do
      player
      |> add_to_inventory(ore_def.ore_id)
      |> award_experience(:mining, ore_def.xp)
      |> deplete_rock(rock_id)
    else
      {:retry, player}
    end
  end
end
```

### 4.2 Shops as GenServers
- Each shop is a persistent GenServer with stock state
- Restocking via `Process.send_after`
- Buy/sell as `GenServer.call` — naturally serialized, no race conditions

### 4.3 Trading as Transient GenServer
- Trade session spawned when both players accept
- Two-phase confirmation via state machine
- Atomic item swap on final confirm

### 4.4 Chat via PubSub
- Use `Phoenix.PubSub` or `Registry` for pub/sub
- Public chat: publish to region topic, nearby subscribers receive
- Private message: direct `GenServer.cast` to target player process
- Clan/party chat: publish to clan/party topic

```elixir
# Public chat — all players in the region receive it
Phoenix.PubSub.broadcast(OpenRSC.PubSub, "region:#{region_id}", {:chat, username, message})

# Private message — direct to player process
GenServer.cast(target_player_pid, {:private_message, from_username, message})
```

### 4.5 Banking
- Bank operations are functions called within the Player process
- No separate bank process needed — bank state is part of player state
- Bank presets stored in player state

**Milestone:** Full economy and social systems working.

---

## Phase 5 — Quests, Content & Plugins

**Goal:** Quest system and extensible content.

### 5.1 Quest State Machine
- Quest progress tracked in player state as `%{quest_id => stage}`
- Quest definitions as data modules:

```elixir
defmodule OpenRSC.Content.Quests.CooksAssistant do
  use OpenRSC.Plugin.Quest

  quest "Cook's Assistant" do
    id 1
    difficulty :novice
    quest_points 1

    stage 0, :not_started
    stage 1, :gathering_ingredients
    stage 2, :returned_ingredients

    on_talk_npc :cook, stage: 0 do
      dialogue do
        npc_say "I need help! I'm trying to bake a cake."
        player_choice ["Sure, what do you need?", "No thanks."] do
          0 -> advance_stage(1); npc_say "I need an egg, milk, and flour."
          1 -> npc_say "Oh well..."
        end
      end
    end

    on_talk_npc :cook, stage: 1, items: [:egg, :milk, :flour] do
      remove_items([:egg, :milk, :flour])
      advance_stage(-1)  # completed
      award_xp(:cooking, 300)
      award_quest_points(1)
      npc_say "Thank you so much!"
    end
  end
end
```

### 5.2 Plugin System via Behaviours + Registry
- Define `@callback` behaviours for each trigger type
- Plugins register at compile time via `use OpenRSC.Plugin`
- Dispatch via `Registry.dispatch/3` — O(1) lookup

```elixir
defmodule OpenRSC.Plugin do
  defmacro __using__(_) do
    quote do
      @before_compile OpenRSC.Plugin
      Module.register_attribute(__MODULE__, :triggers, accumulate: true)
    end
  end
end
```

### 5.3 Hot Code Reload for Content
- **This is Elixir's killer feature for game servers**
- Deploy new quest modules, NPC dialogue, item definitions without restarting
- `Code.purge/1` + `Code.load_file/1` for runtime module replacement
- Player processes pick up new module code on next function call
- Zero-downtime content patches

**Milestone:** Quests playable, content extensible, hot-reloadable.

---

## Phase 6 — Distribution & Scaling

**Goal:** Multi-node clustering for horizontal scaling.

### 6.1 Node Clustering
- BEAM has built-in distributed Erlang
- Nodes discover each other via `libcluster` (DNS, Kubernetes, multicast)
- Processes on different nodes communicate transparently

### 6.2 World Sharding
- Each node owns a set of regions
- Player processes live on the node that owns their current region
- Region transfer: player walks to edge → process migrates to new node
- `:pg` (process groups) for cross-node entity lookup

### 6.3 Global Services
- Use `Horde` for distributed DynamicSupervisors and Registries
- Clan/Party managers as global singletons via `Horde.Registry`
- Auction house as a global GenServer

### 6.4 Session Affinity
- TCP connections pinned to the accepting node
- If player's region moves to another node, proxy packets via internal messaging
- Or: transfer TCP connection via `:gen_tcp.controlling_process/2`

**Milestone:** Multi-node cluster running the game world across machines.

---

## Phase 7 — Infrastructure & Production

### 7.1 Observability
- `Telemetry` hooks throughout: tick duration, packet counts, entity counts, DB latency
- `PromEx` for Prometheus exposition
- `OpentelemetryAPI` for distributed tracing
- LiveView admin dashboard (player list, kick, ban, server stats)

### 7.2 Persistence
- Ecto changesets for player saves
- Auto-save: `Process.send_after(self(), :auto_save, 30_000)` in each Player process
- Graceful shutdown: `terminate/2` callback saves player state
- ETS-backed write-behind cache for high-frequency updates

### 7.3 Rate Limiting & Security
- Per-IP connection limits via ETS counters
- Packet rate limiting in Session process
- Password hashing with Argon2 (comeonin + argon2_elixir)
- Input sanitization for chat/commands

### 7.4 Release & Deployment
- `mix release` for self-contained deployments
- Docker image with multi-stage build
- Config via environment variables (runtime.exs)
- Rolling upgrades via hot code swap (OTP releases support this natively)

**Milestone:** Production-ready Elixir server with observability, persistence, and deployment tooling.

---

## Elixir-Specific Advantages to Leverage

### 1. Pattern Matching for Packets
Elixir's binary pattern matching is arguably the best in any language for game protocol work:
```elixir
def handle_packet(<<16, x::16, y::16>>, player), do: walk_to(player, x, y)
def handle_packet(<<30, message::binary>>, player), do: public_chat(player, message)
def handle_packet(<<50, npc_id::16>>, player), do: attack_npc(player, npc_id)
def handle_packet(<<5>>, player), do: heartbeat(player)
```

### 2. Supervision for Fault Isolation
One player's bug doesn't crash the server. The supervisor restarts just that player's process.

### 3. Process Mailboxes for Game Events
No need for an explicit event queue — every process has a built-in mailbox. Events are just messages.

### 4. ETS for Read-Heavy Shared State
Collision maps, item definitions, NPC definitions — load once into ETS, read from any process with zero message passing overhead.

### 5. Hot Code Reload for Live Content
Ship new quests, balance changes, and bug fixes without restarting the server or disconnecting players. This alone could justify Elixir for a live game.

### 6. Built-in Distribution
The BEAM was designed for distributed systems. Multi-node clustering is a first-class feature, not a bolted-on library.

---

## Risk & Mitigation

| Risk | Mitigation |
|------|------------|
| BEAM not great for CPU-heavy math (combat formulas, pathfinding) | Use NIFs (Rust-backed via Rustler) for hot-path calculations |
| Smaller game server ecosystem than Java/C# | Core OTP primitives are battle-tested; game-specific code is custom regardless |
| Team familiarity | Elixir has a gentle learning curve from Ruby/Python; OTP concepts take time |
| Binary protocol complexity | Elixir's binary pattern matching is actually ideal for this |
| Existing Java data format compatibility | Write importers during Phase 1; Ecto handles the same DB schema |

---

## Phase Summary

| Phase | Focus | Key Elixir Feature |
|-------|-------|--------------------|
| 1 | Network, protocol, sessions | Binary pattern matching, GenServer |
| 2 | World tick, entities as processes | Supervision, Process.send_after |
| 3 | Combat as process interaction | Message passing, transient GenServers |
| 4 | Skills, economy, social | PubSub, ETS, functional pipelines |
| 5 | Quests, plugins, hot reload | Behaviours, hot code swap |
| 6 | Multi-node distribution | Distributed Erlang, libcluster |
| 7 | Infrastructure & production | Telemetry, releases, LiveView |

---

## Hybrid Option: Elixir + Rust NIFs

For the best of both worlds, use Elixir as the orchestration layer and Rust for CPU-intensive work via `Rustler` NIFs:

- **Elixir handles**: networking, session management, entity lifecycle, game loop scheduling, chat/social, quest logic, plugin system, distribution
- **Rust NIFs handle**: pathfinding, combat formula calculations, collision checking, packet codec (if perf-critical), map data loading

This gives you Elixir's process model and fault tolerance with Rust's raw computation speed. The NIF boundary is clean — pure functions in, results out.

```elixir
defmodule OpenRSC.Native.Pathfinding do
  use Rustler, otp_app: :openrsc_server, crate: "pathfinding_nif"

  # Falls back to Elixir implementation if NIF not loaded
  def find_path(_from, _to, _collision_map), do: :erlang.nif_error(:not_loaded)
end
```
