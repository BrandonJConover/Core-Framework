import Foundation

/// Building the static minimap image from a built `Scene` (rt4 `MiniMap.renderMap`, `method3109`
/// and `renderScenery`).
extension Minimap {
	/// rt4 wall and diagonal colours (the game picks them with `Math.random`; these are the means).
	static let wallColor: UInt32 = 0xEEEEEE
	/// Walls and diagonals of locs that can be interacted with (rt4 `key > 0`).
	static let wallInteractiveColor: UInt32 = 0xEE0000
	static let diagonalColor: UInt32 = 0xEEEEEE   // rt4 15658734
	static let diagonalInteractiveColor: UInt32 = 0xEE0000 // rt4 15597568

	/// rt4 `MiniMap.renderMap(level)`.
	func buildImage(scene: Scene, level: Int, palette: [Int32]) {
		var img = MinimapImage()
		let rgb: (Int) -> UInt32 = { hsl in
			guard hsl > 0 && hsl < palette.count else { return 0 }
			return UInt32(bitPattern: palette[hsl]) & 0xFFFFFF
		}
		for z in 1..<103 {
			let row = 4 * 512 * (103 - z) + 24628
			for x in 1..<103 {
				let index = row + (x - 1) * 4
				if (scene.renderFlags[level][x][z] & 0x18) == 0 {
					img.renderTile(scene.tiles[level][x][z], at: index, rgb: rgb)
				}
				if level < 3 && (scene.renderFlags[level + 1][x][z] & 0x8) != 0 {
					img.renderTile(scene.tiles[level + 1][x][z], at: index, rgb: rgb)
				}
			}
		}
		// Map function icons come from the ground decoration of each tile.
		for x in 0..<104 {
			for z in 0..<104 {
				let key = scene.groundDecorKey(level: level, x: x, z: z)
				guard key != 0, let loc = try? store.loc(Self.locId(key)) else { continue }
				var fn = loc.mapFunction
				if let multi = loc.multiLocs {
					for id in multi where id != -1 {
						if let m = (try? store.loc(id)) ?? nil, m.mapFunction >= 0 { fn = m.mapFunction; break }
					}
				}
				if fn >= 0 { img.icons.append((loc.id, x, z)) }
			}
		}
		for z in 1..<103 {
			for x in 1..<103 {
				if (scene.renderFlags[level][x][z] & 0x18) == 0 { paintLocs(&img, scene, level: level, x: x, z: z) }
				if level < 3 && (scene.renderFlags[level + 1][x][z] & 0x8) != 0 { paintLocs(&img, scene, level: level + 1, x: x, z: z) }
			}
		}
		image = img
	}

	static func locId(_ key: Int64) -> Int { Int((UInt64(bitPattern: key) >> 32) & 0x7FFF_FFFF) }

	/// rt4 `MiniMap.method3109`: walls (white or red lines), diagonal walls and map scenes of one tile.
	private func paintLocs(_ img: inout MinimapImage, _ scene: Scene, level: Int, x: Int, z: Int) {
		var key = scene.wallKey(level: level, x: x, z: z)
		let base = x * 4 + (103 - z) * 2048 + 24624
		func put(_ offsets: Int..., color: UInt32) { for o in offsets { img.pixels[base + o] = color } }
		if key != 0 {
			let rot = Int(Int32(truncatingIfNeeded: key)) >> 20 & 3
			let shape = Int(Int32(truncatingIfNeeded: key)) >> 14 & 0x1F
			if let loc = (try? store.loc(Self.locId(key))) ?? nil {
				if loc.mapScene == -1 {
					let c = key > 0 ? Self.wallInteractiveColor : Self.wallColor
					if shape == 0 || shape == 2 {
						switch rot {
						case 0: put(0, 512, 1024, 1536, color: c)
						case 1: put(0, 1, 2, 3, color: c)
						case 2: put(3, 3 + 512, 3 + 1024, 3 + 1536, color: c)
						default: put(1536, 1537, 1538, 1539, color: c)
						}
					}
					if shape == 3 {
						switch rot {
						case 0: put(0, color: c)
						case 1: put(3, color: c)
						case 2: put(1539, color: c)
						default: put(1536, color: c)
						}
					}
					if shape == 2 {
						switch rot {
						case 3: put(0, 512, 1024, 1536, color: c)
						case 0: put(0, 1, 2, 3, color: c)
						case 1: put(3, 515, 1027, 1539, color: c)
						default: put(1536, 1537, 1538, 1539, color: c)
						}
					}
				} else {
					paintMapScene(&img, loc, x: x, z: z, rotation: rot)
				}
			}
		}
		key = scene.sceneryKey(level: level, x: x, z: z)
		if key != 0 {
			let rot = Int(Int32(truncatingIfNeeded: key)) >> 20 & 3
			let shape = Int(Int32(truncatingIfNeeded: key)) >> 14 & 0x1F
			if let loc = (try? store.loc(Self.locId(key))) ?? nil {
				if loc.mapScene == -1 {
					if shape == 9 {
						let c = key > 0 ? Self.diagonalInteractiveColor : Self.diagonalColor
						if rot == 0 || rot == 2 { put(1536, 1025, 514, 3, color: c) } else { put(0, 513, 1026, 1539, color: c) }
					}
				} else {
					paintMapScene(&img, loc, x: x, z: z, rotation: rot)
				}
			}
		}
		key = scene.groundDecorKey(level: level, x: x, z: z)
		if key != 0 {
			let rot = Int(Int32(truncatingIfNeeded: key)) >> 20 & 3
			if let loc = (try? store.loc(Self.locId(key))) ?? nil, loc.mapScene != -1 {
				paintMapScene(&img, loc, x: x, z: z, rotation: rot)
			}
		}
	}

	/// rt4 `MiniMap.renderScenery`: stamps the loc's map scene sprite (rotated with the loc) into the image.
	private func paintMapScene(_ img: inout MinimapImage, _ loc: LocType, x: Int, z: Int, rotation: Int) {
		guard let msi = msiType(loc.mapScene), msi.spriteId != -1 else { return }
		let rot = loc.mapSceneRotated ? (rotation + loc.mapSceneAngleOffset) & 3 : 0
		guard var sprite = indexedSprite(msi.spriteId, rotations: rot) else { return }
		var w = loc.width, l = loc.length
		if rot & 1 == 1 { swap(&w, &l) }
		var dw = sprite.innerWidth, dh = sprite.innerHeight
		if msi.stretch { dh = l * 4; dw = w * 4 }
		sprite.blit(into: &img.pixels, x: x * 4 + 48, y: (104 - l - z) * 4 + 48, w: dw, h: dh, tint: msi.tint)
	}
}

extension IndexedMapSprite {
	/// rt4 `SoftwareIndexedSprite.method1398` / `method1390` (tinted): blits scaled to `w` x `h` into the
	/// 512x512 minimap image, palette index 0 transparent.
	func blit(into out: inout [UInt32], x: Int, y: Int, w: Int, h: Int, tint: Int) {
		guard w > 0, h > 0 else { return }
		var x = x, y = y, w = w, h = h
		let stepX = (innerWidth << 16) / w, stepY = (innerHeight << 16) / h
		var startX = 0, startY = 0
		if xOffset > 0 {
			let d = ((xOffset << 16) + stepX - 1) / stepX
			x += d
			startX = d * stepX - (xOffset << 16)
		}
		if yOffset > 0 {
			let d = ((yOffset << 16) + stepY - 1) / stepY
			y += d
			startY = d * stepY - (yOffset << 16)
		}
		if width < innerWidth { w = ((width << 16) + stepX - startX - 1) / stepX }
		if height < innerHeight { h = ((height << 16) + stepY - startY - 1) / stepY }
		let size = MinimapImage.size
		if y + h > size { h -= y + h - size }
		if y < 0 { h += y; startY += stepY * -y; y = 0 }
		if x + w > size { w -= x + w - size }
		if x < 0 { w += x; startX += stepX * -x; x = 0 }
		guard w > 0, h > 0 else { return }
		let tr = (tint >> 16) & 0xFF, tg = (tint >> 8) & 0xFF, tb = tint & 0xFF
		var sy = startY
		for dy in 0..<h {
			let rowBase = (sy >> 16) * width
			var sx = startX
			for dx in 0..<w {
				let px = (sx >> 16) + rowBase
				if px >= 0 && px < pixels.count {
					let idx = Int(pixels[px])
					if idx != 0 {
						var c = palette[idx]
						if tint != 0 {
							let r = Int(c >> 16 & 0xFF) * tr >> 8, g = Int(c >> 8 & 0xFF) * tg >> 8, b = Int(c & 0xFF) * tb >> 8
							c = UInt32((r << 16) + (g << 8) + b)
						}
						out[(y + dy) * size + x + dx] = c
					}
				}
				sx += stepX
			}
			sy += stepY
		}
	}
}
