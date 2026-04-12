# iOS Mobile-Finish Plan

## Short answer

The Android client gives us most of the reference behavior we need, but not everything we need to make the iOS app truly iPhone-friendly.

## Current implementation status as of April 3, 2026

The first app-shell slice is now in place in the Swift client:

- server host, port, and last username are persisted in the iOS app state
- the login screen now uses separate host and port fields instead of a desktop-style combined address field
- the client now performs the Java-compatible pre-login config bootstrap by opening a temporary socket, sending `opcode 19`, parsing the returned config packet, and then reconnecting for login
- key server config fields are now surfaced to the UI, including server name, welcome text, members-world state, and selected feature toggles

Validation:

- simulator build succeeded with `xcodebuild build -project iOS_Client/OpenRSC/OpenRSC.xcodeproj -scheme OpenRSC -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
- generic iPhone build succeeded with `xcodebuild build -project iOS_Client/OpenRSC/OpenRSC.xcodeproj -scheme OpenRSC -destination 'generic/platform=iOS' -derivedDataPath /tmp/OpenRSCDeviceBuild CODE_SIGNING_ALLOWED=NO`
- physical-device install is still blocked by signing because the project does not yet have a development team selected in Xcode

What it gives us:

- The shared Java client in [Client_Base/src](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src) contains the most complete game behavior and packet handling.
- The Android wrapper adds mobile-specific interaction patterns:
  - touch-to-click and hold-to-right-click in [InputImpl.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Android_Client/Open%20RSC%20Android%20Client/src/main/java/com/openrsc/android/render/InputImpl.java)
  - swipe-to-scroll, swipe-to-zoom, and swipe-to-rotate in [InputImpl.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Android_Client/Open%20RSC%20Android%20Client/src/main/java/com/openrsc/android/render/InputImpl.java)
  - soft-keyboard bridging and scaled bitmap rendering in [RSCBitmapSurfaceView.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Android_Client/Open%20RSC%20Android%20Client/src/main/java/com/openrsc/android/render/RSCBitmapSurfaceView.java)
  - local/LAN server selection and cache bootstrapping in [CacheUpdater.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Android_Client/Open%20RSC%20Android%20Client/src/main/java/com/openrsc/android/updater/CacheUpdater.java)

What it does not give us:

- A directly portable iOS UI layer. Android uses `SurfaceView`, `GestureDetector`, Android keyboard APIs, and Android resource/layout files.
- A modern iPhone-native layout strategy. The old client is still fundamentally a desktop-style 512x334 game surface adapted for mobile.
- A fully isolated reusable protocol module. The deepest protocol truth still lives in the shared Java client and must be ported carefully.

## Bottom line

Yes, the Android app and shared client contain enough reference behavior to finish the iOS app well.

No, they do not contain a drop-in iOS implementation.

The right approach is:

1. Treat [Client_Base/src](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src) as the protocol and gameplay reference.
2. Treat the Android app as the mobile interaction reference.
3. Treat [Local_RSC](/Users/brandonjconover/Documents/GitHub/Local_RSC) as a modern mobile UX and architecture reference.

## What still has to be built for iOS

### 1. Protocol parity

The iOS app still needs the core client behavior that exists in the shared Java client:

- pre-login server-config bootstrap via `opcode 19`
- full login packet parity, including client limitation/capability fields
- correct decoding of bit-packed player and NPC coordinate updates
- broader custom packet coverage beyond the current partial Swift packet handling

Primary references:

- [mudclient.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/mudclient.java)
- [PacketHandler.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/PacketHandler.java)
- [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java)

### 2. Mobile input model

The iOS app needs a touch-first control model instead of a desktop-first one:

- tap-to-move
- long-press for contextual/right-click behavior
- swipe gestures for panel control
- pinch-to-zoom
- optional drag/scroll behaviors for chat and lists
- keyboard handling for login/chat without awkward view jumps

Primary references:

- [InputImpl.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Android_Client/Open%20RSC%20Android%20Client/src/main/java/com/openrsc/android/render/InputImpl.java)
- [useGestures.js](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/hooks/useGestures.js)
- [GestureRecognizer.cs](/Users/brandonjconover/Documents/GitHub/Local_RSC/csharp-client/RSCClient.Core/Input/GestureRecognizer.cs)

### 3. Mobile-first layout

The current iOS app is still too close to a desktop game container. It needs:

- portrait and landscape layouts
- bottom-sheet or side-sheet panels depending on orientation
- quick access to chat, inventory, stats, map, quests, and combat
- large touch targets and gesture-safe spacing
- safe-area aware layout for Dynamic Island / home indicator devices

Useful references:

- [GamePage.jsx](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/pages/GamePage.jsx)
- [SettingsContext.jsx](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/context/SettingsContext.jsx)
- [GameView.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Views/GameView.swift)

### 4. Settings and persistence

The iOS app should persist:

- server host and port
- recent servers
- username
- control preferences
- gesture preferences
- display/accessibility settings
- audio settings

Useful references:

- [ClientPort.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/multiclient/ClientPort.java)
- [SettingsService.js](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/services/SettingsService.js)
- [SettingsService.cs](/Users/brandonjconover/Documents/GitHub/Local_RSC/csharp-client/RSCClient.Core/Services/SettingsService.cs)

### 5. Device polish

The iOS app still needs:

- network interruption/reconnect behavior
- background/foreground lifecycle handling
- haptics
- audio session management
- orientation-aware UI transitions
- clear error and status messaging

## Recommended finish plan

### Phase 1: Stabilize the protocol path

Goal:

- make the Swift client connect and reach a stable logged-in state against the Java protocol

Tasks:

- port `opcode 19` server-config request and config parsing
- port `tellLimitations(...)` login capability data
- fix bit-packed player/NPC/world update decoding
- add packet-level logging in Swift for comparison against Java client behavior

Acceptance criteria:

- iOS app can connect to the Java protocol
- login succeeds with the same account flow as the shared Java client
- player remains in-world without immediate desync

### Phase 2: Build the iPhone shell

Goal:

- make the app feel like an iPhone app rather than a desktop client in a phone frame

Tasks:

- create a real settings store
- persist server targets and last-used account
- redesign login screen for device use
- add connection status, reconnect status, and better error handling

Acceptance criteria:

- user can choose a local/LAN server easily
- login flow is usable on both Simulator and physical iPhone
- app state survives relaunch cleanly

### Phase 3: Add touch-first controls

Goal:

- replace mouse-first assumptions with mobile-first interactions

Tasks:

- implement tap-to-move
- implement long-press contextual action
- implement swipe panel control
- implement pinch zoom
- make chat and list areas scroll naturally

Acceptance criteria:

- core play loop works without relying on desktop-style precision tapping
- common actions are comfortable one-handed or two-handed on phone

### Phase 4: Redesign the in-game UI for mobile

Goal:

- make chat, inventory, map, stats, and actions usable on a small screen

Tasks:

- add portrait bottom-sheet layout
- add landscape side-panel layout
- add compact quick-stats/readouts
- design panel switching around gestures and tabs

Acceptance criteria:

- inventory, chat, stats, and map are all reachable within 1-2 taps
- no critical controls are obscured by the keyboard or safe areas

### Phase 5: Port high-value features from Local_RSC

Goal:

- borrow the good mobile UX ideas without inheriting its protocol shortcuts

Tasks:

- port settings categories and persistence ideas
- port gesture ideas and interaction tuning
- port panel organization ideas
- borrow cleaner service/state boundaries for Swift code organization

Acceptance criteria:

- Swift client architecture becomes easier to extend
- mobile UX improves without diverging from Java protocol truth

### Phase 6: Device polish and production readiness

Goal:

- make the app reliable on real iPhones

Tasks:

- add haptics and audio polish
- handle app background/foreground correctly
- handle reconnects cleanly
- test across portrait/landscape and multiple screen sizes
- add basic telemetry or local debug logging for protocol failures

Acceptance criteria:

- app can be installed on a physical iPhone
- app remains usable through normal mobile interruptions
- major gameplay screens are stable on phone-sized displays

## Suggested first implementation order

If we want the highest-value sequence, I would do this:

1. Port server-config bootstrap and remaining login parity
2. Add persisted server settings and a better login screen
3. Add long-press, swipe, and pinch gesture support
4. Redesign in-game panels for portrait and landscape
5. Fill in packet coverage for the most-used gameplay systems

## Recommendation

The Android app is enough to guide the mobile behavior, but the shared Java client is still the truth for correctness.

So the finish strategy should be:

- correctness from `Client_Base`
- mobile interaction ideas from Android
- modern UX structure from `Local_RSC`

That combination is enough to finish the iOS app well.

## What you need to do to deploy to your phone

The remaining blocker is Xcode signing, not Swift compilation.

To install on your iPhone:

1. Open [OpenRSC.xcodeproj](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC.xcodeproj) in Xcode.
2. Select the `OpenRSC` target.
3. Open `Signing & Capabilities`.
4. Sign in to Xcode with your Apple ID if it is not already added:
   - `Xcode > Settings > Accounts`
5. Choose your development team.
6. Enable `Automatically manage signing`.
7. If Xcode says the bundle identifier is unavailable, change it to something unique such as `com.yourname.openrsc`.
8. Connect your phone, trust the Mac, enable Developer Mode if prompted, and choose the device as the run destination.
9. Build and run from Xcode.

Known runtime constraint:

- when the game server is running on your Mac, a physical iPhone cannot use `localhost`; it must connect to your Mac's LAN IP or hostname instead
