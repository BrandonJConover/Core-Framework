import CoreGraphics

// Maps iOS touch coordinates to RSC game coordinates and gesture types.
// Port of InputImpl.java (com.openrsc.android.render.InputImpl).
// Game canvas is always 512x334 logical pixels.
final class TouchTranslator {
    static let gameWidth:  CGFloat = 512
    static let gameHeight: CGFloat = 334

    // Callback set by RSCGameEngine to receive translated actions.
    var onTap:       ((Int, Int) -> Void)?     // x, y in game coords
    var onLongPress: ((Int, Int) -> Void)?
    var onPan:       ((CGFloat, CGFloat) -> Void)?  // dx, dy
    var onPinch:     ((CGFloat) -> Void)?       // scale factor

    private(set) var viewSize: CGSize = .zero

    func setViewSize(_ size: CGSize) {
        viewSize = size
    }

    // Translate a UIKit CGPoint to game (x, y) coordinates.
    func gameCoords(from point: CGPoint) -> (x: Int, y: Int) {
        guard viewSize.width > 0, viewSize.height > 0 else { return (0, 0) }
        let x = Int(point.x / viewSize.width  * TouchTranslator.gameWidth)
        let y = Int(point.y / viewSize.height * TouchTranslator.gameHeight)
        return (x, y)
    }

    // Called from GameView onTapGesture
    func handleTap(at point: CGPoint) {
        let (x, y) = gameCoords(from: point)
        onTap?(x, y)
    }

    // Called from long-press recognizer
    func handleLongPress(at point: CGPoint) {
        let (x, y) = gameCoords(from: point)
        onLongPress?(x, y)
    }

    // Called from pan recognizer — maps to camera rotation / pitch
    func handlePan(translation: CGPoint) {
        onPan?(translation.x, translation.y)
    }

    // Called from pinch recognizer — maps to zoom
    func handlePinch(scale: CGFloat) {
        onPinch?(scale)
    }
}
