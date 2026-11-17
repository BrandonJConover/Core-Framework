import Foundation

/// A blocking byte stream as the game session sees it. `BlockingSocket` (BSD sockets) is the
/// Linux/test implementation; the iOS app installs a Network.framework one (`NWTransport`) through
/// `GameConnection.transportFactory`. All calls are made from one dedicated network thread.
public protocol ByteTransport: AnyObject {
	func write(_ bytes: [UInt8]) throws
	/// Reads up to `max` bytes; empty array on EOF; throws when the read timeout expires with no data.
	func readSome(max: Int) throws -> [UInt8]
	func readExactly(_ count: Int) throws -> [UInt8]
	func setReadTimeout(milliseconds: Int)
	func close()
}

extension ByteTransport {
	public func readSome() throws -> [UInt8] { try readSome(max: 65536) }
}

extension BlockingSocket: ByteTransport {}

/// Connection failures with text a player can act on.
public struct ConnectFailure: Error, CustomStringConvertible {
	public let host: String
	public let port: Int
	public let reason: String
	public init(host: String, port: Int, reason: String) {
		self.host = host
		self.port = port
		self.reason = reason
	}
	public var description: String {
		"Can't reach \(host):\(port)" + (reason.isEmpty ? "." : " (\(reason)). Check the address, that the server is running and that this device is on the same network.")
	}
}
