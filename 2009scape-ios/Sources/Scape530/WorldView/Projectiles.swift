import Foundation

/// A projectile in flight. Port of rt4 `ProjAnim`: the position is kept in doubles (`x`, `y` on the
/// ground, `z` the height above it, negative up as everywhere in the scene), moved each cycle by a
/// velocity that `setTarget` recomputes so the missile homes in on its target. With an elevation pitch
/// the height follows a parabola (constant acceleration), otherwise a straight line.
final class Projectile: SceneEntity {
	let spotAnimId: Int
	let plane: Int
	let sourceX: Int, sourceY: Int, sourceZ: Int
	/// rt4 `firstCycle` / `lastCycle`: loop counts between which it is visible and alive.
	let firstCycle: Int, lastCycle: Int
	/// rt4 `elevationPitch` (-1 for a straight flight) and `arcScale` (head start along the line, in fine units).
	let elevationPitch: Int
	let arcScale: Int
	/// rt4 `targetIndex`: npc index + 1 when positive, -(player index + 1) when negative, 0 for a tile.
	let targetIndex: Int
	/// rt4 `baseZ`: how far above the target's feet the missile aims (fine units).
	let baseZ: Int
	let seq: SeqType?

	var x = 0.0, y = 0.0, z = 0.0
	var yaw = 0
	private var pitch = 0
	private var velocityX = 0.0, velocityY = 0.0, velocityZ = 0.0, accelerationZ = 0.0, velocity = 0.0
	private var isMobile = false
	private var seqFrame = 0
	private var nextFrame = -1
	private var frameCycle = 0
	private var minY = -32768
	private let store: ConfigStore

	/// rt4 `ProjAnim(spotanimId, plane, sourceX, sourceY, sourceZ, firstCycle, lastCycle, elevationPitch, arcScale, targetIndex, baseZ)`.
	init(store: ConfigStore, spotAnimId: Int, plane: Int, sourceX: Int, sourceY: Int, sourceZ: Int, firstCycle: Int, lastCycle: Int,
	     elevationPitch: Int, arcScale: Int, targetIndex: Int, baseZ: Int) {
		self.store = store
		self.spotAnimId = spotAnimId
		self.plane = plane
		self.sourceX = sourceX
		self.sourceY = sourceY
		self.sourceZ = sourceZ
		self.firstCycle = firstCycle
		self.lastCycle = lastCycle
		self.elevationPitch = elevationPitch
		self.arcScale = arcScale
		self.targetIndex = targetIndex
		self.baseZ = baseZ
		if let t = (try? store.spotAnim(spotAnimId)) ?? nil, t.seq != -1 { seq = (try? store.seq(t.seq)) ?? nil } else { seq = nil }
	}

	/// rt4 `setTarget(targetZ, cycle, targetHeight, targetX)`: aims at a point (fine units) so that it is
	/// reached on `lastCycle + 1`. The first call also places the missile `arcScale` along the line from the source.
	func setTarget(targetY: Int, cycle: Int, targetHeight: Int, targetX: Int) {
		if !isMobile {
			let dy = Double(targetY - sourceY)
			let dx = Double(targetX - sourceX)
			let length = (dx * dx + dy * dy).squareRoot()
			z = Double(sourceZ)
			y = dy * Double(arcScale) / length + Double(sourceY)
			x = Double(arcScale) * dx / length + Double(sourceX)
		}
		let remaining = Double(lastCycle + 1 - cycle)
		velocityY = (Double(targetY) - y) / remaining
		velocityX = (Double(targetX) - x) / remaining
		velocity = (velocityY * velocityY + velocityX * velocityX).squareRoot()
		if elevationPitch == -1 {
			velocityZ = (Double(targetHeight) - z) / remaining
		} else {
			if !isMobile { velocityZ = -velocity * tan(Double(elevationPitch) * 0.02454369) }
			accelerationZ = (Double(targetHeight) - z - velocityZ * remaining) * 2.0 / (remaining * remaining)
		}
	}

	/// rt4 `update(delta)`: moves `delta` cycles along the velocity, then turns to face the way it flies
	/// and steps the graphic's animation.
	func update(_ delta: Int) {
		let d = Double(delta)
		x += velocityX * d
		y += velocityY * d
		isMobile = true
		if elevationPitch == -1 {
			z += velocityZ * d
		} else {
			z += d * accelerationZ * 0.5 * d + d * velocityZ
			velocityZ += accelerationZ * d
		}
		yaw = (Int(atan2(velocityX, velocityY) * 325.949) + 1024) & 0x7FF
		pitch = Int(atan2(velocityZ, velocity) * 325.949) & 0x7FF
		guard let seq = seq, !seq.frames.isEmpty else { return }
		frameCycle += delta
		while seqFrame < seq.frameDelays.count, frameCycle > seq.frameDelays[seqFrame] {
			frameCycle -= seq.frameDelays[seqFrame]
			seqFrame += 1
			if seqFrame >= seq.frames.count {
				seqFrame -= seq.replayOffset
				if seqFrame < 0 || seq.frames.count <= seqFrame { seqFrame = 0 }
			}
			nextFrame = seqFrame + 1
			if seq.frames.count <= nextFrame {
				nextFrame -= seq.replayOffset
				if nextFrame < 0 || nextFrame >= seq.frames.count { nextFrame = -1 }
			}
		}
	}

	// MARK: SceneEntity

	func getMinY() -> Int { minY }

	/// rt4 `ProjAnim.method3703` + `render`: the graphic's model at the current frame, tilted by the flight pitch.
	func render(_ r: Rasteriser3D, yaw orientation: Int, sinPitch: Int, cosPitch: Int, sinYaw: Int, cosYaw: Int, x: Int, y: Int, z: Int, key: Int64) {
		guard let t = (try? store.spotAnim(spotAnimId)) ?? nil,
		      let m = try? store.spotAnimModel(t, frame: seq == nil ? -1 : seqFrame, nextFrame: nextFrame, step: frameCycle) else { return }
		m.rotateX(pitch)
		m.render(r, yaw: orientation, sinPitch: sinPitch, cosPitch: cosPitch, sinYaw: sinYaw, cosYaw: cosYaw, x: x, y: y, z: z, key: key)
		minY = m.getMinY()
	}
}

/// A graphic standing on a tile (rt4 `SpotAnim`, from SPOTANIM_SPECIFIC and ground SPOTANIM_ENTITY):
/// waits `delay` cycles, plays its sequence once, then is gone.
final class GroundSpotAnim: SceneEntity {
	let spotAnimId: Int
	let plane: Int
	let xFine: Int, zFine: Int
	/// Height above the ground in scene units (negative up): rt4 `tileHeight - height`.
	let y: Int
	/// rt4 `anInt590`: first loop on which it shows.
	let startCycle: Int
	/// rt4 `aBoolean41`: finished (or no sequence to play).
	private(set) var finished = false
	private let seq: SeqType?
	private var frame = 0
	private var cycle = 0
	private var minY = -32768
	private let store: ConfigStore

	init(store: ConfigStore, spotAnimId: Int, plane: Int, xFine: Int, zFine: Int, y: Int, delay: Int, loop: Int) {
		self.store = store
		self.spotAnimId = spotAnimId
		self.plane = plane
		self.xFine = xFine
		self.zFine = zFine
		self.y = y
		startCycle = loop + delay
		if let t = (try? store.spotAnim(spotAnimId)) ?? nil, t.seq != -1, let s = (try? store.seq(t.seq)) ?? nil, !s.frames.isEmpty {
			seq = s
		} else {
			seq = nil
		}
		finished = seq == nil
	}

	/// rt4 `method558(delta)`: steps the graphic's sequence; it ends after the last frame. (A graphic
	/// without a sequence is born finished in rt4, so it never shows.)
	func advance(_ delta: Int) {
		guard let seq = seq else { finished = true; return }
		cycle += delta
		while cycle > seq.frameDelays[frame] {
			cycle -= seq.frameDelays[frame]
			frame += 1
			if seq.frames.count <= frame { finished = true; break }
		}
	}

	func getMinY() -> Int { minY }

	func render(_ r: Rasteriser3D, yaw orientation: Int, sinPitch: Int, cosPitch: Int, sinYaw: Int, cosYaw: Int, x: Int, y: Int, z: Int, key: Int64) {
		guard let t = (try? store.spotAnim(spotAnimId)) ?? nil,
		      let m = try? store.spotAnimModel(t, frame: seq == nil ? -1 : frame, nextFrame: -1, step: cycle) else { return }
		m.render(r, yaw: orientation, sinPitch: sinPitch, cosPitch: cosPitch, sinYaw: sinYaw, cosYaw: cosYaw, x: x, y: y, z: z, key: key)
		minY = m.getMinY()
	}
}

extension WorldView {
	// MARK: decode (rt4 Protocol.readZonePacket: MAP_PROJANIM, MAP_PROJANIM_2/3, SPOTANIM_SPECIFIC)

	/// Spawns the projectile or tile graphic of a zone update. Positions that fall outside the scene are dropped, as in rt4.
	func applyMotionUpdate(_ u: ZoneUpdate) {
		guard let scene = scene else { return }
		let level = plane
		func height(_ x: Int, _ z: Int) -> Int { scene.tileHeight(level: level, xFine: x, zFine: z) }
		switch u {
		case let .spotAnim(x, z, id, h, delay):
			let tx = chunk.x + x, tz = chunk.z + z
			guard tx >= 0, tz >= 0, tx < 104, tz < 104, id != 65535 else { return }
			let fx = tx * 128 + 64, fz = tz * 128 + 64
			groundSpots.append(GroundSpotAnim(store: store, spotAnimId: id, plane: level, xFine: fx, zFine: fz, y: height(fx, fz) - h, delay: delay, loop: ctx.loop))
		case let .projectile(op, raw):
			let b = raw[0]
			var sx, sz, dx, dz: Int
			var gfx, target, startH, endH, startDelay, endDelay, pitch, arc: Int
			var sourceHeightAdjust = 0
			if op == ServerProt.mapProjanim {
				// Variant 1: half-tile units, a source entity slot and a signed start height.
				guard raw.count >= 12 else { return }
				sx = chunk.x * 2 + ((b >> 4) & 0xF)
				sz = chunk.z * 2 + (b & 0xF)
				dx = sx + raw[1]
				dz = sz + raw[2]
				gfx = raw[5]
				target = raw[4]
				startH = raw[6]
				endH = raw[7] * 4
				startDelay = raw[8]
				endDelay = raw[9]
				pitch = raw[10]
				arc = raw[11]
				guard sx >= 0, sz >= 0, sx < 208, sz < 208, dx >= 0, dz >= 0, dx < 208, dz < 208, gfx != 65535 else { return }
				sx *= 64; sz *= 64; dx *= 64; dz *= 64
				if raw[3] != 0 { sourceHeightAdjust = attachOffset(source: raw[3], x: &sx, z: &sz) }
				startH -= sourceHeightAdjust
			} else {
				guard raw.count >= 11 else { return }
				gfx = raw[4]
				target = raw[3]
				startH = raw[5] * 4
				endH = raw[6] * 4
				startDelay = raw[7]
				endDelay = raw[8]
				pitch = raw[9]
				arc = raw[10]
				if op == ServerProt.mapProjanim2 {
					// Variant 2: whole tiles within the zone.
					sx = chunk.x + ((b >> 4) & 7)
					sz = chunk.z + (b & 7)
					dx = sx + raw[1]
					dz = sz + raw[2]
					guard sx >= 0, sz >= 0, sx < 104, sz < 104, dx >= 0, dz >= 0, dx < 104, dz < 104, gfx != 65535 else { return }
					sx = sx * 128 + 64; sz = sz * 128 + 64; dx = dx * 128 + 64; dz = dz * 128 + 64
				} else {
					// Variant 3: half-tile units like variant 1.
					sx = chunk.x * 2 + ((b >> 4) & 0xF)
					sz = chunk.z * 2 + (b & 0xF)
					dx = sx + raw[1]
					dz = sz + raw[2]
					guard sx >= 0, sz >= 0, sx < 208, sz < 208, dx >= 0, dz >= 0, dx < 208, dz < 208, gfx != 65535 else { return }
					sx *= 64; sz *= 64; dx *= 64; dz *= 64
				}
			}
			if pitch == 255 { pitch = -1 }
			let p = Projectile(store: store, spotAnimId: gfx, plane: level, sourceX: sx, sourceY: sz, sourceZ: height(sx, sz) - startH,
			                   firstCycle: startDelay + ctx.loop, lastCycle: endDelay + ctx.loop, elevationPitch: pitch, arcScale: arc,
			                   targetIndex: target, baseZ: endH)
			p.setTarget(targetY: dz, cycle: ctx.loop + startDelay, targetHeight: height(dx, dz) - endH, targetX: dx)
			projectiles.append(p)
		default:
			break
		}
	}

	/// The tail of variant 1: a missile can leave from a model part of an actor (hand, staff tip) instead
	/// of its feet. `source` is `index + 1 | slot << 11` for an npc, the negative of that for a player. Moves the
	/// start position by the part's offset (turned with the actor) and returns how much higher it starts.
	private func attachOffset(source: Int, x: inout Int, z: inout Int) -> Int {
		let actor: PathingActor?
		let code: Int
		if source >= 0 {
			code = source - 1
			actor = ctx.npcs[code & 0x7FF]
		} else {
			code = -source - 1
			actor = ctx.players[code & 0x7FF]
		}
		let slot = (code >> 11) & 0xF
		guard let a = actor, let t = a.currentBas.modelRotateTranslate[slot], t.count >= 3 else { return 0 }
		let s = MathTables.sin[a.yaw & 0x7FF], c = MathTables.cos[a.yaw & 0x7FF]
		x += (t[0] * c + t[2] * s) >> 16
		z += (c * t[2] - t[0] * s) >> 16
		return t[1]
	}

	// MARK: cycle (rt4 ScriptRunner.updateSceneProjectiles / method4239)

	/// One client cycle for the projectiles and tile graphics: finished ones go, the others home in on
	/// their target (retargeted every cycle from the target actor's position) and move one step.
	func updateMotionEffects() {
		let loop = ctx.loop
		projectiles.removeAll { p in
			if plane != p.plane || p.lastCycle < loop { return true }
			guard loop >= p.firstCycle, let scene = liveScene else { return false }
			var target: PathingActor?
			if p.targetIndex > 0 { target = ctx.npcs[p.targetIndex - 1] } else if p.targetIndex < 0 { target = ctx.players[-p.targetIndex - 1] }
			if let a = target, a.xFine >= 0, a.xFine < 13312, a.zFine >= 0, a.zFine < 13312 {
				p.setTarget(targetY: a.zFine, cycle: loop, targetHeight: scene.tileHeight(level: p.plane, xFine: a.xFine, zFine: a.zFine) - p.baseZ, targetX: a.xFine)
			}
			p.update(1)
			return false
		}
		groundSpots.removeAll { g in
			if g.plane != plane || g.finished { return true }
			if g.startCycle <= loop {
				g.advance(1)
				return g.finished
			}
			return false
		}
	}

	/// Adds the live projectiles and tile graphics to the scene for this frame (the frame's temporary
	/// entities are cleared before actors are placed).
	func placeMotionEffects(scene: Scene, level: Int) {
		let loop = ctx.loop
		for p in projectiles where p.plane == plane && loop >= p.firstCycle && p.lastCycle >= loop {
			scene.add(level: level, xFine: Int(p.x), zFine: Int(p.y), y: Int(p.z), radius: 60, entity: p, yaw: p.yaw, key: -1, extend: false)
		}
		for g in groundSpots where g.plane == plane && !g.finished && g.startCycle <= loop {
			scene.add(level: level, xFine: g.xFine, zFine: g.zFine, y: g.y, radius: 60, entity: g, yaw: 0, key: -1, extend: false)
		}
	}
}
