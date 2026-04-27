// System update countdown banner. The server fires opcode 52 with a tick
// count when an admin schedules a reboot (mudclient.java:413 — server
// ticks * 32 = milliseconds). We show a top-of-screen amber strip
// counting down so players can finish what they're doing.

import SwiftUI

struct SystemUpdateBanner: View {
    @ObservedObject var worldState: RSCWorldState

    private var secondsRemaining: Int {
        max(0, worldState.systemUpdateTicks / 1000)
    }

    private var displayText: String {
        let s = secondsRemaining
        if s <= 0 { return "" }
        if s < 60 { return "System update in \(s)s" }
        let m = s / 60
        let r = s % 60
        return "System update in \(m)m \(r)s"
    }

    var body: some View {
        if worldState.systemUpdateTicks > 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(displayText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.78))
                    .overlay(Capsule().stroke(Color.yellow.opacity(0.7), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.5), radius: 4)
        }
    }
}
