import Foundation

/// Redirects `SoftwareModel.render` into GPU vertices while active (`SoftwareModel.render` checks it first
/// thing). Entities that build their own model inside `render` (actors, projectiles, graphics, animated
/// locs) are asked to render with a camera at the origin, so the placement they pass on is already the
/// world position. Only used on the game thread, around one frame's dynamic geometry.
final class GPUModelCapture {
	nonisolated(unsafe) static var active: GPUModelCapture?

	let palette: GPUPalette
	var stream = GPUMeshStream()
	var textures = Set<Int>()
	var models = 0

	init(palette: GPUPalette) { self.palette = palette }

	func record(_ model: SoftwareModel, yaw: Int, x: Int, y: Int, z: Int) {
		let t = GPUModelTemplate(model, palette: palette)
		t.append(to: &stream, yaw: yaw, x: x, y: y, z: z)
		textures.formUnion(t.textureIds)
		models += 1
	}
}

/// `WorldView`'s GPU renderer state: the baked scene, the palette, and the last frame.
final class GPUWorldState {
	var mesh: GPUSceneMesh?
	weak var meshScene: Scene?
	var palette: GPUPalette?
	var generation = 0
	var frame: GPUFrame?
	/// Only passed to entities as the (ignored) target of a captured render.
	lazy var dummy = Rasteriser3D(width: 1, height: 1)
	var lastBuildCount = -1
}

extension WorldView {
	/// The frame `draw` prepared for the GPU renderer (nil in software mode or while there is nothing to show).
	public var gpuFrame: GPUFrame? { gpu.frame }

	/// Texture layers for the app's texture array, at the current brightness (nil until a scene has been
	/// built). Create a new one when `GPUFrame.brightness` changes.
	public func makeGPUTextureSet() -> GPUTextureSet? {
		guard let ts = textures else { return nil }
		let palette = gpu.palette ?? GPUPalette(brightness: brightness)
		return GPUTextureSet(store: ts, brightness: brightness, palette: palette)
	}

	/// The baked static scene, for inspection and tests.
	public var gpuMesh: GPUSceneMesh? { gpu.mesh }

	/// GPU counterpart of `renderScene`: places this frame's actors and graphics, runs the roof hider, builds
	/// the camera and the culled draw list, and leaves them in `gpuFrame`. The viewport itself is left
	/// untouched (transparent in a transparent `Raster`); overheads, hit splats and the like are drawn into
	/// the raster as in software mode. Returns false when there is nothing to draw yet.
	func drawGPU(into raster: inout Raster, rect: (x: Int, y: Int, w: Int, h: Int), settings: GPURenderSettings) -> Bool {
		updateBuild()
		guard let scene = scene, let me = selfActor, rect.w > 0, rect.h > 0 else { gpu.frame = nil; return false }
		// Only the viewport lets the Metal scene through; the rest of the 2D layer stays opaque black as in
		// software mode, so the fog colour never shows around a smaller interface.
		raster.clearRect(x: rect.x, y: rect.y, w: rect.w, h: rect.h, transparent: true)

		// Palette and baked scene follow the scene and the brightness setting.
		if gpu.palette == nil || gpu.palette!.brightness != brightness {
			gpu.palette = GPUPalette(brightness: brightness)
			gpu.mesh = nil
		}
		guard let palette = gpu.palette else { return false }
		var fresh = false
		if gpu.mesh == nil || gpu.meshScene !== scene {
			gpu.mesh = GPUSceneMesh(scene: scene, palette: palette)
			gpu.meshScene = scene
			gpu.generation += 1
			fresh = true
		}
		guard let mesh = gpu.mesh else { return false }

		// Temporary entities of the last frame go, this frame's come in (as `renderScene`).
		for s in scene.sceneryList { scene.removeScenery(s) }
		let level = scene.centralPlane
		func place(_ a: PathingActor, key: Int64) {
			guard a.isVisible else { return }
			a.groundY = scene.tileHeight(level: level, xFine: a.xFine, zFine: a.zFine)
			scene.add(level: level, xFine: a.xFine, zFine: a.zFine, y: a.groundY, radius: (a.size - 1) * 64 + 60, entity: a, yaw: a.yaw, key: key, extend: a.stretches)
		}
		func placeSpot(_ a: PathingActor, key: Int64) {
			guard a.isVisible, let m = spotAnimModel(for: a) else { return }
			scene.add(level: level, xFine: a.xFine, zFine: a.zFine, y: a.groundY, radius: (a.size - 1) * 64 + 60, entity: m, yaw: a.yaw, key: key, extend: false)
		}
		placeActors(place: { place($0, key: $1) }, placeSpot: { placeSpot($0, key: $1) })
		placeMotionEffects(scene: scene, level: level)

		camera.clampAngles()
		let groundY = scene.tileHeight(level: level, xFine: me.xFine, zFine: me.zFine)
		let eye = camera.eye(groundY: groundY)
		overlayCamera = OverlayCamera(x: eye.x, y: eye.y, z: eye.z, pitch: eye.pitch, yaw: eye.yaw, level: level,
		                              centerX: rect.w / 2, centerY: rect.h / 2)
		let playerTile = (x: me.xFine >> 7, z: me.zFine >> 7)
		roofs.update(scene: scene, plane: level, playerTile: playerTile, cameraX: eye.x, cameraZ: eye.z, pitch: eye.pitch)

		let tiles = settings.clampedDrawDistance
		let fog = GPUFog.rt4(tiles: tiles, color: settings.fogColor, enabled: settings.fogEnabled)
		var cam = GPUCamera(x: eye.x, y: eye.y, z: eye.z, pitch: eye.pitch, yaw: eye.yaw, width: rect.w, height: rect.h)
		cam.far = Float(tiles * 128) + 768

		let pending = mesh.update(scene: scene, focus: playerTile, timeBudget: fresh ? 0.05 : 0.006, minChunks: fresh ? 12 : 4)
		let mask = removeRoofs ? roofs.mask : nil
		let hideValue = roofs.hideValue
		let list = mesh.makeDrawList(camera: cam, drawDistanceTiles: tiles, minLevel: scene.minLevel, maxLevel: 3,
		                             hideFromLevel: level + 1, hidden: mask.map { m in { l, x, z in m[l][x][z] == hideValue } })

		// Dynamic geometry: temporaries in the scene, then the visible animated locs.
		let cap = GPUModelCapture(palette: palette)
		GPUModelCapture.active = cap
		let ident = 65536
		for s in scene.sceneryList {
			s.entity?.render(gpu.dummy, yaw: s.yaw, sinPitch: 0, cosPitch: ident, sinYaw: 0, cosYaw: ident, x: s.xFine, y: s.y, z: s.zFine, key: s.key)
		}
		for d in list.dynamics {
			d.entity.render(gpu.dummy, yaw: d.yaw, sinPitch: 0, cosPitch: ident, sinYaw: 0, cosYaw: ident, x: d.x, y: d.y, z: d.z, key: 0)
		}
		GPUModelCapture.active = nil

		var used = cap.textures
		for c in list.chunks { used.formUnion(c.textures) }
		var frame = GPUFrame(camera: cam, viewport: rect, settings: settings, fog: fog, list: list, dynamic: cap.stream,
		                     usedTextures: used, brightness: brightness, sceneGeneration: gpu.generation)
		frame.pendingChunks = pending
		gpu.frame = frame

		drawOverlays(into: &raster, rect: rect)
		return true
	}
}
