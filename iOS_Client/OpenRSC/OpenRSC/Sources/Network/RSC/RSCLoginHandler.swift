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
    // Matches inauthentic client path in LoginPacketHandler.java:466-573.
    // Server requires payload >= 38 bytes after opcode (RSCProtocolDecoder.java:131).
    // After basic fields, server reads ClientLimitations if bytes remain (line 482).
    static func encodeLogin(username: String, password: String) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.login.rawValue))
        buf.putByte(0)                             // reconnecting = false
        buf.putInt(clientVersion)                   // 4-byte client version
        buf.putString(username)                     // username + 0x0A terminator
        buf.putString(password)                     // password + 0x0A terminator
        let uid = Int64.random(in: Int64.min...Int64.max)
        buf.putLong(uid)                            // 8-byte UID

        // ClientLimitations — tells server what this client supports.
        // Must send ALL fields or NONE. Server reads them sequentially
        // if packet.getReadableBytes() > 0 (LoginPacketHandler.java:482-505).
        // Use large values so server doesn't limit what it sends us.
        buf.putShort(1143)                          // maxAnimationId (short)
        buf.putInt(1290)                            // maxItemId (int)
        buf.putInt(794)                             // maxNpcId (int)
        buf.putInt(1188)                            // maxSceneryId (int)
        buf.putShort(28)                            // maxPrayerId (short)
        buf.putShort(33)                            // maxSpellId (short)
        buf.putByte(18)                             // maxSkillId (byte)
        buf.putShort(12)                            // maxRoofId (short)
        buf.putShort(17)                            // maxTextureId (short)
        buf.putShort(127)                           // maxTileId (short)
        buf.putInt(348)                             // maxBoundaryId (int)
        buf.putByte(3)                              // maxTeleBubbleId (byte)
        buf.putShort(36)                            // maxProjectileSprite (short)
        buf.putInt(10)                              // maxSkinColor (int)
        buf.putInt(11)                              // maxHairColor (int)
        buf.putInt(15)                              // maxClothingColor (int)
        buf.putShort(50)                            // maxQuestId (short)
        buf.putInt(39)                              // numberOfSounds (int)
        buf.putByte(1)                              // supportsModSprites (byte)
        buf.putByte(5)                              // maxDialogueOptions (byte)
        buf.putInt(192)                             // maxBankItems (int)
        buf.putString("")                           // mapHash (empty string + \n)
        buf.putByte(0)                              // isAndroidClient = false

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
