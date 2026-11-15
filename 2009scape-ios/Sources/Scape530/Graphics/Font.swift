/// Port of rt4 `Font` / `SoftwareFont`: a 256-glyph bitmap font made of a
/// sprite group (archive 8) plus metrics (archive 13, same group id), with
/// rt4's kerning and inline tags (`<col=ff0000>`, `<shad>`, `<br>`, ...).
/// Strings are drawn from cp1252 bytes, like `JagString`.
public final class BitmapFont {
	public let lineHeight: Int
	let glyphWidths: [Int]
	let kerning: [Int8]?
	let glyphs: [SpriteFrame]
	let paragraphTopPadding: Int
	let paragraphBottomPadding: Int
	/// Optional name icons for `<img=n>` (rt4 `nameIcons`).
	public var nameIcons: [SpriteFrame] = []

	// Per-draw state, rt4 keeps these static on Font.
	private var color: UInt32 = 0, colorOverride: UInt32 = 0
	private var shadow = -1, shadowOverride = -1
	private var alpha = 256, alphaOverride = 256
	private var strikeColor = -1, underlineColor = -1
	private var spaceWidth = 0, extraSpaceWidth = 0

	public init(metrics data: [UInt8], glyphs sheet: SpriteSheet) {
		glyphs = sheet.frames
		var widths = [Int](repeating: 0, count: 256)
		if data.count == 257 {
			for i in 0..<256 { widths[i] = Int(data[i]) }
			glyphWidths = widths
			kerning = nil
			lineHeight = Int(data[256])
		} else {
			var o = 0
			for i in 0..<256 { widths[i] = Int(data[o]); o += 1 }
			var heights = [Int](repeating: 0, count: 256), tops = [Int](repeating: 0, count: 256)
			for i in 0..<256 { heights[i] = Int(data[o]); o += 1 }
			for i in 0..<256 { tops[i] = Int(data[o]); o += 1 }
			var left = [[Int8]](repeating: [], count: 256), right = [[Int8]](repeating: [], count: 256)
			for i in 0..<256 {
				var acc: Int8 = 0
				left[i] = (0..<heights[i]).map { _ in acc &+= Int8(bitPattern: data[o]); o += 1; return acc }
			}
			for i in 0..<256 {
				var acc: Int8 = 0
				right[i] = (0..<heights[i]).map { _ in acc &+= Int8(bitPattern: data[o]); o += 1; return acc }
			}
			var k = [Int8](repeating: 0, count: 65536)
			for a in 0..<256 where a != 32 && a != 160 {
				for b in 0..<256 where b != 32 && b != 160 {
					k[a << 8 | b] = Int8(truncatingIfNeeded: BitmapFont.pairKerning(right, left, tops, widths, heights, a, b))
				}
			}
			glyphWidths = widths
			kerning = k
			lineHeight = tops[32] + heights[32]
		}
		var top = Int.max, bottom = Int.min
		for f in sheet.frames.prefix(256) {
			if f.yOffset < top && f.innerHeight != 0 { top = f.yOffset }
			if f.yOffset + f.innerHeight > bottom { bottom = f.yOffset + f.innerHeight }
		}
		paragraphTopPadding = lineHeight - top
		paragraphBottomPadding = bottom - lineHeight
	}

	/// rt4 `Font.method2870` (note: rt4 passes the right edge of `a`'s
	/// predecessor table as arg1 and the left of `b` as arg0).
	static func pairKerning(_ rightEdges: [[Int8]], _ leftEdges: [[Int8]], _ tops: [Int], _ widths: [Int], _ heights: [Int], _ a: Int, _ b: Int) -> Int {
		let aTop = tops[a], aBottom = aTop + heights[a]
		let bTop = tops[b], bBottom = bTop + heights[b]
		let from = max(aTop, bTop), to = min(aBottom, bBottom)
		var best = min(widths[a], widths[b])
		let ra = rightEdges[a], lb = leftEdges[b]
		var ia = from - aTop, ib = from - bTop
		var y = from
		while y < to {
			let v = Int(ra[ia]) + Int(lb[ib])
			if v < best { best = v }
			ia += 1; ib += 1; y += 1
		}
		return -best
	}

	// MARK: measuring

	public func stringWidth(_ s: String) -> Int { width(Cp1252.encode(s)) }

	func width(_ s: [UInt8]) -> Int {
		var tagStart = -1, prev = 0, w = 0
		var i = 0
		while i < s.count {
			var c = Int(s[i])
			if c == 60 {
				tagStart = i
			} else {
				if c == 62 && tagStart != -1 {
					let tag = Cp1252.decode(s[(tagStart + 1)..<i])
					tagStart = -1
					if let e = BitmapFont.entity(tag) {
						c = e
					} else {
						if tag.hasPrefix("img="), let n = Int(tag.dropFirst(4)), n < nameIcons.count {
							w += nameIcons[n].innerWidth
							prev = 0
						}
						i += 1
						continue
					}
				}
				if tagStart == -1 {
					w += glyphWidths[c]
					if let k = kerning, prev != 0 { w += Int(k[prev << 8 | c]) }
					prev = c
				}
			}
			i += 1
		}
		return w
	}

	static func entity(_ tag: String) -> Int? {
		switch tag {
		case "lt": return 60
		case "gt": return 62
		case "nbsp": return 160
		case "shy": return 173
		case "times": return 215
		case "euro": return 128
		case "copy": return 169
		case "reg": return 174
		default: return nil
		}
	}

	// MARK: drawing

	private func setColors(_ rgb: UInt32, _ shadow: Int, _ alpha: Int = 256) {
		strikeColor = -1; underlineColor = -1
		self.shadow = shadow; shadowOverride = shadow
		color = rgb; colorOverride = rgb
		self.alpha = alpha; alphaOverride = alpha
		spaceWidth = 0; extraSpaceWidth = 0
	}

	/// Draws `text` with its baseline at `y` (rt4 `renderLeft`). `shadow` -1 = none.
	public func drawLeft(_ text: String, x: Int, y: Int, color: UInt32, shadow: Int = -1, into r: inout Raster) {
		setColors(color, shadow)
		render(Cp1252.encode(text), x, y, &r)
	}

	public func drawCenter(_ text: String, x: Int, y: Int, color: UInt32, shadow: Int = -1, into r: inout Raster) {
		let b = Cp1252.encode(text)
		setColors(color, shadow)
		render(b, x - width(b) / 2, y, &r)
	}

	public func drawRight(_ text: String, x: Int, y: Int, color: UInt32, shadow: Int = -1, into r: inout Raster) {
		let b = Cp1252.encode(text)
		setColors(color, shadow)
		render(b, x - width(b), y, &r)
	}

	private func parseTag(_ tag: String) {
		func hex(_ s: Substring) -> Int? { Int(s, radix: 16) }
		if tag.hasPrefix("col="), let v = hex(tag.dropFirst(4)) { colorOverride = UInt32(truncatingIfNeeded: v) }
		else if tag == "/col" { colorOverride = color }
		else if tag.hasPrefix("trans="), let v = Int(tag.dropFirst(6)) { alphaOverride = v }
		else if tag == "/trans" { alphaOverride = alpha }
		else if tag.hasPrefix("str="), let v = hex(tag.dropFirst(4)) { strikeColor = v }
		else if tag == "str" { strikeColor = 0x800000 }
		else if tag == "/str" { strikeColor = -1 }
		else if tag.hasPrefix("u="), let v = hex(tag.dropFirst(2)) { underlineColor = v }
		else if tag == "u" { underlineColor = 0 }
		else if tag == "/u" { underlineColor = -1 }
		else if tag.hasPrefix("shad="), let v = hex(tag.dropFirst(5)) { shadowOverride = v }
		else if tag == "shad" { shadowOverride = 0 }
		else if tag == "/shad" { shadowOverride = shadow }
		else if tag == "br" { setColors(color, shadow, alpha) }
	}

	private func render(_ s: [UInt8], _ startX: Int, _ y: Int, _ r: inout Raster) {
		var x = startX
		let top = y - lineHeight
		var tagStart = -1, prev = 0
		var i = 0
		while i < s.count {
			defer { i += 1 }
			var c = Int(s[i])
			if c == 60 { tagStart = i; continue }
			if c == 62 && tagStart != -1 {
				let tag = Cp1252.decode(s[(tagStart + 1)..<i])
				tagStart = -1
				if let e = BitmapFont.entity(tag) {
					c = e
				} else {
					if tag.hasPrefix("img=") {
						if let n = Int(tag.dropFirst(4)), n < nameIcons.count {
							let icon = nameIcons[n]
							r.draw(icon, x: x, y: top + lineHeight - icon.innerHeight, opacity: alphaOverride)
							x += icon.innerWidth
							prev = 0
						}
					} else {
						parseTag(tag)
					}
					continue
				}
			}
			guard tagStart == -1 else { continue }
			if let k = kerning, prev != 0 { x += Int(k[prev << 8 | c]) }
			if c == 32 {
				if spaceWidth > 0 {
					extraSpaceWidth += spaceWidth
					x += extraSpaceWidth >> 8
					extraSpaceWidth &= 0xFF
				}
			} else if c < glyphs.count {
				let g = glyphs[c]
				if shadowOverride != -1 {
					r.drawMask(g.indices, w: g.innerWidth, h: g.innerHeight, x: x + g.xOffset + 1, y: top + g.yOffset + 1, rgb: UInt32(truncatingIfNeeded: shadowOverride), opacity: alphaOverride)
				}
				r.drawMask(g.indices, w: g.innerWidth, h: g.innerHeight, x: x + g.xOffset, y: top + g.yOffset, rgb: colorOverride, opacity: alphaOverride)
			}
			let gw = glyphWidths[c]
			if strikeColor != -1 { r.hline(x, top + lineHeight * 7 / 10, gw, UInt32(strikeColor)) }
			if underlineColor != -1 { r.hline(x, top + lineHeight + 1, gw, UInt32(underlineColor)) }
			x += gw
			prev = c
		}
	}

	/// rt4 `splitParagraph`: word-wraps at spaces and after hyphens, and on `<br>`.
	func split(_ s: [UInt8], maxWidth: Int?) -> [[UInt8]] {
		var buf: [UInt8] = []
		var lines: [[UInt8]] = []
		var w = 0, lineStart = 0, breakAt = -1, widthAtBreak = 0, breakSkip = 0, tagStart = -1, prev = 0
		for i in 0..<s.count {
			var c = Int(s[i])
			if c == 60 { tagStart = i; continue }
			if c == 62 && tagStart != -1 {
				let tagBytes = Array(s[(tagStart + 1)..<i])
				let tag = Cp1252.decode(tagBytes)
				tagStart = -1
				buf.append(60); buf += tagBytes; buf.append(62)
				if tag == "br" {
					lines.append(Array(buf[lineStart..<buf.count]))
					lineStart = buf.count
					w = 0; breakAt = -1; prev = 0
				} else if let e = BitmapFont.entity(tag) {
					w += glyphWidths[e]
					if let k = kerning, prev != 0 { w += Int(k[prev << 8 | e]) }
					prev = e
				} else if tag.hasPrefix("img="), let n = Int(tag.dropFirst(4)), n < nameIcons.count {
					w += nameIcons[n].innerWidth
					prev = 0
				}
				c = 0
			}
			guard tagStart == -1 else { continue }
			if c != 0 {
				buf.append(UInt8(c))
				w += glyphWidths[c]
				if let k = kerning, prev != 0 { w += Int(k[prev << 8 | c]) }
				prev = c
			}
			if c == 32 { breakAt = buf.count; widthAtBreak = w; breakSkip = 1 }
			if let mw = maxWidth, w > mw, breakAt >= 0 {
				lines.append(Array(buf[lineStart..<(breakAt - breakSkip)]))
				lineStart = breakAt
				breakAt = -1
				w -= widthAtBreak
				prev = 0
			}
			if c == 45 { breakAt = buf.count; widthAtBreak = w; breakSkip = 0 }
		}
		if buf.count > lineStart { lines.append(Array(buf[lineStart...])) }
		return lines
	}

	/// rt4 `drawInterfaceText` / `renderParagraphAlpha`: wraps `text` into the
	/// box and aligns it. halign/valign: 0 left/top, 1 centre, 2 right/bottom,
	/// 3 justify/spread. Returns the line count.
	@discardableResult
	public func drawParagraph(_ text: String, x: Int, y: Int, w: Int, h: Int, color: UInt32, shadow: Int = -1, halign: Int = 0, valign: Int = 0, lineSpacing: Int = 0, opacity: Int = 256, into r: inout Raster) -> Int {
		setColors(color, shadow, opacity)
		let spacing = lineSpacing == 0 ? lineHeight : lineSpacing
		let tooSmall = h < paragraphTopPadding + paragraphBottomPadding + spacing && h < spacing * 2
		let lines = split(Cp1252.encode(text), maxWidth: tooSmall ? nil : w)
		var valign = valign
		if valign == 3 && lines.count == 1 { valign = 1 }
		var step = spacing
		var ly: Int
		switch valign {
		case 0: ly = y + paragraphTopPadding
		case 1: ly = y + paragraphTopPadding + (h - paragraphTopPadding - paragraphBottomPadding - (lines.count - 1) * spacing) / 2
		case 2: ly = y + h - paragraphBottomPadding - (lines.count - 1) * spacing
		default:
			let gap = max(0, (h - paragraphTopPadding - paragraphBottomPadding - (lines.count - 1) * spacing) / (lines.count + 1))
			ly = y + paragraphTopPadding + gap
			step += gap
		}
		for (n, line) in lines.enumerated() {
			switch halign {
			case 0: render(line, x, ly, &r)
			case 1: render(line, x + (w - width(line)) / 2, ly, &r)
			case 2: render(line, x + w - width(line), ly, &r)
			default:
				if n == lines.count - 1 {
					render(line, x, ly, &r)
				} else {
					justify(line, w)
					render(line, x, ly, &r)
					spaceWidth = 0
				}
			}
			ly += step
		}
		return lines.count
	}

	private func justify(_ s: [UInt8], _ w: Int) {
		var spaces = 0, inTag = false
		for c in s {
			if c == 60 { inTag = true } else if c == 62 { inTag = false } else if !inTag && c == 32 { spaces += 1 }
		}
		if spaces > 0 { spaceWidth = ((w - width(s)) << 8) / spaces }
	}
}
