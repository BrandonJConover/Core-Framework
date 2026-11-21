import XCTest
@testable import RSCClassic

/// Replays tools/modeldump.c: every client model through load, light, transform,
/// project, commit, merge and split, compared with rsc-c by hash.
final class GameModelTests: XCTestCase {
    static let animated = ["torcha2", "torcha3", "torcha4", "skulltorcha2", "skulltorcha3", "skulltorcha4", "firea2",
                           "firea3", "fireplacea2", "fireplacea3", "firespell2", "firespell3", "lightning2", "lightning3",
                           "clawspell2", "clawspell3", "clawspell4", "clawspell5", "spellcharge2", "spellcharge3"]

    private var lines: [String] = []

    private func h<T>(_ b: Buf<T>?, _ n: Int) -> UInt32 {
        guard let b else { return 0 }
        return fnv1a(Array(UnsafeRawBufferPointer(start: b.pointer, count: n * MemoryLayout<T>.size)))
    }

    private func dump(_ tag: String, _ i: Int, _ m: GameModel) {
        let v = m.vertexCount, f = m.faceCount
        var fv = [UInt8]()
        for i in 0..<f { for j in 0..<Int(m.faceVertexCount[i]) { let x = m.faceVertices[i][j]; fv += [UInt8(x & 0xff), UInt8(x >> 8)] } }
        var s = "\(tag) \(i) v\(v) f\(f) vx\(h(m.vertexX, v)) vy\(h(m.vertexY, v)) vz\(h(m.vertexZ, v))"
        s += " tx\(h(m.vertexTransformedX, v)) ty\(h(m.vertexTransformedY, v)) tz\(h(m.vertexTransformedZ, v))"
        s += " fv\(fnv1a(fv)) ff\(h(m.faceFillFront, f)) fb\(h(m.faceFillBack, f)) fi\(h(m.faceIntensity, f))"
        s += " vi\(h(m.vertexIntensity, v)) va\(h(m.vertexAmbience, v)) nx\(h(m.faceNormalX, f)) ny\(h(m.faceNormalY, f))"
        s += " nz\(h(m.faceNormalZ, f)) ns\(h(m.normalScale, f)) nm\(h(m.normalMagnitude, f))"
        s += " b\(m.minX),\(m.maxX),\(m.minY),\(m.maxY),\(m.minZ),\(m.maxZ) vis\(m.visible ? 1 : 0)"
        if m.projectVertexX != nil {
            s += " px\(h(m.projectVertexX, v)) py\(h(m.projectVertexY, v)) pz\(h(m.projectVertexZ, v)) wx\(h(m.vertexViewX, v)) wy\(h(m.vertexViewY, v))"
        }
        lines.append(s)
    }

    func testModelsMatchCEngine() throws {
        let golden = String(decoding: try Data(contentsOf: TestPaths.golden.appendingPathComponent("models.txt")),
                            as: UTF8.self).split(separator: "\n").map(String.init)
        var gameData = try GameData(config: try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("config85.jag")),
                                    members: true, version: 85)
        for name in Self.animated { _ = gameData.modelIndex(name) }
        let jag = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("models36.jag"))

        var models: [GameModel] = []
        for (i, name) in gameData.modelNames.enumerated() {
            let m: GameModel
            if let data = try jag.file("\(name).ob3") { m = GameModel(ob3: data) } else { m = GameModel(vertices: 1, faces: 1) }
            models.append(m)
            dump("load", i, m)
        }
        for (i, model) in models.enumerated() {
            let c = model.copy()
            c.setLight(gouraud: true, ambience: 48, diffuse: 48, x: -50, y: -10, z: -50)
            c.orient(yaw: (i * 37) & 255, pitch: 0, roll: (i * 11) & 255)
            c.place(x: 1000 + i * 3, y: -200, z: 3000 - i * 5)
            c.apply(); dump("lit", i, c)
            c.projectView(cameraX: 800, cameraY: -500, cameraZ: 1500, pitch: 912, roll: 0, yaw: 0, viewDistance: 512, clipNear: 5)
            dump("proj", i, c)
            let d = model.copy(autocommit: false, isolated: false, unlit: false, unpickable: true)
            d.setLight(gouraud: false, ambience: 60, diffuse: 24, x: -50, y: -10, z: -50)
            d.rotate(yaw: 0, pitch: (i * 5) & 255, roll: 0)
            d.commit(); dump("commit", i, d)
        }
        let pieces = (0..<12).map { models[$0 * 7 % models.count] }
        dump("merge", 0, GameModel(merging: pieces))

        let grid = GameModel(vertices: 33 * 33, faces: 32 * 32, autocommit: true, isolated: false, unlit: false,
                             unpickable: false, projected: true)
        for x in 0..<33 { for z in 0..<33 { grid.createVertex(x: x * 128, y: ((x * 7 + z * 13) % 50) - 25, z: z * 128) } }
        for x in 0..<32 {
            for z in 0..<32 {
                let v = [x * 33 + z, (x + 1) * 33 + z, (x + 1) * 33 + z + 1, x * 33 + z + 1].map { UInt16($0) }
                let f = grid.createFace(v, fillFront: -1 - ((x * 3 + z) & 0x7fff), fillBack: GameModel.colourTransparent)
                grid.faceTag![f] = Int32(x * 100 + z)
            }
        }
        for i in 0..<grid.vertexCount { grid.setVertexAmbience(i, (i * 29) & 0xff) }
        grid.setLight(gouraud: true, ambience: 40, diffuse: 48, x: -50, y: -10, z: -50); dump("grid", 0, grid)
        let split = grid.split(pieceDX: 1024, pieceDZ: 1024, rows: 4, count: 16, pieceMaxVertices: 500, pickable: false)
        for (i, p) in split.enumerated() {
            dump("split", i, p)
            lines.append("tag \(i) \(h(p.faceTag, p.faceCount))")
        }
        let mk = models[5].copy()
        GameModel.maskFaces(mk.faceFillFront, count: mk.faceCount, maskColour: 0xff8040); dump("mask", 0, mk)

        XCTAssertEqual(lines.count, golden.count)
        var failures = 0
        for (i, (a, e)) in zip(lines, golden).enumerated() where a != e {
            XCTFail("line \(i + 1):\n  swift: \(a)\n  c:     \(e)")
            failures += 1
            if failures > 8 { break }
        }
    }
}
