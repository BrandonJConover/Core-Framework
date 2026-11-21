// Headerless bzip2 decompression, as used by RuneScape Classic .jag archives.
// Port of rsc-c's lib/bzip.c (micro-bunzip by Rob Landley / Manuel Novoa III,
// LGPLv2). Jagex strips the "BZh1" magic, so callers pass raw block data.

public enum BZip2Error: Error {
    case notBzipData
    case unexpectedEOF
    case dataError
    case obsoleteFormat
}

public enum BZip2 {
    private static let maxGroups = 6
    private static let groupSize = 50
    private static let maxHuffCodeBits = 20
    private static let maxSymbols = 258

    /// Decompresses Jagex-style bzip2 data (no "BZh1" header) of known output size.
    public static func decompress(_ input: [UInt8], outputSize: Int) throws -> [UInt8] {
        var reader = BitReader(data: input)
        let blockSize = 100_000 // RSC always uses block size 1 ("BZh1")
        var dbuf = [UInt32](repeating: 0, count: blockSize)
        var output = [UInt8]()
        output.reserveCapacity(outputSize)

        while true {
            let magic1 = try reader.bits(24)
            let magic2 = try reader.bits(24)
            _ = try reader.bits(32) // block CRC (not checked)

            if magic1 == 0x177245 && magic2 == 0x385090 {
                break // end of stream
            }
            guard magic1 == 0x314159 && magic2 == 0x265359 else {
                throw BZip2Error.notBzipData
            }
            if try reader.bits(1) != 0 {
                throw BZip2Error.obsoleteFormat
            }

            let origPtr = Int(try reader.bits(24))
            guard origPtr <= blockSize else { throw BZip2Error.dataError }

            // Symbol map
            var symToByte = [UInt8](repeating: 0, count: 256)
            var symTotal = 0
            let used = try reader.bits(16)
            for i in 0..<16 where used & (1 << (15 - i)) != 0 {
                let k = try reader.bits(16)
                for j in 0..<16 where k & (1 << (15 - j)) != 0 {
                    symToByte[symTotal] = UInt8(16 * i + j)
                    symTotal += 1
                }
            }

            let groupCount = Int(try reader.bits(3))
            guard groupCount >= 2 && groupCount <= maxGroups else { throw BZip2Error.dataError }
            let nSelectors = Int(try reader.bits(15))
            guard nSelectors > 0 else { throw BZip2Error.dataError }

            var mtfGroups = (0..<groupCount).map { UInt8($0) }
            var selectors = [UInt8](repeating: 0, count: nSelectors)
            for i in 0..<nSelectors {
                var j = 0
                while try reader.bits(1) != 0 {
                    j += 1
                    guard j < groupCount else { throw BZip2Error.dataError }
                }
                let uc = mtfGroups[j]
                while j > 0 {
                    mtfGroups[j] = mtfGroups[j - 1]
                    j -= 1
                }
                mtfGroups[0] = uc
                selectors[i] = uc
            }

            // Huffman tables
            let symCount = symTotal + 2
            var groups = [HuffmanGroup]()
            for _ in 0..<groupCount {
                var lengths = [Int](repeating: 0, count: symCount)
                var t = Int(try reader.bits(5))
                for i in 0..<symCount {
                    while true {
                        guard t >= 1 && t <= maxHuffCodeBits else { throw BZip2Error.dataError }
                        if try reader.bits(1) == 0 { break }
                        t += try reader.bits(1) == 0 ? 1 : -1
                    }
                    lengths[i] = t
                }
                groups.append(HuffmanGroup(lengths: lengths))
            }

            // Decode symbols, undo MTF and RLE1 into dbuf
            var byteCount = [Int](repeating: 0, count: 256)
            var mtf = (0..<256).map { UInt8($0) }
            var dbufCount = 0
            var selectorIndex = 0
            var groupLeft = 0
            var group = groups[0]
            var runPos = 0
            var run = 0

            while true {
                if groupLeft == 0 {
                    groupLeft = groupSize
                    guard selectorIndex < nSelectors else { throw BZip2Error.dataError }
                    group = groups[Int(selectors[selectorIndex])]
                    selectorIndex += 1
                }
                groupLeft -= 1

                let nextSym = try group.decode(&reader)

                if nextSym <= 1 { // RUNA / RUNB
                    if runPos == 0 {
                        runPos = 1
                        run = 0
                    }
                    run += runPos << nextSym
                    runPos <<= 1
                    continue
                }

                if runPos != 0 {
                    runPos = 0
                    guard dbufCount + run <= blockSize else { throw BZip2Error.dataError }
                    let uc = symToByte[Int(mtf[0])]
                    byteCount[Int(uc)] += run
                    for _ in 0..<run {
                        dbuf[dbufCount] = UInt32(uc)
                        dbufCount += 1
                    }
                }

                if nextSym > symTotal { break } // end of block

                guard dbufCount < blockSize else { throw BZip2Error.dataError }
                var i = nextSym - 1
                let uc = mtf[i]
                while i > 0 {
                    mtf[i] = mtf[i - 1]
                    i -= 1
                }
                mtf[0] = uc
                let byte = symToByte[Int(uc)]
                byteCount[Int(byte)] += 1
                dbuf[dbufCount] = UInt32(byte)
                dbufCount += 1
            }

            // Inverse Burrows-Wheeler transform
            var sum = 0
            for i in 0..<256 {
                let k = sum + byteCount[i]
                byteCount[i] = sum
                sum = k
            }
            for i in 0..<dbufCount {
                let uc = Int(dbuf[i] & 0xff)
                dbuf[byteCount[uc]] |= UInt32(i) << 8
                byteCount[uc] += 1
            }

            guard dbufCount > 0 else { continue }
            guard origPtr < dbufCount else { throw BZip2Error.dataError }

            // Undo the final run-length encoding while writing output
            // dbuf[origPtr] only seeds the walk; its own byte isn't output.
            var pos = Int(dbuf[origPtr] >> 8)
            var current = 0
            var remaining = dbufCount
            var lastByte = -1
            var runLength = 0

            while remaining > 0 {
                remaining -= 1
                let entry = dbuf[pos]
                current = Int(entry & 0xff)
                pos = Int(entry >> 8)

                if runLength == 4 {
                    for _ in 0..<current {
                        output.append(UInt8(lastByte))
                    }
                    runLength = 0
                    lastByte = -1
                    continue
                }

                if current == lastByte {
                    runLength += 1
                } else {
                    runLength = 1
                    lastByte = current
                }
                output.append(UInt8(current))
            }
        }

        if output.count > outputSize {
            output.removeLast(output.count - outputSize)
        }
        return output
    }

    private struct HuffmanGroup {
        var minLen = 0
        var maxLen = 0
        var limit = [Int](repeating: 0, count: 22)
        var base = [Int](repeating: 0, count: 22)
        var permute = [Int](repeating: 0, count: 258)

        init(lengths: [Int]) {
            minLen = lengths.min() ?? 0
            maxLen = lengths.max() ?? 0

            var pp = 0
            for len in minLen...maxLen {
                for (sym, l) in lengths.enumerated() where l == len {
                    permute[pp] = sym
                    pp += 1
                }
            }

            var count = [Int](repeating: 0, count: 22)
            for l in lengths { count[l] += 1 }

            // Canonical Huffman: codes of each length are consecutive.
            var code = 0
            var symbolsSoFar = 0
            for len in minLen...maxLen {
                base[len] = symbolsSoFar - code
                code += count[len]
                symbolsSoFar += count[len]
                limit[len] = code - 1
                code <<= 1
            }
        }

        func decode(_ reader: inout BitReader) throws -> Int {
            var len = minLen
            var code = Int(try reader.bits(len))
            while len <= maxLen {
                if code <= limit[len] {
                    let index = code + base[len]
                    guard index >= 0 && index < BZip2.maxSymbols else { throw BZip2Error.dataError }
                    return permute[index]
                }
                code = (code << 1) | Int(try reader.bits(1))
                len += 1
            }
            throw BZip2Error.dataError
        }
    }

    struct BitReader {
        let data: [UInt8]
        var position = 0
        var bitBuffer: UInt64 = 0
        var bitCount = 0

        init(data: [UInt8]) {
            self.data = data
        }

        mutating func bits(_ n: Int) throws -> UInt32 {
            if n == 0 { return 0 }
            while bitCount < n {
                guard position < data.count else { throw BZip2Error.unexpectedEOF }
                bitBuffer = (bitBuffer << 8) | UInt64(data[position])
                position += 1
                bitCount += 8
            }
            bitCount -= n
            return UInt32((bitBuffer >> UInt64(bitCount)) & ((1 << UInt64(n)) - 1))
        }
    }
}
