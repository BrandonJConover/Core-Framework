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
    @State private var longPressConsumed: Bool = false
    @State private var isPinching: Bool = false
    @State private var pinchStartZoom: CGFloat = 1.0

    var body: some View {
        #if canImport(UIKit)
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                // Metal game canvas — full screen
                MetalViewRepresentable(engine: engine)
                    .ignoresSafeArea()
                    // Single-finger drag = pan-rotate camera. A drag that
                    // never moves more than ~18pt is treated as a tap when
                    // it ends. Real thumb taps drift more than desktop clicks,
                    // so keep this forgiving enough for tap-to-walk/interact.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragStartLocation = value.location
                                if !dragMovedFar {
                                    let dist = hypot(value.translation.width, value.translation.height)
                                    if dist < 18 { return }   // still treating this as a tap-in-progress
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
                                if !dragMovedFar && !longPressConsumed && !isPinching {
                                    // Treated as a tap.
                                    engine.touchTranslator.handleTap(at: value.location)
                                }
                                dragMovedFar = false
                                longPressConsumed = false
                            }
                    )
                    // Long-press = right-click context menu.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onEnded { value in
                                switch value {
                                case .second(true, let drag):
                                    longPressConsumed = true
                                    engine.showContextMenu(at: drag?.location ?? dragStartLocation)
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
                                isPinching = true
                                if abs(scale - 1.0) < 0.01 {
                                    pinchStartZoom = engine.zoomLevel
                                }
                                let newZoom = pinchStartZoom * scale
                                engine.zoomLevel = max(0.5, min(3.0, newZoom))
                            }
                            .onEnded { _ in
                                pinchStartZoom = engine.zoomLevel
                                isPinching = false
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
                    if engine.worldState.experienceFrozen {
                        Text("Exp gain off")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#ff5a5a"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.72))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color(hex: "#ff5a5a").opacity(0.55), lineWidth: 1)
                            )
                            .padding(.top, 4)
                    }
                    Spacer()
                }

                // Friend online/offline toasts (top-right corner).
                VStack {
                    HStack {
                        Spacer()
                        FriendToastStack(worldState: engine.worldState)
                            .padding(.trailing, 12)
                            .padding(.top, 48)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)

                XPDropFloatOverlay(worldState: engine.worldState, gameSize: geo.size)

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
        if engine.worldState.fishingTrawlerOpen {
            FishingTrawlerStatusOverlay(worldState: engine.worldState)
                .allowsHitTesting(false)
        }
        if engine.worldState.serverMessageDialogOpen {
            ServerMessageDialog(worldState: engine.worldState)
        }
        if engine.worldState.inputPromptOpen {
            InputPromptDialog(worldState: engine.worldState)
        }
        if engine.worldState.contactDetailsOpen {
            ContactDetailsDialog(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.recoveryQuestionsOpen {
            RecoveryQuestionsDialog(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.showAppearanceChange {
            AppearancePanel(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.welcomeOpen {
            WelcomePanel(worldState: engine.worldState)
        }
        if engine.worldState.wildernessWarningOpen {
            WildernessWarningPanel(worldState: engine.worldState)
        }
        if engine.worldState.isSleeping {
            SleepPanel(worldState: engine.worldState, engine: engine)
        }
        if engine.worldState.isDead || engine.worldState.deathScreenTimeout > 0 {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("You have died").font(.system(size: 24, weight: .bold)).foregroundColor(.red)
                Text(deathSubtitle).font(.system(size: 14)).foregroundColor(Color(hex: "#888888"))
            }
        }
        if engine.worldState.connectionClosedOpen {
            ConnectionClosedDialog(worldState: engine.worldState, appState: appState, server: server)
        }
    }

    private var deathSubtitle: String {
        let seconds = max(1, Int(ceil(Double(engine.worldState.deathScreenTimeout) * 0.05)))
        return "You will respawn shortly" + (engine.worldState.deathScreenTimeout > 0 ? " (\(seconds)s)" : "")
    }
}

// MARK: - Server Message Dialog

private struct ServerMessageDialog: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        ZStack(alignment: worldState.serverMessageDialogTop ? .top : .center) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 18) {
                Text(worldState.serverMessageDialogText)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)

                Button(action: close) {
                    Text("Click here to close window")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#ff5a5a"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 400)
            .padding(.horizontal, 16)
            .background(Color.black.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
            .padding(.top, worldState.serverMessageDialogTop ? 72 : 0)
        }
    }

    private func close() {
        worldState.serverMessageDialogOpen = false
        worldState.serverMessageDialogText = ""
    }
}

// MARK: - Custom Input Prompt

private struct InputPromptDialog: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 16) {
                Text(worldState.inputPromptText)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)

                Button(action: close) {
                    Text("Click here to continue")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#ff5a5a"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 400)
            .padding(.horizontal, 16)
            .background(Color.black.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
        }
    }

    private func close() {
        worldState.inputPromptOpen = false
        worldState.inputPromptText = ""
    }
}

// MARK: - Connection Closed

private struct ConnectionClosedDialog: View {
    @ObservedObject var worldState: RSCWorldState
    @ObservedObject var appState: AppState
    let server: ServerProfile

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Connection lost")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text(worldState.connectionClosedText.isEmpty ? "Disconnected from the server." : worldState.connectionClosedText)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.86))
                    .multilineTextAlignment(.center)

                Button("Return to servers") {
                    worldState.connectionClosedOpen = false
                    appState.currentView = .serverBrowser(server.gameType)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "#ff5a5a"))
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .padding(.horizontal, 16)
            .background(Color.black.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
        }
    }
}

// MARK: - Account Security Dialogs

private struct ContactDetailsDialog: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    @State private var fullName = ""
    @State private var zipCode = ""
    @State private var country = ""
    @State private var email = ""
    @State private var error = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Please supply your contact details")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.yellow)

                Text("We need this information to provide account support and recovery help.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.88))
                    .multilineTextAlignment(.center)

                securityTextField("Full name", text: $fullName)
                securityTextField("Postcode/Zipcode", text: $zipCode)
                securityTextField("Country", text: $country)
                securityTextField("Email address", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#ff7a7a"))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button("Not now") {
                        worldState.contactDetailsOpen = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.75))

                    Button("Submit") {
                        submit()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#ff5a5a"))
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .padding(.horizontal, 16)
            .background(Color.black.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
        }
    }

    private func securityTextField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
    }

    private func submit() {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let zip = zipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let contactCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let contactEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !zip.isEmpty, !contactCountry.isEmpty, !contactEmail.isEmpty else {
            error = "Please fill in all the requested details."
            return
        }
        guard contactEmail.contains("@"), contactEmail.contains(".") else {
            error = "Please use a valid email address."
            return
        }

        engine.submitContactDetails(name: name, zipCode: zip, country: contactCountry, email: contactEmail)
    }
}

private struct RecoveryQuestionsDialog: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine
    @State private var selectedQuestions = [0, 1, 2, 3, 4]
    @State private var answers = Array(repeating: "", count: 5)
    @State private var error = ""

    private let questions = [
        "Where were you born?",
        "What was your first teacher's name?",
        "What is your father's middle name?",
        "Who was your first best friend?",
        "What is your favourite vacation spot?",
        "What is your mother's middle name?",
        "What was your first pet's name?",
        "What was the name of your first school?",
        "What is your mother's maiden name?",
        "Who was your first boyfriend/girlfriend?",
        "What was the first computer game you purchased?",
        "Who is your favourite actor/actress?",
        "Who is your favourite author?",
        "Who is your favourite musician?",
        "Who is your favourite cartoon character?",
        "What is your favourite book?",
        "What is your favourite food?",
        "What is your favourite movie?"
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    Text("Please provide 5 security questions")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.yellow)

                    Text("These answers are used only if you need to recover your account. Give answers you can type exactly again later.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.88))
                        .multilineTextAlignment(.center)

                    ForEach(0..<5, id: \.self) { idx in
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Question \(idx + 1)", selection: $selectedQuestions[idx]) {
                                ForEach(questions.indices, id: \.self) { q in
                                    Text(questions[q]).tag(q)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)

                            SecureField("Answer \(idx + 1)", text: $answers[idx])
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                        }
                    }

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#ff7a7a"))
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        Button("Not now") {
                            worldState.recoveryQuestionsOpen = false
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.75))

                        Button("Click here when finished") {
                            submit()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#ff5a5a"))
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 460)
                .padding(.horizontal, 16)
                .background(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
            }
            .frame(maxHeight: 520)
        }
    }

    private func submit() {
        let cleanAnswers = answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let shortIndex = cleanAnswers.firstIndex(where: { $0.count < 3 }) else {
            let lowered = cleanAnswers.map { $0.lowercased() }
            guard Set(lowered).count == lowered.count else {
                error = "Each question must have a different answer."
                return
            }
            let pairs = selectedQuestions.indices.map { idx in
                (question: questions[selectedQuestions[idx]], answer: cleanAnswers[idx])
            }
            engine.submitRecoveryQuestions(pairs)
            return
        }
        error = "Please provide a longer answer to question \(shortIndex + 1)."
    }
}

// MARK: - Fishing Trawler

private struct FishingTrawlerStatusOverlay: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                trawlerMetric("Water", "\(worldState.fishingTrawlerWaterLevel)")
                trawlerMetric("Fish", "\(worldState.fishingTrawlerFishCaught)")
                trawlerMetric("Time", "\(worldState.fishingTrawlerMinutesLeft)m")
                if worldState.fishingTrawlerNetBroken {
                    Text("Net broken")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#ff5a5a"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )

            Spacer()
        }
        .padding(.top, 18)
    }

    private func trawlerMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundColor(.white.opacity(0.72))
            Text(value)
                .foregroundColor(.yellow)
                .fontWeight(.bold)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}

private struct XPDropFloatOverlay: View {
    @ObservedObject var worldState: RSCWorldState
    let gameSize: CGSize

    var body: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                ForEach(Array(worldState.xpDrops.enumerated()), id: \.element.id) { index, drop in
                    let age = timeline.date.timeIntervalSince(drop.timestamp)
                    if age >= 0, age < 3 {
                        Text("+\(drop.amount) \(drop.skill)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#7CFF6B"))
                            .shadow(color: .black, radius: 2, x: 0, y: 1)
                            .opacity(max(0, 1.0 - age / 3.0))
                            .position(
                                x: gameSize.width / 2,
                                y: gameSize.height / 2 - 46 - CGFloat(age * 36) - CGFloat(index * 16)
                            )
                    }
                }
            }
        }
        .frame(width: gameSize.width, height: gameSize.height)
        .allowsHitTesting(false)
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
                        Button(action: {
                            if let pendingSpellId = worldState.pendingSpellId {
                                engine.castSpellOnItem(spellId: pendingSpellId, slot: item.id)
                                selectedSlot = nil
                            } else if let sourceSlot = worldState.pendingItemUseSlot {
                                if sourceSlot != item.id {
                                    engine.useItemOnItem(slot1: sourceSlot, slot2: item.id)
                                } else {
                                    engine.cancelItemUse()
                                }
                                selectedSlot = nil
                            } else {
                                selectedSlot = selectedSlot == item.id ? nil : item.id
                            }
                        }) {
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

            if let pendingSlot = worldState.pendingItemUseSlot {
                HStack(spacing: 6) {
                    Text("Use \(engine.itemUseLabel(for: pendingSlot)) with...")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#c8a951"))
                        .lineLimit(1)
                    Spacer()
                    Button("Cancel") { engine.cancelItemUse(); selectedSlot = nil }
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 6)
            }

            if let slot = selectedSlot, let item = worldState.inventory.first(where: { $0.id == slot }) {
                HStack(spacing: 6) {
                    Text(ItemNames.name(for: item.itemId)).font(.system(size: 9, weight: .medium)).foregroundColor(Color(hex: "#c8a951")).lineLimit(1)
                    Spacer()
                    Button(worldState.pendingSpellId == nil
                           ? (worldState.pendingItemUseSlot == nil ? "Use" : "Use with")
                           : "Cast") { engine.useItem(slot: slot); selectedSlot = nil }
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

    var body: some View {
        ScrollView {
            HStack {
                Text("Skills")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("Current/Base")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#c8a951"))
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                ForEach(worldState.skills) { skill in
                    HStack {
                        Text(RSCWorldState.skillShortName(for: skill.id))
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
