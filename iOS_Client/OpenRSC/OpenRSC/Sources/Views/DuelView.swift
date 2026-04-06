import SwiftUI

struct DuelView: View {
    @ObservedObject var gameClient: GameClient
    let uiScale: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                Text("Duel with \(gameClient.tradePartnerName.isEmpty ? "Player" : gameClient.tradePartnerName)")
                    .font(.system(size: 14 * uiScale, weight: .bold))
                    .foregroundColor(ClassicPalette.accent)
                    .padding(8 * uiScale)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.2, green: 0.0, blue: 0.0))

                // Two-column stake lists
                HStack(alignment: .top, spacing: 1) {
                    // Your stake
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Stake")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text)
                        ForEach(Array(gameClient.duelMyItems.enumerated()), id: \.offset) { _, item in
                            Text("Item #\(item.id) x\(item.amount)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.text)
                        }
                        if gameClient.duelMyItems.isEmpty {
                            Text("(nothing)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.mutedText)
                        }
                        Spacer()
                    }
                    .padding(6 * uiScale)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(ClassicPalette.panel)

                    // Their stake
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Their Stake")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text)
                        ForEach(Array(gameClient.duelTheirItems.enumerated()), id: \.offset) { _, item in
                            Text("Item #\(item.id) x\(item.amount)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.text)
                        }
                        if gameClient.duelTheirItems.isEmpty {
                            Text("(nothing)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.mutedText)
                        }
                        Spacer()
                    }
                    .padding(6 * uiScale)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(ClassicPalette.panelAlt)
                }
                .frame(height: 120 * uiScale)

                // Duel rules (read-only)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rules:")
                        .font(.system(size: 10 * uiScale, weight: .semibold))
                        .foregroundColor(.orange)
                    if gameClient.duelSettings.disallowRetreat {
                        Text("• No retreat")
                            .font(.system(size: 10 * uiScale))
                            .foregroundColor(ClassicPalette.text)
                    }
                    if gameClient.duelSettings.disallowMagic {
                        Text("• No magic")
                            .font(.system(size: 10 * uiScale))
                            .foregroundColor(ClassicPalette.text)
                    }
                    if gameClient.duelSettings.disallowPrayer {
                        Text("• No prayer")
                            .font(.system(size: 10 * uiScale))
                            .foregroundColor(ClassicPalette.text)
                    }
                    if gameClient.duelSettings.disallowWeapons {
                        Text("• No weapons")
                            .font(.system(size: 10 * uiScale))
                            .foregroundColor(ClassicPalette.text)
                    }
                    if !gameClient.duelSettings.disallowRetreat && !gameClient.duelSettings.disallowMagic &&
                       !gameClient.duelSettings.disallowPrayer && !gameClient.duelSettings.disallowWeapons {
                        Text("Standard rules")
                            .font(.system(size: 10 * uiScale))
                            .foregroundColor(ClassicPalette.mutedText)
                    }
                }
                .padding(6 * uiScale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ClassicPalette.shellInset)

                // Status
                Text(gameClient.duelTheyAccepted ? "Opponent accepted" : "Waiting for opponent...")
                    .font(.system(size: 10 * uiScale))
                    .foregroundColor(gameClient.duelTheyAccepted ? .green : ClassicPalette.mutedText)
                    .padding(.vertical, 4 * uiScale)

                // Action buttons
                HStack(spacing: 8 * uiScale) {
                    Button(action: {
                        Task { try? await gameClient.sendTradeAccept() } // duel accept uses same opcode
                    }) {
                        Text(gameClient.duelAccepted ? "Accepted ✓" : "Accept")
                            .font(.system(size: 12 * uiScale, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16 * uiScale)
                            .padding(.vertical, 6 * uiScale)
                            .background(gameClient.duelAccepted ? Color.green.opacity(0.5) : Color.green)
                            .cornerRadius(4 * uiScale)
                    }
                    Button(action: {
                        Task { try? await gameClient.sendTradeDecline() } // duel decline uses same opcode
                    }) {
                        Text("Decline")
                            .font(.system(size: 12 * uiScale, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16 * uiScale)
                            .padding(.vertical, 6 * uiScale)
                            .background(Color.red)
                            .cornerRadius(4 * uiScale)
                    }
                }
                .padding(8 * uiScale)
                .background(Color(red: 0.15, green: 0.05, blue: 0.05))
            }
            .background(Color(red: 0.18, green: 0.08, blue: 0.08))
            .cornerRadius(8 * uiScale)
            .overlay(RoundedRectangle(cornerRadius: 8 * uiScale).stroke(Color.red.opacity(0.6), lineWidth: 1))
            .frame(width: 280 * uiScale)
            .shadow(radius: 8)
        }
    }
}

struct DuelConfirmView: View {
    @ObservedObject var gameClient: GameClient
    let uiScale: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Confirm Duel")
                    .font(.system(size: 14 * uiScale, weight: .bold))
                    .foregroundColor(ClassicPalette.accent)
                    .padding(8 * uiScale)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.2, green: 0.0, blue: 0.0))

                HStack(alignment: .top, spacing: 1) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You stake:")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text)
                        ForEach(Array(gameClient.duelMyItems.enumerated()), id: \.offset) { _, item in
                            Text("Item #\(item.id) x\(item.amount)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.text)
                        }
                        if gameClient.duelMyItems.isEmpty {
                            Text("(nothing)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.mutedText)
                        }
                        Spacer()
                    }
                    .padding(6 * uiScale)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(ClassicPalette.panel)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("They stake:")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text)
                        ForEach(Array(gameClient.duelTheirItems.enumerated()), id: \.offset) { _, item in
                            Text("Item #\(item.id) x\(item.amount)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.text)
                        }
                        if gameClient.duelTheirItems.isEmpty {
                            Text("(nothing)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.mutedText)
                        }
                        Spacer()
                    }
                    .padding(6 * uiScale)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(ClassicPalette.panelAlt)
                }
                .frame(height: 100 * uiScale)

                Text("Are you sure you want to duel?")
                    .font(.system(size: 11 * uiScale))
                    .foregroundColor(ClassicPalette.text)
                    .padding(.vertical, 4 * uiScale)

                HStack(spacing: 8 * uiScale) {
                    Button(action: {
                        Task { try? await gameClient.sendTradeAccept() }
                    }) {
                        Text("Fight!")
                            .font(.system(size: 12 * uiScale, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16 * uiScale)
                            .padding(.vertical, 6 * uiScale)
                            .background(Color.red)
                            .cornerRadius(4 * uiScale)
                    }
                    Button(action: {
                        Task { try? await gameClient.sendTradeDecline() }
                    }) {
                        Text("Cancel")
                            .font(.system(size: 12 * uiScale, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16 * uiScale)
                            .padding(.vertical, 6 * uiScale)
                            .background(ClassicPalette.mutedText)
                            .cornerRadius(4 * uiScale)
                    }
                }
                .padding(8 * uiScale)
                .background(Color(red: 0.15, green: 0.05, blue: 0.05))
            }
            .background(Color(red: 0.18, green: 0.08, blue: 0.08))
            .cornerRadius(8 * uiScale)
            .overlay(RoundedRectangle(cornerRadius: 8 * uiScale).stroke(Color.red.opacity(0.6), lineWidth: 1))
            .frame(width: 280 * uiScale)
            .shadow(radius: 8)
        }
    }
}
