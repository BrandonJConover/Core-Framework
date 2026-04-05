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

    init(gameClient: GameClient? = nil) {
        self.gameClient = gameClient
    }

    /// Converts screen coordinates to game coordinates.
    func screenToGame(x: CGFloat, y: CGFloat, viewSize: CGSize) -> (Int, Int) {
        let scaleX = CGFloat(GameClient.gameWidth) / viewSize.width
        let scaleY = CGFloat(GameClient.gameHeight) / viewSize.height

        let gameX = Int(x * scaleX)
        let gameY = Int(y * scaleY)

        return (gameX, gameY)
    }

    // MARK: - Touch Handling

    func onTouchBegan(at location: CGPoint, in viewSize: CGSize) {
        let (gameX, gameY) = screenToGame(x: location.x, y: location.y, viewSize: viewSize)
        mouseX = gameX
        mouseY = gameY
        isPressed = true

        // Start long press timer
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDelay, repeats: false) { [weak self] _ in
            self?.onLongPress()
        }
    }

    func onTouchMoved(at location: CGPoint, in viewSize: CGSize) {
        let (gameX, gameY) = screenToGame(x: location.x, y: location.y, viewSize: viewSize)
        mouseX = gameX
        mouseY = gameY

        // Cancel long press if moved too far
        longPressTimer?.invalidate()
    }

    func onTouchEnded(at location: CGPoint, in viewSize: CGSize) {
        let (gameX, gameY) = screenToGame(x: location.x, y: location.y, viewSize: viewSize)
        mouseX = gameX
        mouseY = gameY
        isPressed = false

        longPressTimer?.invalidate()

        if !isLongPress {
            onTap(x: gameX, y: gameY)
        }
        isLongPress = false
    }

    func onTouchCancelled() {
        isPressed = false
        isLongPress = false
        longPressTimer?.invalidate()
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
        guard swipeToRotate else { return }

        let deltaX = Float(translation.width / viewSize.width) * 100
        let deltaY = Float(translation.height / viewSize.height) * 100

        gameClient?.handlePan(deltaX: deltaX, deltaY: deltaY)
    }

    func onPinch(scale: CGFloat) {
        guard swipeToZoom else { return }
        gameClient?.handlePinch(scale: Float(scale))
    }

    // MARK: - Keyboard Input

    func onKeyPress(_ key: String) {
        guard let client = gameClient else { return }

        switch key {
        case "←":
            client.cameraRotation = (client.cameraRotation - 8) & 255
        case "→":
            client.cameraRotation = (client.cameraRotation + 8) & 255
        case "↑":
            client.cameraZoom = min(255, client.cameraZoom + 8)
        case "↓":
            client.cameraZoom = max(0, client.cameraZoom - 8)
        default:
            // Handle text input
            break
        }
    }
}

// MARK: - SwiftUI Gesture Modifiers

struct GameGestureModifier: ViewModifier {
    @ObservedObject var inputHandler: InputHandler
    let viewSize: CGSize

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.translation == .zero {
                            inputHandler.onTouchBegan(at: value.location, in: viewSize)
                        } else {
                            inputHandler.onTouchMoved(at: value.location, in: viewSize)
                            inputHandler.onPan(translation: value.translation, viewSize: viewSize)
                        }
                    }
                    .onEnded { value in
                        inputHandler.onTouchEnded(at: value.location, in: viewSize)
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        inputHandler.onPinch(scale: scale)
                    }
            )
    }
}

extension View {
    func gameGestures(_ handler: InputHandler, viewSize: CGSize) -> some View {
        modifier(GameGestureModifier(inputHandler: handler, viewSize: viewSize))
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
