// Port of Client_Base/src/orsc/graphics/three/Polygon.java
// Uses `final class` (reference type) to match Java semantics — polygons are
// stored and mutated by reference in Scene arrays.
// All integer fields use Int32 to match Java `int`.

final class Polygon {
    var m_b: Int32 = 0
    var m_c: Bool = false
    var minP6: Int32 = 0
    var m_f: Int32 = 0
    var minP2: Int32 = 0
    var faceID: Int32 = 0
    var maxP2: Int32 = 0
    var normalZ: Int32 = 0
    var normalY: Int32 = 0
    var maxP6: Int32 = 0
    var model: RSModel? = nil
    var m_p: Int32 = -1
    var maxZ: Int32 = 0
    var normalX: Int32 = 0
    var orientation: Int32 = 0
    var m_t: Int32 = 0
    var minZ: Int32 = 0
}
