// "Additional options" dialog and the confirm box: ports of rsc-c's
// ui/additional-options.c and ui/confirm.c.

import Foundation

public enum OptionBinding {
    case checkbox(ReferenceWritableKeyPath<Options, Int>)
    case int(ReferenceWritableKeyPath<Options, Int>)
    case string(ReferenceWritableKeyPath<Options, String>)
}

extension Mudclient {
    static let additionalOptionsWidth = 320, additionalOptionsHeight = 224, additionalOptionsTabHeight = 24
    static let optionHorizGap = 18
    static let optionTabs = ["Game", "Controls", "UI", "Bank"]
    static let confirmDialogWidth = 300, confirmDialogHeight = 80, confirmButtonSize = 40

    private func addOptionLabel(_ panel: Panel, _ label: String, _ x: Int, _ y: Int) -> Int {
        panel.addText(x: x, y: y, text: label, font: .bold12, alternativeColour: false)
        return surface.textWidth(label, font: .bold12) + 2
    }

    private func addOptionString(_ panel: Panel, _ label: String, _ text: String, _ maxLength: Int, _ x: Int,
                                 _ y: Int) -> Int {
        let w = addOptionLabel(panel, label, x, y)
        let control = panel.addTextInput(x: x + w, y: y, width: Mudclient.additionalOptionsWidth / 2 - 10, height: 15,
                                         font: .bold12, maxLength: maxLength, isPassword: false, alternativeColour: true)
        panel.updateText(control, text)
        return control
    }

    private func addOptionCheckbox(_ panel: Panel, _ label: String, _ checked: Int, _ x: Int, _ y: Int) -> Int {
        let w = addOptionLabel(panel, label, x, y)
        let control = panel.addCheckbox(x: x + w, y: y - 7, width: 14, height: 14)
        panel.toggleCheckbox(control, activated: checked != 0)
        return control
    }

    public func createOptionsPanel() {
        gameOptions = Array(repeating: nil, count: 50)
        controlOptions = Array(repeating: nil, count: 50)
        uiOptions = Array(repeating: nil, count: 50)
        bankOptions = Array(repeating: nil, count: 50)
        let uiX = surface.width / 2 - Mudclient.additionalOptionsWidth / 2
        let uiY = surface.height / 2 - Mudclient.additionalOptionsHeight / 2
        let top = uiY + Mudclient.optionHorizGap + Mudclient.additionalOptionsTabHeight + 4
        let column2 = (Mudclient.additionalOptionsWidth - 4) / 2
        let o = options

        /// Lays out one panel: two columns of checkboxes and number fields.
        func build(_ panel: Panel, _ columns: [[(String, OptionBinding, Int)]]) -> [OptionBinding?] {
            var bindings = [OptionBinding?](repeating: nil, count: 50)
            var x = uiX + 4
            for column in columns {
                var y = top
                for (label, binding, maxLength) in column {
                    let control: Int
                    switch binding {
                    case .checkbox(let path): control = addOptionCheckbox(panel, label, o[keyPath: path], x, y)
                    case .int(let path): control = addOptionString(panel, label, String(o[keyPath: path]), maxLength, x, y)
                    case .string(let path): control = addOptionString(panel, label, o[keyPath: path], maxLength, x, y)
                    }
                    bindings[control] = binding
                    y += Mudclient.optionHorizGap
                }
                x += column2
            }
            return bindings
        }

        panelGameOptions = makePanel(50)
        var game1: [(String, OptionBinding, Int)] = [
            ("@whi@Members (restart): ", .checkbox(\.members), 0),
            ("@whi@Idle logout: ", .checkbox(\.idleLogout), 0),
            ("@whi@Remember username:", .checkbox(\.rememberUsername), 0),
            ("@whi@Remember password: ", .checkbox(\.rememberPassword), 0),
            ("@whi@Diversify NPCs: ", .checkbox(\.diversifyNpcs), 0),
            ("@whi@3D ground items: ", .checkbox(\.groundItemModels), 0),
        ]
        game1.append((o.members != 0 ? "@whi@Rename Herblaw items: " : "@whi@Show potion dosage: ",
                      .checkbox(\.renameHerblawItems), 0))
        var game2: [(String, OptionBinding, Int)] = []
        if o.versionEntity > 8 { game2.append(("@whi@HQ sprites (restart): ", .checkbox(\.tgaSprites), 0)) }
        game2 += [
            ("@whi@Show roofs: ", .checkbox(\.showRoofs), 0),
            ("@whi@Interlace (F1): ", .checkbox(\.interlace), 0),
            ("@whi@Low memory (restart): ", .checkbox(\.lowmem), 0),
            ("@whi@Underground flicker: ", .checkbox(\.flicker), 0),
            ("@whi@Fog of war: ", .checkbox(\.fogOfWar), 0),
            ("@whi@Field of view: ", .int(\.fieldOfView), 3),
        ]
        gameOptions = build(panelGameOptions, [game1, game2])

        panelControlOptions = makePanel(50)
        controlOptions = build(panelControlOptions, [[
            ("@whi@Mouse wheel: ", .checkbox(\.mouseWheel), 0),
            ("@whi@Middle click camera: ", .int(\.middleClickCamera), 4),
            ("@whi@Zoom camera: ", .checkbox(\.zoomCamera), 0),
            ("@whi@Tab message respond: ", .checkbox(\.tabRespond), 0),
            ("@whi@Option number keys: ", .checkbox(\.optionNumbers), 0),
            ("@whi@Compass menu: ", .checkbox(\.compassMenu), 0),
            ("@whi@Transaction menus: ", .checkbox(\.transactionMenus), 0),
            ("@whi@Offer-X: ", .checkbox(\.offerX), 0),
            ("@whi@Last Offer-X: ", .checkbox(\.lastOfferX), 0),
        ], [
            ("@whi@Hold to buy/sell in shop: ", .checkbox(\.holdToBuy), 0),
            ("@whi@Vertical drag (touch): ", .int(\.touchVerticalDrag), 4),
            ("@whi@Horizontal pinch (touch): ", .int(\.touchPinch), 4),
            ("@whi@Menu delay (touch): ", .int(\.touchMenuDelay), 4),
        ]])

        panelUIOptions = makePanel(50)
        var ui2: [(String, OptionBinding, Int)] = [("@whi@Wilderness warning: ", .checkbox(\.wildernessWarning), 0)]
        if o.versionMedia >= 59 { ui2.append(("@whi@Certificate items: ", .checkbox(\.certificateItems), 0)) }
        ui2 += [
            ("@whi@Status bars: ", .checkbox(\.statusBars), 0),
            ("@whi@Ground item highlight: ", .checkbox(\.groundItemText), 0),
            ("@whi@Hover tooltip: ", .checkbox(\.showHoverTooltip), 0),
        ]
        if o.versionMedia > 42 { ui2.append(("@whi@Wiki lookup: ", .checkbox(\.wikiLookup), 0)) }
        ui2 += [
            ("@whi@Style outside combat: ", .checkbox(\.combatStyleAlways), 0),
            ("@whi@Text effect FPS: ", .int(\.ranTargetFps), 4),
            ("@whi@Keyboard on right: ", .checkbox(\.touchKeyboardRight), 0),
        ]
        uiOptions = build(panelUIOptions, [[
            ("@whi@Display FPS: ", .checkbox(\.displayFps), 0),
            ("@whi@UI Scale: ", .checkbox(\.uiScale), 0),
            ("@whi@Anti-alias: ", .checkbox(\.antiAlias), 0),
            ("@whi@Number commas: ", .checkbox(\.numberCommas), 0),
            ("@whi@Remaining XP: ", .checkbox(\.remainingExperience), 0),
            ("@whi@Total XP: ", .checkbox(\.totalExperience), 0),
            ("@whi@XP drops: ", .checkbox(\.experienceDrops), 0),
            ("@whi@Inventory count: ", .checkbox(\.inventoryCount), 0),
            ("@whi@K/M amounts: ", .checkbox(\.condenseItemAmounts), 0),
        ], ui2])

        panelBankOptions = makePanel(50)
        bankOptions = build(panelBankOptions, [[
            ("@whi@Always multi-withdraw: ", .checkbox(\.bankUnstackbleWithdraw), 0),
            ("@whi@Search items: ", .checkbox(\.bankSearch), 0),
            ("@whi@Show capacity: ", .checkbox(\.bankCapacity), 0),
            ("@whi@Show total value: ", .checkbox(\.bankValue), 0),
            ("@whi@Bank expand: ", .checkbox(\.bankExpand), 0),
            ("@whi@Bank scrollbar: ", .checkbox(\.bankScroll), 0),
            ("@whi@Bank menus: ", .checkbox(\.bankMenus), 0),
            ("@whi@Show inventory: ", .checkbox(\.bankInventory), 0),
        ], [
            ("@whi@Maintain slot: ", .checkbox(\.bankMaintainSlot), 0),
        ]])
    }

    var activeOptionPanel: Panel? {
        switch optionsTab {
        case 0: return panelGameOptions
        case 1: return panelControlOptions
        case 2: return panelUIOptions
        case 3: return panelBankOptions
        default: return nil
        }
    }

    var activeOptions: [OptionBinding?]? {
        switch optionsTab {
        case 0: return gameOptions
        case 1: return controlOptions
        case 2: return uiOptions
        case 3: return bankOptions
        default: return nil
        }
    }

    private func syncOptionsPanel(_ panel: Panel, _ bindings: [OptionBinding?]) {
        for i in 0..<panel.controlCount {
            switch bindings[i] {
            case .checkbox(let p)?: panel.toggleCheckbox(i, activated: options[keyPath: p] != 0)
            case .int(let p)?: panel.updateText(i, String(options[keyPath: p]))
            case .string(let p)?: panel.updateText(i, options[keyPath: p])
            case nil: break
            }
        }
    }

    public func syncOptionsPanels() {
        syncOptionsPanel(panelGameOptions, gameOptions)
        syncOptionsPanel(panelControlOptions, controlOptions)
        syncOptionsPanel(panelUIOptions, uiOptions)
        syncOptionsPanel(panelBankOptions, bankOptions)
    }

    public func drawAdditionalOptions() {
        surface.drawStringShadow = true
        let w = Mudclient.additionalOptionsWidth, h = Mudclient.additionalOptionsHeight
        let uiX = surface.width / 2 - w / 2
        let uiY = surface.height / 2 - h / 2
        surface.drawBox(x: uiX, y: uiY, width: w, height: 12, colour: Colour.titleBar)
        surface.drawString("Additional options", x: uiX + 1, y: uiY + 10, font: .bold12, colour: Colour.white)
        surface.drawBoxAlpha(x: uiX, y: uiY + 12, width: w, height: h - 12, colour: Colour.grey98, alpha: 224)
        var colour = Colour.white
        if mouseX > uiX + w - 88 && mouseY >= uiY && mouseX < uiX + w && mouseY < uiY + 12 { colour = Colour.red }
        surface.drawStringRight("Close window", x: uiX + w - 2, y: uiY + 10, font: .bold12, colour: colour)
        surface.drawTabs(x: uiX, y: uiY + 12, width: w, height: Mudclient.additionalOptionsTabHeight,
                         tabs: Mudclient.optionTabs, selected: optionsTab)
        surface.drawLineHorizontal(x: uiX + 8, y: uiY + h - 20, width: w - 16, colour: Colour.black)
        var defaultColour = "whi", vanillaColour = "whi"
        if mouseY > uiY + h - 20 && mouseY < uiY + h {
            if mouseX >= uiX + 58 && mouseX <= uiX + 100 {
                defaultColour = "red"
            } else if mouseX >= uiX + 102 && mouseX <= uiX + 140 {
                vanillaColour = "red"
            }
        }
        surface.drawString("Reset to: @\(defaultColour)@default @whi@/ @\(vanillaColour)@vanilla", x: uiX + 4,
                           y: uiY + h - 5, font: .bold12, colour: Colour.white)
        colour = Colour.white
        if mouseX > uiX + w - 90 && mouseY >= uiY + h - 12 && mouseX < uiX + w && mouseY < uiY + h { colour = Colour.red }
        surface.drawString("Save and close", x: uiX + w - 90, y: uiY + h - 5, font: .bold12, colour: colour)
        activeOptionPanel?.drawPanel()
        surface.drawStringShadow = loggedIn
    }

    public func handleAdditionalOptionsInput() {
        let w = Mudclient.additionalOptionsWidth, h = Mudclient.additionalOptionsHeight
        let uiX = surface.width / 2 - w / 2
        let uiY = surface.height / 2 - h / 2
        if lastMouseButtonDown == 1 && mouseX >= uiX && mouseX < uiX + w && mouseY >= uiY + 12 &&
            mouseY <= uiY + 12 + Mudclient.additionalOptionsTabHeight {
            optionsTab = (mouseX - uiX) / (w / 4)
        }
        let panel = activeOptionPanel
        panel?.handleMouse(x: mouseX, y: mouseY, lastButton: lastMouseButtonDown, isDown: mouseButtonDown,
                           scrollDelta: mouseScrollDelta)
        if lastMouseButtonDown == 1 {
            if mouseX > uiX + w - 88 && mouseY >= uiY && mouseX < uiX + w && mouseY < uiY + 12 {
                showAdditionalOptions = false
            }
            if mouseX > uiX + w - 90 && mouseY >= uiY + h - 12 && mouseX < uiX + w && mouseY < uiY + h {
                options.save()
                showAdditionalOptions = false
            }
            if mouseY > uiY + h - 20 && mouseY < uiY + h {
                confirmTextTop = "Are you sure you wish to reset the"
                if mouseX >= uiX + 58 && mouseX <= uiX + 100 {
                    confirmTextBottom = "options to defaults?"
                    confirmType = .optionsDefault
                    showDialogConfirm = true
                } else if mouseX >= uiX + 102 && mouseX <= uiX + 140 {
                    confirmTextBottom = "options to vanilla?"
                    confirmType = .optionsVanilla
                    showDialogConfirm = true
                }
            }
            if let panel, let bindings = activeOptions {
                for i in 0..<panel.controlCount {
                    switch bindings[i] {
                    case .checkbox(let p)?: options[keyPath: p] = panel.isActivated(i) ? 1 : 0
                    case .int(let p)?: options[keyPath: p] = Int(atoi(panel.text(i)))
                    case .string(let p)?: options[keyPath: p] = panel.text(i)
                    case nil: break
                    }
                }
            }
        }
        lastMouseButtonDown = 0
    }

    // MARK: - ui/confirm.c

    public func drawConfirm() {
        let w = Mudclient.confirmDialogWidth, h = Mudclient.confirmDialogHeight, b = Mudclient.confirmButtonSize
        let dx = surface.width / 2 - w / 2
        let dy = surface.height / 2 - h / 2
        surface.drawBox(x: dx, y: dy, width: w, height: h, colour: Colour.black)
        surface.drawBorder(x: dx, y: dy, width: w, height: h, colour: Colour.white)
        let x = surface.width / 2
        var y = dy + 20
        surface.drawStringCentre(confirmTextTop, x: x, y: y, font: .bold14, colour: Colour.white)
        y += 20
        surface.drawStringCentre(confirmTextBottom, x: x, y: y, font: .bold14, colour: Colour.white)
        let cancelX = dx + (w / 2 - b)
        let okX = cancelX + b * 2
        let buttonY = dy + h - 15
        func over(_ bx: Int) -> Bool {
            mouseX >= bx - b / 2 && mouseX <= bx + b / 2 && mouseY >= buttonY - b / 2 && mouseY <= buttonY + b / 2
        }
        surface.drawStringCentre("Cancel", x: cancelX, y: buttonY, font: .bold12,
                                 colour: over(cancelX) ? Colour.yellow : Colour.white)
        surface.drawStringCentre("OK", x: okX, y: buttonY, font: .bold12, colour: over(okX) ? Colour.yellow : Colour.white)
    }

    public func handleConfirmInput() {
        if lastMouseButtonDown == 0 { return }
        let w = Mudclient.confirmDialogWidth, h = Mudclient.confirmDialogHeight, b = Mudclient.confirmButtonSize
        let dx = surface.width / 2 - w / 2
        let dy = surface.height / 2 - h / 2
        let cancelX = dx + (w / 2 - b)
        let okX = cancelX + b * 2
        let buttonY = dy + h - 15
        func over(_ bx: Int) -> Bool {
            mouseX >= bx - b / 2 && mouseX <= bx + b / 2 && mouseY >= buttonY - b / 2 && mouseY <= buttonY + b / 2
        }
        if mouseX < dx || mouseX > dx + w || mouseY < dy || mouseY > dy + h || over(cancelX) {
            showDialogConfirm = false
        } else if over(okX) {
            switch confirmType {
            case .tutorial: sendCommandString("skiptutorial")
            case .optionsDefault:
                options.setDefaults()
                syncOptionsPanels()
            case .optionsVanilla:
                options.setVanilla()
                syncOptionsPanels()
            case .none: break
            }
            showDialogConfirm = false
        }
        lastMouseButtonDown = 0
    }
}
