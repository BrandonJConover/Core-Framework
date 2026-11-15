/// Client -> server game packets. Bodies are ported from rt4's senders
/// (`ClientProt` helpers, `Cheat.java`, `Protocol` keepalive).
public enum ClientMessage {
	/// rt4 sends NO_TIMEOUT every 50 client cycles (~1 s) while idle.
	case keepAlive
	/// `::command` from the chatbox (rt4 `Cheat`), without the leading "::".
	case command(String)
	/// Walk to a world tile. `path` is the client pathfinder's turn points
	/// before `dest`, in walking order (world coords); empty lets the server
	/// path to `dest` itself.
	case walk(destX: Int, destZ: Int, path: [(x: Int, z: Int)] = [], ctrlRun: Bool = false, minimap: Bool = false)

	public func encode(_ cipher: inout IsaacRandom) -> [UInt8] {
		var p = Packet(capacity: 64)
		func op(_ o: Int) { p.p1(o + cipher.nextKey()) }
		switch self {
		case .keepAlive:
			op(ClientProt.noTimeout)
		case .command(let c):
			op(ClientProt.clientCheat)
			p.p1(Cp1252.encode(c).count + 1)
			p.pjstr(c)
		case let .walk(destX, destZ, path, ctrlRun, minimap):
			// rt4 (`ClientProt` walk sender) sends the first waypoint as an
			// absolute tile, then the following ones as offsets from it
			// (x as add, z as sub), truncated to 25 points.
			let points = Array((path.map { ($0.x, $0.z) } + [(destX, destZ)]).prefix(25))
			let steps = points.count
			op(minimap ? ClientProt.moveMinimapclick : ClientProt.moveGameclick)
			p.p1(steps * 2 + 3 + (minimap ? 14 : 0))
			p.p1add(ctrlRun ? 1 : 0)
			let (fx, fz) = points[0]
			p.p2(fx)
			p.p2add(fz)
			for (x, z) in points.dropFirst() {
				p.p1add(x - fx)
				p.p1sub(z - fz)
			}
			if minimap {
				// rt4 appends 14 bytes of camera/minimap state; zeros are accepted.
				p.pdata([UInt8](repeating: 0, count: 14))
			}
		}
		return p.written
	}
}
