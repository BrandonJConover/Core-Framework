/// Pure-Swift raw DEFLATE (RFC 1951) decoder. JS5 gzip containers are
/// decoded the way rt4's `GzipDecompressor` does it: check the 1F 8B magic,
/// skip the fixed 10-byte header, inflate until the final block.
public enum Inflate {
	public struct Failure: Error, CustomStringConvertible {
		public let description: String
		init(_ d: String) { description = d }
	}

	public static func gunzipJs5(_ data: ArraySlice<UInt8>, expectedSize: Int) throws -> [UInt8] {
		let s = data.startIndex
		guard data.count >= 18, data[s] == 0x1F, data[s + 1] == 0x8B else {
			throw Failure("invalid gzip header")
		}
		return try inflate(data[(s + 10)...], expectedSize: expectedSize)
	}

	struct BitReader {
		let d: ArraySlice<UInt8>
		var pos: Int
		var bitBuf: UInt32 = 0
		var bitCount: UInt32 = 0

		init(_ d: ArraySlice<UInt8>) {
			self.d = d
			pos = d.startIndex
		}

		@inline(__always)
		mutating func need(_ n: UInt32) throws {
			while bitCount < n {
				guard pos < d.endIndex else { throw Failure("unexpected end of deflate stream") }
				bitBuf |= UInt32(d[pos]) << bitCount
				pos += 1
				bitCount += 8
			}
		}

		@inline(__always)
		mutating func bits(_ n: UInt32) throws -> Int {
			if n == 0 { return 0 }
			try need(n)
			let v = bitBuf & ((1 << n) - 1)
			bitBuf >>= n
			bitCount -= n
			return Int(v)
		}

		mutating func alignToByte() {
			bitBuf = 0
			bitCount = 0
		}
	}

	/// Canonical Huffman table decoded bit-by-bit (counts/symbols, zlib "puff" style).
	struct Huffman {
		var counts = [Int](repeating: 0, count: 16)
		var symbols: [Int]

		init(lengths: [Int]) throws {
			symbols = [Int](repeating: 0, count: lengths.count)
			for l in lengths { counts[l] += 1 }
			// counts[0] tallies unused (zero-length) codes and takes no slots.
			var offs = [Int](repeating: 0, count: 16)
			for i in 1..<15 { offs[i + 1] = offs[i] + counts[i] }
			for (sym, l) in lengths.enumerated() where l != 0 {
				symbols[offs[l]] = sym
				offs[l] += 1
			}
		}

		func decode(_ br: inout BitReader) throws -> Int {
			var code = 0
			var first = 0
			var index = 0
			for len in 1..<16 {
				code |= try br.bits(1)
				let count = counts[len]
				if code - count < first {
					return symbols[index + (code - first)]
				}
				index += count
				first += count
				first <<= 1
				code <<= 1
			}
			throw Failure("bad huffman code")
		}
	}

	static let lenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
	static let lenExtra: [UInt32] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
	static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
	static let distExtra: [UInt32] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
	static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

	static let fixedTables: (Huffman, Huffman) = {
		var l = [Int](repeating: 8, count: 288)
		for i in 144..<256 { l[i] = 9 }
		for i in 256..<280 { l[i] = 7 }
		let lit = try! Huffman(lengths: l)
		let dist = try! Huffman(lengths: [Int](repeating: 5, count: 30))
		return (lit, dist)
	}()

	public static func inflate(_ data: ArraySlice<UInt8>, expectedSize: Int = 0) throws -> [UInt8] {
		var out: [UInt8] = []
		out.reserveCapacity(expectedSize)
		var br = BitReader(data)
		var final = false
		while !final {
			final = try br.bits(1) == 1
			switch try br.bits(2) {
			case 0:
				br.alignToByte()
				guard br.pos + 4 <= data.endIndex else { throw Failure("truncated stored block") }
				let len = Int(data[br.pos]) | Int(data[br.pos + 1]) << 8
				let nlen = Int(data[br.pos + 2]) | Int(data[br.pos + 3]) << 8
				guard len == (~nlen & 0xFFFF) else { throw Failure("stored length mismatch") }
				br.pos += 4
				guard br.pos + len <= data.endIndex else { throw Failure("truncated stored data") }
				out.append(contentsOf: data[br.pos..<br.pos + len])
				br.pos += len
			case 1:
				try codes(&br, &out, fixedTables.0, fixedTables.1)
			case 2:
				let hlit = try br.bits(5) + 257
				let hdist = try br.bits(5) + 1
				let hclen = try br.bits(4) + 4
				var cl = [Int](repeating: 0, count: 19)
				for i in 0..<hclen { cl[codeLengthOrder[i]] = try br.bits(3) }
				let clTable = try Huffman(lengths: cl)
				var lengths: [Int] = []
				while lengths.count < hlit + hdist {
					let sym = try clTable.decode(&br)
					switch sym {
					case 0..<16: lengths.append(sym)
					case 16:
						guard let prev = lengths.last else { throw Failure("repeat with no previous length") }
						lengths += [Int](repeating: prev, count: 3 + (try br.bits(2)))
					case 17: lengths += [Int](repeating: 0, count: 3 + (try br.bits(3)))
					default: lengths += [Int](repeating: 0, count: 11 + (try br.bits(7)))
					}
				}
				guard lengths.count == hlit + hdist else { throw Failure("too many code lengths") }
				let lit = try Huffman(lengths: Array(lengths[0..<hlit]))
				let dist = try Huffman(lengths: Array(lengths[hlit...]))
				try codes(&br, &out, lit, dist)
			default:
				throw Failure("invalid block type")
			}
		}
		return out
	}

	static func codes(_ br: inout BitReader, _ out: inout [UInt8], _ lit: Huffman, _ dist: Huffman) throws {
		while true {
			let sym = try lit.decode(&br)
			if sym < 256 {
				out.append(UInt8(sym))
			} else if sym == 256 {
				return
			} else {
				let li = sym - 257
				guard li < 29 else { throw Failure("bad length symbol") }
				let len = lenBase[li] + (try br.bits(lenExtra[li]))
				let di = try dist.decode(&br)
				guard di < 30 else { throw Failure("bad distance symbol") }
				let d = distBase[di] + (try br.bits(distExtra[di]))
				guard d <= out.count else { throw Failure("distance too far back") }
				let start = out.count - d
				for i in 0..<len { out.append(out[start + i]) }
			}
		}
	}
}
