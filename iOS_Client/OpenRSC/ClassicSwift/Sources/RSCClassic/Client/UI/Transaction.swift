// Port of rsc-c ui/transaction.c, ui/trade.c and ui/duel.c.

import Foundation

extension Mudclient {
    static let transactionInventoryRows = 6, transactionInventoryColumns = 5
    static let transactionButtonWidth = 69, transactionButtonHeight = 21
    static let duelCheckboxWidth = 11, duelCheckboxHeight = 11

    var transactionIsCompact: Bool { surface.width < 490 || surface.height < 294 }

    /// Sizes shared by every trade and duel screen.
    private struct TransactionLayout {
        let compact: Bool, columns: Int, slotWidth: Int, slotHeight: Int
        let inventoryWidth: Int, inventoryHeight: Int, width: Int, height: Int

        init(compact: Bool) {
            self.compact = compact
            columns = compact ? 3 : 4
            slotWidth = compact ? 39 : Surface.itemGridSlotWidth
            slotHeight = compact ? 27 : Surface.itemGridSlotHeight
            inventoryWidth = Mudclient.transactionInventoryColumns * slotWidth
            inventoryHeight = Mudclient.transactionInventoryRows * slotHeight
            width = inventoryWidth + columns * slotWidth + (compact ? 8 : 27)
            height = Mudclient.transactionInventoryRows * slotHeight + (compact ? 43 : 74)
        }
    }

    private func sendTransactionUpdate(_ opcode: Int) {
        if let ps = packetStream {
            ps.newPacket(opcode)
            ps.putByte(transactionItemCount)
            for i in 0..<transactionItemCount {
                ps.putShort(transactionItems[i])
                ps.putInt(transactionItemsCount[i])
            }
            ps.sendPacket()
        }
        transactionRecipientAccepted = 0
        transactionAccepted = 0
    }

    private func sendBare(_ opcode: Int) {
        guard let ps = packetStream else { return }
        ps.newPacket(opcode)
        ps.sendPacket()
    }

    func offerTransactionItem(opcode: Int, itemId: Int, amount: Int) {
        let item = gameData.items[itemId]
        if item.special == 1 {
            showMessage(opcode == ClientOpcode.tradeItemUpdate
                            ? "This object cannot be traded with other players"
                            : "This object cannot be added to a duel offer", .game)
            return
        }
        let inventoryCount = inventoryCount(itemId)
        var sendUpdate = false
        var itemCountAdd = 0
        for i in 0..<transactionItemCount where transactionItems[i] == itemId {
            if item.stackable == 0 {
                for _ in 0..<max(amount, 0) {
                    if transactionItemsCount[i] < inventoryCount { transactionItemsCount[i] += 1 }
                    sendUpdate = true
                }
            } else {
                itemCountAdd += 1
            }
        }
        if inventoryCount <= itemCountAdd { sendUpdate = true }

        let compact = transactionIsCompact
        let columns = compact ? 3 : 4
        let max = opcode == ClientOpcode.tradeItemUpdate ? (compact ? 4 : 3) * columns : (compact ? 2 : 3) * columns
        if !sendUpdate && transactionItemCount < max {
            if options.transactionMenus != 0 {
                let end = Swift.min(transactionItemCount + amount, max)
                if item.stackable == 1 {
                    var i = transactionItemCount
                    while i < end {
                        transactionItems[i] = itemId
                        transactionItemsCount[i] = 1
                        transactionItemCount += 1
                        i += 1
                    }
                } else {
                    transactionItems[transactionItemCount] = itemId
                    transactionItemsCount[transactionItemCount] = amount
                    transactionItemCount += 1
                }
            } else {
                transactionItems[transactionItemCount] = itemId
                transactionItemsCount[transactionItemCount] = 1
                transactionItemCount += 1
            }
            sendUpdate = true
        }
        if sendUpdate { sendTransactionUpdate(opcode) }
    }

    func removeTransactionItem(opcode: Int, itemId: Int, amount: Int) {
        if options.transactionMenus != 0 {
            var amount = amount
            var newCount = transactionItemCount
            for i in 0..<transactionItemCount where transactionItems[i] == itemId {
                if gameData.items[itemId].stackable == 0 {
                    transactionItemsCount[i] -= amount
                    if transactionItemsCount[i] <= 0 {
                        transactionItems[i] = -1
                        transactionItemsCount[i] = 0
                        newCount -= 1
                    }
                } else {
                    for j in 0..<transactionItemCount {
                        if amount <= 0 { break }
                        if transactionItems[j] == itemId {
                            transactionItems[j] = -1
                            transactionItemsCount[j] = 0
                            amount -= 1
                            newCount -= 1
                        }
                    }
                }
                break
            }
            var kept = 0
            for i in 0..<transactionItemCount where transactionItems[i] != -1 {
                transactionItems[kept] = transactionItems[i]
                transactionItemsCount[kept] = transactionItemsCount[i]
                kept += 1
            }
            transactionItemCount = newCount
        } else {
            guard let slot = (0..<transactionItemCount).first(where: { transactionItems[$0] == itemId }) else { return }
            for _ in 0..<max(amount, 0) {
                if gameData.items[itemId].stackable == 0 && transactionItemsCount[slot] > 1 {
                    transactionItemsCount[slot] -= 1
                    continue
                }
                transactionItemCount -= 1
                mouseButtonDownTime = 0
                for j in slot..<max(slot, transactionItemCount) {
                    transactionItems[j] = transactionItems[j + 1]
                    transactionItemsCount[j] = transactionItemsCount[j + 1]
                }
                break
            }
        }
        sendTransactionUpdate(opcode)
    }

    private func drawTransactionItems(x: Int, y: Int, rows: Int, items: [Int], counts: [Int], count: Int) {
        let compact = transactionIsCompact
        let columns = compact ? 3 : 4
        let slotWidth = compact ? 39 : Surface.itemGridSlotWidth
        let slotHeight = compact ? 27 : Surface.itemGridSlotHeight
        surface.drawItemGrid(x: x, y: y, rows: rows, columns: columns, slotWidth: slotWidth, slotHeight: slotHeight,
                             items: Array(items.prefix(count)), counts: Array(counts.prefix(count)), selected: -1,
                             showInventoryCount: false, stackableFlag: { self.gameData.items[$0].stackable })
        for i in 0..<count {
            let slotX = x + 1 + (i % columns) * slotWidth
            let slotY = y + 1 + (i / columns) * slotHeight
            if mouseX > slotX && mouseX < slotX + (slotWidth - 1) && mouseY > slotY && mouseY < slotY + (slotHeight - 2) {
                transactionSelectedItem = items[i]
            }
        }
    }

    private func drawTransaction(dialogX: Int, dialogY: Int, isTrade: Bool) {
        let updateOpcode = isTrade ? ClientOpcode.tradeItemUpdate : ClientOpcode.duelItemUpdate
        let declineOpcode = isTrade ? ClientOpcode.tradeDecline : ClientOpcode.duelDecline
        let mouseClick = showRightClickMenu ? 0 : mouseButtonClick

        if showDialogOfferX && inputDigitsFinal > 0 {
            if inputDigitsFinal > offerMax {
                showMessage("You don't have that many!", .game)
            } else {
                if transactionOfferType == TransactionOffer.offer {
                    offerTransactionItem(opcode: updateOpcode, itemId: offerId, amount: inputDigitsFinal)
                } else {
                    removeTransactionItem(opcode: updateOpcode, itemId: offerId, amount: inputDigitsFinal)
                }
                transactionLastOffer = inputDigitsFinal
            }
            inputDigitsFinal = 0
            showDialogOfferX = false
        }
        transactionSelectedItem = -1
        if options.transactionMenus == 0 && mouseClick != 0 && mouseItemCountIncrement == 0 {
            mouseItemCountIncrement = 1
        }

        let mx = mouseX - dialogX, my = mouseY - dialogY
        let l = TransactionLayout(compact: transactionIsCompact)
        let compact = l.compact
        let rows = isTrade ? (compact ? 4 : 3) : (compact ? 3 : 2)
        let columns = l.columns, slotWidth = l.slotWidth, slotHeight = l.slotHeight
        let offerY = compact ? 37 : 30, offerX = compact ? 2 : 8
        let offerWidth = columns * slotWidth, offerHeight = rows * slotHeight
        let inventoryX = offerWidth + (compact ? 5 : 20)
        let inventoryY = compact ? 14 : offerY
        let inventoryWidth = l.inventoryWidth, inventoryHeight = l.inventoryHeight
        let tabsWidth = slotWidth * columns, tabsHeight = 24

        if compact && mouseClick != 0 && mx >= offerX && mx <= offerX + tabsWidth && my >= inventoryY &&
            my <= inventoryY + tabsHeight {
            transactionTab = (mx - offerX) / (tabsWidth / 2)
        }
        let transactionWidth = l.width, transactionHeight = l.height
        let buttonY = inventoryHeight + inventoryY + (compact ? 3 : 4)
        let acceptX = inventoryX + (compact ? 0 : 1)
        let declineX = transactionWidth - Mudclient.transactionButtonWidth - (compact ? 2 : 5)

        if mx >= 0 && my >= 0 && mx < transactionWidth && my < transactionHeight - 16 {
            // inventory
            if mx > inventoryX && my > inventoryY && mx < inventoryX + inventoryWidth + 1 &&
                my < inventoryY + inventoryHeight + 1 {
                let slot = (mx - (inventoryX + 1)) / slotWidth +
                    (my - (inventoryY + 1)) / slotHeight * Mudclient.transactionInventoryColumns
                if slot >= 0 && slot < inventoryItemsCount {
                    let itemId = inventoryItemId[slot]
                    if options.transactionMenus != 0 && !showRightClickMenu {
                        addOfferMenus("Offer", type: MenuType.transactionOffer, itemId: itemId,
                                      itemAmount: inventoryCount(itemId),
                                      itemName: "@lre@\(gameData.items[itemId].name)", lastX: transactionLastOffer)
                    } else if mouseItemCountIncrement > 0 {
                        offerTransactionItem(opcode: updateOpcode, itemId: itemId, amount: mouseItemCountIncrement)
                        mouseButtonClick = 0
                    }
                }
            }
            // offer
            if mx > offerX && my > offerY && mx < offerX + offerWidth + 1 && my < offerY + offerHeight + 1 {
                let slot = (mx - (offerX + 1)) / slotWidth + (my - (offerY + 1)) / slotHeight * columns
                let mine = transactionTab == 0
                if slot >= 0 && slot < (mine ? transactionItemCount : transactionRecipientItemCount) {
                    let counts = mine ? transactionItemsCount : transactionRecipientItemsCount
                    let itemId = (mine ? transactionItems : transactionRecipientItems)[slot]
                    if options.transactionMenus != 0 && !showRightClickMenu {
                        let name = "@lre@\(gameData.items[itemId].name)"
                        var itemAmount = 0
                        for i in 0..<transactionItemCount where transactionItems[i] == itemId {
                            if gameData.items[itemId].stackable == 0 {
                                itemAmount = counts[i]
                                break
                            }
                            itemAmount += 1
                        }
                        if mine {
                            addOfferMenus("Remove", type: MenuType.transactionRemove, itemId: itemId,
                                          itemAmount: itemAmount, itemName: name, lastX: transactionLastOffer)
                        } else {
                            withMenuEntry { e in
                                e.actionText = "Examine"
                                e.targetText = name
                                e.type = MenuType.inventoryExamine
                                e.index = itemId
                            }
                            menuItemsCount += 1
                            withMenuEntry { e in
                                e.actionText = "Cancel"
                                e.targetText = ""
                                e.type = MenuType.cancel
                            }
                            menuItemsCount += 1
                        }
                    } else if mouseItemCountIncrement > 0 {
                        removeTransactionItem(opcode: updateOpcode, itemId: itemId, amount: mouseItemCountIncrement)
                        mouseButtonClick = 0
                    }
                }
            }
            // accept and decline
            if mouseClick != 0 && my >= buttonY && my <= buttonY + Mudclient.transactionButtonHeight {
                if mx >= acceptX && mx <= acceptX + Mudclient.transactionButtonWidth {
                    transactionAccepted = 1
                    sendBare(isTrade ? ClientOpcode.tradeAccept : ClientOpcode.duelAccept)
                } else if mx >= declineX && mx < declineX + Mudclient.transactionButtonWidth {
                    showDialogTrade = false
                    showDialogDuel = false
                    sendBare(declineOpcode)
                }
                mouseButtonClick = 0
            }
        } else if mouseClick != 0 {
            showDialogTrade = false
            showDialogDuel = false
            sendBare(declineOpcode)
            mouseButtonClick = 0
        }
        mouseItemCountIncrement = 0

        guard isTrade ? showDialogTrade : showDialogDuel else { return }

        let opponentPaddingBottom = isTrade ? 22 : 24
        let opponentOfferY = offerY + offerHeight + opponentPaddingBottom + 1
        surface.drawBox(x: dialogX, y: dialogY, width: transactionWidth, height: 12,
                        colour: isTrade ? Colour.titleBar : Colour.duelBar)
        surface.drawBoxAlpha(x: dialogX, y: dialogY + 12, width: transactionWidth, height: compact ? 2 : 18,
                             colour: Colour.grey98, alpha: 160)
        let boxWidth = columns * slotWidth
        let boxHeight = inventoryHeight + (compact ? 26 : 44)
        let paddingLeft = compact ? 2 : 8
        surface.drawBoxAlpha(x: dialogX, y: dialogY + inventoryY, width: paddingLeft, height: boxHeight,
                             colour: Colour.grey98, alpha: 160)
        surface.drawBoxAlpha(x: dialogX + boxWidth + paddingLeft + 1, y: dialogY + inventoryY, width: compact ? 2 : 11,
                             height: boxHeight, colour: Colour.grey98, alpha: 160)
        surface.drawBoxAlpha(x: dialogX + boxWidth + paddingLeft + inventoryWidth + (compact ? 4 : 13),
                             y: dialogY + inventoryY, width: compact ? 2 : 6, height: boxHeight,
                             colour: Colour.grey98, alpha: 160)
        if compact {
            let boxY = dialogY + offerHeight + inventoryY + tabsHeight
            if isTrade {
                surface.drawBoxAlpha(x: dialogX + paddingLeft, y: boxY, width: boxWidth + 1, height: 56,
                                     colour: Colour.grey98, alpha: 160)
            } else {
                surface.drawBoxAlpha(x: dialogX + paddingLeft, y: boxY, width: boxWidth + 1, height: 2,
                                     colour: Colour.grey98, alpha: 160)
                surface.drawBoxAlpha(x: dialogX + paddingLeft, y: boxY + 44, width: boxWidth + 1, height: 39,
                                     colour: Colour.grey98, alpha: 160)
            }
            surface.drawBoxAlpha(x: dialogX + transactionWidth - inventoryWidth - 3,
                                 y: dialogY + inventoryY + inventoryHeight + 1, width: inventoryWidth + 1, height: 25,
                                 colour: Colour.grey98, alpha: 160)
        } else {
            surface.drawBoxAlpha(x: dialogX + paddingLeft, y: dialogY + offerHeight + offerY + 1, width: boxWidth + 1,
                                 height: opponentPaddingBottom, colour: Colour.grey98, alpha: 160)
            surface.drawBoxAlpha(x: dialogX + paddingLeft, y: dialogY + opponentOfferY + offerHeight,
                                 width: boxWidth + 1, height: isTrade ? 21 : 26, colour: Colour.grey98, alpha: 160)
            if !isTrade {
                surface.drawBoxAlpha(x: dialogX + paddingLeft, y: dialogY + 258, width: boxWidth + 1, height: 20,
                                     colour: Colour.grey98, alpha: 160)
            }
            surface.drawBoxAlpha(x: dialogX + inventoryX, y: dialogY + 235, width: 246, height: 43,
                                 colour: Colour.grey98, alpha: 160)
        }
        let with = isTrade ? "Trading with: \(transactionRecipientName)"
            : "Preparing to duel with: \(transactionRecipientName)"
        surface.drawString(with, x: dialogX + 1, y: dialogY + 10, font: .bold12, colour: Colour.white)
        if compact {
            let tabsX = dialogX + offerX, tabsY = dialogY + inventoryY
            surface.drawTabs(x: tabsX + 1, y: tabsY, width: tabsWidth, height: tabsHeight - 1,
                             tabs: ["Yours", "Theirs"], selected: transactionTab)
            surface.drawLineVertical(x: tabsX, y: tabsY, height: tabsHeight, colour: Colour.black)
            surface.drawLineVertical(x: tabsX + tabsWidth, y: tabsY, height: tabsHeight, colour: Colour.black)
            surface.drawLineHorizontal(x: dialogX + offerX + 1, y: dialogY + inventoryY, width: tabsWidth,
                                       colour: Colour.black)
        } else {
            surface.drawString(isTrade ? "Your Offer" : "Your Stake", x: dialogX + offerX + 1, y: dialogY + offerY - 3,
                               font: .bold14, colour: Colour.white)
            surface.drawString(isTrade ? "Opponent's Offer" : "Opponent's Stake", x: dialogX + offerX + 1,
                               y: dialogY + opponentOfferY - 3, font: .bold14, colour: Colour.white)
            surface.drawString("Your Inventory", x: dialogX + inventoryX, y: dialogY + inventoryY - 3, font: .bold14,
                               colour: Colour.white)
        }
        surface.drawSprite(x: dialogX + declineX, y: dialogY + buttonY, id: spriteMedia + 26)
        if transactionRecipientAccepted != 0 {
            let textX = dialogX + acceptX + (compact ? 98 : 124)
            surface.drawStringCentre(compact ? "Player" : "Other player", x: textX, y: dialogY + buttonY + 8,
                                     font: .bold12, colour: Colour.white)
            surface.drawStringCentre(compact ? "accepted" : "has accepted", x: textX, y: dialogY + buttonY + 18,
                                     font: .bold12, colour: Colour.white)
        }
        if transactionAccepted != 0 {
            surface.drawStringCentre("Waiting for", x: dialogX + acceptX + 35, y: dialogY + buttonY + 8,
                                     font: .bold12, colour: Colour.white)
            surface.drawStringCentre("other player", x: dialogX + acceptX + 35, y: dialogY + buttonY + 18,
                                     font: .bold12, colour: Colour.white)
        } else {
            surface.drawSprite(x: dialogX + acceptX, y: dialogY + buttonY, id: spriteMedia + 25)
        }

        surface.drawItemGrid(x: dialogX + inventoryX, y: dialogY + inventoryY, rows: Mudclient.transactionInventoryRows,
                             columns: Mudclient.transactionInventoryColumns, slotWidth: slotWidth,
                             slotHeight: slotHeight, items: Array(inventoryItemId.prefix(inventoryItemsCount)),
                             counts: Array(inventoryItemStackCount.prefix(inventoryItemsCount)), selected: -1,
                             showInventoryCount: false, stackableFlag: { self.gameData.items[$0].stackable })
        let mine = transactionTab == 0
        drawTransactionItems(x: dialogX + offerX, y: dialogY + offerY, rows: rows,
                             items: mine ? transactionItems : transactionRecipientItems,
                             counts: mine ? transactionItemsCount : transactionRecipientItemsCount,
                             count: mine ? transactionItemCount : transactionRecipientItemCount)
        if !compact {
            drawTransactionItems(x: dialogX + offerX, y: dialogY + opponentOfferY, rows: rows,
                                 items: transactionRecipientItems, counts: transactionRecipientItemsCount,
                                 count: transactionRecipientItemCount)
        }

        if transactionSelectedItem != -1 {
            var amountText = ""
            if options.condenseItemAmounts != 0 {
                let opponent = my >= opponentOfferY
                let count = opponent ? transactionRecipientItemCount : transactionItemCount
                let items = opponent ? transactionRecipientItems : transactionItems
                let counts = opponent ? transactionRecipientItemsCount : transactionItemsCount
                var itemAmount = 0
                for i in 0..<count where items[i] == transactionSelectedItem {
                    itemAmount = counts[i]
                    break
                }
                if itemAmount >= 100000 { amountText = " (\(formatNumberCommas(itemAmount)))" }
            }
            if !compact {
                let item = gameData.items[transactionSelectedItem]
                surface.drawString("\(item.name): @whi@\(item.description)\(amountText)", x: dialogX + 8,
                                   y: dialogY + transactionHeight - 5, font: .bold12, colour: Colour.yellow)
            }
        }
        if showDialogOfferX {
            drawOfferX()
            handleOfferXInput()
        }
    }

    private func drawTransactionItemsConfirm(x: Int, y: Int, items: [Int], counts: [Int], count: Int) {
        if count == 0 {
            surface.drawStringCentre("Nothing!", x: x, y: y, font: .bold12, colour: Colour.white)
            return
        }
        for i in 0..<count {
            let item = gameData.items[items[i]]
            var line = item.name
            if item.stackable == 0 { line += " x " + ClientUtil.formatConfirmAmount(counts[i]) }
            surface.drawStringCentre(line, x: x, y: y + i * 12, font: .bold12, colour: Colour.white)
        }
    }

    private func drawTransactionConfirm(dialogX: Int, dialogY: Int, isTrade: Bool) {
        let l = TransactionLayout(compact: transactionIsCompact)
        let compact = l.compact
        let offerY = compact ? 37 : 30
        let inventoryY = compact ? 14 : offerY
        let transactionWidth = l.width, transactionHeight = l.height
        let buttonY = l.inventoryHeight + inventoryY + (compact ? 3 : 4)
        let bw = Mudclient.transactionButtonWidth, bh = Mudclient.transactionButtonHeight

        surface.drawBox(x: dialogX, y: dialogY, width: transactionWidth, height: 16, colour: Colour.titleBar)
        surface.drawBoxAlpha(x: dialogX, y: dialogY + 16, width: transactionWidth,
                             height: transactionHeight - (compact ? 11 : 32), colour: Colour.grey98, alpha: 160)
        let username = ClientUtil.decodeUsername(transactionRecipientConfirmName)
        surface.drawStringCentre("Please confirm your \(isTrade ? "trade" : "duel") with @yel@\(username)",
                                 x: dialogX + transactionWidth / 2, y: dialogY + 12, font: .bold12, colour: Colour.white)
        var y = 30
        if compact {
            let tabs = isTrade ? ["Your Offer", "Their Offer"] : ["Your Stake", "Their Stake", "Rules"]
            surface.drawTabs(x: dialogX, y: dialogY + 16, width: transactionWidth, height: 22, tabs: tabs,
                             selected: transactionTab)
            y += 22
            if transactionTab != 2 {
                let mine = transactionTab == 0
                drawTransactionItemsConfirm(
                    x: dialogX + transactionWidth / 2, y: dialogY + y,
                    items: mine ? transactionConfirmItems : transactionRecipientConfirmItems,
                    counts: mine ? transactionConfirmItemsCount : transactionRecipientConfirmItemsCount,
                    count: mine ? transactionConfirmItemCount : transactionRecipientConfirmItemCount)
            }
        } else {
            surface.drawStringCentre(isTrade ? "You are about to give:" : "Your stake:", x: dialogX + 117,
                                     y: dialogY + y, font: .bold12, colour: Colour.yellow)
            surface.drawStringCentre(isTrade ? "In return you will receive:" : "Your opponent's stake:",
                                     x: dialogX + 351, y: dialogY + y, font: .bold12, colour: Colour.yellow)
            y += 12
            drawTransactionItemsConfirm(x: dialogX + 351, y: dialogY + y, items: transactionRecipientConfirmItems,
                                        counts: transactionRecipientConfirmItemsCount,
                                        count: transactionRecipientConfirmItemCount)
            drawTransactionItemsConfirm(x: dialogX + 117, y: dialogY + y, items: transactionConfirmItems,
                                        counts: transactionConfirmItemsCount, count: transactionConfirmItemCount)
        }
        y = 200
        if !compact {
            if isTrade {
                surface.drawStringCentre("Are you sure you want to do this?", x: dialogX + transactionWidth / 2,
                                         y: dialogY + y, font: .bold14, colour: Colour.cyan)
                y += 15
                surface.drawStringCentre("There is NO WAY to reverse a trade if you change your mind.",
                                         x: dialogX + transactionWidth / 2, y: dialogY + y, font: .bold12,
                                         colour: Colour.white)
            } else {
                y += 15
            }
            y += 15
            let line = isTrade ? "Remember that not all players are trustworthy"
                : "If you are sure \(isTouch ? "tap" : "click") 'Accept' to begin the duel"
            surface.drawStringCentre(line, x: dialogX + transactionWidth / 2, y: dialogY + y, font: .bold12,
                                     colour: Colour.white)
            y += 20
        }
        if transactionConfirmAccepted == 0 {
            let offsetY = compact ? 8 : 0
            surface.drawSprite(x: dialogX + (compact ? 4 : 83), y: dialogY + buttonY + offsetY, id: spriteMedia + 25)
            surface.drawSprite(x: dialogX + (compact ? transactionWidth - 73 : 317), y: dialogY + buttonY + offsetY,
                               id: spriteMedia + 26)
        } else {
            surface.drawStringCentre("Waiting for other player...", x: dialogX + transactionWidth / 2,
                                     y: dialogY + y, font: .bold12, colour: Colour.yellow)
        }

        guard mouseButtonClick == 1 else { return }
        let acceptOpcode = isTrade ? ClientOpcode.tradeConfirmAccept : ClientOpcode.duelConfirmAccept
        let declineOpcode = isTrade ? ClientOpcode.tradeDecline : ClientOpcode.duelDecline
        func close(_ opcode: Int) {
            showDialogTradeConfirm = false
            showDialogDuelConfirm = false
            sendBare(opcode)
        }
        if compact {
            if mouseY < dialogY + 12 || mouseX < dialogX || mouseX > dialogX + transactionWidth {
                close(ClientOpcode.tradeDecline)
            } else if mouseY > dialogY + 12 && mouseY < dialogY + 12 + 22 && mouseX < dialogX + transactionWidth - 4 {
                transactionTab = (mouseX - dialogX) / (transactionWidth / (isTrade ? 2 : 3))
            } else if mouseY > dialogY + transactionHeight - bh && mouseY < dialogY + transactionHeight {
                if mouseX > dialogX + 4 && mouseX < dialogX + bw + 4 {
                    transactionConfirmAccepted = 1
                    sendBare(acceptOpcode)
                } else if mouseX > dialogX + transactionWidth - bw - 4 && mouseX < dialogX + transactionWidth - 4 {
                    close(declineOpcode)
                }
            }
        } else {
            if mouseX < dialogX || mouseY < dialogY || mouseX > dialogX + transactionWidth || mouseY > dialogY + 262 {
                close(ClientOpcode.tradeDecline) // C sends the trade decline here for duels too
            } else if mouseY >= dialogY + 238 && mouseY <= dialogY + 238 + bh {
                if mouseX >= dialogX + 118 - 35 && mouseX <= dialogX + 119 + bw {
                    transactionConfirmAccepted = 1
                    sendBare(acceptOpcode)
                } else if mouseX >= dialogX + 352 - 35 && mouseX <= dialogX + 354 + bw {
                    close(declineOpcode)
                }
            }
        }
        mouseButtonClick = 0
    }

    private func transactionDialogOrigin(confirm: Bool) -> (Int, Int) {
        let l = TransactionLayout(compact: transactionIsCompact)
        let x = surface.width / 2 - l.width / 2
        let y = surface.height / 2 - l.height / 2 + (l.compact ? (confirm ? -8 : 0) : 2)
        return (x, y)
    }

    // MARK: trade.c

    func drawTrade() {
        let (x, y) = transactionDialogOrigin(confirm: false)
        drawTransaction(dialogX: x, dialogY: y, isTrade: true)
    }

    func drawTradeConfirm() {
        let (x, y) = transactionDialogOrigin(confirm: true)
        drawTransactionConfirm(dialogX: x, dialogY: y, isTrade: true)
    }

    // MARK: duel.c

    private func drawDuelOption(x: Int, y: Int, width: Int, on: Int) {
        surface.drawBorder(x: x + width, y: y, width: Mudclient.duelCheckboxWidth, height: Mudclient.duelCheckboxHeight,
                           colour: Colour.yellow)
        if on != 0 {
            surface.drawBox(x: x + width + 2, y: y + 2, width: Mudclient.duelCheckboxWidth - 4,
                            height: Mudclient.duelCheckboxHeight - 4, colour: Colour.yellow)
        }
    }

    func drawDuel() {
        let l = TransactionLayout(compact: transactionIsCompact)
        let compact = l.compact
        let offerRows = compact ? 3 : 2
        let (dialogX, dialogY) = transactionDialogOrigin(confirm: false)
        let offsetX = compact ? 2 : 8
        let offsetY = compact ? offerRows * l.slotHeight + 40 : offerRows * l.slotHeight * 2 + 79
        let leftWidth = compact ? 49 : 85, rightWidth = compact ? 44 : 81
        let paddingLeft = offsetX + leftWidth + (compact ? 12 : 17)
        let cw = Mudclient.duelCheckboxWidth, ch = Mudclient.duelCheckboxHeight

        if mouseButtonClick != 0 {
            let mx = mouseX - dialogX, my = mouseY - dialogY
            var sendUpdate = false
            let inLeft = mx >= offsetX + leftWidth && mx <= offsetX + leftWidth + cw
            let inRight = mx >= paddingLeft + rightWidth && mx <= paddingLeft + rightWidth + cw
            let inTop = my >= offsetY + 6 && my <= offsetY + 6 + ch
            let inBottom = my >= offsetY + 25 && my <= offsetY + 25 + ch
            if inLeft && inTop { duelOptionRetreat = duelOptionRetreat == 0 ? 1 : 0; sendUpdate = true }
            if inLeft && inBottom { duelOptionMagic = duelOptionMagic == 0 ? 1 : 0; sendUpdate = true }
            if inRight && inTop { duelOptionPrayer = duelOptionPrayer == 0 ? 1 : 0; sendUpdate = true }
            if inRight && inBottom { duelOptionWeapons = duelOptionWeapons == 0 ? 1 : 0; sendUpdate = true }
            if sendUpdate {
                if let ps = packetStream {
                    ps.newPacket(ClientOpcode.duelOptions)
                    ps.putByte(duelOptionRetreat)
                    ps.putByte(duelOptionMagic)
                    ps.putByte(duelOptionPrayer)
                    ps.putByte(duelOptionWeapons)
                    ps.sendPacket()
                }
                transactionRecipientAccepted = 0
                transactionAccepted = 0
            }
        }

        drawTransaction(dialogX: dialogX, dialogY: dialogY, isTrade: false)
        guard showDialogDuel else { return }

        let optionsWidth = l.columns * l.slotWidth + 1
        let optionsHeight = ch * 2 + 22
        surface.drawBoxAlpha(x: dialogX + offsetX, y: dialogY + offsetY, width: optionsWidth, height: optionsHeight,
                             colour: Colour.greyD0, alpha: 160)
        surface.drawBorder(x: dialogX + offsetX, y: dialogY + offsetY, width: optionsWidth, height: optionsHeight,
                           colour: Colour.black)
        if !compact {
            surface.drawString("Duel Options", x: dialogX + offsetX + 1, y: dialogY + offsetY - 3, font: .bold14,
                               colour: Colour.white)
        }
        let labels = compact ? ["Retreat", "Magic", "Prayer", "Equip"]
            : ["No retreating", "No magic", "No prayer", "No weapons"]
        let values = [duelOptionRetreat, duelOptionMagic, duelOptionPrayer, duelOptionWeapons]
        for i in 0..<4 {
            let x = dialogX + (i < 2 ? offsetX + 1 : paddingLeft)
            let rowY = i % 2 == 0 ? 0 : 19
            surface.drawString(labels[i], x: x, y: dialogY + offsetY + 16 + rowY, font: .bold13, colour: Colour.yellow)
            drawDuelOption(x: dialogX + (i < 2 ? offsetX : paddingLeft), y: dialogY + offsetY + 6 + rowY,
                           width: i < 2 ? leftWidth : rightWidth, on: values[i])
        }
    }

    func drawDuelConfirm() {
        let l = TransactionLayout(compact: transactionIsCompact)
        let (dialogX, dialogY) = transactionDialogOrigin(confirm: true)
        drawTransactionConfirm(dialogX: dialogX, dialogY: dialogY, isTrade: false)
        if l.compact && transactionTab != 2 { return }
        let x = dialogX + l.width / 2
        var y = dialogY + (l.compact ? 52 : 180)
        let rules: [(Int, String, String)] = [
            (duelOptionRetreat, "You can retreat from this duel", "No retreat is possible!"),
            (duelOptionMagic, "Magic may be used", "Magic cannot be used"),
            (duelOptionPrayer, "Prayer may be used", "Prayer cannot be used"),
            (duelOptionWeapons, "Weapons may be used", "Weapons cannot be used"),
        ]
        for (value, allowed, banned) in rules {
            if value == 0 {
                surface.drawStringCentre(allowed, x: x, y: y, font: .bold12, colour: Colour.green)
            } else {
                surface.drawStringCentre(banned, x: x, y: y, font: .bold12, colour: Colour.red)
            }
            y += 12
        }
    }
}
