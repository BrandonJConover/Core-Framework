import Foundation

/// The 3D world behind the interfaces: builds the `Scene` from a REBUILD_NORMAL,
/// runs rt4's per-cycle actor and camera logic, and draws the scene into a
/// `Raster`. rt4 equivalents: `LoginManager.rebuildMap` (scene load),
/// `PlayerList.method1444` / `NpcList.method2274` (actor cycle),
/// `Camera.method4273` + `ScriptRunner.method4326` (camera and scene draw).
public final class WorldView {
	public let store: ConfigStore
	let ctx: WorldContext
	let env = LocEnvironment()
	var textures: TextureStore?
	/// The built scene. Hidden (nil) while a rebuild is in flight: its coordinates no longer match the actors.
	public var scene: Scene? { isBuilding ? nil : liveScene }
	var liveScene: Scene?
	var raster3D: Rasteriser3D?
	/// GPU renderer: nil draws with the software rasteriser; set it to draw through `gpuFrame` instead (see `GPU/`).
	public var gpuSettings: GPURenderSettings?
	let gpu = GPUWorldState()
	/// Rasteriser gamma (rt4 `Rasteriser.setBrightness`); a change rebuilds the 3D buffer's palette and textures.
	public var brightness: Float = 0.8 {
		didSet { if brightness != oldValue { raster3D = nil } }
	}
	/// rt4 `Preferences.removeRoofsSelectively` (false = `neverRemoveRoofs`, roofs always drawn).
	public var removeRoofs: Bool {
		get { roofMode != .never }
		set { roofMode = newValue ? .selective : .never }
	}
	/// rt4 `ScriptRunner.method4047`: 0 never removes roofs, 1 always removes them, 2 removes them selectively.
	public var roofMode: RoofHider.Mode = .selective
	/// Scene-build options (rt4 `Preferences.allLevelsVisible` / `showGroundDecorations` / `manyGroundTextures`).
	/// Changing them with `applySceneOptions` rebuilds the scene as rt4's `method2742` (game state 25) does.
	public private(set) var sceneOptions = SceneOptions()
	public struct SceneOptions: Equatable, Sendable {
		public var allLevelsVisible = true
		public var showGroundDecorations = true
		public var manyGroundTextures = true
		public init() {}
	}
	var roofs = RoofHider()
	/// rt4's one-actor-per-tile rule (`ScriptRunner.method964` / `method3240`): of several size-1 actors standing
	/// exactly on a tile centre only one is drawn; `MenuBuilder.addStacked` lists the hidden ones in the menu.
	public var oneActorPerTile = true
	public var camera = WorldCamera()
	/// The minimap and compass (drawn by `drawMinimap`, see `Minimap/`).
	public private(set) lazy var minimap = Minimap(store: store)

	var rebuild: RebuildNormal?
	var needsBuild = false
	var builtPlane = -1
	var zone: (x: Int, z: Int)?
	public private(set) var selfIndex = -1
	/// Plane of the local player (rt4 `Player.plane`).
	public private(set) var plane = 0
	/// Steps of `TrackedEntity.lastStep` already turned into queue moves.
	var consumedPlayer: [Int: Int] = [:]
	var consumedNpc: [Int: Int] = [:]
	var npcBase: [Int: NpcType] = [:]
	/// Position events (`TrackedEntity.posSerial`) already applied to each actor.
	var seenPlayerPos: [Int: Int] = [:]
	var seenNpcPos: [Int: Int] = [:]
	/// Projectiles and tile graphics in flight (rt4 `SceneGraph.projectiles` / `spotanims`), see `Projectiles.swift`.
	var projectiles: [Projectile] = []
	var groundSpots: [GroundSpotAnim] = []

	/// Seconds the last scene build took, and any build problems.
	public private(set) var lastBuildSeconds = 0.0
	public private(set) var buildErrors: [String] = []
	/// Called with each placed loc (collision flagging hooks in here).
	public var onLocPlaced: ((LocPlacement) -> Void)?
	/// A loc was removed by a zone update (rt4 `SceneGraph.removeLoc`): its type and scene tile / level.
	public var onLocRemoved: ((_ loc: LocType, _ x: Int, _ z: Int, _ level: Int) -> Void)?
	/// A finished scene build is about to replace the old scene; `onLocPlaced` replays its locs next.
	public var onSceneAdopted: (() -> Void)?
	/// Social state fed by `GameClient` (see `WorldView+Social` / `WorldView+Overlay`).
	/// Public chat decoded from player info, for the chat history.
	public var onPublicChat: ((PublicChatEvent) -> Void)?
	/// SOUND_AREA zone updates, already converted to scene-local tiles: (id, x, z, radius, loops, delay).
	public var onSoundArea: ((_ id: Int, _ x: Int, _ z: Int, _ radius: Int, _ loops: Int, _ delay: Int) -> Void)?
	/// rt4 `SoundPlayer.playSeqSound`: an actor's (or graphic's) animation reached sound cue `index`
	/// (`seq.soundEffects[index]`) at the fine position (`xFine`, `zFine`); `isSelf` for the local
	/// player. `GameClient` forwards it: `audio.effects.playSeq(seq, index: i, xFine: x, zFine: z, isSelf: me)`.
	public var onSeqFrameSound: ((_ seq: SeqType, _ index: Int, _ xFine: Int, _ zFine: Int, _ isSelf: Bool) -> Void)? {
		didSet { ctx.onSeqSound = onSeqFrameSound }
	}
	/// True when rt4's ignore rules drop a public chat line from `name37` with staff `rights`.
	public var isChatIgnored: (_ name37: Int64, _ rights: Int) -> Bool = { _, _ in false }
	/// True when the ignore list drops a quick chat line from `name37` (quick chat bypasses the under-13 rule).
	public var isQuickChatIgnored: (_ name37: Int64) -> Bool = { _ in false }
	/// rt4 `Chat.publicFilter`: 0 show all, 1 friends only, 2 hide (3 show all too).
	public var publicFilter = 0
	/// rt4 `VarpDomain.chatEffectsDisabled`: overhead text drawn plain yellow.
	public var chatEffectsDisabled = false
	/// Camera of the last rendered frame.
	var overlayCamera: OverlayCamera?
	/// Incremented every time the scene is rebuilt.
	public private(set) var buildCount = 0
	/// Render-side motion smoothing (see `WorldView+Interpolation.swift`). Off = rt4's faithful 50 Hz look.
	public var smoothMotion = false
	/// How far between the previous client cycle (0) and the latest one (1) the frame being drawn is.
	public var renderAlpha = 1.0
	var interpSaved: [(actor: PathingActor, x: Int, z: Int, yaw: Int)] = []
	var interpCameraSaved: (x: Int, z: Int)?

	/// Collision maps for the four levels of the current scene (rt4 `PathFinder.collisionMaps`),
	/// built with every scene rebuild and updated by loc add/delete packets.
	public internal(set) var collision: [CollisionMap] = []
	/// Kept after a build so loc changes can be placed into the live scene.
	var placer: LocPlacer?
	/// The zone the following zone-update packets apply to, in scene tiles (rt4 `SceneGraph.currentChunkX/Z`).
	var chunk = (x: 0, z: 0)
	/// Ground items per `level << 16 | x << 8 | z`, oldest first (rt4 `SceneGraph.objStacks`).
	public internal(set) var objStacks: [Int: [GroundObj]] = [:]
	/// Models of ground items (see `Items/GroundItems.swift`).
	var groundModels: GroundItemModels?
	/// rt4 `MiniMap.hintMapMarkers`: the four hint arrow slots (HINT_ARROW), drawn over their target and on the minimap.
	public internal(set) var hintArrows = [ServerMessage.HintArrow?](repeating: nil, count: 4)
	/// World tiles plugins want marked on the minimap (the quest helper's target), drawn like a tile hint arrow.
	public var minimapMarkers: [(x: Int, z: Int)] = []
	/// The moving click flag on the minimap (scene tile), set when a walk is sent (rt4 `LoginManager.mapFlagX/Z`).
	public var destinationFlag: (x: Int, z: Int)?

	public init(store: ConfigStore) {
		self.store = store
		ctx = WorldContext(store: store, models: ActorModels(store: store))
	}

	public var isReady: Bool { scene != nil && self.selfActor != nil }

	// MARK: async scene build state

	/// Build the scene on a background thread when a REBUILD arrives (the live session turns this on). Off by
	/// default so recorded sessions fed through `GameClient.handle` have their scene on the first frame.
	public var asyncBuild = false
	/// Incremented by every region change and reset; a finished build is adopted only if it carries the
	/// current stamp (the others were overtaken).
	var rebuildStamp = 0
	/// Stamp of the build running on the background thread, nil when none is.
	var inFlightStamp: Int?
	let mailbox = BuildMailbox()
	/// Zone messages that arrived while a build was in flight; replayed into the new scene when it is adopted.
	var deferredZone: [ServerMessage] = []
	/// True while the scene is being built in the background (the viewport shows rt4's loading box).
	public var isBuilding: Bool { inFlightStamp != nil }

	var selfActor: PathingActor? { ctx.players[selfIndex] }
	/// The local player's scene-local fine position (rt4 `PlayerList.self.xFine/zFine`), for the sound listener.
	public var selfActorFine: (x: Int, z: Int)? { selfActor.map { ($0.xFine, $0.zFine) } }

	/// The local player's position in world tiles.
	public var selfTile: (x: Int, z: Int)? {
		guard let a = selfActor else { return nil }
		return (ctx.originX + (a.xFine >> 7), ctx.originZ + (a.zFine >> 7))
	}

	// MARK: events

	/// Feeds one session event (call before the event is applied to `GameState`).
	func handle(_ e: GameSession.Event, varps: [Int: Int32]) {
		minimap.handle(e)
		switch e {
		case .loggedIn(let a):
			reset()
			selfIndex = a.selfId
			ctx.selfIndex = a.selfId
		case .message(.rebuildNormal(let r)), .message(.rebuildRegion(let r)):
			applyRebuild(r)
		case .message(.spotAnimEntity(let delay, let height, let target, let gfx)):
			applySpotAnimMessage(delay: delay, height: height, target: target, gfx: gfx)
		case .message(let m):
			if applyWorldPacket(m) { break }
			if isBuilding { deferredZone.append(m) } else { applyZone(m) }
		case .players(let result, let decoder):
			env.varps = varps
			applyPlayers(result, decoder)
		case .npcs(let result, let decoder):
			env.varps = varps
			applyNpcs(result, decoder)
		default:
			break
		}
	}

	/// rt4 `Preferences.setAllVisibleLevels` / ground-decoration / ground-texture changes: stores the options
	/// and, when the built scene depends on them, rebuilds the scene around the current zone.
	public func applySceneOptions(_ o: SceneOptions) {
		let old = sceneOptions
		sceneOptions = o
		liveScene?.manyGroundTextures = o.manyGroundTextures
		guard o.allLevelsVisible != old.allLevelsVisible || o.showGroundDecorations != old.showGroundDecorations,
		      rebuild != nil else { return }
		rebuildStamp += 1
		needsBuild = true
	}

	func reset() {
		rebuildStamp += 1
		inFlightStamp = nil
		deferredZone = []
		liveScene = nil
		raster3D = nil
		roofs = RoofHider()
		rebuild = nil
		needsBuild = false
		builtPlane = -1
		zone = nil
		ctx.players = [:]
		ctx.npcs = [:]
		ctx.loop = 0
		env.loop = 0
		consumedPlayer = [:]
		consumedNpc = [:]
		npcBase = [:]
		seenPlayerPos = [:]
		seenNpcPos = [:]
		projectiles = []
		groundSpots = []
		camera = WorldCamera()
		collision = []
		placer = nil
		objStacks = [:]
		destinationFlag = nil
		hintArrows = [ServerMessage.HintArrow?](repeating: nil, count: 4)
	}

	/// rt4 `LoginManager` region change: the scene is rebuilt around the new zone, actors keep their
	/// world positions (so scene coordinates shift by the zone change).
	func applyRebuild(_ r: RebuildNormal) {
		if let z = zone {
			let dx = (r.zoneX - z.x) * 8, dz = (r.zoneZ - z.z) * 8
			for a in ctx.players.values { shift(a, dx, dz) }
			for a in ctx.npcs.values { shift(a, dx, dz) }
			camera.followX -= dx * 128
			camera.followZ -= dz * 128
			camera.prevFollowX -= dx * 128
			camera.prevFollowZ -= dz * 128
			camera.shiftScripted(dx: dx, dz: dz)
		}
		rebuildStamp += 1
		projectiles = []
		groundSpots = []
		zone = (r.zoneX, r.zoneZ)
		ctx.originX = (r.zoneX - 6) * 8
		ctx.originZ = (r.zoneZ - 6) * 8
		rebuild = r
		plane = r.plane
		needsBuild = true
		objStacks = [:]
		destinationFlag = nil
	}

	private func shift(_ a: PathingActor, _ dx: Int, _ dz: Int) {
		a.xFine -= dx * 128
		a.zFine -= dz * 128
		a.prevXFine -= dx * 128
		a.prevZFine -= dz * 128
		for i in 0..<10 { a.queueX[i] -= dx; a.queueZ[i] -= dz }
	}

	// MARK: entity updates (rt4 Protocol.readPlayerInfoPacket / readNpcPacket)

	/// Brings an actor's position up to the decoder's: a new position event (add record or the local
	/// player's teleport block) calls rt4 `method2683` with its jump flag, then each step the decoder
	/// took since the last call is queued with its speed (0 crawl, 1 walk, 2 run).
	private func sync(_ a: PathingActor, _ e: TrackedEntity, consumed: inout Int, seen: inout Int, isNew: Bool) {
		// A decoder that was recreated (login, region reset) counts from zero again: not a position event.
		if e.posSerial < seen { seen = e.posSerial; consumed = 0 }
		if e.posSerial != seen {
			seen = e.posSerial
			if isNew { a.yaw = e.facing; a.targetYaw = e.facing }
			a.setPosition(x: e.x, z: e.z, jump: e.jump)
			consumed = e.lastStep.count
			return
		}
		if e.lastStep.count < consumed { consumed = 0 }
		for (i, dir) in e.lastStep.enumerated().dropFirst(consumed) where dir >= 0 && dir < 8 {
			a.move(speed: i < e.lastSpeed.count ? e.lastSpeed[i] : (e.running ? 2 : 1), direction: dir)
		}
		consumed = e.lastStep.count
		if a.queueX[0] != e.x || a.queueZ[0] != e.z { a.setPosition(x: e.x, z: e.z, jump: false) }
	}

	private func applyMasks(_ a: PathingActor, _ m: EntityMasks) {
		if let anim = m.anim { a.animate(delay: anim.delay, seq: anim.seq) }
		if let f = m.faceEntity { a.faceEntity = f }
		if let t = m.faceTile { a.faceX = t.x; a.faceY = t.z }
		if let f = m.forceMove { a.applyForceMove(f) }
		if let l = m.layeredAnims { a.applyLayeredAnims(l) }
		applySocialMasks(a, m)
	}

	func applyPlayers(_ r: PlayerInfoDecoder.Result, _ d: PlayerInfoDecoder) {
		selfIndex = d.selfIndex
		plane = d.plane
		ctx.selfIndex = d.selfIndex
		for id in r.removed { ctx.players[id] = nil; consumedPlayer[id] = nil; seenPlayerPos[id] = nil }
		for (id, e) in d.players {
			let isNew = ctx.players[id] == nil
			let a = ctx.players[id] ?? PathingActor(kind: .player, index: id, ctx: ctx)
			if isNew { ctx.players[id] = a }
			if let ap = e.appearance, ap != a.appearance {
				a.appearance = ap
				a.look = PlayerLook(ap)
				a.size = ap.size
			}
			var c = consumedPlayer[id] ?? 0, seen = seenPlayerPos[id] ?? 0
			sync(a, e, consumed: &c, seen: &seen, isNew: isNew)
			consumedPlayer[id] = c
			seenPlayerPos[id] = seen
		}
		for (id, m) in r.updated { if let a = ctx.players[id] { applyMasks(a, m) } }
	}

	func applyNpcs(_ r: PlayerInfoDecoder.Result, _ d: NpcInfoDecoder) {
		for id in r.removed { ctx.npcs[id] = nil; consumedNpc[id] = nil; npcBase[id] = nil; seenNpcPos[id] = nil }
		for (id, e) in d.npcs {
			let isNew = ctx.npcs[id] == nil
			let a = ctx.npcs[id] ?? PathingActor(kind: .npc, index: id, ctx: ctx)
			if isNew { ctx.npcs[id] = a }
			if npcBase[id]?.id != e.type, let t = (try? store.npc(e.type)) ?? nil {
				npcBase[id] = t
				a.fallbackBasId = t.basId
			}
			resolveType(a, id)
			var c = consumedNpc[id] ?? 0, seen = seenNpcPos[id] ?? 0
			let added = e.posSerial != seen
			sync(a, e, consumed: &c, seen: &seen, isNew: isNew)
			if added, let t = npcBase[id] {
				// rt4 `loadAreaNPCs`: an add record takes the turn rate from the type (0 = never turns, faces north).
				a.turnRate = t.rotationSpeed
				if t.rotationSpeed == 0 { a.yaw = 0 }
			}
			consumedNpc[id] = c
			seenNpcPos[id] = seen
		}
		for (id, m) in r.updated { if let a = ctx.npcs[id] { applyMasks(a, m) } }
	}

	/// rt4 `NpcType.getMultiNpc`: the variant selected by the npc's varbit/varp, nil when none.
	private func resolveType(_ a: PathingActor, _ id: Int) {
		guard var t = npcBase[id] else { return }
		if let list = t.multiNpcs, !list.isEmpty {
			let v = env.value(varbit: t.multiVarbit, varp: t.multiVarp, store: store)
			let pick = (v < 0 || v >= list.count - 1 || list[v] == -1) ? list[list.count - 1] : list[v]
			guard pick != -1, let r = (try? store.npc(pick)) ?? nil else { a.npcType = nil; return }
			t = r
		}
		a.npcType = t
		a.size = t.size
	}

	// MARK: cycle

	/// One client cycle (20 ms): actors move, turn and animate; the camera eases towards the player.
	func cycle(varps: [Int: Int32]) {
		ctx.loop += 1
		env.loop = ctx.loop
		env.varps = varps
		for (id, a) in ctx.npcs { resolveType(a, id) }
		for a in ctx.players.values { a.snapshotForInterpolation() }
		for a in ctx.npcs.values { a.snapshotForInterpolation() }
		for (id, a) in ctx.players { a.cycle(isSelf: id == selfIndex) }
		for a in ctx.npcs.values { a.cycle(isSelf: false) }
		updateMotionEffects()
		if camera.scripted != nil {
			camera.updateScripted(tileHeight: groundHeight)
		} else if let me = selfActor {
			camera.follow(playerXFine: me.xFine, playerZFine: me.zFine)
		}
		camera.tickShakes()
		// rt4 clears the minimap flag once the player stands on it.
		if let f = destinationFlag, let t = selfSceneTile, t.x == f.x, t.z == f.z { destinationFlag = nil }
	}

	// MARK: scene build (rt4 LoginManager.rebuildMap + method743 / readLocs)

	/// The frame thread's side of the build: adopts a finished build (the single swap point), then starts a
	/// build when a region change or plane change asks for one. Cheap when nothing is pending.
	func updateBuild() {
		if let done = mailbox.take() { adopt(done) }
		guard inFlightStamp == nil else { return }
		guard needsBuild || (liveScene != nil && builtPlane != plane && rebuild != nil), let r = rebuild else { return }
		needsBuild = false
		var buildStore = store
		var async = false
		if asyncBuild, let iso = store.isolatedCopy() { buildStore = iso; async = true }
		let input = BuildInput(rebuild: r, plane: plane, store: buildStore, textures: textures, env: env, stamp: rebuildStamp, minimap: async, options: sceneOptions)
		if !async {
			adopt(Self.performBuild(input))
			return
		}
		inFlightStamp = input.stamp
		let box = mailbox
		DispatchQueue.global(qos: .userInitiated).async { box.put(Self.performBuild(input)) }
	}

	/// Blocks until a build in flight has finished and swaps it in (tests and shells that must not show the loading box).
	public func finishBuild() {
		updateBuild()
		while inFlightStamp != nil {
			adopt(mailbox.wait())
			updateBuild()
		}
	}

	/// The swap: installs the scene, collision and minimap of a finished build and replays the zone messages
	/// that arrived meanwhile. Everything a build made is owned by the frame thread from here on.
	private func adopt(_ b: BuiltWorld) {
		if b.stamp != rebuildStamp {
			// Overtaken by a newer REBUILD (or a reset); that one has its own build coming.
			if inFlightStamp == b.stamp { inFlightStamp = nil }
			return
		}
		inFlightStamp = nil
		if textures == nil { textures = b.textures }
		buildErrors = b.errors
		lastBuildSeconds = b.seconds
		collision = b.collision
		placer = b.placer
		liveScene = b.scene
		if let s = b.scene {
			builtPlane = b.plane
			buildCount += 1
			placer?.onPlaced = { [weak self] p in self?.onLocPlaced?(p) }
			onSceneAdopted?()
			for p in b.placements { onLocPlaced?(p) }
			if let img = b.minimapImage {
				minimap.image = img
				minimap.builtFor = (buildCount, s.centralPlane)
			}
			placeAllObjStacks()
		}
		let queued = deferredZone
		deferredZone = []
		for m in queued { applyZone(m) }
	}

	/// What a build needs. All of it is either immutable or owned by the build: `store` is a private copy for
	/// background builds, `env` is lock-protected, `textures` is only read for its metadata.
	struct BuildInput: @unchecked Sendable {
		var rebuild: RebuildNormal
		var plane: Int
		var store: ConfigStore
		var textures: TextureStore?
		var env: LocEnvironment
		var stamp: Int
		/// Also render the minimap image (background builds; the frame thread builds it lazily otherwise).
		var minimap: Bool
		var options = SceneOptions()
	}

	/// Runs one scene build without touching any `WorldView` state, so it can run on any thread.
	static func performBuild(_ input: BuildInput) -> BuiltWorld {
		let out = BuiltWorld(stamp: input.stamp, plane: input.plane)
		let t0 = Date()
		let r = input.rebuild, plane = input.plane, store = input.store
		do {
			let ts = try input.textures ?? TextureStore(config: store)
			out.textures = ts
			let defined = ts.meta.map(\.defined)
			let builder = LocModelBuilder(store: store) { id in id >= 0 && id < defined.count && defined[id] }
			let s = Scene(store: store, textures: ts, width: 104, length: 104)
			// rt4 defaults `Preferences.allLevelsVisible` to true: every level is built so roofs exist to be hidden.
			s.allLevelsVisible = input.options.allLevelsVisible
			s.manyGroundTextures = input.options.manyGroundTextures
			let baseX = (r.zoneX - 6) * 8, baseZ = (r.zoneZ - 6) * 8
			let placer = LocPlacer(scene: s, store: store, builder: builder, env: input.env)
			placer.showGroundDecorations = input.options.showGroundDecorations
			var placed: [LocPlacement] = []
			var failures = 0
			if let table = r.chunks {
				failures = try buildDynamic(r, table: table, scene: s, placer: placer, placed: &placed, out: out, store: store)
			} else {
				var squares: [MapSquare] = []
				var collisionSquares: [CollisionBuilder.Square] = []
				var regionLocs: [[MapLoc]] = []
				for (i, region) in r.regions.enumerated() {
					let sq = try store.mapSquare(x: region.x, z: region.z)
					if let sq = sq { squares.append(sq) }
					let key = i < r.xteaKeys.count ? r.xteaKeys[i] : [0, 0, 0, 0]
					let locs = (try? store.mapLocs(x: region.x, z: region.z, key: key)) ?? nil
					regionLocs.append(locs ?? [])
					if let sq = sq { collisionSquares.append(CollisionBuilder.Square(terrain: sq, locs: locs ?? [])) }
				}
				out.collision = (try? CollisionBuilder.build(baseX: baseX, baseZ: baseZ, squares: collisionSquares, locType: { try store.loc($0) }))
					?? (0..<4).map { _ in CollisionMap(width: 104, length: 104) }
				placer.onPlaced = { placed.append($0) }
				try s.loadMapSquares(squares, baseTileX: baseX, baseTileZ: baseZ, centralPlane: plane) { scene in
					for (i, region) in r.regions.enumerated() {
						let locs = regionLocs[i]
						for loc in locs {
							let tx = region.x * 64 + loc.x - baseX, tz = region.z * 64 + loc.z - baseZ
							guard tx > 0 && tz > 0 && tx < 103 && tz < 103 else { continue }
							do { try placer.addLoc(plane: loc.level, locIndex: loc.id, shape: loc.shape, x: tx, z: tz, orientation: loc.rotation) } catch { failures += 1 }
						}
					}
				}
			}
			if failures > 0 { out.errors.append("\(failures) locs failed to place") }
			placer.onPlaced = nil
			out.placements = placed
			out.placer = placer
			out.scene = s
			if input.minimap {
				let mm = Minimap(store: store)
				mm.buildImage(scene: s, level: s.centralPlane, palette: mm.hslPalette())
				out.minimapImage = mm.image
			}
		} catch {
			out.errors.append("scene build failed: \(error)")
			out.scene = nil
		}
		out.seconds = Date().timeIntervalSince(t0)
		return out
	}

	// MARK: drawing

	/// Draws the world into `raster` inside `rect` (game pixels). Returns false when there is nothing to draw yet.
	@discardableResult
	public func draw(into raster: inout Raster, rect: (x: Int, y: Int, w: Int, h: Int)) -> Bool {
		updateBuild()
		if isBuilding {
			gpu.frame = nil
			drawLoadingBox(into: &raster, rect: rect)
			return true
		}
		let t0 = PerfStats.now()
		beginInterpolation()
		defer { endInterpolation() }
		if let g = gpuSettings { return drawGPU(into: &raster, rect: rect, settings: g) } // GPU/
		gpu.frame = nil
		guard let r3 = renderScene(rect: rect, pick: nil) else { return false }
		PerfStats.add(.scene, since: t0)
		let t1 = PerfStats.now()
		r3.copy(into: &raster, x: rect.x, y: rect.y)
		PerfStats.add(.copy3D, since: t1)
		let t2 = PerfStats.now()
		drawOverlays(into: &raster, rect: rect)
		PerfStats.add(.overlays, since: t2)
		return true
	}

	/// Renders the scene into the 3D buffer; with `pick` set, also runs rt4's mouse picking at that
	/// point (game pixels) and leaves the result in `ScenePicker.shared`. Nil when there is nothing to draw yet.
	func renderScene(rect: (x: Int, y: Int, w: Int, h: Int), pick: (x: Int, y: Int)?) -> Rasteriser3D? {
		updateBuild()
		guard let scene = scene, let me = selfActor, rect.w > 0, rect.h > 0 else { return nil }

		// The 3D buffer matches the viewport; textures and brightness are set once per buffer.
		if raster3D == nil || Int(raster3D!.stride) != rect.w || Int(raster3D!.bufferHeight) != rect.h {
			let r3 = Rasteriser3D(width: rect.w, height: rect.h)
			r3.unpackTextures(textures)
			r3.setBrightness(brightness, jitter: false)
			textures?.prewarm(brightness: r3.brightness)
			raster3D = r3
		}
		guard let r3 = raster3D else { return nil }
		r3.setClip(0, 0, rect.w, rect.h)
		r3.prepare()
		r3.clear(0)

		// rt4 `ScriptRunner.method4326`: picking is armed only while the mouse is inside the viewport.
		let picker = ScenePicker.shared
		picker.reset()
		if let p = pick {
			picker.allowInput = true
			picker.mouseX = p.x - rect.x - Int(r3.centerX)
			picker.mouseY = p.y - rect.y - Int(r3.centerY)
			picker.tileRequested = true
			picker.tileMaxLevel = plane
		} else {
			picker.allowInput = false
			picker.tileRequested = false
		}
		defer { picker.allowInput = false; picker.tileRequested = false }

		// Temporary entities of the last frame go, this frame's actors come in (rt4 method3711 / method3240).
		let tPlace = PerfStats.now()
		for s in scene.sceneryList { scene.removeScenery(s) }
		let level = scene.centralPlane
		func place(_ a: PathingActor, key: Int64) {
			guard a.isVisible else { return }
			a.groundY = scene.tileHeight(level: level, xFine: a.xFine, zFine: a.zFine)
			scene.add(level: level, xFine: a.xFine, zFine: a.zFine, y: a.groundY, radius: (a.size - 1) * 64 + 60, entity: a, yaw: a.yaw, key: key, extend: a.stretches)
		}
		/// rt4 renders the spot animation model with the same orientation as its actor (the GL path
		/// draws it as a second model with the actor's key).
		func placeSpot(_ a: PathingActor, key: Int64) {
			guard a.isVisible, let m = spotAnimModel(for: a) else { return }
			scene.add(level: level, xFine: a.xFine, zFine: a.zFine, y: a.groundY, radius: (a.size - 1) * 64 + 60, entity: m, yaw: a.yaw, key: key, extend: false)
		}
		placeActors(place: { place($0, key: $1) }, placeSpot: { placeSpot($0, key: $1) })
		placeMotionEffects(scene: scene, level: level)
		PerfStats.add(.place, since: tPlace)

		camera.clampAngles()
		let groundY = scene.tileHeight(level: level, xFine: me.xFine, zFine: me.zFine)
		let eye = camera.eye(groundY: groundY)
		overlayCamera = OverlayCamera(x: eye.x, y: eye.y, z: eye.z, pitch: eye.pitch, yaw: eye.yaw, level: level,
		                              centerX: Int(r3.centerX), centerY: Int(r3.centerY))
		let playerTile = (x: me.xFine >> 7, z: me.zFine >> 7)
		// rt4 `ScriptRunner.method4302`: roofs above the player (or where the camera ray enters a building) are hidden.
		roofs.mode = roofMode
		roofs.update(scene: scene, plane: level, playerTile: playerTile, cameraX: eye.x, cameraZ: eye.z, pitch: eye.pitch)
		let tDraw = PerfStats.now()
		defer { PerfStats.add(.sceneDraw, since: tDraw) }
		scene.draw(into: r3, cameraX: eye.x, cameraY: eye.y, cameraZ: eye.z, pitch: eye.pitch, yaw: eye.yaw, plane: 3,
		           playerTile: (playerTile.x, playerTile.z),
		           hideMask: roofMode != .never ? roofs.mask : nil, hideFromLevel: level + 1, hideValue: roofs.hideValue, roofBoxes: roofs.boxes)
		return r3
	}

	/// Adds this frame's actors to the scene in rt4's order: the local player, npcs with top render priority,
	/// the other players, then the other npcs (`ScriptRunner.method4326`). With `oneActorPerTile` each pass counts
	/// the actors on every tile centre first; an actor on a tile with a count above one is skipped and
	/// decrements it, so the last actor of a pass is the one drawn, and an actor drawn by an earlier pass
	/// hides all later ones. rt4 walks `PlayerList.ids` / `NpcList.ids` (entry order); ascending index is used here.
	func placeActors(place: (PathingActor, Int64) -> Void, placeSpot: (PathingActor, Int64) -> Void) {
		var counts = [Int](repeating: 0, count: oneActorPerTile ? 104 * 104 : 0)
		func covered(_ a: PathingActor, forDraw: Bool) -> (x0: Int, x1: Int, z0: Int, z1: Int)? {
			let size = a.size
			let cx = a.xFine & 0x7F, cz = a.zFine & 0x7F
			if size == 1 {
				guard cx == 64 && cz == 64 else { return nil }
				let x = a.xFine >> 7, z = a.zFine >> 7
				return (x, x + 1, z, z + 1)
			}
			// rt4's draw test for players has z == 0 for odd sizes (kept); npcs and the count pass use 64.
			let zOdd = (forDraw && a.kind == .player) ? 0 : 64
			guard (size & 1 == 0 && cx == 0 && cz == 0) || (size & 1 == 1 && cx == 64 && cz == (forDraw ? zOdd : 64)) else { return nil }
			let x0 = (a.xFine - size * 64) >> 7, z0 = (a.zFine - size * 64) >> 7
			return (max(x0, 0), min(x0 + size, 104), max(z0, 0), min(z0 + size, 104))
		}
		func pass(_ all: [(PathingActor, Int64)]) {
			let list = all.filter { $0.0.isVisible }
			guard oneActorPerTile else {
				for (a, key) in list { place(a, key); placeSpot(a, key) }
				return
			}
			for (a, _) in list {
				guard let c = covered(a, forDraw: false) else { continue }
				for x in c.x0..<max(c.x0, c.x1) { for z in c.z0..<max(c.z0, c.z1) where x >= 0 && z >= 0 && x < 104 && z < 104 { counts[x * 104 + z] += 1 } }
			}
			for (a, key) in list {
				if let c = covered(a, forDraw: true) {
					let xs = max(c.x0, 0)..<max(max(c.x0, 0), min(c.x1, 104)), zs = max(c.z0, 0)..<max(max(c.z0, 0), min(c.z1, 104))
					if a.size == 1 {
						guard !xs.isEmpty && !zs.isEmpty else { continue }
						if counts[xs.lowerBound * 104 + zs.lowerBound] > 1 { counts[xs.lowerBound * 104 + zs.lowerBound] -= 1; continue }
					} else if !xs.isEmpty && !zs.isEmpty && xs.allSatisfy({ x in zs.allSatisfy { counts[x * 104 + $0] > 1 } }) {
						for x in xs { for z in zs { counts[x * 104 + z] -= 1 } }
						continue
					}
				}
				place(a, key); placeSpot(a, key)
			}
		}
		let npcKey = { (id: Int) in Int64(id) << 32 | 0x2000_0000 }
		let me = ctx.players[selfIndex]
		let npcs = ctx.npcs.sorted { $0.key < $1.key }
		pass(me.map { [($0, Int64(selfIndex) << 32)] } ?? [])
		pass(npcs.filter { $0.value.npcType?.topRenderPriority == true }.map { ($0.value, npcKey($0.key)) })
		pass(ctx.players.sorted { $0.key < $1.key }.filter { $0.key != selfIndex }.map { ($0.value, Int64($0.key) << 32) })
		pass(npcs.filter { $0.value.npcType?.topRenderPriority != true }.map { ($0.value, npcKey($0.key)) })
	}
}
