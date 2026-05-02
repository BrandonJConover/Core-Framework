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

    private static let cipherBlocks: [UInt32] = {
        var blocks = [UInt32](repeating: 0, count: bitLengths.count)
        var builder = [UInt32](repeating: 0, count: 33)

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
        }

        return blocks
    }()

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
}
