import SwiftUI

@main
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
        case .game(let server):
            GameView(server: server)
        }
    }
}
