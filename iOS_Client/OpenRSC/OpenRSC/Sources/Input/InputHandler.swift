import Foundation
import SwiftUI

/// Handles touch input and gestures.
/// Equivalent to Android's InputImpl.
@MainActor
final class InputHandler: ObservableObject {
    weak var gameClient: GameClient?

    // Input state
    @Published var mouseX: Int = 0
    @Published var mouseY: Int = 0
    @Published var isPressed: Bool = false
    @Published var isLongPress: Bool = false

    // Gesture configuration
    var longPressDelay: TimeInterval = 0.5
    var swipeToRotate: Bool = true
    var swipeToZoom: Bool = true

    // Timing
    private var lastTapTime: Date?
    private var longPressTimer: Timer?
    private var lastPanTranslation: CGSize = .zero
    private var lastPinchScale: CGFloat = 1
    private var hasDragged = false

    private let tapMovementThreshold: CGFloat = 12

    init(gameClient: GameClient? = nil) {
        self.gameClient = gameClient
    }

    /// Converts screen coordinates to game coordinates.
    func screenToGame(
        x: CGFloat,
        y: CGFloat,
        viewSize: CGSize,
        origin: CGPoint = .zero
    ) -> (Int, Int) {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return (0, 0)
        }

        let scaleX = CGFloat(GameClient.gameWidth) / viewSize.width
        let scaleY = CGFloat(GameClient.gameHeight) / viewSize.height

        let viewportX = min(max(x + origin.x, 0), viewSize.width)
        let viewportY = min(max(y + origin.y, 0), viewSize.height)

        let gameX = Int((viewportX * scaleX).rounded())
        let gameY = Int((viewportY * scaleY).rounded())

        return (
            min(max(gameX, 0), GameClient.gameWidth - 1),
            min(max(gameY, 0), GameClient.gameHeight - 1)
        )
    }

    // MARK: - Touch Handling

    func onTouchBegan(at location: CGPoint, in viewSize: CGSize, origin: CGPoint = .zero) {
        let (gameX, gameY) = screenToGame(x: location.x, y: location.y, viewSize: viewSize, origin: origin)
        mouseX = gameX
        mouseY = gameY
        isPressed = true
        hasDragged = false
        lastPanTranslation = .zero
        lastPinchScale = 1

        // Start long press timer
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onLongPress()
            }
        }
    }

    func onTouchMoved(at location: CGPoint, in viewSize: CGSize, origin: CGPoint = .zero) {
        let (gameX, gameY) = screenToGame(x: location.x, y: location.y, viewSize: viewSize, origin: origin)
        mouseX = gameX
        mouseY = gameY

        // Cancel long press if moved too far
        longPressTimer?.invalidate()
    }

    func onTouchEnded(at location: CGPoint, in viewSize: CGSize, origin: CGPoint = .zero) {
        let (gameX, gameY) = screenToGame(x: location.x, y: location.y, viewSize: viewSize, origin: origin)
        mouseX = gameX
        mouseY = gameY
        isPressed = false

        longPressTimer?.invalidate()

        if !isLongPress && !hasDragged {
            onTap(x: gameX, y: gameY)
        }
        isLongPress = false
        hasDragged = false
        lastPanTranslation = .zero
        lastPinchScale = 1
        gameClient?.finishCameraGesture()
    }

    func onTouchCancelled() {
        isPressed = false
        isLongPress = false
        hasDragged = false
        lastPanTranslation = .zero
        lastPinchScale = 1
        longPressTimer?.invalidate()
        gameClient?.finishCameraGesture()
    }

    // MARK: - Gesture Handling

    private func onTap(x: Int, y: Int) {
        gameClient?.handleTap(x: x, y: y)

        // Check for double tap
        if let lastTap = lastTapTime, Date().timeIntervalSince(lastTap) < 0.3 {
            onDoubleTap(x: x, y: y)
        }
        lastTapTime = Date()
    }

    private func onDoubleTap(x: Int, y: Int) {
        // Double tap action (e.g., toggle run)
        print("Double tap at: \(x), \(y)")
    }

    private func onLongPress() {
        isLongPress = true
        gameClient?.handleLongPress(x: mouseX, y: mouseY)
    }

    func onPan(translation: CGSize, viewSize: CGSize) {
        guard swipeToRotate || swipeToZoom else { return }

        let movement = hypot(translation.width, translation.height)
        if movement >= tapMovementThreshold {
            hasDragged = true
        }

        let incrementalTranslation = CGSize(
            width: translation.width - lastPanTranslation.width,
            height: translation.height - lastPanTranslation.height
        )
        lastPanTranslation = translation

        guard hasDragged else { return }

        let deltaX = swipeToRotate ? Float(incrementalTranslation.width / viewSize.width) * 100 : 0
        let deltaY = swipeToZoom ? Float(incrementalTranslation.height / viewSize.height) * 100 : 0

        guard deltaX != 0 || deltaY != 0 else { return }
        gameClient?.handlePan(deltaX: deltaX, deltaY: deltaY)
    }

    func onPinch(scale: CGFloat) {
        guard swipeToZoom else { return }
        let incrementalScale = scale / max(lastPinchScale, 0.001)
        lastPinchScale = scale

        guard incrementalScale.isFinite, incrementalScale > 0 else { return }

        hasDragged = true
        gameClient?.handlePinch(scale: Float(incrementalScale))
    }

    func onPinchEnded() {
        lastPinchScale = 1
        gameClient?.finishCameraGesture()
    }

    // MARK: - Keyboard Input

    func onKeyPress(_ key: String) {
        guard let client = gameClient else { return }

        switch key {
        case "←":
            client.stepCameraRotation(-1)
        case "→":
            client.stepCameraRotation(1)
        case "↑":
            client.stepCameraZoom(1)
        case "↓":
            client.stepCameraZoom(-1)
        default:
            // Handle text input
            break
        }
    }
}

// MARK: - SwiftUI Gesture Modifiers

struct GameGestureModifier: ViewModifier {
    @ObservedObject var inputHandler: InputHandler
    let viewportSize: CGSize
    let inputOrigin: CGPoint

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !inputHandler.isPressed {
                            inputHandler.onTouchBegan(at: value.location, in: viewportSize, origin: inputOrigin)
                        }
                        if value.translation != .zero {
                            inputHandler.onTouchMoved(at: value.location, in: viewportSize, origin: inputOrigin)
                            inputHandler.onPan(translation: value.translation, viewSize: viewportSize)
                        }
                    }
                    .onEnded { value in
                        inputHandler.onTouchEnded(at: value.location, in: viewportSize, origin: inputOrigin)
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        inputHandler.onPinch(scale: scale)
                    }
                    .onEnded { _ in
                        inputHandler.onPinchEnded()
                    }
            )
    }
}

extension View {
    func gameGestures(
        _ handler: InputHandler,
        viewportSize: CGSize,
        inputOrigin: CGPoint = .zero
    ) -> some View {
        modifier(
            GameGestureModifier(
                inputHandler: handler,
                viewportSize: viewportSize,
                inputOrigin: inputOrigin
            )
        )
    }
}

// MARK: - Virtual Joystick (optional)

struct VirtualJoystick: View {
    @Binding var direction: CGPoint
    let onMove: (CGPoint) -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Base
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 100, height: 100)

            // Knob
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 40, height: 40)
                .offset(dragOffset)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let maxDistance: CGFloat = 30
                    let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

                    if distance > maxDistance {
                        let scale = maxDistance / distance
                        dragOffset = CGSize(
                            width: value.translation.width * scale,
                            height: value.translation.height * scale
                        )
                    } else {
                        dragOffset = value.translation
                    }

                    let normalizedX = dragOffset.width / maxDistance
                    let normalizedY = dragOffset.height / maxDistance
                    direction = CGPoint(x: normalizedX, y: normalizedY)
                    onMove(direction)
                }
                .onEnded { _ in
                    dragOffset = .zero
                    direction = .zero
                    onMove(.zero)
                }
        )
    }
}
