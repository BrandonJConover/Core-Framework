import XCTest
@testable import RSCClassic

/// Replays tools/scenedump.c: builds the same 3D scene (client models, a textured
/// terrain grid, a translucent model, 2D sprites), renders it from several
/// cameras and compares frame hashes, draw order and mouse picks with rsc-c.
/// On a mismatch the Swift frame is written to $TMPDIR/rsc-swift-frames/<name>.raw.
final class SceneTests: XCTestCase {
    func testSceneMatchesCEngine() throws {
        let golden = String(decoding: try Data(contentsOf: TestPaths.golden.appendingPathComponent("scene.txt")),
                            as: UTF8.self).split(separator: "\n").map(String.init)
        var lines: [String] = []
        let w = 512, h = 346

        let s = Surface(width: w, height: h, limit: SpriteBase.limit)
        let gameData = try GameData(config: try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("config85.jag")),
                                    members: true, version: 85)
        let media = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("media59.jag"))
        let index = try XCTUnwrap(try media.file("index.dat"))
        var remaining = gameData.itemSpriteCount
        var file = 1
        while remaining > 0 {
            let c = min(remaining, 30)
            remaining -= 30
            let data = try XCTUnwrap(try media.file("objects\(file).dat"))
            s.parseSprite(id: SpriteBase.item + (file - 1) * 30, spriteData: data, indexData: index, frameCount: c)
            file += 1
        }
        for i in 0..<gameData.itemSpriteCount { s.loadSprite(id: SpriteBase.item + i) }

        let scene = Scene(surface: s, modelCount: 7500, polygonCount: 7500, maxSpriteCount: 1000)
        scene.setBounds(width: w, height: h - 12)
        scene.clipFar3d = 2400
        scene.clipFar2d = 2400
        scene.fogZDistance = 2300

        try MediaLoader.loadTextures(try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("textures17.jag")),
                                     into: s, scene: scene, gameData: gameData)
        for i in 0..<scene.textureCount {
            let dim = Int(scene.textureDimension[i])
            // gcc evaluates the printf arguments right to left, so the fill lookup (which loads the texture) runs first.
            let fill = scene.fillColour(i)
            var px: UInt32 = 0
            if let b = scene.texturePixels[i] {
                px = fnv1a(Array(UnsafeRawBufferPointer(start: b.pointer, count: (dim != 0 ? 128 * 128 : 64 * 64) * 16)))
            }
            lines.append("texture \(i) dim \(dim) alpha \(scene.textureBackTransparent[i] ? 1 : 0) px \(px) fill \(fill)")
        }
        lines.append("fill \(scene.fillColour(-1 - 0x1234)) \(scene.fillColour(Scene.colourTransparent)) \(Scene.rgbToFill(200, 100, 50))")

        var models: [GameModel] = []
        let jag = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("models36.jag"))
        var placed = 0
        var i = 0
        while i < gameData.modelNames.count && placed < 40 {
            defer { i += 3 }
            guard let data = try jag.file("\(gameData.modelNames[i]).ob3") else { continue }
            let m = GameModel(ob3: data).copy()
            if placed % 3 == 2 {
                m.setLight(gouraud: false, ambience: 40, diffuse: 32, x: -50, y: -10, z: -50)
            } else {
                m.setLight(gouraud: true, ambience: 48, diffuse: 48, x: -50, y: -10, z: -50)
            }
            m.orient(yaw: (placed * 29) & 255, pitch: 0, roll: 0)
            m.place(x: 3200 + (placed % 8) * 160, y: 0, z: 3200 + (placed / 8) * 160)
            if placed == 7 { m.transparent = true }
            m.depth = (placed % 5) * 3
            scene.addModel(m)
            models.append(m)
            placed += 1
        }

        let grid = GameModel(vertices: 17 * 17, faces: 16 * 16 + 8, autocommit: true, isolated: false, unlit: false,
                             unpickable: false, projected: false)
        for x in 0..<17 { for z in 0..<17 { grid.createVertex(x: 3000 + x * 128, y: ((x * 7 + z * 13) % 60) - 30, z: 3000 + z * 128) } }
        for x in 0..<16 {
            for z in 0..<16 {
                let fill = (x + z) % 3 == 0 ? (x * 5 + z) % scene.textureCount : -1 - ((x * 3 + z * 7) & 0x7fff)
                if (x * z) % 11 == 5 {
                    grid.createFace([UInt16(x * 17 + z), UInt16((x + 1) * 17 + z), UInt16((x + 1) * 17 + z + 1)],
                                    fillFront: fill, fillBack: Scene.colourTransparent)
                    continue
                }
                let f = grid.createFace([UInt16(x * 17 + z), UInt16((x + 1) * 17 + z), UInt16((x + 1) * 17 + z + 1),
                                         UInt16(x * 17 + z + 1)],
                                        fillFront: fill, fillBack: x & 1 == 1 ? fill : Scene.colourTransparent)
                grid.faceTag![f] = Int32(x * 100 + z)
            }
        }
        for i in 0..<6 {
            grid.createFace([UInt16(i * 17), UInt16(i * 17 + 1), UInt16(i * 17 + 2), UInt16((i + 1) * 17 + 2), UInt16((i + 1) * 17)],
                            fillFront: -1 - i * 1000, fillBack: -1 - i * 1000)
        }
        for i in 0..<grid.vertexCount { grid.setVertexAmbience(i, (i * 29) & 0x1f) }
        grid.setLight(gouraud: true, ambience: 40, diffuse: 48, x: -50, y: -10, z: -50)
        scene.addModel(grid)
        models.append(grid)

        for i in 0..<8 {
            let id = scene.addSprite(id: SpriteBase.item + i * 7, x: 3300 + i * 120, y: -10, z: 3500 + (i % 3) * 150,
                                     width: 90, height: 110, tag: 1000 + i)
            if i == 3 { scene.setSpriteTranslateX(id, 20) }
        }
        scene.setLocalPlayer(0)

        func modelIndex(_ m: GameModel?) -> Int {
            guard let m else { return -2 }
            if m === scene.view { return -1 }
            return models.firstIndex { $0 === m } ?? -2
        }

        func frame(_ name: String) {
            scene.render()
            let bytes = s.pixelBuffer.withMemoryRebound(to: UInt8.self) { Array($0) }
            var order: UInt32 = 2166136261
            for i in 0..<scene.visiblePolygonsCount {
                let p = scene.visiblePolygons[i]
                for v in [Int32(modelIndex(p.model)), Int32(p.face)] {
                    for b in withUnsafeBytes(of: v.littleEndian, Array.init) { order ^= UInt32(b); order = order &* 16777619 }
                }
            }
            var line = "frame \(name) \(fnv1a(bytes)) polys \(scene.visiblePolygonsCount) order \(order) picks \(scene.mousePickedCount)"
            for i in 0..<scene.mousePickedCount {
                line += " \(modelIndex(scene.mousePickedModels[i])):\(scene.mousePickedFaces[i])"
            }
            lines.append(line)
            if let expected = golden.first(where: { $0.hasPrefix("frame \(name) ") }), expected != line {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rsc-swift-frames")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? Data(bytes).write(to: dir.appendingPathComponent("\(name).raw"))
            }
        }

        s.blackScreen(); scene.setCamera(x: 3800, y: 0, z: 3700, yaw: 912, pitch: 0, roll: 0, distance: 1500); frame("overview")
        s.blackScreen(); scene.setMouseLocation(x: 256, y: 180)
        scene.setCamera(x: 3700, y: -20, z: 3500, yaw: 900, pitch: 256, roll: 0, distance: 1100); frame("rotated_pick")
        s.blackScreen(); scene.setMouseLocation(x: 300, y: 200)
        scene.setCamera(x: 3600, y: -20, z: 3600, yaw: 880, pitch: 512, roll: 0, distance: 700); frame("south_pick")
        s.blackScreen(); s.interlace = true
        scene.setCamera(x: 3800, y: 0, z: 3700, yaw: 912, pitch: 640, roll: 0, distance: 1300); frame("interlace")
        s.interlace = false
        s.blackScreen(); scene.setCamera(x: 3400, y: -60, z: 3400, yaw: 960, pitch: 128, roll: 30, distance: 260); frame("closeup_roll")
        s.blackScreen(); scene.setMouseLocation(x: 200, y: 150)
        scene.setCamera(x: 3300, y: -100, z: 3300, yaw: 800, pitch: 800, roll: 0, distance: 120); frame("near_clip")
        for i in 0..<scene.textureCount where scene.textureDimension[i] == 0 && scene.texturePixels[i] != nil {
            scene.scrollTexture(i); scene.scrollTexture(i)
        }
        scene.setLight(ambience: 30, diffuse: 60, x: -30, y: -20, z: -60)
        s.blackScreen(); scene.setCamera(x: 3800, y: 0, z: 3700, yaw: 912, pitch: 0, roll: 0, distance: 1500); frame("scrolled_relit")
        scene.reduceSprites(3)
        scene.removeModel(models[4])
        scene.removeModel(models[9])
        scene.setLightDirection(x: 0, y: 0, z: 0)
        s.blackScreen(); scene.setMouseLocation(x: 256, y: 170)
        scene.setCamera(x: 3700, y: 0, z: 3600, yaw: 912, pitch: 1000, roll: 0, distance: 1600); frame("removed")
        scene.clear()
        s.blackScreen(); scene.setCamera(x: 3800, y: 0, z: 3700, yaw: 912, pitch: 0, roll: 0, distance: 1500); frame("cleared")

        XCTAssertEqual(lines.count, golden.count)
        for (a, b) in zip(lines, golden) where a != b {
            XCTFail("swift: \(a)\n    c: \(b)")
        }
    }
}
