import GameController
import Scape530

/// MFi / DualSense / Xbox controller support: right stick turns and tilts the camera, triggers zoom,
/// Y raises the keyboard. Polled from the game thread once per frame (GCController reads are thread safe).
final class ControllerInput {
	init() {
		// Needed so controllers keep reporting while the app is foreground without a controller UI.
		GCController.shouldMonitorBackgroundEvents = false
		GCController.startWirelessControllerDiscovery {}
	}

	private var yWasDown = false

	/// Applies the controller's current state to the client. Call on the game thread.
	func poll(_ client: GameClient) {
		guard let pad = GCController.controllers().first?.extendedGamepad else { return }
		let stick = pad.rightThumbstick
		let dead: Float = 0.15
		let sx = abs(stick.xAxis.value) > dead ? stick.xAxis.value : 0
		let sy = abs(stick.yAxis.value) > dead ? stick.yAxis.value : 0
		if sx != 0 || sy != 0 {
			client.cameraDrag(dx: Double(sx) * 6, dy: Double(-sy) * 6)
		}
		let zoom = pad.leftTrigger.value - pad.rightTrigger.value // pull right trigger to zoom in
		if abs(zoom) > 0.1 { client.cameraPinch(scale: 1 + Double(zoom) * 0.02) }
		let y = pad.buttonY.isPressed
		if y && !yWasDown { client.toggleKeyboard() }
		yWasDown = y
	}
}
