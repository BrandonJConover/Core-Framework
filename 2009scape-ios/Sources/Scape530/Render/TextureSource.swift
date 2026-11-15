/// What the software rasteriser needs from textures, mirroring the parts of
/// rt4 `TextureProvider` that `Rasteriser` calls. Implemented by the texture
/// pipeline (archive 9 TextureOps) and by test stubs.
public protocol TextureSource: AnyObject {
	/// rt4 `method3232(id, brightness)`: texels as 0xRRGGBB (alpha in the top
	/// byte where the texture has it), already brightness-adjusted, or nil if
	/// not available yet (the rasteriser then fills with the average colour).
	func texels(_ id: Int, brightness: Float) -> [Int32]?
	/// rt4 `getAverageColor`: HSL16 colour used when texels are missing.
	func averageColor(_ id: Int) -> Int
	/// rt4 `isLowDetail`: 64x64 instead of 128x128.
	func isLowDetail(_ id: Int) -> Bool
	/// rt4 `isOpaque`: no transparent texels (lets the rasteriser skip tests).
	func isOpaque(_ id: Int) -> Bool
}
