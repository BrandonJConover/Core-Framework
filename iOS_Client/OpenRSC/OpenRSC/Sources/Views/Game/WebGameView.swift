#if canImport(UIKit)
import SwiftUI
import WebKit

/// Loads the bundled Local_RSC web app via a local HTTP server on 127.0.0.1.
///
/// Why a local HTTP server instead of file:// or a custom URL scheme:
///   - Physical device sandboxing blocks file:// access in WKWebView's
///     separate WebContent process ("Could not create a sandbox extension")
///   - Custom URL scheme handlers require HTTPURLResponse + correct MIME types
///     and still have issues with Vite's type="module" scripts on device
///   - A loopback HTTP server (127.0.0.1) has none of these restrictions,
///     gives the page a real origin, and lets ES modules load correctly
struct WebGameView: UIViewRepresentable {
    let server: ServerProfile
    let username: String?
    let password: String?
    var onBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(server: server, onBack: onBack)
    }

    func makeUIView(context: Context) -> WKWebView {
        UIApplication.shared.isIdleTimerDisabled = true

        let coordinator = context.coordinator

        let config = WKWebViewConfiguration()

        // Inject server config before any scripts run
        let configScript = WKUserScript(
            source: nativeConfigScript(port: coordinator.httpPort),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(configScript)

        // JS → Swift message bridge
        config.userContentController.add(coordinator, name: "nativeBridge")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.panGestureRecognizer.isEnabled = false
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        // dataDetectorTypes is not exposed on WKWebView (it's a UITextView property);
        // disabling auto-detection is configured via WKWebpagePreferences if ever needed.
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        coordinator.webView = webView

        if coordinator.httpPort > 0,
           let url = URL(string: "http://127.0.0.1:\(coordinator.httpPort)/mudclient.html?v=20260429-members#members") {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            coordinator.currentRequest = request
            webView.load(request)
        } else {
            // Server failed to start — show diagnostic page
            webView.loadHTMLString(errorPage, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        UIApplication.shared.isIdleTimerDisabled = false
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "nativeBridge")
        coordinator.httpServer.stop()
        coordinator.recordLog(level: "lifecycle", message: "WebGameView dismantled")
    }

    // MARK: - Private helpers

    private func nativeConfigScript(port: UInt16) -> String {
        let config: [String: Any] = [
            "host": server.host,
            "port": server.port,
            "wsPort": server.wsPort,
            "platform": "ios",
            "httpPort": Int(port),
            "launchArgs": ["members"],
            "autoLogin": [
                "username": username ?? "",
                "password": password ?? "",
                "direct": true,
                "skipTitle": true
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else {
            return "window.rscNativeConfig = { platform: \"ios\", launchArgs: [\"members\"] };"
        }

        return "window.rscNativeConfig = \(json);"
    }

    private var errorPage: String {
        """
        <html>
        <body style="background:#1a1a1a;color:#c8a951;font-family:sans-serif;padding:40px">
        <h2>Web client not available</h2>
        <p>The local HTTP server failed to start, or the web client was not bundled.</p>
        <p>From the repo root, run:<br>
        <code style="color:#fff">bash iOS_Client/build-web-client.sh</code><br>
        then rebuild in Xcode.</p>
        </body></html>
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let httpServer = LocalHTTPServer()
        let httpPort: UInt16
        var onBack: () -> Void
        weak var webView: WKWebView?
        var currentRequest: URLRequest?
        private let sessionLogURL: URL
        private var recentLogLines: [String] = []
        private var observers: [NSObjectProtocol] = []
        private let logQueue = DispatchQueue(label: "com.openrsc.webclient.logs", qos: .utility)
        private let maxRecentLogLines = 600
        private let maxAutomaticRecoveries = 1
        private var automaticRecoveryCount = 0
        private let logDateFormatter = ISO8601DateFormatter()

        init(server: ServerProfile, onBack: @escaping () -> Void) {
            self.onBack = onBack
            self.sessionLogURL = Self.makeLogURL(prefix: "webclient-session")
            var assignedPort: UInt16 = 0
            do {
                assignedPort = try httpServer.start()
            } catch {
                print("[WebGameView] HTTP server failed to start: \(error)")
            }
            self.httpPort = assignedPort
            super.init()
            pruneOldLogs()
            installLifecycleObservers()
            recordLog(
                level: "lifecycle",
                message: "Started web client session host=\(server.host) port=\(server.port) wsPort=\(server.wsPort) httpPort=\(assignedPort)"
            )
        }

        deinit {
            recordLog(level: "lifecycle", message: "Coordinator deinit; stopping local HTTP server")
            observers.forEach(NotificationCenter.default.removeObserver)
            httpServer.stop()
        }

        // JS → Swift messages
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "back":
                DispatchQueue.main.async { self.onBack() }

            case "haptic":
                let style = body["style"] as? String ?? "light"
                DispatchQueue.main.async { self.triggerHaptic(style: style) }

            case "log", "status", "error":
                let level = body["level"] as? String ?? type
                let text = body["message"] as? String ?? "\(body)"
                recordLog(level: level, message: text)

            default:
                recordLog(level: "bridge", message: "Unhandled native bridge message type=\(type)")
                break
            }
        }

        func recordLog(level: String, message: String) {
            let timestamp = logDateFormatter.string(from: Date())
            let trimmedMessage = message.count > 4_000
                ? String(message.prefix(4_000)) + "...[truncated]"
                : message
            let line = "\(timestamp) [\(level)] \(trimmedMessage)"

            recentLogLines.append(line)
            if recentLogLines.count > maxRecentLogLines {
                recentLogLines.removeFirst(recentLogLines.count - maxRecentLogLines)
            }

            print("[WebGameView:\(level)] \(trimmedMessage)")
            appendAsync(line: line, to: sessionLogURL)
        }

        private func triggerHaptic(style: String) {
            switch style {
            case "selection":
                UISelectionFeedbackGenerator().selectionChanged()
            case "medium":
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case "heavy":
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        // Allow local server, VPN, and WebSocket connections
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            let scheme = url?.scheme ?? ""
            let host = url?.host ?? ""

            // Allow: about:, local HTTP server, VPN address, WebSocket connections
            if scheme == "about"
                || (scheme == "http" && host == "127.0.0.1")
                || scheme == "ws" || scheme == "wss"
                || host == "10.8.0.1"
                || host.hasSuffix(".openrsc.com") {
                decisionHandler(.allow)
            } else {
                decisionHandler(.allow) // Allow all for now — ATS handles security
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            recordLog(level: "navigation", message: "Navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            recordLog(level: "navigation", message: "Provisional navigation failed: \(error)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            let bounds = webView.bounds
            let progress = String(format: "%.2f", webView.estimatedProgress)
            let url = webView.url?.absoluteString ?? "nil"
            let message = "Web content process terminated url=\(url) progress=\(progress) loading=\(webView.isLoading) bounds=\(Int(bounds.width))x\(Int(bounds.height))"
            recordLog(level: "crash", message: message)
            let crashLogURL = writeCrashSnapshot(reason: message)
            if scheduleAutomaticRecovery(after: crashLogURL.path) {
                webView.loadHTMLString(
                    WebGameView.webRecoveringPage(
                        sessionLogPath: sessionLogURL.path,
                        crashLogPath: crashLogURL.path
                    ),
                    baseURL: nil
                )
                return
            }
            webView.loadHTMLString(
                WebGameView.webCrashPage(
                    sessionLogPath: sessionLogURL.path,
                    crashLogPath: crashLogURL.path
                ),
                baseURL: nil
            )
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private static func makeLogURL(prefix: String) -> URL {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let filename = "\(prefix)-\(formatter.string(from: Date())).log"

            let baseURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            let directory = baseURL.appendingPathComponent("WebClientLogs", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent(filename)
        }

        private func writeCrashSnapshot(reason: String) -> URL {
            let url = Self.makeLogURL(prefix: "webclient-crash")
            var contents = """
            OpenRSC web client crash snapshot
            Reason: \(reason)
            Session log: \(sessionLogURL.path)
            Captured: \(logDateFormatter.string(from: Date()))

            Recent events:
            """
            contents += "\n" + recentLogLines.joined(separator: "\n") + "\n"
            do {
                try contents.write(to: url, atomically: true, encoding: .utf8)
                recordLog(level: "crash", message: "Wrote crash snapshot to \(url.path)")
            } catch {
                recordLog(level: "crash", message: "Failed to write crash snapshot: \(error)")
            }
            return url
        }

        private func scheduleAutomaticRecovery(after crashLogPath: String) -> Bool {
            guard automaticRecoveryCount < maxAutomaticRecoveries,
                  let request = currentRequest else {
                return false
            }

            automaticRecoveryCount += 1
            recordLog(
                level: "recovery",
                message: "Scheduling automatic web client recovery attempt \(automaticRecoveryCount)/\(maxAutomaticRecoveries) after crash log \(crashLogPath)"
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self,
                      let webView = self.webView else {
                    return
                }
                self.recordLog(level: "recovery", message: "Reloading web client after WebKit process termination")
                webView.load(request)
            }
            return true
        }

        private func appendAsync(line: String, to url: URL) {
            logQueue.async { [line, url] in
                self.append(line: line, to: url)
            }
        }

        private func append(line: String, to url: URL) {
            let data = Data((line + "\n").utf8)
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                print("[WebGameView:log] Failed to append web log: \(error)")
            }
        }

        private func installLifecycleObservers() {
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(
                    forName: UIApplication.didReceiveMemoryWarningNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.recordLog(level: "memory", message: "UIApplication didReceiveMemoryWarning")
                    self?.notifyWebClientOfMemoryWarning()
                }
            )
            observers.append(
                center.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.recordLog(level: "lifecycle", message: "UIApplication didEnterBackground")
                    UIApplication.shared.isIdleTimerDisabled = false
                    self?.notifyWebClientOfAppVisibility(isVisible: false)
                }
            )
            observers.append(
                center.addObserver(
                    forName: UIApplication.willEnterForegroundNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.recordLog(level: "lifecycle", message: "UIApplication willEnterForeground")
                    UIApplication.shared.isIdleTimerDisabled = true
                    self?.notifyWebClientOfAppVisibility(isVisible: true)
                }
            )
        }

        private func pruneOldLogs() {
            let directory = sessionLogURL.deletingLastPathComponent()
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            let logFiles = files.filter { $0.pathExtension == "log" }
            guard logFiles.count > 30 else {
                return
            }

            let sortedFiles = logFiles.sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

            for file in sortedFiles.dropFirst(30) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        private func notifyWebClientOfMemoryWarning() {
            webView?.evaluateJavaScript(
                "window._mudclientHandleMemoryWarning && window._mudclientHandleMemoryWarning()"
            ) { [weak self] _, error in
                if let error {
                    self?.recordLog(level: "memory", message: "Unable to notify web client of memory warning: \(error)")
                }
            }
        }

        private func notifyWebClientOfAppVisibility(isVisible: Bool) {
            let script = """
            window._mudclientHandleNativeVisibility && window._mudclientHandleNativeVisibility(\(isVisible ? "true" : "false"))
            """
            webView?.evaluateJavaScript(script) { [weak self] _, error in
                if let error {
                    self?.recordLog(level: "lifecycle", message: "Unable to notify web client visibility=\(isVisible): \(error)")
                }
            }
        }
    }

    private static func webRecoveringPage(sessionLogPath: String, crashLogPath: String) -> String {
        """
        <html>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
        <body style="background:#1a1a1a;color:#c8a951;font-family:-apple-system,sans-serif;padding:32px;text-align:center;line-height:1.45">
        <h2>Recovering web client</h2>
        <p style="color:#ddd">The embedded web client stopped, so the app saved diagnostics and is reopening it once automatically.</p>
        <p style="color:#ddd;font-size:12px;word-break:break-word;text-align:left">Crash log:<br>\(crashLogPath)</p>
        <p style="color:#ddd;font-size:12px;word-break:break-word;text-align:left">Session log:<br>\(sessionLogPath)</p>
        </body></html>
        """
    }

    private static func webCrashPage(sessionLogPath: String, crashLogPath: String) -> String {
        """
        <html>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
        <body style="background:#1a1a1a;color:#c8a951;font-family:-apple-system,sans-serif;padding:32px;text-align:center;line-height:1.45">
        <h2>Web client stopped</h2>
        <p style="color:#ddd">The embedded web client crashed. A diagnostic log was saved so we can inspect what happened before the WebKit process terminated.</p>
        <p style="color:#ddd;font-size:12px;word-break:break-word;text-align:left">Crash log:<br>\(crashLogPath)</p>
        <p style="color:#ddd;font-size:12px;word-break:break-word;text-align:left">Session log:<br>\(sessionLogPath)</p>
        </body></html>
        """
    }
}
#endif
