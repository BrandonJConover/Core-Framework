import Foundation

/// java.util.Random (48-bit LCG) as used by rt4's procedural texture ops.
struct JavaRandom {
	private var seed: Int64
	init(seed s: Int) { seed = (Int64(s) ^ 0x5DEECE66D) & ((1 << 48) - 1) }
	mutating func next(_ bits: Int) -> Int32 {
		seed = (seed &* 0x5DEECE66D &+ 0xB) & ((1 << 48) - 1)
		return Int32(truncatingIfNeeded: seed >> Int64(48 - bits))
	}
	mutating func nextInt() -> Int32 { next(32) }

	/// rt4 `RandomUtils.nextInt(bound, random)`.
	mutating func nextInt(_ bound: Int) -> Int {
		guard bound > 0 else { return 0 }
		let b = Int32(truncatingIfNeeded: bound)
		if b == (0 &- b) & b {
			let r = Int64(UInt32(bitPattern: nextInt()))
			return Int((r * Int64(b)) >> 32)
		}
		let limit = Int32.min &- Int32(truncatingIfNeeded: Int64(0x1_0000_0000) % Int64(b))
		var v: Int32
		repeat { v = nextInt() } while limit <= v
		// rt4 RandomUtils.shuffle
		let mask = (b &- 1) & (v >> 31)
		let sign = Int32(bitPattern: UInt32(bitPattern: v) >> 31)
		return Int(mask &+ ((v &+ sign) % b))
	}
}

/// Per-generation state: rt4 keeps these as statics on `Texture`
/// (width/height/fractions/masks, the brightness table and the two providers).
final class TextureContext {
	var width = 0
	var height = 0
	var widthFractions: [Int] = []
	var heightFractions: [Int] = []
	var widthMask = 0
	var heightMask = 0
	/// rt4 `Texture.anInt4042`: 2048 at 64 wide, else 4096.
	var unit = 4096
	unowned let store: TextureStore
	init(store: TextureStore) { self.store = store }

	/// rt4 `Texture.setSize(height, width)`.
	func setSize(height h: Int, width w: Int) {
		widthFractions = (0..<w).map { ($0 << 12) / w }
		unit = w == 64 ? 2048 : 4096
		widthMask = w - 1
		width = w
		heightFractions = (0..<h).map { ($0 << 12) / h }
		height = h
		heightMask = h - 1
	}
}

/// Bounds-safe `ArrayUtils.fill(array, start, count, value)`.
@inline(__always) func texFill(_ a: inout [Int], _ start: Int, _ count: Int, _ v: Int) {
	var i = max(start, 0)
	let end = min(start + count, a.count)
	while i < end { a[i] = v; i += 1 }
}

/// Base of the procedural texture graph. Port of rt4 `TextureOp`.
///
/// Each op produces one image row at a time, either monochrome (one `[Int]`,
/// values 0...4096 as 12-bit fixed point) or colour (three `[Int]`: r,g,b).
/// rt4 keeps a bounded per-op row cache; ops are pure functions of the row, so
/// this port simply memoises every computed row for the duration of a build.
class TextureOp {
	var children: [TextureOp?]
	var monochrome: Bool
	/// rt4 `anInt5840`: row cache size (255 = full). Unused here.
	var cacheRows = 0
	var ctx: TextureContext!
	private var monoMemo: [[Int]?] = []
	private var colorMemo: [[[Int]]?] = []

	init(inputs: Int, monochrome: Bool) {
		children = [TextureOp?](repeating: nil, count: inputs)
		self.monochrome = monochrome
	}

	static let sine: [Int] = (0..<256).map { Int(sin(Double($0) / 255.0 * 6.283185307179586) * 4096.0) }
	static let cosine: [Int] = (0..<256).map { Int(cos(Double($0) / 255.0 * 6.283185307179586) * 4096.0) }

	// MARK: overridables

	func decode(_ opcode: Int, _ p: inout Packet) throws {}
	func postDecode() throws {}
	/// rt4 `method4631`: sprite group this op reads from archive 8, or -1.
	var spriteId: Int { -1 }
	/// rt4 `method4627`: other texture this op reads, or -1.
	var textureRef: Int { -1 }
	func computeMono(_ y: Int) -> [Int] { [Int](repeating: 0, count: ctx.width) }
	func computeColor(_ y: Int) -> [[Int]] { [[Int]](repeating: [Int](repeating: 0, count: ctx.width), count: 3) }
	func resetState() {}

	// MARK: memoised access

	final func prepare(_ c: TextureContext) {
		ctx = c
		monoMemo = [[Int]?](repeating: nil, count: c.height)
		colorMemo = [[[Int]]?](repeating: nil, count: c.height)
		resetState()
	}

	final func clear() {
		monoMemo = []
		colorMemo = []
		ctx = nil
		resetState()
	}

	/// rt4 `getMonochromeOutput(row)`.
	final func mono(_ y: Int) -> [Int] {
		if let m = monoMemo[y] { return m }
		let r = computeMono(y)
		monoMemo[y] = r
		return r
	}

	/// rt4 `getColorOutput(row)`.
	final func color(_ y: Int) -> [[Int]] {
		if let m = colorMemo[y] { return m }
		let r = computeColor(y)
		colorMemo[y] = r
		return r
	}

	/// rt4 `getChildMonochromeOutput(child, row)`.
	final func childMono(_ child: Int, _ y: Int) -> [Int] {
		guard let c = children[child] else { return [Int](repeating: 0, count: ctx.width) }
		return c.monochrome ? c.mono(y) : c.color(y)[0]
	}

	/// rt4 `getChildColorOutput(row, child)`.
	final func childColor(_ y: Int, _ child: Int) -> [[Int]] {
		guard let c = children[child] else { return [[Int]](repeating: [Int](repeating: 0, count: ctx.width), count: 3) }
		if c.monochrome { let m = c.mono(y); return [m, m, m] }
		return c.color(y)
	}

	final func zeros() -> [Int] { [Int](repeating: 0, count: ctx.width) }
	final func zeros3() -> [[Int]] { [zeros(), zeros(), zeros()] }
}

/// Smoothstep and lighting tables shared by the noise/bump ops
/// (rt4 `MonochromeImageCache` statics).
enum TextureTables {
	/// rt4 `aByteArray53`: 255 / sqrt((x*x + y*y + 65535) / 65535) over the lower triangle.
	static let normalise: [UInt8] = {
		var t = [UInt8](repeating: 0, count: 32896)
		var n = 0
		for i in 0..<256 {
			for j in 0...i {
				let f = Float(j * j + i * i + 65535) / 65535.0
				t[n] = UInt8(truncatingIfNeeded: Int(255.0 / Double(f).squareRoot()))
				n += 1
			}
		}
		return t
	}()
	/// rt4 `anIntArray1` / `method3211`: 6t^5 - 15t^4 + 10t^3 in 12-bit fixed point.
	static let smooth: [Int] = (0..<4096).map { x in
		let a = (x * ((x * x) >> 12)) >> 12
		let b = x * 6 - 61440
		let c = ((x * b) >> 12) + 40960
		return (a * c) >> 12
	}
}
