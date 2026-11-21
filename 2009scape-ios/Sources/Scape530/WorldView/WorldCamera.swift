import Foundation

/// rt4's third-person camera (`Camera.cameraType == 1`): it follows the local
/// player, `pitchTarget`/`yawTarget` are what the player steers, and the eye
/// sits `ZOOM + pitch * 3` behind the target (`Camera.method555`, called from
/// `ScriptRunner.method4326`).
public struct WorldCamera {
	/// rt4 `Camera.ZOOM`.
	public static let defaultZoom = 600
	public static let minPitch = 128.0, maxPitch = 383.0
	/// Zoom limits for pinch (rt4 has a fixed zoom; these keep the view usable).
	public static let minZoom = 250, maxZoom = 2200

	/// rt4 `Camera.pitchTarget`, `yawTarget` (0...2047 units, 2048 = a full turn).
	public var pitchTarget = 128.0
	public var yawTarget = 0.0
	public var zoom = WorldCamera.defaultZoom
	/// rt4 `Camera.cameraX/Z`: the followed point in fine units, eased towards the player.
	public var followX = 0, followZ = 0
	/// `followX/Z` before the latest `follow` (render-side interpolation).
	var prevFollowX = 0, prevFollowZ = 0
	var initialised = false

	/// rt4 `Camera.cameraType == 2`: a camera placed by the server (CAMERA_DETACH / CAM_LOOKAT) or by CS2, instead of
	/// following the player. Nil is the normal third-person camera (`cameraType == 1`).
	public var scripted: ScriptedCamera?
	/// rt4 `Camera.customCameraActive`, `cameraJitter`, `cameraAmplitude`, `cameraFrequency` and the shake clock
	/// (`Protocol.anIntArray76`): per axis 0...4 (x, height, z, yaw, pitch) shake set by CAM_SHAKE.
	public var shakes = [CameraShake](repeating: CameraShake(), count: 5)

	/// One axis of CAM_SHAKE.
	public struct CameraShake: Equatable {
		public var active = false
		public var jitter = 0, amplitude = 0, frequency = 0
		/// rt4 `anIntArray76[axis]`: counts up once per client cycle.
		public var clock = 0
		public init() {}
	}

	/// The state of a scripted camera (rt4 `Camera.renderX`, `anInt40`, `renderZ`, `cameraPitch`, `cameraYaw` and the
	/// move / look targets of `method2722` / `method3849`). Positions are scene fine units, targets scene tiles.
	public struct ScriptedCamera: Equatable {
		public var x = 0, y = 0, z = 0
		public var pitch = 0, yaw = 0
		/// `anInt5375`, `anInt4232`, `anInt5203`, `anInt5225`, `anInt4612`.
		public var moveX = 0, moveZ = 0, moveHeight = 0, moveConstant = 0, moveProportional = 0
		/// `anInt5449`, `anInt5765`, `anInt1744`, `anInt5230`, `anInt5217`.
		public var lookX = 0, lookZ = 0, lookHeight = 0, lookConstant = 0, lookProportional = 0
		public init() {}
	}

	public init() {}

	/// rt4 `Camera.method2722`: fly to scene tile (`x`, `z`) with the eye `height` above the ground. `snap` (the server
	/// packet; CS2 passes false) jumps there at once when the proportional speed is 100 or more.
	/// `tileHeight(xFine, zFine)` is the scene ground height.
	public mutating func moveTo(x: Int, z: Int, height: Int, speed: Int, rotationSpeed: Int, snap: Bool, tileHeight: (Int, Int) -> Int) {
		var c = scripted ?? ScriptedCamera()
		c.moveProportional = rotationSpeed
		c.moveHeight = height
		c.moveX = x
		c.moveConstant = speed
		c.moveZ = z
		if snap && c.moveProportional >= 100 {
			c.x = c.moveX * 128 + 64
			c.z = c.moveZ * 128 + 64
			c.y = tileHeight(c.x, c.z) - c.moveHeight
		}
		scripted = c
	}

	/// rt4 `Camera.method3849`: turn to look at scene tile (`x`, `z`), `height` above the ground.
	public mutating func lookAt(x: Int, z: Int, height: Int, speed: Int, rotationSpeed: Int, tileHeight: (Int, Int) -> Int) {
		var c = scripted ?? ScriptedCamera()
		c.lookConstant = speed
		c.lookZ = z
		c.lookProportional = rotationSpeed
		c.lookX = x
		c.lookHeight = height
		if c.lookProportional >= 100 {
			let tx = c.lookX * 128 + 64, tz = c.lookZ * 128 + 64
			let ty = tileHeight(tx, tz) - c.lookHeight
			let dy = ty - c.y, dx = tx - c.x, dz = tz - c.z
			let flat = Int(Double(dz * dz + dx * dx).squareRoot())
			c.pitch = Int(atan2(Double(dy), Double(flat)) * 325.949) & 0x7FF
			c.yaw = Int(atan2(Double(dx), Double(dz)) * -325.949) & 0x7FF
			c.pitch = min(max(c.pitch, 128), 383)
		}
		scripted = c
	}

	/// rt4 `Camera.updateLockedCamera`, one client cycle: eases the scripted camera towards its move and look targets.
	public mutating func updateScripted(tileHeight: (Int, Int) -> Int) {
		guard var c = scripted else { return }
		defer { scripted = c }
		var tz = c.moveZ * 128 + 64, tx = c.moveX * 128 + 64
		var ty = tileHeight(tx, tz) - c.moveHeight
		if c.moveProportional >= 100 {
			c.x = c.moveX * 128 + 64
			c.z = c.moveZ * 128 + 64
			c.y = tileHeight(c.x, c.z) - c.moveHeight
		} else {
			if c.x < tx { c.x += c.moveConstant + c.moveProportional * (tx - c.x) / 1000; if c.x > tx { c.x = tx } }
			if c.y < ty { c.y += (ty - c.y) * c.moveProportional / 1000 + c.moveConstant; if c.y > ty { c.y = ty } }
			if c.x > tx { c.x -= c.moveConstant + (c.x - tx) * c.moveProportional / 1000; if c.x < tx { c.x = tx } }
			if c.z < tz { c.z += c.moveConstant + c.moveProportional * (tz - c.z) / 1000; if tz < c.z { c.z = tz } }
			if ty < c.y { c.y -= (c.y - ty) * c.moveProportional / 1000 + c.moveConstant; if ty > c.y { c.y = ty } }
			if c.z > tz { c.z -= c.moveConstant + (c.z - tz) * c.moveProportional / 1000; if tz > c.z { c.z = tz } }
		}
		tz = c.lookZ * 128 + 64
		tx = c.lookX * 128 + 64
		ty = tileHeight(tx, tz) - c.lookHeight
		let dy = ty - c.y, dz = tz - c.z, dx = tx - c.x
		let flat = Int(Double(dx * dx + dz * dz).squareRoot())
		var wantPitch = Int(atan2(Double(dy), Double(flat)) * 325.949) & 0x7FF
		wantPitch = min(max(wantPitch, 128), 383)
		let wantYaw = Int(-325.949 * atan2(Double(dx), Double(dz))) & 0x7FF
		if c.pitch < wantPitch {
			c.pitch += c.lookConstant + c.lookProportional * (wantPitch - c.pitch) / 1000
			if c.pitch > wantPitch { c.pitch = wantPitch }
		}
		if c.pitch > wantPitch {
			c.pitch -= (c.pitch - wantPitch) * c.lookProportional / 1000 + c.lookConstant
			if c.pitch < wantPitch { c.pitch = wantPitch }
		}
		var delta = wantYaw - c.yaw
		if delta > 1024 { delta -= 2048 }
		if delta < -1024 { delta += 2048 }
		if delta > 0 {
			c.yaw += delta * c.lookProportional / 1000 + c.lookConstant
			c.yaw &= 0x7FF
		}
		if delta < 0 {
			c.yaw -= c.lookProportional * -delta / 1000 + c.lookConstant
			c.yaw &= 0x7FF
		}
		var after = wantYaw - c.yaw
		if after > 1024 { after -= 2048 }
		if after < -1024 { after += 2048 }
		if (after < 0 && delta > 0) || (after > 0 && delta < 0) { c.yaw = wantYaw }
	}

	/// rt4 `Camera.resetCameraEffects`: the camera follows the player again and every shake stops.
	public mutating func resetEffects() {
		for i in 0..<5 { shakes[i].active = false }
		scripted = nil
	}

	/// Moves a scripted camera along with a scene shift (rt4 `LoginManager.method2463` subtracts the origin change).
	mutating func shiftScripted(dx: Int, dz: Int) {
		guard var c = scripted else { return }
		c.x -= dx * 128; c.z -= dz * 128
		c.moveZ -= dz; c.lookX -= dx; c.lookZ -= dz; c.moveX -= dx
		scripted = c
	}

	/// One client cycle of the shake clocks (rt4 `anIntArray76[y]++`).
	mutating func tickShakes() { for i in 0..<5 { shakes[i].clock += 1 } }

	/// rt4 `ScriptRunner.method4326`: the eye with the active shakes added. The shakes are not kept: the next frame
	/// starts from the camera state again.
	func applyShakes(to eye: (x: Int, y: Int, z: Int, pitch: Int, yaw: Int)) -> (x: Int, y: Int, z: Int, pitch: Int, yaw: Int) {
		var e = eye
		for axis in 0..<5 where shakes[axis].active {
			let s = shakes[axis]
			let v = Int(Double(-s.jitter) + Double(s.jitter * 2 + 1) * Double.random(in: 0..<1) + sin(Double(s.clock) * (Double(s.frequency) / 100.0)) * Double(s.amplitude))
			switch axis {
			case 3: e.yaw = (e.yaw + v) & 0x7FF
			case 4: e.pitch = min(max(e.pitch + v, 128), 383)
			case 2: e.z += v
			case 1: e.y += v
			default: e.x += v
			}
		}
		return e
	}

	/// rt4 `Camera.method4273`: eases towards the player by 1/16 of the gap each cycle, snapping when far.
	public mutating func follow(playerXFine: Int, playerZFine: Int) {
		prevFollowX = followX
		prevFollowZ = followZ
		if !initialised || followX - playerXFine < -500 || followX - playerXFine > 500 || followZ - playerZFine < -500 || followZ - playerZFine > 500 {
			followX = playerXFine
			followZ = playerZFine
			prevFollowX = followX
			prevFollowZ = followZ
			initialised = true
		}
		if followZ != playerZFine { followZ += (playerZFine - followZ) / 16 }
		if followX != playerXFine { followX += (playerXFine - followX) / 16 }
	}

	/// rt4 `Camera.clampCameraAngle` (the angle part).
	public mutating func clampAngles() {
		pitchTarget = min(max(pitchTarget, Self.minPitch), Self.maxPitch)
		yawTarget = ((yawTarget.truncatingRemainder(dividingBy: 2047)) + 2047).truncatingRemainder(dividingBy: 2047)
	}

	/// rt4 `GameShell.mainInputLoop`: held arrow keys steer the camera once per rendered frame. `calcRenderDelta(v)` is
	/// `v * v * seconds since the last frame`, so up/down tilt by 18^2 and left/right turn by 24^2 units per second
	/// (up wins over down, left over right, as in rt4's `else if`).
	public mutating func applyArrowKeys(up: Bool, down: Bool, left: Bool, right: Bool, seconds: Double) {
		guard up || down || left || right else { return }
		let vertical = 18.0 * 18.0 * seconds
		if up { pitchTarget += vertical } else if down { pitchTarget -= vertical }
		let horizontal = 24.0 * 24.0 * seconds
		if left { yawTarget -= horizontal } else if right { yawTarget += horizontal }
		clampAngles()
	}

	/// rt4 `Camera.method4273` with `Preferences.aBoolean63` set: each arrow key event of the cycle nudges the target by a
	/// fixed step (up +47, down -17, left -65, right +191; the asymmetry is rt4's).
	public mutating func applyLegacyArrowKey(rt4Code code: Int) {
		switch code {
		case KeyCode.up: pitchTarget += 47
		case KeyCode.down: pitchTarget -= 17
		case KeyCode.left: yawTarget -= 65
		case KeyCode.right: yawTarget += 191
		default: return
		}
		clampAngles()
	}

	/// One-finger drag in game pixels: horizontal turns, vertical tilts.
	public mutating func drag(dx: Double, dy: Double) {
		yawTarget += dx * 2.0
		pitchTarget += dy * 0.8
		clampAngles()
	}

	/// Multiplies the zoom distance (pinch `scale` > 1 brings the camera closer).
	public mutating func pinch(scale: Double) {
		guard scale > 0 else { return }
		zoom = min(max(Int(Double(zoom) / scale), Self.minZoom), Self.maxZoom)
	}

	/// The eye position and angles (rt4 `Camera.method555`), looking at the point `groundY - 50`
	/// above the player's tile. Returns scene fine coordinates (Y negative is up) and 0...2047 angles.
	public func eye(groundY: Int) -> (x: Int, y: Int, z: Int, pitch: Int, yaw: Int) {
		applyShakes(to: baseEye(groundY: groundY))
	}

	func baseEye(groundY: Int) -> (x: Int, y: Int, z: Int, pitch: Int, yaw: Int) {
		if let c = scripted { return (c.x, c.y, c.z, c.pitch, c.yaw) }
		var pitch = Int(pitchTarget)
		// rt4: an active pitch shake lifts the pitch to at least `amplitude + 128`.
		if shakes[4].active && shakes[4].amplitude + 128 > pitch { pitch = shakes[4].amplitude + 128 }
		let yaw = Int(yawTarget) & 0x7FF
		let distance = zoom + pitch * 3
		let p = (2048 - pitch) & 0x7FF
		let w = (2048 - yaw) & 0x7FF
		var dy = 0
		var horizontal = distance
		var dx = 0
		if p != 0 {
			dy = (MathTables.sin[p] * -distance) >> 16
			horizontal = (MathTables.cos[p] * distance) >> 16
		}
		if w != 0 {
			dx = (MathTables.sin[w] * horizontal) >> 16
			horizontal = (horizontal * MathTables.cos[w]) >> 16
		}
		return (followX - dx, groundY - 50 - dy, followZ - horizontal, pitch, yaw)
	}
}
