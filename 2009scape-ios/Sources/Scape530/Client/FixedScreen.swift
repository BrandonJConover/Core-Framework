import Foundation

/// rt4 window modes (`DisplayMode.getWindowMode`) the client can run in: fixed 765x503 (top-level interface 548) and
/// resizable (746). The raw value is what the login request, WINDOW_STATUS and CS2 5306/5307 carry. (rt4's 1 is fixed
/// with the GL renderer and 3 is full screen; both are fixed/resizable here.)
public enum WindowMode: Int {
	case fixed = 0
	case resizable = 2
}

extension GameClient {
	/// rt4 `GameShell.canvasWidth/Height` in fixed mode.
	public static let fixedSize = (w: 765, h: 503)

	/// Where the fixed frame sits in the shell's canvas (rt4 centres the 765x503 canvas in its window with
	/// `leftMargin`; here it is also scaled to fit, letterboxed). Nil in resizable mode.
	public var fixedLayout: (x: Int, y: Int, w: Int, h: Int, scale: Double)? {
		guard windowMode == .fixed, outerSize.w > 0, outerSize.h > 0 else { return nil }
		let s = min(Double(outerSize.w) / Double(Self.fixedSize.w), Double(outerSize.h) / Double(Self.fixedSize.h))
		let w = max(1, Int(Double(Self.fixedSize.w) * s)), h = max(1, Int(Double(Self.fixedSize.h) * s))
		return ((outerSize.w - w) / 2, (outerSize.h - h) / 2, w, h, s)
	}

	/// Canvas pixels per game pixel (1 in resizable mode).
	var fixedScale: Double { fixedLayout?.scale ?? 1 }

	/// A point of the shell's canvas in game pixels (what `ui.drawn`, `viewport` and menus use). Identity in
	/// resizable mode. The public touch entry points (`tap`, `hover`, `isOverWorld`, `longPress`, ...) call this.
	public func toGame(x: Int, y: Int) -> (x: Int, y: Int) {
		guard let l = fixedLayout else { return (x, y) }
		return (Int((Double(x - l.x) / l.scale).rounded(.down)), Int((Double(y - l.y) / l.scale).rounded(.down)))
	}

	/// A game pixel's position in the shell's canvas (the inverse of `toGame`).
	public func toCanvas(x: Int, y: Int) -> (x: Int, y: Int) {
		guard let l = fixedLayout else { return (x, y) }
		return (l.x + Int((Double(x) * l.scale).rounded()), l.y + Int((Double(y) * l.scale).rounded()))
	}

	/// Runs `body` with a canvas point converted to game pixels. Nested public calls (a tap that checks
	/// `isOverWorld`) already hold game pixels and are not converted again.
	func mapInput<T>(_ x: Int, _ y: Int, _ body: (Int, Int) -> T) -> T {
		if mapDepth > 0 || fixedLayout == nil { return body(x, y) }
		mapDepth += 1
		defer { mapDepth -= 1 }
		let p = toGame(x: x, y: y)
		return body(p.x, p.y)
	}

	/// Draws the 765x503 frame into the shell's canvas: centred, scaled (nearest) by the largest factor that fits,
	/// black bars elsewhere.
	func compose(_ inner: Raster, width: Int, height: Int) -> Raster {
		guard let l = fixedLayout, (width, height) != (inner.width, inner.height) else { return inner }
		var out: Raster
		if let b = outerBuffer, b.width == width, b.height == height { out = b; outerBuffer = nil; out.clear() } else { out = Raster(width: width, height: height) }
		let sw = inner.width, sh = inner.height
		let cols = (0..<l.w).map { min(sw - 1, Int(Double($0) / l.scale)) }
		inner.pixels.withUnsafeBufferPointer { src in
			out.pixels.withUnsafeMutableBufferPointer { dst in
				for y in 0..<l.h {
					let sy = min(sh - 1, Int(Double(y) / l.scale))
					let srow = sy * sw, drow = (l.y + y) * width + l.x
					for x in 0..<l.w { dst[drow + x] = src[srow + cols[x]] }
				}
			}
		}
		outerBuffer = out
		return out
	}
}
