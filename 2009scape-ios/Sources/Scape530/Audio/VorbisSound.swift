import Foundation

/// LSB-first bit reader over a byte array (rt4 `VorbisSound.readBits/readBit`,
/// which keep this state in statics). Reads past the end yield zero bits and
/// set `overrun` instead of trapping.
final class VorbisBits {
	var bytes: [UInt8]
	var position = 0
	var bitPosition = 0
	var overrun = false

	init(_ bytes: [UInt8] = []) { self.bytes = bytes }

	func reset(_ bytes: [UInt8]) {
		self.bytes = bytes
		position = 0
		bitPosition = 0
		overrun = false
	}

	@inline(__always) private func byte() -> Int {
		if position < bytes.count { return Int(bytes[position]) }
		overrun = true
		return 0
	}

	func readBit() -> Int {
		let v = (byte() >> bitPosition) & 1
		bitPosition += 1
		position += bitPosition >> 3
		bitPosition &= 7
		return v
	}

	func readBits(_ count: Int) -> Int {
		var len = count
		var value = 0
		var shift = 0
		while len >= 8 - bitPosition {
			let take = 8 - bitPosition
			let mask = (1 << take) - 1
			value += ((byte() >> bitPosition) & mask) << shift
			bitPosition = 0
			position += 1
			shift += take
			len -= take
		}
		if len > 0 {
			let mask = (1 << len) - 1
			value += ((byte() >> bitPosition) & mask) << shift
			bitPosition += len
		}
		return jw(value)
	}
}

/// rt4 `VorbisSound.float32Unpack`.
func vorbisFloat32Unpack(_ x: Int) -> Float {
	var mantissa = x & 0x1FFFFF
	let sign = x & Int(Int32.min)
	let exponent = (x >> 21) & 0x3FF
	if sign != 0 { mantissa = -mantissa }
	return Float(Double(mantissa) * pow(2.0, Double(exponent - 788)))
}

/// rt4 `VorbisCodebook`: Huffman tree plus optional vector quantisation table.
final class VorbisCodebook {
	private var entryTree: [Int] = []
	let dimensions: Int
	private let entries: Int
	private var lengths: [Int]
	private var multiplicands: [Int] = []
	private var valueVector: [[Float]] = []

	init(_ r: VorbisBits) {
		_ = r.readBits(24)
		dimensions = r.readBits(16)
		entries = r.readBits(24)
		lengths = [Int](repeating: 0, count: max(entries, 0))
		let ordered = r.readBit() != 0
		if ordered {
			var i = 0
			var length = r.readBits(5) + 1
			while i < entries {
				let run = r.readBits(audioBitCount(entries - i))
				var k = 0
				while k < run && i < entries {
					lengths[i] = length
					i += 1
					k += 1
				}
				length += 1
			}
		} else {
			let sparse = r.readBit() != 0
			for i in 0..<entries {
				if sparse && r.readBit() == 0 {
					lengths[i] = 0
				} else {
					lengths[i] = r.readBits(5) + 1
				}
			}
		}
		createEntryTree()
		let lookupType = r.readBits(4)
		if lookupType > 0 {
			let minimum = vorbisFloat32Unpack(r.readBits(32))
			let delta = vorbisFloat32Unpack(r.readBits(32))
			let valueBits = r.readBits(4) + 1
			let sequence = r.readBit() != 0
			let valueCount: Int
			if lookupType == 1 {
				valueCount = VorbisCodebook.lookup1Values(entries, dimensions)
			} else {
				valueCount = entries * dimensions
			}
			multiplicands = [Int](repeating: 0, count: max(valueCount, 0))
			for i in 0..<multiplicands.count { multiplicands[i] = r.readBits(valueBits) }
			valueVector = [[Float]](repeating: [Float](repeating: 0, count: max(dimensions, 0)), count: max(entries, 0))
			if lookupType == 1 {
				for e in 0..<entries {
					var last: Float = 0
					var divisor = 1
					for d in 0..<dimensions {
						let idx = valueCount > 0 ? (e / divisor) % valueCount : 0
						let v = Float(multiplicands[idx]) * delta + minimum + last
						valueVector[e][d] = v
						if sequence { last = v }
						divisor = jw(divisor * valueCount)
						if divisor == 0 { divisor = 1 }
					}
				}
			} else {
				for e in 0..<entries {
					var last: Float = 0
					var idx = e * dimensions
					for d in 0..<dimensions {
						let m = idx < multiplicands.count ? multiplicands[idx] : 0
						let v = Float(m) * delta + minimum + last
						valueVector[e][d] = v
						if sequence { last = v }
						idx += 1
					}
				}
			}
		}
	}

	/// rt4 `lookup1Values`.
	static func lookup1Values(_ entries: Int, _ dimensions: Int) -> Int {
		guard dimensions > 0 else { return 0 }
		var r = jint(pow(Double(entries), 1.0 / Double(dimensions))) + 1
		while intPow(dimensions, r) > entries && r > 0 { r -= 1 }
		return r
	}

	/// rt4 `IntUtils.pow(exponent, base)` with Java int overflow.
	private static func intPow(_ exponent: Int, _ base: Int) -> Int {
		var e = exponent
		var b = base
		var acc = 1
		while e > 1 {
			if (e & 1) != 0 { acc = jw(acc * b) }
			b = jw(b * b)
			e >>= 1
		}
		return e == 1 ? jw(acc * b) : acc
	}

	/// rt4 `createEntryTree`: canonical Huffman code assignment then a flat decode tree.
	private func createEntryTree() {
		var codes = [UInt32](repeating: 0, count: entries)
		var next = [UInt32](repeating: 0, count: 33)
		for i in 0..<entries {
			let len = lengths[i]
			if len == 0 { continue }
			let bit: UInt32 = 1 << UInt32(32 - len)
			let prefix = next[len]
			codes[i] = prefix
			var updated: UInt32
			if (prefix & bit) == 0 {
				updated = prefix | bit
				var l = len - 1
				while l >= 1 {
					let cur = next[l]
					if cur != prefix { break }
					let b: UInt32 = 1 << UInt32(32 - l)
					if (cur & b) != 0 {
						next[l] = next[l - 1]
						break
					}
					next[l] = cur | b
					l -= 1
				}
			} else {
				updated = next[len - 1]
			}
			next[len] = updated
			var l = len + 1
			while l <= 32 {
				if next[l] == prefix { next[l] = updated }
				l += 1
			}
		}
		entryTree = [Int](repeating: 0, count: 8)
		var highest = 0
		for i in 0..<entries {
			let len = lengths[i]
			if len == 0 { continue }
			let code = codes[i]
			var node = 0
			for d in 0..<len {
				let bit: UInt32 = 0x8000_0000 >> UInt32(d)
				if (code & bit) == 0 {
					node += 1
				} else {
					if entryTree[node] == 0 { entryTree[node] = highest }
					node = entryTree[node]
				}
				if node >= entryTree.count {
					entryTree += [Int](repeating: 0, count: entryTree.count)
				}
			}
			entryTree[node] = ~i
			if node >= highest { highest = node + 1 }
		}
	}

	/// rt4 `decodeScalar`: one Huffman symbol.
	func decodeScalar(_ r: VorbisBits) -> Int {
		var node = 0
		var guardCount = 0
		while node >= 0 && node < entryTree.count && entryTree[node] >= 0 {
			node = r.readBit() == 0 ? node + 1 : entryTree[node]
			guardCount += 1
			if guardCount > 64 { return 0 }
		}
		if node < 0 || node >= entryTree.count { return 0 }
		return ~entryTree[node]
	}

	/// rt4 `decodeVq`.
	func decodeVq(_ r: VorbisBits) -> [Float] {
		let i = decodeScalar(r)
		if i >= 0 && i < valueVector.count { return valueVector[i] }
		return [Float](repeating: 0, count: max(dimensions, 0))
	}
}

/// rt4 `VorbisFloor` (floor type 1).
final class VorbisFloor {
	static let ranges = [256, 128, 86, 64]
	static let inverseDb: [Float] = [1.0649863E-7, 1.1341951E-7, 1.2079015E-7, 1.2863978E-7, 1.369995E-7, 1.459025E-7, 1.5538409E-7, 1.6548181E-7, 1.7623574E-7, 1.8768856E-7, 1.998856E-7, 2.128753E-7, 2.2670913E-7, 2.4144197E-7, 2.5713223E-7, 2.7384212E-7, 2.9163792E-7, 3.1059022E-7, 3.307741E-7, 3.5226967E-7, 3.7516213E-7, 3.995423E-7, 4.255068E-7, 4.5315863E-7, 4.8260745E-7, 5.1397E-7, 5.4737063E-7, 5.829419E-7, 6.208247E-7, 6.611694E-7, 7.041359E-7, 7.4989464E-7, 7.98627E-7, 8.505263E-7, 9.057983E-7, 9.646621E-7, 1.0273513E-6, 1.0941144E-6, 1.1652161E-6, 1.2409384E-6, 1.3215816E-6, 1.4074654E-6, 1.4989305E-6, 1.5963394E-6, 1.7000785E-6, 1.8105592E-6, 1.9282195E-6, 2.053526E-6, 2.1869757E-6, 2.3290977E-6, 2.4804558E-6, 2.6416496E-6, 2.813319E-6, 2.9961443E-6, 3.1908505E-6, 3.39821E-6, 3.619045E-6, 3.8542307E-6, 4.1047006E-6, 4.371447E-6, 4.6555283E-6, 4.958071E-6, 5.280274E-6, 5.623416E-6, 5.988857E-6, 6.3780467E-6, 6.7925284E-6, 7.2339453E-6, 7.704048E-6, 8.2047E-6, 8.737888E-6, 9.305725E-6, 9.910464E-6, 1.0554501E-5, 1.1240392E-5, 1.1970856E-5, 1.2748789E-5, 1.3577278E-5, 1.4459606E-5, 1.5399271E-5, 1.6400005E-5, 1.7465769E-5, 1.8600793E-5, 1.9809577E-5, 2.1096914E-5, 2.2467912E-5, 2.3928002E-5, 2.5482977E-5, 2.7139005E-5, 2.890265E-5, 3.078091E-5, 3.2781227E-5, 3.4911533E-5, 3.718028E-5, 3.9596467E-5, 4.2169668E-5, 4.491009E-5, 4.7828602E-5, 5.0936775E-5, 5.424693E-5, 5.7772202E-5, 6.152657E-5, 6.552491E-5, 6.9783084E-5, 7.4317984E-5, 7.914758E-5, 8.429104E-5, 8.976875E-5, 9.560242E-5, 1.0181521E-4, 1.0843174E-4, 1.1547824E-4, 1.2298267E-4, 1.3097477E-4, 1.3948625E-4, 1.4855085E-4, 1.5820454E-4, 1.6848555E-4, 1.7943469E-4, 1.9109536E-4, 2.0351382E-4, 2.167393E-4, 2.3082423E-4, 2.4582449E-4, 2.6179955E-4, 2.7881275E-4, 2.9693157E-4, 3.1622787E-4, 3.3677815E-4, 3.5866388E-4, 3.8197188E-4, 4.0679457E-4, 4.3323037E-4, 4.613841E-4, 4.913675E-4, 5.2329927E-4, 5.573062E-4, 5.935231E-4, 6.320936E-4, 6.731706E-4, 7.16917E-4, 7.635063E-4, 8.1312325E-4, 8.6596457E-4, 9.2223985E-4, 9.821722E-4, 0.0010459992, 0.0011139743, 0.0011863665, 0.0012634633, 0.0013455702, 0.0014330129, 0.0015261382, 0.0016253153, 0.0017309374, 0.0018434235, 0.0019632196, 0.0020908006, 0.0022266726, 0.0023713743, 0.0025254795, 0.0026895993, 0.0028643848, 0.0030505287, 0.003248769, 0.0034598925, 0.0036847359, 0.0039241905, 0.0041792067, 0.004450795, 0.004740033, 0.005048067, 0.0053761187, 0.005725489, 0.0060975635, 0.0064938175, 0.0069158226, 0.0073652514, 0.007843887, 0.008353627, 0.008896492, 0.009474637, 0.010090352, 0.01074608, 0.011444421, 0.012188144, 0.012980198, 0.013823725, 0.014722068, 0.015678791, 0.016697686, 0.017782796, 0.018938422, 0.020169148, 0.021479854, 0.022875736, 0.02436233, 0.025945531, 0.027631618, 0.029427277, 0.031339627, 0.03337625, 0.035545226, 0.037855156, 0.0403152, 0.042935107, 0.045725275, 0.048696756, 0.05186135, 0.05523159, 0.05882085, 0.062643364, 0.06671428, 0.07104975, 0.075666964, 0.08058423, 0.08582105, 0.09139818, 0.097337745, 0.1036633, 0.11039993, 0.11757434, 0.12521498, 0.13335215, 0.14201812, 0.15124726, 0.16107617, 0.1715438, 0.18269168, 0.19456401, 0.20720787, 0.22067343, 0.23501402, 0.25028655, 0.26655158, 0.28387362, 0.3023213, 0.32196787, 0.34289113, 0.36517414, 0.3889052, 0.41417846, 0.44109413, 0.4697589, 0.50028646, 0.53279793, 0.5674221, 0.6042964, 0.64356697, 0.6853896, 0.72993004, 0.777365, 0.8278826, 0.88168305, 0.9389798, 1.0]

	private let classList: [Int]
	private let classDimensions: [Int]
	private let subclasses: [Int]
	private let classMasterBooks: [Int]
	private let subclassBooks: [[Int]]
	private let multiplier: Int
	private let xList: [Int]
	private var currentXList: [Int]
	private var y: [Int]
	private var step2Flag: [Bool]

	init(_ r: VorbisBits) throws {
		let type = r.readBits(16)
		guard type == 1 else { throw AudioDecodeError("vorbis floor type \(type)") }
		let partitions = r.readBits(5)
		var classCount = 0
		var list = [Int](repeating: 0, count: partitions)
		for i in 0..<partitions {
			let c = r.readBits(4)
			list[i] = c
			if c >= classCount { classCount = c + 1 }
		}
		classList = list
		var dims = [Int](repeating: 0, count: classCount)
		var subs = [Int](repeating: 0, count: classCount)
		var masters = [Int](repeating: 0, count: classCount)
		var books = [[Int]](repeating: [], count: classCount)
		for i in 0..<classCount {
			dims[i] = r.readBits(3) + 1
			let sub = r.readBits(2)
			subs[i] = sub
			if sub != 0 { masters[i] = r.readBits(8) }
			let n = 1 << sub
			var b = [Int](repeating: 0, count: n)
			for j in 0..<n { b[j] = r.readBits(8) - 1 }
			books[i] = b
		}
		classDimensions = dims
		subclasses = subs
		classMasterBooks = masters
		subclassBooks = books
		multiplier = r.readBits(2) + 1
		let rangeBits = r.readBits(4)
		var total = 2
		for i in 0..<partitions { total += dims[list[i]] }
		var xs = [Int](repeating: 0, count: total)
		xs[0] = 0
		xs[1] = 1 << rangeBits
		var n = 2
		for i in 0..<partitions {
			let c = list[i]
			for _ in 0..<dims[c] {
				xs[n] = r.readBits(rangeBits)
				n += 1
			}
		}
		xList = xs
		currentXList = [Int](repeating: 0, count: total)
		y = [Int](repeating: 0, count: total)
		step2Flag = [Bool](repeating: false, count: total)
	}

	private static func lowNeighbour(_ a: [Int], _ i: Int) -> Int {
		let v = a[i]
		var best = -1
		var bestValue = Int(Int32.min)
		for j in 0..<i {
			let x = a[j]
			if x < v && x > bestValue {
				best = j
				bestValue = x
			}
		}
		return best
	}

	private static func highNeighbour(_ a: [Int], _ i: Int) -> Int {
		let v = a[i]
		var best = -1
		var bestValue = Int(Int32.max)
		for j in 0..<i {
			let x = a[j]
			if x > v && x < bestValue {
				best = j
				bestValue = x
			}
		}
		return best
	}

	private func renderLine(_ x0: Int, _ y0: Int, _ x1In: Int, _ y1: Int, _ out: inout [Float], _ limit: Int) {
		let dy = y1 - y0
		let adx = x1In - x0
		guard adx > 0 else { return }
		let ady = dy < 0 ? -dy : dy
		let base = dy / adx
		var y = y0
		var err = 0
		let sy = dy < 0 ? base - 1 : base + 1
		let absErr = ady - (base < 0 ? -base : base) * adx
		let table = VorbisFloor.inverseDb
		if x0 < out.count { out[x0] *= table[max(0, min(255, y0))] }
		var x1 = x1In
		if x1 > limit { x1 = limit }
		var x = x0 + 1
		while x < x1 {
			err += absErr
			if err >= adx {
				err -= adx
				y += sy
			} else {
				y += base
			}
			if x < out.count { out[x] *= table[max(0, min(255, y))] }
			x += 1
		}
	}

	private func sort(_ lo: Int, _ hi: Int) {
		if lo >= hi { return }
		var pivotPos = lo
		let px = currentXList[lo]
		let py = y[lo]
		let pf = step2Flag[lo]
		var i = lo + 1
		while i <= hi {
			let v = currentXList[i]
			if v < px {
				currentXList[pivotPos] = v
				y[pivotPos] = y[i]
				step2Flag[pivotPos] = step2Flag[i]
				pivotPos += 1
				currentXList[i] = currentXList[pivotPos]
				y[i] = y[pivotPos]
				step2Flag[i] = step2Flag[pivotPos]
			}
			i += 1
		}
		currentXList[pivotPos] = px
		y[pivotPos] = py
		step2Flag[pivotPos] = pf
		sort(lo, pivotPos - 1)
		sort(pivotPos + 1, hi)
	}

	private func renderPoint(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ x: Int) -> Int {
		let dy = y1 - y0
		let adx = x1 - x0
		guard adx != 0 else { return y0 }
		let ady = dy < 0 ? -dy : dy
		let off = (ady * (x - x0)) / adx
		return dy < 0 ? y0 - off : y0 + off
	}

	/// rt4 `synthesize`: applies the decoded floor curve to the first `n` spectrum values.
	func synthesize(_ out: inout [Float], _ n: Int) {
		let count = xList.count
		let range = VorbisFloor.ranges[multiplier - 1]
		step2Flag[0] = true
		step2Flag[1] = true
		for i in 2..<max(count, 2) {
			let lo = VorbisFloor.lowNeighbour(currentXList, i)
			let hi = VorbisFloor.highNeighbour(currentXList, i)
			guard lo >= 0, hi >= 0 else { continue }
			let predicted = renderPoint(currentXList[lo], y[lo], currentXList[hi], y[hi], currentXList[i])
			let value = y[i]
			let highRoom = range - predicted
			let lowRoom = (highRoom < predicted ? highRoom : predicted) << 1
			if value == 0 {
				step2Flag[i] = false
				y[i] = predicted
			} else {
				step2Flag[lo] = true
				step2Flag[hi] = true
				step2Flag[i] = true
				if value >= lowRoom {
					y[i] = highRoom > predicted ? value + predicted - predicted : predicted - value + highRoom - 1
				} else {
					y[i] = (value & 1) == 0 ? predicted + value / 2 : predicted - (value + 1) / 2
				}
			}
		}
		sort(0, count - 1)
		var lastX = 0
		var lastY = y[0] * multiplier
		var i = 1
		while i < count {
			if step2Flag[i] {
				let x = currentXList[i]
				let yy = y[i] * multiplier
				renderLine(lastX, lastY, x, yy, &out, n)
				if x >= n { return }
				lastX = x
				lastY = yy
			}
			i += 1
		}
		let tail = VorbisFloor.inverseDb[max(0, min(255, lastY))]
		var x = lastX
		while x < n {
			if x < out.count { out[x] *= tail }
			x += 1
		}
	}

	/// rt4 `decodePacket`: reads the floor's Y values; false if the floor is unused in this packet.
	func decodePacket(_ r: VorbisBits, _ codebooks: [VorbisCodebook]) -> Bool {
		guard r.readBit() != 0 else { return false }
		let count = xList.count
		for i in 0..<count { currentXList[i] = xList[i] }
		let range = VorbisFloor.ranges[multiplier - 1]
		let bits = audioBitCount(range - 1)
		y[0] = r.readBits(bits)
		y[1] = r.readBits(bits)
		var at = 2
		for p in 0..<classList.count {
			let c = classList[p]
			let dim = classDimensions[c]
			let sub = subclasses[c]
			let mask = (1 << sub) - 1
			var cval = 0
			if sub > 0 {
				let book = classMasterBooks[c]
				cval = book < codebooks.count ? codebooks[book].decodeScalar(r) : 0
			}
			for _ in 0..<dim {
				let book = subclassBooks[c][cval & mask]
				cval = Int(UInt32(truncatingIfNeeded: cval) >> UInt32(sub))
				if at < y.count {
					y[at] = (book >= 0 && book < codebooks.count) ? codebooks[book].decodeScalar(r) : 0
				}
				at += 1
			}
		}
		return true
	}
}

/// rt4 `VorbisResidue` (types 0 and 1/2 share the partition walk).
final class VorbisResidue {
	private let type: Int
	private let begin: Int
	private let end: Int
	private let partitionSize: Int
	private let classifications: Int
	private let classBook: Int
	private var books: [Int]

	init(_ r: VorbisBits) {
		type = r.readBits(16)
		begin = r.readBits(24)
		end = r.readBits(24)
		partitionSize = r.readBits(24) + 1
		classifications = r.readBits(6) + 1
		classBook = r.readBits(8)
		var cascade = [Int](repeating: 0, count: classifications)
		for i in 0..<classifications {
			var high = 0
			let low = r.readBits(3)
			if r.readBit() != 0 { high = r.readBits(5) }
			cascade[i] = (high << 3) | low
		}
		books = [Int](repeating: -1, count: classifications * 8)
		for i in 0..<(classifications * 8) {
			books[i] = (cascade[i >> 3] & (1 << (i & 7))) == 0 ? -1 : r.readBits(8)
		}
	}

	/// rt4 `synthesize(vector, n, noResidue)`.
	func synthesize(_ r: VorbisBits, _ codebooks: [VorbisCodebook], _ out: inout [Float], _ n: Int, _ noResidue: Bool) {
		for i in 0..<min(n, out.count) { out[i] = 0 }
		if noResidue { return }
		guard classBook < codebooks.count else { return }
		let dim = codebooks[classBook].dimensions
		let size = end - begin
		let partitionCount = size / partitionSize
		guard partitionCount > 0, dim > 0 else { return }
		var classes = [Int](repeating: 0, count: partitionCount)
		for pass in 0..<8 {
			var part = 0
			while part < partitionCount {
				if pass == 0 {
					var v = codebooks[classBook].decodeScalar(r)
					var d = dim - 1
					while d >= 0 {
						if part + d < partitionCount { classes[part + d] = v % classifications }
						v /= classifications
						d -= 1
					}
				}
				for _ in 0..<dim {
					let cls = classes[part]
					let bookIndex = books[cls * 8 + pass]
					if bookIndex >= 0 && bookIndex < codebooks.count {
						let offset = begin + part * partitionSize
						let book = codebooks[bookIndex]
						if book.dimensions > 0 {
							if type == 0 {
								let steps = partitionSize / book.dimensions
								for s in 0..<steps {
									let vec = book.decodeVq(r)
									for d in 0..<book.dimensions {
										let idx = offset + s + d * steps
										if idx < out.count && d < vec.count { out[idx] += vec[d] }
									}
								}
							} else {
								var s = 0
								while s < partitionSize {
									let vec = book.decodeVq(r)
									for d in 0..<book.dimensions {
										let idx = offset + s
										if idx < out.count && d < vec.count { out[idx] += vec[d] }
										s += 1
									}
								}
							}
						}
					}
					part += 1
					if part >= partitionCount { break }
				}
			}
		}
	}
}

/// rt4 `VorbisMapping`.
final class VorbisMapping {
	let submaps: Int
	var mux = 0
	var submapFloor: [Int]
	var submapResidue: [Int]

	init(_ r: VorbisBits) {
		_ = r.readBits(16)
		submaps = r.readBit() == 0 ? 1 : r.readBits(4) + 1
		if r.readBit() != 0 { _ = r.readBits(8) }
		_ = r.readBits(2)
		if submaps > 1 { mux = r.readBits(4) }
		submapFloor = [Int](repeating: 0, count: submaps)
		submapResidue = [Int](repeating: 0, count: submaps)
		for i in 0..<submaps {
			_ = r.readBits(8)
			submapFloor[i] = r.readBits(8)
			submapResidue[i] = r.readBits(8)
		}
	}
}

/// The shared codebook/floor/residue/mode setup that rt4 reads once from
/// archive 14 group 0 file 0 (`VorbisSound.method2349`), plus the IMDCT twiddle tables.
final class VorbisSetup {
	let blockSize0: Int
	let blockSize1: Int
	var trigA = [[Float]](repeating: [], count: 2)
	var trigB = [[Float]](repeating: [], count: 2)
	var trigC = [[Float]](repeating: [], count: 2)
	var bitReverse = [[Int]](repeating: [], count: 2)
	var codebooks: [VorbisCodebook] = []
	var floors: [VorbisFloor] = []
	var residues: [VorbisResidue] = []
	var mappings: [VorbisMapping] = []
	var modeBlockFlags: [Bool] = []
	var modeMappings: [Int] = []

	init(_ bytes: [UInt8]) throws {
		let r = VorbisBits(bytes)
		blockSize0 = 1 << r.readBits(4)
		blockSize1 = 1 << r.readBits(4)
		guard blockSize0 >= 8, blockSize1 >= blockSize0, blockSize1 <= 32768 else {
			throw AudioDecodeError("vorbis block sizes \(blockSize0)/\(blockSize1)")
		}
		for t in 0..<2 {
			let size = t == 0 ? blockSize0 : blockSize1
			let half = size >> 1
			let quarter = size >> 2
			let eighth = size >> 3
			var a = [Float](repeating: 0, count: half)
			for i in 0..<quarter {
				a[i * 2] = Float(cos(Double(i * 4) * Double.pi / Double(size)))
				a[i * 2 + 1] = -Float(sin(Double(i * 4) * Double.pi / Double(size)))
			}
			var b = [Float](repeating: 0, count: half)
			for i in 0..<quarter {
				b[i * 2] = Float(cos(Double(i * 2 + 1) * Double.pi / Double(size * 2)))
				b[i * 2 + 1] = Float(sin(Double(i * 2 + 1) * Double.pi / Double(size * 2)))
			}
			var c = [Float](repeating: 0, count: quarter)
			for i in 0..<eighth {
				c[i * 2] = Float(cos(Double(i * 4 + 2) * Double.pi / Double(size)))
				c[i * 2 + 1] = -Float(sin(Double(i * 4 + 2) * Double.pi / Double(size)))
			}
			var rev = [Int](repeating: 0, count: eighth)
			let bits = audioBitCount(eighth - 1)
			for i in 0..<eighth {
				var out = 0
				var v = i
				var n = bits
				while n > 0 {
					out = (out << 1) | (v & 1)
					v >>= 1
					n -= 1
				}
				rev[i] = out
			}
			trigA[t] = a
			trigB[t] = b
			trigC[t] = c
			bitReverse[t] = rev
		}
		let bookCount = r.readBits(8) + 1
		for _ in 0..<bookCount { codebooks.append(VorbisCodebook(r)) }
		let timeCount = r.readBits(6) + 1
		for _ in 0..<timeCount { _ = r.readBits(16) }
		let floorCount = r.readBits(6) + 1
		for _ in 0..<floorCount { floors.append(try VorbisFloor(r)) }
		let residueCount = r.readBits(6) + 1
		for _ in 0..<residueCount { residues.append(VorbisResidue(r)) }
		let mappingCount = r.readBits(6) + 1
		for _ in 0..<mappingCount { mappings.append(VorbisMapping(r)) }
		let modeCount = r.readBits(6) + 1
		for _ in 0..<modeCount {
			modeBlockFlags.append(r.readBit() != 0)
			_ = r.readBits(16)
			_ = r.readBits(16)
			modeMappings.append(r.readBits(8))
		}
		if r.overrun { throw AudioDecodeError("vorbis setup header truncated") }
	}
}

/// A Vorbis-coded sample (rt4 `VorbisSound`): archive 14 holds these as the
/// raw audio packets of an Ogg stream without the Ogg container; the shared
/// header lives in group 0. `decode()` turns it into an 8 bit `PcmSound`.
public final class VorbisSound {
	private var rate = 0
	private var samplesLen = 0
	private var start = 0
	private var end = 0
	private var pingPong = false
	private var packets: [[UInt8]] = []

	// Overlap-add state across packets.
	private var prevN = 0
	private var prevQuarter = 0
	private var prevNoResidue = false
	private var prevVector: [Float] = []

	init(_ bytes: [UInt8]) throws {
		var p = Packet(bytes)
		rate = Int(try p.g4())
		samplesLen = Int(try p.g4())
		start = Int(try p.g4())
		end = Int(try p.g4())
		if end < 0 {
			end = ~end
			pingPong = true
		}
		let count = Int(try p.g4())
		guard count >= 0, count < 1_000_000 else { throw AudioDecodeError("vorbis packet count \(count)") }
		for _ in 0..<count {
			var len = 0
			var n = 0
			repeat {
				n = try p.g1()
				len += n
			} while n >= 255
			packets.append(try p.gdata(len))
		}
	}

	/// Shared setup cache, keyed by archive.
	private final class SetupCache: @unchecked Sendable {
		let lock = NSLock()
		var setups: [Int: VorbisSetup] = [:]
	}
	private static let cache = SetupCache()

	static func setup(for archive: AudioArchive) -> VorbisSetup? {
		cache.lock.lock()
		defer { cache.lock.unlock() }
		if let s = cache.setups[archive.archive] { return s }
		guard let bytes = archive.fetchFile(0, 0), let s = try? VorbisSetup(bytes) else { return nil }
		cache.setups[archive.archive] = s
		return s
	}

	/// rt4 `VorbisSound.create(Js5, group, file)`.
	public static func create(archive: AudioArchive, group: Int, file: Int) -> VorbisSound? {
		guard setup(for: archive) != nil, let bytes = archive.fetchFile(group, file) else { return nil }
		return try? VorbisSound(bytes)
	}

	/// rt4 `toPcmSound(null)`: decodes every packet and converts to signed 8 bit.
	public func decode(archive: AudioArchive) -> PcmSound? {
		guard let setup = VorbisSound.setup(for: archive) else { return nil }
		prevN = 0
		prevVector = [Float](repeating: 0, count: setup.blockSize1)
		var vector = [Float](repeating: 0, count: setup.blockSize1)
		var samples = [Int8](repeating: 0, count: max(samplesLen, 0))
		var index = 0
		let bits = VorbisBits()
		for packet in packets {
			bits.reset(packet)
			guard let out = decodePacket(setup, bits, &vector) else { continue }
			var count = out.count
			if count > samplesLen - index { count = samplesLen - index }
			var at = index
			for i in 0..<max(count, 0) {
				var v = jint(Double(out[i] * 128.0 + 128.0))
				if (v & ~0xFF) != 0 { v = ~v >> 31 }
				samples[at] = Int8(truncatingIfNeeded: v - 128)
				at += 1
			}
			index = at
		}
		prevVector = []
		return PcmSound(rate: rate, samples: samples, start: start, end: end, pingPong: pingPong)
	}

	/// rt4 `decodePacket`: floor + residue decode, inverse MDCT, windowing and overlap-add.
	private func decodePacket(_ s: VorbisSetup, _ r: VorbisBits, _ vectorIO: inout [Float]) -> [Float]? {
		_ = r.readBit()
		let modeNumber = r.readBits(audioBitCount(s.modeMappings.count - 1))
		guard modeNumber < s.modeBlockFlags.count else { return nil }
		let longBlock = s.modeBlockFlags[modeNumber]
		let n = longBlock ? s.blockSize1 : s.blockSize0
		var previousWindowFlag = false
		var nextWindowFlag = false
		if longBlock {
			previousWindowFlag = r.readBit() != 0
			nextWindowFlag = r.readBit() != 0
		}
		let windowCenter = n >> 1
		let leftWindowStart: Int, leftWindowEnd: Int, leftN: Int
		if longBlock && !previousWindowFlag {
			leftWindowStart = (n >> 2) - (s.blockSize0 >> 2)
			leftWindowEnd = (n >> 2) + (s.blockSize0 >> 2)
			leftN = s.blockSize0 >> 1
		} else {
			leftWindowStart = 0
			leftWindowEnd = windowCenter
			leftN = n >> 1
		}
		let rightWindowStart: Int, rightWindowEnd: Int, rightN: Int
		if longBlock && !nextWindowFlag {
			rightWindowStart = n - (n >> 2) - (s.blockSize0 >> 2)
			rightWindowEnd = n + (s.blockSize0 >> 2) - (n >> 2)
			rightN = s.blockSize0 >> 1
		} else {
			rightWindowStart = windowCenter
			rightWindowEnd = n
			rightN = n >> 1
		}
		let mapping = s.mappings[min(s.modeMappings[modeNumber], s.mappings.count - 1)]
		let submapIndex = min(mapping.mux, mapping.submaps - 1)
		let floorIndex = mapping.submapFloor[submapIndex]
		guard floorIndex < s.floors.count else { return nil }
		let floor = s.floors[floorIndex]
		let noResidue = !floor.decodePacket(r, s.codebooks)
		for sub in 0..<mapping.submaps {
			let ri = mapping.submapResidue[sub]
			guard ri < s.residues.count else { return nil }
			s.residues[ri].synthesize(r, s.codebooks, &vectorIO, n >> 1, noResidue)
		}
		if !noResidue {
			floor.synthesize(&vectorIO, n >> 1)
		}
		if noResidue {
			var k = n >> 1
			while k < n {
				vectorIO[k] = 0
				k += 1
			}
		} else {
			imdct(s, &vectorIO, n, longBlock)
			applyWindow(&vectorIO, leftWindowStart, leftWindowEnd, leftN, rightWindowStart, rightWindowEnd, rightN)
		}
		var result: [Float]? = nil
		if prevN > 0 {
			let size = (prevN + n) >> 2
			var out = [Float](repeating: 0, count: size)
			if !prevNoResidue {
				for i in 0..<prevQuarter {
					let from = (prevN >> 1) + i
					if i < size && from < prevVector.count { out[i] += prevVector[from] }
				}
			}
			if !noResidue {
				var i = leftWindowStart
				while i < (n >> 1) {
					let at = size + i - (n >> 1)
					if at >= 0 && at < size { out[at] += vectorIO[i] }
					i += 1
				}
			}
			result = out
		}
		swap(&prevVector, &vectorIO)
		prevN = n
		prevQuarter = rightWindowEnd - (n >> 1)
		prevNoResidue = noResidue
		return result
	}

	private func applyWindow(_ v: inout [Float], _ ls: Int, _ le: Int, _ ln: Int, _ rs: Int, _ re: Int, _ rn: Int) {
		var l = ls
		while l < le {
			let b = Float(sin((Double(l - ls) + 0.5) / Double(ln) * 0.5 * Double.pi))
			v[l] *= Float(sin(Double(b) * 1.5707963267948966 * Double(b)))
			l += 1
		}
		l = rs
		while l < re {
			let b = Float(sin((Double(l - rs) + 0.5) / Double(rn) * 0.5 * Double.pi + 1.5707963267948966))
			v[l] *= Float(sin(Double(b) * 1.5707963267948966 * Double(b)))
			l += 1
		}
	}

	/// The inverse MDCT of rt4 `decodePacket`, in place over `v[0..<n]`.
	private func imdct(_ s: VorbisSetup, _ v: inout [Float], _ n: Int, _ longBlock: Bool) {
		let n2 = n >> 1
		let n4 = n >> 2
		let n8 = n >> 3
		for k in 0..<n2 { v[k] *= 0.5 }
		for k in n2..<n { v[k] = -v[n - k - 1] }
		let t = longBlock ? 1 : 0
		let trigA = s.trigA[t]
		let trigB = s.trigB[t]
		let trigC = s.trigC[t]
		let rev = s.bitReverse[t]
		for k in 0..<n4 {
			let a = v[k * 4] - v[n - k * 4 - 1]
			let b = v[k * 4 + 2] - v[n - k * 4 - 3]
			let c = trigA[k * 2]
			let d = trigA[k * 2 + 1]
			v[n - k * 4 - 1] = a * c - b * d
			v[n - k * 4 - 3] = a * d + b * c
		}
		for k in 0..<n8 {
			let a = v[n2 + k * 4 + 3]
			let b = v[n2 + k * 4 + 1]
			let c = v[k * 4 + 3]
			let d = v[k * 4 + 1]
			v[n2 + k * 4 + 3] = a + c
			v[n2 + k * 4 + 1] = b + d
			let e = trigA[n2 - k * 4 - 4]
			let f = trigA[n2 - k * 4 - 3]
			v[k * 4 + 3] = (a - c) * e - (b - d) * f
			v[k * 4 + 1] = (b - d) * e + (a - c) * f
		}
		let logN = audioBitCount(n - 1)
		var l = 0
		while l < logN - 3 {
			let k0 = n >> (l + 2)
			let k1 = 8 << l
			for sIdx in 0..<(2 << l) {
				let base1 = n - k0 * 2 * sIdx
				let base2 = n - k0 * (sIdx * 2 + 1)
				for m in 0..<(n >> (l + 4)) {
					let o = m * 4
					let a = v[base1 - o - 1]
					let b = v[base1 - o - 3]
					let c = v[base2 - o - 1]
					let d = v[base2 - o - 3]
					v[base1 - o - 1] = a + c
					v[base1 - o - 3] = b + d
					let cs = trigA[m * k1]
					let sn = trigA[m * k1 + 1]
					v[base2 - o - 1] = (a - c) * cs - (b - d) * sn
					v[base2 - o - 3] = (b - d) * cs + (a - c) * sn
				}
			}
			l += 1
		}
		l = 1
		while l < n8 - 1 {
			let k0 = rev[l]
			if l < k0 {
				let i1 = l * 8
				let i2 = k0 * 8
				var e = v[i1 + 1]; v[i1 + 1] = v[i2 + 1]; v[i2 + 1] = e
				e = v[i1 + 3]; v[i1 + 3] = v[i2 + 3]; v[i2 + 3] = e
				e = v[i1 + 5]; v[i1 + 5] = v[i2 + 5]; v[i2 + 5] = e
				e = v[i1 + 7]; v[i1 + 7] = v[i2 + 7]; v[i2 + 7] = e
			}
			l += 1
		}
		for i in 0..<n2 { v[i] = v[i * 2 + 1] }
		for i in 0..<n8 {
			v[n - i * 2 - 1] = v[i * 4]
			v[n - i * 2 - 2] = v[i * 4 + 1]
			v[n - n4 - i * 2 - 1] = v[i * 4 + 2]
			v[n - n4 - i * 2 - 2] = v[i * 4 + 3]
		}
		for i in 0..<n8 {
			let b = trigC[i * 2]
			let c = trigC[i * 2 + 1]
			let d = v[n2 + i * 2]
			let e = v[n2 + i * 2 + 1]
			let f = v[n - i * 2 - 2]
			let g = v[n - i * 2 - 1]
			let h = c * (d - f) + b * (e + g)
			v[n2 + i * 2] = (d + f + h) * 0.5
			v[n - i * 2 - 2] = (d + f - h) * 0.5
			let j = c * (e + g) - b * (d - f)
			v[n2 + i * 2 + 1] = (e + j - g) * 0.5
			v[n - i * 2 - 1] = (g + j - e) * 0.5
		}
		for i in 0..<n4 {
			v[i] = v[i * 2 + n2] * trigB[i * 2] + v[i * 2 + n2 + 1] * trigB[i * 2 + 1]
			v[n2 - i - 1] = v[i * 2 + n2] * trigB[i * 2 + 1] - v[i * 2 + n2 + 1] * trigB[i * 2]
		}
		for i in 0..<n4 { v[n + i - n4] = -v[i] }
		for i in 0..<n4 { v[i] = v[n4 + i] }
		for i in 0..<n4 { v[n4 + i] = -v[n4 - i - 1] }
		for i in 0..<n4 { v[n2 + i] = v[n - i - 1] }
	}
}
