import Foundation

/// `VarpType.clientCode` values rt4 acts on (`VarpDomain.refreshMagicVarp`).
public enum VarpClientCode {
	/// Single mouse button mode (rt4 `VarpDomain.anInt2952`): a left click opens the menu when it has options.
	public static let mouseButtons = 5
	/// Chat effects (rt4 `VarpDomain.chatEffectsDisabled`): non-zero draws overhead text plain.
	public static let chatEffects = 6
	/// Bank insert mode (rt4 `VarpDomain.inserting`): item drags insert instead of swap.
	public static let insertMode = 9
}

/// Client-side state derived from varps that carry a `clientCode`.
public struct VarpClientState: Equatable {
	public var mouseButtons = 0
	public var chatEffectsDisabled = 0
	public var inserting = 0
}

extension InterfaceScriptHost {
	/// rt4 `VarpDomain.refreshMagicVarp(id)`: after varp `id` changed, applies its `clientCode` side effect.
	/// Varps without a type or with code 0 do nothing.
	func refreshMagicVarp(_ id: Int) {
		guard let code = (try? store.varpType(id))??.clientCode, code != 0 else { return }
		let value = Int(game.varps[id] ?? 0)
		switch code {
		case VarpClientCode.chatEffects: varpClient.chatEffectsDisabled = value
		case VarpClientCode.mouseButtons: varpClient.mouseButtons = value
		case VarpClientCode.insertMode: varpClient.inserting = value
		default: break
		}
		onVarpClientCode(code, value)
	}

	/// rt4 `VarpDomain.reset`: clears every varp whose `clientCode` is 0; the client-owned ones survive.
	func resetVarps() {
		game.varps = game.varps.filter { id, _ in
			((try? store.varpType(id))??.clientCode ?? 0) != 0
		}
	}
}
