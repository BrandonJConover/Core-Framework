import Foundation

/// Per-sample-region envelope parameters. Port of rt4 `Midi_Class162`.
final class MidiEnvelopes {
	/// Volume envelope: `[time, level]` pairs (time in 1/256 units at even indices).
	var volume: [Int8]?
	/// Release envelope, same layout, with a leading `[0, 64]` pair.
	var release: [Int8]?
	/// Decay strength (`anInt5815`); 0 disables decay.
	var decay = 0
	/// Pitch scaling of the decay rate (`anInt5807`).
	var decayScale = 0
	/// Pitch scaling of the volume envelope rate (`anInt5810`).
	var volumeScale = 0
	/// Pitch scaling of the release envelope rate (`anInt5813`).
	var releaseScale = 0
	/// Vibrato speed (`anInt5814`).
	var vibratoSpeed = 0
	/// Vibrato depth (`anInt5809`).
	var vibratoDepth = 0
	/// Vibrato fade-in delay (`anInt5811`).
	var vibratoDelay = 0
}

/// Resolves instrument samples (synth in archive 4, Vorbis in archive 14) on demand
/// and caches them. Port of rt4 `SoundBank`.
public final class SoundBank {
	private let synthArchive: AudioArchive
	private let vorbisArchive: AudioArchive
	private var cache: [Int: PcmSound] = [:]

	public init(synth: AudioArchive, vorbis: AudioArchive) {
		synthArchive = synth
		vorbisArchive = vorbis
	}

	private func synth(group: Int, file: Int) -> PcmSound? {
		let key = (file ^ ((group >> 12) | ((group << 4) & 0xFFF3))) | (group << 16)
		if let s = cache[key] { return s }
		guard let ss = SynthSound.create(archive: synthArchive, group: group, file: file) else { return nil }
		let s = ss.toPcmSound()
		cache[key] = s
		return s
	}

	/// rt4 `getSynthSound(id)`.
	func synthSound(_ id: Int) -> PcmSound? {
		if synthArchive.capacity() == 1 { return synth(group: 0, file: id) }
		if synthArchive.groupCapacity(id) == 1 { return synth(group: id, file: 0) }
		return nil
	}

	private func vorbis(group: Int, file: Int) -> PcmSound? {
		let key = ((file ^ ((group >> 12) | ((group << 4) & 0xFFF3))) | (group << 16)) ^ 0x1_0000_0000
		if let s = cache[key] { return s }
		guard let v = VorbisSound.create(archive: vorbisArchive, group: group, file: file), let s = v.decode(archive: vorbisArchive) else { return nil }
		cache[key] = s
		return s
	}

	/// rt4 `getVorbisSound(id)`.
	func vorbisSound(_ id: Int) -> PcmSound? {
		if vorbisArchive.capacity() == 1 { return vorbis(group: 0, file: id) }
		if vorbisArchive.groupCapacity(id) == 1 { return vorbis(group: id, file: 0) }
		return nil
	}
}

/// A General-MIDI-like patch: 128 keys, each mapped to a sample plus pitch, pan,
/// volume and envelope settings. Port of rt4 `MidiInstrument` (archive 15, one
/// group per `bank << 7 | program`).
final class MidiInstrument {
	/// Per key pan 0...128 (`aByteArray43`).
	var panning = [UInt8](repeating: 0, count: 128)
	/// Per key sample reference, cleared once resolved: `(id << 2) | loopBit | vorbisBit`, 0 = none (`anIntArray289`).
	private var sampleRefs = [Int](repeating: 0, count: 128)
	/// Overall volume scale (`anInt3078`).
	var volumeScale = 0
	/// Per key mono-note group, -1 = none (`aByteArray44`).
	var noteGroup = [Int8](repeating: 0, count: 128)
	/// Per key volume (`aByteArray45`).
	var noteVolume = [Int8](repeating: 0, count: 128)
	/// Per key decoded sample.
	var sounds = [PcmSound?](repeating: nil, count: 128)
	/// Per key pitch offset in 1/256 semitones; bit 15 set = looped sample (`aShortArray36`).
	var pitchOffset = [Int16](repeating: 0, count: 128)
	var envelopes = [MidiEnvelopes?](repeating: nil, count: 128)

	/// rt4 `method3825`: division rounding toward negative infinity for the interpolation helpers.
	private static func floorDiv(_ a: Int, _ b: Int) -> Int {
		let neg = a < 0 ? 1 : 0
		return (a + neg) / b - neg
	}

	init(_ data: [UInt8]) throws {
		var pos = 0
		func u(_ i: Int) throws -> Int {
			guard i >= 0 && i < data.count else { throw AudioDecodeError("instrument data overrun at \(i)") }
			return Int(data[i])
		}
		func sb(_ i: Int) throws -> Int { Int(Int8(truncatingIfNeeded: try u(i))) }
		func g1() throws -> Int { let v = try u(pos); pos += 1; return v }
		func g1b() throws -> Int { let v = try sb(pos); pos += 1; return v }
		func gVar() throws -> Int {
			var b = try g1b()
			var value = 0
			while b < 0 {
				value = ((b & 0x7F) | value) << 7
				b = try g1b()
			}
			return jw(b | value)
		}
		/// A zero-terminated run of signed bytes; leaves `pos` after the terminator.
		func run() throws -> [Int] {
			var n = 0
			while try u(pos + n) != 0 { n += 1 }
			var r = [Int](repeating: 0, count: n)
			for i in 0..<n { r[i] = try g1b() }
			pos += 1
			return r
		}

		let groupRuns = try run()            // local55: run lengths for note groups
		var groupValuePos = pos              // local57
		pos += groupRuns.count + 1
		let panRuns = try run()              // local106
		var panValuePos = pos                // local108
		pos += panRuns.count + 1
		let envelopeRuns = try run()         // local159
		let runCount = envelopeRuns.count + 1
		var setIndex = [Int](repeating: 0, count: runCount)
		var setCount: Int
		if runCount <= 1 {
			setCount = runCount
		} else {
			setCount = 2
			setIndex[1] = 1
			var last = 1
			for i in 2..<runCount {
				var v = try g1()
				if v == 0 {
					last = setCount
					setCount += 1
				} else {
					if v <= last { v -= 1 }
					last = v
				}
				setIndex[i] = last
			}
		}
		let sets = (0..<setCount).map { _ in MidiEnvelopes() }
		for set in sets {
			var n = try g1()
			if n > 0 { set.volume = [Int8](repeating: 0, count: n * 2) }
			n = try g1()
			if n > 0 {
				var r = [Int8](repeating: 0, count: n * 2 + 2)
				r[1] = 64
				set.release = r
			}
		}
		var n = try g1()
		var volumeCurve: [Int8]? = n > 0 ? [Int8](repeating: 0, count: n * 2) : nil
		n = try g1()
		var panCurve: [Int8]? = n > 0 ? [Int8](repeating: 0, count: n * 2) : nil
		let noteRuns = try run()             // local346
		var acc = 0
		for i in 0..<128 {
			acc += try g1()
			pitchOffset[i] = Int16(truncatingIfNeeded: acc)
		}
		acc = 0
		for i in 0..<128 {
			acc += try g1()
			pitchOffset[i] = Int16(truncatingIfNeeded: Int(pitchOffset[i]) + (acc << 8))
		}
		var remaining = 0
		var runIndex = 0
		var ref = 0
		for i in 0..<128 {
			if remaining == 0 {
				remaining = noteRuns.count > runIndex ? noteRuns[runIndex] : -1
				runIndex += 1
				ref = try gVar()
			}
			pitchOffset[i] = Int16(truncatingIfNeeded: Int(pitchOffset[i]) + (((ref - 1) & 2) << 14))
			sampleRefs[i] = ref
			remaining -= 1
		}
		remaining = 0
		var value = 0
		runIndex = 0
		for i in 0..<128 where sampleRefs[i] != 0 {
			if remaining == 0 {
				value = try sb(groupValuePos) - 1
				groupValuePos += 1
				remaining = groupRuns.count > runIndex ? groupRuns[runIndex] : -1
				runIndex += 1
			}
			remaining -= 1
			noteGroup[i] = Int8(truncatingIfNeeded: value)
		}
		remaining = 0
		runIndex = 0
		value = 0
		for i in 0..<128 where sampleRefs[i] != 0 {
			if remaining == 0 {
				value = (try sb(panValuePos) + 16) << 2
				panValuePos += 1
				remaining = runIndex < panRuns.count ? panRuns[runIndex] : -1
				runIndex += 1
			}
			remaining -= 1
			panning[i] = UInt8(truncatingIfNeeded: value)
		}
		runIndex = 0
		remaining = 0
		var current: MidiEnvelopes?
		for i in 0..<128 where sampleRefs[i] != 0 {
			if remaining == 0 {
				current = sets[setIndex[min(runIndex, runCount - 1)]]
				remaining = runIndex >= envelopeRuns.count ? -1 : envelopeRuns[runIndex]
				runIndex += 1
			}
			envelopes[i] = current
			remaining -= 1
		}
		remaining = 0
		runIndex = 0
		value = 0
		for i in 0..<128 {
			if remaining == 0 {
				remaining = runIndex < noteRuns.count ? noteRuns[runIndex] : -1
				runIndex += 1
				if sampleRefs[i] > 0 { value = try g1() + 1 }
			}
			remaining -= 1
			noteVolume[i] = Int8(truncatingIfNeeded: value)
		}
		volumeScale = try g1() + 1
		for set in sets {
			if set.volume != nil {
				var k = 1
				while k < set.volume!.count {
					set.volume![k] = Int8(truncatingIfNeeded: try g1b())
					k += 2
				}
			}
			if set.release != nil {
				var k = 3
				while k < set.release!.count - 2 {
					set.release![k] = Int8(truncatingIfNeeded: try g1b())
					k += 2
				}
			}
		}
		if volumeCurve != nil {
			var k = 1
			while k < volumeCurve!.count {
				volumeCurve![k] = Int8(truncatingIfNeeded: try g1b())
				k += 2
			}
		}
		if panCurve != nil {
			var k = 1
			while k < panCurve!.count {
				panCurve![k] = Int8(truncatingIfNeeded: try g1b())
				k += 2
			}
		}
		for set in sets where set.release != nil {
			acc = 0
			var k = 2
			while k < set.release!.count {
				acc -= -(try g1()) - 1
				set.release![k] = Int8(truncatingIfNeeded: acc)
				k += 2
			}
		}
		for set in sets where set.volume != nil {
			acc = 0
			var k = 2
			while k < set.volume!.count {
				acc = acc + (try g1()) + 1
				set.volume![k] = Int8(truncatingIfNeeded: acc)
				k += 2
			}
		}
		if var curve = volumeCurve {
			acc = try g1()
			curve[0] = Int8(truncatingIfNeeded: acc)
			var k = 2
			while k < curve.count {
				acc = acc + (try g1()) + 1
				curve[k] = Int8(truncatingIfNeeded: acc)
				k += 2
			}
			var from = Int(curve[0])
			var level = Int(curve[1])
			var i = 0
			while i < from && i < 128 {
				noteVolume[i] = Int8(truncatingIfNeeded: (level * Int(noteVolume[i]) + 32) >> 6)
				i += 1
			}
			k = 2
			while k < curve.count {
				let to = Int(curve[k])
				let toLevel = Int(curve[k + 1])
				k += 2
				var interp = (to - from) * level + (to - from) / 2
				var i = from
				while i < to {
					if i >= 0 && i < 128 {
						let f = MidiInstrument.floorDiv(interp, to - from)
						noteVolume[i] = Int8(truncatingIfNeeded: (f * Int(noteVolume[i]) + 32) >> 6)
					}
					interp += toLevel - level
					i += 1
				}
				level = toLevel
				from = to
			}
			var j = max(from, 0)
			while j < 128 {
				noteVolume[j] = Int8(truncatingIfNeeded: (Int(noteVolume[j]) * level + 32) >> 6)
				j += 1
			}
			volumeCurve = curve
		}
		if var curve = panCurve {
			acc = try g1()
			curve[0] = Int8(truncatingIfNeeded: acc)
			var k = 2
			while k < curve.count {
				acc = acc + (try g1()) + 1
				curve[k] = Int8(truncatingIfNeeded: acc)
				k += 2
			}
			var from = Int(curve[0])
			var offset = Int(curve[1]) << 1
			var i = 0
			while i < from && i < 128 {
				let v = offset + Int(panning[i])
				panning[i] = UInt8(truncatingIfNeeded: max(0, min(128, v)))
				i += 1
			}
			k = 2
			while k < curve.count {
				let to = Int(curve[k])
				var interp = (to - from) * offset + (to - from) / 2
				let toOffset = Int(curve[k + 1]) << 1
				k += 2
				var i = from
				while i < to {
					if i >= 0 && i < 128 {
						let f = MidiInstrument.floorDiv(interp, to - from)
						let v = f + Int(panning[i])
						panning[i] = UInt8(truncatingIfNeeded: max(0, min(128, v)))
					}
					interp += toOffset - offset
					i += 1
				}
				from = to
				offset = toOffset
			}
			var j = max(from, 0)
			while j < 128 {
				let v = Int(panning[j]) + offset
				panning[j] = UInt8(truncatingIfNeeded: max(0, min(128, v)))
				j += 1
			}
			panCurve = curve
		}
		for set in sets { set.decay = try g1() }
		for set in sets {
			if set.volume != nil { set.volumeScale = try g1() }
			if set.release != nil { set.releaseScale = try g1() }
			if set.decay > 0 { set.decayScale = try g1() }
		}
		for set in sets { set.vibratoSpeed = try g1() }
		for set in sets where set.vibratoSpeed > 0 { set.vibratoDepth = try g1() }
		for set in sets where set.vibratoDepth > 0 { set.vibratoDelay = try g1() }
	}

	/// rt4 `MidiInstrument.method2320`.
	static func load(archive: AudioArchive, id: Int) -> MidiInstrument? {
		guard let bytes = archive.fetchFile(id) else { return nil }
		return try? MidiInstrument(bytes)
	}

	/// rt4 `method2436`: loads the samples for the keys in `used` (all keys if nil).
	/// Returns false if any sample could not be loaded.
	func resolveSamples(bank: SoundBank, used: [UInt8]?) -> Bool {
		var last = 0
		var sound: PcmSound?
		var ok = true
		for key in 0..<128 {
			if used == nil || used![key] != 0 {
				var ref = sampleRefs[key]
				if ref != 0 {
					if last != ref {
						last = ref
						ref -= 1
						if (ref & 1) == 0 {
							sound = bank.synthSound(ref >> 2)
						} else {
							sound = bank.vorbisSound(ref >> 2)
						}
						if sound == nil { ok = false }
					}
					if let s = sound {
						sounds[key] = s
						sampleRefs[key] = 0
					}
				}
			}
		}
		return ok
	}
}
