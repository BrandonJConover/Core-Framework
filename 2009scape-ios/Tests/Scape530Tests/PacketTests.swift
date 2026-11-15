import XCTest
@testable import Scape530

final class PacketTests: XCTestCase {
	func testRoundTrip() throws {
		var p = Packet(capacity: 32)
		p.p1(200); p.p2(0xBEEF); p.p3(0x123456); p.p4(Int32(-2)); p.p8(0x0102_0304_0506_0708); p.pjstr("hi")
		var r = Packet(p.written)
		XCTAssertEqual(try r.g1(), 200)
		XCTAssertEqual(try r.g2(), 0xBEEF)
		XCTAssertEqual(try r.g3(), 0x123456)
		XCTAssertEqual(try r.g4(), -2)
		XCTAssertEqual(try r.g8(), 0x0102_0304_0506_0708)
		XCTAssertEqual(try r.gjstr(), "hi")
		XCTAssertThrowsError(try r.g1())
	}

	func testSmarts() throws {
		var r = Packet([0x40, 0xC0, 0x01, 0x05, 0x80, 0x10])
		XCTAssertEqual(try r.gsmart(), 0)
		XCTAssertEqual(try r.gsmart(), 1)
		XCTAssertEqual(try r.gsmarts(), 5)
		XCTAssertEqual(try r.gsmarts(), 0x10)
	}
}
