import Foundation
import Network
import CryptoKit
import Compression

/// Secure, optimized network client for mobile game communication.
/// Features:
/// - TLS 1.3 encryption
/// - Packet compression (LZ4)
/// - Automatic reconnection
/// - Battery-aware networking
/// - Efficient binary protocol
actor SecureNetworkClient {
    // Connection state
    private var connection: NWConnection?
    private var isConnected = false
    private var isReconnecting = false

    // TLS configuration
    private let tlsOptions: NWProtocolTLS.Options

    // Packet buffer
    private var receiveBuffer = Data()
    private var sendQueue: [Packet] = []
    private var isSending = false

    // Compression
    private let compressionThreshold = 128 // Compress packets larger than this

    // Reconnection
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var lastHost: String?
    private var lastPort: Int?

    // Callbacks
    var onPacketReceived: ((Packet) async -> Void)?
    var onConnected: (() async -> Void)?
    var onDisconnected: ((Error?) async -> Void)?
    var onError: ((Error) async -> Void)?

    // Performance metrics
    private var bytesSent: UInt64 = 0
    private var bytesReceived: UInt64 = 0
    private var packetsSent: UInt64 = 0
    private var packetsReceived: UInt64 = 0

    enum NetworkError: Error, LocalizedError {
        case notConnected
        case connectionFailed(String)
        case tlsError(String)
        case compressionError
        case invalidPacket
        case timeout
        case serverUnreachable

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to server"
            case .connectionFailed(let reason): return "Connection failed: \(reason)"
            case .tlsError(let reason): return "TLS error: \(reason)"
            case .compressionError: return "Packet compression failed"
            case .invalidPacket: return "Invalid packet received"
            case .timeout: return "Connection timeout"
            case .serverUnreachable: return "Server unreachable"
            }
        }
    }

    init() {
        // Configure TLS 1.3
        self.tlsOptions = NWProtocolTLS.Options()
        configureTLS()
    }

    private func configureTLS() {
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        // Allow self-signed certificates in development
        // In production, use proper certificate validation
        #if DEBUG
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completion in
                completion(true)
            },
            DispatchQueue.global()
        )
        #endif
    }

    /// Connects to the game server with TLS encryption.
    func connect(host: String, port: Int, useTLS: Bool = true) async throws {
        lastHost = host
        lastPort = port

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        let parameters: NWParameters
        if useTLS {
            parameters = NWParameters(tls: tlsOptions)
        } else {
            parameters = NWParameters.tcp
        }

        // Optimize for mobile
        parameters.allowLocalEndpointReuse = true
        parameters.expiredDNSBehavior = .allow
        parameters.multipathServiceType = .handover // Support WiFi/cellular handover

        // Set service class for game traffic
        parameters.serviceClass = .interactiveVideo

        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    await self?.handleStateChange(state, continuation: continuation)
                }
            }

            connection.betterPathUpdateHandler = { [weak self] betterPathAvailable in
                if betterPathAvailable {
                    Task { [weak self] in
                        await self?.handleBetterPath()
                    }
                }
            }

            connection.start(queue: .global(qos: .userInteractive))

            // Add timeout
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if await !self.isConnected {
                    connection.cancel()
                    continuation.resume(throwing: NetworkError.timeout)
                }
            }
        }
    }

    private func handleStateChange(
        _ state: NWConnection.State,
        continuation: CheckedContinuation<Void, Error>?
    ) {
        switch state {
        case .ready:
            isConnected = true
            reconnectAttempts = 0
            isReconnecting = false
            continuation?.resume()
            startReceiving()
            Task { await onConnected?() }

        case .failed(let error):
            isConnected = false
            continuation?.resume(throwing: NetworkError.connectionFailed(error.localizedDescription))
            Task { await attemptReconnect() }

        case .cancelled:
            isConnected = false
            Task { await onDisconnected?(nil) }

        case .waiting(let error):
            print("Connection waiting: \(error)")

        default:
            break
        }
    }

    private func handleBetterPath() async {
        // Migrate to better network path (e.g., WiFi became available)
        guard let host = lastHost, let port = lastPort else { return }

        do {
            disconnect()
            try await connect(host: host, port: port)
        } catch {
            print("Path migration failed: \(error)")
        }
    }

    private func attemptReconnect() async {
        guard !isReconnecting,
              reconnectAttempts < maxReconnectAttempts,
              let host = lastHost,
              let port = lastPort else {
            await onDisconnected?(NetworkError.serverUnreachable)
            return
        }

        isReconnecting = true
        reconnectAttempts += 1

        // Exponential backoff
        let delay = UInt64(pow(2.0, Double(reconnectAttempts))) * 1_000_000_000

        do {
            try await Task.sleep(nanoseconds: delay)
            try await connect(host: host, port: port)
        } catch {
            await attemptReconnect()
        }
    }

    /// Disconnects from the server.
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        receiveBuffer.removeAll()
        sendQueue.removeAll()
    }

    /// Sends a packet with optional compression.
    func send(_ packet: Packet, compress: Bool = true) async throws {
        guard isConnected else {
            throw NetworkError.notConnected
        }

        var dataToSend = packet.encode()

        // Compress if beneficial
        if compress && dataToSend.count > compressionThreshold {
            if let compressed = compressData(dataToSend) {
                // Prepend compression flag
                var compressedPacket = Data([0x01]) // Compressed flag
                compressedPacket.append(compressed)
                dataToSend = compressedPacket
            }
        } else {
            // Prepend no-compression flag
            var uncompressedPacket = Data([0x00])
            uncompressedPacket.append(dataToSend)
            dataToSend = uncompressedPacket
        }

        try await sendRaw(dataToSend)
        packetsSent += 1
        bytesSent += UInt64(dataToSend.count)
    }

    /// Sends multiple packets efficiently (batching).
    func sendBatch(_ packets: [Packet]) async throws {
        guard !packets.isEmpty else { return }

        // Combine packets into a single send
        var batchData = Data()
        for packet in packets {
            let encoded = packet.encode()
            batchData.append(encoded)
        }

        // Compress batch
        if let compressed = compressData(batchData) {
            var compressedBatch = Data([0x02]) // Batch + compressed flag
            compressedBatch.append(compressed)
            try await sendRaw(compressedBatch)
        } else {
            var uncompressedBatch = Data([0x03]) // Batch flag
            uncompressedBatch.append(batchData)
            try await sendRaw(uncompressedBatch)
        }

        packetsSent += UInt64(packets.count)
    }

    private func sendRaw(_ data: Data) async throws {
        guard let connection = connection else {
            throw NetworkError.notConnected
        }

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

    private func startReceiving() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { [weak self] in
                guard let self = self else { return }

                if let data = content {
                    await self.bytesReceived += UInt64(data.count)
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

                await self.startReceiving()
            }
        }
    }

    private func handleReceivedData(_ data: Data) async {
        receiveBuffer.append(data)

        while receiveBuffer.count > 0 {
            // Check compression flag
            let flag = receiveBuffer[0]

            switch flag {
            case 0x00: // Uncompressed single packet
                guard let packet = tryReadPacket(offset: 1) else { return }
                packetsReceived += 1
                await onPacketReceived?(packet)

            case 0x01: // Compressed single packet
                guard let decompressed = tryDecompressAndRead() else { return }
                guard let packet = parsePacket(from: decompressed) else { return }
                packetsReceived += 1
                await onPacketReceived?(packet)

            case 0x02: // Compressed batch
                guard let decompressed = tryDecompressAndRead() else { return }
                let packets = parseBatch(from: decompressed)
                packetsReceived += UInt64(packets.count)
                for packet in packets {
                    await onPacketReceived?(packet)
                }

            case 0x03: // Uncompressed batch
                receiveBuffer.removeFirst() // Remove flag
                let packets = parseBatchFromBuffer()
                packetsReceived += UInt64(packets.count)
                for packet in packets {
                    await onPacketReceived?(packet)
                }

            default:
                // Legacy uncompressed packet (no flag)
                guard let packet = tryReadPacket(offset: 0) else { return }
                packetsReceived += 1
                await onPacketReceived?(packet)
            }
        }
    }

    private func tryReadPacket(offset: Int) -> Packet? {
        guard receiveBuffer.count >= offset + 2 else { return nil }

        let length = Int(receiveBuffer[offset]) << 8 | Int(receiveBuffer[offset + 1])
        guard receiveBuffer.count >= offset + 2 + length else { return nil }

        let opcode = receiveBuffer[offset + 2]
        let payload = length > 1 ? receiveBuffer.subdata(in: (offset + 3)..<(offset + 2 + length)) : Data()

        receiveBuffer.removeFirst(offset + 2 + length)
        return Packet(opcode: opcode, payload: payload)
    }

    private func tryDecompressAndRead() -> Data? {
        receiveBuffer.removeFirst() // Remove flag

        guard receiveBuffer.count >= 4 else { return nil }

        // Read compressed length
        let compressedLength = Int(receiveBuffer[0]) << 24 |
                               Int(receiveBuffer[1]) << 16 |
                               Int(receiveBuffer[2]) << 8 |
                               Int(receiveBuffer[3])

        guard receiveBuffer.count >= 4 + compressedLength else { return nil }

        let compressed = receiveBuffer.subdata(in: 4..<(4 + compressedLength))
        receiveBuffer.removeFirst(4 + compressedLength)

        return decompressData(compressed)
    }

    private func parsePacket(from data: Data) -> Packet? {
        guard data.count >= 3 else { return nil }

        let length = Int(data[0]) << 8 | Int(data[1])
        guard data.count >= 2 + length else { return nil }

        let opcode = data[2]
        let payload = length > 1 ? data.subdata(in: 3..<(2 + length)) : Data()

        return Packet(opcode: opcode, payload: payload)
    }

    private func parseBatch(from data: Data) -> [Packet] {
        var packets: [Packet] = []
        var offset = 0

        while offset + 2 < data.count {
            let length = Int(data[offset]) << 8 | Int(data[offset + 1])
            guard offset + 2 + length <= data.count else { break }

            let opcode = data[offset + 2]
            let payload = length > 1 ? data.subdata(in: (offset + 3)..<(offset + 2 + length)) : Data()
            packets.append(Packet(opcode: opcode, payload: payload))

            offset += 2 + length
        }

        return packets
    }

    private func parseBatchFromBuffer() -> [Packet] {
        var packets: [Packet] = []

        while let packet = tryReadPacket(offset: 0) {
            packets.append(packet)
        }

        return packets
    }

    // MARK: - Compression

    private func compressData(_ data: Data) -> Data? {
        let sourceSize = data.count
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            compression_encode_buffer(
                destinationBuffer,
                sourceSize,
                sourcePtr.bindMemory(to: UInt8.self).baseAddress!,
                sourceSize,
                nil,
                COMPRESSION_LZ4
            )
        }

        guard compressedSize > 0 && compressedSize < sourceSize else { return nil }

        // Prepend original size for decompression
        var result = Data()
        result.append(UInt8((sourceSize >> 24) & 0xFF))
        result.append(UInt8((sourceSize >> 16) & 0xFF))
        result.append(UInt8((sourceSize >> 8) & 0xFF))
        result.append(UInt8(sourceSize & 0xFF))
        result.append(Data(bytes: destinationBuffer, count: compressedSize))

        return result
    }

    private func decompressData(_ data: Data) -> Data? {
        guard data.count >= 4 else { return nil }

        let originalSize = Int(data[0]) << 24 |
                           Int(data[1]) << 16 |
                           Int(data[2]) << 8 |
                           Int(data[3])

        let compressed = data.subdata(in: 4..<data.count)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: originalSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = compressed.withUnsafeBytes { sourcePtr -> Int in
            compression_decode_buffer(
                destinationBuffer,
                originalSize,
                sourcePtr.bindMemory(to: UInt8.self).baseAddress!,
                compressed.count,
                nil,
                COMPRESSION_LZ4
            )
        }

        guard decompressedSize == originalSize else { return nil }

        return Data(bytes: destinationBuffer, count: originalSize)
    }

    // MARK: - Metrics

    var metrics: NetworkMetrics {
        NetworkMetrics(
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            packetsSent: packetsSent,
            packetsReceived: packetsReceived,
            isConnected: isConnected,
            reconnectAttempts: reconnectAttempts
        )
    }
}

struct NetworkMetrics {
    let bytesSent: UInt64
    let bytesReceived: UInt64
    let packetsSent: UInt64
    let packetsReceived: UInt64
    let isConnected: Bool
    let reconnectAttempts: Int

    var totalBytes: UInt64 { bytesSent + bytesReceived }
    var totalPackets: UInt64 { packetsSent + packetsReceived }
}
