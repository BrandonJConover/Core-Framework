# server-java-modern/ - Development Progress

## Overview
`server-java-modern/` is a Java 21+ modernized variant of the OpenRSC server running parallel to the legacy Java 8 `server/` directory. This document tracks progress toward feature parity with the upstream develop branch.

## Current Status (May 1, 2026)

### Modern client REST API — complete

A full HTTPS-friendly JSON API for non-game-tick traffic (launchers, web
clients, third-party tools) lives at `src/com/openrsc/server/net/api/`.
Listens on port 43595 alongside the existing TCP (43594) and WS (43494)
game protocol. Designed to be reverse-proxied behind nginx; see
`nginx-ssl.conf.template` for the production config.

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/status` | GET | Server up/playerCount/uptime/tick latency |
| `/healthz` | GET | LB-probe alias for status |
| `/api/auth/login` | POST | Username/password → JWT (rate-limited 10/60s/IP) |
| `/api/auth/whoami` | GET | Verify Bearer token → return claims |
| `/api/players/online` | GET | Public list of online players (filters invisibles) |
| `/api/character/{username}` | GET | Public profile w/ skills (online OR offline) |

**Key infrastructure files:**
- `JsonHandler` — Jackson ↔ Netty bridge
- `HttpRouter` — exact-match + `{var}` path-param routing
- `ApiServer` — Netty bootstrap + lifecycle
- `JwtUtil` — HMAC256 signer/verifier; secret persisted to `.jwt-secret`
- `RateLimiter` — sliding-window per-IP limiter

**Tests:** `./api_test.sh` runs 14 endpoint scenarios covering status codes,
JSON shape, auth round-trip, and rate-limit behavior. 19/19 assertions
passing as of May 1, 2026.

**Dependencies added:** `lib/java-jwt-4.4.0.jar` (Auth0, 64KB, zero
transitive deps). No new framework — uses Netty's existing `HttpServerCodec`.

### Remaining work for the modern-client effort

| Item | Effort | Why deferred |
|---|---|---|
| nginx + Let's Encrypt cert in production | Operational | Requires deploying to your VPS; out-of-band of this codebase |
| `ActionSender` event-emitter refactor | ~2 weeks | Heaviest piece. Splits packet serialization from event emission so the modern WS-JSON gameplay protocol on `/ws/v2` can hook the same events as the binary backend. |
| iOS native client integration | iOS-side work | The server side now exposes everything the iOS app needs (auth + player list + profile). |
| Token revocation / blacklist | Optional | JWT is stateless; true revocation needs a revocation cache. Acceptable for 24h tokens. |
| `/api/character/{username}` over the wire to web clients | Front-end work | Server-side is done; client integration is a 2009scape-web concern. |

## Earlier status (April 27, 2026)

### Round 2 modernization — Java 11→21 idiom upgrades (now on develop)

After the initial server-java-modern fork was merged into develop via
the feat/2009scape branch, this round applied modern-Java idioms across
the codebase. All commits pushed to origin/develop.

| Commit | What |
|---|---|
| 1a30e8c79 | Stream.toList(), .isBlank(), Files.readString() — Java 11/16 idioms |
| 8f0262654 | Switch expression conversion + AvatarFormat hashCode |
| a95070268 | Lint cleanup: 5 serialVersionUIDs, 10 redundant casts, 7 fallthrough warnings, 7 hashCode methods (Player/GameObject/Item/3 projectile events/ObjectRemover) |
| 1a9f75c18 | More switch expressions: StringUtil.formatMessage, Player kill-type-id, Player NPC face-on-finish, Npc.updatePosition |
| b5fef399c | AbstractMap.SimpleEntry → Map.entry (41 sites, Java 9+) |
| 1b5995a92 | 4 lossy-conversion fixes in Player XP party-share |

### Modernizations deliberately skipped

| Idiom | Why skipped |
|---|---|
| `var` keyword (Java 10) | 894 candidate sites is pure aesthetic churn that touches almost every file. Negative signal-to-noise. |
| Records (Java 16) | Existing data classes use `getX()` accessor naming, while record components are `x()`. Migration would require renaming every caller. No clean candidates with low caller count found. |
| Virtual threads (Java 21) | Server architecture is fundamentally single-threaded around the 640ms game tick. SQL pools intentionally serial. No fan-out I/O patterns where virtual threads would shine. |
| World.java byte-traversalMask lossy warnings | Real precision concerns but `traversalMask` is `byte` while masks use 16-bit constants — a possibly latent bug. Needs semantic investigation, not mechanical suppression. |
| 34 `this-escape` warnings | Mostly in legacy entity constructors that register self with parent during init. Refactoring touches plugin/event hierarchy widely. Out of scope. |

### Earlier status (April 19, 2026)

### Final state — modernization complete

**Build:** 4-6s clean compile. **Runtime:** 2.2s cold boot (ZGC), 0 warnings.
**Smoke test:** `./smoke_test.sh` → 4/4 pass (TCP accept, WS upgrade, malformed
input resilience, no IO-thread exceptions). **CVE posture:** no known CVEs
in any of the 43 runtime JARs.

Commits pushed to origin/ios/phase1-foundation this session:
| Commit | Summary |
|---|---|
| b0e06fb0f | Initial server-java-modern add (1409 files) — all library upgrades + Java 21 modernizations |
| 0cdcac782 | Added missing ant runserver targets + Java 21 JVM flags |
| c74849081 | Enabled log4j AsyncRoot with disruptor backend |
| 5ad9b3f14 | **Fixed Netty 4.1.119 null-SslContext regression** (broke WebSocket clients) |
| 6b36991bf | Added smoke_test.sh (4-test end-to-end verification) |
| 214669bea | Java 21 diamond operator + String.formatted() cleanup (79 files) |
| 77d583622 | Fixed `${LOG_LEVEL_PATTERN:-%5p}` leaking literally into log output |

### Mechanical modernizations applied across src/ + plugins/
- instanceof pattern matching — 132 occurrences in 50 files
- Diamond operator — 126 sites (3 ChannelInitializer<SocketChannel> skipped — childHandler erasure)
- String.formatted() — 21 sites (1 dead code skipped, 0 locale-version sites touched)
- Deprecated API: `new URL(...)` → `URI.create(...).toURL()` in 3 files
- Switch-expression yield fixes in Payload38Parser/Payload69Parser
- List.of / Set.of conversions in 3 files

### Not applied (deliberately)
- `var` keyword (802 candidate sites) — pure aesthetic, 802 lines of churn for no semantic change
- try-with-resources (79 sites) — subtle behavior differences on .close() throw paths; current code works
- Virtual threads on executors — 3 thread pools + 4 submitSql callers, sequential-by-design game loop; no real ROI

### Library Modernization — Phase 1 & 2 complete

### Library Modernization — Phase 1 & 2 complete

**Build verified:** core.jar (2.1MB) + plugins.jar (2.4MB), 0 errors, 0 warnings, 4-second clean builds.

Drop-in CVE patches:
- commons-codec 1.14 → 1.17.2
- commons-compress 1.18 → 1.27.1 (4 CVEs)
- commons-lang3 3.12.0 → 3.17.0
- log4j-api/core/iostreams 2.17.0 → 2.24.3
- log4j-slf4j18-impl → log4j-slf4j2-impl 2.24.3
- slf4j-nop 2.0.0-alpha5 → 2.0.16 (stable)
- sqlite-jdbc 3.34.0 → 3.47.1.0
- xstream 1.4.18 → 1.4.21 (deserialization CVEs)

Major version bumps:
- netty-all 4.1.33 (2018 fat jar) → netty 4.1.119.Final (9 modular jars)
- guava 30.1.1 → 33.4.0-jre (CVE-2023-2976)
- mysql-connector-java 8.0.19 → mysql-connector-j 8.4.0
- org.json 20190722 → 20240303
- Guice 5.0.2 → 6.0.0 (added jakarta.inject-api-2.0.1)

Removed:
- commons-lang 2.6 (EOL, replaced with commons-lang3 + inlined escapeSql)
- disruptor-3.3.11 (unused, not referenced anywhere in source)

Added:
- commons-text-1.13.0 (provides StringSubstitutor + WordUtils from old commons-lang)

JDA 4 → 5 migration (completed same day):
- JDA-4.0.0_55-withDependencies → JDA 5.2.1 + 11 explicit transitive deps
- DiscordService.java refactor: AccountType removed, GatewayIntents added (MESSAGE_CONTENT is now a privileged intent)
- Removed slf4j-nop (redundant), eliminated cosmetic SLF4J 1.x warning from boot log
- Added: okhttp/okio/kotlin-stdlib, jackson-core/databind/annotations, nv-websocket-client, commons-collections4, trove4j, slf4j-api 2.0.16

### Previous Status (April 13-14, 2026)

### ✅ Completed Milestones

#### 1. Build System Modernization
- **Java version:** Upgraded from 8 to 21
- **Gradle wrapper:** Updated to 9.1
- **build.xml:** Modified for Java 21 target
- **Compilation:** ✅ Clean builds in 5 seconds
- **Output:** core.jar (36MB) + plugins.jar

#### 2. Java 21+ Language Modernizations (37 files)
- ✅ `instanceof` pattern matching (11 files)
- ✅ Diamond operator cleanup (15+ files)
- ✅ `String.formatted()` (10+ files)
- ✅ `var` keyword (6 files)
- ✅ Immutable collections (2 files)
- **Status:** Applied, compiling cleanly

#### 3. Game Improvements Cherry-Picked (14 improvements)
- ✅ 1. Allow Ironmen to Play Fishing Trawler
- ✅ 2. F2P Steel Bar Smelting Fix
- ✅ 3. Plague City Buckets Hotfix
- ✅ 4. Disallow Cutting Webs with Ranged/Magic
- ✅ 5. Enable Ester's Bunnies Easter Event
- ✅ 6. Stop Spell Projectiles from Stealing Aggression
- ✅ 7. Fix Bone Burying/Meat Eating Messages
- ✅ 8. Rework Cape Dyeing Mechanics
- ✅ 9. Fix Item Pickup Bug (2-player scenario)
- ✅ + 4 additional critical fixes
- **Status:** Tested, building successfully

---

## Feature Parity Progress

### Statistics
```
Available improvements on develop:     3,779+ commits
Category breakdown:
  - Memory leak fixes:                 ~10 commits
  - Critical bug fixes:                ~15 commits
  - Balance changes:                   ~20 commits
  - Quest/content fixes:               ~30 commits
  - Performance improvements:          ~15 commits
  - Other gameplay improvements:       ~100+ commits

Applied so far:                        95+ improvements (~2.5%)

Batches Applied (April 12-14, 2026):
  - Batch 1 (9 core fixes)             ✅ Gameplay, minigames, quests
  - Batch 2 (5 memory leak fixes)      ✅ Event cleanup, NPC behavior
  - Batch 3 (6 balance/config fixes)   ✅ XP, quests, commands
  - Batch 4 (5 safety/NPC fixes)       ✅ Thieving, reports, spawns
  - Batch 5 (10 quest/command fixes)   ✅ Herblaw, ClockTower, login
  - Batch 6 (10 content/config fixes)  ✅ Observatory, Zamorak, skills
  - Batch 7 (9 database/parser fixes)  ✅ SQL, YML, custom equip
  - Batch 8 (10 drinkables/OpenPK)     ✅ Potions, shops, content
  - Batch 9 (8 shops/data/systems)     ✅ Banking, aubury, ground items
  - Batch 10 (19 quest/content fixes)  ✅ Entrana, quests, events, agility
  - Batch 11 (manual patches)          ✅ SpellHandler, CombatFormula line-level patches
```

### Next Priority Improvements (Ready to Apply)
1. Fix sleep fatigue bug (617bf67f0)
2. Multiple memory leak fixes (6f8deaa3d, 4439d1c20, d71220b15)
3. Correct XP for gem rocks (c36a26fb1)
4. New ranged combat formulas (7ba801875)
5. Buff crossbolt bolts damage (28e9101fa)
6. NPC spawn audits and fixes
7. Quest-specific improvements

---

## Architecture & Design

### Directory Structure
```
server-java-modern/
├── src/                           # Core server (1,115 Java files)
├── plugins/                       # Plugin system
├── conf/                          # Config files (multiple worlds)
├── lib/                           # 21 JAR dependencies
├── build.xml                      # Ant build (Java 21)
├── build.gradle                   # Gradle config
├── core.jar                       # Compiled output
├── SERVER-MODERN.md              # Documentation
├── CHERRY_PICKS.md               # This tracking document
└── PROGRESS.md                   # Progress tracker

Parallel variants:
├── /server/                       # Java 8 baseline (legacy)
├── /server-rust/                  # Rust implementation (stub)
└── /server-csharp/                # C# implementation (on develop)
```

### Key Files
- `src/com/openrsc/server/Server.java` - Entry point
- `src/com/openrsc/server/model/entity/player/Player.java` - Player entity
- `src/com/openrsc/server/net/rsc/handlers/` - Packet handlers
- `plugins/com/openrsc/server/plugins/` - Game content/quests

---

## Build System Details

### Java Compilation
```bash
javac -target 21 -source 21 \
  -cp lib/*.jar \
  src/**/*.java \
  plugins/**/*.java
```

### Dependencies (21 JARs)
- **Networking:** netty-all-4.1.33.Final.jar
- **Logging:** log4j-api/core-2.17.0.jar
- **Database:** mysql-connector-8.0.19.jar, sqlite-jdbc-3.34.0.jar
- **Discord:** JDA-4.0.0_55-withDependencies.jar
- **Utilities:** guava, guice, commons-*, xstream, etc.

### Build Times
- Clean build: ~5 seconds
- Incremental: <1 second
- No warnings related to Java 21 syntax

---

## Known Issues & Limitations

### Intentional Exclusions
- **Records:** Not applied to avoid API-breaking changes
- **Switch expressions:** Not fully applied
- **Infrastructure:** WebSocket, OAuth, Redis, PostgreSQL not included
- **Cross-server implementations:** Rust, C#, iOS not merged

### Why?
The goal is **graduated feature parity**, not bulk system refactoring. Selective improvements allow:
- Testing after each change
- Clear commit history
- Minimal API conflicts
- Safe rollback if needed

### Testing Strategy
- ✅ Compilation must succeed after each cherry-pick
- ✅ No new compilation errors or warnings
- ✅ JAR file generates correctly
- ⚠️ Runtime testing: Manual/on-server
- ⚠️ Plugin compatibility: Monitor as applied

---

## Next Steps (Recommended)

### Immediate (This week)
1. Apply 5 memory leak fixes (high safety)
2. Apply 5 critical bug fixes  
3. Test on sandbox server
4. Document any issues

### Short-term (This month)
1. Apply balance improvements (~20 commits)
2. Apply quest fixes (~30 commits)
3. Apply NPC behavior improvements
4. Establish regular cherry-pick workflow

### Medium-term (This quarter)
1. Achieve 25% feature parity (70+ improvements)
2. Evaluate record/API changes
3. Consider switch expression refactoring
4. Performance optimization pass

### Long-term (This year)
1. Aim for 80%+ feature parity
2. Evaluate Rust/C# interop options
3. Modernize with sealed classes, virtual threads
4. Complete feature parity

---

## Cherry-Pick Workflow

### Step 1: Identify
```bash
git log develop --oneline | grep -i "fix\|memory\|balance"
```

### Step 2: Inspect
```bash
git show <commit> --stat
git show <commit>  # View changes
```

### Step 3: Apply
```bash
git show <commit>:server/<file> > server-java-modern/<file>
```

### Step 4: Test
```bash
ant clean && ant compile_core
# Check for errors
```

### Step 5: Document
Edit CHERRY_PICKS.md with:
- Commit hash
- Date
- Files changed
- Impact description

### Step 6: Commit (when ready)
```bash
git add server-java-modern/
git commit -m "Cherry-pick: <description>"
```

---

## Performance Metrics

### Build Performance
| Metric | Value |
|--------|-------|
| Clean build time | ~5 seconds |
| JAR size | 36 MB |
| Java files | 1,115 |
| Total LOC | ~350,000 |
| Compilation target | Java 21 |

### Game Performance (Expected)
- No changes to game logic performance
- Java 21 JVM optimizations available
- Same threading model as Java 8
- Memory footprint: ~200-300MB (typical)

---

## Success Criteria

### ✅ Already Met
- [x] Java 21 build system
- [x] Clean compilation (4-5 second builds)
- [x] 95+ improvements applied (~2.5% parity)
- [x] Manual patching of conflict-prone files proven viable
- [x] Baseline already contains many develop changes (verified)
- [x] Documentation in place
- [x] Cherry-pick workflow established
- [x] Memory leak fixes applied
- [x] Balance improvements applied
- [x] Quest/content fixes applied
- [x] Config/operational improvements applied
- [x] OpenPK content improvements applied
- [x] Database/SQL fixes applied
- [x] Drinkables system rework applied
- [x] Shop system fixes applied

### 🔄 In Progress
- [ ] 50+ improvements applied
- [ ] Memory leak fixes prioritized
- [ ] Balance/gameplay parity
- [ ] Regular cherry-pick cadence

### 📋 Future Goals  
- [ ] 80%+ feature parity
- [ ] All critical bug fixes
- [ ] All balance changes
- [ ] Full game content parity
- [ ] Optional: Modern Java features (records, sealed classes)

---

## Maintenance & Support

### Regular Check-ins
- Weekly: Monitor develop for new improvements
- Monthly: Apply 10-15 new cherry-picks
- Quarterly: Assess progress toward parity
- Annually: Evaluate Java version upgrade path

### Documentation
- CHERRY_PICKS.md - Active improvement tracker
- PROGRESS.md - This file, updated quarterly
- SERVER-MODERN.md - Technical documentation
- Commit messages - Clear cherry-pick references

### Contact & Questions
- For improvement ideas: Reference develop commits
- For conflicts: Document in CHERRY_PICKS.md
- For Java 21 issues: Note in compilation errors

---

**Last Updated:** April 14, 2026
**Next Review:** May 14, 2026

## Session Notes (April 14, 2026)

### Improvements Applied This Session
- Applied 70+ improvements from develop branch across 9 batches
- Progressed from 0% to ~1.8% feature parity
- Covered: memory leaks, bug fixes, quest fixes, content updates, OpenPK, drinkables rework, shop fixes, database fixes
- Build remains stable at 4-5 seconds clean compile

### Categories Applied
- **Memory leaks:** 5 fixes (event cleanup, NPC behavior, player references)
- **Critical bugs:** 10+ fixes (CME, NPE, crash prevention, exploits)
- **Quest/content:** 15+ fixes (Plague City, Observatory, Lost City, Grand Tree, etc.)
- **Balance:** 5+ fixes (XP corrections, gem stalls, herblaw timings)
- **OpenPK:** 10+ fixes (shops, NPCs, configs, magic pool)
- **Drinkables:** Full rework applied (authentic potions + custom additions)
- **Database:** SQL error fixes, ID burning fixes, parser fixes
- **Config/ops:** 10+ config updates across all server worlds

### Key Learnings
1. **API Compatibility:** Large structural changes (CombatFormula, Player.java, SpellHandler, Equipment.java, GameStateUpdater, StringUtil) often incompatible due to type mismatches or missing symbols
2. **Risk Stratification:** Plugin-only and config-only changes are safest to apply (>95% success rate)
3. **Incremental Approach:** 5-10 cherry-picks per batch proven effective
4. **Test After Each:** Compilation success is best validation gate
5. **Data Files:** JSON configs (NpcLocs, GroundItems, ItemDefs) apply cleanly
6. **New Files:** Adding entirely new Java files (BadLuckMitigation, custom potions) works well
