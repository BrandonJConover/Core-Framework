import Foundation

/// Piecewise-linear envelope. Port of rt4 `SynthEnvelope`.
final class SynthEnvelope {
	var wavetable = 0
	var minInterval = 0
	var maxInterval = 0
	private var phase = 0
	private var level = 0
	private var slope = 0
	private var nextTime = 0
	private var time = 0
	private var stages = 2
	private var times = [0, 65535]
	private var levels = [0, 65535]

	/// rt4 `decodeStages`.
	func decodeStages(_ p: inout Packet) throws {
		stages = try p.g1()
		times = [Int](repeating: 0, count: stages)
		levels = [Int](repeating: 0, count: stages)
		for i in 0..<stages {
			times[i] = try p.g2()
			levels[i] = try p.g2()
		}
	}

	/// rt4 `decode`.
	func decode(_ p: inout Packet) throws {
		wavetable = try p.g1()
		minInterval = Int(try p.g4())
		maxInterval = Int(try p.g4())
		try decodeStages(&p)
	}

	func reset() {
		nextTime = 0
		phase = 0
		slope = 0
		level = 0
		time = 0
	}

	/// rt4 `nextLevel(sampleCount)`: advances one sample and returns the 0...65535 level.
	func nextLevel(_ sampleCount: Int) -> Int {
		if time >= nextTime {
			level = jw(levels[phase] << 15)
			phase += 1
			if phase >= stages { phase = stages - 1 }
			nextTime = jint(Double(times[phase]) / 65536.0 * Double(sampleCount))
			if nextTime > time {
				slope = (jw(levels[phase] << 15) - level) / (nextTime - time)
			}
		}
		level = jw(level + slope)
		time += 1
		return jw(level - slope) >> 15
	}
}

/// Bi-quad cascade filter, animated by an envelope. Port of rt4 `SynthFilter`.
final class SynthFilter {
	var pairs = [0, 0]
	private var gain = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 4), count: 2), count: 2)
	private var octaves = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 4), count: 2), count: 2)
	private var inverseGain = [0, 0]
	var coefficients = [[Int]](repeating: [Int](repeating: 0, count: 8), count: 2)
	private var floatingCoefficients = [[Float]](repeating: [Float](repeating: 0, count: 8), count: 2)
	var inverseA0 = 0
	private var floatingInverseA0: Float = 0

	private static func octavePhase(_ octave: Float) -> Float {
		let f = Float(pow(2.0, Double(octave))) * 32.703197
		return f * 3.1415927 / 11025.0
	}

	/// rt4 `decode(Buffer, SynthEnvelope)`.
	func decode(_ p: inout Packet, _ envelope: SynthEnvelope) throws {
		let count = try p.g1()
		pairs[0] = count >> 4
		pairs[1] = count & 0xF
		if count == 0 {
			inverseGain[0] = 0
			inverseGain[1] = 0
			return
		}
		inverseGain[0] = try p.g2()
		inverseGain[1] = try p.g2()
		let flags = try p.g1()
		for dir in 0..<2 {
			for i in 0..<pairs[dir] {
				guard i < 4 else { throw AudioDecodeError("synth filter has more than 4 pairs") }
				octaves[dir][0][i] = try p.g2()
				gain[dir][0][i] = try p.g2()
			}
		}
		for dir in 0..<2 {
			for i in 0..<pairs[dir] {
				if (flags & ((1 << (dir * 4)) << i)) == 0 {
					octaves[dir][1][i] = octaves[dir][0][i]
					gain[dir][1][i] = gain[dir][0][i]
				} else {
					octaves[dir][1][i] = try p.g2()
					gain[dir][1][i] = try p.g2()
				}
			}
		}
		if flags != 0 || inverseGain[1] != inverseGain[0] {
			try envelope.decodeStages(&p)
		}
	}

	private func amplitude(_ dir: Int, _ i: Int, _ t: Float) -> Float {
		let g = Float(gain[dir][0][i]) + t * Float(gain[dir][1][i] - gain[dir][0][i])
		let db = g * 0.0015258789
		return 1.0 - Float(pow(10.0, Double(-db / 20.0)))
	}

	private func phase(_ dir: Int, _ i: Int, _ t: Float) -> Float {
		let o = Float(octaves[dir][0][i]) + t * Float(octaves[dir][1][i] - octaves[dir][0][i])
		return SynthFilter.octavePhase(o * 1.2207031e-4)
	}

	/// rt4 `compute(direction, t)`: fills `coefficients[dir]`, returns the tap count.
	func compute(_ dir: Int, _ t: Float) -> Int {
		if dir == 0 {
			let g = Float(inverseGain[0]) + Float(inverseGain[1] - inverseGain[0]) * t
			let db = g * 0.0030517578
			floatingInverseA0 = Float(pow(0.1, Double(db / 20.0)))
			inverseA0 = jint(Double(floatingInverseA0 * 65536.0))
		}
		if pairs[dir] == 0 { return 0 }
		var a = amplitude(dir, 0, t)
		floatingCoefficients[dir][0] = -2.0 * a * Float(cos(Double(phase(dir, 0, t))))
		floatingCoefficients[dir][1] = a * a
		var i = 1
		while i < pairs[dir] {
			a = amplitude(dir, i, t)
			let c1 = -2.0 * a * Float(cos(Double(phase(dir, i, t))))
			let c2 = a * a
			floatingCoefficients[dir][i * 2 + 1] = floatingCoefficients[dir][i * 2 - 1] * c2
			floatingCoefficients[dir][i * 2] = floatingCoefficients[dir][i * 2 - 1] * c1 + floatingCoefficients[dir][i * 2 - 2] * c2
			var j = i * 2 - 1
			while j >= 2 {
				floatingCoefficients[dir][j] += floatingCoefficients[dir][j - 1] * c1 + floatingCoefficients[dir][j - 2] * c2
				j -= 1
			}
			floatingCoefficients[dir][1] += floatingCoefficients[dir][0] * c1 + c2
			floatingCoefficients[dir][0] += c1
			i += 1
		}
		if dir == 0 {
			for k in 0..<(pairs[0] * 2) { floatingCoefficients[0][k] *= floatingInverseA0 }
		}
		for k in 0..<(pairs[dir] * 2) {
			coefficients[dir][k] = jint(Double(floatingCoefficients[dir][k] * 65536.0))
		}
		return pairs[dir] * 2
	}
}

/// One oscillator-bank voice of a synthesised effect. Port of rt4 `SynthInstrument`.
final class SynthInstrument {
	private static let noise: [Int] = {
		var r = JavaRandom(seed: 0)
		return (0..<32768).map { _ in (Int(r.nextInt()) & 2) - 1 }
	}()
	private static let sine: [Int] = (0..<32768).map { jint(sin(Double($0) / 5215.1903) * 16384.0) }

	private var amplitudeModulationAmplitudeEnvelope: SynthEnvelope?
	private var gateClosedPhaseEnvelope: SynthEnvelope?
	private var amplitudeEnvelope = SynthEnvelope()
	private var gateOpenPhaseEnvelope: SynthEnvelope?
	private var phaseEnvelope = SynthEnvelope()
	private var filterEnvelope = SynthEnvelope()
	private var amplitudeModulationEnvelope: SynthEnvelope?
	private var filter = SynthFilter()
	private var phaseModulationAmplitudeEnvelope: SynthEnvelope?
	private var phaseModulationEnvelope: SynthEnvelope?
	/// Duration in milliseconds.
	var length = 500
	private var reverbDelay = 0
	/// Start offset in milliseconds.
	var start = 0
	private var harmonicVolume = [Int](repeating: 0, count: 5)
	private var harmonicDelay = [Int](repeating: 0, count: 5)
	private var reverbVolume = 100
	private var harmonicSemitone = [Int](repeating: 0, count: 5)

	/// rt4 `method3504`: one oscillator sample for waveform `wave`.
	private func oscillate(_ phase: Int, _ amp: Int, _ wave: Int) -> Int {
		switch wave {
		case 1: return (phase & 0x7FFF) < 16384 ? amp : -amp
		case 2: return jw(SynthInstrument.sine[phase & 0x7FFF] * amp) >> 14
		case 3: return (jw((phase & 0x7FFF) * amp) >> 14) - amp
		case 4: return jw(SynthInstrument.noise[(phase / 2607) & 0x7FFF] * amp)
		default: return 0
		}
	}

	/// rt4 `decode` (`method3506`).
	func decode(_ p: inout Packet) throws {
		phaseEnvelope = SynthEnvelope()
		try phaseEnvelope.decode(&p)
		amplitudeEnvelope = SynthEnvelope()
		try amplitudeEnvelope.decode(&p)
		var flag = try p.g1()
		if flag != 0 {
			p.offset -= 1
			let a = SynthEnvelope(); try a.decode(&p); phaseModulationEnvelope = a
			let b = SynthEnvelope(); try b.decode(&p); phaseModulationAmplitudeEnvelope = b
		}
		flag = try p.g1()
		if flag != 0 {
			p.offset -= 1
			let a = SynthEnvelope(); try a.decode(&p); amplitudeModulationEnvelope = a
			let b = SynthEnvelope(); try b.decode(&p); amplitudeModulationAmplitudeEnvelope = b
		}
		flag = try p.g1()
		if flag != 0 {
			p.offset -= 1
			let a = SynthEnvelope(); try a.decode(&p); gateClosedPhaseEnvelope = a
			let b = SynthEnvelope(); try b.decode(&p); gateOpenPhaseEnvelope = b
		}
		for i in 0..<10 {
			let vol = try p.gsmarts()
			if vol == 0 { break }
			guard i < 5 else { throw AudioDecodeError("synth instrument has more than 5 harmonics") }
			harmonicVolume[i] = vol
			harmonicSemitone[i] = try p.gsmart()
			harmonicDelay[i] = try p.gsmarts()
		}
		reverbDelay = try p.gsmarts()
		reverbVolume = try p.gsmarts()
		length = try p.g2()
		start = try p.g2()
		filter = SynthFilter()
		filterEnvelope = SynthEnvelope()
		try filter.decode(&p, filterEnvelope)
	}

	/// rt4 `getSamples(sampleCount, durationMs)`: 16 bit range samples.
	func render(sampleCount n: Int, duration: Int) -> [Int] {
		var samples = [Int](repeating: 0, count: n)
		if duration < 10 { return samples }
		let ratio = Double(n) / (Double(duration) + 0.0)
		phaseEnvelope.reset()
		amplitudeEnvelope.reset()
		var pmStep = 0, pmMin = 0, pmPhase = 0
		if let pm = phaseModulationEnvelope, let pma = phaseModulationAmplitudeEnvelope {
			pm.reset()
			pma.reset()
			pmStep = jint(Double(pm.maxInterval - pm.minInterval) * 32.768 / ratio)
			pmMin = jint(Double(pm.minInterval) * 32.768 / ratio)
		}
		var amStep = 0, amMin = 0, amPhase = 0
		if let am = amplitudeModulationEnvelope, let ama = amplitudeModulationAmplitudeEnvelope {
			am.reset()
			ama.reset()
			amStep = jint(Double(am.maxInterval - am.minInterval) * 32.768 / ratio)
			amMin = jint(Double(am.minInterval) * 32.768 / ratio)
		}
		var oscTimes = [Int](repeating: 0, count: 5)
		var oscStart = [Int](repeating: 0, count: 5)
		var oscAmp = [Int](repeating: 0, count: 5)
		var oscRange = [Int](repeating: 0, count: 5)
		var oscMin = [Int](repeating: 0, count: 5)
		for i in 0..<5 where harmonicVolume[i] != 0 {
			oscTimes[i] = 0
			oscStart[i] = jint(Double(harmonicDelay[i]) * ratio)
			oscAmp[i] = (harmonicVolume[i] << 14) / 100
			oscRange[i] = jint(Double(phaseEnvelope.maxInterval - phaseEnvelope.minInterval) * 32.768 * pow(1.0057929410678534, Double(harmonicSemitone[i])) / ratio)
			oscMin[i] = jint(Double(phaseEnvelope.minInterval) * 32.768 / ratio)
		}
		let wave = phaseEnvelope.wavetable
		for t in 0..<n {
			var phase = phaseEnvelope.nextLevel(n)
			var amp = amplitudeEnvelope.nextLevel(n)
			if let pm = phaseModulationEnvelope, let pma = phaseModulationAmplitudeEnvelope {
				let rate = pm.nextLevel(n)
				let depth = pma.nextLevel(n)
				phase += oscillate(pmPhase, depth, pm.wavetable) >> 1
				pmPhase = jw(pmPhase + (jw(rate * pmStep) >> 16) + pmMin)
			}
			if let am = amplitudeModulationEnvelope, let ama = amplitudeModulationAmplitudeEnvelope {
				let rate = am.nextLevel(n)
				let depth = ama.nextLevel(n)
				amp = jw(amp * ((oscillate(amPhase, depth, am.wavetable) >> 1) + 32768)) >> 15
				amPhase = jw(amPhase + (jw(rate * amStep) >> 16) + amMin)
			}
			for h in 0..<5 where harmonicVolume[h] != 0 {
				let at = t + oscStart[h]
				if at < n {
					samples[at] = jw(samples[at] + oscillate(oscTimes[h], jw(amp * oscAmp[h]) >> 15, wave))
					oscTimes[h] = jw(oscTimes[h] + (jw(phase * oscRange[h]) >> 16) + oscMin[h])
				}
			}
		}
		if let closed = gateClosedPhaseEnvelope, let open = gateOpenPhaseEnvelope {
			closed.reset()
			open.reset()
			var counter = 0
			var gateClosed = true
			for t in 0..<n {
				let c = closed.nextLevel(n)
				let o = open.nextLevel(n)
				let threshold: Int
				if gateClosed {
					threshold = closed.minInterval + (jw((closed.maxInterval - closed.minInterval) * c) >> 8)
				} else {
					threshold = closed.minInterval + (jw((closed.maxInterval - closed.minInterval) * o) >> 8)
				}
				counter += 256
				if counter >= threshold {
					counter = 0
					gateClosed = !gateClosed
				}
				if gateClosed { samples[t] = 0 }
			}
		}
		if reverbDelay > 0 && reverbVolume > 0 {
			let d = jint(Double(reverbDelay) * ratio)
			if d < n {
				for i in d..<n {
					samples[i] = jw(samples[i] + jw(samples[i - d] * reverbVolume) / 100)
				}
			}
		}
		if filter.pairs[0] > 0 || filter.pairs[1] > 0 {
			applyFilter(&samples, n)
		}
		for i in 0..<n {
			if samples[i] < -32768 { samples[i] = -32768 }
			if samples[i] > 32767 { samples[i] = 32767 }
		}
		return samples
	}

	/// The IIR filter section of rt4 `getSamples` (feed-forward `coefficients[0]`, feedback `coefficients[1]`).
	private func applyFilter(_ samples: inout [Int], _ n: Int) {
		filterEnvelope.reset()
		var level = filterEnvelope.nextLevel(n + 1)
		var ffCount = filter.compute(0, Float(level) / 65536.0)
		var fbCount = filter.compute(1, Float(level) / 65536.0)
		guard n >= ffCount + fbCount else { return }
		var i = 0
		var limit = fbCount
		if fbCount > n - ffCount { limit = n - ffCount }
		while i < limit {
			var acc = jw((samples[i + ffCount] * filter.inverseA0) >> 16)
			for k in 0..<ffCount {
				acc = jw(acc + jw((samples[i + ffCount - k - 1] * filter.coefficients[0][k]) >> 16))
			}
			for k in 0..<i {
				acc = jw(acc - jw((samples[i - k - 1] * filter.coefficients[1][k]) >> 16))
			}
			samples[i] = acc
			level = filterEnvelope.nextLevel(n + 1)
			i += 1
		}
		limit = 128
		while true {
			if limit > n - ffCount { limit = n - ffCount }
			while i < limit {
				var acc = jw((samples[i + ffCount] * filter.inverseA0) >> 16)
				for k in 0..<ffCount {
					acc = jw(acc + jw((samples[i + ffCount - k - 1] * filter.coefficients[0][k]) >> 16))
				}
				for k in 0..<fbCount {
					acc = jw(acc - jw((samples[i - k - 1] * filter.coefficients[1][k]) >> 16))
				}
				samples[i] = acc
				level = filterEnvelope.nextLevel(n + 1)
				i += 1
			}
			if i >= n - ffCount {
				while i < n {
					var acc = 0
					var k = i + ffCount - n
					while k < ffCount {
						acc = jw(acc + jw((samples[i + ffCount - k - 1] * filter.coefficients[0][k]) >> 16))
						k += 1
					}
					for k in 0..<fbCount {
						acc = jw(acc - jw((samples[i - k - 1] * filter.coefficients[1][k]) >> 16))
					}
					samples[i] = acc
					_ = filterEnvelope.nextLevel(n + 1)
					i += 1
				}
				break
			}
			ffCount = filter.compute(0, Float(level) / 65536.0)
			fbCount = filter.compute(1, Float(level) / 65536.0)
			limit += 128
		}
	}
}

/// A synthesised sound effect: up to ten instruments mixed to 8 bit.
/// Port of rt4 `SynthSound` (archive 4, group = sound id, file 0).
public final class SynthSound {
	private var instruments = [SynthInstrument?](repeating: nil, count: 10)
	private var start = 0
	private var end = 0

	/// rt4 `SynthSound(Buffer)`.
	public init(_ bytes: [UInt8]) throws {
		var p = Packet(bytes)
		for i in 0..<10 {
			let marker = try p.g1()
			if marker != 0 {
				p.offset -= 1
				let ins = SynthInstrument()
				try ins.decode(&p)
				instruments[i] = ins
			}
		}
		start = try p.g2()
		end = try p.g2()
	}

	/// rt4 `SynthSound.create(Js5, group, file)`.
	public static func create(archive: AudioArchive, group: Int, file: Int = 0) -> SynthSound? {
		guard let bytes = archive.fetchFile(group, file) else { return nil }
		return try? SynthSound(bytes)
	}

	/// rt4 `getSamples`: mixes the instruments into signed 8 bit samples.
	private func mix() -> [Int8] {
		var total = 0
		for case let ins? in instruments where ins.length + ins.start > total { total = ins.length + ins.start }
		if total == 0 { return [] }
		let rate = AudioConfig.sampleRate
		var out = [Int8](repeating: 0, count: total * rate / 1000)
		for case let ins? in instruments {
			let n = ins.length * rate / 1000
			let offset = ins.start * rate / 1000
			let s = ins.render(sampleCount: n, duration: ins.length)
			for i in 0..<n where i + offset < out.count {
				var v = Int(out[i + offset]) + (s[i] >> 8)
				if ((v + 128) & ~0xFF) != 0 { v = (v >> 31) ^ 0x7F }
				out[i + offset] = Int8(truncatingIfNeeded: v)
			}
		}
		return out
	}

	/// rt4 `toPcmSound`.
	public func toPcmSound() -> PcmSound {
		let rate = AudioConfig.sampleRate
		return PcmSound(rate: rate, samples: mix(), start: start * rate / 1000, end: end * rate / 1000)
	}

	/// rt4 `getStart`: trims leading silence (in 20 ms units) off every instrument and
	/// returns how many 20 ms client ticks the sound should be delayed by.
	public func trimLeadingSilence() -> Int {
		var minTicks = 9999999
		for case let ins? in instruments where ins.start / 20 < minTicks { minTicks = ins.start / 20 }
		if start < end && start / 20 < minTicks { minTicks = start / 20 }
		if minTicks == 9999999 || minTicks == 0 { return 0 }
		for case let ins? in instruments { ins.start -= minTicks * 20 }
		if start < end {
			start -= minTicks * 20
			end -= minTicks * 20
		}
		return minTicks
	}
}
