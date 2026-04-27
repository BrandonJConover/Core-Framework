import SwiftUI

// 96x96 minimap that mirrors the bottom-right minimap in the Java client
// (mudclient.java:drawUiTabMinimap, ~line 8948). Each pixel = 1 tile, centered
// on the local player. NPCs = yellow dots, players = cyan, ground items = red,
// player = white star at center.
//
// We render with SwiftUI Canvas instead of dipping into the engine's pixel
// buffer — the buffer is sized for the 3D scene and would be wasteful to
// re-sample. The data we need (`npcs`, `players`, `groundItems`, terrain
// landscape lookups via `LandscapeLoader`) all lives in worldState/engine.
struct MinimapPanel: View {
    @ObservedObject var worldState: RSCWorldState
    @ObservedObject var engine: RSCGameEngine

    /// One minimap tile in points. The minimap itself is 96 tiles wide; we
    /// draw at 2 points per tile so the panel is ~192pt — fits comfortably
    /// in the 280px max HUD height.
    private let pixelsPerTile: CGFloat = 2
    private let tilesAcross: Int = 96

    private var sizePts: CGFloat { CGFloat(tilesAcross) * pixelsPerTile }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Minimap")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("(\(worldState.worldOffsetX + worldState.localPlayerX), \(worldState.worldOffsetZ + worldState.localPlayerY))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#888888"))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            Canvas { ctx, size in
                drawMinimap(ctx: ctx, size: size)
            }
            .frame(width: sizePts, height: sizePts)
            .background(Color(hex: "#0a0a0a"))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "#c8a951"), lineWidth: 1)
            )

            // Compass + scale
            HStack(spacing: 12) {
                Label("N", systemImage: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
                Text("\(worldState.npcs.count) NPCs")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("\(worldState.players.count) players")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text("\(worldState.groundItems.count) items")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func drawMinimap(ctx: GraphicsContext, size: CGSize) {
        let halfTiles = tilesAcross / 2
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        let absX = worldState.worldOffsetX + px
        let absZ = worldState.worldOffsetZ + pz
        let landscapeReady = engine.landscapeLoader.isLoaded

        // Terrain — sample per tile from the loaded landscape archive when
        // available, otherwise fall back to a flat dark background.
        for ty in 0..<tilesAcross {
            for tx in 0..<tilesAcross {
                let worldTX = absX + (tx - halfTiles)
                let worldTZ = absZ + (ty - halfTiles)
                var fill = Color(hex: "#1a1a1a")
                if landscapeReady,
                   let tile = engine.landscapeLoader.getTile(worldX: worldTX, worldZ: worldTZ, plane: 0) {
                    let packed = LandscapeLoader.tileColor(
                        overlay: tile.groundOverlay,
                        texture: tile.groundTexture,
                        elevation: tile.groundElevation
                    )
                    fill = colorFromPackedARGB(packed)
                    if tile.horizontalWall > 0 || tile.verticalWall > 0 {
                        fill = Color(hex: "#3d2c20")
                    } else if tile.roofTexture > 0 {
                        fill = Color(hex: "#5a4a3a")
                    }
                }
                let rect = CGRect(
                    x: CGFloat(tx) * pixelsPerTile,
                    y: CGFloat(ty) * pixelsPerTile,
                    width: pixelsPerTile,
                    height: pixelsPerTile
                )
                ctx.fill(Path(rect), with: .color(fill))
            }
        }

        // Ground items (red dots). We map world tile -> minimap tile -> point.
        for item in worldState.groundItems {
            drawDot(ctx: ctx,
                    worldX: item.x, worldZ: item.y,
                    px: px, pz: pz,
                    halfTiles: halfTiles,
                    color: .red)
        }

        // Players (cyan dots)
        for player in worldState.players {
            drawDot(ctx: ctx,
                    worldX: player.x, worldZ: player.y,
                    px: px, pz: pz,
                    halfTiles: halfTiles,
                    color: .cyan)
        }

        // NPCs (yellow dots)
        for npc in worldState.npcs {
            drawDot(ctx: ctx,
                    worldX: npc.x, worldZ: npc.y,
                    px: px, pz: pz,
                    halfTiles: halfTiles,
                    color: .yellow)
        }

        // Local player — small white plus/star at center
        let cx = CGFloat(halfTiles) * pixelsPerTile
        let cy = CGFloat(halfTiles) * pixelsPerTile
        let starPath = Path { p in
            p.move(to: CGPoint(x: cx, y: cy - 4))
            p.addLine(to: CGPoint(x: cx, y: cy + 4))
            p.move(to: CGPoint(x: cx - 4, y: cy))
            p.addLine(to: CGPoint(x: cx + 4, y: cy))
            p.move(to: CGPoint(x: cx - 3, y: cy - 3))
            p.addLine(to: CGPoint(x: cx + 3, y: cy + 3))
            p.move(to: CGPoint(x: cx + 3, y: cy - 3))
            p.addLine(to: CGPoint(x: cx - 3, y: cy + 3))
        }
        ctx.stroke(starPath, with: .color(.white), lineWidth: 1.5)
    }

    private func drawDot(ctx: GraphicsContext,
                         worldX: Int, worldZ: Int,
                         px: Int, pz: Int,
                         halfTiles: Int,
                         color: Color) {
        let dx = worldX - px
        let dz = worldZ - pz
        guard abs(dx) < halfTiles && abs(dz) < halfTiles else { return }
        let mx = (halfTiles + dx)
        let mz = (halfTiles + dz)
        let rect = CGRect(
            x: CGFloat(mx) * pixelsPerTile - 1,
            y: CGFloat(mz) * pixelsPerTile - 1,
            width: pixelsPerTile + 2,
            height: pixelsPerTile + 2
        )
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
    }

    /// Convert a packed ARGB value (as produced by LandscapeLoader) into a
    /// SwiftUI Color. The packed value is 0xAARRGGBB.
    private func colorFromPackedARGB(_ packed: Int32) -> Color {
        let u = UInt32(bitPattern: packed)
        let r = Double((u >> 16) & 0xFF) / 255.0
        let g = Double((u >> 8) & 0xFF) / 255.0
        let b = Double(u & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
