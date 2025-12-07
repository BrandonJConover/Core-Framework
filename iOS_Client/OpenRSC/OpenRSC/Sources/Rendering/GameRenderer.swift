import Foundation
import Metal
import MetalKit
import SwiftUI

/// Metal-based game renderer.
/// Renders the game world to a texture that is displayed in SwiftUI.
final class GameRenderer: NSObject, ObservableObject {
    // Game dimensions
    static let width = 512
    static let height = 334

    // Metal objects
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var texture: MTLTexture?

    // Frame buffer (ARGB format, matching Android)
    private var pixelBuffer: [UInt32]

    // Rendering state
    @Published var isReady = false

    weak var gameClient: GameClient?

    override init() {
        self.pixelBuffer = Array(repeating: 0xFF000000, count: Self.width * Self.height)
        super.init()
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        // Create texture for frame buffer
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Self.width,
            height: Self.height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        self.texture = device.makeTexture(descriptor: textureDescriptor)

        // Create render pipeline
        setupPipeline()

        isReady = true
    }

    private func setupPipeline() {
        guard let device = device else { return }

        // Create simple vertex/fragment shaders inline
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
            float2 positions[6] = {
                float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
                float2(1.0, -1.0), float2(1.0, 1.0), float2(-1.0, 1.0)
            };

            float2 texCoords[6] = {
                float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
                float2(1.0, 1.0), float2(1.0, 0.0), float2(0.0, 0.0)
            };

            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.texCoord = texCoords[vertexID];
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<float> colorTexture [[texture(0)]]) {
            constexpr sampler textureSampler(mag_filter::nearest, min_filter::nearest);
            return colorTexture.sample(textureSampler, in.texCoord);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline: \(error)")
        }
    }

    /// Updates the frame buffer with new pixel data.
    func updateFrameBuffer(_ pixels: [UInt32]) {
        guard pixels.count == pixelBuffer.count else { return }
        pixelBuffer = pixels
        uploadToTexture()
    }

    private func uploadToTexture() {
        guard let texture = texture else { return }

        let region = MTLRegionMake2D(0, 0, Self.width, Self.height)
        pixelBuffer.withUnsafeBytes { ptr in
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: Self.width * 4
            )
        }
    }

    /// Renders the current frame to the given drawable.
    func render(to drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
        guard let pipelineState = pipelineState,
              let texture = texture else { return }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    // MARK: - Software Rendering

    /// Clears the frame buffer to black.
    func clear() {
        pixelBuffer = Array(repeating: 0xFF000000, count: Self.width * Self.height)
    }

    /// Sets a pixel at the given coordinates.
    func setPixel(x: Int, y: Int, color: UInt32) {
        guard x >= 0 && x < Self.width && y >= 0 && y < Self.height else { return }
        pixelBuffer[y * Self.width + x] = color
    }

    /// Draws a filled rectangle.
    func fillRect(x: Int, y: Int, width: Int, height: Int, color: UInt32) {
        for py in y..<min(y + height, Self.height) {
            for px in x..<min(x + width, Self.width) {
                if px >= 0 && py >= 0 {
                    pixelBuffer[py * Self.width + px] = color
                }
            }
        }
    }

    /// Draws a horizontal line.
    func drawHLine(x: Int, y: Int, width: Int, color: UInt32) {
        guard y >= 0 && y < Self.height else { return }
        for px in max(0, x)..<min(x + width, Self.width) {
            pixelBuffer[y * Self.width + px] = color
        }
    }

    /// Draws a vertical line.
    func drawVLine(x: Int, y: Int, height: Int, color: UInt32) {
        guard x >= 0 && x < Self.width else { return }
        for py in max(0, y)..<min(y + height, Self.height) {
            pixelBuffer[py * Self.width + x] = height
        }
    }

    /// Draws text at the given position (simplified).
    func drawText(_ text: String, x: Int, y: Int, color: UInt32) {
        // Simplified text rendering - would use proper font rendering in production
        var px = x
        for char in text {
            // Draw a simple placeholder for each character
            fillRect(x: px, y: y, width: 6, height: 8, color: color)
            px += 7
        }
    }
}

/// SwiftUI view that displays the Metal renderer.
struct GameRendererView: UIViewRepresentable {
    @ObservedObject var gameClient: GameClient

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.gameClient = gameClient
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(gameClient: gameClient)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var gameClient: GameClient
        private let renderer: GameRenderer

        init(gameClient: GameClient) {
            self.gameClient = gameClient
            self.renderer = GameRenderer()
            super.init()
            self.renderer.gameClient = gameClient
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = view.device?.makeCommandQueue()?.makeCommandBuffer() else {
                return
            }

            // Update renderer with game state
            renderer.updateFrameBuffer(gameClient.frameBuffer)

            // Render to drawable
            renderer.render(to: drawable, commandBuffer: commandBuffer)

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// MARK: - Color Utilities

extension UInt32 {
    /// Creates an ARGB color from components.
    static func argb(_ a: UInt8, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt32 {
        return UInt32(a) << 24 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
    }

    /// Creates an RGB color (opaque).
    static func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt32 {
        return argb(255, r, g, b)
    }

    var alpha: UInt8 { UInt8((self >> 24) & 0xFF) }
    var red: UInt8 { UInt8((self >> 16) & 0xFF) }
    var green: UInt8 { UInt8((self >> 8) & 0xFF) }
    var blue: UInt8 { UInt8(self & 0xFF) }
}
