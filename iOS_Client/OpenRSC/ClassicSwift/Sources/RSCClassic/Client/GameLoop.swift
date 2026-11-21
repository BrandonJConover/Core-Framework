// The in-game loop of rsc-c's mudclient.c: input ticks (handle_game_input,
// handle_inputs), the camera, and drawing the game view (draw_game,
// draw_entity_sprites, draw_overhead, animate_objects).

import Foundation

extension Mudclient {
    static let playerFaceTag = 10000
    static let npcFaceTag = 30000

    // MARK: - Camera

    /// mudclient_is_valid_camera_angle: false when a tall object blocks the view from that side.
    func isValidCameraAngle(_ angle: Int) -> Bool {
        let x = localPlayer.currentX / 128, y = localPlayer.currentY / 128
        func blocked(_ ax: Int, _ ay: Int) -> Bool { (world.objectAdjacency[ax * 96 + ay] & 128) == 128 }
        for i in stride(from: 2, through: 1, by: -1) {
            if angle == 1 && (blocked(x, y - i) || blocked(x - i, y) || blocked(x - i, y - i)) { return false }
            if angle == 3 && (blocked(x, y + i) || blocked(x - i, y) || blocked(x - i, y + i)) { return false }
            if angle == 5 && (blocked(x, y + i) || blocked(x + i, y) || blocked(x + i, y + i)) { return false }
            if angle == 7 && (blocked(x, y - i) || blocked(x + i, y) || blocked(x + i, y - i)) { return false }
            if angle == 0 && blocked(x, y - i) { return false }
            if angle == 2 && blocked(x - i, y) { return false }
            if angle == 4 && blocked(x, y + i) { return false }
            if angle == 6 && blocked(x + i, y) { return false }
        }
        return true
    }

    /// mudclient_auto_rotate_camera
    func autoRotateCamera() {
        if cameraAngle & 1 == 1 && isValidCameraAngle(cameraAngle) { return }
        func settleEven() -> Bool {
            if cameraAngle & 1 == 0 && isValidCameraAngle(cameraAngle) {
                if isValidCameraAngle((cameraAngle + 1) & 7) {
                    cameraAngle = (cameraAngle + 1) & 7
                } else if isValidCameraAngle((cameraAngle + 7) & 7) {
                    cameraAngle = (cameraAngle + 7) & 7
                }
                return true
            }
            return false
        }
        if settleEven() { return }
        for a in [1, -1, 2, -2, 3, -3, 4] {
            let angle = (cameraAngle + a + 8) & 7
            if !isValidCameraAngle(angle) { continue }
            cameraAngle = angle
            break
        }
        _ = settleEven()
    }

    /// mudclient_handle_camera_zoom
    func handleCameraZoom() {
        if keyUp {
            cameraZoom -= 16
        } else if keyDown {
            cameraZoom += 16
        } else if keyPageUp {
            cameraZoom = Mudclient.zoomMin
        } else if keyPageDown {
            cameraZoom = Mudclient.zoomMax
        } else if keyHome {
            cameraZoom = Mudclient.zoomOutdoors
        }
        let touch = isTouchLayout
        let excludeMaxX = Mudclient.vanillaWidth
        let excludeMinY = touch ? 0 : surface.height - 80
        let excludeMaxY = touch ? 100 : surface.height
        if mouseScrollDelta != 0 && (showUITab == 0 || showUITab == UITabs.map) &&
            !(messageTabSelected != .all && mouseY > excludeMinY && mouseY <= excludeMaxY && mouseX <= excludeMaxX) &&
            !showDialogBank {
            cameraZoom += mouseScrollDelta * 24
        }
        cameraZoom = min(max(cameraZoom, Mudclient.zoomMin), Mudclient.zoomMax)
    }

    // MARK: - Input ticks

    /// mudclient_handle_game_input: one game tick of input, movement and animation.
    public func handleGameInput() {
        if systemUpdate > 1 { systemUpdate -= 1 }
        if showDialogConfirm {
            handleConfirmInput()
        } else if showAdditionalOptions {
            handleAdditionalOptionsInput()
        }
        if options.tabRespond != 0 && keyTab && privateMessageTarget != 0 {
            let online = (0..<friendListCount).contains { friendList[$0] == privateMessageTarget && friendListOnline[$0] > 0 }
            if online {
                showDialogSocialInput = SocialTab.messageFriend
                inputPmCurrent = ""
                inputPmFinal = ""
            }
            keyTab = false
        }
        if options.middleClickCamera != 0 && middleButtonDown {
            let ticks = Int(truncatingIfNeeded: ClientTime.ticks())
            if ticks - lastMouseSampleTicks >= 250 {
                lastMouseSampleTicks = ticks
                lastMouseSampleX = mouseX
            }
        }
        packetTick()
        if logoutTimeout > 0 { logoutTimeout -= 1 }
        if options.idleLogout != 0 && mouseActionTimeout > 4500 && combatTimeout == 0 && logoutTimeout == 0 {
            mouseActionTimeout -= 500
            sendLogout()
            return
        }
        if localPlayer.currentAnimation == 8 || localPlayer.currentAnimation == 9 { combatTimeout = 500 }
        if combatTimeout > 0 { combatTimeout -= 1 }
        if showAppearanceChange {
            handleAppearancePanelInput()
            return
        }
        for i in 0..<playerCount { players[i]?.move() }
        if deathScreenTimeout > 0 {
            deathScreenTimeout -= 1
            if deathScreenTimeout == 0 {
                showMessage("You have been granted another life. Be more careful this time!", .game)
                showMessage("You retain your skills. Your objects land where you died", .game)
            }
        }
        for i in 0..<npcCount { npcs[i]?.move() }
        if showUITab != UITabs.map {
            if surface.anInt346 > 0 { sleepWordDelayTimer += 1 }
            if surface.anInt347 > 0 { sleepWordDelayTimer = 0 }
            surface.anInt346 = 0
            surface.anInt347 = 0
        }
        for i in 0..<playerCount {
            if let p = players[i], p.projectileRange > 0 { p.projectileRange -= 1 }
        }
        let lx = localPlayer.currentX, ly = localPlayer.currentY
        if cameraAutoRotatePlayerX - lx < -500 || cameraAutoRotatePlayerX - lx > 500 ||
            cameraAutoRotatePlayerY - ly < -500 || cameraAutoRotatePlayerY - ly > 500 {
            cameraAutoRotatePlayerX = lx
            cameraAutoRotatePlayerY = ly
        }
        if cameraAutoRotatePlayerX != lx {
            cameraAutoRotatePlayerX += (lx - cameraAutoRotatePlayerX) / (16 + (cameraZoom - 500) / 15)
        }
        if cameraAutoRotatePlayerY != ly {
            cameraAutoRotatePlayerY += (ly - cameraAutoRotatePlayerY) / (16 + (cameraZoom - 500) / 15)
        }
        if settingsCameraAuto != 0 {
            var delta = cameraAngle * 32 - cameraRotation
            var direction = 1
            if delta != 0 {
                cameraAutoCounter += 1
                if delta > 128 {
                    direction = -1
                    delta = 256 - delta
                } else if delta > 0 {
                    direction = 1
                } else if delta < -128 {
                    direction = 1
                    delta = 256 + delta
                } else if delta < 0 {
                    direction = -1
                    delta = -delta
                }
                cameraRotation += ((cameraAutoCounter * delta + 255) / 256) * direction
                cameraRotation &= 0xff
            } else {
                cameraAutoCounter = 0
            }
        } else if cameraMomentum != 0 {
            let sign = cameraMomentum > 0 ? 1 : -1
            cameraRotation += abs(cameraMomentum) * sign
            cameraMomentum -= sign
        }
        if sleepWordDelayTimer > 20 {
            sleepWordDelay = 0
            sleepWordDelayTimer = 0
        }
        if isSleeping {
            handleSleepInput()
            return
        }
        handleMessageTabsInput()
        if deathScreenTimeout != 0 { lastMouseButtonDown = 0 }
        if showDialogTrade || showDialogDuel || (showDialogShop && options.holdToBuy != 0) {
            mouseButtonDownTime = mouseButtonDown != 0 ? mouseButtonDownTime + 1 : 0
            if mouseButtonDownTime > 600 {
                mouseItemCountIncrement += 5000
            } else if mouseButtonDownTime > 450 {
                mouseItemCountIncrement += 500
            } else if mouseButtonDownTime > 300 {
                mouseItemCountIncrement += 50
            } else if mouseButtonDownTime > 150 {
                mouseItemCountIncrement += 5
            } else if mouseButtonDownTime > 50 {
                mouseItemCountIncrement += 1
            } else if mouseButtonDownTime > 20 && (mouseButtonDownTime & 5) == 0 {
                mouseItemCountIncrement += 1
            }
        } else {
            mouseButtonDownTime = 0
            mouseItemCountIncrement = 0
        }
        if lastMouseButtonDown == 1 {
            mouseButtonClick = 1
        } else if lastMouseButtonDown == 2 {
            mouseButtonClick = 2
        }
        scene.setMouseLocation(x: mouseX, y: mouseY)
        lastMouseButtonDown = 0
        if settingsCameraAuto != 0 {
            if cameraAutoCounter == 0 {
                if keyLeft || keyRight {
                    let step = keyLeft ? 1 : 7
                    cameraAngle = (cameraAngle + step) & 7
                    if keyLeft { keyLeft = false } else { keyRight = false }
                    if !fogOfWar {
                        if cameraAngle & 1 == 0 { cameraAngle = (cameraAngle + step) & 7 }
                        for _ in 0..<8 {
                            if isValidCameraAngle(cameraAngle) { break }
                            cameraAngle = (cameraAngle + step) & 7
                        }
                    }
                }
            }
        } else if keyLeft {
            cameraRotation = (cameraRotation + 2) & 0xff
        } else if keyRight {
            cameraRotation = (cameraRotation - 2) & 0xff
        }
        if settingsCameraAuto == 0 && options.middleClickCamera != 0 && middleButtonDown {
            let scale = Float(options.middleClickCamera) / 100
            cameraRotation = (originRotation + Int(Float(mouseX - originMouseX) * scale)) & 0xff
        }
        if options.zoomCamera != 0 {
            handleCameraZoom()
        } else if fogOfWar && cameraZoom > Mudclient.zoomIndoors {
            cameraZoom -= 4
        } else if !fogOfWar && cameraZoom < Mudclient.zoomOutdoors {
            cameraZoom += 4
        }
        if mouseClickXStep > 0 {
            mouseClickXStep -= 1
        } else if mouseClickXStep < 0 {
            mouseClickXStep += 1
        }
        scene.scrollTexture(Mudclient.fountainId)
        objectAnimationCount += 1
        if objectAnimationCount > 5 {
            objectAnimationCount = 0
            objectAnimationCycle = (objectAnimationCycle + 1) % 3
            torchAnimationCycle = (torchAnimationCycle + 1) % 4
            clawAnimationCycle = (clawAnimationCycle + 1) % 5
        }
        for i in 0..<objectCount {
            let o = objects[i]
            if o.x >= 0 && o.y >= 0 && o.x < 96 && o.y < 96 && o.id == Mudclient.windmillSailsId {
                o.model?.rotate(yaw: 1, pitch: 0, roll: 0)
            }
        }
        var i = 0
        while i < magicBubbleCount {
            magicBubbles[i].time += 1
            if magicBubbles[i].time > 50 {
                magicBubbleCount -= 1
                for j in i..<magicBubbleCount { magicBubbles[j] = magicBubbles[j + 1] }
            }
            i += 1
        }
    }

    /// mudclient_handle_inputs: one 20ms input tick.
    public func handleInputs() {
        if errorLoadingData { return }
        loginTimer += 1
        if !loggedIn {
            mouseActionTimeout = 0
            handleLoginScreenInput()
        } else {
            mouseActionTimeout += 1
            handleGameInput()
        }
        lastMouseButtonDown = 0
        cameraRotationTime += 1
        if cameraRotationTime > 500 {
            cameraRotationTime = 0
            if options.antiMacro != 0 {
                let roll = Int((Float(CRandom.shared.next()) / Float(CRandom.randMax)) * 4)
                if roll & 1 == 1 { cameraRotationX += cameraRotationXIncrement }
                if roll & 2 == 2 { cameraRotationY += cameraRotationYIncrement }
            }
        }
        if cameraRotationX < -50 {
            cameraRotationXIncrement = 2
        } else if cameraRotationX > 50 {
            cameraRotationXIncrement = -2
        }
        if cameraRotationY < -50 {
            cameraRotationYIncrement = 2
        } else if cameraRotationY > 50 {
            cameraRotationYIncrement = -2
        }
        decrementMessageFlash()
    }

    // MARK: - Combat helpers

    public var isInCombat: Bool { localPlayer.currentAnimation == 8 || localPlayer.currentAnimation == 9 }

    /// mudclient_get_opponent
    func opponent() -> GameCharacter? {
        if !isInCombat {
            guard let target = combatTarget else { return nil }
            if target.maxHits <= 0 { return nil }
            if target.npcId != -1 {
                return knownNpcs[0..<knownNpcCount].contains { $0 === target } ? target : nil
            }
            return knownPlayers[0..<knownPlayerCount].contains { $0 === target } ? target : nil
        }
        let desired = localPlayer.currentAnimation == 8 ? 9 : 8
        let lx = localPlayer.currentX, ly = localPlayer.currentY
        for c in knownNpcs[0..<knownNpcCount] {
            if let c, c.currentX == lx && c.currentY == ly && c.currentAnimation == desired { return c }
        }
        for c in knownPlayers[0..<knownPlayerCount] {
            if let c, c.currentX == lx && c.currentY == ly && c.currentAnimation == desired { return c }
        }
        return nil
    }

    // MARK: - Drawing the game

    /// mudclient_draw_overhead: chat above heads, action bubbles, item names and health bars.
    func drawOverhead() {
        let textHeight = Surface.textHeight(.bold12)
        for i in 0..<receivedMessagesCount {
            let x = receivedMessageX[i]
            var y = receivedMessageY[i]
            let mid = receivedMessageMidPoint[i]
            let height = receivedMessageHeight[i]
            var flag = true
            while flag {
                flag = false
                for j in 0..<i where y + height > receivedMessageY[j] - textHeight &&
                    y - textHeight < receivedMessageY[j] + receivedMessageHeight[j] &&
                    x - mid < receivedMessageX[j] + receivedMessageMidPoint[j] &&
                    x + mid > receivedMessageX[j] - receivedMessageMidPoint[j] &&
                    receivedMessageY[j] - textHeight - height < y {
                    y = receivedMessageY[j] - textHeight - height
                    flag = true
                }
            }
            receivedMessageY[i] = y
            surface.drawParagraph(receivedMessages[i], x: x, y: y, font: .bold12, colour: Colour.yellow, max: 300)
        }
        for i in 0..<actionBubbleCount {
            let b = actionBubbles[i]
            let scaleX = (39 * b.scale) / 100, scaleY = (27 * b.scale) / 100
            surface.drawSpriteScaleAlpha(x: b.x - scaleX / 2, y: b.y - scaleY, width: scaleX, height: scaleY,
                                         id: spriteMedia + 9, alpha: 85)
            let clipX = (36 * b.scale) / 100, clipY = (24 * b.scale) / 100
            let item = gameData.items[b.item]
            surface.drawSpriteTransformMask(x: b.x - clipX / 2, y: (b.y - scaleY + scaleY / 2) - clipY / 2,
                                            width: clipX, height: clipY, id: item.sprite + spriteItem,
                                            maskColour: Int32(item.mask), skinColour: 0, skewX: 0, flip: false)
        }
        // qsort by strcmp (glibc's qsort is a stable merge sort here)
        let sorted = overworldText[0..<overworldTextCount].sorted {
            Surface.bytes($0.text).lexicographicallyPrecedes(Surface.bytes($1.text))
        }
        for (i, t) in sorted.enumerated() { overworldText[i] = t }
        let height = Surface.textHeight(.regular11)
        for i in 0..<overworldTextCount {
            let x = overworldText[i].x, y = overworldText[i].y
            let width = surface.textWidth(overworldText[i].text, font: .regular11)
            for j in 0..<overworldTextCount {
                let x2 = overworldText[j].x, y2 = overworldText[j].y
                if x + width + 2 < x2 || x - width - 2 > x2 { continue }
                if y + height + 2 < y2 || y - height - 2 > y2 { continue }
                overworldText[i].y += height + 1
            }
        }
        for i in 0..<overworldTextCount {
            let t = overworldText[i]
            surface.drawStringCentre(t.text, x: t.x, y: t.y, font: .regular11, colour: t.colour)
        }
        for i in 0..<healthBarCount {
            let h = healthBars[i]
            surface.drawBoxAlpha(x: h.x - 15, y: h.y - 3, width: h.missing, height: 5, colour: Colour.green, alpha: 192)
            surface.drawBoxAlpha(x: h.x - 15 + h.missing, y: h.y - 3, width: 30 - h.missing, height: 5,
                                 colour: Colour.red, alpha: 192)
        }
    }

    /// mudclient_update_object_animation: swaps an animated object's model for the next frame.
    func updateObjectAnimation(_ index: Int, _ name: String) {
        let ox = objects[index].x, oy = objects[index].y
        let within: Bool
        if options.distantAnimation != 0 {
            within = true
        } else {
            let dx = ox - localPlayer.currentX / 128, dy = oy - localPlayer.currentY / 128
            let d = Mudclient.objectAnimationDistance
            within = dx > -d && dx < d && dy > -d && dy < d
        }
        guard ox >= 0 && oy >= 0 && ox < 96 && oy < 96 && within else { return }
        scene.removeModel(objects[index].model)
        let modelIndex = gameData.modelIndex(name)
        guard let source = gameModels[modelIndex], let old = objects[index].model else { return }
        let model = source.copy()
        scene.addModel(model)
        model.setLight(gouraud: true, ambience: 48, diffuse: 48, x: -50, y: -10, z: -50)
        model.copyPosition(from: old)
        model.key = index
        objects[index].model = model
    }

    /// mudclient_animate_objects: fires, torches and spell effects.
    func animateObjects() {
        if objectAnimationCycle != lastObjectAnimationCycle {
            lastObjectAnimationCycle = objectAnimationCycle
            let frame = objectAnimationCycle + 1
            for i in 0..<objectCount {
                switch objects[i].id {
                case Mudclient.fireId: updateObjectAnimation(i, "firea\(frame)")
                case Mudclient.fireplaceId: updateObjectAnimation(i, "fireplacea\(frame)")
                case Mudclient.lightningId: updateObjectAnimation(i, "lightning\(frame)")
                case Mudclient.fireSpellId: updateObjectAnimation(i, "firespell\(frame)")
                case Mudclient.spellChargeId: updateObjectAnimation(i, "spellcharge\(frame)")
                default: break
                }
            }
        }
        if torchAnimationCycle != lastTorchAnimationCycle {
            lastTorchAnimationCycle = torchAnimationCycle
            let frame = torchAnimationCycle + 1
            for i in 0..<objectCount {
                if objects[i].id == Mudclient.torchId {
                    updateObjectAnimation(i, "torcha\(frame)")
                } else if objects[i].id == Mudclient.skullTorchId {
                    updateObjectAnimation(i, "skulltorcha\(frame)")
                }
            }
        }
        if clawAnimationCycle != lastClawAnimationCycle {
            lastClawAnimationCycle = clawAnimationCycle
            for i in 0..<objectCount where objects[i].id == Mudclient.clawSpellId {
                updateObjectAnimation(i, "clawspell\(clawAnimationCycle + 1)")
            }
        }
    }

    /// mudclient_draw_entity_sprites: adds players, projectiles, NPCs, ground items and magic bubbles as scene sprites.
    func drawEntitySprites() {
        scene.reduceSprites(sceneSpriteCount)
        sceneSpriteCount = 0
        for i in 0..<playerCount {
            guard let p = players[i], p.bottomColour != 255 else { continue }
            let x = p.currentX, y = p.currentY
            let id = scene.addSprite(id: 5000 + i, x: x, y: -world.elevation(x, y), z: y, width: 145, height: 220,
                                     tag: i + Mudclient.playerFaceTag)
            sceneSpriteCount += 1
            if p === localPlayer { scene.setLocalPlayer(id) }
            if p.currentAnimation == 8 {
                scene.setSpriteTranslateX(id, -30)
            } else if p.currentAnimation == 9 {
                scene.setSpriteTranslateX(id, 30)
            }
        }
        let range = Mudclient.projectileRangeMax
        for i in 0..<playerCount {
            guard let p = players[i], p.projectileRange > 0 else { continue }
            var target: GameCharacter?
            if p.attackingNpcServerIndex != -1 {
                target = npcsServer[p.attackingNpcServerIndex]
            } else if p.attackingPlayerServerIndex != -1 {
                target = playerServer[p.attackingPlayerServerIndex]
            }
            guard let target else { continue }
            let sx = p.currentX, sy = p.currentY
            let selev = -world.elevation(sx, sy) - 110
            let dx = target.currentX, dy = target.currentY
            // the original game uses the unicorn's height for players here
            let targetHeight = p.attackingNpcServerIndex != -1 ? gameData.npcs[target.npcId].height : gameData.npcs[0].height
            let delev = -world.elevation(dx, dy) - targetHeight / 2
            let rx = (sx * p.projectileRange + dx * (range - p.projectileRange)) / range
            let rz = (selev * p.projectileRange + delev * (range - p.projectileRange)) / range
            let ry = (sy * p.projectileRange + dy * (range - p.projectileRange)) / range
            _ = scene.addSprite(id: spriteProjectile + p.incomingProjectileSprite, x: rx, y: rz, z: ry, width: 32,
                                height: 32, tag: 0)
            sceneSpriteCount += 1
        }
        for i in 0..<npcCount {
            guard let n = npcs[i] else { continue }
            let x = n.currentX, y = n.currentY
            let def = gameData.npcs[n.npcId]
            let id = scene.addSprite(id: 20000 + i, x: x, y: -world.elevation(x, y), z: y, width: def.width,
                                     height: def.height, tag: i + Mudclient.npcFaceTag)
            sceneSpriteCount += 1
            if n.currentAnimation == 8 {
                scene.setSpriteTranslateX(id, -30)
            } else if n.currentAnimation == 9 {
                scene.setSpriteTranslateX(id, 30)
            }
        }
        for i in 0..<groundItemCount {
            let g = groundItems[i]
            let x = g.x * Mudclient.magicLoc + 64, y = g.y * Mudclient.magicLoc + 64
            _ = scene.addSprite(id: 40000 + g.id, x: x, y: -world.elevation(x, y) - g.z, z: y, width: 96, height: 64,
                                tag: i + Mudclient.groundItemFaceTag)
            sceneSpriteCount += 1
        }
        for i in 0..<magicBubbleCount {
            let b = magicBubbles[i]
            let x = b.x * Mudclient.magicLoc + 64, y = b.y * Mudclient.magicLoc + 64
            _ = scene.addSprite(id: 50000 + i, x: x, y: -world.elevation(x, y), z: y, width: 128,
                                height: b.type == 0 ? 256 : 64, tag: i + 50000)
            sceneSpriteCount += 1
        }
    }

    /// The first half of mudclient_draw_game: roofs, entities, the 3D scene and
    /// everything drawn over it before the UI. Returns false when draw_game
    /// returns early (death screen, character designer, sleeping, loading).
    @discardableResult
    func drawGameScene() -> Bool {
        if deathScreenTimeout != 0 {
            surface.fadeToBlack()
            surface.drawStringCentre("Oh dear! You are dead...", x: surface.width / 2, y: (surface.height - 12) / 2,
                                     font: .bold24, colour: Colour.red)
            drawChatMessageTabs()
            draw()
            return false
        }
        if showAppearanceChange {
            drawAppearancePanel()
            return false
        }
        if isSleeping {
            drawSleep()
            return false
        }
        if !world.playerAlive { return false }

        let plane = lastPlaneIndex
        for i in 0..<World.terrainCount {
            scene.removeModel(world.roofModels[plane][i])
            if plane == 0 {
                scene.removeModel(world.wallModels[1][i])
                scene.removeModel(world.roofModels[1][i])
                scene.removeModel(world.wallModels[2][i])
                scene.removeModel(world.roofModels[2][i])
            }
            if options.showRoofs != 0 {
                fogOfWar = true
                if plane == 0 && !world.isUnderRoof(localPlayer.currentX, localPlayer.currentY) {
                    scene.addModel(world.roofModels[plane][i])
                    scene.addModel(world.wallModels[1][i])
                    scene.addModel(world.roofModels[1][i])
                    scene.addModel(world.wallModels[2][i])
                    scene.addModel(world.roofModels[2][i])
                    fogOfWar = false
                }
            }
        }
        if options.lowmem == 0 { animateObjects() }
        drawEntitySprites()
        surface.interlace = false
        surface.blackScreen()
        surface.interlace = options.interlace != 0
        if plane == 3 && options.flicker != 0 {
            let ambience = 40 + Int((Float(CRandom.shared.next()) / Float(CRandom.randMax)) * 3)
            let diffuse = 40 + Int((Float(CRandom.shared.next()) / Float(CRandom.randMax)) * 7)
            scene.setLight(ambience: ambience, diffuse: diffuse, x: -50, y: -10, z: -50)
        }
        actionBubbleCount = 0
        receivedMessagesCount = 0
        healthBarCount = 0
        overworldTextCount = 0
        if settingsCameraAuto != 0 && !fogOfWar { autoRotateCamera() }
        if options.zoomCamera != 0 {
            let clipFar = Int((2400 / Float(Mudclient.zoomOutdoors)) * Float(cameraZoom))
            scene.clipFar3d = clipFar
            scene.clipFar2d = clipFar
            scene.fogZDistance = clipFar - 100
        } else {
            scene.clipFar3d = 2400
            scene.clipFar2d = 2400
            scene.fogZDistance = 2300
        }
        if options.interlace != 0 {
            scene.clipFar3d -= 200
            scene.clipFar2d -= 200
            scene.fogZDistance -= 200
        }
        if gameHeight > Mudclient.vanillaHeight {
            let clipFar = Int(Float(scene.clipFar3d) / (Float(Mudclient.vanillaHeight) / Float(gameHeight)))
            scene.clipFar3d = clipFar
            scene.clipFar2d = clipFar
            scene.fogZDistance = clipFar - 100
        }
        if options.fogOfWar == 0 {
            scene.clipFar3d = 20000
            scene.clipFar2d = 20000
            scene.fogZDistance = 20000
        }
        let cameraX = cameraAutoRotatePlayerX + cameraRotationX
        let cameraZ = cameraAutoRotatePlayerY + cameraRotationY
        let touch = isTouchLayout
        let offsetY = touch ? 100 : (isCompact ? 75 : 0)
        scene.setCamera(x: cameraX, y: -world.elevation(cameraX, cameraZ) - offsetY, z: cameraZ, yaw: 912,
                        pitch: cameraRotation * 4, roll: 0, distance: cameraZoom * 2)
        surface.blackScreen()
        scene.render()
        drawOverhead()

        if mouseClickXStep > 0 {
            surface.drawSprite(x: mouseClickXX - 8, y: mouseClickXY - 8, id: spriteMedia + 14 + (24 - mouseClickXStep) / 6)
        } else if mouseClickXStep < 0 {
            surface.drawSprite(x: mouseClickXX - 8, y: mouseClickXY - 8, id: spriteMedia + 18 + (24 + mouseClickXStep) / 6)
        }
        if options.displayFps != 0 {
            let offsetX = isInWilderness ? 70 : 0
            surface.drawString("Fps: \(fps)", x: touch ? 9 + offsetX : surface.width - 62 - offsetX,
                               y: surface.height - 22, font: .bold12, colour: Colour.yellow)
        }
        if systemUpdate != 0 {
            let seconds = systemUpdate / 50
            let text = "System update in: \(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)"
            surface.drawStringCentre(text, x: 256, y: gameHeight - 19, font: .bold12, colour: Colour.yellow)
        }
        if !loadingArea {
            let depth = wildernessDepth
            isInWilderness = depth > 0
            if isInWilderness {
                let x = touch ? 29 : surface.width - 59
                surface.drawSprite(x: x, y: surface.height - 68, id: spriteMedia + 13)
                surface.drawStringCentre("Wilderness", x: x + 12, y: surface.height - 32, font: .bold12, colour: Colour.yellow)
                surface.drawStringCentre("Level: \(1 + depth / 6)", x: x + 12, y: surface.height - 19, font: .bold12,
                                         colour: Colour.yellow)
                if showWildernessWarning == 0 { showWildernessWarning = 2 }
            }
            if options.wildernessWarning != 0 && showWildernessWarning == 0 && depth > -10 && depth <= 0 {
                showWildernessWarning = 1
            }
        }
        return true
    }

    /// mudclient_draw_game
    public func drawGame() {
        guard drawGameScene() else { return }
        drawChatMessageTabsPanel()
        drawUI()
        surface.drawStringShadow = false
        drawChatMessageTabs()
        if options.statusBars != 0 && isTouchLayout {
            surface.drawStringShadow = true
            drawStatusBars()
        }
        draw()
    }

    /// mudclient_draw_ui
    func drawUI() {
        drawUITabs()
        let noMenus = !showOptionMenu && !showRightClickMenu
        if noMenus { menuItemsCount = 0 }
        if options.experienceDrops != 0 { drawExperienceDrops() }
        if options.statusBars != 0 && !isTouchLayout { drawStatusBars() }
        let transactionMenus = { [self] in
            if showRightClickMenu { drawRightClickMenu() } else { createTopMouseMenu() }
        }
        if showAdditionalOptions {
            drawAdditionalOptions()
            if showDialogConfirm { drawConfirm() }
        } else if showDialogConfirm {
            drawConfirm()
        } else if logoutTimeout != 0 {
            drawLogout()
        } else if showDialogWelcome {
            drawWelcome()
        } else if showDialogServerMessage {
            drawServerMessage()
        } else if showWildernessWarning == 1 {
            drawWildernessWarning()
        } else if showDialogBank && combatTimeout == 0 {
            drawBank()
            if options.bankMenus != 0 { transactionMenus() }
        } else if showDialogShop && combatTimeout == 0 {
            drawShop()
        } else if showDialogTradeConfirm {
            drawTradeConfirm()
        } else if showDialogTrade {
            drawTrade()
            if options.transactionMenus != 0 { transactionMenus() }
        } else if showDialogDuelConfirm {
            drawDuelConfirm()
        } else if showDialogDuel {
            drawDuel()
            if options.transactionMenus != 0 { transactionMenus() }
        } else if showChangePasswordStep != 0 {
            drawChangePassword()
        } else if showDialogSocialInput != 0 {
            drawSocialInput()
        } else {
            if showOptionMenu { drawOptionMenu() }
            setActiveUITab(noMenus: noMenus)
            if isInCombat || options.combatStyleAlways != 0 { drawCombatStyle() }
            if showUITab == 0 && noMenus { createRightClickMenu() }
            drawActiveUITab(noMenus: noMenus)
            if !showOptionMenu {
                if showRightClickMenu { drawRightClickMenu() } else { createTopMouseMenu() }
            }
            drawHoverTooltip()
        }
        mouseButtonClick = 0
    }
}
