/// An interface component (archive 3, group = interface id, file = component
/// index). Port of rt4 `Component.decodeIf1` / `decodeIf3`. Script hooks are
/// kept as raw argument lists for the CS2 interpreter to run later.
public struct Component {
	public enum Kind: Int {
		case layer = 0, legacyButton = 1, inventory = 2, rectangle = 3, text = 4, sprite = 5, model = 6, textInventory = 7, tooltip = 8, line = 9
	}

	/// `interface << 16 | index`.
	public let id: Int
	public var if3 = false
	public var type = 0
	public var kind: Kind? { Kind(rawValue: type) }
	public var buttonType = 0
	public var clientCode = 0
	public var baseX = 0, baseY = 0, baseWidth = 0, baseHeight = 0
	public var dynamicWidth = 0, dynamicHeight = 0
	/// rt4's deob calls these `yMode`/`xMode` the other way round; these names
	/// say what they position.
	public var horizontalMode = 0, verticalMode = 0
	/// Parent layer's full id, or -1 for a root component.
	public var parent = -1
	public var hidden = false
	public var scrollWidth = 0, scrollHeight = 0
	public var noClickThrough = false
	/// Scroll position and scroll extent (rt4 `scrollX/Y`, `scrollMaxH/V`; the
	/// extent starts as the decoded scroll size and CS2 may change it).
	public var scrollX = 0, scrollY = 0
	public var scrollMaxH: Int { get { scrollWidth } set { scrollWidth = newValue } }
	public var scrollMaxV: Int { get { scrollHeight } set { scrollHeight = newValue } }
	/// rt4 `createdComponentId`: the index of a CS2-created child, -1 for a
	/// component that comes from the cache. A created child shares its
	/// parent layer's `id`.
	public var childIndex = -1
	/// Item shown by `cc_setobject` (rt4 `objId`/`objCount`).
	public var objId = -1, objCount = 0, objDrawText = true

	// Sprite
	public var spriteId = -1, activeSpriteId = -1
	public var angle2d = 0
	public var spriteHasAlpha = false
	public var spriteTiling = false
	/// 0 = opaque, 255 = invisible (rt4 draws with 256 - alpha).
	public var alpha = 0
	public var outlineThickness = 0
	public var shadowColor: Int32 = 0
	public var vFlip = false, hFlip = false

	// Model
	public var modelId = -1, activeModelId = -1, modelSeqId = -1, activeModelSeqId = -1
	public var modelXAngle = 0, modelYAngle = 0, modelZAngle = 0, modelZoom = 0, modelYOffset = 0
	public var modelXOffset = 0, modelZOffset = 0
	public var modelOrtho = false
	public var aspectWidth = 0, aspectHeight = 0
	/// rt4 `Component.modelType` for type-6 components: 0 none, 1 model id, 2 npc head, 3 own player head,
	/// 4 item, 5 player (looked up by name hash), 6 npc body, 7 player head built from kits.
	public var modelType = 0
	/// rt4 `anInt495` / `anInt481`: the decoded screen-space shift of the model's centre, in 1/256 of the
	/// component's size relative to its aspect size (not the CS2 `modelXOffset`/`modelZOffset`).
	public var screenShiftX = 0, screenShiftY = 0
	/// rt4 `Component.anInt498`: the second model argument (kit-based heads).
	public var modelExtra = 0
	/// rt4 `ServerActiveProperties.targetParam`: the param id a spell target must have, -1 for none.
	public var targetParam = -1

	// Text
	public var font = -1
	public var text = "", activeText = ""
	public var lineSpacing = 0
	public var halign = 0, valign = 0
	public var shadowed = false
	public var color: Int32 = 0, activeColor: Int32 = 0, overColor: Int32 = 0, activeOverColor: Int32 = 0

	// Rectangle / line
	public var filled = false
	public var lineWidth = 1
	public var lineMirrored = false

	// Inventory (if1)
	public var invMarginX = 0, invMarginY = 0
	public var invSprites: [(x: Int, y: Int, sprite: Int32)?] = []
	public var invOptions: [String?] = []

	// Interaction
	public var option: String?
	public var ops: [String] = []
	public var optionBase = ""
	public var optionCircumfix = ""
	public var optionSuffix = ""
	public var events = 0
	public var dragDeadzone = 0, dragDeadtime = 0
	/// rt4 `dragRenderBehavior`: the dragged component is drawn in place at full opacity instead of floating at half.
	public var dragRenderBehaviour = false
	/// rt4 `aClass13_5` (CS2 op 1301): the layer this component may be dragged within, when the server's drag depth is 0.
	public var dragLayer: ComponentRef?

	// if1 client script (CS1)
	public var cs1Comparisons: [(opcode: Int, operand: Int)] = []
	public var cs1Scripts: [[Int]] = []

	/// CS2 hooks (rt4 `onLoad`, `onMouseOver`, ...), keyed by name.
	public var hooks: [String: [ServerMessage.ScriptArg]] = [:]
	public var triggers: [String: [Int32]] = [:]

	public static let hookNames = [
		"onLoad", "onMouseOver", "onMouseLeave", "onUseWith", "onUse", "onVarpTransmit", "onInvTransmit",
		"onStatTransmit", "onTimer", "onOptionClick", "onMouseRepeat", "onClickRepeat", "onDrag", "onRelease",
		"onHold", "onDragStart", "onDragRelease", "onScroll", "onVarcTransmit", "onVarcstrTransmit",
	]

	/// What scripts address this component by.
	public var ref: ComponentRef { ComponentRef(id: id, child: childIndex) }

	/// A blank component made by CS2 `cc_create` (rt4 `ScriptRunner` opcode 100):
	/// an if3 component of `type` that is child `index` of layer `parentId`.
	public init(parentId: Int, type: Int, index: Int) {
		id = parentId
		if3 = true
		self.type = type
		childIndex = index
		parent = parentId
	}

	public init(id: Int, data: [UInt8]) throws {
		self.id = id
		var p = Packet(data)
		if data.first == 0xFF {
			try decodeIf3(&p)
		} else {
			try decodeIf1(&p)
		}
	}

	func parentId(_ raw: Int) -> Int { raw == 65535 ? -1 : (id & ~0xFFFF) + raw }

	mutating func decodeIf3(_ p: inout Packet) throws {
		if3 = true
		p.offset += 1
		type = try p.g1()
		if type & 0x80 != 0 {
			type &= 0x7F
			_ = try p.gjstr()
		}
		clientCode = try p.g2()
		baseX = try p.g2b()
		baseY = try p.g2b()
		baseWidth = try p.g2()
		baseHeight = try p.g2()
		dynamicWidth = try p.g1b()
		dynamicHeight = try p.g1b()
		horizontalMode = try p.g1b()
		verticalMode = try p.g1b()
		parent = parentId(try p.g2())
		hidden = try p.g1() == 1
		if type == 0 {
			scrollWidth = try p.g2()
			scrollHeight = try p.g2()
			noClickThrough = try p.g1() == 1
		}
		if type == 5 {
			spriteId = Int(try p.g4())
			angle2d = try p.g2()
			let flags = try p.g1()
			spriteHasAlpha = flags & 2 != 0
			spriteTiling = flags & 1 != 0
			alpha = try p.g1()
			outlineThickness = try p.g1()
			shadowColor = try p.g4()
			vFlip = try p.g1() == 1
			hFlip = try p.g1() == 1
		}
		if type == 6 {
			modelId = nullable(try p.g2())
			modelXOffset = try p.g2b()
			modelZOffset = try p.g2b()
			modelXAngle = try p.g2()
			modelYAngle = try p.g2()
			modelYOffset = try p.g2()
			modelZoom = try p.g2()
			modelSeqId = nullable(try p.g2())
			modelOrtho = try p.g1() == 1
			modelZAngle = try p.g2()
			_ = try p.g2()
			_ = try p.g1()
			if dynamicWidth != 0 { aspectWidth = try p.g2() }
			if dynamicHeight != 0 { aspectHeight = try p.g2() }
		}
		if type == 4 {
			font = nullable(try p.g2())
			text = try p.gjstr()
			lineSpacing = try p.g1()
			halign = try p.g1()
			valign = try p.g1()
			shadowed = try p.g1() == 1
			color = try p.g4()
		}
		if type == 3 {
			color = try p.g4()
			filled = try p.g1() == 1
			alpha = try p.g1()
		}
		if type == 9 {
			lineWidth = try p.g1()
			color = try p.g4()
			lineMirrored = try p.g1() == 1
		}
		var eventMask = try p.g3()
		var key = try p.g1()
		while key != 0 {
			// Key remaps (rt4 anIntArray46/aByteArray8/7); not used on touch.
			key = (try p.g1()) | key << 8
			_ = try p.g1b()
			_ = try p.g1b()
			key = try p.g1()
		}
		optionBase = try p.gjstr()
		let opFlags = try p.g1()
		for _ in 0..<(opFlags & 0xF) { ops.append(try p.gjstr()) }
		let cursors = opFlags >> 4
		if cursors > 0 { _ = try p.g1(); _ = try p.g2() }
		if cursors > 1 { _ = try p.g1(); _ = try p.g2() }
		dragDeadzone = try p.g1()
		dragDeadtime = try p.g1()
		dragRenderBehaviour = try p.g1() == 1
		optionCircumfix = try p.gjstr()
		if (eventMask >> 11) & 0x7F != 0 {
			targetParam = nullable(try p.g2())
			_ = try p.g2(); _ = try p.g2()
		}
		events = eventMask
		eventMask = 0
		for name in Component.hookNames {
			let n = try p.g1()
			guard n > 0 else { continue }
			var args: [ServerMessage.ScriptArg] = []
			for _ in 0..<n {
				switch try p.g1() {
				case 0: args.append(.int(try p.g4()))
				case 1: args.append(.string(try p.gjstr()))
				default: break
				}
			}
			hooks[name] = args
		}
		for name in ["varp", "inv", "stat", "varc", "varcstr"] {
			let n = try p.g1()
			guard n > 0 else { continue }
			triggers[name] = try (0..<n).map { _ in try p.g4() }
		}
	}

	mutating func decodeIf1(_ p: inout Packet) throws {
		if3 = false
		type = try p.g1()
		buttonType = try p.g1()
		clientCode = try p.g2()
		baseX = try p.g2b()
		baseY = try p.g2b()
		baseWidth = try p.g2()
		baseHeight = try p.g2()
		alpha = try p.g1()
		parent = parentId(try p.g2())
		_ = try p.g2() // mouse-over redirect
		let comparisons = try p.g1()
		for _ in 0..<comparisons { cs1Comparisons.append((try p.g1(), try p.g2())) }
		let scripts = try p.g1()
		for _ in 0..<scripts {
			let n = try p.g2()
			cs1Scripts.append(try (0..<n).map { _ in let v = try p.g2(); return v == 65535 ? -1 : v })
		}
		if type == 0 {
			scrollHeight = try p.g2()
			hidden = try p.g1() == 1
		}
		if type == 1 {
			_ = try p.g2(); _ = try p.g1()
		}
		if type == 2 {
			dynamicWidth = 3; dynamicHeight = 3
			// rt4 turns the four flags into `ServerActiveProperties` bits: 28 swap, 30 item options,
			// 31 "Use", 29 replace; each option string sets bit 23 + its index.
			let swap = try p.g1(), itemOps = try p.g1(), use = try p.g1(), replace = try p.g1()
			if swap == 1 { events |= 1 << 28 }
			if itemOps == 1 { events |= 1 << 30 }
			if use == 1 { events |= 1 << 31 }
			if replace == 1 { events |= 1 << 29 }
			invMarginX = try p.g1()
			invMarginY = try p.g1()
			for _ in 0..<20 {
				if try p.g1() == 1 {
					invSprites.append((try p.g2b(), try p.g2b(), try p.g4()))
				} else {
					invSprites.append(nil)
				}
			}
			for i in 0..<5 {
				let o = try p.gjstr()
				invOptions.append(o.isEmpty ? nil : o)
				if !o.isEmpty { events |= 1 << (23 + i) }
			}
		}
		if type == 3 { filled = try p.g1() == 1 }
		if type == 4 || type == 1 {
			halign = try p.g1()
			valign = try p.g1()
			lineSpacing = try p.g1()
			font = nullable(try p.g2())
			shadowed = try p.g1() == 1
		}
		if type == 4 {
			text = try p.gjstr()
			activeText = try p.gjstr()
		}
		if type == 1 || type == 3 || type == 4 { color = try p.g4() }
		if type == 3 || type == 4 {
			activeColor = try p.g4()
			overColor = try p.g4()
			activeOverColor = try p.g4()
		}
		if type == 5 {
			spriteId = Int(try p.g4())
			activeSpriteId = Int(try p.g4())
		}
		if type == 6 {
			modelType = 1
			modelId = nullable(try p.g2())
			activeModelId = nullable(try p.g2())
			modelSeqId = nullable(try p.g2())
			activeModelSeqId = nullable(try p.g2())
			modelZoom = try p.g2()
			modelXAngle = try p.g2()
			modelYAngle = try p.g2()
		}
		if type == 7 {
			dynamicWidth = 3; dynamicHeight = 3
			halign = try p.g1()
			font = nullable(try p.g2())
			shadowed = try p.g1() == 1
			color = try p.g4()
			invMarginX = try p.g2b()
			invMarginY = try p.g2b()
			_ = try p.g1()
			for _ in 0..<5 { let o = try p.gjstr(); invOptions.append(o.isEmpty ? nil : o) }
		}
		if type == 8 { text = try p.gjstr() }
		if buttonType == 2 || type == 2 {
			optionCircumfix = try p.gjstr()
			optionSuffix = try p.gjstr()
			let mask = try p.g2() & 0x3F
			events |= mask << 11
		}
		if [1, 4, 5, 6].contains(buttonType) {
			let o = try p.gjstr()
			option = o.isEmpty ? [1: "Ok", 4: "Select", 5: "Select", 6: "Continue"][buttonType] : o
		}
		if [1, 4, 5].contains(buttonType) { events |= 0x400000 }
		if buttonType == 6 { events |= 1 }
	}

	// MARK: layout (rt4 InterfaceList.method2801 / method2291)

	public func size(parentWidth pw: Int, parentHeight ph: Int) -> (w: Int, h: Int) {
		var w = baseWidth, h = baseHeight
		switch dynamicWidth {
		case 1: w = pw - baseWidth
		case 2: w = (baseWidth * pw) >> 14
		case 3:
			if type == 2 { w = baseWidth * 32 + (baseWidth - 1) * invMarginX }
			else if type == 7 { w = baseWidth * 115 + (baseWidth - 1) * invMarginX }
		default: break
		}
		switch dynamicHeight {
		case 1: h = ph - baseHeight
		case 2: h = (ph * baseHeight) >> 14
		case 3:
			if type == 2 { h = baseHeight * 32 + (baseHeight - 1) * invMarginY }
			else if type == 7 { h = baseHeight * 12 + (baseHeight - 1) * invMarginY }
		default: break
		}
		if dynamicWidth == 4, aspectHeight != 0 { w = aspectWidth * h / aspectHeight }
		if dynamicHeight == 4, aspectWidth != 0 { h = aspectHeight * w / aspectWidth }
		return (w, h)
	}

	public func position(width w: Int, height h: Int, parentWidth pw: Int, parentHeight ph: Int) -> (x: Int, y: Int) {
		let x: Int
		switch horizontalMode {
		case 0: x = baseX
		case 1: x = baseX + (pw - w) / 2
		case 2: x = pw - baseX - w
		case 3: x = (baseX * pw) >> 14
		case 4: x = ((baseX * pw) >> 14) + (pw - w) / 2
		default: x = pw - ((pw * baseX) >> 14) - w
		}
		let y: Int
		switch verticalMode {
		case 0: y = baseY
		case 1: y = (ph - h) / 2 + baseY
		case 2: y = ph - h - baseY
		case 3: y = (baseY * ph) >> 14
		case 4: y = ((ph * baseY) >> 14) + (ph - h) / 2
		default: y = ph - ((ph * baseY) >> 14) - h
		}
		return (x, y)
	}
}
