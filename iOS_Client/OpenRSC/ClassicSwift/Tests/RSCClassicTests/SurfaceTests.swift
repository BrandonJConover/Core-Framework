import XCTest
@testable import RSCClassic

/// Replays tools/surfacedump.c's draw calls and compares each frame (and every
/// loaded sprite) with the C engine's output, hashed with FNV-1a.
/// On a mismatch the Swift frame is written to $TMPDIR/rsc-swift-frames/<step>.raw.
final class SurfaceTests: XCTestCase {
    private var lines: [String] = []

    func testSurfaceMatchesCEngine() throws {
        let golden = String(decoding: try Data(contentsOf: TestPaths.golden.appendingPathComponent("surface.txt")),
                            as: Latin1.self).split(separator: "\n").map(String.init)

        let s = Surface(width: 512, height: 346, limit: SpriteBase.limit)
        let config = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("config85.jag"))
        let gameData = try GameData(config: config, members: true, version: 85)
        try MediaLoader.loadJagex(try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("jagex.jag")), into: s)
        try MediaLoader.loadMedia(try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("media59.jag")),
                                  into: s, gameData: gameData)
        for i in 0..<s.limit where s.spriteWidth[i] != 0 || s.spriteColours[i] != nil || s.spritePixels[i] != nil {
            sprite(s, i)
        }

        let m = SpriteBase.media
        func step(_ name: String) {
            let bytes = s.pixelBuffer.withMemoryRebound(to: UInt8.self) { Array($0) }
            lines.append("step \(name) \(fnv1a(bytes))")
            if let expected = golden.first(where: { $0.hasPrefix("step \(name) ") }), expected != lines.last {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rsc-swift-frames")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? Data(bytes).write(to: dir.appendingPathComponent("\(name).raw"))
            }
        }

        s.blackScreen(); step("black")
        s.drawGradient(x: 10, y: 10, width: 200, height: 100, topColour: 0x7272b0, bottomColour: 0x0e0e3e); step("gradient")
        s.drawBox(x: 50, y: 40, width: 120, height: 60, colour: 0x336699); step("box")
        s.drawBoxAlpha(x: 30, y: 30, width: 200, height: 150, colour: 0xff8000, alpha: 100); step("box_alpha")
        s.drawCircle(x: 256, y: 173, radius: 60, colour: 0x00ff00, alpha: 128); step("circle")
        s.drawLineHorizontal(x: 0, y: 5, width: 512, colour: Colour.red)
        s.drawLineVertical(x: 5, y: 0, height: 346, colour: Colour.yellow)
        s.drawBorder(x: 100, y: 100, width: 300, height: 200, colour: Colour.white)
        s.setPixel(x: 511, y: 345, colour: Colour.cyan); step("lines")
        s.drawSprite(x: 20, y: 200, id: m + 10); s.drawSprite(x: 300, y: 20, id: m + 24)
        s.drawSprite(x: -10, y: -5, id: m + 1); s.drawSprite(x: 480, y: 320, id: m + 25); step("sprites")
        s.drawSpriteAlpha(x: 100, y: 250, id: m + 10, alpha: 128); s.drawSpriteAlpha(x: 200, y: 40, id: m + 24, alpha: 64)
        step("sprite_alpha")
        s.drawSpriteScale(x: 10, y: 10, width: 80, height: 60, id: 2150)
        s.drawSpriteScale(x: 400, y: 250, width: 140, height: 140, id: 2155)
        s.drawEntitySprite(x: 450, y: -10, width: 60, height: 40, id: 2162, tx: 0, ty: 0); step("sprite_scale")
        s.drawSpriteScaleAlpha(x: 150, y: 150, width: 100, height: 80, id: m + 24, alpha: 160); step("sprite_scale_alpha")
        s.drawSpriteScaleMask(x: 250, y: 200, width: 64, height: 48, id: 2170, colour: 0xff0000); step("sprite_scale_mask")
        s.drawMinimapSprite(x: 256, y: 173, id: m + 24, rotation: 37, scale: 128)
        s.drawMinimapSprite(x: 100, y: 100, id: 2153, rotation: 200, scale: 192); step("minimap")
        s.drawSpriteTransformMask(x: 20, y: 20, width: 48, height: 32, id: 2157, maskColour: 0x00ff00, skinColour: 0, skewX: 0, flip: false)
        s.drawSpriteTransformMask(x: 80, y: 20, width: 48, height: 32, id: 2157, maskColour: 0xff0000, skinColour: 0xeeaa88, skewX: 10, flip: true)
        s.drawSpriteTransformMask(x: 150, y: 60, width: 40, height: 40, id: m + 1, maskColour: 0x8080ff, skinColour: 0x33ff33, skewX: -5, flip: true)
        s.drawSpriteTransformMask(x: -20, y: 300, width: 64, height: 64, id: 2159, maskColour: 0, skinColour: 0, skewX: 0, flip: false)
        step("transform")
        for i in 0..<8 {
            s.drawStringShadow = i >= 4
            s.drawString("Hello @red@World ~300~x @yel@123!", x: 5, y: 20 + i * 30, font: FontStyle(rawValue: i)!, colour: Colour.white)
        }
        s.drawStringShadow = false; step("strings")
        s.drawStringCentre("Welcome to RuneScape", x: 256, y: 330, font: .bold14, colour: Colour.white)
        s.drawStringRight("Right @gre@aligned", x: 507, y: 340, font: .bold12, colour: Colour.orange); step("string_align")
        let para = "The quick brown fox jumps over the lazy dog. %Line break here and more words to wrap around"
        s.drawParagraph(para, x: 256, y: 100, font: .bold12, colour: Colour.white, max: 200); step("paragraph")
        lines.append("paragraph_height \(s.paragraphHeight(para, font: .bold12, max: 200, maxHeight: 1000)) \(s.paragraphHeight(para, font: .bold12, max: 200, maxHeight: 20))")
        lines.append("text_width" + (0..<8).map { " \(s.textWidth("Hello @red@World ~300~x", font: FontStyle(rawValue: $0)!))" }.joined())
        s.setBounds(minX: 100, minY: 50, maxX: 400, maxY: 300)
        s.drawBox(x: 0, y: 0, width: 512, height: 346, colour: 0x123456)
        s.drawString("Clipped text that runs off the edge", x: 80, y: 60, font: .bold24, colour: Colour.green)
        s.drawSprite(x: 350, y: 250, id: m + 10); s.drawSprite(x: 90, y: 40, id: m + 24); s.resetBounds(); step("bounds")
        s.drawBlur(blurHeight: 3, x: 50, y: 50, width: 100, height: 60); step("blur")
        s.drawTabs(x: 10, y: 250, width: 300, height: 24, tabs: ["Friends", "Ignore", "Other"], selected: 1); step("tabs")
        s.drawScrollbar(x: 400, y: 40, width: 100, height: 200, scrubY: 30, scrubHeight: 40); step("scrollbar")
        s.drawStatusBar(max: 100, current: 37, label: "Hits", x: 20, y: 300, width: 150, height: 20,
                        backgroundColour: Colour.red, foregroundColour: Colour.green, isPercentage: false)
        s.drawStatusBar(max: 250, current: 123, label: "Prayer points", x: 200, y: 300, width: 60, height: 20,
                        backgroundColour: Colour.red, foregroundColour: Colour.green, isPercentage: true); step("status_bar")
        s.interlace = true
        s.drawBox(x: 0, y: 101, width: 80, height: 40, colour: 0x445566)
        s.drawGradient(x: 300, y: 101, width: 80, height: 41, topColour: Colour.red, bottomColour: Colour.blue)
        s.drawSprite(x: 10, y: 111, id: m + 10); s.drawSpriteAlpha(x: 300, y: 121, id: m + 24, alpha: 100)
        s.drawBoxAlpha(x: 200, y: 201, width: 40, height: 40, colour: Colour.white, alpha: 50)
        s.interlace = false; step("interlace")
        s.screenRasterToSprite(id: 3000, x: 50, y: 50, width: 100, height: 80); s.drawSprite(x: 300, y: 200, id: 3000)
        step("raster_to_sprite")
        s.screenRasterToPaletteSprite(id: 3000); sprite(s, 3000); s.drawSprite(x: 10, y: 10, id: 3000); step("palette_sprite")
        s.drawSpriteReversed(id: 3001, x: 0, y: 0, width: 30, height: 40); sprite(s, 3001)
        s.drawSprite(x: 480, y: 0, id: 3001); step("reversed")
        s.drawSprite(x: 0, y: 0, id: SpriteBase.limit - 1); step("logo")
        s.fadeToBlack(); step("fade")
        s.applyLoginFilter(backgroundHeight: 200); step("login_filter")

        s.blackScreen()
        Panel.baseSpriteStart = SpriteBase.util
        let p = Panel(surface: s, max: 50)
        p.addButtonBackground(x: 256, y: 60, width: 200, height: 40)
        p.addTextCentre(x: 256, y: 52, text: "Existing User", font: .bold14, alternativeColour: false)
        let b = p.addButton(x: 256, y: 60, width: 200, height: 40)
        p.addBoxRounded(x: 256, y: 160, width: 300, height: 100)
        p.addText(x: 120, y: 130, text: "Username:", font: .bold14, alternativeColour: true)
        let u = p.addTextInput(x: 256, y: 150, width: 200, height: 40, font: .bold14, maxLength: 12, isPassword: false, alternativeColour: false)
        let pw = p.addTextInput(x: 256, y: 180, width: 200, height: 40, font: .bold14, maxLength: 20, isPassword: true, alternativeColour: true)
        let cb = p.addCheckbox(x: 420, y: 140, width: 14, height: 14)
        let cb2 = p.addCheckbox(x: 440, y: 140, width: 14, height: 14)
        p.addSprite(x: 60, y: 300, spriteId: m + 24)
        let list = p.addTextList(x: 20, y: 220, width: 200, height: 100, font: .bold12, maxEntries: 40, alternativeColour: true)
        for i in 0..<20 { p.addListEntryWrapped(list, text: "@yel@Line \(i) of the chat", flash: true) }
        let il = p.addTextListInteractive(x: 280, y: 220, width: 200, height: 100, font: .bold12, maxLength: 30, alternativeColour: false)
        for i in 0..<12 { p.addListEntry(il, index: i, text: "Quest number \(i)") }
        p.updateText(u, "Zezima"); p.updateText(pw, "hunter2")
        p.focusControlIndex = u
        p.toggleCheckbox(cb2, activated: true)
        p.handleMouse(x: 300, y: 245, lastButton: 1, isDown: 1, scrollDelta: 0)
        p.handleMouse(x: 427, y: 147, lastButton: 1, isDown: 0, scrollDelta: 0)
        p.handleMouse(x: 256, y: 60, lastButton: 1, isDown: 0, scrollDelta: 0)
        p.drawPanel(); step("panel")
        func flag(_ v: Bool) -> Int { v ? 1 : 0 }
        lines.append("panel \(flag(p.isClicked(b))) \(flag(p.isActivated(cb))) \(flag(p.isActivated(cb2))) \(p.controlListPosition[list]) \(p.controlListEntryMouseOver[il]) \(p.controlActivated[il])")
        for key in [Int(UInt8(ascii: "x")), 8, 8, Int(UInt8(ascii: "!")), 9] { p.keyPress(key) }
        lines.append("panel_keys \(p.text(u)) \(p.focusControlIndex)")

        // The C dump prints sprites in id order before the steps, then the two extra ones inline.
        XCTAssertEqual(lines.count, golden.count)
        var failures = 0
        for (i, (a, e)) in zip(lines, golden).enumerated() where a != e {
            XCTFail("line \(i + 1):\n  swift: \(a)\n  c:     \(e)")
            failures += 1
            if failures > 15 { break }
        }
    }

    private func sprite(_ s: Surface, _ id: Int) {
        let area = s.spriteWidth[id] * s.spriteHeight[id]
        let hc = s.spriteColours[id].map { fnv1a(Array($0.prefix(area))) } ?? 0
        let hp = s.spritePixels[id].map { px in fnv1a(px.prefix(area).flatMap { v -> [UInt8] in
            let u = UInt32(bitPattern: v)
            return [UInt8(u & 0xff), UInt8(u >> 8 & 0xff), UInt8(u >> 16 & 0xff), UInt8(u >> 24)]
        }) } ?? 0
        lines.append("sprite \(id) \(s.spriteWidth[id]) \(s.spriteHeight[id]) \(s.spriteWidthFull[id]) \(s.spriteHeightFull[id]) \(s.spriteTranslateX[id]) \(s.spriteTranslateY[id]) \(s.spriteTranslate[id] ? 1 : 0) \(hc) \(hp)")
    }
}
