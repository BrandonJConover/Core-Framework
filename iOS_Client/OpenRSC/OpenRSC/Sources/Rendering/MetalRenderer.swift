import Metal
import MetalKit
import SwiftUI

// Renders a 512x334 pixel buffer (Java ARGB Int32 array) to the screen via Metal.
// Same architecture as RSCBitmapSurfaceView.java on Android:
//   game engine writes pixelData -> upload to MTLTexture -> blit full-screen.
final class MetalRenderer: NSObject, MTKViewDelegate {
    static let gameWidth  = 512
    static let gameHeight = 334

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var gameTexture: MTLTexture?

    // Pixel data buffer written by the game engine each frame.
    // Format: Java ARGB (0xAARRGGBB) — converted to RGBA on upload.
    private var pixelData = [UInt32](repeating: 0xFF000000, count: gameWidth * gameHeight)
    private var pixelsDirty = false
    private let lock = NSLock()

    init?(metalDevice: MTLDevice) {
        self.device = metalDevice
        guard let queue = metalDevice.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        super.init()
        setupPipeline()
        setupTexture()
    }

    // Called by RSCGameEngine with the raw pixelData int array each frame.
    // Matches Android: mudclient.getSurface().pixelData → Bitmap.setPixels()
    func updatePixels(_ pixels: [Int32]) {
        lock.lock()
        defer { lock.unlock() }
        for (i, p) in pixels.enumerated() where i < pixelData.count {
            let argb = UInt32(bitPattern: p)
            let a = (argb >> 24) & 0xFF
            let r = (argb >> 16) & 0xFF
            let g = (argb >> 8)  & 0xFF
            let b =  argb        & 0xFF
            // Pack as RGBA for Metal texture (.rgba8Unorm)
            pixelData[i] = (a << 24) | (b << 16) | (g << 8) | r
        }
        pixelsDirty = true
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipeline = pipelineState,
              let texture = gameTexture,
              let cmdBuffer = commandQueue.makeCommandBuffer() else { return }

        lock.lock()
        if pixelsDirty {
            let region = MTLRegionMake2D(0, 0, MetalRenderer.gameWidth, MetalRenderer.gameHeight)
            pixelData.withUnsafeBytes { ptr in
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

    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary(),
              let vertFn = library.makeFunction(name: "vertexShader"),
              let fragFn = library.makeFunction(name: "fragmentShader") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertFn
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func setupTexture() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: MetalRenderer.gameWidth,
            height: MetalRenderer.gameHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        gameTexture = device.makeTexture(descriptor: desc)
    }
}

// SwiftUI wrapper for the MTKView (iOS only)
#if canImport(UIKit)
import SwiftUI
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
            let renderer = MetalRenderer(metalDevice: dev)
            view.delegate = renderer
            engine.renderer = renderer
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
#endif
