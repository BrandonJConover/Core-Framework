// Bitmap fonts, inline colour codes and small UI widgets from rsc-c's surface.c.

import Foundation

extension Surface {
    /// rsc-c strings are C chars; non-ASCII bytes are negative there and draw as glyph 0.
    @inline(__always)
    static func glyphIndex(_ byte: UInt8) -> Int { byte < 128 ? Int(byte) : 0 }

    static func bytes(_ text: String) -> [UInt8] {
        text.unicodeScalars.map { $0.value < 256 ? UInt8($0.value) : UInt8(ascii: "?") }
    }

    public func drawCharacter(offset: Int, x: Int, y: Int, colour: Int32, font: [Int8]) {
        var drawX = x + Int(font[offset + 5])
        var drawY = y - Int(font[offset + 6])
        var w = Int(font[offset + 3])
        var h = Int(font[offset + 4])
        var fontPos = Int(font[offset]) * (128 * 128) + Int(font[offset + 1]) * 128 + Int(font[offset + 2])
        var destPos = drawX + drawY * width
        var destOffset = width - w
        var fontOffset = 0

        if drawY < boundsMinY {
            let clip = boundsMinY - drawY
            h -= clip; drawY = boundsMinY
            fontPos += clip * w
            destPos += clip * width
        }
        if drawY + h >= boundsMaxY { h -= drawY + h - boundsMaxY + 1 }
        if drawX < boundsMinX {
            let clip = boundsMinX - drawX
            w -= clip; drawX = boundsMinX
            fontPos += clip; destPos += clip
            fontOffset += clip; destOffset += clip
        }
        if drawX + w >= boundsMaxX {
            let clip = drawX + w - boundsMaxX + 1
            w -= clip
            fontOffset += clip; destOffset += clip
        }
        guard w > 0 && h > 0 else { return }

        for _ in 0..<h {
            for _ in 0..<w {
                if font[fontPos] != 0 { pixels[destPos] = colour }
                fontPos += 1
                destPos += 1
            }
            destPos += destOffset
            fontPos += fontOffset
        }
    }

    private static func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }

    public func drawString(_ text: String, x: Int, y: Int, font: FontStyle, colour: Int32) {
        drawString(bytes: Surface.bytes(text), x: x, y: y, font: font, colour: colour)
    }

    public func drawString(bytes text: [UInt8], x: Int, y: Int, font: FontStyle, colour: Int32) {
        let fontData = fonts[font.rawValue]
        let n = text.count
        var x = x
        var colour = colour
        var i = 0
        while i < n {
            if text[i] == 0x40 && i + 4 < n && text[i + 4] == 0x40 { // @col@
                let code = String(decoding: text[(i + 1)..<(i + 4)].map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }, as: UTF8.self)
                let c = Colour.fromCode(code, ranTargetFps: host?.ranTargetFps ?? 10)
                if c >= 0 { colour = Int32(c) }
                i += 4
            } else if text[i] == 0x7e && i + 4 < n && text[i + 4] == 0x7e { // ~nnn~
                if Surface.isDigit(text[i + 1]) && Surface.isDigit(text[i + 2]) && Surface.isDigit(text[i + 3]) {
                    x = Int(String(decoding: text[(i + 1)..<(i + 4)], as: UTF8.self)) ?? x
                }
                i += 4
            } else if text[i] == 0x7e && i + 5 < n && text[i + 5] == 0x7e { // ~nnnn~
                if Surface.isDigit(text[i + 1]) && Surface.isDigit(text[i + 2]) && Surface.isDigit(text[i + 3]) && Surface.isDigit(text[i + 4]) {
                    x = Int(String(decoding: text[(i + 1)..<(i + 5)], as: UTF8.self)) ?? x
                }
                i += 5
            } else {
                let offset = Tables.characterWidth[Surface.glyphIndex(text[i])]
                if drawStringShadow && colour != 0 {
                    drawCharacter(offset: offset, x: x + 1, y: y, colour: Colour.black, font: fontData)
                    drawCharacter(offset: offset, x: x, y: y + 1, colour: Colour.black, font: fontData)
                }
                drawCharacter(offset: offset, x: x, y: y, colour: colour, font: fontData)
                x += Int(fontData[offset + 7])
            }
            i += 1
        }
    }

    public func drawStringRight(_ text: String, x: Int, y: Int, font: FontStyle, colour: Int32) {
        drawString(text, x: x - textWidth(text, font: font), y: y, font: font, colour: colour)
    }

    public func drawStringCentre(_ text: String, x: Int, y: Int, font: FontStyle, colour: Int32) {
        drawString(text, x: x - textWidth(text, font: font) / 2, y: y, font: font, colour: colour)
    }

    private func drawStringCentre(bytes text: [UInt8], x: Int, y: Int, font: FontStyle, colour: Int32) {
        drawString(bytes: text, x: x - textWidth(bytes: text, font: font) / 2, y: y, font: font, colour: colour)
    }

    public func paragraphHeight(_ text: String, font: FontStyle, max maxWidth: Int, maxHeight: Int) -> Int {
        let text = Surface.bytes(text)
        let fontData = fonts[font.rawValue]
        let n = text.count
        var y = 0, w = 0, start = 0, end = 0
        var i = 0
        while i < n {
            if text[i] == 0x40 && i + 4 < n && text[i + 4] == 0x40 {
                i += 4
            } else if text[i] == 0x7e && i + 4 < n && text[i + 4] == 0x7e {
                i += 4
            } else {
                w += Int(fontData[Tables.characterWidth[Surface.glyphIndex(text[i])] + 7])
            }
            if i < n && text[i] == 0x20 {
                end = i
            } else if i < n && text[i] == 0x25 { // '%' forces a line break
                end = i
                w = 1000
            }
            if w > maxWidth {
                if end <= start { end = i }
                w = 0
                i = end + 1
                start = i
                y += Surface.textHeight(font)
                if y >= maxHeight { return i }
            }
            i += 1
        }
        return -1
    }

    public func drawParagraph(_ text: String, x: Int, y: Int, font: FontStyle, colour: Int32, max maxWidth: Int) {
        let text = Surface.bytes(text)
        let fontData = fonts[font.rawValue]
        let n = text.count
        var y = y, w = 0, start = 0, end = 0
        var i = 0
        while i < n {
            if text[i] == 0x40 && i + 4 < n && text[i + 4] == 0x40 {
                i += 4
            } else if text[i] == 0x7e && i + 4 < n && text[i + 4] == 0x7e {
                i += 4
            } else {
                w += Int(fontData[Tables.characterWidth[Surface.glyphIndex(text[i])] + 7])
            }
            if i < n && text[i] == 0x20 {
                end = i
            } else if i < n && text[i] == 0x25 {
                end = i
                w = 1000
            }
            if w > maxWidth {
                if end <= start { end = i }
                drawStringCentre(bytes: Array(text[start..<min(end, n)]), x: x, y: y, font: font, colour: colour)
                w = 0
                i = end + 1
                start = i
                y += Surface.textHeight(font)
            }
            i += 1
        }
        if w > 0 && start < n {
            drawStringCentre(bytes: Array(text[start..<n]), x: x, y: y, font: font, colour: colour)
        }
    }

    public static func textHeight(_ font: FontStyle) -> Int {
        switch font {
        case .regular11: return 12
        case .bold12, .regular12: return 14
        case .bold13, .bold14: return 15
        case .bold16: return 19
        case .bold20: return 24
        case .bold24: return 29
        }
    }

    public func textWidth(_ text: String, font: FontStyle) -> Int {
        textWidth(bytes: Surface.bytes(text), font: font)
    }

    public func textWidth(bytes text: [UInt8], font: FontStyle) -> Int {
        let fontData = fonts[font.rawValue]
        let n = text.count
        var total = 0
        var i = 0
        while i < n {
            if text[i] == 0x40 && i + 4 < n && text[i + 4] == 0x40 {
                i += 4
            } else if text[i] == 0x7e && i + 4 < n && text[i + 4] == 0x7e {
                i += 4
            } else {
                total += Int(fontData[Tables.characterWidth[Surface.glyphIndex(text[i])] + 7])
            }
            i += 1
        }
        return total
    }

    // MARK: - Widgets

    public func drawTabs(x: Int, y: Int, width w: Int, height h: Int, tabs: [String], selected: Int) {
        let count = tabs.count
        var tabWidth = Int(Float(w) / Float(count))
        var offsetX = 0
        for i in 0..<count {
            if i == count - 1 { tabWidth += w % count }
            let colour = selected == i ? Colour.greyDC : Colour.greyA0
            drawBoxAlpha(x: x + offsetX, y: y, width: tabWidth, height: h, colour: colour, alpha: 128)
            drawStringCentre(tabs[i], x: x + offsetX + tabWidth / 2, y: y + 16, font: .bold14, colour: Colour.black)
            if i > 0 { drawLineVertical(x: x + offsetX, y: y, height: h, colour: Colour.black) }
            offsetX += tabWidth
        }
        drawLineHorizontal(x: x, y: y + h, width: w, colour: Colour.black)
    }

    public func drawScrollbar(x: Int, y: Int, width w: Int, height h: Int, scrubY: Int, scrubHeight: Int) {
        let x = x + w - 12
        drawBorder(x: x, y: y, width: 12, height: h, colour: 0)
        drawSprite(x: x + 1, y: y + 1, id: spriteUtil)
        drawSprite(x: x + 1, y: y + h - 12, id: spriteUtil + 1)
        drawLineHorizontal(x: x, y: y + 13, width: 12, colour: 0)
        drawLineHorizontal(x: x, y: y + h - 13, width: 12, colour: 0)
        drawGradient(x: x + 1, y: y + 14, width: 11, height: h - 27,
                     topColour: Surface.scrollbarTopColour, bottomColour: Surface.scrollbarBottomColour)
        drawBox(x: x + 3, y: scrubY + y + 14, width: 7, height: scrubHeight, colour: Surface.scrubMiddleColour)
        drawLineVertical(x: x + 2, y: scrubY + y + 14, height: scrubHeight, colour: Surface.scrubLeftColour)
        drawLineVertical(x: x + 2 + 8, y: scrubY + y + 14, height: scrubHeight, colour: Surface.scrubRightColour)
    }

    public func drawStatusBar(max: Int, current: Int, label: String, x: Int, y: Int, width w: Int, height h: Int,
                              backgroundColour: Int32, foregroundColour: Int32, isPercentage: Bool) {
        let currentWidth = current >= max ? w : Int(Float(current) / Float(max) * Float(w))
        drawBoxAlpha(x: x, y: y, width: currentWidth, height: h, colour: foregroundColour, alpha: 128)
        drawBoxAlpha(x: x + currentWidth, y: y, width: w - currentWidth, height: h, colour: backgroundColour, alpha: 128)
        let isTouch = host?.isTouch ?? true // rsc-c's mudclient_is_touch returns 1 on mobile
        if !isTouch { drawBorder(x: x, y: y, width: w, height: h, colour: Colour.black) }

        var status: String
        if isPercentage {
            status = "\(label): " + String(format: "%.2f%%", Double(Float(current) / Float(max) * 100.0))
        } else {
            status = "\(label): \(current) / \(max)"
        }
        if textWidth(status, font: .regular11) > w - 4, let space = status.firstIndex(of: " ") {
            status = String(status[status.index(after: space)...])
        }
        drawStringCentre(status, x: x + w / 2, y: y + h - (isTouch ? 3 : 4), font: .regular11, colour: Colour.white)
    }

    /// Draws an inventory item sprite with its colour mask (surface_draw_item).
    public func drawItem(x: Int, y: Int, slotWidth: Int, slotHeight: Int, item: ItemConfig) {
        drawSpriteTransformMask(x: x, y: y, width: slotWidth - 1, height: slotHeight - 2, id: spriteItem + item.sprite,
                                maskColour: Int32(truncatingIfNeeded: item.mask), skinColour: 0, skewX: 0, flip: false)
    }

    /// Bank and shop grid (surface_draw_item_grid). Items are drawn through the host.
    public func drawItemGrid(x: Int, y: Int, rows: Int, columns: Int, slotWidth: Int, slotHeight: Int,
                             items: [Int], counts: [Int], selected: Int, showInventoryCount: Bool,
                             stackableFlag: (Int) -> Int) {
        let itemsLength = items.count
        let selectedVisible = selected >= 0 && selected <= itemsLength
        let boxWidth = columns * slotWidth
        let boxHeight = rows * slotHeight
        if !selectedVisible {
            drawBoxAlpha(x: x + 1, y: y + 1, width: boxWidth - 1, height: boxHeight - 1, colour: Colour.greyD0, alpha: 160)
        }
        var index = 0
        for row in 0..<rows {
            for column in 0..<columns {
                let slotX = x + column * slotWidth
                let slotY = y + row * slotHeight
                let slotColour = selected == index ? Colour.red : Colour.greyD0
                let offset = showInventoryCount ? 0 : 1
                if selectedVisible {
                    drawBoxAlpha(x: slotX, y: slotY, width: slotWidth, height: slotHeight, colour: slotColour, alpha: 160)
                }
                if index < itemsLength && items[index] != -1 {
                    let itemId = items[index]
                    host?.drawItem(x: slotX + offset, y: slotY + offset, slotWidth: slotWidth, slotHeight: slotHeight, itemId: itemId)
                    let font: FontStyle = slotWidth < Surface.itemGridSlotWidth ? .regular11 : .bold12
                    let amount = host?.formatItemAmount(counts[index]) ?? String(counts[index])
                    if showInventoryCount {
                        drawString(amount, x: slotX + 1, y: slotY + 10, font: font, colour: Colour.green)
                        let held = host?.formatItemAmount(host?.inventoryCount(itemId: itemId) ?? 0) ?? "0"
                        drawStringRight(held, x: slotX + slotWidth - 2, y: slotY + slotHeight - 5, font: font, colour: Colour.cyan)
                    } else if stackableFlag(itemId) == 0 { // same test as C: items[id].stackable == 0
                        drawString(amount, x: slotX + 1 + offset, y: slotY + 10 + offset, font: font, colour: Colour.yellow)
                    }
                }
                index += 1
            }
        }
        drawBorder(x: x, y: y, width: boxWidth + 1, height: boxHeight + 1, colour: Colour.black)
        for row in 1..<max(rows, 1) {
            drawLineHorizontal(x: x, y: y + row * slotHeight, width: boxWidth, colour: Colour.black)
        }
        for column in 1..<max(columns, 1) {
            drawLineVertical(x: x + column * slotWidth, y: y, height: boxHeight, colour: Colour.black)
        }
    }
}
