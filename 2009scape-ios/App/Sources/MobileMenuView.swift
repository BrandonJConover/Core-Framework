import UIKit
import Scape530

/// The "mobile UI" option list: the library's own menu entries (`GameClient.popupRows`) shown as large
/// touch rows (44 pt minimum) near where the finger pressed, kept inside the safe area, with a clear
/// Cancel row. Tapping outside the panel dismisses it.
final class MobileMenuView: UIView {
	private let panel = UIScrollView()
	private let stack = UIStackView()
	private let rows: [MenuRow]
	private let anchor: CGPoint
	private let onSelect: (MenuRow) -> Void
	private let onDismiss: () -> Void

	init(rows: [MenuRow], anchor: CGPoint, onSelect: @escaping (MenuRow) -> Void, onDismiss: @escaping () -> Void) {
		self.rows = rows
		self.anchor = anchor
		self.onSelect = onSelect
		self.onDismiss = onDismiss
		super.init(frame: .zero)
		backgroundColor = UIColor.black.withAlphaComponent(0.25)
		addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped)))

		panel.backgroundColor = UIColor(red: 0x5D / 255, green: 0x54 / 255, blue: 0x47 / 255, alpha: 0.97)
		panel.layer.cornerRadius = 10
		panel.layer.borderWidth = 1.5
		panel.layer.borderColor = UIColor.black.cgColor
		panel.clipsToBounds = true
		panel.showsVerticalScrollIndicator = true
		panel.delaysContentTouches = false
		addSubview(panel)

		stack.axis = .vertical
		stack.spacing = 1
		stack.translatesAutoresizingMaskIntoConstraints = false
		panel.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: panel.contentLayoutGuide.topAnchor),
			stack.bottomAnchor.constraint(equalTo: panel.contentLayoutGuide.bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: panel.contentLayoutGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: panel.contentLayoutGuide.trailingAnchor),
			stack.widthAnchor.constraint(equalTo: panel.frameLayoutGuide.widthAnchor),
		])
		for (i, row) in rows.enumerated() {
			let b = UIButton(type: .custom)
			b.tag = i
			b.contentHorizontalAlignment = .left
			b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
			b.titleLabel?.numberOfLines = 2
			b.titleLabel?.lineBreakMode = .byTruncatingTail
			b.setAttributedTitle(Self.attributed(row.text, cancel: row.isCancel), for: .normal)
			b.backgroundColor = row.isCancel ? UIColor(white: 0.1, alpha: 0.9) : UIColor(white: 0, alpha: i == 0 ? 0.55 : 0.35)
			b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
			b.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
			b.addTarget(self, action: #selector(rowDown), for: .touchDown)
			stack.addArrangedSubview(b)
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	@objc private func backdropTapped() { onDismiss() }
	@objc private func rowDown() { Haptics.shared.rowSelected() }
	@objc private func rowTapped(_ b: UIButton) {
		guard b.tag < rows.count else { return }
		onSelect(rows[b.tag])
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let safe = bounds.inset(by: safeAreaInsets).insetBy(dx: 8, dy: 8)
		guard safe.width > 0, safe.height > 0 else { return }
		let width = min(max(260, safe.width * 0.4), safe.width)
		stack.layoutIfNeeded()
		let fitting = stack.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
			withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
		let height = min(fitting, safe.height)
		var x = anchor.x - width / 2
		var y = anchor.y - 22 // first row (the default action) lands under the finger
		x = min(max(x, safe.minX), safe.maxX - width)
		y = min(max(y, safe.minY), safe.maxY - height)
		panel.frame = CGRect(x: x, y: y, width: width, height: height)
	}

	/// rt4 text with `<col=rrggbb>` tags to attributed text (white until the first tag); other tags are dropped.
	static func attributed(_ text: String, cancel: Bool) -> NSAttributedString {
		let font = UIFont.systemFont(ofSize: 18, weight: .semibold)
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
