import Foundation

/// Port of orsc.graphics.three.Polygon from the Java desktop client.
/// Represents a polygon face in the 3D scene graph.
/// Class (reference type) because Scene mutates polygons in-place via shared references.
final class RSPolygon {
    var model: RSModel?
    var faceID: Int = 0
    var orientation: Int = 0
    var normalX: Int = 0
    var normalY: Int = 0
    var normalZ: Int = 0
    var minP6: Int = 0
    var maxP6: Int = 0
    var minP2: Int = 0
    var maxP2: Int = 0
    var minZ: Int = 0
    var maxZ: Int = 0
    var m_b: Int = 0
    var m_t: Int = 0
    var m_f: Int = 0
    var m_p: Int = -1
    var m_c: Bool = false
}
