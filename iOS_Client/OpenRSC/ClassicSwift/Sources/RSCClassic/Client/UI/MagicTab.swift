// Port of rsc-c ui/magic-tab.c: spells and prayers.

import Foundation

extension Mudclient {
    static let magicWidth = 196, magicHeight = 182, magicTabHeight = 24
    static let skillPrayer = 5, skillMagic = 6

    func drawUITabMagic(noMenus: Bool) {
        let mw = Mudclient.magicWidth, tabHeight = Mudclient.magicTabHeight
        var uiX = surface.width - mw - 3
        var uiY = UITabs.buttonSize + 1
        var height = Mudclient.magicHeight
        if isTouch {
            height = 198
            uiX = uiTabsTouchX - mw - 1
            uiY = uiTabsTouchY + UITabs.touchHeight - height - 2
        }
        let notTouch = isTouch ? 0 : 1
        if options.versionMedia >= 59 {
            drawUITabLabel(selectedTab: UITabs.magic, width: mw + notTouch, x: uiX - notTouch,
                           y: uiY - UITabs.labelHeight)
        }
        uiTabMinX = uiX
        uiTabMaxX = surface.width
        uiTabMinY = 0
        uiTabMaxY = 240
        if isTouch {
            uiTabMaxX = uiX + mw
            uiTabMinY = uiY - UITabs.labelHeight
            uiTabMaxY = uiY + height
        }
        surface.drawBoxAlpha(x: uiX, y: uiY + tabHeight, width: mw, height: height - tabHeight, colour: Colour.greyDC,
                             alpha: 128)
        var descriptionY = uiY + panelMagic.controlHeight[controlListMagic] + tabHeight - 1
        surface.drawLineHorizontal(x: uiX, y: descriptionY, width: mw, colour: Colour.black)
        descriptionY += 11
        surface.drawTabs(x: uiX, y: uiY, width: mw, height: tabHeight, tabs: ["Magic", "Prayers"],
                         selected: uiTabMagicSubTab)
        let mx = mouseX - uiX, my = mouseY - uiY
        let early = isTouch
        if isTouch {
            panelMagic.handleMouse(x: Mudclient.finger1X, y: Mudclient.finger1Y, lastButton: lastMouseButtonDown,
                                   isDown: Mudclient.finger1Down, scrollDelta: mouseScrollDelta)
        }
        let point = isTouch ? "Tap and hold" : "Point"

        func directions(_ thing: String) {
            surface.drawString("\(point) at a \(thing) for a\(isTouch ? "" : " description")", x: uiX + 2,
                               y: descriptionY, font: .bold12, colour: Colour.black)
            if isTouch {
                surface.drawString("description", x: uiX + 2, y: descriptionY + Surface.textHeight(.bold12),
                                   font: .bold12, colour: Colour.black)
            }
        }

        if uiTabMagicSubTab == 0 {
            panelMagic.clearList(controlListMagic)
            let magicLevel = playerSkillCurrent[Mudclient.skillMagic]
            for (i, spell) in gameData.spells.enumerated() {
                var colour = "@yel@"
                for j in 0..<spell.runesRequired where !hasInventoryItem(spell.runes[j].id, minimum: spell.runes[j].count) {
                    colour = "@whi@"
                    break
                }
                if spell.level > magicLevel { colour = "@bla@" }
                if isTouch && selectedSpell == i { colour = "@gre@" }
                panelMagic.addListEntry(controlListMagic, index: i,
                                        text: cField("\(colour)Level \(spell.level): \(spell.name)"))
            }
            panelMagic.drawPanel()
            let index = panelMagic.listEntryIndex(controlListMagic)
            if index != -1 {
                let spell = gameData.spells[index]
                surface.drawString(cField("Level \(spell.level): \(spell.name)"), x: uiX + 2, y: descriptionY,
                                   font: .bold12, colour: Colour.yellow)
                surface.drawString(spell.description, x: uiX + 2, y: descriptionY + 12, font: .regular11,
                                   colour: Colour.white)
                for i in 0..<spell.runesRequired {
                    let runeId = spell.runes[i].id
                    let have = inventoryCount(runeId)
                    let need = spell.runes[i].count
                    let colour = hasInventoryItem(runeId, minimum: need) ? "@gre@" : "@red@"
                    surface.drawSprite(x: uiX + 2 + i * 44, y: descriptionY + 26,
                                       id: spriteItem + gameData.items[runeId].sprite)
                    surface.drawString("\(colour)\(have)/\(need)", x: uiX + 2 + i * 44, y: descriptionY + 26,
                                       font: .bold12, colour: Colour.white)
                }
                if selectedWiki && noMenus { menuAddWiki(display: spell.name, page: spell.name) }
            } else {
                directions("spell")
            }
        } else if uiTabMagicSubTab == 1 {
            panelMagic.clearList(controlListMagic)
            for (i, prayer) in gameData.prayers.enumerated() {
                var colour = "@whi@"
                if prayer.level > playerSkillBase[Mudclient.skillPrayer] { colour = "@bla@" }
                if prayerOn[i] { colour = "@gre@" }
                panelMagic.addListEntry(controlListMagic, index: i,
                                        text: cField("\(colour)Level \(prayer.level): \(prayer.name)"))
            }
            panelMagic.drawPanel()
            let index = panelMagic.listEntryIndex(controlListMagic)
            if index != -1 {
                let prayer = gameData.prayers[index]
                surface.drawStringCentre(cField("Level \(prayer.level): \(prayer.name)"), x: uiX + mw / 2,
                                         y: descriptionY + 6, font: .bold12, colour: Colour.yellow)
                surface.drawStringCentre(prayer.description, x: uiX + mw / 2, y: descriptionY + 21, font: .regular11,
                                         colour: Colour.white)
                surface.drawStringCentre("Drain rate: \(prayer.drain)", x: uiX + mw / 2, y: descriptionY + 36,
                                         font: .bold12, colour: Colour.black)
                if selectedWiki && noMenus { menuAddWiki(display: prayer.name, page: prayer.name) }
            } else {
                directions("prayer")
            }
        }

        guard noMenus else { return }
        if !early {
            let withinX = options.offHandleScrollDrag != 0 ? true : mx >= 0 && mx < mw
            if !withinX || !(my >= 0 && my < height) { return }
            panelMagic.handleMouse(x: mx + uiX, y: my + uiY, lastButton: lastMouseButtonDown, isDown: mouseButtonDown,
                                   scrollDelta: mouseScrollDelta)
        }
        if my <= tabHeight && mouseButtonClick == 1 {
            if mx < mw / 2 && uiTabMagicSubTab == 1 {
                uiTabMagicSubTab = 0
                panelMagic.resetList(controlListMagic)
            } else if mx > mw / 2 && uiTabMagicSubTab == 0 {
                uiTabMagicSubTab = 1
                panelMagic.resetList(controlListMagic)
            }
        }
        if selectedWiki || mouseButtonClick != 1 { return }

        if uiTabMagicSubTab == 0 {
            let index = panelMagic.listEntryIndex(controlListMagic)
            if index != -1 {
                let spell = gameData.spells[index]
                if spell.level > playerSkillCurrent[Mudclient.skillMagic] {
                    showMessage("Your magic ability is not high enough for this spell", .game)
                } else {
                    var ok = true
                    for i in 0..<spell.runesRequired
                    where !hasInventoryItem(spell.runes[i].id, minimum: spell.runes[i].count) {
                        showMessage("You don't have all the reagents you need for this spell", .game)
                        ok = false
                        break
                    }
                    if ok {
                        selectedSpell = index
                        selectedItemInventoryIndex = -1
                        if isCompact || isTouch { showUITab = 0 }
                    }
                }
            }
        } else if uiTabMagicSubTab == 1 {
            let index = panelMagic.listEntryIndex(controlListMagic)
            if index != -1 {
                if gameData.prayers[index].level > playerSkillBase[Mudclient.skillPrayer] {
                    showMessage("Your prayer ability is not high enough for this prayer", .game)
                } else if playerSkillCurrent[Mudclient.skillPrayer] == 0 {
                    showMessage("You have run out of prayer points. return to a church to recharge", .game)
                } else if prayerOn[index] {
                    if let ps = packetStream {
                        ps.newPacket(ClientOpcode.prayerOff); ps.putByte(index); ps.sendPacket()
                    }
                    prayerOn[index] = false
                    playSound("prayeroff")
                } else {
                    if let ps = packetStream {
                        ps.newPacket(ClientOpcode.prayerOn); ps.putByte(index); ps.sendPacket()
                    }
                    prayerOn[index] = true
                    playSound("prayeron")
                }
            }
        }
        mouseButtonClick = 0
    }
}
