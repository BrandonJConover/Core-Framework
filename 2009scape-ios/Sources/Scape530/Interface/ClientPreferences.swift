import Foundation

/// The client settings the Options interface edits through cs2 (rt4 `Preferences`), with the rt4 defaults.
public struct ClientPreferences: Equatable {
	/// 1 (brightest) to 4; rt4 maps it to a rasteriser gamma of 0.9 / 0.8 / 0.7 / 0.6.
	public var brightness = 3
	/// 0...127 (0 = off).
	public var soundEffectVolume = 127
	/// 0...255 (0 = off).
	public var musicVolume = 255
	/// 0...127 (0 = off).
	public var ambientSoundsVolume = 127
	public var allLevelsVisible = true
	public var neverRemoveRoofs = false
	public var removeRoofsSelectively = true
	public var showGroundDecorations = true
	public var highDetailTextures = true
	public var manyIdleAnimations = true
	public var flickeringEffects = true
	public var manyGroundTextures = true
	public var characterShadows = true
	/// 0...2
	public var sceneryShadows = 2
	public var highDetailLighting = true
	public var highWaterDetail = true
	public var fogEnabled = true
	/// 0...2
	public var antiAliasing = 0
	public var stereo = true
	/// 0...2 (rt4 `Preferences.setParticles`)
	public var particles = 2
	public var cursorsEnabled = true

	// Fields rt4 `Preferences` persists but the Options tab does not edit; kept so a decode/encode round trip is exact.
	/// rt4 `Preferences.windowMode` (also stored as the anti-aliasing mode on decode).
	public var windowMode = 0
	public var fullScreenWidth = 0
	public var fullScreenHeight = 0
	public var lastWorldId = 0
	public var favoriteWorlds = 0
	public var safeMode = false
	/// rt4 `Preferences.aBoolean63` (unnamed in rt4).
	public var unknownFlag = false
	public var buildArea = 0
	public var hdr = false
	/// rt4 `Preferences.sentToServer`: false after a setter op until `Protocol` sent packet 98 (not persisted).
	public var sentToServer = true

	public init() {}

	// MARK: rt4 `Preferences.encode` / `decode` / `toInt`

	/// rt4 `Preferences.encode`: the 33-byte version 11 record written to the "runescape" preferences file.
	public func encode() -> [UInt8] {
		var p = Packet(capacity: 34)
		func b(_ v: Bool) -> Int { v ? 1 : 0 }
		p.p1(11)
		p.p1(brightness)
		p.p1(b(allLevelsVisible))
		p.p1(b(removeRoofsSelectively))
		p.p1(b(showGroundDecorations))
		p.p1(b(highDetailTextures))
		p.p1(b(manyIdleAnimations))
		p.p1(b(flickeringEffects))
		p.p1(b(manyGroundTextures))
		p.p1(b(characterShadows))
		p.p1(sceneryShadows)
		p.p1(b(highDetailLighting))
		p.p1(b(highWaterDetail))
		p.p1(b(fogEnabled))
		p.p1(windowMode)
		p.p1(b(stereo))
		p.p1(soundEffectVolume)
		p.p1(musicVolume)
		p.p1(ambientSoundsVolume)
		p.p2(fullScreenWidth)
		p.p2(fullScreenHeight)
		p.p1(particles)
		p.p4(Int32(truncatingIfNeeded: lastWorldId))
		p.p1(favoriteWorlds)
		p.p1(b(safeMode))
		p.p1(b(unknownFlag))
		p.p1(buildArea)
		p.p1(b(hdr))
		p.p1(b(cursorsEnabled))
		return p.written
	}

	/// rt4 `Preferences.decode`: reads any record version 0...11 over `self` (fields a short or unknown record
	/// does not carry keep their value). Too-short or out-of-range records change nothing.
	public mutating func decode(_ data: [UInt8]) {
		guard let version = data.first, version <= 11 else { return }
		let lengths = [19, 23, 22, 23, 24, 28, 28, 29, 30, 31, 32, 33]
		guard data.count - 1 >= lengths[Int(version)] else { return }
		var i = 1
		func g1() -> Int { defer { i += 1 }; return Int(data[i]) }
		func g2() -> Int { let v = g1() << 8; return v | g1() }
		func g4() -> Int { let v = g2() << 16; return Int(Int32(truncatingIfNeeded: v | g2())) }
		brightness = min(max(g1(), 1), 4)
		allLevelsVisible = g1() == 1
		removeRoofsSelectively = g1() == 1
		showGroundDecorations = g1() == 1
		highDetailTextures = g1() == 1
		manyIdleAnimations = g1() == 1
		flickeringEffects = g1() == 1
		manyGroundTextures = g1() == 1
		characterShadows = g1() == 1
		sceneryShadows = min(g1(), 2)
		if version < 2 {
			highDetailLighting = g1() == 1
			_ = g1()
		} else {
			highDetailLighting = g1() == 1
		}
		highWaterDetail = g1() == 1
		fogEnabled = g1() == 1
		windowMode = min(g1(), 2)
		antiAliasing = windowMode
		stereo = g1() == 1
		soundEffectVolume = min(g1(), 127)
		musicVolume = g1()
		ambientSoundsVolume = min(g1(), 127)
		if version >= 1 { fullScreenWidth = g2(); fullScreenHeight = g2() }
		if version >= 3 && version < 6 { _ = g1() }
		if version >= 4 { particles = g1() }
		if version >= 5 { lastWorldId = g4() }
		if version >= 6 { favoriteWorlds = g1() }
		if version >= 7 { safeMode = g1() == 1 }
		if version >= 8 { unknownFlag = g1() == 1 }
		if version >= 9 { buildArea = g1() }
		if version >= 10 { hdr = g1() != 0 }
		if version >= 11 { cursorsEnabled = g1() != 0 }
	}

	/// rt4 `Preferences.toInt`: the bit set sent to the server in the login block and as packet 98.
	public func toInt() -> Int32 {
		func b(_ v: Bool, _ shift: Int) -> Int { (v ? 1 : 0) << shift }
		let v = b(stereo, 19) + b(fogEnabled, 16) + b(highWaterDetail, 15) + b(highDetailLighting, 13)
			+ b(characterShadows, 10) + b(manyGroundTextures, 9) + b(manyIdleAnimations, 7) + b(highDetailTextures, 6)
			+ b(showGroundDecorations, 5) + b(allLevelsVisible, 3) + (brightness & 7) + b(removeRoofsSelectively, 4)
			+ b(flickeringEffects, 8) + ((sceneryShadows & 3) << 11) + b(soundEffectVolume != 0, 20)
			+ b(musicVolume != 0, 21) + b(ambientSoundsVolume != 0, 22) + (particles << 23)
		return Int32(truncatingIfNeeded: v)
	}

	/// rt4 `Rasteriser.setBrightness` argument for a `brightness` preference (nil when out of range).
	public static func gamma(forBrightness b: Int) -> Float? {
		switch b {
		case 1: return 0.9
		case 2: return 0.8
		case 3: return 0.7
		case 4: return 0.6
		default: return nil
		}
	}

	/// What the platform has to react to; the value is already stored in `InterfaceScriptHost.prefs`.
	public enum Change: Equatable {
		/// Rasteriser gamma changed: rebuild the 3D palette, texture cache and item icons.
		case brightness(gamma: Float)
		case musicVolume(old: Int, new: Int)
		case soundEffectVolume(Int)
		case ambientVolume(Int)
		/// Anything else that changes what the scene shows (roofs, decorations, levels, ground textures...).
		case scene
		/// A setting changed that needs no reaction beyond being stored (idle animations, flickering, shadows,
		/// stereo, texture detail...): stored in `prefs`, persisted and sent to the server.
		case stored
	}
}

extension InterfaceScriptHost {
	/// rt4 `ScriptRunner` 6001-6028 (set) and 6101-6128 (get): the Options tab's controls. Returns nil for
	/// any other op. Setters clamp as rt4 does and report to `onPreferenceChange`.
	func performPreference(_ op: HostOpSpec, ints a: [Int32]) -> HostResult? {
		let result = performPreferenceOp(op, ints: a)
		// rt4 `Preferences.write` + `sentToServer = false` follow every setter except 6021 (`neverRemoveRoofs`).
		if result != nil, (6001...6028).contains(op.opcode), op.opcode != 6021 {
			prefs.sentToServer = false
			onPreferencesWritten()
		}
		return result
	}

	private func performPreferenceOp(_ op: HostOpSpec, ints a: [Int32]) -> HostResult? {
		let v = a.first.map { Int($0) } ?? 0
		let flag = v == 1
		func ret(_ x: Int) -> HostResult { HostResult(ints: [Int32(truncatingIfNeeded: x)]) }
		func bool(_ x: Bool) -> HostResult { ret(x ? 1 : 0) }
		switch op.opcode {
		case 6001:
			prefs.brightness = min(max(v, 1), 4)
			if let g = ClientPreferences.gamma(forBrightness: prefs.brightness) { onPreferenceChange(.brightness(gamma: g)) }
		case 6002: prefs.allLevelsVisible = flag; onPreferenceChange(.scene)
		case 6003: prefs.removeRoofsSelectively = flag; onPreferenceChange(.scene)
		case 6005: prefs.showGroundDecorations = flag; onPreferenceChange(.scene)
		case 6006: prefs.highDetailTextures = flag; onPreferenceChange(.stored)
		case 6007: prefs.manyIdleAnimations = flag; onPreferenceChange(.stored)
		case 6008: prefs.flickeringEffects = flag; onPreferenceChange(.stored)
		case 6009: prefs.manyGroundTextures = flag; onPreferenceChange(.scene)
		case 6010: prefs.characterShadows = flag; onPreferenceChange(.stored)
		case 6011: prefs.sceneryShadows = v < 0 || v > 2 ? 0 : v; onPreferenceChange(.stored)
		case 6012:
			prefs.highDetailLighting = flag
			if let g = ClientPreferences.gamma(forBrightness: prefs.brightness) { onPreferenceChange(.brightness(gamma: g)) }
		case 6014: prefs.highWaterDetail = flag; onPreferenceChange(.stored)
		case 6015: prefs.fogEnabled = flag; onPreferenceChange(.stored)
		case 6016: prefs.antiAliasing = v < 0 || v > 2 ? 0 : v; onPreferenceChange(.stored)
		case 6017: prefs.stereo = flag; onPreferenceChange(.stored)
		case 6018:
			prefs.soundEffectVolume = min(max(v, 0), 127)
			onPreferenceChange(.soundEffectVolume(prefs.soundEffectVolume))
		case 6019:
			let new = min(max(v, 0), 255)
			if new != prefs.musicVolume {
				let old = prefs.musicVolume
				prefs.musicVolume = new
				onPreferenceChange(.musicVolume(old: old, new: new))
			}
		case 6020:
			prefs.ambientSoundsVolume = min(max(v, 0), 127)
			onPreferenceChange(.ambientVolume(prefs.ambientSoundsVolume))
		case 6021: prefs.neverRemoveRoofs = flag; onPreferenceChange(.scene)
		case 6023:
			prefs.particles = min(max(v, 0), 2)
			return ret(1)
		case 6024, 6028:
			if op.opcode == 6028 { prefs.cursorsEnabled = v != 0 }

		case 6101: return ret(prefs.brightness)
		case 6102: return bool(prefs.allLevelsVisible)
		case 6103: return bool(prefs.removeRoofsSelectively)
		case 6105: return bool(prefs.showGroundDecorations)
		case 6106: return bool(prefs.highDetailTextures)
		case 6107: return bool(prefs.manyIdleAnimations)
		case 6108: return bool(prefs.flickeringEffects)
		case 6109: return bool(prefs.manyGroundTextures)
		case 6110: return bool(prefs.characterShadows)
		case 6111: return ret(prefs.sceneryShadows)
		case 6112: return bool(prefs.highDetailLighting)
		case 6114: return bool(prefs.highWaterDetail)
		case 6115: return bool(prefs.fogEnabled)
		case 6116: return ret(prefs.antiAliasing)
		case 6117: return bool(prefs.stereo)
		case 6118: return ret(prefs.soundEffectVolume)
		case 6119: return ret(prefs.musicVolume)
		case 6120: return ret(prefs.ambientSoundsVolume)
		case 6121: return ret(0)
		case 6123: return ret(prefs.particles)
		case 6124: return ret(2)
		case 6128: return bool(prefs.cursorsEnabled)
		default: return nil
		}
		return HostResult()
	}
}
