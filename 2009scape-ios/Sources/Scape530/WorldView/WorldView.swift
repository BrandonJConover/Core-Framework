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
	var locBuilder: LocModelBuilder?
	public private(set) var scene: Scene?
	var raster3D: Rasteriser3D?
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

	/// Seconds the last scene build took, and any build problems.
	public private(set) var lastBuildSeconds = 0.0
	public private(set) var buildErrors: [String] = []
	/// Called with each placed loc (collision flagging hooks in here).
	public var onLocPlaced: ((LocPlacement) -> Void)?
	/// Social state fed by `GameClient` (see `WorldView+Social` / `WorldView+Overlay`).
	/// Public chat decoded from player info, for the chat history.
	public var onPublicChat: ((PublicChatEvent) -> Void)?
	/// True when rt4's ignore rules drop a public chat line from `name37` with staff `rights`.
	public var isChatIgnored: (_ name37: Int64, _ rights: Int) -> Bool = { _, _ in false }
	/// rt4 `Chat.publicFilter`: 0 show all, 1 friends only, 2 hide (3 show all too).
	public var publicFilter = 0
	/// rt4 `VarpDomain.chatEffectsDisabled`: overhead text drawn plain yellow.
	public var chatEffectsDisabled = false
	/// Camera of the last rendered frame.
	var overlayCamera: OverlayCamera?
	/// Incremented every time the scene is rebuilt.
	public private(set) var buildCount = 0

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
	/// The moving click flag on the minimap (scene tile), set when a walk is sent (rt4 `LoginManager.mapFlagX/Z`).
	public var destinationFlag: (x: Int, z: Int)?

	public init(store: ConfigStore) {
		self.store = store
		ctx = WorldContext(store: store, models: ActorModels(store: store))
	}

	public var isReady: Bool { scene != nil && self.selfActor != nil }

	var selfActor: PathingActor? { ctx.players[selfIndex] }

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
		case .message(.rebuildNormal(let r)):
			applyRebuild(r)
		case .message(.spotAnimEntity(let delay, let height, let target, let gfx)):
			applySpotAnimMessage(delay: delay, height: height, target: target, gfx: gfx)
		case .message(let m):
			applyZone(m)
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

	func reset() {
		scene = nil
		raster3D = nil
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
		camera = WorldCamera()
		collision = []
		placer = nil
		objStacks = [:]
		destinationFlag = nil
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
		}
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
		for i in 0..<10 { a.queueX[i] -= dx; a.queueZ[i] -= dz }
	}

	// MARK: entity updates (rt4 Protocol.readPlayerInfoPacket / readNpcPacket)

	private func sync(_ a: PathingActor, _ e: TrackedEntity, consumed: inout Int, isNew: Bool) {
		if isNew {
			a.setPosition(x: e.x, z: e.z, jump: true)
			consumed = e.lastStep.count
			return
		}
		if e.lastStep.count < consumed { consumed = 0 }
		for dir in e.lastStep[consumed...] where dir >= 0 && dir < 8 {
			a.move(speed: e.running ? 2 : 1, direction: dir)
		}
		consumed = e.lastStep.count
		if a.queueX[0] != e.x || a.queueZ[0] != e.z { a.setPosition(x: e.x, z: e.z, jump: false) }
	}

	private func applyMasks(_ a: PathingActor, _ m: EntityMasks) {
		if let anim = m.anim { a.animate(delay: anim.delay, seq: anim.seq) }
		if let f = m.faceEntity { a.faceEntity = f }
		if let t = m.faceTile { a.faceX = t.x; a.faceY = t.z }
		applySocialMasks(a, m)
	}

	func applyPlayers(_ r: PlayerInfoDecoder.Result, _ d: PlayerInfoDecoder) {
		selfIndex = d.selfIndex
		plane = d.plane
		for id in r.removed { ctx.players[id] = nil; consumedPlayer[id] = nil }
		for (id, e) in d.players {
			let isNew = ctx.players[id] == nil
			let a = ctx.players[id] ?? PathingActor(kind: .player, index: id, ctx: ctx)
			if isNew { ctx.players[id] = a }
			if let ap = e.appearance, ap != a.appearance {
				a.appearance = ap
				a.look = PlayerLook(ap)
				a.size = ap.size
			}
			var c = consumedPlayer[id] ?? 0
			sync(a, e, consumed: &c, isNew: isNew)
			consumedPlayer[id] = c
		}
		for (id, m) in r.updated { if let a = ctx.players[id] { applyMasks(a, m) } }
	}

	func applyNpcs(_ r: PlayerInfoDecoder.Result, _ d: NpcInfoDecoder) {
		for id in r.removed { ctx.npcs[id] = nil; consumedNpc[id] = nil; npcBase[id] = nil }
		for (id, e) in d.npcs {
			let isNew = ctx.npcs[id] == nil
			let a = ctx.npcs[id] ?? PathingActor(kind: .npc, index: id, ctx: ctx)
			if isNew { ctx.npcs[id] = a }
			if npcBase[id]?.id != e.type, let t = (try? store.npc(e.type)) ?? nil {
				npcBase[id] = t
				a.fallbackBasId = t.basId
			}
			resolveType(a, id)
			var c = consumedNpc[id] ?? 0
			sync(a, e, consumed: &c, isNew: isNew)
			consumedNpc[id] = c
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
		for (id, a) in ctx.players { a.cycle(isSelf: id == selfIndex) }
		for a in ctx.npcs.values { a.cycle(isSelf: false) }
		if let me = selfActor { camera.follow(playerXFine: me.xFine, playerZFine: me.zFine) }
		// rt4 clears the minimap flag once the player stands on it.
		if let f = destinationFlag, let t = selfSceneTile, t.x == f.x, t.z == f.z { destinationFlag = nil }
	}

	// MARK: scene build (rt4 LoginManager.rebuildMap + method743 / readLocs)

	private func buildScene() {
		guard let r = rebuild else { return }
		let t0 = Date()
		buildErrors = []
		do {
			if textures == nil { textures = try TextureStore(config: store) }
			guard let ts = textures else { return }
			let builder = locBuilder ?? LocModelBuilder(store: store) { id in ts.meta.indices.contains(id) && ts.meta[id].defined }
			locBuilder = builder
			builder.clearCaches()
			let s = Scene(store: store, textures: ts, width: 104, length: 104)
			let baseX = (r.zoneX - 6) * 8, baseZ = (r.zoneZ - 6) * 8
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
			collision = (try? CollisionBuilder.build(baseX: baseX, baseZ: baseZ, squares: collisionSquares, locType: { try self.store.loc($0) }))
				?? (0..<4).map { _ in CollisionMap(width: 104, length: 104) }
			let placer = LocPlacer(scene: s, store: store, builder: builder, env: env)
			placer.onPlaced = { [weak self] p in self?.onLocPlaced?(p) }
			self.placer = placer
			var failures = 0
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
			if failures > 0 { buildErrors.append("\(failures) locs failed to place") }
			scene = s
			builtPlane = plane
			buildCount += 1
			placeAllObjStacks()
		} catch {
			buildErrors.append("scene build failed: \(error)")
			scene = nil
		}
		needsBuild = false
		lastBuildSeconds = Date().timeIntervalSince(t0)
	}

	// MARK: drawing

	/// Draws the world into `raster` inside `rect` (game pixels). Returns false when there is nothing to draw yet.
	@discardableResult
	public func draw(into raster: inout Raster, rect: (x: Int, y: Int, w: Int, h: Int)) -> Bool {
		guard let r3 = renderScene(rect: rect, pick: nil) else { return false }
		r3.copy(into: &raster, x: rect.x, y: rect.y)
		drawOverlays(into: &raster, rect: rect)
		return true
	}

	/// Renders the scene into the 3D buffer; with `pick` set, also runs rt4's mouse picking at that
	/// point (game pixels) and leaves the result in `ScenePicker.shared`. Nil when there is nothing to draw yet.
	func renderScene(rect: (x: Int, y: Int, w: Int, h: Int), pick: (x: Int, y: Int)?) -> Rasteriser3D? {
		if needsBuild || (scene != nil && builtPlane != plane && rebuild != nil) { buildScene() }
		guard let scene = scene, let me = selfActor, rect.w > 0, rect.h > 0 else { return nil }

		// The 3D buffer matches the viewport; textures and brightness are set once per buffer.
		if raster3D == nil || Int(raster3D!.stride) != rect.w || Int(raster3D!.bufferHeight) != rect.h {
			let r3 = Rasteriser3D(width: rect.w, height: rect.h)
			r3.unpackTextures(textures)
			r3.setBrightness(0.8, jitter: false)
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
		for (id, a) in ctx.npcs { place(a, key: Int64(id) << 32 | 0x2000_0000); placeSpot(a, key: Int64(id) << 32 | 0x2000_0000) }
		for (id, a) in ctx.players { place(a, key: Int64(id) << 32); placeSpot(a, key: Int64(id) << 32) }

		camera.clampAngles()
		let groundY = scene.tileHeight(level: level, xFine: me.xFine, zFine: me.zFine)
		let eye = camera.eye(groundY: groundY)
		overlayCamera = OverlayCamera(x: eye.x, y: eye.y, z: eye.z, pitch: eye.pitch, yaw: eye.yaw, level: level,
		                              centerX: Int(r3.centerX), centerY: Int(r3.centerY))
		scene.draw(into: r3, cameraX: eye.x, cameraY: eye.y, cameraZ: eye.z, pitch: eye.pitch, yaw: eye.yaw, plane: level,
		           playerTile: (me.xFine >> 7, me.zFine >> 7))
		return r3
	}
}
