import Foundation

/// The minimap of rt4's resizable interface (component `clientCode == 1338`) and its compass
/// (`clientCode == 1339`): a rotating, zoomed window onto a static image of the scene (rt4 `MiniMap`,
/// `Cs1ScriptRunner.method3047` for the compass), with entity dots on top.
///
/// The static image is rebuilt whenever the scene is (see `buildImage`). Positions in the public API are
/// absolute world tiles unless noted.
public final class Minimap {
	public let store: ConfigStore
	/// The flag drawn at the walk destination (rt4 `LoginManager.mapFlagX/Z`), in world tiles; nil for none.
	public var destination: (x: Int, z: Int)?
	/// Tiles holding ground items, drawn as the item dot (rt4 `SceneGraph.objStacks`). The client does not
	/// track ground items yet, so nothing fills this.
	public var itemTiles: [(x: Int, z: Int)] = []
	/// Friends that are online (encoded name -> world), from `updateFriend` messages.
	public private(set) var friends: [Int64: Int] = [:]
	/// rt4 `MiniMap.anInt4130`: extra zoom (0 = the normal 4 px per tile).
	public var zoom = 0
	/// rt4 `MiniMap.anInt1814`: angle added to the camera yaw.
	public var yawOffset = 0

	var image = MinimapImage()
	/// What the image was built for: (scene build count, level).
	var builtFor = (-1, -1)
	var msiCache: [Int: MsiType?] = [:]
	var spriteCache: [String: IndexedMapSprite?] = [:]
	var maskCache: [Int: Mask?] = [:]
	var sheetCache: [String: SpriteSheet] = [:]
	var palette: [Int32]?

	/// Where the minimap component was drawn last (component rectangle and its circular mask rows).
	struct Placement {
		var x: Int, y: Int, w: Int, h: Int
		var mask: Mask
	}
	var placement: Placement?

	/// rt4 `Component.anIntArray37/45` (`method478`): per row, where the mask sprite starts and how long it is.
	struct Mask {
		var starts: [Int]
		var widths: [Int]
	}

	public init(store: ConfigStore) {
		self.store = store
	}

	func handle(_ e: GameSession.Event) {
		guard case .message(let m) = e, case .updateFriend(let name, let world, _, _) = m else { return }
		if world != 0 { friends[name] = world } else { friends[name] = nil }
	}

	// MARK: assets

	func msiType(_ id: Int) -> MsiType? {
		if let c = msiCache[id] { return c }
		let t = ((try? store.msi(id)) ?? nil) ?? MsiType(id: id)
		msiCache[id] = .some(t)
		return t
	}

	/// An msi sprite turned `rotations` quarter turns (rt4 `MsiType.getSprite`), without rt4's random colour jitter.
	func indexedSprite(_ id: Int, rotations: Int) -> IndexedMapSprite? {
		let key = "\(id)/\(rotations)"
		if let c = spriteCache[key] { return c }
		var s: IndexedMapSprite?
		if let f = (try? store.sprite(id))??.frames.first {
			var t = IndexedMapSprite(f)
			for _ in 0..<rotations { t.flipVertical() }
			s = t
		}
		spriteCache[key] = .some(s)
		return s
	}

	func sheet(_ name: String) -> SpriteSheet? {
		if let s = sheetCache[name] { return s }
		guard let s = (try? store.sprite(named: name)) ?? nil else { return nil }
		sheetCache[name] = s
		return s
	}

	/// rt4 `Component.method478`: the mask rows of a component's sprite (non-zero pixels are inside).
	func mask(spriteId: Int, height: Int) -> Mask? {
		if let c = maskCache[spriteId] { return c }
		var m: Mask?
		if let f = (try? store.sprite(spriteId))??.frames.first {
			var starts = [Int](repeating: 0, count: f.height), widths = starts
			for y in 0..<f.height {
				let row = y - f.yOffset
				var first = 0, end = f.width
				if row >= 0 && row < f.innerHeight {
					func set(_ x: Int) -> Bool {
						let c = x - f.xOffset
						return c >= 0 && c < f.innerWidth && f.indices[row * f.innerWidth + c] != 0
					}
					var x = 0
					while x < f.width { if set(x) { first = x; break }; x += 1 }
					x = first
					while x < f.width { if !set(x) { end = x; break }; x += 1 }
				} else {
					end = 0
				}
				starts[y] = first
				widths[y] = end - first
			}
			m = Mask(starts: starts, widths: widths)
		}
		maskCache[spriteId] = .some(m)
		return m
	}

	/// HSL16 -> 0xRRGGBB palette at rt4's default brightness.
	func hslPalette() -> [Int32] {
		if let p = palette { return p }
		let p = Rasteriser3D(width: 1, height: 1).palette
		palette = p
		return p
	}

	// MARK: projection

	/// rt4 `MiniMap.method1446`: (sin, cos) scaled by the zoom, for the current rotation `theta`.
	func rotation(theta: Int) -> (sin: Int, cos: Int) {
		((MathTables.sin[theta] * 256) / (zoom + 256), (MathTables.cos[theta] * 256) / (zoom + 256))
	}

	/// The map rotation: camera yaw plus `yawOffset`.
	func theta(yaw: Double) -> Int { (yawOffset + Int(yaw)) & 0x7FF }

	/// rt4 `SoftwareSprite.renderRotated`: samples `src` (square, `size` wide) rotated by `theta` and scaled
	/// by `scale` (256 = 1:1) around the anchor, into the rows of `mask` at (x, y). Bilinear like the
	/// deob's `BILINEAR_MINIMAP`. When `skipClear`, source pixels equal to 0 leave the destination alone.
	static func drawRotated(into r: inout Raster, src: [UInt32], srcWidth: Int, srcHeight: Int, x: Int, y: Int, w: Int, h: Int,
	                        anchorX: Int, anchorY: Int, theta: Int, scale: Int, mask: Mask, skipClear: Bool) {
		let centerX = -w / 2, centerY = -h / 2
		let s1 = Int(sin(Double(theta) / 326.11) * 65536.0), c1 = Int(cos(Double(theta) / 326.11) * 65536.0)
		let sn = (s1 * scale) >> 8, cs = (c1 * scale) >> 8
		var originX = (anchorX << 16) + centerY * sn + centerX * cs
		var originY = (anchorY << 16) + (centerY * cs - centerX * sn)
		func at(_ px: Int, _ py: Int) -> UInt32 {
			guard px >= 0, py >= 0, px < srcWidth, py < srcHeight else { return 1 }
			return src[px + py * srcWidth]
		}
		for iy in 0..<min(h, mask.starts.count) {
			let start = mask.starts[iy]
			var dstX = originX + cs * start
			var dstY = originY - sn * start
			let py = y + iy
			if py >= r.clipTop && py < r.clipBottom {
				for ix in 0..<max(mask.widths[iy], 0) {
					let px = x + start + ix
					if px >= r.clipLeft && px < r.clipRight {
						let x1 = dstX >> 16, y1 = dstY >> 16
						let c = at(x1, y1)
						if !(skipClear && c == 0) {
							let x2 = x1 + 1, y2 = y1 + 1
							let c2 = at(x2, y1), c3 = at(x1, y2), c4 = at(x2, y2)
							let xd1 = (dstX >> 8) - (x1 << 8), yd1 = (dstY >> 8) - (y1 << 8)
							let xd2 = (x2 << 8) - (dstX >> 8), yd2 = (y2 << 8) - (dstY >> 8)
							let a1 = xd2 * yd2, a2 = xd1 * yd2, a3 = xd2 * yd1, a4 = xd1 * yd1
							func ch(_ shift: Int) -> Int {
								Int(c >> UInt32(shift) & 0xFF) * a1 + Int(c2 >> UInt32(shift) & 0xFF) * a2
									+ Int(c3 >> UInt32(shift) & 0xFF) * a3 + Int(c4 >> UInt32(shift) & 0xFF) * a4
							}
							let red = ch(16) & 0xFF0000, green = (ch(8) >> 8) & 0xFF00, blue = ch(0) >> 16
							r.pixels[py * r.width + px] = 0xFF00_0000 | UInt32(truncatingIfNeeded: red | green | blue)
						}
					}
					dstX += cs
					dstY -= sn
				}
			}
			originX += sn
			originY += cs
		}
	}
}
