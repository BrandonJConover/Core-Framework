import Foundation
import Security

#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

struct SavedLoginCredential: Codable {
    let username: String
    let password: String
}

enum BiometricKind {
    case none
    case faceID
    case touchID
    case opticID

    var buttonTitle: String {
        switch self {
        case .faceID:
            return "Quick Login with Face ID"
        case .touchID:
            return "Quick Login with Touch ID"
        case .opticID:
            return "Quick Login with Optic ID"
        case .none:
            return "Quick Login"
        }
    }

    var toggleTitle: String {
        switch self {
        case .faceID:
            return "Save for Face ID"
        case .touchID:
            return "Save for Touch ID"
        case .opticID:
            return "Save for Optic ID"
        case .none:
            return "Save for Quick Login"
        }
    }

    var symbolName: String {
        switch self {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.fill"
        }
    }
}

enum BiometricAuthError: LocalizedError {
    case unavailable
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Biometric authentication is not available on this device."
        case .failed:
            return "Quick login could not verify your identity."
        }
    }
}

enum DeviceBiometrics {
    static func availableKind() -> BiometricKind {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        #if os(iOS)
        case .opticID:
            return .opticID
        #endif
        default:
            return .none
        }
        #else
        return .none
        #endif
    }

    static func authenticate(reason: String) async throws {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        context.localizedCancelTitle = "Use Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricAuthError.unavailable
        }

        let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evalError in
                if let evalError {
                    continuation.resume(throwing: evalError)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }

        guard success else {
            throw BiometricAuthError.failed
        }
        #else
        throw BiometricAuthError.unavailable
        #endif
    }
}

enum BiometricLoginStore {
    private static let servicePrefix = "dev.novelgames.openrsc.saved-login"
    private static let account = "credential"

    static func loadCredential(for server: ServerProfile) -> SavedLoginCredential? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName(for: server),
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let credential = try? JSONDecoder().decode(SavedLoginCredential.self, from: data) else {
            return nil
        }
        return credential
    }

    static func saveCredential(username: String, password: String, for server: ServerProfile) -> Bool {
        let credential = SavedLoginCredential(username: username, password: password)
        guard let data = try? JSONEncoder().encode(credential) else {
            return false
        }

        let service = serviceName(for: server)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var insertQuery = query
        insertQuery[kSecValueData] = data
        insertQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insertQuery as CFDictionary, nil) == errSecSuccess
    }

    static func deleteCredential(for server: ServerProfile) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName(for: server),
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func serviceName(for server: ServerProfile) -> String {
        "\(servicePrefix).\(server.gameType.rawValue).\(server.host).\(server.port).\(server.wsPort)"
    }
}
