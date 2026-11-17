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
			await self.openCache(updateError: updateError)
		}
	}

	private func openCache(updateError: Error?) {
		guard hasLocalCache else {
			phase = .failed(updateError.map { "\($0)" } ?? "Could not download the game from \(host):\(port).")
			return
		}
		do {
			let store = ConfigStore(disk: try DiskCache(directory: cacheDirectory))
			let client = try GameClient(store: store, server: .init(host: host, port: port))
			client.username = UserDefaults.standard.string(forKey: "account.username") ?? ""
			if !client.username.isEmpty { client.password = Keychain.password(for: client.username) ?? "" }
			client.onLoggedIn = { user, pass in
				UserDefaults.standard.set(user, forKey: "account.username")
				Keychain.setPassword(pass, for: user)
			}
			client.log = { print("[client] \($0)") }
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
