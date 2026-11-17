import XCTest
@testable import Scape530

/// Byte-level tests of the server packets added for full rt4 `Protocol` coverage, written against rt4's read order.
final class ProtocolCoverageTests: XCTestCase {
	// MARK: byte helpers (the inverse of the Packet transforms)

	func g2(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
	func g2add(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8((v + 128) & 0xFF)] }
	func ig2(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
	func ig2add(_ v: Int) -> [UInt8] { [UInt8((v + 128) & 0xFF), UInt8(v >> 8 & 0xFF)] }
	func g4(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
	func ig4(_ v: Int) -> [UInt8] { g4(v).reversed() }
	/// `mg4`: bytes 23..16, 31..24, 7..0, 15..8.
	func mg4(_ v: Int) -> [UInt8] { [UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF), UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
	func cat(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }
	func str(_ s: String) -> [UInt8] { Array(s.utf8) + [0] }
	func g1sub(_ v: Int) -> UInt8 { UInt8((128 - v) & 0xFF) }

	func decode(_ op: Int, _ body: [UInt8]) throws -> ServerMessage {
		try ServerMessage.decode(GamePacket(opcode: op, payload: body))
	}

	// MARK: hint arrow (217)

	func testHintArrowNpc() throws {
		// flags = slot 1 << 6 | type 1, sprite 2, target 0x0123, 3 skipped bytes, model 65535 (none).
		let m = try decode(ServerProt.hintArrow, [1 << 6 | 1, 2] + g2(0x123) + [0, 0, 0] + g2(65535))
		guard case .hintArrow(let h) = m else { return XCTFail("\(m)") }
		XCTAssertEqual(h.slot, 1); XCTAssertEqual(h.type, 1); XCTAssertEqual(h.sprite, 2)
		XCTAssertEqual(h.target, 0x123); XCTAssertEqual(h.model, -1)
	}

	func testHintArrowPlayerAndModel() throws {
		let m = try decode(ServerProt.hintArrow, [3 << 6 | 10, 0] + g2(77) + [9, 9, 9] + g2(1234))
		guard case .hintArrow(let h) = m else { return XCTFail("\(m)") }
		XCTAssertEqual(h.slot, 3); XCTAssertEqual(h.type, 10); XCTAssertEqual(h.target, 77); XCTAssertEqual(h.model, 1234)
	}

	func testHintArrowTileOffsets() throws {
		// Types 2...6: rt4 folds them into a tile marker and offsets it to the centre or one edge.
		let expected = [2: (64, 64), 3: (0, 64), 4: (128, 64), 5: (64, 0), 6: (64, 128)]
		for (type, off) in expected {
			let m = try decode(ServerProt.hintArrow, [UInt8(type), 1] + g2(3200) + g2(3210) + [40] + g2(65535))
			guard case .hintArrow(let h) = m else { return XCTFail("\(m)") }
			XCTAssertEqual(h.type, 2, "type \(type)")
			XCTAssertEqual([h.tileX, h.tileZ, h.height], [3200, 3210, 40])
			XCTAssertEqual(h.offsetX, off.0, "type \(type)"); XCTAssertEqual(h.offsetZ, off.1, "type \(type)")
		}
	}

	func testHintArrowCleared() throws {
		let m = try decode(ServerProt.hintArrow, [2 << 6 | 0, 0] + g2(65535) + [0, 0, 0, 0, 0])
		guard case .hintArrow(let h) = m else { return XCTFail("\(m)") }
		XCTAssertEqual(h.slot, 2); XCTAssertEqual(h.type, 0)
	}

	// MARK: animation packets

	func testNpcAnimSpecific() throws {
		XCTAssertEqual(try decode(ServerProt.npcAnimSpecific, ig2(300) + [g1sub(5)] + g2(808)), .npcAnim(npc: 300, delay: 5, seq: 808))
		XCTAssertEqual(try decode(ServerProt.npcAnimSpecific, ig2(1) + [g1sub(0)] + g2(65535)), .npcAnim(npc: 1, delay: 0, seq: -1))
	}

	func testLocAnimSpecific() throws {
		let pos = 2 << 28 | 3222 << 14 | 3218
		// shape 10, rotation 3 -> 10 << 2 | 3.
		XCTAssertEqual(try decode(ServerProt.locAnimSpecific, [g1sub(10 << 2 | 3)] + g2(497) + g4(pos)),
		               .locAnimSpecific(level: 2, x: 3222, z: 3218, shape: 10, rotation: 3, seq: 497))
		XCTAssertEqual(try decode(ServerProt.locAnimSpecific, [g1sub(0)] + g2(65535) + g4(pos)),
		               .locAnimSpecific(level: 2, x: 3222, z: 3218, shape: 0, rotation: 0, seq: -1))
	}

	func testResetAnims() throws {
		XCTAssertEqual(try decode(ServerProt.resetAnims, []), .resetAnims)
	}

	func testZoneLocAnimNullSeq() throws {
		// LOC_ANIM: position (g1sub), type (g1sub), ig2 seq. 65535 clears the animation.
		let m = try decode(ServerProt.locAnim, [g1sub(0x23), g1sub(10 << 2 | 1)] + ig2(65535))
		if case .zoneUpdate(.locAnim(_, _, let shape, let rot, let seq)) = m {
			XCTAssertEqual([shape, rot, seq], [10, 1, -1])
		} else { XCTFail("\(m)") }
	}

	// MARK: interface packets

	func testWidgetStructSetting() throws {
		// IF_SET_EVENTS-like: value, parent, skipped, end, start.
		let m = try decode(ServerProt.widgetstructSetting, ig2add(7) + ig4(0x0102_0304) + g2add(0) + ig2(9) + g2add(2))
		XCTAssertEqual(m, .widgetStructSetting(component: 0x0102_0304, start: 2, end: 9, param: 7))
		let n = try decode(ServerProt.widgetstructSetting, ig2add(7) + ig4(5) + g2add(0) + ig2(65535) + g2add(65535))
		XCTAssertEqual(n, .widgetStructSetting(component: 5, start: -1, end: -1, param: 7))
	}

	func testGenerateChatHeadFromBody() throws {
		let m = try decode(ServerProt.generateChatHeadFromBody, g2add(0) + mg4(0x0102_0304) + ig2add(30) + ig2(10) + ig2add(20))
		XCTAssertEqual(m, .chatHeadFromBody(component: 0x0102_0304, kit1: 10, kit2: 20, kit3: 30))
	}

	func testInterfaceAnimateRotate() throws {
		let m = try decode(ServerProt.interfaceAnimateRotate, mg4(0x0A0B_0C0D) + g2add(0) + g2(12) + g2add(34))
		XCTAssertEqual(m, .modelRotation(component: 0x0A0B_0C0D, pitchStep: 12, yawStep: 34))
	}

	func testSettingsStringAndUrl() throws {
		XCTAssertEqual(try decode(ServerProt.setSettingsString, Array("abc".utf8) + [0]), .settingsString("abc"))
		XCTAssertEqual(try decode(ServerProt.urlOpen, Array("https://x.y/z".utf8)), .urlOpen("https://x.y/z"))
		XCTAssertThrowsError(try decode(ServerProt.setSettingsString, Array("abc".utf8) + [0, 1]))
	}

	// MARK: camera

	func testCameraPackets() throws {
		XCTAssertEqual(try decode(ServerProt.cameraDetach, g2(1) + [50, 60] + g2(300) + [10, 20]), .camMoveTo(x: 50, z: 60, height: 300, speed: 10, rotationSpeed: 20))
		XCTAssertEqual(try decode(ServerProt.camLookat, g2(1) + [51, 61] + g2(310) + [11, 21]), .camLookAt(x: 51, z: 61, height: 310, speed: 11, rotationSpeed: 21))
		XCTAssertEqual(try decode(ServerProt.camForceangle, ig2(512) + g2(0) + g2(200)), .camForceAngle(yaw: 512, pitch: 200))
		XCTAssertEqual(try decode(ServerProt.camShake, g2(1) + [3, 4, 5, 6] + g2(7)), .camShake(axis: 3, jitter: 4, amplitude: 5, frequency: 6, phase: 7))
		XCTAssertEqual(try decode(ServerProt.camReset, g2(1)), .camReset)
	}

	func testScriptedCameraMoveLookAndReset() {
		var c = WorldCamera()
		let flat: (Int, Int) -> Int = { _, _ in 0 }
		// A proportional speed of 100 snaps straight onto the target (the server packet's behaviour).
		c.moveTo(x: 10, z: 20, height: 300, speed: 5, rotationSpeed: 100, snap: true, tileHeight: flat)
		XCTAssertEqual(c.scripted?.x, 10 * 128 + 64)
		XCTAssertEqual(c.scripted?.z, 20 * 128 + 64)
		XCTAssertEqual(c.scripted?.y, -300)
		c.lookAt(x: 10, z: 30, height: 0, speed: 5, rotationSpeed: 100, tileHeight: flat)
		XCTAssertEqual(c.scripted?.yaw, 0)
		XCTAssertNotNil(c.scripted?.pitch)
		c.shakes[2].active = true
		c.resetEffects()
		XCTAssertNil(c.scripted)
		XCTAssertFalse(c.shakes[2].active)
		// CS2 passes snap false: the camera stays where it was until the cycle eases it over.
		var d = WorldCamera()
		d.moveTo(x: 10, z: 20, height: 300, speed: 5, rotationSpeed: 100, snap: false, tileHeight: flat)
		XCTAssertEqual(d.scripted?.x, 0)
	}

	// MARK: grand exchange

	func testGrandExchangeOffer() throws {
		// slot, status byte (status 3 | selling 8), item, price, count, done, gold.
		let m = try decode(ServerProt.grandExchangeOffers, cat([2, 0x0B], g2(4151), g4(1000), g4(10), g4(4), g4(4000)))
		XCTAssertEqual(m, .grandExchangeOffer(slot: 2, offer: ServerMessage.StockOffer(status: 3, type: 1, item: 4151, price: 1000, count: 10, completedCount: 4, completedGold: 4000)))
		let buy = try decode(ServerProt.grandExchangeOffers, cat([0, 0x05], g2(995), g4(1), g4(2), g4(3), g4(4)))
		XCTAssertEqual(buy, .grandExchangeOffer(slot: 0, offer: ServerMessage.StockOffer(status: 5, type: 0, item: 995, price: 1, count: 2, completedCount: 3, completedGold: 4)))
		// Status 0 is an empty slot; whatever follows is ignored.
		XCTAssertEqual(try decode(ServerProt.grandExchangeOffers, [4, 0, 1, 2, 3]), .grandExchangeOffer(slot: 4, offer: nil))
	}

	func testGameStateStoresOffers() throws {
		var s = GameState()
		s.apply(.grandExchangeOffer(slot: 1, offer: ServerMessage.StockOffer(status: 1, type: 1, item: 5, price: 6, count: 7, completedCount: 0, completedGold: 0)))
		XCTAssertEqual(s.stockOffers[1].item, 5)
		s.apply(.grandExchangeOffer(slot: 1, offer: nil))
		XCTAssertEqual(s.stockOffers[1], GameState.emptyOffer)
		s.apply(.settingsString("q"))
		XCTAssertEqual(s.settingsString, "q")
	}

	// MARK: reflection and the random file

	func testReflectionCheckAndReply() throws {
		// id 0x01020304, 2 checks: a type-0 (two strings) and a type-4 (two strings, 1 argument string).
		let body = cat([2], g4(0x0102_0304), [0], str("a"), str("b"), [4], str("c"), str("d"), [1], str("e"))
		XCTAssertEqual(try decode(ServerProt.reflectionCheatCheck, body), .reflectionCheck(id: 0x0102_0304, entries: 2))
		var cipher = IsaacRandom(seed: [1, 2, 3, 4])
		let bytes = ClientMessage.reflectionReply(id: 0x0102_0304, entries: 2, error: -1).encode(&cipher)
		let payload = Array(bytes.dropFirst(2))
		XCTAssertEqual(Int(bytes[1]), payload.count)
		XCTAssertEqual(Array(payload.prefix(6)), g4(0x0102_0304) + [0xFF, 0xFF])
		let crc = Crc32.checksum(payload.prefix(6))
		XCTAssertEqual(Array(payload.suffix(4)), g4(Int(UInt32(bitPattern: crc))))
	}

	func testUpdateRandomFile() throws {
		XCTAssertEqual(try decode(ServerProt.updateUid192, [UInt8](repeating: 0, count: 24)), .updateRandomFile)
		XCTAssertThrowsError(try decode(ServerProt.updateUid192, [UInt8](repeating: 0, count: 23)))
	}

	// MARK: dynamic regions

	/// A REBUILD_REGION payload with the given (level, x, z, packed) chunks and one key set per map square.
	func rebuildPayload(chunks: [(Int, Int, Int, Int)], keys: Int, zoneZ: Int) -> [UInt8] {
		var out = ig2add(40) + ig2add(401) + [g1sub(1)] + ig2add(41)
		var bits: [Bool] = []
		func put(_ v: Int, _ n: Int) { for i in stride(from: n - 1, through: 0, by: -1) { bits.append(v >> i & 1 == 1) } }
		for level in 0..<4 { for x in 0..<13 { for z in 0..<13 {
			if let c = chunks.first(where: { $0.0 == level && $0.1 == x && $0.2 == z }) { put(1, 1); put(c.3, 26) } else { put(0, 1) }
		} } }
		while bits.count % 8 != 0 { bits.append(false) }
		for i in stride(from: 0, to: bits.count, by: 8) {
			var b: UInt8 = 0
			for j in 0..<8 where bits[i + j] { b |= 0x80 >> UInt8(j) }
			out.append(b)
		}
		for k in 0..<keys { out += mg4(k * 4 + 1) + mg4(k * 4 + 2) + mg4(k * 4 + 3) + mg4(k * 4 + 4) }
		return out + g2(zoneZ)
	}

	func testRebuildRegionDynamic() throws {
		// packed = chunkX << 14 | chunkZ << 3 | rotation << 1 | level << 24 (rt4 `readRebuildPacket`).
		let a = 400 << 14 | 410 << 3 | 1 << 1 | 1 << 24
		let b = 800 << 14 | 410 << 3 | 3 << 1
		let payload = rebuildPayload(chunks: [(0, 6, 6, a), (1, 6, 7, b), (2, 0, 0, a)], keys: 2, zoneZ: 402)
		let m = try decode(ServerProt.rebuildRegion, payload)
		guard case .rebuildRegion(let r) = m else { return XCTFail("\(m)") }
		XCTAssertEqual(r.localX, 40); XCTAssertEqual(r.zoneX, 401); XCTAssertEqual(r.plane, 1)
		XCTAssertEqual(r.localZ, 41); XCTAssertEqual(r.zoneZ, 402)
		XCTAssertEqual(r.xteaKeys.count, 2)
		XCTAssertEqual(r.xteaKeys[1], [5, 6, 7, 8])
		let table = try XCTUnwrap(r.chunks)
		XCTAssertEqual(table[(0 * 13 + 6) * 13 + 6], a)
		XCTAssertEqual(table[(1 * 13 + 6) * 13 + 7], b)
		XCTAssertEqual(table[0], -1)
		XCTAssertTrue(r.isDynamic)
		// Squares: chunks 400/8 = 50, 410/8 = 51 and 800/8 = 100; `a` is used twice but listed once.
		XCTAssertEqual(r.regions.map { [$0.x, $0.z] }, [[50, 51], [100, 51]])
	}

	func testRebuildRegionTruncatedFails() {
		let payload = rebuildPayload(chunks: [], keys: 0, zoneZ: 1)
		XCTAssertThrowsError(try decode(ServerProt.rebuildRegion, Array(payload.prefix(20))))
	}

	func testChunkRotation() {
		// Four quarter turns bring any tile home, and each turn is a permutation of the chunk.
		for x in 0..<8 { for z in 0..<8 {
			var cx = x, cz = z
			for _ in 0..<4 {
				let nx = Scene.rotateChunkX(1, x: cx, z: cz), nz = Scene.rotateChunkZ(1, x: cx, z: cz)
				cx = nx; cz = nz
			}
			XCTAssertEqual([cx, cz], [x, z])
			XCTAssertEqual(Scene.rotateChunkX(2, x: x, z: z), 7 - x)
			XCTAssertEqual(Scene.rotateChunkZ(2, x: x, z: z), 7 - z)
		} }
		var seen = Set<Int>()
		for x in 0..<8 { for z in 0..<8 { seen.insert(Scene.rotateChunkX(3, x: x, z: z) * 8 + Scene.rotateChunkZ(3, x: x, z: z)) } }
		XCTAssertEqual(seen.count, 64)
	}

	func testDynamicLocPlacement() {
		// A 2x1 loc at the chunk's west edge stays inside the chunk whatever the chunk and loc rotations.
		for chunkRot in 0..<4 { for locRot in 0..<4 {
			let x = WorldView.dynamicLocX(chunkRotation: chunkRot, locRotation: locRot, x: 0, z: 3, width: 2, length: 1)
			let z = WorldView.dynamicLocZ(chunkRotation: chunkRot, locRotation: locRot, x: 0, z: 3, width: 2, length: 1)
			XCTAssertTrue((0...7).contains(x) && (0...7).contains(z), "chunk \(chunkRot) loc \(locRot): \(x),\(z)")
		} }
		XCTAssertEqual(WorldView.dynamicLocX(chunkRotation: 0, locRotation: 0, x: 2, z: 5, width: 1, length: 1), 2)
		XCTAssertEqual(WorldView.dynamicLocZ(chunkRotation: 0, locRotation: 0, x: 2, z: 5, width: 1, length: 1), 5)
		// Turned a half turn the loc lands on the opposite side.
		XCTAssertEqual(WorldView.dynamicLocX(chunkRotation: 2, locRotation: 0, x: 2, z: 5, width: 1, length: 1), 5)
		XCTAssertEqual(WorldView.dynamicLocZ(chunkRotation: 2, locRotation: 0, x: 2, z: 5, width: 1, length: 1), 2)
	}
}
