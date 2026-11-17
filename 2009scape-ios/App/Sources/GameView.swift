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
	/// True once a long press opened the world menu during the current touch, so its lift is not also a tap.
	private var longPressFired = false
	/// The current pan drags an if3 component (rt4 `Cs1ScriptRunner.aClass13_14`) instead of the camera.
	private var draggingComponent = false
	/// True while a one-finger drag that started over the 3D world is turning the camera.
	private var draggingCamera = false

	init(client: GameClient) {
		self.client = client
		super.init(frame: .zero)
		backgroundColor = .black
		isMultipleTouchEnabled = true // pinch zooms the camera
		layer.contentsGravity = .resize
		layer.magnificationFilter = .linear
		layer.minificationFilter = .linear
		addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
		// Long press = rt4's right click (opens the menu at the touch point).
		let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
		press.minimumPressDuration = 0.45
		addGestureRecognizer(press)
		// One-finger drag over the world turns the camera; pinch zooms it.
		let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
		pan.maximumNumberOfTouches = 1
		addGestureRecognizer(pan)
		addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
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
		return (Int((pts.width * scale).rounded(.up)), Int((pts.height * scale).rounded(.up)))
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

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		longPressFired = false
		// Show what a tap here would do while the finger is down (rt4's hover text at the top left).
		if let t = touches.first {
			let p = t.location(in: self)
			client.previewTap(x: Int(p.x * scale), y: Int(p.y * scale))
		}
		super.touchesBegan(touches, with: event)
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		client.clearPreview()
		super.touchesEnded(touches, with: event)
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		client.clearPreview()
		super.touchesCancelled(touches, with: event)
	}

	@objc private func pressed(_ g: UILongPressGestureRecognizer) {
		let p = g.location(in: self)
		let x = Int(p.x * scale), y = Int(p.y * scale)
		switch g.state {
		case .began:
			longPressFired = client.longPress(x: x, y: y)
		case .changed:
			// Moving the finger after a long press on an inventory slot drags the item (rt4 drag/swap).
			client.dragMove(x: x, y: y)
		case .ended:
			if client.isDraggingItem { client.dragEnd(x: x, y: y) }
		case .cancelled, .failed:
			if client.isDraggingItem { client.dragEnd(x: -1, y: -1) }
		default:
			break
		}
	}

	@objc private func panned(_ g: UIPanGestureRecognizer) {
		switch g.state {
		case .began:
			// Only drags that start on the 3D world (not on an interface or the open menu) steer the camera.
			let p = g.location(in: self)
			let start = CGPoint(x: p.x - g.translation(in: self).x, y: p.y - g.translation(in: self).y)
			draggingComponent = !longPressFired && client.beginComponentDrag(x: Int(start.x * scale), y: Int(start.y * scale))
			draggingCamera = !draggingComponent && !longPressFired && client.isOverWorld(x: Int(start.x * scale), y: Int(start.y * scale))
			if draggingCamera || draggingComponent { client.clearPreview() }
			g.setTranslation(.zero, in: self)
		case .changed:
			if draggingComponent {
				let p = g.location(in: self)
				client.moveComponentDrag(x: Int(p.x * scale), y: Int(p.y * scale))
				return
			}
			guard draggingCamera else { return }
			let t = g.translation(in: self)
			client.cameraDrag(dx: Double(t.x * scale), dy: Double(t.y * scale))
			g.setTranslation(.zero, in: self)
		default:
			if draggingComponent {
				let p = g.location(in: self)
				client.endComponentDrag(x: Int(p.x * scale), y: Int(p.y * scale))
				draggingComponent = false
			}
			draggingCamera = false
		}
	}

	@objc private func pinched(_ g: UIPinchGestureRecognizer) {
		guard g.state == .changed else { return }
		client.cameraPinch(scale: Double(g.scale))
		g.scale = 1
	}

	@objc private func tapped(_ g: UITapGestureRecognizer) {
		guard !longPressFired else { return }
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
