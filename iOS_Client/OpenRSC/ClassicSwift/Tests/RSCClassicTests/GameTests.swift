import XCTest
@testable import RSCClassic

/// Replays the server packets and game ticks recorded by tools/gamedump.c (a scripted session
/// in Lumbridge) through the Swift packet handler and compares the game state
/// dumped after each one with the C client's.
final class GameTests: XCTestCase {
    private final class NullHost: MudclientHost {
        func present(_ mud: Mudclient) {}
        func triggerKeyboard(text: String, isPassword: Bool, x: Int, y: Int, width: Int, height: Int,
                             font: FontStyle, isCentred: Bool) {}
        func playSound(_ pcm: [Int16]) {}
    }

    private var lines: [String] = []
    private var mud: Mudclient!

    func testPacketsMatchCEngine() throws {
        let golden = try goldenLines("game.txt")
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("rsc-game-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: config) }

        CRandom.shared.seed(1234)
        let options = Options()
        options.fileURL = config.appendingPathComponent("options.ini")
        let host = NullHost()
        mud = Mudclient(cacheDirectory: TestPaths.cache, options: options)
        mud.host = host
        mud.createSurface(width: 512, height: 346)
        mud.loadJagex()
        mud.startGame()
        mud.resetGame()
        dump()

        for line in golden {
            if line.hasPrefix("packet ") {
                let parts = line.split(separator: " ")
                let hex = Array(parts[2].utf8)
                var bytes = [UInt8]()
                var i = 0
                while i + 1 < hex.count {
                    bytes.append(UInt8(String(decoding: hex[i...i + 1], as: UTF8.self), radix: 16)!)
                    i += 2
                }
                lines.append(line)
                for (j, b) in bytes.enumerated() { mud.incomingPacket[j] = b }
                mud.handlePacket(opcode: Int(bytes[0]), size: bytes.count)
                dump()
            } else if line.hasPrefix("poke ") {
                let parts = line.split(separator: " ")
                let v = Int(parts[2])!
                switch parts[1] {
                case "death": mud.deathScreenTimeout = v
                case "rotation": mud.cameraRotation = v
                case "zoom": mud.cameraZoom = v
                case "roofs": mud.options.showRoofs = v
                case "fog": mud.options.fogOfWar = v
                case "appearance": mud.showAppearanceChange = v != 0
                default: XCTFail("unknown poke \(line)")
                }
                lines.append(line)
            } else if line.hasPrefix("tick ") {
                lines.append(line)
                for _ in 0..<Int(line.dropFirst(5))! { mud.handleInputs() }
            } else if line.hasPrefix("frame ") {
                frame(String(line.split(separator: " ")[1]), golden: line)
            } else if line.hasPrefix("mouse ") {
                let v = line.split(separator: " ").dropFirst().map { Int($0)! }
                lines.append(line)
                mud.mouseX = v[0]; mud.mouseY = v[1]
                mud.mouseButtonClick = 0; mud.mouseButtonDown = 0; mud.lastMouseButtonDown = v[2]
                Mudclient.finger1X = v[0]; Mudclient.finger1Y = v[1]; Mudclient.finger1Down = 0
                mud.handleInputs()
            } else if line.hasPrefix("ui ") {
                ui(String(line.split(separator: " ")[1]))
            }
        }

        var mismatches = 0
        for (i, (a, b)) in zip(lines, golden).enumerated() where a != b {
            mismatches += 1
            if mismatches <= 30 { print("line \(i + 1)\n  swift: \(a)\n  c:     \(b)") }
        }
        XCTAssertEqual(lines.count, golden.count, "line count")
        XCTAssertEqual(mismatches, 0, "\(mismatches) mismatched lines")
    }

    /// draw_scene in gamedump.c: the 3D view part of mudclient_draw_game.
    private func frame(_ name: String, golden: String) {
        mud.drawGameScene()
        let bytes = mud.surface.pixelBuffer.withMemoryRebound(to: UInt8.self) { Array($0) }
        let line = "frame \(name) \(fnv1a(bytes)) sprites \(mud.sceneSpriteCount) models \(mud.scene.modelCount) cam "
            + "\(mud.cameraAutoRotatePlayerX) \(mud.cameraAutoRotatePlayerY) \(mud.cameraRotation) \(mud.cameraZoom)"
        lines.append(line)
        if line != golden {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rsc-swift-frames")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? Data(bytes).write(to: dir.appendingPathComponent("\(name).raw"))
        }
    }

    private final class CaptureTransport: PacketTransport {
        func receive(into buffer: UnsafeMutableRawBufferPointer) -> Int { -1 }
        func send(_ buffer: UnsafeRawBufferPointer) -> Int { buffer.count }
        func close() {}
    }

    /// ui in gamedump.c: a full mudclient_draw_game frame, the menu it built and the packets it sent.
    private func ui(_ name: String) {
        let ps = PacketStream(transport: CaptureTransport(), rsa: RSA(exponentHex: "010001", modulusHex: "01")!)
        mud.packetStream = ps
        mud.drawGame()
        mud.packetStream = nil
        let m = mud!
        let bytes = m.surface.pixelBuffer.withMemoryRebound(to: UInt8.self) { Array($0) }
        lines.append("ui \(name) \(fnv1a(bytes)) tab \(m.showUITab) sub \(m.uiTabStatsSubTab) \(m.uiTabMagicSubTab) "
            + "\(m.uiTabSocialSubTab) spell \(m.selectedSpell) item \(m.selectedItemInventoryIndex) "
            + "rc \(m.showRightClickMenu ? 1 : 0) menu \(m.menuX) \(m.menuY) \(m.menuWidth) \(m.menuHeight) "
            + "wiki \(m.selectedWiki ? 1 : 0) social \(m.showDialogSocialInput) pw \(m.showChangePasswordStep) "
            + "cam \(m.cameraRotation) \(m.settingsCameraAuto) opts \(m.settingsMouseButtonOne) \(m.settingsBlockChat) "
            + "\(m.settingsBlockPrivate) \(m.settingsBlockTrade) \(m.settingsBlockDuel)")
        var menu = "menu \(m.menuItemsCount)"
        for i in 0..<m.menuItemsCount {
            let e = m.menuItems[m.menuIndices[i]]
            menu += " [\(e.type)|\(e.actionText)|\(e.targetText)]"
        }
        lines.append(menu)
        lines.append("sent " + ps.packetData[0..<ps.packetStart].map { String(format: "%02x", $0) }.joined())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rsc-swift-frames")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(bytes).write(to: dir.appendingPathComponent("\(name).raw"))
    }

    private func adjacencyHash() -> UInt32 {
        fnv1a(mud.world.objectAdjacency.flatMap { v -> [UInt8] in
            let u = UInt32(truncatingIfNeeded: v)
            return [UInt8(u & 0xff), UInt8(u >> 8 & 0xff), UInt8(u >> 16 & 0xff), UInt8(u >> 24)]
        })
    }

    private func h16(_ b: Buf<Int16>, _ n: Int) -> UInt32 {
        fnv1a((0..<n).flatMap { i -> [UInt8] in
            let u = UInt16(truncatingIfNeeded: b[i])
            return [UInt8(u & 0xff), UInt8(u >> 8)]
        })
    }

    private func character(_ tag: String, _ i: Int, _ c: GameCharacter?) {
        guard let c else { lines.append("\(tag) \(i) null"); return }
        let w = c.waypointCurrent
        var s = "\(tag) \(i) si \(c.serverIndex) id \(c.serverId) npc \(c.npcId) at \(c.currentX) \(c.currentY)"
        s += " step \(c.movingStep) wc \(w) wp \(c.waypointsX[w]) \(c.waypointsY[w]) anim \(c.currentAnimation) \(c.nextAnimation)"
        s += " name '\(c.name)' lvl \(c.level) col \(c.hairColour) \(c.topColour) \(c.bottomColour) \(c.skinColour)"
        s += " skull \(c.skullVisible) eq" + c.animations.map { " \($0)" }.joined()
        s += " msg \(c.messageTimeout) '\(c.message)' hit \(c.damageTaken) \(c.currentHits) \(c.maxHits) \(c.combatTimer)"
        s += " bubble \(c.bubbleTimeout) \(c.bubbleItem) proj \(c.incomingProjectileSprite) \(c.projectileRange)"
        s += " \(c.attackingPlayerServerIndex) \(c.attackingNpcServerIndex)"
        lines.append(s)
    }

    private func model(_ m: GameModel?) -> String {
        guard let m else { return " nomodel" }
        return " key \(m.key) base \(m.baseX) \(m.baseY) \(m.baseZ) rot \(m.orientationYaw) \(m.orientationPitch) \(m.orientationRoll)"
    }

    private func dump() {
        let m = mud!
        lines.append("region \(m.regionX) \(m.regionY) local \(m.localRegionX) \(m.localRegionY) plane \(m.planeWidth) "
            + "\(m.planeHeight) \(m.planeIndex) \(m.planeMultiplier) last \(m.lastPlaneIndex) bounds \(m.localLowerX) "
            + "\(m.localLowerY) \(m.localUpperX) \(m.localUpperY) alive \(m.world.playerAlive ? 1 : 0) "
            + "loading \(m.loadingArea ? 1 : 0) models \(m.scene.modelCount) adj \(adjacencyHash())")
        lines.append("players \(m.playerCount) known \(m.knownPlayerCount) local \(m.localPlayer.serverIndex)")
        for i in 0..<m.playerCount { character("player", i, m.players[i]) }
        lines.append("npcs \(m.npcCount) known \(m.knownNpcCount)")
        for i in 0..<m.npcCount { character("npc", i, m.npcs[i]) }
        for i in 0..<m.objectCount {
            let o = m.objects[i]
            lines.append("object \(i) \(o.x) \(o.y) \(o.id) \(o.direction)" + model(o.model))
        }
        for i in 0..<m.wallObjectCount {
            let w = m.wallObjects[i]
            var s = "wall \(i) \(w.x) \(w.y) \(w.id) \(w.direction)" + model(w.model)
            if let g = w.model {
                s += " v \(h16(g.vertexX, g.vertexCount)) \(h16(g.vertexY, g.vertexCount)) \(h16(g.vertexZ, g.vertexCount))"
                s += " ff \(g.faceFillFront[0]) \(g.faceFillBack[0])"
            }
            lines.append(s)
        }
        for i in 0..<m.groundItemCount {
            let g = m.groundItems[i]
            lines.append("item \(i) \(g.x) \(g.y) \(g.id) \(g.z)")
        }
        lines.append("inv \(m.inventoryItemsCount)" + (0..<m.inventoryItemsCount).map {
            " \(m.inventoryItemId[$0]):\(m.inventoryItemStackCount[$0]):\(m.inventoryEquipped[$0])" }.joined())
        var s = "skills" + (0..<Mudclient.playerSkillCount).map {
            " \(m.playerSkillCurrent[$0])/\(m.playerSkillBase[$0])/\(m.playerExperience[$0])" }.joined()
        s += " qp \(m.playerQuestPoints) fatigue \(m.statFatigue) \(m.fatigueSleeping) eq"
        s += m.playerStatEquipment.map { " \($0)" }.joined()
        s += " quests" + m.questComplete.map { "\($0)" }.joined()
        lines.append(s)
        s = "friends \(m.friendListCount)" + (0..<m.friendListCount).map { " \(m.friendList[$0]):\(m.friendListOnline[$0])" }.joined()
        s += " ignore \(m.ignoreListCount)" + (0..<m.ignoreListCount).map { " \(m.ignoreList[$0])" }.joined()
        lines.append(s)
        lines.append("messages" + (0..<Mudclient.messageHistoryLength).map {
            " [\(m.messageHistory[$0])|\(m.messageHistoryTimeout[$0])]" }.joined())
        s = "dialogs opt \(m.showOptionMenu ? 1 : 0) \(m.optionMenuCount)"
        s += (0..<min(m.optionMenuCount, 5)).map { " [\(m.optionMenuEntry[$0])]" }.joined()
        s += " welcome \(m.showDialogWelcome ? 1 : 0) \(m.welcomeLastIp) \(m.welcomeDaysAgo) \(m.welcomeRecoverySetDays)"
        s += " \(m.welcomeUnreadMessages) server \(m.showDialogServerMessage ? 1 : 0) \(m.serverMessageBoxTop ? 1 : 0)"
        s += " [\(m.serverMessage)] appearance \(m.showAppearanceChange ? 1 : 0) sleep \(m.isSleeping ? 1 : 0)"
        s += " death \(m.deathScreenTimeout) logout \(m.logoutTimeout) sysupd \(m.systemUpdate)"
        lines.append(s)
        s = "bank \(m.showDialogBank ? 1 : 0) \(m.bankItemCount) max \(m.bankItemsMax)"
        s += (0..<m.bankItemCount).map { " \(m.bankItems[$0]):\(m.bankItemsCount[$0])" }.joined()
        s += " shop \(m.showDialogShop ? 1 : 0) \(m.shopSellPriceMod) \(m.shopBuyPriceMod)"
        s += (0..<40).filter { m.shopItems[$0] != -1 }.map {
            " \($0)=\(m.shopItems[$0]):\(m.shopItemsCount[$0]):\(m.shopItemsPrice[$0])" }.joined()
        lines.append(s)
        s = "trade \(m.showDialogTrade ? 1 : 0) \(m.showDialogTradeConfirm ? 1 : 0) duel \(m.showDialogDuel ? 1 : 0)"
        s += " \(m.showDialogDuelConfirm ? 1 : 0) offerx \(m.showDialogOfferX ? 1 : 0) name '\(m.transactionRecipientName)'"
        s += " acc \(m.transactionRecipientAccepted) \(m.transactionAccepted) items"
        s += (0..<m.transactionRecipientItemCount).map {
            " \(m.transactionRecipientItems[$0]):\(m.transactionRecipientItemsCount[$0])" }.joined()
        s += " confirm \(m.transactionRecipientConfirmName)" + (0..<m.transactionRecipientConfirmItemCount).map {
            " \(m.transactionRecipientConfirmItems[$0]):\(m.transactionRecipientConfirmItemsCount[$0])" }.joined()
        s += " /" + (0..<m.transactionConfirmItemCount).map {
            " \(m.transactionConfirmItems[$0]):\(m.transactionConfirmItemsCount[$0])" }.joined()
        s += " duelopt \(m.duelOptionRetreat) \(m.duelOptionMagic) \(m.duelOptionPrayer) \(m.duelOptionWeapons)"
        lines.append(s)
        s = "misc prayers" + m.prayerOn.map { $0 ? "1" : "0" }.joined() + " bubbles \(m.magicBubbleCount)"
        s += (0..<m.magicBubbleCount).map {
            " \(m.magicBubbles[$0].x):\(m.magicBubbles[$0].y):\(m.magicBubbles[$0].type):\(m.magicBubbles[$0].time)" }.joined()
        s += " settings \(m.settingsCameraAuto) \(m.settingsMouseButtonOne) \(m.settingsSoundDisabled)"
        s += " \(m.settingsBlockChat) \(m.settingsBlockPrivate) \(m.settingsBlockTrade) \(m.settingsBlockDuel)"
        lines.append(s)
    }
}
