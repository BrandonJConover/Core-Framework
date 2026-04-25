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
        case .game(let server, let username, let password):
            GameView(server: server, username: username, password: password)
        }
    }
}
