import Foundation

/// What an actor needs from the world around it each cycle.
final class WorldContext {
	let store: ConfigStore
	let models: ActorModels
	var scene: Scene?
	/// rt4 `client.loop`.
	var loop = 0
	/// World tile of scene tile (0, 0); rt4 `Camera.originX/Z`.
	var originX = 0, originZ = 0
	/// Index -> actor, for `faceEntity` (npc ids below 32768, players above).
	var npcs: [Int: PathingActor] = [:]
	var players: [Int: PathingActor] = [:]

	init(store: ConfigStore, models: ActorModels) {
		self.store = store
		self.models = models
	}
}

/// Port of rt4 `PathingEntity` plus the per-cycle logic that rt4 keeps in
/// `NpcList` (`method2247` movement, `method949` turning, `method879` animation
/// stepping), shared by players and npcs. Field names say what they do; the
/// rt4 name is in the doc comment.
///
/// Not ported: forced movement (`lerpToForceMove*`), layered animations
/// (`aClass147Array3`), spot animations, hit splats, overhead text, the
/// terrain tilt of large creatures (`method2685`) and BAS roll/pitch.
final class PathingActor: SceneEntity {
	enum Kind {
		case player
		case npc
	}

	let kind: Kind
	let ctx: WorldContext
	/// Server index (player or npc id).
	let index: Int

	// Appearance.
	var look: PlayerLook?
	var appearance: PlayerAppearance?
	var npcType: NpcType?
	/// rt4 `anInt3365`: the unresolved type's BAS, used when the resolved variant has none.
	var fallbackBasId = -1
	/// rt4 `Npc.type.size` or `PlayerAppearance.size`.
	var size = 1

	// Position. rt4 `xFine/zFine`.
	var xFine = 0, zFine = 0
	/// rt4 `movementQueueX/Z/Speed`, newest first; `queueSize` is `movementQueueSize`.
	var queueX = [Int](repeating: 0, count: 10)
	var queueZ = [Int](repeating: 0, count: 10)
	var queueSpeed = [Int](repeating: 0, count: 10)
	var queueSize = 0
	/// rt4 `anInt3417`: steps the actor is behind by (speeds it up to catch up).
	var catchUp = 0
	/// rt4 `anInt3405`: queue length when a movement-blocking animation started.
	var animQueueMark = 0
	/// rt4 `anInt3358`: current speed for BAS movement acceleration.
	var speed = 0

	// Orientation. rt4 `anInt3381` (shown), `anInt3400` (wanted), `anInt3376` (turn rate).
	var yaw = 0
	var targetYaw = 0
	var turnRate = 32
	/// rt4 `anInt3385`, `anInt3414`, `anInt3377`, `anInt3402`, `anInt3387`, `anInt3397`, `aBoolean167`:
	/// state of the accelerated turn used by BAS types with a yaw acceleration.
	var turnTicks = 0, yawVelocity = 0, yawFixed = 0, yawTargetFixed = 0, yawTravelled = 0, yawBrakeAt = 0
	var yawBraking = false
	/// rt4 `faceEntity`, `faceX`, `faceY` (half tiles).
	var faceEntity = -1
	var faceX = 0, faceY = 0

	// Animation state. rt4 `seqId`, `anInt3425` (frame), `anInt3373` (next), `anInt3360` (step), `anInt3371`, `anInt3420`.
	var seqId = -1
	var seqFrame = 0, seqNext = 0, seqStep = 0, seqLoops = 0, seqDelay = 0
	/// rt4 `movementSeqId`, `anInt3407`, `anInt3388`, `anInt3396`.
	var moveSeqId = -1
	var moveFrame = 0, moveNext = 0, moveStep = 0
	/// rt4 `aBoolean171`: the current animation stretches the model's footprint.
	var stretches = false

	/// rt4 `PathingEntity.anInt3424`: ground height at the actor.
	var groundY = 0
	/// rt4 `minY`.
	var minY = -32768

	private var bas = BasType(id: -1)
	private var basId = -2

	init(kind: Kind, index: Int, ctx: WorldContext) {
		self.kind = kind
		self.index = index
		self.ctx = ctx
	}

	// MARK: SceneEntity

	func getMinY() -> Int { minY }

	// MARK: BAS

	/// rt4 `getBasId`: the player's appearance, or the npc type's (resolved) BAS.
	var currentBasId: Int {
		switch kind {
		case .player:
			if let l = look { return l.npcId != -1 ? ((try? ctx.store.npc(l.npcId))??.basId ?? -1) : l.basId }
			return -1
		case .npc:
			let b = npcType?.basId ?? -1
			return b != -1 ? b : fallbackBasId
		}
	}

	var currentBas: BasType {
		let id = currentBasId
		if id != basId {
			basId = id
			bas = id == -1 ? BasType(id: -1) : (((try? ctx.store.bas(id)) ?? nil) ?? BasType(id: -1))
		}
		return bas
	}

	// MARK: position (rt4 PathingEntity.method2683, move, method2689)

	/// rt4 `method2683` (`setPosition`): `x/z` are scene tiles. Unless `jump`, a position within
	/// 8 tiles of the last one is appended to the queue so the actor walks to it.
	func setPosition(x: Int, z: Int, jump: Bool) {
		if seqId != -1, let s = try? ctx.store.seq(seqId), s.moveType == 1 { seqId = -1 }
		if !jump {
			let dx = x - queueX[0], dz = z - queueZ[0]
			if dx >= -8 && dx <= 8 && dz >= -8 && dz <= 8 {
				if queueSize < 9 { queueSize += 1 }
				var i = queueSize
				while i > 0 {
					queueX[i] = queueX[i - 1]; queueZ[i] = queueZ[i - 1]; queueSpeed[i] = queueSpeed[i - 1]
					i -= 1
				}
				queueSpeed[0] = 1
				queueX[0] = x
				queueZ[0] = z
				return
			}
		}
		catchUp = 0
		queueX[0] = x
		queueZ[0] = z
		queueSize = 0
		animQueueMark = 0
		zFine = size * 64 + z * 128
		xFine = size * 64 + x * 128
	}

	/// rt4 `PathingEntity.move(speed, direction)`.
	func move(speed: Int, direction: Int) {
		var x = queueX[0], z = queueZ[0]
		if direction == 0 { x -= 1; z += 1 }
		if seqId != -1, let s = try? ctx.store.seq(seqId), s.moveType == 1 { seqId = -1 }
		if queueSize < 9 { queueSize += 1 }
		var i = queueSize
		while i > 0 {
			queueX[i] = queueX[i - 1]; queueZ[i] = queueZ[i - 1]; queueSpeed[i] = queueSpeed[i - 1]
			i -= 1
		}
		if direction == 1 { z += 1 }
		queueSpeed[0] = speed
		if direction == 2 { z += 1; x += 1 }
		if direction == 3 { x -= 1 }
		if direction == 4 { x += 1 }
		if direction == 5 { z -= 1; x -= 1 }
		if direction == 6 { z -= 1 }
		if direction == 7 { z -= 1; x += 1 }
		queueX[0] = x
		queueZ[0] = z
	}

	/// rt4 `method2689`.
	func clearQueue() {
		queueSize = 0
		animQueueMark = 0
	}

	/// rt4 `Player.animate` / `Protocol.animateNpc`.
	func animate(delay: Int, seq newSeq: Int) {
		if newSeq == seqId && newSeq != -1 {
			guard let s = (try? ctx.store.seq(newSeq)) ?? nil else { return }
			if s.exactMove == 1 {
				seqDelay = delay
				seqStep = 0
				seqNext = 1
				seqFrame = 0
				seqLoops = 0
			}
			if s.exactMove == 2 { seqLoops = 0 }
		} else {
			let newPriority = newSeq == -1 ? 0 : ((try? ctx.store.seq(newSeq)) ?? nil)?.priority ?? 0
			let oldPriority = seqId == -1 ? 0 : ((try? ctx.store.seq(seqId)) ?? nil)?.priority ?? 0
			if newSeq == -1 || seqId == -1 || newPriority >= oldPriority {
				seqNext = 1
				seqFrame = 0
				seqDelay = delay
				animQueueMark = queueSize
				seqLoops = 0
				seqStep = 0
				seqId = newSeq
			}
		}
	}

	// MARK: per-cycle update (rt4 NpcList.method4514)

	/// One client cycle (20 ms) of movement, turning and animation.
	func cycle(isSelf: Bool) {
		updateMovement()
		if xFine < 128 || zFine < 128 || xFine >= 13184 || zFine >= 13184 {
			seqId = -1
			xFine = queueX[0] * 128 + size * 64
			zFine = queueZ[0] * 128 + size * 64
			clearQueue()
		}
		if isSelf && (xFine < 1536 || zFine < 1536 || xFine >= 11776 || zFine >= 11776) {
			seqId = -1
			xFine = queueX[0] * 128 + size * 64
			zFine = queueZ[0] * 128 + size * 64
			clearQueue()
		}
		updateFacing()
		updateAnimations()
	}

	/// rt4 `NpcList.method2247`: moves towards the oldest queued tile and picks the walk/run animation.
	func updateMovement() {
		let b = currentBas
		moveSeqId = b.idle
		if queueSize == 0 {
			catchUp = 0
			return
		}
		if seqId != -1 && seqDelay == 0, let s = (try? ctx.store.seq(seqId)) ?? nil {
			if animQueueMark > 0 && s.loopType == 0 { catchUp += 1; return }
			if animQueueMark <= 0 && s.moveType == 0 { catchUp += 1; return }
		}
		let fromX = xFine, fromZ = zFine
		let toX = queueX[queueSize - 1] * 128 + size * 64
		let toZ = queueZ[queueSize - 1] * 128 + size * 64
		if toX - fromX > 256 || toX - fromX < -256 || toZ - fromZ > 256 || toZ - fromZ < -256 {
			xFine = toX
			zFine = toZ
			return
		}
		if toX <= fromX {
			if fromX <= toX {
				if toZ > fromZ { targetYaw = 1024 } else if fromZ > toZ { targetYaw = 0 }
			} else if toZ > fromZ { targetYaw = 768 } else if toZ < fromZ { targetYaw = 256 } else { targetYaw = 512 }
		} else if toZ > fromZ { targetYaw = 1280 } else if fromZ > toZ { targetYaw = 1792 } else { targetYaw = 1536 }

		var turn = (targetYaw - yaw) & 0x7FF
		var anim = b.walkFullTurn
		if turn > 1024 { turn -= 2048 }
		var rotates = true
		var runFlag = 1
		if turn >= -256 && turn <= 256 {
			anim = b.walk
		} else if turn >= 256 && turn < 768 {
			anim = b.walkCW
		} else if turn >= -768 && turn <= -256 {
			anim = b.walkCCW
		}
		var step = 4
		if anim == -1 { anim = b.walk }
		moveSeqId = anim
		if kind == .npc { rotates = npcType?.rotationFlag ?? true }
		if rotates {
			if yaw != targetYaw && faceEntity == -1 && turnRate != 0 { step = 2 }
			if queueSize > 2 { step = 6 }
			if queueSize > 3 { step = 8 }
			if catchUp > 0 && queueSize > 1 { step = 8; catchUp -= 1 }
		} else {
			if queueSize > 1 { step = 6 }
			if queueSize > 2 { step = 8 }
			if catchUp > 0 && queueSize > 1 { catchUp -= 1; step = 8 }
		}
		if queueSpeed[queueSize - 1] == 2 {
			step <<= 1
			runFlag = 2
		} else if queueSpeed[queueSize - 1] == 0 {
			runFlag = 0
			step >>= 1
		}
		if step < 8 || b.run == -1 {
			if b.slowWalk != -1 && runFlag == 0 {
				if b.walkFullTurn == moveSeqId && b.slowWalkFullTurn != -1 {
					moveSeqId = b.slowWalkFullTurn
				} else if b.walkCCW == moveSeqId && b.slowWalkCCW != -1 {
					moveSeqId = b.slowWalkCCW
				} else if b.walkCW == moveSeqId && b.slowWalkCW != -1 {
					moveSeqId = b.slowWalkCW
				} else {
					moveSeqId = b.slowWalk
				}
			}
		} else if b.walkFullTurn == moveSeqId && b.runFullTurn != -1 {
			moveSeqId = b.runFullTurn
		} else if moveSeqId == b.walkCCW && b.runCCW != -1 {
			moveSeqId = b.runCCW
		} else if moveSeqId == b.walkCW && b.runCW != -1 {
			moveSeqId = b.runCW
		} else {
			moveSeqId = b.run
		}
		if b.movementAcceleration != -1 {
			step <<= 7
			if queueSize == 1 {
				let dx = abs(toX - xFine) << 7
				let v2 = speed * speed
				let dz = abs(toZ - zFine) << 7
				let dist = max(dx, dz)
				let brake = b.movementAcceleration * 2 * dist
				if brake < v2 {
					speed /= 2
				} else if dist < v2 / 2 {
					speed -= b.movementAcceleration
					if speed < 0 { speed = 0 }
				} else if speed < step {
					speed += b.movementAcceleration
					if speed > step { speed = step }
				}
			} else if step > speed {
				speed += b.movementAcceleration
				if step < speed { speed = step }
			} else if speed > 0 {
				speed -= b.movementAcceleration
				if speed < 0 { speed = 0 }
			}
			step = speed >> 7
			if step < 1 { step = 1 }
		}
		if fromX < toX {
			xFine += step
			if toX < xFine { xFine = toX }
		} else if fromX > toX {
			xFine -= step
			if toX > xFine { xFine = toX }
		}
		if fromZ < toZ {
			zFine += step
			if zFine > toZ { zFine = toZ }
		} else if toZ < fromZ {
			zFine -= step
			if toZ > zFine { zFine = toZ }
		}
		if xFine == toX && toZ == zFine {
			queueSize -= 1
			if animQueueMark > 0 { animQueueMark -= 1 }
		}
	}

	/// rt4 `NpcList.method949`: turns towards the wanted yaw, at a fixed rate or with BAS acceleration.
	func updateFacing() {
		if turnRate == 0 { return }
		let b = currentBas
		if faceEntity != -1 && faceEntity < 32768 {
			if let n = ctx.npcs[faceEntity] {
				let dz = zFine - n.zFine, dx = xFine - n.xFine
				if dx != 0 || dz != 0 { targetYaw = Self.angle(dx, dz) }
			}
		}
		if faceEntity >= 32768 {
			if let p = ctx.players[faceEntity - 32768] {
				let dz = zFine - p.zFine, dx = xFine - p.xFine
				if dx != 0 || dz != 0 { targetYaw = Self.angle(dx, dz) }
			}
		}
		if (faceX != 0 || faceY != 0) && (queueSize == 0 || catchUp > 0) {
			let dx = xFine - (faceX - ctx.originX - ctx.originX) * 64
			let dz = zFine - (faceY - ctx.originZ - ctx.originZ) * 64
			if dx != 0 || dz != 0 { targetYaw = Self.angle(dx, dz) }
			faceY = 0
			faceX = 0
		}
		let diff = (targetYaw - yaw) & 0x7FF
		if diff == 0 {
			turnTicks = 0
			yawVelocity = 0
		} else if b.yaw.acceleration == 0 {
			turnTicks += 1
			var turning: Bool
			if diff > 1024 {
				yaw -= turnRate
				turning = true
				if diff < turnRate || diff > 2048 - turnRate {
					yaw = targetYaw
					turning = false
				}
				if b.idle == moveSeqId && (turnTicks > 25 || turning) {
					moveSeqId = b.standingCCW == -1 ? b.walk : b.standingCCW
				}
			} else {
				turning = true
				yaw += turnRate
				if turnRate > diff || diff > 2048 - turnRate {
					turning = false
					yaw = targetYaw
				}
				if b.idle == moveSeqId && (turnTicks > 25 || turning) {
					moveSeqId = b.standingCW == -1 ? b.walk : b.standingCW
				}
			}
			yaw &= 0x7FF
		} else {
			if b.idle == moveSeqId && turnTicks > 25 {
				moveSeqId = b.standingCW == -1 ? b.walk : b.standingCW
			}
			let want = targetYaw << 5
			if want != yawTargetFixed {
				yawTravelled = 0
				yawTargetFixed = want
				let delta = (want - yawFixed) & 0xFFFF
				let stop = yawVelocity * yawVelocity / (b.yaw.acceleration * 2)
				if yawVelocity > 0 && delta >= stop && delta - stop < 32768 {
					yawBrakeAt = delta / 2
					yawBraking = true
					var limit = b.yaw.maxSpeed * b.yaw.maxSpeed / (b.yaw.acceleration * 2)
					if limit > 32767 { limit = 32767 }
					if limit < yawBrakeAt { yawBrakeAt = delta - limit }
				} else if yawVelocity < 0 && stop <= 65536 - delta && 65536 - delta - stop < 32768 {
					yawBrakeAt = (65536 - delta) / 2
					yawBraking = true
					var limit = b.yaw.maxSpeed * b.yaw.maxSpeed / (b.yaw.acceleration * 2)
					if limit > 32767 { limit = 32767 }
					if limit < yawBrakeAt { yawBrakeAt = 65536 - delta - limit }
				} else {
					yawBraking = false
				}
			}
			if yawVelocity == 0 {
				let delta = (yawTargetFixed - yawFixed) & 0xFFFF
				if delta < b.yaw.acceleration {
					yawFixed = yawTargetFixed
				} else {
					yawTravelled = 0
					var limit = b.yaw.maxSpeed * b.yaw.maxSpeed / (b.yaw.acceleration * 2)
					yawBraking = true
					if limit > 32767 { limit = 32767 }
					if delta >= 32768 {
						yawVelocity = -b.yaw.acceleration
						yawBrakeAt = (65536 - delta) / 2
						if limit < yawBrakeAt { yawBrakeAt = 65536 - delta - limit }
					} else {
						yawVelocity = b.yaw.acceleration
						yawBrakeAt = delta / 2
						if limit < yawBrakeAt { yawBrakeAt = delta - limit }
					}
				}
			} else if yawVelocity <= 0 {
				if yawTravelled >= yawBrakeAt { yawBraking = false }
				if !yawBraking {
					yawVelocity += b.yaw.acceleration
					if yawVelocity > 0 { yawVelocity = 0 }
				} else if -b.yaw.maxSpeed < yawVelocity {
					yawVelocity -= b.yaw.acceleration
				}
			} else {
				if yawBrakeAt <= yawTravelled { yawBraking = false }
				if !yawBraking {
					yawVelocity -= b.yaw.acceleration
					if yawVelocity < 0 { yawVelocity = 0 }
				} else if yawVelocity < b.yaw.maxSpeed {
					yawVelocity += b.yaw.acceleration
				}
			}
			yawFixed += yawVelocity
			yawFixed &= 0xFFFF
			yawTravelled += abs(yawVelocity)
			yaw = yawFixed >> 5
		}
	}

	/// rt4 `(int) (Math.atan2(dx, dz) * 325.949) & 0x7FF`.
	static func angle(_ dx: Int, _ dz: Int) -> Int {
		Int(atan2(Double(dx), Double(dz)) * 325.949) & 0x7FF
	}

	/// rt4 `NpcList.method879`: advances the movement and action animations by one cycle.
	func updateAnimations() {
		stretches = false
		let store = ctx.store
		if moveSeqId != -1 {
			if let s = (try? store.seq(moveSeqId)) ?? nil, !s.frames.isEmpty {
				moveStep += 1
				if s.frames.count > moveFrame && moveStep > s.frameDelays[moveFrame] {
					moveStep = 1
					moveFrame += 1
					moveNext += 1
				}
				if moveFrame >= s.frames.count {
					moveFrame = 0
					moveStep = 0
				}
				moveNext = moveFrame + 1
				if moveNext >= s.frames.count { moveNext = 0 }
			} else {
				moveSeqId = -1
			}
		}
		// rt4: a looping-type-1 animation waits (delay 1) while the actor still has queued moves from when it started.
		// The forced-move cycle fields are zero here, so the `client.loop` comparisons always hold.
		if seqId != -1 && seqDelay <= 1 {
			if let s = (try? store.seq(seqId)) ?? nil, s.loopType == 1 && animQueueMark > 0 && ctx.loop >= 0 && ctx.loop > 0 {
				seqDelay = 1
				return
			}
		}
		if seqId != -1 && seqDelay == 0 {
			if let s = (try? store.seq(seqId)) ?? nil, !s.frames.isEmpty {
				seqStep += 1
				if seqFrame < s.frames.count && seqStep > s.frameDelays[seqFrame] {
					seqStep = 1
					seqFrame += 1
				}
				if s.frames.count <= seqFrame {
					seqFrame -= s.replayOffset
					seqLoops += 1
					if seqLoops >= s.replayCount {
						seqId = -1
					} else if seqFrame >= 0 && s.frames.count > seqFrame {
						// loops
					} else {
						seqId = -1
					}
				}
				seqNext = seqFrame + 1
				if seqNext >= s.frames.count {
					seqNext -= s.replayOffset
					if s.replayCount <= seqLoops + 1 {
						seqNext = -1
					} else if seqNext < 0 || seqNext >= s.frames.count {
						seqNext = -1
					}
				}
				stretches = s.stretches
			} else {
				seqId = -1
			}
		}
		if seqDelay > 0 { seqDelay -= 1 }
	}

	// MARK: rendering

	/// The posed model for this cycle (rt4 `Player.render` / `Npc.render` model building).
	func buildModel() -> SoftwareModel? {
		let store = ctx.store
		let action: SeqType? = (seqId != -1 && seqDelay == 0) ? ((try? store.seq(seqId)) ?? nil) : nil
		let b = currentBas
		var movement: SeqType?
		if moveSeqId != -1 && !(moveSeqId == b.idle && action != nil) { movement = (try? store.seq(moveSeqId)) ?? nil }
		let actionPose = action.map { SeqPose(seq: $0, frame: seqFrame, nextFrame: seqNext, step: seqStep) }
		let movePose = movement.map { SeqPose(seq: $0, frame: moveFrame, nextFrame: moveNext, step: moveStep) }
		switch kind {
		case .player:
			guard let look = look else { return nil }
			return try? ctx.models.player(look, action: actionPose, movement: movePose)
		case .npc:
			guard let t = npcType else { return nil }
			return try? ctx.models.npc(t, action: actionPose, movement: movePose)
		}
	}

	var isVisible: Bool { kind == .player ? look != nil : npcType != nil }

	func render(_ r: Rasteriser3D, yaw orientation: Int, sinPitch: Int, cosPitch: Int, sinYaw: Int, cosYaw: Int, x: Int, y: Int, z: Int, key: Int64) {
		guard let m = buildModel() else { return }
		minY = m.getMinY()
		m.pickable = true // rt4 `Player.render` / `Npc.render`
		m.render(r, yaw: orientation, sinPitch: sinPitch, cosPitch: cosPitch, sinYaw: sinYaw, cosYaw: cosYaw, x: x, y: y, z: z, key: key)
	}
}
