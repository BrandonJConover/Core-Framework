import SwiftUI

// Bank modal: two-column inventory ↔ bank with quantity-picker actions.
// Replaces the lightweight BankOverlayView in HUDView.swift.
//
// Server protocol (Java client mudclient.java + CustomBankInterface.java):
//  - Deposit:  opcode 23 [SHORT itemID][INT amount]
//  - Withdraw: opcode 22 [SHORT itemID][INT amount]
//  - Close:    opcode 212  (already wired in RSCGameEngine.closeBank)
struct BankPanel: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    /// Pending action shown via the QuantityPicker overlay.
    @State private var pending: PendingAction? = nil

    private enum PendingAction: Equatable {
        case deposit(itemId: Int, max: Int)
        case withdraw(itemId: Int, max: Int)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color(hex: "#444444"))
                columns
                Divider().background(Color(hex: "#444444"))
                footer
            }
            .frame(maxWidth: 540, maxHeight: 520)
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#3a3a3a"), lineWidth: 1))
            .padding(20)

            // Quantity picker dialog
            if let action = pending {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { pending = nil }
                QuantityPicker(title: title(for: action), max: maxFor(action), onPick: { qty in
                    perform(action, qty: qty)
                    pending = nil
                }, onCancel: { pending = nil })
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Bank")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "#c8a951"))
            Spacer()
            Button(action: { engine.closeBank() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: "#888888"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 8) {
            // Inventory column
            VStack(spacing: 4) {
                Text("Inventory (\(worldState.inventory.count)/30)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(worldState.inventory) { item in
                            PanelItemTile(itemId: item.itemId, amount: item.amount)
                                .onTapGesture {
                                    pending = .deposit(itemId: item.itemId, max: item.amount)
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)

            Divider().background(Color(hex: "#3a3a3a"))

            // Bank column
            VStack(spacing: 4) {
                Text("Bank")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(Array(worldState.bankItems.enumerated()), id: \.offset) { _, item in
                            PanelItemTile(itemId: item.id, amount: item.amount)
                                .onTapGesture {
                                    pending = .withdraw(itemId: item.id, max: item.amount)
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(worldState.bankItems.count) / \(worldState.bankMaxItems == 0 ? 192 : worldState.bankMaxItems)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "#888888"))
            Spacer()
            Button("Close") { engine.closeBank() }
                .buttonStyle(PanelActionButtonStyle(color: .red))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Action helpers

    private func title(for action: PendingAction) -> String {
        switch action {
        case .deposit(let id, _):  return "Deposit \(ItemNames.name(for: id))"
        case .withdraw(let id, _): return "Withdraw \(ItemNames.name(for: id))"
        }
    }

    private func maxFor(_ action: PendingAction) -> Int {
        switch action {
        case .deposit(_, let max), .withdraw(_, let max): return max
        }
    }

    private func perform(_ action: PendingAction, qty: Int) {
        switch action {
        case .deposit(let id, let max):
            let amount = qty == Int.max ? max : qty
            engine.bankDeposit(itemId: id, amount: amount)
        case .withdraw(let id, let max):
            let amount = qty == Int.max ? max : qty
            engine.bankWithdraw(itemId: id, amount: amount)
        }
    }
}
