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
	public let ui: InterfaceRenderer
	public var server: Server
	public private(set) var screen: Screen = .title
	public private(set) var focus: Field?
	public var username = ""
	public var password = ""
	public private(set) var status: (title: String, body: String) = ("", "")
	public private(set) var state = GameState()
	public private(set) var session: GameSession?
	public private(set) var lastSize = (w: 0, h: 0)
	private var frameCount = 0
	/// Called when a tap lands on something the client cannot handle yet.
	public var log: (String) -> Void = { _ in }
	/// Called once the server accepts the login (e.g. to save credentials).
	public var onLoggedIn: (_ username: String, _ password: String) -> Void = { _, _ in }

	/// Interface ids, looked up by name where the cache names them.
	let loginInterface: Int

	public init(store: ConfigStore, server: Server) throws {
		self.store = store
		self.server = server
		ui = InterfaceRenderer(store: store)
		loginInterface = try ui.interfaceId(named: "loginscreen") ?? 744
	}

	/// True while a text field has focus, so the shell shows a keyboard.
	public var wantsKeyboard: Bool { focus != nil }

	// MARK: frame

	public func frame(width: Int, height: Int) throws -> Raster {
		frameCount += 1
		lastSize = (width, height)
		if let s = session {
			for e in s.poll() { handle(e) }
		}
		var r = Raster(width: width, height: height)
		switch screen {
		case .title, .loginForm, .connecting:
			try ui.render(loginInterface, state: loginState(), into: &r)
		case .game:
			if state.interfaces.top != -1 {
				try ui.render(state.interfaces.top, state: state.interfaces, into: &r)
			}
			if let p12 = try store.font(named: "p12_full"), let w = state.selfWorld {
				p12.drawLeft("\(w.x), \(w.z)  tick \(state.ticks)", x: 6, y: 16, color: 0xFFFF00, shadow: 0, into: &r)
			}
		}
		return r
	}

	/// rt4 drives the login interface with CS2; until the interpreter lands,
	/// this sets the same components the scripts would.
	func loginState() -> InterfaceState {
		var s = InterfaceState()
		let id = { (c: Int) in self.loginInterface << 16 | c }
		s.hidden[id(131)] = false // parchment scroll
		switch screen {
		case .title:
			s.hidden[id(226)] = false // main menu
		default:
			s.hidden[id(241)] = false // "Please Log In"
			let cursor = frameCount / 20 % 2 == 0 ? "|" : ""
			s.text[id(340)] = username + (focus == .username ? cursor : "")
			s.text[id(346)] = String(repeating: "*", count: password.count) + (focus == .password ? cursor : "")
			s.text[id(333)] = status.title
			s.text[id(334)] = status.body
			if screen == .connecting {
				s.text[id(332)] = "Connecting to server..."
			}
		}
		return s
	}

	// MARK: input

	public func tap(x: Int, y: Int) {
		guard let c = ui.hitTest(x: x, y: y) else {
			if screen == .loginForm { focus = nil }
			return
		}
		let index = c.id & 0xFFFF
		if c.id >> 16 == loginInterface {
			switch (screen, index) {
			case (.title, 250): // Log In (Existing User)
				screen = .loginForm
				focus = .username
				status = ("", "")
			case (.loginForm, 336): focus = .username
			case (.loginForm, 342): focus = .password
			case (.loginForm, 347): submit()
			case (.loginForm, 348):
				screen = .title
				focus = nil
			default:
				log("login screen: component \(index) not wired yet")
			}
			return
		}
		log("tap on \(c.id >> 16):\(index) (\(c.ops.first ?? c.option ?? "no op"))")
	}

	public func type(_ text: String) {
		for ch in text {
			guard let f = focus else { return }
			if ch == "\n" || ch == "\r" { enter(); continue }
			switch f {
			case .username:
				// rt4 allows letters, digits, space and underscore, max 12.
				if username.count < 12, ch.isLetter || ch.isNumber || ch == " " || ch == "_" { username.append(ch) }
			case .password:
				if password.count < 20, ch.isASCII, !ch.isWhitespace { password.append(ch) }
			}
		}
	}

	public func backspace() {
		switch focus {
		case .username: if !username.isEmpty { username.removeLast() }
		case .password: if !password.isEmpty { password.removeLast() }
		case nil: break
		}
	}

	/// Return key: username -> password -> log in, like rt4.
	public func enter() {
		switch focus {
		case .username: focus = .password
		case .password: submit()
		case nil: break
		}
	}

	public func submit() {
		guard screen == .loginForm else { return }
		guard !username.isEmpty, !password.isEmpty else {
			status = ("", "Enter your username and password.")
			return
		}
		focus = nil
		screen = .connecting
		status = ("", "")
		var req = Login.Request(username: username, password: password)
		// Resizable mode: the server opens interface 746, which lays itself
		// out for whatever size we draw at.
		req.windowMode = 2
		req.canvasWidth = max(lastSize.w, 765)
		req.canvasHeight = max(lastSize.h, 503)
		state = GameState()
		let s = GameSession(host: server.host, port: server.port, request: req)
		session = s
		s.start()
	}

	public func logout() {
		session?.close()
		session = nil
		screen = .title
		state = GameState()
	}

	public func send(_ m: ClientMessage) { session?.send(m) }

	func handle(_ e: GameSession.Event) {
		state.apply(e)
		switch e {
		case .loggedIn:
			screen = .game
			onLoggedIn(username, password)
		case .disconnected(let reason):
			session = nil
			if screen == .game {
				screen = .title
			} else {
				screen = .loginForm
				status = ("Error connecting to server.", reason ?? "")
			}
		case .decodeFailed(let op, let err):
			log("decode failed for opcode \(op): \(err)")
		default:
			break
		}
	}
}
