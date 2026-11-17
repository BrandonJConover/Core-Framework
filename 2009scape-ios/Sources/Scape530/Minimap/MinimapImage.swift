import Foundation

/// rt4 `SoftwareIndexedSprite` as the minimap uses it: palette indices (0 transparent) that can be
/// turned by 90 degrees (`flipVertical`) and blitted scaled.
struct IndexedMapSprite {
	var width: Int
	var height: Int
	var xOffset: Int
	var yOffset: Int
	/// rt4 sets `innerWidth/Height = width/height` after loading (`MsiType.getSprite`).
	var innerWidth: Int
	var innerHeight: Int
	var pixels: [UInt8]
	var palette: [UInt32]

	init(_ f: SpriteFrame) {
		width = f.innerWidth; height = f.innerHeight
		innerWidth = f.innerWidth; innerHeight = f.innerHeight
		xOffset = f.xOffset; yOffset = f.yOffset
		pixels = f.indices
		palette = f.palette.map { $0 & 0xFFFFFF }
	}

	/// rt4 `SoftwareIndexedSprite.flipVertical`: a quarter turn (transposes with a flip).
	mutating func flipVertical() {
		var out = [UInt8](repeating: 0, count: width * height)
		var k = 0
		for x in 0..<width {
			var y = height - 1
			while y >= 0 { out[k] = pixels[x + y * width]; k += 1; y -= 1 }
		}
		pixels = out
		let oldY = yOffset
		yOffset = xOffset
		xOffset = innerHeight - height - oldY
		swap(&width, &height)
		swap(&innerWidth, &innerHeight)
	}
}

/// The static part of the minimap: rt4's 512x512 `softwareSprite` built by `MiniMap.renderMap`.
/// Tile (x, z) of the 104x104 scene occupies the 4x4 block at (48 + 4x, 48 + 4 * (103 - z)).
struct MinimapImage {
	static let size = 512
	/// 0xRRGGBB pixels; rt4 uses 1 for "black" and 0 for "unset".
	var pixels = [UInt32](repeating: 1, count: size * size)
	/// rt4 `MiniMap.locId/locX/locZ`: map function icons (scene tiles).
	var icons: [(loc: Int, x: Int, z: Int)] = []

	/// rt4 `MiniMap.anIntArrayArray24`: which of the 16 pixels of a shaped tile show the overlay, per shape.
	static let shapeMask: [[Int]] = [
		[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
		[1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1], [1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
		[0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1], [0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
		[1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1], [1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0],
		[0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0], [1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1],
		[1, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], [0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1],
		[0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1],
	]
	/// rt4 `MiniMap.anIntArrayArray46`: pixel order per tile rotation.
	static let rotationOrder: [[Int]] = [
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], [12, 8, 4, 0, 13, 9, 5, 1, 14, 10, 6, 2, 15, 11, 7, 3],
		[15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0], [3, 7, 11, 15, 2, 6, 10, 14, 1, 5, 9, 13, 0, 4, 8, 12],
	]

	/// rt4 `MiniMap.renderTile`: paints one tile's 4x4 block from its minimap colours.
	/// `rgb` converts an HSL16 colour (0 = none) to 0xRRGGBB.
	mutating func renderTile(_ tile: SceneTile?, at index: Int, rgb: (Int) -> UInt32) {
		guard let tile = tile else { return }
		var index = index
		if let plain = tile.plainTile {
			let c = rgb(plain.minimapHsl)
			if c != 0 {
				for _ in 0..<4 {
					for k in 0..<4 { pixels[index + k] = c }
					index += 512
				}
			}
			return
		}
		guard let shaped = tile.shapedTile else { return }
		let mask = Self.shapeMask[shaped.shape]
		let order = Self.rotationOrder[shaped.rotation & 3]
		let underlay = rgb(shaped.underlayMinimapHsl)
		let overlay = rgb(shaped.overlayMinimapHsl)
		var n = 0
		if underlay != 0 {
			for _ in 0..<4 {
				for k in 0..<4 {
					pixels[index + k] = mask[order[n]] == 0 ? underlay : overlay
					n += 1
				}
				index += 512
			}
			return
		}
		for _ in 0..<4 {
			for k in 0..<4 {
				if mask[order[n]] != 0 { pixels[index + k] = overlay }
				n += 1
			}
			index += 512
		}
	}
}
