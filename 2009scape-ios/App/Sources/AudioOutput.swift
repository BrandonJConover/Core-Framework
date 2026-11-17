import AVFoundation
import Scape530

/// Plays the client's mixed music and sound effects through the speaker. `AudioMixer`
/// renders interleaved 16 bit stereo at 22050 Hz (rt4's rate); an `AVAudioSourceNode`
/// pulls from it and converts to the engine's float format.
final class AudioOutput {
	private let engine = AVAudioEngine()
	private let mixer: AudioMixer
	private var pcm = [Int16](repeating: 0, count: 4096 * 2)

	private var observers: [NSObjectProtocol] = []
	private var wantsPlaying = false

	init(mixer: AudioMixer) {
		self.mixer = mixer
	}

	deinit { observers.forEach(NotificationCenter.default.removeObserver) }

	/// Phone calls, Siri and other apps interrupt the session; the engine stops and must be restarted after.
	/// Unplugging headphones also stops the engine's configuration, so it is restarted on route/config changes.
	private func observeSession() {
		guard observers.isEmpty else { return }
		let nc = NotificationCenter.default
		observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
			guard let self, let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
				let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
			switch type {
			case .began: self.engine.pause()
			case .ended: if self.wantsPlaying { self.resume() }
			@unknown default: break
			}
		})
		observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
			guard let self, self.wantsPlaying, !self.engine.isRunning else { return }
			self.resume()
		})
		observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
			guard let self, self.wantsPlaying else { return }
			self.resume()
		})
	}

	/// App went to the background: stop pulling audio.
	func pause() {
		wantsPlaying = false
		engine.pause()
	}

	/// App is active again (or an interruption ended).
	func resume() {
		wantsPlaying = true
		try? AVAudioSession.sharedInstance().setActive(true)
		if !engine.isRunning { try? engine.start() }
	}

	func start() {
		wantsPlaying = true
		observeSession()
		// Ambient: mixes with other apps' audio and honours the silent switch.
		try? AVAudioSession.sharedInstance().setCategory(.ambient)
		try? AVAudioSession.sharedInstance().setActive(true)
		guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioMixer.sampleRate), channels: 2, interleaved: false) else { return }
		let source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
			guard let self else { return noErr }
			let frames = Int(frameCount)
			self.mixer.render(into: &self.pcm, frames: frames)
			let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
			guard buffers.count >= 2,
				let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
				let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
			self.pcm.withUnsafeBufferPointer { p in
				for i in 0..<frames {
					left[i] = Float(p[i * 2]) / 32768
					right[i] = Float(p[i * 2 + 1]) / 32768
				}
			}
			return noErr
		}
		engine.attach(source)
		engine.connect(source, to: engine.mainMixerNode, format: format)
		do {
			try engine.start()
		} catch {
			print("[audio] engine failed to start: \(error)")
		}
	}

	func stop() {
		wantsPlaying = false
		engine.stop()
	}
}
