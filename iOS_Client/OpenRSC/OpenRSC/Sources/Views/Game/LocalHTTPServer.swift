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

    private enum ServerError: LocalizedError {
        case startTimedOut
        case failedToAssignPort

        var errorDescription: String? {
            switch self {
            case .startTimedOut:
                return "Timed out while starting local web-client server"
            case .failedToAssignPort:
                return "Local web-client server started without an assigned port"
            }
        }
    }

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
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            listener?.cancel()
            listener = nil
            throw ServerError.startTimedOut
        }

        guard port > 0 else {
            listener?.cancel()
            listener = nil
            throw ServerError.failedToAssignPort
        }

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
        let method = parseMethod(from: requestData)
        let path = parsePath(from: requestData)
        let relativePath = safeRelativePath(from: path)

        guard method == "GET" || method == "HEAD",
              let relativePath = relativePath else {
            send(statusCode: 400, mime: "text/plain", body: Data("Bad request".utf8), on: connection)
            return
        }

        if relativePath == "__health" {
            let body = diagnosticsBody()
            send(statusCode: 200, mime: "text/plain; charset=utf-8", body: Data(body.utf8), on: connection)
            return
        }

        let fileURL = fileURL(for: relativePath)

        guard let fileURL = fileURL,
              let body = try? Data(contentsOf: fileURL) else {
            let message = "Not found: \(relativePath)\n\n\(diagnosticsBody())"
            print("[LocalHTTPServer] \(message)")
            send(statusCode: 404, mime: "text/plain; charset=utf-8", body: Data(message.utf8), on: connection)
            return
        }

        send(statusCode: 200, mime: mimeType(for: fileURL.pathExtension), body: method == "HEAD" ? Data() : body, on: connection)
    }

    private func send(statusCode: Int, mime: String, body: Data, on connection: NWConnection) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        default: statusText = "Not Found"
        }
        let header = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(mime)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store, max-age=0",
            "Pragma: no-cache",
            "Expires: 0",
            "Cross-Origin-Resource-Policy: cross-origin",
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

    private func fileURL(for relativePath: String) -> URL? {
        candidateBaseURLs()
            .map { $0.appendingPathComponent(relativePath) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func candidateBaseURLs() -> [URL] {
        var urls: [URL] = []
        let fileManager = FileManager.default

        func append(_ url: URL?) {
            guard let url = url, !urls.contains(url) else { return }
            urls.append(url)
        }

        func appendBundleLocations(from bundle: Bundle) {
            append(bundle.url(forResource: "WebClient", withExtension: nil))
            append(bundle.url(forResource: "mudclient", withExtension: "html")?.deletingLastPathComponent())
            append(bundle.resourceURL?.appendingPathComponent("WebClient"))
            append(bundle.resourceURL?.appendingPathComponent("OpenRSC/Sources/WebClient"))
            append(bundle.resourceURL?.appendingPathComponent("Sources/WebClient"))
            append(bundle.resourceURL?.appendingPathComponent("Resources/WebClient"))
            append(bundle.bundleURL.appendingPathComponent("WebClient"))
            append(bundle.bundleURL.appendingPathComponent("OpenRSC/Sources/WebClient"))
            append(bundle.bundleURL.appendingPathComponent("Sources/WebClient"))
            append(bundle.bundleURL.appendingPathComponent("Resources/WebClient"))
            append(bundle.resourceURL)
            append(bundle.bundleURL)
        }

        appendBundleLocations(from: Bundle.main)

        #if SWIFT_PACKAGE
        appendBundleLocations(from: Bundle.module)
        #endif

        (Bundle.allBundles + Bundle.allFrameworks).forEach(appendBundleLocations)

        let searchRoots = urls
        for root in searchRoots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children where child.pathExtension == "bundle" {
                append(child.appendingPathComponent("WebClient"))
                append(child)

                if let bundle = Bundle(url: child) {
                    appendBundleLocations(from: bundle)
                }
            }
        }

        return urls
    }

    private func diagnosticsBody() -> String {
        let checks = candidateBaseURLs().map { baseURL -> String in
            let mudclientURL = baseURL.appendingPathComponent("mudclient.html")
            let exists = FileManager.default.fileExists(atPath: mudclientURL.path)
            return "\(exists ? "✓" : "x") \(mudclientURL.path)"
        }

        return """
        LocalHTTPServer diagnostics
        Bundle: \(Bundle.main.bundleURL.path)
        Resources: \(Bundle.main.resourceURL?.path ?? "(none)")
        Port: \(port)

        Searched:
        \(checks.joined(separator: "\n"))
        """
    }

    private func parseMethod(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\r\n").first
               ?? text.components(separatedBy: "\n").first else { return "" }

        return firstLine.components(separatedBy: " ").first ?? ""
    }

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

    private func safeRelativePath(from path: String) -> String? {
        let decodedPath = path.removingPercentEncoding ?? path
        let trimmedPath = decodedPath == "/" || decodedPath.isEmpty ? "/mudclient.html" : decodedPath
        let components = trimmedPath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." }

        guard !components.contains("..") else {
            return nil
        }

        return components.isEmpty ? "mudclient.html" : components.joined(separator: "/")
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
