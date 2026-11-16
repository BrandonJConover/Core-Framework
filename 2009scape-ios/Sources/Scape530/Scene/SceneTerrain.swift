import Foundation

/// Terrain: rt4 `SceneGraph.readTile` + `method1169` (colour blending, lighting,
/// tile creation, bridges, occluders), software path only.
extension Scene {
	/// Builds terrain tiles from decoded map squares. `baseTileX/Z` is the world tile that becomes
	/// scene tile (0, 0); each square lands at `(regionX * 64 - baseTileX, regionZ * 64 - baseTileZ)`.
	/// Squares that do not fit are cropped. Replaces any previous terrain, keeps no scenery.
	public func loadMapSquares(_ squares: [MapSquare], baseTileX: Int, baseTileZ: Int, centralPlane: Int = 0, beforeBuild: ((Scene) throws -> Void)? = nil) throws {
		self.centralPlane = centralPlane
		clear()
		let W = width, L = length
		var underlays = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: L), count: W), count: 4)
		var overlays = underlays, shapes = underlays, angles = underlays
		for l in 0..<4 {
			for x in 0..<W { for z in 0..<L { renderFlags[l][x][z] = 0 } }
			for x in 0...W { for z in 0...L { tileHeights[l][x][z] = 0; shadowmap[l][x][z] = 0; occludeFlags[l][x][z] = 0 } }
		}
		// Heights: squares ascending so a square's own tile wins over its neighbour's copied edge row.
		for sq in squares.sorted(by: { ($0.regionX, $0.regionZ) < ($1.regionX, $1.regionZ) }) {
			let ox = sq.regionX * 64 - baseTileX, oz = sq.regionZ * 64 - baseTileZ
			for l in 0..<4 {
				for lx in 0...64 {
					let x = ox + lx
					if x < 0 || x > W { continue }
					for lz in 0...64 {
						let z = oz + lz
						if z < 0 || z > L { continue }
						tileHeights[l][x][z] = sq.heights[l][lx][lz]
					}
				}
				for lx in 0..<64 {
					let x = ox + lx
					if x < 0 || x >= W { continue }
					for lz in 0..<64 {
						let z = oz + lz
						if z < 0 || z >= L { continue }
						underlays[l][x][z] = sq.underlays[l][lx][lz]
						overlays[l][x][z] = sq.overlays[l][lx][lz]
						shapes[l][x][z] = sq.shapes[l][lx][lz]
						angles[l][x][z] = sq.rotations[l][lx][lz]
						renderFlags[l][x][z] = sq.flags[l][lx][lz]
					}
				}
			}
		}
		// rt4 reads the locs between the terrain read and `method1169`: they set walls, scenery,
		// shadows and occluder flags that the tile build then uses.
		try beforeBuild?(self)
		try buildTiles(underlays: underlays, overlays: overlays, shapes: shapes, angles: angles)
	}

	/// rt4 `SceneGraph.method1169` (non-GL, non-underwater).
	func buildTiles(underlays: [[[Int]]], overlays: [[[Int]]], shapes: [[[Int]]], angles: [[[Int]]]) throws {
		let W = width, L = length
		firstVisibleLevel = 99
		let hueShift = (hueJitter >> 2) << 10
		let lightShift = lightnessJitter >> 1

		// Per-id colour data.
		var fluCache: [Int: SceneColor.Underlay] = [:]
		var fluTexture: [Int: Int] = [:]
		var fluBlocks: [Int: Bool] = [:]
		func underlay(_ id: Int) throws -> SceneColor.Underlay {
			if let u = fluCache[id] { return u }
			let t = try store.flu(id)
			let u = SceneColor.Underlay(rgb: t?.rgb ?? 0)
			fluCache[id] = u
			fluTexture[id] = t?.texture ?? -1
			fluBlocks[id] = t?.blockShadow ?? true
			return u
		}
		var floCache: [Int: FloType] = [:]
		func overlay(_ id: Int) throws -> FloType {
			if let f = floCache[id] { return f }
			let f = try store.flo(id) ?? FloType(id: id)
			floCache[id] = f
			return f
		}

		for lvl in 0..<levels {
			let h = tileHeights[lvl]
			let shade = shadowmap[lvl]
			// Light map from the terrain normal (rt4 uses a fixed light direction).
			var light = [[Int]](repeating: [Int](repeating: 0, count: L + 1), count: W + 1)
			let lightLength = Int(Double(5100).squareRoot())
			let lightScale = (lightLength * 768) >> 8
			if W > 2 && L > 2 {
				for z in 1..<(L - 1) {
					for x in 1..<(W - 1) {
						let dz = h[x][z + 1] - h[x][z - 1]
						let dx = h[x + 1][z] - h[x - 1][z]
						let len = Int(Double(dx * dx + dz * dz + 65536).squareRoot())
						let nz = (dz << 8) / len
						let ny = -65536 / len
						let nx = (dx << 8) / len
						let s = (shade[x][z] >> 1) + (shade[x][z - 1] >> 2) + (shade[x + 1][z] >> 3) + (shade[x - 1][z] >> 2) + (shade[x][z + 1] >> 3)
						light[x][z] = (nz * -50 + nx * -50 + ny * -10) / lightScale + 74 - s
					}
				}
			}

			// Underlay colour blended over an 11x11 neighbourhood (two sliding-window passes).
			var rowHue = [Int](repeating: 0, count: L), rowSat = rowHue, rowLight = rowHue, rowChroma = rowHue, rowCount = rowHue
			var blended = [[Int]](repeating: [Int](repeating: 0, count: L), count: W)
			for x in -5..<W {
				for z in 0..<L {
					let addX = x + 5
					if addX < W {
						let id = underlays[lvl][addX][z]
						if id > 0 {
							let u = try underlay(id - 1)
							rowHue[z] += u.weightedHue; rowSat[z] += u.saturation
							rowLight[z] += u.lightness; rowChroma[z] += u.chroma
							rowCount[z] += 1
						}
					}
					let subX = x - 5
					if subX >= 0 {
						let id = underlays[lvl][subX][z]
						if id > 0 {
							let u = try underlay(id - 1)
							rowHue[z] -= u.weightedHue; rowSat[z] -= u.saturation
							rowLight[z] -= u.lightness; rowChroma[z] -= u.chroma
							rowCount[z] -= 1
						}
					}
				}
				if x >= 0 {
					var hue = 0, lightSum = 0, sat = 0, chroma = 0, count = 0
					for z in -5..<L {
						let addZ = z + 5
						if addZ < L {
							sat += rowSat[addZ]; count += rowCount[addZ]; hue += rowHue[addZ]
							chroma += rowChroma[addZ]; lightSum += rowLight[addZ]
						}
						let subZ = z - 5
						if subZ >= 0 {
							sat -= rowSat[subZ]; chroma -= rowChroma[subZ]; hue -= rowHue[subZ]
							count -= rowCount[subZ]; lightSum -= rowLight[subZ]
						}
						if z >= 0 && count > 0 && chroma != 0 {
							blended[x][z] = SceneColor.blendedHsl(lightness: lightSum / count, saturation: sat / count, hue: hue * 256 / chroma)
						}
					}
				}
			}

			if W > 2 && L > 2 {
				for x in 1..<(W - 1) {
					for z in 1..<(L - 1) {
						guard allLevelsVisible || (renderFlags[0][x][z] & 2) != 0
							|| ((renderFlags[lvl][x][z] & 0x10) == 0 && renderLevel(z: z, x: x, level: lvl) == centralPlane) else { continue }
						if firstVisibleLevel > lvl { firstVisibleLevel = lvl }
						let underlayId = underlays[lvl][x][z]
						let overlayId = overlays[lvl][x][z]
						if underlayId == 0 && overlayId == 0 { continue }
						let hSW = h[x][z], hSE = h[x + 1][z], hNE = h[x + 1][z + 1], hNW = h[x][z + 1]
						if lvl > 0 {
							var flat = underlayId != 0 || shapes[lvl][x][z] == 0
							if overlayId > 0, !(try overlay(overlayId - 1)).occludeUnderlay { flat = false }
							if flat && hSW == hSE && hSW == hNE && hNW == hSW { occludeFlags[lvl][x][z] |= 4 }
						}
						var underlayHsl = -1
						var minimapUnderlay = 0
						if underlayId > 0 {
							underlayHsl = blended[x][z]
							var l = (underlayHsl & 0x7F) + lightShift
							if l < 0 { l = 0 } else if l > 127 { l = 127 }
							let adjusted = (underlayHsl & 0x380) + (((underlayHsl + hueShift) & 0xFC00)) + l
							minimapUnderlay = SceneColor.multiplyLightnessSafe(96, adjusted)
						}
						let lSW = light[x][z], lNW = light[x][z + 1], lSE = light[x + 1][z], lNE = light[x + 1][z + 1]
						let uSW = SceneColor.multiplyLightnessSafe(lSW, underlayHsl)
						let uSE = SceneColor.multiplyLightnessSafe(lSE, underlayHsl)
						let uNE = SceneColor.multiplyLightnessSafe(lNE, underlayHsl)
						let uNW = SceneColor.multiplyLightnessSafe(lNW, underlayHsl)
						if overlayId == 0 {
							setTile(level: lvl, x: x, z: z, shape: 0, rotation: 0, texture: -1, heights: [hSW, hSE, hNE, hNW],
								underlay: [uSW, uSE, uNE, uNW], overlay: [0, 0, 0, 0], minimapUnderlay: minimapUnderlay, minimapOverlay: 0)
						} else {
							let shape = shapes[lvl][x][z] + 1
							let rotation = angles[lvl][x][z]
							let flo = try overlay(overlayId - 1)
							var texture = flo.texture
							if texture >= 0 && textures == nil { texture = -1 }
							var baseHsl: Int
							var minimapOverlay: Int
							if texture >= 0 {
								baseHsl = -1
								minimapOverlay = SceneColor.multiplyLightnessGrayscale(textures?.averageColor(texture) ?? 0, 96)
							} else if flo.rgb == 0xFF00FF {
								baseHsl = -2
								minimapOverlay = 0
							} else {
								baseHsl = SceneColor.rgbToHsl(flo.rgb)
								var l = lightShift + (baseHsl & 0x7F)
								if l < 0 { l = 0 } else if l > 127 { l = 127 }
								let adjusted = (baseHsl & 0x380) + (((baseHsl + hueShift) & 0xFC00) + l)
								minimapOverlay = SceneColor.multiplyLightnessGrayscale(adjusted, 96)
							}
							if flo.secondaryRgb >= 0 && flo.secondaryRgb != 0xFF00FF {
								let sec = SceneColor.rgbToHsl(flo.secondaryRgb)
								var l = lightShift + (sec & 0x7F)
								if l < 0 { l = 0 } else if l > 127 { l = 127 }
								let adjusted = (sec & 0x380) + (((sec + hueShift) & 0xFC00) + l)
								minimapOverlay = SceneColor.multiplyLightnessGrayscale(adjusted, 96)
							}
							let oSW = SceneColor.multiplyLightnessGrayscale(baseHsl, lSW)
							let oSE = SceneColor.multiplyLightnessGrayscale(baseHsl, lSE)
							let oNE = SceneColor.multiplyLightnessGrayscale(baseHsl, lNE)
							let oNW = SceneColor.multiplyLightnessGrayscale(baseHsl, lNW)
							setTile(level: lvl, x: x, z: z, shape: shape, rotation: rotation, texture: texture, heights: [hSW, hSE, hNE, hNW],
								underlay: [uSW, uSE, uNE, uNW], overlay: [oSW, oSE, oNE, oNW], minimapUnderlay: minimapUnderlay, minimapOverlay: minimapOverlay)
						}
					}
				}
			}
		}

		// Bridges: tiles on level 1 flagged 2 move to level 0, taking the old level-0 tile with them as `bridgeBelow`.
		for x in 0..<W {
			for z in 0..<L where (renderFlags[1][x][z] & 2) == 2 { shiftBridge(x: x, z: z) }
		}
		buildOccluders()
		ensureTiles(level: allLevelsVisible ? 0 : firstVisibleLevel == 99 ? 0 : firstVisibleLevel)
		minLevel = allLevelsVisible ? 0 : (firstVisibleLevel == 99 ? 0 : firstVisibleLevel)
	}

	/// rt4 `SceneGraph.setTile`.
	func setTile(level: Int, x: Int, z: Int, shape: Int, rotation: Int, texture: Int, heights h: [Int], underlay u: [Int], overlay o: [Int], minimapUnderlay: Int, minimapOverlay: Int) {
		ensureColumn(level: level, x: x, z: z)
		guard let tile = tiles[level][x][z] else { return }
		if shape == 0 {
			tile.plainTile = PlainTile(colorSW: u[0], colorSE: u[1], colorNE: u[2], colorNW: u[3], texture: -1, minimapHsl: minimapUnderlay, flat: false)
		} else if shape == 1 {
			tile.plainTile = PlainTile(colorSW: o[0], colorSE: o[1], colorNE: o[2], colorNW: o[3], texture: texture, minimapHsl: minimapOverlay,
				flat: h[0] == h[1] && h[0] == h[2] && h[0] == h[3])
		} else {
			tile.shapedTile = ShapedTile(shape: shape, rotation: rotation, texture: texture, x: x, z: z, h: h, underlay: u, overlay: o,
				underlayMinimap: minimapUnderlay, overlayMinimap: minimapOverlay)
		}
	}

	/// rt4 `SceneGraph.method3884`.
	func shiftBridge(x: Int, z: Int) {
		let below = tiles[0][x][z]
		for l in 0..<3 {
			let t = tiles[l + 1][x][z]
			tiles[l][x][z] = t
			if let t = t {
				t.level -= 1
				for i in 0..<t.sceneryCount {
					if let s = t.scenery[i], ((s.key >> 29) & 3) == 2, s.xMin == x, s.zMin == z { s.level -= 1 }
				}
			}
		}
		if tiles[0][x][z] == nil { tiles[0][x][z] = SceneTile(level: 0, x: x, z: z) }
		tiles[0][x][z]?.bridgeBelow = below
		tiles[3][x][z] = nil
	}

	/// The occluder search at the end of `method1169`: merges runs of `occludeFlags` into large rectangles.
	func buildOccluders() {
		occluders.removeAll()
		let W = width, L = length
		func add(_ type: Int, _ minX: Int, _ maxX: Int, _ minZ: Int, _ maxZ: Int, _ yHigh: Int, _ yLow: Int) {
			if occluders.count < 500 { occluders.append(Occluder(type: type, minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, yHigh: yHigh, yLow: yLow)) }
		}
		for level in 0..<4 {
			for z in 0...L {
				for x in 0...W {
					if (occludeFlags[level][x][z] & 1) != 0 {
						var hi = level
						var z0 = z
						while z0 > 0 && (occludeFlags[level][x][z0 - 1] & 1) != 0 { z0 -= 1 }
						var lo = level
						var z1 = z
						while z1 < L && (occludeFlags[level][x][z1 + 1] & 1) != 0 { z1 += 1 }
						down: while lo > 0 {
							for zz in z0...z1 where (occludeFlags[lo - 1][x][zz] & 1) == 0 { break down }
							lo -= 1
						}
						up: while hi < 3 {
							for zz in z0...z1 where (occludeFlags[hi + 1][x][zz] & 1) == 0 { break up }
							hi += 1
						}
						if (hi + 1 - lo) * (z1 - z0 + 1) >= 8 {
							let yHigh = tileHeights[hi][x][z0] - 240
							let yLow = tileHeights[lo][x][z0]
							add(1, x * 128, x * 128, z0 * 128, z1 * 128 + 128, yHigh, yLow)
							for l in lo...hi { for zz in z0...z1 { occludeFlags[l][x][zz] &= ~1 } }
						}
					}
					if (occludeFlags[level][x][z] & 2) != 0 {
						var x0 = x
						while x0 > 0 && (occludeFlags[level][x0 - 1][z] & 2) != 0 { x0 -= 1 }
						var lo = level, hi = level
						var x1 = x
						while x1 < W && (occludeFlags[level][x1 + 1][z] & 2) != 0 { x1 += 1 }
						down: while lo > 0 {
							for xx in x0...x1 where (occludeFlags[lo - 1][xx][z] & 2) == 0 { break down }
							lo -= 1
						}
						up: while hi < 3 {
							for xx in x0...x1 where (occludeFlags[hi + 1][xx][z] & 2) == 0 { break up }
							hi += 1
						}
						if (x1 + 1 - x0) * (hi - lo + 1) >= 8 {
							let yHigh = tileHeights[hi][x0][z] - 240
							let yLow = tileHeights[lo][x0][z]
							add(2, x0 * 128, x1 * 128 + 128, z * 128, z * 128, yHigh, yLow)
							for l in lo...hi { for xx in x0...x1 { occludeFlags[l][xx][z] &= ~2 } }
						}
					}
					if (occludeFlags[level][x][z] & 4) != 0 {
						var x0 = x, x1 = x
						var z0 = z
						while z0 > 0 && (occludeFlags[level][x][z0 - 1] & 4) != 0 { z0 -= 1 }
						var z1 = z
						while z1 < L && (occludeFlags[level][x][z1 + 1] & 4) != 0 { z1 += 1 }
						left: while x0 > 0 {
							for zz in z0...z1 where (occludeFlags[level][x0 - 1][zz] & 4) == 0 { break left }
							x0 -= 1
						}
						right: while x1 < W {
							for zz in z0...z1 where (occludeFlags[level][x1 + 1][zz] & 4) == 0 { break right }
							x1 += 1
						}
						if (x1 + 1 - x0) * (z1 - (z0 - 1)) >= 4 {
							let y = tileHeights[level][x0][z0]
							add(4, x0 * 128, x1 * 128 + 128, z0 * 128, z1 * 128 + 128, y, y)
							for xx in x0...x1 { for zz in z0...z1 { occludeFlags[level][xx][zz] &= ~4 } }
						}
					}
				}
			}
		}
	}
}
