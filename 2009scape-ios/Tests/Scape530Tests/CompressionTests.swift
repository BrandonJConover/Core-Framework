import XCTest
@testable import Scape530

final class CompressionTests: XCTestCase {
	static let sample: [UInt8] = Array(String(repeating: "hello hello hello bzip2 world ", count: 20).utf8) + (0...255).map { UInt8($0) }

	static func hex(_ s: String) -> [UInt8] {
		var out: [UInt8] = []
		var i = s.startIndex
		while i < s.endIndex {
			let j = s.index(i, offsetBy: 2)
			out.append(UInt8(s[i..<j], radix: 16)!)
			i = j
		}
		return out
	}

	func testBzip2Headerless() throws {
		let body = Self.hex("314159265359bc9fccf70000bfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0011b461260009800098000000000000000000000000000000000000000000000000000000007534c4c04c000000000002600000000000000026000000000000000000000000000000001a5449e9851e8999436a0c264c4018984182683119343d400323d1346324d3236a60269a6269a0c80c10d06834003406100d32604068c20c11a6010c02c9832a18034a26ce1d3d81c11f5253c1aa2aa04384c2e1959161f1189c52bac245a4c01111922032a0102122232425262728292a2b2c2d2e2f30316d0003f400cc44d0d4d8dce0e4e8ecf3fc7a7c7e80828486888a8c8e9092949698e5a2d1e911e974da7d46a755abd66b75daf7374d86c52668020ea94021b2cebc00445b3da1b220457cf26a000209533e8040e80445b53e40889f0c00445b64e01038010479b300107e3db7dc3fa0008273db9440108043030507090b0dba87ddc46f2262a2f7b19be8ddff0383c28e8fe1f138bc6e3cb4bcc4ccd4dce4ecf4fd050d151d252d353d454d555d656d757d858d959da5adb5bdc5cdd5dde5edf5fe060e161e262e363e464e565e666e767e868e969ea6aeb6bec6ced6dee6eef6ff070f171f272f373f474f575f676f777f878f979fa7afb7bfc7cfd7dfe7e8bb9229c28485e4fe67b80")
		XCTAssertEqual(try Bzip2.decompress(body[...], expectedSize: Self.sample.count), Self.sample)
	}

	func testGzipJs5() throws {
		let gz = Self.hex("1f8b08000000000002ffcb48cdc9c957c8402293aa320b8c14caf38b725250c44765476589976560646266616563e7e0e4e2e6e1e5e3171014121611151397909492969195935750545256515553d7d0d4d2d6d1d5d33730343236313533b7b0b4b2b6b1b5b37770747276717573f7f0f4f2f6f1f5f30f080c0a0e090d0b8f888c8a8e898d8b4f484c4a4e494d4bcfc8cccacec9cdcb2f282c2a2e292d2bafa8acaaaea9adab6f686c6a6e696d6befe8eceaeee9edeb9f3071d2e42953a74d9f3173d6ec3973e7cd5fb070d1e2254b972d5fb172d5ea356bd7addfb071d3e62d5bb76ddfb173d7ee3d7bf7ed3f70f0d0e123478f1d3f71f2d4e93367cf9dbf70f1d2e52b57af5dbf71f3d6ed3b77efdd7ff0f0d1e3274f9f3d7ff1f2d5eb376fdfbdfff0f1d3e72f5fbf7dfff1f3d7ef3f7ffffd1f4d0da3b2a3f96a345f8dca8ee6aba190af009966c1bf080a0000")
		let expected = Self.sample + Self.sample + Self.sample
		XCTAssertEqual(try Inflate.gunzipJs5(gz[...], expectedSize: expected.count), expected)
	}

	func testContainerRoundTripsThroughBothCodecs() throws {
		// type 1 (bzip2) container wrapping the sample
		let body = Self.hex("314159265359bc9fccf70000bfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0011b461260009800098000000000000000000000000000000000000000000000000000000007534c4c04c000000000002600000000000000026000000000000000000000000000000001a5449e9851e8999436a0c264c4018984182683119343d400323d1346324d3236a60269a6269a0c80c10d06834003406100d32604068c20c11a6010c02c9832a18034a26ce1d3d81c11f5253c1aa2aa04384c2e1959161f1189c52bac245a4c01111922032a0102122232425262728292a2b2c2d2e2f30316d0003f400cc44d0d4d8dce0e4e8ecf3fc7a7c7e80828486888a8c8e9092949698e5a2d1e911e974da7d46a755abd66b75daf7374d86c52668020ea94021b2cebc00445b3da1b220457cf26a000209533e8040e80445b53e40889f0c00445b64e01038010479b300107e3db7dc3fa0008273db9440108043030507090b0dba87ddc46f2262a2f7b19be8ddff0383c28e8fe1f138bc6e3cb4bcc4ccd4dce4ecf4fd050d151d252d353d454d555d656d757d858d959da5adb5bdc5cdd5dde5edf5fe060e161e262e363e464e565e666e767e868e969ea6aeb6bec6ced6dee6eef6ff070f171f272f373f474f575f676f777f878f979fa7afb7bfc7cfd7dfe7e8bb9229c28485e4fe67b80")
		var p = Packet(capacity: body.count + 9)
		p.p1(1); p.p4(body.count); p.p4(Self.sample.count); p.pdata(body)
		XCTAssertEqual(try Js5Container.decompress(p.written), Self.sample)
	}

	func testBzip2MultiBlock() throws {
		// 250 KB input with 100k blocks -> 3 bzip2 blocks
		var expected = [UInt8](repeating: 0, count: 250_000)
		for i in 0..<expected.count {
			let v: Int = (i * 7 + i / 300) % 251
			expected[i] = UInt8(v)
		}
		let url = Bundle.module.url(forResource: "Fixtures/multiblock", withExtension: "bz2")!
		let body = [UInt8](try Data(contentsOf: url))
		XCTAssertEqual(try Bzip2.decompress(body[...], expectedSize: expected.count), expected)
	}
}
