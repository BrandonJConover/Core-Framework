import Foundation

/// get_ticks (SDL_GetTicks): milliseconds since the client started. Tests can
/// replace `source` to make timing-dependent code deterministic.
public enum ClientTime {
    static let start = DispatchTime.now().uptimeNanoseconds
    public static var source: () -> UInt64 = { (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }
    public static func ticks() -> UInt64 { source() }
}
