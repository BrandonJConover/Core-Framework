import Foundation
import AVFoundation
import RSCEngine

/// Owns the embedded rsc-c engine (see RSCEngine/README.md).
///
/// rsc-c keeps process-wide global state, so the engine starts once per app
/// launch and keeps running when its screen is hidden. Switching to a
/// different server needs an app restart.
final class RSCEngineHost {
    static let shared = RSCEngineHost()

    enum StartError: LocalizedError {
        case missingCache
        case missingRSAKey
        case alreadyRunning(String)
        case engineFailed

        var errorDescription: String? {
            switch self {
            case .missingCache:
                return "The game cache is missing from the app bundle (rsc-cache)."
            case .missingRSAKey:
                return "This server needs its RSA modulus before the native client can log in."
            case .alreadyRunning(let name):
                return "The game is already connected to \(name). Restart the app to switch servers."
            case .engineFailed:
                return "The game engine failed to start."
            }
        }
    }

    private(set) var runningServerID: UUID?
    private(set) var runningServerName: String?
    private var audio: RSCAudioOutput?

    private init() {}

    var isRunning: Bool { rsc_host_is_running() != 0 }

    /// Directory with options.ini and worlds.cfg.
    static var configDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("rsc-c", isDirectory: true)
    }

    static var cacheDirectory: URL? {
        guard let url = Bundle.main.url(forResource: "rsc-cache", withExtension: nil) else { return nil }
        // rsc-c exits the process if an archive is missing, so check first.
        let probe = url.appendingPathComponent("jagex.jag").path
        return FileManager.default.fileExists(atPath: probe) ? url : nil
    }

    /// Starts the engine for `server`, or confirms it is already running for it.
    func start(server: ServerProfile, windowSize: CGSize) throws {
        if isRunning {
            if runningServerID == server.id { return }
            throw StartError.alreadyRunning(runningServerName ?? "another server")
        }

        guard let cache = Self.cacheDirectory else { throw StartError.missingCache }
        guard let modulus = server.rsaModulusHex, let exponent = server.rsaExponentHex else {
            throw StartError.missingRSAKey
        }

        let config = Self.configDirectory
        try? FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)

        let wrote = rsc_host_write_world(config.path, server.name, server.host, Int32(server.port), exponent, modulus)
        guard wrote == 0 else { throw StartError.engineFailed }

        // Show "New User" on the welcome screen and make it an in-game
        // sign-up form, so players without an account can create one.
        // rsc-c rewrites options.ini on exit, so set these on every start.
        rsc_host_set_option(config.path, "registration", 1)
        rsc_host_set_option(config.path, "account_management", 1)

        rsc_host_set_log_handler { isError, message in
            guard let message else { return }
            let text = String(cString: message).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            print(isError != 0 ? "[rsc-c] ERROR \(text)" : "[rsc-c] \(text)")
        }

        let width = Int32(max(1, windowSize.width.rounded()))
        let height = Int32(max(1, windowSize.height.rounded()))

        let result: Int32 = cache.path.withCString { cachePath in
            config.path.withCString { configPath in
                var hostConfig = rsc_host_config(
                    cache_dir: cachePath,
                    config_dir: configPath,
                    window_width: width,
                    window_height: height,
                    members: 1
                )
                // rsc_host_start copies the paths before returning.
                return rsc_host_start(&hostConfig)
            }
        }

        guard result == 0 else { throw StartError.engineFailed }

        runningServerID = server.id
        runningServerName = server.name

        if audio == nil {
            audio = RSCAudioOutput()
        }
        audio?.start()
    }

    func setAudioEnabled(_ enabled: Bool) {
        enabled ? audio?.start() : audio?.stop()
    }
}

/// Plays the engine's 8 kHz mono PCM sound effects.
final class RSCAudioOutput {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var scratch = [Int16](repeating: 0, count: 4096)
    private var started = false

    init() {
        let rate = Double(rsc_host_audio_sample_rate())
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 8000, channels: 1) else {
            return
        }

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            if self.scratch.count < frames {
                self.scratch = [Int16](repeating: 0, count: frames)
            }
            let read = self.scratch.withUnsafeMutableBufferPointer { ptr -> Int in
                Int(rsc_host_read_audio(ptr.baseAddress, Int32(frames)))
            }
            for buffer in buffers {
                guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<frames {
                    out[i] = i < read ? Float(self.scratch[i]) / 32768.0 : 0
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
    }

    func start() {
        guard source != nil, !started else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        do {
            try engine.start()
            started = true
        } catch {
            print("[RSCAudio] failed to start: \(error)")
        }
    }

    func stop() {
        guard started else { return }
        engine.pause()
        started = false
    }
}
