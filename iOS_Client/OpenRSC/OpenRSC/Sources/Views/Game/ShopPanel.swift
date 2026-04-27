import SwiftUI

// Shop modal: shop stock (left) and your inventory (right).
//
// Server protocol (Java client mudclient.java:3780/3813/3732):
//  - Buy:   opcode 236 [SHORT itemID][SHORT amount]
//  - Sell:  opcode 221 [SHORT itemID][SHORT amount]
//  - Close: opcode 166 (already wired in RSCGameEngine.closeShop)
struct ShopPanel: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    /// Pending shop transaction shown via QuantityPicker.
    @State private var pending: PendingShopAction? = nil

    private struct PendingShopAction: Equatable {
        let isBuy: Bool
        let itemId: Int
        let stock: Int
        let unitPrice: Int
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

            if let p = pending {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { pending = nil }
                quantityDialog(p)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Shop")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "#c8a951"))
            Spacer()
            Button(action: { engine.closeShop() }) {
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
            // Shop stock
            VStack(spacing: 4) {
                Text("Stock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(Array(worldState.shopItems.enumerated()), id: \.offset) { _, item in
                            PanelItemTile(itemId: item.id, amount: item.stock,
                                          subtitle: "\(item.price)gp")
                                .onTapGesture {
                                    pending = PendingShopAction(isBuy: true, itemId: item.id,
                                                                stock: item.stock, unitPrice: item.price)
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)

            Divider().background(Color(hex: "#3a3a3a"))

            // Inventory column (sell)
            VStack(spacing: 4) {
                Text("Inventory")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(worldState.inventory) { item in
                            // Sell price = shop's bid for that item (if shop sells it).
                            let bid = worldState.shopItems.first(where: { $0.id == item.itemId })?.price
                            PanelItemTile(itemId: item.itemId, amount: item.amount,
                                          subtitle: bid.map { "\($0)gp" })
                                .onTapGesture {
                                    pending = PendingShopAction(isBuy: false, itemId: item.itemId,
                                                                stock: item.amount, unitPrice: bid ?? 0)
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
        HStack {
            Spacer()
            Button("Close") { engine.closeShop() }
                .buttonStyle(PanelActionButtonStyle(color: .red))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func quantityDialog(_ p: PendingShopAction) -> some View {
        VStack(spacing: 10) {
            Text(p.isBuy
                 ? "Buy \(ItemNames.name(for: p.itemId))"
                 : "Sell \(ItemNames.name(for: p.itemId))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#c8a951"))

            HStack(spacing: 6) {
                ForEach([1, 5, 10], id: \.self) { qty in
                    Button(action: {
                        commit(p: p, qty: qty)
                    }) {
                        VStack(spacing: 1) {
                            Text("\(qty)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text(priceText(p: p, qty: qty))
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#2a2a2a"))
                        .cornerRadius(6)
                    }
                }
            }

            Text(p.isBuy ? "Buying from shop @ \(p.unitPrice)gp ea"
                         : "Selling to shop @ \(p.unitPrice)gp ea")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#888888"))

            Button("Cancel") { pending = nil }
                .buttonStyle(PanelActionButtonStyle(color: .red))
        }
        .padding(14)
        .background(Color(hex: "#181818"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#3a3a3a"), lineWidth: 1))
    }

    private func priceText(p: PendingShopAction, qty: Int) -> String {
        let total = p.unitPrice * qty
        return p.isBuy ? "= \(total)gp" : "+ \(total)gp"
    }

    private func commit(p: PendingShopAction, qty: Int) {
        if p.isBuy { engine.shopBuy(itemId: p.itemId, amount: qty) }
        else        { engine.shopSell(itemId: p.itemId, amount: qty) }
        pending = nil
    }
}
