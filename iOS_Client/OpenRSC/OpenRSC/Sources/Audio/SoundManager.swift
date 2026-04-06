import AVFoundation
import UIKit

/// Sound manager for playing game audio.
/// Uses AVAudioEngine for low-latency playback.
final class SoundManager: @unchecked Sendable {
    static let shared = SoundManager()

    private let audioEngine = AVAudioEngine()
    private var soundBuffers: [Int: AVAudioPCMBuffer] = [:]
    private var playerNodes: [AVAudioPlayerNode] = []
    private let maxConcurrentSounds = 8
    private var currentNodeIndex = 0
    private let queue = DispatchQueue(label: "com.openrsc.sound", qos: .userInteractive)

    /// Common game sounds
    enum Sound: Int {
        case click = 0
        case walk = 1
        case hit = 2
        case block = 3
        case death = 4
        case levelUp = 5
        case itemPickup = 6
        case itemDrop = 7
        case eat = 8
        case drink = 9
        case teleport = 10
        case magic = 11
        case prayer = 12
        case anvil = 13
        case mine = 14
        case chop = 15
        case fish = 16
        case fire = 17
        case cook = 18
        case openDoor = 19
        case closeDoor = 20
        case privateMessage = 21
        case questComplete = 22
    }

    private init() {
        setupAudioSession()
        setupPlayerNodes()
        preloadCommonSounds()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func setupPlayerNodes() {
        let mainMixer = audioEngine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)

        for _ in 0..<maxConcurrentSounds {
            let playerNode = AVAudioPlayerNode()
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: mainMixer, format: format)
            playerNodes.append(playerNode)
        }

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func preloadCommonSounds() {
        // Preload frequently used sounds
        let commonSounds: [Sound] = [.click, .walk, .hit, .itemPickup, .levelUp]
        for sound in commonSounds {
            _ = loadSound(id: sound.rawValue)
        }
    }

    private func loadSound(id: Int) -> AVAudioPCMBuffer? {
        if let buffer = soundBuffers[id] {
            return buffer
        }

        // Try to load from bundle
        let soundName = "sound_\(id)"
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "wav") else {
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else { return nil }

            try file.read(into: buffer)
            soundBuffers[id] = buffer
            return buffer
        } catch {
            print("Failed to load sound \(id): \(error)")
            return nil
        }
    }

    /// Play a sound by enum.
    func play(_ sound: Sound) async {
        await playById(sound.rawValue)
    }

    /// Play a sound by name.
    func playByName(_ name: String) async {
        // TODO: implement name-based sound lookup
        print("playByName: \(name)")
    }

    /// Play a sound by server ID.
    func playById(_ soundId: Int) async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.playSound(id: soundId)
                continuation.resume()
            }
        }
    }

    private func playSound(id: Int) {
        guard let buffer = loadSound(id: id) else {
            // Generate a simple beep for missing sounds
            playGeneratedBeep()
            return
        }

        let playerNode = playerNodes[currentNodeIndex]
        currentNodeIndex = (currentNodeIndex + 1) % maxConcurrentSounds

        if playerNode.isPlaying {
            playerNode.stop()
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()
    }

    private func playGeneratedBeep() {
        // Generate a simple sine wave beep for missing sounds
        let sampleRate: Double = 44100
        let duration: Double = 0.1
        let frequency: Double = 440

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let sample = sin(2.0 * Double.pi * frequency * Double(i) / sampleRate)
            data[i] = Float(sample * 0.3) // Reduce volume
        }

        let playerNode = playerNodes[currentNodeIndex]
        currentNodeIndex = (currentNodeIndex + 1) % maxConcurrentSounds

        if playerNode.isPlaying {
            playerNode.stop()
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()
    }

    /// Set master volume (0.0 to 1.0).
    func setVolume(_ volume: Float) {
        audioEngine.mainMixerNode.outputVolume = max(0, min(1, volume))
    }

    /// Mute/unmute all sounds.
    func setMuted(_ muted: Bool) {
        audioEngine.mainMixerNode.outputVolume = muted ? 0 : 1
    }

    /// Stop all currently playing sounds.
    func stopAll() {
        for playerNode in playerNodes {
            playerNode.stop()
        }
    }

    /// Pause audio engine (for backgrounding).
    func pause() {
        audioEngine.pause()
    }

    /// Resume audio engine.
    func resume() {
        do {
            try audioEngine.start()
        } catch {
            print("Failed to resume audio engine: \(error)")
        }
    }
}
