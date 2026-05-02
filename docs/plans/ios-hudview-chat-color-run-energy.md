# Plan: iOS — HUDView channel-coloured chat + run-energy bar

> **Hand-off note for ChatGPT.** Read this whole file first. This plan is for the agent who owns `HUDView.swift` (per `iOS_Client/OpenRSC/REMAINING.md` "Avoid (other agents own these)" list). Touch only the files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`.

## Goal

Two cosmetic + UX wins that share the same view file:

1. **Channel-coloured chat** — `[Quest]`, `[Server]`, `[Trade]`, `[System]`, `[Magic]`, `[Kill]` all render white today (with kill the sole exception). Java mudclient tints each channel. Widen `RSCChatMessage`'s metadata + `chatColor()` so each channel gets a recognisable colour.
2. **Run/walk toggle + run-energy bar** — `worldState.fatigue` and run-related fields already arrive from the server. Add a small Run/Walk segmented control next to the existing combat-style chip in the HUD, plus a thin energy bar that drains while running.

Both items are unchecked in the iOS polish list and live in the avoid-listed `HUDView.swift`, so they're handed to its owner via this plan rather than picked up by the engine-only iteration loop.

## Why now

The data side is already wired (worldState carries the fatigue / run-energy / message-channel fields). We're only painting it. No protocol work, no new packets, no risk to the rendering pipeline.

## Scope (files you may edit)

- `iOS_Client/OpenRSC/OpenRSC/Sources/Views/Game/HUDView.swift` — channel colour switch + new Run/Walk chip + energy bar.
- `iOS_Client/OpenRSC/OpenRSC/Sources/GameEngine/RSC/RSCWorldState.swift` — extend `RSCChatMessage` with a `channel: ChatChannel` field (enum), backed by an `init(channel:)` overload; **keep** the existing `isLocal/isPrivate/isKill` booleans and derive `channel` from them in `addChat()` so existing call sites stay compiling.
- `iOS_Client/OpenRSC/OpenRSC/Sources/GameEngine/RSC/RSCPacketHandler.swift` — opt-in: where a handler logs a system/quest/trade/magic message, pass the explicit channel so it doesn't fall back to inference. **Don't** change the existing string sender prefix logic — the channel field is *additive*.
- `iOS_Client/OpenRSC/OpenRSC/Sources/GameEngine/RSC/RSCGameEngine.swift` — add `func toggleRun()` that flips `worldState.runEnabled` and sends opcode 185 (or whatever the modern server expects — confirm against `Client_Base/src/orsc/PacketHandler.java`). If the engine doesn't yet have a `runEnabled` field, add it.

## Out of scope (do NOT touch)

- iOS engine rendering (`RSCGameEngine.tick`, `Scene.swift`, `CharacterBillboards.swift`).
- Any other panel (`MinimapPanel`, `PrayerPanel`, etc.).
- The 530 web client.

## Reference (Java mudclient + server)

| What | Source | Notes |
|---|---|---|
| Chat channel colours | `Client_Base/src/orsc/MessageType.java` + `mudclient.java` `showMessage()` | RSC tints by `MessageType` enum: CHAT (white), QUEST (cyan), PRIVATE (cyan), TRADE (purple-ish), GAME/SYSTEM (yellow), GLOBAL (yellow). Authoritative palette: see `Client_Base/src/orsc/Config.java` `DEFAULT_CHAT_COLOUR_*` constants if exposed, else lift from screenshots. |
| Run/walk toggle outgoing opcode | `Client_Base/src/orsc/PacketHandler.java` (search `setRunMode` / `runMode`) — opcode 185 in custom OpenRSC | If our wire-protocol audit confirms the modern server still listens on 185, keep it. Otherwise port whatever opcode `server-java-modern/src/com/openrsc/server/net/rsc/handlers/` registers for `SetRunMode`. |
| Run-energy field | Already in `worldState.fatigue` (and possibly `runEnergy` — verify). | Java drains 1% every 6 ticks while running; server is authoritative, client just renders. |

## Implementation

### 1. Extend `RSCChatMessage`

```swift
enum ChatChannel: Int, Codable, CaseIterable {
    case chat = 0           // public local
    case privateMsg         // PM in/out
    case quest              // [Quest] / NPC quest dialogue
    case trade              // [Trade] / shop / trade
    case system             // [System] server announcements
    case kill               // kill announcements (red)
    case magic              // [Magic] cast hints
    case clan               // [Clan]
    case party              // [Party]
}

struct RSCChatMessage: Identifiable {
    // existing fields …
    let channel: ChatChannel

    init(sender: String, text: String,
         isLocal: Bool = false, isPrivate: Bool = false, isKill: Bool = false,
         channel: ChatChannel? = nil) {
        // … existing init body
        // Derive channel from legacy flags when caller didn't pass one.
        self.channel = channel ?? Self.deriveChannel(sender: sender,
                                                      isLocal: isLocal,
                                                      isPrivate: isPrivate,
                                                      isKill: isKill)
    }

    private static func deriveChannel(sender: String, isLocal: Bool,
                                       isPrivate: Bool, isKill: Bool) -> ChatChannel {
        if isKill { return .kill }
        if isPrivate { return .privateMsg }
        if isLocal { return .chat }
        switch sender {
        case "[Quest]":   return .quest
        case "[Trade]":   return .trade
        case "[System]":  return .system
        case "[Magic]":   return .magic
        case "[Clan]":    return .clan
        case "[Party]":   return .party
        default:          return .chat
        }
    }
}
```

This keeps every existing call site unchanged. New call sites can pass an explicit `channel:` to skip the string-prefix inference.

### 2. `chatColor()` in `HUDView.swift`

Replace the current 4-arm switch with a channel-driven palette. Numbers below match the desktop client's defaults; tweak only if the visual side feels off.

```swift
private func chatColor(_ msg: RSCChatMessage) -> Color {
    switch msg.channel {
    case .chat:        return .white
    case .privateMsg:  return Color(rgbHex: 0xC8FFFF)   // cyan
    case .quest:       return Color(rgbHex: 0xFFB347)   // orange
    case .trade:       return Color(rgbHex: 0xC8A951)   // gold (matches HUD accent)
    case .system:      return Color(rgbHex: 0xFFFF00)   // yellow
    case .kill:        return .red
    case .magic:       return Color(rgbHex: 0xC8C8FF)   // light violet
    case .clan:        return Color(rgbHex: 0x88FF88)   // light green
    case .party:       return Color(rgbHex: 0xFFFF88)   // light yellow
    }
}
```

If `Color(rgbHex:)` isn't available, the codebase has a `Color(hex:)` initializer in `WelcomePanel.swift` — reuse that signature.

### 3. Run/Walk chip + energy bar

Add a horizontal stack inside whatever HUD region the combat-style chip sits in (search `combatStyle` in HUDView.swift to find the existing chip).

```swift
HStack(spacing: 6) {
    // existing combat-style chip …
    runWalkChip()
    runEnergyBar()
}

@ViewBuilder
private func runWalkChip() -> some View {
    Button(action: { engine.toggleRun() }) {
        HStack(spacing: 3) {
            Image(systemName: worldState.runEnabled ? "figure.run" : "figure.walk")
            Text(worldState.runEnabled ? "Run" : "Walk").font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .overlay(Capsule().stroke(Color(hex: "#c8a951"), lineWidth: 1))
        .clipShape(Capsule())
        .foregroundColor(.white)
    }
}

@ViewBuilder
private func runEnergyBar() -> some View {
    let energy = max(0.0, min(1.0, Double(worldState.runEnergy) / 100.0))
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.5))
            RoundedRectangle(cornerRadius: 2)
                .fill(energy > 0.3 ? Color.green : Color.orange)
                .frame(width: geo.size.width * energy)
        }
    }
    .frame(width: 60, height: 6)
}
```

If `worldState.runEnergy` doesn't exist yet, add it as `@Published var runEnergy: Int = 100` and wire the relevant packet handler that delivers it (search server source for SET_RUN_ENERGY or similar). If the field name is `worldState.fatigue` repurposed, document that in the chip's tooltip.

### 4. `engine.toggleRun()`

```swift
func toggleRun() {
    worldState.runEnabled.toggle()
    Task {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.setRunMode.rawValue))
        buf.putByte(worldState.runEnabled ? 1 : 0)
        try? await connection.send(buf.finishPacket())
    }
}
```

If `RSCOutOpcode.setRunMode` doesn't exist, audit `RSCOutOpcode.swift` for an existing entry first; only add a new case after verifying the modern server's expectation. If you can't confirm the opcode, **don't guess** — log a TODO and ship the visual chip with an inert `toggleRun()` (better than a wrong-opcode disconnect).

### 5. Build

```bash
cd /Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC \
  && xcodegen generate \
  && xcodebuild -project OpenRSC.xcodeproj -scheme OpenRSC \
       -configuration Debug \
       -destination 'id=00008130-000805D10AF0001C' \
       -derivedDataPath /tmp/openrsc-build-ralph build
```

Must report `BUILD SUCCEEDED`. iPhone 15 Pro device id is `00008130-000805D10AF0001C`. If the device is unreachable, fall back to `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` to confirm compile-only.

## Acceptance criteria

1. Tapping the chip flips Run/Walk visibly; the icon + label update; the corresponding packet is sent (verify by reading the Console output for the opcode line).
2. Running drains the energy bar live as the player moves; idle/walking refills it (server-driven — we just render).
3. Each chat channel renders in its assigned colour; existing call sites still compile (legacy boolean flags continue working).
4. Build succeeds.
5. Update [`iOS_Client/OpenRSC/REMAINING.md`](../../iOS_Client/OpenRSC/REMAINING.md): tick the "Channel-coloured chat" and "Run/walk toggle + run-energy bar" entries with commit SHAs inline.

## Out of scope clarifications

- **Don't refactor the chat scrollback.** Just paint colours.
- **Don't add a settings page** for chat colours; lift the 9-colour palette from the table above and ship.
- **Don't widen `ChatChannel` past the listed cases** without checking — broader enums creep into tests/storage and we'd rather grow it on demand.
- **Don't touch the kill announcement path** — it already uses `isKill` and renders red; the new switch keeps that working.

## Commit guidance

Two commits is fine:

1. `iOS: tint chat by channel`
2. `iOS: run/walk chip + energy bar`

Push nothing.
