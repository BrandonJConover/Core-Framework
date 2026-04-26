import Metal
import MetalKit
import SwiftUI

// Renders a 512x334 pixel buffer (Java ARGB Int32 array) to the screen via Metal.
final class MetalRenderer: NSObject, MTKViewDelegate, ObservableObject {
    static let gameWidth  = 512
    static let gameHeight = 334

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var gameTexture: MTLTexture?

    private var pixelData = [UInt8](repeating: 0, count: gameWidth * gameHeight * 4)
    private var pixelsDirty = false
    private let lock = NSLock()
    private var updateCount = 0

    // Metal shader source compiled at runtime (avoids SPM bundle issues)
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut vertexShader(uint vid [[vertex_id]]) {
        const float2 positions[6] = {
            {-1,  1}, { 1,  1}, {-1, -1},
            {-1, -1}, { 1,  1}, { 1, -1}
        };
        const float2 texCoords[6] = {
            {0, 0}, {1, 0}, {0, 1},
            {0, 1}, {1, 0}, {1, 1}
        };
        VertexOut out;
        out.position = float4(positions[vid], 0, 1);
        out.texCoord = texCoords[vid];
        return out;
    }

    fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::nearest, address::clamp_to_edge);
        return tex.sample(s, in.texCoord);
    }
    """

    func setup(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            print("[Metal] Failed to create command queue")
            return
        }
        self.commandQueue = queue
        setupPipeline(device: device)
        setupTexture(device: device)
    }

    // Called by RSCGameEngine with the raw pixelData int array each frame.
    func updatePixels(_ pixels: [Int32]) {
        lock.lock()
        defer { lock.unlock() }

        let count = min(pixels.count, MetalRenderer.gameWidth * MetalRenderer.gameHeight)
        for i in 0..<count {
            let argb = UInt32(bitPattern: pixels[i])
            let base = i * 4
            // RGBA byte order for .rgba8Unorm texture
            pixelData[base]     = UInt8((argb >> 16) & 0xFF) // R
            pixelData[base + 1] = UInt8((argb >> 8)  & 0xFF) // G
            pixelData[base + 2] = UInt8( argb        & 0xFF) // B
            pixelData[base + 3] = UInt8((argb >> 24) & 0xFF) // A
        }
        pixelsDirty = true

        updateCount += 1
        if updateCount <= 3 || updateCount % 200 == 0 {
            print("[Metal] Frame \(updateCount), pipeline=\(pipelineState != nil) texture=\(gameTexture != nil)")
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipeline = pipelineState,
              let texture = gameTexture,
              let cmdBuffer = commandQueue?.makeCommandBuffer() else { return }

        lock.lock()
        if pixelsDirty {
            let region = MTLRegionMake2D(0, 0, MetalRenderer.gameWidth, MetalRenderer.gameHeight)
            pixelData.withUnsafeBufferPointer { ptr in
                texture.replace(region: region, mipmapLevel: 0,
                                withBytes: ptr.baseAddress!,
                                bytesPerRow: MetalRenderer.gameWidth * 4)
            }
            pixelsDirty = false
        }
        lock.unlock()

        guard let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    // MARK: - Setup

    private func setupPipeline(device: MTLDevice) {
        // Compile shader from source at runtime (avoids SPM resource bundle issues)
        do {
            let library = try device.makeLibrary(source: MetalRenderer.shaderSource, options: nil)
            guard let vertFn = library.makeFunction(name: "vertexShader"),
                  let fragFn = library.makeFunction(name: "fragmentShader") else {
                print("[Metal] Failed to find shader functions")
                return
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertFn
            desc.fragmentFunction = fragFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
            print("[Metal] Pipeline created successfully")
        } catch {
            print("[Metal] Pipeline setup failed: \(error)")
        }
    }

    private func setupTexture(device: MTLDevice) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: MetalRenderer.gameWidth,
            height: MetalRenderer.gameHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif
        gameTexture = device.makeTexture(descriptor: desc)
        print("[Metal] Texture created: \(gameTexture != nil)")
    }
}

// SwiftUI wrapper for the MTKView
#if canImport(UIKit)
struct MetalViewRepresentable: UIViewRepresentable {
    let engine: RSCGameEngine

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.autoResizeDrawable = true
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 30
        view.backgroundColor = .black
        if let dev = view.device {
            engine.renderer.setup(device: dev)
            view.delegate = engine.renderer
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
#endif
