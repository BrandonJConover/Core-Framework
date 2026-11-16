import Foundation

/// A public chat line as decoded from a PLAYER_INFO mask, for the chat history.
public struct PublicChatEvent: Equatable {
	public var playerIndex: Int
	public var line: ChatLine
}

/// Social masks of PLAYER_INFO / NPC_INFO applied to actors: overhead chat, hit splats and
/// health bars, and spot animations (rt4 `Protocol.readExtendedPlayerInfo` / `readExtendedNpcInfo`).
extension WorldView {
	func applySocialMasks(_ a: PathingActor, _ m: EntityMasks) {
		for h in m.hits { a.addHit(type: h.type, damage: h.damage) }
		if let bar = m.healthBar {
			a.hitpointsBar = bar
			a.hitpointsBarVisibleUntil = ctx.loop + 300
		}
		if let sp = m.spotAnim { a.setSpotAnim(id: sp.id, height: sp.height, delay: sp.delay) }
		if let text = m.forceChat, a.kind == .npc {
			a.chatMessage = text
			a.chatLoops = 100
		}
		guard a.kind == .player else { return }
		if let text = m.forceChat {
			var line = text
			let tilde = line.hasPrefix("~")
			if tilde { line.removeFirst() }
			a.chatMessage = line
			a.chatEffect = 0
			a.chatColor = 0
			a.chatLoops = 150
			if tilde || a.index == selfIndex, let name = a.appearance?.name37 {
				onPublicChat?(PublicChatEvent(playerIndex: a.index, line: ChatLine(type: 2, name: WordPack.displayName(name), message: line, clan: nil, phraseId: -1)))
			}
		}
		if let c = m.publicChat { applyPublicChat(a, effects: c.effects, rights: c.rights, encoded: c.encoded) }
	}

	/// rt4 PLAYER_INFO flag 0x80: huffman-packed public chat.
	private func applyPublicChat(_ a: PathingActor, effects: Int, rights: Int, encoded: [UInt8]) {
		guard let ap = a.appearance, ap.name37 != 0 else { return }
		// Quick chat phrases (bit 15) need the quick-chat tables, which are not ported.
		if effects & 0x8000 != 0 { return }
		if isChatIgnored(ap.name37, rights) { return }
		guard let codec = (try? WordPack.loadCodec(store)) ?? nil else { return }
		let message = WordPack.display(WordPack.decode(encoded, codec: codec))
		a.chatMessage = message.trimmingCharacters(in: .whitespaces)
		a.chatEffect = effects & 0xFF
		a.chatLoops = 150
		a.chatColor = effects >> 8
		let name = WordPack.displayName(ap.name37)
		let line = rights != 0
			? ChatLine(type: 1, name: WordPack.chatIcon(rights: rights) + name, message: message, clan: nil, phraseId: -1)
			: ChatLine(type: 2, name: name, message: message, clan: nil, phraseId: -1)
		onPublicChat?(PublicChatEvent(playerIndex: a.index, line: line))
	}

	/// rt4 SPOTANIM_ENTITY (opcode 56) aimed at an npc or a player.
	func applySpotAnimMessage(delay: Int, height: Int, target: Int32, gfx: Int) {
		let t = Int(target)
		guard t >> 30 == 0 else {
			// A graphic on a tile: plane, then world x and z.
			let level = (t >> 28) & 3
			let tx = ((t >> 14) & 0x3FFF) - ctx.originX, tz = (t & 0x3FFF) - ctx.originZ
			guard tx >= 0, tz >= 0, tx < 104, tz < 104, gfx != 65535, let scene = scene else { return }
			let fx = tx * 128 + 64, fz = tz * 128 + 64
			groundSpots.append(GroundSpotAnim(store: store, spotAnimId: gfx, plane: level, xFine: fx, zFine: fz,
			                                  y: scene.tileHeight(level: level, xFine: fx, zFine: fz) - height, delay: delay, loop: ctx.loop))
			return
		}
		let id = gfx == 65535 ? -1 : gfx
		if t >> 29 != 0 {
			ctx.npcs[t & 0xFFFF]?.setSpotAnim(id: id, height: height, delay: delay)
		} else if t >> 28 != 0 {
			ctx.players[t & 0xFFFF]?.setSpotAnim(id: id, height: height, delay: delay)
		}
	}

	/// The spot animation model of an actor for this frame, positioned `spotAnimY` above its feet.
	func spotAnimModel(for a: PathingActor) -> SoftwareModel? {
		guard a.spotAnimId != -1, a.spotFrame >= 0, let t = (try? store.spotAnim(a.spotAnimId)) ?? nil,
		      let m = try? store.spotAnimModel(t, frame: a.spotFrame, nextFrame: a.spotNext, step: a.spotStep) else { return nil }
		m.translate(0, -a.spotAnimY, 0)
		return m
	}
}
