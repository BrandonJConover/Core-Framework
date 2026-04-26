import SwiftUI

enum HUDPanel {
    case chat, inventory, stats, combat, prayer, magic, friends, quests, map
}

// MARK: - Main HUD

struct HUDView: View {
    @Binding var activePanel: HUDPanel?
    @ObservedObject var worldState: RSCWorldState
    @ObservedObject var engine: RSCGameEngine

    var body: some View {
        VStack(spacing: 0) {
            // Quick stats bar (always visible)
            QuickStatsBar(worldState: worldState, engine: engine)

            // Active panel content
            if let panel = activePanel {
                panelContent(panel)
                    .frame(maxHeight: 280)
                    .background(Color(hex: "#1a1a1a").opacity(0.95))
                    .topRoundedCorners(12)
            }

            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    HUDButton(icon: "bubble.left", label: "Chat", panel: .chat, activePanel: $activePanel)
                    HUDButton(icon: "bag", label: "Inv", panel: .inventory, activePanel: $activePanel)
                    HUDButton(icon: "chart.bar", label: "Stats", panel: .stats, activePanel: $activePanel)
                    HUDButton(icon: "shield", label: "Combat", panel: .combat, activePanel: $activePanel)
                    HUDButton(icon: "sparkles", label: "Prayer", panel: .prayer, activePanel: $activePanel)
                    HUDButton(icon: "wand.and.stars", label: "Magic", panel: .magic, activePanel: $activePanel)
                    HUDButton(icon: "person.2", label: "Social", panel: .friends, activePanel: $activePanel)
                    HUDButton(icon: "scroll", label: "Quest", panel: .quests, activePanel: $activePanel)
                    HUDButton(icon: "map", label: "Map", panel: .map, activePanel: $activePanel)
                }
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
        case .prayer:
            PrayerPanelView(worldState: worldState, engine: engine)
        case .magic:
            MagicPanelView(worldState: worldState, engine: engine)
        case .friends:
            FriendsPanelView(worldState: worldState, engine: engine)
        case .quests:
            QuestPanelView(worldState: worldState)
        case .map:
            MapPanelView(worldState: worldState)
        }
    }
}

// MARK: - Quick Stats Bar

private struct QuickStatsBar: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

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

            // Fatigue
            if worldState.fatigue > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text("\(worldState.fatigue)%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
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

            // Logout button
            Button(action: { engine.logout() }) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#888888"))
            }
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

    @State private var showEquipment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: { showEquipment = false }) {
                    Text("Inventory")
                        .font(.system(size: 13, weight: showEquipment ? .regular : .semibold))
                        .foregroundColor(showEquipment ? Color(hex: "#888888") : .white)
                }
                Button(action: { showEquipment = true }) {
                    Text("Worn")
                        .font(.system(size: 13, weight: showEquipment ? .semibold : .regular))
                        .foregroundColor(showEquipment ? .white : Color(hex: "#888888"))
                }
                Spacer()
                Text("\(worldState.inventory.count)/30")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#888888"))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if showEquipment {
                EquipmentView(worldState: worldState, engine: engine)
            } else {
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
                    Text(ItemNames.name(for: item.itemId))
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
            } // end else (inventory vs equipment)
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
                Text(ItemNames.name(for: item.itemId))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
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

// MARK: - Prayer Panel

private struct PrayerPanelView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    private let prayers = [
        (0, "Thick Skin", 1), (1, "Burst of Strength", 4), (2, "Clarity of Thought", 7),
        (3, "Rock Skin", 10), (4, "Superhuman Strength", 13), (5, "Improved Reflexes", 16),
        (6, "Rapid Restore", 19), (7, "Rapid Heal", 22), (8, "Protect Items", 25),
        (9, "Steel Skin", 28), (10, "Ultimate Strength", 31), (11, "Incredible Reflexes", 34),
        (12, "Paralyze Monster", 37), (13, "Protect from Missiles", 40)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Prayers")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Points: \(worldState.prayerPoints)/\(worldState.maxPrayer)")
                    .font(.system(size: 11))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(prayers, id: \.0) { prayer in
                        let prayerLevel = worldState.skills.first(where: { $0.id == 5 })?.base ?? 1
                        let canUse = prayerLevel >= prayer.2
                        Button(action: { engine.enablePrayer(prayerId: prayer.0) }) {
                            HStack {
                                Text(prayer.1)
                                    .font(.system(size: 12))
                                    .foregroundColor(canUse ? .white : Color(hex: "#555555"))
                                Spacer()
                                Text("Lvl \(prayer.2)")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "#888888"))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#222222"))
                            .cornerRadius(4)
                        }
                        .disabled(!canUse)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Magic Panel

private struct MagicPanelView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    private let spells = [
        (0, "Wind Strike", 1), (1, "Confuse", 3), (2, "Water Strike", 5),
        (3, "Enchant Lvl-1", 7), (4, "Earth Strike", 9), (5, "Weaken", 11),
        (6, "Fire Strike", 13), (7, "Bones to Bananas", 15), (8, "Wind Bolt", 17),
        (9, "Curse", 19), (10, "Low Alchemy", 21), (11, "Water Bolt", 23),
        (12, "Varrock Teleport", 25), (13, "Enchant Lvl-2", 27), (14, "Earth Bolt", 29),
        (15, "Lumbridge Teleport", 31), (16, "Telekinetic Grab", 33), (17, "Fire Bolt", 35),
        (18, "Falador Teleport", 37), (19, "Crumble Undead", 39), (20, "Wind Blast", 41),
        (21, "Superheat Item", 43), (22, "Camelot Teleport", 45), (23, "Water Blast", 47),
        (24, "Enchant Lvl-3", 49), (25, "Ardougne Teleport", 51),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Magic")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                let magicLvl = worldState.skills.first(where: { $0.id == 6 })?.current ?? 1
                Text("Level: \(magicLvl)")
                    .font(.system(size: 11))
                    .foregroundColor(.purple)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                    ForEach(spells, id: \.0) { spell in
                        let magicLvl = worldState.skills.first(where: { $0.id == 6 })?.base ?? 1
                        let canCast = magicLvl >= spell.2
                        Button(action: { engine.castSpellOnSelf(spellId: spell.0) }) {
                            HStack {
                                Text(spell.1)
                                    .font(.system(size: 10))
                                    .foregroundColor(canCast ? .white : Color(hex: "#555555"))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(spell.2)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Color(hex: "#888888"))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#222222"))
                            .cornerRadius(4)
                        }
                        .disabled(!canCast)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Friends Panel

private struct FriendsPanelView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    @State private var newFriendName = ""
    @State private var showIgnore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: { showIgnore = false }) {
                    Text("Friends")
                        .font(.system(size: 13, weight: showIgnore ? .regular : .semibold))
                        .foregroundColor(showIgnore ? Color(hex: "#888888") : Color(hex: "#c8a951"))
                }
                Button(action: { showIgnore = true }) {
                    Text("Ignore")
                        .font(.system(size: 13, weight: showIgnore ? .semibold : .regular))
                        .foregroundColor(showIgnore ? Color(hex: "#c8a951") : Color(hex: "#888888"))
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if !showIgnore {
                // Add friend
                HStack(spacing: 4) {
                    TextField("Add friend...", text: $newFriendName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#2a2a2a"))
                        .cornerRadius(6)
                        .onSubmit {
                            guard !newFriendName.isEmpty else { return }
                            engine.addFriend(name: newFriendName)
                            newFriendName = ""
                        }
                    Button(action: {
                        guard !newFriendName.isEmpty else { return }
                        engine.addFriend(name: newFriendName)
                        newFriendName = ""
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(hex: "#c8a951"))
                    }
                }
                .padding(.horizontal, 8)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(worldState.friendsList.enumerated()), id: \.offset) { idx, friend in
                            HStack {
                                Circle()
                                    .fill(friend.online ? Color.green : Color(hex: "#555555"))
                                    .frame(width: 8, height: 8)
                                Text(friend.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(friend.online ? .white : Color(hex: "#888888"))
                                Spacer()
                                Button(action: { engine.removeFriend(name: friend.name) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(hex: "#555555"))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#222222"))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(worldState.ignoreList.enumerated()), id: \.offset) { idx, name in
                            HStack {
                                Text(name)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#888888"))
                                Spacer()
                                Button(action: { engine.removeIgnore(name: name) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(hex: "#555555"))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#222222"))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

// MARK: - Character Creation Overlay

struct AppearanceOverlayView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    @State private var gender = 0       // 0=male, 1=female
    @State private var headType = 0     // 0-4
    @State private var hairColour = 0   // 0-9
    @State private var topColour = 0    // 0-14
    @State private var bottomColour = 0 // 0-14
    @State private var skinColour = 0   // 0-4

    private let skinNames = ["Light", "Tan", "Dark", "Brown", "Black"]
    private let hairNames = ["Blond", "Orange", "Black", "Brown", "Grey", "Red", "White", "Green", "Blue", "Purple"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Create Your Character")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: "#c8a951"))

                // Gender
                HStack {
                    Text("Gender:").font(.system(size: 13)).foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $gender) {
                        Text("Male").tag(0)
                        Text("Female").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                // Head style
                stepper(label: "Head Style", value: $headType, range: 0...4)

                // Hair colour
                stepper(label: "Hair: \(hairColour < hairNames.count ? hairNames[hairColour] : "\(hairColour)")",
                        value: $hairColour, range: 0...9)

                // Skin colour
                stepper(label: "Skin: \(skinColour < skinNames.count ? skinNames[skinColour] : "\(skinColour)")",
                        value: $skinColour, range: 0...4)

                // Top colour
                stepper(label: "Top Colour", value: $topColour, range: 0...14)

                // Bottom colour
                stepper(label: "Bottom Colour", value: $bottomColour, range: 0...14)

                Spacer().frame(height: 8)

                Button(action: {
                    engine.sendAppearance(
                        headGender: gender, headType: headType,
                        bodyGender: gender, skinTone: skinColour,
                        hairColour: hairColour, topColour: topColour,
                        bottomColour: bottomColour, skinColour: skinColour
                    )
                }) {
                    Text("Accept")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "#1a1a1a"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#c8a951"))
                        .cornerRadius(10)
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(16)
        }
    }

    private func stepper(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(.white)
            Spacer()
            Button(action: { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } }) {
                Image(systemName: "chevron.left.circle.fill")
                    .foregroundColor(Color(hex: "#c8a951"))
            }
            Text("\(value.wrappedValue)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 30)
            Button(action: { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } }) {
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundColor(Color(hex: "#c8a951"))
            }
        }
    }
}

// MARK: - Duel Overlay

struct DuelOverlayView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    private let settingLabels = ["No Retreat", "No Magic", "No Prayer", "No Weapons"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Duel with \(worldState.duelOpponentName)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                    Spacer()
                    Button(action: { engine.duelDecline() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Settings
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        HStack(spacing: 4) {
                            Image(systemName: worldState.duelSettings[i] ? "checkmark.square" : "square")
                                .font(.system(size: 12))
                                .foregroundColor(worldState.duelSettings[i] ? .red : Color(hex: "#666666"))
                            Text(settingLabels[i])
                                .font(.system(size: 9))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                // Stakes
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Stake")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        ForEach(Array(worldState.duelMyStake.enumerated()), id: \.offset) { _, item in
                            Text("\(ItemNames.name(for: item.id)) x\(item.amount)")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                        if worldState.duelMyStake.isEmpty {
                            Text("Nothing")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#666666"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Their Stake")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        ForEach(Array(worldState.duelTheirStake.enumerated()), id: \.offset) { _, item in
                            Text("\(ItemNames.name(for: item.id)) x\(item.amount)")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                        if worldState.duelTheirStake.isEmpty {
                            Text("Nothing")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#666666"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                // Status and buttons
                HStack {
                    if worldState.duelOpponentAccepted {
                        Text("Opponent accepted").font(.system(size: 10)).foregroundColor(.green)
                    }
                    Spacer()
                    if worldState.duelConfirmOpen {
                        Button("Confirm") { engine.duelConfirmAccept() }
                            .buttonStyle(ActionButtonStyle(color: .red))
                    } else {
                        Button("Accept") { engine.duelAccept() }
                            .buttonStyle(ActionButtonStyle(color: .green))
                    }
                    Button("Decline") { engine.duelDecline() }
                        .buttonStyle(ActionButtonStyle(color: .red))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(16)
            .padding(20)
        }
    }
}

// MARK: - Sleep Overlay

struct SleepOverlayView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    @State private var sleepWord = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Color(hex: "#c8a951"))

                Text("You are sleeping")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Fatigue: \(worldState.sleepFatigue)%")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#888888"))

                if !worldState.sleepStatusText.isEmpty {
                    Text(worldState.sleepStatusText)
                        .font(.system(size: 13))
                        .foregroundColor(worldState.sleepStatusText.contains("Incorrect") ? .red : .yellow)
                }

                Text("Type the word shown on screen to wake up")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#666666"))

                HStack(spacing: 8) {
                    TextField("Sleep word...", text: $sleepWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#2a2a2a"))
                        .cornerRadius(8)
                        .onSubmit { submitSleepWord() }

                    Button("Wake") { submitSleepWord() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#1a1a1a"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#c8a951"))
                        .cornerRadius(8)
                }
                .frame(maxWidth: 300)
            }
        }
    }

    private func submitSleepWord() {
        guard !sleepWord.isEmpty else { return }
        engine.sendSleepWord(sleepWord)
        sleepWord = ""
    }
}

// MARK: - Equipment Panel (shown within Inventory)

private struct EquipmentView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    // Equipment slots map to inventory items with equipped=true
    private var equippedItems: [RSCInventoryItem] {
        worldState.inventory.filter { $0.equipped }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Equipment").font(.system(size: 11, weight: .semibold))
                .padding(.top, 4)

            if equippedItems.isEmpty {
                Text("Nothing equipped")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#666666"))
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(equippedItems) { item in
                        Button(action: { engine.unequipItem(slot: item.id) }) {
                            VStack(spacing: 1) {
                                Text(ItemNames.name(for: item.itemId))
                                    .font(.system(size: 8, weight: .medium))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.4), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 6)
            }

            // Equipment stats
            HStack(spacing: 8) {
                Label("\(worldState.equipmentStats.armourPoints)", systemImage: "shield")
                    .font(.system(size: 9))
                Label("\(worldState.equipmentStats.weaponAimPoints)", systemImage: "scope")
                    .font(.system(size: 9))
                Label("\(worldState.equipmentStats.weaponPowerPoints)", systemImage: "bolt")
                    .font(.system(size: 9))
            }
            .foregroundColor(Color(hex: "#888888"))
            .padding(.bottom, 4)
        }
        .background(Color(hex: "#1a1a1a"))
    }
}

// MARK: - Quest Panel

private struct QuestPanelView: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Quest Journal")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(worldState.quests.filter { $0.stage > 0 }.count)/\(worldState.quests.count) started")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#888888"))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if worldState.quests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "scroll")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "#444444"))
                    Text("No quests yet")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#666666"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(worldState.quests.enumerated()), id: \.offset) { _, quest in
                            HStack {
                                // Status indicator
                                Image(systemName: questIcon(stage: quest.stage))
                                    .font(.system(size: 10))
                                    .foregroundColor(questColor(stage: quest.stage))
                                    .frame(width: 14)

                                Text(quest.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(questColor(stage: quest.stage))
                                Spacer()
                                Text(questStatus(stage: quest.stage))
                                    .font(.system(size: 9))
                                    .foregroundColor(Color(hex: "#888888"))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#222222"))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func questIcon(stage: Int) -> String {
        if stage == 0 { return "circle" }
        if stage == -1 { return "checkmark.circle.fill" }
        return "circle.lefthalf.filled"
    }

    private func questColor(stage: Int) -> Color {
        if stage == 0 { return Color(hex: "#888888") }
        if stage == -1 { return .green }
        return Color(hex: "#c8a951")
    }

    private func questStatus(stage: Int) -> String {
        if stage == 0 { return "Not started" }
        if stage == -1 { return "Complete" }
        return "In progress"
    }
}

// MARK: - Context Menu Overlay

struct ContextMenuOverlay: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture {
                    worldState.contextMenuOpen = false
                    worldState.contextMenuActions = []
                }

            VStack(spacing: 0) {
                // Title
                Text(worldState.contextMenuTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#c8a951"))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)

                Divider().background(Color(hex: "#333333"))

                // Action buttons
                ForEach(Array(worldState.contextMenuActions.enumerated()), id: \.offset) { idx, action in
                    Button(action: {
                        let doAction = action.action
                        worldState.contextMenuOpen = false
                        worldState.contextMenuActions = []
                        // Execute action after menu dismisses
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { doAction() }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: action.icon)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#c8a951"))
                                .frame(width: 20)
                            Text(action.label)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#2a2a2a"))
                    }

                    if idx < worldState.contextMenuActions.count - 1 {
                        Divider().background(Color(hex: "#333333"))
                    }
                }
            }
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.5), radius: 10)
            .frame(maxWidth: 250)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Bank Overlay

struct BankOverlayView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { engine.closeBank() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Bank")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "#c8a951"))
                    Spacer()
                    Text("\(worldState.bankItems.count) items")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#888888"))
                    Button(action: { engine.closeBank() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "#666666"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Items grid
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                        ForEach(Array(worldState.bankItems.enumerated()), id: \.offset) { idx, item in
                            VStack(spacing: 2) {
                                Text(ItemNames.name(for: item.id))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                Text("x\(item.amount)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.yellow)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(hex: "#2a2a2a"))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "#3a3a3a"), lineWidth: 1))
                            .onTapGesture {
                                engine.bankWithdraw(itemId: item.id, amount: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(maxHeight: 400)
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(16)
            .padding(20)
        }
    }
}

// MARK: - Shop Overlay

struct ShopOverlayView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { engine.closeShop() }

            VStack(spacing: 0) {
                HStack {
                    Text("Shop")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "#c8a951"))
                    Spacer()
                    Button(action: { engine.closeShop() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "#666666"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(Array(worldState.shopItems.enumerated()), id: \.offset) { idx, item in
                            VStack(spacing: 2) {
                                Text(ItemNames.name(for: item.id))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                Text("\(item.stock) stk")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(hex: "#888888"))
                                Text("\(item.price)gp")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.yellow)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color(hex: "#2a2a2a"))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "#3a3a3a"), lineWidth: 1))
                            .onTapGesture {
                                engine.shopBuy(itemId: item.id, amount: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(maxHeight: 400)
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(16)
            .padding(20)
        }
    }
}

// MARK: - Trade Overlay

struct TradeOverlayView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Trading with \(worldState.tradePartnerName)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#c8a951"))
                    Spacer()
                    Button(action: { engine.tradeDecline() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Two columns
                HStack(alignment: .top, spacing: 8) {
                    // Your offer
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your offer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(worldState.tradeMyOffer.enumerated()), id: \.offset) { _, item in
                                    HStack {
                                        Text(ItemNames.name(for: item.id))
                                            .font(.system(size: 10))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("x\(item.amount)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.yellow)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "#2a2a2a"))
                                    .cornerRadius(3)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider().background(Color(hex: "#444444"))

                    // Their offer
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(worldState.tradePartnerName)'s offer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(worldState.tradeTheirOffer.enumerated()), id: \.offset) { _, item in
                                    HStack {
                                        Text(ItemNames.name(for: item.id))
                                            .font(.system(size: 10))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("x\(item.amount)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.yellow)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "#2a2a2a"))
                                    .cornerRadius(3)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: 200)

                // Status and buttons
                HStack {
                    if worldState.tradePartnerAccepted {
                        Text("Partner accepted")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Button("Accept") { engine.tradeAccept() }
                        .buttonStyle(ActionButtonStyle(color: .green))
                    Button("Decline") { engine.tradeDecline() }
                        .buttonStyle(ActionButtonStyle(color: .red))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(hex: "#1a1a1a").opacity(0.98))
            .cornerRadius(16)
            .padding(20)
        }
    }
}

// MARK: - Dialogue Overlay

struct DialogueOverlayView: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Text("Choose an option:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#c8a951"))
                    .padding(.top, 12)

                ForEach(Array(worldState.dialogueOptions.enumerated()), id: \.offset) { idx, option in
                    Button(action: {
                        engine.answerDialogue(idx)
                        worldState.dialogueOpen = false
                        worldState.dialogueOptions = []
                    }) {
                        Text(option)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(hex: "#2a2a2a"))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#c8a951").opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(Color(hex: "#1a1a1a").opacity(0.95))
            .topRoundedCorners(16)
        }
    }
}

// MARK: - Top rounded corner modifier

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
