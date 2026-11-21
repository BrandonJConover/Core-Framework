import UIKit
import Scape530

/// The long-press option menu drawn in rt4's own menu style (`MiniMenu`: 0x5D5447 body, black border, black
/// "Choose Option" header, white entries with coloured names) but sized for fingers like the OSRS mobile client:
/// rows at least 44 pt tall, placed under the finger and kept on screen.
///
/// Touch is forgiving: the row is the nearest row centre to the touch point (shifted down a few points, since
/// iOS reports touches slightly above where people aim), anywhere within the menu extended by `slop` on each
/// side. The row under the finger is highlighted while it is held and chosen on lift, so a finger can slide to
/// correct before releasing. A finger that long-pressed to open the menu can keep sliding and release on a row.
/// Lifting outside (beyond the slop) cancels.
final class MobileMenuView: UIView {
	static let body = UIColor(red: 0x5D / 255, green: 0x54 / 255, blue: 0x47 / 255, alpha: 1)
	private let rows: [MenuRow]
	private let anchor: CGPoint
	private let onSelect: (MenuRow) -> Void
	private let onDismiss: () -> Void
	private var panel = CGRect.zero
	private var rowHeight: CGFloat = 44
	private let headerHeight: CGFloat = 30
	private let slop: CGFloat = 20
	/// iOS touch points sit a little above the finger's centre of contact.
	private let fingerOffset: CGFloat = 6
	private var highlighted: Int?
	private var labels: [NSAttributedString] = []
	private var finished = false

	init(rows: [MenuRow], anchor: CGPoint, onSelect: @escaping (MenuRow) -> Void, onDismiss: @escaping () -> Void) {
		self.rows = rows
		self.anchor = anchor
		self.onSelect = onSelect
		self.onDismiss = onDismiss
		super.init(frame: .zero)
		backgroundColor = UIColor.black.withAlphaComponent(0.15)
		isOpaque = false
		contentMode = .redraw
		isMultipleTouchEnabled = false
		labels = rows.map { Self.attributed($0.text, cancel: $0.isCancel) }
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func layoutSubviews() {
		super.layoutSubviews()
		let safe = bounds.inset(by: safeAreaInsets).insetBy(dx: 6, dy: 6)
		guard safe.width > 0, safe.height > 0 else { return }
		let textWidth = labels.map { ceil($0.size().width) }.max() ?? 100
		let width = min(max(textWidth + 32, 220), safe.width)
		rowHeight = max(44, min(52, (safe.height - headerHeight - 4) / CGFloat(max(rows.count, 1))))
		let height = min(headerHeight + rowHeight * CGFloat(rows.count) + 4, safe.height)
		rowHeight = (height - headerHeight - 4) / CGFloat(max(rows.count, 1))
		// rt4 centres the menu on the click; here the first row (the default action) lands under the finger.
		var x = anchor.x - width / 2
		var y = anchor.y - headerHeight - rowHeight / 2
		x = min(max(x, safe.minX), safe.maxX - width)
		y = min(max(y, safe.minY), safe.maxY - height)
		panel = CGRect(x: x, y: y, width: width, height: height)
		setNeedsDisplay()
	}

	override func draw(_ rect: CGRect) {
		guard let ctx = UIGraphicsGetCurrentContext(), panel.width > 0 else { return }
		ctx.setFillColor(Self.body.cgColor)
		ctx.fill(panel)
		ctx.setStrokeColor(UIColor.black.cgColor)
		ctx.setLineWidth(2)
		ctx.stroke(panel.insetBy(dx: 1, dy: 1))
		// Header: black bar with "Choose Option" in the body colour (rt4 `MiniMenu.draw`).
		let header = CGRect(x: panel.minX + 2, y: panel.minY + 2, width: panel.width - 4, height: headerHeight - 4)
		ctx.setFillColor(UIColor.black.cgColor)
		ctx.fill(header)
		let title = NSAttributedString(string: "Choose Option", attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: Self.body])
		title.draw(at: CGPoint(x: header.minX + 6, y: header.midY - title.size().height / 2))
		for (i, label) in labels.enumerated() {
			let r = rowRect(i)
			if i == highlighted {
				ctx.setFillColor(UIColor(white: 1, alpha: 0.18).cgColor)
				ctx.fill(r.insetBy(dx: 2, dy: 1))
			}
			if i > 0 {
				ctx.setFillColor(UIColor.black.withAlphaComponent(0.25).cgColor)
				ctx.fill(CGRect(x: r.minX + 6, y: r.minY, width: r.width - 12, height: 1))
			}
			label.draw(at: CGPoint(x: r.minX + 10, y: r.midY - label.size().height / 2))
		}
	}

	private func rowRect(_ i: Int) -> CGRect {
		CGRect(x: panel.minX, y: panel.minY + headerHeight + CGFloat(i) * rowHeight, width: panel.width, height: rowHeight)
	}

	/// Nearest row to a touch, within the panel grown by `slop`; nil outside.
	private func row(at p: CGPoint) -> Int? {
		let q = CGPoint(x: p.x, y: p.y + fingerOffset)
		guard panel.insetBy(dx: -slop, dy: -slop).contains(q), !rows.isEmpty else { return nil }
		let i = Int(floor((q.y - panel.minY - headerHeight) / rowHeight))
		return min(max(i, 0), rows.count - 1)
	}

	private func setHighlight(_ i: Int?) {
		guard i != highlighted else { return }
		highlighted = i
		if i != nil { Haptics.shared.rowSelected() }
		setNeedsDisplay()
	}

	private func finish(_ i: Int?) {
		guard !finished else { return }
		finished = true
		if let i { onSelect(rows[i]) } else { onDismiss() }
	}

	// Taps and slides after the menu is open.
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		if let t = touches.first { setHighlight(row(at: t.location(in: self))) }
	}
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		if let t = touches.first { setHighlight(row(at: t.location(in: self))) }
	}
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		guard let t = touches.first else { return }
		finish(row(at: t.location(in: self)))
	}
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { setHighlight(nil) }

	// The long press that opened the menu, still held (`GameCanvasView` forwards it).
	private var moved = false
	func track(_ p: CGPoint) {
		if hypot(p.x - anchor.x, p.y - anchor.y) > 10 { moved = true }
		if moved { setHighlight(row(at: p)) }
	}
	/// Lift of the opening press: chooses only if the finger slid onto a row; lifting in place keeps the menu open.
	func release(_ p: CGPoint) {
		guard moved, let i = row(at: p) else { setHighlight(nil); return }
		finish(i)
	}

	/// rt4 text with `<col=rrggbb>` tags to attributed text (white until the first tag); other tags are dropped.
	static func attributed(_ text: String, cancel: Bool) -> NSAttributedString {
		let font = UIFont.systemFont(ofSize: 17, weight: .bold)
		let out = NSMutableAttributedString()
		var color = cancel ? UIColor(red: 1, green: 0.55, blue: 0.5, alpha: 1) : UIColor.white
		var chars = Substring(text)
		var run = ""
		func flush() {
			if !run.isEmpty { out.append(NSAttributedString(string: run, attributes: [.font: font, .foregroundColor: color])); run = "" }
		}
		while let c = chars.first {
			if c == "<", let end = chars.firstIndex(of: ">") {
				let tag = chars[chars.index(after: chars.startIndex)..<end]
				flush()
				if tag.hasPrefix("col="), let v = UInt32(tag.dropFirst(4), radix: 16) {
					color = UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
				} else if tag == "/col" {
					color = .white
				}
				chars = chars[chars.index(after: end)...]
			} else {
				run.append(c)
				chars = chars.dropFirst()
			}
		}
		flush()
		return out
	}
}
