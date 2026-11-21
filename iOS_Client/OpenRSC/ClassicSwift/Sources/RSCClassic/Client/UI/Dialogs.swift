// Ports of the small rsc-c dialogs: ui/welcome.c, ui/server-message.c,
// ui/wilderness-warning.c, ui/option-menu.c and ui/combat-style.c.

import Foundation

extension Mudclient {
    static let welcomeHeight = 65, wildernessWarningHeight = 180

    // MARK: welcome.c

    func drawWelcome() {
        let compact = surface.width < 400
        let width = compact ? Mudclient.minWidth : 400
        var height = Mudclient.welcomeHeight
        if welcomeLastIp != 0 { height += 15 * 3 }
        let dialogX = surface.width / 2 - width / 2
        let dialogY = surface.height / 2 - height / 2
        surface.drawBox(x: dialogX, y: dialogY, width: width, height: height, colour: Colour.black)
        surface.drawBorder(x: dialogX, y: dialogY, width: width, height: height, colour: Colour.white)
        var y = dialogY + 20
        let x = surface.width / 2
        surface.drawStringCentre("Welcome to RuneScape \(loginUsername)", x: x, y: y, font: .bold14,
                                 colour: Colour.yellow)
        y += 30
        let daysAgo: String
        if welcomeDaysAgo <= 0 { daysAgo = "earlier today" }
        else if welcomeDaysAgo == 1 { daysAgo = "yesterday" }
        else { daysAgo = "\(welcomeDaysAgo) days ago" }
        if welcomeLastIp != 0 {
            surface.drawStringCentre("You last logged in \(daysAgo)", x: x, y: y, font: .bold12, colour: Colour.white)
            y += 15
            if welcomeLastIpString.isEmpty {
                welcomeLastIpString = ClientUtil.ipToString(Int32(truncatingIfNeeded: welcomeLastIp))
            }
            surface.drawStringCentre("from: \(welcomeLastIpString)", x: x, y: y, font: .bold12, colour: Colour.white)
            y += 15 * 2
        }
        var colour = Colour.white
        if mouseY > y - 12 && mouseY <= y && mouseX > dialogX + 50 && mouseX < dialogX + width - 50 {
            colour = Colour.red
        }
        surface.drawStringCentre("\(isTouch ? "Tap" : "Click") here to close window", x: x, y: y, font: .bold12,
                                 colour: colour)
        if mouseButtonClick == 1 {
            if colour == Colour.red { showDialogWelcome = false }
            if (mouseX < dialogX + 30 || mouseX > dialogX + width - 30) &&
                (mouseY < dialogY - height / 2 || mouseY > dialogY + height / 2) {
                showDialogWelcome = false
            }
        }
        mouseButtonClick = 0
    }

    // MARK: server-message.c

    func drawServerMessage() {
        let compact = surface.width < 400
        let width = compact ? Mudclient.minWidth : 400
        let dialogX = surface.width / 2
        var dialogY = surface.height / 2 - 6
        var height = serverMessageBoxTop ? 300 : 100
        if compact && serverMessageBoxTop {
            dialogY -= 2
            height = surface.height - 16
        }
        surface.drawBox(x: dialogX - width / 2, y: dialogY - height / 2, width: width, height: height,
                        colour: Colour.black)
        surface.drawBorder(x: dialogX - width / 2, y: dialogY - height / 2, width: width, height: height,
                           colour: Colour.white)
        if compact {
            let at = surface.paragraphHeight(serverMessage, font: .bold12, max: width - 40, maxHeight: 196)
            if at > -1 {
                let bytes = Surface.bytes(serverMessage)
                serverMessage = String(decoding: bytes[0..<(at - 1)], as: Latin1.self)
                serverMessageNext = at + 1 < bytes.count
                    ? String(decoding: bytes[(at + 1)...], as: Latin1.self) : ""
            }
        }
        let message = serverMessagePage == 0 ? serverMessage : serverMessageNext
        surface.drawParagraph(message, x: dialogX, y: dialogY - height / 2 + 20, font: .bold12, colour: Colour.white,
                              max: width - 40)
        let offsetY = dialogY - 10 + height / 2
        var colour = Colour.white
        let hoverRow = mouseY > offsetY - 12 && mouseY <= offsetY
        if compact {
            if serverMessagePage > 0 {
                let previousX = dialogX - width / 2 + 8
                if mouseX >= previousX && mouseX <= previousX + surface.textWidth("Previous", font: .bold12) && hoverRow {
                    colour = Colour.red
                    if mouseButtonClick == 1 { serverMessagePage = 0; mouseButtonClick = 0 }
                }
                surface.drawString("Previous", x: previousX, y: offsetY, font: .bold12, colour: colour)
                colour = Colour.white
            }
            if serverMessagePage == 0 && !serverMessageNext.isEmpty {
                let nextX = dialogX + width / 2 - surface.textWidth("Next", font: .bold12) - 8
                if mouseX >= nextX && mouseX <= nextX + surface.textWidth("Next", font: .bold12) && hoverRow {
                    colour = Colour.red
                    if mouseButtonClick == 1 { serverMessagePage = 1; mouseButtonClick = 0 }
                }
                surface.drawString("Next", x: nextX, y: offsetY, font: .bold12, colour: colour)
                colour = Colour.white
            }
        }
        let closeWidth = compact ? 100 : 150
        if hoverRow && mouseX > dialogX - closeWidth && mouseX < dialogX + closeWidth { colour = Colour.red }
        surface.drawStringCentre("\(isTouch ? "Tap" : "Click") here to close window", x: dialogX, y: offsetY,
                                 font: .bold12, colour: colour)
        if mouseButtonClick == 1 && (colour == Colour.red ||
            ((mouseX < dialogX - width / 2 || mouseX > dialogX + width / 2) &&
             (mouseY < dialogY - height / 2 || mouseY > dialogY + height / 2))) {
            serverMessagePage = 0
            showDialogServerMessage = false
        }
        mouseButtonClick = 0
    }

    // MARK: wilderness-warning.c

    func drawWildernessWarning() {
        let width = surface.width < 340 ? Mudclient.minWidth : 340
        let h = Mudclient.wildernessWarningHeight
        let dialogX = surface.width / 2 - width / 2
        let dialogY = surface.height / 2 - h / 2 - 6
        surface.drawBox(x: dialogX, y: dialogY, width: width, height: h, colour: Colour.black)
        surface.drawBorder(x: dialogX, y: dialogY, width: width, height: h, colour: Colour.white)
        let x = surface.width / 2
        var y = dialogY + 20
        func line(_ text: String, _ advance: Int) {
            y += advance
            surface.drawStringCentre(text, x: x, y: y, font: .bold12, colour: Colour.white)
        }
        surface.drawStringCentre("Warning! Proceed with caution", x: x, y: y, font: .bold14, colour: Colour.red)
        line("If you go much further north you will enter the", 26)
        line("wilderness. This a very dangerous area where", 13)
        line("other players can attack you!", 13)
        line("The further north you go the more dangerous it", 22)
        line("becomes, but the more treasure you will find.", 13)
        line("In the wilderness an indicator at the bottom-\(isTouch ? "left" : "right")", 22)
        line("of the screen will show the current level of danger", 13)
        y += 22
        let hover = mouseY > y - 12 && mouseY <= y && mouseX > x - 75 && mouseX < x + 75
        surface.drawStringCentre("\(isTouch ? "Tap" : "Click") here to close window", x: x, y: y, font: .bold12,
                                 colour: hover ? Colour.red : Colour.white)
        if mouseButtonClick != 0 {
            if hover { showWildernessWarning = 2 }
            if mouseX < dialogX || mouseX > dialogX + width || mouseY < dialogY || mouseY > dialogY + h {
                showWildernessWarning = 2
            }
            mouseButtonClick = 0
        }
    }

    // MARK: option-menu.c

    func drawOptionMenu() {
        let font: FontStyle = isTouch ? .bold14 : .bold12
        let fontHeight = isTouch ? 24 : 12
        let uiX = isTouch ? 12 : 6
        let uiY = isTouch ? 136 : 0
        func choose(_ i: Int) {
            guard let ps = packetStream else { return }
            ps.newPacket(ClientOpcode.chooseOption)
            ps.putByte(i)
            ps.sendPacket()
        }
        if options.optionNumbers != 0 {
            let keys = [key1, key2, key3, key4, key5]
            if let index = keys.firstIndex(of: true) {
                choose(index)
                showOptionMenu = false
                key1 = false; key2 = false; key3 = false; key4 = false; key5 = false
                return
            }
        }
        if mouseButtonClick != 0 {
            for i in 0..<optionMenuCount {
                let entry = optionMenuEntry[i]
                if mouseX < uiX - 6 || mouseX >= uiX - 6 + surface.textWidth(entry, font: font) ||
                    mouseY <= uiY + i * fontHeight || mouseY >= uiY + fontHeight + i * fontHeight {
                    continue
                }
                choose(i)
                break
            }
            mouseButtonClick = 0
            showOptionMenu = false
            return
        }
        for i in 0..<optionMenuCount {
            let entry = optionMenuEntry[i]
            var colour = Colour.cyan
            if mouseX > uiX - 6 && mouseX < uiX - 6 + surface.textWidth(entry, font: font) &&
                mouseY > uiY + i * fontHeight && mouseY < uiY + i * fontHeight + fontHeight {
                colour = Colour.red
            }
            surface.drawString(entry, x: uiX, y: uiY + fontHeight + i * fontHeight, font: font, colour: colour)
        }
    }

    // MARK: combat-style.c

    static let combatStyles = ["Controlled (+1 of each)", "Aggressive (+3 strength)", "Accurate (+3 attack)",
                               "Defensive (+3 defense)"]
    static let combatStylesCompact = ["Controlled (+1 each)", "Aggressive (+3 str.)", "Accurate (+3 att.)",
                                      "Defensive (+3 def.)"]

    func drawCombatStyle() {
        let compact = surface.width < 390
        let buttonHeight = compact ? 22 : 20
        let width = compact ? 106 : 175
        let uiX = isTouch ? 13 : 7
        let uiY = isTouch ? 140 : 15
        let count = Mudclient.combatStyles.count
        if mouseButtonClick != 0 && (compact ? showUITab != UITabs.inventory : true) {
            for i in 0..<(count + 1) {
                if i <= 0 || mouseX <= uiX || mouseX >= uiX + width || mouseY < uiY + i * buttonHeight ||
                    mouseY > uiY + i * buttonHeight + buttonHeight {
                    continue
                }
                combatStyle = i - 1
                mouseButtonClick = 0
                if let ps = packetStream {
                    ps.newPacket(ClientOpcode.combatStyle)
                    ps.putByte(combatStyle)
                    ps.sendPacket()
                }
                break
            }
        }
        for i in 0..<(count + 1) {
            let colour = i == combatStyle + 1 ? Colour.red : Colour.greyBE
            surface.drawBoxAlpha(x: uiX, y: uiY + i * buttonHeight, width: width, height: buttonHeight, colour: colour,
                                 alpha: 128)
            surface.drawLineHorizontal(x: uiX, y: uiY + i * buttonHeight, width: width, colour: Colour.black)
            surface.drawLineHorizontal(x: uiX, y: uiY + i * buttonHeight + buttonHeight, width: width,
                                       colour: Colour.black)
        }
        var y = 16
        if compact {
            surface.drawStringCentre("Combat style", x: uiX + width / 2, y: uiY + y, font: .bold12, colour: Colour.white)
        } else {
            surface.drawStringCentre("Select combat style", x: uiX + width / 2, y: uiY + y, font: .bold13,
                                     colour: Colour.white)
        }
        y += buttonHeight
        for i in 0..<count {
            if compact {
                surface.drawStringCentre(Mudclient.combatStylesCompact[i], x: uiX + width / 2, y: uiY + y - 1,
                                         font: .regular11, colour: Colour.black)
            } else {
                surface.drawStringCentre(Mudclient.combatStyles[i], x: uiX + width / 2, y: uiY + y, font: .bold13,
                                         colour: Colour.black)
            }
            y += buttonHeight
        }
    }
}
