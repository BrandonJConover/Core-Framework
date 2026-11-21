import Foundation

/// The zoom and aspect limits CS2 sets with ops 6200-6202 (rt4 `ScriptRunner.aShort25/aShort9/aShort30/aShort27/
/// aShort22/aShort1/aShort12/aShort21`). rt4 only reads them when drawing with its GL renderer
/// (`ScriptRunner.method2314`, `Camera`), which this software port does not use, so they are kept as the
/// script left them.
public struct ViewportLimits: Equatable {
	/// 6200: zoom at the smallest and largest viewport height (`aShort25`, `aShort9`).
	public var heightZoomLow: Int16 = 256, heightZoomHigh: Int16 = 205
	/// 6201: zoom range used by `Camera` (`aShort30`, `aShort27`).
	public var cameraZoomLow: Int16 = 256, cameraZoomHigh: Int16 = 320
	/// 6202: the zoom clamp (`aShort22`, `aShort1`) and the aspect clamp (`aShort12`, `aShort21`).
	public var minZoom: Int16 = 1, maxZoom: Int16 = 32767
	public var minAspect: Int16 = 1, maxAspect: Int16 = 32767

	public init() {}

	/// rt4 op 6200.
	public mutating func set6200(_ a: Int, _ b: Int) {
		heightZoomLow = Int16(truncatingIfNeeded: a)
		if heightZoomLow <= 0 { heightZoomLow = 256 }
		heightZoomHigh = Int16(truncatingIfNeeded: b)
		if heightZoomHigh <= 0 { heightZoomHigh = 205 }
	}

	/// rt4 op 6201.
	public mutating func set6201(_ a: Int, _ b: Int) {
		cameraZoomLow = Int16(truncatingIfNeeded: a)
		if cameraZoomLow <= 0 { cameraZoomLow = 256 }
		cameraZoomHigh = Int16(truncatingIfNeeded: b)
		if cameraZoomHigh <= 0 { cameraZoomHigh = 320 }
	}

	/// rt4 op 6202.
	public mutating func set6202(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
		minZoom = Int16(truncatingIfNeeded: a)
		if minZoom <= 0 { minZoom = 1 }
		maxZoom = Int16(truncatingIfNeeded: b)
		if maxZoom <= 0 { maxZoom = 32767 } else if minZoom > maxZoom { maxZoom = minZoom }
		minAspect = Int16(truncatingIfNeeded: c)
		if minAspect <= 0 { minAspect = 1 }
		maxAspect = Int16(truncatingIfNeeded: d)
		if maxAspect <= 0 { maxAspect = 32767 } else if maxAspect < minAspect { maxAspect = minAspect }
	}
}

/// CS2 client actions that reach outside the interface layer: appearance edits, audio, packets, item search
/// (rt4 `ScriptRunner` 403-410, 3101-3202, 4210-4212, 5001-5002, 5400-5427, 6200-6302).
extension InterfaceScriptHost {
	/// rt4 `ObjTypeList.capacity`: `(groups - 1) * 256` plus the files in the last group.
	var objCapacity: Int {
		guard let idx = try? store.index(ConfigStore.Archive.objs), idx.groupCapacities.count > 0 else { return 0 }
		let last = idx.groupCapacities.count - 1
		return idx.groupCapacities[last] + last * 256
	}

	/// rt4 `Find.search`: item names containing `needle` (case-insensitive), at most 250, sorted by name. With
	/// `stockMarketOnly` only Grand Exchange items qualify. Notes, lent items and dummy items never match.
	/// nil when more than 250 match (rt4 sets the count to -1).
	func objSearch(stockMarketOnly: Bool, needle: String) -> [Int]? {
		let lowered = needle.lowercased()
		var ids: [Int] = [], names: [[UInt8]] = []
		for id in 0..<objCapacity {
			let t = ((try? store.objResolved(id)) ?? nil) ?? ObjType(id: id)
			guard !stockMarketOnly || t.stockMarket, t.certtemplate == -1, t.lentTemplate == -1, t.dummyItem == 0,
				t.name.lowercased().contains(lowered) else { continue }
			if ids.count >= 250 { return nil }
			ids.append(id)
			names.append(Cp1252.encode(t.name))
		}
		QuickChat.sort(&ids, &names, 0, ids.count - 1)
		return ids
	}

	/// rt4 `Inv.getTotalParam`: the sum of an int param over the items of a container, each weighted by its
	/// stack size when `stacks` is true.
	func invParamTotal(stacks: Bool, inv: Int, param: Int) -> Int {
		guard let slots = game.inventories[inv] else { return 0 }
		let capacity = objCapacity
		var total: Int32 = 0
		for slot in slots.keys.sorted() {
			guard let item = slots[slot], item.id >= 0, item.id < capacity,
				let t = (try? store.objResolved(item.id)) ?? nil, case let .int(v)? = t.params[param] else { continue }
			total = total &+ (stacks ? item.count &* v : v)
		}
		return Int(total)
	}

	/// rt4 `ColorUtils.rgbToHsl` via `SceneColor`, stored in the palette `ObjType.recol_p` indexes (op 5401).
	func setObjRecolour(index: Int, rgb: Int) {
		store.setRecolourPalette(index: index, hsl: SceneColor.rgbToHsl(rgb))
		onObjRecolour()
	}

	/// Handles the ops of this file; nil when `op` is not one of them.
	func performClientOps(_ op: HostOpSpec, ints a: [Int32], strings s: [String]) -> HostResult? {
		func i(_ n: Int) -> Int { n < a.count ? Int(a[n]) : 0 }
		func r(_ v: Int) -> HostResult { HostResult(ints: [Int32(truncatingIfNeeded: v)]) }
		switch op.opcode {
		// appearance (rt4 `PlayerList.self.appearance`)
		case 403: onAppearanceEdit(.identikit(feature: i(0), kit: i(1)))
		case 404: onAppearanceEdit(.colour(slot: i(0), colour: i(1)))
		case 410: onAppearanceEdit(.gender(female: i(0) != 0))
		case 3327: return r(selfFemale() ? 1 : 0)
		// misc actions
		case 3101: onAnimateSelf(i(0), i(1))
		case 3107: onClickPlayerOption(i(0), s.first ?? "")
		// audio: rt4 `SoundPlayer.play(loops = in1, id = in0, delay = in2)`, `MusicPlayer.playSong(in0)`, `playJingle(volume = in1, id = in0)`
		case 3200: onPlaySoundEffect(i(0), i(1), i(2))
		case 3201: onPlaySong(i(0))
		case 3202: onPlayJingle(i(0), i(1))
		// inventory params
		case 3331: return r(invParamTotal(stacks: false, inv: i(0), param: i(1)))
		case 3332: return r(invParamTotal(stacks: true, inv: i(0), param: i(1)))
		// the applet parameter `country`, 0 for every client we launch
		case 3629: return r(0)
		// item search (rt4 `Find`, shared with the quick chat phrase search)
		case 4210:
			let found = objSearch(stockMarketOnly: i(0) == 1, needle: s.first ?? "")
			quickChat.findResults = found
			quickChat.findIndex = found?.count ?? -1
			quickChat.findSize = 0
			return r(quickChat.findIndex)
		case 4211:
			if let results = quickChat.findResults, quickChat.findSize < quickChat.findIndex {
				defer { quickChat.findSize += 1 }
				return r(results[quickChat.findSize] & 0xFFFF)
			}
			return r(-1)
		case 4212: quickChat.findSize = 0
		// chat filters and reports
		case 5001:
			game.chatFilters = (i(0), i(1), i(2))
			send(.chatFilterSettings(public: i(0), private: i(1), trade: i(2)))
		case 5002: send(.bugReport(name37: Base37.encode(s.first ?? ""), category: i(0), flag: i(1)))
		case 5400: send(.twoStrings(s.first ?? "", s.count > 1 ? s[1] : "", i(0)))
		case 5401: setObjRecolour(index: i(0), rgb: i(1))
		case 5411: onQuit()
		case 5421: onOpenUrl(s.first ?? "", i(0) == 1)
		case 5427: menuCursors = (i(0), i(1))
		// viewport limits
		case 6200: viewportLimits.set6200(i(0), i(1))
		case 6201: viewportLimits.set6201(i(0), i(1))
		case 6202: viewportLimits.set6202(i(0), i(1), i(2), i(3))
		// rt4 `Calendar.set(year, month, day)` at 12:00 in the local zone, as days since the game launched
		case 6302:
			var cal = Calendar(identifier: .gregorian)
			cal.timeZone = .current
			var c = DateComponents()
			c.year = i(2); c.month = i(1) + 1; c.day = i(0); c.hour = 12
			guard let d = cal.date(from: c) else { return r(0) }
			return r(Int((d.timeIntervalSince1970 * 1000 / 86_400_000).rounded(.down)) - 11745)
		default: return nil
		}
		return HostResult()
	}
}
