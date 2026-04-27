import SwiftUI

// Duel modal — mirror of TradePanel with rule toggles.
//
// Server protocol (Java client mudclient.java + Opcodes.java):
//  - Duel offer:      opcode 33 [BYTE count][per item: SHORT id, INT amt, SHORT noted]
//  - Settings change: opcode 8  [BYTE retreat][BYTE magic][BYTE prayer][BYTE weapons]
//  - Accept:          opcode 176 (first stage)
//  - Confirm:         opcode 77  (second stage)
//  - Decline:         opcode 197
struct DuelPanel: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    /// Order matches worldState.duelSettings: retreat, magic, prayer, weapons.
    private static let settingLabels = ["No retreat", "No magic", "No prayer", "No weapons"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color(hex: "#444444"))
                if worldState.duelConfirmOpen {
                    confirmPhase
                } else {
                    offerPhase
                }
                Divider().background(Color(hex: "#444444"))
                footer
            }
            .frame(maxWidth: 580, maxHeight: 580)
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#3a3a3a"), lineWidth: 1))
            .padding(20)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(worldState.duelConfirmOpen ? "Confirm Duel" : "Duel")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.red)
                Text("vs \(worldState.duelOpponentName.isEmpty ? "?" : worldState.duelOpponentName)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }
            Spacer()
            Button(action: { engine.duelDecline() }) {
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
            settingsRow

            // Stake lists
            HStack(alignment: .top, spacing: 8) {
                stakeColumn(title: "Your stake",
                            items: worldState.duelMyStake,
                            accepted: worldState.duelAccepted,
                            onTap: removeFromStake)
                Divider().background(Color(hex: "#3a3a3a"))
                stakeColumn(title: "\(worldState.duelOpponentName.isEmpty ? "Opponent" : worldState.duelOpponentName)'s stake",
                            items: worldState.duelTheirStake,
                            accepted: worldState.duelOpponentAccepted,
                            onTap: nil)
            }
            .frame(maxHeight: 150)
            .padding(.horizontal, 8)

            Divider().background(Color(hex: "#444444"))

            // Inventory (bottom) — tap to stake
            VStack(alignment: .leading, spacing: 4) {
                Text("Tap an item to stake it")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#888888"))
                    .padding(.horizontal, 10)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                        ForEach(worldState.inventory) { item in
                            PanelItemTile(itemId: item.itemId, amount: item.amount)
                                .onTapGesture { addToStake(item: item) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var settingsRow: some View {
        VStack(spacing: 4) {
            Text("Duel rules")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "#aaaaaa"))
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    let on = (i < worldState.duelSettings.count) ? worldState.duelSettings[i] : false
                    Button(action: { toggleSetting(i) }) {
                        HStack(spacing: 4) {
                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12))
                                .foregroundColor(on ? .red : Color(hex: "#666666"))
                            Text(Self.settingLabels[i])
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#222222"))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stakeColumn(title: String, items: [(id: Int, amount: Int)],
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
                        PanelItemTile(itemId: item.id, amount: item.amount)
                            .onTapGesture { onTap?(idx) }
                    }
                }
                if items.isEmpty {
                    Text("Nothing staked")
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
            Text("Final stake — review the rules and stakes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.yellow)
                .padding(.top, 6)

            // Active rules
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    let on = (i < worldState.duelSettings.count) ? worldState.duelSettings[i] : false
                    Text(Self.settingLabels[i])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(on ? .red : Color(hex: "#555555"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#222222"))
                        .cornerRadius(5)
                }
            }
            .padding(.horizontal, 8)

            HStack(alignment: .top, spacing: 12) {
                confirmStakeColumn(title: "You stake", items: worldState.duelMyStake)
                Divider().background(Color(hex: "#3a3a3a"))
                confirmStakeColumn(title: "Opponent stakes", items: worldState.duelTheirStake)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private func confirmStakeColumn(title: String, items: [(id: Int, amount: Int)]) -> some View {
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

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if !worldState.duelConfirmOpen && worldState.duelOpponentAccepted {
                Text("Opponent accepted")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            }
            Spacer()
            if worldState.duelConfirmOpen {
                Button("Confirm") { engine.duelConfirmAccept() }
                    .buttonStyle(PanelActionButtonStyle(color: .green))
            } else {
                Button(worldState.duelAccepted ? "Waiting..." : "Accept") {
                    if !worldState.duelAccepted { engine.duelAccept() }
                }
                .buttonStyle(PanelActionButtonStyle(color: .green, disabled: worldState.duelAccepted))
            }
            Button("Decline") { engine.duelDecline() }
                .buttonStyle(PanelActionButtonStyle(color: .red))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func toggleSetting(_ i: Int) {
        guard i >= 0 && i < 4 else { return }
        var s = worldState.duelSettings
        while s.count < 4 { s.append(false) }
        s[i].toggle()
        engine.duelSettingsChange(retreat: s[0], magic: s[1], prayer: s[2], weapons: s[3])
    }

    private func addToStake(item: RSCInventoryItem) {
        var stake = worldState.duelMyStake
        if let idx = stake.firstIndex(where: { $0.id == item.itemId }) {
            stake[idx].amount += 1
        } else {
            stake.append((id: item.itemId, amount: 1))
        }
        engine.duelOffer(stake)
    }

    private func removeFromStake(_ index: Int) {
        guard index >= 0 && index < worldState.duelMyStake.count else { return }
        var stake = worldState.duelMyStake
        if stake[index].amount > 1 {
            stake[index].amount -= 1
        } else {
            stake.remove(at: index)
        }
        engine.duelOffer(stake)
    }
}
