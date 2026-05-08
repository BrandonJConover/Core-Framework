# iOS Mobile-Finish Plan

## Strategy overview

Two parallel tracks:

1. **Hybrid (now)** — Native Swift shell (server browser, navigation) wrapping a WKWebView that runs the Local_RSC React app. Gets something usable on a physical iPhone quickly without re-implementing the full game UI in Swift.
2. **Native (later)** — Replace the WKWebView game surface panel by panel with native SwiftUI + Metal, using the Java client and Android app as protocol/interaction references.

---

## Hybrid phase

### What the hybrid gives us

- All game UI from Local_RSC (inventory, combat, bank, shop, trade, quests, dialogue, chat, map) with zero re-implementation
- Touch gestures already built: swipe, pinch, long-press
- ISAAC cipher, RSC binary protocol, and WebSocket connection already working
- Gets to a playable build in days, not weeks

### Architecture

```
Swift native shell
├── GameSelectorView     — pick RSC or OSRS
├── ServerBrowserView    — add/select/delete servers (UserDefaults)
└── WebGameView          — WKWebView loading bundled Local_RSC dist/
    ├── Injects window.rscNativeConfig = { host, port, wsPort }
    ├── JS → Native bridge: haptics, back navigation, orientation lock
    └── Native → JS bridge: server config, network state
```

### Build pipeline

Local_RSC is built via Vite → `dist/` and bundled into the iOS app as resources.
A helper script `iOS_Client/build-web-client.sh` runs `npm run build` and copies
the output to `iOS_Client/OpenRSC/OpenRSC/Sources/WebClient/`.

Package.swift includes `.process("WebClient")` so Xcode bundles the files into the app.

### JS bridge API

**Swift → JS** (injected before page load via `WKUserScript`):
```js
window.rscNativeConfig = {
  host: "game.openrsc.com",
  port: 43594,
  wsPort: 43494,
  platform: "ios"
}
```

**JS → Swift** (via `window.webkit.messageHandlers`):
- `nativeBridge.back` — user tapped back; Swift pops to server browser
- `nativeBridge.haptic` with `{ style: "light"|"medium"|"heavy"|"selection" }`
- `nativeBridge.orientationLock` with `{ lock: "portrait"|"landscape"|"free" }`

### Local_RSC changes needed

- `vite.config.js`: add `base: './'` so asset paths work from `file://`
- Disable PWA service worker (not supported in WKWebView)
- `src/main.jsx` or `src/App.jsx`: read `window.rscNativeConfig` on startup and pre-populate server host/port in `GameService`
- Add `window.webkit?.messageHandlers?.nativeBridge?.postMessage(...)` calls where native features are wanted

### iOS changes needed

- `Package.swift`: add `.process("WebClient")` resource rule
- `WebGameView.swift` (new): `WKWebView` wrapper as `UIViewRepresentable`, loads `index.html` from bundle, injects config script
- `GameView.swift`: replace Metal renderer with `WebGameView`
- `AppState.swift`: route server selection tap directly to game view (skip native login — web app handles it)
- `Info.plist`: add `NSAppTransportSecurity` exception for WebSocket connections to arbitrary hosts

### Hybrid acceptance criteria

- App installs on a physical iPhone
- Selecting a server opens the WKWebView with Local_RSC pre-configured to that server
- User can log in and reach the in-game screen via the web UI
- Back button returns to server browser
- No crashes on foreground/background transitions

---

## Native track (phases, post-hybrid)

These phases remain from the original plan. As each is completed, the equivalent
WKWebView panel is replaced by native SwiftUI.

### Phase 1: Stabilize the protocol path

- Port `opcode 19` server-config bootstrap
- Port `tellLimitations(...)` login capability data
- Fix bit-packed player/NPC/world update decoding
- Add packet-level logging for comparison against Java client

References:
- [mudclient.java](../Client_Base/src/orsc/mudclient.java)
- [PacketHandler.java](../Client_Base/src/orsc/PacketHandler.java)

### Phase 2: iPhone shell

- Settings store with persistence
- Persisted server targets and last-used account
- Redesigned login screen
- Connection status and reconnect handling

### Phase 3: Touch-first controls

- Tap-to-move
- Long-press contextual action
- Swipe panel control
- Pinch zoom
- Natural scroll for chat and lists

References:
- [InputImpl.java](../Android_Client/Open%20RSC%20Android%20Client/src/main/java/com/openrsc/android/render/InputImpl.java)
- [useGestures.js](../../Local_RSC/src/hooks/useGestures.js)

### Phase 4: Mobile game UI

- Portrait bottom-sheet layout
- Landscape side-panel layout
- Compact quick-stats
- Panel switching via gestures and tabs

References:
- [GamePage.jsx](../../Local_RSC/src/pages/GamePage.jsx)

### Phase 5: Port high-value UX from Local_RSC

- Settings categories and persistence
- Gesture tuning
- Panel organization
- Cleaner service/state boundaries in Swift

### Phase 6: Device polish

- Haptics and audio session management
- Background/foreground lifecycle
- Reconnect handling
- Safe-area aware layouts (Dynamic Island, home indicator)
- Multi-screen-size testing

---

## Current build status (April 2026)

- Swift package builds cleanly (`swift build` passes on macOS 13)
- Xcode simulator build confirmed
- Physical device install blocked by Xcode signing (no team selected)
- Local_RSC builds and runs in browser; connects to server via WebSocket on port 43494
- To deploy to phone: open `OpenRSC.xcodeproj`, set signing team, select device, build and run

## Build plan for full 2001 + 2009 replication

### 2001 client parity

1. Finish protocol bootstrap
- Keep opcode 19 bootstrap
- Port the remaining config fields from the Java client
- Match login capability payloads

2. Fix packet decoding
- Bit-packed player/NPC/world updates
- Inventory, bank, shop, chat, PM, friends, ignore, sleep, sound
- Correct outbound walk/logout/chat encodings

3. Restore core game flow
- Login, reconnect, region loading, movement, combat, trade, banking
- Match the Java client UI state transitions

4. Add parity checks
- Packet fixtures
- Decode snapshots against Java client captures
- Login/world boot smoke cases

### 2009 client parity

1. Separate protocol module
- Keep RSC isolated from 2009/client-rev-specific code
- Add revision selection in the app shell

2. Add 2009 handshake stack
- ISAAC
- RSA login block
- JS5 cache bootstrap

3. Implement 2009 world/game packets
- Region load
- Entity updates
- Interface, chat, inventory, ground items, combat

4. Add 2009 rendering and UI
- Modernized panel layout
- Touch-first controls
- Mobile-friendly navigation

### Shared app work

- Persisted server profiles
- Better LAN/physical-device connection flow
- Haptics, audio, lifecycle, reconnect handling
- Safe-area and orientation polish
- Device testing on multiple screen sizes

## References

- Protocol truth: [Client_Base/src/orsc/mudclient.java](../Client_Base/src/orsc/mudclient.java)
- Mobile interaction: [Android_Client InputImpl.java](../Android_Client/Open%20RSC%20Android%20Client/src/main/java/com/openrsc/android/render/InputImpl.java)
- Modern mobile UX: [Local_RSC/src](../../Local_RSC/src)
