// Port of rsc-c ui/bank.c.

import Foundation

/// (int) of a float as x86 does it: NaN, infinity and out-of-range values become INT_MIN.
func cInt(_ f: Float) -> Int {
    guard f.isFinite, f > -2147483649, f < 2147483648 else { return Int(Int32.min) }
    return Int(f)
}

extension Mudclient {
    static let bankColumnsMin = 6, bankRowsMin = 3, bankColumns = 8, bankRows = 6, bankPageButtonWidth = 65
    static let bankMagicDeposit = 0x87654321, bankMagicWithdraw = 0x12345678, bankScrollSpeed = 120

    private var bankVisibleColumns: Int {
        guard surface.width < Mudclient.vanillaWidth || surface.height < Mudclient.vanillaHeight else {
            return Mudclient.bankColumns
        }
        return min((surface.width - 28) / Surface.itemGridSlotWidth, Mudclient.bankColumns)
    }

    func bankTransaction(itemId: Int, amount: Int, opcode: Int) {
        var amount = amount
        let withdraw = opcode == ClientOpcode.bankWithdraw
        if withdraw && gameData.items[itemId].stackable != 0 &&
            amount + inventoryItemsCount >= Mudclient.inventoryItemsMax {
            amount = Mudclient.inventoryItemsMax - inventoryItemsCount
            if amount <= 0 { return }
        }
        let total = Int(ceil(Float(amount) / 32767))
        for _ in 0..<max(total, 0) {
            var send = amount
            if send > 32767 {
                send = 32767
                amount -= 32767
            }
            if let ps = packetStream {
                ps.newPacket(opcode)
                ps.putShort(itemId)
                ps.putShort(send)
                ps.putInt(withdraw ? Mudclient.bankMagicWithdraw : Mudclient.bankMagicDeposit)
                ps.sendPacket()
            }
        }
        if bankSelectedItem != itemId {
            inputPmFinal = ""
            for i in 0..<bankItemCount where bankItems[i] == itemId {
                bankSelectedItemSlot = i
                bankSelectedItem = itemId
                break
            }
        }
        let compact = surface.width < Mudclient.vanillaWidth || surface.height < Mudclient.vanillaHeight
        let columns = bankVisibleColumns
        if compact || options.bankScroll != 0 {
            let row = bankSelectedItemSlot / columns
            if row < bankScrollRow || row > bankScrollRow + bankVisibleRows { bankScrollRow = row }
        } else {
            bankActivePage = bankSelectedItemSlot / (bankVisibleRows * columns)
        }
    }

    private func drawBankPage(x: Int, y: Int, page: Int, width: Int) {
        var colour = Colour.white
        if bankActivePage == page - 1 {
            colour = Colour.red
        } else if mouseX > x && mouseY >= y && mouseX < x + width && mouseY < y + 12 {
            colour = Colour.yellow
        }
        surface.drawString("<page \(page)>", x: x, y: y + 10, font: .bold12, colour: colour)
    }

    /// The x offsets and widths of the One/Five/10/50/X/last-X/All buttons.
    private func bankAmountHit(_ x: Int, _ y: Int, _ offset: Int, _ width: Int) -> Bool {
        mouseX >= x + offset && mouseY >= y && mouseX < x + offset + width && mouseY <= y + 11
    }

    func drawBankAmounts(amount: Int, lastX: Int, x: Int, y: Int) {
        var offset = 0
        func draw(_ text: String, _ width: Int, from: Int = 0) {
            let hit = mouseX >= x + offset + from && mouseY >= y && mouseX < x + offset + width && mouseY <= y + 11
            surface.drawString(text, x: x + offset + 2, y: y + 10, font: .bold12, colour: hit ? Colour.red : Colour.white)
        }
        draw("One", 30)
        offset += 30
        if amount >= 5 { draw("Five", 30) }
        offset += 30
        var uiAmount = options.offerX != 0 ? 10 : 25
        if amount >= uiAmount { draw("\(uiAmount)", 25) }
        offset += 25
        let showLast = options.offerX != 0 && options.lastOfferX != 0
        uiAmount = options.offerX != 0 ? 50 : 100
        if amount >= uiAmount { draw("\(uiAmount)", showLast ? 23 : 30) }
        offset += 30 - (showLast ? 7 : 0)
        uiAmount = options.offerX != 0 ? 2 : 500
        if amount >= uiAmount { draw(options.offerX != 0 ? "X" : "500", showLast ? 16 : 33) }
        offset += 33 - (showLast ? 17 : 0)
        if showLast && lastX != 0 && amount >= lastX {
            draw(ClientUtil.formatAmountSuffix(lastX, useColour: false, convertTenThousands: true, useCommas: false), 30)
        }
        if showLast { offset += 37 }
        uiAmount = options.offerX != 0 ? amount : 2500
        if amount >= uiAmount { draw(options.offerX != 0 ? "All" : "2500", 32, from: 2) }
    }

    func handleBankAmountsInput(itemId: Int, amount: Int, lastX: Int, x: Int, y: Int, opcode: Int) {
        var offset = 0
        if bankAmountHit(x, y, offset, 30) { bankTransaction(itemId: itemId, amount: 1, opcode: opcode) }
        offset += 30
        if amount >= 5 && bankAmountHit(x, y, offset, 30) { bankTransaction(itemId: itemId, amount: 5, opcode: opcode) }
        offset += 30
        var uiAmount = options.offerX != 0 ? 10 : 25
        if amount >= uiAmount && bankAmountHit(x, y, offset, 25) {
            bankTransaction(itemId: itemId, amount: uiAmount, opcode: opcode)
        }
        offset += 25
        let showLast = options.offerX != 0 && options.lastOfferX != 0
        uiAmount = options.offerX != 0 ? 50 : 100
        if amount >= uiAmount && bankAmountHit(x, y, offset, 30 - (showLast ? 7 : 0)) {
            bankTransaction(itemId: itemId, amount: uiAmount, opcode: opcode)
        }
        offset += 30 - (showLast ? 7 : 0)
        uiAmount = options.offerX != 0 ? 2 : 500
        if amount >= uiAmount && bankAmountHit(x, y, offset, 33 - (showLast ? 17 : 0)) {
            if options.offerX != 0 {
                bankOfferType = opcode == ClientOpcode.bankWithdraw ? BankOffer.withdraw : BankOffer.deposit
                offerId = itemId
                offerMax = amount
                inputDigitsFinal = 0
                showDialogOfferX = true
            } else {
                bankTransaction(itemId: itemId, amount: uiAmount, opcode: opcode)
            }
        }
        offset += 33 - (showLast ? 17 : 0)
        if showLast && lastX != 0 && bankAmountHit(x, y, offset, 30) {
            bankTransaction(itemId: itemId, amount: lastX, opcode: opcode)
        }
        if showLast { offset += 37 }
        uiAmount = options.offerX != 0 ? amount : 2500
        if amount >= uiAmount && mouseX >= x + offset + 2 && mouseY >= y && mouseX < x + offset + 32 &&
            mouseY <= y + 11 {
            bankTransaction(itemId: itemId, amount: uiAmount, opcode: opcode)
        }
    }

    func drawBank() {
        let compact = surface.width < Mudclient.vanillaWidth || surface.height < Mudclient.vanillaHeight
        var columns = Mudclient.bankColumns
        if compact {
            columns = (surface.width - 28) / Surface.itemGridSlotWidth
            if columns > Mudclient.bankColumns { columns = Mudclient.bankColumns }
            else if columns < Mudclient.bankColumnsMin { columns = Mudclient.bankColumnsMin }
        }
        let slotW = Surface.itemGridSlotWidth, slotH = Surface.itemGridSlotHeight
        let padding = (compact ? 100 : 142) + (isTouch ? 18 : 0)
        var rows = options.bankExpand != 0 ? (surface.height - padding) / slotH : Mudclient.bankRows
        if rows > 12 { rows = 12 } else if rows < Mudclient.bankRowsMin { rows = Mudclient.bankRowsMin }
        bankVisibleRows = rows
        let offsetY = compact ? 12 : 0
        let gridHeight = rows * slotH
        let bankHeight = gridHeight + 76 - offsetY
        var pageOffsetX = 50
        var pageWidth = Mudclient.bankPageButtonWidth
        let itemsPerPage = rows * columns
        var title = "Bank"
        if options.bankCapacity != 0 {
            title = cField("Bank (\(bankItemCount)/\(bankItemsMax))", 15)
            pageOffsetX = surface.textWidth(title, font: .bold12) + 5
            pageWidth = 60
        }
        let activePage = bankActivePage
        let itemOffset = compact || options.bankScroll != 0 ? bankScrollRow * columns : activePage * itemsPerPage

        var items = [Int](repeating: 0, count: Mudclient.bankItemsMax)
        var counts = [Int](repeating: 0, count: Mudclient.bankItemsMax)
        var count = 0
        if options.bankSearch != 0 && !inputPmCurrent.isEmpty {
            let search = inputPmCurrent.lowercased()
            var prefix: [(Int, Int)] = [], contains: [(Int, Int)] = []
            for i in 0..<bankItemCount {
                let name = gameData.items[bankItems[i]].name.lowercased()
                if prefix.count < Mudclient.bankItemsMax && name.hasPrefix(search) {
                    prefix.append((bankItems[i], bankItemsCount[i]))
                } else if contains.count < Mudclient.bankItemsMax && name.contains(search) {
                    contains.append((bankItems[i], bankItemsCount[i]))
                }
            }
            for (i, e) in prefix.enumerated() { items[i] = e.0; counts[i] = e.1 }
            for i in prefix.count..<Mudclient.bankItemsMax {
                let c = i - prefix.count
                if c < contains.count { items[i] = contains[c].0; counts[i] = contains[c].1 }
                else { items[i] = -1; counts[i] = 0 }
            }
            count = prefix.count + contains.count
        } else {
            count = bankItemCount
            for i in 0..<count { items[i] = bankItems[i]; counts[i] = bankItemsCount[i] }
        }

        let showScroll = (compact || options.bankScroll != 0) && count > rows * columns
        let maxScrollHeight = gridHeight - 28
        let totalRows = Int(ceil(Float(count) / Float(columns)))
        let scrubHeight = cInt(Float(maxScrollHeight) / (Float(totalRows) / Float(rows)))
        var bankWidth = slotW * columns + (compact ? 11 : 16)
        if showScroll { bankWidth += 13 } else { bankScrollRow = 0 }
        let invColumns = surface.height < 260 ? 6 : 5
        let inventoryWidth = slotW * invColumns
        let showInventory = options.bankInventory != 0 && surface.width > inventoryWidth + bankWidth + 15
        if showInventory {
            drawUITabInventory(noMenus: !showRightClickMenu && !showDialogOfferX)
        }
        let containWidth = showInventory && surface.width < inventoryWidth + bankWidth + 265
            ? surface.width - inventoryWidth - 4 : surface.width
        let uiX = containWidth / 2 - bankWidth / 2
        var uiY = surface.height / 2 - bankHeight / 2 - 30
        if uiY < 18 && options.bankMenus != 0 { uiY = 18 }
        if isTouch { uiY = 34 }
        let gridY = uiY + 28 - offsetY

        if inputDigitsFinal > 0 {
            if inputDigitsFinal > offerMax {
                showMessage("You don't have that many!", .game)
            } else {
                let withdraw = bankOfferType == BankOffer.withdraw
                bankTransaction(itemId: offerId, amount: inputDigitsFinal,
                                opcode: withdraw ? ClientOpcode.bankWithdraw : ClientOpcode.bankDeposit)
                if withdraw { bankLastWithdrawOffer = inputDigitsFinal } else { bankLastDepositOffer = inputDigitsFinal }
            }
            showDialogOfferX = false
            inputDigitsFinal = 0
        }
        if activePage > 0 && count <= itemsPerPage { bankActivePage = 0 }
        if activePage > 1 && count <= itemsPerPage * 2 { bankActivePage = 1 }
        if activePage > 2 && count <= itemsPerPage * 3 { bankActivePage = 2 }
        if bankSelectedItemSlot >= count || bankSelectedItemSlot < 0 { bankSelectedItemSlot = -1 }
        if bankSelectedItemSlot != -1 && items[bankSelectedItemSlot] != bankSelectedItem {
            if options.bankMaintainSlot != 0 {
                if bankSelectedItem != -2 {
                    for i in 0..<count where items[i] == bankSelectedItem {
                        bankSelectedItemSlot = i
                        break
                    }
                } else {
                    bankSelectedItemSlot = -1
                }
            } else {
                bankSelectedItemSlot = -1
                bankSelectedItem = -2
            }
        }
        let itemId = bankSelectedItemSlot < 0 ? -1 : items[bankSelectedItemSlot]

        var mx = mouseX - uiX
        var my = mouseY - uiY + offsetY
        var handled = false
        let searchY = uiY + gridHeight + (compact ? 66 : 92)
        let keyboardX = uiX + 49, keyboardY = searchY - 15

        if showDialogOfferX {
            handled = true
        } else if mouseButtonClick != 0 {
            if mouseX >= uiX && mouseX <= uiX + bankWidth && mouseY >= keyboardY && mouseY <= keyboardY + 20 {
                if isTouch {
                    triggerKeyboard(text: inputPmCurrent, isPassword: false, x: keyboardX, y: keyboardY,
                                    width: bankWidth - 49, height: 20, font: .bold12, isCentred: false)
                }
                bankSearchFocus = true
                mouseButtonClick = 0
            } else {
                bankSearchFocus = false
            }
        }

        if !handled && mx >= 0 && my >= 12 + offsetY && mx < bankWidth && my < gridHeight + 76 {
            handled = true
            var slot = itemOffset
            for row in 0..<rows {
                for column in 0..<columns {
                    let slotX = 7 + column * slotW, slotY = 28 + row * slotH
                    if mx > slotX && mx < slotX + slotW && my > slotY && my < slotY + slotH && slot < count &&
                        items[slot] != -1 {
                        let selectedId = items[slot]
                        let clicked = options.bankMenus != 0 ? !showRightClickMenu && mouseButtonClick == 1
                            : mouseButtonClick != 0
                        if !selectedWiki && !showDialogOfferX && clicked {
                            if bankSelectedItem != selectedId { mouseButtonClick = 0 }
                            bankSelectedItem = selectedId
                            bankSelectedItemSlot = slot
                        }
                        let name = "@lre@\(gameData.items[selectedId].name)"
                        if selectedWiki {
                            menuAddIdWiki(display: name, type: "item", id: selectedId)
                        } else if options.bankMenus != 0 && !showRightClickMenu {
                            addOfferMenus("Withdraw", type: MenuType.bankWithdraw, itemId: selectedId,
                                          itemAmount: counts[slot], itemName: name, lastX: bankLastWithdrawOffer)
                        }
                    }
                    slot += 1
                }
            }
        }

        let mouseInInventory = showInventory && mouseX > surface.width - inventoryWidth
        if !showRightClickMenu && mouseButtonClick != 0 && !mouseInInventory {
            var bankCount = bankSelectedItemSlot >= 0 ? counts[bankSelectedItemSlot] : 0
            if options.bankUnstackbleWithdraw == 0 && itemId >= 0 && gameData.items[itemId].stackable == 1 &&
                bankCount > 1 {
                bankCount = 1
            }
            let offsetX = compact ? 100 : 0
            if bankCount > 0 {
                handleBankAmountsInput(itemId: itemId, amount: bankCount, lastX: bankLastWithdrawOffer,
                                       x: uiX + 220 - offsetX, y: uiY + gridHeight + (compact ? 20 : 34),
                                       opcode: ClientOpcode.bankWithdraw)
            }
            let held = inventoryCount(itemId)
            if held > 0 {
                handleBankAmountsInput(itemId: itemId, amount: held, lastX: bankLastDepositOffer,
                                       x: uiX + 220 - offsetX, y: uiY + gridHeight + (compact ? 39 : 59),
                                       opcode: ClientOpcode.bankDeposit)
            }
            if showDialogOfferX && mx > 0 && mx < bankWidth && my > 0 && my < bankHeight {
                mx = 0
                my = 13
            }
            if !handled {
                let pageHit = !showScroll && my <= 12
                if pageHit && count > itemsPerPage && mx >= pageOffsetX && mx <= pageOffsetX + pageWidth {
                    bankActivePage = 0
                } else if pageHit && count > itemsPerPage && mx >= pageOffsetX + pageWidth &&
                            mx <= pageOffsetX + pageWidth * 2 {
                    bankActivePage = 1
                } else if pageHit && count > itemsPerPage * 2 && mx >= pageOffsetX + pageWidth * 2 &&
                            mx <= pageOffsetX + pageWidth * 3 {
                    bankActivePage = 2
                } else if pageHit && count > itemsPerPage * 3 && mx >= pageOffsetX + pageWidth * 3 &&
                            mx <= pageOffsetX + pageWidth * 4 {
                    bankActivePage = 3
                } else {
                    if let ps = packetStream { ps.newPacket(ClientOpcode.bankClose); ps.sendPacket() }
                    showDialogBank = false
                    showDialogOfferX = false
                    return
                }
            }
        }

        if showScroll && !showRightClickMenu && !showDialogOfferX {
            if !isTouch && mouseScrollDelta != 0 { bankScrollRow -= mouseScrollDelta * -1 }
            let now = Int(ClientTime.ticks())
            if (mouseButtonDown != 0 || Mudclient.finger1Down != 0) && now - bankLastScroll > Mudclient.bankScrollSpeed {
                let scrollbarX = slotW * columns + (compact ? 6 : 8)
                if bankScrollRow > 0 && mouseX > uiX + scrollbarX && mouseX < uiX + scrollbarX + 21 &&
                    mouseY > gridY && mouseY < gridY + 15 {
                    bankScrollRow -= 1
                    bankLastScroll = Int(ClientTime.ticks())
                }
                var dragging = bankHandleDragged
                if options.offHandleScrollDrag == 0 {
                    dragging = dragging && mouseX >= uiX + scrollbarX - 12 && mouseX <= uiX + scrollbarX + 33
                }
                if (dragging || (mouseX > uiX + scrollbarX && mouseX < uiX + scrollbarX + 21)) &&
                    mouseY > gridY + 15 && mouseY < uiY + gridHeight + 15 - offsetY {
                    let scrubY = mouseY - (uiY + 43 - offsetY) - scrubHeight / 2
                    bankScrollRow = cInt(Float(scrubY) / Float(maxScrollHeight) * Float(totalRows))
                    bankHandleDragged = true
                }
                if bankScrollRow < totalRows - rows && mouseX > uiX + scrollbarX && mouseX < uiX + scrollbarX + 21 &&
                    mouseY > uiY + gridHeight + 15 - offsetY && mouseY < uiY + gridHeight + 30 - offsetY {
                    bankScrollRow += 1
                    bankLastScroll = Int(ClientTime.ticks())
                }
            } else {
                bankHandleDragged = false
            }
            if bankScrollRow < 0 { bankScrollRow = 0 }
            else if bankScrollRow > totalRows - rows { bankScrollRow = totalRows - rows }
        }

        surface.drawBox(x: uiX, y: uiY, width: bankWidth, height: 12, colour: Colour.titleBar)
        surface.drawBoxAlpha(x: uiX, y: uiY + 12, width: bankWidth, height: 17 - offsetY, colour: Colour.grey98,
                             alpha: 160)
        surface.drawBoxAlpha(x: uiX, y: uiY + 29 - offsetY, width: compact ? 5 : 8, height: gridHeight,
                             colour: Colour.grey98, alpha: 160)
        surface.drawBoxAlpha(x: uiX + slotW * columns + (compact ? 5 : 7), y: uiY + 29 - offsetY,
                             width: 9 + (showScroll ? 13 : 0) - (compact ? 3 : 0), height: gridHeight,
                             colour: Colour.grey98, alpha: 160)
        surface.drawString(title, x: uiX + 1, y: uiY + 10, font: .bold12, colour: Colour.white)
        if !showScroll {
            if count > itemsPerPage {
                drawBankPage(x: uiX + pageOffsetX, y: uiY, page: 1, width: pageWidth)
                pageOffsetX += pageWidth
                drawBankPage(x: uiX + pageOffsetX, y: uiY, page: 2, width: pageWidth)
                pageOffsetX += pageWidth
            }
            if count > itemsPerPage * 2 {
                drawBankPage(x: uiX + pageOffsetX, y: uiY, page: 3, width: pageWidth)
                pageOffsetX += pageWidth
            }
            if count > itemsPerPage * 3 {
                drawBankPage(x: uiX + pageOffsetX, y: uiY, page: 4, width: pageWidth)
                pageOffsetX += pageWidth
            }
        }
        let closeHover = mouseX > uiX + bankWidth - 88 && mouseY >= uiY && mouseX < uiX + bankWidth && mouseY < uiY + 12
        surface.drawStringRight("Close window", x: uiX + bankWidth - 2, y: uiY + 10, font: .bold12,
                                colour: closeHover ? Colour.red : Colour.white)
        if !compact {
            surface.drawString("Number in bank in green", x: uiX + 7, y: uiY + 24, font: .bold12, colour: Colour.green)
            surface.drawString("Number held in blue", x: uiX + bankWidth - 119, y: uiY + 24, font: .bold12,
                               colour: Colour.cyan)
            if options.bankValue != 0 {
                var total: Int32 = 0
                for i in 0..<bankItemCount {
                    let price = Int32(truncatingIfNeeded: gameData.items[bankItems[i]].basePrice)
                    for _ in 0..<max(bankItemsCount[i], 0) { total = total &+ price }
                    if total < 0 { break }
                }
                let money = total < 0 ? "Total value: a lot!" : "Total value: \(formatNumberCommas(Int(total)))gp"
                surface.drawStringCentre(money, x: uiX + bankWidth / 2 + 12, y: uiY + 24,
                                         font: total >= 10_000_000 ? .regular11 : .bold12, colour: Colour.yellow)
            }
        }
        let gridEnd = max(itemOffset, min(itemOffset + (count - itemOffset), Mudclient.bankItemsMax))
        let gridItems = itemOffset < Mudclient.bankItemsMax ? Array(items[itemOffset..<max(itemOffset, gridEnd)]) : []
        let gridCounts = itemOffset < Mudclient.bankItemsMax ? Array(counts[itemOffset..<max(itemOffset, gridEnd)]) : []
        surface.drawItemGrid(x: uiX + (compact ? 5 : 7), y: gridY, rows: rows, columns: columns, slotWidth: slotW,
                             slotHeight: slotH, items: gridItems, counts: gridCounts,
                             selected: bankSelectedItemSlot - itemOffset, showInventoryCount: true,
                             stackableFlag: { self.gameData.items[$0].stackable })
        if showScroll {
            let scrubY = cInt(Float(bankScrollRow) / Float(totalRows) * Float(maxScrollHeight))
            let scrollbarX = slotW * columns - (compact ? 4 : 0)
            surface.drawScrollbar(x: uiX + 24, y: gridY, width: scrollbarX, height: gridHeight, scrubY: 1 + scrubY,
                                  scrubHeight: scrubHeight)
            surface.drawLineVertical(x: uiX + scrollbarX + 24, y: gridY, height: gridHeight + 1, colour: Colour.black)
            surface.drawLineHorizontal(x: uiX + scrollbarX + 12, y: gridY + gridHeight, width: 12, colour: Colour.black)
        }
        surface.drawBoxAlpha(x: uiX, y: uiY + (gridHeight - 204) + 233 - offsetY, width: bankWidth,
                             height: 47 - offsetY, colour: Colour.grey98, alpha: 160)
        surface.drawLineHorizontal(x: uiX + 5, y: uiY + gridHeight + (compact ? 34 : 52), width: bankWidth - 10,
                                   colour: Colour.black)
        if options.bankSearch != 0 {
            surface.drawBoxAlpha(x: uiX, y: uiY + gridHeight + (compact ? 52 : 76), width: bankWidth,
                                 height: compact ? 18 : 20, colour: Colour.grey98, alpha: 160)
            surface.drawLineHorizontal(x: uiX + 5, y: uiY + gridHeight + (compact ? 52 : 76), width: bankWidth - 10,
                                       colour: Colour.black)
            surface.drawString("Search: \(inputPmCurrent)\(bankSearchFocus ? "*" : " ")", x: uiX + 2, y: searchY,
                               font: .bold12, colour: Colour.white)
        }
        if itemId != -1 {
            var bankCount = counts[bankSelectedItemSlot]
            if options.bankUnstackbleWithdraw == 0 && gameData.items[itemId].stackable == 1 && bankCount > 1 {
                bankCount = 1
            }
            let offsetX = compact ? 100 : 0
            let name = gameData.items[itemId].name
            if bankCount > 0 {
                surface.drawString("Withdraw \(compact ? "" : name)", x: uiX + 2, y: uiY + gridHeight + (compact ? 30 : 44),
                                   font: .bold12, colour: Colour.white)
                drawBankAmounts(amount: bankCount, lastX: bankLastWithdrawOffer, x: uiX + 220 - offsetX,
                                y: uiY + gridHeight + (compact ? 20 : 34))
            }
            let held = inventoryCount(itemId)
            if held > 0 {
                surface.drawString("Deposit \(compact ? "" : name)", x: uiX + 2, y: uiY + gridHeight + (compact ? 48 : 69),
                                   font: .bold12, colour: Colour.white)
                drawBankAmounts(amount: held, lastX: bankLastDepositOffer, x: uiX + 220 - offsetX,
                                y: uiY + gridHeight + (compact ? 39 : 59))
            }
        } else {
            surface.drawStringCentre("Select an object to withdraw or deposit", x: uiX + bankWidth / 2,
                                     y: uiY + gridHeight + (compact ? 30 : 44), font: .bold13, colour: Colour.yellow)
        }
        if showDialogOfferX {
            drawOfferX()
            handleOfferXInput()
        }
    }
}
