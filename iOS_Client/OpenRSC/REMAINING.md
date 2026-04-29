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
- [ ] Terrain textures (deferred — needs sprite-pack metadata + Scene fill switch, multi-iteration). Original REMAINING entry assumed a separate `textures.orsc` archive; in reality Java loads textures from Authentic_Sprites.orsc at IDs `spriteTexture(3225)..+EntityHandler.textureCount()` using the "texture" package. Real port requires (1) parsing texture sprites from Authentic_Sprites.orsc + EntityHandler.textures metadata for type/dictionary, (2) feeding `scene.loadTexture(idx, dictionary, type, indices)` for each one, (3) replacing Scene's bbox terrain fill with `Shader.shadeScanlineTransparent/Opaque/BlendNormal/Large` (already ported, never called) when a polygon has a texture index, (4) ensuring landscape generation tags polygons with the right texture id from FloorDef. Best approached as a separate Phase-5 plan rather than a ralph iteration.
- [x] Walk-target server command opcode 187 with multi-tile pathfinding: currently sends single destination. Server expects `[len][187][SHORT destX][SHORT destZ]` and optionally `[BYTE deltaX][BYTE deltaZ]` pairs for waypoints. Use existing Pathfinder.swift to compute waypoints; encode + send. _(verified — handleTap uses Pathfinder.findPath + appends BYTE deltas; commit 7bf0588b2 added int8 clamping for safety on very-long paths)_
- [x] Quest dialogue: opcode 245 (already shows dialog options). Add SwiftUI overlay that buttons each option; tapping sends opcode 116 with the option index. _(verified — DialogueOverlayView in HUDView.swift + engine.answerDialogue(opcode 116) already wired)_
- [x] Right-click context menu: long-press already triggers it, but the action list is empty. Build context-menu actions per target type (NPC: Talk to, Attack, Examine; Player: Trade, Duel, Follow, Examine; Object: Use, Examine; Item: Pickup, Examine). _(commit f61a4cb80 — also fixed the picker projection to match the tap-to-walk math)_
- [x] Friend status notifications: opcode 149 already adds chat — also flash a small toast UI when friends come online/offline. _(commit 3c7c9afdf — top-right capsule toasts, 3s auto-dismiss)_

## Workflow per iteration

1. Pick top unchecked item.
2. Read corresponding Java in `Client_Base/src/`.
3. Implement; touch only the files this item needs.
4. Run build command. Fix compile errors until BUILD SUCCEEDED.
5. `git add` the files you touched, commit with message starting `iOS: <feature>`.
6. Mark this item `[x]` in this file. Commit the file change.
7. Stop the iteration.

Do NOT push to remote. Do NOT touch the avoid list. Keep changes small and single-feature.
