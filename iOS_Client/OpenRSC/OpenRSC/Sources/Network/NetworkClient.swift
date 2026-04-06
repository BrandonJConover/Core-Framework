import Foundation
import Network

/// Network client for communicating with the RSC game server.
/// Uses NWConnection for modern async networking.
actor NetworkClient {
    private var connection: NWConnection?
    private var isConnected = false

    // Packet buffer for reassembly
    private var receiveBuffer = Data()

    // Callbacks
    var onPacketReceived: ((Packet) -> Void)?
    var onDisconnected: (() -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Callback Setters

    func setOnPacketReceived(_ handler: ((Packet) -> Void)?) {
        onPacketReceived = handler
    }

    enum NetworkError: Error, LocalizedError {
        case notConnected
        case connectionFailed(String)
        case sendFailed
        case invalidPacket

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Not connected to server"
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .sendFailed:
                return "Failed to send packet"
            case .invalidPacket:
                return "Invalid packet received"
            }
        }
    }

    /// Connects to the game server.
    func connect(host: String, port: Int) async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    await self?.handleStateChange(state, continuation: continuation)
                }
            }
            connection.start(queue: .global(qos: .userInteractive))
        }
    }

    private func handleStateChange(
        _ state: NWConnection.State,
        continuation: CheckedContinuation<Void, Error>?
    ) {
        switch state {
        case .ready:
            isConnected = true
            continuation?.resume()
            startReceiving()

        case .failed(let error):
            isConnected = false
            continuation?.resume(throwing: NetworkError.connectionFailed(error.localizedDescription))
            onDisconnected?()

        case .cancelled:
            isConnected = false
            onDisconnected?()

        case .waiting(let error):
            print("Connection waiting: \(error)")

        default:
            break
        }
    }

    /// Disconnects from the server.
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        receiveBuffer.removeAll()
    }

    /// Sends a packet to the server.
    func send(_ packet: Packet) async throws {
        guard let connection = connection, isConnected else {
            throw NetworkError.notConnected
        }

        let data = packet.encode()

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Starts receiving data from the server.
    private func startReceiving() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { [weak self] in
                guard let self = self else { return }

                if let data = content {
                    await self.handleReceivedData(data)
                }

                if let error = error {
                    await self.onError?(error)
                    return
                }

                if isComplete {
                    await self.disconnect()
                    return
                }

                // Continue receiving
                await self.startReceiving()
            }
        }
    }

    /// Handles received data and extracts complete packets.
    private func handleReceivedData(_ data: Data) {
        receiveBuffer.append(data)

        // Process all complete packets in the buffer
        while let packet = tryReadPacket() {
            onPacketReceived?(packet)
        }
    }

    /// Attempts to read a complete packet from the buffer.
    /// RSC packet format: [length:2][opcode:1][data:length-1]
    private func tryReadPacket() -> Packet? {
        // Need at least 2 bytes for length
        guard receiveBuffer.count >= 2 else { return nil }

        // Read length (big-endian short)
        let length = Int(receiveBuffer[0]) << 8 | Int(receiveBuffer[1])

        // Check if we have the complete packet
        guard receiveBuffer.count >= 2 + length else { return nil }

        // Read opcode
        let opcode = receiveBuffer[2]

        // Read payload
        let payloadLength = length - 1
        let payload: Data
        if payloadLength > 0 {
            payload = receiveBuffer.subdata(in: 3..<(3 + payloadLength))
        } else {
            payload = Data()
        }

        // Remove processed bytes from buffer
        receiveBuffer.removeFirst(2 + length)

        return Packet(opcode: opcode, payload: payload)
    }
}

/// Represents a network packet.
struct Packet {
    let opcode: UInt8
    let payload: Data

    var length: Int { payload.count }

    init(opcode: UInt8, payload: Data = Data()) {
        self.opcode = opcode
        self.payload = payload
    }

    /// Encodes the packet for transmission.
    /// Format: [length:2][opcode:1][data]
    func encode() -> Data {
        let frameLength = payload.count + 1 // +1 for opcode
        var data = Data(capacity: frameLength + 2)

        // Write length (big-endian)
        data.append(UInt8(frameLength >> 8))
        data.append(UInt8(frameLength & 0xFF))

        // Write opcode
        data.append(opcode)

        // Write payload
        data.append(payload)

        return data
    }
}

/// Packet reader for extracting data from packets.
struct PacketReader {
    var data: Data
    var position = 0

    // Bit-reading state
    private var bitPosition = 0
    private var isBitMode = false

    init(_ packet: Packet) {
        self.data = packet.payload
    }

    var remaining: Int { data.count - position }

    mutating func readByte() -> UInt8? {
        guard position < data.count else { return nil }
        defer { position += 1 }
        return data[position]
    }

    mutating func readSignedByte() -> Int8? {
        guard let byte = readByte() else { return nil }
        return Int8(bitPattern: byte)
    }

    mutating func readShort() -> UInt16? {
        guard position + 2 <= data.count else { return nil }
        let value = UInt16(data[position]) << 8 | UInt16(data[position + 1])
        position += 2
        return value
    }

    mutating func readSignedShort() -> Int16? {
        guard let value = readShort() else { return nil }
        return Int16(bitPattern: value)
    }

    mutating func readInt() -> UInt32? {
        guard position + 4 <= data.count else { return nil }
        let value = UInt32(data[position]) << 24 |
                    UInt32(data[position + 1]) << 16 |
                    UInt32(data[position + 2]) << 8 |
                    UInt32(data[position + 3])
        position += 4
        return value
    }

    mutating func readLong() -> UInt64? {
        guard position + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for i in 0..<8 {
            value = value << 8 | UInt64(data[position + i])
        }
        position += 8
        return value
    }

    mutating func readString() -> String? {
        var bytes = [UInt8]()
        while let byte = readByte(), byte != 0 {
            bytes.append(byte)
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    mutating func readBytes(_ count: Int) -> Data? {
        guard position + count <= data.count else { return nil }
        let bytes = data.subdata(in: position..<(position + count))
        position += count
        return bytes
    }

    // MARK: - Bit Reading

    mutating func startBitReading() {
        bitPosition = position * 8
        isBitMode = true
    }

    mutating func finishBitReading() {
        position = (bitPosition + 7) / 8
        isBitMode = false
    }

    var hasMoreBits: Bool {
        return bitPosition < data.count * 8
    }

    mutating func readBits(_ numBits: Int) -> Int? {
        guard isBitMode else { return nil }
        var result = 0
        for _ in 0..<numBits {
            guard bitPosition < data.count * 8 else { return nil }
            let byteIndex = bitPosition / 8
            let bitIndex = 7 - (bitPosition % 8)
            result = (result << 1) | Int((data[byteIndex] >> bitIndex) & 1)
            bitPosition += 1
        }
        return result
    }

    mutating func readSignedBits(_ numBits: Int) -> Int? {
        guard let value = readBits(numBits) else { return nil }
        let signBit = 1 << (numBits - 1)
        if value >= signBit {
            return value - (signBit << 1)
        }
        return value
    }
}

/// Packet builder for constructing packets.
struct PacketBuilder {
    private var data = Data()

    mutating func writeByte(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeSignedByte(_ value: Int8) {
        data.append(UInt8(bitPattern: value))
    }

    mutating func writeShort(_ value: UInt16) {
        data.append(UInt8(value >> 8))
        data.append(UInt8(value & 0xFF))
    }

    mutating func writeInt(_ value: UInt32) {
        data.append(UInt8(value >> 24))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    mutating func writeLong(_ value: UInt64) {
        for i in (0..<8).reversed() {
            data.append(UInt8((value >> (i * 8)) & 0xFF))
        }
    }

    mutating func writeString(_ value: String) {
        if let bytes = value.data(using: .utf8) {
            data.append(bytes)
        }
        data.append(0) // Null terminator
    }

    /// Writes a string terminated with a linefeed (0x0A) instead of null.
    /// Required for the server's getString() which reads until byte 10.
    mutating func writeLinefeedString(_ value: String) {
        if let bytes = value.data(using: .utf8) {
            data.append(bytes)
        }
        data.append(0x0A) // Linefeed terminator
    }

    mutating func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }

    func build(opcode: UInt8) -> Packet {
        Packet(opcode: opcode, payload: data)
    }
}
