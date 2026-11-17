import Foundation

/// The dragged if3 component, for the renderer: where it is drawn this frame (rt4 `Cs1ScriptRunner.method28`
/// computes `local123` / `local114` for `renderComponent`).
public struct ComponentDrag: Equatable {
	public var ref: ComponentRef
	/// Top-left corner on screen, clamped inside the drag layer.
	public var x: Int, y: Int
}

/// State of a pressed if3 component that may be dragged (rt4 `Cs1ScriptRunner.aClass13_14` & co).
struct DragState {
	/// rt4 `aClass13_14`: the pressed component.
	var component: ComponentRef
	/// rt4 `aClass13_1`: the layer it can be dragged within.
	var container: ComponentRef
	/// rt4 `anInt5388` / `anInt4035`: where inside the component the press happened.
	var offsetX: Int, offsetY: Int
	/// rt4 `aBoolean172`: the pointer left the dead zone after the dead time.
	var dragging = false
	/// rt4 `anInt4851`: cycles since the press.
	var cycles = 0
}

/// if3 component dragging: rt4 `Cs1ScriptRunner.method1015` (press) and `method28` (every cycle), the
/// `InterfaceList` scan that picks the drag target, and the hold/drag hooks of pressed components.
/// Touch input drives it through `beginDragGesture` / `moveDragGesture` / `endDragGesture`.
extension InterfaceScriptHost {
	enum DragResult { case none, dragged, clicked }

	/// rt4 `InterfaceList.method938`: the layer `depth` parents above `c`, `depth` coming from the server's drag depth
	/// (bits 18-20 of the events). nil without drag depth or when the chain ends early.
	func dragDepthContainer(of c: Component) -> ComponentRef? {
		let depth = (c.events >> 18) & 7
		guard depth != 0 else { return nil }
		var cur = c
		for _ in 0..<depth {
			guard cur.parent >= 0, let up = component(ComponentRef(id: cur.parent)) else { return nil }
			cur = up
		}
		return cur.ref
	}

	/// rt4 `Cs1ScriptRunner.method1836`: the drag depth layer, else the one set with CS2 op 1301.
	func dragContainer(of c: Component) -> ComponentRef? {
		dragDepthContainer(of: c) ?? c.dragLayer
	}

	func holdsPointer(_ c: Component) -> Bool {
		c.hooks["onClickRepeat"] != nil || c.hooks["onDrag"] != nil || c.hooks["onRelease"] != nil || c.hooks["onHold"] != nil
	}

	/// A press at (x, y) that may turn into a drag or a hold (a finger down that started moving). Runs the
	/// `onClickRepeat` hooks of the pressed components like rt4 does on the click and arms the drag of the first
	/// component with a drag layer. Returns false when nothing under the point cares, so the caller can do something else.
	@discardableResult
	public func beginDragGesture(x: Int, y: Int) -> Bool {
		pointer = (x, y)
		pointerHeld = true
		dragStart = (x, y)
		drag = nil
		dragTarget = nil
		heldRefs = []
		var press: [Pending] = []
		for d in renderer.drawn where inside(d, (x, y)) {
			let c = d.component
			guard c.if3 else { continue }
			if c.type == 0 && c.noClickThrough {
				// Nothing below a click-blocking layer sees the press (rt4 drops the requests queued so far).
				press.removeAll()
				heldRefs.removeAll()
				drag = nil
				continue
			}
			let o = renderer.origins[c.ref] ?? (d.x, d.y)
			if drag == nil, let container = dragContainer(of: c), component(container) != nil {
				drag = DragState(component: c.ref, container: container, offsetX: x - o.x, offsetY: y - o.y)
				game.interfaces.componentDrag = ComponentDrag(ref: c.ref, x: o.x, y: o.y)
				break
			}
			guard holdsPointer(c) else { continue }
			heldRefs.append(c.ref)
			if let args = c.hooks["onClickRepeat"] {
				var r = ScriptRequest(args: args)
				r.source = c.ref
				r.mouseX = x - o.x
				r.mouseY = y - o.y
				press.append(Pending(request: r, source: c.ref))
			}
		}
		for p in press where component(p.source) != nil { run(p.request) }
		let took = drag != nil || !heldRefs.isEmpty
		if !took { pointerHeld = false }
		return took
	}

	/// The pressed pointer moved.
	public func moveDragGesture(x: Int, y: Int) {
		pointer = (x, y)
	}

	/// The pointer lifted. The result says what the gesture was: a drag (the release hook ran, IF_DRAG went out when it
	/// ended over a drag target), or a click that never left the dead zone, which the caller treats as a tap at `dragStart`.
	public func endDragGesture(x: Int, y: Int) -> (dragged: Bool, start: (x: Int, y: Int)) {
		pointer = (x, y)
		pointerHeld = false
		var result = DragResult.none
		if drag != nil { result = stepDrag() }
		drag = nil
		dragTarget = nil
		game.interfaces.componentDrag = nil
		return (result == .dragged, dragStart)
	}

	/// rt4 `InterfaceList` scan: the last drawn component under the pointer that accepts drops (events bit 21).
	func findDragTarget() {
		dragTarget = nil
		guard let s = drag, let p = pointer else { return }
		for d in renderer.drawn where d.component.if3 && d.component.ref != s.component && inside(d, p) && (d.component.events >> 21) & 1 != 0 {
			dragTarget = d.component.ref
		}
	}

	/// rt4 `Cs1ScriptRunner.method28`: one cycle of the drag.
	func stepDrag() -> DragResult {
		guard var s = drag else { return .none }
		s.cycles += 1
		guard let comp = component(s.component), let cont = component(s.container),
			let co = renderer.origins[s.component], let ko = renderer.origins[s.container] else {
			// Not drawn this frame: rt4 gives up after one more cycle.
			drag = s.cycles > 1 ? nil : s
			if drag == nil { game.interfaces.componentDrag = nil }
			return .none
		}
		findDragTarget()
		let p = pointer ?? dragStart
		let cs = rect(of: cont), ms = rect(of: comp)
		var x = p.x - s.offsetX
		if ko.x > x { x = ko.x }
		var y = p.y - s.offsetY
		if ko.x + cs.w < x + ms.w { x = ko.x + cs.w - ms.w }
		if y < ko.y { y = ko.y }
		if ko.y + cs.h < y + ms.h { y = ko.y + cs.h - ms.h }
		let dy = y - co.y, dx = x - co.x
		let mouseX = x + cont.scrollX - ko.x, mouseY = cont.scrollY + y - ko.y
		let zone = comp.dragDeadzone
		if s.cycles > comp.dragDeadtime && (zone < dx || -zone > dx || dy > zone || dy < -zone) { s.dragging = true }
		drag = s
		game.interfaces.componentDrag = ComponentDrag(ref: s.component, x: s.dragging ? x : co.x, y: s.dragging ? y : co.y)
		if s.dragging, let args = comp.hooks["onDragStart"] {
			var r = ScriptRequest(args: args)
			r.source = s.component
			r.mouseX = mouseX
			r.mouseY = mouseY
			run(r)
		}
		guard !pointerHeld else { return .none }
		// The pointer is up.
		var result = DragResult.clicked
		if s.dragging {
			result = .dragged
			if let args = comp.hooks["onDragRelease"] {
				var r = ScriptRequest(args: args)
				r.source = s.component
				r.target = dragTarget
				r.mouseX = mouseX
				r.mouseY = mouseY
				run(r)
			}
			if let t = dragTarget, dragDepthContainer(of: comp) != nil {
				send(.ifDrag(component: comp.id, child: comp.childIndex, targetComponent: t.id, targetChild: t.child))
			}
		}
		drag = nil
		game.interfaces.componentDrag = nil
		return result
	}

	/// rt4 `InterfaceList` scan for pressed components: `onDrag` / `onHold` every cycle while the pointer is down over
	/// them, `onRelease` once it is up or left. While an if3 drag is armed they all count as released.
	func collectHeldHooks(medium: inout [Pending], low: inout [Pending]) {
		guard !heldRefs.isEmpty else { return }
		var still: [ComponentRef] = []
		for ref in heldRefs {
			guard let c = component(ref), let d = renderer.drawn.last(where: { $0.component.ref == ref }), let p = pointer else { continue }
			let o = renderer.origins[ref] ?? (d.x, d.y)
			if pointerHeld && drag == nil && inside(d, p) {
				still.append(ref)
				for hook in ["onDrag", "onHold"] {
					guard let args = c.hooks[hook] else { continue }
					var r = ScriptRequest(args: args)
					r.source = ref
					r.mouseX = p.x - o.x
					r.mouseY = p.y - o.y
					low.append(Pending(request: r, source: ref))
				}
			} else if let args = c.hooks["onRelease"] {
				var r = ScriptRequest(args: args)
				r.source = ref
				r.mouseX = p.x - o.x
				r.mouseY = p.y - o.y
				medium.append(Pending(request: r, source: ref))
			}
		}
		heldRefs = still
	}
}
