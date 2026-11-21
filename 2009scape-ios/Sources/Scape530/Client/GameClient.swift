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
	public private(set) lazy var audio: AudioMixer = {
		// Audio reads the cache from other threads, so it needs its own store. A store that cannot be
		// copied (not disk-backed, as in tests) is shared, and then songs load on the calling thread.
		if let copy = store.isolatedCopy() { return AudioMixer(store: copy) }
		audioSharesStore = true
		return AudioMixer(store: store)
	}()
	private var audioSharesStore = false
	private var areaResolverBound = false
	private var lastAreaLoop = 0
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

	/// Called when the server asks the client to open a web page (rt4 `URL_OPEN`).
	public var onOpenURL: (String) -> Void = { _ in }

	/// Why the last connection attempt failed ("Can't reach host:port (...)"), for the shell to show. Cleared on the next login.
	public private(set) var connectError: String?
	/// Non-zero while a dropped game connection is being re-established (rt4 reconnect login, opcode 18).
	public private(set) var reconnectAttempt = 0
	public var maxReconnectAttempts = 4
	/// Whether the app is in the foreground (rt4 `GameShell.focus`). The shell sets it from the scene phase through
	/// `setApplicationFocus(_:)`; the change reaches the server as EVENT_APPLET_FOCUS.
	public private(set) var hasFocus = true
	private var sentFocus = true
	private var sentCamera: (pitch: Int, yaw: Int)?
	private var cameraCooldown = 0
	private var sentWindow: (w: Int, h: Int)?
	private var lastRequest: Login.Request?
	/// rt4 `Protocol.verifyId` of the session that just ended, re-sent by the reconnect login.
	private var lastVerifyId = 0
	/// rt4 `Player.worldId`: the world the next login goes to. Survives a logout (the host is rebuilt).
	public private(set) var currentWorldId: Int32 = 1
	/// The lobby's world list (CS2 6500-6507), fetched from the game server; see `Net/WorldList.swift`.
	public let worldList = WorldList()
	private var worldListSettled = false
	/// Mobile UI: tapping an inventory item runs its "Drop" option (like shift-drop).
	public var tapToDrop = false
	/// Draws the player's tile and the server tick in the top-left corner (developer aid).
	public var showDebugInfo = false
	/// False when the shell draws the world menu itself (`popupRows` / `chooseMenuEntry`).
	public var drawsClassicMenu = true
	/// Toggleable plugins (overlays, menu swaps, trackers); see `Plugins/`.
	public let plugins = PluginManager()

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
		worldList.endpoint = { [weak self] in self.map { ($0.server.host, $0.server.port) } ?? ("127.0.0.1", 43595) }
		bindHost()
		openLoginScreen()
		plugins.attach(self) // Plugins/
		_ = worldList.fetch() // rt4 loads the world list during start-up (`mainLoadState` 135)
	}

	private func bindHost() {
		host.worldId = currentWorldId
		// rt4 starts with `lastWorldId` 0 and the login screen then asks for a world first; this client has the
		// world of its server configuration, so the login screen goes straight to the form.
		if host.prefs.lastWorldId == 0 { host.prefs.lastWorldId = Int(currentWorldId) }
		host.worldList = worldList
		worldList.fallbackWorldId = Int(currentWorldId)
		host.onWorldHop = { [weak self] w in self?.hopWorld(w) ?? false }
		host.onSkipLoginStage = { [weak self] in self?.session?.skipLoginStage() }
		host.send = { [weak self] in self?.send($0) }
		host.onDirectLogin = { [weak self] user, pass in self?.beginLogin(username: user, password: pass) }
		host.log = { [weak self] in self?.log($0) }
		host.onPreferenceChange = { [weak self] in self?.applyPreference($0) }
		bindClientOps()
		host.onPreferencesWritten = { [weak self] in self?.onPreferencesChanged?() }
		host.onVarpClientCode = { [weak self] code, value in
			if code == VarpClientCode.chatEffects { self?.world.chatEffectsDisabled = value != 0 }
		}
		bindWorld()
		bindModels()
	}

	/// Applies an Options-tab change the way rt4's `ScriptRunner` ops 6001-6020 do: volumes go to the audio
	/// players (`MusicPlayer`/`SoundEffectPlayer`), brightness to every software rasteriser.
	func applyPreference(_ change: ClientPreferences.Change) {
		switch change {
		case .brightness(let gamma):
			world.brightness = gamma
			ui.models.brightness = gamma
			ui.icons.setBrightness(gamma)
		case let .musicVolume(old, new):
			// rt4: from silence the current song restarts; to silence it stops (the song id is kept).
			let music = audio.music
			let song = music.currentSongId
			music.volume = new
			if old == 0, song != -1 {
				if audioSharesStore { music.play(songId: song) } else { audioLoader.async { music.play(songId: song) } }
			} else if new == 0 {
				music.stop()
				music.play(songId: song)
			}
		case .soundEffectVolume(let v): audio.effects.effectVolume = v
		case .ambientVolume(let v): audio.effects.ambientVolume = v
		case .scene: applySceneOptions()
		case .stored: break
		}
	}

	/// rt4 `ScriptRunner` 6002 / 6003 / 6005 / 6009 / 6021: roof mode (`method4047`), all-levels, ground decorations
	/// and ground textures reach the world; changed build options rebuild the scene (`method2742`).
	func applySceneOptions() {
		let p = host.prefs
		// rt4 mode 0 (op 6021, `neverRemoveRoofs`) is set by the Tutorial Island scripts; drawing every level there
		// leaves this port's camera under the upper level's floor, so until that is matched it keeps the selective
		// mode (the behaviour players saw). Tracked in PARITY.md.
		if neverRemoveRoofs && Self.honoursNeverRemoveRoofs { world.roofMode = .never }
		else if p.allLevelsVisible { world.roofMode = p.removeRoofsSelectively ? .selective : .always }
		else { world.roofMode = .always }
		var o = WorldView.SceneOptions()
		o.allLevelsVisible = p.allLevelsVisible
		o.showGroundDecorations = p.showGroundDecorations
		o.manyGroundTextures = p.manyGroundTextures
		world.applySceneOptions(o)
	}

	/// Pushes every stored preference to the systems it drives (after `preferencesData` was set or a new login).
	func applyAllPreferences() {
		let p = host.prefs
		if let g = ClientPreferences.gamma(forBrightness: p.brightness) { applyPreference(.brightness(gamma: g)) }
		audio.music.volume = p.musicVolume
		audio.effects.effectVolume = p.soundEffectVolume
		audio.effects.ambientVolume = p.ambientSoundsVolume
		applySceneOptions()
	}

	/// rt4 `Preferences.encode` / `decode` as the persisted "runescape" preferences record. The shell stores it
	/// (e.g. in UserDefaults) and sets it on launch; reading gives the current settings.
	public var preferencesData: Data {
		get { Data(host.prefs.encode()) }
		set {
			var p = host.prefs
			p.decode([UInt8](newValue))
			host.prefs = p
			applyAllPreferences()
		}
	}

	/// Called after any Options-tab setting changed (rt4 `Preferences.write`): store `preferencesData`.
	public var onPreferencesChanged: (() -> Void)?
	/// Off until the all-levels camera matches rt4 (see `applySceneOptions`).
	nonisolated(unsafe) static var honoursNeverRemoveRoofs = false
	/// rt4 `ScriptRunner.neverRemoveRoofs` (op 6021): not persisted.
	var neverRemoveRoofs: Bool { host.prefs.neverRemoveRoofs }

	/// Gives the interface model renderer (chat heads, player models) its view of the world.
	private func bindModels() {
		host.cameraOp = { [weak self] name, args in self?.world.cameraScript(name, args) }
		ui.models.selfLook = { [weak self] in self?.world.selfLook }
		ui.models.playerLook = { [weak self] i in self?.world.ctx.players[i]?.appearance.map(PlayerLook.init) }
		ui.models.resolveNpc = { [weak self] t in
			guard let self, let list = t.multiNpcs, !list.isEmpty else { return t }
			let v = self.world.env.value(varbit: t.multiVarbit, varp: t.multiVarp, store: self.store)
			let pick = (v < 0 || v >= list.count - 1 || list[v] == -1) ? list[list.count - 1] : list[v]
			return pick == -1 ? nil : ((try? self.store.npc(pick)) ?? nil)
		}
	}

	/// Wires the world's chat callbacks to the host's chat history (`Chat/`).
	private func bindWorld() {
		world.onPublicChat = { [weak self] e in
			guard let self else { return }
			self.host.game.chatLog.add(type: e.line.type, name: e.line.name, message: e.line.message, clan: e.line.clan, phraseId: e.line.phraseId)
			self.host.chatAt = self.host.transmitTimer
		}
		world.onSeqFrameSound = { [weak self] seq, i, x, z, me in self?.audio.effects.playSeq(seq, index: i, xFine: x, zFine: z, isSelf: me) }
		world.onSoundArea = { [weak self] id, x, z, radius, loops, delay in
			guard let self, let me = self.world.selfSceneTile else { return }
			self.audio.effects.playArea(id: id, x: x, z: z, radius: radius, loops: loops, delay: delay, playerTileX: me.x, playerTileZ: me.z)
		}
		// rt4 `AreaSoundManager`: ambient loops from locs placed in the scene.
		world.onSceneAdopted = { [weak self] in self?.audio.effects.area.clearLocs() }
		world.onLocPlaced = { [weak self] p in
			guard let self, AreaSoundManager.hasAreaSound(p.loc, store: self.store) else { return }
			self.audio.effects.area.addLoc(p.loc, x: p.x, z: p.z, level: p.level, width: p.width, length: p.length)
		}
		world.onLocRemoved = { [weak self] loc, x, z, level in
			guard let self, AreaSoundManager.hasAreaSound(loc, store: self.store) else { return }
			self.audio.effects.area.removeLoc(id: loc.id, x: x, z: z, level: level)
		}
		world.isQuickChatIgnored = { [weak self] name37 in self?.host.game.ignored.contains(name37) ?? false }
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
		switch r {
		case 21: return ("", Login.message(forHopDelay: Int(host.worldSwitchTimer)))
		case 29: return ("", Login.message(forDisallow: Int(host.loginDisallowResult)))
		case 3...: return ("", Login.message(for: r))
		case -1, -4, -5: return ("", Login.message(for: r))
		default: return ("", "")
		}
	}

	public var state: GameState { host.game }

	/// True while a text field has focus, or in game while the player asked to type into the chatbox
	/// (tap the chat input, or `toggleKeyboard()`), so the shell shows a keyboard.
	public var wantsKeyboard: Bool { focus != nil || (screen == .game && keyboardRequested) }

	/// In-game typing: set when a tap lands on the chatbox, cleared by a tap on the world.
	public var keyboardRequested = false

	/// Set by the shell: asked for the saved password of an account (e.g. behind Face ID) when the player presses
	/// Log In with the password field empty. The completion must run on the thread that drives this client.
	public var savedPasswordProvider: ((String, @escaping (String?) -> Void) -> Void)?
	/// Set by the shell: a Face ID-protected password is saved for the typed username, so the login form shows an
	/// RS-styled "Use Face ID" link beside Log In.
	public var faceIDAvailable = false
	/// Where the "Use Face ID" link was drawn last frame (game pixels).
	private var faceIDLink: (x: Int, y: Int, w: Int, h: Int)?

	/// Mobile login: the rectangle (game pixels) the shell should zoom onto. With the keyboard up, the Username and
	/// Password fields and the Log In line; otherwise the logo and scroll. Nil off the login screens.
	public func loginFocusRect(keyboard: Bool) -> (x: Int, y: Int, w: Int, h: Int)? {
		guard !inGame, host.game.interfaces.top == loginInterface else { return nil }
		var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
		let form = (loginInterface << 16 | 335)...(loginInterface << 16 | 347)
		for d in ui.drawn where d.component.id >> 16 == loginInterface && d.w > 0 && d.h > 0 {
			if keyboard && screen == .loginForm {
				guard form.contains(d.component.id) else { continue }
			} else if d.component.type == 0 || d.w >= lastSize.w * 9 / 10 || d.h >= lastSize.h * 9 / 10 {
				continue // layers and the full-screen background
			}
			minX = min(minX, d.x); minY = min(minY, d.y); maxX = max(maxX, d.x + d.w); maxY = max(maxY, d.y + d.h)
		}
		if let l = faceIDLink, keyboard { minX = min(minX, l.x); maxX = max(maxX, l.x + l.w) }
		guard minX < maxX, minY < maxY else { return nil }
		return (minX, minY, maxX - minX, maxY - minY)
	}

	/// Draws the "Use Face ID" link to the right of the form's Log In (same font and colour as Log In).
	private func drawFaceIDLink(into r: inout Raster) {
		faceIDLink = nil
		guard screen == .loginForm, faceIDAvailable, savedPasswordProvider != nil,
		      let login = ui.drawn.last(where: { $0.component.id == loginInterface << 16 | 347 }),
		      let font = try? store.font(591) else { return }
		let text = "Use Face ID"
		let w = font.stringWidth(text)
		let logInWidth = font.stringWidth("Log In")
		let cx = login.x + login.w / 2
		let x = cx + logInWidth / 2 + 24
		let y = login.y + login.h - 4
		font.drawLeft(text, x: x, y: y, color: 0x663300, into: &r)
		faceIDLink = (x - 6, login.y - 4, w + 12, login.h + 8)
	}

	/// Asks the shell for the saved password (Face ID) and logs in with it.
	public func loginWithSavedPassword() {
		guard screen == .loginForm, !username.isEmpty, let provider = savedPasswordProvider else { return }
		let user = username
		provider(user) { [weak self] pw in
			guard let self, let pw, !pw.isEmpty, self.username == user, self.screen == .loginForm else { return }
			self.password = pw
			self.submit()
		}
	}

	/// Client cycles run since the shell last read `takeCycleCount()` (for the frame-time counter).
	var cyclesThisSecond = 0
	public func takeCycleCount() -> Int { defer { cyclesThisSecond = 0 }; return cyclesThisSecond }

	/// Shows or hides the keyboard in game (for a button in the shell).
	public func toggleKeyboard() { keyboardRequested.toggle() }

	// MARK: frame

	/// Draws one frame at `width` x `height` game pixels. rt4's resizable interface assumes a canvas of at
	/// least 765x503; shells below that (phones) should pick a larger game size and scale the result down
	/// (`App/Sources/GameView.swift` does: `scale = max(1, 503 / h, 765 / w)`) instead of asking for a smaller canvas.
	public func frame(width: Int, height: Int) throws -> Raster {
		try frame(width: width, height: height, at: Date())
	}

	/// Render-side smoothing of actor and camera motion between 50 Hz client cycles (see `WorldView+Interpolation`).
	/// Off is rt4's faithful stepping; on suits 60/120 Hz displays.
	public var smoothMotion: Bool {
		get { world.smoothMotion }
		set { world.smoothMotion = newValue }
	}

	/// `frame(width:height:)` with the display timestamp supplied by the shell (e.g. `CADisplayLink.targetTimestamp`
	/// converted to a `Date`), so cycles and interpolation follow the time the frame will be shown.
	public func frame(width: Int, height: Int, at now: Date) throws -> Raster {
		lastSize = (width, height)
		if !worldListSettled { worldListSettled = worldList.fetch() != -1 }
		host.resize(width: width, height: height)
		world.publicFilter = host.game.chatFilters.public
		if let s = session {
			// A live session builds each region's scene in the background (recorded events fed to `handle` do not).
			world.asyncBuild = true
			for e in s.poll() { handle(e) }
		}
		// One client cycle is 20 ms; always run at least one so scripts and
		// timers advance on every frame, and never more than a few after a stall.
		// (0 is allowed after the first frame so a 60/120 Hz shell redraws without running the game faster than rt4's 50 Hz.)
		// rt4 `NanoTimer.count`: up to 10 cycles per frame; time beyond that is dropped (the timer jumps to now)
		// rather than owed, so a long stall does not make the game race afterwards.
		let cycles = lastCycleAt.map { min(max(Int(now.timeIntervalSince($0) / 0.02), 0), 10) } ?? 1
		lastCycleAt = lastCycleAt.map { $0.addingTimeInterval(Double(cycles) * 0.02) } ?? now
		if let t = lastCycleAt, now.timeIntervalSince(t) > 0.02 { lastCycleAt = now }
		cyclesThisSecond += cycles
		world.renderAlpha = lastCycleAt.map { min(max(now.timeIntervalSince($0) / 0.02, 0), 1) } ?? 1
		for _ in 0..<cycles {
			host.cycle()
			if let f = ui.flames { f.loop = host.loop; f.update() } // Title/Flames
			if inGame { world.cycle(varps: host.game.varps); interaction.cycle(); cycleInventoryUI(); housekeepingCycle() }
		}
		updateTitleMusic()
		if inGame { sendPreferencesIfNeeded(); updateAudio(); plugins.update(cycles: cycles) } // Plugins/
		// GPU mode: the 2D layer is opaque black like software mode; `drawGPU` makes only the viewport transparent
		// so the Metal scene shows through there.
		let transparent = false
		var r = takeFrameBuffer(width: width, height: height, transparent: transparent)
		let top = host.game.interfaces.top
		let showInterface = top != -1 && !(inGame && top == loginInterface)
		// The world is drawn first, inside the viewport component found while laying out the interface
		// (the previous frame's rectangle; a changed rectangle repeats the frame once).
		for pass in 0..<2 {
			let drawnViewport = inGame && drawWorld(into: &r, width: width, height: height)
			if drawnViewport { plugins.drawOverlays(.scene, into: &r) } // Plugins/
			// rt4 `TitleScreen.load`: the title backdrop stays on the canvas behind the login interface.
			if !inGame, top == loginInterface { TitleScreen.draw(store: store, into: &r) }
			if showInterface { try ui.render(top, state: host.game.interfaces, into: &r) }
			let found = showInterface ? ui.drawn.first(where: { $0.component.clientCode == 1337 }).map { (x: $0.x, y: $0.y, w: $0.w, h: $0.h) } : nil
			let changed = found.map { f in viewport.map { $0 != f } ?? true } ?? false
			if let f = found { viewport = f }
			if !(changed && drawnViewport) || pass == 1 { break }
			r.clear(transparent: transparent)
		}
		if !inGame { drawFaceIDLink(into: &r) }
		if !showInterface { ui.worldMap.isShown = false }
		if inGame && showInterface { world.drawMinimap(drawn: ui.drawn, into: &r) } // Minimap/
		// Plugin panels would cover the full-screen world map (755).
		if inGame, top != 755 { plugins.drawOverlays(.hud, into: &r) } // Plugins/
		if inGame { try drawInteraction(into: &r); try drawTargetHint(into: &r) }
		if inGame, showDebugInfo, let p12 = try store.font(named: "p12_full"), let w = host.game.selfWorld {
			p12.drawLeft("\(w.x), \(w.z)  tick \(host.game.ticks)", x: 6, y: 32, color: 0xFFFF00, shadow: 0, into: &r)
		}
		frameBuffer = r
		return r
	}

	/// The last frame's pixels: reused for the next frame once the shell has let go of the returned raster
	/// (copy-on-write makes it a fresh buffer otherwise), so a 60/120 Hz shell does not allocate megabytes per frame.
	private var frameBuffer: Raster?

	private func takeFrameBuffer(width: Int, height: Int, transparent: Bool = false) -> Raster {
		guard var r = frameBuffer, r.width == width, r.height == height else { return Raster(width: width, height: height, transparent: transparent) }
		frameBuffer = nil
		r.clear(transparent: transparent)
		return r
	}

	/// Draws the 3D world into the viewport (the whole raster until the interface has told us where it is).
	private func drawWorld(into r: inout Raster, width: Int, height: Int) -> Bool {
		let v = viewport.flatMap { $0.x + $0.w <= width && $0.y + $0.h <= height ? $0 : nil } ?? (x: 0, y: 0, w: width, h: height)
		world.ctx.characterShadows = host.prefs.characterShadows
		return world.draw(into: &r, rect: v)
	}

	// MARK: camera (rt4 Camera: yawTarget / pitchTarget / ZOOM)

	/// One-finger drag over the world, in game pixels: horizontal turns the camera, vertical tilts it.
	/// While the world map is open the drag pans the map instead (see `worldMapDrag`).
	public func cameraDrag(dx: Double, dy: Double) {
		if worldMapIsOpen { worldMapDrag(dx: dx, dy: dy) } else { world.camera.drag(dx: dx, dy: dy) }
	}

	/// Pinch gesture: `scale` > 1 zooms in, < 1 out (use the change since the last callback).
	/// While the world map is open the pinch zooms the map instead (see `worldMapZoom`).
	public func cameraPinch(scale: Double) {
		if worldMapIsOpen { worldMapZoom(scale: scale) } else { world.camera.pinch(scale: scale) }
	}

	/// Back to rt4's default zoom, facing north.
	public func cameraReset() {
		world.camera.zoom = WorldCamera.defaultZoom
		world.camera.pitchTarget = 128
		world.camera.yawTarget = 0
	}

	/// True when a drag starting at (x, y) belongs to the camera: inside the world viewport and not
	/// on an interactive interface component.
	public func isOverWorld(x: Int, y: Int) -> Bool {
		if inGame, worldMapIsOpen { return isOverWorldMap(x: x, y: y) }
		guard inGame, !interaction.isMenuOpen, let v = viewport else { return false }
		return x >= v.x && y >= v.y && x < v.x + v.w && y < v.y + v.h && ui.hitTest(x: x, y: y) == nil
	}

	// MARK: scrolling (rt4 InterfaceList wheel handling)

	/// Whether interface scrolling applies right now: in game, no menu in the way, not on the world map.
	private var canScrollInterfaces: Bool { inGame && interaction.popup == nil }

	/// A mouse wheel notch count at (x, y) in game pixels, positive scrolling down. Runs the `onScroll` hooks of the
	/// components under the point with the delta (rt4 `InterfaceList` ~723) and wheel-scrolls IF1 layers 45 px per
	/// notch (`method4049`). True when an interface took it (otherwise the shell can zoom the camera).
	@discardableResult
	public func scrollInterface(x: Int, y: Int, delta: Int) -> Bool {
		guard canScrollInterfaces else { return false }
		return host.scrollWheel(x: x, y: y, delta: delta)
	}

	/// Touch pan: the finger moved `dy` game pixels (positive: down) since the last call, with the gesture started at
	/// (x, y). The scrollable layer there follows the finger exactly (bank, quest list, chat history, friends list);
	/// CS2 scrollbars are resynced through a zero `onScroll`. True when a layer took it.
	@discardableResult
	public func dragScroll(x: Int, y: Int, dy: Int) -> Bool {
		guard canScrollInterfaces else { return false }
		return host.scrollDrag(x: x, y: y, dy: dy)
	}

	/// True when a vertical pan starting at (x, y) belongs to a scrollable interface layer rather than the camera.
	public func isOverScrollable(x: Int, y: Int) -> Bool {
		canScrollInterfaces && host.isOverScrollable(x: x, y: y)
	}

	// MARK: input

	/// A tap in game pixels: press and release of the primary button.
	public func tap(x: Int, y: Int) {
		var (x, y) = (x, y)
		if canScrollInterfaces, host.pressScrollbar(x: x, y: y) { return } // IF1 scrollbar arrows and track
		if inGame, interaction.popup == nil, mobileToggles(x: x, y: y) { return }
		if inGame, interaction.popup == nil {
			// Touch forgiveness (OSRS mobile style, not in rt4): a tap anywhere on a dialogue with "Click here to
			// continue" continues it, and a tap just beside a small button presses the nearest one.
			if let c = ui.dialogueContinue(),
			   x >= c.area.x, y >= c.area.y, x < c.area.x + c.area.w, y < c.area.y + c.area.h,
			   ui.hitTest(x: x, y: y) == nil {
				(x, y) = (c.x, c.y)
			} else if ui.hitTest(x: x, y: y) == nil, let n = ui.nearestInteractive(x: x, y: y, slop: touchSlop) {
				(x, y) = n
			}
		}
		performTap(x: x, y: y, hooks: true)
	}


	// MARK: mobile toggles (OSRS mobile style, not in rt4)

	/// The side-panel tab or chat filter pressed by the previous tap, for "tap again to close".
	private var lastToggleTap: Int?
	/// The side panel (746:73) is hidden by tapping its open tab again.
	public private(set) var sidePanelCollapsed = false
	/// The chatbox is collapsed (its resizable-mode container 746:70 hidden) by tapping the selected filter again.
	public private(set) var chatCollapsed = false

	/// Tapping the open side-panel tab again hides the panel (any tab shows it again); tapping the chat's "All"
	/// filter twice collapses or restores the chatbox. True if handled.
	func mobileToggles(x: Int, y: Int) -> Bool {
		guard let hit = ui.hitTest(x: x, y: y) else { lastToggleTap = nil; return false }
		let top = host.game.interfaces.top
		let id = hit.id
		let previous = lastToggleTap
		lastToggleTap = id
		// Side-panel tab stones (both rows of interface 746's tab bar).
		let isTab = top == 746 && id >> 16 == 746 && (41...54).contains(id & 0xFFFF)
		if isTab {
			if sidePanelCollapsed {
				// Any tab brings the panel back (and opens that tab as usual).
				sidePanelCollapsed = false
				host.game.interfaces.hidden[746 << 16 | 73] = nil
			} else if previous == id {
				sidePanelCollapsed = true
				host.game.interfaces.hidden[746 << 16 | 73] = true
				lastToggleTap = nil
				return true
			}
		}
		// The "All" chat filter button: a component with an "All" label drawn inside it.
		if top == 746, let box = ui.drawn.last(where: { $0.component.id == id }),
		   ui.drawn.contains(where: { $0.component.type == 4 && $0.component.text == "All" && $0.x >= box.x - 2 && $0.y >= box.y - 2 && $0.x + $0.w <= box.x + box.w + 2 && $0.y + $0.h <= box.y + box.h + 2 }) {
			if previous == id || chatCollapsed {
				chatCollapsed.toggle()
				host.game.interfaces.hidden[746 << 16 | 70] = chatCollapsed ? true : nil
				lastToggleTap = nil
				return true
			}
		}
		return false
	}

	/// Game pixels a tap may miss a small button by and still press it (set by the shell from its points scale).
	public var touchSlop = 12

	/// `hooks` false when the press hooks already ran for a gesture that began as a drag.
	func performTap(x: Int, y: Int, hooks: Bool) {
		if screen == .loginForm {
			if let l = faceIDLink, x >= l.x, y >= l.y, x < l.x + l.w, y < l.y + l.h {
				loginWithSavedPassword()
				return
			}
			// Log In with an empty password on a saved account: ask the shell for the saved password (Face ID) first.
			if password.isEmpty, !username.isEmpty, savedPasswordProvider != nil,
			   let hit = ui.hitTest(x: x, y: y), hit.id == loginInterface << 16 | 347 {
				loginWithSavedPassword()
				return
			}
			// Touch: a tap on (or near) a field's box focuses that field (login stage 1 username, 2 password).
			for (box, stage) in [(339, 1), (345, 2)] {
				let ids = [box - 3, box - 2, box - 1, box].map { loginInterface << 16 | $0 }
				let rects = ui.drawn.filter { ids.contains($0.component.id) }
				guard let r0 = rects.first else { continue }
				let minX = rects.map(\.x).min()!, maxX = rects.map { $0.x + $0.w }.max()!
				let minY = rects.map(\.y).min()!, maxY = rects.map { $0.y + $0.h }.max()!
				_ = r0
				if x >= minX - 8, x < maxX + 8, y >= minY - 4, y < maxY + 4 {
					host.setVarc(LoginVar.stage, Int32(stage))
					host.cycle()
					return
				}
			}
		}
		if inGame, interaction.popup == nil {
			if tapToDrop, dropTap(x: x, y: y) { return }
			if inventoryTap(x: x, y: y) { keyboardRequested = false; return }
			if componentTargetTap(x: x, y: y) { return }
		}
		let hadTarget = interaction.target != nil
		if inGame, worldTap(x: x, y: y) { keyboardRequested = false; return }
		let hit = inGame ? ui.hitTest(x: x, y: y) : nil
		if inGame, interaction.popup == nil, openComponentMenuOnTap(x: x, y: y, hooks: hooks) { keyboardRequested = false; return }
		if host.tap(x: x, y: y, hooks: hooks) == nil, inGame, let c = hit {
			log("tap on \(c.id >> 16):\(c.id & 0xFFFF) (\(c.ops.first ?? c.option ?? "no op"))")
		}
		// rt4: a click that finds no target leaves target mode.
		if hadTarget { cancelTarget() }
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
		if interaction.popup == nil { previewTap(x: x, y: y) }
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
		// rt4 `LoginManager`: the login block carries the anti-aliasing mode and `Preferences.toInt()`, which also
		// marks the preferences as sent.
		req.worldSelector = host.loginWorldSelector
		req.antiAliasingMode = host.prefs.antiAliasing
		req.preferences = host.prefs.toInt()
		host.prefs.sentToServer = true
		lastVerifyId = 0
		connectError = nil
		lastRequest = req
		let s = GameSession(host: server.host, port: server.port, request: req)
		session = s
		s.start()
	}

	/// Re-logs-in after the connection dropped mid-game (rt4 `LoginManager` reconnecting state): same
	/// credentials with login opcode 18, keeping the world on screen. False once attempts run out.
	private func reconnect() -> Bool {
		guard inGame, var req = lastRequest, reconnectAttempt < maxReconnectAttempts else { return false }
		reconnectAttempt += 1
		req.reconnecting = true
		req.verifyId = lastVerifyId
		req.resumeAccount = host.game.account
		req.canvasWidth = max(lastSize.w, 765)
		req.canvasHeight = max(lastSize.h, 503)
		let s = GameSession(host: server.host, port: server.port, request: req)
		s.startDelay = reconnectAttempt == 1 ? 0.5 : 3
		session = s
		log("reconnecting (attempt \(reconnectAttempt))")
		s.start()
		return true
	}

	/// Gives up on a dead game connection: back to the login screen with an explanation.
	private func connectionLost(_ reason: String?) {
		let requested = host.game.loggedOut
		logout()
		if !requested { connectError = reason ?? "Connection lost." }
	}

	public func logout() {
		let music = audio.music
		audioLoader.async { music.stop() }
		audio.effects.clear()
		audio.effects.area.clearAll()
		if inGame { plugins.loggedOut() } // Plugins/
		session?.close()
		session = nil
		inGame = false
		let (u, p) = (username, password)
		let savedPrefs = host.prefs
		host = InterfaceScriptHost(store: store)
		host.prefs = savedPrefs
		world = WorldView(store: store)
		keyboardRequested = false
		viewport = nil
		interaction.reset()
		host.canvas = (lastSize.w > 0 ? lastSize.w : 765, lastSize.h > 0 ? lastSize.h : 503)
		bindHost()
		applyAllPreferences()
		openLoginScreen()
		username = u
		password = p
	}

	public func send(_ m: ClientMessage) { session?.send(m) }

	/// Connects the CS2 client actions that need the world, audio or the platform (`InterfaceClientOps.swift`).
	private func bindClientOps() {
		host.onAppearanceEdit = { [weak self] in self?.world.editSelfLook($0) }
		host.selfFemale = { [weak self] in self?.world.selfLook?.female ?? false }
		host.onAnimateSelf = { [weak self] seq, delay in self?.world.selfActor?.animate(delay: delay, seq: seq) }
		// The server-sent sounds and music take the same paths as these script ops (rt4 `Protocol` and `ScriptRunner`).
		host.onPlaySoundEffect = { [weak self] id, loops, delay in self?.playAudio(.synthSound(id: id, loops: loops, delay: delay)) }
		host.onPlaySong = { [weak self] id in self?.playAudio(.midiSong(id)) }
		host.onPlayJingle = { [weak self] id, volume in self?.playAudio(.midiJingle(id: id, volume: volume)) }
		host.onClickPlayerOption = { [weak self] option, name in self?.clickPlayerOption(option, name: name) }
		host.onObjRecolour = { [weak self] in
			guard let self else { return }
			self.ui.icons.clear()
			self.ui.models.clearCache()
			self.world.groundModels = nil
		}
	}

	/// rt4 `ClientProt.clickPlayerOption`: walks up to the named player in view and sends the option
	/// (1 follow-style 30, 4 trade 29, 5 action 10, 6 action 44, 7 action 37); "Unable to find" when no such player is near.
	func clickPlayerOption(_ option: Int, name: String) {
		func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "\u{A0}", with: " ") }
		let wanted = norm(name)
		let found = world.ctx.players.values.sorted { $0.index < $1.index }.first {
			guard let n = $0.appearance?.name37, n != 0 else { return false }
			return norm(WordPack.displayName(n)) == wanted
		}
		guard let target = found else {
			host.game.chatLog.add(type: 0, name: "", message: "Unable to find " + WordPack.titleCase(name))
			host.chatAt = host.transmitTimer
			return
		}
		guard let tile = world.playerTile(target.index) else { return }
		approach(.entity(x: tile.x, z: tile.z), clickX: 0, clickY: 0)
		let actions = [1: 30, 4: 29, 5: 10, 6: 44, 7: 37]
		if let action = actions[option] { sendOp(.opPlayer(action: action, index: target.index)) }
	}

	/// rt4 `Protocol` MIDI_SONG / MIDI_JINGLE / SYNTH_SOUND.
	private func playAudio(_ m: ServerMessage) {
		switch m {
		case .midiSong(let id):
			let music = audio.music
			if audioSharesStore { music.play(songId: id) } else { audioLoader.async { music.play(songId: id) } }
		case let .midiJingle(id, _):
			let music = audio.music
			if audioSharesStore { music.playJingle(id: id) } else { audioLoader.async { music.playJingle(id: id) } }
		case let .synthSound(id, loops, delay):
			audio.effects.play(id: id, loops: loops, delay: delay)
		default:
			break
		}
	}

	/// Per frame: keep the listener on the player and report finished songs (rt4 `SoundPlayer` SOUND_SONGEND).
	private func updateAudio() {
		if let me = world.selfActorFine {
			audio.effects.setListener(xFine: me.x, zFine: me.z)
			// rt4 `LoginManager`: `AreaSoundManager.redraw(sceneDelta, self.xFine, self.zFine, plane)` every cycle.
			let area = audio.effects.area
			if areaResolverBound == false {
				areaResolverBound = true
				area.resolveLoc = { [weak self] loc in self.flatMap { $0.world.env.resolve(loc, store: $0.store) } }
			}
			area.syncActors(world.areaSoundSources())
			let loop = world.ctx.loop
			area.redraw(cycles: max(loop - lastAreaLoop, 0), xFine: me.x, zFine: me.z, level: world.plane)
			lastAreaLoop = loop
		}
		if let ended = audio.music.takeSongEnded(), ended >= 0 { send(.songEnd(ended)) }
	}

	/// Plays the title song while at the login screens (rt4 `client.setGameState` ~383-396, game states 5 / 10 / 28)
	/// and fades it out once a login starts. Off with `playsTitleMusic = false`.
	public var playsTitleMusic = true
	private var titleMusicActive = false

	/// rt4 `MusicPlayer.titleSong`: group "scape main" of archive 6.
	var titleSongId: Int? { try? store.index(6).group(named: "scape main") }

	private func updateTitleMusic() {
		guard playsTitleMusic else { return }
		let want = !inGame && session == nil
		guard want != titleMusicActive else { return }
		titleMusicActive = want
		let music = audio.music
		if want {
			guard let song = titleSongId else { return }
			music.volume = host.prefs.musicVolume
			if audioSharesStore { music.play(songId: song) } else { audioLoader.async { music.play(songId: song) } }
		} else if audioSharesStore {
			music.stop()
		} else {
			audioLoader.async { music.stop() }
		}
	}

	/// rt4 `Protocol` (~2526): a changed preference set goes to the server once as packet 98.
	private func sendPreferencesIfNeeded() {
		guard !host.prefs.sentToServer else { return }
		send(.preferences(host.prefs.toInt()))
		host.prefs.sentToServer = true
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
		case let .clanMessage(name37, clan37, messageId, rights, text):
			// rt4 MESSAGE_CLANCHANNEL: same dedupe and ignore rules as private messages, shown as chat type 9.
			guard let codec = (try? WordPack.loadCodec(store)) ?? nil else { return }
			if host.game.chatLog.hasSeen(messageId: messageId) { return }
			if rights <= 1 && chatRestricted(name37) { return }
			_ = host.game.chatLog.remember(messageId: messageId)
			let message = WordPack.display(WordPack.decode(text, codec: codec))
			host.game.chatLog.add(type: 9, name: WordPack.chatIcon(rights: rights) + WordPack.displayName(name37), message: message, clan: WordPack.displayName(clan37))
			host.chatAt = host.transmitTimer
		case let .quickChatPrivate(name37, messageId, rights, phrase, values):
			// rt4 MESSAGE_QUICKCHAT_PRIVATE: same dedupe and ignore rules as typed private messages, chat type 18.
			if host.game.chatLog.hasSeen(messageId: messageId) { return }
			if rights <= 1 && host.game.ignored.contains(name37) { return }
			_ = host.game.chatLog.remember(messageId: messageId)
			guard let message = quickChatText(phrase, values) else { return }
			host.game.chatLog.add(type: 18, name: WordPack.chatIcon(rights: rights) + WordPack.displayName(name37), message: message, phraseId: phrase)
			host.chatAt = host.transmitTimer
		case let .quickChatClan(name37, clan37, messageId, rights, phrase, values):
			if host.game.chatLog.hasSeen(messageId: messageId) { return }
			if rights <= 1 && host.game.ignored.contains(name37) { return }
			_ = host.game.chatLog.remember(messageId: messageId)
			guard let message = quickChatText(phrase, values) else { return }
			host.game.chatLog.add(type: 20, name: WordPack.chatIcon(rights: rights) + WordPack.displayName(name37), message: message, clan: WordPack.displayName(clan37), phraseId: phrase)
			host.chatAt = host.transmitTimer
		case let .quickChatPrivateEcho(name37, phrase, values):
			guard let message = quickChatText(phrase, values) else { return }
			host.game.chatLog.add(type: 19, name: WordPack.displayName(name37), message: message, phraseId: phrase)
			host.chatAt = host.transmitTimer
		case let .privateMessageEcho(name37, text):
			guard let codec = (try? WordPack.loadCodec(store)) ?? nil else { return }
			host.game.chatLog.add(type: 6, name: WordPack.displayName(name37), message: WordPack.display(WordPack.decode(text, codec: codec)))
			host.chatAt = host.transmitTimer
		default:
			break
		}
	}

	/// rt4 `QuickChatPhraseTypeList.get(id).decodeMessage`: the phrase text with its dynamic values filled in.
	private func quickChatText(_ phrase: Int, _ values: [UInt8]) -> String? {
		QuickChat.message(phrase: phrase, values: values, store: store)
	}

	/// Instrumentation for playthrough tests: what the client received but could not act on.
	public struct Diagnostics {
		/// Server opcodes that were framed but have no decoder (opcode -> count).
		public var unhandledPackets: [Int: Int] = [:]
		/// Server opcodes whose payload failed to decode (opcode -> count).
		public var decodeFailures: [Int: Int] = [:]
	}
	public private(set) var diagnostics = Diagnostics()
	/// CS2 opcodes that hit the unported branch.
	public var unportedScriptOpcodes: [Int: Int] { host.unportedOpcodes }
	public var scriptErrorCounts: [String: Int] { host.errorCounts }

	func handle(_ e: GameSession.Event) {
		if case .message(.unhandled(let op, _)) = e { diagnostics.unhandledPackets[op, default: 0] += 1 }
		if case .decodeFailed(let op, _) = e { diagnostics.decodeFailures[op, default: 0] += 1 }
		world.handle(e, varps: host.game.varps)
		if case .message(let m) = e { interaction.handle(m); receiveChat(m); playAudio(m) }
		switch e {
		case .message(.urlOpen(let url)): onOpenURL(url)
		// rt4 `ReflectionCheck`: this client runs no checks, so every entry answers "class not found" (-1).
		case .message(.reflectionCheck(let id, let entries)): send(.reflectionReply(id: id, entries: entries, error: -1))
		default: break
		}
		switch e {
		case .loginQueued:
			host.loginReply = 1
		case .loggedIn:
			host.apply(e)
			host.loginReply = 2
			inGame = true
			beginHousekeeping()
			plugins.loggedIn() // Plugins/
			reconnectAttempt = 0
			log("logged in to \(server.host):\(server.port)")
			onLoggedIn(username, password)
		case .loginFailed(let reply):
			if let v = session?.verifyId { lastVerifyId = v }
			session = nil
			if inGame {
				if !reconnect() { connectionLost("Could not rejoin the game.") }
				return
			}
			switch reply {
			case .failure(let code): host.loginReply = Int32(code)
			case .hopDelay(let ticks): host.loginReply = 21; host.worldSwitchTimer = Int32(ticks)
			case .disallowed(let r): host.loginReply = 29; host.loginDisallowResult = Int32(r)
			// rt4: a login held at reply 1 that never resumed times out (-5); a refused reconnect is an unknown reply.
			case .retry: host.loginReply = -5
			case .success, .reconnected: host.loginReply = 15
			}
		case .disconnected(let reason):
			if let v = session?.verifyId { lastVerifyId = v }
			session = nil
			if inGame {
				log("disconnected: \(reason ?? "closed")")
				// A logout the player asked for ends with the server's LOGOUT packet; anything else is a drop.
				if reason != nil, !host.game.loggedOut, reconnect() { return }
				connectionLost(reason)
			} else {
				// rt4 `LoginManager.loop`: an IOException that survives the retry is reply -4 ("Error connecting to server").
				host.loginReply = -4
				connectError = reason
			}
		case .decodeFailed(let op, let err):
			log("decode failed for opcode \(op): \(err)")
		default:
			host.apply(e)
		}
	}
}

// MARK: if3 component drag (rt4 `Cs1ScriptRunner.method1015` / `method28`)

extension GameClient {
	/// A finger that went down at (x, y) started moving: true when an if3 component there takes the gesture (it can
	/// be dragged, or it reacts to `onDrag` / `onHold`), so the caller leaves the camera alone.
	public func beginComponentDrag(x: Int, y: Int) -> Bool {
		guard inGame, interaction.popup == nil, interaction.target == nil else { return false }
		return host.beginDragGesture(x: x, y: y)
	}

	public func moveComponentDrag(x: Int, y: Int) { host.moveDragGesture(x: x, y: y) }

	/// The finger lifted: a finished drag ran its release hook and sent IF_DRAG; a press that never left the dead
	/// zone is the tap it started as.
	public func endComponentDrag(x: Int, y: Int) {
		let r = host.endDragGesture(x: x, y: y)
		if !r.dragged { performTap(x: r.start.x, y: r.start.y, hooks: false) }
	}
}

// MARK: world map (WorldMap/)

extension GameClient {
	/// True while a world map component was drawn in the last frame (the interface the server opens from the minimap
	/// orb). `cameraDrag`, `cameraPinch` and `isOverWorld` then act on the map, so a shell that already forwards those
	/// gestures to the camera needs no change; the explicit calls below are for shells that route gestures themselves.
	public var worldMapIsOpen: Bool { inGame && ui.worldMap.isShown && ui.worldMap.current != nil }

	/// The map component's rectangle from the last frame (game pixels), nil when the map is not shown.
	public var worldMapRect: (x: Int, y: Int, w: Int, h: Int)? {
		guard worldMapIsOpen, let d = ui.drawn.last(where: { $0.component.clientCode == 1400 }) else { return nil }
		return (d.x, d.y, d.w, d.h)
	}

	/// Is (x, y) on the map picture (not on a button or panel above it)? Use it to start a map pan or pinch.
	public func isOverWorldMap(x: Int, y: Int) -> Bool {
		guard let r = worldMapRect, x >= r.x, y >= r.y, x < r.x + r.w, y < r.y + r.h else { return false }
		// Controls drawn over the map (zoom buttons, search box) keep their own taps.
		for d in ui.drawn.reversed() where x >= d.x && y >= d.y && x < d.x + d.w && y < d.y + d.h {
			if d.component.clientCode == 1400 { return true }
			if d.component.hooks["onOptionClick"] != nil || d.component.hooks["onClickRepeat"] != nil { return false }
		}
		return true
	}

	/// One-finger pan inside the map: `dx` / `dy` are the finger's travel in game pixels since the last call.
	public func worldMapDrag(dx: Double, dy: Double) { ui.worldMap.drag(dx: dx, dy: dy) }

	/// Pinch inside the map: `scale` is the change since the last callback (> 1 zooms in). Call `worldMapZoomEnded()`
	/// when the pinch ends to settle on the nearest zoom level.
	public func worldMapZoom(scale: Double) { ui.worldMap.zoom(by: scale) }

	public func worldMapZoomEnded() { ui.worldMap.snapZoom() }

	/// A tap or drag on the overview (client code 1401) at (x, y): centres the main map there. True when it hit.
	@discardableResult
	public func worldMapOverviewTouch(x: Int, y: Int) -> Bool {
		guard worldMapIsOpen, let d = ui.drawn.last(where: { $0.component.clientCode == 1401 }),
		      x >= d.x, y >= d.y, x < d.x + d.w, y < d.y + d.h else { return false }
		ui.worldMap.centre(overviewX: x - d.x, y: y - d.y, w: d.w, h: d.h)
		return true
	}
}

// MARK: world hop (rt4 `WorldList.hopWorld`)

extension GameClient {
	/// CS2 6503 `setWorldHost`: aim the next login at `w`. rt4 (`modeWhere != 0`) sets the host to the world's
	/// hostname and the port to `worldId + 43594`; here the player then logs in as usual (a hop from inside the game
	/// is a logout first, as in rt4, where the op only works on the login screen). A list that names a loopback
	/// address for itself keeps the host we already use, and the world we are already on keeps its port.
	func hopWorld(_ w: WorldEntry) -> Bool {
		guard !inGame, session == nil else { return false }
		let loopback: Set<String> = ["", "127.0.0.1", "localhost", "::1"]
		let hostname = loopback.contains(w.hostname) ? server.host : w.hostname
		let port = w.id == Int(currentWorldId) ? server.port : 43594 + w.id
		server = Server(host: hostname, port: port)
		currentWorldId = Int32(w.id)
		host.worldId = currentWorldId
		worldList.fallbackWorldId = w.id
		return true
	}
}

// MARK: housekeeping packets (rt4 `Protocol` outbound flush, `ClientProt.sendWindowDetails`)

extension GameClient {
	/// The app moved to the foreground (true) or background (false). rt4 sends EVENT_APPLET_FOCUS when its window's
	/// focus changes; on a touch device this is the app becoming active / inactive.
	public func setApplicationFocus(_ focused: Bool) { hasFocus = focused }

	/// Canvas size and mode as the login packet reports them (resizable window, never below 765x503).
	private var reportedCanvas: (w: Int, h: Int) { (max(lastSize.w, 765), max(lastSize.h, 503)) }

	/// rt4 `LoginManager` after a login: `Protocol.prevFocus = true`, the camera flag set, then `sendWindowDetails`.
	func beginHousekeeping() {
		sentFocus = true
		sentCamera = nil
		cameraCooldown = 0
		sendWindowStatus()
	}

	/// rt4 `ClientProt.sendWindowDetails`: WINDOW_STATUS with the window mode, canvas size and anti-aliasing mode.
	private func sendWindowStatus() {
		let c = reportedCanvas
		sentWindow = c
		send(.windowStatus(mode: 2, width: c.w, height: c.h, antiAliasing: host.prefs.antiAliasing))
	}

	/// One client cycle of the checks rt4 makes before each flush: a changed canvas (`DisplayMode`), the camera
	/// (EVENT_CAMERA_POSITION, at most once per 20 cycles) and the focus.
	func housekeepingCycle() {
		if let w = sentWindow, w != reportedCanvas { sendWindowStatus() }
		if cameraCooldown > 0 { cameraCooldown -= 1 }
		let cam = (pitch: Int(world.camera.pitchTarget), yaw: Int(world.camera.yawTarget) & 0x7FF)
		if cameraCooldown <= 0, sentCamera.map({ $0 != cam }) ?? true {
			cameraCooldown = 20
			sentCamera = cam
			send(.cameraPosition(pitch: cam.pitch, yaw: cam.yaw))
		}
		if hasFocus != sentFocus {
			sentFocus = hasFocus
			send(.appletFocus(hasFocus))
		}
	}
}
