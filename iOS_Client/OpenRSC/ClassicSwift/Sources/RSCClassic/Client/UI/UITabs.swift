// Port of rsc-c ui/ui-tabs.c: the six tab buttons and switching between them.

import Foundation

extension Mudclient {
    static let uiTabNames = ["Inventory", "Map", "Stats", "Spellbook", "Friends", "Options"]

    func drawInventoryCount() {
        if options.inventoryCount == 0 || (isTouch && selectedItemInventoryIndex >= 0) { return }
        let x = isTouch ? uiTabsTouchX + 18 : surface.width - 17
        let y = isTouch ? uiTabsTouchY + 21 : 24
        let count = inventoryItemsCount
        let colour: String
        if count == 30 { colour = "@red@" }
        else if count > 25 { colour = "@or3@" }
        else if count > 20 { colour = "@or2@" }
        else if count > 15 { colour = "@or1@" }
        else if count > 10 { colour = "@gr1@" }
        else if count > 5 { colour = "@gr2@" }
        else { colour = "@gre@" }
        surface.drawStringCentre("\(colour)\(count)", x: x, y: y, font: .bold13, colour: Colour.white)
    }

    func drawInventoryIcon(x: Int, y: Int, selected: Bool) {
        if selected {
            surface.drawBox(x: x, y: y, width: 32, height: 32, colour: Colour.uiLabel)
        } else {
            surface.drawBoxAlpha(x: x, y: y, width: 32, height: 32, colour: Colour.greyB5, alpha: 128)
        }
        drawInventoryItem(x: x, y: y + 5, slotWidth: 32, slotHeight: 22,
                          itemId: inventoryItemId[selectedItemInventoryIndex])
    }

    func drawMagicIcon(x: Int, y: Int, selected: Bool) {
        if selected {
            surface.drawBox(x: x, y: y, width: 32, height: 32, colour: Colour.uiLabel)
        } else {
            surface.drawBoxAlpha(x: x, y: y, width: 32, height: 32, colour: Colour.greyB5, alpha: 128)
        }
        surface.drawSprite(x: x, y: y, id: spriteProjectile + 1)
    }

    func drawUITabs() {
        if showDialogBank && surface.width >= 680 && isTouch { return }
        var buttonY = 3
        if options.versionMedia >= 59 {
            var buttonX = surface.width - UITabs.buttonSize
            if isTouch {
                buttonX = uiTabsTouchX
                buttonY = uiTabsTouchY
            }
            for i in 0..<6 {
                let tab = i + 1
                if isTouch && tab == UITabs.inventory && selectedItemInventoryIndex >= 0 {
                    drawInventoryIcon(x: buttonX, y: buttonY, selected: false)
                } else if isTouch && tab == UITabs.magic && selectedSpell >= 0 {
                    drawMagicIcon(x: buttonX, y: buttonY, selected: false)
                } else {
                    surface.drawSpriteAlpha(x: buttonX, y: buttonY, id: spriteMedia + 33 + i, alpha: 128)
                }
                if isTouch { buttonY += UITabs.buttonSize - 2 } else { buttonX -= UITabs.buttonSize - 2 }
            }
        } else {
            let buttonX = surface.width - surface.spriteWidth[spriteMedia] - 3
            surface.drawSpriteAlpha(x: buttonX, y: buttonY, id: spriteMedia, alpha: 128)
        }
        drawInventoryCount()
    }

    private func toggleUITab(_ tab: Int) {
        if mouseButtonClick != 0 {
            showUITab = showUITab == tab ? 0 : tab
            mouseButtonClick = 0
        }
    }

    func setActiveUITab(noMenus: Bool) {
        let isToggle = isTouch
        var minX = surface.width - UITabs.buttonSize, maxX = surface.width - 3
        var minY = 3, maxY = UITabs.buttonSize
        if isTouch {
            minX = uiTabsTouchX
            maxX = surface.width
            minY = uiTabsTouchY
            maxY = minY + UITabs.buttonSize - 2
        }

        var dragging = false
        if options.offHandleScrollDrag != 0 {
            dragging = panelQuests.controlListScrollbarHandleDragged[controlListQuest] ||
                panelMagic.controlListScrollbarHandleDragged[controlListMagic] ||
                panelSocialList.controlListScrollbarHandleDragged[controlListSocial]
            if dragging { return }
        }

        var changed = false
        for i in 0..<6 {
            let tab = i + 1
            if mouseX >= minX && mouseX < maxX && mouseY >= minY && mouseY < maxY {
                let name = Mudclient.uiTabNames[i]
                let page = tab == UITabs.map ? "RuneScape_Classic_Map" : name
                if isToggle {
                    if showUITab == tab && selectedWiki && noMenus {
                        menuAddWiki(display: name, page: page)
                    } else {
                        toggleUITab(tab)
                    }
                    return
                }
                if showUITab == 0 || mouseY < UITabs.buttonSize - 9 {
                    showUITab = tab
                    if tab == UITabs.map && options.antiMacro != 0 {
                        minimapRandomRotation = Int(CRandom.shared.nextUnitFloat() * 13) - 6
                        minimapRandomScale = Int(CRandom.shared.nextUnitFloat() * 23) - 11
                    }
                    changed = true
                }
                if selectedWiki && noMenus { menuAddWiki(display: name, page: page) }
            }
            if isTouch {
                minY += UITabs.buttonSize - 2
                maxY += UITabs.buttonSize - 2
            } else {
                minX -= UITabs.buttonSize - 2
                maxX -= UITabs.buttonSize - 2
            }
        }

        if !changed && !dragging && showUITab != 0 &&
            (mouseX < uiTabMinX || mouseX > uiTabMaxX || mouseY < uiTabMinY || mouseY > uiTabMaxY) {
            showUITab = 0
        }
    }

    func drawUITabLabel(selectedTab: Int, width: Int, x: Int, y: Int) {
        surface.drawBox(x: x, y: y, width: width, height: 9, colour: Colour.uiLabel)
        let sprite = spriteMedia + 26 + selectedTab
        let offset = !isTouch && showUITab > 4 ? width - surface.spriteWidth[sprite] - 3 : 1
        surface.drawSprite(x: x + offset, y: y + 1, id: sprite)
        surface.drawLineHorizontal(x: x, y: y + 9, width: width, colour: Colour.black)
    }

    func drawActiveUITab(noMenus: Bool) {
        switch showUITab {
        case UITabs.inventory: drawUITabInventory(noMenus: noMenus)
        case UITabs.map: drawUITabMinimap(noMenus: noMenus)
        case UITabs.stats: drawUITabStats(noMenus: noMenus)
        case UITabs.magic: drawUITabMagic(noMenus: noMenus)
        case UITabs.social: drawUITabSocial(noMenus: noMenus)
        case UITabs.options: drawUITabOptions(noMenus: noMenus)
        default: break
        }
        if showUITab != 0 {
            var selectedY = 3
            var selectedX: Int
            if options.versionMedia >= 59 {
                selectedX = surface.width - UITabs.buttonSize * showUITab + (showUITab - 1) * 2
                if isTouch {
                    selectedX = uiTabsTouchX
                    selectedY = uiTabsTouchY + (showUITab - 1) * (UITabs.buttonSize - 2)
                    if showUITab == UITabs.inventory && selectedItemInventoryIndex >= 0 {
                        drawInventoryIcon(x: selectedX, y: selectedY, selected: true)
                        return
                    } else if showUITab == UITabs.magic && selectedSpell >= 0 {
                        drawMagicIcon(x: selectedX, y: selectedY, selected: true)
                        return
                    }
                }
            } else {
                selectedX = surface.width - UITabs.width - 3
            }
            surface.drawSprite(x: selectedX, y: selectedY, id: spriteMedia + showUITab)
        }
        drawInventoryCount()
    }
}
