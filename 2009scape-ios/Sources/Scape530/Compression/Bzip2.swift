/// Pure-Swift bzip2 block decoder for JS5 containers.
///
/// Jagex strips the "BZh1" stream header, so (like rt4's
/// `Bzip2Decompressor.bunzip2`, which starts reading at container offset 9)
/// the input begins directly at the first block magic. Randomised blocks are
/// not produced by Jagex's packer and are rejected.
public enum Bzip2 {
	public struct Failure: Error, CustomStringConvertible {
		public let description: String
		init(_ d: String) { description = d }
	}

	struct BitReader {
		let d: ArraySlice<UInt8>
		var pos: Int
		var buf: UInt64 = 0
		var count: Int = 0

		init(_ d: ArraySlice<UInt8>) {
			self.d = d
			pos = d.startIndex
		}

		@inline(__always)
		mutating func bits(_ n: Int) throws -> Int {
			while count < n {
				guard pos < d.endIndex else { throw Failure("unexpected end of bzip2 stream") }
				buf = buf << 8 | UInt64(d[pos])
				pos += 1
				count += 8
			}
			count -= n
			return Int((buf >> UInt64(count)) & ((1 << UInt64(n)) - 1))
		}

		@inline(__always)
		mutating func bit() throws -> Int { try bits(1) }
	}

	struct Table {
		var minLen = 32
		var maxLen = 0
		var firstCode = [Int](repeating: 0, count: 21)
		var firstIndex = [Int](repeating: 0, count: 21)
		var count = [Int](repeating: 0, count: 21)
		var perm: [Int] = []

		init(lengths: [Int]) {
			for l in lengths {
				minLen = min(minLen, l)
				maxLen = max(maxLen, l)
				count[l] += 1
			}
			var code = 0
			for l in minLen...maxLen {
				firstCode[l] = code
				firstIndex[l] = perm.count
				for (s, sl) in lengths.enumerated() where sl == l { perm.append(s) }
				code = (code + count[l]) << 1
			}
		}

		@inline(__always)
		func decode(_ br: inout BitReader) throws -> Int {
			var l = minLen
			var v = try br.bits(l)
			while true {
				if v - firstCode[l] < count[l] {
					return perm[firstIndex[l] + v - firstCode[l]]
				}
				l += 1
				guard l <= maxLen else { throw Failure("bad bzip2 huffman code") }
				v = v << 1 | (try br.bit())
			}
		}
	}

	public static func decompress(_ data: ArraySlice<UInt8>, expectedSize: Int) throws -> [UInt8] {
		var out: [UInt8] = []
		out.reserveCapacity(expectedSize)
		var br = BitReader(data)
		var tt = [UInt32](repeating: 0, count: 100_000)

		while out.count < expectedSize {
			let magicHi = try br.bits(24)
			let magicLo = try br.bits(24)
			if magicHi == 0x177245 && magicLo == 0x385090 { break }
			guard magicHi == 0x314159 && magicLo == 0x265359 else { throw Failure("bad block magic") }
			_ = try br.bits(32) // block CRC
			guard try br.bit() == 0 else { throw Failure("randomised blocks unsupported") }
			let origPtr = try br.bits(24)

			// Symbol map
			let used16 = try br.bits(16)
			var seqToUnseq: [UInt8] = []
			for i in 0..<16 where used16 & (0x8000 >> i) != 0 {
				let bitsUsed = try br.bits(16)
				for j in 0..<16 where bitsUsed & (0x8000 >> j) != 0 {
					seqToUnseq.append(UInt8(i * 16 + j))
				}
			}
			guard !seqToUnseq.isEmpty else { throw Failure("empty symbol map") }
			let alphaSize = seqToUnseq.count + 2

			// Selectors
			let nGroups = try br.bits(3)
			guard (2...6).contains(nGroups) else { throw Failure("bad group count") }
			let nSelectors = try br.bits(15)
			guard nSelectors >= 1 else { throw Failure("no selectors") }
			var mtfGroups = Array(0..<nGroups)
			var selectors = [Int](repeating: 0, count: nSelectors)
			for i in 0..<nSelectors {
				var j = 0
				while try br.bit() == 1 {
					j += 1
					guard j < nGroups else { throw Failure("bad selector") }
				}
				let v = mtfGroups.remove(at: j)
				mtfGroups.insert(v, at: 0)
				selectors[i] = v
			}

			// Code lengths
			var tables: [Table] = []
			for _ in 0..<nGroups {
				var curr = try br.bits(5)
				var lens = [Int](repeating: 0, count: alphaSize)
				for s in 0..<alphaSize {
					while true {
						guard (1...20).contains(curr) else { throw Failure("bad code length") }
						if try br.bit() == 0 { break }
						curr += try br.bit() == 0 ? 1 : -1
					}
					lens[s] = curr
				}
				tables.append(Table(lengths: lens))
			}

			// MTF + RUNA/RUNB decode into `ll` (stored in tt's low byte)
			let eob = seqToUnseq.count + 1
			var mtf: [UInt8] = (0..<seqToUnseq.count).map { UInt8($0) }
			var unzftab = [Int](repeating: 0, count: 256)
			var nblock = 0
			var groupPos = 0
			var groupNo = -1
			var runLen = 0
			var runWeight = 1

			func flushRun() throws {
				guard runLen > 0 else { return }
				let b = seqToUnseq[Int(mtf[0])]
				guard nblock + runLen <= tt.count else { throw Failure("block overflow") }
				unzftab[Int(b)] += runLen
				for _ in 0..<runLen {
					tt[nblock] = UInt32(b)
					nblock += 1
				}
				runLen = 0
				runWeight = 1
			}

			while true {
				if groupPos == 0 {
					groupNo += 1
					guard groupNo < nSelectors else { throw Failure("selector overrun") }
					groupPos = 50
				}
				groupPos -= 1
				let sym = try tables[selectors[groupNo]].decode(&br)
				if sym <= 1 {
					runLen += (sym + 1) * runWeight
					runWeight <<= 1
					guard runLen <= tt.count else { throw Failure("run overflow") }
					continue
				}
				try flushRun()
				if sym == eob { break }
				let idx = sym - 1
				guard idx < mtf.count else { throw Failure("bad mtf index") }
				let v = mtf.remove(at: idx)
				mtf.insert(v, at: 0)
				let b = seqToUnseq[Int(v)]
				guard nblock < tt.count else { throw Failure("block overflow") }
				unzftab[Int(b)] += 1
				tt[nblock] = UInt32(b)
				nblock += 1
			}
			guard origPtr < nblock else { throw Failure("bad origPtr") }

			// Inverse BWT
			var cftab = [Int](repeating: 0, count: 257)
			for i in 0..<256 { cftab[i + 1] = cftab[i] + unzftab[i] }
			for i in 0..<nblock {
				let b = Int(tt[i] & 0xFF)
				tt[cftab[b]] |= UInt32(i) << 8
				cftab[b] += 1
			}

			// Walk the T-vector, undoing the initial RLE (4 equal bytes + count)
			var tPos = Int(tt[origPtr] >> 8)
			var last = -1
			var same = 0
			var i = 0
			while i < nblock {
				let entry = tt[tPos]
				let ch = Int(entry & 0xFF)
				tPos = Int(entry >> 8)
				i += 1
				if same == 4 {
					if ch > 0 { out.append(contentsOf: repeatElement(UInt8(last), count: ch)) }
					same = 0
					last = -1
					continue
				}
				out.append(UInt8(ch))
				if ch == last {
					same += 1
				} else {
					last = ch
					same = 1
				}
			}
		}
		guard out.count >= expectedSize else { throw Failure("short output: \(out.count) < \(expectedSize)") }
		if out.count > expectedSize { out.removeLast(out.count - expectedSize) }
		return out
	}
}
