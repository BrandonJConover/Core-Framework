import XCTest
@testable import RSCClassic

/// Every definition must match what rsc-c's game_data_load_data parses
/// (golden dumps made by tools/gamedata.c, same line format).
final class GameDataTests: XCTestCase {
    func testMembersMatchesCEngine() throws { try compare(members: true, golden: "gamedata-members.txt") }
    func testFreeMatchesCEngine() throws { try compare(members: false, golden: "gamedata-free.txt") }

    private func compare(members: Bool, golden: String) throws {
        let config = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("config85.jag"))
        let data = try GameData(config: config, members: members, version: 85)
        let expected = String(decoding: try Data(contentsOf: TestPaths.golden.appendingPathComponent(golden)),
                                  as: Latin1.self).split(separator: "\n").map(String.init)
        let actual = dump(data)
        XCTAssertEqual(actual.count, expected.count)
        for (i, (a, e)) in zip(actual, expected).enumerated() where a != e {
            XCTFail("line \(i + 1):\n  swift: \(a)\n  c:     \(e)")
            return
        }
    }

    private func dump(_ g: GameData) -> [String] {
        var out = ["items \(g.items.count)"]
        for (i, it) in g.items.enumerated() {
            out.append("item \(i)|\(it.name)|\(it.description)|\(it.command)|\(it.sprite)|\(it.basePrice)|\(it.stackable)|\(it.wearable)|\(it.mask)|\(it.special)|\(it.members)")
        }
        out.append("npcs \(g.npcs.count)")
        for (i, n) in g.npcs.enumerated() {
            let sprites = n.sprites.map { "\($0)," }.joined()
            out.append("npc \(i)|\(n.name)|\(n.description)|\(n.attack)|\(n.strength)|\(n.hits)|\(n.defense)|\(n.attackable)|\(sprites)|\(n.hairColour)|\(n.topColour)|\(n.bottomColour)|\(n.skinColour)|\(n.width)|\(n.height)|\(n.walkSpeed)|\(n.combatSpeed)|\(n.combatWidth)|\(n.command)")
        }
        out.append("textures \(g.textures.count)")
        for (i, t) in g.textures.enumerated() { out.append("texture \(i)|\(t.name)|\(t.subtypeName)") }
        out.append("animations \(g.animations.count)")
        for (i, a) in g.animations.enumerated() {
            out.append("animation \(i)|\(a.name)|\(a.colour)|\(a.gender)|\(a.hasA)|\(a.hasF)|\(a.fileId)")
        }
        out.append("objects \(g.objects.count)")
        for (i, o) in g.objects.enumerated() {
            out.append("object \(i)|\(o.name)|\(o.description)|\(o.command1)|\(o.command2)|\(o.modelIndex)|\(o.width)|\(o.height)|\(o.type)|\(o.elevation)")
        }
        out.append("models \(g.modelNames.count)")
        for (i, m) in g.modelNames.enumerated() { out.append("model \(i)|\(m)") }
        out.append("walls \(g.walls.count)")
        for (i, w) in g.walls.enumerated() {
            out.append("wall \(i)|\(w.name)|\(w.description)|\(w.command1)|\(w.command2)|\(w.height)|\(w.textureFront)|\(w.textureBack)|\(w.blocking)|\(w.interactive)")
        }
        out.append("roofs \(g.roofs.count)")
        for (i, r) in g.roofs.enumerated() { out.append("roof \(i)|\(r.height)|\(r.fill)") }
        out.append("tiles \(g.tiles.count)")
        for (i, t) in g.tiles.enumerated() { out.append("tile \(i)|\(t.decoration)|\(t.type)|\(t.blocking)") }
        out.append("projectile \(g.projectileSprite)")
        out.append("spells \(g.spells.count)")
        for (i, s) in g.spells.enumerated() {
            let runes = (0..<s.runesRequired).map { j -> String in
                let rune = j < s.runes.count ? s.runes[j] : SpellConfig.Rune()
                return "\(rune.id):\(rune.count),"
            }.joined()
            out.append("spell \(i)|\(s.name)|\(s.description)|\(s.level)|\(s.runesRequired)|\(s.type)|\(runes)")
        }
        out.append("prayers \(g.prayers.count)")
        for (i, p) in g.prayers.enumerated() { out.append("prayer \(i)|\(p.name)|\(p.description)|\(p.level)|\(p.drain)") }
        return out
    }
}
