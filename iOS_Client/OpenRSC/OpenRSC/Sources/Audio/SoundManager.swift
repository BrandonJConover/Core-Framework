import Foundation
import AVFoundation

/// Plays the bundled OpenRSC sound effects.
///
/// The reference Java client (`PC_Client/src/orsc/soundPlayer.java`) loads `.wav`
/// files from `Client_Base/Cache/audio/` keyed by their lowercase filename.
/// Server packet 204 sends a UTF-8 string like "fish" / "anvil" / "advance" and the
/// client looks up `fish.wav` and plays it via `javax.sound.sampled.Clip`.
///
/// We mirror that exactly: the WAV files are bundled in `OpenRSC/Audio/` (copied
/// from the cache directory) and decoded into `AVAudioPlayer` instances on first
/// use. Multiple sounds may overlap. A global mute flag is read from
/// `UserDefaults` (key `openrsc_soundDisabled`).
///
/// `sounds.mem` (the legacy ORSC sound archive) is also bundled for completeness
/// but is NOT consumed by the Java client either: see `mudclient.loadSounds()`
/// at line 14433 — it loads the archive bytes into a local variable and never
/// uses them. The actual playback path is the loose .wav files. We keep
/// archive-parsing scaffolding (`unpackArchive(_:)`) marked TODO in case a
/// future server build references entries by name only.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    /// UserDefaults key matching Java's `mudclient.optionSoundDisabled`.
    static let mutePreferenceKey = "openrsc_soundDisabled"

    /// Cached audio buffers keyed by lowercase sound name (without extension).
    /// Each entry is the raw .wav file data; we instantiate fresh
    /// `AVAudioPlayer` instances per playback so concurrent plays don't clash.
    private var cache: [String: Data] = [:]

    /// Live players retained until they finish so playback isn't cut short.
    private var activePlayers: [AVAudioPlayer] = []

    /// Names that we tried to look up but couldn't find. We log once per name
    /// to avoid console spam if the server sends the same missing sound 50x.
    private var missingNames: Set<String> = []

    private init() {
        configureAudioSession()
        preloadAll()
    }

    // MARK: - Public API

    /// Play a sound effect by name (case-insensitive, no extension).
    /// Mirrors `soundPlayer.playSoundFile(key)` from the Java client.
    func play(name: String, volume: Float = 1.0) {
        guard !isMuted else { return }
        let key = name.lowercased()
        guard let data = cache[key] ?? loadSound(named: key) else {
            if missingNames.insert(key).inserted {
                print("[SoundManager] no bundled sound for '\(key)'")
            }
            return
        }
        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = max(0.0, min(1.0, volume))
            player.prepareToPlay()
            // Hold onto the player until it stops so it isn't deallocated mid-play.
            activePlayers.append(player)
            player.delegate = SoundPlaybackObserver.shared
            SoundPlaybackObserver.shared.register(player) { [weak self] finished in
                self?.activePlayers.removeAll { $0 === finished }
            }
            if !player.play() {
                print("[SoundManager] AVAudioPlayer.play() returned false for '\(key)'")
                activePlayers.removeAll { $0 === player }
            }
        } catch {
            print("[SoundManager] failed to create player for '\(key)': \(error)")
        }
    }

    /// Stop every sound currently playing.
    func stopAll() {
        for p in activePlayers { p.stop() }
        activePlayers.removeAll()
    }

    /// Read the global mute flag from UserDefaults.
    var isMuted: Bool {
        UserDefaults.standard.bool(forKey: Self.mutePreferenceKey)
    }

    /// Toggle the global mute flag (also stops everything currently playing).
    func setMuted(_ muted: Bool) {
        UserDefaults.standard.set(muted, forKey: Self.mutePreferenceKey)
        if muted { stopAll() }
    }

    // MARK: - Loading

    /// Eagerly load every .wav we ship so that the first server-triggered
    /// sound doesn't pay the file-IO cost mid-game.
    private func preloadAll() {
        let names = [
            "advance", "anvil", "chisel", "click", "closedoor", "coins",
            "combat1a", "combat1b", "combat2a", "combat2b", "combat3a", "combat3b",
            "cooking", "death", "dropobject", "eat", "filljug", "fish", "foundgem",
            "mechanical", "mine", "mix", "opendoor", "outofammo", "potato",
            "prayeroff", "prayeron", "prospect", "recharge", "retreat",
            "secretdoor", "shoot", "spellfail", "spellok", "takeobject",
            "underattack", "victory"
        ]
        for n in names {
            _ = loadSound(named: n)
        }
        print("[SoundManager] preloaded \(cache.count) of \(names.count) sounds")
    }

    /// Look up a sound by name in the bundle and cache the WAV bytes.
    @discardableResult
    private func loadSound(named name: String) -> Data? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            cache[name] = data
            return data
        } catch {
            print("[SoundManager] failed to read '\(name).wav': \(error)")
            return nil
        }
    }

    /// Configure the audio session for SFX playback that mixes with music
    /// from other apps (matches the unobtrusive feel of the desktop client).
    private func configureAudioSession() {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[SoundManager] AVAudioSession configure failed: \(error)")
        }
        #endif
    }

    // MARK: - Legacy archive (sounds.mem)

    /// TODO: parse `sounds.mem` if a server is ever observed sending sound
    /// names that aren't backed by a loose .wav. The format mirrors the
    /// Android `DataOperations` archive: `[count: short][per-entry: name(8 chars
    /// padded), offset(int), length(int)] then raw 8-bit unsigned PCM @ 8kHz
    /// (μ-law in some builds)`. Even the current Java desktop client reads the
    /// bytes and discards them, so this is purely a future-proofing hook.
    func unpackArchive(at url: URL) {
        // Intentionally unimplemented — see comment above.
        _ = url
    }
}

/// AVAudioPlayer requires an NSObject delegate; using a singleton keeps every
/// `play()` call lightweight (no per-call delegate object). It demuxes finish
/// callbacks back to per-player closures registered by `SoundManager`.
private final class SoundPlaybackObserver: NSObject, AVAudioPlayerDelegate {
    static let shared = SoundPlaybackObserver()

    private var callbacks: [ObjectIdentifier: (AVAudioPlayer) -> Void] = [:]
    private let lock = NSLock()

    func register(_ player: AVAudioPlayer, onFinish: @escaping (AVAudioPlayer) -> Void) {
        lock.lock()
        callbacks[ObjectIdentifier(player)] = onFinish
        lock.unlock()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        lock.lock()
        let cb = callbacks.removeValue(forKey: ObjectIdentifier(player))
        lock.unlock()
        Task { @MainActor in cb?(player) }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[SoundManager] decode error: \(error?.localizedDescription ?? "unknown")")
        lock.lock()
        let cb = callbacks.removeValue(forKey: ObjectIdentifier(player))
        lock.unlock()
        Task { @MainActor in cb?(player) }
    }
}
