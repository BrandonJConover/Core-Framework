import Foundation

/// The whole client minus the platform: owns the cache-backed renderers, the
/// screen flow (title -> login form -> game) and the live session. A platform
/// shell calls `frame(width:height:)` every display refresh, blits the
/// returned raster, and forwards taps and typed text. Coordinates are in game
/// pixels; the shell picks the game-pixel size for the device (resizable mode
/// makes any size work).
public final class GameClient {
	public enum Screen: Equatable {
		case title, loginForm, connecting, game
	}

	public enum Field { case username, password }

	public struct Server: Equatable {
		public var host: String
		public var port: Int
		public init(host: String, port: Int) { self.host = host; self.port = port }
	}

	public let store: ConfigStore
	/// The CS2 host: owns game state and interface state, runs hooks.
	public private(set) var host: InterfaceScriptHost
	public var ui: InterfaceRenderer { host.renderer }
	public var server: Server
	public private(set) var session: GameSession?
	/// The 3D world drawn behind the interfaces while in game (rt4 scene + camera + actors).
	public private(set) var world: WorldView
	/// Music and sound effects (rt4 `MusicPlayer`/`SoundPlayer`). The iOS layer pulls PCM from
	/// `audio.render(into:frames:)` on its audio thread; everything here only queues work.
	public private(set) lazy var audio = AudioMixer(store: store.isolatedCopy() ?? store)
	/// Song/jingle decoding takes a moment (instruments and samples), so it runs off the frame thread.
	private let audioLoader = DispatchQueue(label: "scape530.audio-loader")
	/// The 3D viewport component's rectangle from the last frame (rt4 `Component.clientCode == 1337`).
	public private(set) var viewport: (x: Int, y: Int, w: Int, h: Int)?
	public private(set) var lastSize = (w: 0, h: 0)
	/// Touch interaction with the world: open menu, click cross, player options.
	public let interaction = WorldInteraction()
	private var inGame = false
	private var lastCycleAt: Date?
	/// Called when a tap lands on something the client cannot handle yet.
	public var log: (String) -> Void = { _ in }
	/// Called once the server accepts the login (e.g. to save credentials).
	public var onLoggedIn: (_ username: String, _ password: String) -> Void = { _, _ in }

	/// The login interface (rt4 `LoginManager.loginScreenId`), looked up by name.
	let loginInterface: Int

	/// CS2 variables the 2009 login interface keeps its state in: the typed
	/// username and password, and the stage (0 main menu, 1 username field,
	/// 2 password field).
	enum LoginVar {
		static let username = 32, password = 33
		static let stage = 174
	}

	public init(store: ConfigStore, server: Server) throws {
		self.store = store
		self.server = server
		let probe = InterfaceRenderer(store: store)
		loginInterface = try probe.interfaceId(named: "loginscreen") ?? 744
		host = InterfaceScriptHost(store: store)
		world = WorldView(store: store)
		bindHost()
		openLoginScreen()
	}

	private func bindHost() {
		host.send = { [weak self] in self?.send($0) }
		host.onDirectLogin = { [weak self] user, pass in self?.beginLogin(username: user, password: pass) }
		host.log = { [weak self] in self?.log($0) }
		bindWorld()
	}

	/// Wires the world's chat callbacks to the host's chat history (`Chat/`).
	private func bindWorld() {
		world.onPublicChat = { [weak self] e in
			guard let self else { return }
			self.host.game.chatLog.add(type: e.line.type, name: e.line.name, message: e.line.message, clan: e.line.clan, phraseId: e.line.phraseId)
			self.host.chatAt = self.host.transmitTimer
		}
		world.onSoundArea = { [weak self] id, x, z, radius, loops, delay in
			guard let self, let me = self.world.selfSceneTile else { return }
			self.audio.effects.playArea(id: id, x: x, z: z, radius: radius, loops: loops, delay: delay, playerTileX: me.x, playerTileZ: me.z)
		}
		world.isChatIgnored = { [weak self] name37, rights in
			guard let self else { return false }
			return rights <= 1 && self.chatRestricted(name37)
		}
	}

	/// rt4 ignore rules for incoming chat from ordinary players: under-13 and quick-chat-only accounts
	/// hear no typed chat, everyone else drops names on the ignore list.
	func chatRestricted(_ name37: Int64) -> Bool {
		if let a = host.game.account, (a.underage && !a.parentalChatConsent) || a.mapQuickChat { return true }
		return host.game.ignored.contains(name37)
	}

	/// rt4 `InterfaceList.method1596`: the login interface becomes the top level
	/// and its onLoad scripts build the screen.
	private func openLoginScreen() {
		host.apply(.ifOpenTop(id: loginInterface, reset: 0))
	}

	// MARK: derived screen state

	public var screen: Screen {
		if inGame { return .game }
		if host.loginReply == -3 { return .connecting }
		return host.varc(LoginVar.stage) == 0 ? .title : .loginForm
	}

	public var focus: Field? {
		guard screen == .loginForm else { return nil }
		return host.varc(LoginVar.stage) == 2 ? .password : .username
	}

	/// The text in the login form, kept by the interface scripts in varcstrs.
	public var username: String {
		get { host.varcstr(LoginVar.username) }
		set { host.setVarcstr(LoginVar.username, newValue) }
	}
	public var password: String {
		get { host.varcstr(LoginVar.password) }
		set { host.setVarcstr(LoginVar.password, newValue) }
	}

	/// The login error the interface is showing, as text.
	public var status: (title: String, body: String) {
		let r = Int(host.loginReply)
		return r > 2 || r == -5 ? ("", r == -5 ? "Error connecting to server." : Login.message(for: r)) : ("", "")
	}

	public var state: GameState { host.game }

	/// True while a text field has focus, or in game while the player asked to type into the chatbox
	/// (tap the chat input, or `toggleKeyboard()`), so the shell shows a keyboard.
	public var wantsKeyboard: Bool { focus != nil || (screen == .game && keyboardRequested) }

	/// In-game typing: set when a tap lands on the chatbox, cleared by a tap on the world.
	public var keyboardRequested = false

	/// Shows or hides the keyboard in game (for a button in the shell).
	public func toggleKeyboard() { keyboardRequested.toggle() }

	// MARK: frame

	/// Draws one frame at `width` x `height` game pixels. rt4's resizable interface assumes a canvas of at
	/// least 765x503; shells below that (phones) should pick a larger game size and scale the result down
	/// (`App/Sources/GameView.swift` does: `scale = max(1, 503 / h, 765 / w)`) instead of asking for a smaller canvas.
	public func frame(width: Int, height: Int) throws -> Raster {
		lastSize = (width, height)
		host.resize(width: width, height: height)
		world.publicFilter = host.game.chatFilters.public
		if let s = session {
			// A live session builds each region's scene in the background (recorded events fed to `handle` do not).
			world.asyncBuild = true
			for e in s.poll() { handle(e) }
		}
		// One client cycle is 20 ms; always run at least one so scripts and
		// timers advance on every frame, and never more than a few after a stall.
		let now = Date()
		let cycles = lastCycleAt.map { min(max(Int(now.timeIntervalSince($0) / 0.02), 1), 5) } ?? 1
		lastCycleAt = lastCycleAt.map { $0.addingTimeInterval(Double(cycles) * 0.02) } ?? now
		for _ in 0..<cycles {
			host.cycle()
			if inGame { world.cycle(varps: host.game.varps); interaction.cycle() }
		}
		if inGame { updateAudio() }
		var r = Raster(width: width, height: height)
		let top = host.game.interfaces.top
		let showInterface = top != -1 && !(inGame && top == loginInterface)
		// The world is drawn first, inside the viewport component found while laying out the interface
		// (the previous frame's rectangle; a changed rectangle repeats the frame once).
		for pass in 0..<2 {
			let drawnViewport = inGame && drawWorld(into: &r, width: width, height: height)
			if showInterface { try ui.render(top, state: host.game.interfaces, into: &r) }
			let found = showInterface ? ui.drawn.first(where: { $0.component.clientCode == 1337 }).map { (x: $0.x, y: $0.y, w: $0.w, h: $0.h) } : nil
			let changed = found.map { f in viewport.map { $0 != f } ?? true } ?? false
			if let f = found { viewport = f }
			if !(changed && drawnViewport) || pass == 1 { break }
			r = Raster(width: width, height: height)
		}
		if inGame && showInterface { world.drawMinimap(drawn: ui.drawn, into: &r) } // Minimap/
		if inGame { try drawInteraction(into: &r) }
		if inGame, let p12 = try store.font(named: "p12_full"), let w = host.game.selfWorld {
			p12.drawLeft("\(w.x), \(w.z)  tick \(host.game.ticks)", x: 6, y: 16, color: 0xFFFF00, shadow: 0, into: &r)
		}
		return r
	}

	/// Draws the 3D world into the viewport (the whole raster until the interface has told us where it is).
	private func drawWorld(into r: inout Raster, width: Int, height: Int) -> Bool {
		let v = viewport.flatMap { $0.x + $0.w <= width && $0.y + $0.h <= height ? $0 : nil } ?? (x: 0, y: 0, w: width, h: height)
		return world.draw(into: &r, rect: v)
	}

	// MARK: camera (rt4 Camera: yawTarget / pitchTarget / ZOOM)

	/// One-finger drag over the world, in game pixels: horizontal turns the camera, vertical tilts it.
	public func cameraDrag(dx: Double, dy: Double) { world.camera.drag(dx: dx, dy: dy) }

	/// Pinch gesture: `scale` > 1 zooms in, < 1 out (use the change since the last callback).
	public func cameraPinch(scale: Double) { world.camera.pinch(scale: scale) }

	/// Back to rt4's default zoom, facing north.
	public func cameraReset() {
		world.camera.zoom = WorldCamera.defaultZoom
		world.camera.pitchTarget = 128
		world.camera.yawTarget = 0
	}

	/// True when a drag starting at (x, y) belongs to the camera: inside the world viewport and not
	/// on an interactive interface component.
	public func isOverWorld(x: Int, y: Int) -> Bool {
		guard inGame, !interaction.isMenuOpen, let v = viewport else { return false }
		return x >= v.x && y >= v.y && x < v.x + v.w && y < v.y + v.h && ui.hitTest(x: x, y: y) == nil
	}

	// MARK: input

	/// A tap in game pixels: press and release of the primary button.
	public func tap(x: Int, y: Int) {
		if inGame, worldTap(x: x, y: y) { keyboardRequested = false; return }
		let hit = inGame ? ui.hitTest(x: x, y: y) : nil
		if host.tap(x: x, y: y) == nil, inGame, let c = hit {
			log("tap on \(c.id >> 16):\(c.id & 0xFFFF) (\(c.ops.first ?? c.option ?? "no op"))")
		}
		if inGame { keyboardRequested = hit.map(takesTyping) ?? false }
		host.cycle()
	}

	/// True for components that read typed keys: the chat input (rt4 interface 137 / its resizable
	/// counterparts) or anything with an `onKey` hook.
	func takesTyping(_ c: Component) -> Bool {
		c.hooks["onKey"] != nil || (c.id >> 16) == 137
	}

	/// Pointer hover (mouse or Apple Pencil hover); drives onMouseOver/Leave.
	public func hover(x: Int, y: Int) {
		interaction.pointer = (x, y)
		host.pointerMoved(x: x, y: y)
	}

	/// Typed characters, one client cycle each so the scripts see them in
	/// order. rt4 queues printable keys as (code -1, char) and Enter as code 84.
	public func type(_ text: String) {
		for ch in text.unicodeScalars {
			if ch == "\n" || ch == "\r" {
				host.key(code: 84, char: -1)
			} else if ch == "\u{20AC}" {
				host.key(code: -1, char: 128)
			} else if ch.value > 0 && ch.value < 256 {
				host.key(code: -1, char: Int(ch.value))
			} else {
				continue
			}
			host.cycle()
		}
	}

	public func backspace() {
		host.key(code: 85, char: -1)
		host.cycle()
	}

	/// Return key: the login scripts move username -> password -> log in.
	public func enter() {
		host.key(code: 84, char: -1)
		host.cycle()
	}

	/// Presses the Log In button of the form.
	public func submit() {
		guard screen == .loginForm else { return }
		let id = loginInterface << 16 | 347
		if let d = ui.drawn.last(where: { $0.component.id == id }) { tap(x: d.x + d.w / 2, y: d.y + d.h / 2) }
	}

	// MARK: session

	/// CS2 `directlogin` (opcode 5600): start connecting. rt4 sets the reply to
	/// -3 ("connecting") and the scripts show it until a result arrives.
	func beginLogin(username: String, password: String) {
		guard session == nil else { return }
		host.loginReply = -3
		var req = Login.Request(username: username, password: password)
		// Resizable mode: the server opens interface 746, which lays itself
		// out for whatever size we draw at.
		req.windowMode = 2
		req.canvasWidth = max(lastSize.w, 765)
		req.canvasHeight = max(lastSize.h, 503)
		let s = GameSession(host: server.host, port: server.port, request: req)
		session = s
		s.start()
	}

	public func logout() {
		let music = audio.music
		audioLoader.async { music.stop() }
		audio.effects.clear()
		session?.close()
		session = nil
		inGame = false
		let (u, p) = (username, password)
		host = InterfaceScriptHost(store: store)
		world = WorldView(store: store)
		keyboardRequested = false
		viewport = nil
		interaction.reset()
		host.canvas = (lastSize.w > 0 ? lastSize.w : 765, lastSize.h > 0 ? lastSize.h : 503)
		bindHost()
		openLoginScreen()
		username = u
		password = p
	}

	public func send(_ m: ClientMessage) { session?.send(m) }

	/// rt4 `Protocol` MIDI_SONG / MIDI_JINGLE / SYNTH_SOUND.
	private func playAudio(_ m: ServerMessage) {
		switch m {
		case .midiSong(let id):
			let music = audio.music
			audioLoader.async { music.play(songId: id) }
		case let .midiJingle(id, _):
			let music = audio.music
			audioLoader.async { music.playJingle(id: id) }
		case let .synthSound(id, loops, delay):
			audio.effects.play(id: id, loops: loops, delay: delay)
		default:
			break
		}
	}

	/// Per frame: keep the listener on the player and report finished songs (rt4 `SoundPlayer` SOUND_SONGEND).
	private func updateAudio() {
		if let me = world.selfActorFine { audio.effects.setListener(xFine: me.x, zFine: me.z) }
		if let ended = audio.music.takeSongEnded(), ended >= 0 { send(.songEnd(ended)) }
	}

	/// Private messages (rt4 `Protocol` MESSAGE_PRIVATE / MESSAGE_PRIVATE_ECHO): huffman-decoded into the chat history.
	private func receiveChat(_ m: ServerMessage) {
		switch m {
		case let .privateMessage(name37, messageId, rights, text):
			guard let codec = (try? WordPack.loadCodec(store)) ?? nil else { return }
			if host.game.chatLog.hasSeen(messageId: messageId) { return }
			if rights <= 1 && chatRestricted(name37) { return }
			_ = host.game.chatLog.remember(messageId: messageId)
			let message = WordPack.display(WordPack.decode(text, codec: codec))
			let name = WordPack.displayName(name37)
			if rights != 0 {
				host.game.chatLog.add(type: 7, name: WordPack.chatIcon(rights: rights) + name, message: message)
			} else {
				host.game.chatLog.add(type: 3, name: name, message: message)
			}
			host.chatAt = host.transmitTimer
		case let .privateMessageEcho(name37, text):
			guard let codec = (try? WordPack.loadCodec(store)) ?? nil else { return }
			host.game.chatLog.add(type: 6, name: WordPack.displayName(name37), message: WordPack.display(WordPack.decode(text, codec: codec)))
			host.chatAt = host.transmitTimer
		default:
			break
		}
	}

	func handle(_ e: GameSession.Event) {
		world.handle(e, varps: host.game.varps)
		if case .message(let m) = e { interaction.handle(m); receiveChat(m); playAudio(m) }
		switch e {
		case .loggedIn:
			host.apply(e)
			host.loginReply = 2
			inGame = true
			onLoggedIn(username, password)
		case .loginFailed(let reply):
			session = nil
			switch reply {
			case .failure(let code): host.loginReply = Int32(code)
			case .hopDelay: host.loginReply = 21
			case .disallowed(let r): host.loginReply = 29; host.loginDisallowResult = Int32(r)
			case .retry, .success: host.loginReply = -5
			}
		case .disconnected(let reason):
			session = nil
			if inGame {
				log("disconnected: \(reason ?? "closed")")
				logout()
			} else {
				host.loginReply = -5
			}
		case .decodeFailed(let op, let err):
			log("decode failed for opcode \(op): \(err)")
		default:
			host.apply(e)
		}
	}
}
