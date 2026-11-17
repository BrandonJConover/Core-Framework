import Foundation

/// Render-side interpolation between client cycles.
///
/// rt4 advances actors and the camera once per 20 ms client cycle and draws every frame in between from the
/// same state, so on a 60 or 120 Hz display motion steps at 50 Hz. With `smoothMotion` on, each frame places
/// actors and the camera at `prev + (current - prev) * renderAlpha`, where `prev` is the state before the
/// latest cycle and `renderAlpha` is the fraction of a cycle elapsed since it ran (`GameClient.frame` sets
/// it from the wall clock). The picture therefore trails the simulation by up to one cycle (20 ms) but moves
/// continuously. Game logic never sees interpolated values: they are applied around drawing and picking only
/// and restored afterwards. Anything that jumped (teleport, force move, region shift, camera snap) is shown
/// at its new position straight away.
extension WorldView {
	/// Largest per-cycle step that is still interpolated; rt4 moves actors by at most 16 fine units a cycle
	/// (running), so anything bigger is a jump.
	static let interpolationMaxStep = 40
	static let interpolationMaxYawStep = 256

	func beginInterpolation() {
		interpSaved.removeAll(keepingCapacity: true)
		interpCameraSaved = nil
		guard smoothMotion, renderAlpha < 1 else { return }
		let alpha = max(0, renderAlpha)
		func blend(_ a: PathingActor) {
			let dx = a.xFine - a.prevXFine, dz = a.zFine - a.prevZFine
			var dyaw = (a.yaw - a.prevYaw) & 0x7FF
			if dyaw > 1024 { dyaw -= 2048 }
			let moves = (dx != 0 || dz != 0) && abs(dx) <= Self.interpolationMaxStep && abs(dz) <= Self.interpolationMaxStep
			let turns = dyaw != 0 && abs(dyaw) <= Self.interpolationMaxYawStep
			guard moves || turns else { return }
			interpSaved.append((a, a.xFine, a.zFine, a.yaw))
			if moves {
				a.xFine = a.prevXFine + Int((Double(dx) * alpha).rounded())
				a.zFine = a.prevZFine + Int((Double(dz) * alpha).rounded())
			}
			if turns { a.yaw = (a.prevYaw + Int((Double(dyaw) * alpha).rounded())) & 0x7FF }
		}
		for a in ctx.players.values { blend(a) }
		for a in ctx.npcs.values { blend(a) }
		let cdx = camera.followX - camera.prevFollowX, cdz = camera.followZ - camera.prevFollowZ
		if (cdx != 0 || cdz != 0) && abs(cdx) <= Self.interpolationMaxStep && abs(cdz) <= Self.interpolationMaxStep {
			interpCameraSaved = (camera.followX, camera.followZ)
			camera.followX = camera.prevFollowX + Int((Double(cdx) * alpha).rounded())
			camera.followZ = camera.prevFollowZ + Int((Double(cdz) * alpha).rounded())
		}
	}

	func endInterpolation() {
		for s in interpSaved { s.actor.xFine = s.x; s.actor.zFine = s.z; s.actor.yaw = s.yaw }
		interpSaved.removeAll(keepingCapacity: true)
		if let c = interpCameraSaved { camera.followX = c.x; camera.followZ = c.z }
		interpCameraSaved = nil
	}
}
