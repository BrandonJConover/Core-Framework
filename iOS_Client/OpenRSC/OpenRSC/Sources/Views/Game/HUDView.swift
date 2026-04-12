import SwiftUI

enum HUDPanel {
    case chat, inventory, stats, map
}

struct HUDView: View {
    @Binding var activePanel: HUDPanel?

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                HUDButton(icon: "bubble.left", label: "Chat", panel: .chat, activePanel: $activePanel)
                Spacer()
                HUDButton(icon: "bag", label: "Inv", panel: .inventory, activePanel: $activePanel)
                Spacer()
                HUDButton(icon: "chart.bar", label: "Stats", panel: .stats, activePanel: $activePanel)
                Spacer()
                HUDButton(icon: "map", label: "Map", panel: .map, activePanel: $activePanel)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .background(Color(hex: "#1a1a1a").opacity(0.85))
        }
    }
}

private struct HUDButton: View {
    let icon: String
    let label: String
    let panel: HUDPanel
    @Binding var activePanel: HUDPanel?

    var isActive: Bool { activePanel == panel }

    var body: some View {
        Button(action: {
            activePanel = isActive ? nil : panel
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(isActive ? Color(hex: "#c8a951") : Color(hex: "#888888"))
            .frame(width: 60, height: 52)
        }
    }
}
