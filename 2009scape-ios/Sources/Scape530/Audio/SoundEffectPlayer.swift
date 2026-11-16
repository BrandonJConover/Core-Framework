import Foundation

/// Sound effects: the server's `SYNTH_SOUND` and `SOUND_AREA` messages and
/// animation sound cues. Port of rt4 `SoundPlayer` (queue, delays, distance
/// attenuation) over `SynthSound` (archive 4) and the voice mixer.
///
/// Time is counted in rt4 client ticks (20 ms) that this class derives from the
/// number of frames rendered, so it needs no external clock; positions are
/// scene-local fine coordinates (128 units per tile) like rt4's `xFine/zFine`.
public final class SoundEffectPlayer {
	private struct Pending {
		var id: Int
		var loops: Int
		var delay: Int
		var sound: PcmSound?
		/// 0 for a plain effect, else `radius | tileX << 16 | tileZ << 8` (rt4 `positions`).
		var position: Int
	}

	/// rt4 queue capacity.
	public static let capacity = 50
	private static let ticksFrames = AudioConfig.sampleRate * 20 / 1000

	private let archive: AudioArchive
	private let lock = NSLock()
	private var queue: [Pending] = []
	private let mixer = VoiceMixer()
	private var cache: [Int: (PcmSound, Int)] = [:]
	private var countdown = SoundEffectPlayer.ticksFrames
	private var scratch: [Int32] = []
	private var listenerX = 0
	private var listenerZ = 0

	/// `Preferences.soundEffectVolume` 0...127 (0 = effects off).
	public var effectVolume = 127
	/// `Preferences.ambientSoundsVolume` 0...127 (0 = positional sounds off).
	public var ambientVolume = 127

	public init(archives: AudioArchives) { archive = archives.synth }

	/// Where the local player stands in scene-local fine coordinates (rt4 `PlayerList.self.xFine/zFine`).
	public func setListener(xFine: Int, zFine: Int) {
		lock.lock()
		listenerX = xFine
		listenerZ = zFine
		lock.unlock()
	}

	/// rt4 `SoundPlayer.play(loops, id, delay)` (`SYNTH_SOUND`: `id`, `loops`, `delay`).
	public func play(id: Int, loops: Int, delay: Int = 0) {
		lock.lock()
		defer { lock.unlock() }
		if effectVolume == 0 || loops == 0 || queue.count >= SoundEffectPlayer.capacity || id == -1 { return }
		queue.append(Pending(id: id, loops: loops, delay: delay, sound: nil, position: 0))
	}

	/// The `SOUND_AREA` zone update (rt4 `Protocol` ~line 365): a sound anchored on a tile,
	/// audible while the player is within `radius + 1` tiles of it. `x`/`z` are scene-local tiles.
	public func playArea(id: Int, x: Int, z: Int, radius: Int, loops: Int, delay: Int, playerTileX: Int, playerTileZ: Int) {
		lock.lock()
		defer { lock.unlock() }
		guard x >= 0, z >= 0, x < 104, z < 104 else { return }
		let reach = radius + 1
		if playerTileX >= x - reach && playerTileX <= x + reach && playerTileZ >= z - reach && playerTileZ <= z + reach
			&& ambientVolume != 0 && loops > 0 && queue.count < SoundEffectPlayer.capacity && id != -1 {
			queue.append(Pending(id: id, loops: loops, delay: delay, sound: nil, position: radius + (x << 16) + (z << 8)))
		}
	}

	/// rt4 `SoundPlayer.playSeqSound`: the sound cue `index` of an animation, at an entity's position.
	/// `isSelf` makes minimum-distance-0 cues audible at full volume (own actions).
	public func playSeq(_ seq: SeqType, index: Int, xFine: Int, zFine: Int, isSelf: Bool) {
		lock.lock()
		defer { lock.unlock() }
		guard queue.count < SoundEffectPlayer.capacity, let all = seq.soundEffects, index >= 0, index < all.count,
			let cue = all[index], let first = cue.first else { return }
		var id = first >> 8
		if cue.count > 1 {
			let alt = Int(Double(cue.count) * Double.random(in: 0..<1))
			if alt > 0 { id = cue[alt] }
		}
		let loops = (first >> 5) & 7
		let minDistance = first & 0x1F
		if minDistance == 0 {
			if isSelf, effectVolume != 0, loops != 0, id != -1, queue.count < SoundEffectPlayer.capacity {
				queue.append(Pending(id: id, loops: loops, delay: 0, sound: nil, position: 0))
			}
		} else if ambientVolume != 0 {
			let z = (zFine - 64) / 128
			let x = (xFine - 64) / 128
			queue.append(Pending(id: id, loops: loops, delay: 0, sound: nil, position: minDistance + (x << 16) + (z << 8)))
		}
	}

	/// Number of voices currently sounding.
	public var activeVoices: Int { lock.lock(); defer { lock.unlock() }; return mixer.voices.count }

	/// Queued (not yet started) effects.
	public var queued: Int { lock.lock(); defer { lock.unlock() }; return queue.count }

	/// rt4 `SoundPlayer.loop` (effects part): once per 20 ms.
	private func controlTick() {
		var i = 0
		while i < queue.count {
			queue[i].delay -= 1
			if queue[i].delay >= -10 {
				if queue[i].sound == nil {
					if let cached = cache[queue[i].id] {
						queue[i].sound = cached.0
						queue[i].delay += cached.1
					} else if let synth = SynthSound.create(archive: archive, group: queue[i].id) {
						let start = synth.trimLeadingSilence()
						let pcm = synth.toPcmSound()
						cache[queue[i].id] = (pcm, start)
						queue[i].sound = pcm
						queue[i].delay += start
					} else {
						i += 1
						continue
					}
				}
				if queue[i].delay < 0 {
					var vol: Int
					let position = queue[i].position
					if position == 0 {
						vol = effectVolume
					} else {
						let minDistance = (position & 0xFF) * 128
						let z = (position >> 8) & 0xFF
						let x = (position >> 16) & 0xFF
						let dz = abs(z * 128 + 64 - listenerZ)
						let dx = abs(x * 128 + 64 - listenerX)
						var distance = dx + dz - 128
						if minDistance < distance {
							queue[i].delay = -100
							i += 1
							continue
						}
						if distance < 0 { distance = 0 }
						vol = ambientVolume * (minDistance - distance) / minDistance
					}
					if vol > 0, let pcm = queue[i].sound, let voice = SoundVoice.effect(pcm, volume: vol) {
						voice.setLoops(queue[i].loops - 1)
						mixer.add(voice)
					}
					queue[i].delay = -100
				}
				i += 1
			} else {
				queue.remove(at: i)
			}
		}
	}

	/// Renders `frames` stereo frames into `buffer` (resized to `frames * 2`).
	public func render(into buffer: inout [Int16], frames: Int) {
		lock.lock()
		defer { lock.unlock() }
		if scratch.count < frames * 2 { scratch = [Int32](repeating: 0, count: frames * 2) }
		for i in 0..<(frames * 2) { scratch[i] = 0 }
		var done = 0
		while done < frames {
			let n = min(frames - done, countdown)
			mixer.read(&scratch, done, n)
			done += n
			countdown -= n
			if countdown <= 0 {
				countdown = SoundEffectPlayer.ticksFrames
				controlTick()
			}
		}
		if buffer.count != frames * 2 { buffer = [Int16](repeating: 0, count: frames * 2) }
		for i in 0..<(frames * 2) { buffer[i] = audioPcm16(scratch[i]) }
	}

	/// Drops every queued and sounding effect (rt4 `LoginManager`: `SoundPlayer.size = 0`).
	public func clear() {
		lock.lock()
		queue.removeAll()
		mixer.removeAll()
		lock.unlock()
	}
}

/// Mixes music and sound effects into one interleaved stereo 16 bit stream at
/// `sampleRate` (22050 Hz, rt4's `AUDIO_SAMPLE_RATE`). The iOS layer pulls from
/// `render(into:frames:)` on its audio thread.
public final class AudioMixer {
	public static let sampleRate = AudioConfig.sampleRate
	public let music: MusicPlayer
	public let effects: SoundEffectPlayer
	private var musicBuffer: [Int16] = []
	private var effectBuffer: [Int16] = []

	public init(archives: AudioArchives) {
		music = MusicPlayer(archives: archives)
		effects = SoundEffectPlayer(archives: archives)
	}

	public convenience init(store: ConfigStore) {
		self.init(archives: AudioArchives(store: store))
	}

	/// Renders `frames` frames (L R interleaved) of music plus effects, summed with
	/// 16 bit saturation, into `buffer` (resized to `frames * 2`).
	public func render(into buffer: inout [Int16], frames: Int) {
		music.render(into: &musicBuffer, frames: frames)
		effects.render(into: &effectBuffer, frames: frames)
		if buffer.count != frames * 2 { buffer = [Int16](repeating: 0, count: frames * 2) }
		for i in 0..<(frames * 2) {
			let s = Int32(musicBuffer[i]) + Int32(effectBuffer[i])
			buffer[i] = Int16(max(-32768, min(32767, s)))
		}
	}

	/// Interleaved little-endian 16 bit stereo bytes of `render`, ready for an audio queue.
	public func renderBytes(frames: Int) -> [UInt8] {
		var pcm: [Int16] = []
		render(into: &pcm, frames: frames)
		return WAV.littleEndianBytes(pcm)
	}
}

/// Minimal WAV (RIFF PCM) writer for tests and tooling.
public enum WAV {
	public static func littleEndianBytes(_ pcm: [Int16]) -> [UInt8] {
		var out = [UInt8]()
		out.reserveCapacity(pcm.count * 2)
		for s in pcm {
			let u = UInt16(bitPattern: s)
			out.append(UInt8(u & 0xFF))
			out.append(UInt8(u >> 8))
		}
		return out
	}

	/// A complete 16 bit PCM WAV file.
	public static func encode(_ pcm: [Int16], sampleRate: Int, channels: Int) -> [UInt8] {
		var out = [UInt8]()
		func u32(_ v: Int) { for s in stride(from: 0, to: 32, by: 8) { out.append(UInt8((v >> s) & 0xFF)) } }
		func u16(_ v: Int) { out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF)) }
		let dataBytes = pcm.count * 2
		out.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
		out.append(contentsOf: Array("WAVE".utf8))
		out.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(channels)
		u32(sampleRate); u32(sampleRate * channels * 2); u16(channels * 2); u16(16)
		out.append(contentsOf: Array("data".utf8)); u32(dataBytes)
		out.append(contentsOf: littleEndianBytes(pcm))
		return out
	}
}
