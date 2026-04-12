import SwiftUI
import MetalKit

struct GameView: View {
    let server: ServerProfile
    @EnvironmentObject var appState: AppState
    @StateObject private var engine: RSCGameEngine
    @State private var activePanel: HUDPanel? = nil

    init(server: ServerProfile) {
        self.server = server
        _engine = StateObject(wrappedValue: RSCGameEngine())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Metal game surface — fills entire screen including safe area
            #if canImport(UIKit)
            MetalViewRepresentable(engine: engine)
                .ignoresSafeArea()
                .onTapGesture { location in
                    engine.touchTranslator.handleTap(at: location)
                }
            #else
            Color.black.ignoresSafeArea()
            #endif

            // HUD overlay
            VStack(spacing: 0) {
                Spacer()
                if let panel = activePanel {
                    PanelSheet(panel: panel)
                        .transition(.move(edge: .bottom))
                }
                HUDView(activePanel: $activePanel)
            }
            .animation(.easeInOut(duration: 0.2), value: activePanel)
        }
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(.keyboard)
        .task {
            await engine.start(server: server, appState: appState)
        }
        .onDisappear {
            engine.stop()
        }
    }
}

// Placeholder bottom sheet for HUD panels
private struct PanelSheet: View {
    let panel: HUDPanel

    var title: String {
        switch panel {
        case .chat: return "Chat"
        case .inventory: return "Inventory"
        case .stats: return "Skills"
        case .map: return "Map"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#c8a951"))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Text("(Coming soon)")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#666666"))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#222222"))
    }
}
