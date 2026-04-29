# Remaining iOS Client Work

Drive iOS OpenRSC toward feature parity with desktop Java client.

## Repo

- Root: `/Users/brandonjconover/Documents/GitHub/Core-Framework`
- iOS sources: `iOS_Client/OpenRSC/OpenRSC/Sources/`
- Java reference: `Client_Base/src/`

## Build command

```sh
cd /Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC \
  && xcodegen generate \
  && xcodebuild -project OpenRSC.xcodeproj -scheme OpenRSC \
       -configuration Debug \
       -destination 'id=00008130-000805D10AF0001C' \
       -derivedDataPath /tmp/openrsc-build-ralph build
```

Must report `BUILD SUCCEEDED`. iPhone 15 Pro device: `Brick the 15th`, id `00008130-000805D10AF0001C`.

## Avoid (other agents own these)

`HUDView.swift, MinimapPanel.swift, PrayerPanel.swift, SpellbookPanel.swift, CombatStylePanel.swift, SettingsPanel.swift, QuestBookPanel.swift, SocialPanel.swift, BankPanel.swift, ShopPanel.swift, TradePanel.swift, DuelPanel.swift, SoundManager.swift, AppearancePanel.swift, ModelArchiveLoader.swift`

## Items (highest impact first)

- [x] Combat animations: port `animFrameToSprite_CombatA = [0,1,2,1,0,0,0,0]` and `animFrameToSprite_CombatB = [0,0,0,0,0,1,2,1]` from mudclient.java line 97-98 into CharacterBillboards.swift; pick CombatA vs CombatB per character based on a new `inCombat: Bool` + `combatRole: Int` field on RSCNPC/RSCPlayer; cycle through frames over time using a tick counter; render combat frames at offset = 15 + frame*1 (NOT walking offsets). _(commit efd14b2f6 — uses combatTimeout/inCombat as the role signal; per-NPC combatRole field on the struct is deferred until the server sends explicit combatant-side info.)_
- [x] Welcome screen: new file `Sources/Views/Game/WelcomePanel.swift`. Show on opcode 182 (already received). Display last login IP + days since last login + welcome text. Dismiss button. _(commit d17b68508 — also added six tip-of-day strings from mudclient tipsArray)_
- [x] Sleep screen: new file `Sources/Views/Game/SleepPanel.swift`. Show on opcode 117 (showSleepScreen). Display the captcha image (raw pixel data from worldState.sleepCaptchaImage), text input field, "Submit" sends opcode 45 (SEND_SLEEPWORD) with the typed string. _(commit 3d49051db)_
- [x] WAKE_UP packet handler: opcode 84, sets `worldState.isSleeping = false`. (Already exists per earlier note — verify and add if missing.) _(verified existed)_
- [x] INCORRECT_SLEEPWORD: opcode 194 (corrected from 224), sets a flag in worldState that SleepPanel can show as "Word incorrect, try again" — adds shake animation. _(SleepPanel shakes captcha on submit; status text already wired)_
- [x] System update timer: opcode 52 (SYSTEM_UPDATE), 2-byte tick countdown until reboot. Display as a banner above the chat window. _(commit 51ed43a57)_
- [x] Kill announcement: opcode 118 (already partially handled — verify it shows in chat with red color). _(prior handler read a single string; rewired to STRING victim/STRING attacker/INT killType per Java PacketHandler.announceKill(); added isKill flag on RSCChatMessage so HUDView paints sender + body in red and distinguishes COMBAT/MAGIC/RANGED in the text)_
- [x] Player appearance update from server: opcode 234's appearance section — currently we only parse position/direction; full appearance update is in PacketHandler.java updatePlayerAppearances. Port that so other players show their actual cosmetic (head/body/legs/colors) instead of default starter avatar. _(case 5 now persists 12 layer sprite IDs + four palette indices into RSCWorldState.playerAppearances keyed by serverIndex; renderer prefers per-player appearance, falling back to starter avatar only until the packet arrives. Added PlayerPalettes.swift with the Java clothing/hair/skin tables verbatim — including the partial-RGB unicode-escape entries — so colours match the desktop client byte-for-byte.)_
- [x] Character facing direction: `RSCGameEngine.tick()` registers every NPC and remote player with `rsDir: 4` hardcoded. Capture the 4-bit direction from `showNPCs`/`showPlayers` (already read but discarded) and the 3-bit reorientation in the per-player update flag, persist it on `RSCNPC`/`RSCPlayer`, and pass it into `CharacterBillboards.register` so characters face the way the server says they're facing. _(captured 4-bit dir on entity entry for both showPlayers and showNPCs, plus the local player; renderer feeds `npc.direction`/`player.direction`/`worldState.localPlayerDirection` into rsDir. Per-tick NPC reorientation now picks up `modelIndex` (motion branch) and `animationNext` (sprite branch) so existing NPCs reface mid-walk. Per-tick player reorientation requires showOtherPlayers to keep a persistent player list — see follow-up entry below.)_
- [x] Persistent showOtherPlayers list: `handleShowPlayers` rebuilds `ws.players` from the "new players" tail of opcode 191 every tick, dropping any prior entries — so per-tick movement/facing updates in the kept-player section have nothing to apply to and remote players blink in/out as the server stops re-announcing them. Mirror Java's `setKnownPlayer/setPlayer` pattern from PacketHandler.java:1339-1414: snapshot the current players into a `known` buffer, walk the kept-player update branches advancing waypoint/direction on the matching entry, then fold genuinely-new players from the tail before assigning back to `ws.players`. _(snapshot ws.players, walk knownCount slots applying motion (modelIndex → tile delta + direction) and animation (animationNext = (needsNextSprite<<2)|nextSprite → direction) updates, drop slots whose needsNextSprite==3, then fold new-tail entries with de-dupe by serverIndex. Also fixed the NPC handler's direction LUT — it had an off-by-1 9-entry encoding (0=stay) that didn't match Java's 8-compass; both handlers now share `movementDeltas` matching mudclient's N/NE/E/SE/S/SW/W/NW order.)_
- [x] Terrain projects off-screen: fixed by commit `38d169327`. Root cause was `Scene.polygons = [Polygon](repeating: Polygon(), count: polyCount)`: `Polygon` is a class, so every slot shared one instance and all visible polys collapsed onto the final bounding box. Scene now allocates distinct Polygon instances with `(0..<polyCount).map { _ in Polygon() }`.
- [x] Projectiles: opcode 234 case 3/4 and opcode 104 case 3/4 now persist projectile sprite/source/range on the target character, decay the 40-tick Java range counter, and render a moving projectile marker through the native Scene camera. Uses bundled projectile sprites when present and a small colored diamond fallback otherwise.
- [x] Skull indicators: player appearance skull flags and NPC opcode 104 case 5 now render overhead skull markers through the native Scene camera, hiding player skulls while item bubbles are active to match Java overlay behavior.
- [x] Inventory stack amounts: opcode 53 full inventory and opcode 90 single-slot updates now use bundled `ItemDefs.json` stackability metadata and the Java packet layouts, so coins/runes/certs/arrows/notes read their 32-bit amounts instead of rendering as `x1`.
- [x] Privacy settings sync: opcode 51 now mirrors Java `updateChatBlockSettings()` and stores chat/private/trade/duel block flags in `RSCWorldState` instead of dropping them.
- [x] Server-authoritative prayer state: opcode 206 now mirrors Java `togglePrayer(length)` and updates `RSCWorldState.activePrayers` instead of discarding accepted/rejected prayer toggles.
- [x] Equipment updates: opcode 254 full equipment and opcode 255 single-slot equipment updates now mirror Java slot remapping and stack amount decoding into `RSCWorldState.equipment`.
- [x] Entity refresh pruning: opcode 211 now mirrors Java `generateCounts()` by clearing ground items, game objects, and wall objects in refreshed 8x8 regions before follow-up entity packets repopulate them.
- [x] Teleport bubbles: opcode 36 now queues Java-style 50-tick visual bubbles and renders expanding fading circles through the native Scene camera.
- [x] NPC wield updates: opcode 104 case 6 now persists NPC wield/wield2 animation IDs and feeds them into billboard render layers so server-driven held items can appear.
- [x] Packet-handler duplicate cleanup: consolidated duplicate top-level cases for friend status, trade decisions/confirm, bank updates, prayer state, and dynamic NPC definitions; corrected opcode 249 to Java's BYTE slot + SHORT item + INT amount layout.
- [x] Clan/party state packets: opcodes 112 and 116 now mirror Java `updateClan()` / `updateParty()` enough to retain membership, invites, settings, and leave/join state in `RSCWorldState` instead of discarding the packets.
- [x] Misc stat packets: opcode 114 now reads both fatigue shorts, opcode 147 retains kills2/lastNpcKilled/kills3, and opcodes 148/98/140 retain OpenPK points/shared-XP/pet-fatigue instead of being skipped.
- [x] Player chat bubbles: opcode 234 case 1/7 now stores local/remote player messages with a Java-style timeout, and the native overlay renders compact bubbles above the speaking player through the Scene camera.
- [x] Ground-item world markers: opcode 99 ground items now render in the live Scene overlay using the Java item sprite range (`spriteItem + itemId`) when bundled, with a red pickup marker/name fallback so drops are visible in the 3D world instead of only on the minimap/fallback map.
- [x] Player trade/duel requests: native context-menu actions now send protocol-235 Java opcodes `142` (PLAYER_INIT_TRADE_REQUEST) and `103` (PLAYER_DUEL) instead of stale opcodes, so player interactions reach the server.
- [x] NPC secondary commands: context menus now use NPC definition `command`/`command2` labels instead of hard-coded Pickpocket, and command2 sends protocol-235 opcode `203` like the Java client.
- [x] Object command labels: `GameObjectDef.xml` command1/command2 are parsed and used by the native context menu, skipping Java's `WalkTo`/`Examine` placeholders so objects expose actions like Chop/Climb/Open with the correct object command opcode.
- [ ] Terrain textures (deferred — needs sprite-pack metadata + Scene fill switch, multi-iteration). Original REMAINING entry assumed a separate `textures.orsc` archive; in reality Java loads textures from Authentic_Sprites.orsc at IDs `spriteTexture(3225)..+EntityHandler.textureCount()` using the "texture" package. Real port requires (1) parsing texture sprites from Authentic_Sprites.orsc + EntityHandler.textures metadata for type/dictionary, (2) feeding `scene.loadTexture(idx, dictionary, type, indices)` for each one, (3) replacing Scene's bbox terrain fill with `Shader.shadeScanlineTransparent/Opaque/BlendNormal/Large` (already ported, never called) when a polygon has a texture index, (4) ensuring landscape generation tags polygons with the right texture id from FloorDef. Best approached as a separate Phase-5 plan rather than a ralph iteration.
- [x] Walk-target server command opcode 187 with multi-tile pathfinding: currently sends single destination. Server expects `[len][187][SHORT destX][SHORT destZ]` and optionally `[BYTE deltaX][BYTE deltaZ]` pairs for waypoints. Use existing Pathfinder.swift to compute waypoints; encode + send. _(verified — handleTap uses Pathfinder.findPath + appends BYTE deltas; commit 7bf0588b2 added int8 clamping for safety on very-long paths)_
- [x] Quest dialogue: opcode 245 (already shows dialog options). Add SwiftUI overlay that buttons each option; tapping sends opcode 116 with the option index. _(verified — DialogueOverlayView in HUDView.swift + engine.answerDialogue(opcode 116) already wired)_
- [x] Right-click context menu: long-press already triggers it, but the action list is empty. Build context-menu actions per target type (NPC: Talk to, Attack, Examine; Player: Trade, Duel, Follow, Examine; Object: Use, Examine; Item: Pickup, Examine). _(commit f61a4cb80 — also fixed the picker projection to match the tap-to-walk math)_
- [x] Friend status notifications: opcode 149 already adds chat — also flash a small toast UI when friends come online/offline. _(commit 3c7c9afdf — top-right capsule toasts, 3s auto-dismiss)_

## Visible polish backlog (each fits one iteration)

- [x] Tap/appearance alignment fixes: player appearance layers now subtract one before AnimationDef lookup like Java, touch scaling matches the 512x334 Metal buffer, pinch zoom drives Scene camera distance, and tap/context-menu targeting chooses the nearest camera-projected tile instead of an approximate inverse raycast.
- [x] Walk-target X marker: drop a small fading red X on the tile we sent to opcode 187 so the player gets feedback that their tap registered. Persist `walkTargetX/Z/Timeout` on `RSCWorldState`, set in `handleTap` after the walk packet ships, decay in `tick()`, and render via `Scene.projectPoint` in `drawHUDOverlay`. Java's mudclient doesn't draw one, but RSC+ and most modern clones do; high-value affordance for mobile.
- [ ] Smooth movement interpolation: remote players + NPCs snap a full tile per server tick. Track `prevX/prevZ` plus an interpolation phase advanced each render tick (engine timer is ~50ms, server ticks every ~640ms), so `CharacterBillboards.register` projects from the lerp'd position. Java client interpolates between waypointsX/waypointsZ; we'd port the same idea minus the queue.
- [ ] XP-drop float-up over the local player: `worldState.xpDrops` already exists but we render it as a static top-right list. Java floats `+12 Strength` upward from the player and fades. Move the renderer to project from the local player's screen anchor and animate Y over the drop's lifetime.
- [ ] Ground-item stack-count badge: opcode 99 gives ground items but stacks (coins/arrows/runes) all look like singles. Read `ItemDef.stackable` from the bundled JSON and overlay an `xN` count on the world marker when amount > 1.
- [ ] Channel-coloured chat: `[Quest]`, `[Server]`, `[Trade]`, `[System]` all render white today. `RSCChatMessage` already passes `isPrivate/isLocal/isKill`; widen the enum (or add a `channel` field) so `chatColor` in HUDView paints quest text orange, system yellow, trade green, etc.
- [ ] Wilderness crossing warning: opcode firing when the player crosses the ditch (Java emits a "Warning! Wilderness" interface). Identify the opcode in PacketHandler.java, capture `wildernessLevel` on world state, and surface it as a one-shot dismissible overlay.
- [ ] Run/walk toggle + run-energy bar in HUD: `worldState.fatigue/run-energy` already arrives. Add a small "Run/Walk" button next to the existing combat-style chip and a thin energy bar that drains while running.

## Bigger structural gaps (multi-iteration)

- [ ] 3D models for trees / buildings / doors: `ModelArchiveLoader.shared` is in the avoid list and currently a stub. Game objects render as colored blocks instead of RSModels. Real port needs the .ob3 format reader + per-tile elevation blending in Scene; deferred behind the texture-port plan.
- [ ] Use-item-on-X workflow: long-press shows "Use" but tapping it does nothing — there's no follow-up inventory picker, so the second item never gets selected. Need a transient "select target" mode that consumes the next entity tap.
- [ ] Bank/Trade/Duel/Shop interaction wiring: panels exist (avoid-listed) but the deposit/withdraw/accept/stake actions don't all fire the corresponding server packets yet. Audit each panel for missing engine calls.
- [ ] Camera occlusion: Java pulls the camera in when geometry blocks line-of-sight to the player. Currently the iOS camera clips through walls.

## Cheap correctness items

- [ ] Local stash of preferences (chat-channel filters, sound on/off, run-default). Save to `UserDefaults` so settings persist across app launches.
- [ ] Bubble-item icon ↔ chat-bubble vertical conflict: when both fire on the same character, they currently stack on top of each other. Anchor chat above the bubble icon, not the head.

## Workflow per iteration

1. Pick top unchecked item.
2. Read corresponding Java in `Client_Base/src/`.
3. Implement; touch only the files this item needs.
4. Run build command. Fix compile errors until BUILD SUCCEEDED.
5. `git add` the files you touched, commit with message starting `iOS: <feature>`.
6. Mark this item `[x]` in this file. Commit the file change.
7. Stop the iteration.

Do NOT push to remote. Do NOT touch the avoid list. Keep changes small and single-feature.
