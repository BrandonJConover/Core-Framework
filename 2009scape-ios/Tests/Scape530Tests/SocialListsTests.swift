import Foundation
import XCTest
@testable import Scape530

/// Local teleport, friends, ignores and clan chat: synthetic server messages, the CS2 ops backed by them,
/// and the friends tab rendered by interface 550's own scripts.
final class SocialListsTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func op(_ name: String) -> HostOpSpec { HostOpSpec(opcode: 0, name: name, ints: 0, strings: 0, outInts: 0, outStrings: 0) }

	// MARK: packet builders (the inverse of the ServerMessage decoders)

	func pkt(_ opcode: Int, _ build: (inout Packet) -> Void) -> GamePacket {
		var p = Packet(capacity: 64)
		build(&p)
		return GamePacket(opcode: opcode, payload: p.written)
	}

	func friendPacket(_ name: String, world: Int, rank: Int, sameGame: Bool = true, worldName: String = "") -> GamePacket {
		pkt(ServerProt.updateFriendlist) {
			var n = Base37.encode(name)
			if !sameGame { n |= Int64.min }
			$0.p8(n); $0.p2(world); $0.p1(rank)
			if world > 0 { $0.pjstr(worldName) }
		}
	}

	// MARK: teleport

	/// A synthetic TELEPORT_LOCAL_PLAYER after the recorded session: the pipeline moves the decoder's
	/// local player, the game state's world position and the world view's actor.
	func testTeleportMovesSelfThroughPipelineStateAndWorld() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		let me = 2047
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var pipe = GameSession.Pipeline(selfId: me)
		for p in try SessionReplayTests.recordedPackets("resizable-session") {
			for e in pipe.handle(p) {
				client.handle(e)
				if case .players = e { for _ in 0..<30 { client.world.cycle(varps: client.state.varps) } }
			}
		}
		let before = try XCTUnwrap(client.state.selfWorld)
		_ = try client.frame(width: 765, height: 503)
		let area = client.audio.effects.area.counts
		print("ambient sources after the replay: \(area), voices \(client.audio.effects.area.voiceCounts)")
		XCTAssertGreaterThan(area.locs, 0, "locs with a bgsound were registered from the scene build")
		let ticks = client.state.ticks

		// Scene tile (60, 61), plane 2, jump set: rt4 reads g1sub x, g1add (plane << 1 | jump), g1 z.
		let events = pipe.handle(pkt(ServerProt.teleportLocalPlayer) { $0.p1sub(60); $0.p1add(2 << 1 | 1); $0.p1(61) })
		XCTAssertEqual(events.count, 2)
		guard case .message(.teleportLocalPlayer(60, 61, 2, true)) = events[0] else { return XCTFail("\(events)") }
		let me0 = try XCTUnwrap(pipe.players.players[me])
		XCTAssertEqual([me0.x, me0.z, pipe.players.plane], [60, 61, 2])
		XCTAssertTrue(me0.jump)
		for e in events { client.handle(e) }
		for _ in 0..<2 { client.world.cycle(varps: client.state.varps) }

		let after = try XCTUnwrap(client.state.selfWorld)
		XCTAssertEqual(after.plane, 2)
		XCTAssertEqual(after.x - before.x, 60 - (before.x - (client.state.rebuild!.zoneX - 6) * 8))
		XCTAssertEqual(after.z, (client.state.rebuild!.zoneZ - 6) * 8 + 61)
		let tile = try XCTUnwrap(client.world.selfSceneTile)
		XCTAssertEqual([tile.x, tile.z], [60, 61], "the actor snapped to the teleport tile")
		XCTAssertEqual(client.world.plane, 2)
		XCTAssertEqual(client.state.ticks, ticks + 1)
	}

	// MARK: friends and ignores

	func testFriendListUpdatesSortAndNotify() throws {
		var game = GameState()
		game.ownWorld = 1
		game.apply(try ServerMessage.decode(pkt(ServerProt.friendlistLoaded) { $0.p1(2) }))
		XCTAssertEqual(game.social.friendsState, 2)
		for m in [friendPacket("offline guy", world: 0, rank: 0), friendPacket("other world", world: 5, rank: 1, worldName: "World 5"), friendPacket("same world", world: 1, rank: 7, worldName: "World 1")] {
			game.apply(try ServerMessage.decode(m))
		}
		// Same-world friends first, other worlds next, offline last (rt4's bubble sort).
		XCTAssertEqual(game.social.friends.map(\.displayName), ["Same World", "Other World", "Offline Guy"])
		XCTAssertEqual(game.social.friends[0].rank, 7)
		XCTAssertEqual(game.social.friends[1].worldName, "World 5")
		// A login notice goes to chat as type 5; an unchanged world says nothing.
		game.apply(try ServerMessage.decode(friendPacket("offline guy", world: 1, rank: 0, worldName: "World 1")))
		XCTAssertEqual(game.chatLog.line(0)?.type, 5)
		XCTAssertEqual(game.chatLog.line(0)?.message, "Offline Guy has logged in.")
		let size = game.chatLog.size
		game.apply(try ServerMessage.decode(friendPacket("offline guy", world: 1, rank: 3, worldName: "World 1")))
		XCTAssertEqual(game.chatLog.size, size)
		XCTAssertEqual(game.social.friends.first { $0.displayName == "Offline Guy" }?.rank, 3)
		// The sign bit of the name is rt4's inverted sameGame flag.
		game.apply(try ServerMessage.decode(friendPacket("same world", world: 1, rank: 7, sameGame: false, worldName: "World 1")))
		XCTAssertEqual(game.social.friends.first { $0.displayName == "Same World" }?.sameGame, false)

		let ignore = pkt(ServerProt.updateIgnorelist) { $0.p8(Base37.encode("pest")); $0.p8(Base37.encode("troll")) }
		game.apply(try ServerMessage.decode(ignore))
		XCTAssertEqual(game.ignored, [Base37.encode("pest"), Base37.encode("troll")])
		XCTAssertTrue(game.social.isIgnored("Pest"))
		XCTAssertTrue(game.social.isIgnored("<img=0>troll"))
		XCTAssertEqual(game.social.indexOfFriend("OTHER WORLD"), 2)
	}

	func testClientSideListChangesSendPackets() {
		var s = SocialLists()
		let me = Base37.encode("me")
		XCTAssertEqual(s.addFriend("Zezima", selfName37: me, members: false).message.map { "\($0)" }, "friendAdd(\(Base37.encode("zezima")))")
		XCTAssertEqual(s.addFriend("zezima", selfName37: me, members: false).notice, "Zezima is already on your friend list")
		XCTAssertEqual(s.addFriend("me", selfName37: me, members: false).notice, "You can't add yourself to your own friend list")
		XCTAssertEqual(s.addIgnore("Zezima", selfName37: me).notice, "Please remove Zezima from your friend list first")
		XCTAssertNotNil(s.addIgnore("Pest", selfName37: me).message)
		XCTAssertEqual(s.addFriend("pest", selfName37: me, members: false).notice, "Please remove Pest from your ignore list first")
		XCTAssertEqual(s.removeFriend("zezima").message.map { "\($0)" }, "friendDel(\(Base37.encode("zezima")))")
		XCTAssertNil(s.removeFriend("zezima").message)
		XCTAssertEqual(s.removeIgnore("pest").message.map { "\($0)" }, "ignoreDel(\(Base37.encode("pest")))")
		// Free accounts stop at 100 friends.
		for i in 0..<100 { _ = s.addFriend("f\(i)", selfName37: me, members: false) }
		XCTAssertEqual(s.friends.count, 100)
		XCTAssertNotNil(s.addFriend("extra", selfName37: me, members: false).notice)
		XCTAssertNotNil(s.addFriend("extra", selfName37: me, members: true).message)
	}

	func testClientPacketBytes() {
		var cipher = IsaacRandom(seed: [0, 0, 0, 0]), plain = IsaacRandom(seed: [0, 0, 0, 0])
		let n = Base37.encode("zezima")
		var name = Packet(capacity: 8); name.p8(n)
		func check(_ m: ClientMessage, _ opcode: Int, _ body: [UInt8]) {
			XCTAssertEqual(m.encode(&cipher), [UInt8(truncatingIfNeeded: opcode + plain.nextKey())] + body)
		}
		check(.friendAdd(n), 120, name.written)
		check(.friendDel(n), 57, name.written)
		check(.ignoreAdd(n), 34, name.written)
		check(.ignoreDel(n), 213, name.written)
		check(.friendSetRank(name37: n, rank: 3), 188, [131] + name.written)
		check(.clanJoinLeave(name37: n), 104, name.written)
		check(.clanJoinLeave(name37: 0), 104, [UInt8](repeating: 0, count: 8))
		check(.clanKick(name37: n), 162, name.written)
	}

	// MARK: clan chat

	func clanJoinPacket(members: [(String, Int, Int, String)], size: Int? = nil) -> GamePacket {
		pkt(ServerProt.joinClanChat) {
			$0.p8(Base37.encode("owner")); $0.p8(Base37.encode("my clan")); $0.p1(5); $0.p1(size ?? members.count)
			for (n, w, r, wn) in members { $0.p8(Base37.encode(n)); $0.p2(w); $0.p1(r); $0.pjstr(wn) }
		}
	}

	func testClanChatJoinUpdateAndLeave() throws {
		var s = SocialLists()
		let me = Base37.encode("me")
		var m = try ServerMessage.decode(clanJoinPacket(members: [("zed", 1, 2, "World 1"), ("me", 1, 255, "World 1"), ("alpha", 3, 0, "World 3")]))
		guard case .joinClanChat(let j) = m else { return XCTFail() }
		s.joinClan(j, selfName37: me)
		XCTAssertEqual(s.clanName, "my_clan")
		XCTAssertEqual(WordPack.titleCase(s.clanOwner ?? ""), "Owner")
		XCTAssertEqual(s.clanMembers.map(\.displayName), ["Alpha", "Me", "Zed"], "sorted by name")
		XCTAssertEqual(s.clanRank, -1, "g1b: 255 is rank -1 (guest)")
		XCTAssertEqual(s.clanMinKick, 5)

		func update(_ name: String, world: Int, rank: Int, worldName: String = "", removed: Bool = false) throws {
			let p = pkt(ServerProt.updateClan) {
				$0.p8(removed ? (Base37.encode(name) | Int64.min) : Base37.encode(name))
				$0.p2(world); $0.p1(rank)
				if !removed { $0.pjstr(worldName) }
			}
			m = try ServerMessage.decode(p)
			guard case let .updateClan(n, w, r, wn, rem) = m else { return XCTFail() }
			s.updateClan(name37: n, world: w, rank: r, worldName: wn, removed: rem, selfName37: me)
		}
		try update("bob", world: 2, rank: 0, worldName: "World 2")
		XCTAssertEqual(s.clanMembers.map(\.displayName), ["Alpha", "Bob", "Me", "Zed"])
		try update("bob", world: 4, rank: 6, worldName: "World 4")
		XCTAssertEqual(s.clanMembers.count, 4)
		XCTAssertEqual(s.clanMembers[1].world, 4)
		XCTAssertEqual(s.clanMembers[1].rank, 6)
		try update("me", world: 1, rank: 9, worldName: "World 1")
		XCTAssertEqual(s.clanRank, 9)
		try update("zed", world: 1, rank: 0, removed: true)
		XCTAssertEqual(s.clanMembers.map(\.displayName), ["Alpha", "Bob", "Me"])

		// rt4: size 255 only refreshes the header.
		m = try ServerMessage.decode(clanJoinPacket(members: [], size: 255))
		guard case .joinClanChat(let header) = m else { return XCTFail() }
		s.joinClan(header, selfName37: me)
		XCTAssertEqual(s.clanMembers.count, 3)

		m = try ServerMessage.decode(pkt(ServerProt.joinClanChat) { $0.p8(0) })
		guard case .joinClanChat(let leave) = m else { return XCTFail() }
		XCTAssertNil(leave)
		s.joinClan(leave, selfName37: me)
		XCTAssertFalse(s.inClan)
		XCTAssertEqual(s.clanMembers.count, 0)
	}

	func testClanMessageDecodes() throws {
		let m = try ServerMessage.decode(pkt(ServerProt.messageClanchannel) {
			$0.p8(Base37.encode("zed")); $0.p1(0); $0.p8(Base37.encode("my clan"))
			$0.p2(1); $0.p3(2); $0.p1(0); $0.pdata([4, 9, 9])
		})
		XCTAssertEqual(m, .clanMessage(name37: Base37.encode("zed"), clan37: Base37.encode("my clan"), messageId: 1 << 32 | 2, rights: 0, text: [4, 9, 9]))
	}

	// MARK: CS2 ops

	func testHostOpsReadSocialState() throws {
		let host = InterfaceScriptHost(store: try store())
		var sent: [ClientMessage] = []
		host.send = { sent.append($0) }
		func call(_ n: String, _ ints: [Int32] = [], _ strs: [String] = []) -> HostResult { host.perform(op(n), ints: ints, strings: strs) }
		XCTAssertEqual(call("friendCount").ints, [-2])
		XCTAssertEqual(call("ignoreCount").ints, [-1])
		XCTAssertEqual(call("clanMemberCount").ints, [-1])
		host.apply(.friendlistLoaded(state: 1))
		XCTAssertEqual(call("friendCount").ints, [-1])
		host.apply(.friendlistLoaded(state: 2))
		host.apply(try ServerMessage.decode(friendPacket("alice", world: 1, rank: 2, worldName: "World 1")))
		host.apply(try ServerMessage.decode(friendPacket("bob", world: 0, rank: 0)))
		host.apply(.ignoreList([Base37.encode("pest")]))
		XCTAssertEqual(call("friendCount").ints, [2])
		XCTAssertEqual(call("friendName", [0]).strings, ["Alice"])
		XCTAssertEqual(call("friendWorld", [0]).ints, [1])
		XCTAssertEqual(call("friendRank", [0]).ints, [2])
		XCTAssertEqual(call("friendWorldName", [0]).strings, ["World 1"])
		XCTAssertEqual(call("friendName", [9]).strings, [""])
		XCTAssertEqual(call("isFriend", [], ["bob"]).ints, [1])
		XCTAssertEqual(call("isFriend", [], ["nobody"]).ints, [0])
		XCTAssertEqual(call("friendIndexOf", [], ["Bob"]).ints, [1])
		XCTAssertEqual(call("ignoreCount").ints, [1])
		XCTAssertEqual(call("ignoreName", [0]).strings, ["Pest"])
		XCTAssertEqual(call("isIgnored", [], ["pest"]).ints, [1])

		_ = call("friendAdd", [], ["Carol"])
		_ = call("ignoreAdd", [], ["Troll"])
		_ = call("friendRemove", [], ["bob"])
		_ = call("ignoreRemove", [], ["pest"])
		_ = call("friendSetRank", [4], ["alice"])
		_ = call("clanJoin", [], ["Owner"])
		_ = call("clanLeave")
		XCTAssertEqual(sent.map { "\($0)" }, [
			"friendAdd(\(Base37.encode("carol")))", "ignoreAdd(\(Base37.encode("troll")))",
			"friendDel(\(Base37.encode("bob")))", "ignoreDel(\(Base37.encode("pest")))",
			"friendSetRank(name37: \(Base37.encode("alice")), rank: 4)",
			"clanJoinLeave(name37: \(Base37.encode("owner")))", "clanJoinLeave(name37: 0)",
		])
		XCTAssertEqual(call("friendCount").ints, [2], "alice and carol")

		host.apply(try ServerMessage.decode(clanJoinPacket(members: [("bob", 2, 1, "World 2"), ("alice", 1, 3, "World 1")])))
		XCTAssertEqual(call("clanName").strings, ["My Clan"])
		XCTAssertEqual(call("clanOwner").strings, ["Owner"])
		XCTAssertEqual(call("clanMemberCount").ints, [2])
		XCTAssertEqual(call("clanMemberName", [0]).strings, ["Alice"])
		XCTAssertEqual(call("clanMemberWorld", [1]).ints, [2])
		XCTAssertEqual(call("clanMemberRank", [0]).ints, [3])
		XCTAssertEqual(call("clanMemberWorldName", [1]).strings, ["World 2"])
		XCTAssertEqual(call("clanMinKick").ints, [5])
	}

	// MARK: friends tab

	/// Interface 550 (the friends tab) builds its rows from the friend ops in its own scripts.
	func testFriendsTabShowsTwoFriends() throws {
		let host = InterfaceScriptHost(store: try store())
		host.resize(width: 190, height: 261)
		host.apply(.ifOpenTop(id: 550, reset: 0))
		host.apply(.friendlistLoaded(state: 2))
		host.apply(try ServerMessage.decode(friendPacket("zezima", world: 1, rank: 0, worldName: "World 1")))
		host.apply(try ServerMessage.decode(friendPacket("iron man", world: 0, rank: 0)))
		for _ in 0..<4 { host.cycle() }
		var r = Raster(width: 190, height: 261)
		try host.renderer.render(host.game.interfaces.top, state: host.game.interfaces, into: &r)
		try save(r, "social-friends-tab")
		XCTAssertEqual(host.takeErrors(), [])
		let shown = host.renderer.drawn.map(\.component.text)
		print("friends tab texts: \(shown.filter { !$0.isEmpty })")
		XCTAssertTrue(shown.contains { $0.contains("Zezima") }, "\(shown)")
		XCTAssertTrue(shown.contains { $0.contains("Iron Man") }, "\(shown)")
	}

	// MARK: ambient area sounds

	/// The first synth sound that decodes to samples.
	func firstSynthId(_ a: AudioArchives) throws -> Int {
		let ids = try a.synth.store.index(4).groupIds.filter { $0 > 0 }
		return try XCTUnwrap(ids.first { SynthSound.create(archive: a.synth, group: $0)?.toPcmSound().samples.isEmpty == false })
	}

	func testAreaSoundsFollowListenerDistanceAndLevel() throws {
		let archives = AudioArchives(store: try store())
		let mixer = AudioMixer(archives: archives)
		let area = mixer.effects.area
		let sound = try firstSynthId(archives)

		var loc = LocType(id: 1)
		loc.bgSound = sound
		loc.bgSoundRange = 5 // tiles
		area.addLoc(loc, x: 50, z: 50, level: 0, width: 1, length: 1)
		XCTAssertEqual(area.counts.locs, 1)

		// 20 tiles away: out of range, nothing plays.
		area.redraw(cycles: 1, xFine: 70 * 128, zFine: 50 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.loops, 0)
		// Two tiles past the loc's east edge: distance 256 - 64 = 192 of radius 640, volume (640 - 192) * 127 / 640.
		area.redraw(cycles: 1, xFine: 53 * 128, zFine: 50 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.loops, 1)
		let near = try XCTUnwrap(mixer.effects.mixer.voices.first)
		XCTAssertEqual(near.currentVolume, ((640 - 192) * 127 / 640) << 6)
		// Standing next to it is louder, and the same voice is reused.
		area.redraw(cycles: 1, xFine: 51 * 128 + 64, zFine: 50 * 128, level: 0)
		XCTAssertEqual(mixer.effects.mixer.voices.count, 1)
		XCTAssertEqual(near.currentVolume, 127 << 6)
		// It is audible in the mix.
		var pcm: [Int16] = []
		mixer.render(into: &pcm, frames: 2048)
		XCTAssertTrue(pcm.contains { $0 != 0 }, "the ambient loop reaches the output")
		// Another level is silent; coming back restarts it; ambient volume 0 mutes it.
		area.redraw(cycles: 1, xFine: 51 * 128, zFine: 50 * 128, level: 1)
		XCTAssertEqual(area.voiceCounts.loops, 0)
		area.redraw(cycles: 1, xFine: 51 * 128, zFine: 50 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.loops, 1)
		mixer.effects.ambientVolume = 0
		area.redraw(cycles: 1, xFine: 51 * 128, zFine: 50 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.loops, 0)
		mixer.effects.ambientVolume = 127
		area.redraw(cycles: 1, xFine: 51 * 128, zFine: 50 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.loops, 1)
		// Removing the loc ends the loop.
		area.removeLoc(id: 1, x: 50, z: 50, level: 0)
		XCTAssertEqual(area.counts.locs, 0)
		XCTAssertEqual(area.voiceCounts.loops, 0)
		XCTAssertTrue(mixer.effects.mixer.voices.isEmpty)
	}

	func testAreaSoundOneShotsAndMultiLocs() throws {
		let archives = AudioArchives(store: try store())
		let mixer = AudioMixer(archives: archives)
		let area = mixer.effects.area
		let sound = try firstSynthId(archives)

		// bgsounds: a one-shot every 4 cycles (min = max = 4).
		var shots = LocType(id: 2)
		shots.bgSounds = [sound]
		shots.bgSoundRange = 4
		shots.bgSoundInterval = (min: 4, max: 4)
		area.addLoc(shots, x: 10, z: 10, level: 0, width: 2, length: 1)
		area.redraw(cycles: 2, xFine: 10 * 128, zFine: 10 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.oneShots, 0, "4 cycles have not passed")
		area.redraw(cycles: 2, xFine: 10 * 128, zFine: 10 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.oneShots, 1)
		XCTAssertEqual(area.voiceCounts.loops, 0)
		area.clearLocs()
		XCTAssertTrue(mixer.effects.mixer.voices.isEmpty)

		// A multi-loc follows its variable: variant A plays, variant none is silent.
		var variantOn = LocType(id: 4)
		variantOn.bgSound = sound
		variantOn.bgSoundRange = 3
		var multi = LocType(id: 3)
		multi.multiLocs = [4, -1]
		var on = true
		area.resolveLoc = { _ in on ? variantOn : nil }
		area.addLoc(multi, x: 20, z: 20, level: 0, width: 1, length: 1)
		area.redraw(cycles: 1, xFine: 20 * 128, zFine: 20 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.loops, 1)
		on = false
		area.redraw(cycles: 1, xFine: 20 * 128, zFine: 20 * 128, level: 0)
		XCTAssertEqual(area.voiceCounts.loops, 0)
	}

	func testActorAmbientSoundsChangeWithMovement() throws {
		let archives = AudioArchives(store: try store())
		let mixer = AudioMixer(archives: archives)
		let area = mixer.effects.area
		let sound = try firstSynthId(archives)
		func npc(sound: Int, x: Int) -> ActorSoundInfo {
			ActorSoundInfo(key: 7, isPlayer: false, xFine: x, zFine: 5000, size: 1, sound: sound, radius: 6)
		}
		area.syncActors([npc(sound: sound, x: 5000)])
		area.redraw(cycles: 1, xFine: 5100, zFine: 5000, level: 0)
		XCTAssertEqual(area.counts.npcs, 1)
		XCTAssertEqual(area.voiceCounts.loops, 1)
		let v = mixer.effects.mixer.voices[0]
		let loud = v.currentVolume
		// It walks away: the same voice gets quieter.
		area.syncActors([npc(sound: sound, x: 5000 + 5 * 128)])
		area.redraw(cycles: 1, xFine: 5100, zFine: 5000, level: 0)
		XCTAssertLessThan(v.currentVolume, loud)
		// Its movement changes to an animation without a sound: the loop is dropped.
		area.syncActors([npc(sound: -1, x: 5000)])
		area.redraw(cycles: 1, xFine: 5100, zFine: 5000, level: 0)
		XCTAssertEqual(area.voiceCounts.loops, 0)
		area.syncActors([])
		XCTAssertEqual(area.counts.npcs, 0)

		// rt4 getSound: walk by default, idle / run / crawl for their animation families.
		var bas = BasType(id: 1)
		bas.idle = 10; bas.walk = 11; bas.run = 12; bas.runFullTurn = 13; bas.slowWalk = 14
		func pick(_ seq: Int) -> Int { WorldView.movementSound(moveSeq: seq, bas: bas, idle: 100, crawl: 400, walk: 200, run: 300) }
		XCTAssertEqual([pick(10), pick(11), pick(12), pick(13), pick(14), pick(99)], [100, 200, 300, 300, 400, 200])
	}

	// MARK: touch preview

	/// A finger held over the world shows the default action at the top left; lifting hides it.
	func testHeldFingerPreviewsTheTapAction() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		let me = 2047
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var pipe = GameSession.Pipeline(selfId: me)
		for p in try SessionReplayTests.recordedPackets("resizable-session") {
			for e in pipe.handle(p) {
				client.handle(e)
				if case .players = e { for _ in 0..<30 { client.world.cycle(varps: client.state.varps) } }
			}
		}
		_ = try client.frame(width: 1015, height: 469)
		let v = try XCTUnwrap(client.viewport)
		// Scan the viewport for the first point that has any entry.
		var texts: Set<String> = []
		var sample: (Int, Int)?
		for y in stride(from: v.y + 20, to: v.y + v.h - 20, by: 90) {
			for x in stride(from: v.x + 20, to: v.x + v.w - 20, by: 90) {
				client.previewTap(x: x, y: y)
				if let t = client.interaction.preview { texts.insert(t); if sample == nil { sample = (x, y) } }
			}
		}
		print("tap previews over the world: \(texts.sorted().prefix(8))")
		XCTAssertTrue(texts.contains { $0.contains("Walk here") }, "\(texts)")
		let (sx, sy) = try XCTUnwrap(sample)
		client.previewTap(x: sx, y: sy)
		let without = try client.frame(width: 1015, height: 469)
		XCTAssertNotNil(client.interaction.preview)
		client.clearPreview()
		let plain = try client.frame(width: 1015, height: 469)
		XCTAssertNil(client.interaction.preview)
		XCTAssertNotEqual(without.pixels, plain.pixels, "the hint text is drawn")
		try save(without, "touch-preview")
		// Off the world (the tab area) there is no preview.
		client.previewTap(x: 5, y: 460)
		XCTAssertNil(client.interaction.preview)
	}
}
