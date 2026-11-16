/// Port of rt4 `HuffmanCodec` (client!fi): the canonical Huffman code that
/// compresses public and private chat text. The table is one byte per symbol,
/// the code length in bits (0 = symbol unused), from the cache's archive 10.
///
/// Codewords are assigned exactly as rt4 does (left-aligned in 32 bits), and
/// decoding walks the same flattened `symbolTree` (a node's "0" child is the
/// next slot, its "1" child the slot the node stores; negative values are
/// `~symbol` leaves).
public struct HuffmanCodec {
	public enum Failure: Error, CustomStringConvertible {
		case noCodeword(UInt8)
		case truncated
		case corruptTree
		public var description: String {
			switch self {
			case .noCodeword(let b): return "no codeword for data value \(b)"
			case .truncated: return "huffman data ended early"
			case .corruptTree: return "huffman tree walk left the table"
			}
		}
	}

	private var symbolTree: [Int32]
	private let codewords: [UInt32]
	private let bits: [UInt8]

	/// rt4 constructor: `bits` is the per-symbol code length table.
	public init(bits: [UInt8]) {
		var next = [UInt32](repeating: 0, count: 33)
		var tree = [Int32](repeating: 0, count: 8)
		var words = [UInt32](repeating: 0, count: bits.count)
		var nextNode = 0
		for symbol in 0..<bits.count {
			let n = Int(bits[symbol])
			if n == 0 { continue }
			let bit: UInt32 = 1 &<< UInt32(32 - n)
			let codeword = next[n]
			words[symbol] = codeword
			let successor: UInt32
			if codeword & bit == 0 {
				var i = n - 1
				while i >= 1 {
					let other = next[i]
					if codeword != other { break }
					let mask: UInt32 = 1 &<< UInt32(32 - i)
					if other & mask != 0 {
						next[i] = next[i - 1]
						break
					}
					next[i] = mask | other
					i -= 1
				}
				successor = codeword | bit
			} else {
				successor = next[n - 1]
			}
			next[n] = successor
			if n + 1 <= 32 {
				for i in (n + 1)...32 where codeword == next[i] { next[i] = successor }
			}
			var node = 0
			for k in 0..<n {
				let mask: UInt32 = 0x8000_0000 >> UInt32(k)
				if codeword & mask == 0 {
					node += 1
				} else {
					if tree[node] == 0 { tree[node] = Int32(nextNode) }
					node = Int(tree[node])
				}
				while tree.count <= node { tree += [Int32](repeating: 0, count: tree.count) }
			}
			tree[node] = ~Int32(symbol)
			if node >= nextNode { nextNode = node + 1 }
		}
		self.bits = bits
		codewords = words
		symbolTree = tree
	}

	/// rt4 `encode`: compresses `src[0..<length]`, returning the packed bytes
	/// (rt4 writes them into a packet at `destOffset`; here the offset is 0).
	public func encode(_ src: [UInt8], length: Int? = nil) throws -> [UInt8] {
		let count = length ?? src.count
		var dest = [UInt8](repeating: 0, count: count * 5 + 8)
		var acc: UInt32 = 0
		var bitPos = 0
		for index in 0..<count {
			let sym = Int(src[index])
			let word = sym < codewords.count ? codewords[sym] : 0
			let nb = sym < bits.count ? Int(bits[sym]) : 0
			if nb == 0 { throw Failure.noCodeword(src[index]) }
			var byte = bitPos >> 3
			let shiftIn = bitPos & 7
			bitPos += nb
			let last = byte + ((shiftIn + nb - 1) >> 3)
			// rt4: `acc &= -shiftIn >> 31`, keeping the partly filled byte only when mid-byte.
			if shiftIn == 0 { acc = 0 }
			var shift = shiftIn + 24
			acc |= word &>> UInt32(truncatingIfNeeded: shift)
			dest[byte] = UInt8(truncatingIfNeeded: acc)
			if byte < last {
				byte += 1
				shift -= 8
				acc = word &>> UInt32(truncatingIfNeeded: shift)
				dest[byte] = UInt8(truncatingIfNeeded: acc)
				if byte < last {
					shift -= 8
					byte += 1
					acc = word &>> UInt32(truncatingIfNeeded: shift)
					dest[byte] = UInt8(truncatingIfNeeded: acc)
					if last > byte {
						shift -= 8
						byte += 1
						acc = word &>> UInt32(truncatingIfNeeded: shift)
						dest[byte] = UInt8(truncatingIfNeeded: acc)
						if last > byte {
							byte += 1
							shift -= 8
							acc = word &<< UInt32(truncatingIfNeeded: -shift)
							dest[byte] = UInt8(truncatingIfNeeded: acc)
						}
					}
				}
			}
		}
		return Array(dest[0..<((bitPos + 7) >> 3)])
	}

	/// rt4 `decode`: reads symbols from `src` starting at `offset` until `length`
	/// symbols were produced. Returns them with the number of source bytes used.
	public func decode(_ src: [UInt8], at offset: Int = 0, length: Int) throws -> (bytes: [UInt8], consumed: Int) {
		if length == 0 { return ([], 0) }
		var out: [UInt8] = []
		out.reserveCapacity(length)
		var node = 0
		var pos = offset
		while true {
			guard pos < src.count else { throw Failure.truncated }
			let byte = src[pos]
			var mask: UInt8 = 0x80
			while mask != 0 {
				if byte & mask != 0 {
					guard node < symbolTree.count else { throw Failure.corruptTree }
					node = Int(symbolTree[node])
				} else {
					node += 1
				}
				guard node >= 0, node < symbolTree.count else { throw Failure.corruptTree }
				let v = symbolTree[node]
				if v < 0 {
					out.append(UInt8(truncatingIfNeeded: ~v))
					if out.count >= length { return (out, pos + 1 - offset) }
					node = 0
				}
				mask >>= 1
			}
			pos += 1
		}
	}
}
