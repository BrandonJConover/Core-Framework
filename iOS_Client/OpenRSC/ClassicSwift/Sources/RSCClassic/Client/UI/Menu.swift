// Port of rsc-c ui/menu.c (right-click and top-left mouse menus) and the
// walk_to helpers from mudclient.c.

import Foundation

/// MenuType: a higher number is a lower priority in the context menu.
public enum MenuType {
    public static let castGroundItem = 200, useWithGroundItem = 210, groundItemTake = 220
    public static let groundItemExamine = 3200
    public static let castWallObject = 300, useWithWallObject = 310, wallObjectCommand1 = 320
    public static let wallObjectCommand2 = 2300, wallObjectExamine = 3300
    public static let castObject = 400, useWithObject = 410, objectCommand1 = 420
    public static let objectCommand2 = 2400, objectExamine = 3400
    public static let castInvItem = 600, useWithInvItem = 610, inventoryUnequip = 620
    public static let inventoryWear = 630, inventoryCommand = 640, inventoryUse = 650
    public static let inventoryDrop = 660, inventoryExamine = 3600
    public static let castNpc = 700, useWithNpc = 710, npcTalk = 720, npcCommand = 725
    public static let npcAttack1 = 715, npcAttack2 = 2715, npcExamine = 3700
    public static let castPlayer = 800, useWithPlayer = 810, playerAttack1 = 805
    public static let playerAttack2 = 2805, playerDuel = 2806, playerTrade = 2810, playerFollow = 2820
    public static let castGround = 900, walk = 920, castSelf = 1000
    public static let bankWithdraw = 601, bankDeposit = 602
    public static let transactionOffer = 603, transactionRemove = 604
    public static let mapLook = 101
    public static let wikiLookup = 102
    public static let cancel = 4000
}

public enum BankOffer { public static let withdraw = 1, deposit = 2 }
public enum TransactionOffer { public static let offer = 0, remove = 1 }

/// snprintf into a fixed `char[size]` field: at most size - 1 bytes survive.
func cField(_ text: String, _ size: Int = 64) -> String {
    let bytes = Surface.bytes(text)
    if bytes.count < size { return text }
    return String(decoding: bytes.prefix(size - 1), as: Latin1.self)
}

extension Mudclient {
    public static let tileFaceTag = 200000
    static let wikiTypePage = "Special:Lookup?type=%@&id=%d&name=%@"

    private var menuEntryHeight: Int { isTouch ? 19 : 15 }

    /// Makes sure menu_items[index] exists (C writes one past the count before incrementing).
    func ensureMenuSlot(_ index: Int) {
        while menuItems.count <= index {
            menuItems.append(MenuEntry())
            menuIndices.append(0)
        }
    }

    /// Writes into menu_items[menu_items_count] with C's 64-byte field truncation.
    func withMenuEntry(_ body: (inout MenuEntry) -> Void) {
        ensureMenuSlot(menuItemsCount)
        body(&menuItems[menuItemsCount])
        menuItems[menuItemsCount].actionText = cField(menuItems[menuItemsCount].actionText)
        menuItems[menuItemsCount].targetText = cField(menuItems[menuItemsCount].targetText)
        menuItems[menuItemsCount].wikiPage = cField(menuItems[menuItemsCount].wikiPage, 256)
    }

    private func send(_ opcode: Int, _ body: (PacketStream) -> Void) {
        guard let ps = packetStream else { return }
        ps.newPacket(opcode)
        body(ps)
        ps.sendPacket()
    }

    // MARK: - walk_to (mudclient.c)

    @discardableResult
    func walkTo(startX: Int, startY: Int, x1: Int, y1: Int, x2: Int, y2: Int, checkObjects: Bool,
                walkToAction: Bool, firstStep: Bool) -> Bool {
        var steps = world.route(startX: startX, startY: startY, endX1: x1, endY1: y1, endX2: x2, endY2: y2,
                                routeX: &walkPathX, routeY: &walkPathY, objects: checkObjects)
        if steps == -1 {
            if firstStep && walkToAction {
                steps = 1
                walkPathX[0] = x1
                walkPathY[0] = y1
            } else {
                return false
            }
        }
        steps -= 1
        let sx = walkPathX[steps], sy = walkPathY[steps]
        steps -= 1
        if walkToAction && steps == -1 && (sx + regionX) % 5 == 0 { steps = 0 }
        let path = steps
        send(walkToAction ? ClientOpcode.walkAction : ClientOpcode.walk) { ps in
            ps.putShort(sx + regionX)
            ps.putShort(sy + regionY)
            var i = path
            while i >= 0 && i > path - 25 {
                ps.putByte(walkPathX[i] - sx)
                ps.putByte(walkPathY[i] - sy)
                i -= 1
            }
        }
        mouseClickXStep = -24
        mouseClickXX = mouseX
        mouseClickXY = mouseY
        return true
    }

    func walkToActionSource(startX: Int, startY: Int, destX: Int, destY: Int, action: Bool) {
        walkTo(startX: startX, startY: startY, x1: destX, y1: destY, x2: destX, y2: destY,
               checkObjects: false, walkToAction: action, firstStep: true)
    }

    func walkToGroundItem(startX: Int, startY: Int, destX: Int, destY: Int, walkToAction: Bool) {
        if walkTo(startX: startX, startY: startY, x1: destX, y1: destY, x2: destX, y2: destY,
                  checkObjects: false, walkToAction: walkToAction, firstStep: false) {
            return
        }
        walkTo(startX: startX, startY: startY, x1: destX, y1: destY, x2: destX, y2: destY,
               checkObjects: true, walkToAction: walkToAction, firstStep: true)
    }

    func walkToWallObject(destX: Int, destY: Int, direction: Int) {
        let sx = localRegionX, sy = localRegionY
        if direction == 0 {
            walkTo(startX: sx, startY: sy, x1: destX, y1: destY - 1, x2: destX, y2: destY,
                   checkObjects: false, walkToAction: true, firstStep: true)
        } else if direction == 1 {
            walkTo(startX: sx, startY: sy, x1: destX - 1, y1: destY, x2: destX, y2: destY,
                   checkObjects: false, walkToAction: true, firstStep: true)
        } else {
            walkTo(startX: sx, startY: sy, x1: destX, y1: destY, x2: destX, y2: destY,
                   checkObjects: true, walkToAction: true, firstStep: true)
        }
    }

    func walkToObject(x: Int, y: Int, direction: Int, id: Int) {
        var x = x, y = y
        let def = gameData.objects[id]
        var width: Int, height: Int
        if direction == World.dirNorth || direction == World.dirSouth {
            width = def.width; height = def.height
        } else {
            height = def.width; width = def.height
        }
        if def.type == 2 || def.type == 3 {
            if direction == World.dirNorth {
                x -= 1; width += 1
            } else if direction == World.dirWest {
                height += 1
            } else if direction == World.dirSouth {
                width += 1
            } else if direction == World.dirEast {
                y -= 1; height += 1
            }
            walkTo(startX: localRegionX, startY: localRegionY, x1: x, y1: y, x2: x + width - 1, y2: y + height - 1,
                   checkObjects: false, walkToAction: true, firstStep: true)
        } else {
            walkTo(startX: localRegionX, startY: localRegionY, x1: x, y1: y, x2: x + width - 1, y2: y + height - 1,
                   checkObjects: true, walkToAction: true, firstStep: true)
        }
    }

    // MARK: - menu_item_click

    func menuItemClick(_ i: Int) {
        ensureMenuSlot(i)
        let item = menuItems[i]
        let mx = item.x, my = item.y, index = item.index
        let source = item.sourceIndex, target = item.targetIndex
        let charX = (mx - 64) / Mudclient.magicLoc, charY = (my - 64) / Mudclient.magicLoc

        switch item.type {
        case MenuType.castGroundItem, MenuType.useWithGroundItem, MenuType.groundItemTake:
            walkToGroundItem(startX: localRegionX, startY: localRegionY, destX: mx, destY: my, walkToAction: true)
            let op = item.type == MenuType.castGroundItem ? ClientOpcode.castGrounditem
                : item.type == MenuType.useWithGroundItem ? ClientOpcode.usewithGrounditem : ClientOpcode.grounditemTake
            send(op) { ps in
                ps.putShort(mx + regionX); ps.putShort(my + regionY)
                ps.putShort(index); ps.putShort(source)
            }
            if item.type == MenuType.castGroundItem { selectedSpell = -1 }
            if item.type == MenuType.useWithGroundItem { selectedItemInventoryIndex = -1 }
        case MenuType.groundItemExamine:
            showMessage(gameData.items[index].description, .game)
        case MenuType.castWallObject, MenuType.useWithWallObject:
            walkToWallObject(destX: mx, destY: my, direction: index)
            let cast = item.type == MenuType.castWallObject
            send(cast ? ClientOpcode.castWallobject : ClientOpcode.usewithWallobject) { ps in
                ps.putShort(mx + regionX); ps.putShort(my + regionY)
                ps.putByte(index); ps.putShort(source)
            }
            if cast { selectedSpell = -1 } else { selectedItemInventoryIndex = -1 }
        case MenuType.wallObjectCommand1, MenuType.wallObjectCommand2:
            walkToWallObject(destX: mx, destY: my, direction: index)
            send(item.type == MenuType.wallObjectCommand1 ? ClientOpcode.wallObjectCommand1
                    : ClientOpcode.wallObjectCommand2) { ps in
                ps.putShort(mx + regionX); ps.putShort(my + regionY); ps.putByte(index)
            }
        case MenuType.wallObjectExamine:
            showMessage(gameData.walls[index].description, .game)
        case MenuType.castObject, MenuType.useWithObject:
            walkToObject(x: mx, y: my, direction: index, id: source)
            let cast = item.type == MenuType.castObject
            send(cast ? ClientOpcode.castObject : ClientOpcode.usewithObject) { ps in
                ps.putShort(mx + regionX); ps.putShort(my + regionY); ps.putShort(target)
            }
            if cast { selectedSpell = -1 } else { selectedItemInventoryIndex = -1 }
        case MenuType.objectCommand1, MenuType.objectCommand2:
            walkToObject(x: mx, y: my, direction: index, id: source)
            send(item.type == MenuType.objectCommand1 ? ClientOpcode.objectCommand1 : ClientOpcode.objectCommand2) { ps in
                ps.putShort(mx + regionX); ps.putShort(my + regionY)
            }
        case MenuType.objectExamine:
            showMessage(gameData.objects[index].description, .game)
        case MenuType.castInvItem:
            send(ClientOpcode.castInvitem) { ps in ps.putShort(index); ps.putShort(source) }
            selectedSpell = -1
        case MenuType.useWithInvItem:
            send(ClientOpcode.usewithInvitem) { ps in ps.putShort(index); ps.putShort(source) }
            selectedItemInventoryIndex = -1
        case MenuType.inventoryUnequip:
            send(ClientOpcode.inventoryUnequip) { ps in ps.putShort(index) }
        case MenuType.inventoryWear:
            send(ClientOpcode.inventoryWear) { ps in ps.putShort(index) }
        case MenuType.inventoryCommand:
            send(ClientOpcode.inventoryCommand) { ps in ps.putShort(index) }
        case MenuType.inventoryUse:
            selectedItemInventoryIndex = index
            showUITab = 0
            selectedItemName = gameData.items[inventoryItemId[selectedItemInventoryIndex]].name
        case MenuType.inventoryDrop:
            send(ClientOpcode.inventoryDrop) { ps in ps.putShort(index) }
            selectedItemInventoryIndex = -1
            showUITab = 0
            showMessage(cField("Dropping \(gameData.items[inventoryItemId[index]].name)"), .bor)
        case MenuType.inventoryExamine:
            showMessage(gameData.items[index].description, .game)
            if options.condenseItemAmounts != 0 {
                let name = gameData.items[index].name
                if showDialogBank {
                    for j in 0..<bankItemCount where bankItems[j] == index && bankItemsCount[j] >= 100000 {
                        showMessage(cField("Total \(name) in bank: \(formatNumberCommas(bankItemsCount[j]))"), .game)
                        break
                    }
                }
                let amount = inventoryCount(index)
                if amount >= 100000 {
                    showMessage(cField("Total \(name) in inventory: \(formatNumberCommas(amount))"), .game)
                }
            }
        case MenuType.castNpc, MenuType.useWithNpc, MenuType.castPlayer, MenuType.useWithPlayer:
            walkToActionSource(startX: localRegionX, startY: localRegionY, destX: charX, destY: charY, action: true)
            let op = [MenuType.castNpc: ClientOpcode.castNpc, MenuType.useWithNpc: ClientOpcode.usewithNpc,
                      MenuType.castPlayer: ClientOpcode.castPlayer, MenuType.useWithPlayer: ClientOpcode.usewithPlayer][item.type]!
            send(op) { ps in ps.putShort(index); ps.putShort(source) }
            if item.type == MenuType.castNpc || item.type == MenuType.castPlayer {
                selectedSpell = -1
            } else {
                selectedItemInventoryIndex = -1
            }
        case MenuType.npcTalk, MenuType.npcCommand, MenuType.npcAttack1, MenuType.npcAttack2,
             MenuType.playerAttack1, MenuType.playerAttack2:
            walkToActionSource(startX: localRegionX, startY: localRegionY, destX: charX, destY: charY, action: true)
            let op: Int
            switch item.type {
            case MenuType.npcTalk: op = ClientOpcode.npcTalk
            case MenuType.npcCommand: op = ClientOpcode.npcCommand
            case MenuType.npcAttack1, MenuType.npcAttack2: op = ClientOpcode.npcAttack
            default: op = ClientOpcode.playerAttack
            }
            send(op) { ps in ps.putShort(index) }
        case MenuType.npcExamine:
            showMessage(gameData.npcs[index].description, .game)
        case MenuType.playerDuel:
            send(ClientOpcode.playerDuel) { ps in ps.putShort(index) }
        case MenuType.playerTrade:
            send(ClientOpcode.playerTrade) { ps in ps.putShort(index) }
        case MenuType.playerFollow:
            send(ClientOpcode.playerFollow) { ps in ps.putShort(index) }
        case MenuType.castGround:
            walkToActionSource(startX: localRegionX, startY: localRegionY, destX: mx, destY: my, action: true)
            send(ClientOpcode.castGround) { ps in
                ps.putShort(mx + regionX); ps.putShort(my + regionY); ps.putShort(index)
            }
            selectedSpell = -1
        case MenuType.walk:
            walkToActionSource(startX: localRegionX, startY: localRegionY, destX: mx, destY: my, action: false)
            if mouseClickXStep == -24 { mouseClickXStep = 24 }
        case MenuType.castSelf:
            send(ClientOpcode.castSelf) { ps in ps.putShort(index) }
            selectedSpell = -1
        case MenuType.bankWithdraw, MenuType.bankDeposit:
            let withdraw = item.type == MenuType.bankWithdraw
            if target < 0 {
                bankOfferType = withdraw ? BankOffer.withdraw : BankOffer.deposit
                offerId = index
                offerMax = abs(target)
                inputDigitsFinal = 0
                showDialogOfferX = true
            } else {
                bankTransaction(itemId: index, amount: target,
                                opcode: withdraw ? ClientOpcode.bankWithdraw : ClientOpcode.bankDeposit)
            }
        case MenuType.transactionOffer, MenuType.transactionRemove:
            let offer = item.type == MenuType.transactionOffer
            if target < 0 {
                transactionOfferType = offer ? TransactionOffer.offer : TransactionOffer.remove
                offerId = index
                offerMax = abs(target)
                inputDigitsFinal = 0
                showDialogOfferX = true
            } else {
                let op = showDialogTrade ? ClientOpcode.tradeItemUpdate : ClientOpcode.duelItemUpdate
                if offer {
                    offerTransactionItem(opcode: op, itemId: index, amount: target)
                } else {
                    removeTransactionItem(opcode: op, itemId: index, amount: target)
                }
            }
        case MenuType.mapLook:
            cameraRotation = index
        case MenuType.wikiLookup:
            let page = item.wikiPage
            let encoded = page.hasPrefix("Special:") ? cField(page, 128) : ClientUtil.urlEncode(page)
            let url = cField(options.wikiURL.replacingOccurrences(of: "%s", with: encoded), 256)
            host?.openURL(url)
            selectedWiki = false
        case MenuType.cancel:
            selectedItemInventoryIndex = -1
            selectedSpell = -1
            selectedWiki = false
        default:
            break
        }
    }

    // MARK: - create_top_mouse_menu

    func createTopMouseMenu() {
        var addCancel = selectedSpell >= 0 || selectedItemInventoryIndex >= 0 || selectedWiki
        if !addCancel {
            for i in 0..<menuItemsCount {
                let t = menuItems[i].type
                if t == MenuType.mapLook || t == MenuType.bankWithdraw || t == MenuType.bankDeposit ||
                    t == MenuType.transactionOffer || t == MenuType.transactionRemove {
                    addCancel = true
                    break
                }
            }
        }
        if addCancel {
            withMenuEntry { e in
                e.actionText = "Cancel"
                e.targetText = ""
                e.type = MenuType.cancel
            }
            menuItemsCount += 1
        }
        ensureMenuSlot(menuItemsCount)
        for i in 0..<menuItemsCount { menuIndices[i] = i }

        var sorted = false
        while !sorted {
            sorted = true
            var i = 0
            while i < menuItemsCount - 1 {
                let current = menuIndices[i], next = menuIndices[i + 1]
                if menuItems[current].type > menuItems[next].type {
                    menuIndices[i] = next
                    menuIndices[i + 1] = current
                    sorted = false
                }
                i += 1
            }
        }

        if menuItemsCount <= 0 { return }

        var index = -1
        for i in 0..<menuItemsCount where !menuItems[menuIndices[i]].targetText.isEmpty {
            index = i
            break
        }

        var menuText = ""
        let first = menuItems[menuIndices[0]]
        if index == -1 && selectedWiki {
            menuText = "@cya@Choose a wiki lookup target"
        } else if (selectedItemInventoryIndex >= 0 || selectedSpell >= 0) && menuItemsCount == 1 {
            menuText = "Choose a target"
        } else if (selectedItemInventoryIndex >= 0 || selectedSpell >= 0) && menuItemsCount > 1 {
            menuText = "@whi@\(first.actionText) \(first.targetText)"
        } else if index != -1 {
            menuText = "\(menuItems[menuIndices[index]].targetText): @whi@\(first.actionText)"
        }
        menuText = cField(menuText, 256)

        if menuItemsCount == 2 && !menuText.isEmpty {
            menuText += "@whi@ / 1 more option"
        }
        if menuItemsCount > 2 && !menuText.isEmpty {
            menuText += "@whi@ / \(menuItemsCount - 1) more options"
        }

        if !menuText.isEmpty {
            var yPosition = 14, xPosition = 6
            if isTouch {
                let yOffset = options.displayFps == 0 ? 18 : 35
                yPosition = surface.height - yOffset
                if isInWilderness { xPosition = 76 }
            }
            surface.drawString(menuText, x: xPosition, y: yPosition, font: .bold12, colour: Colour.yellow)
        }

        let buttonOne = settingsMouseButtonOne != 0
        if (!buttonOne && mouseButtonClick == 1) || (buttonOne && mouseButtonClick == 1 && menuItemsCount == 1) {
            menuItemClick(menuIndices[0])
            mouseButtonClick = 0
            return
        }

        if (!buttonOne && mouseButtonClick == 2) || (buttonOne && mouseButtonClick == 1) {
            menuHeight = (menuItemsCount + 1) * menuEntryHeight
            menuWidth = surface.textWidth("Choose option", font: .bold12) + 5
            if isTouch { menuHeight += 3 }
            for i in 0..<menuItemsCount {
                let w = surface.textWidth("\(menuItems[i].actionText) \(menuItems[i].targetText)", font: .bold12) + 5
                if w > menuWidth { menuWidth = w }
            }
            menuX = mouseX - menuWidth / 2
            menuY = mouseY - 7
            showRightClickMenu = true
            if menuX + menuWidth > surface.width - 2 { menuX = surface.width - 2 - menuWidth }
            if menuY + menuHeight > surface.height - 31 { menuY = surface.height - 31 - menuHeight }
            if menuX < 0 { menuX = 0 }
            if menuY < 0 { menuY = 0 }
            mouseButtonClick = 0
        }
    }

    // MARK: - wiki entries

    func menuAddWiki(display: String, page: String) {
        guard options.wikiLookup != 0 else { return }
        withMenuEntry { e in
            e.actionText = "Wiki lookup"
            e.targetText = display
            e.type = MenuType.wikiLookup
            e.wikiPage = page
        }
        menuItemsCount += 1
    }

    func menuAddIdWiki(display: String, type: String, id: Int) {
        let bytes = Surface.bytes(display)
        var name = display
        if let at = bytes.lastIndex(of: UInt8(ascii: "@")) {
            name = String(decoding: bytes[(at + 1)...], as: Latin1.self)
        }
        let encoded = cField(ClientUtil.urlEncode(name), 128)
        let page = cField("Special:Lookup?type=\(type)&id=\(id)&name=\(encoded)", 256)
        menuAddWiki(display: display, page: page)
    }

    func menuAddGroundItem(_ index: Int) {
        let itemId = groundItems[index].id
        let formatted = cField("@lre@\(gameData.items[itemId].name)")
        withMenuEntry { e in
            e.targetText = formatted
            e.x = groundItems[index].x
            e.y = groundItems[index].y
            e.index = itemId
        }
        if selectedWiki {
            menuAddIdWiki(display: formatted, type: "item", id: itemId)
        } else if selectedSpell >= 0 {
            if gameData.spells[selectedSpell].type == 3 {
                withMenuEntry { e in
                    e.actionText = "Cast \(gameData.spells[selectedSpell].name) on"
                    e.type = MenuType.castGroundItem
                    e.sourceIndex = selectedSpell
                }
                menuItemsCount += 1
            }
        } else if selectedItemInventoryIndex >= 0 {
            withMenuEntry { e in
                e.actionText = "Use \(selectedItemName) with"
                e.type = MenuType.useWithGroundItem
                e.sourceIndex = selectedItemInventoryIndex
            }
            menuItemsCount += 1
        } else {
            withMenuEntry { e in
                e.actionText = "Take"
                e.type = MenuType.groundItemTake
            }
            menuItemsCount += 1
            let previous = menuItems[menuItemsCount - 1].targetText
            withMenuEntry { e in
                e.actionText = "Examine"
                e.targetText = previous
                e.type = MenuType.groundItemExamine
                e.index = groundItems[index].id
            }
            menuItemsCount += 1
        }
    }

    // MARK: - create_right_click_menu

    func createRightClickMenu() {
        let wildernessDepth = self.wildernessDepth
        var selectedFace = -1
        for i in 0..<objectCount { objects[i].alreadyInMenu = false }
        for i in 0..<wallObjectCount { wallObjects[i].alreadyInMenu = false }
        for i in 0..<groundItemCount { groundItems[i].alreadyInMenu = false }

        let pickedCount = scene.mousePickedCount
        let pickedModels = scene.mousePickedModels
        let pickedFaces = scene.mousePickedFaces
        if menuItems.count < pickedCount * 5 { ensureMenuSlot(pickedCount * 6 - 1) }

        for i in 0..<pickedCount {
            let model = pickedModels[i]
            var face = pickedFaces[i]
            if face != -1 && face < model.faceCount, let tags = model.faceTag {
                let tag = Int(tags[face])
                if !((tag <= 65535 || tag >= 200000) && tag <= 300000) { continue }
            }

            if model === scene.view {
                let tag = Int(model.faceTag![face])
                let index = tag % 10000
                let type = tag / 10000
                if !selectedWiki && type == 1 {
                    addPlayerMenu(index, wildernessDepth: wildernessDepth)
                } else if type == 2 && options.groundItemModels == 0 {
                    menuAddGroundItem(index)
                } else if type == 3 {
                    addNpcMenu(index)
                }
            } else if model.key >= 20000 {
                let index = model.key - 20000
                if !groundItems[index].alreadyInMenu {
                    menuAddGroundItem(index)
                    groundItems[index].alreadyInMenu = true
                }
            } else if model.key >= 10000 {
                addWallObjectMenu(model.key - 10000)
            } else if model.key >= 0 {
                addObjectMenu(model.key)
            } else if face >= 0 && face < model.faceCount, let tags = model.faceTag {
                face = Int(tags[face]) - Mudclient.tileFaceTag
                selectedFace = face
            }
        }

        if selectedSpell >= 0 && gameData.spells[selectedSpell].type <= 1 {
            withMenuEntry { e in
                e.actionText = "Cast \(gameData.spells[selectedSpell].name) on self"
                e.targetText = ""
                e.type = MenuType.castSelf
                e.index = selectedSpell
            }
            menuItemsCount += 1
        }

        if selectedFace != -1 {
            if selectedSpell >= 0 {
                if gameData.spells[selectedSpell].type == 6 {
                    withMenuEntry { e in
                        e.actionText = "Cast \(gameData.spells[selectedSpell].name) on ground"
                        e.targetText = ""
                        e.type = MenuType.castGround
                        e.x = world.localX[selectedFace]
                        e.y = world.localY[selectedFace]
                        e.index = selectedSpell
                    }
                    menuItemsCount += 1
                    return
                }
            } else if !selectedWiki && selectedItemInventoryIndex < 0 {
                withMenuEntry { e in
                    e.actionText = "Walk here"
                    e.targetText = ""
                    e.type = MenuType.walk
                    e.x = world.localX[selectedFace]
                    e.y = world.localY[selectedFace]
                }
                menuItemsCount += 1
            }
        }
    }

    private func addPlayerMenu(_ index: Int, wildernessDepth: Int) {
        guard let player = players[index] else { return }
        var levelDifference = 0
        if localPlayer.level > 0 && player.level > 0 {
            levelDifference = localPlayer.level - player.level
        }
        let levelText = " \(ClientUtil.levelDifferenceColour(levelDifference))(level-\(player.level))"
        let target = "@whi@\(player.name)\(levelText)"
        func entry(_ action: String, _ type: Int, position: Bool, source: Int? = nil) {
            withMenuEntry { e in
                e.actionText = action
                e.targetText = target
                e.type = type
                if position { e.x = player.currentX; e.y = player.currentY }
                e.index = player.serverIndex
                if let source { e.sourceIndex = source }
            }
            menuItemsCount += 1
        }
        if selectedSpell >= 0 {
            let type = gameData.spells[selectedSpell].type
            if type == 1 || type == 2 {
                combatTarget = player
                entry("Cast \(gameData.spells[selectedSpell].name) on", MenuType.castPlayer,
                      position: true, source: selectedSpell)
            }
        } else if selectedItemInventoryIndex >= 0 {
            entry("Use \(selectedItemName) with", MenuType.useWithPlayer, position: true,
                  source: selectedItemInventoryIndex)
        } else {
            if wildernessDepth > 0 && ((player.currentY - 64) / Mudclient.magicLoc + planeHeight + regionY) < 2203 {
                combatTarget = player
                entry("Attack", levelDifference >= 0 && levelDifference < 5 ? MenuType.playerAttack1
                        : MenuType.playerAttack2, position: true)
            } else if options.members != 0 {
                entry("Duel with", MenuType.playerDuel, position: true)
            }
            entry("Trade with", MenuType.playerTrade, position: false)
            entry("Follow", MenuType.playerFollow, position: false)
        }
    }

    private func addNpcMenu(_ index: Int) {
        guard let npc = npcs[index] else { return }
        let npcId = npc.npcId
        let def = gameData.npcs[npcId]
        let formatted = cField("@yel@\(def.name)")
        var levelText = ""
        var levelDifference = -1
        if def.attackable > 0 {
            let npcLevel = (def.attack + def.defense + def.strength + def.hits) / 4
            let playerLevel = (playerSkillBase[0] + playerSkillBase[1] + playerSkillBase[2] +
                               playerSkillBase[Mudclient.skillHits] + 27) / 4
            levelDifference = playerLevel - npcLevel
            let colour = levelDifference == 0 ? "@yel@" : ClientUtil.levelDifferenceColour(levelDifference)
            levelText = " \(colour)(level-\(npcLevel))"
        }
        withMenuEntry { e in
            e.x = npc.currentX
            e.y = npc.currentY
            e.index = npc.serverIndex
        }
        if selectedWiki {
            menuAddIdWiki(display: formatted, type: "npc", id: npcId)
        } else if selectedSpell >= 0 {
            if gameData.spells[selectedSpell].type == 2 {
                combatTarget = npc
                withMenuEntry { e in
                    e.actionText = "Cast \(gameData.spells[selectedSpell].name) on"
                    e.targetText = formatted
                    e.type = MenuType.castNpc
                    e.sourceIndex = selectedSpell
                }
                menuItemsCount += 1
            }
        } else if selectedItemInventoryIndex >= 0 {
            withMenuEntry { e in
                e.actionText = "Use \(selectedItemName) with"
                e.targetText = "@yel@\(def.name)"
                e.type = MenuType.useWithNpc
                e.sourceIndex = selectedItemInventoryIndex
            }
            menuItemsCount += 1
        } else {
            if def.attackable > 0 {
                combatTarget = npc
                withMenuEntry { e in
                    e.actionText = "Attack"
                    e.targetText = "@yel@\(def.name)\(levelText)"
                    e.type = levelDifference >= 0 ? MenuType.npcAttack1 : MenuType.npcAttack2
                }
                menuItemsCount += 1
            }
            withMenuEntry { e in
                e.actionText = "Talk-to"
                e.targetText = formatted
                e.type = MenuType.npcTalk
                e.x = npc.currentX; e.y = npc.currentY
                e.index = npc.serverIndex
            }
            menuItemsCount += 1
            if !def.command.isEmpty {
                withMenuEntry { e in
                    e.actionText = def.command
                    e.targetText = formatted
                    e.type = MenuType.npcCommand
                    e.x = npc.currentX; e.y = npc.currentY
                    e.index = npc.serverIndex
                }
                menuItemsCount += 1
            }
            withMenuEntry { e in
                e.actionText = "Examine"
                e.targetText = formatted
                e.type = MenuType.npcExamine
                e.index = npcId
            }
            menuItemsCount += 1
        }
    }

    /// strncasecmp(a, b, n) != 0
    private func differs(_ a: String, _ prefix: String) -> Bool {
        let a = Surface.bytes(a).prefix(prefix.utf8.count).map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
        let b = Array(prefix.lowercased().utf8)
        return a != b
    }

    private func addWallObjectMenu(_ index: Int) {
        let wallId = wallObjects[index].id
        let def = gameData.walls[wallId]
        let formatted = cField("@cya@\(def.name)")
        if selectedWiki {
            menuAddIdWiki(display: formatted, type: "wallobject", id: wallId)
            return
        }
        guard !wallObjects[index].alreadyInMenu else { return }
        withMenuEntry { e in
            e.targetText = formatted
            e.x = wallObjects[index].x
            e.y = wallObjects[index].y
            e.index = wallObjects[index].direction
        }
        if selectedSpell >= 0 {
            if gameData.spells[selectedSpell].type == 4 {
                withMenuEntry { e in
                    e.actionText = "Cast \(gameData.spells[selectedSpell].name) on"
                    e.type = MenuType.castWallObject
                    e.sourceIndex = selectedSpell
                }
                menuItemsCount += 1
            }
        } else if selectedItemInventoryIndex >= 0 {
            withMenuEntry { e in
                e.actionText = "Use \(selectedItemName) with"
                e.type = MenuType.useWithWallObject
                e.sourceIndex = selectedItemInventoryIndex
            }
            menuItemsCount += 1
        } else {
            if differs(def.command1, "WalkTo") {
                withMenuEntry { e in
                    e.actionText = def.command1
                    e.type = MenuType.wallObjectCommand1
                }
                menuItemsCount += 1
            }
            if differs(def.command2, "Examine") {
                withMenuEntry { e in
                    e.actionText = def.command2
                    e.targetText = formatted
                    e.type = MenuType.wallObjectCommand2
                    e.x = wallObjects[index].x
                    e.y = wallObjects[index].y
                    e.index = wallObjects[index].direction
                }
                menuItemsCount += 1
            }
            withMenuEntry { e in
                e.actionText = "Examine"
                e.targetText = "@cya@\(def.name)"
                e.type = MenuType.wallObjectExamine
                e.index = wallId
            }
            menuItemsCount += 1
        }
        wallObjects[index].alreadyInMenu = true
    }

    private func addObjectMenu(_ index: Int) {
        let id = objects[index].id
        guard !objects[index].alreadyInMenu else { return }
        let def = gameData.objects[id]
        let formatted = cField("@cya@\(def.name)")
        withMenuEntry { e in
            e.targetText = formatted
            e.x = objects[index].x
            e.y = objects[index].y
            e.index = objects[index].direction
            e.sourceIndex = id
        }
        if selectedWiki {
            menuAddIdWiki(display: formatted, type: "object", id: id)
        } else if selectedSpell >= 0 {
            if gameData.spells[selectedSpell].type == 5 {
                withMenuEntry { e in
                    e.actionText = "Cast \(gameData.spells[selectedSpell].name) on"
                    e.targetText = "@cya@\(def.name)"
                    e.type = MenuType.castObject
                    e.targetIndex = selectedSpell
                }
                menuItemsCount += 1
            }
        } else if selectedItemInventoryIndex >= 0 {
            withMenuEntry { e in
                e.actionText = "Use \(selectedItemName) with"
                e.type = MenuType.useWithObject
                e.targetIndex = selectedItemInventoryIndex
            }
            menuItemsCount += 1
        } else {
            if differs(def.command1, "WalkTo") {
                withMenuEntry { e in
                    e.actionText = def.command1
                    e.type = MenuType.objectCommand1
                    e.x = objects[index].x; e.y = objects[index].y
                    e.index = objects[index].direction
                    e.sourceIndex = id
                }
                menuItemsCount += 1
            }
            if differs(def.command2, "Examine") {
                withMenuEntry { e in
                    e.actionText = def.command2
                    e.targetText = formatted
                    e.type = MenuType.objectCommand2
                    e.x = objects[index].x; e.y = objects[index].y
                    e.index = objects[index].direction
                    e.sourceIndex = id
                }
                menuItemsCount += 1
            }
            withMenuEntry { e in
                e.actionText = "Examine"
                e.targetText = "@cya@\(def.name)"
                e.type = MenuType.objectExamine
                e.index = id
            }
            menuItemsCount += 1
        }
        objects[index].alreadyInMenu = true
    }

    // MARK: - drawing

    func drawRightClickMenu() {
        let entryHeight = menuEntryHeight
        if mouseButtonClick != 0 {
            for i in 0..<menuItemsCount {
                let entryX = menuX + 2
                let entryY = menuY + entryHeight + 12 + i * entryHeight
                let minY = entryY - (isTouch ? 14 : 12), maxY = entryY + (isTouch ? 6 : 4)
                if mouseX <= entryX - 2 || mouseY <= minY || mouseY >= maxY || mouseX >= entryX - 3 + menuWidth {
                    continue
                }
                menuItemClick(menuIndices[i])
                break
            }
            mouseButtonClick = 0
            showRightClickMenu = false
            return
        }

        if mouseX < menuX - 10 || mouseY < menuY - 10 || mouseX > menuX + menuWidth + 10 ||
            mouseY > menuY + menuHeight + 10 {
            showRightClickMenu = false
            return
        }

        let dark = showDialogBank || showDialogTrade || showDialogDuel
        surface.drawBoxAlpha(x: menuX, y: menuY, width: menuWidth, height: menuHeight, colour: Colour.greyD0,
                             alpha: 160 + (dark ? 40 : 0))
        surface.drawString("Choose option", x: menuX + 2, y: menuY + 12, font: .bold12, colour: Colour.cyan)
        for i in 0..<menuItemsCount {
            let entryX = menuX + 2
            let entryY = menuY + entryHeight + 12 + i * entryHeight
            let minY = entryY - (isTouch ? 14 : 12), maxY = entryY + (isTouch ? 6 : 4)
            var colour = Colour.white
            if mouseX > entryX - 2 && mouseY > minY && mouseY < maxY && mouseX < entryX - 3 + menuWidth {
                colour = Colour.yellow
            }
            let e = menuItems[menuIndices[i]]
            surface.drawString("\(e.actionText) \(e.targetText)", x: entryX, y: entryY, font: .bold12, colour: colour)
        }
    }

    func drawHoverTooltip() {
        guard options.showHoverTooltip != 0 && menuItemsCount > 1 && mouseButtonDown == 0 && !showRightClickMenu
        else { return }
        let e = menuItems[menuIndices[0]]
        if e.actionText == "Walk here" { return }
        let combined = "\(e.actionText) \(e.targetText)"
        let w = surface.textWidth(combined, font: .bold12)
        let h = Surface.textHeight(.bold12)
        surface.drawBoxAlpha(x: mouseX, y: mouseY - h, width: w + 5, height: h + 3, colour: Colour.greyD0, alpha: 120)
        surface.drawString(combined, x: mouseX + 2, y: mouseY, font: .bold12, colour: Colour.white)
    }
}
