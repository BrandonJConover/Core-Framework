import XCTest
@testable import Scape530

/// Golden values produced by running the rt4 Java classes from
/// reference/rt4-client (IsaacRandom with USE_ISAAC forced on,
/// JagString.encode37, Buffer.rsaenc with 2009scape's GlobalConfig key).
final class CryptoTests: XCTestCase {
	func testIsaacMatchesRt4() {
		var r = IsaacRandom(seed: [1, 2, 3, 4], enabled: true)
		var got: [Int: Int] = [:]
		for i in 0..<300 {
			let k = r.nextKey()
			if [0, 1, 2, 3, 4, 5, 255, 256, 299].contains(i) { got[i] = k }
		}
		XCTAssertEqual(got, [0: -621246914, 1: 1957022519, 2: -1345000077, 3: -2021884860, 4: -1882702437,
		                     5: 1616913581, 255: 681500538, 256: 1010642953, 299: 1519510071])
	}

	func testIsaacDisabledByDefault() {
		var r = IsaacRandom(seed: [1, 2, 3, 4])
		XCTAssertEqual(r.nextKey(), 0)
	}

	func testBase37MatchesRt4() {
		XCTAssertEqual(Base37.encode("Zezima"), 1813643468)
		XCTAssertEqual(Base37.encode("test_user 1"), 96890133386609615)
		XCTAssertEqual(Base37.encode("abcdefghijklmnop"), 187939216216112118)
		XCTAssertEqual(Base37.encode("a"), 1)
		XCTAssertEqual(Base37.encode("player"), 1132078325)
		XCTAssertEqual(Base37.decode(Base37.encode("player")), "player")
	}

	func testRsaBlockMatchesRt4() {
		var b = Packet(capacity: 64)
		b.p1(10); b.p4(11); b.p4(22); b.p4(33); b.p4(44)
		b.p8(Base37.encode("player"))
		b.pjstr("hunter2"); b.pjstr(""); b.pjstr(""); b.pjstr("")
		let enc = RsaKey.scape2009.encryptBlock(b.written)
		XCTAssertEqual(CompressionTests.hex("805ddcd120132d0b98170315cc3a0a359e93cc67a61736799f600a685106f592447ce690d5a7732999879f87f3567c92fb5e543dbf8c7cad5887245dbec6808816185796ff55f6e76d9ad55fa744e57352fc0d1fc7fd40cd2260ad272715b565a632f61d8c0506c1c52cdb758d515b993879901244d41958a9baa8984d20eef005"), enc)
	}

	func testXteaRoundTripWithZeroKeyIsIdentityShape() {
		// Encrypt with a reference XTEA, then decrypt with ours.
		let key: [Int32] = [0x01234567, -0x76543211, 0x0BADF00D, 0x1337]
		var plain: [UInt8] = [2, 0, 0, 0, 16] + (0..<16).map { UInt8($0) }
		var data = plain
		Self.xteaEncrypt(&data, key: key)
		XCTAssertNotEqual(data, plain)
		Xtea.decryptContainer(&data, key: key)
		XCTAssertEqual(data, plain)
		plain.removeAll()
	}

	static func xteaEncrypt(_ d: inout [UInt8], key: [Int32]) {
		let k = key.map { UInt32(bitPattern: $0) }
		var off = 5
		while off + 8 <= d.count {
			var v0 = Xtea.readU32(d, off), v1 = Xtea.readU32(d, off + 4), sum: UInt32 = 0
			for _ in 0..<32 {
				v0 &+= (((v1 << 4) ^ (v1 >> 5)) &+ v1) ^ (sum &+ k[Int(sum & 3)])
				sum &+= 0x9E37_79B9
				v1 &+= (((v0 << 4) ^ (v0 >> 5)) &+ v0) ^ (sum &+ k[Int((sum >> 11) & 3)])
			}
			Xtea.writeU32(&d, off, v0)
			Xtea.writeU32(&d, off + 4, v1)
			off += 8
		}
	}
}
