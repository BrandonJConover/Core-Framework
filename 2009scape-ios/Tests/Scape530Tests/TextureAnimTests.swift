import Foundation
import XCTest
@testable import Scape530

/// Texture generation and animation frame decoding against the real cache.
final class TextureAnimTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func testEveryTextureGenerates() throws {
		let cfg = try store()
		let ts = try TextureStore(config: cfg)
		let ids = ts.definedIds
		XCTAssertGreaterThan(ids.count, 0)
		var failures: [String] = []
		var ok = 0
		var opUse: [Int: Int] = [:]
		var sheet: [Int: [Int32]] = [:]
		for id in ids {
			if let g = try? ts.graph(id) { for t in g.opTypes { opUse[t, default: 0] += 1 } }
			do {
				guard let px = try ts.generate(id, brightness: 0.7) else { failures.append("tex \(id): no data"); continue }
				XCTAssertEqual(px.count, ts.isLowDetail(id) ? 4096 : 16384)
				ok += 1
				if sheet.count < 64 { sheet[id] = px }
			} catch { failures.append("tex \(id): \(error)") }
		}
		print("generated \(ok) of \(ids.count) textures; failures: \(failures)")
		print("op type usage (textures per op): \(opUse.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" })")
		XCTAssertEqual(failures, [])

		// contact sheet of the first 64 defined textures, 8 per row
		let cell = 130
		var r = Raster(width: 8 * cell, height: 8 * cell, fill: 0x202020)
		for (n, id) in ids.prefix(64).enumerated() {
			guard let px = sheet[id] else { continue }
			let s = ts.isLowDetail(id) ? 64 : 128
			let ox = (n % 8) * cell + 1, oy = (n / 8) * cell + 1
			for y in 0..<s { for x in 0..<s {
				let c = UInt32(bitPattern: px[y * s + x]) & 0xFFFFFF
				r.pixels[(oy + y) * r.width + ox + x] = 0xFF000000 | c
			} }
		}
		if let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] {
			try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent("textures-contact.png"))
			print("first 64 texture ids: \(ids.prefix(64).map { $0 })")
		}
	}

	func testAverageColourAndFlags() throws {
		let ts = try TextureStore(config: try store())
		let id = try XCTUnwrap(ts.definedIds.first)
		XCTAssertNotNil(ts.texels(id, brightness: 0.8))
		XCTAssertFalse(ts.definedIds.isEmpty)
	}

	func testEveryFramesetDecodes() throws {
		let cfg = try store()
		// every frameset group in the animation archive decodes
		let idx = try cfg.index(ConfigStore.AnimArchive.frames)
		var failures: [String] = []
		var frames = 0
		for g in idx.groupIds {
			do { frames += try cfg.animFrameset(g)?.frames.compactMap { $0 }.count ?? 0 } catch { failures.append("group \(g): \(error)") }
		}
		print("decoded \(idx.groupIds.count) framesets, \(frames) frames; failures \(failures.count)")
		XCTAssertEqual(failures, [])
	}

	func testSeqFramesetsDecode() throws {
		let cfg = try store()
		var seqs = 0, refs = 0, missing: [String] = [], failures: [String] = []
		var id = 0
		var misses = 0, none = 0
		while misses < 2000 && id < 20000 {
			guard let seq = try cfg.seq(id) else { misses += 1; id += 1; continue }
			misses = 0
			seqs += 1
			for packed in seq.frames + (seq.frameset ?? []) {
				refs += 1
				// file id 0xFFFF is rt4's "no frame" marker
				if packed & 0xFFFF == 0xFFFF { none += 1; continue }
				do {
					guard let f = try cfg.animFrame(packed: packed) else { missing.append("seq \(id) frame \(packed >> 16):\(packed & 0xFFFF)"); continue }
					XCTAssertEqual(f.indices.count, f.length)
					XCTAssertEqual(f.x.count, f.length)
				} catch { failures.append("seq \(id): \(error)") }
			}
			id += 1
		}
		print("seqs \(seqs), frame refs \(refs) (\(none) are the 0xFFFF no-frame marker), missing \(missing.count), failures \(failures.count)")
		print("sample missing: \(missing.prefix(5))")
		XCTAssertEqual(failures, [])
		XCTAssertEqual(missing, [])
		XCTAssertGreaterThan(seqs, 0)
	}
}
