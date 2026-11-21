// Port of rsc-c ui/stats-tab.c: skills, equipment status and quest list.

import Foundation

extension Mudclient {
    func drawEquipmentStatus(x: Int, y: Int, lineBreak: Int, noMenus: Bool) {
        var y = y
        let names = StatsTab.equipmentStatNames
        if noMenus && selectedWiki && mouseX > x + 5 && mouseY > y - lineBreak && mouseY < y + lineBreak / 2 - 4 {
            menuAddWiki(display: "Equipment Status", page: "Equipment")
        }
        surface.drawString("Equipment Status", x: x + 5, y: y, font: .bold13, colour: Colour.yellow)
        y += lineBreak
        for i in 0..<3 {
            if noMenus && selectedWiki && mouseX > x + 5 && mouseX < x + StatsTab.width / 2 + 25 &&
                mouseY > y - lineBreak && mouseY < y + 3 {
                menuAddWiki(display: names[i], page: names[i])
            }
            surface.drawString("\(names[i]):@yel@\(playerStatEquipment[i])", x: x + 5, y: y, font: .bold12,
                               colour: Colour.white)
            if i < 2 {
                if noMenus && selectedWiki && mouseX > x + StatsTab.width / 2 + 25 &&
                    mouseY > y - lineBreak && mouseY < y + 3 {
                    menuAddWiki(display: names[i + 3], page: names[i + 3])
                }
                surface.drawString("\(names[i + 3]):@yel@\(playerStatEquipment[i + 3])",
                                   x: x + StatsTab.width / 2 + 25, y: y, font: .bold12, colour: Colour.white)
            }
            y += lineBreak + 1
        }
    }

    func drawUITabStats(noMenus: Bool) {
        let statsWidth = StatsTab.width
        var uiX = surface.width - statsWidth - 3
        var uiY = UITabs.buttonSize + 1
        var height = StatsTab.height
        let compact = isTouch || surface.height < height + 12 + uiY
        let tabs: [String]
        if compact {
            height = StatsTab.compactHeight
            tabs = ["Skills", "Gear", "Quests"]
        } else {
            tabs = ["Skills", "Quests"]
        }
        let lineBreak = compact && !isTouch ? 11 : 12
        if !compact && options.fatigue == 0 { height -= lineBreak }
        if options.maxSkills < 18 { height -= lineBreak }
        if options.totalExperience != 0 || options.remainingExperience != 0 { height += lineBreak }
        if compact && uiTabStatsSubTab == 1 { height = 78 }
        if isTouch {
            height = 198
            uiX = uiTabsTouchX - statsWidth - 1
            uiY = uiTabsTouchY + UITabs.touchHeight - height - 2
        }
        panelQuests.controlHeight[controlListQuest] = height - StatsTab.tabHeight

        let notTouch = isTouch ? 0 : 1
        if options.versionMedia >= 59 {
            drawUITabLabel(selectedTab: UITabs.stats, width: statsWidth + notTouch, x: uiX - notTouch,
                           y: uiY - UITabs.labelHeight)
        }
        uiTabMinX = uiX
        uiTabMaxX = surface.width
        uiTabMinY = 0
        uiTabMaxY = uiY + height + 5
        if isTouch {
            uiTabMaxX = uiX + statsWidth
            uiTabMinY = uiY - UITabs.labelHeight
            uiTabMaxY = uiY + height
        }

        surface.drawBoxAlpha(x: uiX, y: uiY + StatsTab.tabHeight, width: statsWidth, height: height - StatsTab.tabHeight,
                             colour: Colour.greyDC, alpha: 128)
        surface.drawLineHorizontal(x: uiX, y: uiY + StatsTab.tabHeight, width: statsWidth, colour: Colour.black)
        surface.drawTabs(x: uiX, y: uiY, width: statsWidth, height: StatsTab.tabHeight, tabs: tabs,
                         selected: uiTabStatsSubTab)
        if !compact && uiTabStatsSubTab > 1 { uiTabStatsSubTab = 1 }

        if uiTabStatsSubTab == 0 {
            drawSkills(uiX: uiX, uiY: uiY, compact: compact, lineBreak: lineBreak, noMenus: noMenus)
        } else if (!compact && uiTabStatsSubTab == 1) || (compact && uiTabStatsSubTab == 2) {
            let statsHeight = 36 + StatsTab.height + 5
            if noMenus && selectedWiki && mouseX > uiX + 5 && mouseY > uiY + 24 + lineBreak &&
                mouseY < uiY + statsHeight {
                var questIndex = panelQuests.controlListEntryMouseOver[controlListQuest]
                if questIndex > 0 {
                    questIndex -= 1
                    let name = StatsTab.questNames[questIndex]
                    var page = name
                    if let paren = name.firstIndex(of: "(") {
                        page = String(name[..<paren].dropLast())
                    }
                    menuAddWiki(display: name, page: page)
                }
            }
            panelQuests.clearList(controlListQuest)
            panelQuests.addListEntry(controlListQuest, index: 0, text: "@whi@Quest-list (green=completed)")
            for i in 0..<options.maxQuests {
                panelQuests.addListEntry(controlListQuest, index: i + 1,
                                         text: (questComplete[i] != 0 ? "@gre@" : "@red@") + StatsTab.questNames[i])
            }
            panelQuests.drawPanel()
        } else if compact && uiTabStatsSubTab == 1 {
            drawEquipmentStatus(x: uiX, y: uiY + 38, lineBreak: lineBreak, noMenus: noMenus)
        }

        guard noMenus else { return }
        let mx = mouseX - uiX, my = mouseY - uiY
        let withinX = options.offHandleScrollDrag != 0 ? true : mx >= 0 && mx < statsWidth
        if withinX && my >= 0 && my < height {
            let questTab = compact ? 2 : 1
            if uiTabStatsSubTab == questTab {
                if isTouch {
                    panelQuests.handleMouse(x: Mudclient.finger1X, y: Mudclient.finger1Y, lastButton: lastMouseButtonDown,
                                            isDown: Mudclient.finger1Down, scrollDelta: mouseScrollDelta)
                } else {
                    panelQuests.handleMouse(x: mouseX, y: mouseY, lastButton: lastMouseButtonDown,
                                            isDown: mouseButtonDown, scrollDelta: mouseScrollDelta)
                }
            }
            if my <= StatsTab.tabHeight {
                let total = compact ? 3 : 2
                let selected = mx / (statsWidth / total)
                if selected < 0 || selected >= total { return }
                if selectedWiki {
                    let page = compact && selected == 1 ? "Equipment" : tabs[selected]
                    menuAddWiki(display: tabs[selected], page: page)
                } else if mouseButtonClick == 1 {
                    uiTabStatsSubTab = selected
                }
            }
        }
    }

    private func drawSkills(uiX: Int, uiY: Int, compact: Bool, lineBreak: Int, noMenus: Bool) {
        let statsWidth = StatsTab.width
        var y = uiY + 36
        var selectedSkill = -1
        var totalExperience = 0
        if !compact {
            surface.drawString("Skills", x: uiX + 5, y: y, font: .bold13, colour: Colour.yellow)
            if noMenus && selectedWiki && mouseX > uiX + 5 && mouseX < uiX + statsWidth / 2 - 8 &&
                mouseY > y - (lineBreak - 1) && mouseY < y + 2 {
                menuAddWiki(display: "Skills", page: "Skills")
            }
            y += lineBreak + 1
        }
        let perColumn: Int, indent: Int, display: [String]
        if options.maxSkills < 18 {
            perColumn = 8; display = StatsTab.skillNames; indent = uiX + statsWidth / 2 - 7
        } else {
            perColumn = 9; display = StatsTab.shortSkillNames; indent = uiX + statsWidth / 2 - 5
        }
        for i in 0..<perColumn {
            totalExperience &+= playerExperience[i]
            totalExperience &+= playerExperience[i + perColumn]
            var colour = Colour.white
            if noMenus && mouseX > uiX + 3 && mouseY >= y - (lineBreak - 1) && mouseY < y + 2 &&
                mouseX < uiX + statsWidth / 2 - 8 {
                colour = Colour.red
                selectedSkill = i
            }
            surface.drawString("\(display[i]):@yel@\(playerSkillCurrent[i])/\(playerSkillBase[i])", x: uiX + 5, y: y,
                               font: .bold12, colour: colour)
            colour = Colour.white
            let j = i + perColumn
            if noMenus && mouseX >= uiX + 90 && mouseY >= y - lineBreak * (compact ? 1 : 2) &&
                mouseY < y - (compact ? 0 : lineBreak - 1) && mouseX < uiX + statsWidth {
                colour = Colour.red
                selectedSkill = j
            }
            surface.drawString("\(display[j]):@yel@\(playerSkillCurrent[j])/\(playerSkillBase[j])", x: indent,
                               y: y - (compact ? 0 : lineBreak + 1), font: .bold12, colour: colour)
            y += lineBreak + 1
        }
        if compact { y += lineBreak + 1 }
        if noMenus && selectedWiki && mouseX > indent && mouseY > y - lineBreak * 2 && mouseY < y - (lineBreak - 1) {
            menuAddWiki(display: "Quest Points", page: "Quest Points")
        }
        surface.drawString("Quest Points:@yel@\(playerQuestPoints)", x: indent, y: y - 13, font: .bold12,
                           colour: Colour.white)
        if !compact { y += lineBreak }
        if options.fatigue != 0 {
            if noMenus && selectedWiki && mouseX > uiX + 5 && mouseX < uiX + statsWidth / 2 - 5 &&
                mouseY > y - lineBreak * 2 && mouseY < y - (lineBreak - 1) {
                menuAddWiki(display: "Fatigue", page: "Fatigue")
            }
            surface.drawString("Fatigue: @yel@\((statFatigue * 100) / 750)%", x: uiX + 5, y: y - 13, font: .bold12,
                               colour: Colour.white)
            y += compact ? 2 : 8
        }
        if !compact {
            drawEquipmentStatus(x: uiX, y: y, lineBreak: lineBreak, noMenus: noMenus)
            y += 51
            y += lineBreak / 2
        }
        if isTouch { y += 2 }
        surface.drawLineHorizontal(x: uiX, y: y - (compact ? 12 : 15), width: statsWidth, colour: Colour.black)

        var wikiHeight = lineBreak * 2
        if options.totalExperience != 0 { wikiHeight += lineBreak }

        if selectedSkill != -1 {
            if !compact {
                surface.drawString("\(StatsTab.skillNames[selectedSkill]) skill", x: uiX + 5, y: y, font: .bold12,
                                   colour: Colour.yellow)
                y += lineBreak
            }
            let exp = StatsTab.experienceArray
            var nextLevelAt = exp[0]
            for j in 0..<98 where playerExperience[selectedSkill] >= exp[j] {
                nextLevelAt = exp[j + 1]
            }
            let totalXp = playerExperience[selectedSkill]
            surface.drawString("Total xp: \(formatNumberCommas(totalXp / 4))", x: uiX + 5, y: y, font: .bold12,
                               colour: Colour.white)
            y += lineBreak
            surface.drawString("Next level at: \(formatNumberCommas(nextLevelAt / 4))", x: uiX + 5, y: y,
                               font: .bold12, colour: Colour.white)
            if options.remainingExperience != 0 {
                y += lineBreak
                let remaining = nextLevelAt - totalXp
                let fraction = String(String(format: "%.2f", Float(remaining % 4) / 4).dropFirst())
                surface.drawString("Remaining xp: \(formatNumberCommas(remaining / 4))\(fraction)", x: uiX + 5, y: y,
                                   font: .bold12, colour: Colour.white)
            }
            if noMenus && selectedWiki {
                let name = StatsTab.skillNames[selectedSkill]
                menuAddWiki(display: name, page: name)
            }
        } else {
            if noMenus && selectedWiki && mouseX > uiX + 5 && mouseY > y - lineBreak &&
                mouseY < y - lineBreak + wikiHeight + 3 {
                menuAddWiki(display: "Experience", page: "Experience")
            }
            if !compact {
                surface.drawString("Overall levels", x: uiX + 5, y: y, font: .bold12, colour: Colour.yellow)
                y += lineBreak
            }
            var totalLevel = 0
            for i in 0..<StatsTab.skillNames.count { totalLevel += playerSkillBase[i] }
            surface.drawString("Skill total: \(formatNumberCommas(totalLevel))", x: uiX + 5, y: y, font: .bold12,
                               colour: Colour.white)
            y += lineBreak
            if options.totalExperience != 0 {
                surface.drawString("Total xp: \(formatNumberCommas(totalExperience / 4))", x: uiX + 5, y: y,
                                   font: .bold12, colour: Colour.white)
                y += lineBreak
            }
            if noMenus && selectedWiki && mouseX > uiX && mouseY > y - lineBreak && mouseY < y + 5 {
                menuAddWiki(display: "Combat level", page: "Combat level")
            }
            surface.drawString("Combat level: \(localPlayer.level)", x: uiX + 5, y: y, font: .bold12,
                               colour: Colour.white)
        }
    }
}
