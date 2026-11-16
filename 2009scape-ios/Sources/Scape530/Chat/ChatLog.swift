import Foundation

/// One chat history entry (the columns of rt4 `Chat.types/names/messages/clans/phraseIds`).
public struct ChatLine: Equatable {
	/// rt4 chat type: 0 game, 1 public (staff), 2 public, 3 private, 4 trade request,
	/// 5 friend status, 6 private echo, 7 private (staff), 8 challenge request, 9 clan,
	/// 10 assist request, 11 clan notice, 12 trade, 13 assist, 14 duel stake, 15 duel friend,
	/// 16 clan request, 17 quick chat, 18 clan quick chat, 19 quick chat echo, 20 clan quick chat, 21 ally request.
	public var type: Int
	public var name: String?
	public var message: String
	public var clan: String?
	public var phraseId: Int
}

/// Port of rt4 `Chat`: the 100 newest chat lines, newest first, which the chatbox
/// scripts read through ops 5003 to 5012 and 5017.
public struct ChatLog: Equatable {
	public static let capacity = 100
	/// Newest first (rt4 index 0 is the latest line).
	public private(set) var lines: [ChatLine] = []
	/// rt4 `Chat.size`: lines ever added (the scripts compare it to know something arrived).
	public private(set) var size = 0
	/// rt4 `Chat.recentMessages`: ids of the last 100 private messages, so repeats are dropped.
	var recentMessages = [Int64](repeating: 0, count: 100)
	var messageCounter = 0

	public init() {}

	/// rt4 `Chat.add(phraseId, type, message, clan, name)`.
	public mutating func add(type: Int, name: String?, message: String, clan: String? = nil, phraseId: Int = -1) {
		lines.insert(ChatLine(type: type, name: name, message: message, clan: clan, phraseId: phraseId), at: 0)
		if lines.count > Self.capacity { lines.removeLast() }
		size += 1
	}

	/// The line at script index `i` (0 = newest), if any.
	public func line(_ i: Int) -> ChatLine? { i >= 0 && i < lines.count ? lines[i] : nil }

	/// True when a private message id is among the last 100 (rt4 drops repeats).
	func hasSeen(messageId: Int64) -> Bool { recentMessages.contains(messageId) }

	/// Records a private message id; false when it was already there.
	@discardableResult
	mutating func remember(messageId: Int64) -> Bool {
		if recentMessages.contains(messageId) { return false }
		recentMessages[messageCounter] = messageId
		messageCounter = (messageCounter + 1) % 100
		return true
	}

	// MARK: MESSAGE_GAME (rt4 `Protocol` opcode MESSAGE_GAME)

	/// Chat types for the special suffixes the server appends to game messages
	/// (`:tradereq:`, `:chalreq:`, ...), with their canned texts.
	private static let requestSuffixes: [(suffix: String, type: Int, text: String?)] = [
		(":tradereq:", 4, "wishes to trade with you."),
		(":chalreq:", 8, nil),
		(":assistreq:", 10, ""),
		(":duelstake:", 14, ""),
		(":duelfriend:", 15, ""),
		(":clanreq:", 16, ""),
		(":allyreq:", 21, nil),
	]
	private static let noticeSuffixes: [(suffix: String, type: Int)] = [(":clan:", 11), (":trade:", 12), (":assist:", 13)]

	/// Adds a game message the way rt4 does: request suffixes become typed lines (dropped for
	/// ignored senders), everything else a plain type 0 line.
	public mutating func addGameMessage(_ message: String, ignored: Set<Int64> = []) {
		func isIgnored(_ name: String) -> Bool { ignored.contains(Base37.encode(name)) }
		for (suffix, type, text) in Self.requestSuffixes where message.hasSuffix(suffix) {
			guard let colon = message.firstIndex(of: ":") else { break }
			let name = String(message[..<colon])
			if isIgnored(name) { return }
			var body = text ?? ""
			if text == nil {
				// rt4: `message.substring(length - suffixLength, indexOf(':') + 1)` is the text between the name and the suffix.
				let start = message.index(after: colon)
				let end = message.index(message.endIndex, offsetBy: -suffix.count)
				body = start <= end ? String(message[start..<end]) : ""
			}
			add(type: type, name: name, message: body)
			return
		}
		for (suffix, type) in Self.noticeSuffixes where message.hasSuffix(suffix) {
			let name = String(message.dropLast(suffix.count))
			add(type: type, name: "", message: name)
			return
		}
		add(type: 0, name: "", message: message)
	}
}
