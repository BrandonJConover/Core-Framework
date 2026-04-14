import SwiftUI

struct GameView: View {
    let server: ServerProfile
    @EnvironmentObject var appState: AppState

    var body: some View {
        #if canImport(UIKit)
        WebGameView(server: server) {
            appState.currentView = .serverBrowser(server.gameType)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        #else
        // macOS fallback — no UIKit/WKWebView support in this build target
        ZStack {
            Color(hex: "#1a1a1a").ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Game Client")
                    .foregroundColor(Color(hex: "#c8a951"))
                    .font(.system(size: 20, weight: .semibold))
                Text("Run on iOS to play.")
                    .foregroundColor(Color(hex: "#666666"))
                Button("Back") {
                    appState.currentView = .serverBrowser(server.gameType)
                }
                .foregroundColor(Color(hex: "#c8a951"))
            }
        }
        .navigationBarBackButtonHidden(true)
        #endif
    }
}
