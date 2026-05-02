# Plan: iOS — local preference persistence (UserDefaults)

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. Small, contained, no protocol work.

## Goal

Persist a small set of client-side preferences across app launches via `UserDefaults`, so the player doesn't have to re-toggle them every session. Today nothing is persisted — every fresh launch resets chat filters, sound, run-default, etc. to engine-side defaults.

## Why now

This is the smallest correctness win on the iOS polish list — no new packets, no rendering, no view-hierarchy churn. It also paves the way for the HUDView Run/Walk chip plan (the chip's "default to running" preference is the obvious first persisted setting).

## Scope (files you may edit)

- `iOS_Client/OpenRSC/OpenRSC/Sources/Models/UserPreferences.swift` — new file, the entire persistence layer.
- `iOS_Client/OpenRSC/OpenRSC/Sources/GameEngine/RSC/RSCWorldState.swift` — add the published mirror fields (chat-filter / sfx-mute / music-mute / run-default) so views can `@ObservedObject` against them.
- `iOS_Client/OpenRSC/OpenRSC/Sources/GameEngine/RSC/RSCGameEngine.swift` — call `UserPreferences.load()` in `init()` to seed `worldState` from disk; subscribe to changes and flush via `UserPreferences.save(...)`.

## Out of scope (do NOT touch)

- HUDView, MinimapPanel, etc. — UI bindings can come later.
- `Models/AppState.swift` — that's the global app router; keep persistence separate.
- iCloud sync. UserDefaults only.
- 530 web client.

## Reference

Apple's `UserDefaults` is the right primitive: synchronous read, async-debounced write to disk by the OS, free for ~< 4 MB of data. We are persisting a handful of bools and ints — total payload ~50 bytes.

## Implementation

### 1. `UserPreferences.swift`

```swift
import Foundation

/// Lightweight UserDefaults-backed preferences. Loaded once on engine
/// init, written back via `save(...)` whenever a published mirror field
/// changes. No iCloud sync — strictly per-device for now.
struct UserPreferences: Codable, Equatable {
    // Chat filter — false = show, true = hide (matches Java's
    // chat-filter "off / friends / hide" tri-state collapsed to boolean
    // for v1; promote to the tri-state once the network packet that
    // carries it is consumed by HUDView).
    var hidePublicChat: Bool = false
    var hidePrivateChat: Bool = false
    var hideTradeRequests: Bool = false
    var hideDuelRequests: Bool = false

    // Sound + music — independent mutes, defaults on.
    var sfxMuted: Bool = false
    var musicMuted: Bool = false

    // Run/walk — true means "default to running" when the engine sends
    // its first walk command of the session.
    var runByDefault: Bool = false

    // Camera — last-known yaw/pitch/zoom so reopening the app drops
    // the player into the same camera angle. 0 means "use default".
    var lastCameraYawDegrees: Double = 0
    var lastCameraPitchDegrees: Double = 0
    var lastCameraZoom: Double = 0

    // MARK: - Persistence

    private static let key = "openrsc.userPreferences.v1"
    private static let defaults: UserDefaults = .standard

    /// Reads the current persisted prefs, or `default` if none / decode fails.
    static func load() -> UserPreferences {
        guard let data = defaults.data(forKey: key) else { return UserPreferences() }
        return (try? JSONDecoder().decode(UserPreferences.self, from: data)) ?? UserPreferences()
    }

    /// Writes the prefs to UserDefaults. Cheap (≤200 µs) and safe to call
    /// on every change. The OS debounces disk flushes.
    static func save(_ prefs: UserPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: key)
    }

    /// Clears the stored prefs. Used by the "Reset to defaults" affordance
    /// (HUDView SettingsPanel — separate plan).
    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
```

**Versioning:** Bump the storage key to `v2` if the struct gains a non-defaultable field (i.e. requires migration). Decode failures silently fall back to defaults.

### 2. Mirror fields on `RSCWorldState`

Add `@Published` mirrors so views observe them through the existing engine-forwarded `objectWillChange` chain:

```swift
@Published var preferences: UserPreferences = UserPreferences()
```

That's it for the world-state side. Views read `engine.worldState.preferences.runByDefault`, etc.

When a view (e.g. HUDView's settings panel — that's a separate plan) wants to mutate a preference, it does:

```swift
engine.updatePreferences { p in p.runByDefault.toggle() }
```

### 3. `RSCGameEngine` glue

```swift
init() {
    // … existing init body
    worldState.preferences = UserPreferences.load()
}

/// Mutates the live `worldState.preferences` and flushes to UserDefaults.
/// Use this instead of writing the field directly so views, persistence,
/// and any future migration logic stay aligned.
@MainActor
func updatePreferences(_ mutate: (inout UserPreferences) -> Void) {
    var prefs = worldState.preferences
    mutate(&prefs)
    if prefs == worldState.preferences { return }  // no-op
    worldState.preferences = prefs
    UserPreferences.save(prefs)
}
```

If a published mirror is set directly (bypassing `updatePreferences`), persistence won't run — that's intentional, the mutator is the one and only write path.

### 4. Camera-angle convenience hook

Persist camera angles on a debounced cadence (don't write every frame). Add to `tick()`:

```swift
// Save camera every ~5s to bound disk writes; cheaper than dirty-tracking.
if renderLogCount % 100 == 0 {  // 100 ticks × 50ms = 5s
    let yaw = cameraRotationDegrees
    let pitch = cameraPitchDegrees
    let zoom = Double(cameraZoom)
    if abs(yaw - worldState.preferences.lastCameraYawDegrees) > 1
        || abs(pitch - worldState.preferences.lastCameraPitchDegrees) > 1
        || abs(zoom - worldState.preferences.lastCameraZoom) > 50 {
        updatePreferences { p in
            p.lastCameraYawDegrees = yaw
            p.lastCameraPitchDegrees = pitch
            p.lastCameraZoom = zoom
        }
    }
}
```

On launch, after the world loads:

```swift
if worldState.preferences.lastCameraYawDegrees != 0 {
    setCameraRotationDegrees(worldState.preferences.lastCameraYawDegrees)
    setCameraPitchDegrees(worldState.preferences.lastCameraPitchDegrees)
    cameraZoom = Int32(worldState.preferences.lastCameraZoom)
}
```

### 5. Build

```bash
cd /Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC \
  && xcodegen generate \
  && xcodebuild -project OpenRSC.xcodeproj -scheme OpenRSC \
       -configuration Debug \
       -destination 'id=00008130-000805D10AF0001C' \
       -derivedDataPath /tmp/openrsc-build-ralph build
```

Must report `BUILD SUCCEEDED`.

## Acceptance criteria

1. App launches, log in, change camera angle, force-quit. Relaunch — camera angle restored within ±2° / ±100 zoom of last session.
2. `UserPreferences.load()` returns a `UserPreferences` with sane defaults on a fresh install.
3. `UserPreferences.save(p) → load()` round-trips every field.
4. Build succeeds.
5. Update `iOS_Client/OpenRSC/REMAINING.md`: tick the "Local stash of preferences" entry with commit SHA inline.

## Out of scope clarifications

- **Don't add a Settings UI** — that's a follow-up plan for the SettingsPanel owner. This plan only ensures the model + glue works so the future UI just binds.
- **Don't sync to iCloud.** Adding `NSUbiquitousKeyValueStore` introduces account/identity complexity; punt.
- **Don't persist sensitive data** (passwords, tokens). Only cosmetic + UX prefs.
- **Don't migrate from any prior storage** — this is the first iteration; `load()` returning defaults on missing data is the correct behaviour.

## Commit guidance

Single commit, message `iOS: persist UI prefs to UserDefaults`. Push nothing.
