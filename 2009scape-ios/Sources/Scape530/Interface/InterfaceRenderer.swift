import Foundation

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
	/// Whole-component replacements made by CS2 (or by the script host for
	/// IF_* packets): a static component's current state, keyed by its id.
	/// When present it is drawn instead of the cache component.
	public var overrides: [Int: Component] = [:]
	/// CS2-created children (`cc_create`): parent layer id -> child index ->
	/// component. Drawn after the layer's static children.
	public var dynamic: [Int: [Int: Component]] = [:]
	/// IF_SETEVENTS masks for CS2-created children (rt4 `InterfaceList.properties`, keyed by component id and
	/// child index). They outlive the child, so scripts may rebuild a layer and keep the server's settings.
	public var childEvents: [Int: [Int: Int32]] = [:]
	/// WIDGETSTRUCT_SETTING target params of CS2-created children, like `childEvents` (rt4 `ServerActiveProperties.targetParam`).
	public var childTargetParams: [Int: [Int: Int]] = [:]
	/// Items of if1 inventory components (type 2), per component id then slot (rt4 `Component.objTypes`
	/// / `objCounts`, filled by UPDATE_INV_*). Empty slots are absent.
	public var invSlots: [Int: [Int: ServerMessage.InvItem]] = [:]
	/// Animation playback of type-6 components (rt4 `anInt510/500/496`), keyed by component.
	public var modelAnim: [ComponentRef: ModelAnim] = [:]
	/// Pressed, selected and dragged inventory slots (rt4 `MiniMenu.pressedInventoryComponent`, `anInt5014`,
	/// `InterfaceList.clickedInventoryComponent`).
	public var inventoryUI = InventoryUI()
	/// The if3 component being dragged, once the pointer left its dead zone (rt4 `Cs1ScriptRunner.aBoolean172`).
	public var componentDrag: ComponentDrag?
	/// Client cycles counted by `advanceModelAnimations` (rt4 `client.loop`), for the turning player models.
	public var clientLoop = 0

	public init() {}

	/// Inventory slot highlighting for the renderer (all component ids are `interface << 16 | index`).
	public struct InventoryUI {
		/// The item chosen with "Use" (outlined in white while selecting a target).
		public var useSelected: (component: Int, slot: Int)?
		/// A slot that was just activated, drawn at half opacity for 15 client cycles.
		public var pressed: (component: Int, slot: Int)?
		/// A slot being dragged and the finger's offset from where it started (already dead-zone filtered).
		public var dragging: (component: Int, slot: Int, dx: Int, dy: Int)?
		public init() {}
	}

	/// Resets the animation state of every component of `interface` (rt4 `InterfaceList.method1753` on open).
	mutating func resetAnimations(of interface: Int) {
		for key in modelAnim.keys where key.id >> 16 == interface { modelAnim[key] = nil }
	}

	/// Applies the IF_* server messages; returns true if it was one of them.
	@discardableResult
	public mutating func apply(_ m: ServerMessage) -> Bool {
		switch m {
		case .ifOpenTop(let id, _): top = id; resetAnimations(of: id) // sub-interfaces stay open (rt4)
		case .ifOpenSub(let parent, let component, _): open[Int(parent)] = component; resetAnimations(of: component)
		case .ifCloseSub(let parent): open[Int(parent)] = nil
		case .ifSetHide(let c, let h): hidden[Int(c)] = h
		case .ifSetText(let c, let t): text[Int(c)] = t
		case .ifSetColour(let c, let col):
			// IF_SETCOLOUR carries RGB555.
			let r = (col >> 10 & 0x1F) << 3, g = (col >> 5 & 0x1F) << 3, b = (col & 0x1F) << 3
			color[Int(c)] = Int32(r << 16 | g << 8 | b)
		case .ifSetPosition(let c, let x, let y): position[Int(c)] = (x, y)
		case .ifSetScrollPos(let c, let pos): scroll[Int(c)] = pos
		case .invFull(let c, _, let items) where c >= 0:
			var slots: [Int: ServerMessage.InvItem] = [:]
			for (i, it) in items.enumerated() where it.id >= 0 { slots[i] = it }
			invSlots[Int(c)] = slots
			return false
		case .invPartial(let c, _, let changes) where c >= 0:
			for ch in changes { invSlots[Int(c), default: [:]][ch.slot] = ch.item.id >= 0 ? ch.item : nil }
			return false
		case .invClear(let c) where c >= 0:
			invSlots[Int(c)] = [:]
			return false
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
	/// Per interface: layer id (or -1 for the roots) -> indices of its static children in `groups`, so a frame does not
	/// scan every component of the interface for each layer.
	var childIndex: [Int: [Int: [Int]]] = [:]
	/// Every component drawn in the last `render`, in draw order, with its
	/// screen rectangle (clipped to its parents). Used for touch hit tests.
	public internal(set) var drawn: [(component: Component, x: Int, y: Int, w: Int, h: Int)] = []
	/// The unclipped top-left corner of every component in `drawn` (inventory slots are laid out from it).
	public internal(set) var origins: [ComponentRef: (x: Int, y: Int)] = [:]
	/// The dragged component's drawing, run after everything else (rt4 draws it in a last pass).
	var deferredDrag: [(inout Raster) throws -> Void] = []
	/// Sprites drawn fully opaque even though their alpha plane is translucent. The phone shell puts the resizable
	/// side panel background (sprite 1131, 60% opaque in rt4) here so the world does not show through the tabs.
	public var opaqueSprites: Set<Int> = []
	private var opaqueFrames: [Int: SpriteFrame] = [:]
	/// Drawn in place of a type-6 model or a 3D viewport component, if set.
	public var drawModel: ((Component, Int, Int, Int, Int, inout Raster) -> Void)?
	/// Item icons for inventory components and if3 sprites with an item set.
	public private(set) lazy var icons = ItemIcons(store: store)
	/// Models of type-6 components (chat heads, items, npcs). `GameClient` wires the player and npc lookups.
	public private(set) lazy var models = ComponentModels(store: store, icons: icons)
	/// The world map the interface-755 components with client codes 1400 / 1401 draw (`WorldMap/`).
	public private(set) lazy var worldMap = WorldMap(store: store)

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
		var children: [Int: [Int]] = [:]
		for i in out.indices { if let p = out[i]?.parent { children[p, default: []].append(i) } }
		childIndex[interface] = children
		return out
	}

	public func interfaceId(named name: String) throws -> Int? {
		try store.index(ConfigStore.GraphicsArchive.interfaces).group(named: name)
	}

	/// Renders `interface` as the top level filling the raster.
	public func render(_ interface: Int, state: InterfaceState, into r: inout Raster) throws {
		r.resetClip()
		drawn.removeAll(keepingCapacity: true)
		origins.removeAll(keepingCapacity: true)
		deferredDrag.removeAll()
		worldMap.isShown = false
		try renderInterface(interface, x: 0, y: 0, w: r.width, h: r.height, state: state, into: &r)
		r.resetClip()
		for paint in deferredDrag { try paint(&r) }
		deferredDrag.removeAll()
	}

	/// The top-most interactive component under (x, y) from the last render.
	public func hitTest(x: Int, y: Int) -> Component? {
		for d in drawn.reversed() where x >= d.x && y >= d.y && x < d.x + d.w && y < d.y + d.h {
			let c = d.component
			if c.hooks["onClickRepeat"] != nil || c.hooks["onOptionClick"] != nil || !c.ops.isEmpty || c.buttonType != 0 || c.option != nil
				|| c.type == 2 || (c.events >> 11) & 0x7F != 0 || c.events & 1 != 0 {
				return c
			}
		}
		return nil
	}

	/// Touch helper (not in rt4): the centre of the nearest small interactive component within `slop` pixels of
	/// (x, y), for taps that land just beside a button. Big areas (the 3D viewport, layers, inventories) are skipped.
	public func nearestInteractive(x: Int, y: Int, slop: Int) -> (x: Int, y: Int)? {
		var best: (d: Int, x: Int, y: Int)?
		for d in drawn {
			let c = d.component
			// Only small buttons (tabs, chat filters, dialogue options) get the slop: a near miss on a big panel is more
			// likely a tap on the world beside it.
			guard d.w > 0, d.h > 0, d.w <= 64, d.h <= 40, c.type != 2, c.clientCode != 1337 else { continue }
			guard c.hooks["onOptionClick"] != nil || c.hooks["onClickRepeat"] != nil || !c.ops.isEmpty || c.buttonType != 0
				|| c.option != nil || (c.events >> 11) & 0x7F != 0 || c.events & 1 != 0 else { continue }
			let dx = max(d.x - x, 0, x - (d.x + d.w - 1)), dy = max(d.y - y, 0, y - (d.y + d.h - 1))
			let dist = max(dx, dy)
			guard dist <= slop else { continue }
			if best == nil || dist < best!.d { best = (dist, d.x + d.w / 2, d.y + d.h / 2) }
		}
		return best.map { ($0.x, $0.y) }
	}

	/// Touch helper (OSRS mobile style): when a dialogue shows "Click here to continue", the rectangle of that
	/// dialogue's interface and the continue component's centre, so a tap anywhere on the dialogue continues.
	public func dialogueContinue() -> (area: (x: Int, y: Int, w: Int, h: Int), x: Int, y: Int)? {
		guard let cont = drawn.last(where: { $0.component.type == 4 && $0.component.text.lowercased().hasPrefix("click here to continue") }) else { return nil }
		let iface = cont.component.id >> 16
		var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
		for d in drawn where d.component.id >> 16 == iface && d.w > 0 && d.h > 0 {
			minX = min(minX, d.x); minY = min(minY, d.y); maxX = max(maxX, d.x + d.w); maxY = max(maxY, d.y + d.h)
		}
		guard minX < maxX, minY < maxY else { return nil }
		return ((minX, minY, maxX - minX, maxY - minY), cont.x + cont.w / 2, cont.y + cont.h / 2)
	}

	func renderInterface(_ interface: Int, x: Int, y: Int, w: Int, h: Int, state: InterfaceState, into r: inout Raster) throws {
		let comps = try components(interface)
		try renderLayer(comps, interface: interface, parent: -1, ox: x, oy: y, pw: w, ph: h, state: state, into: &r)
	}

	func renderLayer(_ comps: [Component?], interface: Int, parent: Int, ox: Int, oy: Int, pw: Int, ph: Int, state: InterfaceState, into r: inout Raster) throws {
		let clip = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		defer { r.setClip(clip.0, clip.1, clip.2, clip.3) }
		var children: [Component] = []
		if let indices = childIndex[interface]?[parent] {
			children.reserveCapacity(indices.count)
			if state.overrides.isEmpty {
				for i in indices { children.append(comps[i]!) }
			} else {
				for i in indices { let base = comps[i]!; children.append(state.overrides[base.id] ?? base) }
			}
		}
		if parent != -1, let made = state.dynamic[parent] {
			let masks = state.childEvents[parent]
			for index in made.keys.sorted() {
				var child = made[index]!
				if let m = masks?[index] { child.events = Int(m) }
				children.append(child)
			}
		}
		for c in children {
			let isStatic = c.childIndex == -1
			if (isStatic ? state.hidden[c.id] : nil) ?? c.hidden { continue }
			var c = c
			if isStatic, let sz = state.size[c.id] { c.baseWidth = sz.w; c.baseHeight = sz.h }
			let (w, h) = c.size(parentWidth: pw, parentHeight: ph)
			var (lx, ly) = c.position(width: w, height: h, parentWidth: pw, parentHeight: ph)
			if isStatic, let p = state.position[c.id] { lx = p.x; ly = p.y }
			let x = ox + lx, y = oy + ly
			// Clip to this component (lines extend one pixel).
			let extra = c.type == 9 ? 1 : 0
			r.setClip(max(clip.0, x), max(clip.1, y), min(clip.2, x + w + extra), min(clip.3, y + h + extra))
			if c.if3 && (r.clipRight <= r.clipLeft || r.clipBottom <= r.clipTop) {
				r.setClip(clip.0, clip.1, clip.2, clip.3)
				continue
			}
			drawn.append((c, r.clipLeft, r.clipTop, r.clipRight - r.clipLeft, r.clipBottom - r.clipTop))
			origins[c.ref] = (x, y)
			var (px, py) = (x, y)
			if let d = state.componentDrag, d.ref == c.ref {
				(px, py) = (d.x, d.y)
				if !c.dragRenderBehaviour {
					// rt4 `renderComponent`: a pressed component is drawn last, floating at half opacity.
					var faded = c
					faded.alpha = 128
					deferredDrag.append { r in try self.paint(comps, faded, interface: interface, isStatic: isStatic, x: px, y: py, w: w, h: h, clip: (0, 0, r.width, r.height), state: state, into: &r) }
					r.setClip(clip.0, clip.1, clip.2, clip.3)
					continue
				}
			}
			try paint(comps, c, interface: interface, isStatic: isStatic, x: px, y: py, w: w, h: h, clip: clip, state: state, into: &r)
			r.setClip(clip.0, clip.1, clip.2, clip.3)
		}
	}

	/// Draws one component and its layer contents at (x, y), clipped to `clip` (its parent's) and itself.
	func paint(_ comps: [Component?], _ c: Component, interface: Int, isStatic: Bool, x: Int, y: Int, w: Int, h: Int, clip: (Int, Int, Int, Int), state: InterfaceState, into r: inout Raster) throws {
		let saved = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		defer { r.setClip(saved.0, saved.1, saved.2, saved.3) }
		// rt4 `Cs1ScriptRunner.renderComponent` draws a component clipped only to its parent's rectangle (text,
		// sprites and models may overhang their own box, e.g. centred dialogue lines and chat heads); only a layer's
		// children are clipped to the layer.
		r.setClip(clip.0, clip.1, clip.2, clip.3)
		try draw(c, x: x, y: y, w: w, h: h, state: state, into: &r)
		if c.type == 0 {
			r.setClip(max(clip.0, x), max(clip.1, y), min(clip.2, x + w), min(clip.3, y + h))
			let sy = (c.childIndex == -1 ? state.scroll[c.id] : nil) ?? c.scrollY
			try renderLayer(comps, interface: interface, parent: c.id, ox: x - c.scrollX, oy: y - sy, pw: w, ph: h, state: state, into: &r)
			if c.childIndex == -1, let sub = state.open[c.id] {
				try renderInterface(sub, x: x, y: y, w: w, h: h, state: state, into: &r)
			}
		}
	}

	func draw(_ c: Component, x: Int, y: Int, w: Int, h: Int, state: InterfaceState, into r: inout Raster) throws {
		let opacity = 256 - (c.alpha & 0xFF)
		let isStatic = c.childIndex == -1
		// rt4 `Cs1ScriptRunner`: layers with client code 1400 / 1401 are the world map and its overview.
		if c.type == 0 {
			if c.clientCode == 1400 { worldMap.drawMain(into: &r, x: x, y: y, w: w, h: h) }
			else if c.clientCode == 1401 { worldMap.drawOverview(into: &r, x: x, y: y, w: w, h: h) }
		}
		switch c.type {
		case 3:
			let rgb = UInt32(bitPattern: (isStatic ? state.color[c.id] : nil) ?? c.color) & 0xFFFFFF
			if c.filled { r.fillRect(x, y, w, h, rgb, opacity: opacity) } else { r.drawRect(x, y, w, h, rgb, opacity: opacity) }
		case 4:
			guard c.font != -1, let font = try store.font(c.font) else { return }
			let text = (isStatic ? state.text[c.id] : nil) ?? c.text
			let rgb = UInt32(bitPattern: (isStatic ? state.color[c.id] : nil) ?? c.color) & 0xFFFFFF
			font.drawParagraph(text, x: x, y: y, w: w, h: h, color: rgb, shadow: c.shadowed ? 0 : -1,
				halign: c.halign, valign: c.valign, lineSpacing: c.lineSpacing, opacity: 256, into: &r)
		case 2:
			drawInventory(c, x: x, y: y, state: state, into: &r)
		case 5 where c.if3 && c.objId != -1:
			// rt4 draws the item icon with the component's outline thickness and shadow colour.
			guard let icon = icons.sprite(selected: c.outlineThickness, id: c.objId, drawText: c.objDrawText, count: c.objCount, shadow: c.shadowColor) else { return }
			if c.alpha != 0 {
				r.drawScaled(icon, x: x, y: y, w: w, h: h, opacity: opacity)
			} else if w == icon.width && h == icon.height {
				r.draw(icon, x: x, y: y)
			} else {
				r.drawScaled(icon, x: x, y: y, w: w, h: h)
			}
		case 5:
			let id = (isStatic ? state.sprite[c.id] : nil) ?? c.spriteId
			guard id != -1, let sheet = try store.sprite(id), var f = sheet.frames.first else { return }
			if opaqueSprites.contains(id), f.alpha != nil {
				if let o = opaqueFrames[id] { f = o } else {
					f = SpriteFrame(width: f.width, height: f.height, xOffset: f.xOffset, yOffset: f.yOffset, innerWidth: f.innerWidth,
					                innerHeight: f.innerHeight, indices: f.indices, alpha: nil, palette: f.palette)
					opaqueFrames[id] = f
				}
			}
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
			if let hook = drawModel {
				hook(c, x, y, w, h, &r)
			} else {
				models.draw(c, anim: state.modelAnim[c.ref] ?? ModelAnim(), x: x, y: y, w: w, h: h, into: &r)
			}
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

	/// rt4 `renderComponent`, type 2: a grid of `baseWidth` x `baseHeight` 32x32 slots spaced by the
	/// margins, each showing its item's icon (black outline, 0x302020 shadow, count text), or the
	/// slot's own empty sprite for the first 20 slots when defined. The first 20 slots may also be
	/// offset by their sprite's position.
	func drawInventory(_ c: Component, x: Int, y: Int, state: InterfaceState, into r: inout Raster) {
		let items = state.invSlots[c.id] ?? [:]
		let ui = state.inventoryUI
		var slot = 0
		for row in 0..<c.baseHeight {
			for col in 0..<c.baseWidth {
				var sx = x + col * (c.invMarginX + 32), sy = y + row * (c.invMarginY + 32)
				let extra = slot < c.invSprites.count ? c.invSprites[slot] : nil
				if slot < 20, let e = extra { sx += e.x; sy += e.y }
				defer { slot += 1 }
				let dragged = ui.dragging.map { $0.component == c.id && $0.slot == slot } ?? false
				if !dragged && (sx + 32 <= r.clipLeft || sx >= r.clipRight || sy + 32 <= r.clipTop || sy >= r.clipBottom) { continue }
				if let item = items[slot], item.id >= 0 {
					// rt4: the item picked with "Use" has a white outline; the rest a black one and a drop shadow.
					let selected = ui.useSelected.map { $0.component == c.id && $0.slot == slot } ?? false
					let icon = selected
						? icons.sprite(selected: 2, id: item.id, drawText: c.objDrawText, count: Int(item.count), shadow: 0)
						: icons.sprite(selected: 1, id: item.id, drawText: c.objDrawText, count: Int(item.count), shadow: 0x302020)
					guard let icon else { continue }
					if dragged, let d = ui.dragging {
						// Drawn at half opacity where the finger is (at the start position inside the dead zone).
						r.draw(icon, x: sx + d.dx, y: sy + d.dy, opacity: 128)
					} else if let p = ui.pressed, p.component == c.id, p.slot == slot {
						r.draw(icon, x: sx, y: sy, opacity: 128)
					} else {
						r.draw(icon, x: sx, y: sy)
					}
				} else if let e = extra, e.sprite >= 0, let sheet = try? store.sprite(Int(e.sprite)), let f = sheet.frames.first {
					r.draw(f, x: sx, y: sy)
				}
			}
		}
	}

	/// rt4 `InterfaceList` per-cycle animation step for type-6 components with a sequence: `cycles` client cycles
	/// elapse, frames advance by the sequence's delays, wrapping with `replayOffset`.
	/// rt4 clientCode 327 (character design) and 328 (own player, e.g. the equipment screen): the local player's
	/// full model in its standing pose, pitched 150 and swinging its yaw by `sin(loop / 40) * 256`.
	func turnPlayerModel(_ c: Component, _ state: inout InterfaceState) {
		var m = state.overrides[c.id] ?? c
		m.modelXAngle = 150
		m.modelYAngle = Int(Foundation.sin(Double(state.clientLoop) / 40) * 256) & 0x7FF
		m.modelType = 5
		m.modelId = 2047
		let idle = models.selfLook().flatMap { look in look.basId == -1 ? nil : (try? store.bas(look.basId))??.idle } ?? -1
		if m.modelSeqId != idle {
			m.modelSeqId = idle
			state.modelAnim[c.ref] = nil
		}
		state.overrides[c.id] = m
	}

	public func advanceModelAnimations(_ state: inout InterfaceState, cycles: Int = 1) {
		state.clientLoop += cycles
		for d in drawn where d.component.type == 6 {
			let c = d.component
			if c.clientCode == 327 || c.clientCode == 328, c.childIndex == -1 { turnPlayerModel(c, &state) }
			// rt4 turns if1 models by `modelRotationSpeed` (pitch step in the high half, yaw step in the low half) per cycle.
			if c.modelRotationSpeed != 0 && !c.if3 {
				// `drawn` is the last frame's snapshot; the angles accumulate on the live copy between frames.
				var turned = (c.childIndex == -1 ? state.overrides[c.id] : state.dynamic[c.id]?[c.childIndex]) ?? c
				turned.modelXAngle = (turned.modelXAngle + (c.modelRotationSpeed >> 16) * cycles) & 0x7FF
				turned.modelYAngle = (turned.modelYAngle + Int(Int16(truncatingIfNeeded: c.modelRotationSpeed)) * cycles) & 0x7FF
				if c.childIndex == -1 {
					state.overrides[c.id] = turned
				} else if state.dynamic[c.id]?[c.childIndex] != nil {
					state.dynamic[c.id]?[c.childIndex] = turned
				}
			}
			guard c.modelSeqId != -1, let seq = try? store.seq(c.modelSeqId), !seq.frames.isEmpty, seq.frameDelays.count == seq.frames.count else { continue }
			var a = state.modelAnim[c.ref] ?? ModelAnim()
			a.cycles += cycles
			var guardCount = 0
			while a.frame < seq.frameDelays.count, a.cycles > seq.frameDelays[a.frame], guardCount < 64 {
				guardCount += 1
				a.cycles -= seq.frameDelays[a.frame]
				a.frame += 1
				if seq.frames.count <= a.frame {
					a.frame -= seq.replayOffset
					if a.frame < 0 || seq.frames.count <= a.frame { a.frame = 0 }
				}
				a.nextFrame = a.frame + 1
				if seq.frames.count <= a.nextFrame {
					a.nextFrame -= seq.replayOffset
					if a.nextFrame < 0 || seq.frames.count <= a.nextFrame { a.nextFrame = -1 }
				}
			}
			state.modelAnim[c.ref] = a
		}
	}
}
