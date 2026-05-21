import Foundation
import Network

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

// Raw TCP connection using Network.framework NWConnection.
// Matches Java client Network_Base.java / Network_Socket.java:
//   Incoming: [2-byte BE frameSize][opcode][payload] where frameSize includes the 2 header bytes
//   Java subtracts 2 from frameSize to get opcode+payload length
//   Login response is a single raw byte (not framed)
final class TCPConnection: @unchecked Sendable {
    var onPacket: ((UInt8, Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onLoginResponse: ((UInt8) -> Void)?

    private var connection: NWConnection?
    private var inBuffer = [UInt8]()
    private let queue = DispatchQueue(label: "com.openrsc.tcp", qos: .userInitiated)
    private var awaitingLoginResponse = false

    func connect(host: String, port: UInt16) async throws {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = conn
        let resumeGate = ResumeGate()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                conn.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        guard resumeGate.claim() else { return }
                        self?.scheduleReceive()
                        continuation.resume()
                    case .failed(let err):
                        guard resumeGate.claim() else { return }
                        continuation.resume(throwing: err)
                    case .cancelled:
                        if resumeGate.claim() {
                            continuation.resume(throwing: POSIXError(.ECONNABORTED))
                        }
                        let cb = self?.onDisconnect
                        Task { @MainActor in cb?() }
                    default:
                        break
                    }
                }
                conn.start(queue: queue)
            }
        } onCancel: {
            conn.cancel()
        }
    }

    func send(_ data: Data) async throws {
        guard let conn = connection else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func expectLoginResponse() {
        awaitingLoginResponse = true
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        inBuffer.removeAll()
    }

    // MARK: - Receive loop

    private func scheduleReceive() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let data = content, !data.isEmpty {
                // Append raw bytes to our buffer
                data.withUnsafeBytes { ptr in
                    self.inBuffer.append(contentsOf: ptr.bindMemory(to: UInt8.self))
                }
                print("[TCP] Recv \(data.count) bytes (buffer now \(self.inBuffer.count))")
                self.drainBuffer()
            }

            if isComplete || error != nil {
                print("[TCP] Connection closed: complete=\(isComplete) err=\(String(describing: error))")
                Task { @MainActor in self.onDisconnect?() }
                return
            }

            // Schedule next receive
            self.scheduleReceive()
        }
    }

    // MARK: - Packet parsing (matches Network_Base.readIncomingPacket)

    private func drainBuffer() {
        // 1) Login response: single raw byte, no frame header
        if awaitingLoginResponse && !inBuffer.isEmpty {
            let b = inBuffer.removeFirst()
            awaitingLoginResponse = false
            print("[TCP] Login response: \(b)")
            let cb = onLoginResponse
            Task { @MainActor in cb?(b) }
        }

        // 2) Framed packets: [2-byte BE frameSize][opcode][payload...]
        //    frameSize includes the 2 header bytes (server writes buffer.capacity which is payload+3)
        //    Java client: incomingPacketLength = read2bytes(); incomingPacketLength -= 2;
        //    Then reads incomingPacketLength bytes (first byte = opcode, rest = payload)
        var parsed = 0
        while inBuffer.count >= 2 {
            let frameSize = (Int(inBuffer[0]) << 8) | Int(inBuffer[1])
            let payloadLen = frameSize - 2  // matches Java: incomingPacketLength -= 2

            if payloadLen <= 0 || frameSize > 65536 {
                // Bad frame — skip these 2 bytes
                print("[TCP] Bad frame size \(frameSize), skipping")
                inBuffer.removeFirst(2)
                continue
            }

            // Need all frameSize bytes (2 header + payloadLen)
            guard inBuffer.count >= frameSize else {
                break // partial packet, wait for more data
            }

            // Extract opcode (first byte after header) and payload
            let opcode = inBuffer[2]
            let payload: Data
            if payloadLen > 1 {
                payload = Data(inBuffer[3..<frameSize])
            } else {
                payload = Data()
            }

            // Remove consumed bytes
            inBuffer.removeFirst(frameSize)
            parsed += 1

            // Dispatch to handler on main thread
            let op = opcode
            let pl = payload
            Task { @MainActor in
                self.onPacket?(op, pl)
            }
        }

        if parsed > 0 {
            print("[TCP] Parsed \(parsed) packet(s), \(inBuffer.count) remaining")
        }
    }
}
