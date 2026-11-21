import Foundation

/// A rt4 `SceneGraph_Class120` occluder: a rectangle (wall, floor or roof
/// block) that hides everything behind it from the camera.
final class Occluder {
	/// rt4 `anInt4453`: 1 = wall along Z, 2 = wall along X, 4 = floor/roof.
	let type: Int
	let minTileX: Int, maxTileX: Int, minTileZ: Int, maxTileZ: Int
	let minX: Int, maxX: Int, minZ: Int, maxZ: Int
	/// rt4 `anInt4444` / `anInt4447`: the vertical extent (numerically smaller = higher).
	let yHigh: Int, yLow: Int
	/// rt4 `anInt4462`: which side faces the camera this frame (1...5).
	var side = 0
	var zMinSlope = 0, zMaxSlope = 0, yHighSlope = 0, yLowSlope = 0, xMinSlope = 0, xMaxSlope = 0

	/// rt4 `SceneGraph_Class120.method4647`.
	init(type: Int, minX: Int, maxX: Int, minZ: Int, maxZ: Int, yHigh: Int, yLow: Int) {
		self.type = type
		self.minX = minX; self.maxX = maxX; self.minZ = minZ; self.maxZ = maxZ
		minTileX = minX / 128; maxTileX = maxX / 128; minTileZ = minZ / 128; maxTileZ = maxZ / 128
		self.yHigh = yHigh; self.yLow = yLow
	}
}

/// Port of rt4 `SceneGraph` (software path): a grid of `SceneTile`s with
/// terrain, walls, decorations and scenery, drawn back to front into a
/// `Rasteriser3D`. rt4 keeps all of this in static fields; here it is one
/// object so several scenes can coexist.
///
/// Coordinates: tile `x` grows east, `z` north; heights are rt4 units
/// (negative is up), 128 fine units per tile. `tiles` and `tileHeights` are
/// indexed `[level][x][z]` (heights have one extra row and column).
///
/// Not ported: GL-only paths (`GlTile`, lighting, shadows, water), underwater
/// maps, the mouse-pick ray (`MiniMenu`), and the per-frame occluder cull
/// list (`anIntArray8`). Loc placement (`addLoc`) is for a later step; the
/// `set...` / `addScenery` calls below are what it will use.
public final class Scene {
	public let width: Int
	public let length: Int
	public let levels = 4
	/// rt4 `visibility`: draw radius in tiles (25 for the software renderer).
	public let visibility: Int
	public let store: ConfigStore
	public let textures: TextureSource?

	public var tiles: [[[SceneTile?]]]
	public var tileHeights: [[[Int]]]
	/// rt4 `renderFlags`: 1 blocked, 2 bridge, 4 roof, 8 force level 0, 16 hidden.
	public var renderFlags: [[[Int]]]
	/// rt4 `shadowmap` (software): per-tile darkening, filled by loc placement.
	public var shadowmap: [[[Int]]]
	/// rt4 `occludeFlags`: bit 1/2 wall occluder candidates, 4 flat floor; set by loc placement and terrain.
	public var occludeFlags: [[[Int]]]
	/// rt4 `centralPlane`: the player's level; only tiles that render at that level are built.
	public var centralPlane = 0
	/// rt4 `Preferences.allLevelsVisible`.
	public var allLevelsVisible = false
	/// rt4 `Preferences.manyGroundTextures`: false draws terrain textures as their average colour.
	public var manyGroundTextures = true
	/// rt4 `firstVisibleLevel`.
	public internal(set) var firstVisibleLevel = 99
	/// rt4 `anInt5276`: lowest level that is drawn.
	public internal(set) var minLevel = 0
	/// rt4 `anInt4272` / `anInt2293`: random lightness/hue wobble applied to underlays on each load (0 = none).
	public var lightnessJitter = 0
	public var hueJitter = 0

	// Occluders (rt4 aClass120Array1/2).
	var occluders: [Occluder] = []
	var activeOccluders: [Occluder] = []
	/// rt4 `scenery`: scenery added with `trackInList`, so it can be iterated for animation.
	public var sceneryList: [Scenery] = []

	// Camera state of the frame being drawn.
	var cameraX = 0, cameraY = 0, cameraZ = 0
	var sinPitch = 0, cosPitch = 0, sinYaw = 0, cosYaw = 0
	/// rt4 `anInt4069`/`anInt4539`: camera tile.
	var cameraTileX = 0, cameraTileZ = 0
	/// rt4 `LightingManager.anInt987/anInt15/anInt4698/anInt4866`: tile window around the camera.
	var minTileX = 0, maxTileX = 0, minTileZ = 0, maxTileZ = 0
	/// rt4 `anInt437`: frame counter.
	var frame = 0
	/// rt4 `anIntArrayArrayArray12`: per tile, +frame = proven visible, -frame = proven occluded.
	var occlusionCache: [[[Int]]]
	/// rt4 `anInt1142`: tiles still to finish this frame.
	var pendingTiles = 0
	/// rt4 `aBooleanArrayArray1`: per tile (relative to the camera tile) whether it can be on screen.
	var tileOnScreen: [[Bool]]
	var cornerOnScreen: [[Bool]]
	var queue = TileQueue()
	var sceneryScratch = [Scenery?](repeating: nil, count: 100)
	/// Highest level to draw (see `draw`).
	var maxDrawLevel = 3
	var hideMask: [[[UInt8]]]?
	var hideFromLevel = 0
	var hideValue: UInt8 = 0
	var roofBoxes: [RoofBox] = []

	public init(store: ConfigStore, textures: TextureSource?, width: Int = 128, length: Int = 128, visibility: Int = 25) {
		self.store = store
		self.textures = textures
		self.width = width
		self.length = length
		self.visibility = visibility
		tiles = [[[SceneTile?]]](repeating: [[SceneTile?]](repeating: [SceneTile?](repeating: nil, count: length), count: width), count: 4)
		tileHeights = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: length + 1), count: width + 1), count: 4)
		renderFlags = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: length), count: width), count: 4)
		shadowmap = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: length + 1), count: width + 1), count: 4)
		occludeFlags = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: length + 1), count: width + 1), count: 4)
		occlusionCache = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: length + 1), count: width + 1), count: 4)
		tileOnScreen = [[Bool]](repeating: [Bool](repeating: false, count: visibility * 2 + 1), count: visibility * 2 + 1)
		cornerOnScreen = [[Bool]](repeating: [Bool](repeating: false, count: visibility * 2 + 2), count: visibility * 2 + 2)
	}

	/// rt4 `SceneGraph.clear`: drops all tiles, occluders and scenery (heights and flags are kept until the next load).
	public func clear() {
		for l in 0..<levels { for x in 0..<width { for z in 0..<length { tiles[l][x][z] = nil } } }
		occluders.removeAll()
		activeOccluders.removeAll()
		sceneryList.removeAll()
		firstVisibleLevel = 99
		minLevel = 0
	}

	// MARK: - Heights

	/// rt4 `SceneGraph.getTileHeight`: interpolated terrain height at a fine position (0 outside the scene).
	public func tileHeight(level: Int, xFine: Int, zFine: Int) -> Int {
		let x = xFine >> 7, z = zFine >> 7
		if x < 0 || z < 0 || x > width - 1 || z > length - 1 { return 0 }
		let fx = xFine & 0x7F, fz = zFine & 0x7F
		var l = level
		if level < 3 && (renderFlags[1][x][z] & 2) == 2 { l = level + 1 }
		let h = tileHeights[l]
		let hz1 = (fx * h[x + 1][z + 1] + h[x][z + 1] * (128 - fx)) >> 7
		let hz0 = (fx * h[x + 1][z] + (128 - fx) * h[x][z]) >> 7
		return (fz * hz1 + (128 - fz) * hz0) >> 7
	}

	/// rt4 `SceneGraph.getRenderLevel`.
	func renderLevel(z: Int, x: Int, level: Int) -> Int {
		if (renderFlags[level][x][z] & 8) != 0 { return 0 }
		return (level <= 0 || (renderFlags[1][x][z] & 2) == 0) ? level : level - 1
	}

	/// rt4 `SceneGraph.method2750`: makes sure every tile of `level` exists (blank tiles keep scenery and the draw order working).
	func ensureTiles(level: Int) {
		for x in 0..<width {
			for z in 0..<length where tiles[level][x][z] == nil {
				tiles[level][x][z] = SceneTile(level: level, x: x, z: z)
			}
		}
	}

	/// Creates `tiles[l][x][z]` for `l` from `level` down to 0 as rt4 does before attaching anything.
	func ensureColumn(level: Int, x: Int, z: Int) {
		var l = level
		while l >= 0 {
			if tiles[l][x][z] == nil { tiles[l][x][z] = SceneTile(level: l, x: x, z: z) }
			l -= 1
		}
	}

	// MARK: - Placing entities (rt4 SceneGraph.set*/add)

	/// rt4 `SceneGraph.setGroundDecor`.
	public func setGroundDecor(level: Int, x: Int, z: Int, y: Int, entity: SceneEntity?, key: Int64, flag: Bool = false) {
		guard let entity = entity else { return }
		let d = GroundDecor()
		d.entity = entity
		d.xFine = x * 128 + 64
		d.zFine = z * 128 + 64
		d.y = y
		d.key = key
		d.flag = flag
		if tiles[level][x][z] == nil { tiles[level][x][z] = SceneTile(level: level, x: x, z: z) }
		tiles[level][x][z]?.groundDecor = d
	}

	/// rt4 `SceneGraph.setWall`.
	public func setWall(level: Int, x: Int, z: Int, y: Int, primary: SceneEntity?, secondary: SceneEntity?, primaryMask: Int, secondaryMask: Int, key: Int64) {
		if primary == nil && secondary == nil { return }
		let w = Wall()
		w.key = key
		w.xFine = x * 128 + 64
		w.zFine = z * 128 + 64
		w.y = y
		w.primary = primary
		w.secondary = secondary
		w.primaryMask = primaryMask
		w.secondaryMask = secondaryMask
		ensureColumn(level: level, x: x, z: z)
		tiles[level][x][z]?.wall = w
	}

	/// rt4 `SceneGraph.setWallDecor`.
	public func setWallDecor(level: Int, x: Int, z: Int, y: Int, primary: SceneEntity?, secondary: SceneEntity?, mask: Int, rotation: Int, xOffset: Int, zOffset: Int, key: Int64) {
		guard let primary = primary else { return }
		let d = WallDecor()
		d.key = key
		d.xFine = x * 128 + 64
		d.zFine = z * 128 + 64
		d.y = y
		d.primary = primary
		d.secondary = secondary
		d.mask = mask
		d.rotation = rotation
		d.xOffset = xOffset
		d.zOffset = zOffset
		ensureColumn(level: level, x: x, z: z)
		tiles[level][x][z]?.wallDecor = d
	}

	/// rt4 `SceneGraph.setWallDecoration`: scales an existing decoration's offsets by `scale / 16`.
	public func scaleWallDecorOffsets(level: Int, x: Int, z: Int, scale: Int) {
		guard let d = tiles[level][x][z]?.wallDecor else { return }
		d.xOffset = d.xOffset * scale / 16
		d.zOffset = d.zOffset * scale / 16
	}

	/// rt4 `SceneGraph.setObjStack`: a pile of up to three item models; `y` is the ground height.
	public func setObjStack(level: Int, x: Int, z: Int, y: Int, primary: SceneEntity?, key: Int64, secondary: SceneEntity?, tertiary: SceneEntity?) {
		let e = ObjStackEntity()
		e.primary = primary
		e.xFine = x * 128 + 64
		e.zFine = z * 128 + 64
		e.y = y
		e.key = key
		e.secondary = secondary
		e.tertiary = tertiary
		var lift = 0
		if let t = tiles[level][x][z] {
			for i in 0..<t.sceneryCount {
				if let s = t.scenery[i], (s.key & 0x400000) == 0x400000, let ent = s.entity {
					let minY = ent.getMinY()
					if minY != -32768 && minY < lift { lift = minY }
				}
			}
		}
		e.lift = -lift
		if tiles[level][x][z] == nil { tiles[level][x][z] = SceneTile(level: level, x: x, z: z) }
		tiles[level][x][z]?.objStack = e
	}

	/// rt4 `SceneGraph.add`: places a model at a fine position covering `radius` fine units around it
	/// (`extend` widens it by a tile in the direction the yaw points, as for players and npcs).
	@discardableResult
	public func add(level: Int, xFine: Int, zFine: Int, y: Int, radius: Int, entity: SceneEntity?, yaw: Int, key: Int64, extend: Bool) -> Bool {
		guard let entity = entity else { return true }
		var x0 = xFine - radius, z0 = zFine - radius, x1 = xFine + radius, z1 = zFine + radius
		if extend {
			if yaw > 640 && yaw < 1408 { z1 += 128 }
			if yaw > 1152 && yaw < 1920 { x1 += 128 }
			if yaw > 1664 || yaw < 384 { z0 -= 128 }
			if yaw > 128 && yaw < 896 { x0 -= 128 }
		}
		x0 /= 128; z0 /= 128; x1 /= 128; z1 /= 128
		return addScenery(level: level, x: x0, z: z0, sizeX: x1 + 1 - x0, sizeZ: z1 - z0 + 1, xFine: xFine, zFine: zFine, y: y, entity: entity, yaw: yaw, trackInList: true, key: key)
	}

	/// rt4 `SceneGraph.method2256`: attaches one `Scenery` to every tile in the footprint. False if
	/// outside the scene or any tile already holds five.
	@discardableResult
	public func addScenery(level: Int, x: Int, z: Int, sizeX: Int, sizeZ: Int, xFine: Int, zFine: Int, y: Int, entity: SceneEntity, yaw: Int, trackInList: Bool, key: Int64) -> Bool {
		for tx in x..<(x + sizeX) {
			for tz in z..<(z + sizeZ) {
				if tx < 0 || tz < 0 || tx >= width || tz >= length { return false }
				if let t = tiles[level][tx][tz], t.sceneryCount >= 5 { return false }
			}
		}
		let s = Scenery()
		s.key = key
		s.level = level
		s.xFine = xFine
		s.zFine = zFine
		s.y = y
		s.entity = entity
		s.yaw = yaw
		s.xMin = x
		s.zMin = z
		s.xMax = x + sizeX - 1
		s.zMax = z + sizeZ - 1
		for tx in x..<(x + sizeX) {
			for tz in z..<(z + sizeZ) {
				var flags = 0
				if tx > x { flags += 1 }
				if tx < x + sizeX - 1 { flags += 4 }
				if tz > z { flags += 8 }
				if tz < z + sizeZ - 1 { flags += 2 }
				ensureColumn(level: level, x: tx, z: tz)
				guard let t = tiles[level][tx][tz] else { continue }
				t.scenery[t.sceneryCount] = s
				t.interiorFlags[t.sceneryCount] = flags
				t.allInteriorFlags |= flags
				t.sceneryCount += 1
			}
		}
		if trackInList { sceneryList.append(s) }
		return true
	}

	// MARK: - Lookup and removal

	public func wall(level: Int, x: Int, z: Int) -> Wall? { tiles[level][x][z]?.wall }
	public func wallDecor(level: Int, x: Int, z: Int) -> WallDecor? { tiles[level][x][z]?.wallDecor }
	public func groundDecor(level: Int, x: Int, z: Int) -> GroundDecor? { tiles[level][x][z]?.groundDecor }
	public func wallKey(level: Int, x: Int, z: Int) -> Int64 { tiles[level][x][z]?.wall?.key ?? 0 }
	public func wallDecorKey(level: Int, x: Int, z: Int) -> Int64 { tiles[level][x][z]?.wallDecor?.key ?? 0 }
	public func groundDecorKey(level: Int, x: Int, z: Int) -> Int64 { tiles[level][x][z]?.groundDecor?.key ?? 0 }

	/// rt4 `SceneGraph.getScenery`: the loc-type scenery (key type 2) anchored on exactly this tile.
	public func scenery(level: Int, x: Int, z: Int) -> Scenery? {
		guard let t = tiles[level][x][z] else { return nil }
		for i in 0..<t.sceneryCount {
			if let s = t.scenery[i], ((s.key >> 29) & 3) == 2, s.xMin == x, s.zMin == z { return s }
		}
		return nil
	}

	public func sceneryKey(level: Int, x: Int, z: Int) -> Int64 { scenery(level: level, x: x, z: z)?.key ?? 0 }

	/// rt4 `SceneGraph.isLocValid`.
	public func isLocValid(level: Int, x: Int, z: Int, key: Int64) -> Bool {
		guard let t = tiles[level][x][z] else { return false }
		if t.wall?.key == key || t.wallDecor?.key == key || t.groundDecor?.key == key { return true }
		for i in 0..<t.sceneryCount where t.scenery[i]?.key == key { return true }
		return false
	}

	@discardableResult
	public func removeWall(level: Int, x: Int, z: Int) -> Wall? {
		guard let t = tiles[level][x][z] else { return nil }
		defer { t.wall = nil }
		return t.wall
	}

	@discardableResult
	public func removeWallDecor(level: Int, x: Int, z: Int) -> WallDecor? {
		guard let t = tiles[level][x][z] else { return nil }
		defer { t.wallDecor = nil }
		return t.wallDecor
	}

	@discardableResult
	public func removeGroundDecor(level: Int, x: Int, z: Int) -> GroundDecor? {
		guard let t = tiles[level][x][z] else { return nil }
		defer { t.groundDecor = nil }
		return t.groundDecor
	}

	@discardableResult
	public func removeObjStack(level: Int, x: Int, z: Int) -> ObjStackEntity? {
		guard let t = tiles[level][x][z] else { return nil }
		defer { t.objStack = nil }
		return t.objStack
	}

	@discardableResult
	public func removeScenery(level: Int, x: Int, z: Int) -> Scenery? {
		guard let s = scenery(level: level, x: x, z: z) else { return nil }
		removeScenery(s)
		return s
	}

	/// rt4 `SceneGraph.removeScenery(Scenery)`: detaches it from every tile it covers.
	public func removeScenery(_ s: Scenery) {
		for x in s.xMin...s.xMax {
			for z in s.zMin...s.zMax {
				guard let t = tiles[s.level][x][z] else { continue }
				for i in 0..<t.sceneryCount where t.scenery[i] === s {
					t.sceneryCount -= 1
					var j = i
					while j < t.sceneryCount {
						t.scenery[j] = t.scenery[j + 1]
						t.interiorFlags[j] = t.interiorFlags[j + 1]
						j += 1
					}
					t.scenery[t.sceneryCount] = nil
					break
				}
				t.allInteriorFlags = 0
				for i in 0..<t.sceneryCount { t.allInteriorFlags |= t.interiorFlags[i] }
			}
		}
		if let i = sceneryList.firstIndex(where: { $0 === s }) { sceneryList.remove(at: i) }
	}
}

/// rt4's `LinkedList` of tiles as used by the draw loop: `addTail` moves a
/// tile already queued to the back; `removeHead` pops the front.
struct TileQueue {
	private var items: [(SceneTile, Int)] = []
	private var head = 0
	private var stamp = 0

	mutating func addTail(_ t: SceneTile) {
		stamp += 1
		t.queueStamp = stamp
		t.queued = true
		items.append((t, stamp))
	}

	mutating func removeHead() -> SceneTile? {
		while head < items.count {
			let (t, s) = items[head]
			head += 1
			if t.queued && t.queueStamp == s {
				t.queued = false
				if head > 4096 && head * 2 > items.count { items.removeFirst(head); head = 0 }
				return t
			}
		}
		items.removeAll(keepingCapacity: true)
		head = 0
		return nil
	}

	mutating func reset() {
		for i in head..<items.count { items[i].0.queued = false }
		items.removeAll(keepingCapacity: true)
		head = 0
	}
}
