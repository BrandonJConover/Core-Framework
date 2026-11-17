import Foundation

/// Typed literal helper (keeps the type checker fast on rt4's long int expressions).
@inline(__always) func k(_ v: Int32) -> Int32 { v }

/// Java `>>>` on a 32-bit int.
@inline(__always) func ushr(_ a: Int32, _ n: Int32) -> Int32 {
	Int32(bitPattern: UInt32(bitPattern: a) >> UInt32(truncatingIfNeeded: n & 31))
}

/// rt4 `ColorUtils.multiplyLightness`: scales the lightness (low 7 bits) of an
/// HSL16 colour `a` by that of `b`, clamped to 2...126.
@inline(__always) func multiplyLightness(_ a: Int32, _ b: Int32) -> Int32 {
	var b = (b &* (a & 0x7F)) &>> 7
	if b < 2 { b = 2 } else if b > 126 { b = 126 }
	return (a & 0xFF80) &+ b
}

/// Software 3D rasteriser, a port of rt4 `Rasteriser` (static class in the
/// original). It owns its own target buffer (`pixels`, rt4 style 0x00RRGGBB
/// ints, so the integer blending code is bit-exact) and exposes
/// `copy(into:)`/`load(from:)` to move that buffer to and from a `Raster`.
///
/// Typical frame: `load(from: raster)` or `clear`, `setClip` + `prepare()`,
/// fill triangles, `copy(into: &raster)`.
public final class Rasteriser3D {
	/// rt4 `SoftwareRaster.width`: row stride of `pixels`.
	public let stride: Int32
	/// Buffer height in rows.
	public let bufferHeight: Int32
	/// rt4 `SoftwareRaster.pixels`: 0x00RRGGBB.
	/// Backing store of `pixels`: raw memory so the scanline loops index without Array bounds, uniqueness
	/// and exclusivity checks (the buffer never reallocates and lives as long as the rasteriser).
	let px: UnsafeMutablePointer<Int32>
	public let pixelCount: Int
	/// Backing store of `palette`.
	let pal: UnsafeMutablePointer<Int32>
	/// The target buffer as an array (a copy; use `px` in hot code).
	public var pixels: [Int32] {
		get { Array(UnsafeBufferPointer(start: px, count: pixelCount)) }
		set { for i in 0..<min(pixelCount, newValue.count) { px[i] = newValue[i] } }
	}
	/// rt4 `Rasteriser.palette`: HSL16 -> 0xRRGGBB (a copy of `pal`).
	public var palette: [Int32] {
		get { Array(UnsafeBufferPointer(start: pal, count: 65536)) }
		set { for i in 0..<min(65536, newValue.count) { pal[i] = newValue[i] } }
	}
	/// rt4 `Rasteriser.offsets`: row start index for each viewport row.
	var offsets = [Int32](repeating: 0, count: 1024)
	/// rt4 `Rasteriser.textureProvider`.
	public var textureProvider: TextureSource? { didSet { texelCache = [[Int32]?](repeating: nil, count: 2048) } }

	public var centerX: Int32 = 0
	public var centerY: Int32 = 0
	public var screenLowerX: Int32 = 0
	public var screenUpperX: Int32 = 0
	public var screenLowerY: Int32 = 0
	public var screenUpperY: Int32 = 0
	/// rt4 `Rasteriser.width/height`: viewport size.
	public var width: Int32 = 0
	var height: Int32 = 0
	public var viewportHeight: Int32 { height }
	public var textureHasTransparency = false
	var opaque = false
	/// rt4 `jagged`: gouraud/flat scanlines write 4 pixels per palette lookup.
	public var jagged = true
	var lowDetail = false
	public private(set) var brightness: Float = 1.0
	/// rt4 `testX`: set per triangle (see `testPoints`) when x clipping is needed.
	public var testX = false
	/// rt4 `alpha`: global 0...255 transparency (0 = opaque) for flat/gouraud fills.
	public var alpha: Int32 = 0

	/// rt4 `SoftwareRaster.clipLeft/Top/Right/Bottom`.
	public private(set) var clipLeft = 0
	public private(set) var clipTop = 0
	public private(set) var clipRight = 0
	public private(set) var clipBottom = 0

	public init(width: Int, height: Int) {
		stride = Int32(width)
		bufferHeight = Int32(height)
		pixelCount = width * height
		px = UnsafeMutablePointer<Int32>.allocate(capacity: max(1, width * height))
		px.initialize(repeating: 0, count: max(1, width * height))
		pal = UnsafeMutablePointer<Int32>.allocate(capacity: 65536)
		pal.initialize(repeating: 0, count: 65536)
		setClip(0, 0, width, height)
		prepare()
		setBrightness(0.8, jitter: false)
	}

	deinit {
		px.deallocate()
		pal.deallocate()
	}

	public func setClip(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
		clipLeft = max(0, left)
		clipTop = max(0, top)
		clipRight = min(Int(stride), right)
		clipBottom = min(Int(bufferHeight), bottom)
	}

	/// rt4 `Rasteriser.prepare`: viewport = current clip rectangle.
	public func prepare() {
		prepareOffsets(Int32(clipLeft), Int32(clipTop), Int32(clipRight), Int32(clipBottom))
	}

	/// rt4 `Rasteriser.prepareOffsets(l,t,r,b)`.
	public func prepareOffsets(_ left: Int32, _ top: Int32, _ right: Int32, _ bottom: Int32) {
		width = right &- left
		height = bottom &- top
		prepareOffsets()
		if offsets.count < Int(height) {
			var n = 1
			while n < Int(height) { n <<= 1 }
			offsets = [Int32](repeating: 0, count: n)
		}
		var x = top &* stride &+ left
		var y = 0
		while y < Int(height) {
			offsets[y] = x
			x = x &+ stride
			y += 1
		}
	}

	/// rt4 `Rasteriser.prepareOffsets()`: centres the projection in the viewport.
	public func prepareOffsets() {
		centerX = width / 2
		centerY = height / 2
		screenLowerX = 0 &- centerX
		screenUpperX = width &- centerX
		screenLowerY = 0 &- centerY
		screenUpperY = height &- centerY
	}

	/// rt4 `unpackTextures`.
	public func unpackTextures(_ provider: TextureSource?) {
		textureProvider = provider
	}

	/// Texels of the textures seen so far at the current brightness, so a textured triangle does not go through the
	/// provider's lock and dictionary every time. Only available textures are kept (a nil answer may change).
	private var texelCache = [[Int32]?](repeating: nil, count: 2048)

	@inline(__always) private func cachedTexels(_ tp: TextureSource, _ textureId: Int32) -> [Int32]? {
		let i = Int(textureId)
		if i >= 0 && i < 2048 {
			if let t = texelCache[i] { return t }
			let t = tp.texels(i, brightness: brightness)
			texelCache[i] = t
			return t
		}
		return tp.texels(i, brightness: brightness)
	}

	/// rt4 `Rasteriser.setBrightness`: rebuilds the palette. rt4 jitters the
	/// gamma by +-0.015 with `Math.random`; pass `jitter: false` for a
	/// deterministic palette.
	public func setBrightness(_ value: Float, jitter: Bool = true) {
		brightness = value
		texelCache = [[Int32]?](repeating: nil, count: 2048)
		if jitter { brightness = Float(Double(brightness) + Double.random(in: 0..<1) * 0.03 - 0.015) }
		calculateBrightness()
	}

	/// rt4 `Rasteriser.calculateBrightness`: HSL16 (6-bit hue, 3-bit
	/// saturation, 7-bit lightness) to RGB with gamma `brightness`.
	func calculateBrightness() {
		var offset = 0
		let gamma = Double(brightness)
		for y in 0..<512 {
			let hue = Double(y >> 3) / 64.0 + 0.0078125
			let saturation = Double(y & 0x7) / 8.0 + 0.0625
			for x in 0..<128 {
				let lightness = Double(x) / 128.0
				var r = lightness, g = lightness, b = lightness
				if saturation != 0.0 {
					let q: Double
					if lightness < 0.5 { q = lightness * (saturation + 1.0) } else { q = lightness + saturation - lightness * saturation }
					let p = lightness * 2.0 - q
					var t = hue + 0.3333333333333333
					if t > 1.0 { t -= 1 }
					var d11 = hue - 0.3333333333333333
					if d11 < 0.0 { d11 += 1 }
					if t * 6.0 < 1.0 { r = p + (q - p) * 6.0 * t }
					else if t * 2.0 < 1.0 { r = q }
					else if t * 3.0 < 2.0 { r = p + (q - p) * (0.6666666666666666 - t) * 6.0 }
					else { r = p }
					if hue * 6.0 < 1.0 { g = p + (q - p) * 6.0 * hue }
					else if hue * 2.0 < 1.0 { g = q }
					else if hue * 3.0 < 2.0 { g = p + (q - p) * (0.6666666666666666 - hue) * 6.0 }
					else { g = p }
					if d11 * 6.0 < 1.0 { b = p + (q - p) * 6.0 * d11 }
					else if d11 * 2.0 < 1.0 { b = q }
					else if d11 * 3.0 < 2.0 { b = p + (q - p) * (0.6666666666666666 - d11) * 6.0 }
					else { b = p }
				}
				r = pow(r, gamma)
				g = pow(g, gamma)
				b = pow(b, gamma)
				let intR = Int32(r * 256.0), intG = Int32(g * 256.0), intB = Int32(b * 256.0)
				var rgb = (intR &<< 16) &+ (intG &<< 8) &+ intB
				if rgb == 0 { rgb = 1 }
				pal[offset] = rgb
				offset += 1
			}
		}
	}

	// MARK: - Buffer helpers (Swift side)

	/// Fills the whole buffer with 0xRRGGBB.
	public func clear(_ rgb: Int32 = 0) {
		px.update(repeating: rgb, count: pixelCount)
	}

	/// Loads a `Raster` (same size) into the buffer, dropping alpha.
	public func load(from raster: Raster) {
		let n = min(pixelCount, raster.pixels.count)
		for i in 0..<n { px[i] = Int32(bitPattern: raster.pixels[i] & 0xFFFFFF) }
	}

	/// Copies the buffer into `raster` at (x, y) as opaque pixels, honouring
	/// the raster's clip rectangle.
	public func copy(into raster: inout Raster, x: Int = 0, y: Int = 0) {
		let w = Int(stride), h = Int(bufferHeight)
		// Source columns that land inside the destination clip.
		let sx0 = max(0, raster.clipLeft - x), sx1 = min(w, raster.clipRight - x)
		guard sx0 < sx1 else { return }
		let dstWidth = raster.width, clipTop = raster.clipTop, clipBottom = raster.clipBottom
		let src = px
		raster.pixels.withUnsafeMutableBufferPointer { dst in
			let base = dst.baseAddress!
			for sy in 0..<h {
				let dy = y + sy
				guard dy >= clipTop && dy < clipBottom else { continue }
				let s = src + sy * w
				let d = base + dy * dstWidth + x
				for sx in sx0..<sx1 { d[sx] = 0xFF00_0000 | UInt32(bitPattern: s[sx]) }
			}
		}
	}

	/// rt4 `Rasteriser.fillTexturedTriangle`: perspective-correct textured gouraud triangle.

	public func fillTexturedTriangle(_ yA: Int32, _ yB: Int32, _ yC: Int32, _ xA: Int32, _ xB: Int32, _ xC: Int32, _ colorA: Int32, _ colorB: Int32, _ colorC: Int32, _ viewXA: Int32, _ viewXB: Int32, _ viewXC: Int32, _ viewYA: Int32, _ viewYB: Int32, _ viewYC: Int32, _ viewZA: Int32, _ viewZB: Int32, _ viewZC: Int32, _ textureId: Int32) {
		var yA = yA
		var yB = yB
		var yC = yC
		var xA = xA
		var xB = xB
		var xC = xC
		var colorA = colorA
		var colorB = colorB
		var colorC = colorC
		var viewXA = viewXA
		var viewXB = viewXB
		var viewXC = viewXC
		var viewYA = viewYA
		var viewYB = viewYB
		var viewYC = viewYC
		var viewZA = viewZA
		var viewZB = viewZB
		var viewZC = viewZC
		var textureId = textureId
		guard let tp = textureProvider else { return }
		let texelsOpt = cachedTexels(tp, textureId)
		if texelsOpt == nil {
		let averageColor = Int32(truncatingIfNeeded: tp.averageColor(Int(textureId)))
		fillGouraudTriangle(yA, yB, yC, xA, xB, xC, multiplyLightness(averageColor, colorA), multiplyLightness(averageColor, colorB), multiplyLightness(averageColor, colorC))
		return
	}

	guard let texels = texelsOpt else { return }
	lowDetail = tp.isLowDetail(Int(textureId))
	opaque = tp.isOpaque(Int(textureId))
	texels.withUnsafeBufferPointer { fillTexturedTriangleTail($0.baseAddress!, yA, yB, yC, xA, xB, xC, colorA, colorB, colorC, viewXA, viewXB, viewXC, viewYA, viewYB, viewYC, viewZA, viewZB, viewZC, textureId) }
}

	func fillTexturedTriangleTail(_ texels: UnsafePointer<Int32>, _ yA: Int32, _ yB: Int32, _ yC: Int32, _ xA: Int32, _ xB: Int32, _ xC: Int32, _ colorA: Int32, _ colorB: Int32, _ colorC: Int32, _ viewXA: Int32, _ viewXB: Int32, _ viewXC: Int32, _ viewYA: Int32, _ viewYB: Int32, _ viewYC: Int32, _ viewZA: Int32, _ viewZB: Int32, _ viewZC: Int32, _ textureId: Int32) {
		var yA = yA
		var yB = yB
		var yC = yC
		var xA = xA
		var xB = xB
		var xC = xC
		var colorA = colorA
		var colorB = colorB
		var colorC = colorC
		var viewXA = viewXA
		var viewXB = viewXB
		var viewXC = viewXC
		var viewYA = viewYA
		var viewYB = viewYB
		var viewYC = viewYC
		var viewZA = viewZA
		var viewZB = viewZB
		var viewZC = viewZC
		var textureId = textureId
	var dxAB: Int32 = xB &- xA
	var dyAB: Int32 = yB &- yA
	var dxAC: Int32 = xC &- xA
	var dyAC: Int32 = yC &- yA
	var colorStepAB: Int32 = colorB &- colorA
	var colorStepAC: Int32 = colorC &- colorA

	var xStepAB: Int32 = k(0)
	if yB != yA {
		xStepAB = (((xB &- xA) &<< k(16)) / (yB &- yA))
	}

	var xStepBC: Int32 = k(0)
	if yC != yB {
		xStepBC = (((xC &- xB) &<< k(16)) / (yC &- yB))
	}

	var xStepAC: Int32 = k(0)
	if yC != yA {
		xStepAC = (((xA &- xC) &<< k(16)) / (yA &- yC))
	}

	var length: Int32 = (dxAB &* dyAC) &- (dxAC &* dyAB)
	if length == k(0) {
		return
	}

	var colorStepA: Int32 = (((colorStepAB &* dyAC) &- (colorStepAC &* dyAB)) &<< k(9)) / length
	var colorStepB: Int32 = (((colorStepAC &* dxAB) &- (colorStepAB &* dxAC)) &<< k(9)) / length

	var local147: Int32 = viewXA &- viewXB
	var local151: Int32 = viewYA &- viewYB
	var local155: Int32 = viewZA &- viewZB

	var local159: Int32 = viewXC &- viewXA
	var local163: Int32 = viewYC &- viewYA
	var local167: Int32 = viewZC &- viewZA

	var local177: Int32 = ((local159 &* viewYA) &- (local163 &* viewXA)) &<< k(14)
	var local187: Int32 = ((local163 &* viewZA) &- (local167 &* viewYA)) &<< k(5)
	var local197: Int32 = ((local167 &* viewXA) &- (local159 &* viewZA)) &<< k(5)

	var local207: Int32 = ((local147 &* viewYA) &- (local151 &* viewXA)) &<< k(14)
	var local217: Int32 = ((local151 &* viewZA) &- (local155 &* viewYA)) &<< k(5)
	var local227: Int32 = ((local155 &* viewXA) &- (local147 &* viewZA)) &<< k(5)

	var local237: Int32 = ((local151 &* local159) &- (local147 &* local163)) &<< k(14)
	var local247: Int32 = ((local155 &* local163) &- (local151 &* local167)) &<< k(5)
	var local257: Int32 = ((local147 &* local167) &- (local155 &* local159)) &<< k(5)
	var local336: Int32 = 0

	if (yA <= yB) && (yA <= yC) {
		if yA < height {
			if yB > height {
				yB = height
			}

			if yC > height {
				yC = height
			}

			colorA = (((colorA &<< k(9)) &+ colorStepA) &- (colorStepA &* xA))
			if yB < yC {
				xA &<<= k(0x10)
				xC = xA
				if yA < k(0) {
					xC &-= (xStepAC &* yA)
					xA &-= (xStepAB &* yA)
					colorA &-= (colorStepB &* yA)
					yA = k(0)
				}

				xB &<<= k(0x10)
				if yB < k(0) {
					xB &-= (xStepBC &* yB)
					yB = k(0)
				}

				local336 = (yA &- centerY)
				local177 &+= (local197 &* local336)
				local207 &+= (local227 &* local336)
				local237 &+= (local257 &* local336)
				if ((yA != yB) && (xStepAC < xStepAB)) || ((yA == yB) && (xStepAC > xStepBC)) {
					yC &-= yB
					yB &-= yA
					yA = offsets[Int(yA)]
					while true {
						yB &-= 1
						if yB < k(0) {
							while true {
								yC &-= 1
								if yC < k(0) {
									return
								}

								drawTexturedScanline(texels, yA, (xC &>> k(16)), (xB &>> k(16)), colorA, colorStepA, local177, local207, local237, local187, local217, local247)
								xC &+= xStepAC
								xB &+= xStepBC
								colorA &+= colorStepB
								yA &+= stride
								local177 &+= local197
								local207 &+= local227
								local237 &+= local257
							}
						}

						drawTexturedScanline(texels, yA, (xC &>> k(16)), (xA &>> k(16)), colorA, colorStepA, local177, local207, local237, local187, local217, local247)
						xC &+= xStepAC
						xA &+= xStepAB
						colorA &+= colorStepB
						yA &+= stride
						local177 &+= local197
						local207 &+= local227
						local237 &+= local257
					}
				} else {
					yC &-= yB
					yB &-= yA
					yA = offsets[Int(yA)]
					while true {
						yB &-= 1
						if yB < k(0) {
							while true {
								yC &-= 1
								if yC < k(0) {
									return
								}

								drawTexturedScanline(texels, yA, (xB &>> k(16)), (xC &>> k(16)), colorA, colorStepA, local177, local207, local237, local187, local217, local247)
								xC &+= xStepAC
								xB &+= xStepBC
								colorA &+= colorStepB
								yA &+= stride
								local177 &+= local197
								local207 &+= local227
								local237 &+= local257
							}
						}

						drawTexturedScanline(texels, yA, (xA &>> k(16)), (xC &>> k(16)), colorA, colorStepA, local177, local207, local237, local187, local217, local247)
						xC &+= xStepAC
						xA &+= xStepAB
						colorA &+= colorStepB
						yA &+= stride
						local177 &+= local197
						local207 &+= local227
						local237 &+= local257
					}
				}
			} else {
				xA &<<= k(0x10)
				xB = xA
				if yA < k(0) {
					xB &-= (xStepAC &* yA)
					xA &-= (xStepAB &* yA)
					colorA &-= (colorStepB &* yA)
					yA = k(0)
				}

				xC &<<= k(0x10)
				if yC < k(0) {
					xC &-= (xStepBC &* yC)
					yC = k(0)
				}

				local336 = (yA &- centerY)
				local177 &+= (local197 &* local336)
				local207 &+= (local227 &* local336)
				local237 &+= (local257 &* local336)
				if ((yA == yC) || (xStepAC >= xStepAB)) && ((yA != yC) || (xStepBC <= xStepAB)) {
					yB &-= yC
					yC &-= yA
					yA = offsets[Int(yA)]
					while true {
						yC &-= 1
						if yC < k(0) {
							while true {
								yB &-= 1
								if yB < k(0) {
									return
								}
								drawTexturedScanline(texels, yA, (xA &>> k(16)), (xC &>> k(16)), colorA, colorStepA, local177, local207, local237, local187, local217, local247)
								xC &+= xStepBC
								xA &+= xStepAB
								colorA &+= colorStepB
								yA &+= stride
								local177 &+= local197
								local207 &+= local227
								local237 &+= local257
							}
						}

						drawTexturedScanline(texels, yA, (xA &>> k(16)), (xB &>> k(16)), colorA, colorStepA, local177, local207, local237, local187, local217, local247)
						xB &+= xStepAC
						xA &+= xStepAB
						colorA &+= colorStepB
						yA &+= stride
						local177 &+= local197
						local207 &+= local227
						local237 &+= local257
					}
				} else {
					yB &-= yC
					yC &-= yA
					yA = offsets[Int(yA)]
					while true {
						yC &-= 1
						if yC < k(0) {
							while true {
								yB &-= 1
								if yB < k(0) {
									return
								}

								drawTexturedScanline(texels, yA, (xC &>> k(16)), (xA &>> k(16)), colorA, colorStepA, local177, local207, local237, local187, local217, local247)
								xC &+= xStepBC
								xA &+= xStepAB
								colorA &+= colorStepB
								yA &+= stride
								local177 &+= local197
								local207 &+= local227
								local237 &+= local257
							}
						}

						drawTexturedScanline(texels, yA, (xB &>> k(16)), (xA &>> k(16)), colorA, colorStepA, local177, local207, local237, local187, local217, local247)
						xB &+= xStepAC
						xA &+= xStepAB
						colorA &+= colorStepB
						yA &+= stride
						local177 &+= local197
						local207 &+= local227
						local237 &+= local257
					}
				}
			}
		}
	} else if yB <= yC {
		if yB < height {
			if yC > height {
				yC = height
			}

			if yA > height {
				yA = height
			}

			colorB = (((colorB &<< k(9)) &+ colorStepA) &- (colorStepA &* xB))
			if yC < yA {
				xB &<<= k(0x10)
				xA = xB
				if yB < k(0) {
					xA &-= (xStepAB &* yB)
					xB &-= (xStepBC &* yB)
					colorB &-= (colorStepB &* yB)
					yB = k(0)
				}

				xC &<<= k(0x10)
				if yC < k(0) {
					xC &-= (xStepAC &* yC)
					yC = k(0)
				}

				local336 = (yB &- centerY)
				local177 &+= (local197 &* local336)
				local207 &+= (local227 &* local336)
				local237 &+= (local257 &* local336)
				if ((yB != yC) && (xStepAB < xStepBC)) || ((yB == yC) && (xStepAB > xStepAC)) {
					yA &-= yC
					yC &-= yB
					yB = offsets[Int(yB)]
					while true {
						yC &-= 1
						if yC < k(0) {
							while true {
								yA &-= 1
								if yA < k(0) {
									return
								}

								drawTexturedScanline(texels, yB, (xA &>> k(16)), (xC &>> k(16)), colorB, colorStepA, local177, local207, local237, local187, local217, local247)
								xA &+= xStepAB
								xC &+= xStepAC
								colorB &+= colorStepB
								yB &+= stride
								local177 &+= local197
								local207 &+= local227
								local237 &+= local257
							}
						}

						drawTexturedScanline(texels, yB, (xA &>> k(16)), (xB &>> k(16)), colorB, colorStepA, local177, local207, local237, local187, local217, local247)
						xA &+= xStepAB
						xB &+= xStepBC
						colorB &+= colorStepB
						yB &+= stride
						local177 &+= local197
						local207 &+= local227
						local237 &+= local257
					}
				} else {
					yA &-= yC
					yC &-= yB
					yB = offsets[Int(yB)]
					while true {
						yC &-= 1
						if yC < k(0) {
							while true {
								yA &-= 1
								if yA < k(0) {
									return
								}

								drawTexturedScanline(texels, yB, (xC &>> k(16)), (xA &>> k(16)), colorB, colorStepA, local177, local207, local237, local187, local217, local247)
								xA &+= xStepAB
								xC &+= xStepAC
								colorB &+= colorStepB
								yB &+= stride
								local177 &+= local197
								local207 &+= local227
								local237 &+= local257
							}
						}

						drawTexturedScanline(texels, yB, (xB &>> k(16)), (xA &>> k(16)), colorB, colorStepA, local177, local207, local237, local187, local217, local247)
						xA &+= xStepAB
						xB &+= xStepBC
						colorB &+= colorStepB
						yB &+= stride
						local177 &+= local197
						local207 &+= local227
						local237 &+= local257
					}
				}
			} else {
				xB &<<= k(0x10)
				xC = xB
				if yB < k(0) {
					xC &-= (xStepAB &* yB)
					xB &-= (xStepBC &* yB)
					colorB &-= (colorStepB &* yB)
					yB = k(0)
				}

				xA &<<= k(0x10)
				if yA < k(0) {
					xA &-= (xStepAC &* yA)
					yA = k(0)
				}

				local336 = (yB &- centerY)
				local177 &+= (local197 &* local336)
				local207 &+= (local227 &* local336)
				local237 &+= (local257 &* local336)
				if xStepAB < xStepBC {
					yC &-= yA
					yA &-= yB
					yB = offsets[Int(yB)]
					while true {
						yA &-= 1
						if yA < k(0) {
							while true {
								yC &-= 1
								if yC < k(0) {
									return
								}

								drawTexturedScanline(texels, yB, (xA &>> k(16)), (xB &>> k(16)), colorB, colorStepA, local177, local207, local237, local187, local217, local247)
								xA &+= xStepAC
								xB &+= xStepBC
								colorB &+= colorStepB
								yB &+= stride
								local177 &+= local197
								local207 &+= local227
								local237 &+= local257
							}
						}

						drawTexturedScanline(texels, yB, (xC &>> k(16)), (xB &>> k(16)), colorB, colorStepA, local177, local207, local237, local187, local217, local247)
						xC &+= xStepAB
						xB &+= xStepBC
						colorB &+= colorStepB
						yB &+= stride
						local177 &+= local197
						local207 &+= local227
						local237 &+= local257
					}
				} else {
					yC &-= yA
					yA &-= yB
					yB = offsets[Int(yB)]
					while true {
						yA &-= 1
						if yA < k(0) {
							while true {
								yC &-= 1
								if yC < k(0) {
									return
								}

								drawTexturedScanline(texels, yB, (xB &>> k(16)), (xA &>> k(16)), colorB, colorStepA, local177, local207, local237, local187, local217, local247)
								xA &+= xStepAC
								xB &+= xStepBC
								colorB &+= colorStepB
								yB &+= stride
								local177 &+= local197
								local207 &+= local227
								local237 &+= local257
							}
						}

						drawTexturedScanline(texels, yB, (xB &>> k(16)), (xC &>> k(16)), colorB, colorStepA, local177, local207, local237, local187, local217, local247)
						xC &+= xStepAB
						xB &+= xStepBC
						colorB &+= colorStepB
						yB &+= stride
						local177 &+= local197
						local207 &+= local227
						local237 &+= local257
					}
				}
			}
		}
	} else if yC < height {
		if yA > height {
			yA = height
		}

		if yB > height {
			yB = height
		}

		colorC = (((colorC &<< k(9)) &+ colorStepA) &- (colorStepA &* xC))
		if yA < yB {
			xC &<<= k(0x10)
			xB = xC
			if yC < k(0) {
				xB &-= (xStepBC &* yC)
				xC &-= (xStepAC &* yC)
				colorC &-= (colorStepB &* yC)
				yC = k(0)
			}

			xA &<<= k(0x10)
			if yA < k(0) {
				xA &-= (xStepAB &* yA)
				yA = k(0)
			}

			local336 = (yC &- centerY)
			local177 &+= (local197 &* local336)
			local207 &+= (local227 &* local336)
			local237 &+= (local257 &* local336)
			if xStepBC < xStepAC {
				yB &-= yA
				yA &-= yC
				yC = offsets[Int(yC)]
				while true {
					yA &-= 1
					if yA < k(0) {
						while true {
							yB &-= 1
							if yB < k(0) {
								return
							}

							drawTexturedScanline(texels, yC, (xB &>> k(16)), (xA &>> k(16)), colorC, colorStepA, local177, local207, local237, local187, local217, local247)
							xB &+= xStepBC
							xA &+= xStepAB
							colorC &+= colorStepB
							yC &+= stride
							local177 &+= local197
							local207 &+= local227
							local237 &+= local257
						}
					}

					drawTexturedScanline(texels, yC, (xB &>> k(16)), (xC &>> k(16)), colorC, colorStepA, local177, local207, local237, local187, local217, local247)
					xB &+= xStepBC
					xC &+= xStepAC
					colorC &+= colorStepB
					yC &+= stride
					local177 &+= local197
					local207 &+= local227
					local237 &+= local257
				}
			} else {
				yB &-= yA
				yA &-= yC
				yC = offsets[Int(yC)]
				while true {
					yA &-= 1
					if yA < k(0) {
						while true {
							yB &-= 1
							if yB < k(0) {
								return
							}

							drawTexturedScanline(texels, yC, (xA &>> k(16)), (xB &>> k(16)), colorC, colorStepA, local177, local207, local237, local187, local217, local247)
							xB &+= xStepBC
							xA &+= xStepAB
							colorC &+= colorStepB
							yC &+= stride
							local177 &+= local197
							local207 &+= local227
							local237 &+= local257
						}
					}

					drawTexturedScanline(texels, yC, (xC &>> k(16)), (xB &>> k(16)), colorC, colorStepA, local177, local207, local237, local187, local217, local247)
					xB &+= xStepBC
					xC &+= xStepAC
					colorC &+= colorStepB
					yC &+= stride
					local177 &+= local197
					local207 &+= local227
					local237 &+= local257
				}
			}
		} else {
			xC &<<= k(0x10)
			xA = xC
			if yC < k(0) {
				xA &-= (xStepBC &* yC)
				xC &-= (xStepAC &* yC)
				colorC &-= (colorStepB &* yC)
				yC = k(0)
			}

			xB &<<= k(0x10)
			if yB < k(0) {
				xB &-= (xStepAB &* yB)
				yB = k(0)
			}

			local336 = (yC &- centerY)
			local177 &+= (local197 &* local336)
			local207 &+= (local227 &* local336)
			local237 &+= (local257 &* local336)
			if xStepBC < xStepAC {
				yA &-= yB
				yB &-= yC
				yC = offsets[Int(yC)]
				while true {
					yB &-= 1
					if yB < k(0) {
						while true {
							yA &-= 1
							if yA < k(0) {
								return
							}

							drawTexturedScanline(texels, yC, (xB &>> k(16)), (xC &>> k(16)), colorC, colorStepA, local177, local207, local237, local187, local217, local247)
							xB &+= xStepAB
							xC &+= xStepAC
							colorC &+= colorStepB
							yC &+= stride
							local177 &+= local197
							local207 &+= local227
							local237 &+= local257
						}
					}

					drawTexturedScanline(texels, yC, (xA &>> k(16)), (xC &>> k(16)), colorC, colorStepA, local177, local207, local237, local187, local217, local247)
					xA &+= xStepBC
					xC &+= xStepAC
					colorC &+= colorStepB
					yC &+= stride
					local177 &+= local197
					local207 &+= local227
					local237 &+= local257
				}
			} else {
				yA &-= yB
				yB &-= yC
				yC = offsets[Int(yC)]
				while true {
					yB &-= 1
					if yB < k(0) {
						while true {
							yA &-= 1
							if yA < k(0) {
								return
							}

							drawTexturedScanline(texels, yC, (xC &>> k(16)), (xB &>> k(16)), colorC, colorStepA, local177, local207, local237, local187, local217, local247)
							xB &+= xStepAB
							xC &+= xStepAC
							colorC &+= colorStepB
							yC &+= stride
							local177 &+= local197
							local207 &+= local227
							local237 &+= local257
						}
					}

					drawTexturedScanline(texels, yC, (xC &>> k(16)), (xA &>> k(16)), colorC, colorStepA, local177, local207, local237, local187, local217, local247)
					xA &+= xStepBC
					xC &+= xStepAC
					colorC &+= colorStepB
					yC &+= stride
					local177 &+= local197
					local207 &+= local227
					local237 &+= local257
				}
			}
		}
	}
	}

	public func fillTexturedTriangle(_ yA: Int, _ yB: Int, _ yC: Int, _ xA: Int, _ xB: Int, _ xC: Int, _ colorA: Int, _ colorB: Int, _ colorC: Int, _ viewXA: Int, _ viewXB: Int, _ viewXC: Int, _ viewYA: Int, _ viewYB: Int, _ viewYC: Int, _ viewZA: Int, _ viewZB: Int, _ viewZC: Int, _ textureId: Int) {
		fillTexturedTriangle(Int32(truncatingIfNeeded: yA), Int32(truncatingIfNeeded: yB), Int32(truncatingIfNeeded: yC), Int32(truncatingIfNeeded: xA), Int32(truncatingIfNeeded: xB), Int32(truncatingIfNeeded: xC), Int32(truncatingIfNeeded: colorA), Int32(truncatingIfNeeded: colorB), Int32(truncatingIfNeeded: colorC), Int32(truncatingIfNeeded: viewXA), Int32(truncatingIfNeeded: viewXB), Int32(truncatingIfNeeded: viewXC), Int32(truncatingIfNeeded: viewYA), Int32(truncatingIfNeeded: viewYB), Int32(truncatingIfNeeded: viewYC), Int32(truncatingIfNeeded: viewZA), Int32(truncatingIfNeeded: viewZB), Int32(truncatingIfNeeded: viewZC), Int32(truncatingIfNeeded: textureId))
	}

	/// rt4 `Rasteriser.fillTexturedAlphaTriangle`: textured triangle for textures with transparent texels (falls back to flat-average gouraud when `alpha > 10` or texels are missing).

	public func fillTexturedAlphaTriangle(_ yA: Int32, _ yB: Int32, _ yC: Int32, _ xA: Int32, _ xB: Int32, _ xC: Int32, _ colorA: Int32, _ colorB: Int32, _ colorC: Int32, _ viewXA: Int32, _ viewXB: Int32, _ viewXC: Int32, _ viewYA: Int32, _ viewYB: Int32, _ viewYC: Int32, _ viewZA: Int32, _ viewZB: Int32, _ viewZC: Int32, _ textureId: Int32) {
		var yA = yA
		var yB = yB
		var yC = yC
		var xA = xA
		var xB = xB
		var xC = xC
		var colorA = colorA
		var colorB = colorB
		var colorC = colorC
		var viewXA = viewXA
		var viewXB = viewXB
		var viewXC = viewXC
		var viewYA = viewYA
		var viewYB = viewYB
		var viewYC = viewYC
		var viewZA = viewZA
		var viewZB = viewZB
		var viewZC = viewZC
		var textureId = textureId
		guard let tp = textureProvider else { return }
		let texelsOpt = cachedTexels(tp, textureId)
		if texelsOpt == nil || alpha > 10 {
		let average = Int32(truncatingIfNeeded: tp.averageColor(Int(textureId)))
		textureHasTransparency = true
		fillGouraudTriangle(yA, yB, yC, xA, xB, xC, multiplyLightness(average, colorA), multiplyLightness(average, colorB), multiplyLightness(average, colorC))
		return
	}

	guard let texels = texelsOpt else { return }
	lowDetail = tp.isLowDetail(Int(textureId))
	opaque = tp.isOpaque(Int(textureId))
	texels.withUnsafeBufferPointer { fillTexturedAlphaTriangleTail($0.baseAddress!, yA, yB, yC, xA, xB, xC, colorA, colorB, colorC, viewXA, viewXB, viewXC, viewYA, viewYB, viewYC, viewZA, viewZB, viewZC, textureId) }
}

	func fillTexturedAlphaTriangleTail(_ texels: UnsafePointer<Int32>, _ yA: Int32, _ yB: Int32, _ yC: Int32, _ xA: Int32, _ xB: Int32, _ xC: Int32, _ colorA: Int32, _ colorB: Int32, _ colorC: Int32, _ viewXA: Int32, _ viewXB: Int32, _ viewXC: Int32, _ viewYA: Int32, _ viewYB: Int32, _ viewYC: Int32, _ viewZA: Int32, _ viewZB: Int32, _ viewZC: Int32, _ textureId: Int32) {
		var yA = yA
		var yB = yB
		var yC = yC
		var xA = xA
		var xB = xB
		var xC = xC
		var colorA = colorA
		var colorB = colorB
		var colorC = colorC
		var viewXA = viewXA
		var viewXB = viewXB
		var viewXC = viewXC
		var viewYA = viewYA
		var viewYB = viewYB
		var viewYC = viewYC
		var viewZA = viewZA
		var viewZB = viewZB
		var viewZC = viewZC
		var textureId = textureId
	var dxAB: Int32 = xB &- xA
	var dyAB: Int32 = yB &- yA
	var dxAC: Int32 = xC &- xA
	var dyAC: Int32 = yC &- yA
	var colorStepAB: Int32 = colorB &- colorA
	var colorStepAC: Int32 = colorC &- colorA

	var xStepAB: Int32 = k(0)
	if yB != yA {
		xStepAB = (((xB &- xA) &<< k(16)) / (yB &- yA))
	}

	var xStepBC: Int32 = k(0)
	if yC != yB {
		xStepBC = (((xC &- xB) &<< k(16)) / (yC &- yB))
	}

	var xStepAC: Int32 = k(0)
	if yC != yA {
		xStepAC = (((xA &- xC) &<< k(16)) / (yA &- yC))
	}

	var length: Int32 = (dxAB &* dyAC) &- (dxAC &* dyAB)
	if length == k(0) {
		return
	}

	var colorStepA: Int32 = (((colorStepAB &* dyAC) &- (colorStepAC &* dyAB)) &<< k(9)) / length
	var colorStepB: Int32 = (((colorStepAC &* dxAB) &- (colorStepAB &* dxAC)) &<< k(9)) / length

	var local152: Int32 = viewXA &- viewXB
	var local156: Int32 = viewYA &- viewYB
	var local160: Int32 = viewZA &- viewZB

	var local164: Int32 = viewXC &- viewXA
	var local168: Int32 = viewYC &- viewYA
	var local172: Int32 = viewZC &- viewZA

	var local182: Int32 = ((local164 &* viewYA) &- (local168 &* viewXA)) &<< k(14)
	var local192: Int32 = ((local168 &* viewZA) &- (local172 &* viewYA)) &<< k(8)
	var local202: Int32 = ((local172 &* viewXA) &- (local164 &* viewZA)) &<< k(5)
	var local212: Int32 = ((local152 &* viewYA) &- (local156 &* viewXA)) &<< k(14)
	var local222: Int32 = ((local156 &* viewZA) &- (local160 &* viewYA)) &<< k(8)
	var local232: Int32 = ((local160 &* viewXA) &- (local152 &* viewZA)) &<< k(5)
	var local242: Int32 = ((local156 &* local164) &- (local152 &* local168)) &<< k(14)
	var local252: Int32 = ((local160 &* local168) &- (local156 &* local172)) &<< k(8)
	var local262: Int32 = ((local152 &* local172) &- (local160 &* local164)) &<< k(5)
	var local341: Int32 = 0

	if (yA <= yB) && (yA <= yC) {
		if yA < height {
			if yB > height {
				yB = height
			}
			if yC > height {
				yC = height
			}

			colorA = (((colorA &<< k(9)) &+ colorStepA) &- (colorStepA &* xA))
			if yB < yC {
				xA &<<= k(0x10)
				xC = xA
				if yA < k(0) {
					xC &-= (xStepAC &* yA)
					xA &-= (xStepAB &* yA)
					colorA &-= (colorStepB &* yA)
					yA = k(0)
				}

				xB &<<= k(0x10)
				if yB < k(0) {
					xB &-= (xStepBC &* yB)
					yB = k(0)
				}

				local341 = (yA &- centerY)
				local182 &+= (local202 &* local341)
				local212 &+= (local232 &* local341)
				local242 &+= (local262 &* local341)
				if ((yA != yB) && (xStepAC < xStepAB)) || ((yA == yB) && (xStepAC > xStepBC)) {
					yC &-= yB
					yB &-= yA
					yA = offsets[Int(yA)]
					while true {
						yB &-= 1
						if yB < k(0) {
							while true {
								yC &-= 1
								if yC < k(0) {
									return
								}

								drawTexturedAlphaScanline(texels, yA, (xC &>> k(16)), (xB &>> k(16)), colorA, colorStepA, local182, local212, local242, local192, local222, local252)
								xC &+= xStepAC
								xB &+= xStepBC
								colorA &+= colorStepB
								yA &+= stride
								local182 &+= local202
								local212 &+= local232
								local242 &+= local262
							}
						}

						drawTexturedAlphaScanline(texels, yA, (xC &>> k(16)), (xA &>> k(16)), colorA, colorStepA, local182, local212, local242, local192, local222, local252)
						xC &+= xStepAC
						xA &+= xStepAB
						colorA &+= colorStepB
						yA &+= stride
						local182 &+= local202
						local212 &+= local232
						local242 &+= local262
					}
				} else {
					yC &-= yB
					yB &-= yA
					yA = offsets[Int(yA)]
					while true {
						yB &-= 1
						if yB < k(0) {
							while true {
								yC &-= 1
								if yC < k(0) {
									return
								}

								drawTexturedAlphaScanline(texels, yA, (xB &>> k(16)), (xC &>> k(16)), colorA, colorStepA, local182, local212, local242, local192, local222, local252)
								xC &+= xStepAC
								xB &+= xStepBC
								colorA &+= colorStepB
								yA &+= stride
								local182 &+= local202
								local212 &+= local232
								local242 &+= local262
							}
						}

						drawTexturedAlphaScanline(texels, yA, (xA &>> k(16)), (xC &>> k(16)), colorA, colorStepA, local182, local212, local242, local192, local222, local252)
						xC &+= xStepAC
						xA &+= xStepAB
						colorA &+= colorStepB
						yA &+= stride
						local182 &+= local202
						local212 &+= local232
						local242 &+= local262
					}
				}
			} else {
				xA &<<= k(0x10)
				xB = xA
				if yA < k(0) {
					xB &-= (xStepAC &* yA)
					xA &-= (xStepAB &* yA)
					colorA &-= (colorStepB &* yA)
					yA = k(0)
				}

				xC &<<= k(0x10)
				if yC < k(0) {
					xC &-= (xStepBC &* yC)
					yC = k(0)
				}

				local341 = (yA &- centerY)
				local182 &+= (local202 &* local341)
				local212 &+= (local232 &* local341)
				local242 &+= (local262 &* local341)
				if ((yA == yC) || (xStepAC >= xStepAB)) && ((yA != yC) || (xStepBC <= xStepAB)) {
					yB &-= yC
					yC &-= yA
					yA = offsets[Int(yA)]
					while true {
						yC &-= 1
						if yC < k(0) {
							while true {
								yB &-= 1
								if yB < k(0) {
									return
								}

								drawTexturedAlphaScanline(texels, yA, (xA &>> k(16)), (xC &>> k(16)), colorA, colorStepA, local182, local212, local242, local192, local222, local252)
								xC &+= xStepBC
								xA &+= xStepAB
								colorA &+= colorStepB
								yA &+= stride
								local182 &+= local202
								local212 &+= local232
								local242 &+= local262
							}
						}

						drawTexturedAlphaScanline(texels, yA, (xA &>> k(16)), (xB &>> k(16)), colorA, colorStepA, local182, local212, local242, local192, local222, local252)
						xB &+= xStepAC
						xA &+= xStepAB
						colorA &+= colorStepB
						yA &+= stride
						local182 &+= local202
						local212 &+= local232
						local242 &+= local262
					}
				} else {
					yB &-= yC
					yC &-= yA
					yA = offsets[Int(yA)]
					while true {
						yC &-= 1
						if yC < k(0) {
							while true {
								yB &-= 1
								if yB < k(0) {
									return
								}

								drawTexturedAlphaScanline(texels, yA, (xC &>> k(16)), (xA &>> k(16)), colorA, colorStepA, local182, local212, local242, local192, local222, local252)
								xC &+= xStepBC
								xA &+= xStepAB
								colorA &+= colorStepB
								yA &+= stride
								local182 &+= local202
								local212 &+= local232
								local242 &+= local262
							}
						}

						drawTexturedAlphaScanline(texels, yA, (xB &>> k(16)), (xA &>> k(16)), colorA, colorStepA, local182, local212, local242, local192, local222, local252)
						xB &+= xStepAC
						xA &+= xStepAB
						colorA &+= colorStepB
						yA &+= stride
						local182 &+= local202
						local212 &+= local232
						local242 &+= local262
					}
				}
			}
		}
	} else if yB <= yC {
		if yB < height {
			if yC > height {
				yC = height
			}
			if yA > height {
				yA = height
			}

			colorB = (((colorB &<< k(9)) &+ colorStepA) &- (colorStepA &* xB))
			if yC < yA {
				xB &<<= k(0x10)
				xA = xB
				if yB < k(0) {
					xA &-= (xStepAB &* yB)
					xB &-= (xStepBC &* yB)
					colorB &-= (colorStepB &* yB)
					yB = k(0)
				}
				xC &<<= k(0x10)
				if yC < k(0) {
					xC &-= (xStepAC &* yC)
					yC = k(0)
				}

				local341 = (yB &- centerY)
				local182 &+= (local202 &* local341)
				local212 &+= (local232 &* local341)
				local242 &+= (local262 &* local341)
				if ((yB != yC) && (xStepAB < xStepBC)) || ((yB == yC) && (xStepAB > xStepAC)) {
					yA &-= yC
					yC &-= yB
					yB = offsets[Int(yB)]
					while true {
						yC &-= 1
						if yC < k(0) {
							while true {
								yA &-= 1
								if yA < k(0) {
									return
								}

								drawTexturedAlphaScanline(texels, yB, (xA &>> k(16)), (xC &>> k(16)), colorB, colorStepA, local182, local212, local242, local192, local222, local252)
								xA &+= xStepAB
								xC &+= xStepAC
								colorB &+= colorStepB
								yB &+= stride
								local182 &+= local202
								local212 &+= local232
								local242 &+= local262
							}
						}

						drawTexturedAlphaScanline(texels, yB, (xA &>> k(16)), (xB &>> k(16)), colorB, colorStepA, local182, local212, local242, local192, local222, local252)
						xA &+= xStepAB
						xB &+= xStepBC
						colorB &+= colorStepB
						yB &+= stride
						local182 &+= local202
						local212 &+= local232
						local242 &+= local262
					}
				} else {
					yA &-= yC
					yC &-= yB
					yB = offsets[Int(yB)]
					while true {
						yC &-= 1
						if yC < k(0) {
							while true {
								yA &-= 1
								if yA < k(0) {
									return
								}

								drawTexturedAlphaScanline(texels, yB, (xC &>> k(16)), (xA &>> k(16)), colorB, colorStepA, local182, local212, local242, local192, local222, local252)
								xA &+= xStepAB
								xC &+= xStepAC
								colorB &+= colorStepB
								yB &+= stride
								local182 &+= local202
								local212 &+= local232
								local242 &+= local262
							}
						}

						drawTexturedAlphaScanline(texels, yB, (xB &>> k(16)), (xA &>> k(16)), colorB, colorStepA, local182, local212, local242, local192, local222, local252)
						xA &+= xStepAB
						xB &+= xStepBC
						colorB &+= colorStepB
						yB &+= stride
						local182 &+= local202
						local212 &+= local232
						local242 &+= local262
					}
				}
			} else {
				xB &<<= k(0x10)
				xC = xB
				if yB < k(0) {
					xC &-= (xStepAB &* yB)
					xB &-= (xStepBC &* yB)
					colorB &-= (colorStepB &* yB)
					yB = k(0)
				}

				xA &<<= k(0x10)
				if yA < k(0) {
					xA &-= (xStepAC &* yA)
					yA = k(0)
				}

				local341 = (yB &- centerY)
				local182 &+= (local202 &* local341)
				local212 &+= (local232 &* local341)
				local242 &+= (local262 &* local341)
				if xStepAB < xStepBC {
					yC &-= yA
					yA &-= yB
					yB = offsets[Int(yB)]
					while true {
						yA &-= 1
						if yA < k(0) {
							while true {
								yC &-= 1
								if yC < k(0) {
									return
								}

								drawTexturedAlphaScanline(texels, yB, (xA &>> k(16)), (xB &>> k(16)), colorB, colorStepA, local182, local212, local242, local192, local222, local252)
								xA &+= xStepAC
								xB &+= xStepBC
								colorB &+= colorStepB
								yB &+= stride
								local182 &+= local202
								local212 &+= local232
								local242 &+= local262
							}
						}

						drawTexturedAlphaScanline(texels, yB, (xC &>> k(16)), (xB &>> k(16)), colorB, colorStepA, local182, local212, local242, local192, local222, local252)
						xC &+= xStepAB
						xB &+= xStepBC
						colorB &+= colorStepB
						yB &+= stride
						local182 &+= local202
						local212 &+= local232
						local242 &+= local262
					}
				} else {
					yC &-= yA
					yA &-= yB
					yB = offsets[Int(yB)]
					while true {
						yA &-= 1
						if yA < k(0) {
							while true {
								yC &-= 1
								if yC < k(0) {
									return
								}

								drawTexturedAlphaScanline(texels, yB, (xB &>> k(16)), (xA &>> k(16)), colorB, colorStepA, local182, local212, local242, local192, local222, local252)
								xA &+= xStepAC
								xB &+= xStepBC
								colorB &+= colorStepB
								yB &+= stride
								local182 &+= local202
								local212 &+= local232
								local242 &+= local262
							}
						}

						drawTexturedAlphaScanline(texels, yB, (xB &>> k(16)), (xC &>> k(16)), colorB, colorStepA, local182, local212, local242, local192, local222, local252)
						xC &+= xStepAB
						xB &+= xStepBC
						colorB &+= colorStepB
						yB &+= stride
						local182 &+= local202
						local212 &+= local232
						local242 &+= local262
					}
				}
			}
		}
	} else if yC < height {
		if yA > height {
			yA = height
		}
		if yB > height {
			yB = height
		}

		colorC = (((colorC &<< k(9)) &+ colorStepA) &- (colorStepA &* xC))
		if yA < yB {
			xC &<<= k(0x10)
			xB = xC
			if yC < k(0) {
				xB &-= (xStepBC &* yC)
				xC &-= (xStepAC &* yC)
				colorC &-= (colorStepB &* yC)
				yC = k(0)
			}
			xA &<<= k(0x10)
			if yA < k(0) {
				xA &-= (xStepAB &* yA)
				yA = k(0)
			}

			local341 = (yC &- centerY)
			local182 &+= (local202 &* local341)
			local212 &+= (local232 &* local341)
			local242 &+= (local262 &* local341)
			if xStepBC < xStepAC {
				yB &-= yA
				yA &-= yC
				yC = offsets[Int(yC)]
				while true {
					yA &-= 1
					if yA < k(0) {
						while true {
							yB &-= 1
							if yB < k(0) {
								return
							}

							drawTexturedAlphaScanline(texels, yC, (xB &>> k(16)), (xA &>> k(16)), colorC, colorStepA, local182, local212, local242, local192, local222, local252)
							xB &+= xStepBC
							xA &+= xStepAB
							colorC &+= colorStepB
							yC &+= stride
							local182 &+= local202
							local212 &+= local232
							local242 &+= local262
						}
					}

					drawTexturedAlphaScanline(texels, yC, (xB &>> k(16)), (xC &>> k(16)), colorC, colorStepA, local182, local212, local242, local192, local222, local252)
					xB &+= xStepBC
					xC &+= xStepAC
					colorC &+= colorStepB
					yC &+= stride
					local182 &+= local202
					local212 &+= local232
					local242 &+= local262
				}
			} else {
				yB &-= yA
				yA &-= yC
				yC = offsets[Int(yC)]
				while true {
					yA &-= 1
					if yA < k(0) {
						while true {
							yB &-= 1
							if yB < k(0) {
								return
							}

							drawTexturedAlphaScanline(texels, yC, (xA &>> k(16)), (xB &>> k(16)), colorC, colorStepA, local182, local212, local242, local192, local222, local252)
							xB &+= xStepBC
							xA &+= xStepAB
							colorC &+= colorStepB
							yC &+= stride
							local182 &+= local202
							local212 &+= local232
							local242 &+= local262
						}
					}

					drawTexturedAlphaScanline(texels, yC, (xC &>> k(16)), (xB &>> k(16)), colorC, colorStepA, local182, local212, local242, local192, local222, local252)
					xB &+= xStepBC
					xC &+= xStepAC
					colorC &+= colorStepB
					yC &+= stride
					local182 &+= local202
					local212 &+= local232
					local242 &+= local262
				}
			}
		} else {
			xC &<<= k(0x10)
			xA = xC
			if yC < k(0) {
				xA &-= (xStepBC &* yC)
				xC &-= (xStepAC &* yC)
				colorC &-= (colorStepB &* yC)
				yC = k(0)
			}

			xB &<<= k(0x10)
			if yB < k(0) {
				xB &-= (xStepAB &* yB)
				yB = k(0)
			}

			local341 = (yC &- centerY)
			local182 &+= (local202 &* local341)
			local212 &+= (local232 &* local341)
			local242 &+= (local262 &* local341)
			if xStepBC < xStepAC {
				yA &-= yB
				yB &-= yC
				yC = offsets[Int(yC)]
				while true {
					yB &-= 1
					if yB < k(0) {
						while true {
							yA &-= 1
							if yA < k(0) {
								return
							}

							drawTexturedAlphaScanline(texels, yC, (xB &>> k(16)), (xC &>> k(16)), colorC, colorStepA, local182, local212, local242, local192, local222, local252)
							xB &+= xStepAB
							xC &+= xStepAC
							colorC &+= colorStepB
							yC &+= stride
							local182 &+= local202
							local212 &+= local232
							local242 &+= local262
						}
					}

					drawTexturedAlphaScanline(texels, yC, (xA &>> k(16)), (xC &>> k(16)), colorC, colorStepA, local182, local212, local242, local192, local222, local252)
					xA &+= xStepBC
					xC &+= xStepAC
					colorC &+= colorStepB
					yC &+= stride
					local182 &+= local202
					local212 &+= local232
					local242 &+= local262
				}
			} else {
				yA &-= yB
				yB &-= yC
				yC = offsets[Int(yC)]
				while true {
					yB &-= 1
					if yB < k(0) {
						while true {
							yA &-= 1
							if yA < k(0) {
								return
							}

							drawTexturedAlphaScanline(texels, yC, (xC &>> k(16)), (xB &>> k(16)), colorC, colorStepA, local182, local212, local242, local192, local222, local252)
							xB &+= xStepAB
							xC &+= xStepAC
							colorC &+= colorStepB
							yC &+= stride
							local182 &+= local202
							local212 &+= local232
							local242 &+= local262
						}
					}

					drawTexturedAlphaScanline(texels, yC, (xC &>> k(16)), (xA &>> k(16)), colorC, colorStepA, local182, local212, local242, local192, local222, local252)
					xA &+= xStepBC
					xC &+= xStepAC
					colorC &+= colorStepB
					yC &+= stride
					local182 &+= local202
					local212 &+= local232
					local242 &+= local262
				}
			}
		}
	}
	}

	public func fillTexturedAlphaTriangle(_ yA: Int, _ yB: Int, _ yC: Int, _ xA: Int, _ xB: Int, _ xC: Int, _ colorA: Int, _ colorB: Int, _ colorC: Int, _ viewXA: Int, _ viewXB: Int, _ viewXC: Int, _ viewYA: Int, _ viewYB: Int, _ viewYC: Int, _ viewZA: Int, _ viewZB: Int, _ viewZC: Int, _ textureId: Int) {
		fillTexturedAlphaTriangle(Int32(truncatingIfNeeded: yA), Int32(truncatingIfNeeded: yB), Int32(truncatingIfNeeded: yC), Int32(truncatingIfNeeded: xA), Int32(truncatingIfNeeded: xB), Int32(truncatingIfNeeded: xC), Int32(truncatingIfNeeded: colorA), Int32(truncatingIfNeeded: colorB), Int32(truncatingIfNeeded: colorC), Int32(truncatingIfNeeded: viewXA), Int32(truncatingIfNeeded: viewXB), Int32(truncatingIfNeeded: viewXC), Int32(truncatingIfNeeded: viewYA), Int32(truncatingIfNeeded: viewYB), Int32(truncatingIfNeeded: viewYC), Int32(truncatingIfNeeded: viewZA), Int32(truncatingIfNeeded: viewZB), Int32(truncatingIfNeeded: viewZC), Int32(truncatingIfNeeded: textureId))
	}

	/// rt4 `Rasteriser.getOffsetRemainder`: viewport left column.

	public func getOffsetRemainder() -> Int32 {
		return offsets[Int(k(0))] % stride
	}

	/// rt4 `Rasteriser.drawTexturedAlphaScanline`.

	func drawTexturedAlphaScanline(_ texels: UnsafePointer<Int32>, _ offset: Int32, _ xA: Int32, _ xB: Int32, _ lightnessA: Int32, _ lightnessB: Int32, _ verticalA: Int32, _ verticalB: Int32, _ verticalC: Int32, _ horizontalA: Int32, _ horizontalB: Int32, _ horizontalC: Int32) {
		var offset = offset
		var xA = xA
		var xB = xB
		var lightnessA = lightnessA
		var lightnessB = lightnessB
		var verticalA = verticalA
		var verticalB = verticalB
		var verticalC = verticalC
		var horizontalA = horizontalA
		var horizontalB = horizontalB
		var horizontalC = horizontalC
		if testX {
			if xB > width {
				xB = width
			}

			if xA < k(0) {
				xA = k(0)
			}
		}

		if xA >= xB {
			return
		}

		offset &+= xA
		lightnessA &+= (lightnessB &* xA)

		var length: Int32 = xB &- xA
		var lightness: Int32 = 0
		var uvStep: Int32 = 0
		var uA: Int32 = 0
		var vA: Int32 = 0
		var uB: Int32 = 0
		var vB: Int32 = 0
		var c: Int32 = 0
		var delta: Int32 = 0
		var color: Int32 = 0
		var uv: Int32 = 0

		if !lowDetail {
			delta = (xA &- centerX)
			verticalA &+= ((horizontalA &>> k(3)) &* delta)
			verticalB &+= ((horizontalB &>> k(3)) &* delta)
			verticalC &+= ((horizontalC &>> k(3)) &* delta)

			c = (verticalC &>> k(14))
			if c == k(0) {
				uA = k(0)
				vA = k(0)
			} else {
				uA = (verticalA / c)
				vA = (verticalB / c)
			}

			verticalA = (verticalA &+ horizontalA)
			verticalB = (verticalB &+ horizontalB)
			verticalC = (verticalC &+ horizontalC)
			c = (verticalC &>> k(14))
			if c == k(0) {
				uB = k(0)
				vB = k(0)
			} else {
				uB = (verticalA / c)
				vB = (verticalB / c)
			}

			uv = ((uA &<< k(18)) &+ vA)
			uvStep = ((((uB &- uA) &>> k(3)) &<< k(18)) &+ ((vB &- vA) &>> k(3)))
			length &>>= k(3)
			lightnessB &<<= k(3)
			lightness = (lightnessA &>> k(8))
			if opaque {
				if length > k(0) {
					repeat {
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t1 = Int(offset)
						offset &+= 1
						px[_t1] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t2 = Int(offset)
						offset &+= 1
						px[_t2] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t3 = Int(offset)
						offset &+= 1
						px[_t3] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t4 = Int(offset)
						offset &+= 1
						px[_t4] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t5 = Int(offset)
						offset &+= 1
						px[_t5] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t6 = Int(offset)
						offset &+= 1
						px[_t6] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t7 = Int(offset)
						offset &+= 1
						px[_t7] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t8 = Int(offset)
						offset &+= 1
						px[_t8] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))

						uA = uB
						vA = vB

						verticalA &+= horizontalA
						verticalB &+= horizontalB
						verticalC &+= horizontalC

						c = (verticalC &>> k(14))
						if c == k(0) {
							uB = k(0)
							vB = k(0)
						} else {
							uB = (verticalA / c)
							vB = (verticalB / c)
						}

						uv = ((uA &<< k(18)) &+ vA)
						uvStep = ((((uB &- uA) &>> k(3)) &<< k(18)) &+ ((vB &- vA) &>> k(3)))
						lightnessA &+= lightnessB
						lightness = (lightnessA &>> k(8))
						length &-= 1
					} while length > k(0)
				}

				length = ((xB &- xA) & k(0x7))
				if length > k(0) {
					repeat {
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t9 = Int(offset)
						offset &+= 1
						px[_t9] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep
						length &-= 1
					} while length > k(0)
				}
			} else {
				if length > k(0) {
					repeat {
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1

						uv &+= uvStep
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1

						uA = uB
						vA = vB
						verticalA &+= horizontalA
						verticalB &+= horizontalB
						verticalC &+= horizontalC

						c = (verticalC &>> k(14))
						if c == k(0) {
							uB = k(0)
							vB = k(0)
						} else {
							uB = (verticalA / c)
							vB = (verticalB / c)
						}

						uv = ((uA &<< k(18)) &+ vA)
						uvStep = ((((uB &- uA) &>> k(3)) &<< k(18)) &+ ((vB &- vA) &>> k(3)))
						lightnessA &+= lightnessB
						lightness = (lightnessA &>> k(8))
						length &-= 1
					} while length > k(0)
				}

				length = ((xB &- xA) & k(0x7))
				if length > k(0) {
					repeat {
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep
						length &-= 1
					} while length > k(0)
				}
			}
			return
		}

		delta = (xA &- centerX)
		verticalA = (verticalA &+ ((horizontalA &>> k(3)) &* delta))
		verticalB = (verticalB &+ ((horizontalB &>> k(3)) &* delta))
		verticalC = (verticalC &+ ((horizontalC &>> k(3)) &* delta))

		c = (verticalC &>> k(12))
		if c == k(0) {
			uA = k(0)
			vA = k(0)
		} else {
			uA = (verticalA / c)
			vA = (verticalB / c)
		}

		verticalA = (verticalA &+ horizontalA)
		verticalB = (verticalB &+ horizontalB)
		verticalC = (verticalC &+ horizontalC)

		c = (verticalC &>> k(12))
		if c == k(0) {
			uB = k(0)
			vB = k(0)
		} else {
			uB = (verticalA / c)
			vB = (verticalB / c)
		}

		uv = ((uA &<< k(20)) &+ vA)
		uvStep = ((((uB &- uA) &>> k(3)) &<< k(20)) &+ ((vB &- vA) &>> k(3)))
		length &>>= k(0x3)
		lightnessB &<<= k(3)
		lightness = (lightnessA &>> k(8))

		if opaque {
			if length > k(0) {
				repeat {
					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t10 = Int(offset)
					offset &+= 1
					px[_t10] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t11 = Int(offset)
					offset &+= 1
					px[_t11] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t12 = Int(offset)
					offset &+= 1
					px[_t12] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t13 = Int(offset)
					offset &+= 1
					px[_t13] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t14 = Int(offset)
					offset &+= 1
					px[_t14] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t15 = Int(offset)
					offset &+= 1
					px[_t15] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t16 = Int(offset)
					offset &+= 1
					px[_t16] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t17 = Int(offset)
					offset &+= 1
					px[_t17] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))

					uA = uB
					vA = vB
					verticalA &+= horizontalA
					verticalB &+= horizontalB
					verticalC &+= horizontalC

					c = (verticalC &>> k(12))
					if c == k(0) {
						uB = k(0)
						vB = k(0)
					} else {
						uB = (verticalA / c)
						vB = (verticalB / c)
					}

					uv = ((uA &<< k(20)) &+ vA)
					uvStep = ((((uB &- uA) &>> k(3)) &<< k(20)) &+ ((vB &- vA) &>> k(3)))
					lightnessA &+= lightnessB
					lightness = (lightnessA &>> k(8))
					length &-= 1
				} while length > k(0)
			}

			length = ((xB &- xA) & k(0x7))
			if length > k(0) {
				repeat {
					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t18 = Int(offset)
					offset &+= 1
					px[_t18] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep
					length &-= 1
				} while length > k(0)
			}
			return
		}

		if length > k(0) {
			repeat {
				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1

				uA = uB
				vA = vB
				verticalA &+= horizontalA
				verticalB &+= horizontalB
				verticalC &+= horizontalC

				c = (verticalC &>> k(12))
				if c == k(0) {
					uB = k(0)
					vB = k(0)
				} else {
					uB = (verticalA / c)
					vB = (verticalB / c)
				}

				uv = ((uA &<< k(20)) &+ vA)
				uvStep = ((((uB &- uA) &>> k(3)) &<< k(20)) &+ ((vB &- vA) &>> k(3)))
				lightnessA &+= lightnessB
				lightness = (lightnessA &>> k(8))
				length &-= 1
			} while length > k(0)
		}

		length = ((xB &- xA) & k(0x7))
		if length <= k(0) {
			return
		}

		repeat {
			color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
			if color != k(0) {
				px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
			}
			offset &+= 1
			uv &+= uvStep
			length &-= 1
		} while length > k(0)
	}

	/// rt4 `Rasteriser.drawTexturedScanline`.

	func drawTexturedScanline(_ texels: UnsafePointer<Int32>, _ offset: Int32, _ xA: Int32, _ xB: Int32, _ lightnessA: Int32, _ lightnessB: Int32, _ verticalA: Int32, _ verticalB: Int32, _ verticalC: Int32, _ horizontalA: Int32, _ horizontalB: Int32, _ horizontalC: Int32) {
		var offset = offset
		var xA = xA
		var xB = xB
		var lightnessA = lightnessA
		var lightnessB = lightnessB
		var verticalA = verticalA
		var verticalB = verticalB
		var verticalC = verticalC
		var horizontalA = horizontalA
		var horizontalB = horizontalB
		var horizontalC = horizontalC
		if testX {
			if xB > width {
				xB = width
			}

			if xA < k(0) {
				xA = k(0)
			}
		}

		if xA >= xB {
			return
		}

		offset &+= xA
		lightnessA &+= (lightnessB &* xA)

		var length: Int32 = xB &- xA
		var lightness: Int32 = 0
		var uvStep: Int32 = 0
		var uA: Int32 = 0
		var vA: Int32 = 0
		var uB: Int32 = 0
		var vB: Int32 = 0
		var c: Int32 = 0
		var delta: Int32 = 0
		var color: Int32 = 0
		var uv: Int32 = 0

		if !lowDetail {
			delta = (xA &- centerX)
			verticalA &+= (horizontalA &* delta)
			verticalB &+= (horizontalB &* delta)
			verticalC &+= (horizontalC &* delta)

			c = (verticalC &>> k(14))
			if c == k(0) {
				uA = k(0)
				vA = k(0)
			} else {
				uA = (verticalA / c)
				vA = (verticalB / c)
			}

			verticalA &+= (horizontalA &* length)
			verticalB &+= (horizontalB &* length)
			verticalC &+= (horizontalC &* length)

			c = (verticalC &>> k(14))
			if c == k(0) {
				uB = k(0)
				vB = k(0)
			} else {
				uB = (verticalA / c)
				vB = (verticalB / c)
			}

			uv = ((uA &<< k(18)) &+ vA)
			uvStep = ((((uB &- uA) / length) &<< k(18)) &+ ((vB &- vA) / length))
			length &>>= k(0x3)
			lightnessB &<<= k(3)
			lightness = (lightnessA &>> k(8))

			if opaque {
				if length > k(0) {
					repeat {
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t19 = Int(offset)
						offset &+= 1
						px[_t19] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t20 = Int(offset)
						offset &+= 1
						px[_t20] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t21 = Int(offset)
						offset &+= 1
						px[_t21] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t22 = Int(offset)
						offset &+= 1
						px[_t22] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t23 = Int(offset)
						offset &+= 1
						px[_t23] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t24 = Int(offset)
						offset &+= 1
						px[_t24] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t25 = Int(offset)
						offset &+= 1
						px[_t25] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t26 = Int(offset)
						offset &+= 1
						px[_t26] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep

						lightnessA &+= lightnessB
						lightness = (lightnessA &>> k(8))
						length &-= 1
					} while length > k(0)
				}

				length = ((xB &- xA) & k(0x7))
				if length > k(0) {
					repeat {
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						let _t27 = Int(offset)
						offset &+= 1
						px[_t27] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						uv &+= uvStep
						length &-= 1
					} while length > k(0)
				}
			} else {
				if length > k(0) {
					repeat {
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1
						uv &+= uvStep

						lightnessA &+= lightnessB
						lightness = (lightnessA &>> k(8))
						length &-= 1
					} while length > k(0)
				}

				length = ((xB &- xA) & k(0x7))
				if length > k(0) {
					repeat {
						color = texels[Int(((uv & k(0x3F80)) &+ ushr(uv, k(25))))]
						if color != k(0) {
							px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
						}
						offset &+= 1

						uv &+= uvStep
						length &-= 1
					} while length > k(0)
				}
			}
			return
		}

		delta = (xA &- centerX)
		verticalA = (verticalA &+ (horizontalA &* delta))
		verticalB = (verticalB &+ (horizontalB &* delta))
		verticalC = (verticalC &+ (horizontalC &* delta))

		c = (verticalC &>> k(12))
		if c == k(0) {
			uA = k(0)
			vA = k(0)
		} else {
			uA = (verticalA / c)
			vA = (verticalB / c)
		}

		verticalA &+= (horizontalA &* length)
		verticalB &+= (horizontalB &* length)
		verticalC &+= (horizontalC &* length)
		c = (verticalC &>> k(12))
		if c == k(0) {
			uB = k(0)
			vB = k(0)
		} else {
			uB = (verticalA / c)
			vB = (verticalB / c)
		}

		uv = ((uA &<< k(20)) &+ vA)
		uvStep = ((((uB &- uA) / length) &<< k(20)) &+ ((vB &- vA) / length))
		length &>>= k(0x3)
		lightnessB = (lightnessB &<< k(3))
		lightness = (lightnessA &>> k(8))

		if opaque {
			if length > k(0) {
				repeat {
					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t28 = Int(offset)
					offset &+= 1
					px[_t28] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t29 = Int(offset)
					offset &+= 1
					px[_t29] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t30 = Int(offset)
					offset &+= 1
					px[_t30] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t31 = Int(offset)
					offset &+= 1
					px[_t31] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t32 = Int(offset)
					offset &+= 1
					px[_t32] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t33 = Int(offset)
					offset &+= 1
					px[_t33] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t34 = Int(offset)
					offset &+= 1
					px[_t34] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t35 = Int(offset)
					offset &+= 1
					px[_t35] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep

					lightnessA &+= lightnessB
					lightness = (lightnessA &>> k(8))
					length &-= 1
				} while length > k(0)
			}

			length = ((xB &- xA) & k(0x7))
			if length > k(0) {
				repeat {
					color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
					let _t36 = Int(offset)
					offset &+= 1
					px[_t36] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
					uv &+= uvStep
					length &-= 1
				} while length > k(0)
			}
			return
		}

		if length > k(0) {
			repeat {
				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				offset &+= 1
				uv &+= uvStep

				color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
				if color != k(0) {
					px[Int(offset)] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
				}
				uv &+= uvStep

				lightnessA &+= lightnessB
				lightness = (lightnessA &>> k(8))
				length &-= 1
			} while length > k(0)
		}

		length = ((xB &- xA) & k(0x7))
		if length <= k(0) {
			return
		}

		repeat {
			color = texels[Int(((uv & k(0xFC0)) &+ ushr(uv, k(26))))]
			if color != k(0) {
				let _t37 = Int(offset)
				offset &+= 1
				px[_t37] = (((((color & k(0xFF00FF)) &* lightness) & k(Int32(bitPattern: 0xFF00FF00))) &+ (((color & k(0xFF00)) &* lightness) & k(0xFF0000))) &>> k(8))
			}

			uv &+= uvStep
			length &-= 1
		} while length > k(0)
	}

	/// rt4 `Rasteriser.fillTriangle`: flat-colour triangle (colour is an RGB value from `palette`), honours `alpha`.

	public func fillTriangle(_ yA: Int32, _ yB: Int32, _ yC: Int32, _ xA: Int32, _ xB: Int32, _ xC: Int32, _ color: Int32) {
		var yA = yA
		var yB = yB
		var yC = yC
		var xA = xA
		var xB = xB
		var xC = xC
		var color = color
		var mAB: Int32 = k(0)
		if yB != yA {
			mAB = (((xB &- xA) &<< k(16)) / (yB &- yA))
		}

		var mBC: Int32 = k(0)
		if yC != yB {
			mBC = (((xC &- xB) &<< k(16)) / (yC &- yB))
		}

		var mAC: Int32 = k(0)
		if yC != yA {
			mAC = (((xA &- xC) &<< k(16)) / (yA &- yC))
		}

		if (yA <= yB) && (yA <= yC) {
			if yA < height {
				if yB > height {
					yB = height
				}

				if yC > height {
					yC = height
				}

				if yB < yC {
					xA &<<= k(0x10)
					xC = xA
					if yA < k(0) {
						xC &-= (mAC &* yA)
						xA &-= (mAB &* yA)
						yA = k(0)
					}

					xB &<<= k(0x10)
					if yB < k(0) {
						xB &-= (mBC &* yB)
						yB = k(0)
					}

					if ((yA != yB) && (mAC < mAB)) || ((yA == yB) && (mAC > mBC)) {
						yC &-= yB
						yB &-= yA
						yA = offsets[Int(yA)]
						while true {
							yB &-= 1
							if yB < k(0) {
								while true {
									yC &-= 1
									if yC < k(0) {
										return
									}

									drawScanline(yA, color, (xC &>> k(16)), (xB &>> k(16)))
									xC &+= mAC
									xB &+= mBC
									yA &+= stride
								}
							}

							drawScanline(yA, color, (xC &>> k(16)), (xA &>> k(16)))
							xC &+= mAC
							xA &+= mAB
							yA &+= stride
						}
					} else {
						yC &-= yB
						yB &-= yA
						yA = offsets[Int(yA)]
						while true {
							yB &-= 1
							if yB < k(0) {
								while true {
									yC &-= 1
									if yC < k(0) {
										return
									}

									drawScanline(yA, color, (xB &>> k(16)), (xC &>> k(16)))
									xC &+= mAC
									xB &+= mBC
									yA &+= stride
								}
							}

							drawScanline(yA, color, (xA &>> k(16)), (xC &>> k(16)))
							xC &+= mAC
							xA &+= mAB
							yA &+= stride
						}
					}
				} else {
					xA &<<= k(0x10)
					xB = xA
					if yA < k(0) {
						xB &-= (mAC &* yA)
						xA &-= (mAB &* yA)
						yA = k(0)
					}

					xC &<<= k(0x10)
					if yC < k(0) {
						xC &-= (mBC &* yC)
						yC = k(0)
					}

					if ((yA != yC) && (mAC < mAB)) || ((yA == yC) && (mBC > mAB)) {
						yB &-= yC
						yC &-= yA
						yA = offsets[Int(yA)]
						while true {
							yC &-= 1
							if yC < k(0) {
								while true {
									yB &-= 1
									if yB < k(0) {
										return
									}

									drawScanline(yA, color, (xC &>> k(16)), (xA &>> k(16)))
									xC &+= mBC
									xA &+= mAB
									yA &+= stride
								}
							}

							drawScanline(yA, color, (xB &>> k(16)), (xA &>> k(16)))
							xB &+= mAC
							xA &+= mAB
							yA &+= stride
						}
					} else {
						yB &-= yC
						yC &-= yA
						yA = offsets[Int(yA)]
						while true {
							yC &-= 1
							if yC < k(0) {
								while true {
									yB &-= 1
									if yB < k(0) {
										return
									}

									drawScanline(yA, color, (xA &>> k(16)), (xC &>> k(16)))
									xC &+= mBC
									xA &+= mAB
									yA &+= stride
								}
							}

							drawScanline(yA, color, (xA &>> k(16)), (xB &>> k(16)))
							xB &+= mAC
							xA &+= mAB
							yA &+= stride
						}
					}
				}
			}
		} else if yB <= yC {
			if yB < height {
				if yC > height {
					yC = height
				}

				if yA > height {
					yA = height
				}

				if yC < yA {
					xB &<<= k(0x10)
					xA = xB
					if yB < k(0) {
						xA &-= (mAB &* yB)
						xB &-= (mBC &* yB)
						yB = k(0)
					}

					xC &<<= k(0x10)
					if yC < k(0) {
						xC &-= (mAC &* yC)
						yC = k(0)
					}

					if ((yB != yC) && (mAB < mBC)) || ((yB == yC) && (mAB > mAC)) {
						yA &-= yC
						yC &-= yB
						yB = offsets[Int(yB)]
						while true {
							yC &-= 1
							if yC < k(0) {
								while true {
									yA &-= 1
									if yA < k(0) {
										return
									}

									drawScanline(yB, color, (xA &>> k(16)), (xC &>> k(16)))
									xA &+= mAB
									xC &+= mAC
									yB &+= stride
								}
							}

							drawScanline(yB, color, (xA &>> k(16)), (xB &>> k(16)))
							xA &+= mAB
							xB &+= mBC
							yB &+= stride
						}
					} else {
						yA &-= yC
						yC &-= yB
						yB = offsets[Int(yB)]
						while true {
							yC &-= 1
							if yC < k(0) {
								while true {
									yA &-= 1
									if yA < k(0) {
										return
									}

									drawScanline(yB, color, (xC &>> k(16)), (xA &>> k(16)))
									xA &+= mAB
									xC &+= mAC
									yB &+= stride
								}
							}

							drawScanline(yB, color, (xB &>> k(16)), (xA &>> k(16)))
							xA &+= mAB
							xB &+= mBC
							yB &+= stride
						}
					}
				} else {
					xB &<<= k(0x10)
					xC = xB
					if yB < k(0) {
						xC &-= (mAB &* yB)
						xB &-= (mBC &* yB)
						yB = k(0)
					}

					xA &<<= k(0x10)
					if yA < k(0) {
						xA &-= (mAC &* yA)
						yA = k(0)
					}

					if mAB < mBC {
						yC &-= yA
						yA &-= yB
						yB = offsets[Int(yB)]
						while true {
							yA &-= 1
							if yA < k(0) {
								while true {
									yC &-= 1
									if yC < k(0) {
										return
									}

									drawScanline(yB, color, (xA &>> k(16)), (xB &>> k(16)))
									xA &+= mAC
									xB &+= mBC
									yB &+= stride
								}
							}

							drawScanline(yB, color, (xC &>> k(16)), (xB &>> k(16)))
							xC &+= mAB
							xB &+= mBC
							yB &+= stride
						}
					} else {
						yC &-= yA
						yA &-= yB
						yB = offsets[Int(yB)]
						while true {
							yA &-= 1
							if yA < k(0) {
								while true {
									yC &-= 1
									if yC < k(0) {
										return
									}

									drawScanline(yB, color, (xB &>> k(16)), (xA &>> k(16)))
									xA &+= mAC
									xB &+= mBC
									yB &+= stride
								}
							}

							drawScanline(yB, color, (xB &>> k(16)), (xC &>> k(16)))
							xC &+= mAB
							xB &+= mBC
							yB &+= stride
						}
					}
				}
			}
		} else if yC < height {
			if yA > height {
				yA = height
			}

			if yB > height {
				yB = height
			}

			if yA < yB {
				xC &<<= k(0x10)
				xB = xC
				if yC < k(0) {
					xB &-= (mBC &* yC)
					xC &-= (mAC &* yC)
					yC = k(0)
				}

				xA &<<= k(0x10)
				if yA < k(0) {
					xA &-= (mAB &* yA)
					yA = k(0)
				}

				if mBC < mAC {
					yB &-= yA
					yA &-= yC
					yC = offsets[Int(yC)]
					while true {
						yA &-= 1
						if yA < k(0) {
							while true {
								yB &-= 1
								if yB < k(0) {
									return
								}

								drawScanline(yC, color, (xB &>> k(16)), (xA &>> k(16)))
								xB &+= mBC
								xA &+= mAB
								yC &+= stride
							}
						}

						drawScanline(yC, color, (xB &>> k(16)), (xC &>> k(16)))
						xB &+= mBC
						xC &+= mAC
						yC &+= stride
					}
				} else {
					yB &-= yA
					yA &-= yC
					yC = offsets[Int(yC)]
					while true {
						yA &-= 1
						if yA < k(0) {
							while true {
								yB &-= 1
								if yB < k(0) {
									return
								}

								drawScanline(yC, color, (xA &>> k(16)), (xB &>> k(16)))
								xB &+= mBC
								xA &+= mAB
								yC &+= stride
							}
						}

						drawScanline(yC, color, (xC &>> k(16)), (xB &>> k(16)))
						xB &+= mBC
						xC &+= mAC
						yC &+= stride
					}
				}
			} else {
				xC &<<= k(0x10)
				xA = xC
				if yC < k(0) {
					xA &-= (mBC &* yC)
					xC &-= (mAC &* yC)
					yC = k(0)
				}

				xB &<<= k(0x10)
				if yB < k(0) {
					xB &-= (mAB &* yB)
					yB = k(0)
				}

				if mBC < mAC {
					yA &-= yB
					yB &-= yC
					yC = offsets[Int(yC)]
					while true {
						yB &-= 1
						if yB < k(0) {
							while true {
								yA &-= 1
								if yA < k(0) {
									return
								}

								drawScanline(yC, color, (xB &>> k(16)), (xC &>> k(16)))
								xB &+= mAB
								xC &+= mAC
								yC &+= stride
							}
						}

						drawScanline(yC, color, (xA &>> k(16)), (xC &>> k(16)))
						xA &+= mBC
						xC &+= mAC
						yC &+= stride
					}
				} else {
					yA &-= yB
					yB &-= yC
					yC = offsets[Int(yC)]
					while true {
						yB &-= 1
						if yB < k(0) {
							while true {
								yA &-= 1
								if yA < k(0) {
									return
								}

								drawScanline(yC, color, (xC &>> k(16)), (xB &>> k(16)))
								xB &+= mAB
								xC &+= mAC
								yC &+= stride
							}
						}

						drawScanline(yC, color, (xC &>> k(16)), (xA &>> k(16)))
						xA &+= mBC
						xC &+= mAC
						yC &+= stride
					}
				}
			}
		}
	}

	public func fillTriangle(_ yA: Int, _ yB: Int, _ yC: Int, _ xA: Int, _ xB: Int, _ xC: Int, _ color: Int) {
		fillTriangle(Int32(truncatingIfNeeded: yA), Int32(truncatingIfNeeded: yB), Int32(truncatingIfNeeded: yC), Int32(truncatingIfNeeded: xA), Int32(truncatingIfNeeded: xB), Int32(truncatingIfNeeded: xC), Int32(truncatingIfNeeded: color))
	}

	/// rt4 `Rasteriser.setBounds`: sets the projection centre relative to the viewport.

	public func setBounds(_ right: Int32, _ bottom: Int32) {
		var right = right
		var bottom = bottom
		var offset: Int32 = offsets[Int(k(0))]
		var top: Int32 = offset / stride
		var left: Int32 = offset &- (top &* stride)
		centerX = (right &- left)
		centerY = (bottom &- top)
		screenLowerX = (0 &- centerX)
		screenUpperX = (width &- centerX)
		screenLowerY = (0 &- centerY)
		screenUpperY = (height &- centerY)
	}

	/// rt4 `Rasteriser.drawGouraudScanline`.

	func drawGouraudScanline(_ offset: Int32, _ xA: Int32, _ xB: Int32, _ colorA: Int32, _ colorStep: Int32) {
		var offset = offset
		var xA = xA
		var xB = xB
		var colorA = colorA
		var colorStep = colorStep
		if testX {
			if xB > width {
				xB = width
			}

			if xA < k(0) {
				xA = k(0)
			}
		}

		if xA >= xB {
			return
		}

		offset &+= xA
		colorA &+= (colorStep &* xA)
		var alpha: Int32 = 0
		var invAlpha: Int32 = 0
		var srcColor: Int32 = 0
		var length: Int32 = 0
		var color: Int32 = 0

		if !jagged {
			length = (xB &- xA)
			if self.alpha == k(0) {
				repeat {
					let _t38 = Int(offset)
					offset &+= 1
					px[_t38] = pal[Int((colorA &>> k(8)))]
					colorA &+= colorStep
					length &-= 1
				} while length > k(0)
			} else {
				alpha = self.alpha
				invAlpha = (k(256) &- self.alpha)

				repeat {
					color = pal[Int((colorA &>> k(8)))]

					colorA &+= colorStep
					color = (((((color & k(0xFF00FF)) &* invAlpha) &>> k(8)) & k(0xFF00FF)) &+ ((((color & k(0xFF00)) &* invAlpha) &>> k(8)) & k(0xFF00)))

					srcColor = px[Int(offset)]
					let _t39 = Int(offset)
					offset &+= 1
					px[_t39] = ((color &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))

					length &-= 1
				} while length > k(0)
			}
		} else {
			length = ((xB &- xA) &>> k(2))
			colorStep &<<= k(2)

			if self.alpha == k(0) {
				if length > k(0) {
					repeat {
						color = pal[Int((colorA &>> k(8)))]
						colorA &+= colorStep
						let _t40 = Int(offset)
						offset &+= 1
						px[_t40] = color
						let _t41 = Int(offset)
						offset &+= 1
						px[_t41] = color
						let _t42 = Int(offset)
						offset &+= 1
						px[_t42] = color
						let _t43 = Int(offset)
						offset &+= 1
						px[_t43] = color
						length &-= 1
					} while length > k(0)
				}

				length = ((xB &- xA) & k(0x3))
				if length > k(0) {
					color = pal[Int((colorA &>> k(8)))]
					repeat {
						let _t44 = Int(offset)
						offset &+= 1
						px[_t44] = color
						length &-= 1
					} while length > k(0)
				}
			} else {
				alpha = self.alpha
				invAlpha = (k(256) &- self.alpha)
				if length > k(0) {
					repeat {
						color = pal[Int((colorA &>> k(8)))]

						colorA &+= colorStep
						color = (((((color & k(0xFF00FF)) &* invAlpha) &>> k(8)) & k(0xFF00FF)) &+ ((((color & k(0xFF00)) &* invAlpha) &>> k(8)) & k(0xFF00)))

						srcColor = px[Int(offset)]
						let _t45 = Int(offset)
						offset &+= 1
						px[_t45] = ((color &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))

						srcColor = px[Int(offset)]
						let _t46 = Int(offset)
						offset &+= 1
						px[_t46] = ((color &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))

						srcColor = px[Int(offset)]
						let _t47 = Int(offset)
						offset &+= 1
						px[_t47] = ((color &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))

						srcColor = px[Int(offset)]
						let _t48 = Int(offset)
						offset &+= 1
						px[_t48] = ((color &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))

						length &-= 1
					} while length > k(0)
				}

				length = ((xB &- xA) & k(0x3))
				if length <= k(0) {
					return
				}

				color = pal[Int((colorA &>> k(8)))]
				color = (((((color & k(0xFF00FF)) &* invAlpha) &>> k(8)) & k(0xFF00FF)) &+ ((((color & k(0xFF00)) &* invAlpha) &>> k(8)) & k(0xFF00)))
				repeat {
					srcColor = px[Int(offset)]
					let _t49 = Int(offset)
					offset &+= 1
					px[_t49] = ((color &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))
					length &-= 1
				} while length > k(0)
			}
		}
	}

	/// rt4 `Rasteriser.fillSpriteTriangle`: marks covered cells of `mask` with 1 (hit-test mask).

	public func fillSpriteTriangle(_ arg0: inout [UInt8], _ arg1: Int32, _ arg2: Int32, _ arg3: Int32, _ arg4: Int32, _ arg5: Int32, _ arg6: Int32, _ arg7: Int32) {
		var arg1 = arg1
		var arg2 = arg2
		var arg3 = arg3
		var arg4 = arg4
		var arg5 = arg5
		var arg6 = arg6
		var arg7 = arg7
		var local1: Int32 = k(0)
		if arg2 != arg1 {
			local1 = (((arg5 &- arg4) &<< k(16)) / (arg2 &- arg1))
		}

		var local16: Int32 = k(0)
		if arg3 != arg2 {
			local16 = (((arg6 &- arg5) &<< k(16)) / (arg3 &- arg2))
		}

		var local31: Int32 = k(0)
		if arg3 != arg1 {
			local31 = (((arg4 &- arg6) &<< k(16)) / (arg1 &- arg3))
		}

		if (arg1 <= arg2) && (arg1 <= arg3) {
			if arg2 < arg3 {
				arg4 &<<= k(0x10)
				arg6 = arg4
				if arg1 < k(0) {
					arg6 &-= (local31 &* arg1)
					arg4 &-= (local1 &* arg1)
					arg1 = k(0)
				}

				arg5 &<<= k(0x10)
				if arg2 < k(0) {
					arg5 &-= (local16 &* arg2)
					arg2 = k(0)
				}

				if ((arg1 == arg2) || (local31 >= local1)) && ((arg1 != arg2) || (local31 <= local16)) {
					arg3 &-= arg2
					arg2 &-= arg1
					arg1 &*= arg7
					while true {
						arg2 &-= 1
						if arg2 < k(0) {
							while true {
								arg3 &-= 1
								if arg3 < k(0) {
									return
								}
								drawSpriteScanline(&arg0, arg1, (arg5 &>> k(16)), (arg6 &>> k(16)))
								arg6 &+= local31
								arg5 &+= local16
								arg1 &+= arg7
							}
						}

						drawSpriteScanline(&arg0, arg1, (arg4 &>> k(16)), (arg6 &>> k(16)))
						arg6 &+= local31
						arg4 &+= local1
						arg1 &+= arg7
					}
				} else {
					arg3 &-= arg2
					arg2 &-= arg1
					arg1 &*= arg7
					while true {
						arg2 &-= 1
						if arg2 < k(0) {
							while true {
								arg3 &-= 1
								if arg3 < k(0) {
									return
								}
								drawSpriteScanline(&arg0, arg1, (arg6 &>> k(16)), (arg5 &>> k(16)))
								arg6 &+= local31
								arg5 &+= local16
								arg1 &+= arg7
							}
						}

						drawSpriteScanline(&arg0, arg1, (arg6 &>> k(16)), (arg4 &>> k(16)))
						arg6 &+= local31
						arg4 &+= local1
						arg1 &+= arg7
					}
				}
			} else {
				arg4 &<<= k(0x10)
				arg5 = arg4
				if arg1 < k(0) {
					arg5 &-= (local31 &* arg1)
					arg4 &-= (local1 &* arg1)
					arg1 = k(0)
				}

				arg6 &<<= k(0x10)
				if arg3 < k(0) {
					arg6 &-= (local16 &* arg3)
					arg3 = k(0)
				}

				if ((arg1 == arg3) || (local31 >= local1)) && ((arg1 != arg3) || (local16 <= local1)) {
					arg2 &-= arg3
					arg3 &-= arg1
					arg1 &*= arg7
					while true {
						arg3 &-= 1
						if arg3 < k(0) {
							while true {
								arg2 &-= 1
								if arg2 < k(0) {
									return
								}

								drawSpriteScanline(&arg0, arg1, (arg4 &>> k(16)), (arg6 &>> k(16)))
								arg6 &+= local16
								arg4 &+= local1
								arg1 &+= arg7
							}
						}

						drawSpriteScanline(&arg0, arg1, (arg4 &>> k(16)), (arg5 &>> k(16)))
						arg5 &+= local31
						arg4 &+= local1
						arg1 &+= arg7
					}
				} else {
					arg2 &-= arg3
					arg3 &-= arg1
					arg1 &*= arg7
					while true {
						arg3 &-= 1
						if arg3 < k(0) {
							while true {
								arg2 &-= 1
								if arg2 < k(0) {
									return
								}

								drawSpriteScanline(&arg0, arg1, (arg6 &>> k(16)), (arg4 &>> k(16)))
								arg6 &+= local16
								arg4 &+= local1
								arg1 &+= arg7
							}
						}

						drawSpriteScanline(&arg0, arg1, (arg5 &>> k(16)), (arg4 &>> k(16)))
						arg5 &+= local31
						arg4 &+= local1
						arg1 &+= arg7
					}
				}
			}
		} else if arg2 <= arg3 {
			if arg3 < arg1 {
				arg5 &<<= k(0x10)
				arg4 = arg5
				if arg2 < k(0) {
					arg4 &-= (local1 &* arg2)
					arg5 &-= (local16 &* arg2)
					arg2 = k(0)
				}

				arg6 &<<= k(0x10)
				if arg3 < k(0) {
					arg6 &-= (local31 &* arg3)
					arg3 = k(0)
				}

				if ((arg2 != arg3) && (local1 < local16)) || ((arg2 == arg3) && (local1 > local31)) {
					arg1 &-= arg3
					arg3 &-= arg2
					arg2 &*= arg7
					while true {
						arg3 &-= 1
						if arg3 < k(0) {
							while true {
								arg1 &-= 1
								if arg1 < k(0) {
									return
								}
								drawSpriteScanline(&arg0, arg2, (arg4 &>> k(16)), (arg6 &>> k(16)))
								arg4 &+= local1
								arg6 &+= local31
								arg2 &+= arg7
							}
						}

						drawSpriteScanline(&arg0, arg2, (arg4 &>> k(16)), (arg5 &>> k(16)))
						arg4 &+= local1
						arg5 &+= local16
						arg2 &+= arg7
					}
				} else {
					arg1 &-= arg3
					arg3 &-= arg2
					arg2 &*= arg7
					while true {
						arg3 &-= 1
						if arg3 < k(0) {
							while true {
								arg1 &-= 1
								if arg1 < k(0) {
									return
								}

								drawSpriteScanline(&arg0, arg2, (arg6 &>> k(16)), (arg4 &>> k(16)))
								arg4 &+= local1
								arg6 &+= local31
								arg2 &+= arg7
							}
						}

						drawSpriteScanline(&arg0, arg2, (arg5 &>> k(16)), (arg4 &>> k(16)))
						arg4 &+= local1
						arg5 &+= local16
						arg2 &+= arg7
					}
				}
			} else {
				arg5 &<<= k(0x10)
				arg6 = arg5
				if arg2 < k(0) {
					arg6 &-= (local1 &* arg2)
					arg5 &-= (local16 &* arg2)
					arg2 = k(0)
				}

				arg4 &<<= k(0x10)
				if arg1 < k(0) {
					arg4 &-= (local31 &* arg1)
					arg1 = k(0)
				}

				if local1 < local16 {
					arg3 &-= arg1
					arg1 &-= arg2
					arg2 &*= arg7
					while true {
						arg1 &-= 1
						if arg1 < k(0) {
							while true {
								arg3 &-= 1
								if arg3 < k(0) {
									return
								}

								drawSpriteScanline(&arg0, arg2, (arg4 &>> k(16)), (arg5 &>> k(16)))
								arg4 &+= local31
								arg5 &+= local16
								arg2 &+= arg7
							}
						}

						drawSpriteScanline(&arg0, arg2, (arg6 &>> k(16)), (arg5 &>> k(16)))
						arg6 &+= local1
						arg5 &+= local16
						arg2 &+= arg7
					}
				} else {
					arg3 &-= arg1
					arg1 &-= arg2
					arg2 &*= arg7
					while true {
						arg1 &-= 1
						if arg1 < k(0) {
							while true {
								arg3 &-= 1
								if arg3 < k(0) {
									return
								}

								drawSpriteScanline(&arg0, arg2, (arg5 &>> k(16)), (arg4 &>> k(16)))
								arg4 &+= local31
								arg5 &+= local16
								arg2 &+= arg7
							}
						}

						drawSpriteScanline(&arg0, arg2, (arg5 &>> k(16)), (arg6 &>> k(16)))
						arg6 &+= local1
						arg5 &+= local16
						arg2 &+= arg7
					}
				}
			}
		} else if arg1 < arg2 {
			arg6 &<<= k(0x10)
			arg5 = arg6
			if arg3 < k(0) {
				arg5 &-= (local16 &* arg3)
				arg6 &-= (local31 &* arg3)
				arg3 = k(0)
			}

			arg4 &<<= k(0x10)
			if arg1 < k(0) {
				arg4 &-= (local1 &* arg1)
				arg1 = k(0)
			}

			if local16 < local31 {
				arg2 &-= arg1
				arg1 &-= arg3
				arg3 &*= arg7
				while true {
					arg1 &-= 1
					if arg1 < k(0) {
						while true {
							arg2 &-= 1
							if arg2 < k(0) {
								return
							}

							drawSpriteScanline(&arg0, arg3, (arg5 &>> k(16)), (arg4 &>> k(16)))
							arg5 &+= local16
							arg4 &+= local1
							arg3 &+= arg7
						}
					}

					drawSpriteScanline(&arg0, arg3, (arg5 &>> k(16)), (arg6 &>> k(16)))
					arg5 &+= local16
					arg6 &+= local31
					arg3 &+= arg7
				}
			} else {
				arg2 &-= arg1
				arg1 &-= arg3
				arg3 &*= arg7
				while true {
					arg1 &-= 1
					if arg1 < k(0) {
						while true {
							arg2 &-= 1
							if arg2 < k(0) {
								return
							}

							drawSpriteScanline(&arg0, arg3, (arg4 &>> k(16)), (arg5 &>> k(16)))
							arg5 &+= local16
							arg4 &+= local1
							arg3 &+= arg7
						}
					}

					drawSpriteScanline(&arg0, arg3, (arg6 &>> k(16)), (arg5 &>> k(16)))
					arg5 &+= local16
					arg6 &+= local31
					arg3 &+= arg7
				}
			}
		} else {
			arg6 &<<= k(0x10)
			arg4 = arg6
			if arg3 < k(0) {
				arg4 &-= (local16 &* arg3)
				arg6 &-= (local31 &* arg3)
				arg3 = k(0)
			}

			arg5 &<<= k(0x10)
			if arg2 < k(0) {
				arg5 &-= (local1 &* arg2)
				arg2 = k(0)
			}

			if local16 < local31 {
				arg1 &-= arg2
				arg2 &-= arg3
				arg3 &*= arg7
				while true {
					arg2 &-= 1
					if arg2 < k(0) {
						while true {
							arg1 &-= 1
							if arg1 < k(0) {
								return
							}

							drawSpriteScanline(&arg0, arg3, (arg5 &>> k(16)), (arg6 &>> k(16)))
							arg5 &+= local1
							arg6 &+= local31
							arg3 &+= arg7
						}
					}

					drawSpriteScanline(&arg0, arg3, (arg4 &>> k(16)), (arg6 &>> k(16)))
					arg4 &+= local16
					arg6 &+= local31
					arg3 &+= arg7
				}
			} else {
				arg1 &-= arg2
				arg2 &-= arg3
				arg3 &*= arg7
				while true {
					arg2 &-= 1
					if arg2 < k(0) {
						while true {
							arg1 &-= 1
							if arg1 < k(0) {
								return
							}

							drawSpriteScanline(&arg0, arg3, (arg6 &>> k(16)), (arg5 &>> k(16)))
							arg5 &+= local1
							arg6 &+= local31
							arg3 &+= arg7
						}
					}

					drawSpriteScanline(&arg0, arg3, (arg6 &>> k(16)), (arg4 &>> k(16)))
					arg4 &+= local16
					arg6 &+= local31
					arg3 &+= arg7
				}
			}
		}
	}

	/// rt4 `Rasteriser.testPoints`: sets `testX` when any x is outside the viewport.

	public func testPoints(_ a: Int32, _ b: Int32, _ c: Int32) {
		var a = a
		var b = b
		var c = c
		testX = ((((((a < k(0)) || (a > width)) || (b < k(0))) || (b > width)) || (c < k(0))) || (c > width))
	}

	/// rt4 `Rasteriser.drawScanline`.

	func drawScanline(_ offset: Int32, _ color: Int32, _ xA: Int32, _ xB: Int32) {
		var offset = offset
		var color = color
		var xA = xA
		var xB = xB
		if testX {
			if xB > width {
				xB = width
			}
			if xA < k(0) {
				xA = k(0)
			}
		}

		if xA >= xB {
			return
		}

		offset &+= xA
		var length: Int32 = (xB &- xA) &>> k(2)
		if alpha == k(0) {
			while true {
				length &-= 1
				if length < k(0) {
					length = ((xB &- xA) & k(0x3))
					while true {
						length &-= 1
						if length < k(0) {
							return
						}
						let _t50 = Int(offset)
						offset &+= 1
						px[_t50] = color
					}
				}

				let _t51 = Int(offset)
				offset &+= 1
				px[_t51] = color
				let _t52 = Int(offset)
				offset &+= 1
				px[_t52] = color
				let _t53 = Int(offset)
				offset &+= 1
				px[_t53] = color
				let _t54 = Int(offset)
				offset &+= 1
				px[_t54] = color
			}
		} else if alpha == k(254) {
			while true {
				length &-= 1
				if length < k(0) {
					length = ((xB &- xA) & k(0x3))
					while true {
						length &-= 1
						if length < k(0) {
							return
						}
						let _t55 = Int(offset)
						offset &+= 1
						px[_t55] = px[Int(offset)]
					}
				}

				let _t56 = Int(offset)
				offset &+= 1
				px[_t56] = color
				let _t57 = Int(offset)
				offset &+= 1
				px[_t57] = color
				let _t58 = Int(offset)
				offset &+= 1
				px[_t58] = color
				let _t59 = Int(offset)
				offset &+= 1
				px[_t59] = color
			}
		} else {
			var alpha: Int32 = self.alpha
			var invAlpha: Int32 = k(256) &- self.alpha
			var sample: Int32 = ((((color & k(0xFF00FF)) &* invAlpha) &>> k(8)) & k(0xFF00FF)) &+ ((((color & k(0xFF00)) &* invAlpha) &>> k(8)) & k(0xFF00))

			while true {
				length &-= 1
				var srcColor: Int32 = 0

				if length < k(0) {
					length = ((xB &- xA) & k(0x3))
					while true {
						length &-= 1
						if length < k(0) {
							return
						}

						srcColor = px[Int(offset)]
						let _t60 = Int(offset)
						offset &+= 1
						px[_t60] = ((sample &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))
					}
				}

				srcColor = px[Int(offset)]
				let _t61 = Int(offset)
				offset &+= 1
				px[_t61] = ((sample &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))
				srcColor = px[Int(offset)]
				let _t62 = Int(offset)
				offset &+= 1
				px[_t62] = ((sample &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))
				srcColor = px[Int(offset)]
				let _t63 = Int(offset)
				offset &+= 1
				px[_t63] = ((sample &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))
				srcColor = px[Int(offset)]
				let _t64 = Int(offset)
				offset &+= 1
				px[_t64] = ((sample &+ ((((srcColor & k(0xFF00FF)) &* alpha) &>> k(8)) & k(0xFF00FF))) &+ ((((srcColor & k(0xFF00)) &* alpha) &>> k(8)) & k(0xFF00)))
			}
		}
	}

	/// rt4 `Rasteriser.getOffset`: viewport top row.

	public func getOffset() -> Int32 {
		return offsets[Int(k(0))] / stride
	}

	/// rt4 `Rasteriser.fillGouraudTriangle`: gouraud triangle with HSL16 vertex colours, honours `alpha`.

	public func fillGouraudTriangle(_ yA: Int32, _ yB: Int32, _ yC: Int32, _ xA: Int32, _ xB: Int32, _ xC: Int32, _ colorA: Int32, _ colorB: Int32, _ colorC: Int32) {
		var yA = yA
		var yB = yB
		var yC = yC
		var xA = xA
		var xB = xB
		var xC = xC
		var colorA = colorA
		var colorB = colorB
		var colorC = colorC
		var dxAB: Int32 = xB &- xA
		var dyAB: Int32 = yB &- yA
		var dxAC: Int32 = xC &- xA
		var dyAC: Int32 = yC &- yA
		var colorStepAB: Int32 = colorB &- colorA
		var colorStepAC: Int32 = colorC &- colorA

		var xStepBC: Int32 = 0
		if yC == yB {
			xStepBC = k(0)
		} else {
			xStepBC = (((xC &- xB) &<< k(16)) / (yC &- yB))
		}

		var xStepAB: Int32 = 0
		if yB == yA {
			xStepAB = k(0)
		} else {
			xStepAB = ((dxAB &<< k(16)) / dyAB)
		}

		var xStepAC: Int32 = 0
		if yC == yA {
			xStepAC = k(0)
		} else {
			xStepAC = ((dxAC &<< k(16)) / dyAC)
		}

		var length: Int32 = (dxAB &* dyAC) &- (dxAC &* dyAB)
		if length == k(0) {
			return
		}

		var colorStepA: Int32 = (((colorStepAB &* dyAC) &- (colorStepAC &* dyAB)) &<< k(8)) / length
		var colorStepB: Int32 = (((colorStepAC &* dxAB) &- (colorStepAB &* dxAC)) &<< k(8)) / length
		if (yA <= yB) && (yA <= yC) {
			if yA < height {
				if yB > height {
					yB = height
				}
				if yC > height {
					yC = height
				}

				colorA = (((colorA &<< k(8)) &+ colorStepA) &- (colorStepA &* xA))
				if yB < yC {
					xA &<<= k(0x10)
					xC = xA
					if yA < k(0) {
						xC &-= (xStepAC &* yA)
						xA &-= (xStepAB &* yA)
						colorA &-= (colorStepB &* yA)
						yA = k(0)
					}

					xB &<<= k(0x10)
					if yB < k(0) {
						xB &-= (xStepBC &* yB)
						yB = k(0)
					}

					if ((yA == yB) || (xStepAC >= xStepAB)) && ((yA != yB) || (xStepAC <= xStepBC)) {
						yC &-= yB
						yB &-= yA
						yA = offsets[Int(yA)]
						while true {
							yB &-= 1
							if yB < k(0) {
								while true {
									yC &-= 1
									if yC < k(0) {
										return
									}

									drawGouraudScanline(yA, (xB &>> k(16)), (xC &>> k(16)), colorA, colorStepA)
									xC &+= xStepAC
									xB &+= xStepBC
									colorA &+= colorStepB
									yA &+= stride
								}
							}

							drawGouraudScanline(yA, (xA &>> k(16)), (xC &>> k(16)), colorA, colorStepA)
							xC &+= xStepAC
							xA &+= xStepAB
							colorA &+= colorStepB
							yA &+= stride
						}
					} else {
						yC &-= yB
						yB &-= yA
						yA = offsets[Int(yA)]
						while true {
							yB &-= 1
							if yB < k(0) {
								while true {
									yC &-= 1
									if yC < k(0) {
										return
									}

									drawGouraudScanline(yA, (xC &>> k(16)), (xB &>> k(16)), colorA, colorStepA)
									xC &+= xStepAC
									xB &+= xStepBC
									colorA &+= colorStepB
									yA &+= stride
								}
							}

							drawGouraudScanline(yA, (xC &>> k(16)), (xA &>> k(16)), colorA, colorStepA)
							xC &+= xStepAC
							xA &+= xStepAB
							colorA &+= colorStepB
							yA &+= stride
						}
					}
				} else {
					xA &<<= k(0x10)
					xB = xA
					if yA < k(0) {
						xB &-= (xStepAC &* yA)
						xA &-= (xStepAB &* yA)
						colorA &-= (colorStepB &* yA)
						yA = k(0)
					}

					xC &<<= k(0x10)
					if yC < k(0) {
						xC &-= (xStepBC &* yC)
						yC = k(0)
					}

					if ((yA != yC) && (xStepAC < xStepAB)) || ((yA == yC) && (xStepBC > xStepAB)) {
						yB &-= yC
						yC &-= yA
						yA = offsets[Int(yA)]
						while true {
							yC &-= 1
							if yC < k(0) {
								while true {
									yB &-= 1
									if yB < k(0) {
										return
									}

									drawGouraudScanline(yA, (xC &>> k(16)), (xA &>> k(16)), colorA, colorStepA)
									xC &+= xStepBC
									xA &+= xStepAB
									colorA &+= colorStepB
									yA &+= stride
								}
							}

							drawGouraudScanline(yA, (xB &>> k(16)), (xA &>> k(16)), colorA, colorStepA)
							xB &+= xStepAC
							xA &+= xStepAB
							colorA &+= colorStepB
							yA &+= stride
						}
					} else {
						yB &-= yC
						yC &-= yA
						yA = offsets[Int(yA)]
						while true {
							yC &-= 1
							if yC < k(0) {
								while true {
									yB &-= 1
									if yB < k(0) {
										return
									}

									drawGouraudScanline(yA, (xA &>> k(16)), (xC &>> k(16)), colorA, colorStepA)
									xC &+= xStepBC
									xA &+= xStepAB
									colorA &+= colorStepB
									yA &+= stride
								}
							}

							drawGouraudScanline(yA, (xA &>> k(16)), (xB &>> k(16)), colorA, colorStepA)
							xB &+= xStepAC
							xA &+= xStepAB
							colorA &+= colorStepB
							yA &+= stride
						}
					}
				}
			}
		} else if yB <= yC {
			if yB < height {
				if yC > height {
					yC = height
				}
				if yA > height {
					yA = height
				}

				colorB = (((colorB &<< k(8)) &+ colorStepA) &- (colorStepA &* xB))
				if yC < yA {
					xB &<<= k(0x10)
					xA = xB
					if yB < k(0) {
						xA &-= (xStepAB &* yB)
						xB &-= (xStepBC &* yB)
						colorB &-= (colorStepB &* yB)
						yB = k(0)
					}
					xC &<<= k(0x10)
					if yC < k(0) {
						xC &-= (xStepAC &* yC)
						yC = k(0)
					}
					if ((yB == yC) || (xStepAB >= xStepBC)) && ((yB != yC) || (xStepAB <= xStepAC)) {
						yA &-= yC
						yC &-= yB
						yB = offsets[Int(yB)]
						while true {
							yC &-= 1
							if yC < k(0) {
								while true {
									yA &-= 1
									if yA < k(0) {
										return
									}

									drawGouraudScanline(yB, (xC &>> k(16)), (xA &>> k(16)), colorB, colorStepA)
									xA &+= xStepAB
									xC &+= xStepAC
									colorB &+= colorStepB
									yB &+= stride
								}
							}

							drawGouraudScanline(yB, (xB &>> k(16)), (xA &>> k(16)), colorB, colorStepA)
							xA &+= xStepAB
							xB &+= xStepBC
							colorB &+= colorStepB
							yB &+= stride
						}
					} else {
						yA &-= yC
						yC &-= yB
						yB = offsets[Int(yB)]
						while true {
							yC &-= 1
							if yC < k(0) {
								while true {
									yA &-= 1
									if yA < k(0) {
										return
									}

									drawGouraudScanline(yB, (xA &>> k(16)), (xC &>> k(16)), colorB, colorStepA)
									xA &+= xStepAB
									xC &+= xStepAC
									colorB &+= colorStepB
									yB &+= stride
								}
							}

							drawGouraudScanline(yB, (xA &>> k(16)), (xB &>> k(16)), colorB, colorStepA)
							xA &+= xStepAB
							xB &+= xStepBC
							colorB &+= colorStepB
							yB &+= stride
						}
					}
				} else {
					xB &<<= k(0x10)
					xC = xB
					if yB < k(0) {
						xC &-= (xStepAB &* yB)
						xB &-= (xStepBC &* yB)
						colorB &-= (colorStepB &* yB)
						yB = k(0)
					}

					xA &<<= k(0x10)
					if yA < k(0) {
						xA &-= (xStepAC &* yA)
						yA = k(0)
					}

					if xStepAB < xStepBC {
						yC &-= yA
						yA &-= yB
						yB = offsets[Int(yB)]
						while true {
							yA &-= 1
							if yA < k(0) {
								while true {
									yC &-= 1
									if yC < k(0) {
										return
									}

									drawGouraudScanline(yB, (xA &>> k(16)), (xB &>> k(16)), colorB, colorStepA)
									xA &+= xStepAC
									xB &+= xStepBC
									colorB &+= colorStepB
									yB &+= stride
								}
							}

							drawGouraudScanline(yB, (xC &>> k(16)), (xB &>> k(16)), colorB, colorStepA)
							xC &+= xStepAB
							xB &+= xStepBC
							colorB &+= colorStepB
							yB &+= stride
						}
					} else {
						yC &-= yA
						yA &-= yB
						yB = offsets[Int(yB)]
						while true {
							yA &-= 1
							if yA < k(0) {
								while true {
									yC &-= 1
									if yC < k(0) {
										return
									}

									drawGouraudScanline(yB, (xB &>> k(16)), (xA &>> k(16)), colorB, colorStepA)
									xA &+= xStepAC
									xB &+= xStepBC
									colorB &+= colorStepB
									yB &+= stride
								}
							}

							drawGouraudScanline(yB, (xB &>> k(16)), (xC &>> k(16)), colorB, colorStepA)
							xC &+= xStepAB
							xB &+= xStepBC
							colorB &+= colorStepB
							yB &+= stride
						}
					}
				}
			}
		} else if yC < height {
			if yA > height {
				yA = height
			}
			if yB > height {
				yB = height
			}

			colorC = (((colorC &<< k(8)) &+ colorStepA) &- (colorStepA &* xC))
			if yA < yB {
				xC &<<= k(0x10)
				xB = xC
				if yC < k(0) {
					xB &-= (xStepBC &* yC)
					xC &-= (xStepAC &* yC)
					colorC &-= (colorStepB &* yC)
					yC = k(0)
				}

				xA &<<= k(0x10)
				if yA < k(0) {
					xA &-= (xStepAB &* yA)
					yA = k(0)
				}

				if xStepBC < xStepAC {
					yB &-= yA
					yA &-= yC
					yC = offsets[Int(yC)]
					while true {
						yA &-= 1
						if yA < k(0) {
							while true {
								yB &-= 1
								if yB < k(0) {
									return
								}

								drawGouraudScanline(yC, (xB &>> k(16)), (xA &>> k(16)), colorC, colorStepA)
								xB &+= xStepBC
								xA &+= xStepAB
								colorC &+= colorStepB
								yC &+= stride
							}
						}

						drawGouraudScanline(yC, (xB &>> k(16)), (xC &>> k(16)), colorC, colorStepA)
						xB &+= xStepBC
						xC &+= xStepAC
						colorC &+= colorStepB
						yC &+= stride
					}
				} else {
					yB &-= yA
					yA &-= yC
					yC = offsets[Int(yC)]
					while true {
						yA &-= 1
						if yA < k(0) {
							while true {
								yB &-= 1
								if yB < k(0) {
									return
								}

								drawGouraudScanline(yC, (xA &>> k(16)), (xB &>> k(16)), colorC, colorStepA)
								xB &+= xStepBC
								xA &+= xStepAB
								colorC &+= colorStepB
								yC &+= stride
							}
						}

						drawGouraudScanline(yC, (xC &>> k(16)), (xB &>> k(16)), colorC, colorStepA)
						xB &+= xStepBC
						xC &+= xStepAC
						colorC &+= colorStepB
						yC &+= stride
					}
				}
			} else {
				xC &<<= k(0x10)
				xA = xC
				if yC < k(0) {
					xA &-= (xStepBC &* yC)
					xC &-= (xStepAC &* yC)
					colorC &-= (colorStepB &* yC)
					yC = k(0)
				}

				xB &<<= k(0x10)
				if yB < k(0) {
					xB &-= (xStepAB &* yB)
					yB = k(0)
				}

				if xStepBC < xStepAC {
					yA &-= yB
					yB &-= yC
					yC = offsets[Int(yC)]
					while true {
						yB &-= 1
						if yB < k(0) {
							while true {
								yA &-= 1
								if yA < k(0) {
									return
								}

								drawGouraudScanline(yC, (xB &>> k(16)), (xC &>> k(16)), colorC, colorStepA)
								xB &+= xStepAB
								xC &+= xStepAC
								colorC &+= colorStepB
								yC &+= stride
							}
						}

						drawGouraudScanline(yC, (xA &>> k(16)), (xC &>> k(16)), colorC, colorStepA)
						xA &+= xStepBC
						xC &+= xStepAC
						colorC &+= colorStepB
						yC &+= stride
					}
				} else {
					yA &-= yB
					yB &-= yC
					yC = offsets[Int(yC)]
					while true {
						yB &-= 1
						if yB < k(0) {
							while true {
								yA &-= 1
								if yA < k(0) {
									return
								}

								drawGouraudScanline(yC, (xC &>> k(16)), (xB &>> k(16)), colorC, colorStepA)
								xB &+= xStepAB
								xC &+= xStepAC
								colorC &+= colorStepB
								yC &+= stride
							}
						}

						drawGouraudScanline(yC, (xC &>> k(16)), (xA &>> k(16)), colorC, colorStepA)
						xA &+= xStepBC
						xC &+= xStepAC
						colorC &+= colorStepB
						yC &+= stride
					}
				}
			}
		}
	}

	public func fillGouraudTriangle(_ yA: Int, _ yB: Int, _ yC: Int, _ xA: Int, _ xB: Int, _ xC: Int, _ colorA: Int, _ colorB: Int, _ colorC: Int) {
		fillGouraudTriangle(Int32(truncatingIfNeeded: yA), Int32(truncatingIfNeeded: yB), Int32(truncatingIfNeeded: yC), Int32(truncatingIfNeeded: xA), Int32(truncatingIfNeeded: xB), Int32(truncatingIfNeeded: xC), Int32(truncatingIfNeeded: colorA), Int32(truncatingIfNeeded: colorB), Int32(truncatingIfNeeded: colorC))
	}

	/// rt4 `Rasteriser.drawSpriteScanline`.

	func drawSpriteScanline(_ dst: inout [UInt8], _ off: Int32, _ arg2: Int32, _ arg3: Int32) {
		var off = off
		var arg2 = arg2
		var arg3 = arg3
		if arg2 >= arg3 {
			return
		}

		off &+= arg2
		var local13: Int32 = (arg3 &- arg2) &>> k(2)
		while true {
			local13 &-= 1
			if local13 < k(0) {
				local13 = ((arg3 &- arg2) & k(0x3))
				while true {
					local13 &-= 1
					if local13 < k(0) {
						return
					}
					let _t65 = Int(off)
					off &+= 1
					dst[_t65] = 1
				}
			}

			let _t66 = Int(off)
			off &+= 1
			dst[_t66] = 1
			let _t67 = Int(off)
			off &+= 1
			dst[_t67] = 1
			let _t68 = Int(off)
			off &+= 1
			dst[_t68] = 1
			let _t69 = Int(off)
			off &+= 1
			dst[_t69] = 1
		}
	}
}
