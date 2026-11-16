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
	/// IF_BUTTON1...IF_BUTTON10: option `op` (1...10) of component `component`
	/// (`interface << 16 | index`); `child` is the CS2-created child or the
	/// inventory slot, -1 for the component itself (rt4 `ClientProt.method4512`).
	case ifButton(op: Int, component: Int, child: Int)
	/// Opcode 10: an if1 button (button types 1, 4, 5) pressed (rt4 `MiniMenu` actions 8/51/59).
	case ifButtonLegacy(component: Int)
	/// Opcode 132: an if1 "continue" button (button type 6; rt4 `MiniMenu.method10`).
	case ifContinue(component: Int, child: Int)
	/// CLOSE_MODAL (rt4 `ClientProt.closeWidget`).
	case closeModal
	/// RESUME_P_COUNTDIALOG / RESUME_P_NAMEDIALOG / RESUME_P_STRINGDIALOG.
	case resumeCount(Int32)
	case resumeName(String)
	case resumeString(String)

	/// rt4 `ClientProt.method4512`: the opcode for IF_BUTTON1...10.
	static let ifButtonOpcodes = [155, 196, 124, 199, 234, 168, 166, 64, 53, 9]

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
		case let .ifButton(n, component, child):
			op(Self.ifButtonOpcodes[min(max(n, 1), 10) - 1])
			p.p4(component)
			p.p2(child)
		case .ifButtonLegacy(let component):
			op(10)
			p.p4(component)
		case let .ifContinue(component, child):
			// imp4(component), ip2(child)
			op(132)
			let v = Int32(truncatingIfNeeded: component)
			p.p1(Int(v >> 8)); p.p1(Int(v)); p.p1(Int(v >> 24)); p.p1(Int(v >> 16))
			p.ip2(child)
		case .closeModal:
			op(ClientProt.closeModal)
		case .resumeCount(let v):
			op(ClientProt.resumePCountdialog)
			p.p4(v)
		case .resumeName(let name):
			op(ClientProt.resumePNamedialog)
			p.p8(Base37.encode(name))
		case .resumeString(let s):
			op(ClientProt.resumePStringdialog)
			p.p1(Cp1252.encode(s).count + 1)
			p.pjstr(s)
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
