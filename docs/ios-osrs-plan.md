# iOS OSRS Client Plan

## Goal

Add Old School RuneScape (OSRS) support to the existing OpenRSC iOS app so a single app can connect to both RSC and OSRS private servers.

## Current State

The RSC iOS client work is tracked in `ios-mobile-finish-plan.md`. The iOS project lives at `iOS_Client/OpenRSC/OpenRSC.xcodeproj`. OSRS support is a separate protocol module that shares the networking, rendering, and UI shell with RSC.

## Protocol Overview

OSRS uses a fundamentally different protocol from RSC:

- ISAAC cipher is applied to every packet opcode (both directions), not just optionally
- RSA-encrypted login block (BigInteger modpow, not just a simple RSA call)
- JS5 cache delivery service runs before the game login
- Packet sizes use different length encoding
- The OSRS iOS client type is `2` (distinct from desktop `0` and Android `1`)
- Revision numbering: target a fixed revision (221–237 supported by blurite/rsprot)

Key references:
- [blurite/rsprot](https://github.com/blurite/rsprot) — Kotlin, definitive OSRS packet structure for revisions 221–237
- [runelite/runelite](https://github.com/runelite/runelite) — Java desktop client, protocol behavior reference
- [blurite/rsprox](https://github.com/blurite/rsprox) — OSRS traffic proxy, useful for observing packet flow

## Architecture

OSRS adds three new modules alongside the existing RSC modules:

```
iOS_Client/OpenRSC/OpenRSC/Sources/
├── Network/
│   ├── RSC/           (existing)
│   └── OSRS/
│       ├── OSRSConnection.swift       — two-phase connect: JS5 then game login
│       ├── OSRSLoginHandler.swift     — RSA login block builder
│       ├── OSRSPacketEncoder.swift    — ISAAC opcode scrambling, outgoing packets
│       ├── OSRSPacketDecoder.swift    — ISAAC opcode unscrambling, incoming packets
│       ├── OSRSOpcodes.swift          — server-to-client and client-to-server opcode tables
│       └── JS5/
│           ├── JS5Connection.swift    — cache request/response protocol
│           └── JS5CacheManager.swift  — local cache storage (Application Support)
├── Crypto/
│   └── BigIntegerRSA.swift            — modpow for login block encryption (attaswift/BigInt)
└── GameEngine/
    └── OSRS/
        ├── OSRSGameEngine.swift       — packet dispatch, world state update loop
        ├── OSRSWorldState.swift       — players, NPCs, objects, ground items, region tiles
        └── OSRSRenderer.swift         — pixel buffer → MTLTexture (same pattern as RSC)
```

Shared with RSC (no duplication needed):
- `ByteBuffer.swift`
- `ISAACCipher.swift`
- `TCPConnection.swift`
- `MetalRenderer.swift`
- `TouchTranslator.swift`
- `ServerProfile` model
- `GameSelectorView`, `LoginView`, `ServerBrowserView`

## Phase 1 — JS5 Cache Handshake

The client must download the OSRS cache before any game login.

**JS5 Protocol Flow:**

1. Connect TCP to port 43594
2. Send service byte `15` (JS5/update service)
3. Receive 8-byte handshake response
4. Send cache requests: `[byte type, int groupId]`
5. Receive responses: `[byte type, int groupId, bytes data]`
6. Store in `Application Support/osrs-cache/index{N}/{groupId}`

The cache is ~200MB for a full OSRS client. For a private server, this may be smaller depending on what the server serves.

**Implementation notes:**
- Use a separate `NWConnection` for JS5, distinct from the game connection
- JS5 must complete before game login
- Cache version must match the server's expected revision
- For private OSRS servers, confirm the revision and cache version with the server admin

## Phase 2 — Login Block

OSRS login is more complex than RSC:

```
Login block (encrypted with RSA):
  [byte 0xa]                  — magic
  [int[] isaac_seeds]         — 4 ints = client ISAAC seed
  [long uid]                  — client UID
  [string username]           — null-terminated
  [string password]           — null-terminated

Login packet (sent over game connection):
  [byte 16]                   — login service type
  [byte revision_major]
  [byte revision_minor]
  [short rsaBlockSize]
  [bytes rsaBlock]            — RSA-encrypted login block above
  [bytes isaac_seeds_xored]   — server ISAAC seed XOR'd with client seed
```

The RSA modulus and exponent come from the server. For private servers, use the server's configured public key.

**BigInteger.modpow:** iOS does not have a built-in arbitrary-precision integer library. Add [attaswift/BigInt](https://github.com/attaswift/BigInt) via Swift Package Manager.

## Phase 3 — ISAAC Opcode Encoding

After successful login, every outgoing packet's opcode byte is XOR'd with the next value from the client ISAAC cipher. Every incoming packet's opcode byte is XOR'd with the next value from the server ISAAC cipher.

The cipher seeds come from the login response.

```swift
// Encoding outgoing packet opcode
let scrambledOpcode = opcode ^ Int(clientCipher.next() & 0xFF)
buffer.putByte(scrambledOpcode)

// Decoding incoming packet opcode
let unscrambledOpcode = rawOpcode ^ Int(serverCipher.next() & 0xFF)
```

This must be applied after the login handshake completes. RSC does not use ISAAC for game packets (only optionally for login in some revisions).

## Phase 4 — Packet Coverage

Start with the minimum set needed to reach a playable state:

| Opcode Group | Client → Server | Server → Client |
|---|---|---|
| Movement | Walk here, Run here | Player update, NPC update |
| Login | Login packet | Login response, player info |
| Chat | Public chat, command | Chat messages |
| Interface | Button click, interface close | Interface opened, interface set text |
| Inventory | Item use, item drop, equip | Inventory update |
| Map | Region change request | Map region load |

Reference: `blurite/rsprot` `osrs-221/` through `osrs-237/` directories for packet definitions.

## Phase 5 — Rendering

OSRS rendering for a private server follows the same Metal texture blit pattern as RSC:

1. The game engine maintains a `[Int32]` pixel buffer at the game resolution
2. Each frame: upload pixels to `MTLTexture`, blit full-screen via Metal passthrough shader
3. Later iteration: implement tile-based 2D renderer or hook into an existing OSRS renderer reference

For an MVP, the pixel-buffer approach matches how the original OSRS client rendered on older hardware.

## Server Targeting

Develop OSRS support against a **private OSRS server only**, not live Jagex servers:
- [OpenRS2](https://github.com/openrs2/openrs2) — comprehensive OSRS server framework, good protocol reference
- Any existing OSRS private server (Alora, etc.) requires their permission — use your own

**Legal note:** Connecting to live OSRS (Jagex) servers violates their Terms of Service. This feature is for private server use only.

## Revision Pinning

Pick one OSRS revision and pin to it. Revision 221 is a good starting point:
- All rsprot decoders exist for 221
- Many private servers run 221 or are close to it
- OpenRS2 has full cache support for 221

Document the revision in `iOS_Client/OpenRSC/OpenRSC/Sources/Network/OSRS/OSRSConnection.swift` as a constant: `static let REVISION = 221`.

## Milestones

| Milestone | Success Criteria |
|---|---|
| M1 — JS5 handshake | Client completes cache download from a private OSRS server |
| M2 — Login | Client logs in and receives login response packet |
| M3 — World visible | Player coordinates received, blank world renders |
| M4 — Movement | Tap-to-walk works, player moves on screen |
| M5 — Inventory | Item list visible and tappable |
| M6 — Chat | Chat messages sent and received |
| M7 — Full gameplay MVP | All core loops (combat, skills, banking) accessible |

## Key Risks

1. **Weekly opcode shuffles on live OSRS** — irrelevant if targeting private servers with a pinned revision
2. **Cache size** — 200MB download on first launch; show progress UI and handle errors cleanly
3. **RSA key management** — each private server has its own keys; store per server profile
4. **ISAAC state sync** — ISAAC desync causes all subsequent packets to fail; add a desync detection/reconnect path
