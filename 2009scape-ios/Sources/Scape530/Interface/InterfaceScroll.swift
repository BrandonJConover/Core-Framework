import Foundation

/// `Cs1Source` for the live `GameState`: what IF1 scripts (rt4 `Cs1ScriptRunner.run`) read.
extension InterfaceScriptHost: Cs1Source {
	public func cs1BoostedLevel(_ skill: Int) -> Int { statLevel(skill) }
	public func cs1BaseLevel(_ skill: Int) -> Int { statBase(skill) }
	public func cs1Experience(_ skill: Int) -> Int { Int(game.stats[skill]?.xp ?? 0) }
	public func cs1ItemCount(component: Int, obj: Int) -> Int {
		// rt4 ignores members-only objects on a free world.
		if let t = try? store.obj(obj), t.members, !(game.account?.mapMembers ?? false) { return 0 }
		return game.interfaces.invSlots[component]?.values.reduce(0) { $1.id == obj ? $0 + Int($1.count) : $0 } ?? 0
	}
	public func cs1Varp(_ id: Int) -> Int { Int(varp(id)) }
	public func cs1Varbit(_ id: Int) -> Int {
		guard let v = (try? store.varbit(id)) ?? nil else { return 0 }
		return Int(v.value(in: varp(v.varp)))
	}
	public func cs1CombatLevel() -> Int { combatLevel() }
	public func cs1RunEnergy() -> Int { game.runEnergy }
	public func cs1Weight() -> Int { game.weight }
	public func cs1TileX() -> Int { game.selfWorld?.x ?? 0 }
	public func cs1TileZ() -> Int { game.selfWorld?.z ?? 0 }
	public func cs1LastLogAddress() -> String { "" }
}

/// Scrolling of interface layers: rt4 `InterfaceList` fires `onScroll` with the wheel rotation (~line 723) and
/// wheel-scrolls IF1 layers by 45 per notch (`method4049`, ~1220, which also handles the scrollbar's arrows and
/// thumb). Touch input adds a finger-follows-content drag on top of the same state.
extension InterfaceScriptHost {
	/// rt4 `method4049`: an IF1 scrollbar is 16 px wide, directly right of its layer.
	static let scrollbarWidth = 16
	/// rt4 `method4049`: scroll position change per wheel notch, and per press on an arrow.
	static let wheelStep = 45, arrowStep = 4

	/// A layer under a point that can scroll vertically.
	struct ScrollTarget {
		var ref: ComponentRef
		var origin: (x: Int, y: Int)
		var size: (w: Int, h: Int)
		var if1: Bool
		/// The point is on the IF1 scrollbar column rather than the content.
		var onBar: Bool
	}

	/// The current scroll position of a layer (CS2 `if_setscrollpos`, `state.scroll` and IF1 wheel scrolls write it).
	func scrollY(of c: Component) -> Int {
		(c.childIndex == -1 ? game.interfaces.scroll[c.id] : nil) ?? c.scrollY
	}

	/// Scrollable layers (scroll extent taller than the layer) whose rectangle holds (x, y), innermost first. IF1
	/// layers also take the point on their scrollbar column (rt4 accepts the wheel over it).
	func scrollTargets(x: Int, y: Int) -> [ScrollTarget] {
		var out: [ScrollTarget] = []
		var blocked = false
		for d in renderer.drawn.reversed() {
			let c = d.component
			guard c.type == 0, let o = renderer.origins[c.ref] else { continue }
			let s = size(of: c.ref)
			let bar = InterfaceRenderer.scrollbarVisible(c, height: s.h)
			let barRight = bar ? Self.scrollbarWidth : 0
			let inContent = inside(d, (x, y))
			let onBar = bar && x >= o.x + s.w && x < o.x + s.w + barRight && y >= o.y && y < o.y + s.h
			if inContent || onBar {
				if c.scrollMaxV > s.h && !blocked {
					out.append(ScrollTarget(ref: c.ref, origin: o, size: s, if1: !c.if3, onBar: onBar && !inContent))
				}
				// A layer that swallows clicks hides what is below it.
				if c.if3 && c.noClickThrough { blocked = true }
			}
		}
		return out
	}

	/// True when a vertical pan at (x, y) should scroll a layer rather than move the camera.
	public func isOverScrollable(x: Int, y: Int) -> Bool { !scrollTargets(x: x, y: y).isEmpty }

	/// Sets a layer's scroll position, clamped to its extent like rt4's layout pass does (`method4190`). Returns
	/// true when it changed.
	@discardableResult
	func setScrollY(_ t: ScrollTarget, _ y: Int) -> Bool {
		guard let c = component(t.ref) else { return false }
		let clamped = max(min(y, c.scrollMaxV - t.size.h), 0)
		guard clamped != scrollY(of: c) else { return false }
		if t.ref.child == -1 { game.interfaces.scroll[t.ref.id] = nil }
		mutate(t.ref) { $0.scrollY = clamped }
		return true
	}

	/// rt4 `InterfaceList` ~723: every component under the point with an `onScroll` hook runs it with the wheel
	/// rotation as its mouseY (positive scrolls down).
	@discardableResult
	func fireScrollHooks(x: Int, y: Int, delta: Int) -> Bool {
		var fired = false
		for d in renderer.drawn where inside(d, (x, y)) {
			guard let args = d.component.hooks["onScroll"] else { continue }
			var r = ScriptRequest(args: args)
			r.source = d.component.ref
			r.mouseY = delta
			run(r)
			fired = true
		}
		return fired
	}

	/// A mouse wheel turned by `delta` notches (positive: down) with the pointer at (x, y): rt4 runs the `onScroll`
	/// hooks of the components under it and wheel-scrolls IF1 layers 45 px per notch. True if anything took it.
	@discardableResult
	public func scrollWheel(x: Int, y: Int, delta: Int) -> Bool {
		guard delta != 0 else { return false }
		let fired = fireScrollHooks(x: x, y: y, delta: delta)
		var moved = false
		for t in scrollTargets(x: x, y: y) where t.if1 {
			if let c = component(t.ref) { setScrollY(t, scrollY(of: c) + delta * Self.wheelStep) }
			moved = true
		}
		return fired || moved
	}

	/// A finger moved `dy` pixels (positive: down) while pressing at (x, y): the innermost scrollable layer follows
	/// it (content moves with the finger; on an IF1 scrollbar the thumb does). CS2-driven lists are then told with
	/// a zero `onScroll` so their scrollbars resync. True if a layer took the drag.
	@discardableResult
	public func scrollDrag(x: Int, y: Int, dy: Int) -> Bool {
		guard let t = scrollTargets(x: x, y: y).first, let c = component(t.ref) else { return false }
		guard dy != 0 else { return true }
		let current = scrollY(of: c)
		var target = current - dy
		if t.onBar {
			// Dragging the thumb: its travel maps onto the whole extent (rt4 `method4049`).
			let thumb = InterfaceRenderer.scrollbarThumb(height: t.size.h, scrollY: current, scrollMax: c.scrollMaxV).size
			let travel = max(t.size.h - thumb - 32, 1)
			target = current + dy * (c.scrollMaxV - t.size.h) / travel
		}
		if setScrollY(t, target) { fireScrollHooks(x: x, y: y, delta: 0) }
		return true
	}

	/// rt4 `method4049` while the primary button is down: a press on an IF1 scrollbar's arrows scrolls by 4, on its
	/// track jumps the thumb to the pointer. True when the press was on a scrollbar.
	@discardableResult
	public func pressScrollbar(x: Int, y: Int) -> Bool {
		guard let t = scrollTargets(x: x, y: y).first(where: { $0.if1 && $0.onBar }), let c = component(t.ref) else { return false }
		let current = scrollY(of: c)
		let h = t.size.h
		if y < t.origin.y + 16 {
			setScrollY(t, current - Self.arrowStep)
		} else if y >= t.origin.y + h - 16 {
			setScrollY(t, current + Self.arrowStep)
		} else {
			let thumb = InterfaceRenderer.scrollbarThumb(height: h, scrollY: current, scrollMax: c.scrollMaxV).size
			let travel = max(h - thumb - 32, 1)
			setScrollY(t, (c.scrollMaxV - h) * (y - thumb / 2 - t.origin.y - 16) / travel)
		}
		return true
	}

	/// CS2 opcodes 3108 / 3109 (rt4 `Cs1ScriptRunner.method1015`): arms the drag of `ref`, grabbed at
	/// (offsetX, offsetY) inside it. Ignored while another drag is armed or the component has no drag layer.
	public func armDrag(_ ref: ComponentRef, offsetX: Int, offsetY: Int) {
		guard drag == nil, let c = component(ref), let container = dragContainer(of: c), component(container) != nil else { return }
		drag = DragState(component: ref, container: container, offsetX: offsetX, offsetY: offsetY)
		if let o = renderer.origins[ref] { game.interfaces.componentDrag = ComponentDrag(ref: ref, x: o.x, y: o.y) }
	}
}
