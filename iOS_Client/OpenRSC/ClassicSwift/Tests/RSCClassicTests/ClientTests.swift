import XCTest
@testable import RSCClassic

/// Replays tools/clientdump.c: starts the client like mudclient_run (jagex.jag,
/// then startGame) and drives the login screens, options dialog, character
/// designer and chat tabs, hashing every frame and every loaded sprite.
/// On a mismatch the Swift frame is written to $TMPDIR/rsc-swift-frames/<step>.raw.
final class ClientTests: XCTestCase {
    private final class NullHost: MudclientHost {
        func present(_ mud: Mudclient) {}
        func triggerKeyboard(text: String, isPassword: Bool, x: Int, y: Int, width: Int, height: Int,
                             font: FontStyle, isCentred: Bool) {}
        func playSound(_ pcm: [Int16]) {}
    }

    private var lines: [String] = []
    private var golden: [String] = []
    private var mud: Mudclient!

    private func step(_ name: String) {
        let bytes = mud.surface.pixelBuffer.withMemoryRebound(to: UInt8.self) { Array($0) }
        lines.append("step \(name) \(fnv1a(bytes))")
        if let expected = golden.first(where: { $0.hasPrefix("step \(name) ") }), expected != lines.last {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rsc-swift-frames")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? Data(bytes).write(to: dir.appendingPathComponent("\(name).raw"))
        }
    }

    private func sprite(_ id: Int) {
        let s = mud.surface!
        let area = s.spriteWidth[id] * s.spriteHeight[id]
        let hc = s.spriteColours[id].map { fnv1a(Array($0.prefix(area))) } ?? 0
        let hp = s.spritePixels[id].map { px in fnv1a(px.prefix(area).flatMap { v -> [UInt8] in
            let u = UInt32(bitPattern: v)
            return [UInt8(u & 0xff), UInt8(u >> 8 & 0xff), UInt8(u >> 16 & 0xff), UInt8(u >> 24)]
        }) } ?? 0
        lines.append("sprite \(id) \(s.spriteWidth[id]) \(s.spriteHeight[id]) \(s.spriteWidthFull[id]) \(s.spriteHeightFull[id]) \(s.spriteTranslateX[id]) \(s.spriteTranslateY[id]) \(s.spriteTranslate[id] ? 1 : 0) \(hc) \(hp)")
    }

    private func click(_ x: Int, _ y: Int) {
        mud.mouseX = x; mud.mouseY = y; mud.lastMouseButtonDown = 1; mud.mouseButtonDown = 1
        mud.handleLoginScreenInput()
        mud.lastMouseButtonDown = 0; mud.mouseButtonDown = 0
        mud.handleLoginScreenInput()
    }

    private func draw(_ name: String) { mud.drawLoginScreens(); step(name) }

    private func server() { lines.append("server \(mud.server) \(mud.port)") }

    private func printOptions() {
        lines.append("options \(mud.options.idleLogout) \(mud.options.members) \(mud.options.zoomCamera)")
    }

    func testClientMatchesCEngine() throws {
        golden = try goldenLines("client.txt")
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("rsc-client-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: config) }

        CRandom.shared.seed(1234)
        let options = Options()
        options.fileURL = config.appendingPathComponent("options.ini")
        let host = NullHost()
        mud = Mudclient(cacheDirectory: TestPaths.cache, options: options)
        mud.host = host
        mud.createSurface(width: 512, height: 346)

        mud.loadJagex(); step("jagex")
        mud.drawLoadingProgress(42, "Loading something - 42%"); step("loading42")
        mud.startGame(); step("started")

        lines.append("models \(mud.gameData.modelNames.count) anims \(mud.gameData.animations.count)"
                     + mud.gameData.animations.map { " \($0.fileId)" }.joined())
        server()
        for i in 0..<mud.surface.limit where mud.surface.spriteWidth[i] != 0 || mud.surface.spriteColours[i] != nil
            || mud.surface.spritePixels[i] != nil {
            sprite(i)
        }

        for t in [0, 200, 420, 700, 1100, 1450, 1530] { mud.loginTimer = t; draw("welcome_\(t)") }
        mud.loginTimer = 0

        click(256, 290); draw("existing")
        mud.panelLoginExistingUser.updateText(mud.controlLoginUsername, "Zezima")
        mud.panelLoginExistingUser.updateText(mud.controlLoginPassword, "hunter2")
        draw("existing_typed")
        mud.showLoginScreenStatus("Invalid username or password.", "Try again, or create a new account")
        step("existing_status")
        click(410, 280); draw("cancelled")

        click(412, 313); draw("worlds")
        click(150, 260); draw("worlds_pick")
        server()
        click(476, 313); draw("worlds_back")
        server()

        click(476, 313); draw("options")
        for (t, p) in [(216, 81), (296, 81), (376, 81), (136, 81)].enumerated() {
            click(p.0, p.1); mud.mouseX = 0; mud.mouseY = 0; draw("options_tab\(t)")
        }
        for p in [(173, 125), (338, 125), (219, 105)] { click(p.0, p.1) }
        mud.mouseX = 180; mud.mouseY = 274; draw("options_hover")
        printOptions()
        click(180, 274); mud.mouseX = 0; mud.mouseY = 0; draw("confirm")
        click(296, 193); draw("confirm_ok")
        printOptions()
        click(368, 274); draw("options_closed")

        mud.drawAppearancePanel(); step("appearance")
        mud.mouseX = 0; mud.mouseY = 0
        for p in [(256 - 54 - 40, 24 + 145), (256 + 54 + 40, 24 + 145), (256 - 54 - 40, 24 + 145 + 50),
                  (256 + 54 - 40, 24 + 145 + 50), (256 - 54 + 40, 24 + 145 + 100), (256 + 54 + 40, 24 + 145 + 100)] {
            mud.mouseX = p.0; mud.mouseY = p.1; mud.lastMouseButtonDown = 1; mud.mouseButtonDown = 1
            mud.handleAppearancePanelInput()
            mud.lastMouseButtonDown = 0; mud.mouseButtonDown = 0
            mud.handleAppearancePanelInput()
        }
        mud.drawAppearancePanel(); step("appearance_changed")
        lines.append("appearance \(mud.appearanceHeadType) \(mud.appearanceHeadGender) \(mud.appearanceBodyType) "
                     + "\(mud.appearanceHairColour) \(mud.appearanceTopColour) \(mud.appearanceSkinColour) \(mud.appearanceBottomColour)")

        mud.surface.blackScreen()
        mud.showMessage("Welcome to RuneScape!", .game)
        mud.showMessage("@que@You have completed a quest", .quest)
        mud.showMessage("Bob: hello there", .chat)
        mud.showServerMessage("@pri@Alice tells you: hi")
        mud.drawChatMessageTabs(); mud.drawChatMessageTabsPanel(); step("chat_all")
        mud.messageTabSelected = .chat; mud.surface.blackScreen()
        mud.drawChatMessageTabs(); mud.drawChatMessageTabsPanel(); step("chat_history")
        let encoded = ChatMessage.encode("Hello World! this is a TEST of 123 @#%")
        lines.append("chat \(encoded.count)" + encoded.map { " \($0)" }.joined()
                     + " " + ChatMessage.decode(encoded, offset: 0, length: encoded.count))

        compare()
    }

    private func compare() {
        var mismatches = 0
        for (i, (a, b)) in zip(lines, golden).enumerated() where a != b {
            mismatches += 1
            if mismatches <= 40 { print("line \(i + 1)\n  swift: \(a)\n  c:     \(b)") }
        }
        XCTAssertEqual(lines.count, golden.count, "line count")
        XCTAssertEqual(mismatches, 0, "\(mismatches) mismatched lines")
    }
}
