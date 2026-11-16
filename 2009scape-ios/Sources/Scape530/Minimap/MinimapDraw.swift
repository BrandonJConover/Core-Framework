import Foundation

/// The per-frame minimap drawing and hit testing, as `WorldView` / `GameClient` API.
extension WorldView {
	typealias DrawnComponent = (component: Component, x: Int, y: Int, w: Int, h: Int)

	/// Draws the minimap and compass into the components the interface laid out (`clientCode` 1338 and
	/// 1339 in `drawn`, the last frame's `InterfaceRenderer.drawn`). Call after the interface is drawn.
	/// Returns false while there is no scene or local player yet.
	@discardableResult
	public func drawMinimap(drawn: [(component: Component, x: Int, y: Int, w: Int, h: Int)], into r: inout Raster) -> Bool {
		guard let scene = scene, let me = selfActor else { return false }
		let level = scene.centralPlane
		let mm = minimap
		if mm.builtFor != (buildCount, level) {
			mm.buildImage(scene: scene, level: level, palette: mm.hslPalette())
			mm.builtFor = (buildCount, level)
		}
		let saved = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		defer { r.setClip(saved.0, saved.1, saved.2, saved.3) }
		let theta = mm.theta(yaw: camera.yawTarget)

		if let d = drawn.last(where: { $0.component.clientCode == 1339 }), let mask = mm.mask(spriteId: d.component.spriteId, height: d.h),
		   let sheet = mm.sheet("compass"), let f = sheet.frames.first {
			r.setClip(max(saved.0, d.x), max(saved.1, d.y), min(saved.2, d.x + d.w), min(saved.3, d.y + d.h))
			// rt4 `Cs1ScriptRunner.method3047`: the compass sprite turns with the camera yaw alone.
			var canvas = [UInt32](repeating: 0, count: f.width * f.height)
			for (i, c) in f.argb.enumerated() where c >> 24 != 0 {
				canvas[(i / f.innerWidth + f.yOffset) * f.width + i % f.innerWidth + f.xOffset] = c & 0xFFFFFF
			}
			Minimap.drawRotated(into: &r, src: canvas, srcWidth: f.width, srcHeight: f.height, x: d.x, y: d.y, w: d.w, h: d.h,
			                    anchorX: f.width / 2, anchorY: f.height / 2, theta: Int(camera.yawTarget) & 0x7FF, scale: 256, mask: mask, skipClear: true)
		}

		guard let d = drawn.last(where: { $0.component.clientCode == 1338 }),
		      let mask = mm.mask(spriteId: d.component.spriteId, height: d.h) else {
			mm.placement = nil
			return false
		}
		mm.placement = Minimap.Placement(x: d.x, y: d.y, w: d.w, h: d.h, mask: mask)
		r.setClip(max(saved.0, d.x), max(saved.1, d.y), min(saved.2, d.x + d.w), min(saved.3, d.y + d.h))
		Minimap.drawRotated(into: &r, src: mm.image.pixels, srcWidth: MinimapImage.size, srcHeight: MinimapImage.size,
		                    x: d.x, y: d.y, w: d.w, h: d.h, anchorX: me.xFine / 32 + 48, anchorY: 464 - me.zFine / 32,
		                    theta: theta, scale: mm.zoom + 256, mask: mask, skipClear: false)

		let plot = Plotter(mm: mm, d: d, mask: mask, theta: theta, meX: me.xFine / 32, meZ: me.zFine / 32)
		plot.drawIcons(&r, self, scene: scene)
		for t in mm.itemTiles {
			plot.sprite("mapdots", 0, dx: (t.x - ctx.originX) * 4 + 2 - plot.meX, dz: (t.z - ctx.originZ) * 4 + 2 - plot.meZ, &r)
		}
		for a in ctx.npcs.values where a.isVisible {
			guard let t = a.npcType, t.minimapVisible, t.interactive else { continue }
			let dx = a.xFine / 32 - plot.meX, dz = a.zFine / 32 - plot.meZ
			if t.minimapMarker == -1 { plot.sprite("mapdots", 1, dx: dx, dz: dz, &r) } else { plot.sprite("mapfunction", t.minimapMarker, dx: dx, dz: dz, &r) }
		}
		for (id, a) in ctx.players where id != selfIndex && a.isVisible {
			let dx = a.xFine / 32 - plot.meX, dz = a.zFine / 32 - plot.meZ
			let friend = a.appearance.map { mm.friends[$0.name37] != nil } ?? false
			plot.sprite("mapdots", friend ? 3 : 2, dx: dx, dz: dz, &r)
		}
		if let flag = mm.destination ?? destinationFlag.map({ (x: $0.x + ctx.originX, z: $0.z + ctx.originZ) }) {
			plot.sprite("mapflag", 0, dx: (flag.x - ctx.originX) * 4 + 2 - plot.meX, dz: (flag.z - ctx.originZ) * 4 + 2 - plot.meZ, &r)
		}
		// The local player: rt4 fills a 3x3 white square on the centre.
		r.fillRect(d.x + d.w / 2 - 1, d.y + d.h / 2 - 1, 3, 3, 0xFFFFFF)
		return true
	}

	/// The world tile under a point of the minimap (game pixels), or nil outside the round map or when it
	/// was not drawn. rt4 `Cs1ScriptRunner` clientCode 1338 hover: the screen offset is rotated back by the
	/// camera and added to the player's position.
	public func minimapTileAt(x: Int, y: Int) -> (tileX: Int, tileZ: Int)? {
		guard let p = minimap.placement, let me = selfActor else { return nil }
		let row = y - p.y
		guard x >= p.x, x < p.x + p.w, row >= 0, row < p.h, row < p.mask.starts.count else { return nil }
		let col = x - p.x
		guard col >= p.mask.starts[row], col <= p.mask.starts[row] + p.mask.widths[row] else { return nil }
		let dy = row - p.h / 2, dx = col - p.w / 2
		let theta = minimap.theta(yaw: camera.yawTarget)
		let sn = ((minimap.zoom + 256) * MathTables.sin[theta]) >> 8
		let cs = ((minimap.zoom + 256) * MathTables.cos[theta]) >> 8
		let up = (cs * dy - sn * dx) >> 11
		let right = (dy * sn + dx * cs) >> 11
		return (ctx.originX + ((me.xFine + right) >> 7), ctx.originZ + ((me.zFine - up) >> 7))
	}
}

/// Places sprites on the rotated map (rt4 `MiniMap.method1446`).
struct Plotter {
	let mm: Minimap
	let d: (component: Component, x: Int, y: Int, w: Int, h: Int)
	let mask: Minimap.Mask
	let theta: Int
	let meX: Int, meZ: Int

	/// Draws frame `index` of sprite group `name` at an offset (in 1/32 tile units, x east / z north)
	/// from the player; nothing when outside the map circle's bounding radius.
	func sprite(_ name: String, _ index: Int, dx: Int, dz: Int, _ r: inout Raster) {
		guard let sheet = mm.sheet(name), index >= 0, index < sheet.frames.count else { return }
		place(sheet.frames[index], dx: dx, dz: dz, &r)
	}

	func place(_ f: SpriteFrame, dx: Int, dz: Int, _ r: inout Raster) {
		let limit = max(d.w / 2, d.h / 2) + 10
		if limit * limit < dx * dx + dz * dz { return }
		let (sn, cs) = mm.rotation(theta: theta)
		let sx = (sn * dz + dx * cs) >> 16
		let sy = (cs * dz - dx * sn) >> 16
		let x = d.w / 2 + d.x + sx - f.width / 2
		let y = d.h / 2 + d.y - (sy + f.height / 2)
		// Clipped to the round mask like rt4's `method312(..., lineStarts, widths)`.
		let argb = f.argb
		for iy in 0..<f.innerHeight {
			let py = y + f.yOffset + iy
			let row = py - d.y
			guard py >= r.clipTop, py < r.clipBottom, row >= 0, row < mask.starts.count else { continue }
			for ix in 0..<f.innerWidth {
				let px = x + f.xOffset + ix
				let col = px - d.x
				guard px >= r.clipLeft, px < r.clipRight, col >= mask.starts[row], col < mask.starts[row] + mask.widths[row] else { continue }
				let c = argb[iy * f.innerWidth + ix]
				if c >> 24 != 0 { r.pixels[py * r.width + px] = 0xFF00_0000 | c & 0xFFFFFF }
			}
		}
	}

	/// rt4: map function icons from the build, resolved through multi-locs with the current varps.
	func drawIcons(_ r: inout Raster, _ world: WorldView, scene: Scene) {
		for icon in mm.image.icons {
			let dx = icon.x * 4 + 2 - meX, dz = icon.z * 4 + 2 - meZ
			guard var loc = (try? mm.store.loc(icon.loc)) ?? nil else { continue }
			if loc.multiLocs != nil {
				guard let m = world.env.resolve(loc, store: mm.store), m.mapFunction != -1 else { continue }
				loc = m
			}
			if loc.mapFunction >= 0 { sprite("mapfunction", loc.mapFunction, dx: dx, dz: dz, &r) }
		}
	}
}

extension GameClient {
	/// A tap on the minimap to a world tile (for walking), nil when (x, y) is not on the drawn map.
	public func minimapTileAt(x: Int, y: Int) -> (tileX: Int, tileZ: Int)? {
		world.minimapTileAt(x: x, y: y)
	}

	/// The walk destination flag on the minimap, in world tiles; nil removes it.
	public var minimapDestination: (x: Int, z: Int)? {
		get { world.minimap.destination }
		set { world.minimap.destination = newValue }
	}
}
