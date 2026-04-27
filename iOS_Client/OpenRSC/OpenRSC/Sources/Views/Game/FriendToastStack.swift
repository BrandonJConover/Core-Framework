// Floating friend-status toasts. When the server pushes opcode 149
// (friend login/logout) we add an entry to worldState.friendToasts;
// this view renders the active ones and self-removes them after ~3s.

import SwiftUI

struct FriendToastStack: View {
    @ObservedObject var worldState: RSCWorldState
    @State private var pruneTimer: Timer?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(worldState.friendToasts) { toast in
                HStack(spacing: 6) {
                    Circle()
                        .fill(toast.online ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(toast.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(toast.online ? "online" : "offline")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.black.opacity(0.78))
                        .overlay(Capsule().stroke(Color(hex: "#c8a951").opacity(0.5), lineWidth: 1))
                )
                .foregroundColor(.white)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: worldState.friendToasts)
        .onAppear { startPruneTimer() }
        .onDisappear { pruneTimer?.invalidate() }
    }

    private func startPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let cutoff = Date().addingTimeInterval(-3.0)
                worldState.friendToasts.removeAll { $0.createdAt < cutoff }
            }
        }
    }
}
