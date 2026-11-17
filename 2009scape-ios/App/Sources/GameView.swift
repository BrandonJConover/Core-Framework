import SwiftUI
import UIKit
import QuartzCore
import Scape530

/// Hosts the software-rendered game: a display link asks the `GameLoop` (background queue) for frames,
/// which are uploaded to a Metal texture and drawn aspect-fitted into this view's CAMetalLayer. Touch,
/// pointer and keyboard input map back to game pixels. The view respects the safe area (SwiftUI lays it out
/// inside it), so the notch and home indicator never cover the game.
struct GameView: UIViewRepresentable {
	let client: GameClient

	func makeUIView(context: Context) -> GameCanvasView {
		GameCanvasView(client: client)
	}

	func updateUIView(_ view: GameCanvasView, context: Context) {}
}

/// UILabel with insets, for the connection banner.
private final class PaddedLabel: UILabel {
	override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))) }
	override var intrinsicContentSize: CGSize {
		let s = super.intrinsicContentSize
		return CGSize(width: s.width + 24, height: s.height + 12)
	}
}

final class GameCanvasView: UIView, UIKeyInput, UIGestureRecognizerDelegate {
	override class var layerClass: AnyClass { CAMetalLayer.self }
	private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

	let client: GameClient
	private let presenter: MetalFramePresenter?
	private let loop: GameLoop
	private var link: CADisplayLink?
	/// Game pixels per point (>= 1 so rt4's resizable layout always has at least 765x503 to work with).
	private var scale: CGFloat = 1
	/// Game-pixel size requested for the latest frame; also what the aspect-fit mapping assumes.
	private var gameSize = (w: 0, h: 0)
	/// True once a long press opened a menu during the current touch, so its lift is not also a tap.
	private var longPressFired = false
	/// The current pan drags an if3 component (rt4 `Cs1ScriptRunner.aClass13_14`) instead of the camera.
	private var draggingComponent = false
	private var draggingCamera = false
	private var pressPoint = CGPoint.zero
	private var menuView: MobileMenuView?
	private var wasDraggingItem = false
	private var appliedMobileMenu: Bool?
	private var appliedTapToDrop: Bool?
	private var lastKeyboardWanted = false

	private let keyboardButton = UIButton(type: .system)
	private let banner = PaddedLabel()
	private var pinch: UIPinchGestureRecognizer!
	private var twoFingerPan: UIPanGestureRecognizer!

	init(client: GameClient) {
		self.client = client
		let presenter = MetalFramePresenter()
		self.presenter = presenter
		self.loop = GameLoop(client: client, presenter: presenter)
		super.init(frame: .zero)
		loop.layer = metalLayer
		presenter?.attach(to: metalLayer)
		backgroundColor = .black
		isMultipleTouchEnabled = true
		inputAssistantItem.leadingBarButtonGroups = []
		inputAssistantItem.trailingBarButtonGroups = []
		loop.onSnapshot = { [weak self] s in self?.apply(s) }

		addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
		// Long press = rt4's right click (opens the menu at the touch point). 350 ms like a mobile client.
		let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
		press.minimumPressDuration = 0.35
		addGestureRecognizer(press)
		// A mouse or trackpad secondary click does the same.
		let rightClick = UITapGestureRecognizer(target: self, action: #selector(rightClicked(_:)))
		rightClick.buttonMaskRequired = .secondary
		rightClick.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
		addGestureRecognizer(rightClick)
		// One-finger drag over the world turns the camera.
		let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
		pan.maximumNumberOfTouches = 1
		addGestureRecognizer(pan)
		// Two fingers: vertical drag tilts (horizontal turns), together with pinch zoom.
		twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(twoFingerPanned(_:)))
		twoFingerPan.minimumNumberOfTouches = 2
		twoFingerPan.maximumNumberOfTouches = 2
		twoFingerPan.delegate = self
		addGestureRecognizer(twoFingerPan)
		pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
		pinch.delegate = self
		addGestureRecognizer(pinch)
		// Mouse wheel / trackpad scroll zooms.
		let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
		scroll.allowedScrollTypesMask = .all
		scroll.allowedTouchTypes = []
		addGestureRecognizer(scroll)
		// Pointer hover drives the "Talk-to ..." line and interface rollovers.
		addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))

		configureHUD()

		let nc = NotificationCenter.default
		nc.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
		nc.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
		nc.addObserver(self, selector: #selector(setPaused), name: UIApplication.willResignActiveNotification, object: nil)
		nc.addObserver(self, selector: #selector(setPaused), name: UIApplication.didBecomeActiveNotification, object: nil)
		nc.addObserver(self, selector: #selector(updateFrameRate), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
		nc.addObserver(self, selector: #selector(updateFrameRate), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
		Haptics.shared.prepare()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func configureHUD() {
		keyboardButton.setImage(UIImage(systemName: "keyboard"), for: .normal)
		keyboardButton.tintColor = .white
		keyboardButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
		keyboardButton.layer.cornerRadius = 22
		keyboardButton.translatesAutoresizingMaskIntoConstraints = false
		keyboardButton.addTarget(self, action: #selector(keyboardButtonTapped), for: .touchUpInside)
		keyboardButton.isHidden = true
		addSubview(keyboardButton)

		banner.numberOfLines = 0
		banner.textAlignment = .center
		banner.textColor = .white
		banner.font = .systemFont(ofSize: 15, weight: .semibold)
		banner.backgroundColor = UIColor(red: 0.45, green: 0.07, blue: 0.07, alpha: 0.92)
		banner.layer.cornerRadius = 10
		banner.clipsToBounds = true
		banner.translatesAutoresizingMaskIntoConstraints = false
		banner.isHidden = true
		banner.isUserInteractionEnabled = false
		addSubview(banner)

		let safe = safeAreaLayoutGuide
		NSLayoutConstraint.activate([
			keyboardButton.widthAnchor.constraint(equalToConstant: 44),
			keyboardButton.heightAnchor.constraint(equalToConstant: 44),
			keyboardButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
			keyboardButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -96),
			banner.centerXAnchor.constraint(equalTo: centerXAnchor),
			banner.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16),
			banner.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, multiplier: 0.9),
		])
	}

	// MARK: lifecycle / frame pacing

	override func didMoveToWindow() {
		super.didMoveToWindow()
		link?.invalidate()
		link = nil
		guard window != nil else { return }
		let l = CADisplayLink(target: self, selector: #selector(step))
		l.add(to: .main, forMode: .common)
		link = l
		updateFrameRate()
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let s = max(traitCollection.displayScale, 1)
		metalLayer.contentsScale = s
		metalLayer.drawableSize = CGSize(width: bounds.width * s, height: bounds.height * s)
	}

	/// Backgrounded apps must not submit GPU work; the session thread keeps (or loses) the socket and the
	/// client reconnects on its own when the connection turns out to be dead.
	@objc private func setPaused() {
		link?.isPaused = UIApplication.shared.applicationState != .active
	}

	/// ProMotion devices may run up to 120 Hz. The client advances at rt4's 50 Hz cycle; with "Smooth motion" on,
	/// actors and the camera are drawn between cycles (`GameClient.smoothMotion`), so the display link asks for
	/// 120 Hz; with it off extra frames only redraw and 60 is the working rate. Low power mode and thermal
	/// pressure drop to 30.
	@objc private func updateFrameRate() {
		let info = ProcessInfo.processInfo
		let throttled = info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
		link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: throttled ? 30 : 120, preferred: throttled ? 30 : (MobileSettings.smoothMotion ? 120 : 60))
	}

	/// rt4's resizable mode needs at least 765x503; below that we draw at 503 game pixels high and let the
	/// GPU scale it down. Otherwise one game pixel per point, filling the whole safe area.
	private func computeGameSize() -> (Int, Int) {
		let pts = bounds.size
		guard pts.width > 0, pts.height > 0 else { return (0, 0) }
		scale = max(1, 503 / pts.height, 765 / pts.width)
		return (Int((pts.width * scale).rounded(.up)), Int((pts.height * scale).rounded(.up)))
	}

	@objc private func step() {
		guard UIApplication.shared.applicationState != .background else { return }
		let (w, h) = computeGameSize()
		guard w > 0 else { return }
		gameSize = (w, h)
		syncSettings()
		loop.requestFrame(width: w, height: h, smooth: MobileSettings.smoothScaling, smoothMotion: MobileSettings.smoothMotion)
	}

	private func syncSettings() {
		let menu = MobileSettings.mobileMenu, drop = MobileSettings.tapToDrop
		guard menu != appliedMobileMenu || drop != appliedTapToDrop else { return }
		appliedMobileMenu = menu
		appliedTapToDrop = drop
		loop.async { $0.drawsClassicMenu = !menu; $0.tapToDrop = drop }
	}

	/// Runs on the main queue after each frame.
	private func apply(_ s: GameLoop.Snapshot) {
		// Keyboard follows the client's focus (login fields, chat input, the HUD button).
		if s.wantsKeyboard && !isFirstResponder {
			becomeFirstResponder()
		} else if !s.wantsKeyboard && isFirstResponder {
			_ = resignFirstResponder()
		}
		lastKeyboardWanted = s.wantsKeyboard
		keyboardButton.isHidden = s.screen != .game

		if s.reconnectAttempt > 0 && s.screen == .game {
			banner.text = "Connection lost. Reconnecting (\(s.reconnectAttempt)/\(s.maxReconnectAttempts))..."
			banner.isHidden = false
		} else if s.screen != .game, let e = s.connectError {
			banner.text = e
			banner.isHidden = false
		} else {
			banner.isHidden = true
		}

		if s.isDraggingItem != wasDraggingItem {
			wasDraggingItem = s.isDraggingItem
			if s.isDraggingItem { Haptics.shared.dragPickup() } else { Haptics.shared.dragDrop() }
		}

		if MobileSettings.mobileMenu, let rows = s.menuRows {
			if menuView == nil { showMenu(rows) }
		} else if menuView != nil {
			menuView?.removeFromSuperview()
			menuView = nil
		}
	}

	private func showMenu(_ rows: [MenuRow]) {
		let (gx, gy) = toGame(pressPoint)
		let v = MobileMenuView(rows: rows, anchor: pressPoint, onSelect: { [weak self] row in
			guard let self else { return }
			self.closeMenuView()
			if row.isCancel {
				self.loop.async { $0.dismissMenu() }
			} else {
				self.loop.async { $0.chooseMenuEntry(row.index, clickX: gx, clickY: gy) }
			}
		}, onDismiss: { [weak self] in
			self?.closeMenuView()
			self?.loop.async { $0.dismissMenu() }
		})
		v.frame = bounds
		v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		insertSubview(v, belowSubview: keyboardButton)
		menuView = v
	}

	private func closeMenuView() {
		menuView?.removeFromSuperview()
		menuView = nil
	}

	// MARK: coordinates

	/// Where the game image sits in the view (aspect fit, the same rule the Metal presenter uses).
	private var contentRect: CGRect {
		guard gameSize.w > 0, gameSize.h > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
		let f = min(bounds.width / CGFloat(gameSize.w), bounds.height / CGFloat(gameSize.h))
		let w = CGFloat(gameSize.w) * f, h = CGFloat(gameSize.h) * f
		return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
	}

	/// View point to game pixel.
	private func toGame(_ p: CGPoint) -> (Int, Int) {
		let c = contentRect
		guard c.width > 0, c.height > 0 else { return (0, 0) }
		let x = (p.x - c.minX) * CGFloat(gameSize.w) / c.width
		let y = (p.y - c.minY) * CGFloat(gameSize.h) / c.height
		return (Int(x.rounded(.down)), Int(y.rounded(.down)))
	}

	/// Game pixels per view point.
	private var pixelsPerPoint: CGFloat {
		let c = contentRect
		return c.width > 0 ? CGFloat(gameSize.w) / c.width : 1
	}

	// MARK: keyboard shift

	/// In landscape the keyboard covers the lower half; slide the game up so the focused login field stays visible.
	@objc private func keyboardChanged(_ n: Notification) {
		guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue, let window else { return }
		let hiding = n.name == UIResponder.keyboardWillHideNotification
		let overlap = hiding ? 0 : max(0, convert(bounds, to: window).maxY - end.minY)
		UIView.animate(withDuration: 0.25) {
			self.transform = CGAffineTransform(translationX: 0, y: -overlap * 0.6)
		}
	}

	@objc private func keyboardButtonTapped() {
		loop.async { $0.toggleKeyboard() }
	}

	// MARK: touches

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		longPressFired = false
		// Show what a tap here would do while the finger is down (rt4's hover text at the top left).
		if let t = touches.first, t.type != .indirectPointer {
			let (x, y) = toGame(t.location(in: self))
			loop.async { $0.previewTap(x: x, y: y) }
		}
		super.touchesBegan(touches, with: event)
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		loop.async { $0.clearPreview() }
		super.touchesEnded(touches, with: event)
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		loop.async { $0.clearPreview() }
		super.touchesCancelled(touches, with: event)
	}

	@objc private func tapped(_ g: UITapGestureRecognizer) {
		guard !longPressFired else { return }
		let (x, y) = toGame(g.location(in: self))
		loop.async { $0.tap(x: x, y: y) }
	}

	@objc private func pressed(_ g: UILongPressGestureRecognizer) {
		let p = g.location(in: self)
		let (x, y) = toGame(p)
		switch g.state {
		case .began:
			pressPoint = p
			longPressFired = loop.sync { $0.longPress(x: x, y: y) }
			if longPressFired { Haptics.shared.menuOpened() }
		case .changed:
			// Moving the finger after a long press on an inventory slot drags the item (rt4 drag/swap).
			loop.async { $0.dragMove(x: x, y: y) }
		case .ended:
			loop.async { if $0.isDraggingItem { $0.dragEnd(x: x, y: y) } }
		case .cancelled, .failed:
			loop.async { if $0.isDraggingItem { $0.dragEnd(x: -1, y: -1) } }
		default:
			break
		}
	}

	@objc private func rightClicked(_ g: UITapGestureRecognizer) {
		guard g.state == .ended else { return }
		let p = g.location(in: self)
		let (x, y) = toGame(p)
		pressPoint = p
		longPressFired = loop.sync { $0.longPress(x: x, y: y) }
	}

	@objc private func panned(_ g: UIPanGestureRecognizer) {
		switch g.state {
		case .began:
			// Only drags that start on the 3D world (not on an interface or the open menu) steer the camera.
			let p = g.location(in: self)
			let t = g.translation(in: self)
			let (sx, sy) = toGame(CGPoint(x: p.x - t.x, y: p.y - t.y))
			let fired = longPressFired
			draggingComponent = !fired && loop.sync { $0.beginComponentDrag(x: sx, y: sy) }
			draggingCamera = !draggingComponent && !fired && loop.sync { $0.isOverWorld(x: sx, y: sy) }
			if draggingCamera || draggingComponent { loop.async { $0.clearPreview() } }
			g.setTranslation(.zero, in: self)
		case .changed:
			if draggingComponent {
				let (x, y) = toGame(g.location(in: self))
				loop.async { $0.moveComponentDrag(x: x, y: y) }
				return
			}
			guard draggingCamera else { return }
			let t = g.translation(in: self)
			let k = Double(pixelsPerPoint)
			let dx = Double(t.x) * k, dy = Double(t.y) * k
			loop.async { $0.cameraDrag(dx: dx, dy: dy) }
			g.setTranslation(.zero, in: self)
		default:
			if draggingComponent {
				let (x, y) = toGame(g.location(in: self))
				loop.async { $0.endComponentDrag(x: x, y: y) }
				draggingComponent = false
			}
			draggingCamera = false
		}
	}

	@objc private func twoFingerPanned(_ g: UIPanGestureRecognizer) {
		guard g.state == .changed else { return }
		let t = g.translation(in: self)
		let k = Double(pixelsPerPoint)
		let dx = Double(t.x) * k, dy = Double(t.y) * k
		loop.async { $0.cameraDrag(dx: dx, dy: dy) }
		g.setTranslation(.zero, in: self)
	}

	@objc private func pinched(_ g: UIPinchGestureRecognizer) {
		guard g.state == .changed else { return }
		let s = Double(g.scale)
		loop.async { $0.cameraPinch(scale: s) }
		g.scale = 1
	}

	@objc private func scrolled(_ g: UIPanGestureRecognizer) {
		guard g.state == .changed else { return }
		let dy = Double(g.translation(in: self).y)
		g.setTranslation(.zero, in: self)
		loop.async { $0.cameraPinch(scale: 1 + dy * 0.01) }
	}

	@objc private func hovered(_ g: UIHoverGestureRecognizer) {
		guard g.state == .changed || g.state == .began else { return }
		let (x, y) = toGame(g.location(in: self))
		loop.async { $0.hover(x: x, y: y) }
	}

	func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
		(a === pinch && b === twoFingerPan) || (a === twoFingerPan && b === pinch)
	}

	// MARK: UIKeyInput (also receives hardware keyboards)

	override var canBecomeFirstResponder: Bool { true }
	var hasText: Bool { true }
	func insertText(_ text: String) { loop.async { $0.type(text) } }
	func deleteBackward() { loop.async { $0.backspace() } }
	var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
	var autocapitalizationType: UITextAutocapitalizationType { get { .none } set {} }
	var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
	var keyboardType: UIKeyboardType { get { .asciiCapable } set {} }
	var returnKeyType: UIReturnKeyType { get { .go } set {} }

	/// A keyboard the system dismissed itself (iPad dismiss key) must not be re-raised by the client's chat flag.
	override func resignFirstResponder() -> Bool {
		let r = super.resignFirstResponder()
		if r && lastKeyboardWanted { loop.async { $0.keyboardRequested = false } }
		return r
	}
}
