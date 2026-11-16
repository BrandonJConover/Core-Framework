import Foundation

/// Converts accumulated 24 bit mixer output to 16 bit PCM exactly as rt4's
/// `JavaAudioChannel.write` does: clip to 24 bits, keep the top 16.
@inline(__always) func audioPcm16(_ v: Int32) -> Int16 {
	var x = v
	if ((x &+ 8388608) & Int32(bitPattern: 0xFF000000)) != 0 { x = (x >> 31) ^ 0x7FFFFF }
	return Int16(truncatingIfNeeded: x >> 8)
}

/// A song with every instrument and sample it needs already decoded, so that
/// starting it on the audio thread is cheap.
struct PreparedSong {
	let id: Int
	let song: MidiSong
	let instruments: [Int: MidiInstrument]
}

/// Background music. Combines rt4 `MusicPlayer` (what the server asks for),
/// `MidiPlayer` (fade out, then switch song) and `MidiPcmStream` (the synth).
///
/// Songs live in archive 6 (group = song id) and jingles in archive 11. Like
/// rt4, a song plays once; when it ends `takeSongEnded()` reports its id so the
/// client can send `SOUND_SONGEND` and let the server pick the next one.
///
/// Thread model: `play`/`playJingle` decode the new song's samples on the
/// calling thread (can take a few hundred ms), then hand it to `render`
/// under a lock, so `render` can run on the audio thread.
public final class MusicPlayer {
	public static let sampleRate = AudioConfig.sampleRate
	/// rt4 `client.loop` runs `MidiPlayer.loop` every 20 ms; the fade advances once per such tick.
	private static let controlPeriodFrames = AudioConfig.sampleRate * 20 / 1000

	private let archives: AudioArchives
	private let lock = NSLock()
	private let synth = MidiSynth()

	// rt4 MidiPlayer state: 0 idle, 1 fading out the current song.
	private var state = 0
	private var fadeRate = 2
	private var pending: PreparedSong?
	private var pendingVolume = 255
	private var pendingLoop = false

	// rt4 MusicPlayer / SoundPlayer state.
	private var requestedSongId = -1
	private var jingleActive = false
	private var resume: PreparedSong?
	private var songEnded: Int?
	private var controlCountdown = MusicPlayer.controlPeriodFrames
	private var scratch: [Int32] = []

	/// Music volume 0...255 (rt4 `Preferences.musicVolume`; 0 = music off).
	public var volume: Int {
		get { lock.lock(); defer { lock.unlock() }; return musicVolume }
		set {
			lock.lock(); defer { lock.unlock() }
			musicVolume = max(0, min(255, newValue))
			if state == 0 { synth.setVolume(musicVolume) } else { pendingVolume = musicVolume }
		}
	}
	private var musicVolume = 255

	public init(archives: AudioArchives) {
		self.archives = archives
		synth.setVolume(255)
	}

	/// The song id the server last asked for (rt4 `MusicPlayer.groupId`), -1 for none.
	public var currentSongId: Int { lock.lock(); defer { lock.unlock() }; return requestedSongId }

	/// rt4 `MidiPlayer.isPlaying`: a change is pending or notes are still sequencing.
	public var isPlaying: Bool { lock.lock(); defer { lock.unlock() }; return playing }

	private var playing: Bool { state != 0 || synth.isValid }

	/// Current synth volume 0...255 (follows fades).
	public var currentVolume: Int { lock.lock(); defer { lock.unlock() }; return synth.volume }

	// MARK: server-driven API

	/// rt4 `MusicPlayer.playSong(id)` (`MIDI_SONG`). -1 stops the music. Does nothing if that
	/// song is already playing, music is off, or a jingle is running (it resumes afterwards).
	public func play(songId: Int, loop: Bool = false) {
		lock.lock()
		let jingle = jingleActive
		let vol = musicVolume
		if songId == -1 && !jingle {
			pending = nil
			synth.stop(allNotesOff: true)
			state = 1
			requestedSongId = -1
			lock.unlock()
			return
		}
		let wanted = songId != -1 && (requestedSongId != songId || !playing) && vol != 0 && !jingle
		let needsResume = songId != -1 && jingle && vol != 0
		requestedSongId = songId
		lock.unlock()
		if wanted {
			let prepared = prepare(archive: archives.songs, id: songId)
			lock.lock()
			if requestedSongId == songId {
				pending = prepared
				pendingVolume = musicVolume
				pendingLoop = loop
				fadeRate = 2
				state = 1
			}
			lock.unlock()
		} else if needsResume {
			let prepared = prepare(archive: archives.songs, id: songId)
			lock.lock()
			resume = prepared
			lock.unlock()
		}
	}

	/// rt4 `MusicPlayer.playJingle` (`MIDI_JINGLE`): archive 11, replaces whatever plays at once;
	/// the previous song restarts afterwards.
	public func playJingle(id: Int) {
		lock.lock()
		let vol = musicVolume
		let songId = requestedSongId
		lock.unlock()
		guard vol != 0, id != -1 else { return }
		let jingle = prepare(archive: archives.jingles, id: id)
		let again = songId != -1 ? prepare(archive: archives.songs, id: songId) : nil
		lock.lock()
		pending = jingle
		pendingVolume = vol
		pendingLoop = false
		fadeRate = 10000
		state = 1
		jingleActive = true
		resume = again
		lock.unlock()
	}

	/// Fade out and stop (rt4 `MidiPlayer.playFadeOut()` as used on logout).
	public func stop() {
		lock.lock()
		pending = nil
		resume = nil
		jingleActive = false
		requestedSongId = -1
		fadeRate = 2
		state = 1
		lock.unlock()
	}

	/// If the song the server asked for has ended since the last call, returns its id once
	/// (rt4 `SoundPlayer.sendTrackEndPacket`: send `SOUND_SONGEND` with it).
	public func takeSongEnded() -> Int? {
		lock.lock()
		defer { lock.unlock() }
		let v = songEnded
		songEnded = nil
		return v
	}

	// MARK: preparing

	private func prepare(archive: AudioArchive, id: Int) -> PreparedSong? {
		guard let song = MidiSong.create(archive: archive, group: id) else { return nil }
		let bank = SoundBank(synth: archives.synth, vorbis: archives.vorbis)
		guard let instruments = MidiSynth.loadInstruments(song: song, instrumentArchive: archives.instruments, bank: bank) else { return nil }
		return PreparedSong(id: id, song: song, instruments: instruments)
	}

	/// Decodes a song for inspection or offline rendering without touching playback.
	public func debugPrepare(songId: Int) -> Bool { prepare(archive: archives.songs, id: songId) != nil }

	// MARK: rendering

	/// rt4 `MidiPlayer.loop` + the song-switch half of `MidiPlayer.method2699`, once per 20 ms.
	private func controlTick() {
		if state == 1 {
			var v = synth.volume
			if v > 0 && synth.isValid {
				v -= fadeRate
				if v < 0 { v = 0 }
				synth.setVolume(v)
			} else {
				synth.stop(allNotesOff: true)
				synth.clearInstruments()
				if let p = pending {
					pending = nil
					synth.install(p.instruments)
					synth.setVolume(pendingVolume)
					synth.start(song: p.song, loop: pendingLoop)
				}
				state = 0
			}
		}
		// rt4 SoundPlayer.loop tail: resume the song after a jingle, or report the song's end.
		if jingleActive && !playing {
			if musicVolume != 0, requestedSongId != -1, let r = resume {
				resume = nil
				pending = r
				pendingVolume = musicVolume
				pendingLoop = false
				fadeRate = 10000
				state = 1
			}
			jingleActive = false
		} else if musicVolume != 0 && requestedSongId != -1 && !playing {
			songEnded = requestedSongId
			requestedSongId = -1
		}
	}

	/// Renders `frames` stereo frames of music at `AudioConfig.sampleRate` into
	/// `buffer` (interleaved left/right, resized to `frames * 2`).
	public func render(into buffer: inout [Int16], frames: Int) {
		lock.lock()
		defer { lock.unlock() }
		renderLocked(into: &buffer, frames: frames)
	}

	func renderLocked(into buffer: inout [Int16], frames: Int) {
		if scratch.count < frames * 2 { scratch = [Int32](repeating: 0, count: frames * 2) }
		for i in 0..<(frames * 2) { scratch[i] = 0 }
		var done = 0
		while done < frames {
			let n = min(frames - done, controlCountdown)
			synth.read(&scratch, done, n)
			done += n
			controlCountdown -= n
			if controlCountdown <= 0 {
				controlCountdown = MusicPlayer.controlPeriodFrames
				controlTick()
			}
		}
		if buffer.count != frames * 2 { buffer = [Int16](repeating: 0, count: frames * 2) }
		for i in 0..<(frames * 2) { buffer[i] = audioPcm16(scratch[i]) }
	}
}
