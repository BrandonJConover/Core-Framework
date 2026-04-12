import Foundation

enum LoginResult {
    case success(playerID: Int)
    case invalidCredentials
    case alreadyLoggedIn
    case serverFull
    case accountBanned
    case loginServer
    case other(code: UInt8)
}

final class RSCLoginHandler {
    // Client version matching server config client_version: 10009
    static let clientVersion = 10009

    // Builds the RSC login packet (opcode 0).
    // Matches Network_Socket.java encodeLogin flow:
    //   byte reconnecting=0, int clientVersion, lf-string user, lf-string pass,
    //   long uid (8 bytes random), 23 zero bytes padding.
    static func encodeLogin(username: String, password: String) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.login.rawValue))
        buf.putByte(0)                             // reconnecting = false
        buf.putInt(clientVersion)
        buf.putString(username)
        buf.putString(password)
        // 8-byte UID (random, stored per-device in production)
        let uid = Int64.random(in: Int64.min...Int64.max)
        buf.putLong(uid)
        // 23 zero bytes — ensures packet length >= 38 for inauthentic path threshold
        for _ in 0..<23 { buf.putByte(0) }
        return buf.finishPacket()
    }

    // Builds the RSC registration packet (opcode 2).
    static func encodeRegister(username: String, password: String, email: String) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.register.rawValue))
        buf.putString(username)
        buf.putString(password)
        buf.putString(email)
        buf.putByte(0)
        buf.putByte(0)   // 2-byte padding (ensures length > 10)
        return buf.finishPacket()
    }

    // Decodes the server's single-byte login response.
    // Success: (code & 0x40) != 0  (bit 6 set = codes 64–89)
    static func decodeLoginResponse(_ code: UInt8) -> LoginResult {
        if (code & 0x40) != 0 {
            let playerID = Int(code & 0x3F)
            return .success(playerID: playerID)
        }
        switch code {
        case 3:  return .invalidCredentials
        case 4:  return .alreadyLoggedIn
        case 5:  return .serverFull
        case 6:  return .accountBanned
        case 9:  return .loginServer
        default: return .other(code: code)
        }
    }

    // Human-readable error for the UI.
    static func errorMessage(for result: LoginResult) -> String {
        switch result {
        case .success:              return ""
        case .invalidCredentials:   return "Invalid username or password."
        case .alreadyLoggedIn:      return "Account is already logged in."
        case .serverFull:           return "Server is full. Try again later."
        case .accountBanned:        return "Your account has been suspended."
        case .loginServer:          return "Cannot connect to login server."
        case .other(let code):      return "Login failed (code \(code))."
        }
    }
}
