import XCTest
@testable import Scape530

final class ProtocolTests: XCTestCase {
	func testJs5Handshake() {
		XCTAssertEqual(Js5Protocol.handshake(), [15, 0, 0, 2, 18])
		XCTAssertEqual(Js5Protocol.request(archive: 255, group: 255), [1, 255, 0, 255])
	}

	/// Builds a server response the way 2009scape chunks it and feeds it
	/// back a few bytes at a time.
	func testJs5ResponseParserHandlesBlockMarkers() throws {
		let payload = (0..<1500).map { UInt8($0 & 0xFF) }
		var container = Packet(capacity: payload.count + 9)
		container.p1(2); container.p4(payload.count); container.p4(9999); container.pdata(payload)
		let c = container.written

		var wire: [UInt8] = [7, 0x01, 0x02] // archive 7, group 258
		var produced = 0
		var blockPos = 3
		for b in c {
			if blockPos == 512 {
				wire.append(0xFF)
				blockPos = 1
			}
			wire.append(b)
			blockPos += 1
			produced += 1
		}
		// A second, tiny uncompressed response right behind it.
		wire += [255, 0, 255, 0, 0, 0, 0, 2, 0xAA, 0xBB]

		var parser = Js5Protocol.ResponseParser()
		var got: [Js5Protocol.Response] = []
		var i = 0
		while i < wire.count {
			let n = min(37, wire.count - i)
			got += try parser.feed(wire[i..<i + n])
			i += n
		}
		XCTAssertEqual(got.count, 2)
		XCTAssertEqual(got[0].archive, 7)
		XCTAssertEqual(got[0].group, 258)
		XCTAssertEqual(got[0].container, c)
		XCTAssertEqual(got[1].container, [0, 0, 0, 0, 2, 0xAA, 0xBB])
	}

	func testLoginPacketLayout() throws {
		var req = Login.Request(username: "player", password: "hunter2")
		req.archiveChecksums = (0..<28).map { Int32($0) }
		let enc = Login.encode(req, serverKey: 0x0102_0304_0506_0708, clientSeeds: (11, 22))
		XCTAssertEqual(enc.seeds, [11, 22, 0x01020304, 0x05060708])
		var p = Packet(enc.packet)
		XCTAssertEqual(try p.g1(), 16)
		let len = try p.g2()
		XCTAssertEqual(len, enc.packet.count - 3)
		XCTAssertEqual(try p.g4(), 530)
		XCTAssertEqual(try p.g1(), 255) // anInt39 = -1
		p.offset += 1 + 1 + 1 + 2 + 2 + 1 + 24
		XCTAssertEqual(try p.gjstr(), "")
		p.offset += 4 + 4 + 2
		for i in 0..<28 { XCTAssertEqual(try p.g4(), Int32(i)) }
		XCTAssertEqual(try p.g4(), 0) // fake idx28
		let rsaLen = try p.g1()
		XCTAssertEqual(p.remaining, rsaLen)
		XCTAssertEqual(Login.handshake(username: "player"), [14, UInt8((Base37.encode("player") >> 16) & 31)])
	}
}

final class GamePacketTests: XCTestCase {
	func testFramerHandlesFixedAndVariableLengths() throws {
		// Find a fixed-size opcode, a byte-prefixed one and a short-prefixed one from the table.
		let fixed = ServerProt.lengths.firstIndex { $0 > 0 }!
		let varByte = ServerProt.lengths.firstIndex(of: -1)!
		let varShort = ServerProt.lengths.firstIndex(of: -2)!
		var wire: [UInt8] = [UInt8(fixed)] + [UInt8](repeating: 7, count: ServerProt.lengths[fixed])
		wire += [UInt8(varByte), 3, 1, 2, 3]
		wire += [UInt8(varShort), 0x01, 0x02] + [UInt8](repeating: 9, count: 0x102)
		var f = GamePacketFramer(cipher: IsaacRandom(seed: [0, 0, 0, 0]))
		var got: [GamePacket] = []
		for b in wire { got += try f.feed([b]) }
		XCTAssertEqual(got.map(\.opcode), [fixed, varByte, varShort])
		XCTAssertEqual(got[1].payload, [1, 2, 3])
		XCTAssertEqual(got[2].payload.count, 0x102)
	}

	func testRebuildNormalLumbridge() throws {
		// Lumbridge spawn: tile (3222, 3218) -> zone (402, 402), local (54, 50).
		var p = Packet(capacity: 128)
		p.p2add(54)
		let regionCount = 9
		for i in 0..<regionCount {
			for k in 0..<4 {
				let v = Int32(i * 4 + k)
				// mg4 byte order: [b2, b3, b0, b1] -> write as rt4's mp4 equivalent
				let u = UInt32(bitPattern: v)
				p.p1(Int(u >> 16)); p.p1(Int(u >> 24)); p.p1(Int(u)); p.p1(Int(u >> 8))
			}
		}
		p.p1sub(0)
		p.p2(402)
		p.p2add(402)
		p.p2add(50)
		let r = try RebuildNormal(payload: p.written)
		XCTAssertEqual(r.localX, 54)
		XCTAssertEqual(r.localZ, 50)
		XCTAssertEqual(r.zoneX, 402)
		XCTAssertEqual(r.zoneZ, 402)
		XCTAssertEqual(r.worldX, 3222)
		XCTAssertEqual(r.worldZ, 3218)
		XCTAssertEqual(r.xteaKeys.count, regionCount)
		XCTAssertEqual(r.xteaKeys[2], [8, 9, 10, 11])
		XCTAssertEqual(r.regions.count, regionCount)
		XCTAssertEqual(r.regions[4].locGroupName, "l50_50")
	}
}
