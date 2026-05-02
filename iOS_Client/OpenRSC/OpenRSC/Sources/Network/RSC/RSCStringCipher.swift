import Foundation

enum RSCStringCipher {
    private static let bitLengths: [Int] = [
        22, 22, 22, 22, 22, 22, 21, 22, 22, 20, 22, 22, 22, 21, 22, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        3, 8, 22, 16, 22, 16, 17, 7, 13, 13, 13, 16, 7, 10, 6, 16,
        10, 11, 12, 12, 12, 12, 13, 13, 14, 14, 11, 14, 19, 15, 17, 8,
        11, 9, 10, 10, 10, 10, 11, 10, 9, 7, 12, 11, 10, 10, 9, 10,
        10, 12, 10, 9, 8, 12, 12, 9, 14, 8, 12, 17, 16, 17, 22, 13,
        21, 4, 7, 6, 5, 3, 6, 6, 5, 4, 10, 7, 5, 6, 4, 4,
        6, 10, 5, 4, 4, 5, 7, 6, 10, 6, 10, 22, 19, 22, 14, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        22, 22, 22, 22, 22, 22, 21, 22, 21, 22, 22, 22, 21, 22, 22
    ]

    private static let tables: (blocks: [UInt32], dictionary: [Int]) = {
        var blocks = [UInt32](repeating: 0, count: bitLengths.count)
        var builder = [UInt32](repeating: 0, count: 33)
        var dictionary = [Int](repeating: 0, count: 8)
        var dictionaryLimit = 0

        for index in 0..<bitLengths.count {
            let bitLength = bitLengths[index]
            let selector = UInt32(1) << UInt32(32 - bitLength)
            let value = builder[bitLength]
            blocks[index] = value

            let nextValue: UInt32
            if (value & selector) == 0 {
                nextValue = value | selector
                if bitLength > 1 {
                    for length in stride(from: bitLength - 1, through: 1, by: -1) {
                        let previous = builder[length]
                        if value != previous { break }
                        let previousSelector = UInt32(1) << UInt32(32 - length)
                        if (previous & previousSelector) == 0 {
                            builder[length] = previous | previousSelector
                        } else {
                            builder[length] = builder[length - 1]
                            break
                        }
                    }
                }
            } else {
                nextValue = builder[bitLength - 1]
            }

            builder[bitLength] = nextValue
            if bitLength < 32 {
                for length in (bitLength + 1)...32 where builder[length] == value {
                    builder[length] = nextValue
                }
            }

            var dictionaryIndex = 0
            for bit in 0..<bitLength {
                let bitSelector = UInt32(0x80000000) >> UInt32(bit)
                if (value & bitSelector) == 0 {
                    dictionaryIndex += 1
                } else {
                    if dictionary[dictionaryIndex] == 0 {
                        dictionary[dictionaryIndex] = dictionaryLimit
                    }
                    dictionaryIndex = dictionary[dictionaryIndex]
                }

                if dictionary.count <= dictionaryIndex {
                    dictionary += [Int](repeating: 0, count: dictionary.count)
                }
            }

            dictionary[dictionaryIndex] = ~index
            if dictionaryIndex >= dictionaryLimit {
                dictionaryLimit = dictionaryIndex + 1
            }
        }

        return (blocks, dictionary)
    }()

    private static var cipherBlocks: [UInt32] { tables.blocks }
    private static var cipherDictionary: [Int] { tables.dictionary }

    static func encode(_ message: String) -> (plainLength: Int, cipherBytes: [UInt8]) {
        let plain = stringBytes(message)
        var output = [UInt8](repeating: 0, count: plain.count * 4 + 8)
        var carried: UInt32 = 0
        var outputBitOffset = 0

        for byte in plain {
            let value = Int(byte)
            let block = cipherBlocks[value]
            let bitLength = bitLengths[value]
            var outputByteOffset = outputBitOffset >> 3
            var shifter = outputBitOffset & 7
            if shifter == 0 { carried = 0 }

            let lastOutputByteOffset = outputByteOffset + ((shifter + bitLength - 1) >> 3)
            outputBitOffset += bitLength
            shifter += 24

            carried |= block >> UInt32(shifter)
            output[outputByteOffset] = UInt8(truncatingIfNeeded: carried)

            if outputByteOffset < lastOutputByteOffset {
                outputByteOffset += 1
                shifter -= 8
                carried = block >> UInt32(shifter)
                output[outputByteOffset] = UInt8(truncatingIfNeeded: carried)

                if outputByteOffset < lastOutputByteOffset {
                    outputByteOffset += 1
                    shifter -= 8
                    carried = block >> UInt32(shifter)
                    output[outputByteOffset] = UInt8(truncatingIfNeeded: carried)

                    if outputByteOffset < lastOutputByteOffset {
                        outputByteOffset += 1
                        shifter -= 8
                        carried = block >> UInt32(shifter)
                        output[outputByteOffset] = UInt8(truncatingIfNeeded: carried)

                        if outputByteOffset < lastOutputByteOffset {
                            outputByteOffset += 1
                            shifter -= 8
                            carried = block << UInt32(-shifter)
                            output[outputByteOffset] = UInt8(truncatingIfNeeded: carried)
                        }
                    }
                }
            }
        }

        let encodedLength = (outputBitOffset + 7) >> 3
        return (plain.count, Array(output.prefix(encodedLength)))
    }

    static func decode(_ bytes: [UInt8], plainLength: Int) -> String {
        guard plainLength > 0 else { return "" }
        var output = [UInt8]()
        output.reserveCapacity(plainLength)
        var node = 0

        for byte in bytes {
            for mask in [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01] {
                node = (Int(byte) & mask) == 0 ? node + 1 : cipherDictionary[node]
                let value = cipherDictionary[node]
                if value < 0 {
                    output.append(UInt8(truncatingIfNeeded: ~value))
                    if output.count >= plainLength {
                        return decodeStringBytes(output)
                    }
                    node = 0
                }
            }
        }

        return decodeStringBytes(output)
    }

    private static func stringBytes(_ message: String) -> [UInt8] {
        message.map { char in
            switch char {
            case "\u{20AC}": return 128
            case "\u{201A}": return 130
            case "\u{0192}": return 131
            case "\u{201E}": return 132
            case "\u{2026}": return 133
            case "\u{2020}": return 134
            case "\u{2021}": return 135
            case "\u{02C6}": return 136
            case "\u{2030}": return 137
            case "\u{0160}": return 138
            case "\u{2039}": return 139
            case "\u{0152}": return 140
            case "\u{017D}": return 142
            case "\u{2018}": return 145
            case "\u{2019}": return 146
            case "\u{201C}": return 147
            case "\u{201D}": return 148
            case "\u{2022}": return 149
            case "\u{2013}": return 150
            case "\u{2014}": return 151
            case "\u{02DC}": return 152
            case "\u{2122}": return 153
            case "\u{0161}": return 154
            case "\u{203A}": return 155
            case "\u{0153}": return 156
            case "\u{017E}": return 158
            case "\u{0178}": return 159
            default:
                let scalar = char.unicodeScalars.first?.value ?? 63
                return (scalar > 0 && scalar < 128) || (scalar >= 160 && scalar <= 255)
                    ? UInt8(scalar)
                    : 63
            }
        }
    }

    private static func decodeStringBytes(_ bytes: [UInt8]) -> String {
        let scalars = bytes.compactMap { byte -> UnicodeScalar? in
            if byte == 0 { return nil }
            if byte >= 128 && byte < 160 {
                return UnicodeScalar(specialCharacters[Int(byte) - 128].unicodeScalars.first!.value)
            }
            return UnicodeScalar(Int(byte))
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static let specialCharacters: [Character] = [
        "\u{20AC}", "?", "\u{201A}", "\u{0192}", "\u{201E}", "\u{2026}", "\u{2020}", "\u{2021}",
        "\u{02C6}", "\u{2030}", "\u{0160}", "\u{2039}", "\u{0152}", "?", "\u{017D}", "?",
        "?", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", "\u{2022}", "\u{2013}", "\u{2014}",
        "\u{02DC}", "\u{2122}", "\u{0161}", "\u{203A}", "\u{0153}", "?", "\u{017E}", "\u{0178}"
    ]
}
