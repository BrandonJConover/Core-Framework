# 2009scape Web Client — rev 530 patches

Drop-in patches over the upstream 377 web client (`reinismu/runescape-web-client-377`)
that make it talk to the rev-530 2009scape server.

## Layout

Files mirror the path they overlay in the upstream client. `setup.sh` does a
`cp -R client-patch/osrs/. client/osrs/` so new files land alongside their
upstream peers and modifications overwrite cleanly.

Root-level upstream client patches live in `client-patch/root/` and are copied
with the same mirror semantics onto `client/`. This currently patches
`index.html` (for the legacy `window.__exports` global expected by the Parcel
bundle) and the tiny Rust/WASM crate so local builds work on modern Rust.

```
client-patch/osrs/
├── Configuration.ts          # SERVER_ADDRESS, GAME_PORT (43601)
├── Game.ts                   # Cache auto-detect + startUp markers + null-tolerant init
├── GameShell.ts              # Mobile / canvas focus tweaks
├── Js5Cache.ts               # NEW — TS port of rt4-client cache reader (Js5 sectors + Index meta + decompression)
├── PacketHandler530.ts       # NEW — dispatches ~52 server opcodes
├── cache/
│   ├── Archive.ts            # Null-tolerant 377 archive parser (graceful with 530 data)
│   └── media/
│       ├── ImageRGB.ts       # Stub fallback when archive missing
│       ├── IndexedImage.ts   # Stub fallback
│       ├── TypeFace.ts       # Blank-font fallback
│       └── Widget.ts         # Stub widget for missing IDs
├── net/
│   ├── Buffer.ts             # 377→530 OUTGOING_REMAP, NUL-terminator putString, null-tolerant gets
│   ├── Login530.ts           # NEW — rev 530 login handshake
│   └── PacketConstants.ts    # 530 packet sizes (RT4 authoritative)
├── net/requester/
│   └── OnDemandRequester.ts  # Tolerates empty versionlist archive
├── sound/
│   └── SoundTrack.ts         # Position-bound break in load() — fixes empty-buffer infinite loop
└── util/
    ├── PacketConstants.ts    # (legacy location)
    └── SignLink.ts           # CLIENT_REVISION = 530
```

## What works (committed state)

Verified via Playwright:

- Login handshake (11-byte response, RSA, ISAAC no-op)
- Session stable (PING keepalive every ~1.7s)
- Static UI chrome renders
- Server chat messages display
- `::command` round-trip works
- 530 cache loads without error: `startUp()` completes through all markers including `Widget.load`
- Auto-detects cache format (peeks sector 2 byte 7 → 0=530, non-zero=377)

## Local → Hetzner login path

For local development against the WireGuard-hosted server:

```bash
cd 2009scape-web
scripts/use-530-cache.sh
scripts/set-client-server.sh 10.8.0.1
cd client && npm run build
npx serve dist -l tcp://127.0.0.1:8600
```

If the browser opens `ws://10.8.0.1:43601/` but never receives a frame after
sending the first 2-byte login handshake, check the Hetzner server reactor:

```bash
cd 2009scape-web
scripts/check-hetzner-login-path.sh
```

The expected raw TCP probe response from `10.8.0.1:43600` is 9 bytes beginning
with `00`. If this hangs, the `2009scape-server` container may still show as
`Up` while its `NioReactor` thread has died (observed after a Java heap
`OutOfMemoryError`). Restarting `server` and `websockify` in
`/opt/2009scape-web` restores the WebSocket login path.

## What's deferred

- Real fonts/sprites from idx8/idx13 — currently stubbed to blank
- Real widgets from idx3/idx13/idx8 — currently stubbed
- Real def parsers (Item/NPC/Object/Floor) — 530 byte format ports needed
- World rendering (RT5 models, skeletons/skins, HD textures)
- Outgoing interactions (walk/click/inv) — currently suppressed except keepalive + chat-command

See [project_2009scape_web_state.md](../../.claude/.../memory/project_2009scape_web_state.md) for full status.

## Cache file note

`setup.sh` clones the upstream 377 client which ships its own `client_cache/`. To
run against the 530 server you must replace `client/client_cache/main_file_cache.dat`
and the idx0-idx4 files with the 530 cache (`main_file_cache.dat2` renamed to `.dat`,
plus idx0-idx4 from 2009scape's `Server/data/cache/`). The auto-detect in `Game.ts
initStores` handles either format.

## Reference

- Authoritative rt4-client deob: `~/Documents/GitHub/Core-Framework/reference/rt4-client/`
- 530 server source: `/opt/2009scape-web/2009scape/Server/src/main/` on hetzner-phantom
- Deployed instance: http://10.8.0.1:8500/ (over WireGuard)
