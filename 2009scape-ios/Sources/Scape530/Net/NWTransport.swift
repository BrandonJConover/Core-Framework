#if canImport(Network)
import Foundation
import Network

/// `ByteTransport` over Network.framework. The connection itself is fully asynchronous (system-managed
/// path monitoring, no thread parked in connect(2)); the blocking calls the game session makes are
/// bridged with semaphores, so only the dedicated network thread ever waits. Connect has a hard timeout
/// and reports why it failed ("Can't reach host:port (connection refused)").
public final class NWTransport: ByteTransport {
	private let connection: NWConnection
	private let queue = DispatchQueue(label: "scape530.nwtransport")
	private let lock = NSLock()
	private let readSignal = DispatchSemaphore(value: 0)
	private var inbox: [UInt8] = []
	private var inboxStart = 0
	private var closed = false
	private var failure: String?
	private var readTimeoutMs = 10_000

	public static func factory(timeoutSeconds: Int = 10) -> (String, Int) throws -> any ByteTransport {
		{ host, port in try NWTransport(host: host, port: port, timeoutSeconds: timeoutSeconds) }
	}

	public init(host: String, port: Int, timeoutSeconds: Int = 10) throws {
		guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port > 0 else {
			throw ConnectFailure(host: host, port: port, reason: "invalid port")
		}
		let tcp = NWProtocolTCP.Options()
		tcp.noDelay = true
		tcp.connectionTimeout = timeoutSeconds
		let params = NWParameters(tls: nil, tcp: tcp)
		connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)

		let ready = DispatchSemaphore(value: 0)
		let outcome = Outcome()
		connection.stateUpdateHandler = { [weak self] state in
			switch state {
			case .ready:
				if outcome.finish(nil) { ready.signal() }
			case .waiting(let error), .failed(let error):
				// `.waiting` means the path or host is unusable right now (refused, no route, no
				// permission); retrying silently would just look like a hang.
				if outcome.finish(NWTransport.describe(error)) { ready.signal() }
				self?.noteFailure(NWTransport.describe(error))
			case .cancelled:
				if outcome.finish("cancelled") { ready.signal() }
			default:
				break
			}
		}
		connection.start(queue: queue)
		if ready.wait(timeout: .now() + .seconds(timeoutSeconds + 2)) == .timedOut {
			_ = outcome.finish("timed out")
		}
		if let reason = outcome.reason {
			connection.stateUpdateHandler = nil
			connection.cancel()
			throw ConnectFailure(host: host, port: port, reason: reason)
		}
		connection.stateUpdateHandler = { [weak self] state in
			switch state {
			case .failed(let error): self?.noteFailure(NWTransport.describe(error))
			case .cancelled: self?.noteFailure(nil)
			default: break
			}
		}
		receiveLoop()
	}

	deinit { connection.cancel() }

	/// One-shot result of the connect attempt, shared with the state handler.
	private final class Outcome {
		private let lock = NSLock()
		private var done = false
		private(set) var reason: String?
		/// Records the first result; true if this call was it.
		func finish(_ reason: String?) -> Bool {
			lock.lock(); defer { lock.unlock() }
			if done { return false }
			done = true
			self.reason = reason
			return true
		}
	}

	static func describe(_ error: NWError) -> String {
		switch error {
		case .posix(let code):
			switch code {
			case .ECONNREFUSED: return "connection refused"
			case .ETIMEDOUT: return "timed out"
			case .EHOSTUNREACH, .ENETUNREACH: return "no route to host; on iOS also check Settings > Privacy > Local Network"
			case .ECONNRESET: return "connection reset"
			default: return "\(code)".lowercased()
			}
		case .dns: return "unknown host"
		case .tls: return "TLS error"
		default: return "\(error)"
		}
	}

	private func noteFailure(_ reason: String?) {
		lock.lock()
		closed = true
		if failure == nil { failure = reason }
		lock.unlock()
		readSignal.signal()
	}

	private func receiveLoop() {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
			guard let self else { return }
			self.lock.lock()
			if let data, !data.isEmpty { self.inbox.append(contentsOf: data) }
			if let error { self.failure = self.failure ?? NWTransport.describe(error); self.closed = true }
			if isComplete { self.closed = true }
			let finished = self.closed
			self.lock.unlock()
			self.readSignal.signal()
			if !finished { self.receiveLoop() }
		}
	}

	public func setReadTimeout(milliseconds: Int) {
		lock.lock(); readTimeoutMs = max(milliseconds, 1); lock.unlock()
	}

	public func write(_ bytes: [UInt8]) throws {
		lock.lock()
		let reason = closed ? (failure ?? "closed") : nil
		lock.unlock()
		if let reason { throw BlockingSocket.Failure(description: "send failed: \(reason)") }
		let done = DispatchSemaphore(value: 0)
		var sendError: NWError?
		connection.send(content: Data(bytes), completion: .contentProcessed { error in
			sendError = error
			done.signal()
		})
		if done.wait(timeout: .now() + .seconds(15)) == .timedOut {
			throw BlockingSocket.Failure(description: "send timed out")
		}
		if let sendError { throw BlockingSocket.Failure(description: "send failed: \(NWTransport.describe(sendError))") }
	}

	public func readSome(max: Int) throws -> [UInt8] {
		lock.lock()
		let timeout = readTimeoutMs
		lock.unlock()
		let deadline = DispatchTime.now() + .milliseconds(timeout)
		while true {
			lock.lock()
			let available = inbox.count - inboxStart
			if available > 0 {
				let n = min(available, max)
				let out = Array(inbox[inboxStart..<(inboxStart + n)])
				inboxStart += n
				if inboxStart == inbox.count { inbox.removeAll(keepingCapacity: true); inboxStart = 0 }
				lock.unlock()
				return out
			}
			let isClosed = closed, why = failure
			lock.unlock()
			if isClosed {
				if let why { throw BlockingSocket.Failure(description: "connection lost: \(why)") }
				return []
			}
			if readSignal.wait(timeout: deadline) == .timedOut {
				throw BlockingSocket.Failure(description: "recv timed out")
			}
		}
	}

	public func readExactly(_ count: Int) throws -> [UInt8] {
		var out: [UInt8] = []
		out.reserveCapacity(count)
		while out.count < count {
			let chunk = try readSome(max: count - out.count)
			guard !chunk.isEmpty else { throw BlockingSocket.Failure(description: "connection closed") }
			out += chunk
		}
		return out
	}

	public func close() {
		connection.cancel()
	}
}
#endif
