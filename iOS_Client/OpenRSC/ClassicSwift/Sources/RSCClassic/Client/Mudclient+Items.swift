// Item helpers from rsc-c's mudclient.c and the Surface callbacks.

extension Mudclient {
    public func isItemEquipped(_ id: Int) -> Bool {
        (0..<inventoryItemsCount).contains { inventoryItemId[$0] == id && inventoryEquipped[$0] != 0 }
    }

    public func inventoryCount(_ id: Int) -> Int {
        var count = 0
        for i in 0..<inventoryItemsCount where inventoryItemId[i] == id {
            count += gameData.items[id].stackable == 1 ? 1 : inventoryItemStackCount[i]
        }
        return count
    }

    public func hasInventoryItem(_ id: Int, minimum: Int) -> Bool {
        let staffs: [Int: [Int]] = [31: [197, 615, 682], 32: [102, 616, 683], 33: [101, 617, 684], 34: [103, 618, 685]]
        if let s = staffs[id], s.contains(where: isItemEquipped) { return true }
        return inventoryCount(id) >= minimum
    }

    public var isUIScaled: Bool {
        options.uiScale != 0 && gameWidth >= Mudclient.width * 2 && gameHeight >= Mudclient.height * 2
    }

    public func formatNumberCommas(_ number: Int) -> String {
        options.numberCommas != 0 ? ClientUtil.formatNumberCommas(number) : String(number)
    }

    public func formatItemAmountText(_ amount: Int) -> String {
        options.condenseItemAmounts != 0
            ? ClientUtil.formatAmountSuffix(amount, useColour: true, convertTenThousands: false,
                                            useCommas: options.numberCommas != 0)
            : formatNumberCommas(amount)
    }

    public var wildernessDepth: Int {
        if localRegionX + planeWidth + regionX >= 2640 { return -50 }
        return 2203 - (localRegionY + planeHeight + regionY)
    }

    /// mudclient_draw_item: an inventory slot item, with the noted item drawn on top of certificates.
    public func drawInventoryItem(x: Int, y: Int, slotWidth: Int, slotHeight: Int, itemId: Int) {
        let certificate = options.certificateItems != 0 ? ClientUtil.certificateItemId(itemId) : -1
        let offsetX = certificate != -1 ? -2 : 0
        surface.drawItem(x: x + offsetX, y: y, slotWidth: slotWidth, slotHeight: slotHeight, item: gameData.items[itemId])
        if certificate != -1 {
            let w = Float(Surface.itemGridSlotWidth - 1), h = Float(Surface.itemGridSlotHeight - 2)
            let item = gameData.items[certificate]
            surface.drawSpriteTransformMask(x: Int(Float(x + 4) + w * 0.125), y: Int(Float(y + 2) + h * 0.125),
                                            width: Int(w * 0.75), height: Int(h * 0.75), id: spriteItem + item.sprite,
                                            maskColour: Int32(item.mask), skinColour: 0, skewX: 0, flip: false)
        }
    }
}

extension Mudclient: SurfaceHost {
    public func drawItem(x: Int, y: Int, slotWidth: Int, slotHeight: Int, itemId: Int) {
        drawInventoryItem(x: x, y: y, slotWidth: slotWidth, slotHeight: slotHeight, itemId: itemId)
    }

    public func formatItemAmount(_ amount: Int) -> String { formatItemAmountText(amount) }
    public func inventoryCount(itemId: Int) -> Int { inventoryCount(itemId) }
    public var ranTargetFps: Int { options.ranTargetFps }

    public func drawMagicBubble(x: Int, y: Int, width: Int, height: Int, id: Int) {
        drawMagicBubbleSprite(x: x, y: y, width: width, height: height, id: id)
    }

    public func drawGroundItem(x: Int, y: Int, width: Int, height: Int, id: Int) {
        drawGroundItemSprite(x: x, y: y, width: width, height: height, id: id)
    }

    public func drawNpc(x: Int, y: Int, width: Int, height: Int, id: Int, tx: Int, ty: Int) {
        drawNpcSprite(x: x, y: y, width: width, height: height, id: id, skewX: tx, ty: ty)
    }

    public func drawPlayer(x: Int, y: Int, width: Int, height: Int, id: Int, tx: Int, ty: Int) {
        drawPlayerSprite(x: x, y: y, width: width, height: height, id: id, skewX: tx, ty: ty)
    }
}
