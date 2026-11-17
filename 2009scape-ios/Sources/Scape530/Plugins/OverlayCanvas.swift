import Foundation

public struct ScreenPoint: Equatable {
	public var x: Int, y: Int
	public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public extension Raster {
	/// Fills a polygon (any simple shape, even-odd rule) with `rgb` at `opacity` 0...256, honouring the clip.
	mutating func fillPolygon(_ pts: [ScreenPoint], _ rgb: UInt32, opacity: Int = 256) {
		guard pts.count >= 3 else { return }
		let minY = max(pts.map(\.y).min() ?? 0, clipTop), maxY = min(pts.map(\.y).max() ?? 0, clipBottom - 1)
		guard minY <= maxY else { return }
		for y in minY...maxY {
			var xs: [Int] = []
			for i in 0..<pts.count {
				let a = pts[i], b = pts[(i + 1) % pts.count]
				if a.y == b.y { continue }
				let (lo, hi) = a.y < b.y ? (a, b) : (b, a)
				// Half-open so a vertex shared by two edges counts once.
				if y >= lo.y && y < hi.y { xs.append(lo.x + (y - lo.y) * (hi.x - lo.x) / (hi.y - lo.y)) }
			}
			xs.sort()
			var i = 0
			while i + 1 < xs.count {
				hline(xs[i], y, max(xs[i + 1] - xs[i], 1), rgb, opacity: opacity)
				i += 2
			}
		}
		// A polygon of zero height (edge-on) still shows its outline.
		if pts.allSatisfy({ $0.y == pts[0].y }) { strokePolygon(pts, rgb) }
	}

	/// One pixel wide outline.
	mutating func strokePolygon(_ pts: [ScreenPoint], _ rgb: UInt32) {
		guard pts.count >= 2 else { return }
		for i in 0..<pts.count {
			let a = pts[i], b = pts[(i + 1) % pts.count]
			drawLine(a.x, a.y, b.x, b.y, rgb)
		}
	}
}

public enum OverlayFont {
	/// rt4 `p11_full`, `p12_full`, `b12_full`.
	case small, regular, bold
}

/// What an overlay draws with: the 3D viewport, the camera of the frame that was just rendered (to project
/// world positions to screen pixels) and the cache fonts. Coordinates handed back and accepted are raster
/// pixels. A canvas without a camera (before the first scene) projects everything to nil.
public struct OverlayCanvas {
	public let viewport: (x: Int, y: Int, w: Int, h: Int)
	public let loop: Int
	let world: WorldView?
	let cam: WorldView.OverlayCamera?
	let scene: Scene?
	let store: ConfigStore?
	/// Client state and item facts, for overlays that need more than the camera.
	public let ctx: PluginContext

	init(world: WorldView, viewport: (x: Int, y: Int, w: Int, h: Int), ctx: PluginContext) {
		self.ctx = ctx
		self.world = world
		self.viewport = viewport
		cam = world.overlayCamera
		scene = world.scene
		store = world.store
		loop = world.ctx.loop
	}

	/// A canvas that has no world (tests of text and polygon drawing).
	init(viewport: (x: Int, y: Int, w: Int, h: Int), store: ConfigStore?, ctx: PluginContext) {
		self.ctx = ctx
		self.viewport = viewport
		self.store = store
		world = nil; cam = nil; scene = nil
		loop = 0
	}

	/// The npcs in the scene (a snapshot per call, so only ask when something needs them).
	public func npcs() -> [ActorSnapshot] {
		world?.ctx.npcs.sorted { $0.key < $1.key }.map { $0.value.pluginSnapshot(isSelf: false, hits: false) } ?? []
	}

	public var canProject: Bool { cam != nil && scene != nil }

	/// A point `height` fine units above the ground at fine scene position (`xFine`, `zFine`) (128 per tile),
	/// as a raster pixel; nil when behind the camera or off the map.
	public func project(xFine: Int, zFine: Int, height: Int = 0) -> ScreenPoint? {
		guard let world, let cam, let scene, let p = world.project(cam, xFine: xFine, zFine: zFine, height: height, scene: scene) else { return nil }
		return ScreenPoint(x: viewport.x + p.x, y: viewport.y + p.y)
	}

	/// The middle of scene tile (`x`, `z`).
	public func projectTileCenter(x: Int, z: Int, height: Int = 0) -> ScreenPoint? {
		project(xFine: x * 128 + 64, zFine: z * 128 + 64, height: height)
	}

	/// Screen corners of a `size` x `size` tile footprint with its south-west corner on scene tile (`x`, `z`),
	/// in order around the square; nil when any corner cannot be projected.
	public func tileCorners(x: Int, z: Int, size: Int = 1) -> [ScreenPoint]? {
		let c = [(x, z), (x + size, z), (x + size, z + size), (x, z + size)]
		var out: [ScreenPoint] = []
		for (cx, cz) in c {
			guard let p = project(xFine: cx * 128, zFine: cz * 128) else { return nil }
			out.append(p)
		}
		return out
	}

	/// The same footprint around a fine position (an actor mid-step).
	public func footprintCorners(xFine: Int, zFine: Int, size: Int) -> [ScreenPoint]? {
		let h = size * 64
		var out: [ScreenPoint] = []
		for (cx, cz) in [(xFine - h, zFine - h), (xFine + h, zFine - h), (xFine + h, zFine + h), (xFine - h, zFine + h)] {
			guard let p = project(xFine: cx, zFine: cz) else { return nil }
			out.append(p)
		}
		return out
	}

	public func fillTile(x: Int, z: Int, size: Int = 1, color: UInt32, opacity: Int = 80, into r: inout Raster) {
		guard let c = tileCorners(x: x, z: z, size: size) else { return }
		r.fillPolygon(c, color, opacity: opacity)
	}

	public func outlineTile(x: Int, z: Int, size: Int = 1, color: UInt32, into r: inout Raster) {
		guard let c = tileCorners(x: x, z: z, size: size) else { return }
		r.strokePolygon(c, color)
	}

	public func font(_ f: OverlayFont) -> BitmapFont? {
		guard let store else { return nil }
		let name: String
		switch f {
		case .small: name = "p11_full"
		case .regular: name = "p12_full"
		case .bold: name = "b12_full"
		}
		return (try? store.font(named: name)) ?? nil
	}

	/// Text centred on `x` with `y` as its baseline, with a black shadow so it reads on any ground.
	public func drawText(_ text: String, x: Int, y: Int, color: UInt32 = 0xFFFFFF, font f: OverlayFont = .small, centered: Bool = true, into r: inout Raster) {
		guard let font = font(f) else { return }
		if centered { font.drawCenter(text, x: x, y: y, color: color, shadow: 0, into: &r) } else { font.drawLeft(text, x: x, y: y, color: color, shadow: 0, into: &r) }
	}

	public func textWidth(_ text: String, font f: OverlayFont = .small) -> Int { font(f)?.stringWidth(text) ?? 0 }
}
