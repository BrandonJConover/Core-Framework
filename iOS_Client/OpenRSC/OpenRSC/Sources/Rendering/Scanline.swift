import Foundation

/// Port of orsc.graphics.three.Scanline from the Java desktop client.
/// Holds per-scanline interpolation state during polygon rasterization.
struct Scanline {
    var m_d: Int = 0
    var m_k: Int = 0
    var m_e: Int = 0
    var m_l: Int = 0
}
