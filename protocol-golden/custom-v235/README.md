# custom-v235 protocol golden fixtures

These fixtures are payload-first JSON files shared by the Java and Rust parity
harnesses. Keep framing out of the fixture unless a test is specifically about
transport framing.

Required fields:

- `id`: stable test identifier.
- `protocol`: protocol family, usually `custom-v235`.
- `direction`: `client_to_server` or `server_to_client`.
- `opcode_enum`: Java/Rust semantic opcode name.
- `wire_opcode`: byte value on the wire.
- `payload_hex`: payload bytes only, lowercase hex.
- `fields`: decoded semantic fields used to generate the payload.
- `notes`: source or caveat.

## Entity update fixtures

All entity update fixtures are payload-only and intentionally omit transport
framing.

`out_update_players_chat_java_custom.json` documents the Java custom-client
type-1 public-chat layout from `PayloadCustomGenerator` and
`PacketBuilder.writeString`: both string fields are LF-terminated.
`out_update_players_chat.json` now uses the same LF-terminated payload through
the narrow Rust entity-chat writer in `game::state_updater`.

`out_update_players_appearance_java_custom.json` documents a Java custom-client
type-5 player appearance/identity entry from `GameStateUpdater`: LF-terminated
username/icon strings, custom short equipment ids, appearance color bytes,
combat/skull bytes, optional clan marker, visibility flags, and group id.

`out_update_players_damage_java_custom.json` documents a Java custom-client
type-2 player damage entry from `GameStateUpdater`: player index, damage taken,
current hits, and maximum hits.

`out_update_players_projectile_java_custom.json` documents a Java custom-client
type-3 player-to-NPC projectile entry from `GameStateUpdater`: caster player
index, projectile sprite/type, and victim NPC index.
`out_update_players_projectile_player_java_custom.json` covers the matching
type-4 player-to-player variant with the same field widths and a victim player
index.

`out_player_coords_known_move_remove_java_custom.json` documents a Java
custom-client `SEND_PLAYER_COORDS` known-player bitstream: viewer X/Y/sprite,
prior local-player count, one movement update using a 3-bit direction, one
removal update, then byte padding. These known updates are positional in the
viewer's local player cache and do not repeat player indices.

`out_update_npc_damage.json` is byte-oriented and matches the Java
`PayloadCustomGenerator` / `Payload235Generator` `AppearanceUpdateStruct`
ordering for type-2 NPC damage: count, NPC index, update type, damage, current
hits, maximum hits.
`out_update_npc_damage_java_custom.json` covers the same Java custom type-2
damage layout with multiple entries through the Rust state-updater fixture
writer.

`out_npc_coords_known_move_remove_java_custom.json` documents a Java
custom-client `SEND_NPC_COORDS` known-NPC bitstream: prior local-NPC count,
one movement update using a 3-bit direction, one removal update, then byte
padding. These known updates are positional in the viewer's local NPC cache
and do not repeat NPC indices.

## Social fixtures

`out_friend_update_online_java_custom.json` documents a Java custom-client
`SEND_FRIEND_UPDATE` payload: LF-terminated current name, LF-terminated former
name, one online-status byte, and an optional LF-terminated world name when
the Java struct's `worldName` field is non-empty.

`out_ignore_list_one_renamed_java_custom.json` documents a Java custom-client
`SEND_IGNORE_LIST` payload for one ignored player with a former name: one count
byte, LF-terminated current name twice, and LF-terminated former name twice.

`out_private_message_sent_java_custom.json` documents a Java custom-client
`SEND_PRIVATE_MESSAGE_SENT` payload: LF-terminated recipient name followed by
`PacketBuilder.writeRSCString` output for the sent message.

`out_private_message_received_java_custom.json` documents a Java custom-client
`SEND_PRIVATE_MESSAGE` payload: LF-terminated sender name, LF-terminated former
name, four-byte icon sprite, then `PacketBuilder.writeRSCString` output for the
received message.
