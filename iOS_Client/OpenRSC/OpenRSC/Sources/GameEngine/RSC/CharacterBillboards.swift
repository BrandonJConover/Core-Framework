// Registers character billboards with the Scene so they participate in 3D
// rendering. Mirrors the Java pipeline:
//   - drawNPC (mudclient.java:6292)
//   - drawPlayer (mudclient.java:6543)
// Each character consists of up to 12 composited sprite layers: head, shirt,
// pants, shield, weapon, hat, body, legs, gloves, boots, amulet, cape.
// Layer-to-screen-order is remapped via animDirLayer_To_CharLayer per direction
// so legs draw before torso, etc.

import Foundation

enum CharacterBillboards {

    // mudclient.java:395
    static let animFrameToSprite_Walk: [Int] = [0, 1, 2, 1]

    // mudclient.java:92 — maps (rsDir, layerSlot) -> compositing order
    // In each row the 12 values are the draw order of the 12 layers.
    static let animDirLayer_To_CharLayer: [[Int]] = [
        [11, 2, 9, 7, 1, 6, 10, 0, 5, 8, 3, 4],
        [11, 2, 9, 7, 1, 6, 10, 0, 5, 8, 4, 3],
        [11, 3, 4, 2, 9, 7, 1, 6, 10, 0, 5, 8],
        [3, 4, 2, 9, 0, 5, 8, 7, 1, 6, 10, 11],
        [3, 4, 2, 9, 0, 5, 8, 7, 1, 6, 10, 11],
        [3, 4, 2, 9, 0, 5, 8, 7, 1, 6, 10, 11],
        [11, 4, 3, 2, 9, 7, 1, 6, 10, 0, 5, 8],
        [11, 2, 9, 7, 1, 6, 10, 0, 5, 8, 4, 3],
    ]

    /// Register one character (NPC or player) as 12 billboard layers with the
    /// Scene. Scene will draw them in registration order during endScene after
    /// terrain is rasterized.
    /// - tileX/tileZ: player's tile-space coordinates (server units)
    /// - rsDir: 0..7 facing direction from server (npc.direction)
    /// - stepFrame: client-side tick counter for walk animation
    /// - sprites: 12 animation IDs from NPCDef or player appearance (-1 = unused)
    /// - walkModel: NPCDef.walkModel (typically 6)
    /// - authenticYOffset: how many pixels to lift the billboard so the feet
    ///   sit on the tile rather than the sprite center.
    static func register(
        scene: Scene,
        spriteLoader: SpriteLoader,
        tileX: Int,
        tileZ: Int,
        rsDir: Int,
        stepFrame: Int,
        walkModel: Int,
        cameraRotation: Int32,
        sprites: [Int],
        hairColor: Int32 = 0,
        topColor: Int32 = 0,
        bottomColor: Int32 = 0,
        skinColor: Int32 = 0
    ) {
        // Convert server tile coords to Scene world units (128 units/tile, + 64 center)
        let worldX: Int32 = Int32(tileX) * 128 + 64
        let worldZ: Int32 = Int32(tileZ) * 128 + 64
        let worldY: Int32 = 0  // ground level (Scene Y is inverted — negative up)

        let projected = scene.projectPoint(worldX: worldX, worldY: worldY, worldZ: worldZ)
        if projected.depth < scene.rot1024_zTop { return }  // behind camera
        let anchorScreenX = projected.screenX
        let anchorScreenY = projected.screenY
        let depth = projected.depth

        // Direction resolution per mudclient.java:6297-6313 and 6553-6565
        let wantedAnimDir = Int(((Int32(rsDir) &+ (cameraRotation &+ 16) / 32)) & 7)
        var flip = false
        var actualAnimDir = wantedAnimDir
        switch wantedAnimDir {
        case 5: flip = true; actualAnimDir = 3
        case 6: flip = true; actualAnimDir = 2
        case 7: flip = true; actualAnimDir = 1
        default: break
        }

        // Per-layer compositing order for this direction
        let orderRow = animDirLayer_To_CharLayer[min(7, wantedAnimDir)]
        let walkFrame = animFrameToSprite_Walk[(stepFrame / max(1, walkModel)) % 4]
        let dirOffset = actualAnimDir * 3
        let var14 = walkFrame + dirOffset

        // For each of 12 body-layer slots in z-order
        for slot in 0..<12 {
            let layerIdx = orderRow[slot]
            guard layerIdx < sprites.count else { continue }
            let animId = sprites[layerIdx]
            if animId < 0 { continue }
            guard let anim = AnimationDefs.get(animId) else { continue }

            let spriteID = anim.number + var14
            guard let gs = spriteLoader.getSprite(spriteID) else { continue }

            // The sprite is stored as a TRIMMED bitmap of size (gs.width, gs.height)
            // positioned inside a virtual bounding box of size (authenticWidth,
            // authenticHeight) with offset (xShift, yShift). Characters are
            // composited inside this authentic box so layers align correctly.
            //
            // The character's feet anchor sits at (anchorScreenX, anchorScreenY).
            // The authentic box bottom-center coincides with the feet, so:
            //   boxTopLeft = (anchor.x - authW/2, anchor.y - authH)
            //   spriteTopLeft = boxTopLeft + (xShift, yShift)
            let authW = Int32(gs.authenticWidth > 0 ? gs.authenticWidth : gs.width)
            let authH = Int32(gs.authenticHeight > 0 ? gs.authenticHeight : gs.height)
            let spriteW = Int32(gs.width)
            let spriteH = Int32(gs.height)

            let boxLeft = anchorScreenX - authW / 2
            let boxTop = anchorScreenY - authH
            let drawX = boxLeft + Int32(gs.xShift)
            let drawY = boxTop + Int32(gs.yShift)

            // Per-layer color masks. Java mudclient.java:6637-6646 picks mask1
            // based on the AnimationDef.charColour role:
            //   1 = hair color, 2 = top color, 3 = bottom color
            // mask2 is always the skin color so exposed skin is consistently tinted.
            let mask1: Int32 = {
                switch anim.charColour {
                case 1: return hairColor
                case 2: return topColor
                case 3: return bottomColor
                default: return Int32(anim.charColour)  // baked color from def
                }
            }()
            let mask2: Int32 = skinColor

            scene.drawSpriteTinted(
                depth: depth,
                x: drawX, y: drawY,
                width: spriteW, height: spriteH,  // draw at native size (no scale)
                spriteIdx: Int32(spriteID),
                mask1: mask1, mask2: mask2,
                mirrorX: flip
            )
        }
    }
}
