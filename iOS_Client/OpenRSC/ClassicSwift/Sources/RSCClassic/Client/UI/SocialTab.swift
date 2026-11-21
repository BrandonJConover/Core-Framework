// Port of rsc-c ui/social-tab.c: friends and ignore lists and their input dialogs.

import Foundation

extension Mudclient {
    func addFriend(_ username: String) {
        let encoded = ClientUtil.encodeUsername(username)
        if let ps = packetStream { ps.newPacket(ClientOpcode.friendAdd); ps.putLong(encoded); ps.sendPacket() }
        for i in 0..<friendListCount where friendList[i] == encoded { return }
        if friendListCount >= Mudclient.socialListMax { return }
        friendList[friendListCount] = encoded
        friendListOnline[friendListCount] = 0
        friendListCount += 1
    }

    func removeFriend(_ encoded: Int64) {
        if let ps = packetStream { ps.newPacket(ClientOpcode.friendRemove); ps.putLong(encoded); ps.sendPacket() }
        for i in 0..<friendListCount where friendList[i] == encoded {
            friendListCount -= 1
            for j in i..<friendListCount {
                friendList[j] = friendList[j + 1]
                friendListOnline[j] = friendListOnline[j + 1]
            }
            break
        }
        showServerMessage("@pri@\(ClientUtil.decodeUsername(encoded)) has been removed from your friends list")
    }

    func addIgnore(_ username: String) {
        let encoded = ClientUtil.encodeUsername(username)
        if let ps = packetStream { ps.newPacket(ClientOpcode.ignoreAdd); ps.putLong(encoded); ps.sendPacket() }
        for i in 0..<ignoreListCount where ignoreList[i] == encoded { return }
        if ignoreListCount >= Mudclient.socialListMax { return }
        ignoreList[ignoreListCount] = encoded
        ignoreListCount += 1
    }

    func removeIgnore(_ encoded: Int64) {
        if let ps = packetStream { ps.newPacket(ClientOpcode.ignoreRemove); ps.putLong(encoded); ps.sendPacket() }
        for i in 0..<ignoreListCount where ignoreList[i] == encoded {
            ignoreListCount -= 1
            for j in i..<ignoreListCount { ignoreList[j] = ignoreList[j + 1] }
            return
        }
    }

    func sendPrivateMessage(_ username: Int64, _ message: [UInt8]) {
        guard let ps = packetStream else { return }
        ps.newPacket(ClientOpcode.pm)
        ps.putLong(username)
        ps.putBytes(message)
        ps.sendPacket()
    }

    func drawUITabSocial(noMenus: Bool) {
        let sw = SocialTab.width, tabHeight = SocialTab.tabHeight
        var uiX = surface.width - sw - 3
        var uiY = UITabs.buttonSize + 1
        var height = SocialTab.height
        if isTouch {
            height = 198
            uiX = uiTabsTouchX - sw - 1
            uiY = uiTabsTouchY + UITabs.touchHeight - height - 2
        }
        let notTouch = isTouch ? 0 : 1
        if options.versionMedia >= 59 {
            drawUITabLabel(selectedTab: UITabs.social, width: sw + notTouch, x: uiX - notTouch,
                           y: uiY - UITabs.labelHeight)
        }
        uiTabMinX = uiX
        uiTabMaxX = surface.width
        uiTabMinY = 0
        uiTabMaxY = 240
        if isTouch {
            uiTabMaxX = uiX + sw
            uiTabMinY = uiY - UITabs.labelHeight
            uiTabMaxY = uiY + height
        }
        surface.drawBoxAlpha(x: uiX, y: uiY + tabHeight, width: sw, height: height - tabHeight, colour: Colour.greyDC,
                             alpha: 128)
        surface.drawLineHorizontal(x: uiX, y: uiY + height - 16, width: sw, colour: Colour.black)
        surface.drawTabs(x: uiX, y: uiY, width: sw, height: tabHeight, tabs: ["Friends", "Ignore"],
                         selected: uiTabSocialSubTab)
        panelSocialList.clearList(controlListSocial)
        if uiTabSocialSubTab == 0 {
            for i in 0..<friendListCount {
                var colour = "@red@"
                if friendListOnline[i] == SocialTab.friendOnline { colour = "@gre@" }
                else if friendListOnline[i] > 0 { colour = "@yel@" }
                panelSocialList.addListEntry(controlListSocial, index: i,
                                             text: "\(colour)\(ClientUtil.decodeUsername(friendList[i]))~\(uiX + 126)~@whi@Remove")
            }
        } else if uiTabSocialSubTab == 1 {
            for i in 0..<ignoreListCount {
                panelSocialList.addListEntry(controlListSocial, index: i,
                                             text: "@yel@\(ClientUtil.decodeUsername(ignoreList[i]))~"
                                                + String(format: "%04d", uiX + 126) + "~@whi@Remove")
            }
        }
        let mx = mouseX - uiX, my = mouseY - uiY
        let early = isTouch
        if isTouch {
            panelSocialList.handleMouse(x: Mudclient.finger1X, y: Mudclient.finger1Y, lastButton: lastMouseButtonDown,
                                        isDown: Mudclient.finger1Down, scrollDelta: mouseScrollDelta)
        }
        panelSocialList.drawPanel()

        let verb = isTouch ? "Tap" : "Click"
        let addHover = mouseX > uiX && mouseX < uiX + sw && mouseY > uiY + height - 16 && mouseY < uiY + height
        if uiTabSocialSubTab == 0 {
            let index = panelSocialList.listEntryIndex(controlListSocial)
            var text = "\(verb) a name to send a message"
            if index >= 0 && mouseX < uiX + 176 {
                let name = ClientUtil.decodeUsername(friendList[index])
                let online = friendListOnline[index]
                if mouseX > uiX + 116 {
                    text = "\(verb) to remove \(name)"
                } else if online == SocialTab.friendOnline {
                    text = "\(verb) to message \(name)"
                } else if online > 0 {
                    text = online < 200 ? "\(name) is on world \(online - 9)" : "\(name) is on classic \(online - 219)"
                } else {
                    text = "\(name) is offline"
                }
            }
            surface.drawStringCentre(text, x: uiX + sw / 2, y: uiY + 35, font: .bold12, colour: Colour.white)
            surface.drawStringCentre("\(verb) here to add a friend", x: uiX + sw / 2, y: uiY + height - 3,
                                     font: .bold12, colour: addHover ? Colour.yellow : Colour.white)
        } else if uiTabSocialSubTab == 1 {
            let index = panelSocialList.listEntryIndex(controlListSocial)
            var text = "Blocking messages from:"
            if index >= 0 && mouseX < uiX + 176 && mouseX > uiX + 116 {
                text = "\(verb) to remove \(ClientUtil.decodeUsername(ignoreList[index]))"
            }
            surface.drawStringCentre(text, x: uiX + sw / 2, y: uiY + 35, font: .bold12, colour: Colour.white)
            surface.drawStringCentre("\(verb) here to add a name", x: uiX + sw / 2, y: uiY + height - 3,
                                     font: .bold12, colour: addHover ? Colour.yellow : Colour.white)
        }

        guard noMenus else { return }
        if !early {
            let withinX = options.offHandleScrollDrag != 0 ? true : mx >= 0 && mx < sw
            if !withinX || !(my >= 0 && my < height) { return }
            panelSocialList.handleMouse(x: mx + uiX, y: my + uiY, lastButton: lastMouseButtonDown,
                                        isDown: mouseButtonDown, scrollDelta: mouseScrollDelta)
        }
        if my <= tabHeight && mouseButtonClick == 1 {
            if mx < sw / 2 && uiTabSocialSubTab == 1 {
                uiTabSocialSubTab = 0
                panelSocialList.resetList(controlListSocial)
            } else if mx > sw / 2 && uiTabSocialSubTab == 0 {
                uiTabSocialSubTab = 1
                panelSocialList.resetList(controlListSocial)
            }
        }
        if mouseButtonClick == 1 && uiTabSocialSubTab == 0 {
            let index = panelSocialList.listEntryIndex(controlListSocial)
            if index >= 0 && mx < 176 {
                if mx > 116 {
                    removeFriend(friendList[index])
                } else if friendListOnline[index] != 0 {
                    showDialogSocialInput = SocialTab.messageFriend
                    privateMessageTarget = friendList[index]
                    inputPmCurrent = ""
                    inputPmFinal = ""
                }
            }
        }
        if mouseButtonClick == 1 && uiTabSocialSubTab == 1 {
            let index = panelSocialList.listEntryIndex(controlListSocial)
            if index >= 0 && mx < 176 && mx > 116 { removeIgnore(ignoreList[index]) }
        }
        if my > 166 && mouseButtonClick == 1 {
            inputTextCurrent = ""
            inputTextFinal = ""
            if uiTabSocialSubTab == 0 {
                showDialogSocialInput = SocialTab.addFriend
            } else if uiTabSocialSubTab == 1 {
                showDialogSocialInput = SocialTab.addIgnore
            }
        }
        mouseButtonClick = 0
    }

    func drawSocialInput() {
        let messaging = showDialogSocialInput == SocialTab.messageFriend
        let boxWidth = messaging ? surface.width - 12 : SocialTab.dialogAddWidth
        let dialogX = surface.width / 2 - boxWidth / 2
        var dialogY = surface.height / 2 - SocialTab.dialogHeight / 2 + 7
        let cancelX = surface.width / 2 - SocialTab.cancelSize / 2
        let cancelY = surface.height / 2 + SocialTab.cancelSize / 2
        let current = messaging ? inputPmCurrent : inputTextCurrent

        if mouseButtonClick != 0 {
            mouseButtonClick = 0
            if mouseX < dialogX || mouseY < dialogY || mouseX > dialogX + boxWidth ||
                mouseY > dialogY + SocialTab.dialogHeight {
                showDialogSocialInput = 0
                return
            }
            if mouseX > cancelX && mouseX < cancelX + SocialTab.cancelSize && mouseY > cancelY &&
                mouseY < cancelY + SocialTab.cancelSize {
                showDialogSocialInput = 0
                return
            }
            if isTouch {
                let keyboardX = surface.width / 2 - boxWidth / 2, keyboardY = dialogY + 20
                if mouseX >= keyboardX && mouseX <= keyboardX + boxWidth && mouseY >= keyboardY &&
                    mouseY <= keyboardY + 20 {
                    triggerKeyboard(text: current, isPassword: false, x: keyboardX, y: keyboardY,
                                    width: boxWidth - 5, height: 30, font: .bold14, isCentred: true)
                }
            }
        }

        surface.drawBox(x: dialogX, y: dialogY, width: boxWidth, height: SocialTab.dialogHeight, colour: Colour.black)
        surface.drawBorder(x: dialogX, y: dialogY, width: boxWidth, height: SocialTab.dialogHeight,
                           colour: Colour.white)
        dialogY += 20
        let centreX = surface.width / 2

        func prompt(_ title: String) {
            surface.drawStringCentre(title, x: centreX, y: dialogY, font: .bold14, colour: Colour.white)
            dialogY += 20
            surface.drawStringCentre("\(current)*", x: centreX, y: dialogY, font: .bold14, colour: Colour.white)
        }

        switch showDialogSocialInput {
        case SocialTab.addFriend, SocialTab.addIgnore:
            let friend = showDialogSocialInput == SocialTab.addFriend
            prompt(friend ? "Enter name to add to friends list" : "Enter name to add to ignore list")
            let username = inputTextFinal
            if !username.isEmpty {
                if ClientUtil.encodeUsername(username) != localPlayer.encodedUsername {
                    if friend { addFriend(username) } else { addIgnore(username) }
                }
                inputTextCurrent = ""
                inputTextFinal = ""
                showDialogSocialInput = 0
            }
        case SocialTab.messageFriend:
            let target = ClientUtil.decodeUsername(privateMessageTarget)
            prompt("Enter message to send to \(target)")
            let message = inputPmFinal
            if !message.isEmpty {
                let encoded = ChatMessage.encode(message)
                sendPrivateMessage(privateMessageTarget, encoded)
                let decoded = ChatMessage.decode(encoded, offset: 0, length: encoded.count)
                showServerMessage("@pri@You tell \(target): \(decoded)")
                inputPmCurrent = ""
                inputPmFinal = ""
                showDialogSocialInput = 0
            }
        default:
            break
        }

        var colour = Colour.white
        if mouseX > cancelX && mouseX < cancelX + SocialTab.cancelSize && mouseY > cancelY &&
            mouseY < cancelY + SocialTab.cancelSize {
            colour = Colour.yellow
        }
        surface.drawStringCentre("Cancel", x: centreX, y: dialogY + 23, font: .bold12, colour: colour)
    }
}
