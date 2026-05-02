# Plan: 530 web client — Tier 5b player + chat state opcodes

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. Tier 5a (zone-update opcodes) is a sibling plan; if it hasn't merged yet, treat the file lists as "edit alongside whatever 5a touched". Don't undo 5a's work.

## Goal

Decode 14 player-state and chat opcodes that today are silently dropped. After this lands, teleports stop showing a frame of the old region, private/clan chat actually appears, the chat filter settings tab reflects server state, the run-weight indicator updates, and the last-login banner data is captured.

## Why this is next

Tier 5a fixed the *world* state. Tier 5b fixes the *player* state — the second largest source of "the game is in sync but the UI lies" bugs.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — 14 new `case` branches.
- `2009scape-web/client-patch/osrs/Game.ts` — add new world-state fields listed below; do not refactor existing fields.
- `2009scape-web/client-patch/osrs/util/ChatFilterSettings.ts` — new file (5 enum-shaped fields).
- `2009scape-web/client-patch/osrs/util/PrivateMessageQueue.ts` — new file (in-memory ring buffer of received PMs).
- `2009scape-web/client-patch/README.md` — update the deferred bullet only if it mentions Tier 5b.

## Out of scope (do NOT touch)

- Renderer, cache, login, buffer helpers.
- iOS client (`iOS_Client/**`).
- Server side of the wire protocol (we only consume).
- Audio (Tier 5d / Tier 8).
- Widgets (Tier 7) — chat filter settings persists to a model only; no UI yet.

## Reference (rt4-client)

All paths under `reference/rt4-client/client/src/main/java/rt4/`.

| Opcode | Name | rt4 file:line | Notes |
|---|---|---|---|
| 13 | `TELEPORT_LOCAL_PLAYER` | `Protocol.java:1543-1550` | sets `Player.plane = flags >> 1`; `PlayerList.self.teleport(pos1, (flags & 1) == 1, pos2)`. Just two `g1*` reads + the plane bit. |
| 89 | `RESET_CLIENT_VARCACHE` | `Protocol.java:1294+` | wipes client-side varc cache. We don't have one yet — record-and-no-op is fine, but read 0 bytes. |
| 128 | `FORCE_VARP_REFRESH` | `Protocol.java:1634+` | re-asks server for a varp; reads `g2` of varpId. |
| 131 | `RESET_ANIMS` | `Protocol.java:1847+` | clears all in-flight character animations on logout/teleport. Iterate `game.npcs530` + `game.players530`, set `animation = -1`. |
| 142 | `SET_SETTINGS_STRING` | `Protocol.java:2309+` | per-settings string slot. `g1` slot, `gjstr` string. Stash on `game.settingsStrings: string[256]`. |
| 159 | `UPDATE_RUNWEIGHT` | `Protocol.java:1790+` | reads `g2`, stash on `game.runWeight`. |
| 160 | `SET_WALK_TEXT` | `Protocol.java:1626-1633` | reads a string, stash on `game.walkText`. Rendered later by minimap (Tier 7). |
| 164 | `LAST_LOGIN_INFO` | `Protocol.java:1203-1219` | last login IP (g4), days-ago (g2), recovery-days (g2). Mirror the iOS welcome dialog data. Stash on `game.lastLogin = {ip, daysAgo, recoveryDays}`. |
| 169 | `UPDATE_UID192` | `Protocol.java:1290+` | reads `g4`, stash on `game.uid192` for anti-cheat correlation. |
| 191 | `DELETE_INVENTORY` | `Protocol.java:1774-1789` | reads `g2add` containerId, then `ig2` slot count; clear `game.inventory[slotStart..slotEnd]`. |
| 232 | `CHAT_FILTER_SETTINGS` | `Protocol.java:1220-1239` | three `g1` flags (public/private/trade). Push into `ChatFilterSettings.fromServer()`. |

Chat:

| Opcode | Name | rt4 file:line |
|---|---|---|
| 0 | `MESSAGE_PRIVATE` | `Protocol.java:1944+` (long g8 sender + g2 top + g3 bot + g1 rights + variable-length quickchat or jagstring body) |
| 71 | `MESSAGE_PRIVATE_ECHO` | `Protocol.java:1796+` (own outgoing PM echoed back) |
| 247 | `MESSAGE_QUICKCHAT_PRIVATE` | search `Protocol.java` for `MESSAGE_QUICKCHAT_PRIVATE` |
| 141 | `MESSAGE_QUICKCHAT_PRIVATE_ECHO` | search `Protocol.java` for `MESSAGE_QUICKCHAT_PRIVATE_ECHO` |
| 54 | `MESSAGE_CLANCHANNEL` | `Protocol.java:1987+` |
| 81 | `CLAN_QUICK_CHAT` | `Protocol.java:1107+` |
| 196 | `UPDATE_CLAN` | `Protocol.java:2172+` (large — see specific subroutine; just port the parse, store on `game.clanState`) |

## Implementation

### 1. New world-state on `Game`

```ts
public lastLogin: { ip: number; daysAgo: number; recoveryDays: number } | null = null;
public runWeight: number = 0;
public walkText: string = '';
public settingsStrings: string[] = new Array(256).fill('');
public uid192: number = 0;
public chatFilter = ChatFilterSettings.default();
public privateMessages = new PrivateMessageQueue();
public clanState: ClanState | null = null;
```

`ClanState` is just `{ name: string; world: number; rank: number; members: ClanMember[] }`. Port enough fields to round-trip the parse — don't gold-plate.

### 2. `ChatFilterSettings.ts`

```ts
export class ChatFilterSettings {
    public publicFilter = 0;   // 0=on, 1=friends, 2=off
    public privateFilter = 0;
    public tradeFilter = 0;

    static default(): ChatFilterSettings { return new ChatFilterSettings(); }

    static fromServer(buf: Buffer): ChatFilterSettings {
        const s = new ChatFilterSettings();
        s.publicFilter = buf.g1();
        s.privateFilter = buf.g1();
        s.tradeFilter = buf.g1();
        return s;
    }
}
```

### 3. `PrivateMessageQueue.ts`

```ts
export interface PrivateMessage {
    senderName: string;     // resolved later — store name37 raw for now
    senderName37: bigint;
    rights: number;
    body: string;
    receivedAt: number;
}

export class PrivateMessageQueue {
    private buf: PrivateMessage[] = [];
    private cap = 100;

    push(msg: PrivateMessage) {
        this.buf.push(msg);
        if (this.buf.length > this.cap) this.buf.shift();
    }

    all(): PrivateMessage[] { return this.buf.slice(); }
}
```

### 4. Implement the 14 cases

Match the rt4 order: read every byte rt4 reads, in the same order. For chat opcodes, the trickiest part is the body, which is one of:

- A `gjstr` (null-terminated string).
- A "huffman-shrunk" body whose 5-byte header you can record-and-no-op for now (we don't have huffman decode yet — push a placeholder body string `"[quickchat]"` and **note this is a known gap**).

Place every parse step in a comment that names the rt4 line. Future review wants to be able to spot the divergence in 5 seconds.

### 5. Self-test

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
```

`BUILD SUCCEEDED` (zero TS errors). No runtime test target this tier.

## Acceptance criteria

1. Dispatcher's handled-opcode count rises to 68 + 14 = 82 of 97.
2. `Game` exposes the new fields listed in §1.
3. `npm run build` succeeds with zero TS errors.
4. `docs/web-client-plan.md` Tier 5b checklist all ticked, each line with the implementing commit SHA.

## Out of scope clarifications

- **Quickchat body decoding** uses Huffman tables we don't have ported. For 247/141/81, advance the buffer past the body length (1-byte length prefix + `length` bytes) and stash a placeholder string — leave a `// TODO Huffman decode (Tier 8)` comment. Do not block this tier on it.
- **Surfacing the chat in UI** is a render-side concern. We just need the data captured.
- `UPDATE_FRIENDLIST` already lives in our handler list; do not duplicate it.

## Commit guidance

Group by subsystem; commits prefixed `2009scape-web: tier5b — ` (e.g. `tier5b — TELEPORT_LOCAL_PLAYER + RESET_ANIMS`, `tier5b — chat filter + private messages`). Push nothing.
