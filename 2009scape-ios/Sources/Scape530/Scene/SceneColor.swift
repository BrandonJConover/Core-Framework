import Foundation

/// The parts of rt4 `ColorUtils` and `FluType` that terrain colouring needs.
enum SceneColor {
	/// rt4 `ColorUtils.rgbToHsl`: 0xRRGGBB to HSL16 (6-bit hue, 3-bit saturation, 7-bit lightness).
	static func rgbToHsl(_ rgb: Int) -> Int {
		let r = Double((rgb >> 16) & 0xFF) / 256.0
		let g = Double((rgb >> 8) & 0xFF) / 256.0
		let b = Double(rgb & 0xFF) / 256.0
		var hue = 0.0, saturation = 0.0
		var minC = r, maxC = r
		if r > g { minC = g }
		if b < minC { minC = b }
		if g > r { maxC = g }
		if b > maxC { maxC = b }
		let lightness = (minC + maxC) / 2.0
		if minC != maxC {
			if lightness < 0.5 { saturation = (maxC - minC) / (minC + maxC) }
			if lightness >= 0.5 { saturation = (maxC - minC) / (2.0 - maxC - minC) }
			if maxC == r { hue = (g - b) / (maxC - minC) }
			else if g == maxC { hue = (b - r) / (maxC - minC) + 2.0 }
			else if maxC == b { hue = (r - g) / (maxC - minC) + 4.0 }
		}
		var s = Int(saturation * 256.0)
		var l = Int(lightness * 256.0)
		hue /= 6.0
		if l < 0 { l = 0 } else if l > 255 { l = 255 }
		let h = Int(hue * 256.0)
		if s < 0 { s = 0 } else if s > 255 { s = 255 }
		if l > 243 { s >>= 4 } else if l > 217 { s >>= 3 } else if l > 192 { s >>= 2 } else if l > 179 { s >>= 1 }
		return ((h >> 2) << 10) + ((s >> 5) << 7) + (l >> 1)
	}

	/// rt4 `ColorUtils.multiplyLightnessSafe(a, b)`: shade `a` (0...127) applied to HSL16 `b`; -1 stays "no colour" (12345678).
	static func multiplyLightnessSafe(_ a: Int, _ b: Int) -> Int {
		if b == -1 { return 12345678 }
		var v = (a * (b & 0x7F)) >> 7
		if v < 2 { v = 2 } else if v > 126 { v = 126 }
		return v + (b & 0xFF80)
	}

	/// rt4 `ColorUtils.multiplyLightnessGrayscale(a, b)`: like above for overlays; -2 = hidden, -1 = grey (textured).
	static func multiplyLightnessGrayscale(_ a: Int, _ b: Int) -> Int {
		if a == -2 { return 12345678 }
		if a == -1 {
			return min(126, max(2, b))
		}
		var v = ((a & 0x7F) * b) >> 7
		if v < 2 { v = 2 } else if v > 126 { v = 126 }
		return (a & 0xFF80) + v
	}

	/// rt4 `ColorUtils.method1309`: HSL16 from averaged lightness, saturation and hue.
	static func blendedHsl(lightness: Int, saturation: Int, hue: Int) -> Int {
		var s = saturation
		if lightness > 243 { s >>= 4 } else if lightness > 217 { s >>= 3 } else if lightness > 192 { s >>= 2 } else if lightness > 179 { s >>= 1 }
		return (lightness >> 1) + ((s >> 5) << 7) + ((hue >> 2) << 10)
	}

	/// rt4 `ColorUtils.multiplyLightness3(a, b)`.
	static func multiplyLightness(_ a: Int, _ b: Int) -> Int {
		var v = (b * (a & 0x7F)) >> 7
		if v < 2 { v = 2 } else if v > 126 { v = 126 }
		return (a & 0xFF80) + v
	}

	/// rt4 `FluType.rgbToHsl` side effects: the four numbers blended over the 11x11 underlay neighbourhood.
	struct Underlay {
		var saturation = 0
		var weightedHue = 0
		var lightness = 0
		var chroma = 0

		init(rgb: Int) {
			let r = Double((rgb >> 16) & 0xFF) / 256.0
			let g = Double((rgb >> 8) & 0xFF) / 256.0
			let b = Double(rgb & 0xFF) / 256.0
			var minC = r
			if g < r { minC = g }
			if b < minC { minC = b }
			var maxC = r
			var hue = 0.0
			if g > r { maxC = g }
			if b > maxC { maxC = b }
			var sat = 0.0
			let light = (maxC + minC) / 2.0
			if minC != maxC {
				if light < 0.5 { sat = (maxC - minC) / (maxC + minC) }
				if maxC == r { hue = (g - b) / (maxC - minC) }
				else if g == maxC { hue = (b - r) / (maxC - minC) + 2.0 }
				else if b == maxC { hue = (r - g) / (maxC - minC) + 4.0 }
				if light >= 0.5 { sat = (maxC - minC) / ((2.0 - maxC) - minC) }
			}
			if light > 0.5 { chroma = Int(sat * (1.0 - light) * 512.0) } else { chroma = Int(sat * light * 512.0) }
			if chroma < 1 { chroma = 1 }
			saturation = Int(sat * 256.0)
			lightness = Int(light * 256.0)
			if lightness < 0 { lightness = 0 } else if lightness > 255 { lightness = 255 }
			hue /= 6.0
			weightedHue = Int(Double(chroma) * hue)
			if saturation < 0 { saturation = 0 } else if saturation > 255 { saturation = 255 }
		}
	}
}
