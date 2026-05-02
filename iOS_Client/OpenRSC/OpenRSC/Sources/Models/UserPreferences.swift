import Foundation

/// Lightweight UserDefaults-backed preferences. Loaded once on engine init,
/// then written back through RSCGameEngine.updatePreferences(...). This is
/// strictly per-device state: no iCloud sync and no sensitive data.
struct UserPreferences: Codable, Equatable {
    var hidePublicChat: Bool = false
    var hidePrivateChat: Bool = false
    var hideTradeRequests: Bool = false
    var hideDuelRequests: Bool = false

    var sfxMuted: Bool = false
    var musicMuted: Bool = false
    var runByDefault: Bool = false

    var lastCameraYawDegrees: Double = 0
    var lastCameraPitchDegrees: Double = 0
    var lastCameraZoom: Double = 0

    private static let key = "openrsc.userPreferences.v1"
    private static let defaults: UserDefaults = .standard

    static func load() -> UserPreferences {
        guard let data = defaults.data(forKey: key) else { return UserPreferences() }
        return (try? JSONDecoder().decode(UserPreferences.self, from: data)) ?? UserPreferences()
    }

    static func save(_ prefs: UserPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
