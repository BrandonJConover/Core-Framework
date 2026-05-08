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

    // mudclient.java:97-98 — 8-frame combat cycles. CombatA is the attacker
    // standing still on the left of the duel; CombatB is the attacker on the
    // right and renders mirrored. Both use the 3 "combat" sprites at offset
    // 15..17 within an animation's 27-slot range.
    static let animFrameToSprite_CombatA: [Int] = [0, 1, 2, 1, 0, 0, 0, 0]
    static let animFrameToSprite_CombatB: [Int] = [0, 0, 0, 0, 0, 1, 2, 1]

    /// Combat role for a billboard: which side of the fight the character is
    /// rendered as (controls frame table, mirror, and small horizontal lean).
    enum CombatRole {
        /// Not in combat — use the walking frame cycle.
        case none
        /// Attacker on the LEFT — use CombatA frames, no flip, lean right.
        case combatA
        /// Attacker on the RIGHT — use CombatB frames, horizontal flip, lean left.
        case combatB
    }

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
        tileX: Double,
        tileZ: Double,
        rsDir: Int,
        stepFrame: Int,
        walkModel: Int,
        cameraRotation: Int32,
        sprites: [Int],
        hairColor: Int32 = 0,
        topColor: Int32 = 0,
        bottomColor: Int32 = 0,
        skinColor: Int32 = 0,
        combatRole: CombatRole = .none,
        combatModel: Int = 6,
        combatSprite: Int = 5,
        overlayMovement: Int = 0
    ) {
        // Convert server tile coords to Scene world units (128 units/tile, + 64 center)
        let worldX: Int32 = Int32((tileX * 128.0).rounded()) + 64
        let worldZ: Int32 = Int32((tileZ * 128.0).rounded()) + 64
        let worldY: Int32 = 0  // ground level (Scene Y is inverted — negative up)

        let projected = scene.projectPoint(worldX: worldX, worldY: worldY, worldZ: worldZ)
        if projected.depth < scene.rot1024_zTop { return }  // behind camera
        let anchorScreenX = projected.screenX
        let anchorScreenY = projected.screenY
        let depth = projected.depth

        // Direction resolution per mudclient.java:6297-6313 and 6553-6565.
        // Combat ignores rsDir and forces a fixed dir so attacker always faces
        // the duel partner. Walk uses the camera-relative direction.
        let wantedAnimDir: Int
        var flip = false
        var actualAnimDir: Int
        var anchorXAdjust: Int32 = 0

        switch combatRole {
        case .none:
            wantedAnimDir = Int(((Int32(rsDir) &+ (cameraRotation &+ 16) / 32)) & 7)
            actualAnimDir = wantedAnimDir
            switch wantedAnimDir {
            case 5: flip = true; actualAnimDir = 3
            case 6: flip = true; actualAnimDir = 2
            case 7: flip = true; actualAnimDir = 1
            default: break
            }
        case .combatA:
            // Java mudclient.java:6320-6322: var11 = 2 (face east), var13 = 5,
            // x -= overlayMovement * combatSprite / 100 (lean right toward foe).
            wantedAnimDir = 2
            actualAnimDir = 5
            flip = false
            anchorXAdjust = -Int32(overlayMovement * combatSprite / 100)
        case .combatB:
            // Java mudclient.java:6322-6328: var11 = 2, var13 = 5, mirror.
            wantedAnimDir = 2
            actualAnimDir = 5
            flip = true
            anchorXAdjust = Int32(overlayMovement * combatSprite / 100)
        }

        // Per-layer compositing order for this direction
        let orderRow = animDirLayer_To_CharLayer[min(7, wantedAnimDir)]
        let dirOffset = actualAnimDir * 3
        let var14: Int
        switch combatRole {
        case .none:
            let walkFrame = animFrameToSprite_Walk[(stepFrame / max(1, walkModel)) % 4]
            var14 = walkFrame + dirOffset
        case .combatA:
            // mudclient.java:6321 — frame divisor is (combatModel - 1)
            let combatFrame = animFrameToSprite_CombatA[(stepFrame / max(1, combatModel - 1)) % 8]
            var14 = combatFrame + dirOffset    // = 15 + frame because dirOffset = 15
        case .combatB:
            // mudclient.java:6327 — divisor is combatModel
            let combatFrame = animFrameToSprite_CombatB[(stepFrame / max(1, combatModel)) % 8]
            var14 = combatFrame + dirOffset
        }

        // For each of 12 body-layer slots in z-order
        for slot in 0..<12 {
            let layerIdx = orderRow[slot]
            guard layerIdx < sprites.count else { continue }
            let animId = sprites[layerIdx]
            if animId < 0 { continue }
            guard let anim = AnimationDefs.get(animId) else { continue }

            let layerFrame = frameOffsetForLayer(
                layer: layerIdx,
                baseOffset: var14,
                actualAnimDir: actualAnimDir,
                mirrorX: flip,
                animation: anim,
                stepFrame: stepFrame,
                walkModel: walkModel,
                combatRole: combatRole
            )
            guard let layerFrame else { continue }

            let spriteID = anim.number + layerFrame.offset
            guard let gs = spriteLoader.getSprite(spriteID) else { continue }
            let baseGs = spriteLoader.getSprite(anim.number)

            // The sprite is stored as a TRIMMED bitmap of size (gs.width, gs.height)
            // positioned inside a virtual bounding box of size (authenticWidth,
            // authenticHeight) with offset (xShift, yShift). Characters are
            // composited inside this authentic box so layers align correctly.
            // Java drawPlayer/drawNPC passes the actor's virtual box width and
            // height into drawSpriteClipping; the renderer then scales the
            // trimmed bitmap according to its authentic dimensions and x/y shift.
            // Replicate that math before registering the billboard layer.
            //
            // The character's feet anchor sits at (anchorScreenX, anchorScreenY).
            // The authentic box bottom-center coincides with the feet, so:
            //   boxTopLeft = (anchor.x - authW/2, anchor.y - authH)
            //   spriteTopLeft = boxTopLeft + (xShift, yShift)
            let authW = max(1, Int32(gs.authenticWidth > 0 ? gs.authenticWidth : gs.width))
            let authH = max(1, Int32(gs.authenticHeight > 0 ? gs.authenticHeight : gs.height))
            let baseAuthWidthSource = baseGs?.authenticWidth ?? gs.authenticWidth
            let baseAuthHeightSource = baseGs?.authenticHeight ?? gs.authenticHeight
            let baseAuthW = max(1, Int32(baseAuthWidthSource > 0 ? baseAuthWidthSource : gs.width))
            let baseAuthH = max(1, Int32(baseAuthHeightSource > 0 ? baseAuthHeightSource : gs.height))
            let actorW = baseAuthW
            let actorH = baseAuthH
            let spriteVirtualW = max(1, (authW * actorW) / baseAuthW)
            let spriteW = max(1, (Int32(gs.width) * spriteVirtualW) / authW)
            let spriteH = max(1, (Int32(gs.height) * actorH) / authH)
            let shiftX = (Int32(gs.xShift) * spriteVirtualW) / authW
            let shiftY = (Int32(gs.yShift) * actorH) / authH
            let xOffset = (Int32(layerFrame.xOffset) * actorW) / authW
            let yOffset = (Int32(layerFrame.yOffset) * actorH) / authH

            let drawX = anchorScreenX - actorW / 2 + anchorXAdjust + xOffset
                - (spriteVirtualW - actorW) / 2 + shiftX
            let drawY = anchorScreenY - actorH + yOffset + shiftY

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
                width: spriteW, height: spriteH,
                spriteIdx: Int32(spriteID),
                mask1: mask1, mask2: mask2, blueMask: Int32(anim.blueMask),
                mirrorX: flip
            )
        }
    }

    private static func frameOffsetForLayer(layer: Int,
                                            baseOffset: Int,
                                            actualAnimDir: Int,
                                            mirrorX: Bool,
                                            animation: AnimationDef,
                                            stepFrame: Int,
                                            walkModel: Int,
                                            combatRole: CombatRole) -> (offset: Int, xOffset: Int, yOffset: Int)? {
        // Java mudclient.java:6625: combat direction 5 is only drawable when
        // the animation actually owns combat-A frames. Ranged weapons such as
        // crossbow/longbow set hasA=false; indexing +15 anyway lands in the
        // next animation's sprite range and visually equips the wrong item.
        if actualAnimDir == 5 && !animation.hasA {
            return nil
        }

        var offset = baseOffset
        var xOffset = 0
        var yOffset = 0

        // Java mudclient.java:6590-6623: mirrored side-facing weapon/shield
        // layers either use special F sprites or get hand-tuned offsets so the
        // held item remains attached to the correct hand after mirroring.
        guard mirrorX && actualAnimDir >= 1 && actualAnimDir <= 3 && combatRole == .none else {
            return (offset, xOffset, yOffset)
        }

        if animation.hasF {
            offset += 15
        } else if layer == 4 && actualAnimDir == 1 {
            offset = actualAnimDir * 3 + animFrameToSprite_Walk[((stepFrame / max(1, walkModel)) + 2) % 4]
            xOffset = -22
            yOffset = -3
        } else if layer == 4 && actualAnimDir == 2 {
            offset = actualAnimDir * 3 + animFrameToSprite_Walk[((stepFrame / max(1, walkModel)) + 2) % 4]
            xOffset = 0
            yOffset = -8
        } else if layer == 4 && actualAnimDir == 3 {
            offset = actualAnimDir * 3 + animFrameToSprite_Walk[((stepFrame / max(1, walkModel)) + 2) % 4]
            xOffset = 26
            yOffset = -5
        } else if layer == 3 && actualAnimDir == 1 {
            offset = actualAnimDir * 3 + animFrameToSprite_Walk[((stepFrame / max(1, walkModel)) + 2) % 4]
            xOffset = 22
            yOffset = 3
        } else if layer == 3 && actualAnimDir == 2 {
            offset = actualAnimDir * 3 + animFrameToSprite_Walk[((stepFrame / max(1, walkModel)) + 2) % 4]
            xOffset = 0
            yOffset = 8
        } else if layer == 3 && actualAnimDir == 3 {
            offset = actualAnimDir * 3 + animFrameToSprite_Walk[((stepFrame / max(1, walkModel)) + 2) % 4]
            xOffset = -26
            yOffset = 5
        }

        return (offset, xOffset, yOffset)
    }
}
