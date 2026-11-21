import XCTest
@testable import RSCClassic

/// Replays tools/worlddump.c: loads the login-screen area and a few in-game map
/// sections, then compares terrain/wall/roof models, adjacency, minimap,
/// rendered frames and routes with rsc-c.
final class WorldTests: XCTestCase {
    private var lines: [String] = []

    private func h<T>(_ b: Buf<T>?, _ n: Int) -> UInt32 {
        guard n > 0 else { return 2166136261 }
        guard let b else { return 0 }
        return fnv1a(Array(UnsafeRawBufferPointer(start: b.pointer, count: n * MemoryLayout<T>.size)))
    }

    private func h<T>(_ a: [T]) -> UInt32 {
        a.withUnsafeBytes { fnv1a(Array($0)) }
    }

    /// C's `int` arrays are 4 bytes per element; Swift's Int is 8.
    private func h32(_ a: [Int]) -> UInt32 { h(a.map { Int32(truncatingIfNeeded: $0) }) }

    private func mdump(_ tag: String, _ p: Int, _ i: Int, _ m: GameModel?) {
        guard let m else { lines.append("\(tag) \(p) \(i) null"); return }
        let v = m.vertexCount, f = m.faceCount
        var fv = [UInt8]()
        for i in 0..<f { for j in 0..<Int(m.faceVertexCount[i]) { let x = m.faceVertices[i][j]; fv += [UInt8(x & 0xff), UInt8(x >> 8)] } }
        var s = "\(tag) \(p) \(i) v\(v) f\(f) vx\(h(m.vertexX, v)) vy\(h(m.vertexY, v)) vz\(h(m.vertexZ, v))"
        s += " va\(h(m.vertexAmbience, v)) vi\(h(m.vertexIntensity, v)) fv\(fnv1a(fv)) ff\(h(m.faceFillFront, f))"
        s += " fb\(h(m.faceFillBack, f)) fi\(h(m.faceIntensity, f)) ft\(m.faceTag != nil ? h(m.faceTag, f) : 0)"
        lines.append(s)
    }

    func testWorldMatchesCEngine() throws {
        let golden = try goldenLines("world.txt")
        var gameData = try GameData(config: try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("config85.jag")),
                                    members: true, version: 85)
        for name in GameModelTests.animated { _ = gameData.modelIndex(name) }
        let (s, scene) = try makeTestScene(gameData: gameData)

        let rng = CRandom.shared
        rng.seed(1)
        let r1 = rng.next(), r2 = rng.next(), r3 = rng.next()
        rng.seed(4321)
        lines.append("rand \(r1) \(r2) \(r3) \(rng.next())")
        lines.append("terrain_colours \(h(World.terrainColours))")

        let jag = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("models36.jag"))
        let models: [GameModel] = try gameData.modelNames.map { name in
            if let data = try jag.file("\(name).ob3") { return GameModel(ob3: data) }
            return GameModel(vertices: 1, faces: 1)
        }

        let world = World(scene: scene, surface: s, gameData: gameData, version: 63)
        world.baseMediaSprite = SpriteBase.media
        func pack(_ n: String) throws -> JagArchive { try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent(n)) }
        world.mapPack = try pack("maps63.jag")
        world.memberMapPack = try pack("maps63.mem")
        world.landscapePack = try pack("land63.jag")
        world.memberLandscapePack = try pack("land63.mem")

        func wdump(_ name: String) {
            for i in 0..<World.terrainCount { mdump("terrain", 0, i, world.terrainModels[i]) }
            for p in 0..<World.planeCount { for i in 0..<World.terrainCount where world.wallModels[p][i] != nil { mdump("wall", p, i, world.wallModels[p][i]) } }
            for p in 0..<World.planeCount { for i in 0..<World.terrainCount where world.roofModels[p][i] != nil { mdump("roof", p, i, world.roofModels[p][i]) } }
            let mm = world.baseMediaSprite - 1
            let minimap = s.spritePixels[mm].map { h($0) } ?? 0
            var line = "world \(name) adj \(h32(world.objectAdjacency)) thl \(h32(world.terrainHeightLocal))"
            line += " lx \(h32(world.localX)) ly \(h32(world.localY)) models \(scene.modelCount)"
            line += " minimap \(minimap) \(s.spriteWidth[mm])x\(s.spriteHeight[mm])"
            lines.append(line)
            lines.append("planes \(name) td \(h(world.tileDecoration)) tdir \(h(world.tileDirection)) wd \(h(world.wallsDiagonal))" +
                         " wr \(h(world.wallsRoof)) th \(h(world.terrainHeight)) tc \(h(world.terrainColour))")
            var e = "elev \(name)"
            for i in 0..<12 { e += " \(world.elevation((i * 977) % 12288, (i * 1361 + 400) % 12288))" }
            e += " roof"
            for i in 0..<12 { e += " \(world.isUnderRoof((i * 733) % 12288, (i * 1201) % 12288) ? 1 : 0)" }
            lines.append(e)
        }

        func frame(_ name: String, _ x: Int, _ y: Int, _ rot: Int, _ zoom: Int) {
            s.blackScreen()
            scene.setCamera(x: x, y: -world.elevation(x, y), z: y, yaw: 912, pitch: rot, roll: 0, distance: zoom)
            scene.render()
            let bytes = s.pixelBuffer.withMemoryRebound(to: UInt8.self) { Array($0) }
            lines.append("frame \(name) \(fnv1a(bytes)) polys \(scene.visiblePolygonsCount)")
            if let expected = golden.first(where: { $0.hasPrefix("frame \(name) ") }), expected != lines.last {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rsc-swift-frames")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? Data(bytes).write(to: dir.appendingPathComponent("\(name).raw"))
            }
        }

        var rx = [Int](repeating: 0, count: World.pathStepsMax), ry = rx
        func route(_ sx: Int, _ sy: Int, _ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ obj: Bool) {
            let n = world.route(startX: sx, startY: sy, endX1: x1, endY1: y1, endX2: x2, endY2: y2,
                                routeX: &rx, routeY: &ry, objects: obj)
            var line = "route \(sx),\(sy)->\(x1),\(y1)..\(x2),\(y2) \(obj ? 1 : 0) \(n):"
            for i in 0..<max(n, 0) { line += " \(rx[i]),\(ry[i])" }
            lines.append(line)
        }

        rng.seed(4321)
        world.loadSection(x: 50 * 48 + 23, y: 50 * 48 + 23, plane: 0)
        world.addModels(models)
        scene.clipFar3d = 4100; scene.clipFar2d = 4100; scene.fogZDistance = 4000
        wdump("login")
        frame("login1", 9728, 6400, 888, 2200)
        frame("login2", 9216, 9216, 888, 2200)

        scene.clipFar3d = 2400; scene.clipFar2d = 2400; scene.fogZDistance = 2300
        world.loadSection(x: 2304 + 120, y: 1776 + 650, plane: 0)
        wdump("lumbridge")
        frame("lumbridge1", 6144, 6144, 0, 1500)
        frame("lumbridge2", 5800, 6500, 512, 1200)
        route(48, 48, 48, 48, 48, 48, false)
        route(48, 48, 60, 40, 60, 40, false)
        route(48, 48, 30, 70, 31, 71, true)
        route(40, 50, 90, 10, 90, 10, false)
        route(10, 10, 85, 85, 85, 85, false)
        world.registerObject(x: 44, y: 44, id: 1)
        world.registerWallObject(x: 46, y: 46, dir: 0, id: 1)
        world.registerWallObject(x: 47, y: 47, dir: 3, id: 2)
        lines.append("objects adj \(h32(world.objectAdjacency))")
        for i in 0..<World.terrainCount where i % 9 == 4 { mdump("shadow", 0, i, world.terrainModels[i]) }
        route(40, 40, 52, 52, 52, 52, false)
        world.removeObject(x: 44, y: 44, id: 1)
        world.removeWallObject(x: 46, y: 46, dir: 0, id: 1)
        world.removeWallObject(x: 47, y: 47, dir: 3, id: 2)
        lines.append("removed adj \(h32(world.objectAdjacency))")

        world.loadSection(x: 2304 + 120, y: 1776 + 650, plane: 1)
        wdump("upstairs")
        frame("upstairs1", 6144, 6144, 256, 1500)

        world.loadSection(x: 2304 + 130, y: 1776 + 500, plane: 0)
        wdump("varrock")
        frame("varrock1", 6144, 6144, 128, 1800)

        XCTAssertEqual(lines.count, golden.count)
        var failures = 0
        for (a, b) in zip(lines, golden) where a != b {
            failures += 1
            if failures <= 25 { XCTFail("swift: \(a)\n    c: \(b)") }
        }
        XCTAssertEqual(failures, 0)
    }
}
