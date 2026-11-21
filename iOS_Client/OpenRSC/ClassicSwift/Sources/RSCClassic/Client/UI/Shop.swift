// Port of rsc-c ui/shop.c.

import Foundation

extension Mudclient {
    static let shopColumns = 8, shopRows = 5

    private func shopPrice(_ index: Int, mod: Int) -> Int {
        var priceMod = mod + shopItemsPrice[index]
        if priceMod < 10 { priceMod = 10 }
        return (priceMod * gameData.items[shopItems[index]].basePrice) / 100
    }

    private func sendShopTrade(_ opcode: Int, itemId: Int, price: Int) {
        guard let ps = packetStream else { return }
        ps.newPacket(opcode)
        ps.putShort(itemId)
        ps.putInt(price)
        ps.sendPacket()
    }

    func drawShop() {
        let cols = Mudclient.shopColumns, rows = Mudclient.shopRows
        let compact = surface.width < cols * Surface.itemGridSlotWidth + 16 ||
            surface.height < rows * Surface.itemGridSlotHeight + 96
        let slotWidth = compact ? 39 : Surface.itemGridSlotWidth
        let slotHeight = compact ? 27 : Surface.itemGridSlotHeight
        let shopWidth = slotWidth * cols + (compact ? 11 : 16)
        let shopHeight = slotHeight * rows + 76
        let gridHeight = slotHeight * rows
        let x = surface.width / 2 - shopWidth / 2
        let y = surface.height / 2 - shopHeight / 2 - 6
        let mx = mouseX - x, my = mouseY - y

        if shopSelectedItemIndex >= 0 && (mouseButtonClick != 0 || mouseItemCountIncrement != 0) {
            let itemId = shopItems[shopSelectedItemIndex]
            if itemId != -1 {
                // The compact test compares the panel-relative mouse with the absolute x, as C does.
                if shopItemsCount[shopSelectedItemIndex] > 0 &&
                    (compact ? (mx > x && mx < shopWidth) : (mx > shopWidth - 110 && mx < shopWidth)) &&
                    my >= gridHeight + 34 && my <= gridHeight + 45 {
                    sendShopTrade(ClientOpcode.shopBuy, itemId: itemId,
                                  price: shopPrice(shopSelectedItemIndex, mod: shopBuyPriceMod))
                } else if inventoryCount(itemId) > 0 &&
                    (compact ? (mx > x && mx < shopWidth) : (mx > 2 && mx < 112)) &&
                    my >= gridHeight + 59 && my <= gridHeight + 70 {
                    sendShopTrade(ClientOpcode.shopSell, itemId: itemId,
                                  price: shopPrice(shopSelectedItemIndex, mod: shopSellPriceMod))
                } else {
                    mouseItemCountIncrement = 0
                }
            }
        }

        if mouseButtonClick != 0 {
            mouseButtonClick = 0
            if mx >= 0 && my >= 12 && mx < shopWidth && my < shopHeight {
                var index = 0
                for row in 0..<rows {
                    for column in 0..<cols {
                        let slotX = 7 + column * slotWidth
                        let slotY = 28 + row * slotHeight
                        if mx > slotX && mx < slotX + slotWidth && my > slotY && my < slotY + slotHeight &&
                            shopItems[index] != -1 {
                            shopSelectedItemIndex = index
                            shopSelectedItemType = shopItems[index]
                        }
                        index += 1
                    }
                }
            } else {
                if let ps = packetStream {
                    ps.newPacket(ClientOpcode.shopClose)
                    ps.sendPacket()
                }
                showDialogShop = false
                return
            }
        }

        surface.drawBox(x: x, y: y, width: shopWidth, height: 12, colour: Colour.titleBar)
        surface.drawBoxAlpha(x: x, y: y + 12, width: shopWidth, height: 17, colour: Colour.grey98, alpha: 160)
        surface.drawBoxAlpha(x: x, y: y + 29, width: compact ? 5 : 8, height: gridHeight, colour: Colour.grey98, alpha: 160)
        surface.drawBoxAlpha(x: x + slotWidth * cols + (compact ? 5 : 7), y: y + 29, width: compact ? 6 : 9,
                             height: gridHeight, colour: Colour.grey98, alpha: 160)
        surface.drawBoxAlpha(x: x, y: y + gridHeight + 29, width: shopWidth, height: 47, colour: Colour.grey98, alpha: 160)
        surface.drawString("Buying and selling items", x: x + 1, y: y + 10, font: .bold12, colour: Colour.white)

        var textColour = Colour.white
        if mouseX > x + shopWidth - 88 && mouseY >= y && mouseX < x + shopWidth && mouseY < y + 12 {
            textColour = Colour.red
        }
        surface.drawStringRight("Close window", x: x + shopWidth - 2, y: y + 10, font: .bold12, colour: textColour)
        if !compact {
            surface.drawString("Shops stock in green", x: x + 2, y: y + 24, font: .bold12, colour: Colour.green)
            surface.drawString("Number you own in blue", x: x + 135, y: y + 24, font: .bold12, colour: Colour.cyan)
        }
        let money = "Your money: \(formatNumberCommas(inventoryCount(Mudclient.coinsId)))gp"
        if compact {
            surface.drawStringCentre(money, x: x + shopWidth / 2, y: y + 24, font: .bold12, colour: Colour.yellow)
        } else {
            surface.drawString(money, x: x + 280, y: y + 24, font: .bold12, colour: Colour.yellow)
        }

        let length = rows * cols
        surface.drawItemGrid(x: x + (compact ? 4 : 7), y: y + 28, rows: rows, columns: cols, slotWidth: slotWidth,
                             slotHeight: slotHeight, items: Array(shopItems[0..<length]),
                             counts: Array(shopItemsCount[0..<length]), selected: shopSelectedItemIndex,
                             showInventoryCount: true, stackableFlag: { self.gameData.items[$0].stackable })
        surface.drawLineHorizontal(x: x + 5, y: y + gridHeight + 52, width: shopWidth - 10, colour: Colour.black)

        if shopSelectedItemIndex == -1 {
            surface.drawStringCentre("Select an object to buy or sell", x: x + shopWidth / 2, y: y + gridHeight + 44,
                                     font: .bold13, colour: Colour.yellow)
            return
        }

        let selectedId = shopItems[shopSelectedItemIndex]
        guard selectedId != -1 else { return }
        let tapWord = isTouch ? "Tap" : "Click"
        if shopItemsCount[shopSelectedItemIndex] > 0 {
            let price = shopPrice(shopSelectedItemIndex, mod: shopBuyPriceMod)
            let buy = "Buy a new \(gameData.items[selectedId].name) for \(price)gp"
            let overBuyRow = mouseY >= y + gridHeight + 34 && mouseX < x + shopWidth && mouseY <= y + gridHeight + 45
            if compact {
                textColour = mouseX > x && overBuyRow ? Colour.red : Colour.white
                surface.drawStringCentre(buy, x: x + shopWidth / 2, y: y + gridHeight + 44, font: .bold12,
                                         colour: textColour)
            } else {
                surface.drawString(buy, x: x + 2, y: y + gridHeight + 44, font: .bold12, colour: Colour.yellow)
                textColour = mouseX > x + shopWidth - 110 && overBuyRow ? Colour.red : Colour.white
                surface.drawStringRight("\(tapWord) here to buy", x: x + shopWidth - 3, y: y + gridHeight + 44,
                                        font: .bold13, colour: textColour)
            }
        } else {
            surface.drawStringCentre("This item is not currently available to buy", x: x + shopWidth / 2,
                                     y: y + gridHeight + 44, font: .bold13, colour: Colour.yellow)
        }

        if inventoryCount(selectedId) > 0 {
            let price = shopPrice(shopSelectedItemIndex, mod: shopSellPriceMod)
            let sell = cField("Sell your \(gameData.items[selectedId].name) for \(price)gp", 256)
            let overSellRow = mouseY >= y + gridHeight + 59 && mouseY <= y + gridHeight + 70
            if compact {
                textColour = mouseX > x && overSellRow && mouseX < x + shopWidth ? Colour.red : Colour.white
                surface.drawStringCentre(sell, x: x + shopWidth / 2, y: y + gridHeight + 69, font: .bold12,
                                         colour: textColour)
            } else {
                surface.drawStringRight(sell, x: x + shopWidth - 3, y: y + gridHeight + 69, font: .bold12,
                                        colour: Colour.yellow)
                textColour = mouseX > x + 2 && overSellRow && mouseX < x + 112 ? Colour.red : Colour.white
                surface.drawString("\(tapWord) here to sell", x: x + 2, y: y + gridHeight + 69, font: .bold13,
                                   colour: textColour)
            }
            return
        }
        surface.drawStringCentre("You do not have any of this item to sell", x: x + shopWidth / 2,
                                 y: y + gridHeight + 69, font: .bold13, colour: Colour.yellow)
    }
}
