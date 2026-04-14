import SwiftUI

enum HUDPanel {
    case chat, inventory, stats, map, combat
}

// MARK: - Main HUD

struct HUDView: View {
    @Binding var activePanel: HUDPanel?
    @ObservedObject var worldState: RSCWorldState
    @ObservedObject var engine: RSCGameEngine

    var body: some View {
        VStack(spacing: 0) {
            // Quick stats bar (always visible)
            QuickStatsBar(worldState: worldState)

            // Active panel content
            if let panel = activePanel {
                panelContent(panel)
                    .frame(maxHeight: 280)
                    .background(Color(hex: "#1a1a1a").opacity(0.95))
                    .topRoundedCorners(12)
            }

            // Tab bar
            HStack(spacing: 0) {
                HUDButton(icon: "bubble.left", label: "Chat", panel: .chat, activePanel: $activePanel)
                Spacer()
                HUDButton(icon: "bag", label: "Inv", panel: .inventory, activePanel: $activePanel)
                Spacer()
                HUDButton(icon: "chart.bar", label: "Stats", panel: .stats, activePanel: $activePanel)
                Spacer()
                HUDButton(icon: "shield", label: "Combat", panel: .combat, activePanel: $activePanel)
                Spacer()
                HUDButton(icon: "map", label: "Map", panel: .map, activePanel: $activePanel)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(Color(hex: "#1a1a1a").opacity(0.85))
        }
    }

    @ViewBuilder
    private func panelContent(_ panel: HUDPanel) -> some View {
        switch panel {
        case .chat:
            ChatPanelView(worldState: worldState, engine: engine)
        case .inventory:
            InventoryPanelView(worldState: worldState, engine: engine)
        case .stats:
            StatsPanelView(worldState: worldState)
        case .combat:
            CombatPanelView(worldState: worldState, engine: engine)
        case .map:
            MapPanelView(worldState: worldState)
        }
    }
}

// MARK: - Quick Stats Bar

private struct QuickStatsBar: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        HStack(spacing: 12) {
            // HP
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundColor(hpColor)
                    .font(.system(size: 12))
                Text("\(worldState.hitpoints)/\(worldState.maxHitpoints)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }

            // Prayer
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .foregroundColor(.cyan)
                    .font(.system(size: 12))
                Text("\(worldState.prayerPoints)/\(worldState.maxPrayer)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }

            Spacer()

            // Combat indicator
            if worldState.inCombat {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    Text("In Combat")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                }
            }

            // Position
            Text("(\(worldState.localPlayerX), \(worldState.localPlayerY))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: "#888888"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: "#111111").opacity(0.9))
    }

    private var hpColor: Color {
        let pct = worldState.maxHitpoints > 0
            ? Double(worldState.hitpoints) / Double(worldState.maxHitpoints)
            : 1.0
        if pct > 0.5 { return .green }
        if pct > 0.25 { return .yellow }
        return .red
    }
}

// MARK: - Chat Panel

private struct ChatPanelView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    @State private var chatInput = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(worldState.chatMessages) { msg in
                            HStack(alignment: .top, spacing: 4) {
                                Text(msg.sender + ":")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(chatColor(msg))
                                Text(msg.text)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: worldState.chatMessages.count) { _ in
                    if let last = worldState.chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Input bar
            HStack(spacing: 8) {
                TextField("Type a message...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#2a2a2a"))
                    .cornerRadius(8)
                    .onSubmit { sendChat() }

                Button(action: sendChat) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(chatInput.isEmpty ? Color(hex: "#555555") : Color(hex: "#c8a951"))
                }
                .disabled(chatInput.isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func sendChat() {
        guard !chatInput.isEmpty else { return }
        if chatInput.hasPrefix("::") {
            engine.sendServerCommand(String(chatInput.dropFirst(2)))
        } else {
            engine.sendChatMessage(chatInput)
        }
        chatInput = ""
    }

    private func chatColor(_ msg: RSCChatMessage) -> Color {
        if msg.isPrivate { return .cyan }
        if msg.isLocal { return Color(hex: "#c8a951") }
        if msg.sender.hasPrefix("[") { return .yellow }
        return .white
    }
}

// MARK: - Inventory Panel

private struct InventoryPanelView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    @State private var selectedSlot: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Inventory")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(worldState.inventory.count)/30")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#888888"))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                    ForEach(worldState.inventory) { item in
                        InventorySlotView(item: item, isSelected: selectedSlot == item.id) {
                            selectedSlot = selectedSlot == item.id ? nil : item.id
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            // Action bar for selected item
            if let slot = selectedSlot, let item = worldState.inventory.first(where: { $0.id == slot }) {
                HStack(spacing: 12) {
                    Text("Item \(item.itemId)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#c8a951"))
                    Spacer()
                    Button("Use") { engine.useItem(slot: slot); selectedSlot = nil }
                        .buttonStyle(ActionButtonStyle(color: .blue))
                    Button(item.equipped ? "Unequip" : "Equip") {
                        if item.equipped {
                            engine.unequipItem(slot: slot)
                        } else {
                            engine.equipItem(slot: slot)
                        }
                        selectedSlot = nil
                    }
                    .buttonStyle(ActionButtonStyle(color: .green))
                    Button("Drop") { engine.dropItem(slot: slot); selectedSlot = nil }
                        .buttonStyle(ActionButtonStyle(color: .red))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
    }
}

private struct InventorySlotView: View {
    let item: RSCInventoryItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(item.itemId)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                if item.amount > 1 {
                    Text("x\(item.amount)")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color(hex: "#c8a951").opacity(0.2) : Color(hex: "#2a2a2a"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? Color(hex: "#c8a951") : (item.equipped ? Color.green.opacity(0.5) : Color(hex: "#3a3a3a")),
                        lineWidth: 1
                    )
            )
        }
        .foregroundColor(.white)
    }
}

// MARK: - Stats Panel

private struct StatsPanelView: View {
    @ObservedObject var worldState: RSCWorldState

    private let skillNames = [
        "Attack", "Defense", "Strength", "Hits", "Ranged",
        "Prayer", "Magic", "Cooking", "Woodcut", "Fletching",
        "Fishing", "Firemaking", "Crafting", "Smithing", "Mining",
        "Herblaw", "Agility", "Thieving"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Skills")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Combat Lvl \(worldState.combatLevel)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#c8a951"))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                    ForEach(worldState.skills) { skill in
                        HStack {
                            Text(skill.id < skillNames.count ? skillNames[skill.id] : "Skill \(skill.id)")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#aaaaaa"))
                            Spacer()
                            Text("\(skill.current)/\(skill.base)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(skill.current < skill.base ? .red : (skill.current > skill.base ? .green : .white))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#222222"))
                        .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 8)
            }

            // Equipment stats
            if worldState.equipmentStats.armourPoints > 0 || worldState.equipmentStats.weaponAimPoints > 0 {
                HStack(spacing: 16) {
                    StatBadge(label: "Armour", value: worldState.equipmentStats.armourPoints)
                    StatBadge(label: "Aim", value: worldState.equipmentStats.weaponAimPoints)
                    StatBadge(label: "Power", value: worldState.equipmentStats.weaponPowerPoints)
                    StatBadge(label: "Magic", value: worldState.equipmentStats.magicPoints)
                    StatBadge(label: "Prayer", value: worldState.equipmentStats.prayerPoints)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
    }
}

private struct StatBadge: View {
    let label: String
    let value: Int
    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Color(hex: "#888888"))
        }
    }
}

// MARK: - Combat Panel

private struct CombatPanelView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    private let styles = [
        (0, "Controlled", "+1 All"),
        (1, "Aggressive", "+3 Str"),
        (2, "Accurate", "+3 Atk"),
        (3, "Defensive", "+3 Def"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            // HP bar
            VStack(spacing: 2) {
                HStack {
                    Text("Hitpoints")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#888888"))
                    Spacer()
                    Text("\(worldState.hitpoints)/\(worldState.maxHitpoints)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: "#2a2a2a"))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hpColor)
                            .frame(width: geo.size.width * hpPct)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            // Target info
            if let target = worldState.combatTarget {
                VStack(spacing: 2) {
                    HStack {
                        Image(systemName: "target")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                        Text("\(target.name) (Lvl \(target.combatLevel))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                        Spacer()
                        Text("\(target.currentHp)/\(target.maxHp)")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    let tPct = target.maxHp > 0 ? CGFloat(target.currentHp) / CGFloat(target.maxHp) : 0
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#2a2a2a"))
                            RoundedRectangle(cornerRadius: 3).fill(Color.red).frame(width: geo.size.width * tPct)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 8)
            }

            // Combat styles
            Text("Attack Style")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#888888"))
                .padding(.horizontal, 8)

            HStack(spacing: 6) {
                ForEach(styles, id: \.0) { style in
                    let isActive = worldState.combatStyle == style.0
                    Button(action: { engine.setCombatStyle(style.0) }) {
                        VStack(spacing: 2) {
                            Text(style.1)
                                .font(.system(size: 11, weight: .medium))
                            Text(style.2)
                                .font(.system(size: 9))
                                .foregroundColor(isActive ? Color(hex: "#c8a951") : Color(hex: "#666666"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isActive ? Color(hex: "#c8a951").opacity(0.15) : Color(hex: "#2a2a2a"))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isActive ? Color(hex: "#c8a951") : Color(hex: "#3a3a3a"), lineWidth: 1)
                        )
                    }
                    .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var hpPct: CGFloat {
        worldState.maxHitpoints > 0 ? CGFloat(worldState.hitpoints) / CGFloat(worldState.maxHitpoints) : 0
    }

    private var hpColor: Color {
        if hpPct > 0.5 { return .green }
        if hpPct > 0.25 { return .yellow }
        return .red
    }
}

// MARK: - Map Panel

private struct MapPanelView: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "map")
                .font(.system(size: 32))
                .foregroundColor(Color(hex: "#444444"))
            Text("World Map")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#666666"))
            Text("Coming soon")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#444444"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab button

private struct HUDButton: View {
    let icon: String
    let label: String
    let panel: HUDPanel
    @Binding var activePanel: HUDPanel?

    var isActive: Bool { activePanel == panel }

    var body: some View {
        Button(action: {
            activePanel = isActive ? nil : panel
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(isActive ? Color(hex: "#c8a951") : Color(hex: "#888888"))
            .frame(width: 52, height: 48)
        }
    }
}

// MARK: - Action Button Style

private struct ActionButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.3), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: - Top rounded corner modifier

extension View {
    func topRoundedCorners(_ radius: CGFloat) -> some View {
        clipShape(TopRoundedShape(radius: radius))
    }
}

private struct TopRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
