// Port of rsc-c ui/options-tab.c: game, security and privacy options, logout,
// and the change password dialog.

import Foundation

public enum PasswordStep {
    public static let none = 0, new = 1, confirm = 2, mismatch = 3, finished = 4, short = 5, current = 6
}

extension Mudclient {
    static let changePasswordWidth = 300, changePasswordHeight = 60
    static let optionsWidth = 196, optionsLineBreak = 15

    private var soundVisible: Bool { options.members != 0 && options.lowmem == 0 }

    func sendPrivacySettings(chat: Int, privateChat: Int, trade: Int, duel: Int) {
        guard let ps = packetStream else { return }
        ps.newPacket(ClientOpcode.settingsPrivacy)
        ps.putByte(chat); ps.putByte(privateChat); ps.putByte(trade); ps.putByte(duel)
        ps.sendPacket()
    }

    func drawChangePassword() {
        let w = Mudclient.changePasswordWidth, h = Mudclient.changePasswordHeight
        let dialogX = surface.width / 2 - w / 2
        let dialogY = surface.height / 2 - h / 2 + 7
        let x = surface.width / 2
        var y = dialogY + 22
        if mouseButtonClick != 0 {
            mouseButtonClick = 0
            if mouseX >= dialogX && mouseX <= dialogX + w && mouseY >= y + 4 && mouseY <= y + 34 &&
                (showChangePasswordStep == PasswordStep.current || showChangePasswordStep == PasswordStep.confirm ||
                 (showAppearanceChange ? 1 : 0) == PasswordStep.new) {
                triggerKeyboard(text: inputTextCurrent, isPassword: true, x: dialogX - 2, y: y + 6, width: w,
                                height: 30, font: .bold14, isCentred: true)
            } else if mouseX < dialogX || mouseY < dialogY || mouseX > w + dialogX || mouseY > h + dialogY {
                showChangePasswordStep = PasswordStep.none
                return
            }
        }
        surface.drawBox(x: dialogX, y: dialogY, width: w, height: h, colour: Colour.black)
        surface.drawBorder(x: dialogX, y: dialogY, width: w, height: h, colour: Colour.white)

        func lines(_ top: String, _ bottom: String) {
            surface.drawStringCentre(top, x: x, y: y, font: .bold14, colour: Colour.white)
            y += 25
            surface.drawStringCentre(bottom, x: x, y: y, font: .bold14, colour: Colour.white)
        }
        let masked = String(repeating: "X", count: Surface.bytes(inputTextCurrent).count) + "*"

        switch showChangePasswordStep {
        case PasswordStep.current:
            lines("Please enter your current password", masked)
            if !inputTextFinal.isEmpty {
                changePasswordOld = inputTextFinal
                inputTextCurrent = ""
                inputTextFinal = ""
                showChangePasswordStep = 1
            }
        case PasswordStep.new:
            lines("Please enter your new password", masked)
            if !inputTextFinal.isEmpty {
                changePasswordNew = inputTextFinal
                inputTextCurrent = ""
                inputTextFinal = ""
                showChangePasswordStep = Surface.bytes(changePasswordNew).count >= 5
                    ? PasswordStep.confirm : PasswordStep.short
            }
        case PasswordStep.confirm:
            lines("Enter password again to confirm", masked)
            if !inputTextFinal.isEmpty {
                if inputTextFinal.lowercased() == changePasswordNew.lowercased() {
                    showChangePasswordStep = PasswordStep.finished
                    changePassword(old: changePasswordOld, new: changePasswordNew)
                } else {
                    showChangePasswordStep = PasswordStep.mismatch
                }
            }
        case PasswordStep.mismatch:
            lines("Passwords do not match!", "Press any key to close")
        case PasswordStep.finished:
            lines("Ok, your request has been sent", "Press any key to close")
        case 5:
            lines("Password must be at", "least 5 letters long")
        default:
            break
        }
    }

    func drawUITabOptions(noMenus: Bool) {
        let ow = Mudclient.optionsWidth, lb = Mudclient.optionsLineBreak
        var uiX = surface.width - ow - 3
        var uiY = UITabs.buttonSize + 1
        var height = 265
        let compact = isTouch || surface.height < height + lb * 2 + uiY
        let playerX = regionX + localRegionX, playerY = regionY + localRegionY
        let skipTutorial = options.skipTutorial != 0 && playerX >= 190 && playerX <= 240 && playerY >= 720 &&
            playerY <= 770
        if compact { height = 152 }
        if options.showAdditionalOptions != 0 && soundVisible { height += lb }
        if skipTutorial { height += lb }
        if isTouch {
            height = 198
            uiX = uiTabsTouchX - ow - 1
            uiY = uiTabsTouchY + UITabs.touchHeight - height - 2
        }
        let notTouch = isTouch ? 0 : 1
        if options.versionMedia >= 59 {
            drawUITabLabel(selectedTab: UITabs.options, width: ow + notTouch, x: uiX - notTouch,
                           y: uiY - UITabs.labelHeight)
        }
        uiTabMinX = uiX
        uiTabMaxX = surface.width
        uiTabMinY = 0
        uiTabMaxY = uiY + height + 10
        if isTouch {
            uiTabMaxX = uiX + ow
            uiTabMinY = uiY - UITabs.labelHeight
            uiTabMaxY = uiY + height
        }

        var controlsHeight = compact ? 48 : 65
        if isTouch { controlsHeight += 9 }
        if options.showAdditionalOptions != 0 && soundVisible { controlsHeight += lb }
        surface.drawBoxAlpha(x: uiX, y: uiY, width: ow, height: controlsHeight, colour: Colour.greyB5, alpha: 160)
        var securityHeight = compact ? 15 : 65
        if isTouch { securityHeight += lb - 4 }
        surface.drawBoxAlpha(x: uiX, y: uiY + controlsHeight, width: ow, height: securityHeight, colour: Colour.greyC9,
                             alpha: 160)
        var privacyHeight = compact ? 60 : 95
        if isTouch { privacyHeight += lb - 4 }
        surface.drawBoxAlpha(x: uiX, y: uiY + securityHeight + controlsHeight, width: ow, height: privacyHeight,
                             colour: Colour.greyB5, alpha: 160)
        let hideLogoutLabel = isTouch && skipTutorial
        var logoutHeight = compact ? 29 : 40
        if !hideLogoutLabel && skipTutorial { logoutHeight += lb }
        surface.drawBoxAlpha(x: uiX, y: uiY + privacyHeight + securityHeight + controlsHeight, width: ow,
                             height: logoutHeight, colour: Colour.greyC9, alpha: 160)

        let x = uiX + 3
        var y = uiY + lb
        func hover(_ y: Int) -> Bool { mouseX > x && mouseX < x + ow && mouseY > y - 12 && mouseY < y + 4 }
        func text(_ s: String, _ x: Int, _ y: Int, _ colour: Int32, _ font: FontStyle = .bold12) {
            surface.drawString(s, x: x, y: y, font: font, colour: colour)
        }

        if !compact {
            text("Game options - click to toggle", x, y, Colour.black)
            y += lb
        } else if isTouch {
            y -= 4
            text("Game options - tap to toggle", x, y, Colour.black)
            y += lb - 3
        }
        text("Camera angle mode - \(settingsCameraAuto != 0 ? "@gre@Auto" : "@red@Manual")", x, y, Colour.white)
        y += lb
        text("Mouse buttons - \(settingsMouseButtonOne != 0 ? "@red@One" : "@gre@Two")", x, y, Colour.white)
        y += lb
        if soundVisible {
            text("Sound effects - \(settingsSoundDisabled != 0 ? "@red@off" : "@gre@on")", x, y, Colour.white)
            y += lb
        }
        if options.showAdditionalOptions != 0 {
            text("Additional options...", x, y, hover(y) ? Colour.yellow : Colour.white)
        }
        if options.showAdditionalOptions != 0 || !soundVisible { y += lb }

        if options.accountManagement != 0 {
            if !compact {
                y += 5
                text("Security settings", x, y, Colour.black)
                y += lb
            }
            if isTouch {
                y -= 1
                text("Security settings", x, y, Colour.black)
                y += lb - 3
            }
            text("Change password", x, y, hover(y) ? Colour.yellow : Colour.white)
            y += lb
            if !compact { y += lb * 2 }
        } else {
            if !compact {
                text("To change your contact details,", x, y, Colour.white, .regular11)
                y += lb
                text("password, recovery questions, etc..", x, y, Colour.white, .regular11)
                y += lb
                text("Please select 'account management'", x, y, Colour.white, .regular11)
                y += lb
                let location = referId == 0 ? "from the runescape.com front page"
                    : referId == 1 ? "from the link below the gamewindow" : "from the runescape front webpage"
                text(location, x, y, Colour.white, .regular11)
                y += lb + 5
            } else {
                y += lb
            }
        }

        if !compact {
            text("Privacy settings. Will be applied to", x, y, Colour.black)
            y += lb
            text("all people not on your friends list", x, y, Colour.black)
            y += lb
        }
        if isTouch {
            y -= 1
            text("Privacy settings", uiX + 3, y, Colour.black)
            y += lb - 3
        }
        func onOff(_ v: Int) -> String { v == 0 ? "@red@<off>" : "@gre@<on>" }
        text("Block chat messages: \(onOff(settingsBlockChat))", uiX + 3, y, Colour.white)
        y += lb
        text("Block private messages: \(onOff(settingsBlockPrivate))", uiX + 3, y, Colour.white)
        y += lb
        text("Block trade requests: \(onOff(settingsBlockTrade))", uiX + 3, y, Colour.white)
        y += lb
        if options.members != 0 {
            text("Block duel requests: \(onOff(settingsBlockDuel))", uiX + 3, y, Colour.white)
        }
        y += lb + (compact ? 0 : 5)
        if skipTutorial {
            text("Skip the tutorial", x, y, hover(y) ? Colour.yellow : Colour.white)
            y += compact ? lb - 1 : lb + 5
        }
        if !hideLogoutLabel {
            text("Always logout when you finish", x, y, Colour.black)
            y += lb - (compact ? 2 : 0)
        }
        text("Click here to logout", uiX + 3, y, hover(y) ? Colour.yellow : Colour.white)

        guard noMenus else { return }
        let mx = mouseX - uiX, my = mouseY - uiY
        guard mx >= 0 && my >= 0 && mx < 196 && my < height else { return }
        y = uiY + lb + (compact ? 0 : lb) + (isTouch ? lb - 7 : 0)
        let click = mouseButtonClick == 1
        func sendGame(_ setting: Int, _ value: Int) {
            guard let ps = packetStream else { return }
            ps.newPacket(ClientOpcode.settingsGame)
            ps.putByte(setting); ps.putByte(value)
            ps.sendPacket()
        }
        if hover(y) && click {
            settingsCameraAuto = settingsCameraAuto != 0 ? 0 : 1
            sendGame(0, settingsCameraAuto)
        }
        y += lb
        if hover(y) && click {
            settingsMouseButtonOne = settingsMouseButtonOne != 0 ? 0 : 1
            sendGame(2, settingsMouseButtonOne)
        }
        y += lb
        if soundVisible && hover(y) && click {
            settingsSoundDisabled = settingsSoundDisabled != 0 ? 0 : 1
            sendGame(3, settingsSoundDisabled)
        }
        if soundVisible { y += lb }
        if options.showAdditionalOptions != 0 && hover(y) && click { showAdditionalOptions = true }
        if options.showAdditionalOptions != 0 || !soundVisible { y += lb }
        if !compact { y += lb + 5 } else if isTouch { y += lb - 4 }
        if options.accountManagement != 0 && hover(y) && click {
            showChangePasswordStep = PasswordStep.current
            inputTextCurrent = ""
            inputTextFinal = ""
        }
        var changed = false
        y += compact ? lb : lb * 5
        if isTouch { y += lb - 4 }
        if hover(y) && click { settingsBlockChat = 1 - settingsBlockChat; changed = true }
        y += lb
        if hover(y) && click { settingsBlockPrivate = 1 - settingsBlockPrivate; changed = true }
        y += lb
        if hover(y) && click { settingsBlockTrade = 1 - settingsBlockTrade; changed = true }
        y += lb
        if options.members != 0 && hover(y) && click { settingsBlockDuel = 1 - settingsBlockDuel; changed = true }
        if changed {
            sendPrivacySettings(chat: settingsBlockChat, privateChat: settingsBlockPrivate, trade: settingsBlockTrade,
                                duel: settingsBlockDuel)
        }
        y += lb + (compact ? 0 : 5)
        if skipTutorial {
            if hover(y) && click {
                confirmTextTop = "Are you sure you wish to skip the tutorial"
                confirmTextBottom = "and teleport to Lumbridge?"
                confirmType = .tutorial
                showDialogConfirm = true
            }
            y += compact ? lb - 1 : lb + 5
        }
        if !hideLogoutLabel { y += lb - (compact ? 2 : 0) }
        if hover(y) && click { sendLogout() }
        mouseButtonClick = 0
    }
}
