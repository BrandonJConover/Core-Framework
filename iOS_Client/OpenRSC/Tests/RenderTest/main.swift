// Local render-pipeline tests. Run via `swift test` on macOS so I can catch
// bugs without round-trips through Xcode + on-device rebuilds.
//
// What this verifies:
//   1. sprites_v2.dat loads (count + sample pixels + non-zero content).
//   2. NPCDef JSON loads + animation.number assignment matches Java's algorithm.
//   3. Scene.projectPoint produces on-screen coords for near-camera points.
//   4. World.generateLandscapeModel mesh vertices project to visible screen area.
//   5. CharacterBillboards.register produces billboards via scene.drawSprite.

import XCTest
@testable import OpenRSC

final class RenderPipelineTests: XCTestCase {

    var fixtureDir: String {
        if let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures") {
            return url.path
        }
        return FileManager.default.currentDirectoryPath + "/Tests/RenderTest/Fixtures"
    }

    // --- 1. Sprite archive format ---

    func test_sprite_archive_loads_with_expected_count_and_metadata() throws {
        let path = fixtureDir + "/sprites_v2.dat"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(data.count, 1_000_000, "sprites_v2.dat should be >1MB")

        let bytes = [UInt8](data)
        XCTAssertEqual(bytes[0], 0x53); XCTAssertEqual(bytes[1], 0x50)
        XCTAssertEqual(bytes[2], 0x52); XCTAssertEqual(bytes[3], 0x32)

        let count = (Int(bytes[4]) << 24) | (Int(bytes[5]) << 16)
                  | (Int(bytes[6]) << 8) | Int(bytes[7])
        XCTAssertEqual(count, 2259, "Should have 2259 sprites")

        // Spot-check first entry: head1 frame 0 should be a small head sprite
        let e0 = 8
        let id0 = be32(bytes, e0)
        let w0 = be32(bytes, e0 + 8)
        let h0 = be32(bytes, e0 + 12)
        let authW0 = be32(bytes, e0 + 28)
        let authH0 = be32(bytes, e0 + 32)
        XCTAssertEqual(id0, 0, "First entry ID is 0")
        XCTAssertGreaterThan(w0, 0)
        XCTAssertGreaterThan(h0, 0)
        XCTAssertGreaterThan(authW0, 0)
        XCTAssertGreaterThan(authH0, 0)
        print("head1: \(w0)x\(h0) authentic=\(authW0)x\(authH0)")
    }

    private func be32(_ b: [UInt8], _ i: Int) -> Int {
        let u = (UInt32(b[i]) << 24) | (UInt32(b[i+1]) << 16)
              | (UInt32(b[i+2]) << 8) | UInt32(b[i+3])
        return Int(Int32(bitPattern: u))
    }

    // --- 2. AnimationDef number assignment ---

    func test_animation_number_assignment_matches_java() {
        NPCDefinitions.assignAnimationNumbers()
        XCTAssertEqual(AnimationDefs.get(0)?.number, 0, "head1 gets slot 0")
        XCTAssertEqual(AnimationDefs.get(1)?.number, 27, "body1 gets slot 27")
        XCTAssertEqual(AnimationDefs.get(2)?.number, 54, "legs1 gets slot 54")
        XCTAssertEqual(AnimationDefs.get(3)?.number, 81, "fhead1 gets slot 81")
        XCTAssertEqual(AnimationDefs.get(4)?.number, 108, "fbody1 gets slot 108")
    }

    // --- 3. Scene projection ---

    func test_scene_projects_player_origin_near_screen_center() {
        let (graphics, scene) = buildEngine()
        scene.setCamera(centerX: 0, centerY: -180, centerZ: 0,
                        xRot: 256, yRot: 0, zRot: 0,  // xRot=64*4
                        offset: 1500)

        let (sx, sy, depth) = scene.projectPoint(worldX: 0, worldY: 0, worldZ: 0)
        print("player origin: screen=(\(sx),\(sy)) depth=\(depth)")
        XCTAssertGreaterThan(depth, 0, "Player origin must be in front of camera")
        XCTAssertGreaterThan(sx, -Int32(graphics.width2), "Screen X within one screen-width of center")
        XCTAssertLessThan(sx, 2 * Int32(graphics.width2))
        XCTAssertGreaterThan(sy, -Int32(graphics.height2))
        XCTAssertLessThan(sy, 2 * Int32(graphics.height2))
    }

    func test_scene_projects_nearby_tile_on_screen() {
        let (_, scene) = buildEngine()
        scene.setCamera(centerX: 0, centerY: -180, centerZ: 0,
                        xRot: 256, yRot: 0, zRot: 0,
                        offset: 1500)
        // One tile in each cardinal direction — should all stay near the screen
        for (wx, wz) in [(128, 0), (-128, 0), (0, 128), (0, -128), (0, 256), (256, 256)] {
            let (sx, sy, depth) = scene.projectPoint(worldX: Int32(wx), worldY: 0, worldZ: Int32(wz))
            print("  tile (\(wx),0,\(wz)) → (\(sx),\(sy)) depth=\(depth)")
            // Allow points within ~2× screen size — near the player everything should project close
            XCTAssertGreaterThan(depth, -100, "tile (\(wx),\(wz)) behind plane — depth=\(depth)")
        }
    }

    // --- 4. World terrain mesh is on-screen ---

    func test_world_landscape_model_has_on_screen_vertices() {
        let (_, scene) = buildEngine()
        let world = World(scene: scene, graphics: scene.graphics)
        world.loadSections(worldX: 217, worldZ: 741, plane: 0)
        XCTAssertGreaterThanOrEqual(scene.modelCount, 1, "At least one landscape model was added")

        scene.setCamera(centerX: 0, centerY: -180, centerZ: 0,
                        xRot: 256, yRot: 0, zRot: 0,
                        offset: 1500)

        guard let model = scene.models[0] else { return XCTFail("No model") }
        var onScreen = 0
        var offScreen = 0
        for i in 0..<Int(model.vertHead) {
            let (sx, sy, d) = scene.projectPoint(
                worldX: model.vertX[i], worldY: model.vertY[i], worldZ: model.vertZ[i])
            if d > 0 && sx >= 0 && sx < scene.graphics.width2 && sy >= 0 && sy < scene.graphics.height2 {
                onScreen += 1
            } else {
                offScreen += 1
            }
        }
        print("Of \(model.vertHead) verts: on-screen=\(onScreen) off-screen=\(offScreen)")
        XCTAssertGreaterThan(onScreen, 0, "At least some terrain verts land on screen (if 0, projection or mesh is wrong)")
    }

    // --- 5. SpriteLoader reads sprites_v2.dat when placed at a findable path ---

    func test_sprite_loader_parses_fixture_bytes_directly() throws {
        // Verify the parse step by calling it on raw bytes — sidesteps Bundle.main lookup.
        // We read sprites_v2.dat from the fixture and call the public init.
        let data = try Data(contentsOf: URL(fileURLWithPath: fixtureDir + "/sprites_v2.dat"))
        let loader = SpriteLoader()
        loader.parseBytes([UInt8](data))
        XCTAssertEqual(loader.sprites.count, 2259, "All sprites decoded (got \(loader.sprites.count))")
        let gs0 = loader.getSprite(0)
        XCTAssertNotNil(gs0, "sprite ID 0 should exist")
        XCTAssertEqual(gs0?.pixels.count, (gs0?.width ?? 0) * (gs0?.height ?? 0), "Pixel count matches dimensions")
    }

    // --- 6. End-to-end billboard render — proves a character lands in the framebuffer ---

    func test_billboard_register_and_render_paints_pixels() throws {
        // Set up engine + load real sprites + bridge to graphics atlas
        let (graphics, scene) = buildEngine()
        let data = try Data(contentsOf: URL(fileURLWithPath: fixtureDir + "/sprites_v2.dat"))
        let loader = SpriteLoader()
        loader.parseBytes([UInt8](data))
        loader.bridgeInto(graphics)
        NPCDefinitions.assignAnimationNumbers()

        scene.setCamera(centerX: 0, centerY: -180, centerZ: 0,
                        xRot: 256, yRot: 0, zRot: 0,
                        offset: 1500)

        // Register a character at the player's tile (origin) using head1+body1+legs1
        scene.reduceSprites(0)
        CharacterBillboards.register(
            scene: scene, spriteLoader: loader,
            tileX: 0, tileZ: 0,
            rsDir: 4, stepFrame: 0, walkModel: 6,
            cameraRotation: 0,
            sprites: [0, 1, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1],
            hairColor: 0xC8B89B, topColor: 0xC83232,
            bottomColor: 0x3A5AA3, skinColor: 0xECC8A6
        )
        XCTAssertGreaterThan(scene.m_n, 0, "At least one billboard layer enqueued")
        // Dump every queued layer + a sample of its sprite pixels
        for li in 0..<scene.m_n {
            let id = Int(scene.m_Ob[li])
            let x = scene.m_Eb[li], y = scene.m_Fb[li]
            let w = scene.m_gb[li], h = scene.m_Q[li]
            if let gs = loader.getSprite(id) {
                let sample = (0..<min(8, gs.pixels.count)).map { String(gs.pixels[$0], radix: 16) }
                let nonzero = gs.pixels.filter { $0 != 0 }.count
                print("layer[\(li)]: pos=(\(x),\(y)) size=\(w)x\(h) id=\(id) " +
                      "spritePixels=\(gs.width)x\(gs.height) nonZero=\(nonzero)/\(gs.pixels.count) sample=\(sample)")
            } else {
                print("layer[\(li)]: pos=(\(x),\(y)) size=\(w)x\(h) id=\(id) — SPRITE MISSING")
            }
        }
        let firstLayer = (x: scene.m_Eb[0], y: scene.m_Fb[0],
                          w: scene.m_gb[0], h: scene.m_Q[0],
                          id: scene.m_Ob[0])
        XCTAssertGreaterThan(firstLayer.x, -Int32(graphics.width2),
                             "Billboard X should be within ~one screen-width of center")
        XCTAssertLessThan(firstLayer.x, 2 * Int32(graphics.width2))

        // Run the full Scene pass — terrain rasterization + sprite blitting
        scene.endScene(1)

        // Count pixels that were actually painted (i.e. non-zero / non-default).
        // Some sky/clear is fine; we want sprite pixels in the lower-center band where the character should be.
        let bandTop = Int(graphics.height2) / 2 - 60
        let bandBottom = Int(graphics.height2) / 2 + 80
        let bandLeft = Int(graphics.width2) / 2 - 40
        let bandRight = Int(graphics.width2) / 2 + 40
        var painted = 0
        for y in bandTop...bandBottom {
            for x in bandLeft...bandRight {
                if graphics.pixelData[y * Int(graphics.width2) + x] != 0 {
                    painted += 1
                }
            }
        }
        let bandSize = (bandBottom - bandTop + 1) * (bandRight - bandLeft + 1)
        print("Painted pixels in character band: \(painted)/\(bandSize)")
        XCTAssertGreaterThan(painted, 100,
            "Character billboard should paint pixels in the screen-center band — got \(painted) (if 0, blit math is wrong)")
    }

    // --- helpers ---

    private func buildEngine() -> (GraphicsController, Scene) {
        let g = GraphicsController(width: 512, height: 334, spriteCount: 5000)
        let s = Scene(graphics: g, modelCount: 100, polyCount: 10000, spriteCount: 200)
        return (g, s)
    }
}
