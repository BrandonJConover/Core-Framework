import Foundation

/// Paths shared by the tests. The game cache is the one bundled with the
/// C engine (RSCEngine/rsc-cache), so both ports read identical data.
enum TestPaths {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let cache = packageRoot.deletingLastPathComponent()
        .appendingPathComponent("RSCEngine/rsc-cache")
    static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Golden")
}

func fnv1a(_ bytes: [UInt8]) -> UInt32 {
    var h: UInt32 = 2166136261
    for b in bytes {
        h ^= UInt32(b)
        h = h &* 16777619
    }
    return h
}

@testable import RSCClassic

/// Mirrors tools/common.h's setup_scene: a 512x346 surface with the item sprites
/// and a scene with every texture loaded.
func makeTestScene(gameData: GameData) throws -> (Surface, Scene) {
    let w = 512, h = 346
    let s = Surface(width: w, height: h, limit: SpriteBase.limit)
    let media = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("media59.jag"))
    guard let index = try media.file("index.dat") else { throw MediaError.missing("index.dat") }
    var remaining = gameData.itemSpriteCount
    var file = 1
    while remaining > 0 {
        let c = min(remaining, 30)
        remaining -= 30
        guard let data = try media.file("objects\(file).dat") else { throw MediaError.missing("objects\(file).dat") }
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
    return (s, scene)
}

func goldenLines(_ name: String) throws -> [String] {
    String(decoding: try Data(contentsOf: TestPaths.golden.appendingPathComponent(name)), as: UTF8.self)
        .split(separator: "\n").map(String.init)
}
