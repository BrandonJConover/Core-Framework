import Foundation

/// What `LocPlacer.addLoc` placed, for the collision map to flag (rt4 calls
/// `CollisionMap.flagWall/flagScenery/flagGroundDecor` inline from `addLoc`).
public struct LocPlacement {
	public var loc: LocType
	public var shape: Int
	public var rotation: Int
	/// Scene tile of the loc's south-west corner and the level it was placed on.
	public var x: Int, z: Int, level: Int
	/// Footprint after the rotation swap (rt4 `width`/`length` in `addLoc`).
	public var width: Int, length: Int
}

/// rt4 per-loc state shared by `Loc` entities: the cycle counter and the
/// variable lookup that resolves multi-locs (`LocType.getMultiLoc`).
///
/// A scene can be built on a background thread while the frame thread keeps updating the cycle counter and
/// variables, so both are guarded by a lock.
public final class LocEnvironment {
	private let lock = NSLock()
	private var _loop = 0
	private var _varps: [Int: Int32] = [:]
	/// rt4 `client.loop`.
	public var loop: Int {
		get { lock.lock(); defer { lock.unlock() }; return _loop }
		set { lock.lock(); _loop = newValue; lock.unlock() }
	}
	public var varps: [Int: Int32] {
		get { lock.lock(); defer { lock.unlock() }; return _varps }
		set { lock.lock(); _varps = newValue; lock.unlock() }
	}
	public init() {}

	/// rt4 `VarpDomain.getVarbit` / `activeVarps`: the value that selects a multi-loc/npc variant.
	public func value(varbit: Int, varp: Int, store: ConfigStore) -> Int {
		if varbit != -1 {
			guard let v = try? store.varbit(varbit) else { return -1 }
			return Int(v.value(in: varps[v.varp] ?? 0))
		}
		if varp != -1 { return Int(varps[varp] ?? 0) }
		return -1
	}

	/// rt4 `LocType.getMultiLoc`: nil when the variant is "none".
	public func resolve(_ loc: LocType, store: ConfigStore) -> LocType? {
		guard let list = loc.multiLocs, !list.isEmpty else { return loc }
		let v = value(varbit: loc.multiVarbit, varp: loc.multiVarp, store: store)
		let id: Int
		if v < 0 || v >= list.count - 1 || list[v] == -1 { id = list[list.count - 1] } else { id = list[v] }
		return id == -1 ? nil : (try? store.loc(id)) ?? nil
	}
}

/// rt4 `Loc` (client!dc): a scenery entity that animates and/or switches
/// between variants with a varbit. Static locs use a plain `SoftwareModel`.
public final class DynamicLoc: SceneEntity {
	let env: LocEnvironment
	/// Weak: the scene owns this entity.
	weak var scene: Scene?
	let store: ConfigStore
	let builder: LocModelBuilder
	let locId: Int, shape: Int, rotation: Int, level: Int, x: Int, z: Int
	/// rt4 `aClass144_2`, `anInt1297`, `anInt1304`, `anInt1317`, `anInt1320`.
	var seq: SeqType?
	var frame = 0, nextFrame = 0, step = 0, startLoop = 0
	/// rt4 `aBoolean80`: a multi-loc whose animation follows the resolved variant.
	var followsVariant = false

	init(env: LocEnvironment, scene: Scene, store: ConfigStore, builder: LocModelBuilder, locId: Int, shape: Int, rotation: Int, level: Int, x: Int, z: Int, seqId: Int, randomise: Bool) {
		self.env = env; self.scene = scene; self.store = store; self.builder = builder
		self.locId = locId; self.shape = shape; self.rotation = rotation; self.level = level; self.x = x; self.z = z
		if seqId != -1, let s = try? store.seq(seqId) {
			seq = s
			frame = 0
			nextFrame = s.frames.count <= 1 ? 0 : 1
			step = 1
			startLoop = env.loop - 1
			if randomise && s.replayOffset != -1 && !s.frames.isEmpty {
				frame = Int.random(in: 0..<s.frames.count)
				nextFrame = frame + 1
				if nextFrame >= s.frames.count {
					nextFrame -= s.replayOffset
					if nextFrame < 0 || nextFrame >= s.frames.count { nextFrame = -1 }
				}
				step = Int.random(in: 0..<max(1, s.frameDelays[frame])) + 1
				startLoop = env.loop - step
			}
		}
		if let l = try? store.loc(locId), l.multiLocs != nil { followsVariant = true }
	}

	public func getMinY() -> Int { -32768 }

	public func updateWhileHidden(yaw: Int, level: Int, y: Int, x: Int, z: Int) { advance() }

	/// rt4 `Loc.method1047`: catches the animation up to `client.loop`.
	func advance() {
		guard let s = seq, !s.frames.isEmpty else { return }
		var elapsed = env.loop - startLoop
		let n = s.frames.count
		if elapsed > 100 && s.replayOffset > 0 {
			let limit = n - s.replayOffset
			while frame < limit && s.frameDelays[frame] < elapsed {
				elapsed -= s.frameDelays[frame]
				frame += 1
			}
			if frame >= limit {
				var total = 0
				for i in limit..<n { total += s.frameDelays[i] }
				if total > 0 { elapsed %= total }
			}
			nextFrame = frame + 1
			if nextFrame >= n {
				nextFrame -= s.replayOffset
				if nextFrame < 0 || nextFrame >= n { nextFrame = -1 }
			}
		}
		while frame < n && elapsed > s.frameDelays[frame] {
			elapsed -= s.frameDelays[frame]
			frame += 1
			if n <= frame {
				frame -= s.replayOffset
				if frame < 0 || n <= frame { seq = nil; break }
			}
			nextFrame = frame + 1
			if n <= nextFrame {
				nextFrame -= s.replayOffset
				if nextFrame < 0 || nextFrame >= n { nextFrame = -1 }
			}
		}
		step = elapsed
		startLoop = env.loop - elapsed
	}

	/// rt4 `Loc.method1048` (software path): the model for this cycle.
	func currentModel() -> SoftwareModel? {
		guard var type = (try? store.loc(locId)) ?? nil else { return nil }
		let baseAnim = type.anim
		if type.multiLocs != nil {
			guard let t = env.resolve(type, store: store) else { return nil }
			type = t
		}
		if followsVariant && (seq == nil || seq?.id != type.anim) {
			let id = type.anim == -1 ? baseAnim : type.anim
			seq = id == -1 ? nil : ((try? store.seq(id)) ?? nil)
			if let s = seq, !s.frames.isEmpty {
				if type.allowRandomizedAnimation && s.replayOffset != -1 {
					frame = Int.random(in: 0..<s.frames.count)
					startLoop -= Int.random(in: 0..<max(1, s.frameDelays[frame]))
				} else {
					frame = 0
					startLoop = env.loop - 1
				}
			}
		}
		let r = rotation & 3
		let w = (r == 1 || r == 3) ? type.length : type.width
		let l = (r == 1 || r == 3) ? type.width : type.length
		let east = x + ((w + 1) >> 1), west = x + (w >> 1)
		let north = z + ((l + 1) >> 1), south = z + (l >> 1)
		advance()
		guard let scene = scene else { return nil }
		let h = scene.tileHeights[level]
		let baseY = (h[east][north] + h[west][north] + h[west][south] + h[east][south]) >> 2
		let terrain = LocTerrain(heights: h, upper: level < 3 ? scene.tileHeights[level + 1] : nil, x: (w << 6) + (x << 7), baseY: baseY, z: (l << 6) + (z << 7))
		do {
			guard let s = seq, !s.frames.isEmpty else {
				return try builder.model(for: type, shape: shape, rotation: rotation, terrain: terrain)
			}
			guard let base = try builder.animatedBase(for: type, shape: shape, rotation: rotation, terrain: terrain) else { return nil }
			return try SoftwareModel.posed(base, store: store, action: SeqPose(seq: s, frame: frame, nextFrame: nextFrame, step: step), movement: nil)
		} catch {
			return nil
		}
	}

	public func render(_ r: Rasteriser3D, yaw: Int, sinPitch: Int, cosPitch: Int, sinYaw: Int, cosYaw: Int, x: Int, y: Int, z: Int, key: Int64) {
		currentModel()?.render(r, yaw: yaw, sinPitch: sinPitch, cosPitch: cosPitch, sinYaw: sinYaw, cosYaw: cosYaw, x: x, y: y, z: z, key: key)
	}
}

/// Port of rt4 `SceneGraph.addLoc` (software path, `lowmem` loading): places
/// one map loc into a `Scene` as a wall, wall decoration, scenery, roof or
/// ground decoration with rt4's heights, keys, shadow and occluder flags.
public final class LocPlacer {
	public let scene: Scene
	public let store: ConfigStore
	public let builder: LocModelBuilder
	public let env: LocEnvironment
	/// Called after each loc is placed (collision flagging hooks in here).
	public var onPlaced: ((LocPlacement) -> Void)?

	static let wallRotation = [1, 2, 4, 8]
	static let cornerRotation = [16, 32, 64, 128]
	static let decorX = [1, 0, -1, 0], decorZ = [0, -1, 0, 1]
	static let diagX = [1, -1, -1, 1], diagZ = [-1, -1, 1, 1]

	public init(scene: Scene, store: ConfigStore, builder: LocModelBuilder, env: LocEnvironment) {
		self.scene = scene; self.store = store; self.builder = builder; self.env = env
	}

	/// rt4 `SceneGraph.addLoc(currentPlane, lowmem, plane, highmem, map, locIndex, locType, x, z, orientation)`
	/// with `currentPlane == plane`, `lowmem = true`, `highmem = false` as `readLocs` calls it.
	public func addLoc(plane: Int, locIndex: Int, shape locType: Int, x: Int, z: Int, orientation: Int) throws {
		let lowmem = true
		if lowmem && !scene.allLevelsVisible && (scene.renderFlags[0][x][z] & 0x2) == 0 {
			if (scene.renderFlags[plane][x][z] & 0x10) != 0 || scene.renderLevel(z: z, x: x, level: plane) != scene.centralPlane { return }
		}
		if plane < scene.firstVisibleLevel { scene.firstVisibleLevel = plane }
		guard let loc = try store.loc(locIndex) else { return }

		let width: Int, length: Int
		if orientation == 1 || orientation == 3 { length = loc.width; width = loc.length } else { width = loc.width; length = loc.length }
		let west: Int, east: Int
		if x + width <= scene.width { west = x + (width >> 1); east = x + ((width + 1) >> 1) } else { east = x + 1; west = x }
		let south: Int, north: Int
		if length + z > scene.length { south = z; north = z + 1 } else { south = (length >> 1) + z; north = z + ((length + 1) >> 1) }

		let heights = scene.tileHeights[plane]
		let fineX = (width << 6) + (x << 7)
		let fineZ = (length << 6) + (z << 7)
		let averageY = (heights[west][north] + heights[east][south] + heights[west][south] + heights[east][north]) >> 2
		let upper: [[Int]]? = plane < 3 ? scene.tileHeights[plane + 1] : nil

		var bitset = Int64(x) | 0x4000_0000 | (Int64(z) << 7) | (Int64(locType) << 14) | (Int64(orientation) << 20)
		if loc.interactable == 0 { bitset |= Int64.min }
		if loc.supportItems == 1 { bitset |= 0x40_0000 }
		// rt4 ORs `Integer.MIN_VALUE` (sign-extending over the id bits that follow); the flag bit alone is meant.
		if loc.hasAnimation { bitset |= 0x8000_0000 }
		bitset |= Int64(locIndex) << 32
		let castShadow = loc.castShadow

		let animated = loc.anim != -1 || loc.multiLocs != nil
		func entity(_ shape: Int, _ rotation: Int) throws -> SceneEntity? {
			if animated {
				return DynamicLoc(env: env, scene: scene, store: store, builder: builder, locId: locIndex, shape: shape, rotation: rotation, level: plane, x: x, z: z, seqId: loc.anim, randomise: loc.allowRandomizedAnimation)
			}
			let terrain = LocTerrain(heights: heights, upper: upper, x: fineX, baseY: averageY, z: fineZ)
			return try builder.model(for: loc, shape: shape, rotation: rotation, terrain: terrain)
		}
		_ = castShadow
		let placement = LocPlacement(loc: loc, shape: locType, rotation: orientation, x: x, z: z, level: plane, width: width, length: length)
		defer { onPlaced?(placement) }

		if locType == 22 {
			if loc.interactable != 0 || loc.blockWalk == 1 || loc.forceDecor {
				let e = try entity(22, orientation)
				scene.setGroundDecor(level: plane, x: x, z: z, y: averageY, entity: e, key: bitset, flag: loc.flags90and98.0)
			}
		} else if locType == 10 || locType == 11 {
			let e = try entity(10, locType == 11 ? orientation + 4 : orientation)
			if let e = e {
				let ok = scene.addScenery(level: plane, x: x, z: z, sizeX: width, sizeZ: length, xFine: x * 128 + width * 64, zFine: z * 128 + length * 64, y: averageY, entity: e, yaw: 0, trackInList: false, key: bitset)
				if loc.active && ok && lowmem {
					var amount = 15
					if let m = e as? SoftwareModel { m.ensureBounds(); amount = min(30, m.lengthXZ / 4) }
					for dx in 0...width {
						for dz in 0...length where x + dx <= scene.width && z + dz <= scene.length {
							if scene.shadowmap[plane][x + dx][z + dz] < amount { scene.shadowmap[plane][x + dx][z + dz] = amount }
						}
					}
				}
			}
		} else if locType >= 12 {
			let e = try entity(locType, orientation)
			addSingle(plane, x, z, averageY, e, bitset)
			if lowmem && locType <= 17 && locType != 13 && plane > 0 { scene.occludeFlags[plane][x][z] |= 4 }
		} else if locType == 0 {
			let e = try entity(0, orientation)
			scene.setWall(level: plane, x: x, z: z, y: averageY, primary: e, secondary: nil, primaryMask: Self.wallRotation[orientation], secondaryMask: 0, key: bitset)
			switch orientation {
			case 0:
				if loc.active { scene.shadowmap[plane][x][z] = 50; scene.shadowmap[plane][x][z + 1] = 50 }
				if loc.occlude { scene.occludeFlags[plane][x][z] |= 1 }
			case 1:
				if loc.active { scene.shadowmap[plane][x][z + 1] = 50; scene.shadowmap[plane][x + 1][z + 1] = 50 }
				if loc.occlude { scene.occludeFlags[plane][x][z + 1] |= 2 }
			case 2:
				if loc.active { scene.shadowmap[plane][x + 1][z] = 50; scene.shadowmap[plane][x + 1][z + 1] = 50 }
				if loc.occlude { scene.occludeFlags[plane][x + 1][z] |= 1 }
			default:
				if loc.active { scene.shadowmap[plane][x][z] = 50; scene.shadowmap[plane][x + 1][z] = 50 }
				if loc.occlude { scene.occludeFlags[plane][x][z] |= 2 }
			}
			if loc.wallOffset != 16 { scene.scaleWallDecorOffsets(level: plane, x: x, z: z, scale: loc.wallOffset) }
		} else if locType == 1 {
			let e = try entity(1, orientation)
			scene.setWall(level: plane, x: x, z: z, y: averageY, primary: e, secondary: nil, primaryMask: Self.cornerRotation[orientation], secondaryMask: 0, key: bitset)
			if loc.active {
				switch orientation {
				case 0: scene.shadowmap[plane][x][z + 1] = 50
				case 1: scene.shadowmap[plane][x + 1][z + 1] = 50
				case 2: scene.shadowmap[plane][x + 1][z] = 50
				default: scene.shadowmap[plane][x][z] = 50
				}
			}
		} else if locType == 2 {
			let next = (orientation + 1) & 3
			let a = try entity(2, orientation + 4)
			let b = try entity(2, next)
			scene.setWall(level: plane, x: x, z: z, y: averageY, primary: a, secondary: b, primaryMask: Self.wallRotation[orientation], secondaryMask: Self.wallRotation[next], key: bitset)
			if loc.occlude {
				switch orientation {
				case 0: scene.occludeFlags[plane][x][z] |= 1; scene.occludeFlags[plane][x][z + 1] |= 2
				case 1: scene.occludeFlags[plane][x][z + 1] |= 2; scene.occludeFlags[plane][x + 1][z] |= 1
				case 2: scene.occludeFlags[plane][x + 1][z] |= 1; scene.occludeFlags[plane][x][z] |= 2
				default: scene.occludeFlags[plane][x][z] |= 2; scene.occludeFlags[plane][x][z] |= 1
				}
			}
			if loc.wallOffset != 16 { scene.scaleWallDecorOffsets(level: plane, x: x, z: z, scale: loc.wallOffset) }
		} else if locType == 3 {
			let e = try entity(3, orientation)
			scene.setWall(level: plane, x: x, z: z, y: averageY, primary: e, secondary: nil, primaryMask: Self.cornerRotation[orientation], secondaryMask: 0, key: bitset)
			if loc.active {
				switch orientation {
				case 0: scene.shadowmap[plane][x][z + 1] = 50
				case 1: scene.shadowmap[plane][x + 1][z + 1] = 50
				case 2: scene.shadowmap[plane][x + 1][z] = 50
				default: scene.shadowmap[plane][x][z] = 50
				}
			}
		} else if locType == 9 {
			let e = try entity(9, orientation)
			addSingle(plane, x, z, averageY, e, bitset)
			if loc.wallOffset != 16 { scene.scaleWallDecorOffsets(level: plane, x: x, z: z, scale: loc.wallOffset) }
		} else if locType == 4 {
			let e = try entity(4, orientation)
			scene.setWallDecor(level: plane, x: x, z: z, y: averageY, primary: e, secondary: nil, mask: Self.wallRotation[orientation], rotation: 0, xOffset: 0, zOffset: 0, key: bitset)
		} else if locType == 5 {
			var off = 16
			let k = scene.wallKey(level: plane, x: x, z: z)
			if k != 0, let w = try store.loc(Int(truncatingIfNeeded: k >> 32) & Int(Int32.max)) { off = w.wallOffset }
			let e = try entity(4, orientation)
			scene.setWallDecor(level: plane, x: x, z: z, y: averageY, primary: e, secondary: nil, mask: Self.wallRotation[orientation], rotation: 0, xOffset: off * Self.decorX[orientation], zOffset: Self.decorZ[orientation] * off, key: bitset)
		} else if locType == 6 {
			var off = 8
			let k = scene.wallKey(level: plane, x: x, z: z)
			if k != 0, let w = try store.loc(Int(truncatingIfNeeded: k >> 32) & Int(Int32.max)) { off = w.wallOffset / 2 }
			let e = try entity(4, orientation + 4)
			scene.setWallDecor(level: plane, x: x, z: z, y: averageY, primary: e, secondary: nil, mask: 256, rotation: orientation, xOffset: off * Self.diagX[orientation], zOffset: off * Self.diagZ[orientation], key: bitset)
		} else if locType == 7 {
			let r = (orientation + 2) & 3
			let e = try entity(4, r + 4)
			scene.setWallDecor(level: plane, x: x, z: z, y: averageY, primary: e, secondary: nil, mask: 256, rotation: r, xOffset: 0, zOffset: 0, key: bitset)
		} else if locType == 8 {
			var off = 8
			let k = scene.wallKey(level: plane, x: x, z: z)
			if k != 0, let w = try store.loc(Int(truncatingIfNeeded: k >> 32) & Int(Int32.max)) { off = w.wallOffset / 2 }
			let r = (orientation + 2) & 3
			let a = try entity(4, orientation + 4)
			let b = try entity(4, r + 4)
			scene.setWallDecor(level: plane, x: x, z: z, y: averageY, primary: a, secondary: b, mask: 256, rotation: orientation, xOffset: off * Self.diagX[orientation], zOffset: Self.diagZ[orientation] * off, key: bitset)
		}
	}

	/// rt4 `SceneGraph.method35`: a 1x1 scenery entry.
	private func addSingle(_ plane: Int, _ x: Int, _ z: Int, _ y: Int, _ e: SceneEntity?, _ key: Int64) {
		guard let e = e else { return }
		scene.addScenery(level: plane, x: x, z: z, sizeX: 1, sizeZ: 1, xFine: x * 128 + 64, zFine: z * 128 + 64, y: y, entity: e, yaw: 0, trackInList: false, key: key)
	}
}
