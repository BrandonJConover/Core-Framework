import Foundation
import LocalAuthentication
import Security

/// Minimal generic-password Keychain storage for the remembered account.
enum Keychain {
	// Separate namespace prevents an older unprotected credential from being
	// returned after biometric protection is enabled.
	static let service = "com.brandonconover.scape530.account.biometric"

	static func setPassword(_ password: String, for account: String) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		SecItemDelete(query as CFDictionary)
		var add = query
		add[kSecValueData as String] = Data(password.utf8)
		if let access = SecAccessControlCreateWithFlags(
			nil,
			kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
			.biometryCurrentSet,
			nil) {
			add[kSecAttrAccessControl as String] = access
		} else {
			add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
		}
		SecItemAdd(add as CFDictionary, nil)
	}

	static func password(for account: String, prompt: String, completion: @escaping (String?) -> Void) {
		let context = LAContext()
		context.localizedReason = prompt
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
			kSecUseAuthenticationContext as String: context,
		]
		DispatchQueue.global(qos: .userInitiated).async {
			var out: CFTypeRef?
			guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
				  let data = out as? Data,
				  let password = String(data: data, encoding: .utf8) else {
				DispatchQueue.main.async { completion(nil) }
				return
			}
			DispatchQueue.main.async { completion(password) }
		}
	}

	/// Reads the protected password, asking for Face ID / Touch ID. Blocks; call it off the main thread.
	static func unlockedPassword(for account: String, prompt: String) -> String? {
		let context = LAContext()
		context.localizedReason = prompt
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
			kSecUseAuthenticationContext as String: context,
		]
		var out: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func password(for account: String) -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var out: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}
}
