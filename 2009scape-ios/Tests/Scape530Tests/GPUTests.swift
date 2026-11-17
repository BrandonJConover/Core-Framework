import Foundation
import XCTest
@testable import Scape530

/// A tiny CPU rasteriser over `GPUVertex` triangle lists and a `Mat4` view-projection: what the Metal
/// pipeline does (perspective-correct interpolation, depth test, back-face culling by winding, texture
/// array, fog, alpha test / blend), enough to look at the buffers as a picture.
struct GPUReferenceRaster {
	var width: Int, height: Int
	var pixels: [UInt32]
	var depth: [Float]

	init(width: Int, height: Int, clear: UInt32) {
		self.width = width; self.height = height
		pixels = [UInt32](repeating: clear, count: width * height)
		depth = [Float](repeating: .infinity, count: width * height)
	}

	mutating func draw(_ vertices: [GPUVertex], frame: GPUFrame, textures: (Int) -> [UInt8]?, blend: Bool) {
		let vp = frame.camera.viewProjection
		let fog = frame.fog
		let fogRGB = (Float((fog.color >> 16) & 0xFF), Float((fog.color >> 8) & 0xFF), Float(fog.color & 0xFF))
		var cache: [Int: [UInt8]?] = [:]
		var t = 0
		while t + 2 < vertices.count {
			defer { t += 3 }
			let v = [vertices[t], vertices[t + 1], vertices[t + 2]]
			let c = v.map { vp.transform($0.x, $0.y, $0.z) }
			if c.contains(where: { $0.w < frame.camera.near }) { continue }
			let sx = c.map { (($0.x / $0.w) + 1) * 0.5 * Float(width) }
			let sy = c.map { (1 - ($0.y / $0.w)) * 0.5 * Float(height) }
			// The software rasteriser's visibility test: (xa - xb)(yc - yb) - (ya - yb)(xc - xb) > 0.
			let cross = (sx[0] - sx[1]) * (sy[2] - sy[1]) - (sy[0] - sy[1]) * (sx[2] - sx[1])
			if cross <= 0 { continue }
			let minX = max(0, Int(floor(min(sx[0], sx[1], sx[2])))), maxX = min(width - 1, Int(ceil(max(sx[0], sx[1], sx[2]))))
			let minY = max(0, Int(floor(min(sy[0], sy[1], sy[2])))), maxY = min(height - 1, Int(ceil(max(sy[0], sy[1], sy[2]))))
			if minX > maxX || minY > maxY { continue }
			let area = -cross // (b - a) x (c - a), the sign the edge functions below use
			for y in minY...maxY {
				for x in minX...maxX {
					let px = Float(x) + 0.5, py = Float(y) + 0.5
					// Barycentrics in screen space.
					let w0 = ((sx[1] - px) * (sy[2] - py) - (sy[1] - py) * (sx[2] - px)) / area
					let w1 = ((sx[2] - px) * (sy[0] - py) - (sy[2] - py) * (sx[0] - px)) / area
					let w2 = 1 - w0 - w1
					if w0 < 0 || w1 < 0 || w2 < 0 { continue }
					let iw0 = w0 / c[0].w, iw1 = w1 / c[1].w, iw2 = w2 / c[2].w
					let inv = iw0 + iw1 + iw2
					let viewZ = 1 / inv
					let z = (w0 * c[0].z / c[0].w + w1 * c[1].z / c[1].w + w2 * c[2].z / c[2].w)
					let idx = y * width + x
					if z >= depth[idx] { continue }
					func lerp(_ a: Float, _ b: Float, _ cc: Float) -> Float { (a * iw0 + b * iw1 + cc * iw2) / inv }
					let u = lerp(v[0].u, v[1].u, v[2].u), vv = lerp(v[0].v, v[1].v, v[2].v)
					func chan(_ s: Int) -> Float {
						func byte(_ vx: GPUVertex) -> Float { Float((vx.color >> UInt32(s)) & 0xFF) }
						return lerp(byte(v[0]), byte(v[1]), byte(v[2]))
					}
					var r = chan(0), g = chan(8), b = chan(16), a = chan(24) / 255
					let mat = Int(v[0].material)
					if mat != 0 {
						let id = mat - 1
						if cache[id] == nil { cache[id] = textures(id) }
						if let tex = cache[id] ?? nil {
							let tx = Int((u - floor(u)) * 128) & 127, ty = Int((vv - floor(vv)) * 128) & 127
							let o = (ty * 128 + tx) * 4
							r = r * Float(tex[o]) / 255; g = g * Float(tex[o + 1]) / 255; b = b * Float(tex[o + 2]) / 255
							a *= Float(tex[o + 3]) / 255
						}
					}
					if a < 0.5 && !blend { continue }
					let f = fog.factor(depth: viewZ)
					r += (fogRGB.0 - r) * f; g += (fogRGB.1 - g) * f; b += (fogRGB.2 - b) * f
					var out = (r, g, b)
					if blend {
						let d = pixels[idx]
						out = (r * a + Float((d >> 16) & 0xFF) * (1 - a), g * a + Float((d >> 8) & 0xFF) * (1 - a), b * a + Float(d & 0xFF) * (1 - a))
					} else {
						depth[idx] = z
					}
					pixels[idx] = 0xFF00_0000 | UInt32(min(255, max(0, out.0))) << 16 | UInt32(min(255, max(0, out.1))) << 8 | UInt32(min(255, max(0, out.2)))
				}
			}
		}
	}

	/// Renders a frame: static chunk ranges, dynamic geometry, then the blended passes.
	static func render(_ frame: GPUFrame, textures: (Int) -> [UInt8]?) -> GPUReferenceRaster {
		let c = frame.settings.fogColor
		var r = GPUReferenceRaster(width: frame.viewport.w, height: frame.viewport.h, clear: 0xFF00_0000 | UInt32(c))
		for item in frame.list.items where !item.blend {
			let chunk = frame.list.chunks[Int(item.chunk)]
			r.draw(Array(chunk.opaque[Int(item.first)..<Int(item.first + item.count)]), frame: frame, textures: textures, blend: false)
		}
		r.draw(frame.dynamic.opaque, frame: frame, textures: textures, blend: false)
		for item in frame.list.items where item.blend {
			let chunk = frame.list.chunks[Int(item.chunk)]
			r.draw(Array(chunk.blend[Int(item.first)..<Int(item.first + item.count)]), frame: frame, textures: textures, blend: true)
		}
		r.draw(frame.dynamic.blend, frame: frame, textures: textures, blend: true)
		return r
	}

	var raster: Raster {
		var r = Raster(width: width, height: height)
		r.pixels = pixels
		return r
	}
}

final class GPUTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	/// Replays the recorded session (see `WorldViewTests.replay`) and returns the client in game.
	func replayedClient() throws -> GameClient {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		let me = 2047
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var players = PlayerInfoDecoder(selfIndex: me, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") {
			switch pkt.opcode {
			case ServerProt.playerInfo:
				let r = try players.decode(pkt.payload)
				client.handle(.players(r, players))
				for _ in 0..<30 { client.world.cycle(varps: client.state.varps) }
			case ServerProt.npcInfo:
				let p = try XCTUnwrap(players.players[me])
				let r = try npcs.decode(pkt.payload, selfX: p.x, selfZ: p.z)
				client.handle(.npcs(r, npcs))
			default:
				let m = try ServerMessage.decode(pkt)
				if case .rebuildNormal(let r) = m {
					if let z = zone {
						players.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
						npcs.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
					} else {
						players = PlayerInfoDecoder(selfIndex: me, localX: r.localX, localZ: r.localZ)
					}
					zone = (r.zoneX, r.zoneZ)
				}
				client.handle(.message(m))
			}
		}
		return client
	}

	/// Draws one GPU-mode frame of the replayed world and returns the world, its raster and the GPU frame.
	func gpuFrame(_ client: GameClient, settings: GPURenderSettings = GPURenderSettings(), size: (Int, Int) = (1015, 469)) throws -> (WorldView, Raster, GPUFrame) {
		let world = client.world
		world.gpuSettings = settings
		var r = Raster(width: size.0, height: size.1, transparent: true)
		XCTAssertTrue(world.draw(into: &r, rect: (0, 0, size.0, size.1)))
		// Finish baking the static scene (the frame loop does it over a few frames).
		if let scene = world.scene, let mesh = world.gpuMesh { mesh.buildAll(scene: scene) }
		XCTAssertTrue(world.draw(into: &r, rect: (0, 0, size.0, size.1)))
		return (world, r, try XCTUnwrap(world.gpuFrame))
	}

	// MARK: no cache needed

	func testVertexLayout() {
		XCTAssertEqual(GPUVertex.layout.stride, 44)
		XCTAssertEqual(MemoryLayout<GPUVertex>.offset(of: \GPUVertex.nx), GPUVertex.layout.normal)
		XCTAssertEqual(MemoryLayout<GPUVertex>.offset(of: \GPUVertex.u), GPUVertex.layout.uv)
		XCTAssertEqual(MemoryLayout<GPUVertex>.offset(of: \GPUVertex.color), GPUVertex.layout.color)
		XCTAssertEqual(MemoryLayout<GPUVertex>.offset(of: \GPUVertex.base), GPUVertex.layout.base)
		XCTAssertEqual(MemoryLayout<GPUVertex>.offset(of: \GPUVertex.material), GPUVertex.layout.materialFlags)
		XCTAssertEqual(MemoryLayout<GPUMaterial>.stride, 16)
		XCTAssertEqual(GPUVertex.rgba(1, 2, 3, 4), 0x0403_0201)
	}

	/// rt4's integer projection of `Scene.draw` / `WorldView.project`, the reference for the matrices.
	func softwareProject(_ x: Int, _ y: Int, _ z: Int, eye: GPUCamera) -> (Int, Int)? {
		let dx = x - eye.x, dy = y - eye.y, dz = z - eye.z
		let sp = MathTables.sin[eye.pitch & 2047], cp = MathTables.cos[eye.pitch & 2047]
		let sy = MathTables.sin[eye.yaw & 2047], cy = MathTables.cos[eye.yaw & 2047]
		let a = (dx * cy + sy * dz) >> 16
		let b = (dz * cy - sy * dx) >> 16
		let c = (cp * dy - b * sp) >> 16
		let d = (b * cp + dy * sp) >> 16
		if d < 50 { return nil }
		return ((a << 9) / d + eye.centerX, (c << 9) / d + eye.centerY)
	}

	/// The same projection in doubles without any rounding.
	func exactProject(_ x: Int, _ y: Int, _ z: Int, eye: GPUCamera) -> (Double, Double) {
		let dx = Double(x - eye.x), dy = Double(y - eye.y), dz = Double(z - eye.z)
		let sp = Double(MathTables.sin[eye.pitch & 2047]) / 65536, cp = Double(MathTables.cos[eye.pitch & 2047]) / 65536
		let sy = Double(MathTables.sin[eye.yaw & 2047]) / 65536, cy = Double(MathTables.cos[eye.yaw & 2047]) / 65536
		let a = dx * cy + sy * dz, b = dz * cy - sy * dx
		let c = cp * dy - b * sp, d = b * cp + dy * sp
		return (a * 512 / d + Double(eye.centerX), c * 512 / d + Double(eye.centerY))
	}

	func testCameraMatricesMatchSoftwareProjection() {
		var rng = SystemRandomNumberGenerator()
		var checked = 0
		for sizeIndex in 0..<3 {
			let (w, h) = [(1015, 469), (765, 503), (1024, 768)][sizeIndex]
			for _ in 0..<40 {
				let cam = GPUCamera(x: Int.random(in: 2000...9000, using: &rng), y: -Int.random(in: 200...1500, using: &rng), z: Int.random(in: 2000...9000, using: &rng),
				                    pitch: Int.random(in: 128...383, using: &rng), yaw: Int.random(in: 0...2047, using: &rng), width: w, height: h)
				for _ in 0..<20 {
					let px = cam.x + Int.random(in: -3000...3000, using: &rng), pz = cam.z + Int.random(in: -3000...3000, using: &rng)
					let py = Int.random(in: -400...50, using: &rng)
					guard let s = softwareProject(px, py, pz, eye: cam), let g = cam.project(rt4: px, y: py, z: pz) else { continue }
					// The software projection floors `a` and `c` to whole units before dividing by the depth, so it
					// is only exact to about 1100 / depth pixels: compare with that allowance, and to float
					// precision against the exact value.
					guard abs(s.0 - w / 2) < w * 2, abs(s.1 - h / 2) < h * 2 else { continue }
					let slack = 1.0 + (1100.0 + abs(Double(g.x) - Double(cam.centerX)) + abs(Double(g.y) - Double(cam.centerY))) / Double(g.depth)
					XCTAssertEqual(Double(g.x), Double(s.0), accuracy: slack, "x for \(cam) point \((px, py, pz))")
					XCTAssertEqual(Double(g.y), Double(s.1), accuracy: slack, "y for \(cam) point \((px, py, pz))")
					let exact = exactProject(px, py, pz, eye: cam)
					XCTAssertEqual(Double(g.x), exact.0, accuracy: 0.05 + abs(exact.0) * 1e-5)
					XCTAssertEqual(Double(g.y), exact.1, accuracy: 0.05 + abs(exact.1) * 1e-5)
					checked += 1
				}
			}
		}
		XCTAssertGreaterThan(checked, 500)
	}

	func testFrustumAndFog() {
		var cam = GPUCamera(x: 5000, y: -600, z: 5000, pitch: 200, yaw: 0, width: 1015, height: 469)
		cam.far = 8000
		let f = cam.frustum
		// North of the eye (yaw 0 looks along +z) at ground level is in view; the same box south is behind.
		var ahead = GPUBounds(); ahead.add(4900, 0, 6000); ahead.add(5100, 100, 6200)
		var behind = GPUBounds(); behind.add(4900, 0, 3000); behind.add(5100, 100, 3200)
		var far = GPUBounds(); far.add(4900, 0, 14000); far.add(5100, 100, 14200)
		XCTAssertTrue(f.intersects(ahead))
		XCTAssertFalse(f.intersects(behind))
		XCTAssertFalse(f.intersects(far))
		let fog = GPUFog.rt4(tiles: 56, color: 0xC8C0A8, enabled: true)
		XCTAssertEqual(fog.start, 56 * 128 - 1024)
		XCTAssertEqual(fog.end, 56 * 128 - 512)
		XCTAssertEqual(fog.factor(depth: 100), 0)
		XCTAssertEqual(fog.factor(depth: 56 * 128), 1)
		XCTAssertEqual(GPUFog.rt4(tiles: 56, color: 0, enabled: false).factor(depth: 1e6), 0)
	}

	func testTransparentRasterBlend() {
		var r = Raster(width: 4, height: 1, transparent: true)
		XCTAssertEqual(r.pixels[0], 0)
		r.fillRect(0, 0, 1, 1, 0xFF0000, opacity: 128)
		XCTAssertEqual(r.pixels[0] >> 24, 128)
		XCTAssertEqual((r.pixels[0] >> 16) & 0xFF, 255)
		r.fillRect(0, 0, 1, 1, 0x0000FF, opacity: 128)
		XCTAssertGreaterThan(r.pixels[0] >> 24, 128)
		r.fillRect(1, 0, 1, 1, 0x00FF00)
		XCTAssertEqual(r.pixels[1], 0xFF00_FF00)
		XCTAssertEqual(r.pixels[3], 0)
		// An opaque raster is unchanged by the new path.
		var o = Raster(width: 1, height: 1)
		o.fillRect(0, 0, 1, 1, 0xFFFFFF, opacity: 128)
		XCTAssertEqual(o.pixels[0] >> 24, 0xFF)
	}

	func testPaletteMatchesSoftwarePalette() {
		let p = GPUPalette(brightness: 0.8)
		let r = Rasteriser3D(width: 1, height: 1)
		r.setBrightness(0.8, jitter: false)
		let pal = r.palette
		for hsl in [0, 1, 2000, 12345, 40000, 65535] {
			let c = UInt32(truncatingIfNeeded: pal[hsl]) & 0xFFFFFF
			let v = p.rgba(hsl)
			XCTAssertEqual(Int(v & 0xFF), Int((c >> 16) & 0xFF))
			XCTAssertEqual(Int((v >> 8) & 0xFF), Int((c >> 8) & 0xFF))
			XCTAssertEqual(Int((v >> 16) & 0xFF), Int(c & 0xFF))
			XCTAssertEqual(v >> 24, 255)
		}
		// High (lighting) bits of lit gouraud values are ignored.
		XCTAssertEqual(p.rgba(5000 | (100 << 17)), p.rgba(5000))
		XCTAssertEqual(GPUPalette.shade(64) & 0xFF, 127)
	}

	func testModelTemplateFromHandBuiltModel() {
		// One gouraud triangle, one textured flat triangle, one hidden, one translucent.
		let m = SoftwareModel()
		m.vertexCount = 4; m.triangleCount = 4
		m.vertexX = [0, 128, 0, 128]; m.vertexY = [0, 0, -128, -128]; m.vertexZ = [0, 0, 0, 0]
		m.triangleVertexA = [0, 1, 0, 0]; m.triangleVertexB = [1, 3, 1, 1]; m.triangleVertexC = [2, 2, 2, 3]
		m.triangleColorA = [0x2800 | 60, 80, 70, 0x2800 | 60]
		m.triangleColorB = [0x2800 | 90, 0, 0, 0x2800 | 60]
		m.triangleColorC = [0x2800 | 40, -1, -2, 0x2800 | 60]
		m.triangleColors = [Int16(0x2800 | 70), 0, 0, Int16(0x2800 | 60)]
		m.triangleTextures = [-1, 7, -1, -1]
		m.triangleAlpha = [0, 0, 0, 100]
		let palette = GPUPalette(brightness: 0.8)
		let t = GPUModelTemplate(m, palette: palette)
		XCTAssertEqual(t.opaque.count, 6)
		XCTAssertEqual(t.blend.count, 3)
		XCTAssertEqual(t.textureIds, [7])
		XCTAssertEqual(t.opaque[0].color, palette.rgba(0x2800 | 60))
		XCTAssertEqual(t.opaque[1].color, palette.rgba(0x2800 | 90))
		XCTAssertEqual(t.opaque[2].color, palette.rgba(0x2800 | 40))
		XCTAssertEqual(t.opaque[0].y, 0)
		XCTAssertEqual(t.opaque[2].y, 128, "rt4 y is negative up, GPU y is up")
		XCTAssertEqual(t.opaque[3].material, 8)
		XCTAssertEqual(t.opaque[3].color, GPUPalette.shade(80))
		XCTAssertEqual(t.blend[0].a, 155)
		XCTAssertEqual(Set(t.opaque[3...5].map(\.color)), [GPUPalette.shade(80)], "flat textured face has one shade")
		// UVs from the face's own vertices (a, b, c) -> (0,0), (1,0), (0,1).
		XCTAssertEqual(t.opaque[3].u, 0, accuracy: 1e-4)
		XCTAssertEqual(t.opaque[4].u, 1, accuracy: 1e-4)
		XCTAssertEqual(t.opaque[5].v, 1, accuracy: 1e-4)
		for v in t.opaque + t.blend {
			XCTAssertEqual(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz, 1, accuracy: 1e-4)
		}
		// Placement: yaw 512 is a quarter turn; translate to (1000, y -64, 2000).
		var s = GPUMeshStream()
		t.append(to: &s, yaw: 512, x: 1000, y: -64, z: 2000)
		XCTAssertEqual(s.opaque.count, 6)
		XCTAssertEqual(s.opaque[1].x, 1000 + 0, accuracy: 0.01)   // (128,0,0) turned: z' = z c - x s = -128
		XCTAssertEqual(s.opaque[1].z, 2000 - 128, accuracy: 0.01)
		XCTAssertEqual(s.opaque[0].y, 64, accuracy: 0.01)
	}

	// MARK: real cache scenes

	func testSceneMeshFromRealScene() throws {
		let client = try replayedClient()
		let (world, _, frame) = try gpuFrame(client)
		let scene = try XCTUnwrap(world.scene)
		let mesh = try XCTUnwrap(world.gpuMesh)
		XCTAssertEqual(mesh.builtCount, mesh.totalChunks)
		XCTAssertGreaterThan(mesh.triangleCount, 20000)
		var vertices = 0, bad = 0
		var bounds = GPUBounds()
		var terrain = 0, textured = 0
		for case let c? in mesh.chunks {
			XCTAssertEqual((c.opaque.count + c.blend.count) % 3, 0)
			for v in c.opaque + c.blend {
				vertices += 1
				let nums = [v.x, v.y, v.z, v.nx, v.ny, v.nz, v.u, v.v]
				if nums.contains(where: { !$0.isFinite }) { bad += 1 }
				bounds.add(v)
				if v.flags & GPUVertex.flagTerrain != 0 { terrain += 1 }
				if v.material != 0 { textured += 1 }
				XCTAssertEqual(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz, 1, accuracy: 0.01)
			}
		}
		XCTAssertEqual(bad, 0, "no NaN or infinite values")
		XCTAssertGreaterThan(terrain, 10000)
		print("gpu scene: \(vertices) vertices (\(vertices / 3) triangles, \(vertices * 44 / 1024 / 1024) MB), terrain \(terrain), textured \(textured), bounds x \(bounds.minX)...\(bounds.maxX) y \(bounds.minY)...\(bounds.maxY) z \(bounds.minZ)...\(bounds.maxZ)")
		// Everything sits inside the 104 x 104 tile scene (models overhang the edge a little).
		XCTAssertGreaterThan(bounds.minX, -1024); XCTAssertLessThan(bounds.maxX, Float(scene.width * 128 + 1024))
		XCTAssertGreaterThan(bounds.minZ, -1024); XCTAssertLessThan(bounds.maxZ, Float(scene.length * 128 + 1024))
		XCTAssertGreaterThan(bounds.maxY, -1000); XCTAssertLessThan(bounds.maxY, 4000)
		XCTAssertGreaterThan(frame.list.items.count, 0)
		XCTAssertGreaterThan(frame.dynamic.opaque.count, 0, "the player and npcs are in the dynamic stream")
	}

	func testTerrainColoursMatchSoftwareTiles() throws {
		let client = try replayedClient()
		let (world, _, _) = try gpuFrame(client)
		let scene = try XCTUnwrap(world.scene)
		let palette = try XCTUnwrap(world.gpu.palette)
		let level = scene.centralPlane
		var checked = 0
		for x in 20..<80 {
			for z in 20..<80 where checked < 25 {
				guard let t = scene.tiles[level][x][z], let p = t.plainTile, p.texture == -1, p.colorNE != 12345678, p.colorSW != 12345678 else { continue }
				var stream = GPUMeshStream(), b = GPUBounds()
				GPUTerrainMesher.appendPlain(p, level: t.heightLevel, x: x, z: z, scene: scene, palette: palette, into: &stream, bounds: &b)
				XCTAssertEqual(stream.opaque.count, 6)
				// Triangle 1 is (NE, NW, SE), triangle 2 is (SW, SE, NW), as the software draws them.
				XCTAssertEqual(stream.opaque[0].color, palette.rgba(p.colorNE))
				XCTAssertEqual(stream.opaque[1].color, palette.rgba(p.colorNW))
				XCTAssertEqual(stream.opaque[2].color, palette.rgba(p.colorSE))
				XCTAssertEqual(stream.opaque[3].color, palette.rgba(p.colorSW))
				XCTAssertEqual(stream.opaque[3].x, Float(x * 128)); XCTAssertEqual(stream.opaque[3].z, Float(z * 128))
				XCTAssertEqual(stream.opaque[3].y, Float(-scene.tileHeights[level][x][z]))
				XCTAssertGreaterThan(stream.opaque[3].ny, 0.3, "ground normals point up")
				checked += 1
			}
		}
		XCTAssertGreaterThan(checked, 10)
	}

	func testModelColoursMatchSoftwareModel() throws {
		let client = try replayedClient()
		let (world, _, _) = try gpuFrame(client)
		let scene = try XCTUnwrap(world.scene)
		let palette = try XCTUnwrap(world.gpu.palette)
		var checked = 0
		search: for x in 0..<104 {
			for z in 0..<104 {
				guard let t = scene.tiles[scene.centralPlane][x][z] else { continue }
				var models: [SoftwareModel] = []
				for i in 0..<t.sceneryCount { if let m = t.scenery[i]?.entity as? SoftwareModel { models.append(m) } }
				if let m = t.wall?.primary as? SoftwareModel { models.append(m) }
				for m in models where m.triangleCount >= 3 {
					let tpl = GPUModelTemplate(m, palette: palette)
					// The opaque stream holds the model's non-hidden, non-translucent triangles in order.
					var k = 0, compared = 0
					for i in 0..<m.triangleCount where m.triangleColorC[i] != -2 && (m.triangleAlpha?[i] ?? 0) == 0 {
						defer { k += 3 }
						if (m.triangleTextures?[i] ?? -1) != -1 { continue }
						let colC = m.triangleColorC[i]
						let expect = [palette.rgba(m.triangleColorA[i]), palette.rgba(colC == -1 ? m.triangleColorA[i] : m.triangleColorB[i]), palette.rgba(colC == -1 ? m.triangleColorA[i] : colC)]
						XCTAssertEqual(Array(tpl.opaque[k..<k + 3].map(\.color)), expect, "triangle \(i)")
						compared += 1
						if compared >= 12 { break }
					}
					if compared > 0 { checked += 1 }
					if checked >= 6 { break search }
				}
			}
		}
		XCTAssertGreaterThan(checked, 2)
	}

	func testCullingKeepsPlayerAreaAndDropsFarTiles() throws {
		let client = try replayedClient()
		let (world, _, frame) = try gpuFrame(client)
		let scene = try XCTUnwrap(world.scene)
		let mesh = try XCTUnwrap(world.gpuMesh)
		let me = try XCTUnwrap(world.selfActor)
		let pt = (x: me.xFine >> 7, z: me.zFine >> 7)
		let level = scene.centralPlane
		let playerChunk = try XCTUnwrap(mesh.chunk(level: level, cx: pt.x / 8, cz: pt.z / 8))
		XCTAssertTrue(frame.list.chunks.contains { $0 === playerChunk }, "the chunk under the player is drawn")
		// Every drawn chunk is within the draw distance of the eye.
		let eye = frame.camera.position
		for c in frame.list.chunks {
			let b = c.bounds
			guard !b.isEmpty else { continue }
			let dx = max(b.minX - eye.x, 0, eye.x - b.maxX), dz = max(b.minZ - eye.z, 0, eye.z - b.maxZ)
			XCTAssertLessThanOrEqual((dx * dx + dz * dz).squareRoot(), Float(frame.settings.clampedDrawDistance * 128) + 1)
		}
		// A short draw distance keeps a subset, dropping the far tiles; a long one keeps more than the software 25.
		let cam = frame.camera
		let near = mesh.makeDrawList(camera: cam, drawDistanceTiles: 10)
		let soft = mesh.makeDrawList(camera: cam, drawDistanceTiles: 25)
		let hd = mesh.makeDrawList(camera: cam, drawDistanceTiles: 70)
		print("chunks drawn: 10 tiles \(near.chunks.count), 25 tiles \(soft.chunks.count), 70 tiles \(hd.chunks.count) (of \(near.tested)); triangles \(near.triangleCount) / \(soft.triangleCount) / \(hd.triangleCount)")
		XCTAssertLessThan(near.chunks.count, soft.chunks.count)
		XCTAssertLessThanOrEqual(soft.chunks.count, hd.chunks.count)
		XCTAssertGreaterThan(hd.triangleCount, soft.triangleCount)
		XCTAssertTrue(near.chunks.contains { $0 === playerChunk })
		// Far tiles really are gone: no chunk of the 10-tile list lies farther than 10 tiles.
		for c in near.chunks where !c.bounds.isEmpty {
			let b = c.bounds
			let dx = max(b.minX - eye.x, 0, eye.x - b.maxX), dz = max(b.minZ - eye.z, 0, eye.z - b.maxZ)
			XCTAssertLessThanOrEqual((dx * dx + dz * dz).squareRoot(), 10 * 128 + 1)
		}
		// Looking the other way drops the chunks that were ahead.
		var back = cam
		back.yaw = (cam.yaw + 1024) & 2047
		let turned = mesh.makeDrawList(camera: back, drawDistanceTiles: 25)
		XCTAssertNotEqual(Set(turned.chunks.map(\.id)), Set(soft.chunks.map(\.id)))
	}

	func testRoofHidingDropsTiles() throws {
		let client = try replayedClient()
		let (world, _, frame) = try gpuFrame(client)
		let mesh = try XCTUnwrap(world.gpuMesh)
		let all = mesh.makeDrawList(camera: frame.camera, drawDistanceTiles: 56)
		let hiddenAbove = mesh.makeDrawList(camera: frame.camera, drawDistanceTiles: 56, hideFromLevel: 1, hidden: { _, _, _ in true })
		let noUpper = mesh.makeDrawList(camera: frame.camera, drawDistanceTiles: 56, minLevel: 0, maxLevel: 0)
		XCTAssertLessThan(hiddenAbove.triangleCount, all.triangleCount)
		XCTAssertEqual(hiddenAbove.triangleCount, noUpper.triangleCount)
	}

	func testProjectionMatchesWorldViewProject() throws {
		let client = try replayedClient()
		let (world, _, frame) = try gpuFrame(client)
		let scene = try XCTUnwrap(world.scene)
		let cam = try XCTUnwrap(world.overlayCamera)
		let me = try XCTUnwrap(world.selfActor)
		var checked = 0
		for dx in stride(from: -6, through: 6, by: 2) {
			for dz in stride(from: -4, through: 8, by: 2) {
				let x = me.xFine + dx * 128, z = me.zFine + dz * 128
				for h in [0, 60, 200] {
					guard let sw = world.project(cam, xFine: x, zFine: z, height: h, scene: scene) else { continue }
					let y = scene.tileHeight(level: cam.level, xFine: x, zFine: z) - h
					let g = try XCTUnwrap(frame.camera.project(rt4: x, y: y, z: z))
					let slack = 1.0 + 1100.0 / Double(g.depth)
					XCTAssertEqual(Double(g.x), Double(sw.x), accuracy: slack)
					XCTAssertEqual(Double(g.y), Double(sw.y), accuracy: slack)
					if g.depth > 1500 {
						XCTAssertEqual(Double(g.x), Double(sw.x), accuracy: 1.0, "within 1 px at distance")
						XCTAssertEqual(Double(g.y), Double(sw.y), accuracy: 1.0, "within 1 px at distance")
					}
					checked += 1
				}
			}
		}
		XCTAssertGreaterThan(checked, 30)
		// The player's own tile lands inside the viewport.
		let c = try XCTUnwrap(frame.camera.project(rt4: me.xFine, y: scene.tileHeight(level: cam.level, xFine: me.xFine, zFine: me.zFine), z: me.zFine))
		XCTAssertTrue(c.x > 0 && c.x < Float(frame.viewport.w) && c.y > 0 && c.y < Float(frame.viewport.h))
	}

	func testGPUModeLeavesViewportTransparentAndDrawsOverlays() throws {
		let client = try replayedClient()
		let (world, r, frame) = try gpuFrame(client)
		let v = frame.viewport
		var transparent = 0, total = 0
		for y in stride(from: 0, to: v.h, by: 4) { for x in stride(from: 0, to: v.w, by: 4) { total += 1; if r.pixels[y * v.w + x] >> 24 == 0 { transparent += 1 } } }
		XCTAssertGreaterThan(transparent, total * 9 / 10, "the viewport is transparent for the Metal scene")
		world.gpuSettings = nil
		var soft = Raster(width: v.w, height: v.h)
		XCTAssertTrue(world.draw(into: &soft, rect: (0, 0, v.w, v.h)))
		XCTAssertNil(world.gpuFrame, "software mode has no GPU frame")
		XCTAssertEqual(soft.pixels[0] >> 24, 0xFF)
	}

	func testCPUReferenceRenderOfGPUBuffers() throws {
		let client = try replayedClient()
		let world = client.world
		let (_, _, frame) = try gpuFrame(client)
		let store = try XCTUnwrap(world.textures)
		let palette = try XCTUnwrap(world.gpu.palette)
		let set = GPUTextureSet(store: store, brightness: frame.brightness, palette: palette)
		var texCache: [Int: [UInt8]?] = [:]
		let ref = GPUReferenceRaster.render(frame) { id in
			if let c = texCache[id] { return c }
			let t = set.rgba(id: id)
			texCache[id] = t
			return t
		}
		try save(ref.raster, "gpu-reference-56tiles")
		// Compare with the software frame of the same camera: both must cover the viewport with ground.
		world.gpuSettings = nil
		var soft = Raster(width: frame.viewport.w, height: frame.viewport.h)
		XCTAssertTrue(world.draw(into: &soft, rect: (0, 0, frame.viewport.w, frame.viewport.h)))
		try save(soft, "gpu-reference-software")
		let sky = 0xFF00_0000 | UInt32(frame.settings.fogColor)
		var covered = 0, total = 0, agree = 0
		for y in stride(from: 0, to: frame.viewport.h, by: 3) {
			for x in stride(from: 0, to: frame.viewport.w, by: 3) {
				total += 1
				let g = ref.pixels[y * frame.viewport.w + x], s = soft.pixels[y * frame.viewport.w + x]
				if g != sky { covered += 1 }
				// Same coarse colour: each channel within 48 of the software pixel.
				let dr = abs(Int((g >> 16) & 0xFF) - Int((s >> 16) & 0xFF)), dg = abs(Int((g >> 8) & 0xFF) - Int((s >> 8) & 0xFF)), db = abs(Int(g & 0xFF) - Int(s & 0xFF))
				if max(dr, dg, db) < 48 { agree += 1 }
			}
		}
		print("reference raster: \(covered * 100 / total)% covered, \(agree * 100 / total)% within 48/channel of the software frame")
		XCTAssertGreaterThan(covered, total * 6 / 10)
		XCTAssertGreaterThan(agree, total * 4 / 10)
		// A longer draw distance shows more world than the software's 25 tiles (more of the frame is ground, less sky).
		var far = GPURenderSettings()
		far.drawDistanceTiles = 25
		let (_, _, shortFrame) = try gpuFrame(client, settings: far)
		XCTAssertLessThan(shortFrame.list.triangleCount, frame.list.triangleCount)
	}

	func testTextureSetBuildsLayers() throws {
		let client = try replayedClient()
		let (world, _, frame) = try gpuFrame(client)
		let store = try XCTUnwrap(world.textures)
		let palette = try XCTUnwrap(world.gpu.palette)
		let set = GPUTextureSet(store: store, brightness: frame.brightness, palette: palette)
		XCTAssertGreaterThan(set.layerCount, 10)
		XCTAssertFalse(frame.usedTextures.isEmpty, "the scene uses textures")
		let id = try XCTUnwrap(frame.usedTextures.sorted().first { set.layerOf[$0] != nil })
		let layer = try XCTUnwrap(set.rgba(id: id))
		XCTAssertEqual(layer.count, GPUTextureSet.size * GPUTextureSet.size * 4)
		XCTAssertTrue(stride(from: 3, to: layer.count, by: 4).contains { layer[$0] == 255 })
		let table = set.materials(uploaded: [id: 3])
		XCTAssertEqual(table.count, store.meta.count + 1)
		XCTAssertEqual(table[id + 1].layer, 3)
		XCTAssertEqual(table[0].layer, -1)
		XCTAssertEqual(frame.uniforms.count, GPUFrame.uniformCount)
		XCTAssertTrue(frame.uniforms.allSatisfy { $0.isFinite })
	}

	func testLocChangeRebuildsOnlyItsChunk() throws {
		let client = try replayedClient()
		let (world, _, _) = try gpuFrame(client)
		let scene = try XCTUnwrap(world.scene)
		let mesh = try XCTUnwrap(world.gpuMesh)
		let before = mesh.chunks.map { $0?.id ?? 0 }
		// Remove a wall (a loc zone update does the same) and let the mesh notice.
		var target: (l: Int, x: Int, z: Int)?
		outer: for x in 30..<70 { for z in 30..<70 where scene.tiles[0][x][z]?.wall != nil { target = (0, x, z); break outer } }
		let t = try XCTUnwrap(target)
		scene.removeWall(level: t.l, x: t.x, z: t.z)
		mesh.signatureInterval = 1
		let left = mesh.update(scene: scene, focus: (t.x, t.z), timeBudget: 1, minChunks: 1000)
		XCTAssertEqual(left, 0)
		let after = mesh.chunks.map { $0?.id ?? 0 }
		var changed = 0
		for i in 0..<before.count where before[i] != after[i] { changed += 1 }
		XCTAssertEqual(changed, 1, "exactly the chunk holding the wall is rebuilt")
		let c = try XCTUnwrap(mesh.chunk(level: 0, cx: t.x / 8, cz: t.z / 8))
		XCTAssertNotEqual(before[mesh.index(0, t.x / 8, t.z / 8)], c.id)
	}
}
