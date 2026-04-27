import SwiftUI

// Trade modal — two phases driven by RSCWorldState:
//  - Offer phase   (worldState.tradeOpen): build offer lists, accept first stage.
//  - Confirm phase (worldState.tradeConfirmOpen): final review + confirm.
//
// Server protocol (Java client mudclient.java + Opcodes.java):
//  - Trade offer:     opcode 46 — full list resend on each modification.
//                     Format: BYTE count, then per item: SHORT id, INT amt, SHORT noted.
//  - Trade accept:    opcode 55  (first-stage)
//  - Trade confirm:   opcode 104 (second-stage)
//  - Trade decline:   opcode 230 (works both phases)
struct TradePanel: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color(hex: "#444444"))
                if worldState.tradeConfirmOpen {
                    confirmPhase
                } else {
                    offerPhase
                }
                Divider().background(Color(hex: "#444444"))
                footer
            }
            .frame(maxWidth: 560, maxHeight: 540)
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#3a3a3a"), lineWidth: 1))
            .padding(20)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(worldState.tradeConfirmOpen ? "Confirm Trade" : "Trading")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "#c8a951"))
                Text("with \(worldState.tradePartnerName.isEmpty ? "?" : worldState.tradePartnerName)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }
            Spacer()
            Button(action: { engine.tradeDecline() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Offer phase

    private var offerPhase: some View {
        VStack(spacing: 6) {
            // Offers (top)
            HStack(alignment: .top, spacing: 8) {
                offerColumn(title: "Your offer",
                            items: worldState.tradeMyOffer,
                            accepted: worldState.tradeAccepted,
                            onTap: removeFromMyOffer)
                Divider().background(Color(hex: "#3a3a3a"))
                offerColumn(title: "\(worldState.tradePartnerName.isEmpty ? "Partner" : worldState.tradePartnerName)'s offer",
                            items: worldState.tradeTheirOffer,
                            accepted: worldState.tradePartnerAccepted,
                            onTap: nil)
            }
            .frame(maxHeight: 170)
            .padding(.horizontal, 8)

            Divider().background(Color(hex: "#444444"))

            // Inventory (bottom) — tap to add
            VStack(alignment: .leading, spacing: 4) {
                Text("Tap an item to add it to your offer")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#888888"))
                    .padding(.horizontal, 10)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                        ForEach(worldState.inventory) { item in
                            PanelItemTile(itemId: item.itemId, amount: item.amount)
                                .onTapGesture { addToMyOffer(item: item) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func offerColumn(title: String, items: [(id: Int, amount: Int)],
                             accepted: Bool, onTap: ((Int) -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                if accepted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        PanelItemTile(itemId: item.id, amount: item.amount,
                                      highlighted: false)
                            .onTapGesture { onTap?(idx) }
                    }
                }
                if items.isEmpty {
                    Text("Nothing offered")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#666666"))
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Confirm phase

    private var confirmPhase: some View {
        VStack(spacing: 8) {
            Text("Final offer — please review carefully")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.yellow)
                .padding(.top, 6)

            HStack(alignment: .top, spacing: 12) {
                confirmColumn(title: "You give", items: worldState.tradeMyOffer)
                Divider().background(Color(hex: "#3a3a3a"))
                confirmColumn(title: "You receive", items: worldState.tradeTheirOffer)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private func confirmColumn(title: String, items: [(id: Int, amount: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#c8a951"))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(ItemNames.name(for: item.id))
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text("x\(item.amount)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#222222"))
                        .cornerRadius(4)
                    }
                    if items.isEmpty {
                        Text("Nothing")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#666666"))
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer (Accept / Decline)

    private var footer: some View {
        HStack(spacing: 10) {
            if !worldState.tradeConfirmOpen && worldState.tradePartnerAccepted {
                Text("Partner accepted")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            }
            Spacer()
            if worldState.tradeConfirmOpen {
                Button("Confirm") { engine.tradeConfirmAccept() }
                    .buttonStyle(PanelActionButtonStyle(color: .green))
            } else {
                Button(worldState.tradeAccepted ? "Waiting..." : "Accept") {
                    if !worldState.tradeAccepted { engine.tradeAccept() }
                }
                .buttonStyle(PanelActionButtonStyle(color: .green, disabled: worldState.tradeAccepted))
            }
            Button("Decline") { engine.tradeDecline() }
                .buttonStyle(PanelActionButtonStyle(color: .red))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    /// Tapping an inventory item adds 1 of it to the offer (or merges with an
    /// existing entry). Then resends the full offer list (opcode 46).
    private func addToMyOffer(item: RSCInventoryItem) {
        var offer = worldState.tradeMyOffer
        if let idx = offer.firstIndex(where: { $0.id == item.itemId }) {
            offer[idx].amount += 1
        } else {
            offer.append((id: item.itemId, amount: 1))
        }
        engine.tradeOffer(offer)
    }

    /// Tapping an offer entry removes one of it (or the whole stack).
    private func removeFromMyOffer(_ index: Int) {
        guard index >= 0 && index < worldState.tradeMyOffer.count else { return }
        var offer = worldState.tradeMyOffer
        if offer[index].amount > 1 {
            offer[index].amount -= 1
        } else {
            offer.remove(at: index)
        }
        engine.tradeOffer(offer)
    }
}
