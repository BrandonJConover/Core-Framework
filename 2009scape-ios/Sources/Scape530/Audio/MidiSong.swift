import Foundation

/// Reads a Java-style variable length int the way rt4 `Buffer.gVarInt` does.
@inline(__always) private func gVarInt(_ d: [UInt8], _ pos: inout Int) -> Int {
	guard pos < d.count else { return 0 }
	var b = Int(Int8(bitPattern: d[pos])); pos += 1
	var value = 0
	while b < 0 {
		value = ((b & 0x7F) | value) << 7
		guard pos < d.count else { return value }
		b = Int(Int8(bitPattern: d[pos])); pos += 1
	}
	return jw(b | value)
}

/// Appends a standard MIDI variable length quantity (rt4 `Buffer.pVarInt`).
private func pVarInt(_ out: inout [UInt8], _ value: Int) {
	let v = UInt32(truncatingIfNeeded: value)
	if (v & 0xFFFFFF80) != 0 {
		if (v & 0xFFFFC000) != 0 {
			if (v & 0xFFE00000) != 0 {
				if (v & 0xF0000000) != 0 { out.append(UInt8(truncatingIfNeeded: (v >> 28) | 0x80)) }
				out.append(UInt8(truncatingIfNeeded: (v >> 21) | 0x80))
			}
			out.append(UInt8(truncatingIfNeeded: (v >> 14) | 0x80))
		}
		out.append(UInt8(truncatingIfNeeded: (v >> 7) | 0x80))
	}
	out.append(UInt8(truncatingIfNeeded: v & 0x7F))
}

private func put4(_ out: inout [UInt8], _ v: Int) {
	out.append(UInt8(truncatingIfNeeded: v >> 24))
	out.append(UInt8(truncatingIfNeeded: v >> 16))
	out.append(UInt8(truncatingIfNeeded: v >> 8))
	out.append(UInt8(truncatingIfNeeded: v))
}

private func put2(_ out: inout [UInt8], _ v: Int) {
	out.append(UInt8(truncatingIfNeeded: v >> 8))
	out.append(UInt8(truncatingIfNeeded: v))
}

/// A song as stored in archive 6 / 11: rt4's compact MIDI encoding, expanded
/// to a Standard MIDI File (format 0/1) in `midiBytes`. Port of rt4 `Song`.
///
/// The compact form splits a MIDI file into parallel streams (event status
/// bytes, delta times, controller numbers, then one stream of value deltas per
/// event kind) which this class re-interleaves.
public final class MidiSong {
	/// The decoded Standard MIDI File bytes.
	public let midiBytes: [UInt8]
	private var programs: [Int: [UInt8]]?

	/// rt4 `Song(Buffer)`.
	public init(_ data: [UInt8]) throws {
		guard data.count > 3 else { throw AudioDecodeError("song too short") }
		var tail = Packet(data, offset: data.count - 3)
		let tracks = try tail.g1()
		let division = try tail.g2()
		var pos = 0
		var tempoChanges = 0, controllerEvents = 0, noteOnEvents = 0, noteOffEvents = 0
		var pitchWheelEvents = 0, channelPressureEvents = 0, keyPressureEvents = 0, bankSelectEvents = 0
		func byte(_ i: Int) throws -> Int {
			guard i >= 0 && i < data.count else { throw AudioDecodeError("song data overrun at \(i)") }
			return Int(data[i])
		}
		func sbyte(_ i: Int) throws -> Int {
			guard i >= 0 && i < data.count else { throw AudioDecodeError("song data overrun at \(i)") }
			return Int(Int8(bitPattern: data[i]))
		}
		for _ in 0..<tracks {
			while true {
				let statusAndChannel = try byte(pos); pos += 1
				let kind = statusAndChannel & 0xF
				if statusAndChannel == 7 { break }
				if statusAndChannel == 23 {
					tempoChanges += 1
				} else if kind == 0 {
					noteOnEvents += 1
				} else if kind == 1 {
					noteOffEvents += 1
				} else if kind == 2 {
					controllerEvents += 1
				} else if kind == 3 {
					pitchWheelEvents += 1
				} else if kind == 4 {
					channelPressureEvents += 1
				} else if kind == 5 {
					keyPressureEvents += 1
				} else if kind == 6 {
					bankSelectEvents += 1
				} else {
					throw AudioDecodeError("bad song event kind \(kind)")
				}
			}
		}
		var deltaTimePos = pos
		let deltaCount = tracks + tempoChanges + controllerEvents + noteOnEvents + noteOffEvents + pitchWheelEvents + channelPressureEvents + keyPressureEvents + bankSelectEvents
		var scan = Packet(data, offset: pos)
		for _ in 0..<deltaCount {
			var p = scan.offset
			_ = gVarInt(data, &p)
			scan.offset = p
		}
		pos = scan.offset
		var controllerPos = pos
		var modulationWheelMsbEvents = 0, modulationWheelLsbEvents = 0
		var channelVolumeMsbEvents = 0, channelVolumeLsbEvents = 0
		var panMsbEvents = 0, panLsbEvents = 0
		var nonRegisteredMsbEvents = 0, nonRegisteredLsbEvents = 0
		var registeredMsbEvents = 0, registeredLsbEvents = 0
		var otherKnownControllerEvents = 0, unknownControllerEvents = 0
		var controller = 0
		for _ in 0..<controllerEvents {
			controller = (controller + (try byte(pos))) & 0x7F; pos += 1
			if controller == 0 || controller == 32 {
				bankSelectEvents += 1
			} else if controller == 1 {
				modulationWheelMsbEvents += 1
			} else if controller == 33 {
				modulationWheelLsbEvents += 1
			} else if controller == 7 {
				channelVolumeMsbEvents += 1
			} else if controller == 39 {
				channelVolumeLsbEvents += 1
			} else if controller == 10 {
				panMsbEvents += 1
			} else if controller == 42 {
				panLsbEvents += 1
			} else if controller == 99 {
				nonRegisteredMsbEvents += 1
			} else if controller == 98 {
				nonRegisteredLsbEvents += 1
			} else if controller == 101 {
				registeredMsbEvents += 1
			} else if controller == 100 {
				registeredLsbEvents += 1
			} else if controller == 64 || controller == 65 || controller == 120 || controller == 121 || controller == 123 {
				otherKnownControllerEvents += 1
			} else {
				unknownControllerEvents += 1
			}
		}
		var otherKnownControllerPos = pos
		pos += otherKnownControllerEvents
		var keyPressurePos = pos
		pos += keyPressureEvents
		var channelPressurePos = pos
		pos += channelPressureEvents
		var pitchWheelMsbPos = pos
		pos += pitchWheelEvents
		var modulationWheelMsbPos = pos
		pos += modulationWheelMsbEvents
		var channelVolumeMsbPos = pos
		pos += channelVolumeMsbEvents
		var panMsbPos = pos
		pos += panMsbEvents
		var keyPos = pos
		pos += noteOnEvents + noteOffEvents + keyPressureEvents
		var onVelocityPos = pos
		pos += noteOnEvents
		var unknownControllerPos = pos
		pos += unknownControllerEvents
		var offVelocityPos = pos
		pos += noteOffEvents
		var modulationWheelLsbPos = pos
		pos += modulationWheelLsbEvents
		var channelVolumeLsbPos = pos
		pos += channelVolumeLsbEvents
		var panLsbPos = pos
		pos += panLsbEvents
		var bankSelectPos = pos
		pos += bankSelectEvents
		var pitchWheelLsbPos = pos
		pos += pitchWheelEvents
		var nonRegisteredMsbPos = pos
		pos += nonRegisteredMsbEvents
		var nonRegisteredLsbPos = pos
		pos += nonRegisteredLsbEvents
		var registeredMsbPos = pos
		pos += registeredMsbEvents
		var registeredLsbPos = pos
		pos += registeredLsbEvents
		var tempoPos = pos
		pos += tempoChanges * 3

		var out = [UInt8]()
		out.reserveCapacity(data.count * 2)
		put4(&out, 1297377380) // "MThd"
		put4(&out, 6)
		put2(&out, tracks > 1 ? 1 : 0)
		put2(&out, tracks)
		put2(&out, division)

		var statusPos = 0 // status byte stream starts at the beginning of the data
		var deltaPos = deltaTimePos
		var channel = 0
		var key = 0, onVelocity = 0, offVelocity = 0, pitchWheel = 0, channelPressure = 0, keyPressure = 0
		var values = [Int](repeating: 0, count: 128)
		controller = 0
		var controllerReadPos = controllerPos
		deltaTimePos = 0
		controllerPos = 0

		for _ in 0..<tracks {
			put4(&out, 1297379947) // "MTrk"
			let lengthAt = out.count
			put4(&out, 0)
			let bodyStart = out.count
			var previous = -1
			trackLoop: while true {
				let deltaTime = gVarInt(data, &deltaPos)
				pVarInt(&out, deltaTime)
				let status = try byte(statusPos); statusPos += 1
				let statusChanged = status != previous
				previous = status & 0xF
				if status == 7 {
					if statusChanged { out.append(255) }
					out.append(47)
					out.append(0)
					let len = out.count - bodyStart
					out[lengthAt] = UInt8(truncatingIfNeeded: len >> 24)
					out[lengthAt + 1] = UInt8(truncatingIfNeeded: len >> 16)
					out[lengthAt + 2] = UInt8(truncatingIfNeeded: len >> 8)
					out[lengthAt + 3] = UInt8(truncatingIfNeeded: len)
					break trackLoop
				}
				if status == 23 {
					if statusChanged { out.append(255) }
					out.append(81)
					out.append(3)
					out.append(UInt8(truncatingIfNeeded: try byte(tempoPos))); tempoPos += 1
					out.append(UInt8(truncatingIfNeeded: try byte(tempoPos))); tempoPos += 1
					out.append(UInt8(truncatingIfNeeded: try byte(tempoPos))); tempoPos += 1
					continue
				}
				channel ^= status >> 4
				let kind = status & 0xF
				if kind == 0 {
					if statusChanged { out.append(UInt8(truncatingIfNeeded: channel + 144)) }
					key += try sbyte(keyPos); keyPos += 1
					onVelocity += try sbyte(onVelocityPos); onVelocityPos += 1
					out.append(UInt8(truncatingIfNeeded: key & 0x7F))
					out.append(UInt8(truncatingIfNeeded: onVelocity & 0x7F))
				} else if kind == 1 {
					if statusChanged { out.append(UInt8(truncatingIfNeeded: channel + 128)) }
					key += try sbyte(keyPos); keyPos += 1
					offVelocity += try sbyte(offVelocityPos); offVelocityPos += 1
					out.append(UInt8(truncatingIfNeeded: key & 0x7F))
					out.append(UInt8(truncatingIfNeeded: offVelocity & 0x7F))
				} else if kind == 2 {
					if statusChanged { out.append(UInt8(truncatingIfNeeded: channel + 176)) }
					controller = (controller + (try byte(controllerReadPos))) & 0x7F; controllerReadPos += 1
					out.append(UInt8(truncatingIfNeeded: controller))
					let delta: Int
					if controller == 0 || controller == 32 {
						delta = try sbyte(bankSelectPos); bankSelectPos += 1
					} else if controller == 1 {
						delta = try sbyte(modulationWheelMsbPos); modulationWheelMsbPos += 1
					} else if controller == 33 {
						delta = try sbyte(modulationWheelLsbPos); modulationWheelLsbPos += 1
					} else if controller == 7 {
						delta = try sbyte(channelVolumeMsbPos); channelVolumeMsbPos += 1
					} else if controller == 39 {
						delta = try sbyte(channelVolumeLsbPos); channelVolumeLsbPos += 1
					} else if controller == 10 {
						delta = try sbyte(panMsbPos); panMsbPos += 1
					} else if controller == 42 {
						delta = try sbyte(panLsbPos); panLsbPos += 1
					} else if controller == 99 {
						delta = try sbyte(nonRegisteredMsbPos); nonRegisteredMsbPos += 1
					} else if controller == 98 {
						delta = try sbyte(nonRegisteredLsbPos); nonRegisteredLsbPos += 1
					} else if controller == 101 {
						delta = try sbyte(registeredMsbPos); registeredMsbPos += 1
					} else if controller == 100 {
						delta = try sbyte(registeredLsbPos); registeredLsbPos += 1
					} else if controller == 64 || controller == 65 || controller == 120 || controller == 121 || controller == 123 {
						delta = try sbyte(otherKnownControllerPos); otherKnownControllerPos += 1
					} else {
						delta = try sbyte(unknownControllerPos); unknownControllerPos += 1
					}
					let v = delta + values[controller]
					values[controller] = v
					out.append(UInt8(truncatingIfNeeded: v & 0x7F))
				} else if kind == 3 {
					if statusChanged { out.append(UInt8(truncatingIfNeeded: channel + 224)) }
					pitchWheel += try sbyte(pitchWheelLsbPos); pitchWheelLsbPos += 1
					pitchWheel += (try sbyte(pitchWheelMsbPos)) << 7; pitchWheelMsbPos += 1
					out.append(UInt8(truncatingIfNeeded: pitchWheel & 0x7F))
					out.append(UInt8(truncatingIfNeeded: (pitchWheel >> 7) & 0x7F))
				} else if kind == 4 {
					if statusChanged { out.append(UInt8(truncatingIfNeeded: channel + 208)) }
					channelPressure += try sbyte(channelPressurePos); channelPressurePos += 1
					out.append(UInt8(truncatingIfNeeded: channelPressure & 0x7F))
				} else if kind == 5 {
					if statusChanged { out.append(UInt8(truncatingIfNeeded: channel + 160)) }
					key += try sbyte(keyPos); keyPos += 1
					keyPressure += try sbyte(keyPressurePos); keyPressurePos += 1
					out.append(UInt8(truncatingIfNeeded: key & 0x7F))
					out.append(UInt8(truncatingIfNeeded: keyPressure & 0x7F))
				} else if kind == 6 {
					if statusChanged { out.append(UInt8(truncatingIfNeeded: channel + 192)) }
					out.append(UInt8(truncatingIfNeeded: try byte(bankSelectPos))); bankSelectPos += 1
				} else {
					throw AudioDecodeError("bad song event kind \(kind)")
				}
			}
		}
		midiBytes = out
		_ = deltaTimePos
		_ = controllerPos
	}

	/// rt4 `Song.create(Js5, group, file)`.
	public static func create(archive: AudioArchive, group: Int, file: Int = 0) -> MidiSong? {
		guard let bytes = archive.fetchFile(group, file) else { return nil }
		return try? MidiSong(bytes)
	}

	/// rt4 `createPrograms`: runs through the song and records, per program
	/// (bank << 7 | patch, percussion bank 128), which keys are ever struck
	/// so only those samples need loading.
	func usedPrograms() -> [Int: [UInt8]] {
		if let p = programs { return p }
		var result: [Int: [UInt8]] = [:]
		var banks = [Int](repeating: 0, count: 16)
		var progs = [Int](repeating: 0, count: 16)
		banks[9] = 128
		progs[9] = 128
		let song = MidiDecoder(midiBytes)
		let trackCount = song.trackCount
		for t in 0..<trackCount {
			song.loadTrackPosition(t)
			song.addDeltaTime(t)
			song.saveTrackPosition(t)
		}
		var guardCount = 0
		outer: while true {
			guardCount += 1
			if guardCount > 5_000_000 { break }
			let track = song.nextTrack()
			if track < 0 { break }
			let time = song.times[track]
			while song.times[track] == time {
				song.loadTrackPosition(track)
				let event = song.nextEvent(track)
				if event == 1 {
					song.loadEndOfTrackPosition()
					song.saveTrackPosition(track)
					if song.hasNoMoreTracks { break outer }
					continue outer
				}
				let kind = event & 0xF0
				if kind == 176 {
					let ch = event & 0xF
					let controller = (event >> 8) & 0x7F
					let value = (event >> 16) & 0x7F
					if controller == 0 { banks[ch] = (banks[ch] & ~0x1FC000) + (value << 14) }
					if controller == 32 { banks[ch] = (banks[ch] & ~0x3F80) + (value << 7) }
				}
				if kind == 192 {
					let ch = event & 0xF
					progs[ch] = banks[ch] + ((event >> 8) & 0x7F)
				}
				if kind == 144 {
					let ch = event & 0xF
					let key = (event >> 8) & 0x7F
					let velocity = (event >> 16) & 0x7F
					if velocity > 0 {
						let program = progs[ch]
						var flags = result[program] ?? [UInt8](repeating: 0, count: 128)
						flags[key] = 1
						result[program] = flags
					}
				}
				song.addDeltaTime(track)
				song.saveTrackPosition(track)
			}
		}
		programs = result
		return result
	}

	func releasePrograms() { programs = nil }
}

/// Reads events from the SMF that `MidiSong` produced, merging tracks by time.
/// Port of rt4 `MidiDecoder`. Event words are `status | data1 << 8 | data2 << 16`;
/// meta events return 1 (end of track), 2 (tempo) or 3 (other).
final class MidiDecoder {
	static let statusLengths: [Int8] = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

	var times: [Int] = []
	private var positions: [Int] = []
	var division = 0
	private var startPositions: [Int] = []
	private var startMillis = 0
	private var statuses: [Int] = []
	private var tempo = 0
	private var data: [UInt8]?
	private var offset = 0

	init() {}
	init(_ bytes: [UInt8]) { initialise(bytes) }

	var isValid: Bool { data != nil }
	var trackCount: Int { positions.count }

	@inline(__always) private func g1() -> Int {
		guard let d = data, offset >= 0, offset < d.count else { offset += 1; return 0 }
		let v = Int(d[offset]); offset += 1
		return v
	}

	/// rt4 `init(byte[])`.
	func initialise(_ bytes: [UInt8]) {
		data = bytes
		offset = 10
		let tracks = (g1() << 8) | g1()
		division = (g1() << 8) | g1()
		tempo = 500000
		startPositions = [Int](repeating: 0, count: tracks)
		var i = 0
		while i < tracks {
			let id = (g1() << 24) | (g1() << 16) | (g1() << 8) | g1()
			let len = (g1() << 24) | (g1() << 16) | (g1() << 8) | g1()
			if id == 1297379947 {
				startPositions[i] = offset
				i += 1
			}
			offset += len
			if offset > bytes.count + 8 { break }
		}
		startMillis = 0
		positions = startPositions
		times = [Int](repeating: 0, count: tracks)
		statuses = [Int](repeating: 0, count: tracks)
	}

	func release() {
		data = nil
		startPositions = []
		positions = []
		times = []
		statuses = []
	}

	/// rt4 `getTimeMillis`: absolute time of `time` ticks in tempo-weighted units.
	func timeMillis(_ time: Int) -> Int { startMillis + time * tempo }

	/// rt4 `hasNextTrack` (despite its name: true when every track is finished).
	var hasNoMoreTracks: Bool {
		for p in positions where p >= 0 { return false }
		return true
	}

	/// rt4 `setStartMillis`: restart every track from its beginning at `millis`.
	func restart(at millis: Int) {
		startMillis = millis
		for i in 0..<positions.count {
			times[i] = 0
			statuses[i] = 0
			offset = startPositions[i]
			addDeltaTime(i)
			positions[i] = offset
		}
	}

	func loadTrackPosition(_ track: Int) { offset = positions[track] }
	func saveTrackPosition(_ track: Int) { positions[track] = offset }
	func loadEndOfTrackPosition() { offset = -1 }

	func addDeltaTime(_ track: Int) {
		guard let d = data else { return }
		var p = offset
		let delta = gVarInt(d, &p)
		offset = p
		times[track] += delta
	}

	/// rt4 `getNextTrack`: the unfinished track with the earliest next event, or -1.
	func nextTrack() -> Int {
		var track = -1
		var minTime = Int(Int32.max)
		for i in 0..<positions.count where positions[i] >= 0 && times[i] < minTime {
			track = i
			minTime = times[i]
		}
		return track
	}

	func nextEvent(_ track: Int) -> Int {
		guard let d = data, offset >= 0, offset < d.count else { return 1 }
		let statusByte = Int(Int8(bitPattern: d[offset]))
		var status: Int
		if statusByte < 0 {
			status = statusByte & 0xFF
			statuses[track] = status
			offset += 1
		} else {
			status = statuses[track]
		}
		if status != 240 && status != 247 {
			return event(track, status)
		}
		var p = offset
		let len = gVarInt(d, &p)
		offset = p
		if status == 247 && len > 0, offset < d.count {
			let s2 = Int(d[offset])
			if (s2 >= 241 && s2 <= 243) || s2 == 246 || s2 == 248 || (s2 >= 250 && s2 <= 252) || s2 == 254 {
				offset += 1
				statuses[track] = s2
				return event(track, s2)
			}
		}
		offset += len
		return 0
	}

	private func event(_ track: Int, _ status: Int) -> Int {
		if status != 255 {
			guard status >= 128 else { return 0 }
			let len = MidiDecoder.statusLengths[status - 128]
			var event = status
			if len >= 1 { event |= g1() << 8 }
			if len >= 2 { event |= g1() << 16 }
			return event
		}
		let type = g1()
		guard let d = data else { return 1 }
		var p = offset
		var skip = gVarInt(d, &p)
		offset = p
		if type == 47 {
			offset += skip
			return 1
		} else if type == 81 {
			let newTempo = (g1() << 16) | (g1() << 8) | g1()
			skip -= 3
			let time = times[track]
			startMillis += time * (tempo - newTempo)
			tempo = newTempo
			offset += skip
			return 2
		} else {
			offset += skip
			return 3
		}
	}
}
