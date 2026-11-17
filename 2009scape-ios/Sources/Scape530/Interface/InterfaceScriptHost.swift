import Foundation

/// The CS2 host: owns the live `GameState` (and so the `InterfaceState` the
/// renderer draws), answers the interpreter's component, variable and game
/// queries, and fires interface hooks the way rt4 does.
///
/// rt4 sources: `InterfaceList` (component tree, hook scan `method946`, onLoad
/// `method1626`, layout `method2801`/`method2291`), `client.mainUpdate` (hook
/// queues: timer first, then release/leave, then the rest), `ClientProt.method4512`
/// (option clicks), `Protocol` (var/inventory/stat transmit bookkeeping) and
/// `ScriptRunner` (what each opcode does to a `Component`).
public final class InterfaceScriptHost: ScriptHost {
	public let store: ConfigStore
	public let renderer: InterfaceRenderer
	/// Everything the UI shows; `game.interfaces` is what gets rendered.
	public var game = GameState()
	/// Canvas size in game pixels (rt4 `GameShell.canvasWidth/Height`).
	public var canvas = (w: 765, h: 503)
	/// rt4 `client.loop`: client cycles (20 ms each) since start.
	public internal(set) var loop = 0
	/// rt4 `InterfaceList.transmitTimer`.
	public internal(set) var transmitTimer = 1
	public private(set) var runner: ScriptRunner!

	// MARK: callbacks to the platform

	/// Outgoing client packets (IF_BUTTON, resume dialogs, ...).
	public var send: (ClientMessage) -> Void = { _ in }
	/// CS2 `directlogin(user, password, flag)` (opcode 5600).
	public var onDirectLogin: (_ user: String, _ password: String) -> Void = { _, _ in }
	/// Called with text for chat-style notices and script errors.
	public var log: (String) -> Void = { _ in }
	/// Script failures since the last `takeErrors()`; scripts that fail are
	/// dropped like rt4 does (it reports and carries on).
	public private(set) var errors: [String] = []

	// MARK: login state read by CS2 (rt4 `LoginManager`)

	/// rt4 `LoginManager.reply`: -2 idle, -3 connecting, 2 ok, 3 bad credentials, ...
	public var loginReply: Int32 = -2
	public var loginDisallowResult: Int32 = -1
	/// rt4 `Player.worldId` shown on the login screen.
	public var worldId: Int32 = 1

	// MARK: client settings

	/// Options-tab settings (rt4 `Preferences`), edited by cs2 ops 6001-6028.
	public var prefs = ClientPreferences()
	/// Told after a setting changes so the platform can apply it (volumes to audio, brightness to the rasteriser).
	public var onPreferenceChange: (ClientPreferences.Change) -> Void = { _ in }
	/// State derived from varps with a `clientCode` (rt4 `VarpDomain.refreshMagicVarp`).
	public internal(set) var varpClient = VarpClientState()
	/// Called after a varp with a non-zero `clientCode` changed, with that code and the new value.
	public var onVarpClientCode: (_ code: Int, _ value: Int) -> Void = { _, _ in }

	// MARK: variables

	var varcs: [Int: Int32] = [:]
	var varcstrs: [Int: String] = [:]
	var varpLog = TransmitLog(), invLog = TransmitLog(), statLog = TransmitLog()
	var varcLog = TransmitLog(), varcstrLog = TransmitLog()
	var readers: [ComponentRef: Readers] = [:]
	var openTypes: [Int: Int] = [:]
	/// IF_SETEVENTS masks for child ranges of a component: id -> [(start, end, mask)].
	var slotEvents: [Int: [(start: Int, end: Int, mask: Int32)]] = [:]
	var keyQueue: [(code: Int, char: Int)] = []
	/// rt4 `Chat.transmitAt` and friends: the transmit timer value of the last change.
	var chatAt = 0, friendAt = 0, clanAt = 0, miscAt = 0
	var hovering: Set<ComponentRef> = []
	/// if3 drag state (rt4 `Cs1ScriptRunner.aClass13_14` & co), see `ComponentDrag.swift`.
	var drag: DragState?
	/// rt4 `InterfaceList.aClass13_12`: the drag target under the pointer this cycle.
	var dragTarget: ComponentRef?
	/// The pointer is down on a gesture started with `beginDragGesture` (rt4 `Mouse.pressedButton == 1`).
	var pointerHeld = false
	var dragStart = (x: 0, y: 0)
	/// Components pressed by the gesture that track hold and drag hooks (rt4 `Component.aBoolean24`).
	var heldRefs: [ComponentRef] = []
	/// Quick chat phrase being composed and the phrase search (rt4 `ScriptRunner.activePhrase`, `Find`).
	var quickChat = QuickChatState()
	var pointer: (x: Int, y: Int)?
	/// Children per interface: `[interface: [parent id: [component index]]]`.
	var childLists: [Int: [Int: [Int]]] = [:]

	struct TransmitLog {
		var writer = 0
		var ring = [Int](repeating: 0, count: 32)
		mutating func note(_ id: Int) { ring[writer & 31] = id; writer += 1 }
		/// rt4's reader check: due if anything new was logged, and (when the
		/// hook names triggers and fewer than 32 are pending) one matches.
		func due(reader: inout Int, triggers: [Int32]?) -> Bool {
			guard writer > reader else { return false }
			defer { reader = writer }
			guard let t = triggers, writer - reader <= 32 else { return true }
			for i in reader..<writer where t.contains(Int32(truncatingIfNeeded: ring[i & 31])) { return true }
			return false
		}
	}

	struct Readers {
		var varp = 0, inv = 0, stat = 0, varc = 0, varcstr = 0
		var lastTransmit = -1
	}

	struct Pending {
		var request: ScriptRequest
		var source: ComponentRef
	}

	public init(store: ConfigStore) {
		self.store = store
		renderer = InterfaceRenderer(store: store)
		runner = ScriptRunner(store: store, host: self)
	}

	public func takeErrors() -> [String] {
		defer { errors.removeAll() }
		return errors
	}

	// MARK: running scripts

	/// rt4 `ScriptRunner.run(HookRequest)`; failures are recorded, not thrown.
	@discardableResult
	public func run(_ request: ScriptRequest) -> Bool {
		do {
			try runner.run(request, maxCycles: 2_000_000)
			return true
		} catch {
			let id: String
			if case .int(let s)? = request.args.first { id = "\(s)" } else { id = "?" }
			errors.append("script \(id): \(error)")
			log("script \(id): \(error)")
			return false
		}
	}

	/// Runs script `id` with arguments, as the RUNCLIENTSCRIPT packet does
	/// (rt4 `Protocol` opcode `RUN_CS2`: the server's arguments become the hook args).
	public func runScript(_ id: Int32, _ args: [ServerMessage.ScriptArg]) {
		run(ScriptRequest(args: [.int(id)] + args))
	}

	// MARK: server packets

	/// Folds a server message into the game state and fires the hooks rt4 would:
	/// onLoad when an interface opens, transmit bookkeeping for vars, inventories
	/// and stats, RUNCLIENTSCRIPT.
	public func apply(_ m: ServerMessage) {
		switch m {
		case .ifOpenTop(let id, _):
			game.interfaces.top = id
			game.interfaces.open = [:]
			openTypes = [:]
			runOnLoad(interface: id)
		case let .ifOpenSub(parent, component, type):
			game.interfaces.open[Int(parent)] = component
			openTypes[Int(parent)] = type
			runOnLoad(interface: component)
		case .ifCloseSub(let parent):
			game.interfaces.open[Int(parent)] = nil
			openTypes[Int(parent)] = nil
		case .ifSetHide(let c, let h): mutate(ComponentRef(id: Int(c))) { $0.hidden = h }
		case .ifSetText(let c, let t): mutate(ComponentRef(id: Int(c))) { $0.text = t }
		case .ifSetColour(let c, let col):
			// IF_SETCOLOUR carries RGB555.
			let r = (col >> 10 & 0x1F) << 3, g = (col >> 5 & 0x1F) << 3, b = (col & 0x1F) << 3
			mutate(ComponentRef(id: Int(c))) { $0.color = Int32(r << 16 | g << 8 | b) }
		case .ifSetPosition(let c, let x, let y): mutate(ComponentRef(id: Int(c))) { $0.baseX = x; $0.baseY = y }
		case .ifSetScrollPos(let c, let pos): mutate(ComponentRef(id: Int(c))) { $0.scrollY = max(pos, 0) }
		case let .ifSetEvents(c, start, end, mask):
			if start == -1 && end == -1 {
				mutate(ComponentRef(id: Int(c))) { $0.events = Int(mask) }
			} else {
				slotEvents[Int(c), default: []].append((start, end, mask))
			}
		case let .ifSetObject(c, obj, count): mutate(ComponentRef(id: Int(c))) { $0.objId = obj; $0.objCount = Int(count) }
		case let .ifSetModel(c, model): mutate(ComponentRef(id: Int(c))) { $0.modelType = 1; $0.modelId = model }
		case let .ifSetNpcHead(c, npc): mutate(ComponentRef(id: Int(c))) { $0.modelType = 2; $0.modelId = npc }
		case .ifSetPlayerHead(let c): mutate(ComponentRef(id: Int(c))) { $0.modelType = 3; $0.modelId = 0 }
		case let .ifSetAnim(c, seq):
			// rt4: a new sequence (or -1) restarts the playback.
			let ref = ComponentRef(id: Int(c))
			if component(ref)?.modelSeqId != seq || seq == -1 { game.interfaces.modelAnim[ref] = nil }
			mutate(ref) { $0.modelSeqId = seq }
		case let .runClientScript(id, args): runScript(id, args)
		case .gameMessage: game.apply(m); chatAt = transmitTimer
		case .friendlistLoaded, .updateFriend, .ignoreList:
			game.ownWorld = Int(worldId)
			game.apply(m)
			friendAt = transmitTimer
			if case .updateFriend = m { chatAt = transmitTimer }
		case .joinClanChat, .updateClan: game.apply(m); clanAt = transmitTimer
		case .rebootTimer: game.apply(m); miscAt = transmitTimer
		case .varp(let id, let v): setVarp(id, v)
		case let .varbit(id, v): writeVarbit(id, v)
		case let .varc(id, v): setVarc(id, v)
		case .resetClientVarcache:
			resetVarps()
			varpLog.writer += 32
		case .forceVarpRefresh: varpLog.writer += 32
		case .updateStat(let s, _, _):
			game.apply(m)
			statLog.note(s)
		case .invFull(_, let inv, _), .invPartial(_, let inv, _):
			game.apply(m)
			invLog.note(inv & 0x7FFF)
		default:
			game.apply(m)
		}
	}

	/// Folds a session event (messages go through `apply(_: ServerMessage)`).
	public func apply(_ e: GameSession.Event) {
		if case .message(let m) = e { apply(m) } else { game.apply(e) }
	}

	// MARK: components

	/// The cache component `id` (`interface << 16 | index`).
	func base(_ id: Int) -> Component? {
		guard id >= 0, let comps = try? renderer.components(id >> 16) else { return nil }
		let i = id & 0xFFFF
		return i < comps.count ? comps[i] : nil
	}

	/// The component as scripts currently see it (rt4 `InterfaceList.getComponent`/`method1418`).
	public func component(_ ref: ComponentRef) -> Component? {
		if ref.child == -1 { return game.interfaces.overrides[ref.id] ?? base(ref.id) }
		return game.interfaces.dynamic[ref.id]?[ref.child]
	}

	func mutate(_ ref: ComponentRef, _ f: (inout Component) -> Void) {
		if ref.child == -1 {
			guard var c = game.interfaces.overrides[ref.id] ?? base(ref.id) else { return }
			f(&c)
			game.interfaces.overrides[ref.id] = c
		} else if var c = game.interfaces.dynamic[ref.id]?[ref.child] {
			f(&c)
			game.interfaces.dynamic[ref.id]?[ref.child] = c
		}
	}

	/// Ids of the static children of layer `parent` in interface `iface`
	/// (`parent` -1: the interface's root components), in index order.
	func staticChildren(_ iface: Int, parent: Int) -> [Int] {
		if childLists[iface] == nil {
			var lists: [Int: [Int]] = [:]
			if let comps = try? renderer.components(iface) {
				for case let c? in comps { lists[c.parent, default: []].append(c.id) }
			}
			childLists[iface] = lists
		}
		return childLists[iface]?[parent] ?? []
	}

	// MARK: layout (rt4 InterfaceList.update / method4668)

	/// Size of the container a component is laid out in: its parent layer, the
	/// component an interface is opened in, or the canvas.
	func parentSize(of c: Component) -> (w: Int, h: Int) {
		if c.childIndex != -1 { return size(of: ComponentRef(id: c.id)) }
		if c.parent != -1 { return size(of: ComponentRef(id: c.parent)) }
		let iface = c.id >> 16
		if iface == game.interfaces.top { return canvas }
		if let container = game.interfaces.open.first(where: { $0.value == iface })?.key {
			return size(of: ComponentRef(id: container))
		}
		return canvas
	}

	func size(of ref: ComponentRef) -> (w: Int, h: Int) {
		guard let c = component(ref) else { return (0, 0) }
		let p = parentSize(of: c)
		return c.size(parentWidth: p.w, parentHeight: p.h)
	}

	/// Position relative to the parent plus size, as rt4 computes `x/y/width/height`.
	func rect(of c: Component) -> (x: Int, y: Int, w: Int, h: Int) {
		let p = parentSize(of: c)
		let s = c.size(parentWidth: p.w, parentHeight: p.h)
		let pos = c.position(width: s.w, height: s.h, parentWidth: p.w, parentHeight: p.h)
		return (pos.x, pos.y, s.w, s.h)
	}

	// MARK: ScriptHost: variables

	public func varp(_ id: Int) -> Int32 { game.varps[id] ?? 0 }

	public func setVarp(_ id: Int, _ value: Int32) {
		if (game.varps[id] ?? 0) != value || game.varps[id] == nil { varpLog.note(id) }
		game.varps[id] = value
		refreshMagicVarp(id)
	}

	func writeVarbit(_ id: Int, _ value: Int32) {
		guard let v = try? store.varbit(id) else { return }
		let width = v.endBit - v.startBit
		let mask: UInt32 = width >= 31 ? 0xFFFF_FFFF : (1 << UInt32(width + 1)) - 1
		let cur = UInt32(bitPattern: varp(v.varp))
		let new = (cur & ~(mask << UInt32(v.startBit))) | ((UInt32(bitPattern: value) & mask) << UInt32(v.startBit))
		setVarp(v.varp, Int32(bitPattern: new))
	}

	public func varc(_ id: Int) -> Int32 { varcs[id] ?? 0 }
	public func setVarc(_ id: Int, _ value: Int32) {
		varcs[id] = value
		varcLog.note(id)
	}
	public func varcstr(_ id: Int) -> String { varcstrs[id] ?? "" }
	public func setVarcstr(_ id: Int, _ value: String) {
		varcstrs[id] = value
		varcstrLog.note(id)
	}

	// MARK: ScriptHost: component tree

	public func componentExists(_ id: Int) -> Bool { base(id) != nil }

	public func createChild(of parent: Int, type: Int, index: Int) throws -> ComponentRef {
		guard base(parent) != nil else { throw ScriptRunner.StackFault(message: "cc_create on missing component \(parent)") }
		if index > 0, game.interfaces.dynamic[parent]?[index - 1] == nil {
			throw ScriptRunner.StackFault(message: "Gap at:\(index - 1)")
		}
		game.interfaces.dynamic[parent, default: [:]][index] = Component(parentId: parent, type: type, index: index)
		return ComponentRef(id: parent, child: index)
	}

	public func deleteChild(_ ref: ComponentRef) throws {
		game.interfaces.dynamic[ref.id]?[ref.child] = nil
		hovering.remove(ref)
		readers[ref] = nil
	}

	public func deleteChildren(of parent: Int) {
		for index in game.interfaces.dynamic[parent]?.keys ?? [:].keys {
			let r = ComponentRef(id: parent, child: index)
			hovering.remove(r)
			readers[r] = nil
		}
		game.interfaces.dynamic[parent] = nil
	}

	public func child(of id: Int, index: Int) -> ComponentRef? {
		if index == -1 { return base(id) == nil ? nil : ComponentRef(id: id) }
		return game.interfaces.dynamic[id]?[index] == nil ? nil : ComponentRef(id: id, child: index)
	}

	public func childCount(of id: Int) -> Int {
		guard let made = game.interfaces.dynamic[id] else { return 0 }
		var n = 0
		while made[n] != nil { n += 1 }
		return n
	}

	public func isInterfaceOpen(parent: Int, interface: Int?) -> Bool {
		guard let open = game.interfaces.open[parent] else { return false }
		return interface.map { $0 == open } ?? true
	}

	// MARK: ScriptHost: component properties

	/// Debug: sees every component setter call.
	public var traceSet: ((ComponentRef, ComponentSetter, [Int32]) -> Void)?

	public func set(_ ref: ComponentRef, _ setter: ComponentSetter, _ a: [Int32]) {
		traceSet?(ref, setter, a)
		func i(_ n: Int) -> Int { n < a.count ? Int(a[n]) : 0 }
		let rect = component(ref).map { self.rect(of: $0) }
		mutate(ref) { c in
			switch setter {
			case .position:
				c.baseX = i(0); c.baseY = i(1)
				// Runner passes [x, y, rt4 xMode, rt4 yMode]; rt4's xMode positions y.
				c.verticalMode = i(2); c.horizontalMode = i(3)
			case .size:
				c.baseWidth = i(0); c.baseHeight = i(1)
				c.dynamicWidth = i(2); c.dynamicHeight = i(3)
			case .hidden: c.hidden = i(0) == 1
			case .aspect: c.aspectWidth = i(0); c.aspectHeight = i(1)
			case .noClickThrough: c.noClickThrough = i(0) == 1
			case .scrollPos:
				// rt4 clamps to the scroll extent beyond the visible size.
				let w = rect?.w ?? 0, h = rect?.h ?? 0
				c.scrollX = max(min(i(0), c.scrollMaxH - w), 0)
				c.scrollY = max(min(i(1), c.scrollMaxV - h), 0)
			case .rgb: c.color = a[0]
			case .filled: c.filled = i(0) == 1
			case .trans: c.alpha = i(0)
			case .lineWidth: c.lineWidth = i(0)
			case .sprite: c.spriteId = i(0)
			case .angle2d: c.angle2d = i(0)
			case .spriteTiling: c.spriteTiling = i(0) == 1
			case .model: c.modelType = 1; c.modelId = i(0)
			case .modelRotation:
				c.modelXOffset = i(0); c.modelZOffset = i(1); c.modelXAngle = i(2)
				c.modelYAngle = i(3); c.modelYOffset = i(4); c.modelZoom = i(5)
			case .animation: c.modelSeqId = i(0)
			case .modelOrtho: c.modelOrtho = i(0) == 1
			case .font: c.font = i(0)
			case .textAlignment: c.halign = i(0); c.valign = i(1); c.lineSpacing = i(2)
			case .shadowed: c.shadowed = i(0) == 1
			case .outlineThickness: c.outlineThickness = i(0)
			case .shadowColor: c.shadowColor = a[0]
			case .vFlip: c.vFlip = i(0) == 1
			case .hFlip: c.hFlip = i(0) == 1
			case .scrollMax: c.scrollMaxH = i(0); c.scrollMaxV = i(1)
			case .hasAlpha: c.spriteHasAlpha = i(0) == 1
			case .modelZoom: c.modelZoom = i(0)
			case .item:
				if i(0) == -1 {
					c.objId = -1
				} else {
					c.objId = i(0); c.objCount = i(1); c.objDrawText = i(2) != 0
				}
			case .npcHead: c.modelType = 2; c.modelId = i(0)
			case .selfHead: c.modelType = 3; c.modelId = 0
			case .otherPlayerHead: c.modelType = 6; c.modelId = i(0)
			case .playerFull: c.modelType = 5; c.modelId = i(0)
			case .dragDeadZone: c.dragDeadzone = i(0)
			case .dragDeadTime: c.dragDeadtime = i(0)
			case .opEnabled:
				let bit = i(0) + 1
				c.events = i(1) != 0 ? c.events | (1 << bit) : c.events & ~(1 << bit)
			case .draggable: c.dragLayer = child(of: i(0), index: i(1))
			case .dragRenderBehaviour: c.dragRenderBehaviour = i(0) == 1
			case .opcode1121, .opcode1308: break
			}
		}
	}

	public func setString(_ ref: ComponentRef, _ setter: ComponentStringSetter, _ value: String) {
		mutate(ref) { c in
			switch setter {
			case .text: c.text = value
			case .optionBase: c.optionBase = value
			case .optionCircumfix: c.optionCircumfix = value
			}
		}
	}

	public func setOption(_ ref: ComponentRef, slot: Int, _ text: String) {
		mutate(ref) { c in
			while c.ops.count <= slot { c.ops.append("") }
			c.ops[slot] = text
		}
	}

	public func clearOptions(_ ref: ComponentRef) { mutate(ref) { $0.ops = [] } }

	static let triggerKey = ["onVarpTransmit": "varp", "onInvTransmit": "inv", "onStatTransmit": "stat",
		"onVarcTransmit": "varc", "onVarcstrTransmit": "varcstr"]

	public func setHook(_ ref: ComponentRef, _ hook: String, args: [ServerMessage.ScriptArg]?, triggers: [Int32]?) {
		mutate(ref) { c in
			c.hooks[hook] = args
			if let key = Self.triggerKey[hook] { c.triggers[key] = triggers }
		}
	}

	public func get(_ ref: ComponentRef, _ getter: ComponentGetter) -> Int32 {
		guard let c = component(ref) else { return 0 }
		switch getter {
		case .x: return Int32(rect(of: c).x)
		case .y: return Int32(rect(of: c).y)
		case .width: return Int32(rect(of: c).w)
		case .height: return Int32(rect(of: c).h)
		case .hidden: return c.hidden ? 1 : 0
		case .layer: return Int32(c.childIndex != -1 ? c.id : c.parent)
		case .scrollX: return Int32(c.scrollX)
		case .scrollY: return Int32(c.scrollY)
		case .scrollMaxH: return Int32(c.scrollMaxH == 0 ? rect(of: c).w : c.scrollMaxH)
		case .scrollMaxV: return Int32(c.scrollMaxV == 0 ? rect(of: c).h : c.scrollMaxV)
		case .modelZoom: return Int32(c.modelZoom)
		case .modelXAngle: return Int32(c.modelXAngle)
		case .modelYOffset: return Int32(c.modelYOffset)
		case .modelYAngle: return Int32(c.modelYAngle)
		case .alpha: return Int32(c.alpha)
		case .modelXOffset: return Int32(c.modelXOffset)
		case .modelZOffset: return Int32(c.modelZOffset)
		case .spriteId: return Int32(c.spriteId)
		case .objId: return Int32(c.objId)
		case .objCount: return Int32(c.objCount)
		case .childIndex: return Int32(c.childIndex)
		case .targetMask: return Int32((c.events >> 11) & 0x3F)
		}
	}

	public func text(of ref: ComponentRef) -> String { component(ref)?.text ?? "" }

	public func option(of ref: ComponentRef, slot: Int) -> String {
		guard let c = component(ref), slot >= 0, slot < c.ops.count else { return "" }
		return c.ops[slot]
	}

	public func optionBase(of ref: ComponentRef) -> String { component(ref)?.optionBase ?? "" }

	// MARK: ScriptHost: fonts

	public func paragraphLineCount(font: Int, text: String, width: Int) -> Int32 {
		guard let f = try? store.font(font) else { return 1 }
		return Int32(f.split(Cp1252.encode(text), maxWidth: width).count)
	}

	public func maxLineWidth(font: Int, text: String, width: Int) -> Int32 {
		guard let f = try? store.font(font) else { return 0 }
		var widest = 0
		for line in f.split(Cp1252.encode(text), maxWidth: width) { widest = max(widest, f.width(line)) }
		return Int32(widest)
	}
}
