import Foundation

/// Marks the tile under the player, the tile the player is walking to, and npcs picked by name.
public final class TileIndicatorsPlugin: ClientPlugin {
	public let id = "indicators"
	public let name = "NPC & Tile Indicators"
	public let summary = "Highlights your tile, your destination tile and chosen npcs."
	public var enabled = false
	public let config = PluginConfig([
		.toggle("playerTile", "Tile under you", true),
		.toggle("destinationTile", "Destination tile", true),
		.list("npcs", "Highlighted npcs", [], help: "One name per line; * at the start or end matches any text."),
		.choice("npcStyle", "Npc highlight", ["Fill", "Outline", "Both"], "Both"),
		.toggle("npcNames", "Label highlighted npcs", false),
	])
	public var subscriptions: PluginSubscription { [.overlayScene] }

	public init() {}

	public func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster) {
		guard layer == .scene, canvas.canProject else { return }
		let ctx = canvas.ctx
		if config.bool("playerTile"), let me = ctx.selfActor, me.size == 1 {
			canvas.fillTile(x: me.tileX, z: me.tileZ, color: 0x00FFFF, opacity: 50, into: &r)
			canvas.outlineTile(x: me.tileX, z: me.tileZ, color: 0x00FFFF, into: &r)
		}
		if config.bool("destinationTile"), let d = ctx.destinationTile {
			canvas.fillTile(x: d.x, z: d.z, color: 0xFFFF00, opacity: 60, into: &r)
			canvas.outlineTile(x: d.x, z: d.z, color: 0xFFFF00, into: &r)
		}
		let names = config.list("npcs")
		guard !names.isEmpty else { return }
		let style = config.string("npcStyle"), labels = config.bool("npcNames")
		for npc in canvas.npcs() where PluginMatch.any(names, npc.name) {
			guard let c = canvas.footprintCorners(xFine: npc.fineX, zFine: npc.fineZ, size: npc.size) else { continue }
			if style != "Outline" { r.fillPolygon(c, 0xFF8000, opacity: 70) }
			if style != "Fill" { r.strokePolygon(c, 0xFF8000) }
			if labels, let top = canvas.project(xFine: npc.fineX, zFine: npc.fineZ, height: 200) {
				canvas.drawText(npc.name, x: top.x, y: top.y, color: 0xFFB060, into: &r)
			}
		}
	}
}
