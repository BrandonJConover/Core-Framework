/// Live interface state the server changes with IF_* packets (and, later,
/// CS2 scripts): which sub-interfaces are open where, and per-component
/// overrides. The renderer reads it every frame.
public struct InterfaceState {
	public var top: Int = -1
	/// Container component id -> opened interface id.
	public var open: [Int: Int] = [:]
	public var hidden: [Int: Bool] = [:]
	public var text: [Int: String] = [:]
	public var color: [Int: Int32] = [:]
	public var sprite: [Int: Int] = [:]
	public var position: [Int: (x: Int, y: Int)] = [:]
	public var scroll: [Int: Int] = [:]
	/// Base size overrides (CS2 `cc_setsize`), applied before dynamic sizing.
	public var size: [Int: (w: Int, h: Int)] = [:]

	public init() {}

	/// Applies the IF_* server messages; returns true if it was one of them.
	@discardableResult
	public mutating func apply(_ m: ServerMessage) -> Bool {
		switch m {
		case .ifOpenTop(let id, _): top = id; open = [:]
		case .ifOpenSub(let parent, let component, _): open[Int(parent)] = component
		case .ifCloseSub(let parent): open[Int(parent)] = nil
		case .ifSetHide(let c, let h): hidden[Int(c)] = h
		case .ifSetText(let c, let t): text[Int(c)] = t
		case .ifSetColour(let c, let col):
			// IF_SETCOLOUR carries RGB555.
			let r = (col >> 10 & 0x1F) << 3, g = (col >> 5 & 0x1F) << 3, b = (col & 0x1F) << 3
			color[Int(c)] = Int32(r << 16 | g << 8 | b)
		case .ifSetPosition(let c, let x, let y): position[Int(c)] = (x, y)
		case .ifSetScrollPos(let c, let pos): scroll[Int(c)] = pos
		default: return false
		}
		return true
	}
}

/// Draws interfaces into a `Raster` the way rt4 `renderComponent` does for
/// rectangles, text, sprites, lines and layers. Models (type 6) and
/// inventories (type 2) need the 3D renderer and item icons, so they are
/// left as hooks for now.
public final class InterfaceRenderer {
	let store: ConfigStore
	var groups: [Int: [Component?]] = [:]
	/// Every component drawn in the last `render`, in draw order, with its
	/// screen rectangle (clipped to its parents). Used for touch hit tests.
	public private(set) var drawn: [(component: Component, x: Int, y: Int, w: Int, h: Int)] = []
	/// Drawn in place of a type-6 model or a 3D viewport component, if set.
	public var drawModel: ((Component, Int, Int, Int, Int, inout Raster) -> Void)?

	public init(store: ConfigStore) {
		self.store = store
	}

	public func components(_ interface: Int) throws -> [Component?] {
		if let c = groups[interface] { return c }
		let idx = try store.index(ConfigStore.GraphicsArchive.interfaces)
		let files = try store.files(archive: ConfigStore.GraphicsArchive.interfaces, group: interface)
		let count = idx.isValid(group: interface) ? idx.groupCapacities[interface] : 0
		var out = [Component?](repeating: nil, count: count)
		for (f, data) in files where f < count {
			out[f] = try Component(id: interface << 16 | f, data: data)
		}
		groups[interface] = out
		return out
	}

	public func interfaceId(named name: String) throws -> Int? {
		try store.index(ConfigStore.GraphicsArchive.interfaces).group(named: name)
	}

	/// Renders `interface` as the top level filling the raster.
	public func render(_ interface: Int, state: InterfaceState, into r: inout Raster) throws {
		r.resetClip()
		drawn.removeAll(keepingCapacity: true)
		try renderInterface(interface, x: 0, y: 0, w: r.width, h: r.height, state: state, into: &r)
	}

	/// The top-most interactive component under (x, y) from the last render.
	public func hitTest(x: Int, y: Int) -> Component? {
		for d in drawn.reversed() where x >= d.x && y >= d.y && x < d.x + d.w && y < d.y + d.h {
			let c = d.component
			if c.hooks["onClickRepeat"] != nil || c.hooks["onOptionClick"] != nil || !c.ops.isEmpty || c.buttonType != 0 || c.option != nil {
				return c
			}
		}
		return nil
	}

	func renderInterface(_ interface: Int, x: Int, y: Int, w: Int, h: Int, state: InterfaceState, into r: inout Raster) throws {
		let comps = try components(interface)
		try renderLayer(comps, parent: -1, ox: x, oy: y, pw: w, ph: h, state: state, into: &r)
	}

	func renderLayer(_ comps: [Component?], parent: Int, ox: Int, oy: Int, pw: Int, ph: Int, state: InterfaceState, into r: inout Raster) throws {
		let clip = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		defer { r.setClip(clip.0, clip.1, clip.2, clip.3) }
		for case let c? in comps where c.parent == parent {
			if state.hidden[c.id] ?? c.hidden { continue }
			var c = c
			if let sz = state.size[c.id] { c.baseWidth = sz.w; c.baseHeight = sz.h }
			let (w, h) = c.size(parentWidth: pw, parentHeight: ph)
			var (lx, ly) = c.position(width: w, height: h, parentWidth: pw, parentHeight: ph)
			if let p = state.position[c.id] { lx = p.x; ly = p.y }
			let x = ox + lx, y = oy + ly
			// Clip to this component (lines extend one pixel).
			let extra = c.type == 9 ? 1 : 0
			r.setClip(max(clip.0, x), max(clip.1, y), min(clip.2, x + w + extra), min(clip.3, y + h + extra))
			if c.if3 && (r.clipRight <= r.clipLeft || r.clipBottom <= r.clipTop) {
				r.setClip(clip.0, clip.1, clip.2, clip.3)
				continue
			}
			drawn.append((c, r.clipLeft, r.clipTop, r.clipRight - r.clipLeft, r.clipBottom - r.clipTop))
			try draw(c, x: x, y: y, w: w, h: h, state: state, into: &r)
			if c.type == 0 {
				let sy = state.scroll[c.id] ?? 0
				try renderLayer(comps, parent: c.id, ox: x, oy: y - sy, pw: w, ph: h, state: state, into: &r)
				if let sub = state.open[c.id] {
					try renderInterface(sub, x: x, y: y, w: w, h: h, state: state, into: &r)
				}
			}
			r.setClip(clip.0, clip.1, clip.2, clip.3)
		}
	}

	func draw(_ c: Component, x: Int, y: Int, w: Int, h: Int, state: InterfaceState, into r: inout Raster) throws {
		let opacity = 256 - (c.alpha & 0xFF)
		switch c.type {
		case 3:
			let rgb = UInt32(bitPattern: state.color[c.id] ?? c.color) & 0xFFFFFF
			if c.filled { r.fillRect(x, y, w, h, rgb, opacity: opacity) } else { r.drawRect(x, y, w, h, rgb, opacity: opacity) }
		case 4:
			guard c.font != -1, let font = try store.font(c.font) else { return }
			let text = state.text[c.id] ?? c.text
			let rgb = UInt32(bitPattern: state.color[c.id] ?? c.color) & 0xFFFFFF
			font.drawParagraph(text, x: x, y: y, w: w, h: h, color: rgb, shadow: c.shadowed ? 0 : -1,
				halign: c.halign, valign: c.valign, lineSpacing: c.lineSpacing, opacity: 256, into: &r)
		case 5:
			let id = state.sprite[c.id] ?? c.spriteId
			guard id != -1, let sheet = try store.sprite(id), let f = sheet.frames.first else { return }
			if !c.if3 {
				r.draw(f, x: x, y: y)
			} else if c.spriteTiling {
				let saved = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
				r.setClip(max(saved.0, x), max(saved.1, y), min(saved.2, x + w), min(saved.3, y + h))
				var ty = y
				while ty < y + h {
					var tx = x
					while tx < x + w {
						r.draw(f, x: tx, y: ty, opacity: opacity, hFlip: c.hFlip, vFlip: c.vFlip)
						tx += max(f.width, 1)
					}
					ty += max(f.height, 1)
				}
				r.setClip(saved.0, saved.1, saved.2, saved.3)
			} else if f.width == w && f.height == h {
				r.draw(f, x: x, y: y, opacity: opacity, hFlip: c.hFlip, vFlip: c.vFlip)
			} else {
				r.drawScaled(f, x: x, y: y, w: w, h: h, opacity: opacity)
			}
		case 6:
			drawModel?(c, x, y, w, h, &r)
		case 9:
			let rgb = UInt32(bitPattern: c.color) & 0xFFFFFF
			if c.lineMirrored {
				r.drawLine(x, y + h, x + w, y, rgb)
			} else {
				r.drawLine(x, y, x + w, y + h, rgb)
			}
		default:
			break
		}
	}
}
