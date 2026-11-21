// Chat input, history tabs and messages: port of rsc-c's ui/message-tabs.c.

import Foundation

extension Mudclient {
    public func createMessageTabsPanel() {
        panelMessageTabs = makePanel(10)
        let p = panelMessageTabs!
        p.forceDesktopLists = true // panel_draw_text_list treats this panel as desktop
        let touch = isTouchLayout
        let x = 5 + (touch ? 5 : 0)
        let y = touch ? 100 : Mudclient.height - 22
        let width = Mudclient.width - 14 - (touch ? 14 : 0)
        controlTextListAll = p.addTextListInput(x: x, y: y, width: width, height: 14, font: .bold12,
                                                maxLength: ChatMessage.maxInputLength, isPassword: false,
                                                alternativeColour: true)
        let listX = x - 2
        let listY = y - 55 - (touch ? 13 : 0)
        let listWidth = Mudclient.width - 10
        let listHeight = 56 + (touch ? 14 : 0)
        controlTextListChat = p.addTextList(x: listX, y: listY, width: listWidth, height: listHeight, font: .bold12,
                                            maxEntries: 20, alternativeColour: true)
        controlTextListQuest = p.addTextList(x: listX, y: listY, width: listWidth, height: listHeight, font: .bold12,
                                             maxEntries: 20, alternativeColour: true)
        controlTextListPrivate = p.addTextList(x: listX, y: listY, width: listWidth, height: listHeight, font: .bold12,
                                               maxEntries: 20, alternativeColour: true)
        p.setFocus(controlTextListAll)
    }

    public func drawChatMessageTabs() {
        let compact = surface.width < Mudclient.vanillaWidth
        let touch = isTouchLayout
        let p = panelMessageTabs!
        let panelWidth = (compact ? surface.width : Mudclient.vanillaWidth) - 14 - (touch ? 14 : 0)
        p.controlWidth[controlTextListAll] = panelWidth
        p.controlWidth[controlTextListChat] = panelWidth + 4
        p.controlWidth[controlTextListQuest] = panelWidth + 4
        p.controlWidth[controlTextListPrivate] = panelWidth + 4

        var x = 0
        var y = surface.height - 16 + (compact ? 1 : 0)
        let buttonWidth = compact ? Int(Float(surface.width) * 0.245) : 100
        if touch {
            surface.drawSprite(x: x, y: y + 4, id: spriteMedia + 22)
        } else if compact {
            surface.drawSpriteTransformMask(x: x, y: y, width: surface.width + buttonWidth, height: 15,
                                            id: spriteMedia + Mudclient.hbarSpriteOffset, maskColour: 0, skinColour: 0,
                                            skewX: 0, flip: false)
        } else {
            surface.drawSprite(x: x, y: y, id: spriteMedia + Mudclient.hbarSpriteOffset)
        }
        if !compact && surface.width > Mudclient.hbarWidth {
            for i in 0..<(surface.width / Mudclient.hbarWidth) {
                surface.drawSprite(x: x + Mudclient.hbarWidth + Mudclient.hbarWidth * i, y: y + 4, id: spriteMedia + 22)
            }
            if !touch {
                surface.drawLineHorizontal(x: 503, y: surface.height - 14, width: surface.width - 503, colour: Colour.black)
                surface.drawLineHorizontal(x: 503, y: surface.height - 13, width: surface.width - 503, colour: Colour.black)
            }
        }
        if !touch && !compact && options.wikiLookup != 0 && options.versionMedia > 42 {
            surface.drawBox(x: x + 416, y: y + 3, width: 84, height: 9, colour: Colour.messageTabWiki)
            surface.drawBox(x: x + 414, y: y + 7, width: 88, height: 5, colour: Colour.messageTabWiki)
            surface.drawBox(x: x + 413, y: y + 8, width: 90, height: 3, colour: Colour.messageTabWiki)
        }
        if touch {
            x = 9
            y = 24
            for i in 0..<(4 + (compact ? 0 : 1)) {
                let bx = x + i * buttonWidth + (i == 4 ? 1 : 0)
                let by = y - 13
                surface.drawSpriteScaleMask(x: bx, y: by, width: buttonWidth - 10, height: 19, id: spriteMedia + 39,
                                            colour: i == 4 && options.wikiLookup == 0 ? 0xff1b00 : 0x00c1ff)
                if options.wikiLookup != 0 && i == 4 {
                    surface.drawBox(x: bx + 4, y: by + 4, width: buttonWidth - 18, height: 12, colour: 0x3a779d)
                }
            }
        } else {
            y = surface.height - 6 + (compact ? 1 : 0)
        }
        x = Int(Float(buttonWidth) * 0.54)
        func colour(_ tab: MessageTab, _ flash: Int) -> Int32 {
            var c = messageTabSelected == tab ? Colour.messageTabOrange : Colour.messageTabPurple
            if flash % 30 > 15 { c = Colour.messageTabRed }
            return c
        }
        surface.drawStringCentre(compact ? "All" : "All messages", x: x, y: y, font: .regular11,
                                 colour: colour(.all, messageTabFlashAll))
        surface.drawStringCentre(compact ? "Chat" : "Chat history", x: x + buttonWidth + 1, y: y, font: .regular11,
                                 colour: colour(.chat, messageTabFlashHistory))
        surface.drawStringCentre(compact ? "Quest" : "Quest history", x: x + buttonWidth * 2 + 1, y: y,
                                 font: .regular11, colour: colour(.quest, messageTabFlashQuest))
        surface.drawStringCentre(compact ? "Private" : "Private history", x: x + buttonWidth * 3 + 1, y: y,
                                 font: .regular11, colour: colour(.private, messageTabFlashPrivate))
        if !compact && (options.versionMedia > 42 || options.wikiLookup != 0) {
            surface.drawStringCentre(options.wikiLookup != 0 ? "Wiki lookup" : "Report abuse", x: x + buttonWidth * 4 + 3,
                                     y: y, font: .regular11,
                                     colour: selectedWiki ? Colour.messageTabOrange : Colour.white)
        }
    }

    public func drawChatMessageTabsPanel() {
        let touch = isTouchLayout
        if messageTabSelected == .all {
            let x = 5 + (touch ? 5 : 0)
            let y = touch ? 91 : surface.height - 30
            for i in 0..<Mudclient.messageHistoryLength where messageHistoryTimeout[i] > 0 {
                surface.drawString(messageHistory[i], x: x, y: y - i * 12, font: .bold12, colour: Colour.yellow)
            }
        }
        let p = panelMessageTabs!
        p.hide(controlTextListChat)
        p.hide(controlTextListQuest)
        p.hide(controlTextListPrivate)
        switch messageTabSelected {
        case .chat: p.show(controlTextListChat)
        case .quest: p.show(controlTextListQuest)
        case .private: p.show(controlTextListPrivate)
        case .all: break
        }
        Panel.textListEntryHeightMod = 2
        p.drawPanel()
        Panel.textListEntryHeightMod = 0
        if touch {
            var bx = 9, by = 108
            if options.touchKeyboardRight != 0 {
                bx = surface.width - 50
                by = surface.height - 265
            }
            surface.drawSprite(x: bx, y: by, id: spriteMedia + 40)
        }
    }

    public func sendCommandString(_ command: String) {
        guard let ps = packetStream else { return }
        ps.newPacket(ClientOpcode.command)
        ps.putString(command)
        ps.sendPacket()
    }

    public func sendChatMessage(_ encoded: [UInt8]) {
        guard let ps = packetStream else { return }
        ps.newPacket(ClientOpcode.chat)
        ps.putBytes(encoded)
        ps.sendPacket()
    }

    public func handleMessageTabsInput() {
        let touch = isTouchLayout
        let compact = surface.width < Mudclient.vanillaWidth
        let scale: Float = compact ? Float(surface.width) / Float(Mudclient.minWidth) : 1
        let barMinY = touch ? 0 : surface.height - 16
        let barMaxY = touch ? 30 : surface.height
        let barMaxX = touch ? Mudclient.hbarWidth : surface.width
        let p = panelMessageTabs!

        if lastMouseButtonDown == 1 && mouseX <= barMaxX && mouseY > barMinY && mouseY <= barMaxY {
            func edge(_ c: Float, _ v: Int) -> Int { compact ? Int(c * scale) : v }
            if mouseX > edge(12, 15) && mouseX < edge(75, 96) {
                messageTabSelected = .all
            } else if mouseX > edge(89, 110) && mouseX < edge(151, 194) {
                messageTabSelected = .chat
                p.controlListPosition[controlTextListChat] = 999_999
            } else if mouseX > edge(168, 215) && mouseX < edge(230, 295) {
                messageTabSelected = .quest
                p.controlListPosition[controlTextListQuest] = 999_999
            } else if mouseX > edge(246, 318) && mouseX < edge(308, 395) {
                messageTabSelected = .private
                p.controlListPosition[controlTextListPrivate] = 999_999
            } else if !compact && mouseX > 417 && mouseX < 497 {
                if options.wikiLookup != 0 { selectedWiki.toggle() }
            }
            lastMouseButtonDown = 0
            mouseButtonDown = 0
        }

        if touch {
            var kx = 9, ky = 108
            if options.touchKeyboardRight != 0 {
                kx = surface.width - 50
                ky = 100
            }
            p.handleMouse(x: Mudclient.finger1X, y: Mudclient.finger1Y, lastButton: lastMouseButtonDown,
                          isDown: Mudclient.finger1Down, scrollDelta: mouseScrollDelta)
            let chatInput = p.text(controlTextListAll)
            let inputX = 11
            let inputWidth = min(surface.width - inputX, Mudclient.hbarWidth)
            let triggerWidth = max(surface.textWidth(chatInput, font: .bold12), 32)
            let inputY = 93, inputHeight = 15
            let withinInput = mouseX <= inputX + triggerWidth && mouseY >= inputY - 8 && mouseY <= inputY + inputHeight + 4
            let withinButton = mouseX >= kx && mouseX <= kx + surface.spriteWidth[spriteMedia + 40] && mouseY >= ky &&
                mouseY <= ky + surface.spriteHeight[spriteMedia + 40]
            if !showRightClickMenu && lastMouseButtonDown == 1 && (withinInput || withinButton) {
                triggerKeyboard(text: chatInput, isPassword: false, x: inputX, y: inputY, width: inputWidth,
                                height: inputHeight, font: .bold12, isCentred: false)
                lastMouseButtonDown = 0
            }
        } else {
            p.handleMouse(x: mouseX, y: mouseY, lastButton: lastMouseButtonDown, isDown: mouseButtonDown,
                          scrollDelta: mouseScrollDelta)
        }

        let listWidth = (compact ? surface.width : Mudclient.vanillaWidth) - (touch ? 14 : 0)
        let minScrollY = touch ? 0 : surface.height - 78
        let maxScrollY = touch ? 102 : surface.height
        if messageTabSelected != .all && mouseX >= listWidth - 18 && mouseX < listWidth + 1 && mouseY >= minScrollY &&
            mouseY <= maxScrollY {
            lastMouseButtonDown = 0
        }

        if p.isClicked(controlTextListAll) {
            let message = p.text(controlTextListAll)
            if message.hasPrefix("::") {
                let command = String(message.dropFirst(2))
                let lower = command.lowercased()
                if lower.hasPrefix("closecon") {
                    packetStream?.close()
                } else if lower.hasPrefix("logout") {
                    closeConnection()
                } else if lower.hasPrefix("lostcon") {
                    lostConnection()
                } else if lower.hasPrefix("displayfps") {
                    options.displayFps = options.displayFps == 0 ? 1 : 0
                } else {
                    sendCommandString(command)
                }
            } else {
                let encoded = ChatMessage.encode(message)
                sendChatMessage(encoded)
                let decoded = ChatMessage.decode(encoded, offset: 0, length: encoded.count)
                localPlayer.messageTimeout = 150
                localPlayer.message = decoded
                showMessage("\(localPlayer.name): \(decoded)", .chat)
            }
            p.updateText(controlTextListAll, "")
        }

        if messageTabSelected == .all {
            for i in 0..<5 where messageHistoryTimeout[i] > 0 { messageHistoryTimeout[i] -= 1 }
        }
    }

    public func decrementMessageFlash() {
        if messageTabFlashAll > 0 { messageTabFlashAll -= 1 }
        if messageTabFlashHistory > 0 { messageTabFlashHistory -= 1 }
        if messageTabFlashQuest > 0 { messageTabFlashQuest -= 1 }
        if messageTabFlashPrivate > 0 { messageTabFlashPrivate -= 1 }
    }

    public func showMessage(_ text: String, _ type: MessageType) {
        var message = Surface.bytes(text)
        if type == .chat || type == .bor || type == .private {
            while message.count > 5 && message[0] == 64 && message[4] == 64 { message.removeFirst(5) }
            if let colon = message.lastIndex(of: 58) {
                let name = String(decoding: message[..<colon], as: Latin1.self)
                let encoded = ClientUtil.encodeUsername(name)
                for i in 0..<ignoreListCount where ignoreList[i] == encoded { return }
            }
        }

        let compact = surface.width < Mudclient.vanillaWidth
        let maxTextWidth = (compact ? surface.width : Mudclient.width) - 15
        if compact && surface.textWidth(bytes: message, font: .bold12) >= maxTextWidth {
            var message1 = [UInt8]()
            var lastSpace = -1
            var lastColour: [UInt8] = []
            for i in 0..<message.count {
                message1.append(message[i])
                if message[i] == 32 { lastSpace = i }
                if message[i] == 64 && message.count - i >= 4 && i + 4 < message.count && message[i + 4] == 64 {
                    lastColour = Array(message[(i + 1)..<(i + 4)])
                }
                if surface.textWidth(bytes: message1, font: .bold12) >= maxTextWidth {
                    let position = lastSpace == -1 ? i : lastSpace
                    message1 = Array(message1[..<position])
                    showMessage(String(decoding: message1, as: Latin1.self), type)
                    var message2 = [UInt8]()
                    if message1.first == 64 { message2 += message1.prefix(5) }
                    if !lastColour.isEmpty { message2 += [64] + lastColour + [64] }
                    if position + 1 < message.count { message2 += message[(position + 1)...] }
                    showMessage(String(decoding: message2, as: Latin1.self), type)
                    return
                }
            }
            return
        }

        let plain = String(decoding: message, as: Latin1.self)
        let coloured: String
        switch type {
        case .chat: coloured = "@yel@" + plain
        case .game, .bor: coloured = "@whi@" + plain
        case .private: coloured = "@cya@" + plain
        default: coloured = plain
        }

        if messageTabSelected != .all {
            if type == .bor || type == .game { messageTabFlashAll = Mudclient.messageFlashTime }
            if type == .chat && messageTabSelected != .chat { messageTabFlashHistory = Mudclient.messageFlashTime }
            if type == .quest && messageTabSelected != .quest { messageTabFlashQuest = Mudclient.messageFlashTime }
            if type == .private && messageTabSelected != .private { messageTabFlashPrivate = Mudclient.messageFlashTime }
            if type == .game && messageTabSelected != .all { messageTabSelected = .all }
            if type == .private && messageTabSelected != .private && messageTabSelected != .all {
                messageTabSelected = .all
            }
        }

        for i in stride(from: Mudclient.messageHistoryLength - 1, to: 0, by: -1) {
            messageHistory[i] = messageHistory[i - 1]
            messageHistoryTimeout[i] = messageHistoryTimeout[i - 1]
        }
        messageHistory[0] = String(coloured.prefix(254))
        messageHistoryTimeout[0] = 300

        let p = panelMessageTabs!
        func add(_ control: Int) {
            let flash = p.controlListPosition[control] == p.controlListEntryCount[control] - 4
            p.addListEntryWrapped(control, text: coloured, flash: flash)
        }
        switch type {
        case .chat: add(controlTextListChat)
        case .quest: add(controlTextListQuest)
        case .private: add(controlTextListPrivate)
        default: break
        }
    }

    public func showServerMessage(_ message: String) {
        let prefix = message.prefix(5).lowercased()
        if prefix == "@bor@" {
            showMessage(message, .bor)
        } else if prefix == "@que@" {
            showMessage("@whi@" + message, .quest)
        } else if prefix == "@pri@" {
            showMessage(message, .private)
        } else {
            showMessage(message, .game)
        }
    }
}
