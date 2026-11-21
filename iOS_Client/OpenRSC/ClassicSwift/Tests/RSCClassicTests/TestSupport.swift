import Foundation

/// Paths shared by the tests. The game cache is the one bundled with the
/// C engine (RSCEngine/rsc-cache), so both ports read identical data.
enum TestPaths {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let cache = packageRoot.deletingLastPathComponent()
        .appendingPathComponent("RSCEngine/rsc-cache")
    static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Golden")
}

func fnv1a(_ bytes: [UInt8]) -> UInt32 {
    var h: UInt32 = 2166136261
    for b in bytes {
        h ^= UInt32(b)
        h = h &* 16777619
    }
    return h
}
