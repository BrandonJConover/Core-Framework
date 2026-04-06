import SwiftUI

struct TradeView: View {
    @ObservedObject var gameClient: GameClient
    let uiScale: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                Text("Trading with \(gameClient.tradePartnerName.isEmpty ? "Player" : gameClient.tradePartnerName)")
                    .font(.system(size: 14 * uiScale, weight: .bold))
                    .foregroundColor(ClassicPalette.accent)
                    .padding(8 * uiScale)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.3, green: 0.2, blue: 0.0))

                // Two-column item lists
                HStack(alignment: .top, spacing: 1) {
                    // Your offer
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Offer")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text)
                        ForEach(Array(gameClient.tradeMyItems.enumerated()), id: \.offset) { _, item in
                            Text("Item #\(item.id) x\(item.amount)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.text)
                        }
                        if gameClient.tradeMyItems.isEmpty {
                            Text("(nothing)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.mutedText)
                        }
                        Spacer()
                    }
                    .padding(6 * uiScale)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(ClassicPalette.panel)

                    // Their offer
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Their Offer")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text)
                        ForEach(Array(gameClient.tradeTheirItems.enumerated()), id: \.offset) { _, item in
                            Text("Item #\(item.id) x\(item.amount)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.text)
                        }
                        if gameClient.tradeTheirItems.isEmpty {
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
                .frame(height: 160 * uiScale)

                // Status
                Text(gameClient.tradeTheyAccepted ? "Other player has accepted" : "Waiting for other player...")
                    .font(.system(size: 10 * uiScale))
                    .foregroundColor(gameClient.tradeTheyAccepted ? .green : ClassicPalette.mutedText)
                    .padding(.vertical, 4 * uiScale)

                // Action buttons
                HStack(spacing: 8 * uiScale) {
                    Button(action: {
                        Task { try? await gameClient.sendTradeAccept() }
                    }) {
                        Text(gameClient.tradeAccepted ? "Accepted ✓" : "Accept")
                            .font(.system(size: 12 * uiScale, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16 * uiScale)
                            .padding(.vertical, 6 * uiScale)
                            .background(gameClient.tradeAccepted ? Color.green.opacity(0.5) : Color.green)
                            .cornerRadius(4 * uiScale)
                    }
                    Button(action: {
                        Task { try? await gameClient.sendTradeDecline() }
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
                .background(ClassicPalette.shellInset)
            }
            .background(ClassicPalette.shell)
            .cornerRadius(8 * uiScale)
            .overlay(RoundedRectangle(cornerRadius: 8 * uiScale).stroke(ClassicPalette.panelBorder, lineWidth: 1))
            .frame(width: 280 * uiScale)
            .shadow(radius: 8)
        }
    }
}

struct TradeConfirmView: View {
    @ObservedObject var gameClient: GameClient
    let uiScale: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Confirm Trade")
                    .font(.system(size: 14 * uiScale, weight: .bold))
                    .foregroundColor(ClassicPalette.accent)
                    .padding(8 * uiScale)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.3, green: 0.2, blue: 0.0))

                HStack(alignment: .top, spacing: 1) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You give:")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text)
                        ForEach(Array(gameClient.tradeMyItems.enumerated()), id: \.offset) { _, item in
                            Text("Item #\(item.id) x\(item.amount)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.text)
                        }
                        if gameClient.tradeMyItems.isEmpty {
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
                        Text("You receive:")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text)
                        ForEach(Array(gameClient.tradeTheirItems.enumerated()), id: \.offset) { _, item in
                            Text("Item #\(item.id) x\(item.amount)")
                                .font(.system(size: 10 * uiScale))
                                .foregroundColor(ClassicPalette.text)
                        }
                        if gameClient.tradeTheirItems.isEmpty {
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

                Text("Are you sure?")
                    .font(.system(size: 11 * uiScale))
                    .foregroundColor(ClassicPalette.text)
                    .padding(.vertical, 4 * uiScale)

                HStack(spacing: 8 * uiScale) {
                    Button(action: {
                        Task { try? await gameClient.sendTradeAccept() }
                    }) {
                        Text("Confirm")
                            .font(.system(size: 12 * uiScale, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16 * uiScale)
                            .padding(.vertical, 6 * uiScale)
                            .background(Color.green)
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
                            .background(Color.red)
                            .cornerRadius(4 * uiScale)
                    }
                }
                .padding(8 * uiScale)
                .background(ClassicPalette.shellInset)
            }
            .background(ClassicPalette.shell)
            .cornerRadius(8 * uiScale)
            .overlay(RoundedRectangle(cornerRadius: 8 * uiScale).stroke(ClassicPalette.panelBorder, lineWidth: 1))
            .frame(width: 280 * uiScale)
            .shadow(radius: 8)
        }
    }
}
