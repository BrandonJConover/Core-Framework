import Foundation

/// rt4 `VertexNormal` (client!hd): accumulated face normals at a vertex.
public struct VertexNormal {
	public var x = 0, y = 0, z = 0, magnitude = 0
	public init() {}
}

/// rt4 `TriangleNormal` (client!qj): normal of a flat-shaded triangle.
public struct TriangleNormal {
	public var x = 0, y = 0, z = 0
	public init() {}
}

/// Port of rt4 `RawModel` (client!gb): an editable model as stored in cache
/// archive 7, before lighting. Field names follow what they do; the rt4
/// obfuscated name is given where it is not obvious.
///
/// Java `short`/`byte` arrays are kept as `Int16`/`Int8` so signed/unsigned
/// handling (`& 0xFFFF`, `& 0xFF`) matches the original.
public final class RawModel {
	public struct DecodeError: Error, CustomStringConvertible {
		public let description: String
	}

	public var vertexCount = 0
	public var triangleCount = 0
	public var texturedCount = 0
	public var priority: Int8 = 0

	public var vertexX: [Int] = []
	public var vertexY: [Int] = []
	public var vertexZ: [Int] = []
	public var triangleVertexA: [Int] = []
	public var triangleVertexB: [Int] = []
	public var triangleVertexC: [Int] = []

	public var triangleInfo: [Int8]?
	public var trianglePriorities: [Int8]?
	public var triangleAlpha: [Int8]?
	public var triangleColors: [Int16] = []
	public var triangleTextures: [Int16]?
	public var triangleTextureIndex: [Int8]?

	/// Per-vertex / per-triangle animation labels (`vertexBones` / `triangleBones`
	/// in rt4); `createBones()` turns them into the grouped arrays below.
	public var vertexBones: [Int]?
	public var triangleBones: [Int]?
	public var boneVertices: [[Int]]?
	public var boneTriangles: [[Int]]?

	public var textureTypes: [Int8]?
	public var textureFacesP: [Int16]?
	public var textureFacesM: [Int16]?
	public var textureFacesN: [Int16]?
	public var texturesScaleX: [Int16]?
	public var texturesScaleY: [Int16]?
	public var texturesScaleZ: [Int16]?
	public var textureRotationY: [Int8]?
	/// rt4 `aByteArray32` / `aByteArray34` / `aByteArray28` / `aByteArray33`: extra texture-space parameters.
	public var textureParamA: [Int8]?
	public var textureParamB: [Int8]?
	public var textureParamC: [Int8]?
	public var textureParamD: [Int8]?

	/// Bitmask of which merged source model owns each vertex/triangle (merge constructor).
	public var vertexSources: [Int16]?
	public var triangleSources: [Int16]?

	public var vertexNormals: [VertexNormal]?
	/// rt4 `aClass57Array2`: normals merged with neighbouring models.
	public var mergedNormals: [VertexNormal?]?
	public var triangleNormals: [TriangleNormal?]?

	/// rt4 `aShort19` / `aShort18`: ambient and contrast used by `createModel()`.
	public var lightAmbient = 0
	public var lightContrast = 0

	private var boundsValid = false
	private var minX = 0, maxX = 0, minY = 0, maxY = 0, minZ = 0, maxZ = 0

	private init() {}

	/// Empty model with room for editing (rt4 `RawModel(int,int,int)`).
	public init(vertexCapacity: Int, triangleCapacity: Int) {
		vertexX = [Int](repeating: 0, count: vertexCapacity)
		vertexY = vertexX; vertexZ = vertexX
		vertexBones = vertexX
		triangleVertexA = [Int](repeating: 0, count: triangleCapacity)
		triangleVertexB = triangleVertexA; triangleVertexC = triangleVertexA
		triangleInfo = [Int8](repeating: 0, count: triangleCapacity)
		trianglePriorities = triangleInfo; triangleAlpha = triangleInfo
		triangleColors = [Int16](repeating: 0, count: triangleCapacity)
		triangleTextures = triangleColors
		triangleTextureIndex = triangleInfo
		triangleBones = triangleVertexA
	}

	/// rt4 `RawModel(byte[])`: picks the new or the old header from the trailing 0xFF 0xFF.
	public convenience init(data src: [UInt8]) throws {
		self.init()
		guard src.count >= 18 else { throw DecodeError(description: "model too short: \(src.count)") }
		if src.count >= 23 && src[src.count - 1] == 0xFF && src[src.count - 2] == 0xFF {
			try decodeNew(src)
		} else {
			try decodeOld(src)
		}
	}

	// MARK: decoding

	private static func buffers(_ src: [UInt8], _ n: Int) -> [Packet] { [Packet](repeating: Packet(src), count: n) }

	private func checkCounts(_ v: Int, _ t: Int, _ end: Int, _ size: Int) throws {
		guard end <= size else { throw DecodeError(description: "model layout \(end) exceeds data \(size) (v=\(v) t=\(t))") }
	}

	/// rt4 `decodeNew`.
	private func decodeNew(_ src: [UInt8]) throws {
		var b = RawModel.buffers(src, 7)
		b[0].offset = src.count - 23
		let vertexCount = try b[0].g2()
		let triangleCount = try b[0].g2()
		let texturedCount = try b[0].g1()
		let hasInfo = try b[0].g1()
		let hasTriangleInfo = (hasInfo & 1) == 1
		let hasParticleEmitters = (hasInfo & 2) == 2
		let priority = try b[0].g1()
		let hasAlpha = try b[0].g1()
		let hasTriangleBones = try b[0].g1()
		let hasTextures = try b[0].g1()
		let hasVertexBones = try b[0].g1()
		let dxLen = try b[0].g2(), dyLen = try b[0].g2(), dzLen = try b[0].g2()
		let vertexIndexLen = try b[0].g2()
		let triangleTextureLen = try b[0].g2()

		var simple = 0, complex = 0, cube = 0
		if texturedCount > 0 {
			var types = [Int8](repeating: 0, count: texturedCount)
			b[0].offset = 0
			for i in 0..<texturedCount {
				let type = Int8(truncatingIfNeeded: try b[0].g1b())
				types[i] = type
				if type == 0 { simple += 1 } else if type >= 1 && type <= 3 { complex += 1 }
				if type == 2 { cube += 1 }
			}
			textureTypes = types
		}

		var offset = texturedCount + vertexCount
		let triangleInfoOff = offset
		if hasTriangleInfo { offset += triangleCount }
		let triangleTypeOff = offset
		offset += triangleCount
		let priorityOff = offset
		if priority == 255 { offset += triangleCount }
		let triangleBonesOff = offset
		if hasTriangleBones == 1 { offset += triangleCount }
		let vertexBonesOff = offset
		if hasVertexBones == 1 { offset += vertexCount }
		let alphaOff = offset
		if hasAlpha == 1 { offset += triangleCount }
		let vertexIndexOff = offset
		offset += vertexIndexLen
		let texturesOff = offset
		if hasTextures == 1 { offset += triangleCount * 2 }
		let textureIndexOff = offset
		offset += triangleTextureLen
		let colorOff = offset
		offset += triangleCount * 2
		let dxOff = offset; offset += dxLen
		let dyOff = offset; offset += dyLen
		let dzOff = offset; offset += dzLen
		let simplePmnOff = offset; offset += simple * 6
		let complexPmnOff = offset; offset += complex * 6
		let complexScaleOff = offset; offset += complex * 6
		let complexRotOff = offset; offset += complex
		let cube1Off = offset; offset += complex
		let cube2Off = offset; offset += complex + cube * 2
		try checkCounts(vertexCount, triangleCount, offset, src.count)

		self.vertexCount = vertexCount
		self.triangleCount = triangleCount
		self.texturedCount = texturedCount
		vertexX = [Int](repeating: 0, count: vertexCount)
		vertexY = vertexX; vertexZ = vertexX
		triangleVertexA = [Int](repeating: 0, count: triangleCount)
		triangleVertexB = triangleVertexA; triangleVertexC = triangleVertexA
		if hasVertexBones == 1 { vertexBones = [Int](repeating: 0, count: vertexCount) }
		if hasTriangleInfo { triangleInfo = [Int8](repeating: 0, count: triangleCount) }
		if priority == 255 { trianglePriorities = [Int8](repeating: 0, count: triangleCount) } else { self.priority = Int8(truncatingIfNeeded: priority) }
		if hasAlpha == 1 { triangleAlpha = [Int8](repeating: 0, count: triangleCount) }
		if hasTriangleBones == 1 { triangleBones = [Int](repeating: 0, count: triangleCount) }
		if hasTextures == 1 { triangleTextures = [Int16](repeating: 0, count: triangleCount) }
		if hasTextures == 1 && texturedCount > 0 { triangleTextureIndex = [Int8](repeating: 0, count: triangleCount) }
		triangleColors = [Int16](repeating: 0, count: triangleCount)
		if texturedCount > 0 {
			let z16 = [Int16](repeating: 0, count: texturedCount), z8 = [Int8](repeating: 0, count: texturedCount)
			textureFacesP = z16; textureFacesM = z16; textureFacesN = z16
			// rt4 sizes these by the complex/cube counts but indexes by texture; we size by texturedCount.
			if complex > 0 {
				texturesScaleX = z16; texturesScaleY = z16; texturesScaleZ = z16
				textureRotationY = z8; textureParamA = z8; textureParamB = z8
			}
			if cube > 0 { textureParamC = z8; textureParamD = z8 }
		}

		b[0].offset = texturedCount
		b[1].offset = dxOff; b[2].offset = dyOff; b[3].offset = dzOff; b[4].offset = vertexBonesOff
		var px = 0, py = 0, pz = 0
		for v in 0..<vertexCount {
			let flags = try b[0].g1()
			let dx = flags & 1 != 0 ? try b[1].gsmart() : 0
			let dy = flags & 2 != 0 ? try b[2].gsmart() : 0
			let dz = flags & 4 != 0 ? try b[3].gsmart() : 0
			px += dx; py += dy; pz += dz
			vertexX[v] = px; vertexY[v] = py; vertexZ[v] = pz
			if hasVertexBones == 1 { vertexBones![v] = try b[4].g1() }
		}

		b[0].offset = colorOff
		b[1].offset = triangleInfoOff; b[2].offset = priorityOff; b[3].offset = alphaOff
		b[4].offset = triangleBonesOff; b[5].offset = texturesOff; b[6].offset = textureIndexOff
		for t in 0..<triangleCount {
			triangleColors[t] = Int16(truncatingIfNeeded: try b[0].g2())
			if hasTriangleInfo { triangleInfo![t] = Int8(truncatingIfNeeded: try b[1].g1b()) }
			if priority == 255 { trianglePriorities![t] = Int8(truncatingIfNeeded: try b[2].g1b()) }
			if hasAlpha == 1 { triangleAlpha![t] = Int8(truncatingIfNeeded: try b[3].g1b()) }
			if hasTriangleBones == 1 { triangleBones![t] = try b[4].g1() }
			if hasTextures == 1 { triangleTextures![t] = Int16(truncatingIfNeeded: try b[5].g2() - 1) }
			if triangleTextureIndex != nil {
				if triangleTextures![t] == -1 {
					triangleTextureIndex![t] = -1
				} else {
					triangleTextureIndex![t] = Int8(truncatingIfNeeded: try b[6].g1() - 1)
				}
			}
		}

		try decodeTriangleIndices(b[0], b[1], vertexIndexOff, triangleTypeOff)

		b[0].offset = simplePmnOff; b[1].offset = complexPmnOff; b[2].offset = complexScaleOff
		b[3].offset = complexRotOff; b[4].offset = cube1Off; b[5].offset = cube2Off
		for t in 0..<texturedCount {
			let type = Int(textureTypes![t]) & 0xFF
			if type == 0 {
				textureFacesP![t] = Int16(truncatingIfNeeded: try b[0].g2())
				textureFacesM![t] = Int16(truncatingIfNeeded: try b[0].g2())
				textureFacesN![t] = Int16(truncatingIfNeeded: try b[0].g2())
			} else if type >= 1 && type <= 3 {
				textureFacesP![t] = Int16(truncatingIfNeeded: try b[1].g2())
				textureFacesM![t] = Int16(truncatingIfNeeded: try b[1].g2())
				textureFacesN![t] = Int16(truncatingIfNeeded: try b[1].g2())
				texturesScaleX![t] = Int16(truncatingIfNeeded: try b[2].g2())
				texturesScaleY![t] = Int16(truncatingIfNeeded: try b[2].g2())
				texturesScaleZ![t] = Int16(truncatingIfNeeded: try b[2].g2())
				textureRotationY![t] = Int8(truncatingIfNeeded: try b[3].g1b())
				textureParamA![t] = Int8(truncatingIfNeeded: try b[4].g1b())
				textureParamB![t] = Int8(truncatingIfNeeded: try b[5].g1b())
				if type == 2 {
					textureParamC![t] = Int8(truncatingIfNeeded: try b[5].g1b())
					textureParamD![t] = Int8(truncatingIfNeeded: try b[5].g1b())
				}
			}
		}
		// Particle emitter/effector tail (flag 2) is unused in rev 530; nothing to read.
		_ = hasParticleEmitters
	}

	/// Shared triangle-strip index decoder (types 1-4) from `decodeNew`/`decodeOld`.
	private func decodeTriangleIndices(_ idxIn: Packet, _ typesIn: Packet, _ indexOff: Int, _ typeOff: Int) throws {
		var idx = idxIn, types = typesIn
		idx.offset = indexOff
		types.offset = typeOff
		var a = 0, b = 0, c = 0, last = 0
		for t in 0..<triangleCount {
			let type = try types.g1()
			if type == 1 {
				a = try idx.gsmart() + last
				b = try idx.gsmart() + a
				c = try idx.gsmart() + b
				last = c
			} else if type == 2 {
				b = c
				c = try idx.gsmart() + last
				last = c
			} else if type == 3 {
				a = c
				c = try idx.gsmart() + last
				last = c
			} else if type == 4 {
				let b0 = a
				a = b
				b = b0
				c = try idx.gsmart() + last
				last = c
			} else { continue }
			triangleVertexA[t] = a; triangleVertexB[t] = b; triangleVertexC[t] = c
		}
	}

	/// rt4 `decodeOld`.
	private func decodeOld(_ src: [UInt8]) throws {
		var hasTriangleInfoFlag = false
		var hasTexturesFlag = false
		var b = RawModel.buffers(src, 5)
		b[0].offset = src.count - 18
		let vertexCount = try b[0].g2()
		let triangleCount = try b[0].g2()
		let texturedCount = try b[0].g1()
		let hasInfo = try b[0].g1()
		let hasPriorities = try b[0].g1()
		let hasAlpha = try b[0].g1()
		let hasTriangleBones = try b[0].g1()
		let hasVertexBones = try b[0].g1()
		let dxLen = try b[0].g2(), dyLen = try b[0].g2(), dzLen = try b[0].g2()
		let vertexIndexLen = try b[0].g2()

		var offset = vertexCount
		let triangleTypeOff = offset; offset += triangleCount
		let priorityOff = offset
		if hasPriorities == 255 { offset += triangleCount }
		let triangleBonesOff = offset
		if hasTriangleBones == 1 { offset += triangleCount }
		let triangleInfoOff = offset
		if hasInfo == 1 { offset += triangleCount }
		let vertexBonesOff = offset
		if hasVertexBones == 1 { offset += vertexCount }
		let alphaOff = offset
		if hasAlpha == 1 { offset += triangleCount }
		let vertexIndexOff = offset; offset += vertexIndexLen
		let colorOff = offset; offset += triangleCount * 2
		let pmnOff = offset; offset += texturedCount * 6
		let dxOff = offset; offset += dxLen
		let dyOff = offset; offset += dyLen
		let dzOff = offset; offset += dzLen
		try checkCounts(vertexCount, triangleCount, offset, src.count)

		self.vertexCount = vertexCount
		self.triangleCount = triangleCount
		self.texturedCount = texturedCount
		vertexX = [Int](repeating: 0, count: vertexCount)
		vertexY = vertexX; vertexZ = vertexX
		triangleVertexA = [Int](repeating: 0, count: triangleCount)
		triangleVertexB = triangleVertexA; triangleVertexC = triangleVertexA
		if texturedCount > 0 {
			textureTypes = [Int8](repeating: 0, count: texturedCount)
			textureFacesP = [Int16](repeating: 0, count: texturedCount)
			textureFacesM = textureFacesP; textureFacesN = textureFacesP
		}
		if hasVertexBones == 1 { vertexBones = [Int](repeating: 0, count: vertexCount) }
		if hasInfo == 1 {
			triangleInfo = [Int8](repeating: 0, count: triangleCount)
			triangleTextureIndex = [Int8](repeating: 0, count: triangleCount)
			triangleTextures = [Int16](repeating: 0, count: triangleCount)
		}
		if hasPriorities == 255 { trianglePriorities = [Int8](repeating: 0, count: triangleCount) } else { priority = Int8(truncatingIfNeeded: hasPriorities) }
		if hasAlpha == 1 { triangleAlpha = [Int8](repeating: 0, count: triangleCount) }
		if hasTriangleBones == 1 { triangleBones = [Int](repeating: 0, count: triangleCount) }
		triangleColors = [Int16](repeating: 0, count: triangleCount)

		b[0].offset = 0
		b[1].offset = dxOff; b[2].offset = dyOff; b[3].offset = dzOff; b[4].offset = vertexBonesOff
		var px = 0, py = 0, pz = 0
		for v in 0..<vertexCount {
			let flags = try b[0].g1()
			let dx = flags & 1 != 0 ? try b[1].gsmart() : 0
			let dy = flags & 2 != 0 ? try b[2].gsmart() : 0
			let dz = flags & 4 != 0 ? try b[3].gsmart() : 0
			px += dx; py += dy; pz += dz
			vertexX[v] = px; vertexY[v] = py; vertexZ[v] = pz
			if hasVertexBones == 1 { vertexBones![v] = try b[4].g1() }
		}

		b[0].offset = colorOff
		b[1].offset = triangleInfoOff; b[2].offset = priorityOff; b[3].offset = alphaOff; b[4].offset = triangleBonesOff
		for t in 0..<triangleCount {
			triangleColors[t] = Int16(truncatingIfNeeded: try b[0].g2())
			if hasInfo == 1 {
				let flags = try b[1].g1()
				if flags & 1 == 1 {
					triangleInfo![t] = 1
					hasTriangleInfoFlag = true
				} else {
					triangleInfo![t] = 0
				}
				if flags & 2 == 2 {
					triangleTextureIndex![t] = Int8(truncatingIfNeeded: flags >> 2)
					triangleTextures![t] = triangleColors[t]
					triangleColors[t] = 127
					if triangleTextures![t] != -1 { hasTexturesFlag = true }
				} else {
					triangleTextureIndex![t] = -1
					triangleTextures![t] = -1
				}
			}
			if hasPriorities == 255 { trianglePriorities![t] = Int8(truncatingIfNeeded: try b[2].g1b()) }
			if hasAlpha == 1 { triangleAlpha![t] = Int8(truncatingIfNeeded: try b[3].g1b()) }
			if hasTriangleBones == 1 { triangleBones![t] = try b[4].g1() }
		}

		try decodeTriangleIndices(b[0], b[1], vertexIndexOff, triangleTypeOff)

		b[0].offset = pmnOff
		for t in 0..<texturedCount {
			textureTypes![t] = 0
			textureFacesP![t] = Int16(truncatingIfNeeded: try b[0].g2())
			textureFacesM![t] = Int16(truncatingIfNeeded: try b[0].g2())
			textureFacesN![t] = Int16(truncatingIfNeeded: try b[0].g2())
		}
		if triangleTextureIndex != nil {
			var hasFaceTextures = false
			for i in 0..<triangleCount {
				let index = Int(triangleTextureIndex![i]) & 0xFF
				if index != 255 {
					guard index < texturedCount else { throw DecodeError(description: "texture index \(index) >= \(texturedCount)") }
					if Int(textureFacesP![index]) & 0xFFFF == triangleVertexA[i]
						&& Int(textureFacesM![index]) & 0xFFFF == triangleVertexB[i]
						&& Int(textureFacesN![index]) & 0xFFFF == triangleVertexC[i] {
						triangleTextureIndex![i] = -1
					} else {
						hasFaceTextures = true
					}
				}
			}
			if !hasFaceTextures { triangleTextureIndex = nil }
		}
		if !hasTexturesFlag { triangleTextures = nil }
		if !hasTriangleInfoFlag { triangleInfo = nil }
	}

	// MARK: merging

	/// rt4 `RawModel(RawModel[], int)`: concatenates models (player/NPC kits),
	/// welding vertices that share a position.
	public convenience init(merging models: [RawModel?], count: Int? = nil) {
		self.init()
		let count = min(count ?? models.count, models.count)
		var keepInfo = false, keepPriorities = false, keepAlpha = false
		var keepBones = false, keepTextures = false, keepTextureIndex = false
		vertexCount = 0; triangleCount = 0; texturedCount = 0
		priority = -1
		for i in 0..<count {
			guard let m = models[i] else { continue }
			vertexCount += m.vertexCount
			triangleCount += m.triangleCount
			texturedCount += m.texturedCount
			if m.trianglePriorities == nil {
				if priority == -1 { priority = m.priority }
				if priority != m.priority { keepPriorities = true }
			} else {
				keepPriorities = true
			}
			keepInfo = keepInfo || m.triangleInfo != nil
			keepAlpha = keepAlpha || m.triangleAlpha != nil
			keepBones = keepBones || m.triangleBones != nil
			keepTextures = keepTextures || m.triangleTextures != nil
			keepTextureIndex = keepTextureIndex || m.triangleTextureIndex != nil
		}
		vertexX = [Int](repeating: 0, count: vertexCount)
		vertexY = vertexX; vertexZ = vertexX
		vertexBones = vertexX
		vertexSources = [Int16](repeating: 0, count: vertexCount)
		triangleVertexA = [Int](repeating: 0, count: triangleCount)
		triangleVertexB = triangleVertexA; triangleVertexC = triangleVertexA
		if keepInfo { triangleInfo = [Int8](repeating: 0, count: triangleCount) }
		if keepPriorities { trianglePriorities = [Int8](repeating: 0, count: triangleCount) }
		if keepAlpha { triangleAlpha = [Int8](repeating: 0, count: triangleCount) }
		if keepBones { triangleBones = [Int](repeating: 0, count: triangleCount) }
		if keepTextures { triangleTextures = [Int16](repeating: 0, count: triangleCount) }
		if keepTextureIndex { triangleTextureIndex = [Int8](repeating: 0, count: triangleCount) }
		triangleColors = [Int16](repeating: 0, count: triangleCount)
		triangleSources = [Int16](repeating: 0, count: triangleCount)
		if texturedCount > 0 {
			let z16 = [Int16](repeating: 0, count: texturedCount), z8 = [Int8](repeating: 0, count: texturedCount)
			textureTypes = z8
			textureFacesP = z16; textureFacesM = z16; textureFacesN = z16
			texturesScaleX = z16; texturesScaleY = z16; texturesScaleZ = z16
			textureRotationY = z8; textureParamA = z8; textureParamB = z8; textureParamC = z8; textureParamD = z8
		}
		vertexCount = 0; triangleCount = 0; texturedCount = 0
		for i in 0..<count {
			let source = Int16(truncatingIfNeeded: 1 << i)
			guard let other = models[i] else { continue }
			for t in 0..<other.triangleCount {
				let n = triangleCount
				if keepInfo, let oi = other.triangleInfo { triangleInfo![n] = oi[t] }
				if keepPriorities { trianglePriorities![n] = other.trianglePriorities?[t] ?? other.priority }
				if keepAlpha, let oa = other.triangleAlpha { triangleAlpha![n] = oa[t] }
				if keepBones, let ob = other.triangleBones { triangleBones![n] = ob[t] }
				if keepTextures { triangleTextures![n] = other.triangleTextures?[t] ?? -1 }
				if keepTextureIndex {
					if let oti = other.triangleTextureIndex, oti[t] != -1 {
						triangleTextureIndex![n] = Int8(truncatingIfNeeded: Int(oti[t]) + texturedCount)
					} else {
						triangleTextureIndex![n] = -1
					}
				}
				triangleColors[n] = other.triangleColors[t]
				triangleSources![n] = source
				triangleVertexA[n] = addVertex(other, other.triangleVertexA[t], source)
				triangleVertexB[n] = addVertex(other, other.triangleVertexB[t], source)
				triangleVertexC[n] = addVertex(other, other.triangleVertexC[t], source)
				triangleCount += 1
			}
			for t in 0..<other.texturedCount {
				let n = texturedCount
				let type = other.textureTypes![t]
				textureTypes![n] = type
				if type == 0 {
					textureFacesP![n] = Int16(truncatingIfNeeded: addVertex(other, Int(other.textureFacesP![t]) & 0xFFFF, source))
					textureFacesM![n] = Int16(truncatingIfNeeded: addVertex(other, Int(other.textureFacesM![t]) & 0xFFFF, source))
					textureFacesN![n] = Int16(truncatingIfNeeded: addVertex(other, Int(other.textureFacesN![t]) & 0xFFFF, source))
				} else if type >= 1 && type <= 3 {
					textureFacesP![n] = other.textureFacesP![t]
					textureFacesM![n] = other.textureFacesM![t]
					textureFacesN![n] = other.textureFacesN![t]
					texturesScaleX![n] = other.texturesScaleX![t]
					texturesScaleY![n] = other.texturesScaleY![t]
					texturesScaleZ![n] = other.texturesScaleZ![t]
					textureRotationY![n] = other.textureRotationY![t]
					textureParamA![n] = other.textureParamA![t]
					textureParamB![n] = other.textureParamB![t]
					// rt4 tests `type == 2` in an unreachable else-branch; the cube params are copied here instead.
					if type == 2, let c = other.textureParamC, let d = other.textureParamD {
						textureParamC![n] = c[t]; textureParamD![n] = d[t]
					}
				}
				texturedCount += 1
			}
		}
	}

	/// rt4 `addVertex(RawModel, int, short)`: finds or appends a vertex by position.
	private func addVertex(_ m: RawModel, _ vertex: Int, _ source: Int16) -> Int {
		let x = m.vertexX[vertex], y = m.vertexY[vertex], z = m.vertexZ[vertex]
		for i in 0..<vertexCount where x == vertexX[i] && y == vertexY[i] && z == vertexZ[i] {
			vertexSources![i] |= source
			return i
		}
		vertexX[vertexCount] = x; vertexY[vertexCount] = y; vertexZ[vertexCount] = z
		vertexSources![vertexCount] = source
		if let vb = m.vertexBones { vertexBones![vertexCount] = vb[vertex] }
		vertexCount += 1
		return vertexCount - 1
	}

	/// rt4 copy constructor / `method1675`: deep copy (arrays are values in Swift).
	public func copy() -> RawModel {
		let m = RawModel()
		m.vertexCount = vertexCount; m.triangleCount = triangleCount; m.texturedCount = texturedCount
		m.priority = priority
		m.vertexX = vertexX; m.vertexY = vertexY; m.vertexZ = vertexZ
		m.triangleVertexA = triangleVertexA; m.triangleVertexB = triangleVertexB; m.triangleVertexC = triangleVertexC
		m.triangleInfo = triangleInfo; m.trianglePriorities = trianglePriorities; m.triangleAlpha = triangleAlpha
		m.triangleColors = triangleColors; m.triangleTextures = triangleTextures; m.triangleTextureIndex = triangleTextureIndex
		m.vertexBones = vertexBones; m.triangleBones = triangleBones; m.boneVertices = boneVertices; m.boneTriangles = boneTriangles
		m.textureTypes = textureTypes; m.textureFacesP = textureFacesP; m.textureFacesM = textureFacesM; m.textureFacesN = textureFacesN
		m.texturesScaleX = texturesScaleX; m.texturesScaleY = texturesScaleY; m.texturesScaleZ = texturesScaleZ
		m.textureRotationY = textureRotationY
		m.textureParamA = textureParamA; m.textureParamB = textureParamB; m.textureParamC = textureParamC; m.textureParamD = textureParamD
		m.vertexSources = vertexSources; m.triangleSources = triangleSources
		m.vertexNormals = vertexNormals; m.mergedNormals = mergedNormals; m.triangleNormals = triangleNormals
		m.lightAmbient = lightAmbient; m.lightContrast = lightContrast
		return m
	}

	// MARK: editing

	private func invalidate() {
		vertexNormals = nil
		mergedNormals = nil
		triangleNormals = nil
		boundsValid = false
	}

	/// rt4 `recolor(short, short)`.
	public func recolor(_ src: Int, _ dest: Int) {
		let s = Int16(truncatingIfNeeded: src), d = Int16(truncatingIfNeeded: dest)
		for i in 0..<triangleCount where triangleColors[i] == s { triangleColors[i] = d }
	}

	/// rt4 `retexture(short, short)`.
	public func retexture(_ src: Int, _ dest: Int) {
		guard triangleTextures != nil else { return }
		let s = Int16(truncatingIfNeeded: src), d = Int16(truncatingIfNeeded: dest)
		for i in 0..<triangleCount where triangleTextures![i] == s { triangleTextures![i] = d }
	}

	/// rt4 `translate`.
	public func translate(_ x: Int, _ y: Int, _ z: Int) {
		for v in 0..<vertexCount { vertexX[v] += x; vertexY[v] += y; vertexZ[v] += z }
		invalidate()
	}

	/// rt4 `resize` (128 = 100%).
	public func resize(_ x: Int, _ y: Int, _ z: Int) {
		for v in 0..<vertexCount {
			vertexX[v] = vertexX[v] * x / 128
			vertexY[v] = vertexY[v] * y / 128
			vertexZ[v] = vertexZ[v] * z / 128
		}
		invalidate()
	}

	/// rt4 `negateXz`: rotate 180 degrees about Y.
	public func rotateY180() {
		for v in 0..<vertexCount { vertexX[v] = -vertexX[v]; vertexZ[v] = -vertexZ[v] }
		invalidate()
	}

	/// rt4 `swapXz`: quarter turn about Y (x = z, z = -x).
	public func rotateY90() {
		for v in 0..<vertexCount { let t = vertexX[v]; vertexX[v] = vertexZ[v]; vertexZ[v] = -t }
		invalidate()
	}

	/// rt4 `method1689`: the opposite quarter turn about Y (x = -z, z = x).
	public func rotateY270() {
		for v in 0..<vertexCount { let t = vertexZ[v]; vertexZ[v] = vertexX[v]; vertexX[v] = -t }
		invalidate()
	}

	/// rt4 `method1682`: rotate about Y by 256 units (45 degrees).
	public func rotateY45() {
		let sin = MathTables.sin[256], cos = MathTables.cos[256]
		for i in 0..<vertexCount {
			let t = (vertexZ[i] * sin + vertexX[i] * cos) >> 16
			vertexZ[i] = (vertexZ[i] * cos - vertexX[i] * sin) >> 16
			vertexX[i] = t
		}
		invalidate()
	}

	/// rt4 private `rotate(int)`: angle (0..2047) about the Z axis.
	public func rotateZ(_ theta: Int) {
		let sin = MathTables.sin[theta & 2047], cos = MathTables.cos[theta & 2047]
		for v in 0..<vertexCount {
			let t = (vertexY[v] * sin + vertexX[v] * cos) >> 16
			vertexY[v] = (vertexY[v] * cos - vertexX[v] * sin) >> 16
			vertexX[v] = t
		}
		invalidate()
	}

	/// rt4 `method1677`: angle about the X axis.
	public func rotateX(_ theta: Int) {
		let sin = MathTables.sin[theta & 2047], cos = MathTables.cos[theta & 2047]
		for v in 0..<vertexCount {
			let t = (vertexY[v] * cos - vertexZ[v] * sin) >> 16
			vertexZ[v] = (vertexY[v] * sin + vertexZ[v] * cos) >> 16
			vertexY[v] = t
		}
		invalidate()
	}

	/// Rotate about Y by an arbitrary angle (rt4 inlined this in `method1684`).
	public func rotateY(_ theta: Int) {
		let sin = MathTables.sin[theta & 2047], cos = MathTables.cos[theta & 2047]
		for v in 0..<vertexCount {
			let t = (vertexZ[v] * sin + vertexX[v] * cos) >> 16
			vertexZ[v] = (vertexZ[v] * cos - vertexX[v] * sin) >> 16
			vertexX[v] = t
		}
		invalidate()
	}

	/// rt4 `method1684(x, y, z)`: Z, then X, then Y rotation (each skipped when 0).
	/// Unlike the other rotations this does not drop cached normals, as in rt4.
	public func rotateAngles(x: Int, y: Int, z: Int) {
		if z != 0 {
			let sin = MathTables.sin[z], cos = MathTables.cos[z]
			for i in 0..<vertexCount {
				let t = (vertexY[i] * sin + vertexX[i] * cos) >> 16
				vertexY[i] = (vertexY[i] * cos - vertexX[i] * sin) >> 16
				vertexX[i] = t
			}
		}
		if x != 0 {
			let sin = MathTables.sin[x], cos = MathTables.cos[x]
			for i in 0..<vertexCount {
				let t = (vertexY[i] * cos - vertexZ[i] * sin) >> 16
				vertexZ[i] = (vertexY[i] * sin + vertexZ[i] * cos) >> 16
				vertexY[i] = t
			}
		}
		if y != 0 {
			let sin = MathTables.sin[y], cos = MathTables.cos[y]
			for i in 0..<vertexCount {
				let t = (vertexZ[i] * sin + vertexX[i] * cos) >> 16
				vertexZ[i] = (vertexZ[i] * cos - vertexX[i] * sin) >> 16
				vertexX[i] = t
			}
		}
	}

	/// rt4 `method1673`: mirror along Z and flip winding.
	public func mirrorZ() {
		for v in 0..<vertexCount { vertexZ[v] = -vertexZ[v] }
		for t in 0..<triangleCount { let a = triangleVertexA[t]; triangleVertexA[t] = triangleVertexC[t]; triangleVertexC[t] = a }
		invalidate()
	}

	/// rt4 `addTriangle`: appends into pre-sized (editing) arrays.
	@discardableResult
	public func addTriangle(_ a: Int, _ b: Int, _ c: Int, color: Int, alpha: Int) -> Int {
		let n = triangleCount
		triangleVertexA[n] = a; triangleVertexB[n] = b; triangleVertexC[n] = c
		triangleInfo![n] = 1
		triangleTextureIndex![n] = -1
		triangleColors[n] = Int16(truncatingIfNeeded: color)
		triangleTextures![n] = -1
		triangleAlpha![n] = Int8(truncatingIfNeeded: alpha)
		triangleCount += 1
		return n
	}

	/// rt4 `method1685`: index of the vertex at (x, 0, z), appending if absent.
	@discardableResult
	public func addGroundVertex(_ x: Int, _ z: Int) -> Int {
		for i in 0..<vertexCount where vertexX[i] == x && vertexY[i] == 0 && vertexZ[i] == z { return i }
		vertexX[vertexCount] = x; vertexY[vertexCount] = 0; vertexZ[vertexCount] = z
		vertexCount += 1
		return vertexCount - 1
	}

	/// rt4 `resetBones`.
	public func resetBones() {
		vertexBones = nil; triangleBones = nil; boneVertices = nil; boneTriangles = nil
	}

	/// rt4 `createBones`: groups vertices/triangles by label for animation.
	public func createBones() {
		if let vb = vertexBones {
			var lens = [Int](repeating: 0, count: 256)
			var maxBone = 0
			for i in 0..<vertexCount { let b = vb[i] & 0xFF; lens[b] += 1; maxBone = max(maxBone, b) }
			var groups = (0...maxBone).map { [Int](repeating: 0, count: lens[$0]) }
			var fill = [Int](repeating: 0, count: 256)
			for i in 0..<vertexCount { let b = vb[i] & 0xFF; groups[b][fill[b]] = i; fill[b] += 1 }
			boneVertices = groups
			vertexBones = nil
		}
		guard let tb = triangleBones else { return }
		var lens = [Int](repeating: 0, count: 256)
		var maxBone = 0
		for i in 0..<triangleCount { let b = tb[i] & 0xFF; lens[b] += 1; maxBone = max(maxBone, b) }
		var groups = (0...maxBone).map { [Int](repeating: 0, count: lens[$0]) }
		var fill = [Int](repeating: 0, count: 256)
		for i in 0..<triangleCount { let b = tb[i] & 0xFF; groups[b][fill[b]] = i; fill[b] += 1 }
		boneTriangles = groups
		triangleBones = nil
	}

	// MARK: bounds

	/// rt4 `calculateBounds` (values truncated to Java `short`).
	private func calculateBounds() {
		if boundsValid { return }
		boundsValid = true
		var mnX = 32767, mnY = 32767, mnZ = 32767, mxX = -32768, mxY = -32768, mxZ = -32768
		for v in 0..<vertexCount {
			mnX = min(mnX, vertexX[v]); mxX = max(mxX, vertexX[v])
			mnY = min(mnY, vertexY[v]); mxY = max(mxY, vertexY[v])
			mnZ = min(mnZ, vertexZ[v]); mxZ = max(mxZ, vertexZ[v])
		}
		func s(_ v: Int) -> Int { Int(Int16(truncatingIfNeeded: v)) }
		minX = s(mnX); maxX = s(mxX); minY = s(mnY); maxY = s(mxY); minZ = s(mnZ); maxZ = s(mxZ)
	}

	public var bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int, minZ: Int, maxZ: Int) {
		calculateBounds()
		return (minX, maxX, minY, maxY, minZ, maxZ)
	}

	/// rt4 `getMinY`.
	public func getMinY() -> Int { calculateBounds(); return minY }

	// MARK: normals

	/// rt4 `calculateNormals`: accumulates per-vertex normals (info 0) and per-face normals (info 1).
	public func calculateNormals() {
		if vertexNormals != nil { return }
		var normals = [VertexNormal](repeating: VertexNormal(), count: vertexCount)
		var faceNormals = [TriangleNormal?](repeating: nil, count: 0)
		var haveFaceNormals = false
		for t in 0..<triangleCount {
			let a = triangleVertexA[t], b = triangleVertexB[t], c = triangleVertexC[t]
			let bx = vertexX[b] - vertexX[a], by = vertexY[b] - vertexY[a], bz = vertexZ[b] - vertexZ[a]
			let cx = vertexX[c] - vertexX[a], cy = vertexY[c] - vertexY[a], cz = vertexZ[c] - vertexZ[a]
			var nx = by * cz - cy * bz
			var ny = bz * cx - cz * bx
			var nz = bx * cy - cx * by
			while nx > 8192 || ny > 8192 || nz > 8192 || nx < -8192 || ny < -8192 || nz < -8192 {
				nx >>= 1; ny >>= 1; nz >>= 1
			}
			var len = Int(Double(nx * nx + ny * ny + nz * nz).squareRoot())
			if len <= 0 { len = 1 }
			nx = nx * 256 / len
			ny = ny * 256 / len
			nz = nz * 256 / len
			let info = triangleInfo?[t] ?? 0
			if info == 0 {
				for v in [a, b, c] {
					normals[v].x += nx; normals[v].y += ny; normals[v].z += nz; normals[v].magnitude += 1
				}
			} else if info == 1 {
				if !haveFaceNormals { faceNormals = [TriangleNormal?](repeating: nil, count: triangleCount); haveFaceNormals = true }
				var n = TriangleNormal()
				n.x = nx; n.y = ny; n.z = nz
				faceNormals[t] = n
			}
		}
		vertexNormals = normals
		if haveFaceNormals { triangleNormals = faceNormals }
	}

	/// rt4 `method4544`: welds the lighting normals of coincident vertices
	/// between two models placed next to each other (`dx/dy/dz` = offset of
	/// `other` relative to self). With `flatten`, triangles whose three vertices
	/// all touched are marked info 2 (hidden-face smoothing for scenery).
	public func mergeNormals(with other: RawModel, dx: Int, dy: Int, dz: Int, flatten: Bool) {
		other.calculateBounds()
		other.calculateNormals()
		calculateNormals()
		var touchedSelf = [Bool](repeating: false, count: vertexCount)
		var touchedOther = [Bool](repeating: false, count: other.vertexCount)
		var matches = 0
		for i in 0..<vertexCount {
			guard let n = vertexNormals?[i], n.magnitude != 0 else { continue }
			let y = vertexY[i] - dy
			guard y >= other.minY && y <= other.maxY else { continue }
			let x = vertexX[i] - dx
			guard x >= other.minX && x <= other.maxX else { continue }
			let z = vertexZ[i] - dz
			guard z >= other.minZ && z <= other.maxZ else { continue }
			for j in 0..<other.vertexCount {
				let on = other.vertexNormals![j]
				guard x == other.vertexX[j], z == other.vertexZ[j], y == other.vertexY[j], on.magnitude != 0 else { continue }
				if mergedNormals == nil { mergedNormals = [VertexNormal?](repeating: nil, count: vertexCount) }
				if other.mergedNormals == nil { other.mergedNormals = [VertexNormal?](repeating: nil, count: other.vertexCount) }
				var a = mergedNormals![i] ?? n
				var b = other.mergedNormals![j] ?? on
				a.x += on.x; a.y += on.y; a.z += on.z; a.magnitude += on.magnitude
				b.x += n.x; b.y += n.y; b.z += n.z; b.magnitude += n.magnitude
				mergedNormals![i] = a
				other.mergedNormals![j] = b
				matches += 1
				touchedSelf[i] = true
				touchedOther[j] = true
			}
		}
		guard matches >= 3, flatten else { return }
		for t in 0..<triangleCount where touchedSelf[triangleVertexA[t]] && touchedSelf[triangleVertexB[t]] && touchedSelf[triangleVertexC[t]] {
			if triangleInfo == nil { triangleInfo = [Int8](repeating: 0, count: triangleCount) }
			triangleInfo![t] = 2
		}
		for t in 0..<other.triangleCount where touchedOther[other.triangleVertexA[t]] && touchedOther[other.triangleVertexB[t]] && touchedOther[other.triangleVertexC[t]] {
			if other.triangleInfo == nil { other.triangleInfo = [Int8](repeating: 0, count: other.triangleCount) }
			other.triangleInfo![t] = 2
		}
	}

	// MARK: terrain fitting

	/// rt4 static `method1680`: bilinear height at a world coordinate (0 outside the grid).
	public static func heightAt(_ h: [[Int]], _ x: Int, _ z: Int) -> Int {
		let tx = x >> 7, tz = z >> 7
		if tx < 0 || tz < 0 || tx >= h.count || tz >= h[0].count { return 0 }
		let fx = x & 0x7F, fz = z & 0x7F
		let a = (h[tx][tz] * (128 - fx) + h[tx + 1][tz] * fx) >> 7
		let b = (h[tx][tz + 1] * (128 - fx) + h[tx + 1][tz + 1] * fx) >> 7
		return (a * (128 - fz) + b * fz) >> 7
	}

	/// rt4 `method1667`: tilt a model to lie on a terrain patch (orientation 3).
	private func tiltToTerrain(_ h: [[Int]], _ x: Int, _ baseY: Int, _ z: Int, _ w: Int, _ d: Int) {
		let h00 = RawModel.heightAt(h, x - w / 2, z - d / 2)
		let h10 = RawModel.heightAt(h, x + w / 2, z - d / 2)
		let h01 = RawModel.heightAt(h, x - w / 2, z + d / 2)
		let h11 = RawModel.heightAt(h, x + w / 2, z + d / 2)
		let minA = min(h00, h10), minB = min(h01, h11)
		let minC = min(h10, h11), minD = min(h00, h01)
		if d != 0 {
			let a = Int(atan2(Double(minA - minB), Double(d)) * 325.95) & 0x7FF
			if a != 0 { rotateX(a) }
		}
		if w != 0 {
			let a = Int(atan2(Double(minD - minC), Double(w)) * 325.95) & 0x7FF
			if a != 0 { rotateZ(a) }
		}
		var m = h00 + h11
		if h10 + h01 < m { m = h10 + h01 }
		m = (m >> 1) - baseY
		if m != 0 { translate(0, m, 0) }
	}

	/// rt4 `method1670`: fits the model to the terrain heights. `orientation`:
	/// 1 = per-vertex drape, 2 = drape below a height fraction, 3 = tilt as a
	/// whole, 4/5 = use the secondary (bridge) height grid. Returns `self`
	/// when no adjustment is needed or the model is out of the grid.
	public func fitToTerrain(orientation: Int, arg1: Int, heights: [[Int]], upper: [[Int]]?, x: Int, baseY: Int, z: Int) -> RawModel {
		calculateBounds()
		var lo = x + minX, hi = x + maxX, zlo = z + minZ, zhi = z + maxZ
		if [1, 2, 3, 5].contains(orientation) && (lo < 0 || ((hi + 128) >> 7) >= heights.count || zlo < 0 || ((zhi + 128) >> 7) >= heights[0].count) { return self }
		if orientation == 4 || orientation == 5 {
			guard let up = upper else { return self }
			if lo < 0 || ((hi + 128) >> 7) >= up.count || zlo < 0 || ((zhi + 128) >> 7) >= up[0].count { return self }
		} else {
			lo >>= 7; hi = (hi + 127) >> 7; zlo >>= 7; zhi = (zhi + 127) >> 7
			if heights[lo][zlo] == baseY && heights[hi][zlo] == baseY && heights[lo][zhi] == baseY && heights[hi][zhi] == baseY { return self }
		}
		let m = copy()
		m.vertexNormals = vertexNormals; m.triangleNormals = triangleNormals; m.mergedNormals = mergedNormals
		if orientation != 3 { m.vertexY = [Int](repeating: 0, count: m.vertexCount) }
		switch orientation {
		case 1:
			for i in 0..<m.vertexCount {
				let wx = vertexX[i] + x, wz = vertexZ[i] + z
				let fx = wx & 0x7F, fz = wz & 0x7F, tx = wx >> 7, tz = wz >> 7
				let a = (heights[tx][tz] * (128 - fx) + heights[tx + 1][tz] * fx) >> 7
				let b = (heights[tx][tz + 1] * (128 - fx) + heights[tx + 1][tz + 1] * fx) >> 7
				m.vertexY[i] = vertexY[i] + ((a * (128 - fz) + b * fz) >> 7) - baseY
			}
		case 2:
			for i in 0..<m.vertexCount {
				let frac = minY == 0 ? arg1 : (vertexY[i] << 16) / minY
				if frac < arg1 {
					let wx = vertexX[i] + x, wz = vertexZ[i] + z
					let fx = wx & 0x7F, fz = wz & 0x7F, tx = wx >> 7, tz = wz >> 7
					let a = (heights[tx][tz] * (128 - fx) + heights[tx + 1][tz] * fx) >> 7
					let b = (heights[tx][tz + 1] * (128 - fx) + heights[tx + 1][tz + 1] * fx) >> 7
					let hh = (a * (128 - fz) + b * fz) >> 7
					m.vertexY[i] = vertexY[i] + (hh - baseY) * (arg1 - frac) / arg1
				} else {
					m.vertexY[i] = vertexY[i]
				}
			}
		case 3:
			// rt4 applies the tilt to `this`, not the copy (kept as-is; orientation 3 is rare).
			tiltToTerrain(heights, x, baseY, z, (arg1 & 0xFF) * 4, ((arg1 >> 8) & 0xFF) * 4)
		case 4, 5:
			guard let up = upper else { return self }
			let height = maxY - minY
			for i in 0..<vertexCount {
				let wx = vertexX[i] + x, wz = vertexZ[i] + z
				let fx = wx & 0x7F, fz = wz & 0x7F, tx = wx >> 7, tz = wz >> 7
				func sample(_ g: [[Int]]) -> Int {
					let a = (g[tx][tz] * (128 - fx) + g[tx + 1][tz] * fx) >> 7
					let b = (g[tx][tz + 1] * (128 - fx) + g[tx + 1][tz + 1] * fx) >> 7
					return (a * (128 - fz) + b * fz) >> 7
				}
				if orientation == 4 {
					m.vertexY[i] = vertexY[i] + sample(up) + height - baseY
				} else {
					let lower = sample(heights), upperH = sample(up)
					let diff = lower - upperH
					m.vertexY[i] = (((vertexY[i] << 8) / height * diff) >> 8) - (baseY - lower)
				}
			}
		default: break
		}
		boundsValid = false
		return m
	}

	// MARK: lighting

	/// rt4 `createModel()`/`createSoftwareModel`: lights with the stored ambient/contrast.
	public func createModel(textureAvailable: (Int) -> Bool = { _ in true }) -> SoftwareModel {
		SoftwareModel(self, ambient: lightAmbient, contrast: lightContrast, x: -50, y: -10, z: -50, textureAvailable: textureAvailable)
	}

	/// rt4 `createModel(a, c, x, y, z)` software path.
	public func createModel(ambient: Int, contrast: Int, x: Int, y: Int, z: Int, textureAvailable: (Int) -> Bool = { _ in true }) -> SoftwareModel {
		SoftwareModel(self, ambient: ambient, contrast: contrast, x: x, y: y, z: z, textureAvailable: textureAvailable)
	}
}
