import Foundation
import UIKit

/// Mobile-specific optimizations for battery life and performance.
final class MobileOptimizations: ObservableObject {
    static let shared = MobileOptimizations()

    // State
    @Published var isLowPowerMode: Bool = false
    @Published var isBackgrounded: Bool = false
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var batteryLevel: Float = 1.0
    @Published var batteryState: UIDevice.BatteryState = .unknown

    // Settings
    @Published var targetFrameRate: Int = 60
    @Published var renderQuality: RenderQuality = .high
    @Published var networkQuality: NetworkQuality = .balanced

    enum RenderQuality {
        case low, medium, high

        var tickRate: Int {
            switch self {
            case .low: return 15
            case .medium: return 30
            case .high: return 60
            }
        }
    }

    enum NetworkQuality {
        case lowBandwidth, balanced, highPerformance

        var compressionEnabled: Bool { self != .highPerformance }
        var batchingEnabled: Bool { self != .highPerformance }
        var packetCoalescing: Int {
            switch self {
            case .lowBandwidth: return 5
            case .balanced: return 3
            case .highPerformance: return 1
            }
        }
    }

    private init() {
        setupObservers()
        updateBatteryState()
    }

    private func setupObservers() {
        // Low power mode
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.adjustForPowerState()
        }

        // App lifecycle
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isBackgrounded = true
            self?.adjustForBackground()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isBackgrounded = false
            self?.adjustForForeground()
        }

        // Thermal state
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
            self?.adjustForThermalState()
        }

        // Battery
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBatteryState()
        }

        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBatteryState()
        }
    }

    private func updateBatteryState() {
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
        adjustForBatteryLevel()
    }

    private func adjustForPowerState() {
        if isLowPowerMode {
            targetFrameRate = 30
            renderQuality = .medium
            networkQuality = .lowBandwidth
        } else {
            restoreNormalSettings()
        }
    }

    private func adjustForBackground() {
        // Minimize resource usage when backgrounded
        targetFrameRate = 1
        networkQuality = .lowBandwidth
    }

    private func adjustForForeground() {
        restoreNormalSettings()
    }

    private func adjustForThermalState() {
        switch thermalState {
        case .nominal:
            restoreNormalSettings()

        case .fair:
            targetFrameRate = min(targetFrameRate, 45)
            renderQuality = .medium

        case .serious:
            targetFrameRate = 30
            renderQuality = .low
            networkQuality = .lowBandwidth

        case .critical:
            targetFrameRate = 15
            renderQuality = .low
            networkQuality = .lowBandwidth

        @unknown default:
            break
        }
    }

    private func adjustForBatteryLevel() {
        guard batteryState != .charging && batteryState != .full else {
            restoreNormalSettings()
            return
        }

        if batteryLevel < 0.1 {
            // Critical battery
            targetFrameRate = 15
            renderQuality = .low
            networkQuality = .lowBandwidth
        } else if batteryLevel < 0.2 {
            // Low battery
            targetFrameRate = 30
            renderQuality = .medium
            networkQuality = .lowBandwidth
        }
    }

    private func restoreNormalSettings() {
        guard !isLowPowerMode && !isBackgrounded else { return }

        targetFrameRate = 60
        renderQuality = .high
        networkQuality = .balanced
    }
}

// MARK: - Memory Management

final class MemoryManager {
    static let shared = MemoryManager()

    // Texture cache with LRU eviction
    private var textureCache: [Int: CachedTexture] = [:]
    private let maxCacheSize = 50_000_000 // 50 MB

    private var currentCacheSize = 0

    struct CachedTexture {
        let data: Data
        var lastAccess: Date
    }

    func cacheTexture(id: Int, data: Data) {
        // Evict if necessary
        while currentCacheSize + data.count > maxCacheSize && !textureCache.isEmpty {
            evictLRU()
        }

        textureCache[id] = CachedTexture(data: data, lastAccess: Date())
        currentCacheSize += data.count
    }

    func getTexture(id: Int) -> Data? {
        guard var cached = textureCache[id] else { return nil }
        cached.lastAccess = Date()
        textureCache[id] = cached
        return cached.data
    }

    private func evictLRU() {
        guard let oldest = textureCache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { return }
        currentCacheSize -= oldest.value.data.count
        textureCache.removeValue(forKey: oldest.key)
    }

    func clearCache() {
        textureCache.removeAll()
        currentCacheSize = 0
    }

    func handleMemoryWarning() {
        // Clear half the cache
        let toRemove = textureCache.count / 2
        let sortedKeys = textureCache.sorted { $0.value.lastAccess < $1.value.lastAccess }
            .prefix(toRemove)
            .map { $0.key }

        for key in sortedKeys {
            if let cached = textureCache.removeValue(forKey: key) {
                currentCacheSize -= cached.data.count
            }
        }
    }
}

// MARK: - Frame Rate Limiter

final class FrameRateLimiter {
    private var lastFrameTime: CFTimeInterval = 0
    private var targetInterval: CFTimeInterval = 1.0 / 60.0

    var targetFPS: Int {
        didSet {
            targetInterval = 1.0 / Double(targetFPS)
        }
    }

    init(targetFPS: Int = 60) {
        self.targetFPS = targetFPS
        self.targetInterval = 1.0 / Double(targetFPS)
    }

    /// Returns true if enough time has passed for the next frame.
    func shouldRenderFrame() -> Bool {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - lastFrameTime

        if elapsed >= targetInterval {
            lastFrameTime = currentTime
            return true
        }

        return false
    }

    /// Waits until the next frame time (for CPU-bound rendering).
    func waitForNextFrame() async {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - lastFrameTime
        let remaining = targetInterval - elapsed

        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }

        lastFrameTime = CACurrentMediaTime()
    }
}
