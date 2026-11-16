import Foundation

/// Audio constants. rt4 `GlobalConfig.AUDIO_SAMPLE_RATE` (default 22050) is
/// also `AudioChannel.sampleRate`; every rate in the engine is derived from it.
public enum AudioConfig {
	public static let sampleRate = 22050
}

/// Wraps to a Java `int` (two's complement 32 bit), keeping the value in `Int`.
@inline(__always) func jw(_ v: Int) -> Int { Int(Int32(truncatingIfNeeded: v)) }

/// Number of bits needed for `v` (rt4 `IntUtils.bitCount`, Vorbis `ilog`).
func audioBitCount(_ value: Int) -> Int {
	var v = UInt32(truncatingIfNeeded: value)
	var n = 0
	if v >= 65536 { n += 16; v >>= 16 }
	if v >= 256 { n += 8; v >>= 8 }
	if v >= 16 { n += 4; v >>= 4 }
	if v >= 4 { n += 2; v >>= 2 }
	if v >= 1 { n += 1; v >>= 1 }
	return n + Int(v)
}

/// A decoded sound: signed 8 bit mono samples plus loop points. rt4 `PcmSound`.
/// `start`/`end` are the loop bounds in samples; `pingPong` is the ping-pong
/// (bidirectional) loop flag (`aBoolean165`).
public final class PcmSound {
	public var rate: Int
	public var samples: [Int8]
	public var start: Int
	public var end: Int
	public var pingPong: Bool

	public init(rate: Int, samples: [Int8], start: Int, end: Int, pingPong: Bool = false) {
		self.rate = rate
		self.samples = samples
		self.start = start
		self.end = end
		self.pingPong = pingPong
	}

	public var duration: Double { Double(samples.count) / Double(max(rate, 1)) }

	/// The sound as stereo-less 16 bit PCM at its own rate (for tests and WAV dumps).
	public func asInt16() -> [Int16] { samples.map { Int16($0) << 8 } }
}

/// One JS5 archive as the audio code sees it (rt4 `Js5.fetchFile` overloads).
public struct AudioArchive {
	let store: ConfigStore
	public let archive: Int

	public init(store: ConfigStore, archive: Int) {
		self.store = store
		self.archive = archive
	}

	/// rt4 `Js5.capacity()`: the number of group slots.
	public func capacity() -> Int { (try? store.index(archive).capacity) ?? -1 }

	/// rt4 `Js5.getGroupCapacity`.
	public func groupCapacity(_ group: Int) -> Int {
		guard let idx = try? store.index(archive), group >= 0, group < idx.capacity else { return 0 }
		return idx.groupCapacities[group]
	}

	public func isValid(group: Int) -> Bool { ((try? store.index(archive))?.isValid(group: group)) ?? false }

	/// rt4 `Js5.fetchFile(group, file)`.
	public func fetchFile(_ group: Int, _ file: Int) -> [UInt8]? {
		(try? store.file(archive: archive, group: group, file: file)) ?? nil
	}

	/// rt4 `Js5.fetchFile(id)`: the single file of group `id` (or file `id` of the only group).
	public func fetchFile(_ id: Int) -> [UInt8]? {
		let cap = capacity()
		if cap < 0 { return nil }
		if cap == 1 { return fetchFile(0, id) }
		if !isValid(group: id) { return nil }
		if groupCapacity(id) == 1 { return fetchFile(id, 0) }
		return nil
	}
}

/// The JS5 archives the audio engine reads (rt4 `client.js5Archive4/6/11/14/15`).
public struct AudioArchives {
	/// Archive 4: synthesised sound effects (`SynthSound`).
	public let synth: AudioArchive
	/// Archive 6: songs, group = song id (compact MIDI).
	public let songs: AudioArchive
	/// Archive 11: jingles, same format as songs.
	public let jingles: AudioArchive
	/// Archive 14: Ogg-less Vorbis samples (`VorbisSound`); group 0 file 0 is the shared codebook setup.
	public let vorbis: AudioArchive
	/// Archive 15: instrument patches (`MidiInstrument`), group = program id.
	public let instruments: AudioArchive

	public init(store: ConfigStore) {
		synth = AudioArchive(store: store, archive: 4)
		songs = AudioArchive(store: store, archive: 6)
		jingles = AudioArchive(store: store, archive: 11)
		vorbis = AudioArchive(store: store, archive: 14)
		instruments = AudioArchive(store: store, archive: 15)
	}
}

/// Thrown when an audio asset in the cache cannot be decoded.
public struct AudioDecodeError: Error, CustomStringConvertible {
	public let message: String
	public init(_ message: String) { self.message = message }
	public var description: String { "audio: \(message)" }
}
