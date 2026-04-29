// Welcome dialog shown once after login. Mirrors the Java client's
// `showLoginDialog` (PacketHandler.java:2396) — last login IP, days since
// previous login, recovery-questions countdown, and a tip-of-the-day.

import SwiftUI

struct WelcomePanel: View {
    @ObservedObject var worldState: RSCWorldState

    /// Tip text array — taken verbatim from mudclient.java's tipsArray (the
    /// six rotating strings shown in the welcome box).
    private static let tips: [String] = [
        "Try the Tutorial Island for a complete walkthrough of the game.",
        "Right-click an item to see all the actions you can do with it.",
        "Hold and drag the screen with one finger to rotate the camera.",
        "Pinch to zoom in and out of the world view.",
        "Tap the chat tab in the HUD to open the keyboard and type a message.",
        "Long-press an NPC or object to see its options."
    ]

    private var lastLoginText: String {
        let days = worldState.welcomeDaysAgo
        if days == 0 { return "earlier today" }
        if days == 1 { return "yesterday" }
        if days >= 1000 { return "never" }
        return "\(days) days ago"
    }

    private var recoveryText: String? {
        let r = worldState.welcomeRecoveryDays
        guard r > 0 && r < 14 else { return nil }
        return r == 1
            ? "Recovery questions will change tomorrow."
            : "Recovery questions will change in \(r) days."
    }

    var body: some View {
        ZStack {
            // Tap-anywhere-outside backdrop. Acts as a safety net if the
            // primary button slips off-screen on smaller landscape layouts.
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { worldState.welcomeOpen = false }
            VStack(spacing: 14) {
                Text("Welcome to \(worldState.serverName.isEmpty ? "OpenRSC" : worldState.serverName)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "#c8a951"))

                if !worldState.localPlayerName.isEmpty {
                    Text(worldState.localPlayerName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if !worldState.welcomeLastIP.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Last login from").foregroundColor(.gray)
                            Text(worldState.welcomeLastIP).foregroundColor(.white).bold()
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text("Last login was").foregroundColor(.gray)
                            Text(lastLoginText).foregroundColor(.white).bold()
                        }
                    }
                    if let recovery = recoveryText {
                        Text(recovery).foregroundColor(.orange)
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().background(Color(hex: "#c8a951").opacity(0.5))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tip of the Day")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#c8a951"))
                    let idx = max(0, min(Self.tips.count - 1, worldState.welcomeTipOfDay))
                    Text(Self.tips[idx])
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { worldState.welcomeOpen = false }) {
                    Text("Click here to play")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#c8a951"))
                        .cornerRadius(6)
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#1a1a1a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "#c8a951"), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
            .padding(20)
        }
    }
}
