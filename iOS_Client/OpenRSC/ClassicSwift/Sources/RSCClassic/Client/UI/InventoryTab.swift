// Port of rsc-c ui/inventory-tab.c.

import Foundation

extension Mudclient {
    func drawUITabInventory(noMenus: Bool) {
        let columns = surface.height < 260 ? 6 : 5
        let rows = Mudclient.inventoryItemsMax / columns
        let slotW = Surface.itemGridSlotWidth
        let slotHeight = Surface.itemGridSlotHeight - (isTouch ? 1 : 0)
        let width = slotW * columns
        let height = slotHeight * rows
        var uiX = surface.width - width - 3
        var uiY = UITabs.buttonSize + 1
        if isTouch {
            uiX = showDialogBank ? surface.width - width - 5 : uiTabsTouchX - width - 1
            uiY = uiTabsTouchY + UITabs.touchHeight - height - 2
        }
        if options.versionMedia >= 59 {
            drawUITabLabel(selectedTab: UITabs.inventory, width: width, x: uiX, y: uiY - UITabs.labelHeight)
        }
        uiTabMinX = uiX
        uiTabMaxX = surface.width
        uiTabMinY = 0
        uiTabMaxY = uiY + height
        if isTouch {
            uiTabMaxX = uiX + width
            uiTabMinY = uiY - UITabs.labelHeight
            uiTabMaxY = uiY + height
        }

        for i in 0..<Mudclient.inventoryItemsMax {
            let slotX = uiX + (i % columns) * slotW
            let slotY = uiY + (i / columns) * slotHeight
            var colour = Colour.greyB5
            if i < inventoryItemsCount && inventoryEquipped[i] != 0 { colour = Colour.red }
            surface.drawBoxAlpha(x: slotX, y: slotY, width: slotW, height: slotHeight, colour: colour, alpha: 128)
            if i < inventoryItemsCount {
                let itemId = inventoryItemId[i]
                drawInventoryItem(x: slotX, y: slotY, slotWidth: slotW, slotHeight: Surface.itemGridSlotHeight,
                                  itemId: itemId)
                if gameData.items[itemId].stackable == 0 {
                    surface.drawString(cField(formatItemAmountText(inventoryItemStackCount[i]), 12),
                                       x: slotX + 1, y: slotY + 10, font: .bold12, colour: Colour.yellow)
                }
            }
        }
        for i in stride(from: 1, through: columns - 1, by: 1) {
            surface.drawLineVertical(x: uiX + i * slotW, y: uiY, height: height, colour: Colour.black)
        }
        for i in stride(from: 1, through: rows - 1, by: 1) {
            surface.drawLineHorizontal(x: uiX, y: uiY + i * slotHeight, width: width, colour: Colour.black)
        }

        guard noMenus else { return }
        let mx = mouseX - uiX, my = mouseY - uiY
        if mx < 0 || my < 0 || mx > width || my > height { return }
        let itemIndex = mx / slotW + (my / slotHeight) * columns
        if itemIndex >= inventoryItemsCount { return }
        let itemId = inventoryItemId[itemIndex]
        let item = gameData.items[itemId]
        let name = "@lre@\(item.name)"

        func add(_ action: String, _ type: Int, _ index: Int, source: Int? = nil) {
            withMenuEntry { e in
                e.actionText = action
                e.targetText = name
                e.type = type
                e.index = index
                if let source { e.sourceIndex = source }
            }
            menuItemsCount += 1
        }

        if selectedWiki {
            menuAddIdWiki(display: name, type: "item", id: itemId)
        } else if showDialogBank {
            addOfferMenus("Deposit", type: MenuType.bankDeposit, itemId: itemId, itemAmount: inventoryCount(itemId),
                          itemName: name, lastX: bankLastDepositOffer)
        } else if selectedSpell >= 0 {
            if gameData.spells[selectedSpell].type == 3 {
                add("Cast \(gameData.spells[selectedSpell].name) on", MenuType.castInvItem, itemIndex,
                    source: selectedSpell)
            }
        } else {
            if selectedItemInventoryIndex >= 0 {
                add("Use \(selectedItemName) with:", MenuType.useWithInvItem, itemIndex,
                    source: selectedItemInventoryIndex)
                return
            }
            if inventoryEquipped[itemIndex] == 1 {
                add("Remove", MenuType.inventoryUnequip, itemIndex)
            } else if item.wearable != 0 {
                add(item.wearable & 24 != 0 ? "Wield" : "Wear", MenuType.inventoryWear, itemIndex)
            }
            if !item.command.isEmpty {
                add(item.command, MenuType.inventoryCommand, itemIndex)
            }
            add("Use", MenuType.inventoryUse, itemIndex)
            add("Drop", MenuType.inventoryDrop, itemIndex)
            add("Examine", MenuType.inventoryExamine, itemId)
        }
    }
}
