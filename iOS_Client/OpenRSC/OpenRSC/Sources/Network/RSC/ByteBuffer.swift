import Foundation

// Port of RSBuffer.java / Network_Base framing.
// Packet framing: [UInt16 length (big-endian), byte opcode, payload...]
// where length = 1 + payloadLength (opcode byte is counted in length).
final class ByteBuffer {
    private var data: [UInt8]
    private var readPos: Int = 0
    private var writePos: Int = 0
    private var packetStart: Int = 0

    init(capacity: Int = 5000) {
        data = [UInt8](repeating: 0, count: capacity)
    }

    // MARK: - Write

    func putByte(_ v: Int) {
        ensureCapacity(1)
        data[writePos] = UInt8(v & 0xFF)
        writePos += 1
    }

    func putShort(_ v: Int) {
        ensureCapacity(2)
        data[writePos]     = UInt8((v >> 8) & 0xFF)
        data[writePos + 1] = UInt8(v & 0xFF)
        writePos += 2
    }

    func putInt(_ v: Int) {
        ensureCapacity(4)
        data[writePos]     = UInt8((v >> 24) & 0xFF)
        data[writePos + 1] = UInt8((v >> 16) & 0xFF)
        data[writePos + 2] = UInt8((v >> 8) & 0xFF)
        data[writePos + 3] = UInt8(v & 0xFF)
        writePos += 4
    }

    func putLong(_ v: Int64) {
        putInt(Int((v >> 32) & 0xFFFFFFFF))
        putInt(Int(v & 0xFFFFFFFF))
    }

    // Writes string bytes followed by 0x0A linefeed terminator (RSC protocol).
    func putString(_ s: String) {
        let bytes = Array(s.utf8)
        ensureCapacity(bytes.count + 1)
        for b in bytes {
            data[writePos] = b
            writePos += 1
        }
        data[writePos] = 0x0A
        writePos += 1
    }

    // MARK: - Packet framing (matches Network_Base.newPacket / finishPacket)

    // Reserves 2 bytes for length header, then writes opcode byte.
    // Call finishPacket() to backfill the length.
    func newPacket(opcode: Int) {
        packetStart = writePos
        writePos += 2               // reserve 2 bytes for [UInt16 length]
        putByte(opcode)
    }

    // Backfills the 2-byte length header.
    // Length = bytes written after the 2-byte header (includes opcode byte).
    // Returns the complete packet as Data.
    func finishPacket() -> Data {
        let packetLen = writePos - packetStart - 2
        data[packetStart]     = UInt8((packetLen >> 8) & 0xFF)
        data[packetStart + 1] = UInt8(packetLen & 0xFF)
        let result = Data(data[packetStart..<writePos])
        writePos = packetStart
        return result
    }

    // MARK: - Read

    func setReadData(_ incoming: Data) {
        let bytes = [UInt8](incoming)
        if bytes.count > data.count {
            data = [UInt8](repeating: 0, count: bytes.count + 1024)
        }
        data.replaceSubrange(0..<bytes.count, with: bytes)
        readPos = 0
        writePos = bytes.count
    }

    func getByte() -> Int {
        guard readPos < writePos else { return 0 }
        let v = Int(Int8(bitPattern: data[readPos]))
        readPos += 1
        return v
    }

    func getUnsignedByte() -> Int {
        guard readPos < writePos else { return 0 }
        let v = Int(data[readPos])
        readPos += 1
        return v
    }

    func getShort() -> Int {
        let hi = getUnsignedByte()
        let lo = getUnsignedByte()
        let v = (hi << 8) | lo
        return v < 32768 ? v : v - 65536
    }

    func getUnsignedShort() -> Int {
        let hi = getUnsignedByte()
        let lo = getUnsignedByte()
        return (hi << 8) | lo
    }

    func get32() -> Int {
        let b0 = getUnsignedByte()
        let b1 = getUnsignedByte()
        let b2 = getUnsignedByte()
        let b3 = getUnsignedByte()
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    // Reads bytes until 0x0A linefeed terminator (RSC string format).
    func getString() -> String {
        var bytes = [UInt8]()
        while readPos < writePos {
            let b = data[readPos]
            readPos += 1
            if b == 0x0A { break }
            bytes.append(b)
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    var bytesRemaining: Int { max(0, writePos - readPos) }

    // MARK: - Private

    private func ensureCapacity(_ needed: Int) {
        if writePos + needed > data.count {
            data += [UInt8](repeating: 0, count: max(needed, 1024))
        }
    }
}
