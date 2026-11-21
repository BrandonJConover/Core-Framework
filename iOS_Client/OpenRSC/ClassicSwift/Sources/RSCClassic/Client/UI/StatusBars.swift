// Ports of rsc-c ui/status-bars.c, ui/experience-drops.c and ui/sleep.c.

import Foundation

extension Mudclient {
    // MARK: status-bars.c

    func drawStatusBars() {
        let compact = surface.width < 390
        let buttonHeight = compact ? 22 : 20
        var barWidth = 175 / 2 - 1
        if isTouch {
            barWidth = Int(Float(surface.width) * 0.353 / 2 - 6)
        } else if compact {
            barWidth = 106 / 2 - 1
        }
        let barHeight = isTouch ? 13 : 16
        let uiX = isTouch ? 4 : 7
        let uiY = isTouch ? surface.height - barHeight : 15 + buttonHeight * 5 + 6
        var x = uiX, y = uiY
        let hits = Mudclient.skillHits, prayer = Mudclient.skillPrayer
        surface.drawStatusBar(max: playerSkillBase[hits], current: playerSkillCurrent[hits], label: "Hits", x: x, y: y,
                              width: barWidth, height: barHeight, backgroundColour: Colour.red,
                              foregroundColour: Colour.green, isPercentage: false)
        let opponent = self.opponent()
        let showOpponent = opponent != nil && opponent!.maxHits != 0
        if !isTouch && barWidth >= surface.width / 6 && !showOpponent {
            y += barHeight + 5
        } else {
            x += barWidth + (isTouch ? 4 : 3)
        }
        surface.drawStatusBar(max: playerSkillBase[prayer], current: playerSkillCurrent[prayer], label: "Prayer",
                              x: x, y: y, width: barWidth, height: barHeight, backgroundColour: Colour.black,
                              foregroundColour: Colour.cyan, isPercentage: false)
        if isTouch {
            let gap: Float = Float(surface.width) * 0.293
            let advance: Float = Float(barWidth) + gap + 9
            x = Int(Float(x) + advance)
        }
        if showOpponent, let opponent {
            if isTouch { y = uiY } else { x = uiX; y += barHeight + 5 }
            let name = opponent.npcId != -1 ? gameData.npcs[opponent.npcId].name : opponent.name
            surface.drawStatusBar(max: opponent.maxHits, current: opponent.currentHits, label: name, x: x, y: y,
                                  width: isTouch ? barWidth : barWidth * 2 + 3, height: barHeight,
                                  backgroundColour: Colour.red, foregroundColour: Colour.green, isPercentage: false)
            if isTouch { x += barWidth + 4 }
        }
        if !isSleeping && options.fatigue != 0 {
            if isTouch { y = uiY } else { x = uiX; y += barHeight + 5 }
            var width = barWidth >= surface.width / 6 && !showOpponent ? barWidth : barWidth * 2 + 3
            if isTouch {
                if showOpponent {
                    width = barWidth
                } else {
                    width = Int(Float(barWidth) * 1.75)
                    let half: Float = Float(surface.width) * 0.353 / 2
                    let shift: Float = half - Float(width / 2) - 3
                    x = Int(Float(x) + shift)
                }
            }
            surface.drawStatusBar(max: 750, current: statFatigue, label: "Fatigue", x: x, y: y, width: width,
                                  height: barHeight, backgroundColour: Colour.black, foregroundColour: 0xe2e2e2,
                                  isPercentage: true)
        }
        x = isTouch ? 86 : surface.width - 2
        y = isTouch ? 108 + buttonHeight * 5 + 15 : 48
        for i in 0..<Mudclient.playerSkillCount {
            if i == prayer || i == hits { continue }
            if playerSkillCurrent[i] == playerSkillBase[i] { continue }
            let p = Float(playerSkillCurrent[i]) / Float(playerSkillBase[i])
            let colour: String
            if p >= 1.15 { colour = "@gre@" }
            else if p >= 1.1 { colour = "@gr3@" }
            else if p >= 1.05 { colour = "@gr2@" }
            else if p >= 1.0 { colour = "@gr1@" }
            else if p <= 0.9 { colour = "@red@" }
            else if p <= 0.95 { colour = "@or3@" }
            else if p <= 0.975 { colour = "@or2@" }
            else { colour = "@or1@" }
            surface.drawStringRight(cField("\(colour)\(StatsTab.skillNames[i]): \(playerSkillCurrent[i])/\(playerSkillBase[i])", 32),
                                    x: x, y: y, font: .regular11, colour: Colour.white)
            y += 14
        }
    }

    // MARK: experience-drops.c

    func drawExperienceDrops() {
        let x = surface.width / 2
        for i in 0..<experienceDropCount {
            let dropY = Int(experienceDropY[i])
            let amount = experienceDropAmount[i]
            let fraction = String(String(format: "%.2f", Float(amount % 4) / 4).dropFirst())
            surface.drawStringCentre("\(formatNumberCommas(amount / 4))\(fraction) \(StatsTab.skillNames[experienceDropSkill[i]]) XP",
                                     x: x, y: dropY, font: .bold12, colour: Colour.white)
            if experienceDropSpeed[i] > 0 { experienceDropY[i] -= experienceDropSpeed[i] }
            experienceDropSpeed[i] += 0.5
        }
        var visible = false
        for i in 0..<experienceDropCount where Int(experienceDropY[i]) > 0 { visible = true }
        if !visible { experienceDropCount = 0 }
    }

    // MARK: sleep.c

    private var sleepIsCompact: Bool { surface.width < Mudclient.vanillaWidth || surface.height < Mudclient.vanillaHeight }

    func drawSleep() {
        let compact = sleepIsCompact
        surface.fadeToBlack()
        let zzzWidth = 80 + (surface.width / 2 - Mudclient.vanillaWidth / 2)
        var frequency = 0.15 * Float(surface.width * surface.height) /
            Float(Mudclient.vanillaWidth * Mudclient.vanillaHeight)
        frequency = Float(fmin(Double(frequency), 1.0))
        let rng = CRandom.shared
        if rng.nextUnitFloat() <= frequency {
            // gcc evaluates the arguments right to left: colour, then y, then x
            let colour = Int32(truncatingIfNeeded: Int(rng.nextUnitFloat() * Float(Colour.white)))
            let y = Int(rng.nextUnitFloat() * Float(surface.height))
            let x = Int(rng.nextUnitFloat() * Float(zzzWidth))
            surface.drawStringCentre("ZZZ", x: x, y: y, font: .bold16, colour: colour)
        }
        if rng.nextUnitFloat() <= frequency {
            let colour = Int32(truncatingIfNeeded: Int(rng.nextUnitFloat() * Float(Colour.white)))
            let y = Int(rng.nextUnitFloat() * Float(surface.height))
            let x = Int(Float(surface.width) - rng.nextUnitFloat() * Float(zzzWidth))
            surface.drawStringCentre("ZZZ", x: x, y: y, font: .bold16, colour: colour)
        }
        let x = surface.width / 2
        var y = surface.height / 2 - (compact ? Mudclient.minHeight : Mudclient.vanillaHeight) / 2
        y += compact ? 28 : 50
        if isTouch { y += 15 }
        surface.drawBox(x: x - 100, y: y + 74 + (compact ? 0 : 36), width: 200, height: compact ? 36 : 40,
                        colour: Colour.black)
        surface.drawStringCentre("You are sleeping", x: x, y: y, font: .bold24, colour: Colour.yellow)
        y += compact ? 28 : 40
        surface.drawStringCentre("Fatigue: \((fatigueSleeping * 100) / 750)%", x: x, y: y, font: .bold24,
                                 colour: Colour.yellow)
        y += compact ? 25 : 50
        let top = compact ? (isTouch ? "To wake up just tap below" : "To wake up just use your keyboard")
            : (isTouch ? "When you want to wake up just tap below" : "When you want to wake up just use your")
        surface.drawStringCentre(top, x: x, y: y, font: .bold16, colour: Colour.white)
        y += 20
        let bottom = compact ? (isTouch ? "and type the word in the box" : "to type the word in the box below")
            : (isTouch ? "and type the word in the box" : "keyboard to type the word in the box below")
        surface.drawStringCentre(bottom, x: x, y: y, font: .bold16, colour: Colour.white)
        y += 20
        surface.drawStringCentre("\(inputTextCurrent)*", x: x, y: y, font: .bold16, colour: Colour.cyan)
        y += compact ? 16 : 49
        if let status = sleepingStatusText {
            surface.drawStringCentre(status, x: x, y: y + 31, font: .bold16, colour: Colour.red)
        } else {
            surface.drawSprite(x: x - 127, y: y + 1, id: spriteTexture + 1)
        }
        surface.drawBorder(x: x - 128, y: y, width: 257, height: 42, colour: Colour.white)
        drawChatMessageTabs()
        y += 61
        surface.drawStringCentre("If you can't read the word", x: x, y: y, font: .bold12, colour: Colour.white)
        y += 15
        surface.drawStringCentre("@yel@\(isTouch ? "tap" : "click") here@whi@ to get a different one", x: x, y: y,
                                 font: .bold12, colour: Colour.white)
        draw()
    }

    private func sendSleepWord(_ word: String) {
        guard let ps = packetStream else { return }
        ps.newPacket(ClientOpcode.sleepWord)
        ps.putString(word)
        if sleepWordDelay == 0 {
            ps.putByte(0)
            sleepWordDelay = 1
        }
        ps.sendPacket()
    }

    func handleSleepInput() {
        let compact = sleepIsCompact
        let x = surface.width / 2
        var y = surface.height / 2 - (compact ? Mudclient.minHeight : Mudclient.vanillaHeight) / 2 + (compact ? 28 : 50)
        if isTouch { y += 15 }
        if !inputTextFinal.isEmpty {
            let lower = inputTextFinal.lowercased()
            if lower.hasPrefix("::lostcon") {
                packetStream?.close()
            } else if lower.hasPrefix("::closecon") {
                closeConnection()
            } else {
                sendSleepWord(inputTextFinal)
                inputTextCurrent = ""
                inputTextFinal = ""
                sleepingStatusText = "Please wait..."
            }
        }
        let keyboardX = x - 100 - 3, keyboardY = y + 74 + (compact ? 0 : 36)
        if lastMouseButtonDown == 1 && mouseX > keyboardX && mouseX < keyboardX + 200 && mouseY > keyboardY &&
            mouseY < keyboardY + 28 {
            triggerKeyboard(text: inputTextCurrent, isPassword: false, x: keyboardX, y: keyboardY, width: 200,
                            height: 28, font: .bold16, isCentred: true)
        }
        if lastMouseButtonDown == 1 && mouseY > y + (compact ? 157 : 225) && mouseY < y + (compact ? 192 : 260) &&
            mouseX > x - 200 && mouseX < x + 200 {
            sendSleepWord("-null-")
            inputTextCurrent = ""
            inputTextFinal = ""
            sleepingStatusText = "Please wait..."
        }
        lastMouseButtonDown = 0
    }
}
