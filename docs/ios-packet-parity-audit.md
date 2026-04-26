# iOS Packet Parity Audit

Date: 2026-04-04

## Summary

The current iOS client does not match the Java server's packet formats throughout.

What is aligned:

- The iOS client uses the server's custom "inauthentic" login/bootstrap path.
- The bootstrap request `opcode 19` is aligned.
- The base login packet shape is aligned enough for the server to accept it.
- Many outgoing and incoming opcode numbers match the server's custom/203-era opcode map.

What is not aligned:

- Client-to-server and server-to-client frame length semantics are not identical.
- Several iOS outbound gameplay packets use the wrong opcode or the wrong payload encoding.
- Several iOS inbound packet decoders assume simpler payloads than the server actually sends.
- The iOS client does not yet implement the server's bit-packed mob update formats.

## Transport Framing

Directionally, the app and server are compatible today, but they are not literally using one symmetric framing rule in both directions.

Client to server:

- iOS writes `[length][opcode][payload]` where `length = opcode + payload bytes`.
- Reference: [NetworkClient.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/NetworkClient.swift#L322)
- Server custom decoder expects the same for inauthentic clients.
- Reference: [RSCProtocolDecoder.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/RSCProtocolDecoder.java#L328)

Server to client:

- Server writes `[length][opcode][payload]` where `length = full frame bytes including the 2-byte length header`.
- Reference: [RSCProtocolEncoderMain.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/RSCProtocolEncoderMain.java#L40)
- iOS reads the same convention on receive.
- Reference: [NetworkClient.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/NetworkClient.swift#L255)

This means the transport works, but it is asymmetric.

## Confirmed Matches

### Bootstrap

- iOS sends `opcode 19` with no payload to request server configs.
- Reference: [GameClient.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Models/GameClient.swift#L96)
- Server explicitly handles `opcode 19` as the custom server-config bootstrap.
- Reference: [RSCConnectionHandler.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/RSCConnectionHandler.java#L93)

### Base Login

- iOS sends:
  - reconnect flag byte
  - 4-byte client version
  - line-feed terminated username
  - line-feed terminated password
  - 8-byte uid placeholder
- Reference: [GameClient.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Models/GameClient.swift#L115)
- Server's inauthentic login path reads those same base fields.
- Reference: [LoginPacketHandler.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/LoginPacketHandler.java#L471)

## Confirmed Mismatches

### Outbound: walk packet uses the wrong opcode

- iOS `walkTo` sends opcode `16`.
- Reference: [GameClient.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Models/GameClient.swift#L490)
- On the server custom parser, `16` maps to `WALK_TO_ENTITY`, not `WALK_TO_POINT`.
- `WALK_TO_POINT` is `187`.
- Reference: [PayloadCustomParser.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/parsers/impl/PayloadCustomParser.java#L29)

### Outbound: logout packet uses the wrong opcode

- iOS `logout()` sends opcode `1`.
- Reference: [GameClient.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Models/GameClient.swift#L511)
- The custom parser recognizes logout as `102` and confirm-logout as `31`.
- Opcode `1` is not a valid logged-in custom opcode there.
- Reference: [PayloadCustomParser.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/parsers/impl/PayloadCustomParser.java#L39)

### Outbound: chat payload encoding is wrong

- iOS sends chat message opcode `216` with a plain line-feed terminated string.
- Reference: [GameClient.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Models/GameClient.swift#L505)
- The server custom parser expects `CHAT_MESSAGE` to be an RSC encrypted string payload, not a plain terminated string.
- Reference: [PayloadCustomParser.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/parsers/impl/PayloadCustomParser.java#L508)

### Inbound: packed mob coordinate packets are decoded incorrectly

- The server sends `SEND_NPC_COORDS` and `SEND_PLAYER_COORDS` using bit access and variable-width bit fields.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L809)
- The iOS client tries to read those packets as plain shorts and bytes.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L298)

### Inbound: appearance/update packets are decoded incorrectly

- The server writes `SEND_UPDATE_NPC` and `SEND_UPDATE_PLAYERS` as a heterogenous stream of bytes, shorts, ints, appearance bytes, and strings.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L819)
- The iOS client assumes a fixed simplified structure.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L343)

### Inbound: inventory packet shape is wrong

- Server inventory packet includes:
  - item id
  - wielded flag byte
  - noted flag byte
  - optional amount only when stackable/noted
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L553)
- iOS inventory decoder reads id, then immediately attempts a 4-byte amount and ignores the explicit noted byte.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L528)

### Inbound: bank open packet shape is wrong

- Server sends bank open as `short storedSize`, `short maxBankSize`, then entries.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L620)
- iOS reads the item count as a single byte.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L560)

### Inbound: shop open packet shape is wrong

- Server sends:
  - itemCount byte
  - isGeneralStore byte
  - sellModifier byte
  - buyModifier byte
  - stockSensitivity byte
  - then `short itemId`, `short amount`, `short baseAmount`
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L669)
- iOS does not read `stockSensitivity`, and then expects a 4-byte price per item instead of a 2-byte base amount.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L592)

### Inbound: server message packet shape is wrong

- Server message opcode `131` includes icon sprite, message type, info flags, message text, and optional sender/color fields.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L726)
- iOS treats opcode `131` as a single plain string.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L641)

### Inbound: private message packet shape is wrong

- Server private message includes sender, former name, icon sprite, and encrypted RSC string.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L742)
- iOS expects two plain strings.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L666)

### Inbound: friend and ignore list packet shapes are wrong

- Server friend update includes current name, former name, online status, and optionally world name.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L523)
- iOS expects only `name + worldId`.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L688)

- Server ignore list includes repeated current/former name pairs.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L532)
- iOS expects a flat list of one string per ignore entry.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L695)

### Inbound: sleep screen and sound packet shapes are wrong

- Server sound packet writes a string sound name.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L366)
- iOS expects a 2-byte sound id.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L737)

- Server sleep screen writes raw image bytes with no leading short length.
- Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L518)
- iOS expects a leading short image length.
- Reference: [PacketHandler.swift](/Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC/OpenRSC/Sources/Network/PacketHandler.swift#L750)

## Important Nuance

The iOS client is not completely random or disconnected from the server protocol.

It appears to be a partial port that already knows:

- the custom bootstrap opcode
- the inauthentic login path
- the custom/203-era opcode numbers for many packets

But many payload readers and a few payload writers were simplified during the Android-to-iOS conversion and no longer match the Java server's actual packet bodies.

## Recommended Fix Order

1. Fix outbound packets that are definitely wrong:
   - walk opcode
   - logout opcode
   - chat encoding
2. Port bit-level decoding for player/npc coordinate updates.
3. Port appearance/update packet decoding from the shared Java client.
4. Fix inventory, bank, shop, chat, PM, friend, ignore, sleep, and sound payload readers.
5. Add packet parity tests using captured server payload fixtures for the iOS decoder.
