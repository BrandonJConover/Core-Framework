#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Small blocking TCP socket over BSD sockets. Good for the probe CLI and
/// tests; the app will move to a non-blocking transport (Network.framework)
/// once the game loop exists.
public final class BlockingSocket {
	public struct Failure: Error, CustomStringConvertible {
		public let description: String
	}

	private var fd: Int32 = -1

	public init(host: String, port: Int, timeoutSeconds: Int = 10) throws {
		var hints = addrinfo()
		hints.ai_family = AF_UNSPEC
		#if canImport(Darwin)
		hints.ai_socktype = SOCK_STREAM
		#else
		hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
		#endif
		var res: UnsafeMutablePointer<addrinfo>?
		let rc = getaddrinfo(host, String(port), &hints, &res)
		guard rc == 0, let first = res else {
			throw Failure(description: "cannot resolve \(host)")
		}
		defer { freeaddrinfo(res) }
		var ai: UnsafeMutablePointer<addrinfo>? = first
		while let a = ai {
			let s = socket(a.pointee.ai_family, a.pointee.ai_socktype, a.pointee.ai_protocol)
			if s >= 0 {
				var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
				setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
				setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
				var one: Int32 = 1
				setsockopt(s, Int32(IPPROTO_TCP), TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
				if connect(s, a.pointee.ai_addr, a.pointee.ai_addrlen) == 0 {
					fd = s
					return
				}
				BlockingSocket.closeFD(s)
			}
			ai = a.pointee.ai_next
		}
		throw Failure(description: "cannot connect to \(host):\(port)")
	}

	deinit { close() }

	/// Receive timeout; `readSome` throws when it expires with no data.
	public func setReadTimeout(milliseconds: Int) {
		var tv = timeval(tv_sec: milliseconds / 1000, tv_usec: .init((milliseconds % 1000) * 1000))
		setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
	}

	public func close() {
		if fd >= 0 {
			BlockingSocket.closeFD(fd)
			fd = -1
		}
	}

	static func closeFD(_ fd: Int32) {
		#if canImport(Darwin)
		_ = Darwin.close(fd)
		#else
		_ = Glibc.close(fd)
		#endif
	}

	public func write(_ bytes: [UInt8]) throws {
		var sent = 0
		while sent < bytes.count {
			let n = bytes[sent...].withUnsafeBytes { buf in
				#if canImport(Darwin)
				Darwin.send(fd, buf.baseAddress, buf.count, 0)
				#else
				Glibc.send(fd, buf.baseAddress, buf.count, Int32(MSG_NOSIGNAL))
				#endif
			}
			guard n > 0 else { throw Failure(description: "send failed") }
			sent += n
		}
	}

	/// Reads up to `max` bytes; returns an empty array on EOF.
	public func readSome(max: Int = 65536) throws -> [UInt8] {
		var buf = [UInt8](repeating: 0, count: max)
		let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, max, 0) }
		guard n >= 0 else { throw Failure(description: "recv failed or timed out") }
		return Array(buf[0..<n])
	}

	public func readExactly(_ count: Int) throws -> [UInt8] {
		var out: [UInt8] = []
		out.reserveCapacity(count)
		while out.count < count {
			let chunk = try readSome(max: count - out.count)
			guard !chunk.isEmpty else { throw Failure(description: "connection closed") }
			out += chunk
		}
		return out
	}
}
