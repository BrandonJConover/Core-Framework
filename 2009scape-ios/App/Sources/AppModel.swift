import Foundation
import SwiftUI
import Scape530

/// App-level flow: make sure the cache is present and current, then hand a
/// `GameClient` to the game view. Server address lives in UserDefaults, the
/// last account in UserDefaults + Keychain.
@MainActor
final class AppModel: ObservableObject {
	enum Phase {
		case updatingCache(label: String, fraction: Double)
		case ready(GameClient)
		case failed(String)
	}

	@Published private(set) var phase: Phase = .updatingCache(label: "Connecting to update server", fraction: 0)
	@Published var host: String {
		didSet { UserDefaults.standard.set(host, forKey: "server.host") }
	}
	@Published var port: Int {
		didSet { UserDefaults.standard.set(port, forKey: "server.port") }
	}

	let cacheDirectory: URL
	/// Speaker output for the client's music and sound effects.
	private var audioOutput: AudioOutput?

	/// Brandon's home test server (the Linux machine on the LAN). Used until another address is saved;
	/// addresses of earlier test hosts (the Mac, the old default) are replaced by it.
	static let defaultHost = "192.168.0.223"
	static let defaultPort = 43595
	private static let retiredHosts: Set<String> = ["", "127.0.0.1", "192.168.0.12", "192.168.0.30"]

	init() {
		#if canImport(Network)
		// Game connections go through Network.framework (clear connect errors, hard timeout).
		GameConnection.transportFactory = NWTransport.factory()
		#endif
		let saved = UserDefaults.standard.string(forKey: "server.host") ?? ""
		let p = UserDefaults.standard.integer(forKey: "server.port")
		if Self.retiredHosts.contains(saved) {
			host = Self.defaultHost
			port = Self.defaultPort
		} else {
			host = saved
			port = p == 0 ? Self.defaultPort : p
		}
		let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		cacheDirectory = support.appendingPathComponent("cache530", isDirectory: true)
		start()
	}

	/// The running client's plugins, for the settings sheet; nil until the cache is open.
	var plugins: PluginManager? {
		if case .ready(let client) = phase { return client.plugins }
		return nil
	}

	/// False until the player has entered a server address.
	/// True once the cache is open and the client runs (title screen or game).
	var isReady: Bool { if case .ready = phase { return true } else { return false } }

	var hasConfiguredServer: Bool { !host.isEmpty }

	var hasLocalCache: Bool {
		FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent("main_file_cache.idx255").path)
	}

	/// Checks the cache against the server (downloading what changed), then
	/// opens it. With no server but an existing cache, it still starts.
	func start() {
		guard hasConfiguredServer else {
			phase = .failed("Enter the address of a 2009scape server to download the game.")
			return
		}
		phase = .updatingCache(label: "Connecting to update server", fraction: 0)
		let dir = cacheDirectory, host = host, port = port
		Task.detached(priority: .userInitiated) {
			var updateError: Error?
			do {
				let updater = CacheUpdater(directory: dir, host: host, port: port)
				try updater.run { p in
					let fraction = p.total == 0 ? 1 : Double(p.done) / Double(p.total)
					Task { @MainActor in
						self.phase = .updatingCache(label: "Loading archive \(p.archive) - \(Int(fraction * 100))%", fraction: fraction)
					}
				}
			} catch {
				updateError = error
			}
			// The saved password is protected by Face ID / Touch ID: unlock it here, off the main thread and before
			// the client starts, so it is never released without the owner.
			let user = UserDefaults.standard.string(forKey: "account.username") ?? ""
			let savedPassword = user.isEmpty ? nil : Keychain.unlockedPassword(for: user, prompt: "Unlock your 2009scape account")
			await self.openCache(updateError: updateError, savedPassword: savedPassword)
		}
	}

	private func openCache(updateError: Error?, savedPassword: String? = nil) {
		guard hasLocalCache else {
			phase = .failed(updateError.map { "\($0)" } ?? "Could not download the game from \(host):\(port).")
			return
		}
		do {
			let store = ConfigStore(disk: try DiskCache(directory: cacheDirectory))
			let client = try GameClient(store: store, server: .init(host: host, port: port))
			client.username = UserDefaults.standard.string(forKey: "account.username") ?? ""
			if !client.username.isEmpty, let savedPassword { client.password = savedPassword }
			client.onLoggedIn = { [weak client] user, pass in
				// Quest helper flags are saved per account.
				client?.plugins.plugin(ofType: QuestHelperPlugin.self)?.accountKey = user.lowercased()
				UserDefaults.standard.set(user, forKey: "account.username")
				Keychain.setPassword(pass, for: user)
			}
			client.log = { ClientLogFile.shared.write($0) }
			// Plugins: settings in UserDefaults, notifications (idle, low hitpoints) to the system.
			client.plugins.useSettingsStore(UserDefaultsPluginSettingsStore())
			client.plugins.onNotification = { PluginNotifier.shared.handle($0) }
			if client.plugins.isEnabled("idleNotifier") { PluginNotifier.shared.requestAuthorization() }
			audioOutput?.stop()
			let output = AudioOutput(mixer: client.audio)
			output.start()
			audioOutput = output
			phase = .ready(client)
		} catch {
			phase = .failed("The game cache could not be opened.\n\(error)")
		}
	}

	/// Backgrounding pauses audio (rendering pauses in the game view); coming back resumes it. A connection
	/// that died meanwhile is noticed by the session thread and rejoined by the client's reconnect logic.
	func scenePhaseChanged(_ phase: ScenePhase) {
		switch phase {
		case .background: audioOutput?.pause()
		case .active: audioOutput?.resume()
		default: break
		}
	}

	func applyServer(host: String, port: Int) {
		self.host = host
		self.port = port
		if case .ready(let client) = phase {
			client.server = .init(host: host, port: port)
		}
		start()
	}
}

/// The client's log lines (disconnect reasons, decode failures) in Documents/client.log, kept to the last ~256 KB,
/// so a session on the phone can be diagnosed afterwards (`xcrun devicectl device copy from --domain-type
/// appDataContainer`). Also sent to the unified log (NSLog).
final class ClientLogFile {
	static let shared = ClientLogFile()
	private let queue = DispatchQueue(label: "scape530.log", qos: .utility)
	private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("client.log")
	private let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f }()

	func write(_ line: String) {
		NSLog("[client] %@", line)
		let now = Date()
		queue.async { [self] in
			let text = "\(stamp.string(from: now)) \(line)\n"
			guard let data = text.data(using: .utf8) else { return }
			if let h = try? FileHandle(forWritingTo: url) {
				defer { try? h.close() }
				let size = (try? h.seekToEnd()) ?? 0
				if size > 256 * 1024, let old = try? Data(contentsOf: url) {
					try? Data(old.suffix(128 * 1024)).write(to: url)
					if let h2 = try? FileHandle(forWritingTo: url) { _ = try? h2.seekToEnd(); try? h2.write(contentsOf: data); try? h2.close() }
					return
				}
				try? h.write(contentsOf: data)
			} else {
				try? data.write(to: url)
			}
		}
	}
}
