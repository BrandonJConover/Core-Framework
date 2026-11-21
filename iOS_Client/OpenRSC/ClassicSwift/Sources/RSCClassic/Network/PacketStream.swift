// Packet framing for the RSC protocol: port of rsc-c's packet-stream.c.
// The socket is abstracted behind PacketTransport so the framing logic can be
// tested without a server.

import Foundation

/// A non-blocking byte stream (rsc-c uses a non-blocking TCP socket).
public protocol PacketTransport: AnyObject {
    /// Returns bytes read (> 0), 0 when the peer closed, or < 0 when no data is ready yet.
    func receive(into buffer: UnsafeMutableRawBufferPointer) -> Int
    /// Returns bytes written or < 0 on error.
    func send(_ buffer: UnsafeRawBufferPointer) -> Int
    func close()
}

public final class PacketStream {
    public static let bufferLength = 5000
    public static let usernameLength = 20
    public static let passwordLength = 20

    public let transport: PacketTransport
    public private(set) var closed = false
    var delay = 0
    var length = 0
    var maxReadTries = 1000
    public var packetData = [UInt8](repeating: 0, count: PacketStream.bufferLength)
    public private(set) var packetEnd = 3
    var packetMaxLength = 5000
    public private(set) var packetStart = 0
    var readTries = 0
    public private(set) var socketException = false
    public private(set) var socketExceptionMessage: String?
    var availableBuffer = [UInt8](repeating: 0, count: PacketStream.bufferLength)
    var availableLength = 0
    var availableOffset = 0

    let rsa: RSA
    public private(set) var isaacIn = ISAAC()
    public private(set) var isaacOut = ISAAC()
    public private(set) var isaacReady = false

    /// How long read_bytes sleeps between empty reads (delay_ticks(1) in C).
    public var retryDelay: TimeInterval = 0.001

    public init(transport: PacketTransport, rsa: RSA) {
        self.transport = transport
        self.rsa = rsa
    }

    func availableBytes(_ wanted: Int) -> Bool {
        if availableLength >= wanted { return true }
        let start = availableOffset + availableLength
        var bytes = availableBuffer.withUnsafeMutableBytes { buf in
            transport.receive(into: UnsafeMutableRawBufferPointer(rebasing: buf[start..<(start + wanted - availableLength)]))
        }
        if bytes < 0 { bytes = 0 }
        availableLength += bytes
        return availableLength >= wanted
    }

    /// Blocking read of `count` bytes into `buffer` starting at `at`. Returns false on close/timeout.
    func readBytes(_ count: Int, into buffer: inout [UInt8], at start: Int = 0) -> Bool {
        if closed { return false }
        var count = count
        var offset = start
        if availableLength > 0 {
            let copy = min(count, availableLength)
            for i in 0..<copy { buffer[offset + i] = availableBuffer[availableOffset + i] }
            count -= copy
            offset += copy
            availableLength -= copy
            availableOffset = availableLength == 0 ? 0 : availableOffset + copy
        }
        // Note: like C, the socket read below restarts at `start`, not after the copied bytes.
        offset = start
        var waited = 0
        while count > 0 {
            let bytes = buffer.withUnsafeMutableBytes { buf in
                transport.receive(into: UnsafeMutableRawBufferPointer(rebasing: buf[offset..<(offset + count)]))
            }
            if bytes > 0 {
                count -= bytes
                offset += bytes
            } else if bytes == 0 {
                closed = true
                return false
            } else {
                waited += 1
                if waited >= 5000 {
                    close()
                    return false
                }
                Thread.sleep(forTimeInterval: retryDelay)
            }
        }
        return true
    }

    func writeBytes(_ count: Int) -> Int {
        if closed { return -1 }
        return packetData.withUnsafeBytes { transport.send(UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
    }

    public func readByte() -> Int {
        if closed { return -1 }
        var b: [UInt8] = [0]
        return readBytes(1, into: &b) ? Int(b[0]) : -1
    }

    public var hasPacket: Bool { packetStart > 0 }

    /// The next key of the incoming ISAAC stream, which decodes an incoming opcode.
    public func nextIncomingIsaac() -> UInt32 { isaacIn.next() }

    /// Reads one incoming packet into `buffer` (opcode first). Returns its length, or 0 if none is complete yet.
    public func readPacket(into buffer: inout [UInt8]) -> Int {
        readTries += 1
        if maxReadTries > 0 && readTries > maxReadTries {
            socketException = true
            socketExceptionMessage = "time-out"
            maxReadTries += maxReadTries
            return 0
        }
        if length == 0 && availableBytes(2) {
            length = readByte()
            if length >= 160 {
                length = (length - 160) * 256 + readByte()
            }
        }
        if length > 0 && availableBytes(length) {
            if length >= 160 {
                if !readBytes(length, into: &buffer) { return 0 }
            } else {
                buffer[length - 1] = UInt8(truncatingIfNeeded: readByte())
                if length > 1 && !readBytes(length - 1, into: &buffer) { return 0 }
            }
            let n = length
            length = 0
            readTries = 0
            return n
        }
        return 0
    }

    public func newPacket(_ opcode: Int) {
        if packetStart > (packetMaxLength * 4) / 5 {
            if writePacket(0) < 0 {
                socketException = true
                socketExceptionMessage = "failed to write packet"
            }
        }
        var opcode = UInt32(truncatingIfNeeded: opcode)
        if isaacReady { opcode = opcode &+ isaacOut.next() }
        packetData[packetStart + 2] = UInt8(truncatingIfNeeded: opcode)
        packetData[packetStart + 3] = 0
        packetEnd = packetStart + 3
    }

    @discardableResult
    public func writePacket(_ minDelay: Int) -> Int {
        if socketException {
            packetStart = 0
            packetEnd = 3
            socketException = false
            return -1
        }
        delay += 1
        if delay < minDelay { return 0 }
        if packetStart > 0 {
            delay = 0
            if writeBytes(packetStart) < 0 { return -1 }
        }
        packetStart = 0
        packetEnd = 3
        return 0
    }

    public func sendPacket() {
        let len = packetEnd - packetStart - 2
        if len >= 160 {
            packetData[packetStart] = UInt8(truncatingIfNeeded: 160 + len / 256)
            packetData[packetStart + 1] = UInt8(truncatingIfNeeded: len)
        } else {
            packetData[packetStart] = UInt8(truncatingIfNeeded: len)
            packetEnd -= 1
            packetData[packetStart + 1] = packetData[packetEnd]
        }
        packetStart = packetEnd
    }

    @discardableResult
    public func flushPacket() -> Int {
        sendPacket()
        return writePacket(0)
    }

    public func putBytes(_ bytes: [UInt8]) {
        for b in bytes {
            packetData[packetEnd] = b
            packetEnd += 1
        }
    }

    public func putByte(_ v: Int) {
        packetData[packetEnd] = UInt8(truncatingIfNeeded: v)
        packetEnd += 1
    }

    public func putShort(_ v: Int) {
        putByte(v >> 8)
        putByte(v)
    }

    public func putInt(_ v: Int) {
        putByte(v >> 24)
        putByte(v >> 16)
        putByte(v >> 8)
        putByte(v)
    }

    public func putLong(_ v: Int64) {
        putInt(Int(Int32(truncatingIfNeeded: v >> 32)))
        putInt(Int(Int32(truncatingIfNeeded: v)))
    }

    public func putString(_ s: String) {
        putBytes(Array(s.utf8))
    }

    func putRSA(_ input: [UInt8]) {
        let result = rsa.crypt(input)
        putByte(64)
        if result.count < 64 {
            for _ in 0..<(64 - result.count) { putByte(0) }
        }
        putBytes(result)
    }

    /// Writes the RSA login block and switches on ISAAC opcode scrambling.
    public func putLoginBlock(username: String, password: String, isaacKeys: [UInt32], uuid: UInt32) {
        var block: [UInt8] = [0x0a]
        isaacIn = ISAAC()
        isaacOut = ISAAC()
        for i in 0..<4 {
            isaacIn.randrsl[i] = isaacKeys[i]
            isaacOut.randrsl[i] = isaacKeys[i]
            block += PacketStream.bigEndian(isaacKeys[i])
        }
        block += PacketStream.bigEndian(uuid)
        block += Array(username.utf8.prefix(PacketStream.usernameLength)) + [0x0a]
        block += Array(password.utf8.prefix(PacketStream.passwordLength)) + [0x0a]
        isaacIn.initialise(useSeed: true)
        isaacOut.initialise(useSeed: true)
        isaacReady = true
        putRSA(block)
    }

    static func bigEndian(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]
    }

    public func getByte() -> Int { readByte() }
    public func getShort() -> Int { getByte() * 256 + getByte() }
    public func getInt() -> Int { Int(Int32(truncatingIfNeeded: getShort() * 65536 + getShort())) }
    public func getLong() -> Int64 {
        let i = Int64(getShort()), j = Int64(getShort()), k = Int64(getShort()), l = Int64(getShort())
        return (i << 48) + (j << 32) + (k << 16) + l
    }

    public func close() {
        transport.close()
        closed = true
    }
}
