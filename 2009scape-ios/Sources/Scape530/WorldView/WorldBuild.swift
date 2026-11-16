import Foundation

/// Everything one scene build produces: the unit that is handed from the build thread to the frame thread.
/// The build thread owns it until `BuildMailbox.put`; the frame thread owns it after `take`/`wait`.
final class BuiltWorld: @unchecked Sendable {
	/// `WorldView.rebuildStamp` the build started with.
	let stamp: Int
	/// The plane the scene was built for (rt4 `SceneGraph.centralPlane`).
	let plane: Int
	var scene: Scene?
	var collision: [CollisionMap] = []
	var placer: LocPlacer?
	/// Created by the first build (later builds reuse the world's).
	var textures: TextureStore?
	var errors: [String] = []
	var seconds = 0.0
	/// Locs placed during the build, replayed to `WorldView.onLocPlaced` on adoption.
	var placements: [LocPlacement] = []
	/// The static minimap image for `scene` at `plane`, rendered on the build thread.
	var minimapImage: MinimapImage?

	init(stamp: Int, plane: Int) {
		self.stamp = stamp
		self.plane = plane
	}
}

/// The single place a finished build crosses from the build thread to the frame thread.
final class BuildMailbox: @unchecked Sendable {
	private let condition = NSCondition()
	private var result: BuiltWorld?

	/// Build thread: publishes a result (replacing an older unclaimed one, which is stale by definition).
	func put(_ built: BuiltWorld) {
		condition.lock()
		result = built
		condition.signal()
		condition.unlock()
	}

	/// Frame thread: the finished build, if there is one.
	func take() -> BuiltWorld? {
		condition.lock()
		defer { condition.unlock() }
		let r = result
		result = nil
		return r
	}

	/// Blocks until a build has been published.
	func wait() -> BuiltWorld {
		condition.lock()
		defer { condition.unlock() }
		while result == nil { condition.wait() }
		let r = result
		result = nil
		return r!
	}
}

extension WorldView {
	/// rt4 `Fonts.drawTextOnScreen(.., LocalizedText.LOADING)`: the viewport goes black and a boxed
	/// "Loading - please wait." sits at its top left (rt4 draws at canvas (6, 6); the viewport's corner here).
	func drawLoadingBox(into r: inout Raster, rect: (x: Int, y: Int, w: Int, h: Int)) {
		r.drawRect(rect.x, rect.y, rect.w, rect.h, 0xFF00_0000)
		guard let font = (try? store.font(named: "p12_full")) ?? nil else { return }
		let text = "Loading - please wait."
		let w = font.stringWidth(text), h = font.lineHeight
		let x = rect.x + 6, y = rect.y + 6
		let boxW = w + 8, boxH = h + 8
		for (rx, ry, rw, rh) in [(x, y, boxW, 1), (x, y + boxH - 1, boxW, 1), (x, y, 1, boxH), (x + boxW - 1, y, 1, boxH)] {
			r.drawRect(rx, ry, rw, rh, 0xFFFF_FFFF)
		}
		_ = font.drawParagraph(text, x: x + 4, y: y + 4, w: w, h: h, color: 0xFFFFFF, shadow: -1, halign: 1, valign: 1, into: &r)
	}
}
