/// A rendered item icon (rt4 `SoftwareSprite` from `Inv.renderObjectSprite`): 36x32, 0xAARRGGBB,
/// alpha 0 where nothing was drawn.
public struct ItemSprite {
	public static let width = 36, height = 32
	public var pixels: [UInt32]
	public var width: Int { ItemSprite.width }
	public var height: Int { ItemSprite.height }
}

/// Item icon renderer and cache: port of rt4 `Inv.getObjectSprite` / `renderObjectSprite` plus
/// `SoftwareSprite.drawOutline` / `drawShadow` and `Inv.formatObjAmount`.
///
/// One instance owns a 36x32 `Rasteriser3D` and is not thread-safe; use it from the UI thread.
public final class ItemIcons {
	let store: ConfigStore
	var textures: TextureStore?
	private var triedTextures = false
	private var rasteriser: Rasteriser3D?
	private var cache: [Key: ItemSprite] = [:]
	private var font: BitmapFont?

	struct Key: Hashable {
		let selected: Int, id: Int, drawText: Bool, count: Int, shadow: Int32
	}

	public init(store: ConfigStore, textures: TextureStore? = nil) {
		self.store = store
		self.textures = textures
		triedTextures = textures != nil
	}

	public func clear() { cache = [:] }

	/// rt4 `Inv.getObjectSprite(selected, id, drawText, count, shadow)`. `selected` is the outline:
	/// 0 none, 1 black, 2 black then white (a pressed inventory slot). Nil when the item has no model.
	/// rt4 skips its cache when a texture had transparency; icons here are always cached.
	public func sprite(selected: Int, id: Int, drawText: Bool, count: Int, shadow: Int32) -> ItemSprite? {
		let key = Key(selected: selected, id: id, drawText: drawText, count: count, shadow: shadow)
		if let s = cache[key] { return s }
		guard let s = (try? render(shadow: shadow, id: id, drawText: drawText, state: selected, stack: count, cert: false)) ?? nil else { return nil }
		cache[key] = s
		return s
	}

	/// rt4 `Inv.formatObjAmount`: yellow below 100,000, white thousands with `K`, green millions with `M`.
	public static func formatAmount(_ n: Int) -> String {
		if n < 100_000 { return "<col=ffff00>\(n)</col>" }
		if n >= 10_000_000 { return "<col=00ff80>\(n / 1_000_000)M</col>" }
		return "<col=ffffff>\(n / 1000)K</col>"
	}

	private func raster() -> Rasteriser3D {
		if let r = rasteriser { return r }
		if !triedTextures {
			triedTextures = true
			textures = try? TextureStore(config: store)
		}
		let r = Rasteriser3D(width: ItemSprite.width, height: ItemSprite.height)
		r.unpackTextures(textures)
		r.setBrightness(0.8, jitter: false)
		rasteriser = r
		return r
	}

	func textureAvailable(_ id: Int) -> Bool {
		guard let t = textures else { return false }
		return t.meta.indices.contains(id) && t.meta[id].defined
	}

	/// rt4 `Inv.renderObjectSprite`. `state` is the outline level, `cert` draws a noted item's real
	/// item at 1.5x zoom (it is the small picture on the note), `linked` sprites are never cached.
	func render(shadow: Int32, id: Int, drawText: Bool, state: Int, stack: Int, cert: Bool) throws -> ItemSprite? {
		guard let base = try store.objResolved(id) else { return nil }
		let o = try store.objForCount(base, stack)
		_ = raster()
		guard let model = try store.objModel(o, textureAvailable: { self.textureAvailable($0) }) else { return nil }

		var linked: ItemSprite?
		if o.certtemplate != -1 {
			// The note's picture is the real item at state 1, count 10, drawn larger.
			guard let l = try render(shadow: 0, id: o.certlink, drawText: false, state: 1, stack: 10, cert: true) else { return nil }
			linked = l
		} else if o.lentTemplate != -1 {
			guard let l = try render(shadow: shadow, id: o.lentLink, drawText: false, state: state, stack: stack, cert: false) else { return nil }
			linked = l
		}

		let r = raster()
		r.setClip(0, 0, ItemSprite.width, ItemSprite.height)
		r.prepare()
		// rt4 `Rasteriser.setBounds(16, 16)`.
		r.centerX = 16
		r.centerY = 16
		r.screenLowerX = -16
		r.screenUpperX = r.width - 16
		r.screenLowerY = -16
		r.screenUpperY = r.height - 16
		r.jagged = false
		r.clear(0)

		var zoom = o.zoom2d
		if cert { zoom = Int(Double(zoom) * 1.5) } else if state == 2 { zoom = Int(Double(zoom) * 1.04) }
		let pc = (MathTables.cos[o.xAngle2D & 2047] * zoom) >> 16
		let ps = (MathTables.sin[o.xAngle2D & 2047] * zoom) >> 16
		model.ensureBounds()
		model.renderAtOrigin(r, yAngle: o.yAngle2D, zAngle: o.zAngle2D, xAngle: o.xAngle2D, x: o.xOffset2D, y: ps + o.yOffset2D - model.minY / 2, z: o.yOffset2D + pc)
		r.jagged = true

		var px = r.pixels.map { Int($0) & 0xFFFFFF }
		let w = ItemSprite.width, h = ItemSprite.height
		if state >= 1 { px = ItemIcons.outline(px, w, h, 1) }
		if state >= 2 { px = ItemIcons.outline(px, w, h, 0xFFFFFF) }
		if shadow != 0 { ItemIcons.dropShadow(&px, w, h, Int(shadow) & 0xFFFFFF) }

		func argb(_ p: [Int]) -> [UInt32] { p.map { $0 == 0 ? 0 : 0xFF00_0000 | UInt32($0) } }
		var out = px
		if o.certtemplate != -1, let l = linked {
			// The item's own sprite goes on top of the note paper.
			for i in 0..<out.count where l.pixels[i] != 0 { out[i] = Int(l.pixels[i] & 0xFFFFFF) }
		} else if o.lentTemplate != -1, let l = linked {
			// The lent border goes on top of the real item.
			out = l.pixels.map { Int($0 & 0xFFFFFF) }
			for i in 0..<out.count where px[i] != 0 { out[i] = px[i] }
		}

		if drawText && (o.stackable || stack != 1) && stack != -1 { drawCount(&out, stack) }
		return ItemSprite(pixels: argb(out))
	}

	/// rt4 `SoftwareSprite.drawOutline(rgb)`: paints empty pixels that touch a drawn pixel
	/// left, above, right or below.
	static func outline(_ src: [Int], _ w: Int, _ h: Int, _ rgb: Int) -> [Int] {
		var dest = src
		for y in 0..<h {
			for x in 0..<w {
				let i = y * w + x
				guard src[i] == 0 else { continue }
				if (x > 0 && src[i - 1] != 0) || (y > 0 && src[i - w] != 0) || (x < w - 1 && src[i + 1] != 0) || (y < h - 1 && src[i + w] != 0) {
					dest[i] = rgb
				}
			}
		}
		return dest
	}

	/// rt4 `SoftwareSprite.drawShadow(rgb)`: an empty pixel whose up-left neighbour is drawn.
	static func dropShadow(_ px: inout [Int], _ w: Int, _ h: Int, _ rgb: Int) {
		var y = h - 1
		while y > 0 {
			var x = w - 1
			while x > 0 {
				if px[y * w + x] == 0 && px[(y - 1) * w + x - 1] != 0 { px[y * w + x] = rgb }
				x -= 1
			}
			y -= 1
		}
	}

	/// The count text at the top left (rt4 `ObjTypeList.font.renderLeft(formatObjAmount, 0, 9, yellow, 1)`).
	private func drawCount(_ px: inout [Int], _ count: Int) {
		if font == nil { font = (try? store.font(named: "p11_full")) ?? nil }
		guard let f = font else { return }
		var scratch = Raster(width: ItemSprite.width, height: ItemSprite.height)
		f.drawLeft(ItemIcons.formatAmount(count), x: 0, y: 9, color: 0xFFFF00, shadow: 1, into: &scratch)
		for i in 0..<px.count where scratch.pixels[i] != 0xFF00_0000 { px[i] = Int(scratch.pixels[i] & 0xFFFFFF) }
	}
}

extension Raster {
	/// Draws an item icon at (x, y), `opacity` 0...256 (rt4 `Sprite.render` / `renderAlpha`).
	public mutating func draw(_ s: ItemSprite, x: Int, y: Int, opacity: Int = 256) {
		drawScaled(s, x: x, y: y, w: s.width, h: s.height, opacity: opacity)
	}

	/// Draws an item icon stretched to w x h (rt4 `renderResized`, nearest neighbour).
	public mutating func drawScaled(_ s: ItemSprite, x: Int, y: Int, w: Int, h: Int, opacity: Int = 256) {
		guard w > 0, h > 0 else { return }
		let y0 = max(y, clipTop), y1 = min(y + h, clipBottom)
		let x0 = max(x, clipLeft), x1 = min(x + w, clipRight)
		guard x0 < x1, y0 < y1 else { return }
		for dy in y0..<y1 {
			let sy = (dy - y) * s.height / h
			for dx in x0..<x1 {
				let c = s.pixels[sy * s.width + (dx - x) * s.width / w]
				if c != 0 { blend(dy * width + dx, c & 0xFFFFFF, opacity) }
			}
		}
	}
}
