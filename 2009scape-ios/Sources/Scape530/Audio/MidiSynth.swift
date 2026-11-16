import Foundation

/// A set of voices summed into one buffer (rt4 `MixerPcmStream`, minus the
/// unused listener machinery). Finished voices drop out after each pass.
final class VoiceMixer {
	private(set) var voices: [SoundVoice] = []

	func add(_ v: SoundVoice) { voices.append(v) }
	func remove(_ v: SoundVoice) { voices.removeAll { $0 === v } }
	func removeAll() { voices.removeAll() }

	func read(_ out: inout [Int32], _ off: Int, _ len: Int) {
		for v in voices { v.read(&out, off, len) }
		voices.removeAll { $0.finished }
	}

	func skip(_ len: Int) {
		for v in voices { v.skip(len) }
		voices.removeAll { $0.finished }
	}
}

/// One sounding note. Port of rt4 `MidiNote`.
final class MidiNote {
	/// Index into the volume envelope (`anInt3763`).
	var volumeEnvelopeIndex = 0
	/// Portamento factor 4096...0 (`anInt3764`).
	var portamento = 0
	/// Pan 0...128 (`anInt3765`).
	var pan = 0
	var envelopes: MidiEnvelopes!
	/// -1 while the key is held; >= 0 once released, counting release envelope time (`anInt3767`).
	var releaseCounter = -1
	var voice: SoundVoice?
	/// Vibrato phase accumulator (`anInt3768`).
	var vibratoPhase = 0
	var sound: PcmSound!
	/// Base pitch in 1/256 semitones (`anInt3769`).
	var basePitch = 0
	/// Volume envelope time (`anInt3770`).
	var volumeEnvelopeTime = 0
	/// Frames until the next 10 ms control tick (`anInt3771`).
	var framesToTick = 0
	/// Base volume from instrument and velocity (`anInt3772`).
	var baseVolume = 0
	var channel = 0
	/// Ticks since note start, for vibrato fade-in (`anInt3774`).
	var age = 0
	/// Accumulator for the cc81 sample restart (`anInt3775`).
	var restartAccumulator = 0
	/// Mono-note group, -1 if none (`anInt3776`).
	var noteGroup = 0
	/// Index into the release envelope (`anInt3777`).
	var releaseEnvelopeIndex = 0
	var key = 0
	/// Portamento pitch delta in 1/256 semitones (`anInt3781`).
	var portamentoDelta = 0
	/// Decay accumulator (`anInt3782`).
	var decayAccumulator = 0
	var instrument: MidiInstrument!
	/// Set once the note has been dropped from the synth's list.
	var removed = false

	func releaseResources() {
		envelopes = nil
		sound = nil
		voice = nil
		instrument = nil
	}
}

/// Software MIDI synthesiser: plays a `MidiSong` through `MidiInstrument` patches,
/// 16 channels, mixing into interleaved stereo `Int32` at `AudioConfig.sampleRate`.
/// Port of rt4 `MidiPcmStream` plus `MidiNoteStream`.
final class MidiSynth {
	private var loop = false
	/// Position of the sequencer in `division * 1_000_000 / rate` units per frame (`aLong189`).
	private var clock = 0
	/// Time of the next event (`aLong188`), its tick (`anInt5674`) and track (`anInt5675`).
	private var nextEventTime = 0
	private var nextEventTick = 0
	private var nextEventTrack = 0
	private let decoder = MidiDecoder()

	/// Default program (bank << 7 | patch) per channel (`anIntArray499`).
	private var defaultPrograms = [Int](repeating: 0, count: 16)
	/// Current program per channel (`anIntArray506`) and bank select (`anIntArray502`).
	private var programs = [Int](repeating: 0, count: 16)
	private var bankSelect = [Int](repeating: 0, count: 16)
	/// cc7 (`anIntArray495`), cc10 (`anIntArray496`), cc11 (`anIntArray505`).
	private var channelVolume = [Int](repeating: 0, count: 16)
	private var channelPan = [Int](repeating: 0, count: 16)
	private var channelExpression = [Int](repeating: 0, count: 16)
	/// Pitch bend (`anIntArray497`), mod wheel cc1 (`anIntArray500`), portamento time cc5 (`anIntArray504`).
	private var pitchBend = [Int](repeating: 0, count: 16)
	private var modWheel = [Int](repeating: 0, count: 16)
	private var portamentoTime = [Int](repeating: 0, count: 16)
	/// bit0 hold pedal, bit1 portamento/legato, bit2 cc81 sample restart (`channelFlags`).
	private var channelFlags = [Int](repeating: 0, count: 16)
	/// Active (N)RPN selector (`anIntArray498`) and pitch bend range from RPN 0 (`anIntArray501`).
	private var rpn = [Int](repeating: 0, count: 16)
	private var bendRange = [Int](repeating: 0, count: 16)
	/// cc16/48 sample start offset (`anIntArray509`).
	private var startOffset = [Int](repeating: 0, count: 16)
	/// cc17/49 restart rate: raw (`anIntArray510`) and as a step (`anIntArray503`).
	private var restartRaw = [Int](repeating: 0, count: 16)
	private var restartStep = [Int](repeating: 0, count: 16)
	/// Per-channel gain, 256 = unity (`anIntArray507`).
	private var channelGain = [Int](repeating: 256, count: 16)
	/// Master volume 0...255 (`anInt5668`).
	private(set) var volume = 256

	private var heldNotes = [[MidiNote?]](repeating: [MidiNote?](repeating: nil, count: 128), count: 16)
	private var groupNotes = [[MidiNote?]](repeating: [MidiNote?](repeating: nil, count: 128), count: 16)
	private var notes: [MidiNote] = []
	private let released = VoiceMixer()
	private(set) var instruments: [Int: MidiInstrument] = [:]

	private let rate = AudioConfig.sampleRate
	private let sequencerUnit = 1_000_000

	init() {
		for i in 0..<16 { channelGain[i] = 256 }
		reset(allNotesOff: true)
		defaultPrograms[9] = 128
		bankSelect[9] = 128
		setProgram(128, channel: 9)
	}

	var isValid: Bool { decoder.isValid }

	func setVolume(_ v: Int) { volume = v }

	// MARK: loading

	/// rt4 `isSongReady`, run to completion: loads every instrument and sample the song
	/// uses (only the keys it strikes). Returns nil if something is missing from the cache,
	/// in which case the song cannot be played faithfully. Pure function so it can run
	/// off the audio thread.
	static func loadInstruments(song: MidiSong, instrumentArchive: AudioArchive, bank: SoundBank) -> [Int: MidiInstrument]? {
		let used = song.usedPrograms()
		var loaded: [Int: MidiInstrument] = [:]
		var ready = true
		for (program, keys) in used {
			guard let instrument = MidiInstrument.load(archive: instrumentArchive, id: program) else {
				ready = false
				continue
			}
			loaded[program] = instrument
			if !instrument.resolveSamples(bank: bank, used: keys) { ready = false }
		}
		song.releasePrograms()
		return ready ? loaded : nil
	}

	func install(_ loaded: [Int: MidiInstrument]) { instruments = loaded }

	func clearInstruments() { instruments.removeAll() }

	// MARK: transport

	/// rt4 `method4431` / `method4416`: start playing.
	func start(song: MidiSong, loop: Bool) {
		stop(allNotesOff: true)
		decoder.initialise(song.midiBytes)
		self.loop = loop
		clock = 0
		for t in 0..<decoder.trackCount {
			decoder.loadTrackPosition(t)
			decoder.addDeltaTime(t)
			decoder.saveTrackPosition(t)
		}
		nextEventTrack = decoder.nextTrack()
		nextEventTick = nextEventTrack >= 0 ? decoder.times[nextEventTrack] : 0
		nextEventTime = decoder.timeMillis(nextEventTick)
	}

	/// rt4 `method4446` / `method4448`.
	func stop(allNotesOff all: Bool) {
		decoder.release()
		reset(allNotesOff: all)
	}

	// MARK: controller state

	/// rt4 `method4441`.
	private func reset(allNotesOff all: Bool) {
		if all { soundsOff(channel: -1) } else { releaseNotes(channel: -1) }
		resetControllers(-1)
		for i in 0..<16 { programs[i] = defaultPrograms[i] }
		for i in 0..<16 { bankSelect[i] = defaultPrograms[i] & ~0x7F }
	}

	/// rt4 `method4421`.
	private func resetControllers(_ ch: Int) {
		if ch < 0 {
			for i in 0..<16 { resetControllers(i) }
			return
		}
		channelVolume[ch] = 12800
		channelPan[ch] = 8192
		channelExpression[ch] = 16383
		pitchBend[ch] = 8192
		modWheel[ch] = 0
		portamentoTime[ch] = 8192
		releaseLegato(ch)
		resetRestart(ch)
		channelFlags[ch] = 0
		rpn[ch] = 32767
		bendRange[ch] = 256
		startOffset[ch] = 0
		setRestartRate(ch, 8192)
	}

	/// rt4 `method4423`.
	private func setRestartRate(_ ch: Int, _ v: Int) {
		restartRaw[ch] = v
		restartStep[ch] = jint(pow(2.0, Double(v) * 5.4931640625E-4) * 2097152.0 + 0.5)
	}

	/// rt4 `method4425`.
	private func setProgram(_ program: Int, channel ch: Int) {
		if programs[ch] != program {
			programs[ch] = program
			for k in 0..<128 { groupNotes[ch][k] = nil }
		}
	}

	private func unlink(_ n: MidiNote) { n.removed = true }

	private func compact() { notes.removeAll { $0.removed } }

	/// rt4 `method4422` (cc120): silence the channel's notes now (short fade).
	private func soundsOff(channel ch: Int) {
		for n in notes where !n.removed && (ch < 0 || n.channel == ch) {
			if let v = n.voice {
				v.fadeOut(frames: rate / 100)
				if v.isRamping { released.add(v) }
				n.releaseResources()
			}
			if n.releaseCounter < 0 { heldNotes[n.channel][n.key] = nil }
			unlink(n)
		}
		compact()
	}

	/// rt4 `method4430` (cc123): release every held note on the channel.
	private func releaseNotes(channel ch: Int) {
		for n in notes where !n.removed && (ch < 0 || ch == n.channel) && n.releaseCounter < 0 {
			heldNotes[n.channel][n.key] = nil
			n.releaseCounter = 0
		}
	}

	/// rt4 `method4443`: leaving legato mode releases notes that are no longer held.
	private func releaseLegato(_ ch: Int) {
		if (channelFlags[ch] & 2) == 0 { return }
		for n in notes where !n.removed && n.channel == ch && heldNotes[ch][n.key] == nil && n.releaseCounter < 0 {
			n.releaseCounter = 0
		}
	}

	/// rt4 `method4438`.
	private func resetRestart(_ ch: Int) {
		if (channelFlags[ch] & 4) == 0 { return }
		for n in notes where !n.removed && n.channel == ch { n.restartAccumulator = 0 }
	}

	// MARK: note on/off

	/// rt4 `method4434`: key released.
	private func noteOff(key: Int, channel ch: Int) {
		guard let note = heldNotes[ch][key] else { return }
		heldNotes[ch][key] = nil
		if (channelFlags[ch] & 2) == 0 {
			note.releaseCounter = 0
			return
		}
		for n in notes where !n.removed && n.channel == note.channel && n.releaseCounter < 0 && n !== note {
			note.releaseCounter = 0
			break
		}
	}

	/// rt4 `method4427`: key pressed.
	private func noteOn(velocity: Int, channel ch: Int, key: Int) {
		noteOff(key: key, channel: ch)
		if (channelFlags[ch] & 2) != 0 {
			for n in notes.reversed() where !n.removed && n.channel == ch && n.releaseCounter < 0 {
				heldNotes[ch][n.key] = nil
				heldNotes[ch][key] = n
				let current = n.basePitch + ((n.portamento * n.portamentoDelta) >> 12)
				n.portamento = 4096
				n.basePitch += (key - n.key) << 8
				n.portamentoDelta = current - n.basePitch
				n.key = key
				return
			}
		}
		guard let instrument = instruments[programs[ch]],
			let sound = instrument.sounds[key],
			let envelopes = instrument.envelopes[key] else { return }
		let note = MidiNote()
		note.sound = sound
		note.instrument = instrument
		note.channel = ch
		note.envelopes = envelopes
		note.noteGroup = Int(instrument.noteGroup[key])
		note.key = key
		note.baseVolume = (Int(instrument.noteVolume[key]) * velocity * velocity * instrument.volumeScale + 1024) >> 11
		note.pan = Int(instrument.panning[key])
		note.basePitch = (key << 8) - (Int(instrument.pitchOffset[key]) & 0x7FFF)
		note.releaseCounter = -1
		let looped = instrument.pitchOffset[key] < 0
		if startOffset[ch] == 0 {
			note.voice = SoundVoice.note(sound, rate: pitchRate(note), volume: noteVolume(note), pan: notePan(note))
		} else {
			note.voice = SoundVoice.note(sound, rate: pitchRate(note), volume: 0, pan: notePan(note))
			applyStartOffset(note, looped: looped)
		}
		if looped { note.voice?.setLoops(-1) }
		if note.noteGroup >= 0 {
			if let previous = groupNotes[ch][note.noteGroup], previous.releaseCounter < 0 {
				heldNotes[ch][previous.key] = nil
				previous.releaseCounter = 0
			}
			groupNotes[ch][note.noteGroup] = note
		}
		notes.append(note)
		heldNotes[ch][key] = note
	}

	/// rt4 `method4442`: cc16/48 start offset, as a fraction of the sample (in 1/64).
	private func applyStartOffset(_ note: MidiNote, looped: Bool) {
		guard let voice = note.voice else { return }
		var length = note.sound.samples.count
		var pos: Int
		if looped && note.sound.pingPong {
			let total = length + length - note.sound.start
			length <<= 8
			pos = (total * startOffset[note.channel]) >> 6
			if pos >= length {
				voice.reverse()
				pos = length + length - pos - 1
			}
		} else {
			pos = (length * startOffset[note.channel]) >> 6
		}
		voice.setPosition(pos)
	}

	// MARK: per-note parameters

	/// rt4 `method4437`: note pan 0...16384 combining the instrument pan with the channel pan.
	private func notePan(_ note: MidiNote) -> Int {
		let ch = channelPan[note.channel]
		return ch < 8192 ? (note.pan * ch + 32) >> 6 : 16384 - (((128 - note.pan) * (16384 - ch) + 32) >> 6)
	}

	/// rt4 `method4439`: playback step in 1/256 samples per output frame.
	private func pitchRate(_ note: MidiNote) -> Int {
		let env = note.envelopes!
		var pitch = ((note.portamentoDelta * note.portamento) >> 12) + note.basePitch
		pitch += (bendRange[note.channel] * (pitchBend[note.channel] - 8192)) >> 12
		if env.vibratoSpeed > 0 && (env.vibratoDepth > 0 || modWheel[note.channel] > 0) {
			var depth = env.vibratoDepth << 2
			let delay = env.vibratoDelay << 1
			if delay > note.age { depth = note.age * depth / delay }
			depth += modWheel[note.channel] >> 7
			let s = sin(Double(note.vibratoPhase & 0x1FF) * 0.01227184630308513)
			pitch += jint(Double(depth) * s)
		}
		let r = jint(Double(note.sound.rate * 256) * pow(2.0, Double(pitch) * 3.255208333333333E-4) / Double(rate) + 0.5)
		return r >= 1 ? r : 1
	}

	/// rt4 `method4449`: note volume (gain units for `SoundVoice`).
	private func noteVolume(_ note: MidiNote) -> Int {
		let ch = note.channel
		if channelGain[ch] == 0 { return 0 }
		let env = note.envelopes!
		var v = (channelVolume[ch] * channelExpression[ch] + 4096) >> 13
		let squared = (v * v + 16384) >> 15
		let scaled = (note.baseVolume * squared + 16384) >> 15
		let mastered = (scaled * volume + 128) >> 8
		v = (channelGain[ch] * mastered + 128) >> 8
		if env.decay > 0 {
			v = jint(pow(0.5, Double(note.decayAccumulator) * 1.953125E-5 * Double(env.decay)) * Double(v) + 0.5)
		}
		if let e = env.volume {
			let time = note.volumeEnvelopeTime
			let i = note.volumeEnvelopeIndex
			var level = Int(e[i + 1])
			if e.count - 2 > i {
				let t1 = (Int(e[i + 2]) & 0xFF) << 8
				let t0 = (Int(e[i]) & 0xFF) << 8
				if t1 != t0 { level += (Int(e[i + 3]) - level) * (time - t0) / (t1 - t0) }
			}
			v = (level * v + 32) >> 6
		}
		if note.releaseCounter > 0, let e = env.release {
			let time = note.releaseCounter
			let i = note.releaseEnvelopeIndex
			var level = Int(e[i + 1])
			if e.count - 2 > i {
				let t0 = (Int(e[i]) & 0xFF) << 8
				let t1 = (Int(e[i + 2]) & 0xFF) << 8
				if t1 != t0 { level += (time - t0) * (-level + Int(e[i + 3])) / (t1 - t0) }
			}
			v = (v * level + 32) >> 6
		}
		return v
	}

	// MARK: 10 ms note control tick

	/// rt4 `method4433`: per-note envelope/pitch/volume update, every `rate / 100` frames.
	/// `remaining`/`offset`/`buffer` describe the frames still to render in the current call
	/// so a note that ends here can finish them (fade) before it is dropped.
	/// Returns true if the note was removed.
	private func tick(_ note: MidiNote, remaining: Int, offset: Int, out: inout [Int32], render: Bool) -> Bool {
		note.framesToTick = rate / 100
		if note.releaseCounter >= 0 && (note.voice == nil || note.voice!.isOutOfRange) {
			note.releaseResources()
			unlink(note)
			if note.noteGroup > 0, groupNotes[note.channel][note.noteGroup] === note {
				groupNotes[note.channel][note.noteGroup] = nil
			}
			return true
		}
		guard let voice = note.voice, let env = note.envelopes else {
			unlink(note)
			return true
		}
		var p = note.portamento
		if p > 0 {
			p -= jint(pow(2.0, Double(portamentoTime[note.channel]) * 4.921259842519685E-4) * 16.0 + 0.5)
			if p < 0 { p = 0 }
			note.portamento = p
		}
		voice.setRate(pitchRate(note))
		note.vibratoPhase += env.vibratoSpeed
		note.age += 1
		let pitch = Double(((note.key - 60) << 8) + ((note.portamento * note.portamentoDelta) >> 12)) * 5.086263020833333E-6
		var done = false
		if env.decay > 0 {
			if env.decayScale > 0 {
				note.decayAccumulator += jint(pow(2.0, pitch * Double(env.decayScale)) * 128.0 + 0.5)
			} else {
				note.decayAccumulator += 128
			}
			if note.decayAccumulator * env.decay >= 819200 { done = true }
		}
		if let e = env.volume {
			if env.volumeScale <= 0 {
				note.volumeEnvelopeTime += 128
			} else {
				note.volumeEnvelopeTime += jint(pow(2.0, Double(env.volumeScale) * pitch) * 128.0 + 0.5)
			}
			while note.volumeEnvelopeIndex < e.count - 2 && note.volumeEnvelopeTime > (Int(e[note.volumeEnvelopeIndex + 2]) & 0xFF) << 8 {
				note.volumeEnvelopeIndex += 2
			}
			if e.count - 2 == note.volumeEnvelopeIndex && e[note.volumeEnvelopeIndex + 1] == 0 { done = true }
		}
		if note.releaseCounter >= 0, let e = env.release, (channelFlags[note.channel] & 1) == 0,
			note.noteGroup < 0 || groupNotes[note.channel][note.noteGroup] !== note {
			if env.releaseScale > 0 {
				note.releaseCounter += jint(pow(2.0, Double(env.releaseScale) * pitch) * 128.0 + 0.5)
			} else {
				note.releaseCounter += 128
			}
			while e.count - 2 > note.releaseEnvelopeIndex && (Int(e[note.releaseEnvelopeIndex + 2]) & 0xFF) << 8 < note.releaseCounter {
				note.releaseEnvelopeIndex += 2
			}
			if note.releaseEnvelopeIndex == e.count - 2 { done = true }
		}
		if !done {
			voice.rampTo(frames: note.framesToTick, volume: noteVolume(note), pan: notePan(note))
			return false
		}
		voice.fadeOut(frames: note.framesToTick)
		if render {
			voice.read(&out, offset, remaining)
		} else {
			voice.skip(remaining)
		}
		if voice.isRamping { released.add(voice) }
		let ch = note.channel
		let group = note.noteGroup
		let wasReleased = note.releaseCounter >= 0
		note.releaseResources()
		if wasReleased {
			unlink(note)
			if group > 0, groupNotes[ch][group] === note { groupNotes[ch][group] = nil }
		}
		return true
	}

	/// rt4 `method4445`: a note with no voice is dropped once released.
	private func dropIfSilent(_ note: MidiNote) -> Bool {
		if note.voice != nil { return false }
		if note.releaseCounter >= 0 {
			unlink(note)
			if note.noteGroup > 0, groupNotes[note.channel][note.noteGroup] === note {
				groupNotes[note.channel][note.noteGroup] = nil
			}
		}
		return true
	}

	// MARK: rendering (rt4 MidiNoteStream)

	/// rt4 `MidiNoteStream.read`.
	private func readNotes(_ out: inout [Int32], _ off: Int, _ len: Int) {
		released.read(&out, off, len)
		for note in notes where !note.removed {
			if dropIfSilent(note) { continue }
			var remaining = len
			var at = off
			repeat {
				if remaining <= note.framesToTick {
					renderNote(&out, note, at, remaining, at + remaining)
					note.framesToTick -= remaining
					break
				}
				renderNote(&out, note, at, note.framesToTick, remaining + at)
				remaining -= note.framesToTick
				at += note.framesToTick
				if tick(note, remaining: remaining, offset: at, out: &out, render: true) { break }
			} while true
		}
		compact()
	}

	/// rt4 `MidiNoteStream.skip`.
	private func skipNotes(_ len: Int) {
		released.skip(len)
		for note in notes where !note.removed {
			if dropIfSilent(note) { continue }
			var remaining = len
			repeat {
				if remaining <= note.framesToTick {
					skipNote(note, remaining)
					note.framesToTick -= remaining
					break
				}
				skipNote(note, note.framesToTick)
				remaining -= note.framesToTick
				var none: [Int32] = []
				if tick(note, remaining: remaining, offset: 0, out: &none, render: false) { break }
			} while true
		}
		compact()
	}

	/// rt4 `method4146`: render `count` frames of a note, handling cc81 sample restarts.
	private func renderNote(_ out: inout [Int32], _ note: MidiNote, _ offIn: Int, _ countIn: Int, _ blockEnd: Int) {
		guard let voice = note.voice else { return }
		var off = offIn
		var count = countIn
		if (channelFlags[note.channel] & 4) != 0 && note.releaseCounter < 0 {
			let step = restartStep[note.channel] / rate
			while step > 0 {
				let untilWrap = (step + 1048575 - note.restartAccumulator) / step
				if count < untilWrap {
					note.restartAccumulator += count * step
					break
				}
				count -= untilWrap
				note.voice!.read(&out, off, untilWrap)
				var fade = rate / 100
				let old = note.voice!
				let limit = 262144 / step
				if limit < fade { fade = limit }
				note.restartAccumulator += step * untilWrap - 1048576
				let looped = note.instrument.pitchOffset[note.key] < 0
				if startOffset[note.channel] == 0 {
					note.voice = SoundVoice.note(note.sound, rate: old.absRate, volume: old.currentVolume, pan: old.currentPan)
				} else {
					note.voice = SoundVoice.note(note.sound, rate: old.absRate, volume: 0, pan: old.currentPan)
					applyStartOffset(note, looped: looped)
					note.voice?.rampTo(frames: fade, volume: old.currentVolume)
				}
				if looped { note.voice?.setLoops(-1) }
				off += untilWrap
				old.fadeOut(frames: fade)
				old.read(&out, off, blockEnd - off)
				if old.isRamping { released.add(old) }
			}
		}
		note.voice?.read(&out, off, count)
		_ = voice
	}

	/// rt4 `MidiNoteStream.skip(MidiNote, int)`.
	private func skipNote(_ note: MidiNote, _ lenIn: Int) {
		guard let voice = note.voice else { return }
		var len = lenIn
		if (channelFlags[note.channel] & 4) != 0 && note.releaseCounter < 0 {
			let step = restartStep[note.channel] / rate
			if step > 0 {
				let untilWrap = (step + 1048575 - note.restartAccumulator) / step
				note.restartAccumulator = (step * len + note.restartAccumulator) & 0xFFFFF
				if len >= untilWrap {
					let looped = note.instrument.pitchOffset[note.key] < 0
					if startOffset[note.channel] == 0 {
						note.voice = SoundVoice.note(note.sound, rate: voice.absRate, volume: voice.currentVolume, pan: voice.currentPan)
					} else {
						note.voice = SoundVoice.note(note.sound, rate: voice.absRate, volume: 0, pan: voice.currentPan)
						applyStartOffset(note, looped: looped)
					}
					if looped { note.voice?.setLoops(-1) }
					len = note.restartAccumulator / step
				}
			}
		}
		note.voice?.skip(len)
	}

	// MARK: sequencer

	/// rt4 `MidiPcmStream.read`: sequences events and renders `len` frames at `off`.
	func read(_ out: inout [Int32], _ offIn: Int, _ lenIn: Int) {
		var off = offIn
		var len = lenIn
		if decoder.isValid {
			let unit = decoder.division * sequencerUnit / rate
			if unit > 0 {
				repeat {
					let target = clock + len * unit
					if nextEventTime - target >= 0 {
						clock = target
						break
					}
					let n = max(0, (nextEventTime + unit - clock - 1) / unit)
					clock += unit * n
					readNotes(&out, off, n)
					len -= n
					off += n
					processEvents()
				} while decoder.isValid
			}
		}
		readNotes(&out, off, len)
	}

	/// rt4 `MidiPcmStream.skip`.
	func skip(_ lenIn: Int) {
		var len = lenIn
		if decoder.isValid {
			let unit = decoder.division * sequencerUnit / rate
			if unit > 0 {
				repeat {
					let target = clock + len * unit
					if nextEventTime - target >= 0 {
						clock = target
						break
					}
					let n = max(0, (unit + nextEventTime - clock - 1) / unit)
					len -= n
					clock += n * unit
					skipNotes(n)
					processEvents()
				} while decoder.isValid
			}
		}
		skipNotes(len)
	}

	/// rt4 `method4435`: runs every event due at the current tick and finds the next one.
	private func processEvents() {
		var track = nextEventTrack
		var tick = nextEventTick
		var time = nextEventTime
		while nextEventTick == tick {
			while track >= 0 && tick == decoder.times[track] {
				decoder.loadTrackPosition(track)
				let event = decoder.nextEvent(track)
				if event == 1 {
					decoder.loadEndOfTrackPosition()
					decoder.saveTrackPosition(track)
					if decoder.hasNoMoreTracks {
						if !loop || tick == 0 {
							reset(allNotesOff: true)
							decoder.release()
							return
						}
						decoder.restart(at: time)
					}
					break
				}
				if (event & 0x80) != 0 { handle(event) }
				decoder.addDeltaTime(track)
				decoder.saveTrackPosition(track)
			}
			track = decoder.nextTrack()
			if track < 0 {
				// every track ended without the end-of-song branch above: stop
				reset(allNotesOff: true)
				decoder.release()
				return
			}
			tick = decoder.times[track]
			time = decoder.timeMillis(tick)
		}
		nextEventTrack = track
		nextEventTime = time
		nextEventTick = tick
	}

	/// rt4 `method4429`: apply one channel event word.
	private func handle(_ event: Int) {
		let kind = event & 0xF0
		let ch = event & 0xF
		let d1 = (event >> 8) & 0x7F
		let d2 = (event >> 16) & 0x7F
		switch kind {
		case 128:
			noteOff(key: d1, channel: ch)
		case 144:
			if d2 > 0 { noteOn(velocity: d2, channel: ch, key: d1) } else { noteOff(key: d1, channel: ch) }
		case 160:
			break
		case 176:
			controller(ch, d1, d2)
		case 192:
			setProgram(bankSelect[ch] + d1, channel: ch)
		case 208:
			break
		case 224:
			pitchBend[ch] = ((event >> 9) & 0x3F80) + ((event & 0x7FBE) >> 8)
		default:
			if (event & 0xFF) == 255 { reset(allNotesOff: true) }
		}
	}

	private func controller(_ ch: Int, _ cc: Int, _ v: Int) {
		if cc == 0 { bankSelect[ch] = (v << 14) + (bankSelect[ch] & ~0x1FC000) }
		if cc == 32 { bankSelect[ch] = (bankSelect[ch] & ~0x3F80) + (v << 7) }
		if cc == 1 { modWheel[ch] = (v << 7) + (modWheel[ch] & ~0x3F80) }
		if cc == 33 { modWheel[ch] = (modWheel[ch] & ~0x7F) + v }
		if cc == 5 { portamentoTime[ch] = (portamentoTime[ch] & ~0x3F80) + (v << 7) }
		if cc == 37 { portamentoTime[ch] = v + (portamentoTime[ch] & ~0x7F) }
		if cc == 7 { channelVolume[ch] = (v << 7) + (channelVolume[ch] & ~0x3F80) }
		if cc == 39 { channelVolume[ch] = (channelVolume[ch] & ~0x7F) + v }
		if cc == 10 { channelPan[ch] = (channelPan[ch] & ~0x3F80) + (v << 7) }
		if cc == 42 { channelPan[ch] = v + (channelPan[ch] & ~0x7F) }
		if cc == 11 { channelExpression[ch] = (channelExpression[ch] & ~0x3F80) + (v << 7) }
		if cc == 43 { channelExpression[ch] = v + (channelExpression[ch] & ~0x7F) }
		if cc == 64 {
			if v >= 64 { channelFlags[ch] |= 1 } else { channelFlags[ch] &= ~1 }
		}
		if cc == 65 {
			if v < 64 {
				releaseLegato(ch)
				channelFlags[ch] &= ~2
			} else {
				channelFlags[ch] |= 2
			}
		}
		if cc == 99 { rpn[ch] = (v << 7) + (rpn[ch] & 0x7F) }
		if cc == 98 { rpn[ch] = (rpn[ch] & 0x3F80) + v }
		if cc == 101 { rpn[ch] = (v << 7) + (rpn[ch] & 0x7F) + 16384 }
		if cc == 100 { rpn[ch] = v + (rpn[ch] & 0x3F80) + 16384 }
		if cc == 120 { soundsOff(channel: ch) }
		if cc == 121 { resetControllers(ch) }
		if cc == 123 { releaseNotes(channel: ch) }
		if cc == 6, rpn[ch] == 16384 { bendRange[ch] = (bendRange[ch] & ~0x3F80) + (v << 7) }
		if cc == 38, rpn[ch] == 16384 { bendRange[ch] = (bendRange[ch] & ~0x7F) + v }
		if cc == 16 { startOffset[ch] = (startOffset[ch] & ~0x3F80) + (v << 7) }
		if cc == 48 { startOffset[ch] = (startOffset[ch] & ~0x7F) + v }
		if cc == 81 {
			if v >= 64 {
				channelFlags[ch] |= 4
			} else {
				resetRestart(ch)
				channelFlags[ch] &= ~4
			}
		}
		if cc == 17 { setRestartRate(ch, (v << 7) + (restartRaw[ch] & ~0x3F80)) }
		if cc == 49 { setRestartRate(ch, (restartRaw[ch] & ~0x7F) + v) }
	}
}
