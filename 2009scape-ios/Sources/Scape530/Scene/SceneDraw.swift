import Foundation

/// Drawing: rt4 `SceneGraph.method2954` (camera + visibility), `method3292`
/// (tile selection and ordering), `method4245` (per-tile painter's algorithm),
/// `method2610` / `method2762` (terrain triangles) and the occlusion tests.
extension Scene {
	// rt4 anIntArray386 / 324 / 215 / 294 / 489 / 211 / 307: tables indexed by the 3x3 position of the camera relative to a tile.
	static let backWallMasks = [76, 8, 137, 4, 0, 1, 38, 2, 19]
	static let frontWallMasks = [19, 55, 38, 155, 255, 110, 137, 205, 76]
	static let cornerCullMasks = [160, 192, 80, 96, 0, 144, 80, 48, 160]
	static let waitMatch16 = [0, 0, 2, 0, 0, 2, 1, 1, 0]
	static let waitMatch32 = [2, 0, 0, 2, 0, 0, 0, 4, 4]
	static let waitMatch64 = [0, 4, 4, 8, 0, 0, 8, 0, 0]
	static let waitMatch128 = [1, 1, 0, 0, 0, 8, 0, 0, 8]

	/// Draws the scene into `r`. The caller prepares the rasteriser (clip rectangle, `prepare()`,
	/// brightness, texture source) and clears the buffer first, as rt4 does around `SceneGraph.method2954`.
	///
	/// - Parameters:
	///   - cameraX/Y/Z: camera position in fine units (Y is a height, negative is up).
	///   - pitch: 0...2047 (rt4 camera pitch, typically 128...383); yaw 0...2047.
	///   - plane: highest level to draw (3 draws everything built).
	///   - playerTile: tile whose surroundings (16 tiles) keep hidden entities animating; defaults to the camera tile.
	///   - hideMask: rt4's roof-hiding map (`[level][x][z]`): tiles at `level >= hideFromLevel` whose entry equals `hideValue` are skipped.
	public func draw(into r: Rasteriser3D, cameraX: Int, cameraY: Int, cameraZ: Int, pitch: Int, yaw: Int, plane: Int = 3,
	                 playerTile: (x: Int, z: Int)? = nil,
	                 hideMask: [[[UInt8]]]? = nil, hideFromLevel: Int = 0, hideValue: UInt8 = 0) {
		var cx = cameraX, cz = cameraZ
		if cx < 0 { cx = 0 } else if cx >= width * 128 { cx = width * 128 - 1 }
		if cz < 0 { cz = 0 } else if cz >= length * 128 { cz = length * 128 - 1 }
		sinPitch = MathTables.sin[pitch & 2047]
		cosPitch = MathTables.cos[pitch & 2047]
		sinYaw = MathTables.sin[yaw & 2047]
		cosYaw = MathTables.cos[yaw & 2047]
		self.cameraX = cx
		self.cameraY = cameraY
		self.cameraZ = cz
		cameraTileX = cx / 128
		cameraTileZ = cz / 128
		minTileX = max(0, cameraTileX - visibility)
		minTileZ = max(0, cameraTileZ - visibility)
		maxTileX = min(width, cameraTileX + visibility)
		maxTileZ = min(length, cameraTileZ + visibility)
		maxDrawLevel = plane
		self.hideMask = hideMask
		self.hideFromLevel = hideFromLevel
		self.hideValue = hideValue

		// Per-corner visibility over the (2v+2)^2 grid, then per tile as "any of its four corners".
		let v = visibility
		for i in 0..<(v * 2 + 2) {
			for j in 0..<(v * 2 + 2) {
				let dx = ((i - v) << 7) - (cx & 0x7F)
				let dz = ((j - v) << 7) - (cz & 0x7F)
				let tx = cameraTileX + i - v, tz = cameraTileZ + j - v
				if tx >= 0 && tz >= 0 && tx < width && tz < length {
					let bottom = tileHeights[0][tx][tz] + 128 - cameraY
					let top = tileHeights[3][tx][tz] - cameraY - 1000
					cornerOnScreen[i][j] = boxOnScreen(r, dx, top, bottom, dz, 3500)
				} else {
					cornerOnScreen[i][j] = false
				}
			}
		}
		for i in 0..<(v * 2 + 1) {
			for j in 0..<(v * 2 + 1) {
				tileOnScreen[i][j] = cornerOnScreen[i][j] || cornerOnScreen[i + 1][j] || cornerOnScreen[i][j + 1] || cornerOnScreen[i + 1][j + 1]
			}
		}
		selectActiveOccluders()
		drawFrame(r, playerX: playerTile?.x ?? cameraTileX, playerZ: playerTile?.z ?? cameraTileZ)
	}

	/// rt4 `SceneGraph.method3049`: does the vertical edge column at (dx, dz) between heights `top` and `bottom` reach the screen?
	func boxOnScreen(_ r: Rasteriser3D, _ dx: Int, _ top: Int, _ bottom: Int, _ dz: Int, _ maxDistance: Int) -> Bool {
		let xr = (dz * sinYaw + dx * cosYaw) >> 16
		let zr = (dz * cosYaw - dx * sinYaw) >> 16
		var z1 = (top * sinPitch + zr * cosPitch) >> 16
		let y1 = (top * cosPitch - zr * sinPitch) >> 16
		if z1 < 1 { z1 = 1 }
		let sx1 = (xr << 9) / z1
		let sy1 = (y1 << 9) / z1
		var z2 = (bottom * sinPitch + zr * cosPitch) >> 16
		let y2 = (bottom * cosPitch - zr * sinPitch) >> 16
		if z2 < 1 { z2 = 1 }
		let sx2 = (xr << 9) / z2
		let sy2 = (y2 << 9) / z2
		let lx = Int(r.screenLowerX), ux = Int(r.screenUpperX), ly = Int(r.screenLowerY), uy = Int(r.screenUpperY)
		if z1 < 50 && z2 < 50 { return false }
		if z1 > maxDistance && z2 > maxDistance { return false }
		if sx1 < lx && sx2 < lx { return false }
		if sx1 > ux && sx2 > ux { return false }
		if sy1 < ly && sy2 < ly { return false }
		return sy1 <= uy || sy2 <= uy
	}

	// MARK: - Occluders

	/// rt4 `SceneGraph.method2419`: keeps the occluders that face the camera and touch the screen, with their slopes.
	func selectActiveOccluders() {
		activeOccluders.removeAll(keepingCapacity: true)
		let v = visibility
		for o in occluders {
			switch o.type {
			case 1:
				let i = o.minTileX + v - cameraTileX
				guard i >= 0 && i <= v * 2 else { continue }
				var j = max(0, o.minTileZ + v - cameraTileZ)
				let jEnd = min(v * 2, o.maxTileZ + v - cameraTileZ)
				var seen = false
				while j <= jEnd { if tileOnScreen[i][j] { seen = true; break }; j += 1 }
				guard seen else { continue }
				var d = cameraX - o.minX
				if d > 32 { o.side = 1 } else {
					if d >= -32 { continue }
					o.side = 2
					d = -d
				}
				o.zMinSlope = ((o.minZ - cameraZ) << 8) / d
				o.zMaxSlope = ((o.maxZ - cameraZ) << 8) / d
				o.yHighSlope = ((o.yHigh - cameraY) << 8) / d
				o.yLowSlope = ((o.yLow - cameraY) << 8) / d
				activeOccluders.append(o)
			case 2:
				let i = o.minTileZ + v - cameraTileZ
				guard i >= 0 && i <= v * 2 else { continue }
				var j = max(0, o.minTileX + v - cameraTileX)
				let jEnd = min(v * 2, o.maxTileX + v - cameraTileX)
				var seen = false
				while j <= jEnd { if tileOnScreen[j][i] { seen = true; break }; j += 1 }
				guard seen else { continue }
				var d = cameraZ - o.minZ
				if d > 32 { o.side = 3 } else {
					if d >= -32 { continue }
					o.side = 4
					d = -d
				}
				o.xMinSlope = ((o.minX - cameraX) << 8) / d
				o.xMaxSlope = ((o.maxX - cameraX) << 8) / d
				o.yHighSlope = ((o.yHigh - cameraY) << 8) / d
				o.yLowSlope = ((o.yLow - cameraY) << 8) / d
				activeOccluders.append(o)
			case 4:
				let d = o.yHigh - cameraY
				guard d > 128 else { continue }
				let j0 = max(0, o.minTileZ + v - cameraTileZ)
				let j1 = min(v * 2, o.maxTileZ + v - cameraTileZ)
				guard j0 <= j1 else { continue }
				let i0 = max(0, o.minTileX + v - cameraTileX)
				let i1 = min(v * 2, o.maxTileX + v - cameraTileX)
				var seen = false
				if i0 <= i1 {
					search: for i in i0...i1 { for j in j0...j1 where tileOnScreen[i][j] { seen = true; break search } }
				}
				guard seen else { continue }
				o.side = 5
				o.xMinSlope = ((o.minX - cameraX) << 8) / d
				o.xMaxSlope = ((o.maxX - cameraX) << 8) / d
				o.zMinSlope = ((o.minZ - cameraZ) << 8) / d
				o.zMaxSlope = ((o.maxZ - cameraZ) << 8) / d
				activeOccluders.append(o)
			default:
				continue
			}
		}
	}

	/// rt4 `SceneGraph.method4394`: is the point (camera-world x, y, z) hidden behind an active occluder?
	func pointOccluded(_ x: Int, _ y: Int, _ z: Int) -> Bool {
		for o in activeOccluders {
			switch o.side {
			case 1:
				let d = o.minX - x
				if d > 0 {
					let z0 = o.minZ + ((o.zMinSlope * d) >> 8), z1 = o.maxZ + ((o.zMaxSlope * d) >> 8)
					let y0 = o.yHigh + ((o.yHighSlope * d) >> 8), y1 = o.yLow + ((o.yLowSlope * d) >> 8)
					if z >= z0 && z <= z1 && y >= y0 && y <= y1 { return true }
				}
			case 2:
				let d = x - o.minX
				if d > 0 {
					let z0 = o.minZ + ((o.zMinSlope * d) >> 8), z1 = o.maxZ + ((o.zMaxSlope * d) >> 8)
					let y0 = o.yHigh + ((o.yHighSlope * d) >> 8), y1 = o.yLow + ((o.yLowSlope * d) >> 8)
					if z >= z0 && z <= z1 && y >= y0 && y <= y1 { return true }
				}
			case 3:
				let d = o.minZ - z
				if d > 0 {
					let x0 = o.minX + ((o.xMinSlope * d) >> 8), x1 = o.maxX + ((o.xMaxSlope * d) >> 8)
					let y0 = o.yHigh + ((o.yHighSlope * d) >> 8), y1 = o.yLow + ((o.yLowSlope * d) >> 8)
					if x >= x0 && x <= x1 && y >= y0 && y <= y1 { return true }
				}
			case 4:
				let d = z - o.minZ
				if d > 0 {
					let x0 = o.minX + ((o.xMinSlope * d) >> 8), x1 = o.maxX + ((o.xMaxSlope * d) >> 8)
					let y0 = o.yHigh + ((o.yHighSlope * d) >> 8), y1 = o.yLow + ((o.yLowSlope * d) >> 8)
					if x >= x0 && x <= x1 && y >= y0 && y <= y1 { return true }
				}
			case 5:
				let d = y - o.yHigh
				if d > 0 {
					let x0 = o.minX + ((o.xMinSlope * d) >> 8), x1 = o.maxX + ((o.xMaxSlope * d) >> 8)
					let z0 = o.minZ + ((o.zMinSlope * d) >> 8), z1 = o.maxZ + ((o.zMaxSlope * d) >> 8)
					if x >= x0 && x <= x1 && z >= z0 && z <= z1 { return true }
				}
			default: break
			}
		}
		return false
	}

	/// rt4 `SceneGraph.method187`: all four corners of the tile are behind occluders (cached per frame).
	func isTileOccluded(_ level: Int, _ x: Int, _ z: Int) -> Bool {
		let cached = occlusionCache[level][x][z]
		if cached == -frame { return false }
		if cached == frame { return true }
		let px = x << 7, pz = z << 7
		let h = tileHeights[level]
		if pointOccluded(px + 1, h[x][z], pz + 1) && pointOccluded(px + 127, h[x + 1][z], pz + 1)
			&& pointOccluded(px + 127, h[x + 1][z + 1], pz + 127) && pointOccluded(px + 1, h[x][z + 1], pz + 127) {
			occlusionCache[level][x][z] = frame
			return true
		}
		occlusionCache[level][x][z] = -frame
		return false
	}

	/// rt4 `SceneGraph.method4611`: a wall decoration at height `minY` above the tile is fully hidden.
	func isWallDecorOccluded(_ level: Int, _ x: Int, _ z: Int, _ minY: Int) -> Bool {
		guard isTileOccluded(level, x, z) else { return false }
		let px = x << 7, pz = z << 7
		let h = tileHeights[level]
		return pointOccluded(px + 1, h[x][z] + minY, pz + 1) && pointOccluded(px + 127, h[x + 1][z] + minY, pz + 1)
			&& pointOccluded(px + 127, h[x + 1][z + 1] + minY, pz + 127) && pointOccluded(px + 1, h[x][z + 1] + minY, pz + 127)
	}

	/// rt4 `SceneGraph.method3850`: the wall piece `mask` of a tile is hidden.
	func isWallOccluded(_ level: Int, _ x: Int, _ z: Int, _ mask: Int) -> Bool {
		guard isTileOccluded(level, x, z) else { return false }
		let px = x << 7, pz = z << 7
		let top = tileHeights[level][x][z] - 1
		let mid = top - 120, low = top - 230, roof = top - 238
		if mask < 16 {
			switch mask {
			case 1:
				if px > cameraX {
					if !pointOccluded(px, top, pz) { return false }
					if !pointOccluded(px, top, pz + 128) { return false }
				}
				if level > 0 {
					if !pointOccluded(px, mid, pz) { return false }
					if !pointOccluded(px, mid, pz + 128) { return false }
				}
				if !pointOccluded(px, low, pz) { return false }
				return pointOccluded(px, low, pz + 128)
			case 2:
				if pz < cameraZ {
					if !pointOccluded(px, top, pz + 128) { return false }
					if !pointOccluded(px + 128, top, pz + 128) { return false }
				}
				if level > 0 {
					if !pointOccluded(px, mid, pz + 128) { return false }
					if !pointOccluded(px + 128, mid, pz + 128) { return false }
				}
				if !pointOccluded(px, low, pz + 128) { return false }
				return pointOccluded(px + 128, low, pz + 128)
			case 4:
				if px < cameraX {
					if !pointOccluded(px + 128, top, pz) { return false }
					if !pointOccluded(px + 128, top, pz + 128) { return false }
				}
				if level > 0 {
					if !pointOccluded(px + 128, mid, pz) { return false }
					if !pointOccluded(px + 128, mid, pz + 128) { return false }
				}
				if !pointOccluded(px + 128, low, pz) { return false }
				return pointOccluded(px + 128, low, pz + 128)
			case 8:
				if pz > cameraZ {
					if !pointOccluded(px, top, pz) { return false }
					if !pointOccluded(px + 128, top, pz) { return false }
				}
				if level > 0 {
					if !pointOccluded(px, mid, pz) { return false }
					if !pointOccluded(px + 128, mid, pz) { return false }
				}
				if !pointOccluded(px, low, pz) { return false }
				return pointOccluded(px + 128, low, pz)
			default: break
			}
		}
		if !pointOccluded(px + 64, roof, pz + 64) { return false }
		switch mask {
		case 16: return pointOccluded(px, low, pz + 128)
		case 32: return pointOccluded(px + 128, low, pz + 128)
		case 64: return pointOccluded(px + 128, low, pz)
		case 128: return pointOccluded(px, low, pz)
		default: return true
		}
	}

	/// rt4 `SceneGraph.method1599`: a scenery footprint (tiles xMin...xMax, zMin...zMax) with top `minY` is hidden.
	func isSceneryOccluded(_ level: Int, _ x0: Int, _ x1: Int, _ z0: Int, _ z1: Int, _ minY: Int) -> Bool {
		if x0 != x1 || z0 != z1 {
			for tx in x0...x1 { for tz in z0...z1 where occlusionCache[level][tx][tz] == -frame { return false } }
			let px0 = (x0 << 7) + 1, pz0 = (z0 << 7) + 2
			let y = tileHeights[level][x0][z0] + minY
			if !pointOccluded(px0, y, pz0) { return false }
			let px1 = (x1 << 7) - 1
			if !pointOccluded(px1, y, pz0) { return false }
			let pz1 = (z1 << 7) - 1
			if !pointOccluded(px0, y, pz1) { return false }
			return pointOccluded(px1, y, pz1)
		}
		guard isTileOccluded(level, x0, z0) else { return false }
		let px = x0 << 7, pz = z0 << 7
		let h = tileHeights[level]
		return pointOccluded(px + 1, h[x0][z0] + minY, pz + 1) && pointOccluded(px + 127, h[x0 + 1][z0] + minY, pz + 1)
			&& pointOccluded(px + 127, h[x0 + 1][z0 + 1] + minY, pz + 127) && pointOccluded(px + 1, h[x0][z0 + 1] + minY, pz + 127)
	}

	// MARK: - Frame

	/// rt4 `SceneGraph.method3292`.
	func drawFrame(_ r: Rasteriser3D, playerX: Int, playerZ: Int) {
		frame += 1
		pendingTiles = 0
		queue.reset()
		let top = min(levels, maxDrawLevel + 1)
		let nearMinX = playerX - 16, nearMaxX = playerX + 16, nearMinZ = playerZ - 16, nearMaxZ = playerZ + 16
		let v = visibility
		guard minLevel < top else { return }
		for level in minLevel..<top {
			for x in minTileX..<maxTileX {
				for z in minTileZ..<maxTileZ {
					guard let t = tiles[level][x][z] else { continue }
					let hidden = hideMask != nil && level >= hideFromLevel && hideMask![level][x][z] == hideValue
					if tileOnScreen[x + v - cameraTileX][z + v - cameraTileZ] && !hidden {
						t.pendingGround = true
						t.visible = true
						t.pendingScenery = t.sceneryCount > 0
						pendingTiles += 1
					} else {
						t.pendingGround = false
						t.visible = false
						t.wallWait = 0
						if x >= nearMinX && x <= nearMaxX && z >= nearMinZ && z <= nearMaxZ {
							if let w = t.wall {
								w.primary?.updateWhileHidden(yaw: 0, level: level, y: w.y, x: w.xFine, z: w.zFine)
								w.secondary?.updateWhileHidden(yaw: 0, level: level, y: w.y, x: w.xFine, z: w.zFine)
							}
							if let d = t.wallDecor {
								d.primary?.updateWhileHidden(yaw: d.rotation, level: level, y: d.y, x: d.xFine, z: d.zFine)
								d.secondary?.updateWhileHidden(yaw: d.rotation, level: level, y: d.y, x: d.xFine, z: d.zFine)
							}
							if let g = t.groundDecor {
								g.entity?.updateWhileHidden(yaw: 0, level: level, y: g.y, x: g.xFine, z: g.zFine)
							}
							for i in 0..<t.sceneryCount {
								if let s = t.scenery[i] { s.entity?.updateWhileHidden(yaw: s.yaw, level: level, y: s.y, x: s.xFine, z: s.zFine) }
							}
						}
					}
				}
			}
		}
		for firstPass in [true, false] {
			for level in minLevel..<top {
				for dx in -v...0 {
					let x1 = cameraTileX + dx, x2 = cameraTileX - dx
					guard x1 >= minTileX || x2 < maxTileX else { continue }
					for dz in -v...0 {
						let z1 = cameraTileZ + dz, z2 = cameraTileZ - dz
						if x1 >= minTileX {
							if z1 >= minTileZ, let t = tiles[level][x1][z1], t.pendingGround { drawTiles(r, start: t, firstPass: firstPass) }
							if z2 < maxTileZ, let t = tiles[level][x1][z2], t.pendingGround { drawTiles(r, start: t, firstPass: firstPass) }
						}
						if x2 < maxTileX {
							if z1 >= minTileZ, let t = tiles[level][x2][z1], t.pendingGround { drawTiles(r, start: t, firstPass: firstPass) }
							if z2 < maxTileZ, let t = tiles[level][x2][z2], t.pendingGround { drawTiles(r, start: t, firstPass: firstPass) }
						}
						if pendingTiles == 0 { return }
					}
				}
			}
		}
	}

	@inline(__always)
	func renderEntity(_ e: SceneEntity?, _ r: Rasteriser3D, yaw: Int, x: Int, y: Int, z: Int, key: Int64) {
		e?.render(r, yaw: yaw, sinPitch: sinPitch, cosPitch: cosPitch, sinYaw: sinYaw, cosYaw: cosYaw, x: x, y: y, z: z, key: key)
	}

	/// rt4 `SceneGraph.method4245`: paints `start` and everything that has to come after it, taking tiles
	/// off a work queue only once the tiles nearer the camera that can cover them are done.
	func drawTiles(_ r: Rasteriser3D, start: SceneTile, firstPass: Bool) {
		var firstPass = firstPass
		queue.addTail(start)
		tileLoop: while true {
			var t: SceneTile
			repeat {
				guard let head = queue.removeHead() else { return }
				t = head
			} while !t.visible
			let x = t.x, z = t.z, level = t.level, hl = t.heightLevel
			let row = tiles[level]

			if t.pendingGround {
				// Wait for nearer tiles (towards the camera) that are still pending.
				if firstPass {
					if level > 0, let below = tiles[level - 1][x][z], below.visible { continue tileLoop }
					if x <= cameraTileX && x > minTileX, let n = row[x - 1][z], n.visible, n.pendingGround || (t.allInteriorFlags & 1) == 0 { continue tileLoop }
					if x >= cameraTileX && x < maxTileX - 1, let n = row[x + 1][z], n.visible, n.pendingGround || (t.allInteriorFlags & 4) == 0 { continue tileLoop }
					if z <= cameraTileZ && z > minTileZ, let n = row[x][z - 1], n.visible, n.pendingGround || (t.allInteriorFlags & 8) == 0 { continue tileLoop }
					if z >= cameraTileZ && z < maxTileZ - 1, let n = row[x][z + 1], n.visible, n.pendingGround || (t.allInteriorFlags & 2) == 0 { continue tileLoop }
				} else {
					firstPass = true
				}
				t.pendingGround = false
				if let b = t.bridgeBelow {
					if let p = b.plainTile {
						if !isTileOccluded(0, x, z) { drawPlainTile(r, p, level: 0, x: x, z: z) }
					} else if let s = b.shapedTile {
						if !isTileOccluded(0, x, z) { drawShapedTile(r, s) }
					}
					if let w = b.wall {
						renderEntity(w.primary, r, yaw: 0, x: w.xFine - cameraX, y: w.y - cameraY, z: w.zFine - cameraZ, key: w.key)
					}
					for i in 0..<b.sceneryCount {
						if let s = b.scenery[i] {
							renderEntity(s.entity, r, yaw: s.yaw, x: s.xFine - cameraX, y: s.y - cameraY, z: s.zFine - cameraZ, key: s.key)
						}
					}
				}
				var groundDrawn = false
				if let p = t.plainTile {
					if !isTileOccluded(hl, x, z) {
						groundDrawn = true
						if p.colorNE != 12345678 { drawPlainTile(r, p, level: hl, x: x, z: z) }
					}
				} else if let s = t.shapedTile {
					if !isTileOccluded(hl, x, z) {
						groundDrawn = true
						drawShapedTile(r, s)
					}
				}
				if groundDrawn, let g = t.groundDecor, (g.key & 0x80000000) != 0 {
					renderEntity(g.entity, r, yaw: 0, x: g.xFine - cameraX, y: g.y - cameraY, z: g.zFine - cameraZ, key: g.key)
				}
				var cameraSide = 0
				var frontMask = 0
				let wall = t.wall
				let decor = t.wallDecor
				if wall != nil || decor != nil {
					if cameraTileX == x { cameraSide += 1 } else if cameraTileX < x { cameraSide += 2 }
					if cameraTileZ == z { cameraSide += 3 } else if cameraTileZ > z { cameraSide += 6 }
					frontMask = Self.frontWallMasks[cameraSide]
					t.backWalls = Self.backWallMasks[cameraSide]
				}
				if let w = wall {
					if (w.primaryMask & Self.cornerCullMasks[cameraSide]) == 0 {
						t.wallWait = 0
					} else if w.primaryMask == 16 {
						t.wallWait = 3; t.wallWaitMatch = Self.waitMatch16[cameraSide]; t.wallWaitOther = 3 - t.wallWaitMatch
					} else if w.primaryMask == 32 {
						t.wallWait = 6; t.wallWaitMatch = Self.waitMatch32[cameraSide]; t.wallWaitOther = 6 - t.wallWaitMatch
					} else if w.primaryMask == 64 {
						t.wallWait = 12; t.wallWaitMatch = Self.waitMatch64[cameraSide]; t.wallWaitOther = 12 - t.wallWaitMatch
					} else {
						t.wallWait = 9; t.wallWaitMatch = Self.waitMatch128[cameraSide]; t.wallWaitOther = 9 - t.wallWaitMatch
					}
					if (w.primaryMask & frontMask) != 0 && !isWallOccluded(hl, x, z, w.primaryMask) {
						renderEntity(w.primary, r, yaw: 0, x: w.xFine - cameraX, y: w.y - cameraY, z: w.zFine - cameraZ, key: w.key)
					}
					if (w.secondaryMask & frontMask) != 0 && !isWallOccluded(hl, x, z, w.secondaryMask) {
						renderEntity(w.secondary, r, yaw: 0, x: w.xFine - cameraX, y: w.y - cameraY, z: w.zFine - cameraZ, key: w.key)
					}
				}
				if let d = decor, let p = d.primary, !isWallDecorOccluded(hl, x, z, p.getMinY()) {
					drawWallDecor(r, d, mask: frontMask, greaterEqual: false)
				}
				if groundDrawn {
					if let g = t.groundDecor, (g.key & 0x80000000) == 0 {
						renderEntity(g.entity, r, yaw: 0, x: g.xFine - cameraX, y: g.y - cameraY, z: g.zFine - cameraZ, key: g.key)
					}
					if let o = t.objStack, o.lift == 0 {
						drawObjStack(r, o, lift: 0)
					}
				}
				let f = t.allInteriorFlags
				if f != 0 {
					if x < cameraTileX && (f & 4) != 0, let n = row[x + 1][z], n.visible { queue.addTail(n) }
					if z < cameraTileZ && (f & 2) != 0, let n = row[x][z + 1], n.visible { queue.addTail(n) }
					if x > cameraTileX && (f & 1) != 0, let n = row[x - 1][z], n.visible { queue.addTail(n) }
					if z > cameraTileZ && (f & 8) != 0, let n = row[x][z - 1], n.visible { queue.addTail(n) }
				}
			}

			// Wall corners waiting for scenery in front of them.
			if t.wallWait != 0 {
				var ready = true
				for i in 0..<t.sceneryCount {
					if let s = t.scenery[i], s.lastFrame != frame, (t.interiorFlags[i] & t.wallWait) == t.wallWaitMatch { ready = false; break }
				}
				if ready {
					if let w = t.wall, !isWallOccluded(hl, x, z, w.primaryMask) {
						renderEntity(w.primary, r, yaw: 0, x: w.xFine - cameraX, y: w.y - cameraY, z: w.zFine - cameraZ, key: w.key)
					}
					t.wallWait = 0
				}
			}

			if t.pendingScenery {
				let count = t.sceneryCount
				t.pendingScenery = false
				var n = 0
				scan: for i in 0..<count {
					guard let s = t.scenery[i], s.lastFrame != frame else { continue }
					for sx in s.xMin...s.xMax {
						for sz in s.zMin...s.zMax {
							guard let nt = row[sx][sz] else { continue }
							if nt.pendingGround { t.pendingScenery = true; continue scan }
							if nt.wallWait != 0 {
								var m = 0
								if sx > s.xMin { m += 1 }
								if sx < s.xMax { m += 4 }
								if sz > s.zMin { m += 8 }
								if sz < s.zMax { m += 2 }
								if (m & nt.wallWait) == t.wallWaitOther { t.pendingScenery = true; continue scan }
							}
						}
					}
					if n < sceneryScratch.count { sceneryScratch[n] = s; n += 1 }
					var dx = cameraTileX - s.xMin
					let dx2 = s.xMax - cameraTileX
					if dx2 > dx { dx = dx2 }
					let dz = cameraTileZ - s.zMin
					let dz2 = s.zMax - cameraTileZ
					s.sortDistance = dx + (dz2 > dz ? dz2 : dz)
				}
				while n > 0 {
					var best = -50
					var bi = -1
					for i in 0..<n {
						guard let s = sceneryScratch[i], s.lastFrame != frame else { continue }
						if s.sortDistance > best {
							best = s.sortDistance
							bi = i
						} else if s.sortDistance == best, bi >= 0, let b = sceneryScratch[bi] {
							let ax = s.xFine - cameraX, az = s.zFine - cameraZ
							let bx = b.xFine - cameraX, bz = b.zFine - cameraZ
							if ax * ax + az * az > bx * bx + bz * bz { bi = i }
						}
					}
					if bi == -1 { break }
					guard let s = sceneryScratch[bi] else { break }
					s.lastFrame = frame
					if !isSceneryOccluded(hl, s.xMin, s.xMax, s.zMin, s.zMax, s.entity?.getMinY() ?? 0) {
						renderEntity(s.entity, r, yaw: s.yaw, x: s.xFine - cameraX, y: s.y - cameraY, z: s.zFine - cameraZ, key: s.key)
					}
					for sx in s.xMin...s.xMax {
						for sz in s.zMin...s.zMax {
							guard let nt = row[sx][sz] else { continue }
							if nt.wallWait != 0 {
								queue.addTail(nt)
							} else if (sx != x || sz != z) && nt.visible {
								queue.addTail(nt)
							}
						}
					}
				}
				if t.pendingScenery { continue tileLoop }
			}

			// Not finished while something nearer the camera still has to go first.
			if !t.visible || t.wallWait != 0 { continue tileLoop }
			if x <= cameraTileX && x > minTileX, let n = row[x - 1][z], n.visible { continue tileLoop }
			if x >= cameraTileX && x < maxTileX - 1, let n = row[x + 1][z], n.visible { continue tileLoop }
			if z <= cameraTileZ && z > minTileZ, let n = row[x][z - 1], n.visible { continue tileLoop }
			if z >= cameraTileZ && z < maxTileZ - 1, let n = row[x][z + 1], n.visible { continue tileLoop }

			t.visible = false
			pendingTiles -= 1
			if let o = t.objStack, o.lift != 0 {
				drawObjStack(r, o, lift: o.lift)
			}
			if t.backWalls != 0 {
				if let d = t.wallDecor, let p = d.primary, !isWallDecorOccluded(hl, x, z, p.getMinY()) {
					drawWallDecor(r, d, mask: t.backWalls, greaterEqual: true)
				}
				if let w = t.wall {
					if (w.secondaryMask & t.backWalls) != 0 && !isWallOccluded(hl, x, z, w.secondaryMask) {
						renderEntity(w.secondary, r, yaw: 0, x: w.xFine - cameraX, y: w.y - cameraY, z: w.zFine - cameraZ, key: w.key)
					}
					if (w.primaryMask & t.backWalls) != 0 && !isWallOccluded(hl, x, z, w.primaryMask) {
						renderEntity(w.primary, r, yaw: 0, x: w.xFine - cameraX, y: w.y - cameraY, z: w.zFine - cameraZ, key: w.key)
					}
				}
			}
			if level < min(levels, maxDrawLevel + 1) - 1, let n = tiles[level + 1][x][z], n.visible { queue.addTail(n) }
			if x < cameraTileX, let n = row[x + 1][z], n.visible { queue.addTail(n) }
			if z < cameraTileZ, let n = row[x][z + 1], n.visible { queue.addTail(n) }
			if x > cameraTileX, let n = row[x - 1][z], n.visible { queue.addTail(n) }
			if z > cameraTileZ, let n = row[x][z - 1], n.visible { queue.addTail(n) }
		}
	}

	/// The wall decoration block that rt4 writes out twice (front pass with `<`, back pass with `>=`).
	private func drawWallDecor(_ r: Rasteriser3D, _ d: WallDecor, mask: Int, greaterEqual: Bool) {
		if (d.mask & mask) != 0 {
			renderEntity(d.primary, r, yaw: 0, x: d.xFine + d.xOffset - cameraX, y: d.y - cameraY, z: d.zFine + d.zOffset - cameraZ, key: d.key)
		} else if d.mask == 256 {
			let dx = d.xFine - cameraX, dy = d.y - cameraY, dz = d.zFine - cameraZ
			let rot = d.rotation
			let a = (rot == 1 || rot == 2) ? -dx : dx
			let b = (rot == 2 || rot == 3) ? -dz : dz
			let primaryFirst = greaterEqual ? b >= a : b < a
			if primaryFirst {
				renderEntity(d.primary, r, yaw: 0, x: dx + d.xOffset, y: dy, z: dz + d.zOffset, key: d.key)
			} else if d.secondary != nil {
				renderEntity(d.secondary, r, yaw: 0, x: dx, y: dy, z: dz, key: d.key)
			}
		}
	}

	private func drawObjStack(_ r: Rasteriser3D, _ o: ObjStackEntity, lift: Int) {
		let x = o.xFine - cameraX, y = o.y - cameraY - lift, z = o.zFine - cameraZ
		renderEntity(o.secondary, r, yaw: 0, x: x, y: y, z: z, key: o.key)
		renderEntity(o.tertiary, r, yaw: 0, x: x, y: y, z: z, key: o.key)
		renderEntity(o.primary, r, yaw: 0, x: x, y: y, z: z, key: o.key)
	}

	// MARK: - Terrain triangles

	/// rt4 `SceneGraph.method2610`: draws a PlainTile as two triangles.
	func drawPlainTile(_ r: Rasteriser3D, _ tile: PlainTile, level: Int, x: Int, z: Int) {
		let cxs = Int(r.centerX), cys = Int(r.centerY), w = Int(r.width)
		let h = tileHeights[level]
		let x0 = (x << 7) - cameraX, z0 = (z << 7) - cameraZ
		let x1 = x0 + 128, z1 = z0 + 128
		let y00 = h[x][z] - cameraY, y10 = h[x + 1][z] - cameraY
		let y11 = h[x + 1][z + 1] - cameraY, y01 = h[x][z + 1] - cameraY

		@inline(__always) func project(_ px: Int, _ py: Int, _ pz: Int) -> (vx: Int, vy: Int, vz: Int) {
			let xr = (pz * sinYaw + px * cosYaw) >> 16
			let zr = (pz * cosYaw - px * sinYaw) >> 16
			return (xr, (py * cosPitch - zr * sinPitch) >> 16, (py * sinPitch + zr * cosPitch) >> 16)
		}
		let a = project(x0, y00, z0)
		if a.vz < 50 { return }
		let b = project(x1, y10, z0)
		if b.vz < 50 { return }
		let c = project(x1, y11, z1)
		if c.vz < 50 { return }
		let d = project(x0, y01, z1)
		if d.vz < 50 { return }
		let sxA = cxs + (a.vx << 9) / a.vz, syA = cys + (a.vy << 9) / a.vz
		let sxB = cxs + (b.vx << 9) / b.vz, syB = cys + (b.vy << 9) / b.vz
		let sxC = cxs + (c.vx << 9) / c.vz, syC = cys + (c.vy << 9) / c.vz
		let sxD = cxs + (d.vx << 9) / d.vz, syD = cys + (d.vy << 9) / d.vz
		r.alpha = 0
		if (sxC - sxD) * (syB - syD) - (syC - syD) * (sxB - sxD) > 0 {
			r.testX = sxC < 0 || sxD < 0 || sxB < 0 || sxC > w || sxD > w || sxB > w
			if tile.texture == -1 {
				if tile.colorNE != 12345678 {
					r.fillGouraudTriangle(syC, syD, syB, sxC, sxD, sxB, tile.colorNE, tile.colorNW, tile.colorSE)
				}
			} else if tile.flat {
				r.fillTexturedTriangle(syC, syD, syB, sxC, sxD, sxB, tile.colorNE, tile.colorNW, tile.colorSE,
					a.vx, b.vx, d.vx, a.vy, b.vy, d.vy, a.vz, b.vz, d.vz, tile.texture)
			} else {
				r.fillTexturedTriangle(syC, syD, syB, sxC, sxD, sxB, tile.colorNE, tile.colorNW, tile.colorSE,
					c.vx, d.vx, b.vx, c.vy, d.vy, b.vy, c.vz, d.vz, b.vz, tile.texture)
			}
		}
		if (sxA - sxB) * (syD - syB) - (syA - syB) * (sxD - sxB) > 0 {
			r.testX = sxA < 0 || sxB < 0 || sxD < 0 || sxA > w || sxB > w || sxD > w
			if tile.texture == -1 {
				if tile.colorSW != 12345678 {
					r.fillGouraudTriangle(syA, syB, syD, sxA, sxB, sxD, tile.colorSW, tile.colorSE, tile.colorNW)
				}
			} else {
				r.fillTexturedTriangle(syA, syB, syD, sxA, sxB, sxD, tile.colorSW, tile.colorSE, tile.colorNW,
					a.vx, b.vx, d.vx, a.vy, b.vy, d.vy, a.vz, b.vz, d.vz, tile.texture)
			}
		}
	}

	/// rt4 `SceneGraph.method2762`: draws a ShapedTile's triangles.
	func drawShapedTile(_ r: Rasteriser3D, _ tile: ShapedTile) {
		let cxs = Int(r.centerX), cys = Int(r.centerY), w = Int(r.width)
		let n = tile.vertexX.count
		var sx = [Int](repeating: 0, count: n), sy = sx, vx = sx, vy = sx, vz = sx
		for i in 0..<n {
			let px = tile.vertexX[i] - cameraX
			let py = tile.vertexY[i] - cameraY
			let pz = tile.vertexZ[i] - cameraZ
			let xr = (pz * sinYaw + px * cosYaw) >> 16
			let zr = (pz * cosYaw - px * sinYaw) >> 16
			let yv = (py * cosPitch - zr * sinPitch) >> 16
			let zv = (py * sinPitch + zr * cosPitch) >> 16
			if zv < 50 { return }
			vx[i] = xr; vy[i] = yv; vz[i] = zv
			sx[i] = cxs + (xr << 9) / zv
			sy[i] = cys + (yv << 9) / zv
		}
		r.alpha = 0
		for i in 0..<tile.triA.count {
			let a = tile.triA[i], b = tile.triB[i], c = tile.triC[i]
			let xa = sx[a], xb = sx[b], xc = sx[c]
			let ya = sy[a], yb = sy[b], yc = sy[c]
			guard (xa - xb) * (yc - yb) - (ya - yb) * (xc - xb) > 0 else { continue }
			r.testX = xa < 0 || xb < 0 || xc < 0 || xa > w || xb > w || xc > w
			if let tex = tile.textures, tex[i] != -1 {
				if tile.flat {
					r.fillTexturedTriangle(ya, yb, yc, xa, xb, xc, tile.colorA[i], tile.colorB[i], tile.colorC[i],
						vx[0], vx[1], vx[3], vy[0], vy[1], vy[3], vz[0], vz[1], vz[3], tex[i])
				} else {
					r.fillTexturedTriangle(ya, yb, yc, xa, xb, xc, tile.colorA[i], tile.colorB[i], tile.colorC[i],
						vx[a], vx[b], vx[c], vy[a], vy[b], vy[c], vz[a], vz[b], vz[c], tex[i])
				}
			} else if tile.colorA[i] != 12345678 {
				r.fillGouraudTriangle(ya, yb, yc, xa, xb, xc, tile.colorA[i], tile.colorB[i], tile.colorC[i])
			}
		}
	}
}
