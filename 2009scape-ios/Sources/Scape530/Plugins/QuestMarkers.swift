import Foundation

/// An arrow on the edge of the viewport pointing at an off-screen target.
public struct QuestEdgeMarker: Equatable {
	public var x: Int, y: Int
	/// Clockwise from straight up, radians: the way the arrow points.
	public var angle: Double
	/// Tiles to the target.
	public var distance: Int
}

/// The geometry of quest markers, pure so it can be tested without a scene.
public enum QuestMarkerMath {
	/// A world offset (`dx` tiles east, `dz` tiles north of the player) in camera terms: `right` of the view centre and
	/// `forward` along the view. The same rotation `WorldView.project` applies (rt4 `method1026`, yaw 0...2047).
	public static func cameraRelative(dx: Double, dz: Double, yaw: Int) -> (right: Double, forward: Double) {
		let a = Double(yaw & 2047) * 2 * Double.pi / 2048
		let s = sin(a), c = cos(a)
		return (dx * c + dz * s, dz * c - dx * s)
	}

	/// Where on the viewport edge (inset by `inset` pixels) the arrow for an offset goes. nil when the offset is zero.
	public static func edgeMarker(dx: Int, dz: Int, yaw: Int, viewport v: (x: Int, y: Int, w: Int, h: Int), inset: Int = 16) -> QuestEdgeMarker? {
		guard dx != 0 || dz != 0 else { return nil }
		let rel = cameraRelative(dx: Double(dx), dz: Double(dz), yaw: yaw)
		// Screen direction: right is +x, forward is up (-y).
		let vx = rel.right, vy = -rel.forward
		let len = (vx * vx + vy * vy).squareRoot()
		guard len > 0 else { return nil }
		let ux = vx / len, uy = vy / len
		let halfW = Double(v.w) / 2 - Double(inset), halfH = Double(v.h) / 2 - Double(inset)
		guard halfW > 0, halfH > 0 else { return nil }
		let tx = abs(ux) > 1e-9 ? halfW / abs(ux) : .infinity
		let ty = abs(uy) > 1e-9 ? halfH / abs(uy) : .infinity
		let t = min(tx, ty)
		let cx = Double(v.x) + Double(v.w) / 2, cy = Double(v.y) + Double(v.h) / 2
		let dist = Int(((Double(dx) * Double(dx) + Double(dz) * Double(dz)).squareRoot()).rounded())
		return QuestEdgeMarker(x: Int((cx + ux * t).rounded()), y: Int((cy + uy * t).rounded()), angle: atan2(ux, -uy), distance: dist)
	}

	/// True when a projected point is inside the viewport with `margin` pixels to spare.
	public static func onScreen(_ p: ScreenPoint?, viewport v: (x: Int, y: Int, w: Int, h: Int), margin: Int = 8) -> Bool {
		guard let p else { return false }
		return p.x >= v.x + margin && p.x < v.x + v.w - margin && p.y >= v.y + margin && p.y < v.y + v.h - margin
	}

	/// The corners of an arrow head at (`x`, `y`) pointing along `angle` (clockwise from up).
	public static func arrowHead(x: Int, y: Int, angle: Double, size: Int = 11) -> [ScreenPoint] {
		let s = Double(size)
		func pt(_ forward: Double, _ side: Double) -> ScreenPoint {
			let fx = sin(angle), fy = -cos(angle)   // forward on screen
			let sx = cos(angle), sy = sin(angle)    // to the right of forward
			return ScreenPoint(x: Int((Double(x) + fx * forward + sx * side).rounded()), y: Int((Double(y) + fy * forward + sy * side).rounded()))
		}
		return [pt(s, 0), pt(-s * 0.6, s * 0.75), pt(-s * 0.2, 0), pt(-s * 0.6, -s * 0.75)]
	}

	/// Greedy word wrap with a width function (pixels).
	public static func wrap(_ text: String, width: Int, measure: (String) -> Int) -> [String] {
		var lines: [String] = [], line = ""
		for word in text.split(separator: " ", omittingEmptySubsequences: true) {
			let candidate = line.isEmpty ? String(word) : line + " " + word
			if measure(candidate) <= width || line.isEmpty { line = candidate } else { lines.append(line); line = String(word) }
		}
		if !line.isEmpty { lines.append(line) }
		return lines
	}
}
