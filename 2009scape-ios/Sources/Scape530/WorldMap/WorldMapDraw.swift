import Foundation

/// A raw view of a `Raster` for the map's tile loops (rt4 `SoftwareRaster` statics): fills, lines, shaped tiles and
/// scaled indexed sprites, all clipped to the raster's clip rectangle. Colours are 0xRRGGBB.
struct MapTarget {
	let base: UnsafeMutablePointer<UInt32>
	let stride: Int
	let clipLeft: Int, clipTop: Int, clipRight: Int, clipBottom: Int

	@inline(__always) private func px(_ c: Int) -> UInt32 { 0xFF00_0000 | (UInt32(truncatingIfNeeded: c) & 0xFFFFFF) }

	func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ colour: Int) {
		let x0 = max(x, clipLeft), x1 = min(x + w, clipRight), y0 = max(y, clipTop), y1 = min(y + h, clipBottom)
		guard x0 < x1, y0 < y1 else { return }
		let c = px(colour)
		for yy in y0..<y1 { (base + yy * stride + x0).update(repeating: c, count: x1 - x0) }
	}

	func vline(_ x: Int, _ y: Int, _ h: Int, _ colour: Int) { fill(x, y, 1, h, colour) }
	func hline(_ x: Int, _ y: Int, _ w: Int, _ colour: Int) { fill(x, y, w, 1, colour) }

	/// rt4 `WorldMap.method4667`: the part of a `w` x `h` tile at (x, y) covered by tile shape `shape` (1...8) turned
	/// `rotation` quarter turns in `colour`; the rest gets `rest` when `fillRest`.
	func shaped(_ x: Int, _ y: Int, _ w: Int, _ h: Int, shape shapeIn: Int, rotation rotIn: Int, colour: Int, rest: Int, fillRest: Bool) {
		var shape = shapeIn, rot = rotIn
		if shape == 9 { rot = (rot + 1) & 3; shape = 1 }
		if shape == 10 { rot = (rot + 3) & 3; shape = 1 }
		if shape == 11 { rot = (rot + 3) & 3; shape = 8 }
		guard let rule = MapTarget.rule(shape: shape, rotation: rot) else { return }
		let x0 = max(x, clipLeft), x1 = min(x + w, clipRight), y0 = max(y, clipTop), y1 = min(y + h, clipBottom)
		guard x0 < x1, y0 < y1 else { return }
		let over = px(colour), under = px(rest)
		for dy in (y0 - y)..<(y1 - y) {
			let v = rule.bottomUp ? h - 1 - dy : dy
			let row = base + (y + dy) * stride + x
			for dx in (x0 - x)..<(x1 - x) {
				let u = rule.mirrored ? w - 1 - dx : dx
				if rule.test(u, v, w, h) { row[dx] = over } else if fillRest { row[dx] = under }
			}
		}
	}

	struct Rule {
		/// The row index counts from the bottom (rt4 loops its rows downwards) / the column from the right.
		var bottomUp: Bool, mirrored: Bool
		var test: (_ u: Int, _ v: Int, _ w: Int, _ h: Int) -> Bool
	}

	/// The coverage test of every shape and rotation, read off `method4667`'s loops: (u, v) are the column and row
	/// of the pixel, flipped as the loop direction says.
	static func rule(shape: Int, rotation: Int) -> Rule? {
		switch (shape, rotation) {
		case (1, 0): return Rule(bottomUp: false, mirrored: false) { u, v, _, _ in u <= v }
		case (1, 1): return Rule(bottomUp: true, mirrored: false) { u, v, _, _ in v >= u }
		case (1, 2): return Rule(bottomUp: false, mirrored: false) { u, v, _, _ in u >= v }
		case (1, 3): return Rule(bottomUp: true, mirrored: false) { u, v, _, _ in u >= v }
		case (2, 0): return Rule(bottomUp: true, mirrored: false) { u, v, _, _ in (v >> 1) >= u }
		case (2, 1): return Rule(bottomUp: false, mirrored: false) { u, v, _, _ in (v << 1) <= u }
		case (2, 2): return Rule(bottomUp: false, mirrored: true) { u, v, _, _ in (v >> 1) >= u }
		case (2, 3): return Rule(bottomUp: true, mirrored: true) { u, v, _, _ in (v << 1) <= u }
		case (3, 0): return Rule(bottomUp: true, mirrored: true) { u, v, _, _ in (v >> 1) >= u }
		case (3, 1): return Rule(bottomUp: true, mirrored: false) { u, v, _, _ in u >= (v << 1) }
		case (3, 2): return Rule(bottomUp: false, mirrored: false) { u, v, _, _ in u <= (v >> 1) }
		case (3, 3): return Rule(bottomUp: false, mirrored: true) { u, v, _, _ in (v << 1) <= u }
		case (4, 0): return Rule(bottomUp: true, mirrored: false) { u, v, _, _ in (v >> 1) <= u }
		case (4, 1): return Rule(bottomUp: false, mirrored: false) { u, v, _, _ in (v << 1) >= u }
		case (4, 2): return Rule(bottomUp: false, mirrored: true) { u, v, _, _ in u >= (v >> 1) }
		case (4, 3): return Rule(bottomUp: true, mirrored: true) { u, v, _, _ in u <= (v << 1) }
		case (5, 0): return Rule(bottomUp: true, mirrored: true) { u, v, _, _ in (v >> 1) <= u }
		case (5, 1): return Rule(bottomUp: true, mirrored: false) { u, v, _, _ in u <= (v << 1) }
		case (5, 2): return Rule(bottomUp: false, mirrored: false) { u, v, _, _ in u >= (v >> 1) }
		case (5, 3): return Rule(bottomUp: false, mirrored: true) { u, v, _, _ in (v << 1) >= u }
		case (6, 0): return Rule(bottomUp: false, mirrored: false) { u, _, w, _ in u <= w / 2 }
		case (6, 1): return Rule(bottomUp: false, mirrored: false) { _, v, _, h in v <= h / 2 }
		case (6, 2): return Rule(bottomUp: false, mirrored: false) { u, _, w, _ in u >= w / 2 }
		case (6, 3): return Rule(bottomUp: false, mirrored: false) { _, v, _, h in v >= h / 2 }
		case (7, 0): return Rule(bottomUp: false, mirrored: false) { u, v, _, h in u <= v - h / 2 }
		case (7, 1): return Rule(bottomUp: true, mirrored: false) { u, v, _, h in v - h / 2 >= u }
		case (7, 2): return Rule(bottomUp: true, mirrored: true) { u, v, _, h in u <= v - h / 2 }
		case (7, 3): return Rule(bottomUp: false, mirrored: true) { u, v, _, h in v - h / 2 >= u }
		case (8, 0): return Rule(bottomUp: false, mirrored: false) { u, v, _, h in v - h / 2 <= u }
		case (8, 1): return Rule(bottomUp: true, mirrored: false) { u, v, _, h in v - h / 2 <= u }
		case (8, 2): return Rule(bottomUp: true, mirrored: true) { u, v, _, h in u >= v - h / 2 }
		case (8, 3): return Rule(bottomUp: false, mirrored: true) { u, v, _, h in v - h / 2 <= u }
		default: return nil
		}
	}

	/// rt4 `SoftwareIndexedSprite.method1398` / `method1390`: the sprite scaled to `w` x `h` at (x, y), palette index 0
	/// transparent; `tint` (0 for none) multiplies each channel.
	func scaled(_ s: IndexedMapSprite, x xIn: Int, y yIn: Int, w wIn: Int, h hIn: Int, tint: Int) {
		guard wIn > 0, hIn > 0 else { return }
		var x = xIn, y = yIn, w = wIn, h = hIn
		let stepX = (s.innerWidth << 16) / w, stepY = (s.innerHeight << 16) / h
		guard stepX > 0, stepY > 0 else { return }
		var startX = 0, startY = 0
		if s.xOffset > 0 {
			let d = (((s.xOffset << 16) + stepX - 1) / stepX)
			x += d
			startX = d * stepX - (s.xOffset << 16)
		}
		if s.yOffset > 0 {
			let d = (((s.yOffset << 16) + stepY - 1) / stepY)
			y += d
			startY = d * stepY - (s.yOffset << 16)
		}
		if s.width < s.innerWidth { w = (((s.width << 16) + stepX - startX - 1) / stepX) }
		if s.height < s.innerHeight { h = (((s.height << 16) + stepY - startY - 1) / stepY) }
		if y + h > clipBottom { h -= y + h - clipBottom }
		if y < clipTop { let d = clipTop - y; h -= d; y += d; startY += stepY * d }
		if x + w > clipRight { w -= x + w - clipRight }
		if x < clipLeft { let d = clipLeft - x; w -= d; x += d; startX += stepX * d }
		guard w > 0, h > 0 else { return }
		let tr = (tint >> 16) & 0xFF, tg = (tint >> 8) & 0xFF, tb = tint & 0xFF
		var sy = startY
		for dy in 0..<h {
			let rowBase = (sy >> 16) * s.width
			var sx = startX
			let out = base + (y + dy) * stride + x
			for dx in 0..<w {
				let i = (sx >> 16) + rowBase
				if i >= 0 && i < s.pixels.count {
					let idx = Int(s.pixels[i])
					if idx != 0 {
						var c = s.palette[idx]
						if tint != 0 {
							let r = (Int(c >> 16 & 0xFF) * tr) >> 8, g = (Int(c >> 8 & 0xFF) * tg) >> 8, b = (Int(c & 0xFF) * tb) >> 8
							c = UInt32((r << 16) + (g << 8) + b)
						}
						out[dx] = 0xFF00_0000 | c
					}
				}
				sx += stepX
			}
			sy += stepY
		}
	}
}

extension WorldMap {
	// MARK: ground (rt4 `method4364` / `method2735`)

	/// rt4 `WorldMap.method4364`: paints the part of the map between tiles (leftTile, topTile) and
	/// (rightTile, bottomTile) into the pixel rectangle (leftPx, topPx) to (rightPx, bottomPx).
	func drawGround(into r: inout Raster, leftPx: Int, topPx: Int, rightPx: Int, bottomPx: Int, leftTile: Int, topTile: Int, rightTile: Int, bottomTile: Int) {
		let tilesW = rightTile - leftTile, tilesH = bottomTile - topTile
		guard tilesW > 0, tilesH > 0, current != nil, loadPercentage == 100 else { return }
		let xScale = ((rightPx - leftPx) << 16) / tilesW
		let yScale = ((bottomPx - topPx) << 16) / tilesH
		let clip = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		let stride = r.width
		r.pixels.withUnsafeMutableBufferPointer { buf in
			let t = MapTarget(base: buf.baseAddress!, stride: stride, clipLeft: clip.0, clipTop: clip.1, clipRight: clip.2, clipBottom: clip.3)
			paintGround(t, topPx: topPx, bottomTile: bottomTile, topTile: topTile, rightTile: rightTile, leftPx: leftPx, leftTile: leftTile, yScale: yScale, xScale: xScale)
		}
	}

	/// The colour of tiles with no data (rt4: the map's background, else a chequerboard of the "hidden" overlay).
	@inline(__always) private func emptyColour(_ current: WorldMapDefinition, even: Bool) -> Int {
		var c: Int
		if current.backgroundColor != -1 { c = current.backgroundColor }
		else if even { c = overlayColors[min(hiddenOverlay + 1, overlayColors.count - 1)] }
		else { c = 0x4B5368 }
		if c == 0 { c = 1 }
		return c
	}

	/// rt4 `WorldMap.method2735`.
	private func paintGround(_ t: MapTarget, topPx: Int, bottomTile: Int, topTile: Int, rightTile: Int, leftPx: Int, leftTile: Int, yScale: Int, xScale: Int) {
		guard let current else { return }
		var tilesW = rightTile - leftTile, tilesH = bottomTile - topTile
		if width > rightTile { tilesW += 1 }
		if length > bottomTile { tilesH += 1 }
		let chunksX = chunks.ground.count
		let oc = overlayColors
		func colour(_ id: UInt8) -> Int { Int(id) < oc.count ? oc[Int(id)] : 0 }
		for c in 0..<tilesW {
			var x0 = (c * xScale) >> 16
			var x1 = ((c + 1) * xScale) >> 16
			let pw = x1 - x0
			guard pw > 0 else { continue }
			let cx = (c + leftTile) >> 6
			x0 += leftPx
			x1 += leftPx
			guard cx >= 0, cx < chunksX else {
				for r in 0..<tilesH {
					let colourFill = emptyColour(current, even: ((c + leftTile) & 4) == ((r + topTile) & 4))
					let y0 = ((yScale * r) >> 16) + topPx, y1 = topPx + (((r + 1) * yScale) >> 16)
					t.fill(x0, y0, pw, y1 - y0, colourFill)
				}
				continue
			}
			let ground = chunks.ground[cx], ov1 = chunks.overlay[cx], sh1 = chunks.overlayShape[cx]
			let wall = chunks.lines[cx], ov2 = chunks.overlay2[cx], sh2 = chunks.overlay2Shape[cx]
			for r in 0..<tilesH {
				let y0r = (yScale * r) >> 16
				var y1 = ((r + 1) * yScale) >> 16
				let ph = y1 - y0r
				guard ph > 0 else { continue }
				y1 += topPx
				let cz = (topTile + r) >> 6
				let y0 = y0r + topPx
				let tile = (((topTile + r) & 0x3F) << 6) + ((leftTile + c) & 0x3F)
				var under: Int
				if cz < 0 || cz > ground.count - 1 || ground[cz] == nil {
					under = emptyColour(current, even: ((r + topTile) & 4) == ((leftTile + c) & 4))
					if cz < 0 || cz > ground.count - 1 {
						t.fill(x0, y0, pw, ph, under)
						continue
					}
				} else {
					under = Int(ground[cz]![tile])
				}
				var over = ov1[cz].map { colour($0[tile]) } ?? 0
				if under == 0 { under = 1 }
				var over2 = ov2[cz].map { colour($0[tile]) } ?? 0
				if over == 0 && over2 == 0 {
					t.fill(x0, y0, pw, ph, under)
				} else {
					if over != 0 {
						if over == -1 { over = 1 }
						let sh = sh1[cz]?[tile] ?? 0
						let shape = Int(sh & 0xFC)
						if shape == 0 || pw <= 1 || ph <= 1 {
							t.fill(x0, y0, pw, ph, over)
						} else {
							t.shaped(x0, y0, pw, ph, shape: shape >> 2, rotation: Int(sh & 3), colour: over, rest: under, fillRest: true)
						}
					}
					if over2 != 0 {
						if over2 == -1 { over2 = under }
						let sh = sh2[cz]?[tile] ?? 0
						let shape = Int(sh & 0xFC)
						if shape == 0 || pw <= 1 || ph <= 1 {
							t.fill(x0, y0, pw, ph, over2)
						}
						t.shaped(x0, y0, pw, ph, shape: shape >> 2, rotation: Int(sh & 3), colour: over2, rest: 0, fillRest: over == 0)
					}
				}
				if let walls = wall[cz] {
					let line = Int(walls[tile])
					if line != 0 { drawLine(t, line, x0: x0, y0: y0, pw: pw, ph: ph, xEnd: x1, yEnd: y1) }
				}
			}
		}
		// Map scenes (trees, buildings...) stretch over their tiles on top of everything else.
		paintScenery(t, topPx: topPx, leftPx: leftPx, leftTile: leftTile, topTile: topTile, tilesW: tilesW, tilesH: tilesH, xScale: xScale, yScale: yScale)
	}

	/// The wall line of a tile (rt4 `method2735`: 1-4 single sides, 5-8 the same in red, 9-12 white and a side, 17-20
	/// corner dots, 25 and 26 diagonals).
	private func drawLine(_ t: MapTarget, _ lineIn: Int, x0: Int, y0: Int, pw: Int, ph: Int, xEnd: Int, yEnd: Int) {
		var line = lineIn
		let right = pw == 1 ? x0 : xEnd - 1
		let bottom = ph == 1 ? y0 : yEnd - 1
		var colour = 0xCCCCCC
		if (line >= 5 && line <= 8) || (line >= 13 && line <= 16) || (line >= 21 && line <= 24) || line == 27 || line == 28 {
			colour = 0xCC0000
			line -= 4
		}
		switch line {
		case 1: t.vline(x0, y0, ph, colour)
		case 2: t.hline(x0, y0, pw, colour)
		case 3: t.vline(right, y0, ph, colour)
		case 4: t.hline(x0, bottom, pw, colour)
		case 9: t.vline(x0, y0, ph, 0xFFFFFF); t.hline(x0, y0, pw, colour)
		case 10: t.vline(right, y0, ph, 0xFFFFFF); t.hline(x0, y0, pw, colour)
		case 11: t.vline(right, y0, ph, 0xFFFFFF); t.hline(x0, bottom, pw, colour)
		case 12: t.vline(x0, y0, ph, 0xFFFFFF); t.hline(x0, bottom, pw, colour)
		case 17: t.hline(x0, y0, 1, colour)
		case 18: t.hline(right, y0, 1, colour)
		case 19: t.hline(right, bottom, 1, colour)
		case 20: t.hline(x0, bottom, 1, colour)
		case 25: for i in 0..<ph { t.hline(i + x0, -i + bottom, 1, colour) }
		case 26: for i in 0..<ph { t.hline(i + x0, y0 + i, 1, colour) }
		default: break
		}
	}

	func msiSprite(_ id: Int, rotations: Int) -> IndexedMapSprite? {
		let key = rotations << 16 | id
		if let c = msiSprites[key] { return c }
		var s: IndexedMapSprite?
		if let f = (try? store.sprite(id))??.frames.first {
			var t = IndexedMapSprite(f)
			for _ in 0..<rotations { t.flipVertical() }
			s = t
		}
		msiSprites[key] = .some(s)
		return s
	}

	private func paintScenery(_ t: MapTarget, topPx: Int, leftPx: Int, leftTile: Int, topTile: Int, tilesW: Int, tilesH: Int, xScale: Int, yScale: Int) {
		let chunksX = chunks.scenery.count
		for c in -2..<(tilesW + 2) {
			var x0 = (c * xScale) >> 16
			let x1 = ((c + 1) * xScale) >> 16
			let pw = x1 - x0
			guard pw > 0 else { continue }
			x0 += leftPx
			let cx = (leftTile + c) >> 6
			guard cx >= 0, cx < chunksX else { continue }
			let col = chunks.scenery[cx]
			for r in -2..<(tilesH + 2) {
				let y0r = (r * yScale) >> 16
				let ph = (((r + 1) * yScale) >> 16) - y0r
				guard ph > 0 else { continue }
				let y0 = y0r + topPx
				let cz = (r + topTile) >> 6
				guard cz >= 0, cz < col.count, let chunk = col[cz] else { continue }
				let scene = Int(chunk[(((topTile + r) & 0x3F) << 6) + ((c + leftTile) & 0x3F)])
				let id = scene & 0x3FFF
				guard id != 0 else { continue }
				var angle = (scene >> 14) & 3
				guard let msi = (try? store.msi(id - 1)) ?? nil, msi.spriteId != -1, let sprite = msiSprite(msi.spriteId, rotations: angle) else { continue }
				var h = ph * sprite.height / 4
				var w = pw * sprite.width / 4
				if msi.stretch {
					var a = (scene >> 16) & 0xF, b = (scene >> 20) & 0xF
					if angle & 1 == 1 { swap(&a, &b) }
					angle = 0
					w = pw * a
					h = ph * b
				}
				if w != 0 && h != 0 { t.scaled(sprite, x: x0, y: y0 + ph - h, w: w, h: h, tint: msi.tint) }
			}
		}
	}

	// MARK: icons (rt4 `method1195` / `method3991`)

	/// rt4 `method3991`: the map function icons, the flashing one with its rings. Drawn from the loc ids stored per tile.
	func drawIcons(into r: inout Raster, leftPx: Int, topPx: Int, rightPx: Int, bottomPx: Int, leftTile: Int, topTile: Int, rightTile: Int, bottomTile: Int) {
		let tilesW = rightTile - leftTile, tilesH = bottomTile - topTile
		guard tilesW > 0, tilesH > 0, current != nil, loadPercentage == 100 else { return }
		let xScale = ((rightPx - leftPx) << 16) / tilesW
		let yScale = ((bottomPx - topPx) << 16) / tilesH
		guard xScale > 0, yScale > 0 else { return }
		var phase = -1
		if flashCount > 0 { phase = flashPhase <= 10 ? flashPhase * 5 : 50 - (flashPhase - 10) * 5 }
		let marginX = 983_040 / xScale, marginY = 983_040 / yScale
		var flashing: [(id: Int, x: Int, y: Int)] = []
		let chunksX = chunks.icons.count
		var locs: [Int: Int] = [:]
		for c in -marginX..<(tilesW + marginX) {
			let x1 = (xScale * (c + 1)) >> 16
			var x0 = (c * xScale) >> 16
			guard x1 - x0 > 0 else { continue }
			let cx = (leftTile + c) >> 6
			x0 += leftPx
			guard cx >= 0, cx < chunksX else { continue }
			let col = chunks.icons[cx]
			for rr in -marginY..<(tilesH + marginY) {
				let y1 = (yScale * (rr + 1)) >> 16
				var y0 = (rr * yScale) >> 16
				guard y1 - y0 > 0 else { continue }
				y0 += topPx
				let cz = (topTile + rr) >> 6
				guard cz >= 0, cz < col.count, let chunk = col[cz] else { continue }
				let v = Int(chunk[((c + leftTile) & 0x3F) + (((topTile + rr) & 0x3F) << 6)])
				guard v != 0 else { continue }
				let fn: Int
				if let known = locs[v] { fn = known } else {
					fn = ((try? store.loc(v - 1)) ?? nil)?.mapFunction ?? -1
					locs[v] = fn
				}
				guard fn >= 0, fn < functionSprites.count, !hiddenFunctions[fn] else { continue }
				if phase != -1 && fn == flashIcon {
					flashing.append((fn, x0, y0))
				} else {
					r.draw(functionSprites[fn], x: x0 - 7, y: y0 - 7)
				}
			}
		}
		for f in flashing {
			for radius in [15, 13, 11, 9] { fillCircle(&r, f.x, f.y, radius, alpha: phase) }
			r.draw(functionSprites[f.id], x: f.x - 7, y: f.y - 7)
		}
	}

	/// rt4 `SoftwareRaster.method2502`: a yellow disc blended with `alpha` (0...256).
	func fillCircle(_ r: inout Raster, _ cx: Int, _ cy: Int, _ radius: Int, alpha: Int) {
		guard alpha > 0 else { return }
		for dy in -radius...radius {
			let half = Int(Double(radius * radius - dy * dy).squareRoot())
			r.fillRect(cx - half, cy + dy, half * 2 + 1, 1, 0xFFFF00, opacity: alpha)
		}
	}

	// MARK: labels (rt4 `method959`)

	/// rt4 `method959`: the drawn labels, in the font of their size class for the current zoom.
	func drawLabels(into r: inout Raster, leftPx: Int, topPx: Int, rightPx: Int, bottomPx: Int, leftTile: Int, topTile: Int, rightTile: Int, bottomTile: Int) {
		guard rightTile != leftTile, bottomTile != topTile else { return }
		let z = Double(zoom)
		for i in 0..<labels.count where labels.isDrawn(i) {
			let tx = labels.x[i] - originX
			let tz = originZ + length - labels.z[i] - 1
			let x = leftPx + (rightPx - leftPx) * (tx - leftTile) / (rightTile - leftTile)
			var y = (bottomPx - topPx) * (tz - topTile) / (bottomTile - topTile) + topPx
			var colour: UInt32 = 0xFFFFFF
			let size = labels.sizeClass(i)
			var fontSize = 0
			if size == 0 {
				if z == 3 { fontSize = 11 }
				if z == 4 { fontSize = 12 }
				if z == 6 { fontSize = 14 }
				if z >= 8 { fontSize = 17 }
			} else if size == 1 {
				if z == 3 { fontSize = 14 }
				if z == 4 { fontSize = 17 }
				if z == 6 { fontSize = 19 }
				if z >= 8 { fontSize = 22 }
			} else if size == 2 {
				if z == 3 { fontSize = 19 }
				colour = 0xFFAA00
				if z == 4 { fontSize = 22 }
				if z == 6 { fontSize = 26 }
				if z >= 8 { fontSize = 30 }
			}
			if labels.colour[i] != -1 { colour = UInt32(truncatingIfNeeded: labels.colour[i]) & 0xFFFFFF }
			guard fontSize != 0, let font = labelFonts[fontSize] else { continue }
			let lines = labels.names[i].components(separatedBy: "<br>")
			y -= (font.lineHeight * (lines.count - 1)) / 2
			y += font.capHeight / 2
			for line in lines {
				font.drawCentered(line, x: x, baseline: y, color: colour, into: &r)
				y += font.lineHeight
			}
		}
	}

	// MARK: components (rt4 `method2225` and `Cs1ScriptRunner.method4`)

	/// The map component (client code 1400): loads one stage while loading, then draws the map at (x, y) in a `w` x
	/// `h` rectangle. Sets the view size the scripts read with ops 5208 and 5209.
	func drawMain(into r: inout Raster, x: Int, y: Int, w: Int, h: Int) {
		isShown = true
		componentSize = (w, h)
		if loadPercentage < 100 { step() }
		let saved = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		defer { r.setClip(saved.0, saved.1, saved.2, saved.3) }
		r.setClip(max(saved.0, x), max(saved.1, y), min(saved.2, x + w), min(saved.3, y + h))
		if loadPercentage < 100 {
			let mx = x + w / 2, my = h / 2 + y - 18 - 20
			r.fillRect(x, y, w, h, 0)
			r.drawRect(mx - 152, my, 304, 34, 0x8C1111)
			r.drawRect(mx - 151, my + 1, 302, 32, 0)
			r.fillRect(mx - 150, my + 2, loadPercentage * 3, 30, 0x8C1111)
			r.fillRect(mx + loadPercentage * 3 - 150, my + 2, 300 - loadPercentage * 3, 30, 0)
			if let f = ((try? store.font(named: "b12_full")) ?? nil) { f.drawCenter("Loading...", x: mx, y: my + 20, color: 0xFFFFFF, shadow: 0, into: &r) }
			return
		}
		let halfW = Int(Float(w) / zoom), halfH = Int(Float(h) / zoom)
		viewHeightTiles = Int(Float(h * 2) / zoom)
		viewWidthTiles = Int(Float(w * 2) / zoom)
		viewLeft = viewX - halfW
		viewTop = viewZ - halfH
		let leftTile = viewLeft, topTile = viewTop, bottomTile = viewZ + halfH, rightTile = halfW + viewX
		drawGround(into: &r, leftPx: x, topPx: y, rightPx: x + w, bottomPx: y + h, leftTile: leftTile, topTile: topTile, rightTile: rightTile, bottomTile: bottomTile)
		drawIcons(into: &r, leftPx: x, topPx: y, rightPx: x + w, bottomPx: y + h, leftTile: leftTile, topTile: topTile, rightTile: rightTile, bottomTile: bottomTile)
		drawLabels(into: &r, leftPx: x, topPx: y, rightPx: x + w, bottomPx: y + h, leftTile: leftTile, topTile: topTile, rightTile: rightTile, bottomTile: bottomTile)
	}

	/// The overview component (client code 1401): the whole map in `w` x `h`, the shown area outlined and the flashing
	/// icons as dots.
	func drawOverview(into r: inout Raster, x: Int, y: Int, w: Int, h: Int) {
		let saved = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		defer { r.setClip(saved.0, saved.1, saved.2, saved.3) }
		r.setClip(max(saved.0, x), max(saved.1, y), min(saved.2, x + w), min(saved.3, y + h))
		r.fillRect(x, y, w, h, 0)
		guard loadPercentage == 100, w > 0, h > 0, width > 0, length > 0 else { return }
		if overview == nil || overview!.width != w || overview!.height != h {
			var img = Raster(width: w, height: h)
			drawGround(into: &img, leftPx: 0, topPx: 0, rightPx: w, bottomPx: h, leftTile: 0, topTile: 0, rightTile: width, bottomTile: length)
			overview = img
		}
		r.blit(overview!, x: x, y: y)
		let top = h * viewTop / length + y
		let boxH = viewHeightTiles * h / length
		let left = x + w * viewLeft / width
		let boxW = w * viewWidthTiles / width
		r.fillRect(left, top, boxW, boxH, 0xFF0000, opacity: 128)
		r.drawRect(left, top, boxW, boxH, 0xFF0000)
		guard flashCount > 0 else { return }
		let alpha = flashPhase > 10 ? (20 - flashPhase) * 25 : flashPhase * 25
		for e in elements where e.id == flashIcon {
			r.fillRect(w * e.x / width + x - 2, y + e.z * h / length - 2, 4, 4, 0xFFFF00, opacity: alpha)
		}
	}
}
