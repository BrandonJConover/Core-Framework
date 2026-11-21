import Foundation

/// The world map's CS2 ops (rt4 `ScriptRunner` 5200-5220).
extension InterfaceScriptHost {
	/// Handles ops 5200-5220; nil for any other op.
	func performWorldMap(_ op: HostOpSpec, ints a: [Int32], strings s: [String]) -> HostResult? {
		guard op.opcode >= 5200 && op.opcode <= 5220 else { return nil }
		let wm = renderer.worldMap
		func i(_ n: Int) -> Int { n < a.count ? Int(a[n]) : 0 }
		func r(_ v: Int) -> HostResult { HostResult(ints: [Int32(truncatingIfNeeded: v)]) }
		let text = s.first ?? ""
		switch op.opcode {
		case 5200: wm.setZoom(percent: i(0))
		case 5201: return r(wm.zoomPercent)
		case 5202: wm.flash(function: i(0))
		case 5203: wm.centre(onLabelPrefix: text)
		case 5204: return HostResult(strings: [wm.labelName(startingWith: text)])
		case 5205: wm.load(group: text)
		case 5206:
			// getDungeonmap(coord): the group of the first valid map showing the tile.
			let c = i(0)
			return HostResult(strings: [wm.maps(containing: (c >> 14) & 0x3FFF, z: c & 0x3FFF).first?.group ?? ""])
		case 5207: return HostResult(strings: [wm.map(group: text)?.name ?? ""])
		case 5208: return HostResult(ints: [Int32(wm.viewWidthTiles), Int32(wm.viewHeightTiles)])
		case 5209:
			let c = wm.centreTile
			return HostResult(ints: [Int32(c.x), Int32(c.z)])
		case 5210:
			guard let m = wm.current else { return HostResult(ints: [0, 0]) }
			return HostResult(ints: [Int32(m.originX * 64), Int32(m.originZ * 64)])
		case 5211:
			guard let m = wm.current else { return HostResult(ints: [0, 0]) }
			return HostResult(ints: [Int32(m.maxX - m.minX), Int32(m.maxZ - m.minZ)])
		case 5212, 5213:
			let label = wm.nextLabel(restart: op.opcode == 5212)
			return HostResult(ints: [Int32(label?.size ?? 0)], strings: [label?.name ?? ""])
		case 5214:
			let c = i(0)
			wm.centre(onX: (c >> 14) & 0x3FFF, z: c & 0x3FFF)
		case 5215:
			let c = i(0)
			let found = wm.maps(containing: (c >> 14) & 0x3FFF, z: c & 0x3FFF).contains { $0.group.caseInsensitiveCompare(text) == .orderedSame }
			return r(found ? 1 : 0)
		case 5216:
			let f = i(0)
			if f >= 0 && f < wm.hiddenFunctions.count { wm.hiddenFunctions[f].toggle() }
		case 5217:
			let f = i(0)
			return r(f >= 0 && f < wm.hiddenFunctions.count && wm.hiddenFunctions[f] ? 1 : 0)
		case 5218: return r(wm.current?.defaultZoom ?? -1)
		case 5219: wm.centre(onLabelNamed: text)
		case 5220: return r(wm.loadPercentage == 100 ? 1 : 0)
		default: break
		}
		return HostResult()
	}
}
