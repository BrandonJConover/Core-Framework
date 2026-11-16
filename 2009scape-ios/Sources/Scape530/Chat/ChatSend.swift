import Foundation

/// Chat out: what the chatbox scripts do through CS2 ops 5008 (`sayPublic`) and 5009
/// (`sendPrivateMessage`), ported from rt4 `ScriptRunner`.
extension InterfaceScriptHost {
	/// rt4 `LocalizedText.STABLE_CHATCOL0...11`: typed prefixes selecting the overhead colour.
	static let chatColourPrefixes = ["yellow:", "red:", "green:", "cyan:", "purple:", "white:", "flash1:", "flash2:", "flash3:", "glow1:", "glow2:", "glow3:"]
	/// `STABLE_CHATEFFECT1...5` (and `STABLE_CHATEFFECTC5`): prefixes selecting the effect (1...5).
	static let chatEffectPrefixes = ["wave:", "wave2:", "shake:", "scroll:", "slide:"]

	/// rt4: members under 13 without consent, and quick-chat-only worlds, may not type (staff always may).
	var chatBlocked: Bool {
		guard let a = game.account else { return false }
		return a.staffModLevel == 0 && ((a.underage && !a.parentalChatConsent) || a.mapQuickChat)
	}

	/// Splits the colour and effect prefixes off a typed line (rt4 op 5008 body).
	static func parseChatPrefixes(_ typed: String) -> (colour: Int, effect: Int, text: String) {
		var text = typed
		var colour = 0, effect = 0
		let lower = text.lowercased()
		for (i, prefix) in chatColourPrefixes.enumerated() where lower.hasPrefix(prefix) {
			colour = i
			text = String(text.dropFirst(prefix.count))
			break
		}
		let lower2 = text.lowercased()
		for (i, prefix) in chatEffectPrefixes.enumerated() where lower2.hasPrefix(prefix) {
			effect = i + 1
			text = String(text.dropFirst(prefix.count))
			break
		}
		return (colour, effect, text)
	}

	/// rt4 op 5008: `::command` goes to the server as CLIENT_CHEAT, anything else as public chat.
	func sayPublic(_ line: String) {
		if line.hasPrefix("::") {
			send(.command(String(line.dropFirst(2))))
			return
		}
		guard !chatBlocked, let codec = (try? WordPack.loadCodec(store)) ?? nil else { return }
		let parsed = Self.parseChatPrefixes(line)
		guard let packed = try? WordPack.encode(parsed.text, codec: codec) else { return }
		send(.publicChat(colour: parsed.colour, effect: parsed.effect, text: packed))
	}

	/// rt4 op 5009.
	func sendPrivateMessage(to name: String, text: String) {
		guard !chatBlocked, let codec = (try? WordPack.loadCodec(store)) ?? nil,
		      let packed = try? WordPack.encode(text, codec: codec) else { return }
		send(.privateMessage(name37: Base37.encode(name), text: packed))
	}
}
