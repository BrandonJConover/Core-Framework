// Billboarded entities the scene asks the client to draw: players, NPCs,
// ground items and magic bubbles (mudclient_draw_player and friends), plus
// rsc-c's custom/item-highlight.c.

extension Mudclient {
    static let highlightSingles: [Int: Int32] = [
        40: 0x00DE00, 41: 0xDF4B4B, 42: 0x0BDBED, 38: 0xFFFFFF, 46: 0xFFFF00, 619: 0x8E1400, 422: 0xFD8D28,
        828: 0x00CE00, 831: 0xCE0000, 832: 0x0000CE, 575: 0xF6F68C, 576: 0xFF0000, 577: 0xFFFF00, 578: 0x0000FF,
        579: 0x00FF00, 580: 0xFF00FF, 581: 0xFFFFFF, 971: 0xD81010,
    ]
    static let highlightGroups: [([Int], Int32)] = [
        ([438, 439, 440, 441, 442, 443], 0x31B131),
        ([160, 164, 284, 289, 297, 302, 314], 0x004CFF),
        ([159, 163, 285, 290, 298, 303, 315], 0x33CC33),
        ([158, 162, 286, 291, 299, 304, 316], 0xFF3300),
        ([157, 161, 287, 292, 300, 305, 317], 0xFFFFFF),
        ([522, 523, 524, 525, 526, 527, 542, 543, 544, 597, 610], 0xBB00FF),
        ([64, 68, 73, 79, 85, 91, 96, 106, 110, 115, 122, 126, 130, 153, 173, 203, 226, 310, 562, 1090, 1260], 0x99B2CC),
        ([65, 69, 74, 80, 86, 92, 97, 107, 111, 116, 120, 123, 127, 131, 154, 174, 204, 227, 311, 564, 645, 673, 1069,
          1091, 1139, 1261], 0xB2CC99),
        ([75, 81, 93, 98, 112, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 647, 674, 1070,
          1092, 1134, 1140, 1262], 0x00FFFF),
        ([593, 594, 795, 1276, 1277, 1278], 0xFF0044),
    ]

    /// highlight_item: text colour for valuable ground items, or 0.
    static func highlightItem(_ id: Int) -> Int32 {
        if let c = highlightSingles[id] { return c }
        for (ids, c) in highlightGroups where ids.contains(id) { return c }
        return 0
    }

    func drawCharacterMessage(_ c: GameCharacter, _ x: Int, _ y: Int, _ width: Int) {
        if c.messageTimeout <= 0 || receivedMessagesCount >= Mudclient.receivedMessageMax { return }
        let textWidth = surface.textWidth(c.message, font: .bold12)
        let i = receivedMessagesCount
        receivedMessageMidPoint[i] = min(textWidth / 2, 150)
        receivedMessageHeight[i] = (textWidth / 300) * Surface.textHeight(.bold12)
        receivedMessageX[i] = x + width / 2
        receivedMessageY[i] = y
        receivedMessages[i] = c.message
        receivedMessagesCount += 1
    }

    func drawCharacterDamage(_ c: GameCharacter, _ x: Int, _ y: Int, _ ty: Int, _ width: Int, _ height: Int,
                             _ isNpc: Bool) {
        if c.currentAnimation != 8 && c.currentAnimation != 9 && c.combatTimer == 0 { return }
        if c.combatTimer > 0 {
            var ox = x
            if c.currentAnimation == 8 { ox -= 20 * ty / 100 } else if c.currentAnimation == 9 { ox += 20 * ty / 100 }
            let missing = c.currentHits * 30 / c.maxHits
            if healthBarCount < Mudclient.healthBarMax {
                healthBars[healthBarCount] = HealthBar(x: ox + width / 2, y: y, missing: missing)
                healthBarCount += 1
            }
        }
        if c.combatTimer > 150 {
            var ox = x
            if c.currentAnimation == 8 { ox -= 10 * ty / 100 } else if c.currentAnimation == 9 { ox += 10 * ty / 100 }
            surface.drawSprite(x: ox + width / 2 - 12, y: y + height / 2 - 12, id: spriteMedia + 11 + (isNpc ? 1 : 0))
            surface.drawStringCentre(String(c.damageTaken), x: ox + width / 2 - 1, y: y + height / 2 + 5, font: .bold13,
                                     colour: Colour.white)
        }
    }

    private func facing(_ animation: Int) -> (order: Int, i2: Int, flip: Bool) {
        let order = (animation + (cameraRotation + 16) / 32) & 7
        switch order {
        case 5: return (order, 3, true)
        case 6: return (order, 2, true)
        case 7: return (order, 1, true)
        default: return (order, order, false)
        }
    }

    private func spriteLoaded(_ id: Int) -> Bool { surface.spritePixels[id] != nil || surface.spriteColours[id] != nil }

    func drawPlayerSprite(x: Int, y: Int, width: Int, height: Int, id: Int, skewX: Int, ty: Int) {
        guard let player = players[id], player.bottomColour != 255 else { return }
        var x = x
        var (order, i2, flip) = facing(player.currentAnimation)
        let walk = GameCharacter.walkModel
        var j2 = i2 * 3 + walk[(Int(player.stepCount) / 6) % 4]
        if player.currentAnimation == 8 {
            i2 = 5; order = 2; flip = false
            x -= 5 * ty / 100
            j2 = i2 * 3 + GameCharacter.combatModel1[(loginTimer / 5) % 8]
        } else if player.currentAnimation == 9 {
            i2 = 5; order = 2; flip = true
            x += 5 * ty / 100
            j2 = i2 * 3 + GameCharacter.combatModel2[(loginTimer / 6) % 8]
        }
        for i in 0..<AnimationIndex.count {
            let slot = GameCharacter.animationOrder[order][i]
            let animationId = player.animations[slot] - 1
            if animationId < 0 { continue }
            let anim = gameData.animations[animationId]
            var ox = 0, oy = 0
            var j5 = j2
            if flip && i2 >= 1 && i2 <= 3 {
                let swing = i2 * 3 + walk[(2 + Int(player.stepCount) / 6) % 4]
                if anim.hasF == 1 {
                    j5 += 15
                } else if slot == AnimationIndex.rightHand {
                    (ox, oy) = [(-22, -3), (0, -8), (26, -5)][i2 - 1]
                    j5 = swing
                } else if slot == AnimationIndex.leftHand {
                    (ox, oy) = [(22, 3), (0, 8), (-26, 5)][i2 - 1]
                    j5 = swing
                }
            }
            if i2 != 5 || anim.hasA == 1 {
                let spriteId = j5 + anim.fileId
                if !spriteLoaded(spriteId) { continue }
                ox = ox * width / surface.spriteWidthFull[spriteId]
                oy = oy * height / surface.spriteHeightFull[spriteId]
                let clipWidth = width * surface.spriteWidthFull[spriteId] / surface.spriteWidthFull[anim.fileId]
                ox -= (clipWidth - width) / 2
                var colour = Int32(anim.colour)
                if anim.colour == 1 {
                    colour = GameCharacter.hairColours[player.hairColour]
                } else if anim.colour == 2 {
                    colour = GameCharacter.topBottomColours[player.topColour]
                } else if anim.colour == 3 {
                    colour = GameCharacter.topBottomColours[player.bottomColour]
                }
                surface.drawSpriteTransformMask(x: x + ox, y: y + oy, width: clipWidth, height: height, id: spriteId,
                                                maskColour: colour, skinColour: GameCharacter.skinColours[player.skinColour],
                                                skewX: skewX, flip: flip)
            }
        }
        drawCharacterMessage(player, x, y, width)
        if player.bubbleTimeout > 0 && actionBubbleCount < Mudclient.actionBubbleMax {
            actionBubbles[actionBubbleCount] = ActionBubble(x: x + width / 2, y: y, scale: ty, item: player.bubbleItem)
            actionBubbleCount += 1
        }
        drawCharacterDamage(player, x, y, ty, width, height, false)
        if player.skullVisible != 0 && player.bubbleTimeout == 0 {
            var k3 = skewX + x + width / 2
            if player.currentAnimation == 8 { k3 -= 20 * ty / 100 } else if player.currentAnimation == 9 { k3 += 20 * ty / 100 }
            let w = 16 * ty / 100, h = 16 * ty / 100
            surface.drawSpriteScale(x: k3 - w / 2, y: y - h / 2 - 10 * ty / 100, width: w, height: h, id: spriteMedia + 13)
        }
    }

    func drawNpcSprite(x: Int, y: Int, width: Int, height: Int, id: Int, skewX: Int, ty: Int) {
        guard let npc = npcs[id] else { return }
        let def = gameData.npcs[npc.npcId]
        var x = x
        var (order, i2, flip) = facing(npc.currentAnimation)
        var j2 = i2 * 3 + GameCharacter.walkModel[(Int(npc.stepCount) / def.walkSpeed) % 4]
        if npc.currentAnimation == 8 {
            i2 = 5; order = 2; flip = false
            x -= def.combatWidth * ty / 100
            let index = (loginTimer / def.combatSpeed - 1) % 8
            // rsc-c reads one entry before the array (character_walk_model[3] = 1) when the index is -1.
            j2 = i2 * 3 + (index < 0 ? 1 : GameCharacter.combatModel1[index])
        } else if npc.currentAnimation == 9 {
            i2 = 5; order = 2; flip = true
            x += def.combatWidth * ty / 100
            j2 = i2 * 3 + GameCharacter.combatModel2[(loginTimer / def.combatSpeed) % 8]
        }
        for i in 0..<AnimationIndex.count {
            let slot = GameCharacter.animationOrder[order][i]
            let animationId = def.sprites[slot]
            if animationId < 0 { continue }
            let anim = gameData.animations[animationId]
            var k4 = j2
            if flip && i2 >= 1 && i2 <= 3 && anim.hasF == 1 { k4 += 15 }
            if i2 != 5 || anim.hasA == 1 {
                let spriteId = k4 + anim.fileId
                if !spriteLoaded(spriteId) { continue }
                let clipWidth = width * surface.spriteWidthFull[spriteId] / surface.spriteWidthFull[anim.fileId]
                let ox = -(clipWidth - width) / 2
                var colour = Int32(anim.colour)
                var skin: Int32 = 0
                if anim.colour == 1 {
                    colour = Int32(def.hairColour); skin = Int32(def.skinColour)
                } else if anim.colour == 2 {
                    colour = Int32(def.topColour); skin = Int32(def.skinColour)
                } else if anim.colour == 3 {
                    colour = Int32(def.bottomColour); skin = Int32(def.skinColour)
                }
                surface.drawSpriteTransformMask(x: x + ox, y: y, width: clipWidth, height: height, id: spriteId,
                                                maskColour: colour, skinColour: skin, skewX: skewX, flip: flip)
            }
        }
        drawCharacterMessage(npc, x, y, width)
        drawCharacterDamage(npc, x, y, ty, width, height, true)
    }

    func drawMagicBubbleSprite(x: Int, y: Int, width: Int, height: Int, id: Int) {
        let type = magicBubbles[id].type, time = magicBubbles[id].time
        if type == 0 {
            surface.drawCircle(x: x + width / 2, y: y + height / 2, radius: 20 + time * 2,
                               colour: Colour.blue + Int32(time * 5 * 256), alpha: 255 - time * 5)
        } else if type == 1 {
            surface.drawCircle(x: x + width / 2, y: y + height / 2, radius: 10 + time,
                               colour: Colour.red + Int32(time * 5 * 256), alpha: 255 - time * 5)
        }
    }

    func drawGroundItemSprite(x: Int, y: Int, width: Int, height: Int, id: Int) {
        let highlight = Mudclient.highlightItem(id)
        if highlight != 0 && options.groundItemText != 0 && overworldTextCount < Mudclient.overworldTextMax {
            overworldText[overworldTextCount] = OverworldText(text: gameData.items[id].name, x: x + width / 2,
                                                              y: y - height / 2, colour: highlight)
            overworldTextCount += 1
        }
        if options.groundItemModels == 0 {
            let item = gameData.items[id]
            surface.drawSpriteTransformMask(x: x, y: y, width: width, height: height, id: item.sprite + spriteItem,
                                            maskColour: Int32(item.mask), skinColour: 0, skewX: 0, flip: false)
        }
    }
}
