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
    var onBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(server: server, onBack: onBack)
    }

    func makeUIView(context: Context) -> WKWebView {
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

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.scrollView.bounces = false
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor

        if coordinator.httpPort > 0,
           let url = URL(string: "http://127.0.0.1:\(coordinator.httpPort)/mudclient.html#free,\(server.host),\(server.wsPort)") {
            webView.load(URLRequest(url: url))
        } else {
            // Server failed to start — show diagnostic page
            webView.loadHTMLString(errorPage, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Private helpers

    private func nativeConfigScript(port: UInt16) -> String {
        """
        window.rscNativeConfig = {
          host: "\(server.host)",
          port: \(server.port),
          wsPort: \(server.wsPort),
          platform: "ios"
        };
        """
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

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let httpServer = LocalHTTPServer()
        let httpPort: UInt16
        var onBack: () -> Void

        init(server: ServerProfile, onBack: @escaping () -> Void) {
            self.onBack = onBack
            var assignedPort: UInt16 = 0
            do {
                assignedPort = try httpServer.start()
            } catch {
                print("[WebGameView] HTTP server failed to start: \(error)")
            }
            self.httpPort = assignedPort
            super.init()
        }

        deinit {
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

            default:
                break
            }
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
            print("[WebGameView] Navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[WebGameView] Provisional navigation failed: \(error)")
        }
    }
}
#endif
