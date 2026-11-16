import Foundation

/// One playing sample: linear-interpolating resampler with stereo gain ramps,
/// forward/backward playback and loop/ping-pong handling.
/// Port of rt4 `SoundPcmStream` (stereo path only; rt4's mono and "aligned"
/// fast paths are numerically the same except for the backward aligned copy,
/// which is kept).
///
/// Positions are 8.8 fixed point sample indices. Gains are in 1/64 units of
/// the 8 bit sample scaled by 256. The output buffer is interleaved stereo
/// `Int32` (left, right) accumulated with Java `int` wraparound.
final class SoundVoice {
	/// Marker in `volume` while the voice is fading out to silence (`Integer.MIN_VALUE`).
	private static let fading = Int(Int32.min)

	let sound: PcmSound
	private let start: Int
	private let end: Int
	private let pingPong: Bool

	/// Playback step per output frame in 1/256 samples; negative plays backward (`anInt342`).
	private(set) var rate: Int
	/// Target volume, or `fading` (`volume`).
	private var volume: Int
	private var pan: Int
	/// Current mono gain and ramp delta (`anInt348`, `anInt344`).
	private var monoGain = 0
	private var monoStep = 0
	/// Current left/right gain and ramp deltas (`anInt355/anInt352`, `anInt347/anInt354`).
	private var leftGain = 0
	private var rightGain = 0
	private var leftStep = 0
	private var rightStep = 0
	/// Frames left in the current gain ramp (`anInt351`).
	private var rampLeft = 0
	/// Remaining loop repeats, -1 = forever (`anInt350`).
	private var loops = 0
	/// Position in 1/256 samples (`anInt346`).
	private(set) var position = 0
	/// Set when the voice has run out and should be dropped from its mixer (rt4 `unlink`).
	private(set) var finished = false

	init(sound: PcmSound, rate: Int, volume: Int, pan: Int = 8192) {
		self.sound = sound
		start = sound.start
		end = sound.end
		pingPong = sound.pingPong
		self.rate = rate
		self.volume = volume
		self.pan = pan
		snapGains()
	}

	/// rt4 `SoundPcmStream.create(PcmSound, volume)` (sound effects): rate is the
	/// sample rate over the output rate, volume is pre-scaled by 64.
	static func effect(_ sound: PcmSound, volume: Int) -> SoundVoice? {
		guard !sound.samples.isEmpty else { return nil }
		let rate = Int(Int64(sound.rate) * 256 * 100 / (Int64(AudioConfig.sampleRate) * 100))
		return SoundVoice(sound: sound, rate: rate, volume: volume << 6)
	}

	/// rt4 `SoundPcmStream.create(PcmSound, rate, volume, pan)` (music notes).
	static func note(_ sound: PcmSound, rate: Int, volume: Int, pan: Int) -> SoundVoice? {
		guard !sound.samples.isEmpty else { return nil }
		return SoundVoice(sound: sound, rate: rate, volume: volume, pan: pan)
	}

	// MARK: pan law (rt4 method419 / method421)

	static func leftGain(_ vol: Int, _ pan: Int) -> Int {
		pan < 0 ? vol : jint(Double(vol) * (Double(16384 - pan) * 1.220703125E-4).squareRoot() + 0.5)
	}

	static func rightGain(_ vol: Int, _ pan: Int) -> Int {
		pan < 0 ? -vol : jint(Double(vol) * (Double(pan) * 1.220703125E-4).squareRoot() + 0.5)
	}

	/// rt4 `method416`.
	private func snapGains() {
		monoGain = volume
		leftGain = SoundVoice.leftGain(volume, pan)
		rightGain = SoundVoice.rightGain(volume, pan)
	}

	// MARK: control surface

	var currentVolume: Int { volume == SoundVoice.fading ? 0 : volume }
	var currentPan: Int { pan < 0 ? -1 : pan }
	var absRate: Int { rate < 0 ? -rate : rate }
	var isRamping: Bool { rampLeft != 0 }
	/// rt4 `method411`: the playhead is outside the sample.
	var isOutOfRange: Bool { position < 0 || position >= sound.samples.count << 8 }

	func setLoops(_ n: Int) { loops = n }

	/// rt4 `method410`: change speed, keeping direction.
	func setRate(_ r: Int) { rate = rate < 0 ? -r : r }

	/// rt4 `method409`: play backward.
	func reverse() { rate = -(rate < 0 ? -rate : rate) }

	/// rt4 `method401`.
	func setPosition(_ p: Int) {
		let limit = sound.samples.count << 8
		position = max(-1, min(p, limit))
	}

	/// rt4 `method408` (and `setVolume`): jump to a volume/pan without ramping.
	func setVolume(_ vol: Int, pan: Int) {
		volume = vol
		self.pan = pan
		rampLeft = 0
		snapGains()
	}

	/// rt4 `method417`: ramp to a volume/pan over `frames` frames.
	func rampTo(frames: Int, volume vol: Int, pan newPan: Int) {
		if frames == 0 {
			setVolume(vol, pan: newPan)
			return
		}
		let l = SoundVoice.leftGain(vol, newPan)
		let r = SoundVoice.rightGain(vol, newPan)
		if leftGain == l && rightGain == r {
			rampLeft = 0
			return
		}
		var biggest = vol - monoGain
		if monoGain - vol > biggest { biggest = monoGain - vol }
		if l - leftGain > biggest { biggest = l - leftGain }
		if leftGain - l > biggest { biggest = leftGain - l }
		if r - rightGain > biggest { biggest = r - rightGain }
		if rightGain - r > biggest { biggest = rightGain - r }
		var len = frames
		if len > biggest { len = biggest }
		if len <= 0 {
			setVolume(vol, pan: newPan)
			return
		}
		rampLeft = len
		volume = vol
		pan = newPan
		monoStep = (vol - monoGain) / len
		leftStep = (l - leftGain) / len
		rightStep = (r - rightGain) / len
	}

	/// rt4 `method398`.
	func rampTo(frames: Int, volume vol: Int) { rampTo(frames: frames, volume: vol, pan: currentPan) }

	/// rt4 `method384`: fade to silence over `frames` frames, then finish.
	func fadeOut(frames: Int) {
		if frames == 0 {
			setVolume(0, pan: currentPan)
			finished = true
		} else if leftGain == 0 && rightGain == 0 {
			rampLeft = 0
			volume = 0
			monoGain = 0
			finished = true
		} else {
			var biggest = -monoGain
			if monoGain > biggest { biggest = monoGain }
			if -leftGain > biggest { biggest = -leftGain }
			if leftGain > biggest { biggest = leftGain }
			if -rightGain > biggest { biggest = -rightGain }
			if rightGain > biggest { biggest = rightGain }
			var len = frames
			if len > biggest { len = biggest }
			if len <= 0 { len = 1 }
			rampLeft = len
			volume = SoundVoice.fading
			monoStep = -monoGain / len
			leftStep = -leftGain / len
			rightStep = -rightGain / len
		}
	}

	/// rt4 `method406`: abandon a ramp in progress.
	private func abortRamp() {
		if rampLeft == 0 { return }
		if volume == SoundVoice.fading { volume = 0 }
		rampLeft = 0
		snapGains()
	}

	/// rt4 `method383`: called when a ramp segment ends; starts the next segment or finishes.
	/// Returns true when the voice has faded out completely.
	private func nextRampSegment() -> Bool {
		var target = volume
		var l = 0, r = 0
		if target == SoundVoice.fading {
			target = 0
		} else {
			l = SoundVoice.leftGain(target, pan)
			r = SoundVoice.rightGain(target, pan)
		}
		if monoGain != target || leftGain != l || rightGain != r {
			if monoGain < target {
				monoStep = 1
				rampLeft = target - monoGain
			} else if monoGain > target {
				monoStep = -1
				rampLeft = monoGain - target
			} else {
				monoStep = 0
			}
			if leftGain < l {
				leftStep = 1
				if rampLeft == 0 || rampLeft > l - leftGain { rampLeft = l - leftGain }
			} else if leftGain > l {
				leftStep = -1
				if rampLeft == 0 || rampLeft > leftGain - l { rampLeft = leftGain - l }
			} else {
				leftStep = 0
			}
			if rightGain < r {
				rightStep = 1
				if rampLeft == 0 || rampLeft > r - rightGain { rampLeft = r - rightGain }
			} else if rightGain > r {
				rightStep = -1
				if rampLeft == 0 || rampLeft > rightGain - r { rampLeft = rightGain - r }
			} else {
				rightStep = 0
			}
			return false
		} else if volume == SoundVoice.fading {
			volume = 0
			monoGain = 0
			leftGain = 0
			rightGain = 0
			finished = true
			return true
		} else {
			snapGains()
			return false
		}
	}

	// MARK: sample access

	@inline(__always) private func sample(_ i: Int) -> Int {
		(i >= 0 && i < sound.samples.count) ? Int(sound.samples[i]) : 0
	}

	// MARK: rendering primitives

	/// rt4 `method388`/`method400`: forward interpolating mix of frames `cur..<limitFrame`
	/// until the position reaches `limit8` (1/256 samples). `edge` is the sample after the
	/// last real one (loop start or silence). Returns the frame index reached.
	private func mixForward(_ out: inout [Int32], _ curIn: Int, _ limit8: Int, _ limitFrame: Int, _ edge: Int) -> Int {
		var cur = curIn
		while true {
			if rampLeft > 0 {
				var stop = cur + rampLeft
				if stop > limitFrame { stop = limitFrame }
				rampLeft += cur
				cur = forwardRun(&out, cur, limit8, stop, edge, ramp: true)
				rampLeft -= cur
				if rampLeft != 0 { return cur }
				if !nextRampSegment() { continue }
				return limitFrame
			}
			return forwardRun(&out, cur, limit8, limitFrame, edge, ramp: false)
		}
	}

	private func forwardRun(_ out: inout [Int32], _ curIn: Int, _ limit8: Int, _ endFrame: Int, _ edge: Int, ramp: Bool) -> Int {
		var cur = curIn
		var pos = position
		var vl = leftGain
		var vr = rightGain
		let dl = ramp ? leftStep : 0
		let dr = ramp ? rightStep : 0
		let step = rate
		if ramp { monoGain -= monoStep * cur }
		var firstEnd: Int
		if step == 0 { firstEnd = endFrame } else {
			firstEnd = cur + (limit8 + step - pos - 257) / step
			if firstEnd > endFrame { firstEnd = endFrame }
		}
		let n = sound.samples.count
		while cur < firstEnd {
			let idx = pos >> 8
			let s0 = (idx >= 0 && idx < n) ? Int(sound.samples[idx]) : 0
			let s1 = (idx + 1 >= 0 && idx + 1 < n) ? Int(sound.samples[idx + 1]) : 0
			let v = (s0 << 8) + (s1 - s0) * (pos & 0xFF)
			out[cur * 2] = out[cur * 2] &+ Int32(truncatingIfNeeded: jw(v * vl) >> 6)
			vl += dl
			out[cur * 2 + 1] = out[cur * 2 + 1] &+ Int32(truncatingIfNeeded: jw(v * vr) >> 6)
			vr += dr
			pos += step
			cur += 1
		}
		var secondEnd: Int
		if step == 0 { secondEnd = endFrame } else {
			secondEnd = cur + (limit8 + step - pos - 1) / step
			if secondEnd > endFrame { secondEnd = endFrame }
		}
		while cur < secondEnd {
			let idx = pos >> 8
			let s0 = (idx >= 0 && idx < n) ? Int(sound.samples[idx]) : 0
			let v = (s0 << 8) + (edge - s0) * (pos & 0xFF)
			out[cur * 2] = out[cur * 2] &+ Int32(truncatingIfNeeded: jw(v * vl) >> 6)
			vl += dl
			out[cur * 2 + 1] = out[cur * 2 + 1] &+ Int32(truncatingIfNeeded: jw(v * vr) >> 6)
			vr += dr
			pos += step
			cur += 1
		}
		if ramp {
			monoGain += monoStep * cur
			leftGain = vl
			rightGain = vr
		}
		position = pos
		return cur
	}

	/// rt4 `method403`: backward counterpart of `mixForward`.
	private func mixBackward(_ out: inout [Int32], _ curIn: Int, _ limit8: Int, _ limitFrame: Int, _ edge: Int) -> Int {
		var cur = curIn
		while true {
			if rampLeft > 0 {
				var stop = cur + rampLeft
				if stop > limitFrame { stop = limitFrame }
				rampLeft += cur
				if rate == -256 && (position & 0xFF) == 0 {
					cur = backwardAligned(&out, cur, limit8, stop, ramp: true)
				} else {
					cur = backwardRun(&out, cur, limit8, stop, edge, ramp: true)
				}
				rampLeft -= cur
				if rampLeft != 0 { return cur }
				if !nextRampSegment() { continue }
				return limitFrame
			}
			if rate == -256 && (position & 0xFF) == 0 {
				return backwardAligned(&out, cur, limit8, limitFrame, ramp: false)
			}
			return backwardRun(&out, cur, limit8, limitFrame, edge, ramp: false)
		}
	}

	private func backwardRun(_ out: inout [Int32], _ curIn: Int, _ limit8: Int, _ endFrame: Int, _ edge: Int, ramp: Bool) -> Int {
		var cur = curIn
		var pos = position
		var vl = leftGain
		var vr = rightGain
		let dl = ramp ? leftStep : 0
		let dr = ramp ? rightStep : 0
		let step = rate
		if ramp { monoGain -= monoStep * cur }
		var firstEnd: Int
		if step == 0 { firstEnd = endFrame } else {
			firstEnd = cur + (limit8 + step + 256 - pos) / step
			if firstEnd > endFrame { firstEnd = endFrame }
		}
		while cur < firstEnd {
			let idx = pos >> 8
			let s0 = sample(idx - 1)
			let v = (s0 << 8) + (sample(idx) - s0) * (pos & 0xFF)
			out[cur * 2] = out[cur * 2] &+ Int32(truncatingIfNeeded: jw(v * vl) >> 6)
			vl += dl
			out[cur * 2 + 1] = out[cur * 2 + 1] &+ Int32(truncatingIfNeeded: jw(v * vr) >> 6)
			vr += dr
			pos += step
			cur += 1
		}
		var secondEnd: Int
		if step == 0 { secondEnd = endFrame } else {
			secondEnd = cur + (limit8 + step - pos) / step
			if secondEnd > endFrame { secondEnd = endFrame }
		}
		while cur < secondEnd {
			let v = (edge << 8) + (sample(pos >> 8) - edge) * (pos & 0xFF)
			out[cur * 2] = out[cur * 2] &+ Int32(truncatingIfNeeded: jw(v * vl) >> 6)
			vl += dl
			out[cur * 2 + 1] = out[cur * 2 + 1] &+ Int32(truncatingIfNeeded: jw(v * vr) >> 6)
			vr += dr
			pos += step
			cur += 1
		}
		if ramp {
			monoGain += monoStep * cur
			leftGain = vl
			rightGain = vr
		}
		position = pos
		return cur
	}

	/// rt4 `method414`/`method402`: whole-sample backward copy at exactly -1.0 speed.
	private func backwardAligned(_ out: inout [Int32], _ curIn: Int, _ limit8: Int, _ endFrame: Int, ramp: Bool) -> Int {
		var cur = curIn
		var idx = position >> 8
		let limitIdx = limit8 >> 8
		var vl = leftGain << 2
		var vr = rightGain << 2
		let dl = ramp ? leftStep << 2 : 0
		let dr = ramp ? rightStep << 2 : 0
		var stop = cur + idx + 1 - limitIdx
		if stop > endFrame { stop = endFrame }
		if ramp { monoGain += monoStep * (stop - cur) }
		while cur < stop {
			let s = sample(idx)
			out[cur * 2] = out[cur * 2] &+ Int32(truncatingIfNeeded: s * vl)
			out[cur * 2 + 1] = out[cur * 2 + 1] &+ Int32(truncatingIfNeeded: s * vr)
			vl += dl
			vr += dr
			idx -= 1
			cur += 1
		}
		if ramp {
			leftGain = vl >> 2
			rightGain = vr >> 2
		}
		position = idx << 8
		return cur
	}

	// MARK: mixing entry points

	/// rt4 `read`: mixes `len` frames into `out` starting at frame `off`.
	func read(_ out: inout [Int32], _ off: Int, _ len: Int) {
		if volume == 0 && rampLeft == 0 {
			skip(len)
			return
		}
		let start8 = start << 8
		let end8 = end << 8
		let len8 = sound.samples.count << 8
		let loopSpan = end8 - start8
		if loopSpan <= 0 { loops = 0 }
		var cur = off
		let endFrame = off + len
		if position < 0 {
			if rate <= 0 {
				abortRamp()
				finished = true
				return
			}
			position = 0
		}
		if position >= len8 {
			if rate >= 0 {
				abortRamp()
				finished = true
				return
			}
			position = len8 - 1
		}
		if loops >= 0 {
			var finishedLoops = false
			if loops > 0 {
				if pingPong {
					if rate < 0 {
						cur = mixBackward(&out, cur, start8, endFrame, sample(start))
						if position >= start8 { return }
						position = start8 + start8 - position - 1
						rate = -rate
						loops -= 1
						if loops == 0 { finishedLoops = true }
					}
					while !finishedLoops {
						cur = mixForward(&out, cur, end8, endFrame, sample(end - 1))
						if position < end8 { return }
						position = end8 + end8 - position - 1
						rate = -rate
						loops -= 1
						if loops == 0 { break }
						cur = mixBackward(&out, cur, start8, endFrame, sample(start))
						if position >= start8 { return }
						position = start8 + start8 - position - 1
						rate = -rate
						loops -= 1
						if loops == 0 { break }
					}
				} else if rate < 0 {
					while true {
						cur = mixBackward(&out, cur, start8, endFrame, sample(end - 1))
						if position >= start8 { return }
						let n = (end8 - position - 1) / loopSpan
						if n >= loops {
							position += loopSpan * loops
							loops = 0
							break
						}
						position += loopSpan * n
						loops -= n
					}
				} else {
					while true {
						cur = mixForward(&out, cur, end8, endFrame, sample(start))
						if position < end8 { return }
						let n = (position - start8) / loopSpan
						if n >= loops {
							position -= loopSpan * loops
							loops = 0
							break
						}
						position -= loopSpan * n
						loops -= n
					}
				}
			}
			if rate < 0 {
				_ = mixBackward(&out, cur, 0, endFrame, 0)
				if position < 0 {
					position = -1
					abortRamp()
					finished = true
				}
			} else {
				_ = mixForward(&out, cur, len8, endFrame, 0)
				if position >= len8 {
					position = len8
					abortRamp()
					finished = true
				}
			}
		} else if pingPong {
			if rate < 0 {
				cur = mixBackward(&out, cur, start8, endFrame, sample(start))
				if position >= start8 { return }
				position = start8 + start8 - position - 1
				rate = -rate
			}
			while true {
				cur = mixForward(&out, cur, end8, endFrame, sample(end - 1))
				if position < end8 { return }
				position = end8 + end8 - position - 1
				rate = -rate
				cur = mixBackward(&out, cur, start8, endFrame, sample(start))
				if position >= start8 { return }
				position = start8 + start8 - position - 1
				rate = -rate
			}
		} else if rate < 0 {
			while true {
				cur = mixBackward(&out, cur, start8, endFrame, sample(end - 1))
				if position >= start8 { return }
				position = end8 - (end8 - 1 - position) % loopSpan - 1
			}
		} else {
			while true {
				cur = mixForward(&out, cur, end8, endFrame, sample(start))
				if position < end8 { return }
				position = start8 + (position - start8) % loopSpan
			}
		}
	}

	/// rt4 `skip`: advances the playhead and ramps without producing audio.
	func skip(_ lenIn: Int) {
		var len = lenIn
		if rampLeft > 0 {
			if len >= rampLeft {
				if volume == SoundVoice.fading {
					volume = 0
					monoGain = 0
					leftGain = 0
					rightGain = 0
					finished = true
					len = rampLeft
				}
				rampLeft = 0
				snapGains()
			} else {
				monoGain += monoStep * len
				leftGain += leftStep * len
				rightGain += rightStep * len
				rampLeft -= len
			}
		}
		let start8 = start << 8
		let end8 = end << 8
		let len8 = sound.samples.count << 8
		let loopSpan = end8 - start8
		if loopSpan <= 0 { loops = 0 }
		if position < 0 {
			if rate <= 0 {
				abortRamp()
				finished = true
				return
			}
			position = 0
		}
		if position >= len8 {
			if rate >= 0 {
				abortRamp()
				finished = true
				return
			}
			position = len8 - 1
		}
		position += rate * len
		if loops >= 0 {
			if loops > 0 {
				if pingPong {
					var done = false
					if rate < 0 {
						if position >= start8 { return }
						position = start8 + start8 - position - 1
						rate = -rate
						loops -= 1
						if loops == 0 { done = true }
					}
					while !done {
						if position < end8 { return }
						position = end8 + end8 - position - 1
						rate = -rate
						loops -= 1
						if loops == 0 { break }
						if position >= start8 { return }
						position = start8 + start8 - position - 1
						rate = -rate
						loops -= 1
						if loops == 0 { break }
					}
				} else {
					if rate < 0 {
						if position >= start8 { return }
						let n = (end8 - position - 1) / loopSpan
						if n >= loops {
							position += loopSpan * loops
							loops = 0
						} else {
							position += loopSpan * n
							loops -= n
							return
						}
					} else if position >= end8 {
						let n = (position - start8) / loopSpan
						if n >= loops {
							position -= loopSpan * loops
							loops = 0
						} else {
							position -= loopSpan * n
							loops -= n
							return
						}
					} else {
						return
					}
				}
			}
			if rate < 0 {
				if position < 0 {
					position = -1
					abortRamp()
					finished = true
				}
			} else if position >= len8 {
				position = len8
				abortRamp()
				finished = true
			}
		} else if pingPong {
			if rate < 0 {
				if position >= start8 { return }
				position = start8 + start8 - position - 1
				rate = -rate
			}
			while position >= end8 {
				position = end8 + end8 - position - 1
				rate = -rate
				if position >= start8 { return }
				position = start8 + start8 - position - 1
				rate = -rate
			}
		} else if rate < 0 {
			if position >= start8 { return }
			position = end8 - (end8 - 1 - position) % loopSpan - 1
		} else if position >= end8 {
			position = start8 + (position - start8) % loopSpan
		}
	}
}
