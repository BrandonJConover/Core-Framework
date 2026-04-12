import Foundation

// Protocol both RSCConnection and future OSRSConnection conform to.
@MainActor
protocol GameConnection: AnyObject {
    var onPacket: ((UInt8, Data) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    var isConnected: Bool { get }

    func connect(host: String, port: UInt16) async throws
    func send(_ data: Data) async throws
    func disconnect()
}
