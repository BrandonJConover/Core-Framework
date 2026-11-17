import Foundation

/// Everything rt4 draws on top of the 3D viewport for actors: overhead prayer and skull icons,
/// overhead chat (with its colour and motion effects), health bars and hit splats. Port of
/// `ScriptRunner.drawOverheads` and the screen projection `ScriptRunner.method1026`
/// (`setOverheadScreenCoordinateOffsets`).
extension WorldView {
	/// The camera of the last rendered frame, for projecting actor positions to the screen.
	struct OverlayCamera {
		var x = 0, y = 0, z = 0, pitch = 0, yaw = 0
		var level = 0
		/// rt4 `Rasteriser.centerX/Y`: the projection centre inside the viewport.
		var centerX = 0, centerY = 0
	}

	/// rt4 `method1026`: projects a point `height` above the ground at (`xFine`, `zFine`) to
	/// viewport coordinates, or nil when it is off the map or behind the camera.
	func project(_ cam: OverlayCamera, xFine: Int, zFine: Int, height: Int, scene: Scene) -> (x: Int, y: Int)? {
		if xFine < 128 || zFine < 128 || xFine > 13056 || zFine > 13056 { return nil }
		let worldY = scene.tileHeight(level: cam.level, xFine: xFine, zFine: zFine) - height
		let dz = zFine - cam.z
		let dy = worldY - cam.y
		let dx = xFine - cam.x
		let sp = MathTables.sin[cam.pitch & 2047], cp = MathTables.cos[cam.pitch & 2047]
		let sy = MathTables.sin[cam.yaw & 2047], cy = MathTables.cos[cam.yaw & 2047]
		let a = (dx * cy + sy * dz) >> 16
		let b = (dz * cy - sy * dx) >> 16
		let c = (cp * dy - b * sp) >> 16
		let d = (b * cp + dy * sp) >> 16
		if d < 50 { return nil }
		return ((a << 9) / d + cam.centerX, (c << 9) / d + cam.centerY)
	}

	/// One overhead chat line queued while walking the actors (rt4 `OverheadChat` arrays).
	struct OverheadLine {
		var halfWidth: Int
		var lineHeight: Int
		var x: Int, y: Int
		var colour: Int, effect: Int, loops: Int
		var message: String
	}

	static let overheadColours: [Int] = [16776960, 16711680, 65280, 65535, 16711935, 16777215]

	/// rt4 `drawOverheads`: draws into `r` inside `rect` (the viewport, in raster coordinates).
	func drawOverlays(into r: inout Raster, rect: (x: Int, y: Int, w: Int, h: Int)) {
		guard let scene = scene, let cam = overlayCamera, selfActor != nil else { return }
		guard let b12 = (try? store.font(named: "b12_full")) ?? nil, let p11 = (try? store.font(named: "p11_full")) ?? nil else { return }
		let marks = ((try? store.sprite(named: "hitmarks")) ?? nil)?.frames ?? []
		let defaultBars = ((try? store.sprite(named: "hitbar_default")) ?? nil)?.frames ?? []
		let prayers = ((try? store.sprite(named: "headicons_prayer")) ?? nil)?.frames ?? []
		let skulls = ((try? store.sprite(named: "headicons_pk")) ?? nil)?.frames ?? []
		let loop = ctx.loop
		let hintIcons = hintArrows.contains(where: { $0 != nil }) ? (((try? store.sprite(named: "hint_headicons")) ?? nil)?.frames ?? []) : []

		// Clip to the viewport (rt4 sets the viewport clip before drawing overheads).
		let savedClip = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		r.setClip(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h)
		defer { r.setClip(savedClip.0, savedClip.1, savedClip.2, savedClip.3) }

		var order: [PathingActor] = []
		if let me = selfActor { order.append(me) }
		order += ctx.players.filter { $0.key != selfIndex }.sorted { $0.key < $1.key }.map(\.value)
		order += ctx.npcs.sorted { $0.key < $1.key }.map(\.value)

		var lines: [OverheadLine] = []
		for a in order where a.isVisible {
			let isNpc = a.kind == .npc
			let type: NpcType? = isNpc ? a.npcType : nil
			/// rt4: npc types may override the icon, bar and splat height.
			let iconHeight = type.flatMap { $0.iconHeight == -1 ? nil : $0.iconHeight }
			func at(_ h: Int) -> (x: Int, y: Int)? { project(cam, xFine: a.xFine, zFine: a.zFine, height: h, scene: scene) }

			// Prayer and skull icons.
			var iconOffset = 30
			if let t = type {
				if t.headIcon >= 0 && t.headIcon < prayers.count, let p = at((iconHeight ?? a.modelHeight) + 15) {
					r.draw(prayers[t.headIcon], x: rect.x + p.x - 12, y: rect.y + p.y - 30)
				}
				// rt4: a hint arrow on this npc blinks above its head (10 of every 20 cycles).
				if loop % 20 < 10, hintArrows.contains(where: { $0?.type == 1 && $0?.target == a.index }), let p = at((iconHeight ?? a.modelHeight) + 15) {
					for h in hintArrows { if let h = h, h.type == 1, h.target == a.index, h.sprite < hintIcons.count { r.draw(hintIcons[h.sprite], x: rect.x + p.x - 12, y: rect.y + p.y - 28) } }
				}
			} else if let ap = a.appearance, ap.skullIcon != -1 || ap.prayerIcon != -1, let p = at(a.modelHeight + 15) {
				if ap.skullIcon >= 0 && ap.skullIcon < skulls.count {
					r.draw(skulls[ap.skullIcon], x: rect.x + p.x - 12, y: rect.y + p.y - iconOffset)
				}
				if ap.skullIcon != -1 { iconOffset += 25 }
				if ap.prayerIcon >= 0 && ap.prayerIcon < prayers.count {
					r.draw(prayers[ap.prayerIcon], x: rect.x + p.x - 12, y: rect.y + p.y - iconOffset)
				}
				if ap.prayerIcon != -1 { iconOffset += 25 }
			}
			// A hint arrow on a player sits above its prayer icons.
			if type == nil, hintArrows.contains(where: { $0?.type == 10 && $0?.target == a.index }), let p = at(a.modelHeight + 15) {
				for h in hintArrows { if let h = h, h.type == 10, h.target == a.index, h.sprite < hintIcons.count { r.draw(hintIcons[h.sprite], x: rect.x + p.x - 12, y: rect.y + p.y - iconOffset) } }
			}

			// Overhead chat is collected now and drawn after all bars and splats.
			if let msg = a.chatMessage, isNpc || publicFilter == 0 || publicFilter == 3, lines.count < 50, let p = at(a.modelHeight) {
				lines.append(OverheadLine(halfWidth: b12.stringWidth(msg) / 2, lineHeight: b12.lineHeight, x: p.x, y: p.y,
				                          colour: a.chatColor, effect: a.chatEffect, loops: a.chatLoops, message: msg))
			}

			// Health bar.
			if a.hitpointsBarVisibleUntil > loop {
				var bg = defaultBars.count > 0 ? defaultBars[0] : nil
				var fg = defaultBars.count > 1 ? defaultBars[1] : nil
				if let t = type, t.hitBarId != -1, let custom = (try? store.sprite(t.hitBarId)) ?? nil, custom.frames.count == 2 {
					bg = custom.frames[0]
					fg = custom.frames[1]
				}
				if let bg = bg, let fg = fg, let p = at(bg.height + (iconHeight ?? a.modelHeight) + 10) {
					let x = rect.x + p.x - (bg.width >> 1), y = rect.y + p.y - 3
					r.draw(bg, x: x, y: y)
					let w = bg.width * a.hitpointsBar / 255
					let clip = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
					r.setClip(max(clip.0, x), max(clip.1, y), min(clip.2, x + w), min(clip.3, y + bg.height))
					r.draw(fg, x: x, y: y)
					r.setClip(clip.0, clip.1, clip.2, clip.3)
				}
			}

			// Hit splats.
			for i in 0..<4 where a.hitVisibleUntil[i] > loop {
				guard var p = at((iconHeight ?? a.modelHeight) / 2) else { continue }
				if i == 1 { p.y -= 20 }
				if i == 2 { p.y -= 10; p.x -= 15 }
				if i == 3 { p.y -= 10; p.x += 15 }
				let kind = a.hitTypes[i]
				if kind >= 0 && kind < marks.count { r.draw(marks[kind], x: rect.x + p.x - 12, y: rect.y + p.y - 12) }
				p11.drawCenter(String(a.hitDamages[i]), x: p.x + rect.x - 1, y: p.y + 3 + rect.y, color: 0xFFFFFF, shadow: 0, into: &r)
			}
		}

		drawOverheadChat(lines, b12, rect: rect, into: &r)
		drawTileHintArrows(hintIcons, cam: cam, scene: scene, rect: rect, into: &r)
	}

	/// rt4 `MiniMap.method4000`: hint arrows on a tile float above it, blinking like the others. Types 3...6 were turned
	/// into type 2 with an offset to one edge of the tile when they were read.
	func drawTileHintArrows(_ icons: [SpriteFrame], cam: OverlayCamera, scene: Scene, rect: (x: Int, y: Int, w: Int, h: Int), into r: inout Raster) {
		for case let h? in hintArrows where h.type == 2 && h.sprite < icons.count {
			let xFine = ((h.tileX - ctx.originX) << 7) + h.offsetX, zFine = ((h.tileZ - ctx.originZ) << 7) + h.offsetZ
			if let p = project(cam, xFine: xFine, zFine: zFine, height: h.height * 2, scene: scene), ctx.loop % 20 < 10 {
				r.draw(icons[h.sprite], x: rect.x + p.x - 12, y: rect.y + p.y - 28)
			}
		}
	}

	/// rt4 colour effects 6 to 11 for overhead chat (`anInt3325` is the cycle counter).
	static func overheadColour(_ index: Int, loops: Int, cycle: Int) -> Int {
		var colour = 16776960
		if index < 6 { colour = overheadColours[index] }
		let k = 150 - loops
		switch index {
		case 6: colour = cycle % 20 >= 10 ? 16776960 : 16711680
		case 7: colour = cycle % 20 < 10 ? 255 : 65535
		case 8: colour = cycle % 20 >= 10 ? 8454016 : 45056
		case 9:
			if k < 50 { colour = k * 1280 + 16711680 } else if k < 100 { colour = 16776960 + 16384000 - k * 327680 } else if k < 150 { colour = k * 5 + 65280 - 500 }
		case 10:
			if k < 50 { colour = k * 5 + 16711680 } else if k < 100 { colour = 16711935 - (k - 50) * 327680 } else if k < 150 { colour = k * 327680 + 255 + 500 - k * 5 - 32768000 }
		case 11:
			if k < 50 { colour = 16777215 - k * 327685 } else if k < 100 { colour = k * 327685 + 65280 - 16384250 } else if k < 150 { colour = 16777215 + 32768000 - k * 327680 }
		default: break
		}
		return colour & 0xFFFFFF
	}

	/// The second half of rt4 `drawOverheads`: stacks overlapping lines upwards, picks the colour and
	/// draws with the wave / wave2 / shake / scroll / slide effect.
	func drawOverheadChat(_ lines: [OverheadLine], _ font: BitmapFont, rect: (x: Int, y: Int, w: Int, h: Int), into r: inout Raster) {
		var placedY = [Int](repeating: 0, count: lines.count)
		for i in 0..<lines.count {
			var y = lines[i].y
			let x = lines[i].x, h = lines[i].lineHeight, hw = lines[i].halfWidth
			var moved = true
			while moved {
				moved = false
				for j in 0..<i {
					let oy = placedY[j], oh = lines[j].lineHeight, ox = lines[j].x, ohw = lines[j].halfWidth
					if oy - oh < y + 2 && y - h < oy + 2 && x - hw < ox + ohw && ox - ohw < hw + x && oy - oh < y {
						y = oy - oh
						moved = true
					}
				}
			}
			placedY[i] = y
			let l = lines[i]
			let sx = rect.x + x, sy = rect.y + y
			if chatEffectsDisabled {
				font.drawCenter(l.message, x: sx, y: sy, color: 16776960, shadow: 0, into: &r)
				continue
			}
			let colour = UInt32(Self.overheadColour(l.colour, loops: l.loops, cycle: ctx.loop))
			let k = 150 - l.loops
			switch l.effect {
			case 1: // wave
				font.drawOffsets(l.message, centerX: sx, y: sy, color: colour, into: &r) { n, _ in (0, Int(sin(Double(n) / 2.0 + Double(self.ctx.loop) / 5.0) * 5.0)) }
			case 2: // wave2
				font.drawOffsets(l.message, centerX: sx, y: sy, color: colour, into: &r) { n, _ in
					(Int(sin(Double(n) / 5.0 + Double(self.ctx.loop) / 5.0) * 5.0), Int(sin(Double(n) / 3.0 + Double(self.ctx.loop) / 5.0) * 5.0))
				}
			case 3: // shake
				let amp = max(7.0 - Double(k) / 8.0, 0.0)
				font.drawOffsets(l.message, centerX: sx, y: sy, color: colour, into: &r) { n, _ in (0, Int(sin(Double(n) / 1.5 + Double(self.ctx.loop) / 1.0) * amp)) }
			case 4: // scroll: slides in from the right inside a 100 px window
				let travel = k * (font.stringWidth(l.message) + 100) / 150
				let clip = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
				r.setClip(max(clip.0, sx - 50), max(clip.1, rect.y), min(clip.2, sx + 50), min(clip.3, rect.y + rect.h))
				font.drawLeft(l.message, x: sx + 50 - travel, y: sy, color: colour, shadow: 0, into: &r)
				r.setClip(clip.0, clip.1, clip.2, clip.3)
			case 5: // slide: rises from below, then drops away
				var dy = 0
				if k < 25 { dy = k - 25 } else if k > 125 { dy = k - 125 }
				let clip = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
				r.setClip(max(clip.0, rect.x), max(clip.1, sy - font.lineHeight - 1), min(clip.2, rect.x + rect.w), min(clip.3, sy + 5))
				font.drawCenter(l.message, x: sx, y: sy + dy, color: colour, shadow: 0, into: &r)
				r.setClip(clip.0, clip.1, clip.2, clip.3)
			default:
				font.drawCenter(l.message, x: sx, y: sy, color: colour, shadow: 0, into: &r)
			}
		}
	}
}

extension BitmapFont {
	/// rt4 `Font.renderOffset` (behind `renderWave`, `renderWave2`, `renderShake`): draws `text`
	/// centred on `centerX` with a per-glyph (dx, dy) from `offset(glyphIndex, glyph)`. A glyph is
	/// one character or one `<..>` entity such as `<lt>`; the index counts glyphs.
	func drawOffsets(_ text: String, centerX: Int, y: Int, color: UInt32, into r: inout Raster, offset: (Int, UInt8) -> (Int, Int)) {
		let bytes = Cp1252.encode(text)
		// Split into glyph units, keeping `<..>` tags together.
		var units: [[UInt8]] = []
		var i = 0
		while i < bytes.count {
			if bytes[i] == 60, let close = bytes[i...].firstIndex(of: 62) {
				units.append(Array(bytes[i...close]))
				i = close + 1
			} else {
				units.append([bytes[i]])
				i += 1
			}
		}
		let startX = centerX - width(bytes) / 2
		var prefix: [UInt8] = []
		for (n, u) in units.enumerated() {
			prefix += u
			let code: Int
			if u.count > 1, let e = BitmapFont.entity(Cp1252.decode(u.dropFirst().dropLast())) { code = e } else { code = Int(u[0]) }
			let x = startX + width(prefix) - (code < glyphWidths.count ? glyphWidths[code] : 0)
			let (dx, dy) = offset(n, u[0])
			drawLeft(Cp1252.decode(u), x: x + dx, y: y + dy, color: color, shadow: 0, into: &r)
		}
	}
}
