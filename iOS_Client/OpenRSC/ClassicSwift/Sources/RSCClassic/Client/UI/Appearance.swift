// Character design screen: port of rsc-c's ui/appearance.c.

extension Mudclient {
    static let appearanceArrowSize = 20, appearanceBoxWidth = 53, appearanceColumnWidth = 54
    static let appearanceAcceptWidth = 200, appearanceAcceptHeight = 30
    static let appearanceCharacterWidth = 64, appearanceCharacterHeight = 102

    private func createAppearanceBox(_ type: String, _ x: Int, _ y: Int) -> (left: Int, right: Int) {
        let p = panelAppearance!
        let padding = isCompact ? 5 : 8
        let boxHeight = padding + (isCompact ? 25 : 33)
        p.addBoxRounded(x: x, y: y, width: Mudclient.appearanceBoxWidth, height: boxHeight)
        let parts = type.split(separator: "\n").map(String.init)
        if parts.count < 2 {
            p.addTextCentre(x: x, y: y, text: parts[0], font: .bold12, alternativeColour: true)
        } else {
            p.addTextCentre(x: x, y: y - padding, text: parts[0], font: .bold12, alternativeColour: true)
            p.addTextCentre(x: x, y: y + padding, text: parts[1], font: .bold12, alternativeColour: true)
        }
        let size = Mudclient.appearanceArrowSize
        let left = p.addButton(x: x - 40, y: y, width: size, height: size)
        p.addSprite(x: x - 40, y: y, spriteId: Panel.baseSpriteStart + 7)
        let right = p.addButton(x: x + 40, y: y, width: size, height: size)
        p.addSprite(x: x + 40, y: y, spriteId: Panel.baseSpriteStart + 6)
        return (left, right)
    }

    public func createAppearancePanel() {
        panelAppearance = makePanel(100)
        let p = panelAppearance!
        let compact = isCompact
        let x = (compact ? Mudclient.minWidth : Mudclient.vanillaWidth) / 2
        var y = 10
        if !compact {
            p.addTextCentre(x: x, y: y, text: "Please design Your Character", font: .bold14, alternativeColour: true)
            y += 14
            p.addTextCentre(x: x - 55, y: y + 110, text: "Front", font: .bold13, alternativeColour: true)
            p.addTextCentre(x: x, y: y + 110, text: "Side", font: .bold13, alternativeColour: true)
            p.addTextCentre(x: x + 55, y: y + 110, text: "Back", font: .bold13, alternativeColour: true)
            y += 145
        } else {
            y += 102
        }
        let padding = compact ? 5 : 8
        let boxHeight = padding + (compact ? 25 : 33)
        let margin = boxHeight + (compact ? 3 : 9)
        let col = Mudclient.appearanceColumnWidth
        (controlAppearanceHeadLeft, controlAppearanceHeadRight) = createAppearanceBox("Head\nType", x - col, y)
        (controlAppearanceHairLeft, controlAppearanceHairRight) = createAppearanceBox("Hair\nColor", x + col, y)
        y += margin
        (controlAppearanceGenderLeft, controlAppearanceGenderRight) = createAppearanceBox("Gender", x - col, y)
        (controlAppearanceTopLeft, controlAppearanceTopRight) = createAppearanceBox("Top\nColor", x + col, y)
        y += margin
        (controlAppearanceSkinLeft, controlAppearanceSkinRight) = createAppearanceBox("Skin\nColor", x - col, y)
        (controlAppearanceBottomLeft, controlAppearanceBottomRight) = createAppearanceBox("Bottom\nColor", x + col, y)
        y += margin - (compact ? -1 : 3)
        p.addButtonBackground(x: x, y: y, width: Mudclient.appearanceAcceptWidth, height: Mudclient.appearanceAcceptHeight)
        p.addTextCentre(x: x, y: y, text: "Accept", font: .bold14, alternativeColour: false)
        controlAppearanceAccept = p.addButton(x: x, y: y, width: Mudclient.appearanceAcceptWidth,
                                              height: Mudclient.appearanceAcceptHeight)
    }

    private func headTypeInvalid(_ type: Int) -> Bool {
        let g = gameData.animations[type].gender
        return (g & 3) != 1 || (g & (4 * appearanceHeadGender)) == 0
    }

    public func handleAppearancePanelInput() {
        let p = panelAppearance!
        p.handleMouse(x: mouseX, y: mouseY, lastButton: lastMouseButtonDown, isDown: mouseButtonDown,
                      scrollDelta: mouseScrollDelta)
        let count = gameData.animations.count
        if p.isClicked(controlAppearanceHeadLeft) {
            repeat { appearanceHeadType = (appearanceHeadType - 1 + count) % count } while headTypeInvalid(appearanceHeadType)
        }
        if p.isClicked(controlAppearanceHeadRight) {
            repeat { appearanceHeadType = (appearanceHeadType + 1) % count } while headTypeInvalid(appearanceHeadType)
        }
        let hair = GameCharacter.hairColours.count
        if p.isClicked(controlAppearanceHairLeft) { appearanceHairColour = (appearanceHairColour - 1 + hair) % hair }
        if p.isClicked(controlAppearanceHairRight) { appearanceHairColour = (appearanceHairColour + 1) % hair }
        if p.isClicked(controlAppearanceGenderLeft) || p.isClicked(controlAppearanceGenderRight) {
            appearanceHeadGender = 3 - appearanceHeadGender
            while headTypeInvalid(appearanceHeadType) { appearanceHeadType = (appearanceHeadType + 1) % count }
            while true {
                let g = gameData.animations[appearanceBodyType].gender
                if (g & 3) == 2 && (g & (4 * appearanceHeadGender)) != 0 { break }
                appearanceBodyType = (appearanceBodyType + 1) % count
            }
        }
        let tb = GameCharacter.topBottomColours.count
        if p.isClicked(controlAppearanceTopLeft) { appearanceTopColour = (appearanceTopColour - 1 + tb) % tb }
        if p.isClicked(controlAppearanceTopRight) { appearanceTopColour = (appearanceTopColour + 1) % tb }
        let skin = GameCharacter.skinColours.count
        if p.isClicked(controlAppearanceSkinLeft) { appearanceSkinColour = (appearanceSkinColour - 1 + skin) % skin }
        if p.isClicked(controlAppearanceSkinRight) { appearanceSkinColour = (appearanceSkinColour + 1) % skin }
        if p.isClicked(controlAppearanceBottomLeft) { appearanceBottomColour = (appearanceBottomColour - 1 + tb) % tb }
        if p.isClicked(controlAppearanceBottomRight) { appearanceBottomColour = (appearanceBottomColour + 1) % tb }
        if p.isClicked(controlAppearanceAccept) {
            if let ps = packetStream {
                ps.newPacket(ClientOpcode.appearance)
                ps.putByte(appearanceHeadGender)
                ps.putByte(appearanceHeadType)
                ps.putByte(appearanceBodyType)
                ps.putByte(2)
                ps.putByte(appearanceHairColour)
                ps.putByte(appearanceTopColour)
                ps.putByte(appearanceBottomColour)
                ps.putByte(appearanceSkinColour)
                ps.sendPacket()
            }
            surface.blackScreen()
            showAppearanceChange = false
        }
    }

    public func drawAppearancePanel() {
        surface.interlace = false
        surface.blackScreen()
        panelAppearance.drawPanel()
        let compact = isCompact
        let x = surface.width / 2
        let y = (compact ? -7 : 25) + (surface.height / 2 - (compact ? Mudclient.minHeight : Mudclient.vanillaHeight) / 2)
        let w = Mudclient.appearanceCharacterWidth, h = Mudclient.appearanceCharacterHeight
        let bottom = GameCharacter.topBottomColours[appearanceBottomColour]
        let top = GameCharacter.topBottomColours[appearanceTopColour]
        let hair = GameCharacter.hairColours[appearanceHairColour]
        let skin = GameCharacter.skinColours[appearanceSkinColour]
        let legs = gameData.animations[AnimationIndex.legs].fileId
        let legs2 = gameData.animations[2].fileId
        let body = gameData.animations[appearanceBodyType].fileId
        let head = gameData.animations[appearanceHeadType].fileId
        for (i, dx) in [-55, 0, 55].enumerated() {
            let frame = i * 6
            surface.drawSpriteScaleMask(x: x - 32 + dx, y: y, width: w, height: h, id: (i == 0 ? legs : legs2) + frame,
                                        colour: bottom)
            surface.drawSpriteTransformMask(x: x - 32 + dx, y: y, width: w, height: h, id: body + frame,
                                            maskColour: top, skinColour: skin, skewX: 0, flip: false)
            surface.drawSpriteTransformMask(x: x - 32 + dx, y: y, width: w, height: h, id: head + frame,
                                            maskColour: hair, skinColour: skin, skewX: 0, flip: false)
        }
        if options.lowmem == 0 { drawBlueBar() }
        draw()
    }
}
