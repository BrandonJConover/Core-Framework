import Foundation

/// Ambient sound sources among the actors in the scene (rt4 `AreaSoundManager.add` for npcs and players).
extension WorldView {
	/// rt4 `Npc.getSound` / `Player.getSound`: the sound of the movement animation an actor is playing.
	/// Walking is the default; the idle, run and crawl (slow walk) animation families pick their own.
	static func movementSound(moveSeq: Int, bas: BasType, idle: Int, crawl: Int, walk: Int, run: Int) -> Int {
		if bas.idle == moveSeq { return idle }
		if moveSeq == bas.run || moveSeq == bas.runFullTurn || moveSeq == bas.runCW || moveSeq == bas.runCCW { return run }
		if moveSeq == bas.slowWalk || moveSeq == bas.slowWalkFullTurn || moveSeq == bas.slowWalkCW || moveSeq == bas.slowWalkCCW { return crawl }
		return walk
	}

	/// Every npc and player that can make ambient sound right now, with the sound its current movement plays.
	public func areaSoundSources() -> [ActorSoundInfo] {
		var out: [ActorSoundInfo] = []
		for (id, a) in ctx.npcs {
			guard let t = a.npcType, t.sounds.radius > 0 else { continue }
			let s = t.sounds
			if s.idle == -1 && s.walk == -1 && s.run == -1 { continue }
			let sound = Self.movementSound(moveSeq: a.moveSeqId, bas: a.currentBas, idle: s.idle, crawl: s.crawl, walk: s.walk, run: s.run)
			out.append(ActorSoundInfo(key: id, isPlayer: false, xFine: a.xFine, zFine: a.zFine, size: a.size, sound: sound, radius: s.radius))
		}
		for (id, a) in ctx.players {
			guard let ap = a.appearance, ap.soundRadius > 0 else { continue }
			let s = ap.sounds
			let sound = Self.movementSound(moveSeq: a.moveSeqId, bas: a.currentBas, idle: s[0], crawl: s[1], walk: s[2], run: s[3])
			out.append(ActorSoundInfo(key: id, isPlayer: true, xFine: a.xFine, zFine: a.zFine, size: a.size, sound: sound, radius: ap.soundRadius))
		}
		return out
	}
}
