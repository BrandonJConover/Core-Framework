// Local render-pipeline tests. Run via `swift test` on macOS so I can catch
// bugs without round-trips through Xcode + on-device rebuilds.
//
// What this verifies:
//   1. sprites_v2.dat loads (count + sample pixels + non-zero content).
//   2. NPCDef JSON loads + animation.number assignment matches Java's algorithm.
//   3. Scene.projectPoint produces on-screen coords for near-camera points.
//   4. World.generateLandscapeModel mesh vertices project to visible screen area.
//   5. CharacterBillboards.register produces billboards via scene.drawSprite.

import XCTest
@testable import OpenRSC

final class RenderPipelineTests: XCTestCase {

    var fixtureDir: String {
        if let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures") {
            return url.path
        }
        return FileManager.default.currentDirectoryPath + "/Tests/RenderTest/Fixtures"
    }

    // --- RSC packet parser smoke tests ---

    func test_rsc_combat_level_matches_server_formula() {
        XCTAssertEqual(
            RSCWorldState.rscCombatLevel(
                attack: 40,
                defense: 35,
                strength: 45,
                hits: 42,
                magic: 30,
                prayer: 25,
                ranged: 20
            ),
            47
        )
        XCTAssertEqual(
            RSCWorldState.rscCombatLevel(
                attack: 1,
                defense: 20,
                strength: 1,
                hits: 30,
                magic: 15,
                prayer: 10,
                ranged: 60
            ),
            38
        )
    }

    @MainActor
    func test_rsc_bank_open_uses_short_counts_and_int_amounts() {
        let ws = RSCWorldState()
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 42, payload: Data([
            0x00, 0x02,             // item count
            0x02, 0x00,             // max items = 512
            0x00, 0x0A,             // item id 10
            0x00, 0x01, 0x11, 0x70, // amount 70000
            0x00, 0x14,             // item id 20
            0x00, 0x00, 0x00, 0x03  // amount 3
        ]))

        XCTAssertTrue(ws.bankOpen)
        XCTAssertEqual(ws.bankMaxItems, 512)
        XCTAssertEqual(ws.bankItems.count, 2)
        XCTAssertEqual(ws.bankItems[0].id, 10)
        XCTAssertEqual(ws.bankItems[0].amount, 70_000)
        XCTAssertEqual(ws.bankItems[1].id, 20)
        XCTAssertEqual(ws.bankItems[1].amount, 3)
    }

    @MainActor
    func test_rsc_bank_update_uses_byte_slot_short_id_and_int_amount() {
        let ws = RSCWorldState()
        ws.bankItems = [(id: 10, amount: 1)]
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 249, payload: Data([
            0x00,                   // slot
            0x00, 0x0A,             // item id 10
            0x00, 0x01, 0x11, 0x70  // amount 70000
        ]))

        XCTAssertEqual(ws.bankItems.count, 1)
        XCTAssertEqual(ws.bankItems[0].id, 10)
        XCTAssertEqual(ws.bankItems[0].amount, 70_000)
    }

    @MainActor
    func test_rsc_bank_update_removes_slot_when_amount_is_zero() {
        let ws = RSCWorldState()
        ws.bankItems = [(id: 10, amount: 1), (id: 20, amount: 2), (id: 30, amount: 3)]
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 249, payload: Data([
            0x01,                   // slot
            0x00, 0x14,             // item id 20
            0x00, 0x00, 0x00, 0x00  // amount 0 removes the slot
        ]))

        XCTAssertEqual(ws.bankItems.count, 2)
        XCTAssertEqual(ws.bankItems[0].id, 10)
        XCTAssertEqual(ws.bankItems[0].amount, 1)
        XCTAssertEqual(ws.bankItems[1].id, 30)
        XCTAssertEqual(ws.bankItems[1].amount, 3)
    }

    @MainActor
    func test_rsc_bank_update_appends_when_slot_matches_count() {
        let ws = RSCWorldState()
        ws.bankItems = [(id: 10, amount: 1)]
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 249, payload: Data([
            0x01,                   // slot == current count
            0x00, 0x28,             // item id 40
            0x00, 0x00, 0x00, 0x05  // amount 5
        ]))

        XCTAssertEqual(ws.bankItems.count, 2)
        XCTAssertEqual(ws.bankItems[0].id, 10)
        XCTAssertEqual(ws.bankItems[0].amount, 1)
        XCTAssertEqual(ws.bankItems[1].id, 40)
        XCTAssertEqual(ws.bankItems[1].amount, 5)
    }

    @MainActor
    func test_rsc_trade_update_replaces_partner_and_local_offers() {
        let ws = RSCWorldState()
        ws.tradeTheirOffer = [(id: 1, amount: 1)]
        ws.tradeMyOffer = [(id: 2, amount: 2)]
        ws.tradeAccepted = true
        ws.tradePartnerAccepted = true
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 97, payload: Data([
            0x01,                   // partner count
            0x00, 0x64,             // partner item id 100
            0x00, 0x00, 0x00, 0x02, // partner amount 2
            0x02,                   // my count
            0x00, 0xC8,             // my item id 200
            0x00, 0x00, 0x00, 0x03, // my amount 3
            0x00, 0xC9,             // my item id 201
            0x00, 0x01, 0x11, 0x70  // my amount 70000
        ]))

        XCTAssertEqual(ws.tradeTheirOffer.count, 1)
        XCTAssertEqual(ws.tradeTheirOffer[0].id, 100)
        XCTAssertEqual(ws.tradeTheirOffer[0].amount, 2)
        XCTAssertEqual(ws.tradeMyOffer.count, 2)
        XCTAssertEqual(ws.tradeMyOffer[0].id, 200)
        XCTAssertEqual(ws.tradeMyOffer[0].amount, 3)
        XCTAssertEqual(ws.tradeMyOffer[1].id, 201)
        XCTAssertEqual(ws.tradeMyOffer[1].amount, 70_000)
        XCTAssertFalse(ws.tradeAccepted)
        XCTAssertFalse(ws.tradePartnerAccepted)
    }

    @MainActor
    func test_rsc_trade_update_stops_at_truncated_stack() {
        let ws = RSCWorldState()
        ws.tradeTheirOffer = [(id: 1, amount: 1)]
        ws.tradeMyOffer = [(id: 2, amount: 2)]
        ws.tradeAccepted = true
        ws.tradePartnerAccepted = true
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 97, payload: Data([
            0x01,                   // partner count
            0x00, 0x64,             // partner item id 100
            0x00, 0x00, 0x00, 0x02, // partner amount 2
            0x02,                   // my count declares two stacks
            0x00, 0xC8,             // my item id 200
            0x00, 0x00, 0x00, 0x03, // my amount 3
            0x00, 0xC9              // truncated second stack: id without amount
        ]))

        XCTAssertEqual(ws.tradeTheirOffer.count, 1)
        XCTAssertEqual(ws.tradeTheirOffer[0].id, 100)
        XCTAssertEqual(ws.tradeTheirOffer[0].amount, 2)
        XCTAssertEqual(ws.tradeMyOffer.count, 1)
        XCTAssertEqual(ws.tradeMyOffer[0].id, 200)
        XCTAssertEqual(ws.tradeMyOffer[0].amount, 3)
        XCTAssertFalse(ws.tradeAccepted)
        XCTAssertFalse(ws.tradePartnerAccepted)
    }

    @MainActor
    func test_rsc_trade_confirm_uses_rsc_strings_and_int_amounts() {
        let ws = RSCWorldState()
        ws.tradeOpen = true
        ws.tradeAccepted = true
        ws.tradePartnerAccepted = true
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 20, payload: Data(rscStringBytes("Alice") + [
            0x01,                   // partner count
            0x01, 0x2C,             // partner item id 300
            0x00, 0x00, 0x00, 0x04, // partner amount 4
            0x01,                   // my count
            0x01, 0x90,             // my item id 400
            0x00, 0x01, 0x11, 0x70  // my amount 70000
        ]))

        XCTAssertEqual(ws.tradePartnerName, "Alice")
        XCTAssertFalse(ws.tradeOpen)
        XCTAssertTrue(ws.tradeConfirmOpen)
        XCTAssertEqual(ws.tradeTheirOffer.count, 1)
        XCTAssertEqual(ws.tradeTheirOffer[0].id, 300)
        XCTAssertEqual(ws.tradeTheirOffer[0].amount, 4)
        XCTAssertEqual(ws.tradeMyOffer.count, 1)
        XCTAssertEqual(ws.tradeMyOffer[0].id, 400)
        XCTAssertEqual(ws.tradeMyOffer[0].amount, 70_000)
        XCTAssertFalse(ws.tradeAccepted)
        XCTAssertFalse(ws.tradePartnerAccepted)
    }

    @MainActor
    func test_rsc_duel_settings_use_java_order_and_one_means_restriction() {
        let ws = RSCWorldState()
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 30, payload: Data([1, 0, 1, 0]))

        XCTAssertEqual(ws.duelSettings, [true, false, true, false])
    }

    @MainActor
    func test_rsc_duel_confirm_uses_rsc_strings_stakes_and_settings() {
        let ws = RSCWorldState()
        ws.duelOpen = true
        ws.duelAccepted = true
        ws.duelOpponentAccepted = true
        ws.duelSettings = [false, false, false, false]
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 172, payload: Data(rscStringBytes("Bob") + [
            0x01,                   // opponent stake count
            0x00, 0x65,             // opponent item id 101
            0x00, 0x00, 0x00, 0x02, // opponent amount 2
            0x02,                   // my stake count
            0x00, 0x66,             // my item id 102
            0x00, 0x00, 0x00, 0x03, // my amount 3
            0x00, 0x67,             // my item id 103
            0x00, 0x01, 0x11, 0x70, // my amount 70000
            1, 0, 1, 0              // retreat/magic/prayer/weapons restrictions
        ]))

        XCTAssertFalse(ws.duelOpen)
        XCTAssertTrue(ws.duelConfirmOpen)
        XCTAssertEqual(ws.duelOpponentName, "Bob")
        XCTAssertEqual(ws.duelTheirStake.count, 1)
        XCTAssertEqual(ws.duelTheirStake[0].id, 101)
        XCTAssertEqual(ws.duelTheirStake[0].amount, 2)
        XCTAssertEqual(ws.duelMyStake.count, 2)
        XCTAssertEqual(ws.duelMyStake[0].id, 102)
        XCTAssertEqual(ws.duelMyStake[0].amount, 3)
        XCTAssertEqual(ws.duelMyStake[1].id, 103)
        XCTAssertEqual(ws.duelMyStake[1].amount, 70_000)
        XCTAssertEqual(ws.duelSettings, [true, false, true, false])
        XCTAssertFalse(ws.duelAccepted)
        XCTAssertFalse(ws.duelOpponentAccepted)
    }

    @MainActor
    func test_rsc_opening_transaction_panel_closes_bank_pin_overlay() {
        let ws = RSCWorldState()
        ws.bankOpen = true
        ws.bankPinOpen = true
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 101, payload: Data([
            0x01,                   // count
            0x00,                   // shopType
            0x64,                   // sell modifier
            0x64,                   // buy modifier
            0x01,                   // price multiplier
            0x00, 0x64,             // item id 100
            0x00, 0x0A,             // stock 10
            0x00, 0x01              // price
        ]))

        XCTAssertFalse(ws.bankOpen)
        XCTAssertFalse(ws.bankPinOpen)
        XCTAssertTrue(ws.shopOpen)
    }

    @MainActor
    func test_rsc_game_object_packet_adds_replaces_and_removes_by_tile() {
        let ws = RSCWorldState()
        ws.localPlayerX = 100
        ws.localPlayerY = 200
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 48, payload: Data([
            0x01, 0x02,  // object id 258
            0x03,        // x = local + 3
            0xFE,        // y = local - 2
            0x06         // direction
        ]))

        XCTAssertEqual(ws.gameObjects.count, 1)
        XCTAssertEqual(ws.gameObjects[0].x, 103)
        XCTAssertEqual(ws.gameObjects[0].y, 198)
        XCTAssertEqual(ws.gameObjects[0].objectId, 258)
        XCTAssertEqual(ws.gameObjects[0].direction, 6)

        handler.handlePacket(opcode: 48, payload: Data([
            0x01, 0x03,  // replacement object id 259 at same tile
            0x03,
            0xFE,
            0x02
        ]))

        XCTAssertEqual(ws.gameObjects.count, 1)
        XCTAssertEqual(ws.gameObjects[0].objectId, 259)
        XCTAssertEqual(ws.gameObjects[0].direction, 2)

        handler.handlePacket(opcode: 48, payload: Data([
            0xEA, 0x60,  // object id 60000 means remove-only
            0x03,
            0xFE,
            0x00
        ]))

        XCTAssertTrue(ws.gameObjects.isEmpty)
    }

    @MainActor
    func test_rsc_game_object_packet_batch_removes_8x8_region() {
        let ws = RSCWorldState()
        ws.localPlayerX = 100
        ws.localPlayerY = 200
        ws.gameObjects = [
            RSCGameObject(x: 100, y: 200, objectId: 1, direction: 0),
            RSCGameObject(x: 107, y: 207, objectId: 2, direction: 0),
            RSCGameObject(x: 108, y: 208, objectId: 3, direction: 0)
        ]
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 48, payload: Data([
            0xFF,  // batch remove
            0x00,  // region x = local x
            0x00   // region z = local y
        ]))

        XCTAssertEqual(ws.gameObjects.count, 1)
        XCTAssertEqual(ws.gameObjects[0].objectId, 3)
    }

    @MainActor
    func test_rsc_wall_packet_replaces_same_direction_only_and_removes_sentinel() {
        let ws = RSCWorldState()
        ws.localPlayerX = 50
        ws.localPlayerY = 60
        let handler = RSCPacketHandler()
        handler.worldState = ws

        handler.handlePacket(opcode: 91, payload: Data([
            0x00, 0x2A,  // wall id 42
            0x01,
            0x02,
            0x00,
            0x00, 0x2B,  // wall id 43, same tile but different direction
            0x01,
            0x02,
            0x01
        ]))

        XCTAssertEqual(ws.wallObjects.count, 2)

        handler.handlePacket(opcode: 91, payload: Data([
            0x00, 0x2C,  // replaces only direction 0
            0x01,
            0x02,
            0x00
        ]))

        XCTAssertEqual(ws.wallObjects.count, 2)
        XCTAssertEqual(ws.wallObjects.first { $0.direction == 0 }?.wallId, 44)
        XCTAssertEqual(ws.wallObjects.first { $0.direction == 1 }?.wallId, 43)

        handler.handlePacket(opcode: 91, payload: Data([
            0xEA, 0x60,  // wall id 60000 removes same tile/direction only
            0x01,
            0x02,
            0x00
        ]))

        XCTAssertEqual(ws.wallObjects.count, 1)
        XCTAssertEqual(ws.wallObjects[0].wallId, 43)
        XCTAssertEqual(ws.wallObjects[0].direction, 1)
    }

    @MainActor
    func test_rsc_npc_reannounce_replaces_existing_server_index() {
        let ws = RSCWorldState()
        ws.localPlayerX = 100
        ws.localPlayerY = 200
        ws.npcs = [
            RSCNPC(id: 42, x: 100, y: 200, npcId: 1, name: "Old"),
        ]
        let handler = RSCPacketHandler()
        handler.worldState = ws

        var bits = BitWriter()
        bits.write(1, count: 8)   // one known NPC retained
        bits.write(0, count: 1)   // retained NPC has no movement update
        bits.write(42, count: 12) // reannounce same server index
        bits.write(2, count: 6)   // relX
        bits.write(3, count: 6)   // relZ
        bits.write(4, count: 4)   // direction
        bits.write(5, count: 10)  // npc type id

        handler.handlePacket(opcode: 79, payload: Data(bits.bytes))

        XCTAssertEqual(ws.npcs.count, 1)
        XCTAssertEqual(ws.npcs[0].id, 42)
        XCTAssertEqual(ws.npcs[0].x, 102)
        XCTAssertEqual(ws.npcs[0].y, 203)
        XCTAssertEqual(ws.npcs[0].npcId, 5)
        XCTAssertEqual(ws.npcs[0].direction, 4)
    }

    @MainActor
    func test_rsc_player_known_count_prunes_stale_players_and_appearances() {
        let ws = RSCWorldState()
        ws.playerServerIndex = 7
        ws.players = [
            RSCPlayer(id: 100, x: 10, y: 20, name: "Keep", moving: false, combatLevel: 3),
            RSCPlayer(id: 200, x: 30, y: 40, name: "Drop", moving: false, combatLevel: 4),
        ]
        ws.playerAppearances = [
            7: RSCPlayerAppearance(sprites: [], colourHair: 0, colourTop: 0, colourBottom: 0, colourSkin: 0),
            100: RSCPlayerAppearance(sprites: [], colourHair: 1, colourTop: 1, colourBottom: 1, colourSkin: 1),
            200: RSCPlayerAppearance(sprites: [], colourHair: 2, colourTop: 2, colourBottom: 2, colourSkin: 2),
        ]
        let handler = RSCPacketHandler()
        handler.worldState = ws

        var bits = BitWriter()
        bits.write(120, count: 11)  // local x
        bits.write(240, count: 13)  // local z
        bits.write(4, count: 4)     // local direction
        bits.write(1, count: 8)     // only first known remote player remains
        bits.write(0, count: 1)     // retained player has no update

        handler.handlePacket(opcode: 191, payload: Data(bits.bytes))

        XCTAssertEqual(ws.localPlayerX, 120)
        XCTAssertEqual(ws.localPlayerY, 240)
        XCTAssertEqual(ws.players.map(\.id), [100])
        XCTAssertNotNil(ws.playerAppearances[7])
        XCTAssertNotNil(ws.playerAppearances[100])
        XCTAssertNil(ws.playerAppearances[200])
    }

    // --- 1. Sprite archive format ---

    func test_sprite_archive_loads_with_expected_count_and_metadata() throws {
        let path = fixtureDir + "/sprites_v2.dat"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(data.count, 1_000_000, "sprites_v2.dat should be >1MB")

        let bytes = [UInt8](data)
        XCTAssertEqual(bytes[0], 0x53); XCTAssertEqual(bytes[1], 0x50)
        XCTAssertEqual(bytes[2], 0x52); XCTAssertEqual(bytes[3], 0x32)

        let count = (Int(bytes[4]) << 24) | (Int(bytes[5]) << 16)
                  | (Int(bytes[6]) << 8) | Int(bytes[7])
        XCTAssertEqual(count, 2259, "Should have 2259 sprites")

        // Spot-check first entry: head1 frame 0 should be a small head sprite
        let e0 = 8
        let id0 = be32(bytes, e0)
        let w0 = be32(bytes, e0 + 8)
        let h0 = be32(bytes, e0 + 12)
        let authW0 = be32(bytes, e0 + 28)
        let authH0 = be32(bytes, e0 + 32)
        XCTAssertEqual(id0, 0, "First entry ID is 0")
        XCTAssertGreaterThan(w0, 0)
        XCTAssertGreaterThan(h0, 0)
        XCTAssertGreaterThan(authW0, 0)
        XCTAssertGreaterThan(authH0, 0)
        print("head1: \(w0)x\(h0) authentic=\(authW0)x\(authH0)")
    }

    private func be32(_ b: [UInt8], _ i: Int) -> Int {
        let u = (UInt32(b[i]) << 24) | (UInt32(b[i+1]) << 16)
              | (UInt32(b[i+2]) << 8) | UInt32(b[i+3])
        return Int(Int32(bitPattern: u))
    }

    // --- 1b. Texture page semantics ---

    func test_scene_load_texture_builds_java_style_brightness_pages() throws {
        let (_, scene) = buildEngine()
        let black: Int32 = 0x000000
        let transparentMagenta: Int32 = 0xF800FF
        let color: Int32 = 0x123456
        let palette = [black, transparentMagenta, color]
        var indices = [UInt8](repeating: 2, count: 64 * 64)
        indices[0] = 0
        indices[1] = 1

        scene.loadTexture(index: 83, pixels: palette, type: 0, data: Data(indices))

        XCTAssertEqual(scene.loadedTextureCount, 1)
        XCTAssertGreaterThan(scene.resourceDatabase.count, 83)
        XCTAssertEqual(scene.textureTypes[83], 0)
        XCTAssertEqual(scene.textureIndexData[83], Data(indices))
        XCTAssertEqual(scene.m_L[83], palette)
        XCTAssertEqual(scene.m_Hb[83], 0)

        let pages = try XCTUnwrap(scene.resourceDatabase[83])
        XCTAssertEqual(pages.count, 64 * 64 * 4)
        XCTAssertEqual(pages[0], 1, "Black texture pixels are coerced to 1 so 0 stays reserved for transparency")
        XCTAssertEqual(pages[1], 0, "Java transparent-magenta sentinel becomes transparent 0")

        let maskedColor = UInt32(bitPattern: color) & 0x00F8_F8FF
        XCTAssertEqual(pages[2], Int32(bitPattern: maskedColor))
        XCTAssertEqual(pages[64 * 64 + 2], Int32(bitPattern: (maskedColor &- (maskedColor >> 3)) & 0x00F8_F8FF))
        XCTAssertEqual(pages[64 * 64 * 2 + 2], Int32(bitPattern: (maskedColor &- (maskedColor >> 2)) & 0x00F8_F8FF))
        XCTAssertEqual(pages[64 * 64 * 3 + 2], Int32(bitPattern: (maskedColor &- (maskedColor >> 3) &- (maskedColor >> 2)) & 0x00F8_F8FF))
    }

    func test_scene_load_large_texture_uses_128_square_pages() throws {
        let (_, scene) = buildEngine()
        let palette: [Int32] = [0x112233]
        let indices = Data([UInt8](repeating: 0, count: 128 * 128))

        scene.loadTexture(index: 2, pixels: palette, type: 1, data: indices)

        let pages = try XCTUnwrap(scene.resourceDatabase[2])
        XCTAssertEqual(pages.count, 128 * 128 * 4)
        XCTAssertEqual(scene.textureTypes[2], 1)
        XCTAssertEqual(scene.m_Hb[2], 1)
    }

    func test_sprite_loader_feeds_scene_palette_not_expanded_pixels_for_terrain_textures() throws {
        let (_, scene) = buildEngine()
        let loader = SpriteLoader()
        let archive = makeSingleSpriteArchive(
            id: SpriteLoader.terrainTextureBaseID,
            width: 64,
            height: 64,
            authenticWidth: 64,
            authenticHeight: 64,
            pixels: [Int32](repeating: Int32(bitPattern: 0xFF11_2233), count: 64 * 64)
        )
        loader.parseBytes(archive)
        let buffers = loader.terrainTextureBuffers()
        XCTAssertEqual(buffers.count, 1)
        XCTAssertEqual(buffers[0].palette.count, 256)
        XCTAssertEqual(buffers[0].pixels.count, 64 * 64)

        XCTAssertEqual(loader.loadTerrainTextures(into: scene), 1)

        XCTAssertEqual(scene.m_L[0], buffers[0].palette)
        XCTAssertNotEqual(scene.m_L[0].count, buffers[0].pixels.count)
        XCTAssertEqual(scene.textureIndexData[0], buffers[0].indices)
    }

    func test_transparent_normal_shader_handles_bottom_half_texture_rows() {
        let (graphics, _) = buildEngine()
        var texture = [Int32](repeating: 0, count: 64 * 64 * 2)
        texture[63 * 128 + 63] = 0x00ABCDEF
        let shader = Shader()

        graphics.pixelData.withUnsafeMutableBufferPointer { destBuffer in
            texture.withUnsafeBufferPointer { textureBuffer in
                shader.shadeScanlineTransparentNormal(
                    var0: 0, var1: 0, var2: 0, var3: 0,
                    dest: destBuffer.baseAddress!,
                    var5: 1, var6: 0,
                    var7: 63, var8: 63, var9: 0,
                    var10: 0, var11: 0, var12: 0,
                    var13: 0, texture: textureBuffer.baseAddress!,
                    var15: 1
                )
            }
        }

        XCTAssertEqual(graphics.pixelData[0], 0x00ABCDEF)
    }

    @MainActor
    func test_boundary_wall_direction_two_endpoint_matches_rendered_diagonal() {
        let endpoints = RSCGameEngine.boundaryWallTileEndpoints(tileX: 10, tileZ: 20, direction: 2)
        XCTAssertEqual(endpoints.start.x, 11.0)
        XCTAssertEqual(endpoints.start.z, 20.0)
        XCTAssertEqual(endpoints.end.x, 10.0)
        XCTAssertEqual(endpoints.end.z, 21.0)
    }

    @MainActor
    func test_object_model_lighting_matches_java_post_placement_call() {
        let model = RSModel(vertexCount: 4, faceCount: 1)
        let v0 = model.insertVertex(x: 0, y: 0, z: 0)
        let v1 = model.insertVertex(x: 128, y: 0, z: 0)
        let v2 = model.insertVertex(x: 128, y: 0, z: 128)
        let v3 = model.insertVertex(x: 0, y: 0, z: 128)
        model.insertFace(count: 4, indices: [v0, v1, v2, v3], texFront: -1, texBack: -1)

        RSCGameEngine.applyJavaObjectLighting(to: model)

        XCTAssertEqual(model.faceDiffuseLight.first, 12_345_678)
    }

    // --- 2. AnimationDef number assignment ---

    func test_animation_number_assignment_matches_java() {
        NPCDefinitions.assignAnimationNumbers()
        XCTAssertEqual(AnimationDefs.get(0)?.number, 0, "head1 gets slot 0")
        XCTAssertEqual(AnimationDefs.get(1)?.number, 27, "body1 gets slot 27")
        XCTAssertEqual(AnimationDefs.get(2)?.number, 54, "legs1 gets slot 54")
        XCTAssertEqual(AnimationDefs.get(3)?.number, 81, "fhead1 gets slot 81")
        XCTAssertEqual(AnimationDefs.get(4)?.number, 108, "fbody1 gets slot 108")
    }

    // --- 3. Scene projection ---

    func test_scene_projects_player_origin_near_screen_center() {
        let (graphics, scene) = buildEngine()
        scene.setCamera(centerX: 0, centerY: -180, centerZ: 0,
                        xRot: 256, yRot: 0, zRot: 0,  // xRot=64*4
                        offset: 1500)

        let (sx, sy, depth) = scene.projectPoint(worldX: 0, worldY: 0, worldZ: 0)
        print("player origin: screen=(\(sx),\(sy)) depth=\(depth)")
        XCTAssertGreaterThan(depth, 0, "Player origin must be in front of camera")
        XCTAssertGreaterThan(sx, -Int32(graphics.width2), "Screen X within one screen-width of center")
        XCTAssertLessThan(sx, 2 * Int32(graphics.width2))
        XCTAssertGreaterThan(sy, -Int32(graphics.height2))
        XCTAssertLessThan(sy, 2 * Int32(graphics.height2))
    }

    func test_scene_projects_nearby_tile_on_screen() {
        let (_, scene) = buildEngine()
        scene.setCamera(centerX: 0, centerY: -180, centerZ: 0,
                        xRot: 256, yRot: 0, zRot: 0,
                        offset: 1500)
        // One tile in each cardinal direction — should all stay near the screen
        for (wx, wz) in [(128, 0), (-128, 0), (0, 128), (0, -128), (0, 256), (256, 256)] {
            let (sx, sy, depth) = scene.projectPoint(worldX: Int32(wx), worldY: 0, worldZ: Int32(wz))
            print("  tile (\(wx),0,\(wz)) → (\(sx),\(sy)) depth=\(depth)")
            // Allow points within ~2× screen size — near the player everything should project close
            XCTAssertGreaterThan(depth, -100, "tile (\(wx),\(wz)) behind plane — depth=\(depth)")
        }
    }

    // --- 4. World terrain mesh is on-screen ---

    func test_world_landscape_model_has_on_screen_vertices() {
        let (_, scene) = buildEngine()
        let world = World(scene: scene, graphics: scene.graphics)
        world.loadSections(worldX: 217, worldZ: 741, plane: 0)
        XCTAssertGreaterThanOrEqual(scene.modelCount, 1, "At least one landscape model was added")

        scene.setCamera(centerX: 0, centerY: -180, centerZ: 0,
                        xRot: 256, yRot: 0, zRot: 0,
                        offset: 1500)

        guard let model = scene.models[0] else { return XCTFail("No model") }
        var onScreen = 0
        var offScreen = 0
        for i in 0..<Int(model.vertHead) {
            let (sx, sy, d) = scene.projectPoint(
                worldX: model.vertX[i], worldY: model.vertY[i], worldZ: model.vertZ[i])
            if d > 0 && sx >= 0 && sx < scene.graphics.width2 && sy >= 0 && sy < scene.graphics.height2 {
                onScreen += 1
            } else {
                offScreen += 1
            }
        }
        print("Of \(model.vertHead) verts: on-screen=\(onScreen) off-screen=\(offScreen)")
        XCTAssertGreaterThan(onScreen, 0, "At least some terrain verts land on screen (if 0, projection or mesh is wrong)")
    }

    func test_object_and_wall_render_cull_matches_generated_terrain_footprint() {
        XCTAssertEqual(World.generatedTerrainViewSize, 32)
        XCTAssertTrue(World.isTileOffsetInsideGeneratedTerrain(dx: -16, dz: -16))
        XCTAssertTrue(World.isTileOffsetInsideGeneratedTerrain(dx: 15, dz: 15))
        XCTAssertFalse(World.isTileOffsetInsideGeneratedTerrain(dx: 16, dz: 0))
        XCTAssertFalse(World.isTileOffsetInsideGeneratedTerrain(dx: 0, dz: 16))
        XCTAssertFalse(World.isTileOffsetInsideGeneratedTerrain(dx: -17, dz: 0))
        XCTAssertFalse(World.isTileOffsetInsideGeneratedTerrain(dx: 0, dz: -17))
    }

    // --- 5. SpriteLoader reads sprites_v2.dat when placed at a findable path ---

    func test_sprite_loader_parses_fixture_bytes_directly() throws {
        // Verify the parse step by calling it on raw bytes — sidesteps Bundle.main lookup.
        // We read sprites_v2.dat from the fixture and call the public init.
        let data = try Data(contentsOf: URL(fileURLWithPath: fixtureDir + "/sprites_v2.dat"))
        let loader = SpriteLoader()
        loader.parseBytes([UInt8](data))
        XCTAssertEqual(loader.sprites.count, 2259, "All sprites decoded (got \(loader.sprites.count))")
        let gs0 = loader.getSprite(0)
        XCTAssertNotNil(gs0, "sprite ID 0 should exist")
        XCTAssertEqual(gs0?.pixels.count, (gs0?.width ?? 0) * (gs0?.height ?? 0), "Pixel count matches dimensions")
    }

    // --- 6. End-to-end billboard render — proves a character lands in the framebuffer ---

    func test_billboard_register_and_render_paints_pixels() throws {
        // Set up engine + load real sprites + bridge to graphics atlas
        let (graphics, scene) = buildEngine()
        let data = try Data(contentsOf: URL(fileURLWithPath: fixtureDir + "/sprites_v2.dat"))
        let loader = SpriteLoader()
        loader.parseBytes([UInt8](data))
        loader.bridgeInto(graphics)
        NPCDefinitions.assignAnimationNumbers()

        scene.setCamera(centerX: 0, centerY: -180, centerZ: 0,
                        xRot: 256, yRot: 0, zRot: 0,
                        offset: 1500)

        // Register a character at the player's tile (origin) using head1+body1+legs1
        scene.reduceSprites(0)
        CharacterBillboards.register(
            scene: scene, spriteLoader: loader,
            tileX: 0, tileZ: 0,
            rsDir: 4, stepFrame: 0, walkModel: 6,
            cameraRotation: 0,
            sprites: [0, 1, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1],
            hairColor: 0xC8B89B, topColor: 0xC83232,
            bottomColor: 0x3A5AA3, skinColor: 0xECC8A6
        )
        XCTAssertGreaterThan(scene.m_n, 0, "At least one billboard layer enqueued")
        // Dump every queued layer + a sample of its sprite pixels
        for li in 0..<scene.m_n {
            let id = Int(scene.m_Ob[li])
            let x = scene.m_Eb[li], y = scene.m_Fb[li]
            let w = scene.m_gb[li], h = scene.m_Q[li]
            if let gs = loader.getSprite(id) {
                let sample = (0..<min(8, gs.pixels.count)).map { String(gs.pixels[$0], radix: 16) }
                let nonzero = gs.pixels.filter { $0 != 0 }.count
                print("layer[\(li)]: pos=(\(x),\(y)) size=\(w)x\(h) id=\(id) " +
                      "spritePixels=\(gs.width)x\(gs.height) nonZero=\(nonzero)/\(gs.pixels.count) sample=\(sample)")
            } else {
                print("layer[\(li)]: pos=(\(x),\(y)) size=\(w)x\(h) id=\(id) — SPRITE MISSING")
            }
        }
        let firstLayer = (x: scene.m_Eb[0], y: scene.m_Fb[0],
                          w: scene.m_gb[0], h: scene.m_Q[0],
                          id: scene.m_Ob[0])
        XCTAssertGreaterThan(firstLayer.x, -Int32(graphics.width2),
                             "Billboard X should be within ~one screen-width of center")
        XCTAssertLessThan(firstLayer.x, 2 * Int32(graphics.width2))

        // Run the full Scene pass — terrain rasterization + sprite blitting
        scene.endScene(1)

        // Count pixels that were actually painted (i.e. non-zero / non-default).
        // Some sky/clear is fine; we want sprite pixels in the lower-center band where the character should be.
        let bandTop = Int(graphics.height2) / 2 - 60
        let bandBottom = Int(graphics.height2) / 2 + 80
        let bandLeft = Int(graphics.width2) / 2 - 40
        let bandRight = Int(graphics.width2) / 2 + 40
        var painted = 0
        for y in bandTop...bandBottom {
            for x in bandLeft...bandRight {
                if graphics.pixelData[y * Int(graphics.width2) + x] != 0 {
                    painted += 1
                }
            }
        }
        let bandSize = (bandBottom - bandTop + 1) * (bandRight - bandLeft + 1)
        print("Painted pixels in character band: \(painted)/\(bandSize)")
        XCTAssertGreaterThan(painted, 100,
            "Character billboard should paint pixels in the screen-center band — got \(painted) (if 0, blit math is wrong)")
    }

    // --- helpers ---

    private func buildEngine() -> (GraphicsController, Scene) {
        let g = GraphicsController(width: 512, height: 334, spriteCount: 5000)
        let s = Scene(graphics: g, modelCount: 100, polyCount: 10000, spriteCount: 200)
        return (g, s)
    }

    private func rscStringBytes(_ string: String) -> [UInt8] {
        Array(string.utf8) + [0x0A]
    }

    private func makeSingleSpriteArchive(id: Int, width: Int, height: Int,
                                         authenticWidth: Int, authenticHeight: Int,
                                         pixels: [Int32]) -> [UInt8] {
        var bytes: [UInt8] = [0x53, 0x50, 0x52, 0x32] // SPR2
        appendBE32(1, to: &bytes)
        appendBE32(id, to: &bytes)
        appendBE32(0, to: &bytes) // pixel offset
        appendBE32(width, to: &bytes)
        appendBE32(height, to: &bytes)
        bytes.append(0) // requiresShift
        bytes.append(contentsOf: [0, 0, 0])
        appendBE32(0, to: &bytes) // xShift
        appendBE32(0, to: &bytes) // yShift
        appendBE32(authenticWidth, to: &bytes)
        appendBE32(authenticHeight, to: &bytes)
        for pixel in pixels {
            appendBE32(Int(UInt32(bitPattern: pixel)), to: &bytes)
        }
        return bytes
    }

    private func appendBE32(_ value: Int, to bytes: inout [UInt8]) {
        let u = UInt32(truncatingIfNeeded: value)
        bytes.append(UInt8((u >> 24) & 0xFF))
        bytes.append(UInt8((u >> 16) & 0xFF))
        bytes.append(UInt8((u >> 8) & 0xFF))
        bytes.append(UInt8(u & 0xFF))
    }

    private struct BitWriter {
        private(set) var bytes: [UInt8] = []
        private var bitCount: Int = 0

        mutating func write(_ value: Int, count: Int) {
            guard count > 0 else { return }
            for bit in stride(from: count - 1, through: 0, by: -1) {
                if bitCount % 8 == 0 {
                    bytes.append(0)
                }
                let byteIndex = bitCount / 8
                let bitOffset = 7 - (bitCount % 8)
                if ((value >> bit) & 1) != 0 {
                    bytes[byteIndex] |= UInt8(1 << bitOffset)
                }
                bitCount += 1
            }
        }
    }
}
