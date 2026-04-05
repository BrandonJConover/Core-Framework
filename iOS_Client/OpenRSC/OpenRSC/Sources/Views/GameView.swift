import SwiftUI
import MetalKit

private enum GamePanel {
    case social
    case inventory
    case skills
    case magic
    case settings
}

private enum SocialListTab: String, CaseIterable, Identifiable {
    case friends = "Friends"
    case ignore = "Ignore"

    var id: String { rawValue }
}

private enum ClassicPalette {
    static let shell = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let shellInset = Color(red: 0.20, green: 0.20, blue: 0.22)
    static let panel = Color(red: 0.79, green: 0.79, blue: 0.76)
    static let panelAlt = Color(red: 0.70, green: 0.70, blue: 0.68)
    static let panelBorder = Color(red: 0.24, green: 0.22, blue: 0.18)
    static let text = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let mutedText = Color(red: 0.31, green: 0.30, blue: 0.28)
    static let accent = Color(red: 0.94, green: 0.79, blue: 0.27)
}

/// Main game view that renders the game world.
/// Equivalent to Android's RSCBitmapSurfaceView.
struct GameView: View {
    @EnvironmentObject private var gameState: GameState
    @ObservedObject var gameClient: GameClient
    @StateObject private var inputHandler = InputHandler()

    @State private var activePanel: GamePanel?
    @State private var socialListTab: SocialListTab = .friends

    private var isAnyPanelOpen: Bool {
        activePanel != nil
    }

    var body: some View {
        GeometryReader { geometry in
            let viewportRect = GameViewport.fittedRect(in: geometry.size)
            let uiScale = viewportScale(for: viewportRect.size)
            let interactionFrame = gameplayInteractionFrame(in: viewportRect.size, uiScale: uiScale)
            let panelWidth = min(max(viewportRect.width * 0.42, 220), 320)
            let panelX = min(
                geometry.size.width - panelWidth / 2 - (10 * uiScale),
                viewportRect.maxX - panelWidth / 2 - (10 * uiScale)
            )

            ZStack {
                GameRendererView(gameClient: gameClient)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(0)

                if !isAnyPanelOpen {
                    Color.clear
                        .frame(width: interactionFrame.width, height: interactionFrame.height)
                        .position(
                            x: viewportRect.minX + interactionFrame.midX,
                            y: viewportRect.minY + interactionFrame.midY
                        )
                        .contentShape(Rectangle())
                        .gameGestures(
                            inputHandler,
                            viewportSize: viewportRect.size,
                            inputOrigin: interactionFrame.origin
                        )
                        .allowsHitTesting(true)
                        .zIndex(1)
                }

                if isAnyPanelOpen {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closePanels()
                        }
                        .zIndex(2)
                }

                VStack(spacing: 0) {
                    TopBar(gameClient: gameClient, uiScale: uiScale)
                        .padding(.top, 6 * uiScale)

                    Spacer(minLength: 0)

                    HStack(alignment: .bottom, spacing: 10 * uiScale) {
                        ChatView(
                            messages: gameClient.chatMessages,
                            uiScale: uiScale,
                            onSend: { text in
                                Task { try? await gameClient.sendChat(text) }
                            }
                        )
                        .frame(maxWidth: viewportRect.width * 0.62)

                        Spacer(minLength: 0)

                        TabButtonsView(
                            activePanel: activePanel,
                            uiScale: uiScale,
                            onTap: togglePanel
                        )
                    }
                    .padding(.horizontal, 10 * uiScale)
                    .padding(.bottom, 8 * uiScale)
                }
                .frame(width: viewportRect.width, height: viewportRect.height)
                .position(x: viewportRect.midX, y: viewportRect.midY)
                .zIndex(3)

                if let activePanel {
                    panelView(for: activePanel, uiScale: uiScale)
                        .frame(width: panelWidth)
                        .contentShape(Rectangle())
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .position(x: panelX, y: viewportRect.midY)
                        .zIndex(4)
                }
            }
            .ignoresSafeArea()
            .onAppear {
                inputHandler.gameClient = gameClient
            }
        }
    }

    @ViewBuilder
    private func panelView(for panel: GamePanel, uiScale: CGFloat) -> some View {
        switch panel {
        case .social:
            SocialPanel(
                selectedTab: $socialListTab,
                friends: gameClient.friendList,
                ignores: gameClient.ignoreList,
                uiScale: uiScale,
                onClose: closePanels
            )
        case .inventory:
            InventoryView(items: gameClient.inventory, uiScale: uiScale, onClose: closePanels)
        case .skills:
            SkillsView(
                skills: gameClient.skills,
                questPoints: gameClient.questPoints,
                questList: gameClient.questList,
                uiScale: uiScale,
                onClose: closePanels
            )
        case .magic:
            MagicPanel(
                magicLevel: gameClient.skills.first(where: { $0.name == "Magic" })?.currentLevel ?? 1,
                prayerLevel: gameClient.skills.first(where: { $0.name == "Prayer" })?.currentLevel ?? 1,
                uiScale: uiScale,
                onClose: closePanels
            )
        case .settings:
            SettingsPanel(uiScale: uiScale, onClose: closePanels)
        }
    }

    private func togglePanel(_ panel: GamePanel) {
        withAnimation(.easeOut(duration: 0.18)) {
            activePanel = activePanel == panel ? nil : panel
        }
    }

    private func closePanels() {
        withAnimation(.easeOut(duration: 0.18)) {
            activePanel = nil
        }
    }

    private func viewportScale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let widthScale = size.width / CGFloat(GameClient.gameWidth)
        let heightScale = size.height / CGFloat(GameClient.gameHeight)
        return max(0.82, min(1.55, min(widthScale, heightScale)))
    }

    private func gameplayInteractionFrame(in viewportSize: CGSize, uiScale: CGFloat) -> CGRect {
        let horizontalInset = min(18 * uiScale, viewportSize.width * 0.04)
        let topInset = min(max(54 * uiScale, 40), viewportSize.height * 0.18)
        let bottomInset = min(max(124 * uiScale, 92), viewportSize.height * 0.36)
        let width = max(120, viewportSize.width - horizontalInset * 2)
        let height = max(120, viewportSize.height - topInset - bottomInset)

        return CGRect(
            x: horizontalInset,
            y: topInset,
            width: width,
            height: height
        )
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
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
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
    let uiScale: CGFloat

    private var bodyWidth: CGFloat { 22 * uiScale }
    private var bodyHeight: CGFloat { 10 * uiScale }

    var body: some View {
        HStack(spacing: 4 * uiScale) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2 * uiScale)
                    .stroke(battery.color.opacity(0.95), lineWidth: max(1, uiScale))
                    .frame(width: bodyWidth, height: bodyHeight)

                RoundedRectangle(cornerRadius: 1.5 * uiScale)
                    .fill(battery.color.opacity(0.95))
                    .frame(
                        width: max(2 * uiScale, (bodyWidth - (3 * uiScale)) * battery.normalizedLevel),
                        height: bodyHeight - (3 * uiScale)
                    )
                    .padding(.leading, 1.5 * uiScale)

                if battery.state == .charging || battery.state == .full {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6 * uiScale, weight: .bold))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(width: bodyWidth, height: bodyHeight)
                }
            }
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: uiScale)
                    .fill(battery.color.opacity(0.95))
                    .frame(width: max(2, 2 * uiScale), height: 5 * uiScale)
                    .offset(x: 4 * uiScale)
            }

            Text(battery.percentageText)
                .font(.system(size: 10 * uiScale, weight: .semibold, design: .monospaced))
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

    let uiScale: CGFloat

    var body: some View {
        HStack(spacing: 10 * uiScale) {
            Group {
                if let compassImage = SpriteManager.shared.getGuiImage(.compass) {
                    Image(uiImage: compassImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "location.north.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                }
            }
            .frame(width: 22 * uiScale, height: 22 * uiScale)
            .rotationEffect(.degrees(Double(gameClient.cameraRotation) / 256.0 * 360.0))

            if let player = gameClient.localPlayer {
                VStack(alignment: .leading, spacing: 2 * uiScale) {
                    Text(player.username)
                        .font(.system(size: 12 * uiScale, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Combat \(player.combatLevel)")
                        .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.72))
                }
            } else {
                Text("Connecting")
                    .font(.system(size: 12 * uiScale, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4 * uiScale) {
                HStack(spacing: 8 * uiScale) {
                    Image(systemName: gameState.isConnected ? "wifi" : "wifi.slash")
                        .font(.system(size: 12 * uiScale, weight: .bold))
                        .foregroundColor(gameState.isConnected ? .green : .red)
                    BatteryStatusView(battery: battery, uiScale: uiScale)
                }

                Text("Camera \(cameraAngleLabel)")
                    .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 10 * uiScale)
        .padding(.vertical, 6 * uiScale)
        .background(
            RoundedRectangle(cornerRadius: 8 * uiScale)
                .fill(ClassicPalette.shell.opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: 8 * uiScale)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 8 * uiScale)
    }

    private var cameraAngleLabel: String {
        let step = ((gameClient.cameraRotation + 16) / 32) & 7
        return "Angle \(step)"
    }
}

private enum ChatTab: String, CaseIterable {
    case all = "All"
    case game = "Game"
    case quest = "Quest"
    case priv = "Private"
}

/// Chat display area with message tabs and text input.
struct ChatView: View {
    let messages: [ChatMessage]
    let uiScale: CGFloat
    var onSend: ((String) -> Void)?

    @State private var selectedTab: ChatTab = .all
    @State private var inputText: String = ""

    private var filteredMessages: [ChatMessage] {
        switch selectedTab {
        case .all:
            return Array(messages.suffix(20))
        case .game:
            return messages.filter { $0.type == .server || $0.type == .player || $0.type == .trade }.suffix(20).map { $0 }
        case .quest:
            return messages.filter { $0.type == .quest }.suffix(20).map { $0 }
        case .priv:
            return messages.filter { $0.type == .privateIn || $0.type == .privateOut }.suffix(20).map { $0 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message type tabs
            HStack(spacing: 0) {
                ForEach(ChatTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.system(size: 9 * uiScale, weight: .semibold, design: .monospaced))
                            .foregroundColor(selectedTab == tab ? ClassicPalette.accent : Color.white.opacity(0.6))
                            .padding(.horizontal, 6 * uiScale)
                            .padding(.vertical, 3 * uiScale)
                            .background(
                                selectedTab == tab
                                    ? ClassicPalette.shell.opacity(0.9)
                                    : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4 * uiScale)
            .background(ClassicPalette.shell.opacity(0.6))

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2 * uiScale) {
                        ForEach(filteredMessages) { message in
                            HStack(spacing: 4 * uiScale) {
                                if let sender = message.sender {
                                    Text("\(sender):")
                                        .font(.system(size: 11 * uiScale, weight: .bold, design: .monospaced))
                                        .foregroundColor(.cyan)
                                }
                                Text(message.message)
                                    .font(.system(size: 11 * uiScale, weight: .medium, design: .monospaced))
                                    .foregroundColor(messageColor(for: message.type))
                            }
                            .id(message.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6 * uiScale)
                }
                .onChange(of: messages.count) { _ in
                    if let last = filteredMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 80 * uiScale)

            // Chat input
            HStack(spacing: 6 * uiScale) {
                TextField("Chat...", text: $inputText)
                    .font(.system(size: 11 * uiScale, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .tint(ClassicPalette.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Text("Send")
                        .font(.system(size: 10 * uiScale, weight: .bold, design: .monospaced))
                        .foregroundColor(inputText.isEmpty ? Color.white.opacity(0.4) : ClassicPalette.accent)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 8 * uiScale)
            .padding(.vertical, 4 * uiScale)
            .background(ClassicPalette.shell.opacity(0.7))
        }
        .background(
            RoundedRectangle(cornerRadius: 8 * uiScale)
                .fill(ClassicPalette.shell.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 8 * uiScale)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8 * uiScale))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSend?(text)
        inputText = ""
    }

    private func messageColor(for type: ChatMessage.MessageType) -> Color {
        switch type {
        case .player: return .white
        case .server: return .yellow
        case .quest: return .green
        case .trade: return .purple
        case .privateIn, .privateOut: return .cyan
        }
    }
}

private struct TabButtonsView: View {
    let activePanel: GamePanel?
    let uiScale: CGFloat
    let onTap: (GamePanel) -> Void

    private let buttons: [(panel: GamePanel, guiPart: SpriteManager.GuiPart)] = [
        (.social, .socialTab),
        (.inventory, .bagTab),
        (.skills, .skillsTab),
        (.magic, .spellTab),
        (.settings, .settingsTab)
    ]

    var body: some View {
        VStack(spacing: 5 * uiScale) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, entry in
                ClassicTabButton(
                    guiPart: entry.guiPart,
                    isActive: activePanel == entry.panel,
                    uiScale: uiScale
                ) {
                    onTap(entry.panel)
                }
            }
        }
        .padding(.vertical, 4 * uiScale)
    }
}

private struct ClassicTabButton: View {
    let guiPart: SpriteManager.GuiPart
    let isActive: Bool
    let uiScale: CGFloat
    let action: () -> Void

    private var width: CGFloat {
        122 * uiScale
    }

    private var minimumHeight: CGFloat {
        max(34 * uiScale, 44)
    }

    private var guiImage: UIImage? {
        SpriteManager.shared.getGuiImage(guiPart)
    }

    private var buttonHeight: CGFloat {
        guard let guiImage else { return minimumHeight }
        return max(minimumHeight, width * (guiImage.size.height / max(guiImage.size.width, 1)))
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let guiImage {
                    Image(uiImage: guiImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 5 * uiScale)
                        .fill(ClassicPalette.panelAlt)
                }
            }
            .frame(width: width, height: buttonHeight)
            .padding(.vertical, 1 * uiScale)
            .overlay(
                RoundedRectangle(cornerRadius: 5 * uiScale)
                    .stroke(isActive ? ClassicPalette.accent : Color.white.opacity(0.18), lineWidth: isActive ? 2 : 1)
            )
            .shadow(color: .black.opacity(isActive ? 0.30 : 0.14), radius: isActive ? 6 : 3, y: 2)
            .opacity(isActive ? 1 : 0.92)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }
}

private struct ClassicPanelContainer<Content: View>: View {
    let title: String
    let guiPart: SpriteManager.GuiPart
    let uiScale: CGFloat
    let onClose: () -> Void
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8 * uiScale) {
                ClassicGuiSpriteView(part: guiPart)
                    .frame(width: 86 * uiScale)

                Text(title)
                    .font(.system(size: 13 * uiScale, weight: .bold, design: .monospaced))
                    .foregroundColor(ClassicPalette.text)

                Spacer()

                Button(action: onClose) {
                    if let image = SpriteManager.shared.getGuiImage(.xMark) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16 * uiScale, height: 16 * uiScale)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18 * uiScale, weight: .semibold))
                            .foregroundColor(ClassicPalette.text.opacity(0.8))
                    }
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10 * uiScale)
            .padding(.vertical, 8 * uiScale)
            .background(ClassicPalette.panelAlt)

            Divider()
                .overlay(ClassicPalette.panelBorder)

            content
                .padding(10 * uiScale)
        }
        .background(
            RoundedRectangle(cornerRadius: 10 * uiScale)
                .fill(ClassicPalette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 10 * uiScale)
                        .stroke(ClassicPalette.panelBorder, lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

private struct ClassicGuiSpriteView: View {
    let part: SpriteManager.GuiPart

    var body: some View {
        if let image = SpriteManager.shared.getGuiImage(part) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(ClassicPalette.panelAlt)
        }
    }
}

struct SettingsPanel: View {
    @EnvironmentObject private var gameState: GameState
    let uiScale: CGFloat
    let onClose: () -> Void

    var body: some View {
        ClassicPanelContainer(
            title: "Options",
            guiPart: .settingsTab,
            uiScale: uiScale,
            onClose: onClose,
            content: VStack(alignment: .leading, spacing: 12 * uiScale) {
                settingsSection(title: "Display") {
                    VStack(alignment: .leading, spacing: 8 * uiScale) {
                        Text("Landscape orientation")
                            .font(.system(size: 12 * uiScale, weight: .bold, design: .monospaced))
                            .foregroundColor(ClassicPalette.text)

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
                            .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundColor(ClassicPalette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsSection(title: "Camera") {
                    VStack(alignment: .leading, spacing: 6 * uiScale) {
                        SettingsBullet(text: "Rotation snaps in classic 8-way steps.", uiScale: uiScale)
                        SettingsBullet(text: "Zoom is limited to the original-style mobile-safe range.", uiScale: uiScale)
                        SettingsBullet(text: "Viewport stays aspect-fit to the device instead of stretching.", uiScale: uiScale)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6 * uiScale) {
            Text(title)
                .font(.system(size: 11 * uiScale, weight: .bold, design: .monospaced))
                .foregroundColor(ClassicPalette.mutedText)
            content()
        }
    }
}

private struct SettingsBullet: View {
    let text: String
    let uiScale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 6 * uiScale) {
            Circle()
                .fill(ClassicPalette.accent)
                .frame(width: 5 * uiScale, height: 5 * uiScale)
                .padding(.top, 5 * uiScale)

            Text(text)
                .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                .foregroundColor(ClassicPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SocialPanel: View {
    @Binding var selectedTab: SocialListTab
    let friends: [(name: String, online: Bool)]
    let ignores: [String]
    let uiScale: CGFloat
    let onClose: () -> Void

    var body: some View {
        ClassicPanelContainer(
            title: "Social",
            guiPart: .socialTab,
            uiScale: uiScale,
            onClose: onClose,
            content: VStack(alignment: .leading, spacing: 10 * uiScale) {
                Picker("Social", selection: $selectedTab) {
                    ForEach(SocialListTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if selectedTab == .friends {
                    Text("Click a name to send a message")
                        .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                        .foregroundColor(ClassicPalette.mutedText)

                    ScrollView {
                        LazyVStack(spacing: 6 * uiScale) {
                            if friends.isEmpty {
                                SocialEmptyState(text: "Your friends list is empty.", uiScale: uiScale)
                            } else {
                                ForEach(Array(friends.enumerated()), id: \.offset) { _, friend in
                                    SocialRow(
                                        name: friend.name,
                                        statusText: friend.online ? "Online" : "Offline",
                                        statusColor: friend.online ? .green : .red,
                                        uiScale: uiScale
                                    )
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260 * uiScale)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6 * uiScale) {
                            if ignores.isEmpty {
                                SocialEmptyState(text: "Your ignore list is empty.", uiScale: uiScale)
                            } else {
                                ForEach(ignores, id: \.self) { name in
                                    SocialRow(
                                        name: name,
                                        statusText: "Ignored",
                                        statusColor: .yellow,
                                        uiScale: uiScale
                                    )
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260 * uiScale)
                }
            }
        )
    }
}

private struct SocialRow: View {
    let name: String
    let statusText: String
    let statusColor: Color
    let uiScale: CGFloat

    var body: some View {
        HStack(spacing: 8 * uiScale) {
            Circle()
                .fill(statusColor)
                .frame(width: 7 * uiScale, height: 7 * uiScale)

            Text(name)
                .font(.system(size: 11 * uiScale, weight: .bold, design: .monospaced))
                .foregroundColor(ClassicPalette.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(statusText)
                .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                .foregroundColor(ClassicPalette.mutedText)
        }
        .padding(.horizontal, 8 * uiScale)
        .padding(.vertical, 7 * uiScale)
        .background(
            RoundedRectangle(cornerRadius: 6 * uiScale)
                .fill(Color.white.opacity(0.28))
        )
    }
}

private struct SocialEmptyState: View {
    let text: String
    let uiScale: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 11 * uiScale, weight: .medium, design: .monospaced))
            .foregroundColor(ClassicPalette.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16 * uiScale)
    }
}

/// Inventory panel.
struct InventoryView: View {
    let items: [InventoryItem]
    let uiScale: CGFloat
    let onClose: () -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 34 * uiScale, maximum: 38 * uiScale), spacing: 4 * uiScale), count: 5)
    }

    var body: some View {
        ClassicPanelContainer(
            title: "Inventory",
            guiPart: .bagTab,
            uiScale: uiScale,
            onClose: onClose,
            content: LazyVGrid(columns: columns, spacing: 4 * uiScale) {
                ForEach(0..<30, id: \.self) { index in
                    if index < items.count {
                        InventorySlot(item: items[index], uiScale: uiScale)
                    } else {
                        EmptySlot(uiScale: uiScale)
                    }
                }
            }
        )
    }
}

struct InventorySlot: View {
    let item: InventoryItem
    let uiScale: CGFloat

    private var itemImage: UIImage? {
        SpriteManager.shared.getItemSprite(itemId: item.itemId).flatMap {
            SpriteManager.shared.imageForSprite($0)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4 * uiScale)
                .fill(Color(red: 0.71, green: 0.71, blue: 0.71).opacity(0.5))
                .frame(width: 36 * uiScale, height: 36 * uiScale)

            if let img = itemImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32 * uiScale, height: 32 * uiScale)
                    .frame(width: 36 * uiScale, height: 36 * uiScale)
            } else {
                Image(systemName: "square.dashed")
                    .font(.system(size: 14 * uiScale))
                    .foregroundColor(ClassicPalette.text.opacity(0.4))
                    .frame(width: 36 * uiScale, height: 36 * uiScale)
            }

            if item.amount > 1 {
                Text(formatAmount(item.amount))
                    .font(.system(size: 8 * uiScale, weight: .bold, design: .monospaced))
                    .foregroundColor(amountColor(item.amount))
                    .shadow(color: .black.opacity(0.8), radius: 1, x: 1, y: 1)
                    .padding(.leading, 2 * uiScale)
                    .padding(.top, 1 * uiScale)
            }
        }
        .frame(width: 36 * uiScale, height: 36 * uiScale)
    }

    private func formatAmount(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }

    private func amountColor(_ n: Int) -> Color {
        if n >= 1_000_000 { return .green }
        if n >= 1_000 { return .yellow }
        return .white
    }
}

struct EmptySlot: View {
    let uiScale: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4 * uiScale)
            .fill(Color.white.opacity(0.16))
            .frame(width: 36 * uiScale, height: 36 * uiScale)
    }
}

private enum SkillsSubTab { case stats, quests }

/// Skills panel — two-column layout matching the desktop client.
struct SkillsView: View {
    let skills: [Skill]
    let questPoints: Int
    let questList: [Int: Int]
    let uiScale: CGFloat
    let onClose: () -> Void

    @State private var subTab: SkillsSubTab = .stats

    private var leftSkills: [Skill] { Array(skills.prefix(skills.count / 2)) }
    private var rightSkills: [Skill] { Array(skills.dropFirst(skills.count / 2)) }

    var body: some View {
        ClassicPanelContainer(
            title: "Skills",
            guiPart: .skillsTab,
            uiScale: uiScale,
            onClose: onClose,
            content: VStack(alignment: .leading, spacing: 8 * uiScale) {
                // Sub-tab selector matching desktop Stats / Quests
                HStack(spacing: 0) {
                    subTabButton("Stats", selected: subTab == .stats) { subTab = .stats }
                    subTabButton("Quests", selected: subTab == .quests) { subTab = .quests }
                    Spacer(minLength: 0)
                }

                if subTab == .stats {
                    HStack(alignment: .top, spacing: 4 * uiScale) {
                        VStack(alignment: .leading, spacing: 3 * uiScale) {
                            ForEach(leftSkills) { skill in
                                skillRow(skill, uiScale: uiScale)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3 * uiScale) {
                            ForEach(rightSkills) { skill in
                                skillRow(skill, uiScale: uiScale)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4 * uiScale) {
                        HStack(spacing: 4 * uiScale) {
                            Text("Quest Points:")
                                .font(.system(size: 10 * uiScale, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("\(questPoints)")
                                .font(.system(size: 10 * uiScale, weight: .bold, design: .monospaced))
                                .foregroundColor(ClassicPalette.accent)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3 * uiScale) {
                                if questList.isEmpty {
                                    Text("No quests started.")
                                        .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                                        .foregroundColor(ClassicPalette.mutedText)
                                } else {
                                    ForEach(questList.keys.sorted(), id: \.self) { qId in
                                        let state = questList[qId] ?? 0
                                        HStack(spacing: 4 * uiScale) {
                                            Circle()
                                                .fill(state > 0 ? Color.green : Color.white.opacity(0.4))
                                                .frame(width: 6 * uiScale, height: 6 * uiScale)
                                            Text("Quest \(qId)")
                                                .font(.system(size: 10 * uiScale, weight: .medium, design: .monospaced))
                                                .foregroundColor(state > 0 ? .white : ClassicPalette.mutedText)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200 * uiScale)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func subTabButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11 * uiScale, weight: .bold, design: .monospaced))
                .foregroundColor(selected ? ClassicPalette.text : ClassicPalette.mutedText)
                .padding(.horizontal, 10 * uiScale)
                .padding(.vertical, 5 * uiScale)
                .background(
                    RoundedRectangle(cornerRadius: 4 * uiScale)
                        .fill(selected ? Color.white.opacity(0.55) : Color.white.opacity(0.22))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func skillRow(_ skill: Skill, uiScale: CGFloat) -> some View {
        let drained = skill.currentLevel < skill.maxLevel
        HStack(spacing: 2 * uiScale) {
            Text("\(skill.name):")
                .font(.system(size: 9 * uiScale, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(skill.currentLevel)")
                .font(.system(size: 9 * uiScale, weight: .bold, design: .monospaced))
                .foregroundColor(drained ? .red : .yellow)
            Text("/\(skill.maxLevel)")
                .font(.system(size: 9 * uiScale, weight: .medium, design: .monospaced))
                .foregroundColor(.yellow)
        }
    }
}

// MARK: - Magic / Prayer Panel

private enum MagicSubTab { case magic, prayers }

private struct ClassicSpell {
    let name: String
    let level: Int
    let runes: String
}

private struct ClassicPrayer {
    let name: String
    let level: Int
}

struct MagicPanel: View {
    let magicLevel: Int
    let prayerLevel: Int
    let uiScale: CGFloat
    let onClose: () -> Void

    @State private var subTab: MagicSubTab = .magic

    private static let spells: [ClassicSpell] = [
        ClassicSpell(name: "Wind Strike", level: 1, runes: "1 Air, 1 Mind"),
        ClassicSpell(name: "Water Strike", level: 5, runes: "1 Air, 1 Mind, 1 Water"),
        ClassicSpell(name: "Earth Strike", level: 9, runes: "2 Air, 1 Mind, 1 Earth"),
        ClassicSpell(name: "Fire Strike", level: 13, runes: "3 Air, 1 Mind, 1 Fire"),
        ClassicSpell(name: "Wind Bolt", level: 17, runes: "2 Air, 1 Chaos"),
        ClassicSpell(name: "Water Bolt", level: 23, runes: "2 Air, 1 Chaos, 2 Water"),
        ClassicSpell(name: "Earth Bolt", level: 29, runes: "3 Air, 1 Chaos, 2 Earth"),
        ClassicSpell(name: "Fire Bolt", level: 35, runes: "4 Air, 1 Chaos, 3 Fire"),
        ClassicSpell(name: "Wind Blast", level: 41, runes: "3 Air, 1 Death"),
        ClassicSpell(name: "Water Blast", level: 47, runes: "3 Air, 1 Death, 3 Water"),
        ClassicSpell(name: "Earth Blast", level: 53, runes: "4 Air, 1 Death, 3 Earth"),
        ClassicSpell(name: "Fire Blast", level: 59, runes: "5 Air, 1 Death, 4 Fire"),
        ClassicSpell(name: "Teleport to Lumbridge", level: 31, runes: "1 Law, 3 Air, 1 Earth"),
        ClassicSpell(name: "Teleport to Falador", level: 37, runes: "1 Law, 3 Air, 1 Water"),
        ClassicSpell(name: "Teleport to Varrock", level: 25, runes: "1 Law, 3 Air, 1 Fire"),
    ]

    private static let prayers: [ClassicPrayer] = [
        ClassicPrayer(name: "Thick Skin", level: 1),
        ClassicPrayer(name: "Burst of Strength", level: 4),
        ClassicPrayer(name: "Clarity of Thought", level: 7),
        ClassicPrayer(name: "Rock Skin", level: 10),
        ClassicPrayer(name: "Superhuman Strength", level: 13),
        ClassicPrayer(name: "Improved Reflexes", level: 16),
        ClassicPrayer(name: "Rapid Restore", level: 19),
        ClassicPrayer(name: "Rapid Heal", level: 22),
        ClassicPrayer(name: "Protect Item", level: 25),
        ClassicPrayer(name: "Steel Skin", level: 28),
        ClassicPrayer(name: "Ultimate Strength", level: 31),
        ClassicPrayer(name: "Incredible Reflexes", level: 34),
        ClassicPrayer(name: "Paralyze Monster", level: 37),
        ClassicPrayer(name: "Protect from Magic", level: 40),
    ]

    var body: some View {
        ClassicPanelContainer(
            title: "Magic & Prayers",
            guiPart: .spellTab,
            uiScale: uiScale,
            onClose: onClose,
            content: VStack(alignment: .leading, spacing: 8 * uiScale) {
                // Sub-tab selector
                HStack(spacing: 0) {
                    subTabButton("Magic", selected: subTab == .magic) { subTab = .magic }
                    subTabButton("Prayers", selected: subTab == .prayers) { subTab = .prayers }
                    Spacer(minLength: 0)
                }

                if subTab == .magic {
                    Text("Magic level: \(magicLevel)")
                        .font(.system(size: 10 * uiScale, weight: .bold, design: .monospaced))
                        .foregroundColor(ClassicPalette.accent)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4 * uiScale) {
                            ForEach(Self.spells.sorted(by: { $0.level < $1.level }), id: \.name) { spell in
                                let canCast = magicLevel >= spell.level
                                HStack(alignment: .top, spacing: 4 * uiScale) {
                                    Text("Lv.\(spell.level)")
                                        .font(.system(size: 9 * uiScale, weight: .bold, design: .monospaced))
                                        .foregroundColor(canCast ? ClassicPalette.accent : ClassicPalette.mutedText)
                                        .frame(width: 30 * uiScale, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1 * uiScale) {
                                        Text(spell.name)
                                            .font(.system(size: 10 * uiScale, weight: .bold, design: .monospaced))
                                            .foregroundColor(canCast ? .white : ClassicPalette.mutedText)
                                        Text(spell.runes)
                                            .font(.system(size: 8 * uiScale, weight: .medium, design: .monospaced))
                                            .foregroundColor(ClassicPalette.mutedText)
                                    }
                                }
                                .padding(.vertical, 2 * uiScale)
                                .padding(.horizontal, 4 * uiScale)
                                .background(
                                    canCast
                                        ? RoundedRectangle(cornerRadius: 3 * uiScale).fill(Color.white.opacity(0.06))
                                        : nil
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 260 * uiScale)
                } else {
                    Text("Prayer level: \(prayerLevel)")
                        .font(.system(size: 10 * uiScale, weight: .bold, design: .monospaced))
                        .foregroundColor(ClassicPalette.accent)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4 * uiScale) {
                            ForEach(Self.prayers, id: \.name) { prayer in
                                let canUse = prayerLevel >= prayer.level
                                HStack(spacing: 4 * uiScale) {
                                    Text("Lv.\(prayer.level)")
                                        .font(.system(size: 9 * uiScale, weight: .bold, design: .monospaced))
                                        .foregroundColor(canUse ? ClassicPalette.accent : ClassicPalette.mutedText)
                                        .frame(width: 30 * uiScale, alignment: .leading)
                                    Text(prayer.name)
                                        .font(.system(size: 10 * uiScale, weight: .bold, design: .monospaced))
                                        .foregroundColor(canUse ? .white : ClassicPalette.mutedText)
                                }
                                .padding(.vertical, 2 * uiScale)
                                .padding(.horizontal, 4 * uiScale)
                                .background(
                                    canUse
                                        ? RoundedRectangle(cornerRadius: 3 * uiScale).fill(Color.white.opacity(0.06))
                                        : nil
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 260 * uiScale)
                }
            }
        )
    }

    @ViewBuilder
    private func subTabButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11 * uiScale, weight: .bold, design: .monospaced))
                .foregroundColor(selected ? ClassicPalette.text : ClassicPalette.mutedText)
                .padding(.horizontal, 10 * uiScale)
                .padding(.vertical, 5 * uiScale)
                .background(
                    RoundedRectangle(cornerRadius: 4 * uiScale)
                        .fill(selected ? Color.white.opacity(0.55) : Color.white.opacity(0.22))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    GameView(gameClient: GameClient(networkClient: NetworkClient()))
        .environmentObject(GameState())
}
