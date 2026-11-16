import Foundation

/// Port of the data side of rt4 `SoftwareModel` (client!w): a lit model ready
/// for the rasteriser. Only construction (lighting), simple transforms and
/// bounds are ported; projection/rasterisation (`render`, `setCamera`, ...)
/// belongs to the renderer.
///
/// Per-triangle colours follow rt4: `triangleColorA/B/C` hold HSL16 colours
/// (for textured faces, a lightness 2...126 instead). For Gouraud triangles
/// the lit values carry the lightness in bits 17+ above the HSL16 colour.
/// `triangleColorC == -1` means flat shading (use colour A only) and `-2`
/// means the triangle is hidden.
public final class SoftwareModel {
	public var vertexCount = 0
	public var triangleCount = 0
	public var vertexX: [Int] = []
	public var vertexY: [Int] = []
	public var vertexZ: [Int] = []
	public var triangleVertexA: [Int] = []
	public var triangleVertexB: [Int] = []
	public var triangleVertexC: [Int] = []
	/// rt4 `anIntArray533` / `anIntArray523` / `triangleInfo`(int[]).
	public var triangleColorA: [Int] = []
	public var triangleColorB: [Int] = []
	public var triangleColorC: [Int] = []
	public var triangleAlpha: [Int8]?
	public var trianglePriorities: [Int8]?
	public var priority: Int8 = 0
	/// rt4 `aShortArray92`: texture id per triangle or -1 (nil when untextured).
	public var triangleTextures: [Int]?
	/// rt4 `aByteArray74`: index into `textureFacesP/M/N` per triangle, -1 for none (nil when none).
	public var triangleTextureFace: [Int8]?
	public var textureFacesP: [Int] = []
	public var textureFacesM: [Int] = []
	public var textureFacesN: [Int] = []
	public var textureFaceCount = 0
	/// Original (unlit) triangle colours, kept as rt4 does.
	public var triangleColors: [Int16] = []
	/// Animation groups.
	public var boneVertices: [[Int]]?
	public var boneTriangles: [[Int]]?
	public var vertexSources: [Int16]?
	public var triangleSources: [Int16]?

	var boundsValid = false
	public private(set) var minX = 0, maxX = 0, minY = 0, maxY = 0, minZ = 0, maxZ = 0
	/// rt4 `lengthXZ` and `aShort35` (max radius incl. Y).
	public private(set) var lengthXZ = 0, radius = 0

	public init() {}

	/// rt4 `SoftwareModel(RawModel, ambient, contrast, x, y, z)`. Calls
	/// `calculateNormals()` and `createBones()` on the raw model like rt4.
	/// `textureAvailable` replaces `Rasteriser.textureProvider.method3236`.
	public init(_ model: RawModel, ambient: Int, contrast: Int, x lx: Int, y ly: Int, z lz: Int, textureAvailable: (Int) -> Bool = { _ in true }) {
		model.calculateNormals()
		model.createBones()
		vertexCount = model.vertexCount
		vertexX = model.vertexX; vertexY = model.vertexY; vertexZ = model.vertexZ
		triangleCount = model.triangleCount
		triangleVertexA = model.triangleVertexA; triangleVertexB = model.triangleVertexB; triangleVertexC = model.triangleVertexC
		trianglePriorities = model.trianglePriorities
		triangleAlpha = model.triangleAlpha
		priority = model.priority
		triangleColors = model.triangleColors
		boneVertices = model.boneVertices; boneTriangles = model.boneTriangles
		triangleSources = model.triangleSources; vertexSources = model.vertexSources

		let lightLen = Int(Double(lx * lx + ly * ly + lz * lz).squareRoot())
		var divisor = (contrast * lightLen) >> 8
		if divisor == 0 { divisor = 1 } // rt4 would throw ArithmeticException
		triangleColorA = [Int](repeating: 0, count: triangleCount)
		triangleColorB = triangleColorA
		triangleColorC = triangleColorA

		if let tex = model.triangleTextures {
			var t = [Int](repeating: -1, count: triangleCount)
			for i in 0..<triangleCount {
				let id = Int(tex[i])
				t[i] = (id != -1 && textureAvailable(id)) ? id : -1
			}
			triangleTextures = t
		}

		if model.texturedCount > 0, let tti = model.triangleTextureIndex, let types = model.textureTypes {
			var used = [Int](repeating: 0, count: model.texturedCount)
			for i in 0..<triangleCount where tti[i] != -1 { used[Int(tti[i]) & 0xFF] += 1 }
			var n = 0
			for j in 0..<model.texturedCount where used[j] > 0 && types[j] == 0 { n += 1 }
			textureFaceCount = n
			textureFacesP = [Int](repeating: 0, count: n)
			textureFacesM = textureFacesP; textureFacesN = textureFacesP
			var k = 0
			for j in 0..<model.texturedCount {
				if used[j] > 0 && types[j] == 0 {
					textureFacesP[k] = Int(model.textureFacesP![j]) & 0xFFFF
					textureFacesM[k] = Int(model.textureFacesM![j]) & 0xFFFF
					textureFacesN[k] = Int(model.textureFacesN![j]) & 0xFFFF
					used[j] = k
					k += 1
				} else {
					used[j] = -1
				}
			}
			var face = [Int8](repeating: 0, count: triangleCount)
			for j in 0..<triangleCount {
				if tti[j] == -1 {
					face[j] = -1
				} else {
					face[j] = Int8(truncatingIfNeeded: used[Int(tti[j]) & 0xFF])
					if face[j] == -1 && triangleTextures != nil { triangleTextures![j] = -1 }
				}
			}
			triangleTextureFace = face
		}

		func normal(_ v: Int) -> VertexNormal {
			if let m = model.mergedNormals, let n = m[v] { return n }
			return model.vertexNormals![v]
		}
		func intensity(_ n: VertexNormal) -> Int {
			let d = divisor * max(n.magnitude, 1)
			return (lx * n.x + ly * n.y + lz * n.z) / d
		}
		func shl17(_ v: Int) -> Int { Int(Int32(truncatingIfNeeded: v << 17)) }
		func mul(_ a: Int, _ b: Int) -> Int { // ColorUtils.multiplyLightness2
			let l = min(126, max(2, (b * (a & 0x7F)) >> 7))
			return (a & 0xFF80) + l
		}
		func clamp(_ v: Int) -> Int { min(126, max(2, v)) } // ColorUtils.method4582

		for i in 0..<triangleCount {
			var info = Int(model.triangleInfo?[i] ?? 0)
			let alpha = Int(model.triangleAlpha?[i] ?? 0)
			let tex = triangleTextures?[i] ?? -1
			if alpha == -2 { info = 3 }
			if alpha == -1 { info = 2 }
			let a = triangleVertexA[i], b = triangleVertexB[i], c = triangleVertexC[i]
			if tex == -1 {
				if info == 0 {
					let colour = Int(model.triangleColors[i]) & 0xFFFF
					var v = shl17(ambient + intensity(normal(a)))
					triangleColorA[i] = v | mul(colour, v >> 17)
					v = shl17(ambient + intensity(normal(b)))
					triangleColorB[i] = v | mul(colour, v >> 17)
					v = shl17(ambient + intensity(normal(c)))
					triangleColorC[i] = v | mul(colour, v >> 17)
				} else if info == 1 {
					let n = model.triangleNormals![i]!
					let v = shl17(ambient + (lx * n.x + ly * n.y + lz * n.z) / max(1, divisor + divisor / 2))
					triangleColorA[i] = v | mul(Int(model.triangleColors[i]) & 0xFFFF, v >> 17)
					triangleColorC[i] = -1
				} else if info == 3 {
					triangleColorA[i] = 128
					triangleColorC[i] = -1
				} else {
					triangleColorC[i] = -2
				}
			} else if info == 0 {
				triangleColorA[i] = clamp(ambient + intensity(normal(a)))
				triangleColorB[i] = clamp(ambient + intensity(normal(b)))
				triangleColorC[i] = clamp(ambient + intensity(normal(c)))
			} else if info == 1 {
				let n = model.triangleNormals![i]!
				triangleColorA[i] = clamp(ambient + (lx * n.x + ly * n.y + lz * n.z) / max(1, divisor + divisor / 2))
				triangleColorC[i] = -1
			} else {
				triangleColorC[i] = -2
			}
		}
	}

	// MARK: transforms

	public func rotateX(_ a: Int) {
		let s = MathTables.sin[a & 2047], c = MathTables.cos[a & 2047]
		for v in 0..<vertexCount {
			let t = (vertexY[v] * c - vertexZ[v] * s) >> 16
			vertexZ[v] = (vertexY[v] * s + vertexZ[v] * c) >> 16
			vertexY[v] = t
		}
		boundsValid = false
	}

	public func rotateY(_ a: Int) {
		let s = MathTables.sin[a & 2047], c = MathTables.cos[a & 2047]
		for v in 0..<vertexCount {
			let t = (vertexZ[v] * s + vertexX[v] * c) >> 16
			vertexZ[v] = (vertexZ[v] * c - vertexX[v] * s) >> 16
			vertexX[v] = t
		}
		boundsValid = false
	}

	public func rotateZ(_ a: Int) {
		let s = MathTables.sin[a & 2047], c = MathTables.cos[a & 2047]
		for v in 0..<vertexCount {
			let t = (vertexY[v] * s + vertexX[v] * c) >> 16
			vertexY[v] = (vertexY[v] * c - vertexX[v] * s) >> 16
			vertexX[v] = t
		}
		boundsValid = false
	}

	/// rt4 `rotateCounterClockwise`.
	public func rotateCounterClockwise() {
		for v in 0..<vertexCount { let t = vertexX[v]; vertexX[v] = vertexZ[v]; vertexZ[v] = -t }
		boundsValid = false
	}

	public func translate(_ x: Int, _ y: Int, _ z: Int) {
		for v in 0..<vertexCount { vertexX[v] += x; vertexY[v] += y; vertexZ[v] += z }
		boundsValid = false
	}

	/// 128 = 100%.
	public func resize(_ x: Int, _ y: Int, _ z: Int) {
		for v in 0..<vertexCount {
			vertexX[v] = vertexX[v] * x / 128
			vertexY[v] = vertexY[v] * y / 128
			vertexZ[v] = vertexZ[v] * z / 128
		}
		boundsValid = false
	}

	/// Deep copy (rt4 `copy`/`method4560` family, minus the shared scratch buffers).
	public func copy() -> SoftwareModel {
		let m = SoftwareModel()
		m.vertexCount = vertexCount; m.triangleCount = triangleCount
		m.vertexX = vertexX; m.vertexY = vertexY; m.vertexZ = vertexZ
		m.triangleVertexA = triangleVertexA; m.triangleVertexB = triangleVertexB; m.triangleVertexC = triangleVertexC
		m.triangleColorA = triangleColorA; m.triangleColorB = triangleColorB; m.triangleColorC = triangleColorC
		m.triangleAlpha = triangleAlpha; m.trianglePriorities = trianglePriorities; m.priority = priority
		m.triangleTextures = triangleTextures; m.triangleTextureFace = triangleTextureFace
		m.textureFacesP = textureFacesP; m.textureFacesM = textureFacesM; m.textureFacesN = textureFacesN
		m.textureFaceCount = textureFaceCount; m.triangleColors = triangleColors
		m.boneVertices = boneVertices; m.boneTriangles = boneTriangles
		m.vertexSources = vertexSources; m.triangleSources = triangleSources
		return m
	}

	// MARK: bounds

	/// rt4 `calculateBounds`.
	public func calculateBounds() {
		var mnX = 32767, mnY = 32767, mnZ = 32767, mxX = -32768, mxY = -32768, mxZ = -32768
		var lxz = 0, lr = 0
		for v in 0..<vertexCount {
			let x = vertexX[v], y = vertexY[v], z = vertexZ[v]
			mnX = min(mnX, x); mxX = max(mxX, x)
			mnY = min(mnY, y); mxY = max(mxY, y)
			mnZ = min(mnZ, z); mxZ = max(mxZ, z)
			var d = x * x + z * z
			if d > lxz { lxz = d }
			d += y * y
			if d > lr { lr = d }
		}
		func s(_ v: Int) -> Int { Int(Int16(truncatingIfNeeded: v)) }
		minX = s(mnX); maxX = s(mxX); minY = s(mnY); maxY = s(mxY); minZ = s(mnZ); maxZ = s(mxZ)
		lengthXZ = s(Int(Double(lxz).squareRoot() + 0.99))
		radius = s(Int(Double(lr).squareRoot() + 0.99))
		boundsValid = true
	}

	public func ensureBounds() { if !boundsValid { calculateBounds() } }
}
