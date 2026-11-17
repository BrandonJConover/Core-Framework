import Foundation

/// Server packets that act on the world's actors, camera and markers (rt4 `Protocol.readPacketInternal` branches
/// NPC_ANIM_SPECIFIC, RESET_ANIMS, HINT_ARROW, CAMERA_DETACH, CAM_LOOKAT, CAM_FORCEANGLE, CAM_SHAKE and CAM_RESET).
extension WorldView {
	/// The scene's ground height at a fine position, for the camera (rt4 `SceneGraph.getTileHeight(Player.plane, ...)`).
	func groundHeight(_ xFine: Int, _ zFine: Int) -> Int {
		guard let s = liveScene else { return 0 }
		return s.tileHeight(level: s.centralPlane, xFine: xFine, zFine: zFine)
	}

	/// Applies the messages that do not depend on the scene being built; false when `m` is not one of them.
	func applyWorldPacket(_ m: ServerMessage) -> Bool {
		switch m {
		case let .npcAnim(npc, delay, seq):
			ctx.npcs[npc]?.animate(delay: delay, seq: seq)
		case .resetAnims:
			for a in ctx.players.values { a.seqId = -1 }
			for a in ctx.npcs.values { a.seqId = -1 }
		case let .hintArrow(h):
			applyHintArrow(h)
		case let .camMoveTo(x, z, height, speed, rotationSpeed):
			camera.moveTo(x: x, z: z, height: height, speed: speed, rotationSpeed: rotationSpeed, snap: true, tileHeight: groundHeight)
		case let .camLookAt(x, z, height, speed, rotationSpeed):
			camera.lookAt(x: x, z: z, height: height, speed: speed, rotationSpeed: rotationSpeed, tileHeight: groundHeight)
		case let .camForceAngle(yaw, pitch):
			camera.yawTarget = Double(yaw)
			camera.pitchTarget = Double(pitch)
			if var c = camera.scripted {
				c.pitch = Int(camera.pitchTarget)
				c.yaw = Int(camera.yawTarget)
				camera.scripted = c
			}
			camera.clampAngles()
		case let .camShake(axis, jitter, amplitude, frequency, phase):
			guard axis >= 0 && axis < 5 else { return true }
			camera.shakes[axis].active = true
			camera.shakes[axis].jitter = jitter
			camera.shakes[axis].amplitude = amplitude
			camera.shakes[axis].frequency = frequency
			camera.shakes[axis].clock = phase
		case .camReset:
			camera.resetEffects()
		default:
			return false
		}
		return true
	}

	/// The CS2 camera opcodes 5500, 5501, 5503, 5504, 5505 and 5506 (rt4 `ScriptRunner`). Coordinates arrive packed as
	/// `plane << 28 | x << 14 | z` in world tiles. nil for any other name (the spline opcodes stay unported).
	func cameraScript(_ name: String, _ a: [Int]) -> Int? {
		func v(_ n: Int) -> Int { n < a.count ? a[n] : 0 }
		switch name {
		case "cameraMoveTo":
			camera.moveTo(x: ((v(0) >> 14) & 0x3FFF) - ctx.originX, z: (v(0) & 0x3FFF) - ctx.originZ, height: v(1), speed: v(2), rotationSpeed: v(3), snap: false, tileHeight: groundHeight)
		case "cameraPointAt":
			camera.lookAt(x: ((v(0) >> 14) & 0x3FFF) - ctx.originX, z: (v(0) & 0x3FFF) - ctx.originZ, height: v(1), speed: v(2), rotationSpeed: v(3), tileHeight: groundHeight)
		case "cameraUnlock":
			camera.resetEffects()
		case "cameraSetAngles":
			camera.pitchTarget = Double(v(0))
			camera.yawTarget = Double(v(1))
			if var c = camera.scripted {
				c.pitch = v(0)
				c.yaw = v(1)
				camera.scripted = c
			}
			camera.clampAngles()
		case "cameraPitch": return Int(camera.pitchTarget)
		case "cameraYaw": return Int(camera.yawTarget)
		default: return nil
		}
		return 0
	}

	/// rt4 HINT_ARROW: a marker whose sprite is not in `hint_headicons` is dropped (rt4 does not read its target either).
	func applyHintArrow(_ h: ServerMessage.HintArrow) {
		guard h.slot >= 0 && h.slot < hintArrows.count else { return }
		let count = ((try? store.sprite(named: "hint_headicons")) ?? nil)?.frames.count ?? 0
		guard h.sprite >= 0 && h.sprite < count else { return }
		hintArrows[h.slot] = h
	}

	/// LOC_ANIM (20) and LOC_ANIM_SPECIFIC (235), rt4 `SceneGraph.method1881`: the loc of the given layer on a scene
	/// tile starts playing `seq` (-1 stops it). The old entity is kept as the loc's predecessor, so an animation that
	/// is already running is carried over.
	func animateLoc(level: Int, x: Int, z: Int, shape: Int, rotation: Int, seq: Int) {
		guard let s = liveScene, let placer = placer, x >= 0, z >= 0, x < 103, z < 103, level >= 0, level < 4 else { return }
		let layer = Self.locLayer(shape)
		func make(_ id: Int, _ shape: Int, _ rotation: Int, _ previous: SceneEntity?) -> SceneEntity {
			placer.animatedLoc(id: id, shape: shape, rotation: rotation, level: level, x: x, z: z, seq: seq, previous: previous)
		}
		func locId(_ key: Int64) -> Int { Int((key >> 32) & Int64(Int32.max)) }
		switch layer {
		case 0:
			guard let wall = s.wall(level: level, x: x, z: z) else { return }
			let id = locId(wall.key)
			if shape == 2 {
				wall.primary = make(id, 2, rotation + 4, wall.primary)
				wall.secondary = make(id, 2, (rotation + 1) & 3, wall.secondary)
			} else {
				wall.primary = make(id, shape, rotation, wall.primary)
			}
		case 1:
			guard let decor = s.wallDecor(level: level, x: x, z: z) else { return }
			let id = locId(decor.key)
			switch shape {
			case 4, 5: decor.primary = make(id, 4, rotation, decor.primary)
			case 6: decor.primary = make(id, 4, rotation + 4, decor.primary)
			case 7: decor.primary = make(id, 4, ((rotation + 2) & 3) + 4, decor.primary)
			case 8:
				decor.primary = make(id, 4, rotation + 4, decor.primary)
				decor.secondary = make(id, 4, ((rotation + 2) & 3) + 4, decor.secondary)
			default: break
			}
		case 2:
			guard let scenery = s.scenery(level: level, x: x, z: z) else { return }
			scenery.entity = make(locId(scenery.key), shape == 11 ? 10 : shape, rotation, scenery.entity)
		default:
			guard let decor = s.groundDecor(level: level, x: x, z: z) else { return }
			decor.entity = make(locId(decor.key), 22, rotation, decor.entity)
		}
	}
}
