import XCTest
@testable import RSCClassic

/// ISAAC, RSA and packet framing checked against rsc-c (golden output from tools/netdump.c).
final class NetworkTests: XCTestCase {
    static let modulus = "87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25"
    let keys: [UInt32] = [0x12345678, 0x9abcdef0, 0x0badf00d, 0xdeadbeef]

    /// A loopback transport: `incoming` is what the server sent, `outgoing` what the client wrote.
    final class MockTransport: PacketTransport {
        var incoming: [UInt8] = []
        var outgoing: [UInt8] = []
        func receive(into buffer: UnsafeMutableRawBufferPointer) -> Int {
            if incoming.isEmpty { return -1 }
            let n = min(buffer.count, incoming.count)
            for i in 0..<n { buffer[i] = incoming[i] }
            incoming.removeFirst(n)
            return n
        }
        func send(_ buffer: UnsafeRawBufferPointer) -> Int {
            outgoing += buffer
            return buffer.count
        }
        func close() {}
    }

    func testMatchesCEngine() throws {
        let golden = String(decoding: try Data(contentsOf: TestPaths.golden.appendingPathComponent("net.txt")),
                            as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lines: [String] = []
        func hex(_ tag: String, _ bytes: [UInt8]) { lines.append(tag + bytes.map { String(format: "%02x", $0) }.joined()) }

        var isaac = ISAAC(seed: keys)
        lines.append("isaac" + (0..<600).map { _ in " \(isaac.next())" }.joined())
        var zero = ISAAC()
        zero.initialise(useSeed: false)
        lines.append("isaac0" + (0..<10).map { _ in " \(zero.next())" }.joined())

        let rsa = try XCTUnwrap(RSA(exponentHex: "00010001", modulusHex: Self.modulus))
        let inputs: [[UInt8]] = [[1], Array("hello world".utf8),
                                 [0x0a, 0x12, 0x34, 0x56, 0x78] + Array(" a much longer login-ish block of bytes!!\n".utf8)]
        for input in inputs { hex("rsa ", rsa.crypt(input)) }
        let rsa2 = try XCTUnwrap(RSA(exponentHex: "81f390b2cf8ca7039ee507975951d5a0b15a87bf8b3f99c966834118c50fd94d",
                                     modulusHex: "88c38748a58228f7261cdc340b5691d7d0975dee0ecdb717609e6bf971eb3fe723ef9d130e4686813739768ad9472eb46d8bfcc042c1a5fcb05e931f632eea5d"))
        hex("rsa2 ", rsa2.crypt(inputs[2]))

        let transport = MockTransport()
        let ps = PacketStream(transport: transport, rsa: rsa)
        func out(_ tag: String) { hex(tag, Array(ps.packetData[0..<ps.packetStart])) }
        ps.newPacket(67); ps.sendPacket(); out("out_empty ")
        ps.newPacket(45); ps.putByte(300); ps.putShort(-2); ps.putInt(Int(Int32(bitPattern: 0x89abcdef)))
        ps.putLong(0x0123456789abcdef); ps.putString("Zezima"); ps.sendPacket(); out("out_mixed ")
        ps.newPacket(216); for i in 0..<200 { ps.putByte(i * 7) }
        ps.sendPacket(); out("out_long ")
        ps.writePacket(0)
        hex("wire ", transport.outgoing)
        ps.newPacket(0); ps.putShort(204)
        ps.putLoginBlock(username: "tester", password: "secret123", isaacKeys: keys, uuid: 0x0a0b0c0d)
        ps.sendPacket(); out("out_login ")
        for i in 0..<5 { ps.newPacket(67); ps.putByte(i); ps.sendPacket() }
        out("out_isaac ")

        transport.incoming = [3, 0xaa, 0x10, 0x20, 1, 0x55, 161, 44] + (0..<300).map { UInt8(truncatingIfNeeded: $0 * 3 + 1) }
        var buffer = [UInt8](repeating: 0, count: 5000)
        for _ in 0..<6 {
            let n = ps.readPacket(into: &buffer)
            hex("read \(n) ", Array(buffer[0..<n]))
        }

        XCTAssertEqual(lines.count, golden.count - 1) // golden ends with a newline
        for (i, (a, e)) in zip(lines, golden).enumerated() where a != e {
            XCTFail("line \(i + 1):\n  swift: \(a.prefix(200))\n  c:     \(e.prefix(200))")
        }
    }
}
