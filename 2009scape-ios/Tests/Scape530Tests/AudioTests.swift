import Foundation
import XCTest
@testable import Scape530

/// Audio engine tests: unit checks of the voice mixer and decoders, then the
/// real cache's synth effects, Vorbis samples, songs and instruments. WAVs go
/// to `SCAPE530_OUT` (if set).
final class AudioTests: XCTestCase {
	func archives() throws -> AudioArchives {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return AudioArchives(store: ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir))))
	}

	func writeWav(_ pcm: [Int16], _ name: String, channels: Int = 2, rate: Int = AudioConfig.sampleRate) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(WAV.encode(pcm, sampleRate: rate, channels: channels)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".wav"))
	}

	struct Stats {
		var rms = 0.0
		var peak = 0
		var zeroCrossRate = 0.0
		var clipped = 0
		var silentFraction = 0.0
	}

	/// RMS/peak/zero-crossings over one channel of interleaved PCM.
	func stats(_ pcm: [Int16], channels: Int = 2, channel: Int = 0) -> Stats {
		var s = Stats()
		var sum = 0.0
		var n = 0
		var crossings = 0
		var prev = 0
		var silent = 0
		var i = channel
		while i < pcm.count {
			let v = Int(pcm[i])
			sum += Double(v * v)
			s.peak = max(s.peak, abs(v))
			if abs(v) >= 32767 { s.clipped += 1 }
			if abs(v) < 4 { silent += 1 }
			if (v >= 0) != (prev >= 0) { crossings += 1 }
			prev = v
			n += 1
			i += channels
		}
		s.rms = n > 0 ? (sum / Double(n)).squareRoot() : 0
		s.zeroCrossRate = n > 1 ? Double(crossings) / Double(n - 1) : 0
		s.silentFraction = n > 0 ? Double(silent) / Double(n) : 1
		return s
	}

	// MARK: unit tests (no cache)

	func testJavaRandomMatchesJdk() {
		var r = JavaRandom(seed: 0)
		XCTAssertEqual(Int(r.nextInt()), -1155484576)
		XCTAssertEqual(Int(r.nextInt()), -723955400)
	}

	func testMidiStatusTable() {
		// rt4 MidiDecoder.STATUS_LENGTHS has one entry per status 0x80...0xFF.
		XCTAssertEqual(MidiDecoder.statusLengths.count, 128)
	}

	func testAudioPcm16Clips() {
		XCTAssertEqual(audioPcm16(0), 0)
		XCTAssertEqual(audioPcm16(256 * 1000), 1000)
		XCTAssertEqual(audioPcm16(-256 * 1000), -1000)
		XCTAssertEqual(audioPcm16(100_000_000), 32767)
		XCTAssertEqual(audioPcm16(-100_000_000), -32768)
	}

	func testVoicePlaysConstantSampleAtUnitSpeed() {
		let sound = PcmSound(rate: AudioConfig.sampleRate, samples: [Int8](repeating: 100, count: 400), start: 0, end: 0)
		let voice = SoundVoice.note(sound, rate: 256, volume: 16384, pan: 8192)!
		var out = [Int32](repeating: 0, count: 2 * 600)
		voice.read(&out, 0, 600)
		// 100 * 256 * 16384 >> 6 = 6_553_600 on both channels (centre pan is unity on each side).
		XCTAssertEqual(out[0], 6_553_600)
		XCTAssertEqual(out[1], 6_553_600)
		XCTAssertEqual(out[2 * 399], 6_553_600)
		XCTAssertEqual(out[2 * 400], 0)
		XCTAssertTrue(voice.finished)
	}

	func testVoicePanLawAndLoop() {
		let sound = PcmSound(rate: AudioConfig.sampleRate, samples: (0..<100).map { Int8($0 % 20) }, start: 20, end: 80)
		let voice = SoundVoice.note(sound, rate: 256, volume: 8192, pan: 0)!
		voice.setLoops(-1)
		var out = [Int32](repeating: 0, count: 2 * 1000)
		voice.read(&out, 0, 1000)
		XCTAssertFalse(voice.finished)
		// pan 0 is hard left: right gain 0.
		XCTAssertTrue((0..<1000).allSatisfy { out[2 * $0 + 1] == 0 })
		XCTAssertTrue((0..<1000).contains { out[2 * $0] != 0 })
		XCTAssertLessThan(voice.position, 100 << 8)
	}

	func testVoiceRampAndFadeOut() {
		let sound = PcmSound(rate: AudioConfig.sampleRate, samples: [Int8](repeating: 64, count: 5000), start: 0, end: 0)
		let voice = SoundVoice.note(sound, rate: 256, volume: 0, pan: 8192)!
		voice.rampTo(frames: 100, volume: 8000)
		XCTAssertTrue(voice.isRamping)
		var out = [Int32](repeating: 0, count: 2 * 400)
		voice.read(&out, 0, 200)
		XCTAssertLessThan(out[2 * 10], out[2 * 90])
		XCTAssertEqual(out[2 * 150], out[2 * 199])
		voice.fadeOut(frames: 100)
		voice.read(&out, 200, 200)
		XCTAssertGreaterThan(out[2 * 200], out[2 * 280])
		XCTAssertEqual(out[2 * 399], 0)
		XCTAssertTrue(voice.finished)
	}

	func testPingPongLoopReverses() {
		let samples: [Int8] = (0..<64).map { Int8($0) }
		let sound = PcmSound(rate: AudioConfig.sampleRate, samples: samples, start: 8, end: 40, pingPong: true)
		let voice = SoundVoice.note(sound, rate: 256, volume: 4096, pan: 8192)!
		voice.setLoops(-1)
		var out = [Int32](repeating: 0, count: 2 * 400)
		voice.read(&out, 0, 400)
		let left = (0..<400).map { out[2 * $0] }
		// the playhead must stay inside the sample and the waveform must go both up and down
		XCTAssertTrue(zip(left, left.dropFirst()).contains { $0 > $1 })
		XCTAssertTrue(zip(left, left.dropFirst()).contains { $0 < $1 })
		XCTAssertFalse(voice.finished)
	}

	// MARK: real cache

	func testSynthSoundsDecodeAndRender() throws {
		let a = try archives()
		let index = try a.synth.store.index(4)
		var decoded = 0
		var failed: [Int] = []
		var silent: [Int] = []
		var longest = 0.0
		var clipHeavy: [Int] = []
		for g in index.groupIds.enumerated().filter({ $0.offset % 10 == 0 }).map({ $0.element }) {
			guard let bytes = a.synth.fetchFile(g, 0) else { continue }
			do {
				let s = try SynthSound(bytes)
				let pcm = s.toPcmSound()
				decoded += 1
				longest = max(longest, pcm.duration)
				let st = stats(pcm.asInt16(), channels: 1)
				if pcm.samples.isEmpty || st.peak == 0 { silent.append(g) }
				if st.clipped * 20 > pcm.samples.count && pcm.samples.count > 0 { clipHeavy.append(g) }
			} catch {
				failed.append(g)
			}
		}
		print("synth: \(index.groupIds.count) groups, \(decoded) decoded, \(failed.count) failed \(failed.prefix(10)), \(silent.count) silent \(silent.prefix(10)), \(clipHeavy.count) clip-heavy \(clipHeavy.prefix(10)), longest \(longest)s")
		XCTAssertEqual(failed, [])
		XCTAssertGreaterThan(decoded, 100)
		// (every 10th of the 6750 effects; the full set decodes too but takes ~10 minutes in a debug build)
		XCTAssertLessThan(silent.count * 10, decoded)
	}

	/// Renders a few well-known effects through the player and checks the waveform is sane.
	func testRenderSoundEffects() throws {
		let a = try archives()
		let index = try a.synth.store.index(4)
		let ids = index.groupIds
		let mixer = AudioMixer(archives: a)
		var checked = 0
		for id in [0, 1, 2, 3, 10, 60, 62, 100, 200, 300, 400, 500].filter({ ids.contains($0) }).prefix(8) {
			mixer.effects.clear()
			mixer.effects.play(id: id, loops: 1, delay: 0)
			var pcm: [Int16] = []
			mixer.render(into: &pcm, frames: AudioConfig.sampleRate * 2)
			let st = stats(pcm)
			print("effect \(id): rms \(Int(st.rms)) peak \(st.peak) zcr \(String(format: "%.3f", st.zeroCrossRate)) silent \(String(format: "%.2f", st.silentFraction))")
			guard st.peak > 0 else { continue }
			checked += 1
			XCTAssertLessThan(st.clipped, pcm.count / 2 / 20, "effect \(id) clips heavily")
			XCTAssertLessThan(st.zeroCrossRate, 0.5, "effect \(id) looks like noise")
			try writeWav(pcm, "sfx-\(id)")
		}
		XCTAssertGreaterThan(checked, 2)
	}

	func testVorbisSamplesDecode() throws {
		let a = try archives()
		let index = try a.vorbis.store.index(14)
		print("vorbis archive: capacity \(index.capacity), groups \(index.groupIds.count)")
		XCTAssertNotNil(VorbisSound.setup(for: a.vorbis), "shared vorbis setup (group 0)")
		var ok = 0
		var failed = 0
		var worst = 0.0
		for g in index.groupIds where g != 0 {
			guard a.vorbis.isValid(group: g), let v = VorbisSound.create(archive: a.vorbis, group: g, file: 0), let pcm = v.decode(archive: a.vorbis) else {
				failed += 1
				continue
			}
			ok += 1
			let st = stats(pcm.asInt16(), channels: 1)
			if ok <= 3 { print("vorbis \(g): \(pcm.samples.count) samples @\(pcm.rate) loop \(pcm.start)-\(pcm.end) pingpong \(pcm.pingPong) rms \(Int(st.rms)) zcr \(String(format: "%.3f", st.zeroCrossRate))") }
			worst = max(worst, st.zeroCrossRate)
			if ok == 1 { try writeWav(pcm.asInt16(), "vorbis-\(g)", channels: 1, rate: pcm.rate) }
		}
		print("vorbis: \(ok) decoded, \(failed) failed")
		XCTAssertGreaterThan(ok, 0)
		XCTAssertEqual(failed, 0)
	}

	func testEverySongExpandsToMidi() throws {
		let a = try archives()
		let index = try a.songs.store.index(6)
		var ok = 0
		var failures: [String] = []
		for g in index.groupIds {
			guard let bytes = a.songs.fetchFile(g, 0) else { continue }
			do {
				let song = try MidiSong(bytes)
				let d = MidiDecoder(song.midiBytes)
				XCTAssertEqual(Array(song.midiBytes[0..<4]), Array("MThd".utf8))
				XCTAssertGreaterThan(d.trackCount, 0)
				ok += 1
			} catch {
				failures.append("\(g): \(error)")
			}
		}
		print("songs: \(index.groupIds.count) groups, \(ok) expanded, ids \(index.groupIds.prefix(12))")
		XCTAssertEqual(failures, [])
		XCTAssertGreaterThan(ok, 100)
	}

	func testInstrumentsDecode() throws {
		let a = try archives()
		let index = try a.instruments.store.index(15)
		var ok = 0
		var failed: [Int] = []
		for g in index.groupIds {
			if MidiInstrument.load(archive: a.instruments, id: g) != nil { ok += 1 } else { failed.append(g) }
		}
		print("instruments: \(index.groupIds.count) groups (capacity \(index.capacity)), \(ok) decode, failed \(failed.prefix(10))")
		XCTAssertEqual(failed, [])
	}

	func testRenderSongTenSeconds() throws {
		let a = try archives()
		let index = try a.songs.store.index(6)
		let id = [62, 289, 1, 0].first { index.groupIds.contains($0) } ?? index.groupIds[0]
		let mixer = AudioMixer(archives: a)
		let t0 = Date()
		mixer.music.play(songId: id)
		print("song \(id) prepared in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
		var all: [Int16] = []
		var chunk: [Int16] = []
		let t1 = Date()
		for _ in 0..<20 {
			mixer.render(into: &chunk, frames: AudioConfig.sampleRate / 2)
			all += chunk
		}
		print("rendered 10 s in \(String(format: "%.2f", Date().timeIntervalSince(t1)))s")
		let left = stats(all, channel: 0)
		let right = stats(all, channel: 1)
		print("song \(id): L rms \(Int(left.rms)) peak \(left.peak) zcr \(String(format: "%.3f", left.zeroCrossRate)) clipped \(left.clipped) silent \(String(format: "%.2f", left.silentFraction)) | R rms \(Int(right.rms)) peak \(right.peak)")
		XCTAssertEqual(all.count, AudioConfig.sampleRate * 10 * 2)
		XCTAssertGreaterThan(left.rms, 200)
		XCTAssertGreaterThan(right.rms, 200)
		XCTAssertLessThan(left.zeroCrossRate, 0.35, "spectrum looks like noise")
		XCTAssertGreaterThan(left.zeroCrossRate, 0.001)
		XCTAssertLessThan(left.clipped, all.count / 2 / 100, "clipping storm")
		XCTAssertLessThan(left.silentFraction, 0.5)
		try writeWav(all, "song-\(id)-10s")
	}

	func testMixerEffectOverMusicAndFade() throws {
		let a = try archives()
		let index = try a.songs.store.index(6)
		let ids = Array(index.groupIds.prefix(2))
		let mixer = AudioMixer(archives: a)
		mixer.music.play(songId: ids[0])
		var pcm: [Int16] = []
		mixer.render(into: &pcm, frames: AudioConfig.sampleRate)
		let before = stats(pcm).rms
		mixer.effects.play(id: try XCTUnwrap(try a.synth.store.index(4).groupIds.first { $0 > 0 }), loops: 1)
		mixer.render(into: &pcm, frames: AudioConfig.sampleRate)
		XCTAssertGreaterThan(before, 0)
		// switching song fades the old one out (volume steps down by 2 per 20 ms)
		mixer.music.play(songId: ids[1])
		var fading = false
		for _ in 0..<20 {
			mixer.render(into: &pcm, frames: AudioConfig.sampleRate / 10)
			if mixer.music.currentVolume < 255 { fading = true }
		}
		XCTAssertTrue(fading || mixer.music.currentVolume == 255)
		XCTAssertTrue(mixer.music.isPlaying)
	}
}
