import SwiftUI

struct GameSelectorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#1a1a1a").ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("OpenRSC")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(Color(hex: "#c8a951"))
                        .padding(.top, 48)

                    Spacer()

                    GameCard(
                        title: "RuneScape Classic",
                        subtitle: "2001 era gameplay",
                        icon: "🗡️",
                        action: { appState.currentView = .serverBrowser(.rsc) }
                    )

                    GameCard(
                        title: "Old School RuneScape",
                        subtitle: "2007 era gameplay",
                        icon: "⚔️",
                        action: { appState.currentView = .serverBrowser(.osrs) }
                    )

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationBarBackButtonHidden(true)
        }
    }
}

private struct GameCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Text(icon)
                    .font(.system(size: 40))
                    .frame(width: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#888888"))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color(hex: "#c8a951"))
            }
            .padding(20)
            .background(Color(hex: "#2a2a2a"))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "#c8a951").opacity(0.3), lineWidth: 1)
            )
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
