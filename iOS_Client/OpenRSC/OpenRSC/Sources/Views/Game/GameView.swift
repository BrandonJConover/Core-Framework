import SwiftUI

struct GameView: View {
    let server: ServerProfile
    let username: String
    let password: String
    @EnvironmentObject var appState: AppState
    @StateObject private var engine = RSCGameEngine()
    @State private var activePanel: HUDPanel? = nil
    @State private var hudVisible: Bool = true
    @State private var quickStatsVisible: Bool = true

    // Gesture state — accumulators that capture the camera/zoom snapshot at
    // gesture-start so .onChanged values are interpreted as deltas, not absolutes.
    @State private var dragStartLocation: CGPoint = .zero
    @State private var dragStartCameraRotation: CGFloat = 0
    @State private var dragStartCameraPitch: CGFloat = 0
    @State private var dragMovedFar: Bool = false
    @State private var pinchStartZoom: CGFloat = 1.6

    var body: some View {
        #if canImport(UIKit)
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                // Metal game canvas — full screen
                MetalViewRepresentable(engine: engine)
                    .ignoresSafeArea()
                    // Single-finger drag = pan-rotate camera. A drag that
                    // never moves more than ~10pt is treated as a tap when
                    // it ends. Threshold avoids tiny finger jitter being
                    // counted as a drag.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !dragMovedFar {
                                    let dist = hypot(value.translation.width, value.translation.height)
                                    if dist < 10 { return }   // still treating this as a tap-in-progress
                                    dragMovedFar = true
                                    dragStartCameraRotation = CGFloat(engine.cameraRotationDegrees)
                                    dragStartCameraPitch = CGFloat(engine.cameraPitchDegrees)
                                }
                                // Horizontal drag rotates the yaw, vertical drag
                                // adjusts pitch. Sensitivity scales 1 pt → ~0.6°.
                                let rotDelta = value.translation.width * 0.6
                                let pitchDelta = -value.translation.height * 0.4
                                engine.setCameraRotationDegrees(Double(dragStartCameraRotation + rotDelta))
                                engine.setCameraPitchDegrees(Double(dragStartCameraPitch + pitchDelta))
                            }
                            .onEnded { value in
                                if !dragMovedFar {
                                    // Treated as a tap.
                                    engine.touchTranslator.handleTap(at: value.location)
                                }
                                dragMovedFar = false
                            }
                    )
                    // Long-press = right-click context menu.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onEnded { value in
                                switch value {
                                case .second(true, let drag):
                                    engine.showContextMenu(at: drag?.location ?? .zero)
                                default: break
                                }
                            }
                    )
                    // Pinch = zoom. The gesture's `scale` is multiplicative
                    // since the gesture started, so we capture the start zoom
                    // once and apply scale relative to it.
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                if abs(scale - 1.0) < 0.01 {
                                    pinchStartZoom = engine.zoomLevel
                                }
                                let newZoom = pinchStartZoom * scale
                                engine.zoomLevel = max(0.5, min(3.0, newZoom))
                            }
                            .onEnded { _ in
                                pinchStartZoom = engine.zoomLevel
                            }
                    )

                // Orientation-adaptive HUD
                if isLandscape {
                    landscapeLayout(geo: geo)
                } else {
                    portraitLayout(geo: geo)
                }

                // Toggle HUD button (always visible, top-left)
                VStack {
                    HStack {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { hudVisible.toggle() } }) {
                            Image(systemName: hudVisible ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Color(hex: "#c8a951").opacity(0.8))
                                .shadow(color: .black, radius: 4)
                        }
                        .padding(.leading, 8)
                        .padding(.top, 4)

                        // Quick stats toggle
                        if !hudVisible {
                            Button(action: { withAnimation { quickStatsVisible.toggle() } }) {
                                Image(systemName: "heart.text.square")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(hex: "#c8a951").opacity(0.8))
                                    .shadow(color: .black, radius: 4)
                            }
                        }

                        Spacer()
                    }
                    Spacer()
                }

                // Floating quick stats when HUD is hidden
                if !hudVisible && quickStatsVisible {
                    VStack {
                        FloatingQuickStats(worldState: engine.worldState)
                            .padding(.top, 36)
                        Spacer()
                    }
                }

                // System update countdown — small floating banner above
                // the modal stack so it stays visible during banks/trades.
                VStack {
                    Spacer().frame(height: 18)
                    SystemUpdateBanner(worldState: engine.worldState)
                    Spacer()
                }

                // Modal overlays
                modalOverlays
            }
            .onAppear { engine.touchTranslator.setViewSize(geo.size) }
            .onChange(of: geo.size) { newSize in engine.touchTranslator.setViewSize(newSize) }
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        .onAppear {
            Task { await engine.start(server: server, username: username, password: password, appState: appState) }
        }
        .onDisappear { engine.stop() }
        #else
        ZStack {
            Color(hex: "#1a1a1a").ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Game Client").foregroundColor(Color(hex: "#c8a951")).font(.system(size: 20, weight: .semibold))
                Text("Run on iOS to play.").foregroundColor(Color(hex: "#666666"))
                Button("Back") { appState.currentView = .serverBrowser(server.gameType) }
                    .foregroundColor(Color(hex: "#c8a951"))
            }
        }
        .navigationBarBackButtonHidden(true)
        #endif
    }

    // MARK: - Portrait Layout (bottom panel)

    @ViewBuilder
    private func portraitLayout(geo: GeometryProxy) -> some View {
        if hudVisible {
            VStack(spacing: 0) {
                Spacer()
                HUDView(
                    activePanel: $activePanel,
                    worldState: engine.worldState,
                    engine: engine
                )
                .frame(maxHeight: geo.size.height * 0.45) // Max 45% of screen
                .transition(.move(edge: .bottom))
            }
        }
    }

    // MARK: - Landscape Layout (side panel)

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        if hudVisible {
            HStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    // Compact quick stats
                    CompactQuickStats(worldState: engine.worldState)

                    // Panel content
                    if let panel = activePanel {
                        panelContentLandscape(panel)
                            .frame(maxHeight: .infinity)
                    }

                    // Tab bar (vertical in landscape)
                    LandscapeTabBar(activePanel: $activePanel)
                }
                .frame(width: min(280, geo.size.width * 0.35))
                .background(Color(hex: "#1a1a1a").opacity(0.95))
                .transition(.move(edge: .trailing))
            }
        }
    }

    @ViewBuilder
    private func panelContentLandscape(_ panel: HUDPanel) -> some View {
        switch panel {
        case .chat:     ChatPanelCompact(worldState: engine.worldState, engine: engine)
        case .inventory: InventoryPanelCompact(worldState: engine.worldState, engine: engine)
        case .stats:    StatsPanelView_Internal(worldState: engine.worldState)
        case .combat:   CombatPanelView_Internal(worldState: engine.worldState, engine: engine)
        case .prayer:   PrayerPanelView_Internal(worldState: engine.worldState, engine: engine)
        case .magic:    MagicPanelView_Internal(worldState: engine.worldState, engine: engine)
        case .friends:  FriendsPanelView_Internal(worldState: engine.worldState, engine: engine)
        case .quests:   QuestPanelView_Internal(worldState: engine.worldState)
        case .map:      MapPanelView_Internal(worldState: engine.worldState)
        case .minimap:  MinimapPanel(worldState: engine.worldState, engine: engine)
        case .settings: SettingsPanel(worldState: engine.worldState, engine: engine)
        }
    }

    // MARK: - Modal overlays

    @ViewBuilder
    private var modalOverlays: some View {
        if engine.worldState.bankOpen {
            BankPanel(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.shopOpen {
            ShopPanel(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.dialogueOpen {
            DialogueOverlayView(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.tradeOpen || engine.worldState.tradeConfirmOpen {
            TradePanel(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.duelOpen || engine.worldState.duelConfirmOpen {
            DuelPanel(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.contextMenuOpen {
            ContextMenuOverlay(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.showAppearanceChange {
            AppearancePanel(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.welcomeShown {
            WelcomePanel(worldState: engine.worldState)
        }
        if engine.worldState.isSleeping {
            SleepPanel(worldState: engine.worldState, engine: engine)
        }
        // XP drop notifications (top-right, floating up)
        if !engine.worldState.xpDrops.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(engine.worldState.xpDrops) { drop in
                    Text("+\(drop.amount) \(drop.skill) XP")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.green)
                        .shadow(color: .black, radius: 2)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
            .padding(.top, 40)
            .allowsHitTesting(false)
        }
        if engine.worldState.isSleeping {
            SleepOverlayView(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.isDead {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("You have died").font(.system(size: 24, weight: .bold)).foregroundColor(.red)
                Text("You will respawn shortly").font(.system(size: 14)).foregroundColor(Color(hex: "#888888"))
            }
        }
    }
}

// MARK: - Floating Quick Stats (shown when HUD is hidden)

private struct FloatingQuickStats: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill").foregroundColor(hpColor).font(.system(size: 10))
                Text("\(worldState.hitpoints)/\(worldState.maxHitpoints)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            HStack(spacing: 3) {
                Image(systemName: "sparkles").foregroundColor(.cyan).font(.system(size: 10))
                Text("\(worldState.prayerPoints)/\(worldState.maxPrayer)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            if worldState.fatigue > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "moon.zzz").foregroundColor(.orange).font(.system(size: 10))
                    Text("\(worldState.fatigue)%").font(.system(size: 10, design: .monospaced))
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }

    private var hpColor: Color {
        let pct = worldState.maxHitpoints > 0 ? Double(worldState.hitpoints) / Double(worldState.maxHitpoints) : 1.0
        return pct > 0.5 ? .green : (pct > 0.25 ? .yellow : .red)
    }
}

// MARK: - Compact Quick Stats (landscape sidebar top)

private struct CompactQuickStats: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        HStack(spacing: 8) {
            Label("\(worldState.hitpoints)/\(worldState.maxHitpoints)", systemImage: "heart.fill")
                .foregroundColor(.green)
            Label("\(worldState.prayerPoints)/\(worldState.maxPrayer)", systemImage: "sparkles")
                .foregroundColor(.cyan)
            if worldState.inCombat {
                Image(systemName: "bolt.fill").foregroundColor(.red)
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#111111"))
    }
}

// MARK: - Landscape Tab Bar (vertical icons)

private struct LandscapeTabBar: View {
    @Binding var activePanel: HUDPanel?

    private let tabs: [(HUDPanel, String, String)] = [
        (.chat, "bubble.left", "Chat"),
        (.inventory, "bag", "Inv"),
        (.stats, "chart.bar", "Stats"),
        (.combat, "shield", "Cmbt"),
        (.prayer, "sparkles", "Pray"),
        (.magic, "wand.and.stars", "Mage"),
        (.friends, "person.2", "Soc"),
        (.quests, "scroll", "Quest"),
        (.map, "map", "Map"),
        (.minimap, "location.viewfinder", "Mini"),
        (.settings, "gearshape", "Opts"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab in
                let isActive = activePanel == tab.0
                Button(action: { activePanel = isActive ? nil : tab.0 }) {
                    VStack(spacing: 1) {
                        Image(systemName: tab.1)
                            .font(.system(size: 16))
                        Text(tab.2)
                            .font(.system(size: 8))
                    }
                    .foregroundColor(isActive ? Color(hex: "#c8a951") : Color(hex: "#666666"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color(hex: "#111111"))
    }
}

// MARK: - Compact panel variants for landscape sidebar

// Re-export the existing panel views with internal names for landscape use
// These reference the private structs in HUDView.swift through the public HUDView

private struct ChatPanelCompact: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    @State private var chatInput = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(worldState.chatMessages.suffix(50)) { msg in
                        HStack(alignment: .top, spacing: 3) {
                            Text(msg.sender + ":")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(msg.isPrivate ? .cyan : (msg.sender.hasPrefix("[") ? .yellow : Color(hex: "#c8a951")))
                            Text(msg.text)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }

            HStack(spacing: 4) {
                TextField("Chat...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#2a2a2a"))
                    .cornerRadius(6)
                    .onSubmit {
                        guard !chatInput.isEmpty else { return }
                        if chatInput.hasPrefix("::") { engine.sendServerCommand(String(chatInput.dropFirst(2))) }
                        else { engine.sendChatMessage(chatInput) }
                        chatInput = ""
                    }
                Button(action: {
                    guard !chatInput.isEmpty else { return }
                    if chatInput.hasPrefix("::") { engine.sendServerCommand(String(chatInput.dropFirst(2))) }
                    else { engine.sendChatMessage(chatInput) }
                    chatInput = ""
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(chatInput.isEmpty ? Color(hex: "#444444") : Color(hex: "#c8a951"))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }
}

private struct InventoryPanelCompact: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    @State private var selectedSlot: Int? = nil

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Inventory").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(worldState.inventory.count)/30").font(.system(size: 9)).foregroundColor(Color(hex: "#888888"))
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
                    ForEach(worldState.inventory) { item in
                        Button(action: { selectedSlot = selectedSlot == item.id ? nil : item.id }) {
                            VStack(spacing: 1) {
                                Text(ItemNames.name(for: item.itemId))
                                    .font(.system(size: 8, weight: .medium))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                if item.amount > 1 {
                                    Text("x\(item.amount)").font(.system(size: 7)).foregroundColor(.yellow)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(selectedSlot == item.id ? Color(hex: "#c8a951").opacity(0.2) : Color(hex: "#2a2a2a"))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(
                                selectedSlot == item.id ? Color(hex: "#c8a951") : (item.equipped ? .green.opacity(0.5) : Color(hex: "#333333")),
                                lineWidth: 1))
                        }
                        .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 4)
            }

            if let slot = selectedSlot, let item = worldState.inventory.first(where: { $0.id == slot }) {
                HStack(spacing: 6) {
                    Text(ItemNames.name(for: item.itemId)).font(.system(size: 9, weight: .medium)).foregroundColor(Color(hex: "#c8a951")).lineLimit(1)
                    Spacer()
                    Button("Use") { engine.useItem(slot: slot); selectedSlot = nil }
                        .font(.system(size: 9)).foregroundColor(.blue)
                    Button(item.equipped ? "Unequip" : "Equip") {
                        item.equipped ? engine.unequipItem(slot: slot) : engine.equipItem(slot: slot); selectedSlot = nil
                    }.font(.system(size: 9)).foregroundColor(.green)
                    Button("Drop") { engine.dropItem(slot: slot); selectedSlot = nil }
                        .font(.system(size: 9)).foregroundColor(.red)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
        }
    }
}

// Wrapper views that forward to the private HUDView panels
// These are needed because HUDView's panels are private structs

private struct StatsPanelView_Internal: View {
    @ObservedObject var worldState: RSCWorldState
    private let skillNames = ["Atk","Def","Str","HP","Rng","Pray","Mag","Cook","WC","Fletch","Fish","FM","Craft","Smith","Mine","Herb","Agil","Thief"]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                ForEach(worldState.skills) { skill in
                    HStack {
                        Text(skill.id < skillNames.count ? skillNames[skill.id] : "?\(skill.id)")
                            .font(.system(size: 9)).foregroundColor(Color(hex: "#aaa"))
                        Spacer()
                        Text("\(skill.current)/\(skill.base)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(skill.current < skill.base ? .red : .white)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color(hex: "#222222")).cornerRadius(3)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct CombatPanelView_Internal: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    private let styles = [(0,"Ctrl"),(1,"Aggr"),(2,"Acc"),(3,"Def")]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(styles, id: \.0) { s in
                    Button(action: { engine.setCombatStyle(s.0) }) {
                        Text(s.1).font(.system(size: 10, weight: worldState.combatStyle == s.0 ? .bold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(worldState.combatStyle == s.0 ? Color(hex: "#c8a951").opacity(0.2) : Color(hex: "#222"))
                            .cornerRadius(4)
                    }.foregroundColor(worldState.combatStyle == s.0 ? Color(hex: "#c8a951") : .white)
                }
            }.padding(.horizontal, 4).padding(.top, 4)
            Spacer()
        }
    }
}

private struct PrayerPanelView_Internal: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    private let prayers = [(0,"Thick Skin",1),(1,"Burst of Str",4),(2,"Clarity",7),(3,"Rock Skin",10),(4,"Superh Str",13),(5,"Impr Reflex",16),(6,"Rapid Rest",19),(7,"Rapid Heal",22),(8,"Protect Item",25),(9,"Steel Skin",28),(10,"Ultim Str",31),(11,"Incr Reflex",34),(12,"Paralyze Mon",37),(13,"Prot Missile",40)]

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(prayers, id: \.0) { p in
                    let isActive = worldState.activePrayers.indices.contains(p.0) && worldState.activePrayers[p.0]
                    Button(action: { engine.togglePrayer(prayerId: p.0) }) {
                        HStack {
                            Text(p.1)
                                .font(.system(size: 9, weight: isActive ? .bold : .regular))
                                .foregroundColor(isActive ? Color(hex: "#c8a951") : .white)
                            Spacer()
                            Text("L\(p.2)").font(.system(size: 8)).foregroundColor(Color(hex: "#666"))
                        }
                        .padding(.horizontal, 4).padding(.vertical, 3)
                        .background(isActive ? Color(hex: "#c8a951").opacity(0.15) : Color(hex: "#222"))
                        .cornerRadius(3)
                    }
                }
            }.padding(.horizontal, 4)
        }
    }
}

private struct MagicPanelView_Internal: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    private let spells = [(0,"Wind Strike",1),(1,"Confuse",3),(2,"Water Strike",5),(3,"Earth Strike",9),(4,"Fire Strike",13),(5,"Wind Bolt",17),(6,"Water Bolt",23),(7,"Earth Bolt",29),(8,"Fire Bolt",35)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                ForEach(spells, id: \.0) { s in
                    Button(action: { engine.castSpellOnSelf(spellId: s.0) }) {
                        HStack {
                            Text(s.1).font(.system(size: 8)).foregroundColor(.white).lineLimit(1)
                            Spacer()
                            Text("\(s.2)").font(.system(size: 7)).foregroundColor(Color(hex: "#666"))
                        }.padding(.horizontal, 3).padding(.vertical, 2).background(Color(hex: "#222")).cornerRadius(3)
                    }
                }
            }.padding(.horizontal, 4)
        }
    }
}

private struct FriendsPanelView_Internal: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(Array(worldState.friendsList.enumerated()), id: \.offset) { _, f in
                    HStack {
                        Circle().fill(f.online ? .green : Color(hex: "#444")).frame(width: 6, height: 6)
                        Text(f.name).font(.system(size: 9)).foregroundColor(f.online ? .white : Color(hex: "#666"))
                        Spacer()
                    }.padding(.horizontal, 4).padding(.vertical, 2).background(Color(hex: "#222")).cornerRadius(3)
                }
            }.padding(.horizontal, 4)
        }
    }
}

private struct QuestPanelView_Internal: View {
    @ObservedObject var worldState: RSCWorldState
    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(Array(worldState.quests.enumerated()), id: \.offset) { _, quest in
                    HStack {
                        Image(systemName: quest.stage == -1 ? "checkmark.circle.fill" : (quest.stage > 0 ? "circle.lefthalf.filled" : "circle"))
                            .font(.system(size: 8))
                            .foregroundColor(quest.stage == -1 ? .green : (quest.stage > 0 ? Color(hex: "#c8a951") : Color(hex: "#666")))
                        Text(quest.name)
                            .font(.system(size: 9))
                            .foregroundColor(quest.stage == -1 ? .green : .white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color(hex: "#222")).cornerRadius(3)
                }
            }.padding(.horizontal, 4)
        }
    }
}

private struct MapPanelView_Internal: View {
    @ObservedObject var worldState: RSCWorldState
    var body: some View {
        VStack {
            Image(systemName: "map").font(.system(size: 24)).foregroundColor(Color(hex: "#444"))
            Text("(\(worldState.localPlayerX), \(worldState.localPlayerY))").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "#666"))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
