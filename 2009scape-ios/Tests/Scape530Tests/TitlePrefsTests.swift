import Foundation
import XCTest
@testable import Scape530

/// Preferences (rt4 `Preferences` encode/decode/toInt, packet 98, scene effects), the title screen backdrop and
/// fire (`TitleScreen`, `Flames`), the cs2 ops 5424-5426 and the title song.
final class TitlePrefsTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func emptyHost() -> InterfaceScriptHost {
		InterfaceScriptHost(store: ConfigStore(source: { _, _ in nil }))
	}

	// MARK: preferences format

	func testEncodeMatchesRt4Layout() {
		let bytes = ClientPreferences().encode()
		// rt4 `Preferences.encode`: version 11, then the fields in order, 34 bytes in all.
		XCTAssertEqual(bytes, [11, 3, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 0, 1, 127, 255, 127, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
	}

	func testRoundTrip() {
		var p = ClientPreferences()
		p.brightness = 1; p.allLevelsVisible = false; p.removeRoofsSelectively = false; p.showGroundDecorations = false
		p.highDetailTextures = false; p.manyIdleAnimations = false; p.flickeringEffects = false; p.manyGroundTextures = false
		p.characterShadows = false; p.sceneryShadows = 1; p.highDetailLighting = false; p.highWaterDetail = false
		p.fogEnabled = false; p.windowMode = 2; p.antiAliasing = 2; p.stereo = false; p.soundEffectVolume = 33
		p.musicVolume = 200; p.ambientSoundsVolume = 44; p.fullScreenWidth = 1280; p.fullScreenHeight = 720; p.particles = 1
		p.lastWorldId = 0x01020304; p.favoriteWorlds = 5; p.safeMode = true; p.unknownFlag = true; p.buildArea = 3
		p.hdr = true; p.cursorsEnabled = false
		var q = ClientPreferences()
		q.decode(p.encode())
		XCTAssertEqual(q, p)
		XCTAssertEqual(q.encode(), p.encode())
	}

	func testDecodeClampsAndAcceptsOlderVersions() {
		var p = ClientPreferences()
		var raw = ClientPreferences().encode()
		raw[1] = 0 // brightness below 1
		raw[10] = 9 // scenery shadows above 2
		raw[16] = 200 // sound effects above 127
		p.decode(raw)
		XCTAssertEqual(p.brightness, 1)
		XCTAssertEqual(p.sceneryShadows, 2)
		XCTAssertEqual(p.soundEffectVolume, 127)
		// Version 0 is 19 bytes of settings; later fields keep their defaults.
		var old = ClientPreferences()
		old.musicVolume = 10
		var v0 = Array(ClientPreferences().encode()[0..<20])
		v0[0] = 0
		v0[1] = 2
		old.decode(v0)
		XCTAssertEqual(old.brightness, 2)
		XCTAssertEqual(old.particles, 2)
		XCTAssertEqual(old.cursorsEnabled, true)
		// A short record, or an unknown version, changes nothing.
		var same = ClientPreferences()
		same.decode([11, 1, 2, 3])
		same.decode([12] + [UInt8](repeating: 0, count: 40))
		same.decode([])
		XCTAssertEqual(same, ClientPreferences())
	}

	func testToIntDefaultsAndBits() {
		var p = ClientPreferences()
		XCTAssertEqual(p.toInt(), 24_754_171)
		p.stereo = false; p.musicVolume = 0; p.particles = 0; p.brightness = 4
		XCTAssertEqual(p.toInt(), 24_754_171 - (1 << 19) - (1 << 21) - (2 << 23) + 1)
	}

	func testPacket98() {
		var enc = IsaacRandom(seed: [0, 0, 0, 0])
		var key = IsaacRandom(seed: [0, 0, 0, 0])
		let bytes = ClientMessage.preferences(0x0102_0304).encode(&enc)
		XCTAssertEqual(bytes, [UInt8(truncatingIfNeeded: 98 + key.nextKey()), 1, 2, 3, 4])
		XCTAssertEqual(ClientProt.preferences, 98)
	}

	// MARK: setter ops

	func testSettersMarkUnsentAndPersist() {
		let host = emptyHost()
		var written = 0
		host.onPreferencesWritten = { written += 1 }
		func set(_ op: Int, _ v: Int32) { _ = host.perform(HostOps.table[op]!, ints: [v], strings: []) }
		XCTAssertTrue(host.prefs.sentToServer)
		set(6007, 0)
		XCTAssertFalse(host.prefs.sentToServer)
		XCTAssertFalse(host.prefs.manyIdleAnimations)
		XCTAssertEqual(written, 1)
		host.prefs.sentToServer = true
		set(6021, 1) // neverRemoveRoofs is neither saved nor sent
		XCTAssertTrue(host.prefs.sentToServer)
		XCTAssertEqual(written, 1)
	}

	func testMenuStyleOps() {
		let host = emptyHost()
		func run(_ op: Int, _ v: [Int32]) { _ = host.perform(HostOps.table[op]!, ints: v, strings: []) }
		run(5424, [0x112233, 40, 0x445566, 90, 1, 2, 3, 4, 5, 0xFFFFFF, 0xFFFF00])
		XCTAssertEqual(host.menuStyle?.bodyColour, 0x112233)
		XCTAssertEqual(host.menuStyle?.hoverTextColour, 0xFFFF00)
		XCTAssertEqual(host.menuStyle?.bottomCorner, 5)
		run(5426, [7])
		XCTAssertEqual(host.defaultCursor, 7)
		run(5425, [])
		XCTAssertNil(host.menuStyle)
	}

	// MARK: flames

	func testFlamesGradientAndRender() {
		let f = Flames(runes: [], rng: FlameRandom(seed: 7))
		XCTAssertEqual(f.gradientColor(0), 0xBF6428)
		XCTAssertEqual(f.gradientColor(64), 0xEC963A)
		XCTAssertEqual(f.gradientColor(128), 0xF2D766)
		XCTAssertEqual(f.gradientColor(200), 0xFFF2BA)
		let bg: UInt32 = 0xFF10_2030
		var r = Raster(width: 200, height: 300, fill: bg)
		for i in 0..<80 {
			f.loop = i
			f.update(); f.update()
			f.render(into: &r, x: 20, y: 10)
		}
		var changed = 0
		for y in 10..<(10 + Flames.height) { for x in 20..<(20 + Flames.width) where r.pixels[y * 200 + x] != bg { changed += 1 } }
		XCTAssertGreaterThan(changed, 500, "fire drawn over the background")
		XCTAssertEqual(r.pixels[5 * 200 + 5], bg, "outside the block is untouched")
		XCTAssertEqual(r.pixels[(10 + 254) * 200 + 30], bg, "below the 254 rows is untouched")
	}

	// MARK: with the cache

	func testTitleScreenDrawsBackdropAndLogo() throws {
		let s = try store()
		var r = Raster(width: 765, height: 503)
		TitleScreen.draw(store: s, into: &r)
		var colours = Set<UInt32>()
		for i in stride(from: 0, to: r.pixels.count, by: 7) { colours.insert(r.pixels[i]) }
		XCTAssertGreaterThan(colours.count, 200, "titlebg drawn")
		try save(r, "title-backdrop")
	}

	func testLoginScreenShowsFlamesAndPlaysTitleSong() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		var r = try client.frame(width: 765, height: 503)
		for _ in 0..<40 { r = try client.frame(width: 765, height: 503); Thread.sleep(forTimeInterval: 0.02) }
		try save(r, "title-login-765x503")
		let wide = try client.frame(width: 852, height: 393)
		try save(wide, "title-login-852x393")
		let id = try XCTUnwrap(client.titleSongId, "archive 6 has \"scape main\"")
		let deadline = Date().addingTimeInterval(5)
		while client.audio.music.currentSongId != id && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
		XCTAssertEqual(client.audio.music.currentSongId, id, "the title song is requested at the login screen")
		// "High detail" hides the 1402 components; "Standard detail" shows the software fire in the braziers.
		XCTAssertNil(client.ui.flames)
		for c in [128, 129] { client.host.game.interfaces.hidden[744 << 16 | c] = false }
		_ = try client.frame(width: 852, height: 393)
		// Let the fire burn in on a scratch canvas, then draw the screen in its first moments (before the script's fade).
		let fire = try XCTUnwrap(client.ui.flames)
		var scratch = Raster(width: 200, height: 300)
		for i in 0..<400 { fire.loop = i; fire.update(); fire.render(into: &scratch, x: 10, y: 10) }
		let fresh = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		fresh.playsTitleMusic = false
		let t0 = Date()
		var shot = try fresh.frame(width: 852, height: 393, at: t0)
		for c in [128, 129] { fresh.host.game.interfaces.hidden[744 << 16 | c] = false }
		shot = try fresh.frame(width: 852, height: 393, at: t0.addingTimeInterval(0.02))
		let f2 = try XCTUnwrap(fresh.ui.flames)
		for i in 0..<400 { f2.loop = i; f2.update(); f2.render(into: &scratch, x: 10, y: 10) }
		for i in 2..<6 { shot = try fresh.frame(width: 852, height: 393, at: t0.addingTimeInterval(0.02 * Double(i))) }
		try save(shot, "title-login-sd-fire-852x393")
		XCTAssertEqual(fresh.ui.drawn.filter { $0.component.clientCode == 1402 }.count, 2)
		XCTAssertNotNil(client.ui.flames, "the 1402 components create the fire")
	}

	func testLoginInterfaceHasFlameComponents() throws {
		let s = try store()
		let r = InterfaceRenderer(store: s)
		var found: [String] = []
		for i in 0..<1000 {
			guard let comps = try? r.components(i) else { continue }
			for c in comps.compactMap({ $0 }) where c.clientCode == 1402 { found.append("\(i):\(c.id & 0xFFFF)") }
		}
		XCTAssertEqual(found, ["744:128", "744:129"], "the login interface has two fire components")
	}

	func testPreferencesPersistAndApply() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		client.playsTitleMusic = false
		var saved = 0
		client.onPreferencesChanged = { saved += 1 }
		func set(_ op: Int, _ v: Int32) { _ = client.host.perform(HostOps.table[op]!, ints: [v], strings: []) }
		set(6021, 0) // the login screen script leaves neverRemoveRoofs on
		set(6003, 0) // selective off
		XCTAssertEqual(client.world.roofMode, .always)
		set(6003, 1)
		XCTAssertEqual(client.world.roofMode, .selective)
		set(6021, 1)
		XCTAssertEqual(client.world.roofMode, .never)
		set(6021, 0)
		saved = 0
		set(6002, 0)
		set(6005, 0)
		set(6009, 0)
		XCTAssertEqual(client.world.sceneOptions.allLevelsVisible, false)
		XCTAssertEqual(client.world.sceneOptions.showGroundDecorations, false)
		XCTAssertEqual(client.world.sceneOptions.manyGroundTextures, false)
		XCTAssertEqual(client.world.roofMode, .always, "without all levels roofs are simply removed")
		XCTAssertEqual(saved, 3, "every setter but 6021 writes the preferences")
		// The record round-trips through the shell's storage and re-applies everything on the next launch.
		set(6001, 1)
		set(6019, 100)
		let data = client.preferencesData
		XCTAssertEqual(data.count, 34)
		let other = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		other.playsTitleMusic = false
		other.preferencesData = data
		XCTAssertEqual(other.host.prefs.brightness, 1)
		XCTAssertEqual(other.world.brightness, 0.9)
		XCTAssertEqual(other.world.sceneOptions.allLevelsVisible, false)
		XCTAssertEqual(other.audio.music.volume, 100)
		XCTAssertEqual(other.host.prefs.toInt(), client.host.prefs.toInt())
	}
}

extension WorldViewTests {
	/// Options reach the built scene (rt4 `method2742` rebuilds it): ground decorations and levels, ground textures.
	func testPreferencesChangeBuiltScene() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		client.playsTitleMusic = false
		try replay(client)
		_ = client.host.perform(HostOps.table[6021]!, ints: [0], strings: [])
		let (w, h) = (1015, 469)
		_ = try client.frame(width: w, height: h)
		client.world.finishBuild()
		func decorations() -> Int {
			guard let sc = client.world.scene else { return -1 }
			var n = 0
			for l in 0..<4 { for x in 0..<104 { for z in 0..<104 where sc.groundDecor(level: l, x: x, z: z) != nil { n += 1 } } }
			return n
		}
		func set(_ op: Int, _ v: Int32) { _ = client.host.perform(HostOps.table[op]!, ints: [v], strings: []) }
		let before = decorations()
		let builds = client.world.buildCount
		set(6005, 0)
		client.world.finishBuild()
		XCTAssertGreaterThan(client.world.buildCount, builds, "the scene is rebuilt")
		XCTAssertLessThan(decorations(), before, "decorative ground locs are skipped")
		set(6005, 1)
		client.world.finishBuild()
		XCTAssertEqual(decorations(), before)
		// Ground textures draw as flat colours.
		var textured = Raster(width: w, height: h)
		XCTAssertTrue(client.world.draw(into: &textured, rect: (0, 0, w, h)))
		set(6009, 0)
		var flat = Raster(width: w, height: h)
		XCTAssertTrue(client.world.draw(into: &flat, rect: (0, 0, w, h)))
		XCTAssertNotEqual(textured.pixels, flat.pixels)
		XCTAssertEqual(client.world.scene?.manyGroundTextures, false)
		// Always-remove roofs hides every roof above the player.
		set(6009, 1)
		set(6003, 0)
		var always = Raster(width: w, height: h)
		XCTAssertTrue(client.world.draw(into: &always, rect: (0, 0, w, h)))
		XCTAssertEqual(client.world.roofs.mode, .always)
		var hidden = 0
		for l in 1...3 { for x in 0..<104 { for z in 0..<104 where client.world.roofs.mask[l][x][z] == client.world.roofs.hideValue { hidden += 1 } } }
		XCTAssertGreaterThan(hidden, 0)
	}
}
