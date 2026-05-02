import SwiftUI

// Hide @main when building as a Swift Package library so test runners don't see
// a duplicate _main symbol. The Xcode iOS app build defines OPENRSC_APP.
#if OPENRSC_APP
@main
#endif
struct OpenRSCApp: App {
    @StateObject private var appState = AppState()

    var body: WindowGroup<AnyView> {
        WindowGroup {
            AnyView(
                RootView()
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
            )
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        switch appState.currentView {
        case .selector:
            GameSelectorView()
        case .serverBrowser(let gameType):
            ServerBrowserView(gameType: gameType)
        case .login(let server):
            LoginView(server: server)
        case .webGame(let server, let username, let password):
            WebGameScreen(server: server, username: username, password: password)
        case .game(let server, let username, let password):
            GameView(server: server, username: username, password: password)
        }
    }
}

private struct WebGameScreen: View {
    let server: ServerProfile
    let username: String?
    let password: String?
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .topLeading) {
            #if canImport(UIKit)
            WebGameView(server: server, username: username, password: password) {
                appState.currentView = .serverBrowser(server.gameType)
            }
            .ignoresSafeArea()
            #else
            Color(hex: "#1a1a1a").ignoresSafeArea()
            Text("Web client requires iOS")
                .foregroundColor(.white)
            #endif

            Button(action: { appState.currentView = .serverBrowser(server.gameType) }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color(hex: "#c8a951"), Color.black.opacity(0.55))
            }
            .padding(.top, 14)
            .padding(.leading, 14)
        }
    }
}
