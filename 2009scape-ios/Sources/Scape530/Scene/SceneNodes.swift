/// What the scene graph needs from anything it draws. Mirrors rt4 `Entity`
/// (client!th): `render` is `Entity.render` without the particle argument
/// and `getMinY` is `Entity.getMinY`.
public protocol SceneEntity: AnyObject {
	/// rt4 `Entity.render(yaw, sinPitch, cosPitch, sinYaw, cosYaw, x, y, z, key, level, particles)`.
	/// `x/y/z` are camera-relative (the scene has already subtracted the camera).
	func render(_ r: Rasteriser3D, yaw: Int, sinPitch: Int, cosPitch: Int, sinYaw: Int, cosYaw: Int, x: Int, y: Int, z: Int, key: Int64)

	/// rt4 `Entity.getMinY`: lowest model Y (negative = up), or -32768 when unknown.
	/// Used for occlusion tests of tall scenery and wall decorations.
	func getMinY() -> Int

	/// rt4 `Entity.method4545`: called every frame for entities on tiles that
	/// are near the player but not visible, so animations keep advancing.
	func updateWhileHidden(yaw: Int, level: Int, y: Int, x: Int, z: Int)
}

extension SceneEntity {
	public func getMinY() -> Int { -32768 }
	public func updateWhileHidden(yaw: Int, level: Int, y: Int, x: Int, z: Int) {}
}

/// rt4 `PlainTile` (client!rh): a flat-shaded or textured quad split into two
/// triangles. Colours are HSL16 (or `12345678` for "do not draw").
public final class PlainTile {
	/// rt4 `anInt4872`: lit colour at (x, z).
	public let colorSW: Int
	/// rt4 `anInt4867`: colour at (x+1, z).
	public let colorSE: Int
	/// rt4 `anInt4865`: colour at (x+1, z+1).
	public let colorNE: Int
	/// rt4 `anInt4864`: colour at (x, z+1).
	public let colorNW: Int
	/// rt4 `anInt4869`: texture id or -1.
	public let texture: Int
	/// rt4 `anInt4871`: HSL16 underlay colour used for the minimap (rt4 stores its palette RGB).
	public let minimapHsl: Int
	/// rt4 `aBoolean241`: all four corners at the same height (selects texture mapping order).
	public let flat: Bool

	public init(colorSW: Int, colorSE: Int, colorNE: Int, colorNW: Int, texture: Int, minimapHsl: Int, flat: Bool) {
		self.colorSW = colorSW; self.colorSE = colorSE; self.colorNE = colorNE; self.colorNW = colorNW
		self.texture = texture; self.minimapHsl = minimapHsl; self.flat = flat
	}
}

/// rt4 `Wall` (client!jh).
public final class Wall {
	public var xFine = 0
	public var zFine = 0
	/// rt4 `anInt3051`: Y.
	public var y = 0
	public var primary: SceneEntity?
	public var secondary: SceneEntity?
	/// rt4 `anInt3049` / `anInt3052`: orientation bit masks (1,2,4,8 sides; 16...128 corners).
	public var primaryMask = 0
	public var secondaryMask = 0
	public var key: Int64 = 0
	public init() {}
}

/// rt4 `WallDecor` (client!df).
public final class WallDecor {
	public var xFine = 0
	public var zFine = 0
	/// rt4 `anInt1391`: Y.
	public var y = 0
	public var xOffset = 0
	public var zOffset = 0
	public var primary: SceneEntity?
	public var secondary: SceneEntity?
	/// rt4 `anInt1388`: rotation 0...3.
	public var rotation = 0
	/// rt4 `anInt1395`: visibility mask (256 = diagonal/two-sided).
	public var mask = 0
	public var key: Int64 = 0
	public init() {}
}

/// rt4 `GroundDecor` (client!bm).
public final class GroundDecor {
	public var entity: SceneEntity?
	public var xFine = 0
	public var zFine = 0
	/// rt4 `anInt733`: Y.
	public var y = 0
	public var key: Int64 = 0
	/// rt4 `aBoolean49`.
	public var flag = false
	public init() {}
}

/// rt4 `Scenery` (client!ec): a multi-tile entity (loc, player, npc, spotanim...).
public final class Scenery {
	public var entity: SceneEntity?
	public var xMin = 0, xMax = 0, zMin = 0, zMax = 0
	public var level = 0
	/// rt4 `anInt1699`, `anInt1706`, `anInt1703`: fine position.
	public var xFine = 0, y = 0, zFine = 0
	/// rt4 `anInt1714`: yaw 0...2047.
	public var yaw = 0
	public var key: Int64 = 0
	/// rt4 `anInt1707`: frame stamp of the last draw.
	var lastFrame = 0
	/// rt4 `anInt1705`: draw-order distance.
	var sortDistance = 0
	public init() {}
}

/// rt4 `ObjStackEntity` (client!jj): up to three item models on a tile.
public final class ObjStackEntity {
	public var primary: SceneEntity?
	public var secondary: SceneEntity?
	public var tertiary: SceneEntity?
	public var xFine = 0
	public var zFine = 0
	/// rt4 `anInt3057`: Y.
	public var y = 0
	/// rt4 `anInt3063`: height of tall scenery on the tile that lifts the stack.
	public var lift = 0
	public var key: Int64 = 0
	public init() {}
}

/// rt4 `Tile` (client!bj). Field names follow what the draw loop does with them.
public final class SceneTile {
	/// rt4 `anInt672`: level this tile is drawn on (bridge tiles shift down one level).
	public var level: Int
	/// rt4 `anInt668`: level the terrain heights belong to.
	public let heightLevel: Int
	public let x: Int
	public let z: Int
	public var plainTile: PlainTile?
	public var shapedTile: ShapedTile?
	public var wall: Wall?
	public var wallDecor: WallDecor?
	public var groundDecor: GroundDecor?
	public var objStack: ObjStackEntity?
	/// rt4 `aClass3_Sub5_1`: the level-0 tile that sits under a bridge.
	public var bridgeBelow: SceneTile?
	public var scenery = [Scenery?](repeating: nil, count: 5)
	public var sceneryCount = 0
	/// rt4 `interiorFlags`: per-scenery bit mask of which sides continue into neighbour tiles.
	public var interiorFlags = [Int](repeating: 0, count: 5)
	public var allInteriorFlags = 0

	/// rt4 `aBoolean45`: ground (and first wall pass) not drawn yet.
	var pendingGround = false
	/// rt4 `aBoolean46`: tile is in this frame's visible set and not finished.
	var visible = false
	/// rt4 `aBoolean47`: scenery on this tile still has to be drawn.
	var pendingScenery = false
	/// rt4 `anInt663`: bit mask of wall sides still waiting for scenery in front of them.
	var wallWait = 0
	/// rt4 `anInt665` / `anInt667`.
	var wallWaitMatch = 0
	var wallWaitOther = 0
	/// rt4 `anInt670`: which wall sides face away from the camera (drawn after the scenery).
	var backWalls = 0
	var queueStamp = 0
	var queued = false

	public init(level: Int, x: Int, z: Int) {
		self.level = level
		self.heightLevel = level
		self.x = x
		self.z = z
	}
}
