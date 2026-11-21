import Foundation

enum GameType: String, Codable, CaseIterable {
    case rsc  = "2001scape"
    case rscWeb = "2001scape Web"
    case osrs = "Old School RuneScape"
}

struct ServerProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int
    var wsPort: Int
    var lastUsername: String
    var gameType: GameType
    /// RSA public key the native RSC engine encrypts the login block with.
    /// Hex, or the decimal value the server prints at startup
    /// ("RSA modulus: ..."). Must match the server's client.pem.
    var rsaModulus: String = ""
    var rsaExponent: String = "10001"

    static let openRSCDefault = ServerProfile(
        name: "2001scape (Home)",
        host: "192.168.0.30",
        port: 43594,
        wsPort: 43494,
        lastUsername: "",
        gameType: .rsc
    )

    static let openRSCWebDefault = ServerProfile(
        name: "2001scape Web (Home)",
        host: "192.168.0.30",
        port: 43594,
        wsPort: 43494,
        lastUsername: "",
        gameType: .rscWeb
    )
}

extension ServerProfile {
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, wsPort, lastUsername, gameType, rsaModulus, rsaExponent
    }

    // Decode older saved profiles that predate the RSA fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        wsPort = try c.decodeIfPresent(Int.self, forKey: .wsPort) ?? 43494
        lastUsername = try c.decodeIfPresent(String.self, forKey: .lastUsername) ?? ""
        gameType = try c.decode(GameType.self, forKey: .gameType)
        rsaModulus = try c.decodeIfPresent(String.self, forKey: .rsaModulus) ?? ""
        rsaExponent = try c.decodeIfPresent(String.self, forKey: .rsaExponent) ?? "10001"
    }

    /// Hex form of `rsaModulus` for rsc-c, accepting hex or decimal input.
    /// Returns nil when the value is empty or not a number.
    var rsaModulusHex: String? { RSAKeyText.hex(from: rsaModulus) }
    var rsaExponentHex: String? { RSAKeyText.hex(from: rsaExponent.isEmpty ? "10001" : rsaExponent) }
}

/// Converts the RSA values people paste (hex, or the decimal number the Java
/// server logs) into the hex strings rsc-c's worlds.cfg expects.
enum RSAKeyText {
    static func hex(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: ":", options: .backwards) {
            // tolerate a pasted log line: "... RSA modulus: 1088..."
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }

        let lower = text.lowercased()
        if lower.hasPrefix("0x") {
            let digits = String(lower.dropFirst(2))
            return isHex(digits) ? digits : nil
        }
        // Server logs print decimal; anything with a-f is hex. A short pure-digit
        // value is ambiguous only for the exponent, where 10001 (hex) is the
        // conventional spelling of 65537.
        if lower.allSatisfy(\.isNumber) && lower.count > 8 {
            return decimalToHex(lower)
        }
        if lower == "65537" { return "10001" }
        return isHex(lower) ? lower : nil
    }

    private static func isHex(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isHexDigit }
    }

    /// Arbitrary-precision decimal -> hex by repeated division by 16.
    static func decimalToHex(_ decimal: String) -> String? {
        var digits = decimal.compactMap { $0.wholeNumberValue }
        guard digits.count == decimal.count, !digits.isEmpty else { return nil }

        var hexDigits: [Character] = []
        let alphabet = Array("0123456789abcdef")
        while !(digits.count == 1 && digits[0] == 0) && !digits.isEmpty {
            var quotient: [Int] = []
            var remainder = 0
            for d in digits {
                let value = remainder * 10 + d
                let q = value / 16
                remainder = value % 16
                if !(quotient.isEmpty && q == 0) { quotient.append(q) }
            }
            hexDigits.append(alphabet[remainder])
            digits = quotient.isEmpty ? [0] : quotient
        }
        return hexDigits.isEmpty ? "0" : String(hexDigits.reversed())
    }
}
