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

	public init() {}

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
		let pitch = Int(pitchTarget)
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
