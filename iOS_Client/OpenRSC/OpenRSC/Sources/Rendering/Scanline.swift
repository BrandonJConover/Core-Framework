// Port of Client_Base/src/orsc/graphics/three/Scanline.java
// Uses `struct` (value type) — Java's `final class Scanline` holds only primitive
// fields so value semantics are safe and more efficient in Swift arrays.
// All integer fields use Int32 to match Java `int`.

struct Scanline {
    var m_e: Int32 = 0
    var m_k: Int32 = 0
    var m_d: Int32 = 0
    var m_l: Int32 = 0
}
