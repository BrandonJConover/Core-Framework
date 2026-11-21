// Port of rsc-c ui/minimap-tab.c.

import Foundation

extension Mudclient {
    static let minimapWidth = 156, minimapHeight = 152

    func drawMinimapEntity(x: Int, y: Int, colour: Int32) {
        if x + 2 < surface.boundsMinX || x - 2 > surface.boundsMaxX ||
            y + 2 < surface.boundsMinY || y - 2 > surface.boundsMaxY { return }
        surface.drawLineVertical(x: x, y: y - 1, height: 3, colour: colour)
        surface.drawLineHorizontal(x: x - 1, y: y, width: 3, colour: colour)
    }

    func drawUITabMinimap(noMenus: Bool) {
        let mw = Mudclient.minimapWidth, mh = Mudclient.minimapHeight
        var uiX = surface.width - mw - 3
        var uiY = UITabs.buttonSize + 1
        if isTouch {
            uiX = uiTabsTouchX - mw - 1
            uiY = uiTabsTouchY + (UITabs.touchHeight - mh + 10) / 2
        }
        uiTabMinX = surface.width - 199
        uiTabMaxX = surface.width
        uiTabMinY = 0
        uiTabMaxY = 240
        if isTouch {
            uiTabMinX = uiX
            uiTabMaxX = uiX + mw
            uiTabMinY = uiY - UITabs.labelHeight
            uiTabMaxY = uiY + mh
        }
        if options.versionMedia >= 59 {
            drawUITabLabel(selectedTab: UITabs.map, width: mw, x: uiX, y: uiY - UITabs.labelHeight)
        }
        surface.drawBox(x: uiX, y: uiY, width: mw, height: mh, colour: Colour.black)
        surface.setBounds(minX: uiX, minY: uiY, maxX: uiX + mw, maxY: uiY + mh)

        let scale = 192 + minimapRandomScale
        let rotation = (cameraRotation + minimapRandomRotation) & 0xff
        let sin = Tables.sinCos2048[(1024 - rotation * 4) & 1023]
        let cos = Tables.sinCos2048[((1024 - rotation * 4) & 1023) + 1024]
        let px = localPlayer.currentX, py = localPlayer.currentY

        func rotate(_ x: Int, _ y: Int) -> (Int, Int) {
            ((y * sin + x * cos) >> 18, (y * cos - x * sin) >> 18)
        }

        let (playerX, playerY) = rotate(((px - 6040) * 3 * scale) / 2048, ((py - 6040) * 3 * scale) / 2048)
        surface.drawMinimapSprite(x: uiX + mw / 2 - playerX, y: uiY + mh / 2 + playerY, id: spriteMedia - 1,
                                  rotation: (rotation + 64) & 255, scale: scale)

        func plot(_ dx: Int, _ dy: Int, _ colour: Int32) {
            let (x, y) = rotate((dx * 3 * scale) / 2048, (dy * 3 * scale) / 2048)
            drawMinimapEntity(x: uiX + mw / 2 + x, y: uiY + mh / 2 - y, colour: colour)
        }
        for i in 0..<objectCount {
            plot(objects[i].x * Mudclient.magicLoc + 64 - px, objects[i].y * Mudclient.magicLoc + 64 - py, Colour.cyan)
        }
        for i in 0..<groundItemCount {
            plot(groundItems[i].x * Mudclient.magicLoc + 64 - px, groundItems[i].y * Mudclient.magicLoc + 64 - py,
                 Colour.red)
        }
        for i in 0..<npcCount {
            guard let npc = npcs[i] else { continue }
            plot(npc.currentX - px, npc.currentY - py, Colour.yellow)
        }
        for i in 0..<playerCount {
            guard let player = players[i] else { continue }
            var colour = Colour.white
            for j in 0..<friendListCount
            where player.encodedUsername == friendList[j] && friendListOnline[j] == SocialTab.friendOnline {
                colour = Colour.green
                break
            }
            plot(player.currentX - px, player.currentY - py, colour)
        }

        surface.drawCircle(x: uiX + mw / 2, y: uiY + mh / 2, radius: 2, colour: Colour.white, alpha: 255)
        surface.drawMinimapSprite(x: uiX + 19, y: uiY + 19, id: spriteMedia + 24,
                                  rotation: (cameraRotation + 128) & 255, scale: 128)
        surface.setBounds(minX: 0, minY: 0, maxX: surface.width, maxY: surface.height)

        guard noMenus else { return }
        let mx = mouseX - uiX, my = mouseY - uiY
        if options.compassMenu != 0 && mx > 0 && mx <= 32 && my > 0 && my <= 32 {
            for (name, angle) in [("North", 128), ("East", 192), ("South", 0), ("West", 64)] {
                withMenuEntry { e in
                    e.actionText = "Look"
                    e.targetText = name
                    e.type = MenuType.mapLook
                    e.index = angle
                }
                menuItemsCount += 1
            }
            return
        }
        if mx >= 0 && my >= 0 && mx < mw + 40 && my < mh {
            var deltaY = ((mouseX - (uiX + mw / 2)) * 16384) / (3 * scale)
            var deltaX = ((mouseY - (uiY + mh / 2)) * 16384) / (3 * scale)
            let temp = (deltaX * sin + deltaY * cos) >> 15
            deltaX = (deltaX * cos - deltaY * sin) >> 15
            deltaY = temp
            deltaY += px
            deltaX = py - deltaX
            if mouseButtonClick == 1 {
                walkToActionSource(startX: localRegionX, startY: localRegionY, destX: deltaY / 128, destY: deltaX / 128,
                                   action: false)
                mouseButtonClick = 0
            }
        }
    }
}
