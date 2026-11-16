import Foundation
import XCTest
@testable import Scape530

/// Chat, overhead text, hit splats, health bars and spot animations.
final class SocialTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	// MARK: Huffman

	/// A table whose canonical code is worked out by hand from rt4's constructor:
	/// a = 0, b = 10, c = 110, d = 111 (code lengths 1, 2, 3, 3 for symbols 97...100).
	static func tinyTable() -> [UInt8] {
		var bits = [UInt8](repeating: 0, count: 256)
		bits[97] = 1; bits[98] = 2; bits[99] = 3; bits[100] = 3
		return bits
	}

	func testHuffmanMatchesHandDerivedBytes() throws {
		let codec = HuffmanCodec(bits: Self.tinyTable())
		// abcd = 0 10 110 111 -> 0101 1011 1000 0000
		XCTAssertEqual(try codec.encode(Array("abcd".utf8)), [0x5B, 0x80])
		// dcba = 111 110 10 0 -> 1111 1010 0000 0000
		XCTAssertEqual(try codec.encode(Array("dcba".utf8)), [0xFA, 0x00])
		// aaaaaaaaa (nine zero bits) is two bytes of zeros
		XCTAssertEqual(try codec.encode(Array("aaaaaaaaa".utf8)), [0x00, 0x00])
		XCTAssertEqual(try codec.decode([0x5B, 0x80], length: 4).bytes, Array("abcd".utf8))
		XCTAssertEqual(try codec.decode([0xFA, 0x00], length: 4).bytes, Array("dcba".utf8))
		XCTAssertEqual(try codec.decode([0xFA, 0x00], length: 4).consumed, 2)
		XCTAssertThrowsError(try codec.encode(Array("e".utf8)))
		// WordPack adds the length smart in front.
		XCTAssertEqual(try WordPack.encode("abcd", codec: codec), [0x04, 0x5B, 0x80])
		XCTAssertEqual(WordPack.decode([0x04, 0x5B, 0x80], codec: codec), "abcd")
	}

	/// A complete prefix code over all 256 symbols with mixed lengths: 128 symbols of 8 bits, 64 of 7 bits... = Kraft sum 1.
	func testHuffmanRoundTripsRandomText() throws {
		var bits = [UInt8](repeating: 0, count: 256)
		for i in 0..<256 { bits[i] = i < 128 ? 8 : (i < 192 ? 7 : 0) }
		bits[192] = 0
		let codec = HuffmanCodec(bits: bits)
		var rng = SystemRandomNumberGenerator()
		for _ in 0..<200 {
			let n = Int.random(in: 1...300, using: &rng)
			let text = (0..<n).map { _ in UInt8.random(in: 0..<192, using: &rng) }
			let packed = try codec.encode(text)
			XCTAssertEqual(try codec.decode(packed, length: n).bytes, text)
		}
	}

	func testWordPackTextRules() {
		XCTAssertEqual(WordPack.sentenceCase("hELLO there. how ARE you? fine!"), "Hello there. How Are you? Fine!")
		XCTAssertEqual(WordPack.escape("a<b>c"), "a<lt>b<gt>c")
		XCTAssertEqual(WordPack.displayName(Base37.encode("mr_big guy")), "Mr Big Guy")
		let p = InterfaceScriptHost.parseChatPrefixes("Flash2:wave:Hello")
		XCTAssertEqual(p.colour, 7)
		XCTAssertEqual(p.effect, 1)
		XCTAssertEqual(p.text, "Hello")
		let q = InterfaceScriptHost.parseChatPrefixes("no prefix")
		XCTAssertEqual([q.colour, q.effect], [0, 0])
		XCTAssertEqual(q.text, "no prefix")
		XCTAssertEqual(InterfaceScriptHost.parseChatPrefixes("glow3:scroll:x").colour, 11)
		XCTAssertEqual(InterfaceScriptHost.parseChatPrefixes("glow3:scroll:x").effect, 4)
	}

	func testClientChatPackets() {
		var cipher = IsaacRandom(seed: [0, 0, 0, 0])
		let pub = ClientMessage.publicChat(colour: 3, effect: 2, text: [4, 0x5B, 0x80]).encode(&cipher)
		XCTAssertEqual(pub, [237, 5, 3, 2, 4, 0x5B, 0x80])
		let priv = ClientMessage.privateMessage(name37: 0x0102, text: [4, 0x5B, 0x80]).encode(&cipher)
		XCTAssertEqual(priv, [201, 11, 0, 0, 0, 0, 0, 0, 1, 2, 4, 0x5B, 0x80])
		XCTAssertEqual(ClientMessage.command("tele 1,2").encode(&cipher), [44, 9] + Array("tele 1,2".utf8) + [0])
	}

	func testGameMessageSuffixes() {
		var log = ChatLog()
		log.addGameMessage("Welcome to the game.")
		log.addGameMessage("Bob:tradereq:")
		log.addGameMessage("Alice:chalreq:with a 5 stake:chalreq:".replacingOccurrences(of: ":chalreq:with a 5 stake", with: ":on a stake"))
		log.addGameMessage("Zed:tradereq:", ignored: [Base37.encode("Zed")])
		XCTAssertEqual(log.size, 3)
		XCTAssertEqual(log.line(2), ChatLine(type: 0, name: "", message: "Welcome to the game.", clan: nil, phraseId: -1))
		XCTAssertEqual(log.line(1)?.type, 4)
		XCTAssertEqual(log.line(1)?.name, "Bob")
		XCTAssertEqual(log.line(0)?.type, 8)
		XCTAssertEqual(log.line(0)?.message, "on a stake")
		for i in 0..<120 { log.add(type: 0, name: "", message: "m\(i)") }
		XCTAssertEqual(log.lines.count, 100)
		XCTAssertEqual(log.line(0)?.message, "m119")
		XCTAssertEqual(log.size, 123)
	}

	func testPrivateMessageDecoding() throws {
		let payload: [UInt8] = [0, 0, 0, 0, 0, 0, 0x12, 0x34, 0x00, 0x01, 0x00, 0x00, 0x02, 0x01, 9, 8, 7]
		let m = try ServerMessage.decode(GamePacket(opcode: ServerProt.messagePrivate, payload: payload))
		XCTAssertEqual(m, .privateMessage(name37: 0x1234, messageId: 0x1_0000_0002, rights: 1, text: [9, 8, 7]))
		let e = try ServerMessage.decode(GamePacket(opcode: ServerProt.messagePrivateEcho, payload: [0, 0, 0, 0, 0, 0, 0, 5, 1, 2]))
		XCTAssertEqual(e, .privateMessageEcho(name37: 5, text: [1, 2]))
	}

	// MARK: real cache

	func testRealHuffmanTable() throws {
		let s = try store()
		let codec = try XCTUnwrap(try WordPack.loadCodec(s))
		for text in ["Hello world!", "how much for the rune scimitar? 99 gp", "::tele 3222,3218", "lol xD :)", "The quick brown fox jumps over the lazy dog"] {
			let packed = try WordPack.encode(text, codec: codec)
			XCTAssertEqual(WordPack.decode(packed, codec: codec), text)
		}
		// Common letters compress: "e" takes fewer bits than the 8-bit raw byte.
		XCTAssertLessThan(try codec.encode(Array("eeeeeeee".utf8)).count, 8)
	}

	/// Typing in game reaches the chatbox scripts (CS2 `onKey` on the chat line), and Enter runs op 5008
	/// (`sayPublic`), which sends PUBLIC_CHAT through the huffman encoder. Uses the recorded fixed session
	/// because the resizable one stands on Tutorial Island with an instruction panel covering the chat.
	func testTypingInGameSendsPublicChat() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replayResizable(client, session: "login-session", me: 11)
		var sent: [ClientMessage] = []
		client.host.send = { sent.append($0) }
		try save(try client.frame(width: 1015, height: 469), "social-chat-box")
		client.type("hello there")
		// The chat line shows what is being typed, as rt4 does: "Name: text*".
		let line = try XCTUnwrap(client.host.component(ComponentRef(id: 137 << 16 | 51))?.text)
		XCTAssertTrue(line.hasSuffix("hello there*"), line)
		client.enter()
		let codec = try XCTUnwrap(try WordPack.loadCodec(s))
		let chats = sent.compactMap { m -> (Int, Int, [UInt8])? in if case let .publicChat(c, e, t) = m { return (c, e, t) } else { return nil } }
		XCTAssertEqual(chats.count, 1, "sent: \(sent)")
		if let c = chats.first {
			XCTAssertEqual(WordPack.decode(c.2, codec: codec), "hello there")
			XCTAssertEqual([c.0, c.1], [0, 0])
		}
		// Colour and effect prefixes become the packet's colour and effect bytes.
		sent.removeAll()
		client.type("red:wave:ahoy")
		client.enter()
		if case let .publicChat(c, e, t)? = sent.first {
			XCTAssertEqual([c, e], [1, 1])
			XCTAssertEqual(WordPack.decode(t, codec: codec), "ahoy")
		} else {
			XCTFail("no chat sent: \(sent)")
		}
		// Typed commands go out as CLIENT_CHEAT.
		sent.removeAll()
		client.type("::tele 1,2,3")
		client.enter()
		XCTAssertTrue(sent.contains { if case .command("tele 1,2,3") = $0 { return true } else { return false } }, "sent: \(sent)")
		// The chat line is an input: tapping it summons the keyboard, the world does not.
		XCTAssertFalse(client.wantsKeyboard)
		client.toggleKeyboard()
		XCTAssertTrue(client.wantsKeyboard)
	}

	/// Crops `r` to a rectangle and scales it up (nearest) so small overlays are easy to look at.
	func crop(_ r: Raster, x: Int, y: Int, w: Int, h: Int, scale: Int) -> Raster {
		var out = Raster(width: w * scale, height: h * scale)
		for yy in 0..<(h * scale) {
			for xx in 0..<(w * scale) {
				let sx = min(max(x + xx / scale, 0), r.width - 1), sy = min(max(y + yy / scale, 0), r.height - 1)
				out.pixels[yy * out.width + xx] = r.pixels[sy * r.width + sx]
			}
		}
		return out
	}

	/// A spot animation id whose graphic has a model and a sequence.
	func animatedSpot(_ s: ConfigStore) throws -> Int {
		for id in 1..<800 {
			guard let t = try s.spotAnim(id), t.model != 0, t.seq != -1, let seq = try s.seq(t.seq), seq.frames.count > 3 else { continue }
			if try s.spotAnimBody(t) != nil { return id }
		}
		throw XCTSkip("no animated spot animation in this cache")
	}

	/// Inbound chat, overhead text, a hit splat with a health bar and a spot animation, drawn into the world frame.
	func testOverheadsHitsplatsAndSpotAnimRender() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replayResizable(client, session: "login-session", me: 11)
		let world = client.world
		let decoder = try XCTUnwrap(client.state.players)
		let npcDecoder = try XCTUnwrap(client.state.npcs)
		let codec = try XCTUnwrap(try WordPack.loadCodec(s))
		let spot = try animatedSpot(s)

		// A tick of player info: our own public chat (wave effect, flashing colour), a normal hit with a
		// health bar, and a graphic. Chat arrives huffman-packed, exactly as rt4's mask 0x80 carries it.
		var mine = EntityMasks()
		mine.publicChat = (effects: 6 << 8 | 1, rights: 0, encoded: try WordPack.encode("hELLO everyone, i am <here>!", codec: codec))
		mine.hits = [HitSplat(damage: 12, type: 1)]
		mine.healthBar = 150
		mine.spotAnim = SpotAnimUpdate(id: spot, height: 60, delay: 0)
		var result = PlayerInfoDecoder.Result()
		result.updated[11] = mine
		client.handle(.players(result, decoder))
		let a = try XCTUnwrap(world.ctx.players[11])
		XCTAssertEqual(a.chatMessage, "Hello everyone, i am <lt>here<gt>!")
		XCTAssertEqual(a.chatLoops, 150)
		XCTAssertEqual([a.chatColor, a.chatEffect], [6, 1])
		XCTAssertEqual(a.hitDamages[0], 12)
		XCTAssertEqual(a.spotAnimId, spot)
		let line = try XCTUnwrap(client.state.chatLog.line(0))
		XCTAssertEqual(line.type, 2)
		XCTAssertEqual(line.name, "Walker3")
		XCTAssertEqual(line.message, "Hello everyone, i am <lt>here<gt>!")

		// An npc shouts and takes a blocked hit and a hard one.
		let (npcId, _) = try XCTUnwrap(world.ctx.npcs.sorted { $0.key < $1.key }.first)
		var theirs = EntityMasks()
		theirs.forceChat = "Grr!"
		theirs.hits = [HitSplat(damage: 0, type: 0), HitSplat(damage: 31, type: 2)]
		theirs.healthBar = 70
		var nr = PlayerInfoDecoder.Result()
		nr.updated[npcId] = theirs
		client.handle(.npcs(nr, npcDecoder))
		XCTAssertEqual(world.ctx.npcs[npcId]?.chatMessage, "Grr!")
		XCTAssertEqual(world.ctx.npcs[npcId]?.chatLoops, 100)

		// A few cycles: the spot animation starts, chat counts down.
		for _ in 0..<6 { world.cycle(varps: client.state.varps) }
		XCTAssertEqual(a.chatLoops, 144)
		XCTAssertGreaterThan(a.hitVisibleUntil[0], world.ctx.loop)
		XCTAssertGreaterThanOrEqual(a.spotFrame, 0)
		// Advance the graphic to the middle of its sequence (it starts small).
		let spotSeq = try XCTUnwrap(try s.seq(try XCTUnwrap(try s.spotAnim(spot)).seq))
		var guardCycles = 0
		while a.spotFrame < spotSeq.frames.count / 2 && a.spotAnimId != -1 && guardCycles < 400 {
			world.cycle(varps: client.state.varps)
			guardCycles += 1
		}
		XCTAssertNotEqual(a.spotAnimId, -1)
		XCTAssertGreaterThan(a.chatLoops, 0)

		let (w, h) = (1015, 469)
		var withOverlays = Raster(width: w, height: h)
		XCTAssertTrue(world.draw(into: &withOverlays, rect: (0, 0, w, h)))
		try save(withOverlays, "social-overlays-full")
		let cam = try XCTUnwrap(world.overlayCamera)
		let scene = try XCTUnwrap(world.scene)
		let head = try XCTUnwrap(world.project(cam, xFine: a.xFine, zFine: a.zFine, height: a.modelHeight, scene: scene))
		try save(crop(withOverlays, x: head.x - 130, y: head.y - 70, w: 260, h: 210, scale: 3), "social-overlays-crop")

		do {
			// Only the graphic: hide chat, bars and splats, keep the spot animation.
			let saved = (a.chatMessage, a.hitVisibleUntil, a.hitpointsBarVisibleUntil)
			a.chatMessage = nil; a.hitVisibleUntil = [0, 0, 0, 0]; a.hitpointsBarVisibleUntil = -1000
			var only = Raster(width: w, height: h)
			XCTAssertTrue(world.draw(into: &only, rect: (0, 0, w, h)))
			let saveSpot = a.spotAnimId
			a.spotAnimId = -1
			var none = Raster(width: w, height: h)
			XCTAssertTrue(world.draw(into: &none, rect: (0, 0, w, h)))
			a.spotAnimId = saveSpot
			(a.chatMessage, a.hitVisibleUntil, a.hitpointsBarVisibleUntil) = saved
			var n = 0
			for i in 0..<only.pixels.count where only.pixels[i] != none.pixels[i] { n += 1 }
			let t = try XCTUnwrap(try s.spotAnim(spot))
			let m = try XCTUnwrap(try s.spotAnimModel(t, frame: a.spotFrame, nextFrame: a.spotNext, step: a.spotStep))
			XCTAssertGreaterThan(n, 150, "the spot animation model is drawn")
			try save(crop(only, x: head.x - 130, y: head.y - 70, w: 260, h: 210, scale: 3), "social-spotanim-crop")
		}
		// The same frame with every overlay state cleared: only the overlays differ.
		for actor in Array(world.ctx.players.values) + Array(world.ctx.npcs.values) {
			actor.chatMessage = nil
			actor.hitVisibleUntil = [0, 0, 0, 0]
			actor.hitpointsBarVisibleUntil = -1000
			actor.spotAnimId = -1
		}
		var bare = Raster(width: w, height: h)
		XCTAssertTrue(world.draw(into: &bare, rect: (0, 0, w, h)))
		func differing(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Int {
			var n = 0
			for y in max(y0, 0)..<min(y1, h) { for x in max(x0, 0)..<min(x1, w) where withOverlays.pixels[y * w + x] != bare.pixels[y * w + x] { n += 1 } }
			return n
		}
		// Overhead text and health bar sit above the head, the splat on the body, the graphic around the feet.
		XCTAssertGreaterThan(differing(head.x - 120, head.y - 60, head.x + 120, head.y - 5), 150, "overhead chat and health bar")
		let body = try XCTUnwrap(world.project(cam, xFine: a.xFine, zFine: a.zFine, height: a.modelHeight / 2, scene: scene))
		XCTAssertGreaterThan(differing(body.x - 16, body.y - 16, body.x + 16, body.y + 16), 100, "hit splat")
		let feet = try XCTUnwrap(world.project(cam, xFine: a.xFine, zFine: a.zFine, height: 30, scene: scene))
		XCTAssertGreaterThan(differing(feet.x - 60, feet.y - 90, feet.x + 60, feet.y + 20), 100, "spot animation")
		// The npc's splats show too.
		let npc = try XCTUnwrap(world.ctx.npcs[npcId])
		_ = try XCTUnwrap(world.project(cam, xFine: npc.xFine, zFine: npc.zFine, height: npc.modelHeight, scene: scene))
	}

	/// Chat lines arriving as session events: game messages with request suffixes, private messages and echoes.
	func testInboundMessagesReachTheChatLog() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replayResizable(client, session: "login-session", me: 11)
		let codec = try XCTUnwrap(try WordPack.loadCodec(s))
		let before = client.state.chatLog.size
		client.handle(.message(.gameMessage("You find a coin.")))
		client.handle(.message(.gameMessage("Bob:tradereq:")))
		client.handle(.message(.privateMessage(name37: Base37.encode("bob_smith"), messageId: 77, rights: 0, text: try WordPack.encode("sUP mate", codec: codec))))
		client.handle(.message(.privateMessage(name37: Base37.encode("bob_smith"), messageId: 77, rights: 0, text: try WordPack.encode("sUP mate", codec: codec))))
		client.handle(.message(.privateMessage(name37: Base37.encode("mod_x"), messageId: 78, rights: 2, text: try WordPack.encode("hello", codec: codec))))
		client.handle(.message(.privateMessageEcho(name37: Base37.encode("bob_smith"), text: try WordPack.encode("hi bob", codec: codec))))
		let log = client.state.chatLog
		XCTAssertEqual(log.size - before, 5, "the repeated private message id is dropped")
		XCTAssertEqual(log.line(0), ChatLine(type: 6, name: "Bob Smith", message: "Hi bob", clan: nil, phraseId: -1))
		XCTAssertEqual(log.line(1)?.type, 7)
		XCTAssertEqual(log.line(1)?.name, "<img=1>Mod X")
		XCTAssertEqual(log.line(2), ChatLine(type: 3, name: "Bob Smith", message: "Sup mate", clan: nil, phraseId: -1))
		XCTAssertEqual(log.line(3)?.type, 4)
		XCTAssertEqual(log.line(4)?.message, "You find a coin.")
		// The chatbox hooks fire: the chat transmit timer moved past the components' last read.
		XCTAssertGreaterThan(client.host.chatAt, 0)
		// The chatbox scripts pick the lines up through the CS2 chat ops and draw them.
		var chatboxFrame = try client.frame(width: 1015, height: 469)
		for _ in 0..<3 { chatboxFrame = try client.frame(width: 1015, height: 469) }
		try save(chatboxFrame, "social-chatbox-inbound")
		// Ignoring a name drops its private messages.
		client.handle(.message(.ignoreList([Base37.encode("spammer")])))
		let n = client.state.chatLog.size
		client.handle(.message(.privateMessage(name37: Base37.encode("spammer"), messageId: 99, rights: 0, text: try WordPack.encode("buy gold", codec: codec))))
		XCTAssertEqual(client.state.chatLog.size, n)
	}

	/// With a live server (`SCAPE530_SERVER=host:port`): log in, send a public chat message and see our own
	/// words come back in player info (the server echoes public chat to the speaker).
	func testLivePublicChatEcho() throws {
		let env = ProcessInfo.processInfo.environment
		guard let server = env["SCAPE530_SERVER"] else { throw XCTSkip("needs SCAPE530_SERVER") }
		let parts = server.split(separator: ":")
		let client = try GameClient(store: try store(), server: .init(host: String(parts[0]), port: Int(parts[1]) ?? 43595))
		let (w, h) = (1015, 469)
		_ = try client.frame(width: w, height: h)
		let d = try XCTUnwrap(client.ui.drawn.last { $0.component.id == client.loginInterface << 16 | 250 })
		client.tap(x: d.x + d.w / 2, y: d.y + d.h / 2)
		client.type("socialbot\ntester\n")
		let deadline = Date().addingTimeInterval(25)
		while Date() < deadline && (client.screen != .game || client.state.ticks < 12) {
			Thread.sleep(forTimeInterval: 0.02)
			_ = try client.frame(width: w, height: h)
		}
		XCTAssertEqual(client.screen, .game, "status: \(client.status)")
		let codec = try XCTUnwrap(try WordPack.loadCodec(client.store))
		client.send(.publicChat(colour: 3, effect: 1, text: try WordPack.encode("hello from swift", codec: codec)))
		var echoed = false
		let until = Date().addingTimeInterval(8)
		var frame = try client.frame(width: w, height: h)
		while Date() < until && !echoed {
			Thread.sleep(forTimeInterval: 0.02)
			frame = try client.frame(width: w, height: h)
			echoed = client.state.chatLog.lines.contains { ($0.type == 1 || $0.type == 2) && $0.message == "Hello from swift" } // type 1 when the server gives the account a staff icon
		}
		XCTAssertTrue(echoed, "chat log: \(client.state.chatLog.lines.prefix(5))")
		try save(frame, "social-live-chat")
		client.logout()
	}

	/// Feeds the recorded resizable session into `client` (see `WorldViewTests.replay`).
	func replayResizable(_ client: GameClient, session: String = "resizable-session", me: Int = 2047, cyclesPerTick: Int = 30) throws {
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var players = PlayerInfoDecoder(selfIndex: me, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?
		for pkt in try SessionReplayTests.recordedPackets(session) {
			switch pkt.opcode {
			case ServerProt.playerInfo:
				let r = try players.decode(pkt.payload)
				client.handle(.players(r, players))
				for _ in 0..<cyclesPerTick { client.world.cycle(varps: client.state.varps) }
			case ServerProt.npcInfo:
				let p = try XCTUnwrap(players.players[me])
				let r = try npcs.decode(pkt.payload, selfX: p.x, selfZ: p.z)
				client.handle(.npcs(r, npcs))
			default:
				let m = try ServerMessage.decode(pkt)
				if case .rebuildNormal(let r) = m {
					if let z = zone {
						players.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
						npcs.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
					} else {
						players = PlayerInfoDecoder(selfIndex: me, localX: r.localX, localZ: r.localZ)
					}
					zone = (r.zoneX, r.zoneZ)
				}
				client.handle(.message(m))
			}
		}
	}
}
