import SwiftUI
import MetalKit

/// Main game view that renders the game world.
/// Equivalent to Android's RSCBitmapSurfaceView.
struct GameView: View {
    @EnvironmentObject private var gameState: GameState
    @ObservedObject var gameClient: GameClient
    @StateObject private var inputHandler = InputHandler()

    @State private var showingInventory = false
    @State private var showingSkills = false
    @State private var showingChat = false
    @State private var showingSettings = false

    private var isAnyPanelOpen: Bool {
        showingInventory || showingSkills || showingSettings
    }

    var body: some View {
        GeometryReader { geometry in
            let viewportRect = GameViewport.fittedRect(in: geometry.size)

            ZStack {
                // Game renderer — edge-to-edge under notch/home indicator
                GameRendererView(gameClient: gameClient)
                    .ignoresSafeArea()

                if !isAnyPanelOpen {
                    Color.clear
                        .frame(width: viewportRect.width, height: viewportRect.height)
                        .position(x: viewportRect.midX, y: viewportRect.midY)
                        .contentShape(Rectangle())
                        .gameGestures(inputHandler, viewSize: viewportRect.size)
                }

                // UI overlay — respects safe area
                ZStack {
                    if isAnyPanelOpen {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                closePanels()
                            }
                    }

                    VStack {
                        // Top bar
                        TopBar(gameClient: gameClient)

                        Spacer()

                        // Bottom UI
                        HStack(alignment: .bottom, spacing: 0) {
                            // Chat area
                            ChatView(messages: gameClient.chatMessages)
                                .frame(maxWidth: .infinity, maxHeight: 130)

                            // Tab buttons
                            TabButtonsView(
                                showingInventory: $showingInventory,
                                showingSkills: $showingSkills,
                                showingSettings: $showingSettings
                            )
                        }
                    }
                    .padding(.horizontal, 8)

                    // Side panels
                    if showingInventory {
                        InventoryView(items: gameClient.inventory) {
                            closePanels()
                        }
                            .frame(width: 200)
                            .transition(.move(edge: .trailing))
                            .position(x: geometry.size.width - 100, y: geometry.size.height / 2)
                    }

                    if showingSkills {
                        SkillsView(skills: gameClient.skills) {
                            closePanels()
                        }
                            .frame(width: 200)
                            .transition(.move(edge: .trailing))
                            .position(x: geometry.size.width - 100, y: geometry.size.height / 2)
                    }

                    if showingSettings {
                        SettingsPanel {
                            closePanels()
                        }
                            .frame(width: 240)
                            .transition(.move(edge: .trailing))
                            .position(x: geometry.size.width - 120, y: geometry.size.height / 2)
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear {
                inputHandler.gameClient = gameClient
            }
        }
    }

    private func closePanels() {
        showingInventory = false
        showingSkills = false
        showingSettings = false
    }
}

/// Monitors real device battery level and state.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Float?
    @Published private(set) var state: UIDevice.BatteryState = .unknown
    private var observers: [NSObjectProtocol] = []

    var normalizedLevel: CGFloat {
        if state == .full { return 1.0 }
        return CGFloat(level ?? 0.5)
    }

    var percentageText: String {
        if state == .full { return "100%" }
        guard let level else { return "--%" }
        return "\(Int((level * 100).rounded()))%"
    }

    var color: Color {
        if state == .charging || state == .full { return .green }
        guard let level else { return .gray }
        if level < 0.15 { return .red }
        if level < 0.25 { return .yellow }
        return .white
    }

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()

        observers.append(NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refresh() {
        let batteryLevel = UIDevice.current.batteryLevel
        level = batteryLevel >= 0 ? min(max(batteryLevel, 0), 1) : nil
        state = UIDevice.current.batteryState
    }
}

private struct BatteryStatusView: View {
    @ObservedObject var battery: BatteryMonitor

    private let bodyWidth: CGFloat = 22
    private let bodyHeight: CGFloat = 10

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(battery.color.opacity(0.95), lineWidth: 1)
                    .frame(width: bodyWidth, height: bodyHeight)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(battery.color.opacity(0.95))
                    .frame(
                        width: max(2, (bodyWidth - 3) * battery.normalizedLevel),
                        height: bodyHeight - 3
                    )
                    .padding(.leading, 1.5)

                if battery.state == .charging || battery.state == .full {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(width: bodyWidth, height: bodyHeight)
                }
            }
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(battery.color.opacity(0.95))
                    .frame(width: 2, height: 5)
                    .offset(x: 4)
            }

            Text(battery.percentageText)
                .font(.caption2.monospacedDigit())
                .foregroundColor(battery.color)
        }
        .animation(.easeOut(duration: 0.2), value: battery.normalizedLevel)
        .animation(.easeOut(duration: 0.2), value: battery.state)
    }
}

/// Top bar with player info and status.
struct TopBar: View {
    @EnvironmentObject private var gameState: GameState
    @ObservedObject var gameClient: GameClient
    @StateObject private var battery = BatteryMonitor()

    var body: some View {
        HStack {
            // Compass
            Image(systemName: "safari")
                .foregroundColor(.white)
                .rotationEffect(.degrees(Double(gameClient.cameraRotation) * 1.4))

            Spacer()

            // Player info
            if let player = gameClient.localPlayer {
                Text(player.username)
                    .font(.caption)
                    .foregroundColor(.white)

                Text("Combat: \(player.combatLevel)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Battery/connectivity indicators
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .foregroundColor(gameState.isConnected ? .green : .red)
                BatteryStatusView(battery: battery)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
    }
}

/// Chat display area.
struct ChatView: View {
    let messages: [ChatMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(messages.suffix(20)) { message in
                        HStack(spacing: 4) {
                            if let sender = message.sender {
                                Text("\(sender):")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.cyan)
                            }
                            Text(message.message)
                                .font(.system(size: 11))
                                .foregroundColor(messageColor(for: message.type))
                        }
                    }
                }
                .padding(4)
            }
        }
        .background(Color.black.opacity(0.6))
    }

    private func messageColor(for type: ChatMessage.MessageType) -> Color {
        switch type {
        case .player: return .white
        case .server: return .yellow
        case .quest: return .green
        case .trade: return .purple
        case .privateIn: return .cyan
        case .privateOut: return .cyan
        }
    }
}

/// Tab buttons for inventory, skills, etc.
struct TabButtonsView: View {
    @Binding var showingInventory: Bool
    @Binding var showingSkills: Bool
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(spacing: 2) {
            TabButton(icon: "bag.fill", isActive: showingInventory) {
                showingInventory.toggle()
                showingSkills = false
                showingSettings = false
            }

            TabButton(icon: "chart.bar.fill", isActive: showingSkills) {
                showingSkills.toggle()
                showingInventory = false
                showingSettings = false
            }

            TabButton(icon: "map.fill", isActive: false) {
                // Toggle map
            }

            TabButton(icon: "gearshape.fill", isActive: showingSettings) {
                showingSettings.toggle()
                showingInventory = false
                showingSkills = false
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.5))
        .cornerRadius(4)
    }
}

struct SettingsPanel: View {
    @EnvironmentObject private var gameState: GameState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.caption.bold())
                    .foregroundColor(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.75))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Landscape Orientation")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.8))

                Picker(
                    "Landscape Orientation",
                    selection: Binding(
                        get: { gameState.gameOrientationPreference },
                        set: { gameState.updateGameOrientationPreference($0) }
                    )
                ) {
                    ForEach(GameOrientationPreference.allCases) { preference in
                        Text(preference.shortTitle).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Text(gameState.gameOrientationPreference.detail)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.black.opacity(0.82))
        .cornerRadius(8)
    }
}

struct TabButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isActive ? .yellow : .white)
                .frame(width: 32, height: 32)
        }
    }
}

/// Inventory panel.
struct InventoryView: View {
    let items: [InventoryItem]
    let onClose: () -> Void

    let columns = Array(repeating: GridItem(.fixed(32), spacing: 2), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Inventory")
                    .font(.caption.bold())
                    .foregroundColor(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<30) { index in
                    if index < items.count {
                        InventorySlot(item: items[index])
                    } else {
                        EmptySlot()
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }
}

struct InventorySlot: View {
    let item: InventoryItem

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 32, height: 32)

            // Item icon placeholder
            Text("\(item.itemId)")
                .font(.system(size: 8))
                .foregroundColor(.white)

            if item.amount > 1 {
                Text("\(item.amount)")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
            }
        }
        .cornerRadius(2)
    }
}

struct EmptySlot: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 32, height: 32)
            .cornerRadius(2)
    }
}

/// Skills panel.
struct SkillsView: View {
    let skills: [Skill]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Skills")
                    .font(.caption.bold())
                    .foregroundColor(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            ForEach(skills) { skill in
                HStack {
                    Text(skill.name)
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .frame(width: 70, alignment: .leading)

                    Text("\(skill.currentLevel)/\(skill.maxLevel)")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)

                    Spacer()
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }
}

#Preview {
    GameView(gameClient: GameClient(networkClient: NetworkClient()))
        .environmentObject(GameState())
}
