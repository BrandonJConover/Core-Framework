import SwiftUI

// Shared styling + helpers for the bank/shop/trade/duel modal panels.
// Kept internal-scope (default) so the four panel files in this directory
// can reuse them without duplicating the look-and-feel.

/// Standard accept/decline button style for modal panels.
struct PanelActionButtonStyle: ButtonStyle {
    let color: Color
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(disabled ? Color(hex: "#555555") : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background((disabled ? Color.gray : color).opacity(0.15))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke((disabled ? Color.gray : color).opacity(0.4), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// Quantity-picker action sheet shown from bank/shop/duel/trade item taps.
struct QuantityPicker: View {
    let title: String
    let max: Int
    let onPick: (Int) -> Void
    let onCancel: () -> Void

    @State private var customText: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#c8a951"))

            HStack(spacing: 6) {
                ForEach(presetButtons(), id: \.self) { n in
                    Button(action: { onPick(n) }) {
                        Text(n == Int.max ? "All" : "\(n)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#2a2a2a"))
                            .cornerRadius(6)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("X", text: $customText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#222222"))
                    .cornerRadius(6)
                    .frame(width: 80)
                Button("OK") {
                    if let n = Int(customText), n > 0 { onPick(n) }
                }
                .buttonStyle(PanelActionButtonStyle(color: .green))
                Button("Cancel") { onCancel() }
                    .buttonStyle(PanelActionButtonStyle(color: .red))
            }
        }
        .padding(14)
        .background(Color(hex: "#181818"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#3a3a3a"), lineWidth: 1))
    }

    private func presetButtons() -> [Int] {
        // Show 1, 5, 25 always; All only when max > 0.
        var presets: [Int] = [1, 5, 25]
        if max > 0 { presets.append(Int.max) }
        return presets
    }
}

/// Compact item tile used in inventory/bank/shop grids.
struct PanelItemTile: View {
    let itemId: Int
    let amount: Int
    let subtitle: String?
    let highlighted: Bool

    init(itemId: Int, amount: Int, subtitle: String? = nil, highlighted: Bool = false) {
        self.itemId = itemId
        self.amount = amount
        self.subtitle = subtitle
        self.highlighted = highlighted
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(ItemNames.name(for: itemId))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            if amount > 1 {
                Text("x\(amount.formatted)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.yellow)
            }
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color(hex: highlighted ? "#3d3520" : "#2a2a2a"))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(highlighted ? Color(hex: "#c8a951") : Color(hex: "#3a3a3a"),
                        lineWidth: highlighted ? 1.5 : 1)
        )
    }
}

private extension Int {
    /// Compact integer formatter — "1.2k" / "3.4m" for the tile labels.
    var formatted: String {
        if self >= 1_000_000 { return String(format: "%.1fm", Double(self) / 1_000_000) }
        if self >= 10_000 { return String(format: "%.0fk", Double(self) / 1_000) }
        return "\(self)"
    }
}
