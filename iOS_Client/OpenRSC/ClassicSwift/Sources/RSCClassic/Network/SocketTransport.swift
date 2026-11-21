// Non-blocking TCP transport (the socket half of rsc-c's packet_stream_new).

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SocketError: Error {
    case resolve(String)
    case socket(Int32)
    case connect(Int32)
    case timeout
}

public final class SocketTransport: PacketTransport {
    private var fd: Int32 = -1

    /// Connects to host:port (IPv4, 5 second timeout, TCP_NODELAY, non-blocking).
    public init(host: String, port: Int, timeout: TimeInterval = 5) throws {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        #if canImport(Darwin)
        hints.ai_socktype = SOCK_STREAM
        #else
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #endif
        hints.ai_protocol = Int32(IPPROTO_TCP)
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let info = result else {
            throw SocketError.resolve(String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(result) }

        fd = socket(AF_INET, info.pointee.ai_socktype, 0)
        guard fd >= 0 else { throw SocketError.socket(errno) }

        var on: Int32 = 1
        setsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
        #if canImport(Darwin)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

        if connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) != 0 {
            guard errno == EINPROGRESS else {
                let err = errno
                close()
                throw SocketError.connect(err)
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&pfd, 1, Int32(timeout * 1000))
            if ready <= 0 {
                close()
                throw SocketError.timeout
            }
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
            if err != 0 {
                close()
                throw SocketError.connect(err)
            }
        }
    }

    public func receive(into buffer: UnsafeMutableRawBufferPointer) -> Int {
        guard fd >= 0, let base = buffer.baseAddress else { return 0 }
        if buffer.count == 0 { return -1 }
        return recv(fd, base, buffer.count, 0)
    }

    public func send(_ buffer: UnsafeRawBufferPointer) -> Int {
        guard fd >= 0, let base = buffer.baseAddress else { return -1 }
        #if canImport(Darwin)
        return write(fd, base, buffer.count)
        #else
        return Glibc.send(fd, base, buffer.count, Int32(MSG_NOSIGNAL))
        #endif
    }

    public func close() {
        if fd >= 0 {
            #if canImport(Darwin)
            Darwin.close(fd)
            #else
            Glibc.close(fd)
            #endif
            fd = -1
        }
    }

    deinit { close() }
}
