//! Protocol parity foothold for Java-vs-Rust golden tests.
//!
//! This module starts with static oracle checks that do not require spawning
//! the Java server. Fixture-backed byte comparisons should be added here as
//! each packet family is ported.

#[cfg(test)]
mod tests {
    use bytes::{Bytes, BytesMut};
    use tokio_util::codec::{Decoder, Encoder};

    use crate::game::state_updater;
    use crate::protocol::codec::RscCodec;
    use crate::protocol::legacy::{self, ProtocolVersion};
    use crate::protocol::opcodes::{OpcodeIn, OpcodeOut};
    use crate::protocol::{BitReader, Packet, PacketReader};

    fn load_fixture(source: &str) -> serde_json::Value {
        serde_json::from_str(source).unwrap()
    }

    fn fixture_packet(value: &serde_json::Value) -> Packet {
        let wire_opcode = value["wire_opcode"].as_u64().unwrap() as u8;
        let payload = hex::decode(value["payload_hex"].as_str().unwrap()).unwrap();
        Packet::new(wire_opcode, payload)
    }

    #[test]
    fn v177_selected_wire_opcodes_match_java_parser_table() {
        let cases = [
            (5, OpcodeIn::HEARTBEAT),
            (215, OpcodeIn::WALK_TO_ENTITY),
            (194, OpcodeIn::WALK_TO_POINT),
            (236, OpcodeIn::PLAYER_APPEARANCE_CHANGE),
            (3, OpcodeIn::CHAT_MESSAGE),
            (7, OpcodeIn::COMMAND),
            (205, OpcodeIn::BANK_DEPOSIT),
            (206, OpcodeIn::BANK_WITHDRAW),
            (207, OpcodeIn::BANK_CLOSE),
            (0, OpcodeIn::LOGIN),
            (254, OpcodeIn::KNOWN_PLAYERS),
        ];

        for (wire, expected) in cases {
            assert_eq!(
                legacy::decode_opcode(ProtocolVersion::V177, wire),
                Some(expected),
                "wire opcode {wire} should match Java Payload177Parser"
            );
        }
    }

    #[test]
    fn v235_custom_extension_opcodes_match_java_custom_parser() {
        let cases = [
            (194, OpcodeIn::SOCIAL_ADD_DELAYED_IGNORE),
            (203, OpcodeIn::NPC_COMMAND2),
            (168, OpcodeIn::ITEM_UNEQUIP_FROM_EQUIPMENT),
            (172, OpcodeIn::ITEM_EQUIP_FROM_BANK),
            (173, OpcodeIn::ITEM_REMOVE_TO_BANK),
            (24, OpcodeIn::BANK_DEPOSIT_ALL_FROM_INVENTORY),
            (26, OpcodeIn::BANK_DEPOSIT_ALL_FROM_EQUIPMENT),
            (27, OpcodeIn::BANK_SAVE_PRESET),
            (28, OpcodeIn::BANK_LOAD_PRESET),
        ];

        for (wire, expected) in cases {
            assert_eq!(
                legacy::decode_opcode(ProtocolVersion::V235, wire),
                Some(expected),
                "custom-v235 wire opcode {wire} should match Java PayloadCustomParser"
            );
        }
    }

    #[test]
    fn custom_outgoing_wire_values_match_java_payload_custom_generator() {
        let cases = [
            (OpcodeOut::SEND_WORLD_INFO, 25),
            (OpcodeOut::SEND_INVENTORY, 53),
            (OpcodeOut::SEND_BANK_OPEN, 42),
            (OpcodeOut::SEND_SHOP_OPEN, 101),
            (OpcodeOut::SEND_SERVER_MESSAGE, 131),
            (OpcodeOut::SEND_UPDATE_PLAYERS, 234),
            (OpcodeOut::SEND_PRIVACY_SETTINGS, 51),
            (OpcodeOut::SEND_GAME_SETTINGS, 240),
            (OpcodeOut::SEND_EQUIPMENT, 254),
            (OpcodeOut::SEND_EQUIPMENT_UPDATE, 255),
        ];

        for (opcode, expected_wire) in cases {
            assert_eq!(opcode.wire(), expected_wire);
        }
    }

    #[test]
    fn simplified_rust_frame_roundtrip_is_stable_for_fixture_harness() {
        let mut codec = RscCodec::new();
        let packet = Packet::new(OpcodeOut::SEND_SERVER_MESSAGE.wire(), b"hello\0".to_vec());
        let mut frame = BytesMut::new();

        codec.encode(packet.clone(), &mut frame).unwrap();
        assert_eq!(
            frame.as_ref(),
            &[131, 0, 6, b'h', b'e', b'l', b'l', b'o', 0]
        );

        let decoded = codec.decode(&mut frame).unwrap().unwrap();
        assert_eq!(decoded.opcode, packet.opcode);
        assert_eq!(decoded.payload, packet.payload);
    }

    #[test]
    fn shared_fixture_payload_hex_is_parseable() {
        let fixture =
            include_str!("../../../protocol-golden/custom-v235/out_server_message_plain.json");
        let value: serde_json::Value = serde_json::from_str(fixture).unwrap();
        assert_eq!(value["id"], "out_server_message_plain");
        assert_eq!(value["wire_opcode"], 131);

        let payload_hex = value["payload_hex"].as_str().unwrap();
        let payload = hex::decode(payload_hex).unwrap();
        assert_eq!(payload.last(), Some(&b'\n'));
    }

    #[test]
    fn bank_deposit_fixture_matches_java_parser_shape() {
        let fixture =
            include_str!("../../../protocol-golden/custom-v235/in_bank_deposit_fixed_width.json");
        let value = load_fixture(fixture);
        assert_eq!(value["opcode_enum"], "BANK_DEPOSIT");
        assert_eq!(value["wire_opcode"], 23);

        let packet = fixture_packet(&value);
        let mut reader = PacketReader::new(&packet);

        assert_eq!(reader.read_short().unwrap(), 10);
        assert_eq!(reader.read_int().unwrap(), 5);
        assert_eq!(reader.remaining(), 0);
    }

    #[test]
    fn bank_withdraw_fixture_matches_java_parser_shape() {
        let fixture =
            include_str!("../../../protocol-golden/custom-v235/in_bank_withdraw_fixed_width.json");
        let value = load_fixture(fixture);
        assert_eq!(value["opcode_enum"], "BANK_WITHDRAW");
        assert_eq!(value["wire_opcode"], 22);
        assert_eq!(
            legacy::decode_opcode(ProtocolVersion::V235, 22),
            Some(OpcodeIn::BANK_WITHDRAW)
        );

        let packet = fixture_packet(&value);
        let mut reader = PacketReader::new(&packet);

        assert_eq!(reader.read_short().unwrap(), 10);
        assert_eq!(reader.read_int().unwrap(), 5);
        assert_eq!(reader.remaining(), 0);
    }

    #[test]
    fn bank_close_fixture_matches_java_parser_shape() {
        let fixture = include_str!("../../../protocol-golden/custom-v235/in_bank_close.json");
        let value = load_fixture(fixture);
        assert_eq!(value["opcode_enum"], "BANK_CLOSE");
        assert_eq!(value["wire_opcode"], 212);
        assert_eq!(
            legacy::decode_opcode(ProtocolVersion::V235, 212),
            Some(OpcodeIn::BANK_CLOSE)
        );

        let packet = fixture_packet(&value);
        let reader = PacketReader::new(&packet);
        assert_eq!(reader.remaining(), 0);
    }

    #[test]
    fn prayer_toggle_fixtures_match_java_parser_shape() {
        let cases = [
            (
                include_str!("../../../protocol-golden/custom-v235/in_prayer_activated.json"),
                "PRAYER_ACTIVATED",
                60,
                OpcodeIn::PRAYER_ACTIVATED,
            ),
            (
                include_str!("../../../protocol-golden/custom-v235/in_prayer_deactivated.json"),
                "PRAYER_DEACTIVATED",
                254,
                OpcodeIn::PRAYER_DEACTIVATED,
            ),
        ];

        for (fixture, opcode_enum, wire_opcode, opcode) in cases {
            let value = load_fixture(fixture);
            assert_eq!(value["opcode_enum"], opcode_enum);
            assert_eq!(value["wire_opcode"], wire_opcode);
            assert_eq!(
                legacy::decode_opcode(ProtocolVersion::V235, wire_opcode as u8),
                Some(opcode)
            );

            let packet = fixture_packet(&value);
            let mut reader = PacketReader::new(&packet);
            assert_eq!(reader.read_byte().unwrap(), 4);
            assert_eq!(reader.remaining(), 0);
        }
    }

    #[test]
    fn privacy_settings_fixtures_match_custom_v235_payload_shape() {
        let incoming = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/in_privacy_settings_changed.json"
        ));
        assert_eq!(incoming["opcode_enum"], "PRIVACY_SETTINGS_CHANGED");
        assert_eq!(incoming["wire_opcode"], 64);
        assert_eq!(
            legacy::decode_opcode(ProtocolVersion::V235, 64),
            Some(OpcodeIn::PRIVACY_SETTINGS_CHANGED)
        );

        let packet = fixture_packet(&incoming);
        let mut reader = PacketReader::new(&packet);
        assert_eq!(reader.read_byte().unwrap(), 0);
        assert_eq!(reader.read_byte().unwrap(), 1);
        assert_eq!(reader.read_byte().unwrap(), 2);
        assert_eq!(reader.read_byte().unwrap(), 0);
        assert_eq!(reader.remaining(), 0);

        let outgoing = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_privacy_settings.json"
        ));
        assert_eq!(outgoing["opcode_enum"], "SEND_PRIVACY_SETTINGS");
        assert_eq!(outgoing["wire_opcode"], 51);
        assert_eq!(OpcodeOut::SEND_PRIVACY_SETTINGS.wire(), 51);

        let payload = hex::decode(outgoing["payload_hex"].as_str().unwrap()).unwrap();
        assert_eq!(payload, vec![0, 1, 2, 0]);
    }

    #[test]
    fn update_players_chat_fixture_matches_java_custom_entity_writer() {
        let fixture = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_update_players_chat.json"
        ));
        assert_eq!(fixture["opcode_enum"], "SEND_UPDATE_PLAYERS");
        assert_eq!(fixture["wire_opcode"], 234);
        assert_eq!(OpcodeOut::SEND_UPDATE_PLAYERS.wire(), 234);

        let expected_payload = hex::decode(fixture["payload_hex"].as_str().unwrap()).unwrap();
        let packet =
            state_updater::build_custom_v235_player_chat_update_packet(&[(42, "", "hello")]);

        assert_eq!(packet.payload.as_ref(), expected_payload.as_slice());

        assert_eq!(
            packet.payload.as_ref(),
            &[
                0x00, 0x01, // count
                0x00, 0x2a, // player index
                0x01, // update type: public chat
                0x0a, // empty icon string, Java PacketBuilder.writeString
                b'h', b'e', b'l', b'l', b'o', 0x0a,
            ]
        );
    }

    #[test]
    fn update_players_chat_java_custom_fixture_matches_entity_writer() {
        let fixture = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_update_players_chat_java_custom.json"
        ));
        assert_eq!(fixture["opcode_enum"], "SEND_UPDATE_PLAYERS");
        assert_eq!(fixture["wire_opcode"], 234);
        assert_eq!(OpcodeOut::SEND_UPDATE_PLAYERS.wire(), 234);

        let java_payload = hex::decode(fixture["payload_hex"].as_str().unwrap()).unwrap();
        assert_eq!(
            java_payload.as_slice(),
            &[
                0x00, 0x01, // count
                0x00, 0x2a, // player index
                0x01, // update type: public chat
                0x0a, // empty icon string, Java PacketBuilder.writeString
                b'h', b'e', b'l', b'l', b'o', 0x0a,
            ]
        );

        let rust_packet =
            state_updater::build_custom_v235_player_chat_update_packet(&[(42, "", "hello")]);

        assert_eq!(rust_packet.payload.as_ref(), java_payload.as_slice());
    }

    #[test]
    fn update_npc_damage_fixture_matches_entity_writer() {
        let fixture = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_update_npc_damage.json"
        ));
        assert_eq!(fixture["opcode_enum"], "SEND_UPDATE_NPC");
        assert_eq!(fixture["wire_opcode"], 104);
        assert_eq!(OpcodeOut::SEND_UPDATE_NPC.wire(), 104);

        let expected_payload = hex::decode(fixture["payload_hex"].as_str().unwrap()).unwrap();
        let packet = state_updater::build_custom_v235_npc_damage_update_packet(&[(37, 3, 7, 10)]);

        assert_eq!(packet.payload.as_ref(), expected_payload.as_slice());

        let mut reader = PacketReader::new(&packet);
        assert_eq!(reader.read_short().unwrap(), 1);
        assert_eq!(reader.read_short().unwrap(), 37);
        assert_eq!(reader.read_byte().unwrap(), 2);
        assert_eq!(reader.read_byte().unwrap(), 3);
        assert_eq!(reader.read_byte().unwrap(), 7);
        assert_eq!(reader.read_byte().unwrap(), 10);
        assert_eq!(reader.remaining(), 0);
    }

    #[test]
    fn update_npc_damage_java_custom_fixture_matches_entity_writer() {
        let fixture = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_update_npc_damage_java_custom.json"
        ));
        assert_eq!(fixture["opcode_enum"], "SEND_UPDATE_NPC");
        assert_eq!(fixture["wire_opcode"], 104);
        assert_eq!(OpcodeOut::SEND_UPDATE_NPC.wire(), 104);

        let expected_payload = hex::decode(fixture["payload_hex"].as_str().unwrap()).unwrap();
        let packet = state_updater::build_custom_v235_npc_damage_update_packet(&[
            (37, 3, 7, 10),
            (4095, 0, 1, 12),
        ]);

        assert_eq!(packet.payload.as_ref(), expected_payload.as_slice());

        let mut reader = PacketReader::new(&packet);
        assert_eq!(reader.read_short().unwrap(), 2);
        assert_eq!(reader.read_short().unwrap(), 37);
        assert_eq!(reader.read_byte().unwrap(), 2);
        assert_eq!(reader.read_byte().unwrap(), 3);
        assert_eq!(reader.read_byte().unwrap(), 7);
        assert_eq!(reader.read_byte().unwrap(), 10);
        assert_eq!(reader.read_short().unwrap(), 4095);
        assert_eq!(reader.read_byte().unwrap(), 2);
        assert_eq!(reader.read_byte().unwrap(), 0);
        assert_eq!(reader.read_byte().unwrap(), 1);
        assert_eq!(reader.read_byte().unwrap(), 12);
        assert_eq!(reader.remaining(), 0);
    }

    #[test]
    fn update_players_projectile_java_custom_fixture_matches_entity_writer() {
        let fixture = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_update_players_projectile_java_custom.json"
        ));
        assert_eq!(fixture["opcode_enum"], "SEND_UPDATE_PLAYERS");
        assert_eq!(fixture["wire_opcode"], 234);
        assert_eq!(OpcodeOut::SEND_UPDATE_PLAYERS.wire(), 234);

        let expected_payload = hex::decode(fixture["payload_hex"].as_str().unwrap()).unwrap();
        let entry = state_updater::CustomV235ProjectileUpdate {
            caster_index: 42,
            projectile_type: 2,
            target: state_updater::CustomV235ProjectileTarget::Npc(37),
        };
        let packet = state_updater::build_custom_v235_player_projectile_update_packet(&[entry]);

        assert_eq!(packet.payload.as_ref(), expected_payload.as_slice());

        let mut reader = PacketReader::new(&packet);
        assert_eq!(reader.read_short().unwrap(), 1);
        assert_eq!(reader.read_short().unwrap(), 42);
        assert_eq!(reader.read_byte().unwrap(), 3);
        assert_eq!(reader.read_short().unwrap(), 2);
        assert_eq!(reader.read_short().unwrap(), 37);
        assert_eq!(reader.remaining(), 0);
    }

    #[test]
    fn npc_coords_known_move_remove_java_custom_fixture_matches_bit_writer() {
        let fixture = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_npc_coords_known_move_remove_java_custom.json"
        ));
        assert_eq!(fixture["opcode_enum"], "SEND_NPC_COORDS");
        assert_eq!(fixture["wire_opcode"], 79);
        assert_eq!(OpcodeOut::SEND_NPC_COORDS.wire(), 79);

        let expected_payload = hex::decode(fixture["payload_hex"].as_str().unwrap()).unwrap();
        let packet = state_updater::build_custom_v235_npc_coords_known_update_packet(&[
            state_updater::CustomV235KnownNpcCoordUpdate::Moved(
                crate::game::entity::Direction::East,
            ),
            state_updater::CustomV235KnownNpcCoordUpdate::Removed,
        ]);

        assert_eq!(packet.payload.as_ref(), expected_payload.as_slice());

        let mut reader = BitReader::new(Bytes::copy_from_slice(packet.payload.as_ref()));
        assert_eq!(reader.read_bits(8).unwrap(), 2);
        assert_eq!(reader.read_bits(1).unwrap(), 1);
        assert_eq!(reader.read_bits(1).unwrap(), 0);
        assert_eq!(reader.read_bits(3).unwrap(), 6);
        assert_eq!(reader.read_bits(1).unwrap(), 1);
        assert_eq!(reader.read_bits(1).unwrap(), 1);
        assert_eq!(reader.read_bits(2).unwrap(), 3);
        assert_eq!(reader.read_bits(7).unwrap(), 0);
    }

    #[test]
    fn player_coords_known_move_remove_java_custom_fixture_matches_bit_writer() {
        let fixture = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_player_coords_known_move_remove_java_custom.json"
        ));
        assert_eq!(fixture["opcode_enum"], "SEND_PLAYER_COORDS");
        assert_eq!(fixture["wire_opcode"], 191);
        assert_eq!(OpcodeOut::SEND_PLAYER_COORDS.wire(), 191);

        let expected_payload = hex::decode(fixture["payload_hex"].as_str().unwrap()).unwrap();
        let packet = state_updater::build_custom_v235_player_coords_known_update_packet(
            122,
            647,
            crate::game::entity::Direction::South,
            &[
                state_updater::CustomV235KnownPlayerCoordUpdate::Moved(
                    crate::game::entity::Direction::East,
                ),
                state_updater::CustomV235KnownPlayerCoordUpdate::Removed,
            ],
        );

        assert_eq!(packet.payload.as_ref(), expected_payload.as_slice());

        let mut reader = BitReader::new(Bytes::copy_from_slice(packet.payload.as_ref()));
        assert_eq!(reader.read_bits(11).unwrap(), 122);
        assert_eq!(reader.read_bits(13).unwrap(), 647);
        assert_eq!(reader.read_bits(4).unwrap(), 4);
        assert_eq!(reader.read_bits(8).unwrap(), 2);
        assert_eq!(reader.read_bits(1).unwrap(), 1);
        assert_eq!(reader.read_bits(1).unwrap(), 0);
        assert_eq!(reader.read_bits(3).unwrap(), 6);
        assert_eq!(reader.read_bits(1).unwrap(), 1);
        assert_eq!(reader.read_bits(1).unwrap(), 1);
        assert_eq!(reader.read_bits(2).unwrap(), 3);
        assert_eq!(reader.read_bits(3).unwrap(), 0);
    }

    #[test]
    fn update_players_appearance_java_custom_fixture_matches_entity_writer() {
        let fixture = load_fixture(include_str!(
            "../../../protocol-golden/custom-v235/out_update_players_appearance_java_custom.json"
        ));
        assert_eq!(fixture["opcode_enum"], "SEND_UPDATE_PLAYERS");
        assert_eq!(fixture["wire_opcode"], 234);
        assert_eq!(OpcodeOut::SEND_UPDATE_PLAYERS.wire(), 234);

        let expected_payload = hex::decode(fixture["payload_hex"].as_str().unwrap()).unwrap();
        let entry = state_updater::CustomV235PlayerAppearanceUpdate {
            player_index: 42,
            username: "alice",
            equipment: &[],
            hair_colour: 2,
            top_colour: 8,
            trouser_colour: 14,
            skin_colour: 3,
            combat_level: 12,
            skull_type: 0,
            clan_tag: None,
            invisible: false,
            invulnerable: false,
            group_id: 10,
            icon: "",
        };
        let packet = state_updater::build_custom_v235_player_appearance_update_packet(&[entry]);

        assert_eq!(packet.payload.as_ref(), expected_payload.as_slice());

        let mut reader = PacketReader::new(&packet);
        assert_eq!(reader.read_short().unwrap(), 1);
        assert_eq!(reader.read_short().unwrap(), 42);
        assert_eq!(reader.read_byte().unwrap(), 5);
        assert_eq!(&packet.payload.as_ref()[5..11], b"alice\n");
        assert_eq!(reader.read_byte().unwrap(), b'a');
        assert_eq!(reader.read_byte().unwrap(), b'l');
        assert_eq!(reader.read_byte().unwrap(), b'i');
        assert_eq!(reader.read_byte().unwrap(), b'c');
        assert_eq!(reader.read_byte().unwrap(), b'e');
        assert_eq!(reader.read_byte().unwrap(), b'\n');
        assert_eq!(reader.read_byte().unwrap(), 0);
        assert_eq!(reader.read_byte().unwrap(), 2);
        assert_eq!(reader.read_byte().unwrap(), 8);
        assert_eq!(reader.read_byte().unwrap(), 14);
        assert_eq!(reader.read_byte().unwrap(), 3);
        assert_eq!(reader.read_byte().unwrap(), 12);
        assert_eq!(reader.read_byte().unwrap(), 0);
        assert_eq!(reader.read_byte().unwrap(), 0);
        assert_eq!(reader.read_byte().unwrap(), 0);
        assert_eq!(reader.read_byte().unwrap(), 0);
        assert_eq!(reader.read_byte().unwrap(), 10);
        assert_eq!(reader.read_byte().unwrap(), b'\n');
        assert_eq!(reader.remaining(), 0);
    }
}
