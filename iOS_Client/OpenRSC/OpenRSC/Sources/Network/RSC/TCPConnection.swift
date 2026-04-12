import Foundation
import Network

// Raw TCP connection using Network.framework NWConnection.
// Reads RSC-framed packets: [UInt16 length (big-endian), byte opcode, payload...]
// where length counts the opcode byte + payload bytes.
final class TCPConnection: @unchecked Sendable {
    var onPacket: ((UInt8, Data) -> Void)?
    var onDisconnect: (() -> Void)?

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.openrsc.tcp", qos: .userInitiated)

    func connect(host: String, port: UInt16) async throws {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    continuation.resume()
                    self?.startReceiving()
                case .failed(let err):
                    continuation.resume(throwing: err)
                case .cancelled:
                    let cb = self?.onDisconnect
                    Task { @MainActor in cb?() }
                default:
                    break
                }
            }
            conn.start(queue: queue)
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

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
    }

    // MARK: - Private

    private func startReceiving() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let data = content, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                Task { @MainActor in self.onDisconnect?() }
                return
            }
            self.startReceiving()
        }
    }

    // Drains receiveBuffer, parsing RSC framed packets.
    // Frame format: [byte hi, byte lo] = length, then `length` bytes (first byte = opcode).
    private func processBuffer() {
        while receiveBuffer.count >= 2 {
            let hi = Int(receiveBuffer[0])
            let lo = Int(receiveBuffer[1])
            let length = (hi << 8) | lo

            guard length > 0, receiveBuffer.count >= 2 + length else { break }

            let opcode = receiveBuffer[2]
            let payload = length > 1 ? receiveBuffer.subdata(in: 3..<(2 + length)) : Data()
            receiveBuffer.removeFirst(2 + length)

            let op = opcode
            let pl = payload
            Task { @MainActor in
                self.onPacket?(op, pl)
            }
        }
    }
}
