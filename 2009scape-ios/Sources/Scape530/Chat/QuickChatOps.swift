import Foundation

/// CS2 quick chat ops 5050-5073 (rt4 `ScriptRunner`), answered from the quick chat archives.
extension InterfaceScriptHost {
	/// rt4 `ScriptRunner.activePhrase`, `Find.results/index/size` for the phrase search.
	struct QuickChatState {
		var phrase: QuickChatPhrase?
		var findResults: [Int]?
		var findIndex = 0
		var findSize = 0
	}

	func performQuickChat(_ op: HostOpSpec, ints a: [Int32], strings s: [String]) -> HostResult? {
		guard op.opcode >= 5050, op.opcode <= 5073 else { return nil }
		func i(_ n: Int) -> Int { n < a.count ? Int(a[n]) : 0 }
		func r(_ v: Int) -> HostResult { HostResult(ints: [Int32(truncatingIfNeeded: v)]) }
		func cat(_ n: Int) -> QuickChatCatType { ((try? store.quickChatCat(i(n))) ?? nil) ?? QuickChatCatType(id: i(n)) }
		func phrase(_ n: Int) -> QuickChatPhraseType { ((try? store.quickChatPhrase(i(n))) ?? nil) ?? QuickChatPhraseType(id: i(n)) }
		func at(_ list: [Int], _ n: Int) -> HostResult { r(n >= 0 && n < list.count ? list[n] : -1) }

		switch op.opcode {
		case 5050: return HostResult(strings: [cat(0).description])
		case 5051: return r(cat(0).subcategories.count)
		case 5052: return at(cat(0).subcategories, i(1))
		case 5053: return r(cat(0).phrases.count)
		case 5054: return at(cat(0).phrases, i(1))
		case 5055: return HostResult(strings: [phrase(0).text])
		case 5056: return r(phrase(0).automaticResponses.count)
		case 5057: return at(phrase(0).automaticResponses, i(1))
		case 5058:
			let t = phrase(0)
			quickChat.phrase = QuickChatPhrase(id: i(0), values: [Int32](repeating: 0, count: t.dynamicCommandCount))
		case 5059: sendQuickChat(.quickChat(clan: false, phrase: quickChat.phrase?.id ?? 0, values: quickChatBody()))
		case 5060:
			sendQuickChat(.quickChatPrivate(name37: Base37.encode(s.first ?? ""), phrase: quickChat.phrase?.id ?? 0, values: quickChatBody()))
		case 5061: sendQuickChat(.quickChat(clan: true, phrase: quickChat.phrase?.id ?? 0, values: quickChatBody()))
		case 5062: return at(cat(0).subcategoryShortcuts, i(1))
		case 5063: return at(cat(0).phraseShortcuts, i(1))
		case 5064:
			guard i(1) != -1 else { return r(-1) }
			let c = cat(0)
			return r(c.subcategoryShortcuts.firstIndex(of: i(1)).map { c.subcategories[$0] } ?? -1)
		case 5065:
			guard i(1) != -1 else { return r(-1) }
			let c = cat(0)
			return r(c.phraseShortcuts.firstIndex(of: i(1)).map { c.phrases[$0] } ?? -1)
		case 5066: return r(phrase(0).dynamicCommandCount)
		case 5067: return r(phrase(0).dynamicCommand(i(1)))
		case 5068, 5069:
			if var p = quickChat.phrase, i(0) >= 0, i(0) < p.values.count {
				p.values[i(0)] = Int32(truncatingIfNeeded: i(1))
				quickChat.phrase = p
			}
		case 5070:
			let t = phrase(0)
			guard t.dynamicCommand(i(1)) == 0 else { return r(-1) }
			return r(t.dynamicCommandParam(i(2), i(1)))
		case 5071:
			let found = QuickChat.search(secondary: i(0) == 1, needle: s.first ?? "", store: store)
			quickChat.findResults = found
			quickChat.findIndex = found?.count ?? -1
			quickChat.findSize = 0
			return r(quickChat.findIndex)
		case 5072:
			if let results = quickChat.findResults, quickChat.findSize < quickChat.findIndex {
				defer { quickChat.findSize += 1 }
				return r(results[quickChat.findSize] & 0xFFFF)
			}
			return r(-1)
		case 5073: quickChat.findSize = 0
		default: break
		}
		return HostResult()
	}

	/// The bytes `encodeMessage` writes for the phrase being composed.
	private func quickChatBody() -> [UInt8] {
		guard let p = quickChat.phrase else { return [] }
		return QuickChat.phraseBody(p, store: store)
	}

	private func sendQuickChat(_ m: ClientMessage) {
		guard quickChat.phrase != nil else { return }
		send(m)
	}
}
