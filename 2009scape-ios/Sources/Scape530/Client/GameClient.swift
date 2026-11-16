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

	/// True while a text field has focus, so the shell shows a keyboard.
	public var wantsKeyboard: Bool { focus != nil }

	// MARK: frame

	public func frame(width: Int, height: Int) throws -> Raster {
		lastSize = (width, height)
		host.resize(width: width, height: height)
		if let s = session {
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
		if inGame, worldTap(x: x, y: y) { return }
		if host.tap(x: x, y: y) == nil, inGame, let c = ui.hitTest(x: x, y: y) {
			log("tap on \(c.id >> 16):\(c.id & 0xFFFF) (\(c.ops.first ?? c.option ?? "no op"))")
		}
		host.cycle()
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
		session?.close()
		session = nil
		inGame = false
		let (u, p) = (username, password)
		host = InterfaceScriptHost(store: store)
		world = WorldView(store: store)
		viewport = nil
		interaction.reset()
		host.canvas = (lastSize.w > 0 ? lastSize.w : 765, lastSize.h > 0 ? lastSize.h : 503)
		bindHost()
		openLoginScreen()
		username = u
		password = p
	}

	public func send(_ m: ClientMessage) { session?.send(m) }

	func handle(_ e: GameSession.Event) {
		world.handle(e, varps: host.game.varps)
		if case .message(let m) = e { interaction.handle(m) }
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
