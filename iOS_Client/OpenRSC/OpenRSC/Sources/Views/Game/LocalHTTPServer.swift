#if canImport(UIKit)
import Foundation
import Network

/// Minimal HTTP/1.1 file server that serves app bundle files on 127.0.0.1.
///
/// WKWebView sandbox restrictions on physical devices block file:// access
/// and custom URL scheme handlers. A local loopback HTTP server sidesteps
/// all of those restrictions and gives the web content a proper secure origin
/// so ES module scripts load correctly.
final class LocalHTTPServer {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.openrsc.httpserver", attributes: .concurrent)
    private(set) var port: UInt16 = 0

    // MARK: - Lifecycle

    /// Start listening on a random available port. Returns the assigned port number.
    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params)

        let semaphore = DispatchSemaphore(value: 0)

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = self?.listener?.port?.rawValue ?? 0
                semaphore.signal()
            case .failed(let error):
                print("[LocalHTTPServer] Failed: \(error)")
                semaphore.signal()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        listener?.start(queue: queue)
        semaphore.wait()
        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            if let error = error {
                print("[LocalHTTPServer] Receive error: \(error)")
                connection.cancel()
                return
            }
            guard let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            self?.respond(to: data, on: connection)
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        let path = parsePath(from: requestData)
        let relativePath = path == "/" || path.isEmpty ? "index.html" : String(path.dropFirst())

        // WebClient is bundled as a folder reference — try WebClient/ subdir first, then bundle root
        let webClientURL = Bundle.main.bundleURL.appendingPathComponent("WebClient").appendingPathComponent(relativePath)
        let rootURL = Bundle.main.bundleURL.appendingPathComponent(relativePath)
        let fileURL = FileManager.default.fileExists(atPath: webClientURL.path) ? webClientURL : rootURL

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let body = try? Data(contentsOf: fileURL) else {
            send(statusCode: 404, mime: "text/plain", body: Data("Not found: \(relativePath)".utf8), on: connection)
            return
        }

        send(statusCode: 200, mime: mimeType(for: fileURL.pathExtension), body: body, on: connection)
    }

    private func send(statusCode: Int, mime: String, body: Data, on connection: NWConnection) {
        let statusText = statusCode == 200 ? "OK" : "Not Found"
        let header = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(mime)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-cache",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var response = Data(header.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    private func parsePath(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\r\n").first
               ?? text.components(separatedBy: "\n").first else { return "/" }

        // "GET /path?query HTTP/1.1"
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return "/" }

        return parts[1]
            .components(separatedBy: "?").first?
            .components(separatedBy: "#").first ?? "/"
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html":         return "text/html; charset=utf-8"
        case "js", "mjs":   return "application/javascript; charset=utf-8"
        case "css":          return "text/css; charset=utf-8"
        case "json":         return "application/json; charset=utf-8"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "svg":          return "image/svg+xml"
        case "ico":          return "image/x-icon"
        case "woff":         return "font/woff"
        case "woff2":        return "font/woff2"
        case "ttf":          return "font/ttf"
        case "wasm":         return "application/wasm"
        case "data":         return "application/octet-stream"
        case "webmanifest":  return "application/manifest+json"
        default:             return "application/octet-stream"
        }
    }
}
#endif
