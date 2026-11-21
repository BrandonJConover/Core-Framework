import Foundation

/// Hook scanning and dispatch (rt4 `InterfaceList.method946` scan, `method1626`
/// onLoad, `client.mainUpdate` queues, `ClientProt.method4512` option clicks).
extension InterfaceScriptHost {
	// MARK: tree walk

	/// Visits the visible component tree in draw order: the top-level interface,
	/// each layer's static children, then its created children, then the
	/// interface open in it. Hidden if3 components and their subtrees are skipped.
	func walk(_ visit: (Component) -> Void) {
		guard game.interfaces.top != -1 else { return }
		walkInterface(game.interfaces.top, visit)
	}

	func walkInterface(_ iface: Int, _ visit: (Component) -> Void) {
		for id in staticChildren(iface, parent: -1) {
			if let c = component(ComponentRef(id: id)) { walkComponent(c, visit) }
		}
	}

	func walkComponent(_ c: Component, _ visit: (Component) -> Void) {
		if c.if3 && c.hidden { return }
		visit(c)
		guard c.type == 0 else { return }
		for id in staticChildren(c.id >> 16, parent: c.id) {
			if let child = component(ComponentRef(id: id)) { walkComponent(child, visit) }
		}
		if let made = game.interfaces.dynamic[c.id] {
			for index in made.keys.sorted() { if let child = made[index] { walkComponent(child, visit) } }
		}
		if let sub = game.interfaces.open[c.id] { walkInterface(sub, visit) }
	}

	// MARK: onDialogAbort / onWidgetsOpenClose

	/// rt4 `InterfaceList.runScripts(kind, iface)` / `method7`: runs every component's `onDialogAbort` (kind 0,
	/// server packet GAME_FRAME_UNK) or `onWidgetsOpenClose` (kind 1, after any sub-interface opens, closes or
	/// moves) hook in `iface`, descending into created children and the interfaces open in layers. The chatbox
	/// scripts use the latter to show the dialogue layer when a dialogue opens.
	public func runScripts(kind: Int, interface iface: Int) {
		guard iface != -1, let comps = try? renderer.components(iface) else { return }
		let hook = kind == 0 ? "onDialogAbort" : "onWidgetsOpenClose"
		for case let base? in comps {
			guard let c = component(base.ref) else { continue }
			runScripts(kind: kind, hook: hook, component: c)
		}
	}

	private func runScripts(kind: Int, hook: String, component c: Component) {
		if c.type == 0 {
			if let made = game.interfaces.dynamic[c.id] {
				for index in made.keys.sorted() { if let child = made[index] { runScripts(kind: kind, hook: hook, component: child) } }
			}
			if let sub = game.interfaces.open[c.id] { runScripts(kind: kind, interface: sub) }
		}
		if let args = c.hooks[hook] {
			var req = ScriptRequest(args: args)
			req.source = c.ref
			run(req)
		}
	}

	/// rt4 runs `runScripts(1, top)` after every sub-interface open, close and move.
	func widgetsChanged() {
		if game.interfaces.top != -1 { runScripts(kind: 1, interface: game.interfaces.top) }
	}

	// MARK: onLoad

	/// rt4 `InterfaceList.method1626`: runs every component's onLoad hook when
	/// the interface opens.
	public func runOnLoad(interface iface: Int) {
		guard iface != -1, let comps = try? renderer.components(iface) else { return }
		for case let base? in comps {
			guard let c = component(base.ref), let args = c.hooks["onLoad"] else { continue }
			var req = ScriptRequest(args: args)
			req.source = c.ref
			run(req)
		}
	}

	// MARK: client cycle

	/// One client cycle (20 ms): scans the visible tree for due hooks and runs
	/// them in rt4's priority order (timers, then release/leave, then the rest).
	public func cycle() {
		loop += 1
		transmitTimer += 1
		renderer.advanceModelAnimations(&game.interfaces)
		renderer.worldMap.cycle() // WorldMap/: zoom easing, gliding and the flash timer
		var high: [Pending] = [], medium: [Pending] = [], low: [Pending] = []
		var remapped: [(c: Component, op: Int)] = []
		walk { c in
			if c.if3, !c.keyRemapCodes.isEmpty { for op in keyRemapOptions(c) { remapped.append((c, op)) } }
			guard !c.hooks.isEmpty else { return }
			let ref = c.ref
			func queue(_ hook: String, into list: inout [Pending], key: Int = 0, char: Int = 0) {
				guard let args = c.hooks[hook] else { return }
				var req = ScriptRequest(args: args)
				req.source = ref
				req.keyCode = key
				req.keyChar = char
				list.append(Pending(request: req, source: ref))
			}
			queue("onTimer", into: &high)
			var rd = readers[ref] ?? Readers()
			if c.hooks["onVarcTransmit"] != nil, varcLog.due(reader: &rd.varc, triggers: c.triggers["varc"]) { queue("onVarcTransmit", into: &low) }
			if c.hooks["onVarcstrTransmit"] != nil, varcstrLog.due(reader: &rd.varcstr, triggers: c.triggers["varcstr"]) { queue("onVarcstrTransmit", into: &low) }
			if c.hooks["onVarpTransmit"] != nil, varpLog.due(reader: &rd.varp, triggers: c.triggers["varp"]) { queue("onVarpTransmit", into: &low) }
			if c.hooks["onInvTransmit"] != nil, invLog.due(reader: &rd.inv, triggers: c.triggers["inv"]) { queue("onInvTransmit", into: &low) }
			if c.hooks["onStatTransmit"] != nil, statLog.due(reader: &rd.stat, triggers: c.triggers["stat"]) { queue("onStatTransmit", into: &low) }
			if chatAt > rd.lastTransmit { queue("onMsg", into: &low) }
			if friendAt > rd.lastTransmit { queue("onFriendTransmit", into: &low) }
			if clanAt > rd.lastTransmit { queue("onClanTransmit", into: &low) }
			if stockAt > rd.lastTransmit { queue("onStockTransmit", into: &low) }
			if miscAt > rd.lastTransmit { queue("onMiscTransmit", into: &low) }
			rd.lastTransmit = transmitTimer
			readers[ref] = rd
			if c.hooks["onKey"] != nil {
				for k in keyQueue { queue("onKey", into: &low, key: k.code, char: k.char) }
			}
		}
		keyQueue.removeAll()
		// rt4 `ClientProt.method4512(EMPTY, -1, op, component.id)`: the component is looked up by id with child -1.
		for r in remapped { if let target = component(ComponentRef(id: r.c.id)) { clickOption(target, op: r.op) } }
		collectPointerHooks(medium: &medium, low: &low)
		collectHeldHooks(medium: &medium, low: &low)
		for p in high + medium + low where component(p.source) != nil { run(p.request) }
		if drag != nil { _ = stepDrag() }
	}

	// MARK: key remaps

	/// rt4 `InterfaceList.method1320` (if3 branch): the option slots (1...10) of `c` whose remapped key is held this cycle,
	/// honouring the modifier mask and the repeat delay, and updating the per-slot next-fire cycle.
	func keyRemapOptions(_ c: Component) -> [Int] {
		let ref = c.ref
		var next = keyRemapNext[ref]
		var fire: [Int] = []
		for i in 0..<c.keyRemapCodes.count {
			if keyboard.isPressed(c.keyRemapCodes[i]) {
				guard next == nil || loop >= next![i] else { continue }
				let m = c.keyRemapMods[i]
				guard m == 0 || ((m & 2) == 0 || keyboard.isPressed(KeyCode.alt)) && ((m & 1) == 0 || keyboard.isPressed(KeyCode.ctrl)) && ((m & 4) == 0 || keyboard.isPressed(KeyCode.shift)) else { continue }
				fire.append(i + 1)
				if next == nil { next = [Int](repeating: 0, count: c.keyRemapCodes.count) }
				let k = c.keyRemapRepeat[i]
				next![i] = k == 0 ? Int.max : loop + k
			} else if next != nil {
				next![i] = 0
			}
		}
		keyRemapNext[ref] = next
		return fire
	}

	// MARK: pointer

	/// Last pointer position in canvas pixels (hover hooks use it each cycle).
	public func pointerMoved(x: Int, y: Int) { pointer = (x, y) }
	public func pointerLeft() { pointer = nil }

	func inside(_ d: (component: Component, x: Int, y: Int, w: Int, h: Int), _ p: (x: Int, y: Int)) -> Bool {
		p.x >= d.x && p.y >= d.y && p.x < d.x + d.w && p.y < d.y + d.h
	}

	/// onMouseOver / onMouseLeave / onMouseRepeat for components under the
	/// pointer, using the rectangles of the last render.
	func collectPointerHooks(medium: inout [Pending], low: inout [Pending]) {
		for d in renderer.drawn {
			let c = d.component
			guard c.hooks["onMouseOver"] != nil || c.hooks["onMouseLeave"] != nil || c.hooks["onMouseRepeat"] != nil else { continue }
			let ref = c.ref
			let over = pointer.map { inside(d, $0) } ?? false
			func req(_ hook: String) -> Pending? {
				guard let args = c.hooks[hook], let p = pointer else { return nil }
				var r = ScriptRequest(args: args)
				r.source = ref
				r.mouseX = p.x - d.x
				r.mouseY = p.y - d.y
				return Pending(request: r, source: ref)
			}
			if over, !hovering.contains(ref) {
				hovering.insert(ref)
				if let r = req("onMouseOver") { low.append(r) }
			} else if over, let r = req("onMouseRepeat") {
				low.append(r)
			} else if !over, hovering.contains(ref) {
				hovering.remove(ref)
				if var r = c.hooks["onMouseLeave"].map({ ScriptRequest(args: $0) }) {
					r.source = ref
					medium.append(Pending(request: r, source: ref))
				}
			}
		}
	}

	// MARK: keys

	/// Queues a key for the next cycle's onKey hooks. rt4 queues typed
	/// characters as (code -1, char) and pressed keys as (code, char -1);
	/// Enter is code 84, Backspace 85.
	public func key(code: Int, char: Int) {
		if keyQueue.count < 128 { keyQueue.append((code, char)) }
	}

	// MARK: resize

	/// rt4 `InterfaceList.method3712(true)`: after the canvas changes, runs
	/// onResize for components whose size changed.
	public func resize(width: Int, height: Int) {
		guard (width, height) != (canvas.w, canvas.h) else { return }
		var before: [ComponentRef: (Int, Int)] = [:]
		walk { c in if c.hooks["onResize"] != nil { let r = rect(of: c); before[c.ref] = (r.w, r.h) } }
		canvas = (width, height)
		var low: [Pending] = []
		walk { c in
			guard let args = c.hooks["onResize"], let old = before[c.ref] else { return }
			let r = rect(of: c)
			if old != (r.w, r.h) {
				var req = ScriptRequest(args: args)
				req.source = c.ref
				low.append(Pending(request: req, source: c.ref))
			}
		}
		for p in low where component(p.source) != nil { run(p.request) }
	}

	// MARK: taps

	/// Is option `index` (0-based) of `c` clickable? rt4 `InterfaceList.getOp`
	/// shows it when the server enabled the op or an onOptionClick hook exists.
	func optionText(_ c: Component, _ index: Int) -> String? {
		guard (c.events >> (index + 1)) & 1 != 0 || c.hooks["onOptionClick"] != nil else { return nil }
		guard index < c.ops.count else { return nil }
		let t = c.ops[index].trimmingCharacters(in: .whitespaces)
		return t.isEmpty ? nil : c.ops[index]
	}

	/// A tap at (x, y): fires onClickRepeat (press) and onRelease like a click
	/// down/up pair, performs the top-most option under the finger (onOptionClick
	/// then the IF_BUTTON packet, rt4 `ClientProt.method4512`), and returns the
	/// component that took the option, if any.
	@discardableResult
	public func tap(x: Int, y: Int, hooks: Bool = true, perform: Bool = true) -> Component? {
		pointer = (x, y)
		let p = (x: x, y: y)
		var press: [Pending] = [], release: [Pending] = []
		var handled: Component?
		// Draw order, so a noClickThrough layer drops what lies beneath it.
		for d in renderer.drawn where inside(d, p) {
			let c = d.component
			if c.type == 0 && c.noClickThrough {
				press.removeAll()
				release.removeAll()
				handled = nil
			}
			func req(_ hook: String) -> Pending? {
				guard let args = c.hooks[hook] else { return nil }
				var r = ScriptRequest(args: args)
				r.source = c.ref
				r.mouseX = x - d.x
				r.mouseY = y - d.y
				return Pending(request: r, source: c.ref)
			}
			if hooks, let r = req("onClickRepeat") { press.append(r) }
			if hooks, let r = req("onRelease") { release.append(r) }
		}
		for d in renderer.drawn.reversed() where inside(d, p) && perform {
			let c = d.component
			if c.type == 0 && c.noClickThrough && handled == nil {
				// Nothing above this layer took the click; nothing below may.
				if performOption(c, localX: x - d.x, localY: y - d.y) { handled = c }
				break
			}
			if performOption(c, localX: x - d.x, localY: y - d.y) { handled = c; break }
		}
		for r in press where component(r.source) != nil { run(r.request) }
		for r in release where component(r.source) != nil { run(r.request) }
		return handled
	}

	/// The default (lowest enabled) option of `c`, if it has one.
	func performOption(_ c: Component, localX: Int, localY: Int) -> Bool {
		if c.if3 {
			// rt4 `MiniMenu.addComponentEntries`: the "Continue" entry (action 41, events bit 0) is added last, so it is the default.
			if c.events & 1 != 0 {
				send(.ifContinue(component: c.id, child: c.childIndex))
				return true
			}
			for i in 0..<min(c.ops.count, 10) where optionText(c, i) != nil {
				clickOption(c, op: i + 1)
				return true
			}
			return false
		}
		// if1 buttons (rt4 `MiniMenu.addComponentEntries`).
		switch c.buttonType {
		case 1, 4, 5: send(.ifButtonLegacy(component: c.id)); return true
		case 3: send(.closeModal); return true
		case 6: send(.ifContinue(component: c.id, child: -1)); return true
		default: return false
		}
	}

	/// rt4 `ClientProt.method4512(opBase, child, op, component)`.
	public func clickOption(_ c: Component, op: Int) {
		if let args = c.hooks["onOptionClick"] {
			var req = ScriptRequest(args: args)
			req.source = c.ref
			req.op = op
			req.opBase = c.optionBase
			run(req)
		}
		guard (c.events >> op) & 1 != 0 else { return }
		send(.ifButton(op: op, component: c.id, child: c.childIndex))
	}
}
