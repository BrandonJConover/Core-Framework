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
	/// rt4 `Preferences.favoriteWorlds` (CS2 5308 / 5309): 0...2.
	public var favouriteWorlds = 0
	/// rt4 `Preferences.lastWorldId` (CS2 6504 / 6505).
	public var lastWorldId = 0
	/// rt4 `Preferences.aBoolean63` (CS2 6600 / 6601).
	public var pref6600 = false

	public init() {}

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
		/// Anything else that changes what the scene shows (roofs, decorations, levels, shadows...).
		case scene
	}
}

extension InterfaceScriptHost {
	/// rt4 `ScriptRunner` 6001-6028 (set) and 6101-6128 (get): the Options tab's controls. Returns nil for
	/// any other op. Setters clamp as rt4 does and report to `onPreferenceChange`.
	func performPreference(_ op: HostOpSpec, ints a: [Int32]) -> HostResult? {
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
		case 6006: prefs.highDetailTextures = flag
		case 6007: prefs.manyIdleAnimations = flag
		case 6008: prefs.flickeringEffects = flag
		case 6009: prefs.manyGroundTextures = flag
		case 6010: prefs.characterShadows = flag
		case 6011: prefs.sceneryShadows = v < 0 || v > 2 ? 0 : v
		case 6012:
			prefs.highDetailLighting = flag
			if let g = ClientPreferences.gamma(forBrightness: prefs.brightness) { onPreferenceChange(.brightness(gamma: g)) }
		case 6014: prefs.highWaterDetail = flag
		case 6015: prefs.fogEnabled = flag
		case 6016: prefs.antiAliasing = v < 0 || v > 2 ? 0 : v
		case 6017: prefs.stereo = flag
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
