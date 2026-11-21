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
	/// The local player's index (rt4 `PlayerList.selfId`), so sound cues of its own actions are full volume.
	var selfIndex = -1
	/// rt4 `Preferences.characterShadowsOn`.
	var characterShadows = true
	/// rt4 `ShadowModelList.SHADOWS`.
	let shadows = ShadowModelList()
	/// rt4 `SoundPlayer.playSeqSound(zFine, seq, xFine, self, index)`: an animation reached cue `index`
	/// at an actor's fine position. See `WorldView.onSeqFrameSound`.
	var onSeqSound: ((_ seq: SeqType, _ index: Int, _ xFine: Int, _ zFine: Int, _ isSelf: Bool) -> Void)?

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
/// Forced movement (`lerpToForceMove*`) and layered animations (`aClass147Array3`) are ported
/// (see `applyForceMove`, `applyLayeredAnims`). Render-time effects: the character shadow
/// (`ShadowModelList`), BAS roll and pitch (`method2687`, `AxisSpring`) and the terrain tilt of
/// large creatures (`method2685`, `FootprintTilt`).
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
	var look: PlayerLook? { didSet { lookVersion &+= 1 } }
	private var lookVersion = 0
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

	/// One layered animation (rt4 `PathingEntity_Class147`): plays on the model parts of its slot
	/// on top of the action and movement animations.
	struct LayerAnim: Equatable {
		/// `anInt5396`
		var seq: Int
		/// `anInt5398`: the next frame for tweening, -1 for none.
		var next: Int
		/// `anInt5399`
		var frame: Int
		/// `anInt5400`: completed loops.
		var loops: Int
		/// `anInt5404`: cycles into the frame.
		var step: Int
		/// `anInt5408`: cycles left before it starts.
		var delay: Int
	}
	/// rt4 `aClass147Array3`: one slot per model part bit.
	var layers = [LayerAnim?](repeating: nil, count: 12)

	// Forced movement (rt4 `forceMoveStartX/Y`, `forceMoveDestX/Y`, `forceMoveCyclesToStart/Dest`,
	// `forceMoveDirection`): the actor is dragged from start to destination tile between two loop counts.
	var forceStartX = 0, forceStartZ = 0, forceDestX = 0, forceDestZ = 0
	var forceCyclesToStart = 0, forceCyclesToDest = 0
	var forceDirection = 0

	// Overhead text (rt4 `chatMessage`, `chatEffect`, `chatColor`, `chatLoops`; `OverheadChat.loop` ticks it down).
	var chatMessage: String?
	var chatEffect = 0, chatColor = 0, chatLoops = 0

	// Hit splats and health bar (rt4 `hitDamages`, `hitTypes`, `hitVisibleUntil`, `hitpointsBar*`).
	var hitDamages = [Int](repeating: 0, count: 4)
	var hitTypes = [Int](repeating: 0, count: 4)
	var hitVisibleUntil = [Int](repeating: 0, count: 4)
	var hitpointsBar = 0
	var hitpointsBarVisibleUntil = -1000

	// Spot animation (rt4 `spotAnimId`, `spotAnimStart`, `anInt3399` frame, `anInt3418` next frame,
	// `anInt3361` frame cycle, `spotAnimY`).
	var spotAnimId = -1
	var spotAnimStart = 0
	var spotFrame = 0, spotNext = -1, spotStep = 0
	var spotAnimY = 0

	/// Position and facing at the start of the latest client cycle, for render-side interpolation.
	var prevXFine = 0, prevZFine = 0, prevYaw = 0
	@inline(__always) func snapshotForInterpolation() { prevXFine = xFine; prevZFine = zFine; prevYaw = yaw }

	/// rt4 `PathingEntity.anInt3424`: ground height at the actor.
	var groundY = 0
	/// rt4 `minY`.
	var minY = -32768
	/// rt4 `anInt3419/3383/3355/3398/aBoolean170` (roll) and `anInt3367/3427/3423/3357/aBoolean169` (pitch).
	var roll = AxisSpring(), pitch = AxisSpring()
	/// `ctx.loop` of the last roll/pitch step: rt4 steps them once per drawn frame, one per client cycle.
	private var rollPitchLoop = -1

	private var bas = BasType(id: -1)
	private var basId = -2

	init(kind: Kind, index: Int, ctx: WorldContext) {
		self.kind = kind
		self.index = index
		self.ctx = ctx
	}

	// MARK: SceneEntity

	func getMinY() -> Int { minY }

	// MARK: sound cues

	/// rt4 `SoundPlayer.playSeqSound` for this actor (the world forwards it to the audio mixer).
	func playSeqSound(_ seq: SeqType, _ cue: Int) {
		guard seq.soundEffects != nil else { return }
		ctx.onSeqSound?(seq, cue, xFine, zFine, kind == .player && index == ctx.selfIndex)
	}

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
				playSeqSound(s, seqFrame)
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
				if newSeq != -1, let s = (try? ctx.store.seq(newSeq)) ?? nil { playSeqSound(s, seqFrame) }
			}
		}
	}

	/// rt4 `Protocol.readExtendedPlayerInfo` mask 0x400: `[startX, startZ, destX, destZ, cyclesToStart,
	/// cyclesToDest, direction]` (tiles; the cycle counts are relative to now).
	func applyForceMove(_ v: [Int]) {
		guard v.count == 7 else { return }
		forceStartX = v[0]; forceStartZ = v[1]
		forceDestX = v[2]; forceDestZ = v[3]
		forceCyclesToStart = v[4] + ctx.loop
		forceCyclesToDest = v[5] + ctx.loop
		forceDirection = v[6]
		queueSize = 1
		animQueueMark = 0
	}

	/// rt4 `Player.method865` / `Protocol.method3037`: layered animation masks. Each entry starts
	/// (or restarts, or clears with seq -1) the animation on every slot whose bit is set.
	func applyLayeredAnims(_ list: [LayeredAnim]) {
		for l in list {
			var slot = 0
			var bits = l.slotMask
			while bits != 0 && slot < layers.count {
				defer { slot += 1; bits >>= 1 }
				guard bits & 1 != 0 else { continue }
				if l.seq == -1 { layers[slot] = nil; continue }
				guard let s = (try? ctx.store.seq(l.seq)) ?? nil else { continue }
				if let cur = layers[slot] {
					if l.seq == cur.seq {
						if s.exactMove == 0 {
							layers[slot] = nil
						} else if s.exactMove == 1 {
							layers[slot] = LayerAnim(seq: l.seq, next: 1, frame: 0, loops: 0, step: 0, delay: l.delay)
							playSeqSound(s, 0)
							continue
						} else if s.exactMove == 2 {
							layers[slot]?.loops = 0
						}
					} else if let old = (try? ctx.store.seq(cur.seq)) ?? nil, s.priority >= old.priority {
						layers[slot] = nil
					}
				}
				if layers[slot] == nil {
					layers[slot] = LayerAnim(seq: l.seq, next: 1, frame: 0, loops: 0, step: 0, delay: l.delay)
					playSeqSound(s, 0)
				}
			}
		}
	}

	// MARK: per-cycle update (rt4 NpcList.method4514)

	/// One client cycle (20 ms) of movement, turning and animation.
	func cycle(isSelf: Bool) {
		// rt4 `OverheadChat.loop`.
		if chatLoops > 0 {
			chatLoops -= 1
			if chatLoops == 0 { chatMessage = nil }
		}
		if ctx.loop < forceCyclesToStart {
			lerpToForceMoveStart()
		} else if forceCyclesToDest >= ctx.loop {
			lerpToForceMoveDest()
		} else {
			updateMovement()
		}
		if xFine < 128 || zFine < 128 || xFine >= 13184 || zFine >= 13184 {
			seqId = -1
			spotAnimId = -1
			forceCyclesToStart = 0
			forceCyclesToDest = 0
			xFine = queueX[0] * 128 + size * 64
			zFine = queueZ[0] * 128 + size * 64
			clearQueue()
		}
		if isSelf && (xFine < 1536 || zFine < 1536 || xFine >= 11776 || zFine >= 11776) {
			spotAnimId = -1
			forceCyclesToStart = 0
			forceCyclesToDest = 0
			seqId = -1
			xFine = queueX[0] * 128 + size * 64
			zFine = queueZ[0] * 128 + size * 64
			clearQueue()
		}
		updateFacing()
		updateAnimations()
	}

	/// rt4 `forceMoveDirection` to the yaw the actor faces while dragged.
	private func forceMoveYaw() -> Int? {
		switch forceDirection {
		case 0: return 1024
		case 1: return 1536
		case 2: return 0
		case 3: return 512
		default: return nil
		}
	}

	/// rt4 `NpcList.lerpToForceMoveStart`: before the forced move begins the actor eases (a
	/// `1 / cyclesLeft` share of the distance per cycle) to its start tile.
	func lerpToForceMoveStart() {
		let left = forceCyclesToStart - ctx.loop
		let startX = forceStartX * 128 + size * 64
		let startZ = forceStartZ * 128 + size * 64
		xFine += (startX - xFine) / left
		zFine += (startZ - zFine) / left
		if let y = forceMoveYaw() { targetYaw = y }
		catchUp = 0
	}

	/// rt4 `NpcList.lerpToForceMoveDest`: between the two cycle counts the position is the linear
	/// interpolation from start to destination. Like rt4 it is only refreshed when the animation is
	/// not mid-frame (or on the last cycle), so the actor does not shimmer against its own animation.
	func lerpToForceMoveDest() {
		var refresh = ctx.loop == forceCyclesToDest || seqId == -1 || seqDelay != 0
		if !refresh, let s = (try? ctx.store.seq(seqId)) ?? nil, seqFrame >= 0, seqFrame < s.frameDelays.count {
			refresh = seqStep + 1 > s.frameDelays[seqFrame]
		}
		let span = forceCyclesToDest - forceCyclesToStart
		if refresh && span != 0 {
			let t = ctx.loop - forceCyclesToStart
			let startX = forceStartX * 128 + size * 64, startZ = forceStartZ * 128 + size * 64
			let destX = forceDestX * 128 + size * 64, destZ = forceDestZ * 128 + size * 64
			xFine = (t * destX + startX * (span - t)) / span
			zFine = (destZ * t + startZ * (span - t)) / span
		}
		catchUp = 0
		if let y = forceMoveYaw() {
			targetYaw = y
			yaw = y
		}
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
					playSeqSound(s, moveFrame)
				}
				if moveFrame >= s.frames.count {
					moveFrame = 0
					moveStep = 0
					playSeqSound(s, moveFrame)
				}
				moveNext = moveFrame + 1
				if moveNext >= s.frames.count { moveNext = 0 }
			} else {
				moveSeqId = -1
			}
		}
		updateSpotAnim()
		// rt4: a looping-type-1 animation waits (delay 1) while the actor still has queued moves from when it started.
		if seqId != -1 && seqDelay <= 1 {
			if let s = (try? store.seq(seqId)) ?? nil, s.loopType == 1 && animQueueMark > 0 && ctx.loop >= forceCyclesToStart && ctx.loop > forceCyclesToDest {
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
					playSeqSound(s, seqFrame)
				}
				if s.frames.count <= seqFrame {
					seqFrame -= s.replayOffset
					seqLoops += 1
					if seqLoops >= s.replayCount {
						seqId = -1
					} else if seqFrame >= 0 && s.frames.count > seqFrame {
						playSeqSound(s, seqFrame)
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
		updateLayers()
	}

	/// The tail of rt4 `NpcList.method879`: steps every layered animation (waiting out its delay first),
	/// dropping it when its loops are used up.
	func updateLayers() {
		for i in 0..<layers.count {
			guard var l = layers[i] else { continue }
			if l.delay > 0 {
				l.delay -= 1
				layers[i] = l
				continue
			}
			guard let s = (try? ctx.store.seq(l.seq)) ?? nil, !s.frames.isEmpty else {
				layers[i] = nil
				continue
			}
			l.step += 1
			if l.frame < s.frames.count && l.step > s.frameDelays[l.frame] {
				l.frame += 1
				l.step = 1
				playSeqSound(s, l.frame)
			}
			if s.frames.count <= l.frame {
				l.loops += 1
				l.frame -= s.replayOffset
				if s.replayCount <= l.loops {
					layers[i] = nil
					continue
				} else if l.frame >= 0 && l.frame < s.frames.count {
					playSeqSound(s, l.frame)
				} else {
					layers[i] = nil
					continue
				}
			}
			l.next = l.frame + 1
			if s.frames.count <= l.next {
				l.next -= s.replayOffset
				if l.loops + 1 >= s.replayCount {
					l.next = -1
				} else if l.next < 0 || s.frames.count <= l.next {
					l.next = -1
				}
			}
			layers[i] = l
		}
	}

	// MARK: hits and spot animations (rt4 PathingEntity.addHit, Protocol spotanim masks, NpcList.method879)

	/// rt4 `PathingEntity.addHit`: the first free of four splat slots shows `damage` for 70 cycles.
	func addHit(type: Int, damage: Int) {
		for i in 0..<4 where ctx.loop >= hitVisibleUntil[i] {
			hitDamages[i] = damage
			hitTypes[i] = type
			hitVisibleUntil[i] = ctx.loop + 70
			return
		}
	}

	/// rt4 priority rule for replacing a running spot animation: the new one wins unless the
	/// running one has a higher sequence priority.
	private func spotPriority(_ id: Int) -> Int {
		guard id != -1, let t = (try? ctx.store.spotAnim(id)) ?? nil, t.seq != -1, let s = (try? ctx.store.seq(t.seq)) ?? nil else { return 0 }
		return s.priority
	}

	/// rt4 spot animation mask (`Protocol` flags 0x100 players, 0x80 npcs, and SPOTANIM_ENTITY).
	func setSpotAnim(id: Int, height: Int, delay: Int) {
		guard id == -1 || spotAnimId == -1 || spotPriority(id) >= spotPriority(spotAnimId) else { return }
		spotAnimStart = delay + ctx.loop
		spotStep = 0
		spotFrame = 0
		spotAnimId = id
		if spotAnimStart > ctx.loop { spotFrame = -1 }
		spotAnimY = height
		spotNext = 1
		if id != -1 && ctx.loop == spotAnimStart, let t = (try? ctx.store.spotAnim(id)) ?? nil, t.seq != -1,
		   let s = (try? ctx.store.seq(t.seq)) ?? nil, !s.frames.isEmpty {
			playSeqSound(s, 0)
		}
	}

	/// The spot animation part of rt4 `NpcList.method879`.
	func updateSpotAnim() {
		guard spotAnimId != -1, ctx.loop >= spotAnimStart else { return }
		guard let t = (try? ctx.store.spotAnim(spotAnimId)) ?? nil, t.seq != -1,
		      let s = (try? ctx.store.seq(t.seq)) ?? nil, !s.frames.isEmpty else {
			spotAnimId = -1
			return
		}
		if spotFrame < 0 {
			spotFrame = 0
			playSeqSound(s, 0)
		}
		spotStep += 1
		if spotFrame < s.frames.count && s.frameDelays[spotFrame] < spotStep {
			spotFrame += 1
			spotStep = 1
			playSeqSound(s, spotFrame)
		}
		if spotFrame >= s.frames.count { spotAnimId = -1 }
		spotNext = spotFrame + 1
		if s.frames.count <= spotNext { spotNext = -1 }
	}

	/// rt4 `PathingEntity.method2691`: model height above the ground (200 until a model was built).
	var modelHeight: Int { minY == -32768 ? 200 : -minY }

	// MARK: rendering

	/// Everything the posed model is a function of. The pose only changes on client cycles, so with 60/120 Hz
	/// drawing most frames reuse the model built for the previous one (it is never mutated after building).
	private struct ModelSignature: Equatable {
		var lookVersion: Int, npcId: Int, bas: Int
		var seqId: Int, seqDelay: Int, seqFrame: Int, seqNext: Int, seqStep: Int
		var moveSeqId: Int, moveFrame: Int, moveNext: Int, moveStep: Int
		var layers: [LayerAnim?]
	}
	/// Turn off to rebuild the pose on every draw (benchmark A/B).
	nonisolated(unsafe) static var cacheModels = true
	private var cachedModel: SoftwareModel?
	private var cachedSignature: ModelSignature?

	/// The posed model for this cycle (rt4 `Player.render` / `Npc.render` model building).
	func buildModel() -> SoftwareModel? {
		let sig = ModelSignature(lookVersion: lookVersion, npcId: npcType?.id ?? -1, bas: currentBasId,
		                         seqId: seqId, seqDelay: seqDelay, seqFrame: seqFrame, seqNext: seqNext, seqStep: seqStep,
		                         moveSeqId: moveSeqId, moveFrame: moveFrame, moveNext: moveNext, moveStep: moveStep, layers: layers)
		if Self.cacheModels, let m = cachedModel, cachedSignature == sig { return m }
		let m = buildModelUncached()
		cachedModel = m
		cachedSignature = m == nil ? nil : sig
		return m
	}

	private func buildModelUncached() -> SoftwareModel? {
		let store = ctx.store
		let action: SeqType? = (seqId != -1 && seqDelay == 0) ? ((try? store.seq(seqId)) ?? nil) : nil
		let b = currentBas
		var movement: SeqType?
		if moveSeqId != -1 && !(moveSeqId == b.idle && action != nil) { movement = (try? store.seq(moveSeqId)) ?? nil }
		var layerPoses = [SeqPose?](repeating: nil, count: layers.count)
		for (i, l) in layers.enumerated() {
			guard let l, let s = (try? store.seq(l.seq)) ?? nil, !s.frames.isEmpty, l.frame < s.frames.count else { continue }
			layerPoses[i] = SeqPose(seq: s, frame: l.frame, nextFrame: l.next, step: l.step)
		}
		let actionPose = action.map { SeqPose(seq: $0, frame: seqFrame, nextFrame: seqNext, step: seqStep) }
		let movePose = movement.map { SeqPose(seq: $0, frame: moveFrame, nextFrame: moveNext, step: moveStep) }
		switch kind {
		case .player:
			guard let look = look else { return nil }
			return try? ctx.models.player(look, layers: layerPoses, action: actionPose, movement: movePose)
		case .npc:
			guard let t = npcType else { return nil }
			return try? ctx.models.npc(t, layers: layerPoses, action: actionPose, movement: movePose)
		}
	}

	var isVisible: Bool { kind == .player ? look != nil : npcType != nil }

	/// rt4 `PathingEntity.method2687` state update: where the roll and pitch angles head while the actor
	/// turns (`aBoolean167 && anInt3414 != 0`). Called once per client cycle from `render`.
	func stepRollPitch(_ b: BasType) {
		var rollTarget = 0, pitchTarget = 0
		if yawBraking && yawVelocity != 0 {
			pitchTarget = b.pitch.target
			rollTarget = yawVelocity >= 0 ? b.roll.target : -b.roll.target
		}
		roll.step(target: rollTarget, acceleration: b.roll.acceleration, maxSpeed: b.roll.maxSpeed)
		pitch.step(target: pitchTarget, acceleration: b.pitch.acceleration, maxSpeed: b.pitch.maxSpeed)
	}

	/// rt4 `PathingEntity.method2687` model part: lean the model about its middle height.
	static func applyRollPitch(_ m: SoftwareModel, roll: Int, pitch: Int) {
		if roll != 0 {
			let half = m.getMinY() / 2
			m.translate(0, -half, 0)
			m.rotateZ((roll >> 5) & 0x7FF)
			m.translate(0, half, 0)
		}
		if pitch != 0 {
			let half = m.getMinY() / 2
			m.translate(0, -half, 0)
			m.rotateX((pitch >> 5) & 0x7FF)
			m.translate(0, half, 0)
		}
	}

	/// The tilt rt4 `method2685` would apply here (zero without a footprint or a scene).
	func footprintTilt(orientation: Int) -> FootprintTilt {
		guard let scene = ctx.scene else { return FootprintTilt() }
		let level = scene.centralPlane
		return FootprintTilt.compute(width: currentBas.opcode26.0, length: currentBas.opcode26.1, orientation: orientation,
		                             xFine: xFine, zFine: zFine, groundY: groundY) { scene.tileHeight(level: level, xFine: $0, zFine: $1) }
	}

	var hasShadow: Bool {
		switch kind {
		case .player: return look.map { $0.npcId == -1 || ((try? ctx.store.npc($0.npcId)) ?? nil)?.hasShadow ?? true } ?? false
		case .npc: return npcType?.hasShadow ?? false
		}
	}

	/// rt4 `Npc.render` / `Player.render` shadow call (`ShadowModelList.method1043`).
	private func shadowModel(for body: SoftwareModel, orientation: Int) -> SoftwareModel? {
		guard ctx.characterShadows, hasShadow, let scene = ctx.scene else { return nil }
		let level = scene.centralPlane
		let action: SeqType? = (seqId != -1 && seqDelay == 0) ? ((try? ctx.store.seq(seqId)) ?? nil) : nil
		let b = currentBas
		var movement: SeqType?
		if moveSeqId != -1 && !(moveSeqId == b.idle && action != nil) {
			movement = (try? ctx.store.seq(moveSeqId)) ?? nil
		}
		let seq = movement ?? action
		let frame = movement == nil ? seqFrame : moveFrame
		let height = { (x: Int, z: Int) in scene.tileHeight(level: level, xFine: x, zFine: z) }
		switch kind {
		case .player:
			return ctx.shadows.shadow(store: ctx.store, modifier1: 160, stretches: stretches, seq: seq, xFine: xFine, colour2: 0, zFine: zFine,
			                          colour1: 0, size: 1, body: body, orientation: orientation, frame: frame, groundY: groundY, modifier2: 240, height: height)
		case .npc:
			guard let t = npcType else { return nil }
			return ctx.shadows.shadow(store: ctx.store, modifier1: t.shadowModifiers[0], stretches: stretches, seq: seq, xFine: xFine,
			                          colour2: t.shadowColours[1], zFine: zFine, colour1: t.shadowColours[0], size: t.size, body: body,
			                          orientation: orientation, frame: frame, groundY: groundY, modifier2: t.shadowModifiers[1], height: height)
		}
	}

	func render(_ r: Rasteriser3D, yaw orientation: Int, sinPitch: Int, cosPitch: Int, sinYaw: Int, cosYaw: Int, x: Int, y: Int, z: Int, key: Int64) {
		guard var m = buildModel() else { return }
		minY = m.getMinY()
		if let shadow = shadowModel(for: m, orientation: orientation) {
			// rt4 draws it with yaw 0 (already turned), no key, before the body.
			shadow.render(r, yaw: 0, sinPitch: sinPitch, cosPitch: cosPitch, sinYaw: sinYaw, cosYaw: cosYaw, x: x, y: y, z: z, key: -1)
		}
		let b = currentBas
		let leans = b.roll.target != 0 || b.pitch.target != 0
		let tilt = footprintTilt(orientation: orientation)
		if leans || !tilt.isIdentity {
			// The cached pose is shared between frames: lean a copy.
			m = m.copy()
			if leans {
				if rollPitchLoop != ctx.loop { rollPitchLoop = ctx.loop; stepRollPitch(b) }
				Self.applyRollPitch(m, roll: roll.position, pitch: pitch.position)
			}
			tilt.apply(to: m)
		}
		m.pickable = true // rt4 `Player.render` / `Npc.render`
		m.render(r, yaw: orientation, sinPitch: sinPitch, cosPitch: cosPitch, sinYaw: sinYaw, cosYaw: cosYaw, x: x, y: y, z: z, key: key)
	}
}

/// Port of the roll or pitch half of rt4 `PathingEntity.method2687`: a position that eases towards
/// `target` with a constant acceleration, a speed limit and a braking point (`intermediate`) chosen so
/// it stops on the target. Units are 1/32 of a model angle.
struct AxisSpring: Equatable {
	/// `anInt3383` / `anInt3427`
	var position = 0
	/// `anInt3355` / `anInt3423`
	var velocity = 0
	/// `anInt3398` / `anInt3357`: where acceleration turns to braking.
	var intermediate = 0
	/// `aBoolean170` / `aBoolean169`: still accelerating.
	var accelerating = false
	/// `anInt3419` / `anInt3367`: the target of the previous step.
	var lastTarget = 0

	mutating func step(target: Int, acceleration: Int, maxSpeed: Int) {
		guard acceleration > 0 else { return }
		let brake = maxSpeed * maxSpeed / (acceleration * 2)
		if lastTarget != target {
			lastTarget = target
			if velocity > 0 && position < target {
				let stop = velocity * velocity / (acceleration * 2)
				if stop <= target - position {
					accelerating = true
					intermediate = (target + position - stop) / 2
					intermediate = max(intermediate, target - brake)
				} else {
					accelerating = false
				}
			} else if velocity < 0 && position > target {
				let stop = velocity * velocity / (acceleration * 2)
				if target - position >= stop {
					accelerating = true
					intermediate = (position + stop + target) / 2
					intermediate = min(intermediate, brake + target)
				} else {
					accelerating = false
				}
			} else {
				accelerating = false
			}
		}
		if velocity == 0 {
			let d = lastTarget - position
			if -acceleration < d && acceleration > d {
				position = lastTarget
			} else {
				accelerating = true
				intermediate = (lastTarget + position) / 2
				if d >= 0 {
					velocity = acceleration
					intermediate = max(intermediate, lastTarget - brake)
				} else {
					velocity = -acceleration
					intermediate = min(intermediate, brake + lastTarget)
				}
			}
		} else if velocity > 0 {
			if position >= intermediate { accelerating = false }
			if !accelerating {
				velocity -= acceleration
				if velocity < 0 { velocity = 0 }
			} else if maxSpeed > velocity {
				velocity += acceleration
			}
		} else {
			if intermediate >= position { accelerating = false }
			if !accelerating {
				velocity += acceleration
				if velocity > 0 { velocity = 0 }
			} else if velocity > -maxSpeed {
				velocity -= acceleration
			}
		}
		position += velocity
	}
}

/// Port of rt4 `PathingEntity.method2685`: a creature with a BAS footprint (`BasType.anInt1059` x
/// `anInt1050`, opcode 26, in fine units) lies on the slope under its four corners.
struct FootprintTilt: Equatable {
	/// `anInt2640`: `rotateX` angle.
	var rotateX = 0
	/// `anInt2680`: `rotateZ` angle.
	var rotateZ = 0
	/// `anInt1938`: vertical shift.
	var translateY = 0

	var isIdentity: Bool { rotateX == 0 && rotateZ == 0 && translateY == 0 }

	/// `height(xFine, zFine)` is `SceneGraph.getTileHeight(Player.plane, ...)`; `groundY` is `anInt3424`.
	static func compute(width: Int, length: Int, orientation: Int, xFine: Int, zFine: Int, groundY: Int, height: (Int, Int) -> Int) -> FootprintTilt {
		guard width != 0 && length != 0 else { return FootprintTilt() }
		let sin = MathTables.sin[orientation & 2047], cos = MathTables.cos[orientation & 2047]
		let hw = width / 2, hl = length / 2
		// Corner (-w/2, -l/2), (w/2, -l/2), (-w/2, l/2), (w/2, l/2), each turned by the orientation.
		func corner(_ cx: Int, _ cz: Int) -> Int {
			let dz = (cz * cos - cx * sin) >> 16
			let dx = (sin * cz + cos * cx) >> 16
			return height(xFine + dx, zFine + dz)
		}
		let h00 = corner(-width / 2, -length / 2)
		let h10 = corner(hw, -length / 2)
		let h01 = corner(-width / 2, hl)
		let h11 = corner(hw, hl)
		let aX = min(h00, h10) - min(h11, h01)
		let aZ = min(h01, h00) - min(h11, h10)
		var t = FootprintTilt()
		t.rotateX = Int(atan2(Double(aX), Double(length)) * 325.95) & 0x7FF
		t.rotateZ = Int(atan2(Double(aZ), Double(width)) * 325.95) & 0x7FF
		var y = h11 + h00
		if h01 + h10 < y { y = h01 + h10 }
		t.translateY = (y >> 1) - groundY
		return t
	}

	func apply(to m: SoftwareModel) {
		if rotateX != 0 { m.rotateX(rotateX) }
		if rotateZ != 0 { m.rotateZ(rotateZ) }
		if translateY != 0 { m.translate(0, translateY, 0) }
	}
}
