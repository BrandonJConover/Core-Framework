import Foundation

/// Something drawn per frame rather than baked into a chunk: an animated or multi-state loc (`DynamicLoc`)
/// placed at a scene position.
public struct GPUDynamicRef {
	let entity: SceneEntity
	public let yaw: Int
	public let x: Int, y: Int, z: Int
	/// The tile it hangs off, for roof hiding.
	public let level: Int, tileX: Int, tileZ: Int
}

/// One 8 x 8 tile block of one level, as GPU vertex streams. Geometry is appended tile by tile so a tile's
/// triangles are one contiguous range (`opaqueRanges` / `blendRanges`: `first, count` pairs indexed by
/// `localX * 8 + localZ`), which lets the draw list drop single hidden-roof tiles.
public final class GPUChunkMesh {
	public static let size = 8
	/// Unique per build; a rebuilt chunk gets a new id so the app can drop the old GPU buffers.
	public let id: Int
	public let level: Int, cx: Int, cz: Int
	public internal(set) var opaque: [GPUVertex] = []
	public internal(set) var blend: [GPUVertex] = []
	public internal(set) var opaqueRanges = [Int32](repeating: 0, count: 128)
	public internal(set) var blendRanges = [Int32](repeating: 0, count: 128)
	public internal(set) var bounds = GPUBounds()
	public internal(set) var dynamics: [GPUDynamicRef] = []
	/// Texture ids used by this chunk (for lazy texture upload).
	public internal(set) var textures: Set<Int> = []
	var signature = 0

	init(id: Int, level: Int, cx: Int, cz: Int) { self.id = id; self.level = level; self.cx = cx; self.cz = cz }

	public var isEmpty: Bool { opaque.isEmpty && blend.isEmpty && dynamics.isEmpty }
	public var triangleCount: Int { (opaque.count + blend.count) / 3 }
	/// Bytes of vertex data (for budgeting GPU memory).
	public var byteCount: Int { (opaque.count + blend.count) * MemoryLayout<GPUVertex>.stride }
}

/// One contiguous vertex range of a chunk to draw.
public struct GPUDrawItem {
	/// Index into `GPUDrawList.chunks`.
	public var chunk: Int32
	public var blend: Bool
	public var first: Int32
	public var count: Int32
}

/// What survived culling for one frame.
public struct GPUDrawList {
	public var chunks: [GPUChunkMesh] = []
	/// Opaque items nearest first, then blended items farthest first.
	public var items: [GPUDrawItem] = []
	public var dynamics: [GPUDynamicRef] = []
	/// Chunks tested / kept, for diagnostics.
	public var tested = 0
	public var culledByDistance = 0, culledByFrustum = 0
	public init() {}
	public var triangleCount: Int { items.reduce(0) { $0 + Int($1.count) } / 3 }
}

/// All static geometry of a `Scene` baked into GPU chunks: terrain (plain and shaped tiles, bridges),
/// walls, wall decorations, ground decorations, ground item piles and scenery. Rebuilt per chunk when its
/// content changes (loc add/remove, ground items), detected by a cheap identity signature of the tile
/// nodes; animated locs are kept as dynamic references and meshed every frame.
public final class GPUSceneMesh {
	public static let levels = 4
	public let width: Int, length: Int
	public let chunksX: Int, chunksZ: Int
	public let palette: GPUPalette
	/// `[level][cx][cz]` flattened; nil = nothing to draw there or not built yet.
	public private(set) var chunks: [GPUChunkMesh?]
	private var built: [Bool]
	private var nextID = 1
	private var templates: [ObjectIdentifier: GPUModelTemplate] = [:]
	private var checkTick = 0
	/// Re-verify signatures every this many `update` calls.
	public var signatureInterval = 25
	/// Texture ids used anywhere in the built chunks.
	public private(set) var usedTextures: Set<Int> = []

	public init(scene: Scene, palette: GPUPalette) {
		width = scene.width; length = scene.length
		chunksX = (scene.width + GPUChunkMesh.size - 1) / GPUChunkMesh.size
		chunksZ = (scene.length + GPUChunkMesh.size - 1) / GPUChunkMesh.size
		self.palette = palette
		chunks = [GPUChunkMesh?](repeating: nil, count: Self.levels * chunksX * chunksZ)
		built = [Bool](repeating: false, count: Self.levels * chunksX * chunksZ)
	}

	@inline(__always) func index(_ level: Int, _ cx: Int, _ cz: Int) -> Int { (level * chunksX + cx) * chunksZ + cz }
	public func chunk(level: Int, cx: Int, cz: Int) -> GPUChunkMesh? {
		guard level >= 0, level < Self.levels, cx >= 0, cz >= 0, cx < chunksX, cz < chunksZ else { return nil }
		return chunks[index(level, cx, cz)]
	}
	public var builtCount: Int { built.reduce(0) { $0 + ($1 ? 1 : 0) } }
	public var totalChunks: Int { built.count }
	public var triangleCount: Int { chunks.reduce(0) { $0 + ($1?.triangleCount ?? 0) } }

	// MARK: building

	/// Builds every chunk (tests, first frame of a small scene).
	public func buildAll(scene: Scene) {
		for l in 0..<Self.levels { for cx in 0..<chunksX { for cz in 0..<chunksZ { rebuild(scene, l, cx, cz) } } }
	}

	/// Builds missing chunks nearest `focus` (a scene tile) first, within `timeBudget` seconds (at least
	/// `minChunks` of them), and re-checks signatures of built chunks now and then. Returns chunks left to build.
	@discardableResult
	public func update(scene: Scene, focus: (x: Int, z: Int), timeBudget: Double = 0.006, minChunks: Int = 4) -> Int {
		checkTick += 1
		if checkTick % max(1, signatureInterval) == 0 {
			for l in 0..<Self.levels { for cx in 0..<chunksX { for cz in 0..<chunksZ {
				let i = index(l, cx, cz)
				if built[i], signature(scene, l, cx, cz) != (chunks[i]?.signature ?? Self.emptySignature) { built[i] = false }
			} } }
		}
		var pending: [(d: Int, l: Int, cx: Int, cz: Int)] = []
		for l in 0..<Self.levels { for cx in 0..<chunksX { for cz in 0..<chunksZ where !built[index(l, cx, cz)] {
			let dx = cx * GPUChunkMesh.size + 4 - focus.x, dz = cz * GPUChunkMesh.size + 4 - focus.z
			pending.append((dx * dx + dz * dz + l, l, cx, cz))
		} } }
		pending.sort { $0.d < $1.d }
		let t0 = Date()
		var done = 0
		for p in pending {
			if done >= minChunks && Date().timeIntervalSince(t0) > timeBudget { break }
			rebuild(scene, p.l, p.cx, p.cz)
			done += 1
		}
		return pending.count - done
	}

	static let emptySignature = 0

	/// Mixes the identity of every node on the chunk's tiles. Nodes are replaced (not mutated) when a loc or
	/// ground item changes, so a changed pointer is a changed chunk.
	func signature(_ scene: Scene, _ level: Int, _ cx: Int, _ cz: Int) -> Int {
		var h = 1469598103934665603 &+ level
		@inline(__always) func mix(_ o: AnyObject?) {
			guard let o = o else { h = (h ^ 0x9E37) &* 1099511628211; return }
			h = (h ^ Int(bitPattern: UInt(bitPattern: ObjectIdentifier(o).hashValue))) &* 1099511628211
		}
		let x0 = cx * GPUChunkMesh.size, z0 = cz * GPUChunkMesh.size
		let row = scene.tiles[level]
		for x in x0..<min(x0 + GPUChunkMesh.size, width) {
			for z in z0..<min(z0 + GPUChunkMesh.size, length) {
				guard let t = row[x][z] else { h = (h ^ 1) &* 1099511628211; continue }
				mix(t); mix(t.plainTile); mix(t.shapedTile); mix(t.wall); mix(t.wallDecor); mix(t.groundDecor); mix(t.objStack)
				mix(t.bridgeBelow)
				if let b = t.bridgeBelow { mix(b.wall); mix(b.plainTile); mix(b.shapedTile) }
				for i in 0..<t.sceneryCount { if let s = t.scenery[i], Self.isLoc(s) { mix(s) } }
			}
		}
		return h
	}

	/// Locs have key type 2 (`(key >> 29) & 3`); players, npcs, graphics and projectiles are temporary entities.
	@inline(__always) static func isLoc(_ s: Scenery) -> Bool { ((s.key >> 29) & 3) == 2 }

	private func template(_ model: SoftwareModel, flags: UInt16 = 0) -> GPUModelTemplate {
		let key = ObjectIdentifier(model)
		if let t = templates[key], t.model === model { return t }
		let t = GPUModelTemplate(model, palette: palette, flags: flags)
		templates[key] = t
		return t
	}

	/// Drops cached model templates (a new palette / brightness makes a new `GPUSceneMesh` anyway).
	public func trimTemplates() { templates.removeAll() }

	func rebuild(_ scene: Scene, _ level: Int, _ cx: Int, _ cz: Int) {
		let i = index(level, cx, cz)
		built[i] = true
		let chunk = GPUChunkMesh(id: nextID, level: level, cx: cx, cz: cz)
		nextID += 1
		chunk.signature = signature(scene, level, cx, cz)
		var stream = GPUMeshStream()
		var bounds = GPUBounds()
		let row = scene.tiles[level]
		let x0 = cx * GPUChunkMesh.size, z0 = cz * GPUChunkMesh.size

		func put(_ entity: SceneEntity?, yaw: Int, x: Int, y: Int, z: Int, tx: Int, tz: Int, flags: UInt16 = 0) {
			guard let entity = entity else { return }
			if let m = entity as? SoftwareModel {
				var tpl = template(m)
				if flags != 0 { tpl = GPUModelTemplate(m, palette: palette, flags: flags) }
				bounds.add(tpl.append(to: &stream, yaw: yaw, x: x, y: y, z: z))
			} else if entity is DynamicLoc {
				chunk.dynamics.append(GPUDynamicRef(entity: entity, yaw: yaw, x: x, y: y, z: z, level: level, tileX: tx, tileZ: tz))
			}
		}

		for lx in 0..<GPUChunkMesh.size {
			for lz in 0..<GPUChunkMesh.size {
				let x = x0 + lx, z = z0 + lz
				let slot = (lx * GPUChunkMesh.size + lz) * 2
				chunk.opaqueRanges[slot] = Int32(stream.opaque.count)
				chunk.blendRanges[slot] = Int32(stream.blend.count)
				if x < width, z < length, let t = row[x][z] {
					if let b = t.bridgeBelow {
						GPUTerrainMesher.append(tile: b, scene: scene, palette: palette, into: &stream, bounds: &bounds)
						if let w = b.wall { put(w.primary, yaw: 0, x: w.xFine, y: w.y, z: w.zFine, tx: x, tz: z) }
						for k in 0..<b.sceneryCount {
							if let s = b.scenery[k], Self.isLoc(s), s.xMin == b.x, s.zMin == b.z {
								put(s.entity, yaw: s.yaw, x: s.xFine, y: s.y, z: s.zFine, tx: x, tz: z)
							}
						}
					}
					GPUTerrainMesher.append(tile: t, scene: scene, palette: palette, into: &stream, bounds: &bounds)
					if let w = t.wall {
						put(w.primary, yaw: 0, x: w.xFine, y: w.y, z: w.zFine, tx: x, tz: z)
						put(w.secondary, yaw: 0, x: w.xFine, y: w.y, z: w.zFine, tx: x, tz: z)
					}
					if let d = t.wallDecor {
						put(d.primary, yaw: 0, x: d.xFine + d.xOffset, y: d.y, z: d.zFine + d.zOffset, tx: x, tz: z)
						put(d.secondary, yaw: 0, x: d.xFine, y: d.y, z: d.zFine, tx: x, tz: z)
					}
					if let g = t.groundDecor { put(g.entity, yaw: 0, x: g.xFine, y: g.y, z: g.zFine, tx: x, tz: z, flags: GPUVertex.flagDecal) }
					if let o = t.objStack {
						let y = o.y - o.lift
						put(o.secondary, yaw: 0, x: o.xFine, y: y, z: o.zFine, tx: x, tz: z)
						put(o.tertiary, yaw: 0, x: o.xFine, y: y, z: o.zFine, tx: x, tz: z)
						put(o.primary, yaw: 0, x: o.xFine, y: y, z: o.zFine, tx: x, tz: z)
					}
					for k in 0..<t.sceneryCount {
						if let s = t.scenery[k], Self.isLoc(s), s.xMin == x, s.zMin == z {
							put(s.entity, yaw: s.yaw, x: s.xFine, y: s.y, z: s.zFine, tx: x, tz: z)
						}
					}
				}
				chunk.opaqueRanges[slot + 1] = Int32(stream.opaque.count) - chunk.opaqueRanges[slot]
				chunk.blendRanges[slot + 1] = Int32(stream.blend.count) - chunk.blendRanges[slot]
			}
		}
		chunk.opaque = stream.opaque
		chunk.blend = stream.blend
		var lastMaterial: UInt16 = 0
		for v in stream.opaque + stream.blend where v.material != 0 && v.material != lastMaterial {
			lastMaterial = v.material
			chunk.textures.insert(Int(v.material) - 1)
		}
		chunk.bounds = bounds
		usedTextures.formUnion(chunk.textures)
		chunks[i] = chunk.isEmpty ? nil : chunk
	}

	// MARK: culling

	/// The chunks and ranges to draw from `camera`: levels `minLevel...maxLevel`, within `drawDistanceTiles`
	/// of the eye (horizontally) and inside the view frustum. `hidden(level, x, z)` drops single tiles
	/// (rt4's roof hiding: tiles above the player that the roof flood fill marked).
	public func makeDrawList(camera: GPUCamera, drawDistanceTiles: Int, minLevel: Int = 0, maxLevel: Int = 3,
	                         hideFromLevel: Int = 4, hidden: ((Int, Int, Int) -> Bool)? = nil) -> GPUDrawList {
		var list = GPUDrawList()
		let frustum = camera.frustum
		let eye = camera.position
		let maxDist = Float(drawDistanceTiles * 128)
		var opaque: [(d: Float, item: GPUDrawItem)] = [], blend: [(d: Float, item: GPUDrawItem)] = []
		for l in max(0, minLevel)...min(maxLevel, Self.levels - 1) {
			for cx in 0..<chunksX {
				for cz in 0..<chunksZ {
					guard let c = chunks[index(l, cx, cz)] else { continue }
					list.tested += 1
					let b = c.bounds
					// Horizontal distance from the eye to the nearest point of the chunk's box.
					let dx = max(b.minX - eye.x, 0, eye.x - b.maxX), dz = max(b.minZ - eye.z, 0, eye.z - b.maxZ)
					let dist = (dx * dx + dz * dz).squareRoot()
					let hasStatic = !b.isEmpty
					if hasStatic && dist > maxDist && c.dynamics.isEmpty { list.culledByDistance += 1; continue }
					if hasStatic && !frustum.intersects(b) && c.dynamics.isEmpty { list.culledByFrustum += 1; continue }
					let staticVisible = hasStatic && dist <= maxDist && frustum.intersects(b)
					let ci = Int32(list.chunks.count)
					var used = false
					let anyHidden = hidden != nil && l >= hideFromLevel
					func emit(_ ranges: [Int32], blend isBlend: Bool, total: Int) {
						if total == 0 { return }
						if !anyHidden {
							let item = GPUDrawItem(chunk: ci, blend: isBlend, first: 0, count: Int32(total))
							if isBlend { blend.append((dist, item)) } else { opaque.append((dist, item)) }
							used = true
							return
						}
						// Merge runs of visible tiles into ranges.
						var runStart: Int32 = -1, runEnd: Int32 = 0
						func flush() {
							if runStart >= 0 && runEnd > runStart {
								let item = GPUDrawItem(chunk: ci, blend: isBlend, first: runStart, count: runEnd - runStart)
								if isBlend { blend.append((dist, item)) } else { opaque.append((dist, item)) }
								used = true
							}
							runStart = -1
						}
						for lx in 0..<GPUChunkMesh.size {
							for lz in 0..<GPUChunkMesh.size {
								let slot = (lx * GPUChunkMesh.size + lz) * 2
								let first = ranges[slot], count = ranges[slot + 1]
								if count == 0 { continue }
								if hidden!(l, cx * GPUChunkMesh.size + lx, cz * GPUChunkMesh.size + lz) { flush(); continue }
								if runStart >= 0 && first == runEnd { runEnd = first + count } else { flush(); runStart = first; runEnd = first + count }
							}
						}
						flush()
					}
					if staticVisible {
						emit(c.opaqueRanges, blend: false, total: c.opaque.count)
						emit(c.blendRanges, blend: true, total: c.blend.count)
					}
					for d in c.dynamics {
						if let hide = hidden, d.level >= hideFromLevel, hide(d.level, d.tileX, d.tileZ) { continue }
						let ddx = Float(d.x) - eye.x, ddz = Float(d.z) - eye.z
						if (ddx * ddx + ddz * ddz).squareRoot() <= maxDist + 256 { list.dynamics.append(d); used = true }
					}
					if used { list.chunks.append(c) }
				}
			}
		}
		opaque.sort { $0.d < $1.d }
		blend.sort { $0.d > $1.d }
		list.items = opaque.map(\.item) + blend.map(\.item)
		return list
	}
}
