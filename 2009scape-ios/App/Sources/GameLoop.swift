import QuartzCore
import Scape530

/// Runs everything that touches the `GameClient` (cycles, software rasteriser, input) on one serial
/// background queue so the main thread only handles UIKit. Frames are rendered and handed to Metal from
/// that queue; the display link on the main thread just asks for the next one and a frame request is
/// dropped while the previous is still in flight (no queue build-up when the device is slow).
/// All client access must go through `async` / `sync`.
final class GameLoop: @unchecked Sendable {
	/// What the main thread needs to know after a frame (UI state is read here, not from the client).
	struct Snapshot {
		var screen: GameClient.Screen
		var wantsKeyboard: Bool
		var connectError: String?
		var reconnectAttempt: Int
		var maxReconnectAttempts: Int
		var menuRows: [MenuRow]?
		var isDraggingItem: Bool
	}

	private let client: GameClient
	private let queue = DispatchQueue(label: "scape530.game", qos: .userInteractive)
	private let presenter: MetalFramePresenter?
	/// The GPU scene renderer (nil when Metal cannot build it); used while `MobileSettings.gpuRenderer` is on.
	private let scenePresenter: MetalScenePresenter?
	/// Set by the view right after it is created (the layer exists only then).
	var layer: CAMetalLayer?
	private let controller = ControllerInput()
	private let lock = NSLock()
	private var busy = false
	/// Delivered on the main queue after every rendered frame.
	var onSnapshot: (Snapshot) -> Void = { _ in }

	init(client: GameClient, presenter: MetalFramePresenter?) {
		self.client = client
		self.presenter = presenter
		scenePresenter = presenter.flatMap { MetalScenePresenter(device: $0.device) }
	}

	func async(_ work: @escaping (GameClient) -> Void) {
		queue.async { [client] in work(client) }
	}

	/// Blocks the caller until `work` has run after everything queued before it (at most one frame).
	func sync<T>(_ work: (GameClient) -> T) -> T {
		queue.sync { work(client) }
	}

	/// Renders one frame at `width` x `height` game pixels unless the previous one is still running.
	func requestFrame(width: Int, height: Int, smooth: Bool, smoothMotion: Bool = false) {
		lock.lock()
		if busy { lock.unlock(); return }
		busy = true
		lock.unlock()
		queue.async { [self] in
			defer { lock.lock(); busy = false; lock.unlock() }
			controller.poll(client)
			client.smoothMotion = smoothMotion
			do {
				// Software mode draws the whole frame into the raster; GPU mode leaves the 3D viewport transparent
				// and draws the scene in Metal under the raster (see `WorldView.gpuFrame`).
				let gpu = MobileSettings.gpuRenderer && scenePresenter != nil
				client.world.gpuSettings = gpu ? MobileSettings.gpuSettings : nil
				let raster = try client.frame(width: width, height: height)
				presenter?.smoothScaling = smooth
				if let layer {
					if gpu, client.screen == .game, let frame = client.world.gpuFrame, let sp = scenePresenter {
						sp.smoothScaling = smooth
						sp.present(raster, frame: frame, world: client.world, in: layer)
					} else {
						presenter?.present(raster, in: layer)
					}
				}
			} catch {
				print("[frame] \(error)")
			}
			let snap = Snapshot(
				screen: client.screen, wantsKeyboard: client.wantsKeyboard, connectError: client.connectError,
				reconnectAttempt: client.reconnectAttempt, maxReconnectAttempts: client.maxReconnectAttempts,
				menuRows: client.popupRows, isDraggingItem: client.isDraggingItem)
			DispatchQueue.main.async { [onSnapshot] in onSnapshot(snap) }
		}
	}
}
