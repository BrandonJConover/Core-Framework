// Classic UI controls (text, inputs, lists, buttons, checkboxes): port of rsc-c's panel.c.

import Foundation

public enum PanelControlType: Int {
    case text = 0, centreText = 1, box = 2, textList = 4, listInput = 5, textInput = 6
    case textListInteractive = 9, button = 10, roundedBox = 11, sprite = 12, checkbox = 14
}

/// What a Panel needs from the game client (mudclient in C).
public protocol PanelHost: AnyObject {
    var isTouch: Bool { get }
    var offHandleScrollDrag: Bool { get }
    /// Opens the on-screen keyboard for a focused text input (touch only).
    func triggerKeyboard(text: String, isPassword: Bool, x: Int, y: Int, width: Int, height: Int,
                         font: FontStyle, isCentred: Bool)
}

public final class Panel {
    public static let maxTextLength = 255
    public static let roundedBoxOutColour: Int32 = 0x758eab
    public static let roundedBoxMiddleColour: Int32 = 0x627a9e
    public static let roundedBoxInColour: Int32 = 0x566488
    public static let boxTopColour: Int32 = 0x545d78
    public static let boxBottomColour: Int32 = 0x8792b3
    public static let boxTopLineColour: Int32 = 0x617097
    public static let boxBottomLineColour: Int32 = 0x586688

    /// panel_base_sprite_start: the corner sprites for rounded boxes (sprite_util in the client).
    public static var baseSpriteStart = 0
    public static var textListEntryHeightMod = 0

    public let surface: Surface
    public weak var host: PanelHost?
    /// rsc-c turns the touch list layout off for the quest and message-tab panels.
    public var forceDesktopLists = false

    public let maxControls: Int
    public private(set) var controlCount = 0
    public var controlShown: [Bool]
    var controlListScrollbarHandleDragged: [Bool]
    public var controlMaskText: [Bool]
    public var controlClicked: [Bool]
    public var controlListPosition: [Int]
    public var controlListEntryCount: [Int]
    public var controlActivated: [Int]
    public var controlListEntryMouseOver: [Int]
    public var controlUseAlternativeColour: [Bool]
    public var controlX: [Int]
    public var controlY: [Int]
    public var controlType: [PanelControlType]
    public var controlWidth: [Int]
    public var controlHeight: [Int]
    public var controlInputMaxLength: [Int]
    /// Font style, or the sprite id for sprite controls.
    public var controlFontStyle: [Int]
    public var controlText: [[UInt8]]
    public var controlListEntries: [[[UInt8]]]

    public var mouseX = 0
    public var mouseY = 0
    public var mouseLastButtonDown = 0
    public var mouseButtonDown = 0
    public var mouseMetaButtonHeld = 0
    public var mouseScrollDelta = 0
    public var focusControlIndex = -1
    public var offsetX = 0
    public var offsetY = 0

    public init(surface: Surface, max: Int) {
        self.surface = surface
        maxControls = max
        controlShown = Array(repeating: false, count: max)
        controlListScrollbarHandleDragged = Array(repeating: false, count: max)
        controlMaskText = Array(repeating: false, count: max)
        controlClicked = Array(repeating: false, count: max)
        controlUseAlternativeColour = Array(repeating: false, count: max)
        controlListPosition = Array(repeating: 0, count: max)
        controlListEntryCount = Array(repeating: 0, count: max)
        controlActivated = Array(repeating: 0, count: max)
        controlListEntryMouseOver = Array(repeating: 0, count: max)
        controlX = Array(repeating: 0, count: max)
        controlY = Array(repeating: 0, count: max)
        controlType = Array(repeating: .text, count: max)
        controlWidth = Array(repeating: 0, count: max)
        controlHeight = Array(repeating: 0, count: max)
        controlInputMaxLength = Array(repeating: 0, count: max)
        controlFontStyle = Array(repeating: 0, count: max)
        controlText = Array(repeating: [], count: max)
        controlListEntries = Array(repeating: [], count: max)
    }

    var isTouch: Bool { host?.isTouch ?? true }

    static func clip(_ text: [UInt8]) -> [UInt8] {
        let bytes = text.prefix { $0 != 0 }
        return Array(bytes.prefix(maxTextLength - 1))
    }

    // MARK: - Input

    public func handleMouse(x: Int, y: Int, lastButton: Int, isDown: Int, scrollDelta: Int) {
        mouseX = x
        mouseY = y
        mouseButtonDown = isDown
        mouseScrollDelta = scrollDelta
        if lastButton != 0 { mouseLastButtonDown = lastButton }

        if lastButton == 1 {
            for i in 0..<controlCount {
                let type = controlType[i]
                if controlShown[i] && (type == .button || type == .checkbox) &&
                    mouseX >= controlX[i] + offsetX && mouseY >= controlY[i] + offsetY &&
                    mouseX <= controlX[i] + offsetX + controlWidth[i] &&
                    mouseY <= controlY[i] + offsetY + controlHeight[i] {
                    if type == .button {
                        controlClicked[i] = true
                    } else {
                        controlActivated[i] = 1 - controlActivated[i]
                    }
                }
            }
        }

        if isDown == 1 {
            mouseMetaButtonHeld += 1
        } else {
            mouseMetaButtonHeld = 0
        }
    }

    public func isClicked(_ control: Int) -> Bool {
        if controlShown[control] && controlClicked[control] {
            controlClicked[control] = false
            return true
        }
        return false
    }

    public func keyPress(_ key: Int) {
        if key == 0 { return }
        let f = focusControlIndex
        guard f != -1 && controlShown[f] else { return }
        var length = controlText[f].count

        if key == 8 && length > 0 {
            controlText[f].removeLast()
            length -= 1
        }
        if (key == 10 || key == 13) && length > 0 {
            controlClicked[f] = true
        }
        if length < controlInputMaxLength[f], key >= 0, key < 256, Tables.charSet.contains(UInt8(key)) {
            controlText[f].append(UInt8(key))
        }
        if key == 9 {
            repeat {
                focusControlIndex = (focusControlIndex + 1) % controlCount
            } while controlType[focusControlIndex] != .listInput && controlType[focusControlIndex] != .textInput
        }
    }

    // MARK: - Drawing

    public func drawPanel() {
        for i in 0..<controlCount where controlShown[i] {
            let x = controlX[i] + offsetX
            let y = controlY[i] + offsetY
            let font = FontStyle(rawValue: controlFontStyle[i]) ?? .regular11
            switch controlType[i] {
            case .text:
                drawText(i, x: x, y: y, text: controlText[i], font: font)
            case .centreText:
                drawText(i, x: controlX[i] - surface.textWidth(bytes: controlText[i], font: font) / 2 + offsetX,
                         y: y, text: controlText[i], font: font)
            case .box:
                drawBox(x: x, y: y, width: controlWidth[i], height: controlHeight[i])
            case .textList, .textListInteractive:
                drawTextList(i, x: x, y: y, width: controlWidth[i], height: controlHeight[i], font: font,
                             entryCount: controlListEntryCount[i], position: controlListPosition[i],
                             interactive: controlType[i] == .textListInteractive)
            case .listInput, .textInput:
                drawTextInput(i, x: x, y: y, width: controlWidth[i], height: controlHeight[i],
                              text: controlText[i], font: font)
            case .roundedBox:
                drawRoundedBox(x: x, y: y, width: controlWidth[i], height: controlHeight[i])
            case .sprite:
                surface.drawSprite(x: x, y: y, id: controlFontStyle[i])
            case .checkbox:
                drawCheckbox(i, x: x, y: y, width: controlWidth[i], height: controlHeight[i])
            case .button:
                break
            }
        }
        mouseLastButtonDown = 0
    }

    func drawCheckbox(_ control: Int, x: Int, y: Int, width: Int, height: Int) {
        surface.drawBox(x: x, y: y, width: width, height: height, colour: Colour.white)
        surface.drawLineHorizontal(x: x, y: y, width: width, colour: Panel.boxBottomColour)
        surface.drawLineVertical(x: x, y: y, height: height, colour: Panel.boxBottomColour)
        surface.drawLineHorizontal(x: x, y: y + height - 1, width: width, colour: Panel.boxTopColour)
        surface.drawLineVertical(x: x + width - 1, y: y, height: height, colour: Panel.boxTopColour)
        if controlActivated[control] == 1 {
            for i in 0..<max(height, 0) {
                surface.drawLineHorizontal(x: x + i, y: y + i, width: 1, colour: Colour.black)
                surface.drawLineHorizontal(x: x + width - 1 - i, y: y + i, width: 1, colour: Colour.black)
            }
        }
    }

    func drawText(_ control: Int, x: Int, y: Int, text: [UInt8], font: FontStyle) {
        drawString(control, x: x, y: y + Surface.textHeight(font) / 3, text: text, font: font)
    }

    func drawString(_ control: Int, x: Int, y: Int, text: [UInt8], font: FontStyle) {
        let colour = controlUseAlternativeColour[control] ? Colour.white : 0
        surface.drawString(bytes: text, x: x, y: y, font: font, colour: colour)
    }

    func drawTextInput(_ control: Int, x: Int, y: Int, width: Int, height: Int, text: [UInt8], font: FontStyle) {
        var x = x
        var display = controlMaskText[control] ? [UInt8](repeating: UInt8(ascii: "X"), count: text.count) : text

        if controlType[control] == .listInput {
            if mouseLastButtonDown == 1 && mouseX >= x && mouseY >= y - height / 2 &&
                mouseX <= x + width && mouseY <= y + height / 2 {
                focusControlIndex = control
            }
        } else if controlType[control] == .textInput {
            let centred = !controlUseAlternativeColour[control]
            let minX = centred ? x - width / 2 : x
            let maxX = centred ? x + width / 2 : x + width
            if mouseLastButtonDown == 1 && mouseX >= minX && mouseY >= y - height / 2 &&
                mouseX <= maxX && mouseY <= y + height / 2 {
                setFocus(control)
            }
            if centred {
                x -= surface.textWidth(bytes: display, font: font) / 2
            }
        }

        if focusControlIndex == control { display.append(UInt8(ascii: "*")) }
        drawString(control, x: x, y: y + Surface.textHeight(font) / 3, text: display, font: font)
    }

    public func drawBox(x: Int, y: Int, width: Int, height: Int) {
        let s = surface
        s.drawGradient(x: x, y: y, width: width, height: height, topColour: Panel.boxTopColour, bottomColour: Panel.boxBottomColour)
        s.drawLineHorizontal(x: x, y: y, width: width, colour: Panel.boxBottomColour)
        s.drawLineHorizontal(x: x + 1, y: y + 1, width: width - 2, colour: Panel.boxBottomColour)
        s.drawLineHorizontal(x: x + 2, y: y + 2, width: width - 4, colour: Panel.boxTopLineColour)
        s.drawLineVertical(x: x, y: y, height: height, colour: Panel.boxBottomColour)
        s.drawLineVertical(x: x + 1, y: y + 1, height: height - 2, colour: Panel.boxBottomColour)
        s.drawLineVertical(x: x + 2, y: y + 2, height: height - 4, colour: Panel.boxTopLineColour)
        s.drawLineHorizontal(x: x, y: y + height - 1, width: width, colour: Panel.boxTopColour)
        s.drawLineHorizontal(x: x + 1, y: y + height - 2, width: width - 2, colour: Panel.boxTopColour)
        s.drawLineHorizontal(x: x + 2, y: y + height - 3, width: width - 4, colour: Panel.boxBottomLineColour)
        s.drawLineVertical(x: x + width - 1, y: y, height: height, colour: Panel.boxTopColour)
        s.drawLineVertical(x: x + width - 2, y: y + 1, height: height - 2, colour: Panel.boxTopColour)
        s.drawLineVertical(x: x + width - 3, y: y + 2, height: height - 4, colour: Panel.boxBottomLineColour)
    }

    public func drawRoundedBox(x: Int, y: Int, width: Int, height: Int) {
        let s = surface
        s.drawBox(x: x, y: y, width: width, height: height, colour: 0)
        s.drawBorder(x: x, y: y, width: width, height: height, colour: Panel.roundedBoxOutColour)
        s.drawBorder(x: x + 1, y: y + 1, width: width - 2, height: height - 2, colour: Panel.roundedBoxMiddleColour)
        s.drawBorder(x: x + 2, y: y + 2, width: width - 4, height: height - 4, colour: Panel.roundedBoxInColour)
        s.drawSprite(x: x, y: y, id: 2 + Panel.baseSpriteStart)
        s.drawSprite(x: x + width - 7, y: y, id: 3 + Panel.baseSpriteStart)
        s.drawSprite(x: x, y: y + height - 7, id: 4 + Panel.baseSpriteStart)
        s.drawSprite(x: x + width - 7, y: y + height - 7, id: 5 + Panel.baseSpriteStart)
    }

    func drawTextList(_ control: Int, x: Int, y: Int, width: Int, height: Int, font: FontStyle,
                      entryCount: Int, position: Int, interactive: Bool) {
        let touch = forceDesktopLists ? false : isTouch
        let entryHeight = Surface.textHeight(font) + (touch ? 6 : 0)
        let displayed = height / entryHeight
        let maxEntries = entryCount - displayed
        var position = position
        if position > maxEntries {
            position = maxEntries
        } else if position < 0 {
            position = 0
        }
        controlListPosition[control] = position

        if displayed < entryCount {
            let cornerTopRight = x + width - 12
            var scrubHeight = ((height - 27) * displayed) / entryCount
            if scrubHeight < 6 { scrubHeight = 6 }

            if !touch && mouseScrollDelta != 0 && mouseX > x && mouseX < x + width && mouseY > y && mouseY < y + height {
                position += mouseScrollDelta
                position = min(max(position, 0), maxEntries)
                controlListPosition[control] = position
            }

            if mouseButtonDown == 1 && mouseX >= cornerTopRight && mouseX <= cornerTopRight + 12 {
                if mouseY > y && mouseY < y + 12 && position > 0 { position -= 1 }
                if mouseY > y + height - 12 && mouseY < y + height && position < maxEntries { position += 1 }
                controlListPosition[control] = position
            }

            if mouseButtonDown == 1 {
                let withinX = mouseX >= cornerTopRight && mouseX <= cornerTopRight + 12
                var dragging = controlListScrollbarHandleDragged[control]
                if !(host?.offHandleScrollDrag ?? false) {
                    dragging = dragging && mouseX >= cornerTopRight - 12 && mouseX <= cornerTopRight + 24
                }
                let withinY = mouseY > y + 12 && mouseY < y + height - 12
                if (withinX || dragging) && withinY {
                    controlListScrollbarHandleDragged[control] = true
                    let l3 = mouseY - y - 12 - scrubHeight / 2
                    position = (l3 * entryCount) / (height - 24)
                    if position < 0 {
                        position = 0
                    } else if position > maxEntries {
                        position = maxEntries
                    }
                    controlListPosition[control] = position
                }
            } else {
                controlListScrollbarHandleDragged[control] = false
            }

            let scrubY = ((height - 27 - scrubHeight) * position) / maxEntries
            surface.drawScrollbar(x: x, y: y, width: width, height: height, scrubY: scrubY, scrubHeight: scrubHeight)
        } else {
            position = 0
            controlListPosition[control] = 0
        }

        if interactive { controlListEntryMouseOver[control] = -1 }

        let listStartY = height - displayed * entryHeight
        var listY = y + ((Surface.textHeight(font) * 5) / 6 + listStartY / 2) + (touch ? 3 : 0)
        let entries = controlListEntries[control]

        var i = position
        while i < entryCount {
            let entry = i < entries.count ? entries[i] : []
            if interactive {
                var colour = controlUseAlternativeColour[control] ? Colour.white : Colour.black
                if mouseX >= x + 2 && mouseX <= x + width - 12 && mouseY - 2 <= listY &&
                    mouseY - 2 > listY - Surface.textHeight(font) {
                    colour = controlUseAlternativeColour[control] ? Colour.grey80 : Colour.white
                    controlListEntryMouseOver[control] = i
                    if mouseLastButtonDown == 1 {
                        controlActivated[control] = i
                        controlClicked[control] = true
                    }
                }
                if controlActivated[control] == i { colour = Colour.red }
                surface.drawString(bytes: entry, x: x + 2, y: listY, font: font, colour: colour)
                listY += entryHeight
            } else {
                drawString(control, x: x + 2, y: listY, text: entry, font: font)
                listY += Surface.textHeight(font) - Panel.textListEntryHeightMod
            }
            if listY >= y + height { return }
            i += 1
        }
    }

    // MARK: - Building

    private func prepare(_ type: PanelControlType, x: Int, y: Int) -> Int {
        controlType[controlCount] = type
        controlShown[controlCount] = true
        controlX[controlCount] = x
        controlY[controlCount] = y
        controlCount += 1
        return controlCount - 1
    }

    @discardableResult
    public func addText(x: Int, y: Int, text: String, font: FontStyle, alternativeColour: Bool) -> Int {
        controlFontStyle[controlCount] = font.rawValue
        controlUseAlternativeColour[controlCount] = alternativeColour
        controlText[controlCount] = Panel.clip(Surface.bytes(text))
        return prepare(.text, x: x, y: y)
    }

    @discardableResult
    public func addTextCentre(x: Int, y: Int, text: String, font: FontStyle, alternativeColour: Bool) -> Int {
        controlFontStyle[controlCount] = font.rawValue
        controlUseAlternativeColour[controlCount] = alternativeColour
        controlText[controlCount] = Panel.clip(Surface.bytes(text))
        return prepare(.centreText, x: x, y: y)
    }

    @discardableResult
    public func addBoxRounded(x: Int, y: Int, width: Int, height: Int) -> Int {
        controlWidth[controlCount] = width
        controlHeight[controlCount] = height
        return prepare(.roundedBox, x: x - width / 2, y: y - height / 2)
    }

    @discardableResult
    public func addSprite(x: Int, y: Int, spriteId: Int) -> Int {
        let w = surface.spriteWidth[spriteId], h = surface.spriteHeight[spriteId]
        controlWidth[controlCount] = w
        controlHeight[controlCount] = h
        controlFontStyle[controlCount] = spriteId
        return prepare(.sprite, x: x - w / 2, y: y - h / 2)
    }

    @discardableResult
    public func addTextList(x: Int, y: Int, width: Int, height: Int, font: FontStyle, maxEntries: Int,
                            alternativeColour: Bool) -> Int {
        controlWidth[controlCount] = width
        controlHeight[controlCount] = height
        controlUseAlternativeColour[controlCount] = alternativeColour
        controlFontStyle[controlCount] = font.rawValue
        controlInputMaxLength[controlCount] = maxEntries
        controlListEntries[controlCount] = Array(repeating: [], count: maxEntries)
        return prepare(.textList, x: x, y: y)
    }

    @discardableResult
    public func addTextListInput(x: Int, y: Int, width: Int, height: Int, font: FontStyle, maxLength: Int,
                                 isPassword: Bool, alternativeColour: Bool) -> Int {
        controlMaskText[controlCount] = isPassword
        controlFontStyle[controlCount] = font.rawValue
        controlUseAlternativeColour[controlCount] = alternativeColour
        controlWidth[controlCount] = width
        controlHeight[controlCount] = height
        controlInputMaxLength[controlCount] = maxLength
        return prepare(.listInput, x: x, y: y)
    }

    @discardableResult
    public func addTextInput(x: Int, y: Int, width: Int, height: Int, font: FontStyle, maxLength: Int,
                             isPassword: Bool, alternativeColour: Bool) -> Int {
        controlMaskText[controlCount] = isPassword
        controlFontStyle[controlCount] = font.rawValue
        controlUseAlternativeColour[controlCount] = alternativeColour
        controlWidth[controlCount] = width
        controlHeight[controlCount] = height
        controlInputMaxLength[controlCount] = maxLength
        return prepare(.textInput, x: x, y: y)
    }

    @discardableResult
    public func addTextListInteractive(x: Int, y: Int, width: Int, height: Int, font: FontStyle, maxLength: Int,
                                       alternativeColour: Bool) -> Int {
        controlShown[controlCount] = true
        controlFontStyle[controlCount] = font.rawValue
        controlUseAlternativeColour[controlCount] = alternativeColour
        controlWidth[controlCount] = width
        controlHeight[controlCount] = height
        controlInputMaxLength[controlCount] = maxLength
        controlListEntries[controlCount] = Array(repeating: [], count: maxLength + 1)
        controlActivated[controlCount] = -1
        controlListEntryMouseOver[controlCount] = -1
        return prepare(.textListInteractive, x: x, y: y)
    }

    @discardableResult
    public func addButtonBackground(x: Int, y: Int, width: Int, height: Int) -> Int {
        controlWidth[controlCount] = width
        controlHeight[controlCount] = height
        return prepare(.box, x: x - width / 2, y: y - height / 2)
    }

    @discardableResult
    public func addButton(x: Int, y: Int, width: Int, height: Int) -> Int {
        controlWidth[controlCount] = width
        controlHeight[controlCount] = height
        return prepare(.button, x: x - width / 2, y: y - height / 2)
    }

    @discardableResult
    public func addCheckbox(x: Int, y: Int, width: Int, height: Int) -> Int {
        controlWidth[controlCount] = width
        controlHeight[controlCount] = height
        return prepare(.checkbox, x: x, y: y)
    }

    // MARK: - State

    public func toggleCheckbox(_ control: Int, activated: Bool) { controlActivated[control] = activated ? 1 : 0 }
    public func isActivated(_ control: Int) -> Bool { controlActivated[control] != 0 }
    public func clearList(_ control: Int) { controlListEntryCount[control] = 0 }

    public func resetList(_ control: Int) {
        controlListPosition[control] = 0
        controlListEntryMouseOver[control] = -1
    }

    public func addListEntry(_ control: Int, index: Int, text: String) {
        let bytes = Surface.bytes(text)
        controlListEntries[control][index] = controlType[control] == .textListInteractive ? Panel.clip(bytes) : bytes
        if index + 1 > controlListEntryCount[control] { controlListEntryCount[control] = index + 1 }
    }

    public func addListEntryWrapped(_ control: Int, text: String, flash: Bool) {
        var index = controlListEntryCount[control]
        controlListEntryCount[control] += 1
        if index >= controlInputMaxLength[control] {
            index -= 1
            controlListEntryCount[control] -= 1
            for i in 0..<max(index, 0) {
                controlListEntries[control][i] = controlListEntries[control][i + 1]
            }
        }
        let bytes = Surface.bytes(text)
        controlListEntries[control][index] = controlType[control] == .textList ? Panel.clip(bytes) : bytes
        if flash { controlListPosition[control] = 999_999 }
    }

    public func updateText(_ control: Int, _ text: String) { controlText[control] = Panel.clip(Surface.bytes(text)) }
    public func text(_ control: Int) -> String { String(decoding: controlText[control], as: Latin1.self) }
    public func show(_ control: Int) { controlShown[control] = true }
    public func hide(_ control: Int) { controlShown[control] = false }
    public func listEntryIndex(_ control: Int) -> Int { controlListEntryMouseOver[control] }

    public func setFocus(_ control: Int) {
        focusControlIndex = control
        guard isTouch, controlType[control] == .textInput else { return }
        let width = controlWidth[control], height = controlHeight[control]
        let centred = !controlUseAlternativeColour[control]
        let x = controlX[control] + offsetX - (centred ? width / 2 : 0)
        let y = controlY[control] + offsetY
        host?.triggerKeyboard(text: text(control), isPassword: controlMaskText[control], x: x, y: y - height / 2,
                              width: width, height: height, font: FontStyle(rawValue: controlFontStyle[control]) ?? .regular11,
                              isCentred: centred)
    }
}
