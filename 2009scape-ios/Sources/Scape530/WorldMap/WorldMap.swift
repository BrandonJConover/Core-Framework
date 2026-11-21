import Foundation

/// The world map (rt4 `WorldMap`, `MapList`, `Cs1ScriptRunner.method4`): a zoomable, pannable picture of a map
/// area built from the cache's world map archive (23), with map function icons, text labels and a flashing
/// highlight, shown by the interface components with client code 1400 (the map) and 1401 (the overview).
///
/// The interface scripts drive it through CS2 ops 5200-5220 (`performWorldMap`); the shell pans and zooms it with
/// `drag(dx:dy:)` and `zoom(by:)` (`GameClient.worldMapDrag` / `worldMapZoom`).
///
/// Coordinates: the map's own tiles run from `originX` (west) and from `originZ + length - 1` (north) with z
/// counted downwards, so `viewX`/`viewZ` are tiles inside the loaded area, not world coordinates.
public final class WorldMap {
	public let store: ConfigStore
	/// Current varp values, to resolve multi-locs when a map is loaded.
	public var varps: () -> [Int: Int32] = { [:] }
	/// The local player's world tile, for the starting view (nil when not in the world).
	public var playerTile: () -> (x: Int, z: Int)? = { nil }

	// MARK: map list (rt4 `MapList`)

	/// Every map of the archive.
	public private(set) lazy var maps: [WorldMapDefinition] = (try? store.worldMaps()) ?? []
	/// rt4 `MapList.aBooleanArray130`: map function icons the player switched off, by function id.
	public internal(set) lazy var hiddenFunctions: [Bool] = [Bool](repeating: false, count: functionSprites.count)
	lazy var functionSprites: [SpriteFrame] = ((try? store.sprite(named: "mapfunction")) ?? nil)?.frames ?? []

	// MARK: loaded map (rt4 `WorldMap` statics)

	public internal(set) var current: WorldMapDefinition?
	/// 0 to 100 (rt4 `loadPercentage`); `step()` advances it one stage at a time.
	public internal(set) var loadPercentage = 0
	/// Pixels per two tiles (rt4 `zoom`): 3, 4, 6, 8 and 16 are the 37, 50, 75, 100 and 200 percent levels.
	public internal(set) var zoom: Float = 8
	public internal(set) var targetZoom: Float = 8
	/// The west edge, the south edge and the size of the loaded area, in tiles (multiples of 64).
	public internal(set) var originX = 0, originZ = 0, length = 0, width = 0
	/// rt4 `anInt435` / `anInt919`: the tile in the middle of the view, from the area's west edge and north edge.
	public internal(set) var viewX = 0, viewZ = 0
	/// rt4 `anInt3482` / `anInt4901`: where the view is gliding to (-1 for nowhere).
	var goalX = -1, goalZ = -1
	/// rt4 `anInt172`, `anInt1864` and `Cs1ScriptRunner.anInt2428`: the flashing map function id, how many flashes
	/// remain and the phase (1...20).
	var flashIcon = 0, flashCount = 0, flashPhase = 20
	/// rt4 `anInt2387` / `anInt1176`: the size of the shown area in tiles; `viewLeft` / `viewTop` its corner
	/// (rt4 `Cs1ScriptRunner.anInt2882` / `anInt2884`).
	public internal(set) var viewWidthTiles = 0, viewHeightTiles = 0
	var viewLeft = 0, viewTop = 0

	var labels = WorldMapLabels()
	var elements: [WorldMapElement] = []
	var chunks = WorldMapChunks(chunksX: 0, chunksZ: 0)
	/// rt4 `overlayColors`, by overlay id + 1: 0xRRGGBB, 0 for none and -1 for "no colour".
	var overlayColors: [Int] = []
	var hiddenOverlay = 0

	/// Where the map component was drawn last, and whether one was this frame (rt4 `WorldMap.component`).
	public internal(set) var componentSize = (w: 0, h: 0)
	public internal(set) var isShown = false
	/// Whole-map picture for the 1401 overview, rebuilt when its size changes (rt4 `aClass3_Sub2_Sub1_2`).
	var overview: Raster?

	var labelFonts: [Int: WorldMapFont] = [:]
	var palette: [Int32]?
	var textures: TextureStore??
	var msiSprites: [Int: IndexedMapSprite?] = [:]
	let env = LocEnvironment()

	public init(store: ConfigStore) {
		self.store = store
	}

	// MARK: map selection

	/// The map whose group is `group` (rt4 `MapList.get`).
	public func map(group: String) -> WorldMapDefinition? {
		maps.first { $0.group.caseInsensitiveCompare(group) == .orderedSame }
	}

	/// The maps showing the tile, valid ones only (rt4 `ScriptRunner.method3333`).
	public func maps(containing x: Int, z: Int) -> [WorldMapDefinition] {
		maps.filter { $0.valid && $0.contains(x: x, z: z) }
	}

	/// rt4 `WorldMap.method1853` (CS2 `worldmap_load`): unloads the current map and starts loading `group`.
	public func load(group: String) {
		clear()
		current = maps.first { $0.group == group }
	}

	/// Starts loading the first map that shows the tile (the main map for most of the world).
	public func load(containing x: Int, z: Int) {
		if let m = maps(containing: x, z: z).first { load(group: m.group) }
	}

	/// rt4 `WorldMap.clear(false)`: drops the loaded map and its data.
	public func clear() {
		chunks = WorldMapChunks(chunksX: 0, chunksZ: 0)
		overlayColors = []
		current = nil
		loadPercentage = 0
		elements = []
		labels = WorldMapLabels()
		overview = nil
		labelFonts = [:]
		goalX = -1; goalZ = -1
		componentSize = (0, 0)
		isShown = false
	}

	/// Runs every remaining load stage at once (rt4 does one per frame, with a progress bar).
	public func loadAll() {
		var guardCount = 0
		while current != nil && loadPercentage < 100 && guardCount < 40 { step(); guardCount += 1 }
	}

	// MARK: load stages (rt4 `WorldMap.load`)

	/// One stage of loading: setup (10), underlay (20), overlay (30), overlay2 (40), locs (50), labels (60), fonts (70).
	public func step() {
		guard let map = current, loadPercentage < 100 else { return }
		switch loadPercentage {
		case 0..<10:
			loadPercentage = 10
		case 10:
			setUp(map)
			loadPercentage = 20
		case 20:
			readUnderlay(store.worldMapFile("underlay", group: map.group) ?? [])
			loadPercentage = 30
		case 30:
			readOverlay(store.worldMapFile("overlay", group: map.group) ?? [], overlay2: false)
			loadPercentage = 40
		case 40:
			readOverlay(store.worldMapFile("overlay2", group: map.group) ?? [], overlay2: true)
			loadPercentage = 50
		case 50:
			readLocs(store.worldMapFile("loc", group: map.group) ?? [])
			loadPercentage = 60
		case 60:
			let name = map.group + "_labels"
			labels = store.worldMapHasGroup(name) ? store.worldMapLabels(group: name) : WorldMapLabels()
			loadPercentage = 70
		default:
			loadFonts()
			loadPercentage = 100
		}
	}

	private func setUp(_ map: WorldMapDefinition) {
		originX = (map.minX >> 6) << 6
		originZ = (map.minZ >> 6) << 6
		length = ((map.maxZ >> 6) << 6) + 64 - originZ
		width = ((map.maxX >> 6) << 6) + 64 - originX
		let level: Float
		switch map.defaultZoom {
		case 37: level = 3
		case 50: level = 4
		case 75: level = 6
		case 100: level = 8
		case 200: level = 16
		default: level = 8
		}
		zoom = level
		targetZoom = level
		if let p = playerTile(), p.x - originX >= 0, p.x - originX < width, originZ + length - p.z - 1 >= 0, originZ + length - p.z - 1 < length {
			viewX = p.x - originX
			viewZ = originZ + length - p.z - 1
		} else {
			viewZ = originZ + length - map.originZ * 64 - 1
			viewX = map.originX * 64 - originX
		}
		clampView()
		chunks = WorldMapChunks(chunksX: width >> 6, chunksZ: length >> 6)
		env.varps = varps()
		loadOverlayColors()
	}

	/// rt4 `WorldMap.loadOverlayColors`, without rt4's random brightness jitter.
	private func loadOverlayColors() {
		let pal = hslPalette()
		let ids = ((try? store.files(archive: ConfigStore.Archive.configs, group: ConfigStore.ConfigGroup.flo))?.keys.max()) ?? -1
		overlayColors = [Int](repeating: 0, count: ids + 2)
		hiddenOverlay = 0
		guard ids >= 0 else { return }
		func rgb(_ hsl: Int) -> Int { Int(pal[hsl & 0xFFFF]) & 0xFFFFFF }
		for id in 0...ids {
			guard let flo = (try? store.flo(id)) ?? nil else { continue }
			if flo.hideUnderlay { hiddenOverlay = id }
			var texture = flo.texture
			if texture >= 0 && !textureAvailable(texture) { texture = -1 }
			let colour: Int
			if flo.secondaryRgb >= 0, flo.secondaryRgb != 0xFF00FF {
				colour = rgb(SceneColor.multiplyLightnessGrayscale(shiftedHsl(SceneColor.rgbToHsl(flo.secondaryRgb)), 96))
			} else if texture >= 0 {
				colour = rgb(SceneColor.multiplyLightnessGrayscale(textureStore()?.averageColor(texture) ?? 0, 96))
			} else if flo.rgb == 0xFF00FF {
				colour = -1
			} else {
				colour = rgb(SceneColor.multiplyLightnessGrayscale(shiftedHsl(SceneColor.rgbToHsl(flo.rgb)), 96))
			}
			overlayColors[id + 1] = colour
		}
	}

	/// An HSL16 colour with rt4's lightness and hue jitter (zero here).
	@inline(__always) func shiftedHsl(_ hsl: Int) -> Int {
		let l = min(max(hsl & 0x7F, 0), 127)
		return l + (hsl & 0x380) + (hsl & 0xFC00)
	}

	func textureStore() -> TextureStore? {
		if let t = textures { return t }
		let t = try? TextureStore(config: store)
		textures = .some(t)
		return t
	}

	func textureAvailable(_ id: Int) -> Bool { (textureStore()?.meta.count ?? 0) > id }

	/// HSL16 -> 0xRRGGBB at rt4's default brightness.
	func hslPalette() -> [Int32] {
		if let p = palette { return p }
		let p = Rasteriser3D(width: 1, height: 1).palette
		palette = p
		return p
	}

	// MARK: reading the data files

	/// rt4 `WorldMap.readUnderlay`: the ground colours, each tile blended with its 11x11 neighbourhood.
	private func readUnderlay(_ data: [UInt8]) {
		let W = width, L = length
		guard W > 0, L > 0 else { return }
		var underlays = [[UInt8]](repeating: [UInt8](repeating: 0, count: L), count: W)
		var o = 0
		while o < data.count {
			var blockX = 0, blockZ = 0, partial = false
			if data[o] == 1, o + 2 < data.count { blockX = Int(data[o + 1]); blockZ = Int(data[o + 2]); partial = true; o += 3 } else { o += 1 }
			guard o + 1 < data.count else { break }
			let cx = Int(data[o]), cz = Int(data[o + 1])
			o += 2
			let x0 = cx * 64 - originX
			let z0 = length + originZ - cz * 64 - 1
			if x0 >= 0, z0 - 63 >= 0, W > x0 + 63, L > z0 {
				for i in 0..<64 {
					for j in 0..<64 where !partial || (i >= blockX * 8 && i < blockX * 8 + 8 && j >= blockZ * 8 && j < blockZ * 8 + 8) {
						guard o < data.count else { break }
						underlays[x0 + i][z0 - j] = data[o]
						o += 1
					}
				}
			} else {
				o += partial ? 64 : 4096
			}
		}
		let pal = hslPalette()
		var flu: [Int: SceneColor.Underlay] = [:]
		func underlay(_ id: Int) -> SceneColor.Underlay {
			if let u = flu[id] { return u }
			let u = SceneColor.Underlay(rgb: ((try? store.flu(id)) ?? nil)?.rgb ?? 0)
			flu[id] = u
			return u
		}
		var rowSat = [Int](repeating: 0, count: L), rowHue = rowSat, rowLight = rowSat, rowChroma = rowSat, rowCount = rowSat
		for x in -5..<W {
			for z in 0..<L {
				if x + 5 < W {
					let id = Int(underlays[x + 5][z])
					if id > 0 {
						let u = underlay(id - 1)
						rowHue[z] += u.weightedHue; rowSat[z] += u.saturation; rowLight[z] += u.lightness; rowChroma[z] += u.chroma
						rowCount[z] += 1
					}
				}
				if x - 5 >= 0 {
					let id = Int(underlays[x - 5][z])
					if id > 0 {
						let u = underlay(id - 1)
						rowHue[z] -= u.weightedHue; rowSat[z] -= u.saturation; rowLight[z] -= u.lightness; rowChroma[z] -= u.chroma
						rowCount[z] -= 1
					}
				}
			}
			guard x >= 0 else { continue }
			var hue = 0, sat = 0, light = 0, chroma = 0, count = 0
			for z in -5..<L {
				if z + 5 < L {
					count += rowCount[z + 5]; sat += rowSat[z + 5]; light += rowLight[z + 5]; hue += rowHue[z + 5]; chroma += rowChroma[z + 5]
				}
				if z - 5 >= 0 {
					light -= rowLight[z - 5]; chroma -= rowChroma[z - 5]; hue -= rowHue[z - 5]; count -= rowCount[z - 5]; sat -= rowSat[z - 5]
				}
				guard z >= 0, count > 0 else { continue }
				let tile = ((z & 63) << 6) + (x & 63)
				if underlays[x][z] != 0 {
					let hsl = chroma == 0 ? 0 : SceneColor.blendedHsl(lightness: light / count, saturation: sat / count, hue: hue * 256 / chroma)
					if chunks.ground[x >> 6][z >> 6] == nil { chunks.ground[x >> 6][z >> 6] = [Int32](repeating: 0, count: 4096) }
					let shaded = SceneColor.multiplyLightnessSafe(96, shiftedHsl(hsl))
					chunks.ground[x >> 6][z >> 6]![tile] = pal[shaded & 0xFFFF]
				} else if chunks.ground[x >> 6][z >> 6] != nil {
					chunks.ground[x >> 6][z >> 6]![tile] = 0
				}
			}
		}
	}

	/// rt4 `WorldMap.readOverlay` / `readOverlay2`: the id and shape/rotation of the first or second overlay per tile.
	private func readOverlay(_ data: [UInt8], overlay2: Bool) {
		guard width > 0, length > 0 else { return }
		var o = 0
		while o < data.count {
			var blockX = 0, blockZ = 0, partial = false
			if data[o] == 1, o + 2 < data.count { blockX = Int(data[o + 1]); blockZ = Int(data[o + 2]); partial = true; o += 3 } else { o += 1 }
			guard o + 1 < data.count else { break }
			let cx = Int(data[o]), cz = Int(data[o + 1])
			o += 2
			let x0 = cx * 64 - originX
			let z0 = originZ + length - cz * 64 - 1
			if x0 >= 0, z0 - 63 >= 0, x0 + 63 < width, z0 < length {
				let gx = x0 >> 6, gz = z0 >> 6
				for i in 0..<64 {
					for j in 0..<64 where !partial || (i >= blockX * 8 && i < blockX * 8 + 8 && j >= blockZ * 8 && j < blockZ * 8 + 8) {
						guard o < data.count else { break }
						let id = data[o]
						o += 1
						guard id != 0, o < data.count else { continue }
						let shape = data[o]
						o += 1
						let index = i + ((63 - j) << 6)
						if overlay2 {
							if chunks.overlay2[gx][gz] == nil { chunks.overlay2[gx][gz] = [UInt8](repeating: 0, count: 4096) }
							chunks.overlay2[gx][gz]![index] = id
							if chunks.overlay2Shape[gx][gz] == nil { chunks.overlay2Shape[gx][gz] = [UInt8](repeating: 0, count: 4096) }
							chunks.overlay2Shape[gx][gz]![index] = shape
						} else {
							if chunks.overlay[gx][gz] == nil { chunks.overlay[gx][gz] = [UInt8](repeating: 0, count: 4096) }
							chunks.overlay[gx][gz]![index] = id
							if chunks.overlayShape[gx][gz] == nil { chunks.overlayShape[gx][gz] = [UInt8](repeating: 0, count: 4096) }
							chunks.overlayShape[gx][gz]![index] = shape
						}
					}
				}
			} else {
				var k = 0
				let n = partial ? 64 : 4096
				while k < n, o < data.count {
					let id = data[o]
					o += 1
					if id != 0 { o += 1 }
					k += 1
				}
			}
		}
	}

	/// rt4 `WorldMap.readLocs`: wall lines, map scenes and map function icons.
	private func readLocs(_ data: [UInt8]) {
		guard width > 0, length > 0 else { return }
		var locs: [Int: LocType?] = [:]
		func loc(_ id: Int) -> LocType? {
			if let c = locs[id] { return c }
			let l = (try? store.loc(id)) ?? nil
			locs[id] = .some(l)
			return l
		}
		var o = 0
		while o < data.count {
			var blockX = 0, blockZ = 0, partial = false
			if data[o] == 1, o + 2 < data.count { blockX = Int(data[o + 1]); blockZ = Int(data[o + 2]); partial = true; o += 3 } else { o += 1 }
			guard o + 1 < data.count else { break }
			let cx = Int(data[o]), cz = Int(data[o + 1])
			o += 2
			let x0 = cx * 64 - originX
			let z0 = originZ + length - cz * 64 - 1
			if x0 >= 0, z0 - 63 >= 0, width > x0 + 63, z0 < length {
				let gx = x0 >> 6, gz = z0 >> 6
				for i in 0..<64 {
					for j in 0..<64 where !partial || (i >= blockX * 8 && i < blockX * 8 + 8 && j >= blockZ * 8 && j < blockZ * 8 + 8) {
						guard o < data.count else { break }
						let flags = Int(data[o])
						o += 1
						guard flags != 0 else { continue }
						let index = i + ((63 - j) << 6)
						if flags & 1 != 0, o < data.count {
							if chunks.lines[gx][gz] == nil { chunks.lines[gx][gz] = [UInt8](repeating: 0, count: 4096) }
							chunks.lines[gx][gz]![index] = data[o]
							o += 1
						}
						if flags & 2 != 0, o + 2 < data.count {
							let v = Int32(data[o]) << 16 | Int32(data[o + 1]) << 8 | Int32(data[o + 2])
							o += 3
							if chunks.scenery[gx][gz] == nil { chunks.scenery[gx][gz] = [Int32](repeating: 0, count: 4096) }
							chunks.scenery[gx][gz]![index] = v
						}
						if flags & 4 != 0, o + 2 < data.count {
							let id = (Int(data[o]) << 16 | Int(data[o + 1]) << 8 | Int(data[o + 2])) - 1
							o += 3
							if chunks.icons[gx][gz] == nil { chunks.icons[gx][gz] = [Int32](repeating: 0, count: 4096) }
							guard var t = loc(id) else { continue }
							if t.multiLocs != nil {
								guard let m = env.resolve(t, store: store), m.mapFunction != -1 else { continue }
								t = m
							}
							chunks.icons[gx][gz]![index] = Int32(t.id + 1)
							elements.append(WorldMapElement(id: t.mapFunction, x: x0, z: z0))
						}
					}
				}
			} else {
				var k = 0
				let n = partial ? 64 : 4096
				while k < n, o < data.count {
					let f = data[o]
					o += 1
					if f & 1 != 0 { o += 1 }
					if f & 2 != 0 { o += 2 }
					if f & 4 != 0 { o += 3 }
					k += 1
				}
			}
		}
	}

	private func loadFonts() {
		guard labelFonts.isEmpty else { return }
		let base = ((try? store.font(named: "b12_full")) ?? nil) ?? ((try? store.font(named: "p12_full")) ?? nil)
		guard let base else { return }
		for s in [11, 12, 14, 17, 19, 22, 26, 30] { labelFonts[s] = WorldMapFont(size: s, base: base) }
	}

	// MARK: view (rt4 `method965` and friends)

	/// rt4 `WorldMap.method965`: keeps the view centre inside the area.
	func clampView() {
		if viewX < 0 { goalZ = -1; viewX = 0; goalX = -1 }
		if viewX > width { goalZ = -1; viewX = width; goalX = -1 }
		if viewZ < 0 { goalX = -1; goalZ = -1; viewZ = 0 }
		if length < viewZ { viewZ = length; goalZ = -1; goalX = -1 }
	}

	/// rt4 `WorldMap.method3616`: glides the view to a world tile, keeping the shown area inside the map.
	public func centre(onX x: Int, z: Int) {
		let halfW = Int(Float(componentSize.w) / zoom), halfH = Int(Float(componentSize.h) / zoom)
		goalX = x - originX
		let left = goalX - halfW, right = goalX + halfW
		if left < 0 { goalX = halfW }
		goalZ = length + originZ - z - 1
		let bottom = halfH + goalZ, top = goalZ - halfH
		if right > width { goalX = width - halfW }
		if top < 0 { goalZ = halfH }
		if length < bottom { goalZ = length - halfH }
	}

	/// rt4 `WorldMap.method4641` / `method1964`: sets the view centre outright.
	func setView(x: Int? = nil, z: Int? = nil) {
		goalX = -1; goalZ = -1
		if let x { viewX = x }
		if let z { viewZ = z }
		clampView()
	}

	/// rt4 `WorldMap.method2387`: centres on the point (px, py) of a component `w` x `h` pixels (the overview).
	public func centre(overviewX px: Int, y py: Int, w: Int, h: Int) {
		guard w > 0, h > 0 else { return }
		viewX = width * px / w
		viewZ = length * py / h
		goalX = -1; goalZ = -1
		clampView()
	}

	/// The world tile at the middle of the view (op 5209).
	public var centreTile: (x: Int, z: Int) { (originX + viewX, originZ + length - viewZ - 1) }

	// MARK: zoom

	static let zoomLevels: [(percent: Int, zoom: Float)] = [(37, 3), (50, 4), (75, 6), (100, 8), (200, 16)]

	/// rt4 `getTargetZoom` (op 5201): the zoom level as a percentage; the nearest level while pinching.
	public var zoomPercent: Int {
		WorldMap.zoomLevels.min { abs($0.zoom - targetZoom) < abs($1.zoom - targetZoom) }!.percent
	}

	/// rt4 `setTargetZoom` (op 5200): 37, 50, 75, 100 or 200 percent.
	public func setZoom(percent: Int) {
		goalX = -1; goalZ = -1
		if let l = WorldMap.zoomLevels.first(where: { $0.percent == percent }) { targetZoom = l.zoom }
		goalX = -1; goalZ = -1
	}

	// MARK: pan and zoom gestures

	private var dragRemainder = (x: 0.0, z: 0.0)

	/// One-finger pan inside the map: the picture follows the finger, `dx` / `dy` in game pixels since the last call
	/// (rt4 moves the centre by the finger's travel * 2 / zoom tiles).
	public func drag(dx: Double, dy: Double) {
		guard current != nil, loadPercentage == 100 else { return }
		let k = 2.0 / Double(targetZoom)
		dragRemainder.x += -dx * k
		dragRemainder.z += -dy * k
		let sx = Int(dragRemainder.x), sz = Int(dragRemainder.z)
		dragRemainder.x -= Double(sx); dragRemainder.z -= Double(sz)
		if sx != 0 { setView(x: viewX + sx) }
		if sz != 0 { setView(z: viewZ + sz) }
	}

	/// Pinch: `scale` is the change since the last call (> 1 zooms in); eases toward the new zoom like the level buttons.
	public func zoom(by scale: Double) {
		guard current != nil, scale > 0 else { return }
		goalX = -1; goalZ = -1
		targetZoom = min(max(Float(Double(targetZoom) * scale), 3), 16)
	}

	/// Snaps the zoom to the nearest level (call when the pinch ends), so the zoom buttons and label sizes match.
	public func snapZoom() {
		if let l = WorldMap.zoomLevels.min(by: { abs($0.zoom - targetZoom) < abs($1.zoom - targetZoom) }) { targetZoom = l.zoom }
	}

	// MARK: cycle

	/// One client cycle while the map is shown (rt4 `WorldMap.method447` and the flash timer): zoom eases 3% a step and
	/// the view glides toward a goal.
	public func cycle() {
		guard isShown, current != nil, loadPercentage == 100 else { return }
		if zoom < targetZoom {
			zoom = Float(Double(zoom) + Double(zoom) / 30.0)
			if targetZoom < zoom { zoom = targetZoom }
			clampView()
		} else if targetZoom < zoom {
			zoom = Float(Double(zoom) - Double(zoom) / 30.0)
			if targetZoom > zoom { zoom = targetZoom }
			clampView()
		}
		if flashCount > 0 {
			flashPhase -= 1
			if flashPhase == 0 { flashPhase = 20; flashCount -= 1 }
		}
		guard goalX != -1, goalZ != -1 else { return }
		var dx = goalX - viewX
		if dx != 2 { dx >>= 4 }
		var dz = goalZ - viewZ
		if dz != 2 { dz >>= 4 }
		viewZ += dz
		viewX += dx
		if dx == 0 && dz == 0 { goalX = -1; goalZ = -1 }
		clampView()
	}

	/// rt4 `WorldMap.method4444` (op 5202): flashes the map function `id` three times.
	public func flash(function id: Int) {
		flashIcon = id
		flashPhase = 20
		flashCount = 3
	}

	// MARK: labels (ops 5203, 5204, 5212, 5213, 5219)

	/// A label's name as the scripts see it: line breaks as spaces.
	func labelName(_ i: Int) -> String { labels.names[i].replacingOccurrences(of: "<br>", with: " ") }

	/// rt4 `method3218`: the first label whose name starts with `text` (ignoring case).
	func labelIndex(prefix text: String) -> Int? {
		guard !text.isEmpty else { return nil }
		let t = text.lowercased()
		return labels.names.indices.first { labelName($0).lowercased().hasPrefix(t) }
	}

	/// rt4 `method1879`: the label named exactly `text` (ignoring case).
	func labelIndex(exact text: String) -> Int? {
		guard !text.isEmpty else { return nil }
		return labels.names.indices.first { labelName($0).caseInsensitiveCompare(text) == .orderedSame }
	}

	/// Op 5203: glides to the first label starting with `text`.
	public func centre(onLabelPrefix text: String) {
		if let i = labelIndex(prefix: text) { centre(onX: labels.x[i], z: labels.z[i]) }
	}

	/// Op 5219: glides to the label named `text`.
	public func centre(onLabelNamed text: String) {
		if let i = labelIndex(exact: text) { centre(onX: labels.x[i], z: labels.z[i]) }
	}

	/// Op 5204: the full name of the first label starting with `text`, or "".
	public func labelName(startingWith text: String) -> String {
		labelIndex(prefix: text).map { labelName($0) } ?? ""
	}

	private var labelCursor = 0

	/// Ops 5212 / 5213: the listed labels in order. `restart` begins again.
	public func nextLabel(restart: Bool) -> (name: String, size: Int)? {
		if restart { labelCursor = 0 }
		while labelCursor < labels.count {
			let i = labelCursor
			labelCursor += 1
			if labels.isListed(i) { return (labelName(i), labels.sizeClass(i)) }
		}
		return nil
	}

	public var labelCount: Int { labels.count }
	public var iconCount: Int { elements.count }
}
