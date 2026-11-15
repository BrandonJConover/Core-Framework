import SwiftUI
import UIKit
import Scape530

/// Hosts the software-rendered game in a UIView: a display link asks the
/// client for a frame at ~50 fps (rt4's rate), the frame is shown as a
/// CGImage scaled to the view, taps map back to game pixels, and the view
/// itself is the keyboard target while a text field has focus.
struct GameView: UIViewRepresentable {
	let client: GameClient

	func makeUIView(context: Context) -> GameCanvasView {
		GameCanvasView(client: client)
	}

	func updateUIView(_ view: GameCanvasView, context: Context) {
		view.client = client
	}
}

final class GameCanvasView: UIView, UIKeyInput {
	var client: GameClient
	private var link: CADisplayLink?
	/// Game pixels per point.
	private var scale: CGFloat = 1
	private let colorSpace = CGColorSpaceCreateDeviceRGB()

	init(client: GameClient) {
		self.client = client
		super.init(frame: .zero)
		backgroundColor = .black
		isMultipleTouchEnabled = false
		layer.contentsGravity = .resize
		layer.magnificationFilter = .linear
		layer.minificationFilter = .linear
		addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
	}

	/// In landscape the keyboard covers the lower half; slide the game up so
	/// the focused login field stays visible (rt4 never had this problem).
	@objc private func keyboardChanged(_ n: Notification) {
		guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue, let window else { return }
		let hiding = n.name == UIResponder.keyboardWillHideNotification
		let overlap = hiding ? 0 : max(0, convert(bounds, to: window).maxY - end.minY)
		UIView.animate(withDuration: 0.25) {
			self.transform = CGAffineTransform(translationX: 0, y: -overlap * 0.6)
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func didMoveToWindow() {
		super.didMoveToWindow()
		link?.invalidate()
		guard window != nil else { return }
		let l = CADisplayLink(target: self, selector: #selector(step))
		l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 50, preferred: 50)
		l.add(to: .main, forMode: .common)
		link = l
	}

	/// rt4's resizable mode needs at least 765x503; below that we draw at
	/// 503 game pixels high and let the GPU scale it down.
	private func gameSize() -> (Int, Int) {
		let pts = bounds.size
		guard pts.width > 0, pts.height > 0 else { return (0, 0) }
		scale = max(1, 503 / pts.height, 765 / pts.width)
		return (Int(pts.width * scale), Int(pts.height * scale))
	}

	@objc private func step() {
		let (w, h) = gameSize()
		guard w > 0 else { return }
		do {
			let r = try client.frame(width: w, height: h)
			layer.contents = image(r)
		} catch {
			print("[frame] \(error)")
		}
		syncKeyboard()
	}

	private func image(_ r: Raster) -> CGImage? {
		let data = r.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
		guard let provider = CGDataProvider(data: data as CFData) else { return nil }
		return CGImage(
			width: r.width, height: r.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: r.width * 4,
			space: colorSpace,
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
			provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
	}

	@objc private func tapped(_ g: UITapGestureRecognizer) {
		let p = g.location(in: self)
		client.tap(x: Int(p.x * scale), y: Int(p.y * scale))
		syncKeyboard()
	}

	private func syncKeyboard() {
		if client.wantsKeyboard && !isFirstResponder {
			becomeFirstResponder()
		} else if !client.wantsKeyboard && isFirstResponder {
			resignFirstResponder()
		}
	}

	// MARK: UIKeyInput (also receives hardware keyboards)

	override var canBecomeFirstResponder: Bool { true }
	var hasText: Bool { true }
	func insertText(_ text: String) { client.type(text) }
	func deleteBackward() { client.backspace() }
	var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
	var autocapitalizationType: UITextAutocapitalizationType { get { .none } set {} }
	var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
	var keyboardType: UIKeyboardType { get { .asciiCapable } set {} }
	var returnKeyType: UIReturnKeyType { get { .go } set {} }
}
