import Metal
import QuartzCore
import Scape530

/// Uploads the client's software-rendered `Raster` (0xAARRGGBB words = BGRA bytes on little-endian)
/// into a shared-storage MTLTexture and draws it as a fullscreen quad into a `CAMetalLayer`,
/// aspect-fitted (letterboxed) in the layer's drawable. A ring of textures with a semaphore keeps the
/// CPU from overwriting a texture the GPU is still sampling; when the GPU falls behind the frame is
/// skipped rather than blocking the main thread.
final class MetalFramePresenter {
	private static let shaderSource = """
	#include <metal_stdlib>
	using namespace metal;
	struct VOut { float4 position [[position]]; float2 uv; };
	vertex VOut frameVertex(uint vid [[vertex_id]], constant float4 &place [[buffer(0)]]) {
		float2 c = float2((vid & 1) != 0 ? 1.0 : -1.0, (vid & 2) != 0 ? 1.0 : -1.0);
		VOut o;
		o.position = float4(c * place.xy + place.zw, 0.0, 1.0);
		o.uv = float2((c.x + 1.0) * 0.5, (1.0 - c.y) * 0.5);
		return o;
	}
	fragment float4 frameFragment(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) {
		return float4(tex.sample(smp, in.uv).rgb, 1.0);
	}
	"""

	private static let ringSize = 3

	/// Scaling quality: true smooths non-integer scales (bilinear); false is always pixel-exact (nearest).
	var smoothScaling = true
	/// Extra zoom applied after the aspect fit, as a scale about the drawable's centre and a translation in
	/// drawable fractions (the mobile login zoom; see `GameCanvasView.updateZoom`). Identity when nil.
	var zoom: (scale: Double, tx: Double, ty: Double)?

	let device: MTLDevice
	private let queue: MTLCommandQueue
	private let pipeline: MTLRenderPipelineState
	private let linear: MTLSamplerState
	private let nearest: MTLSamplerState
	private var textures: [MTLTexture?] = Array(repeating: nil, count: MetalFramePresenter.ringSize)
	private var nextTexture = 0
	private let inflight = DispatchSemaphore(value: MetalFramePresenter.ringSize)

	init?() {
		guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
		self.device = device
		self.queue = queue
		do {
			let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
			let d = MTLRenderPipelineDescriptor()
			d.vertexFunction = library.makeFunction(name: "frameVertex")
			d.fragmentFunction = library.makeFunction(name: "frameFragment")
			d.colorAttachments[0].pixelFormat = .bgra8Unorm
			pipeline = try device.makeRenderPipelineState(descriptor: d)
		} catch {
			print("[metal] pipeline failed: \(error)")
			return nil
		}
		func sampler(_ filter: MTLSamplerMinMagFilter) -> MTLSamplerState? {
			let s = MTLSamplerDescriptor()
			s.minFilter = filter
			s.magFilter = filter
			s.sAddressMode = .clampToEdge
			s.tAddressMode = .clampToEdge
			return device.makeSamplerState(descriptor: s)
		}
		guard let l = sampler(.linear), let n = sampler(.nearest) else { return nil }
		linear = l
		nearest = n
	}

	/// Configures a layer to be presented to by this presenter.
	func attach(to layer: CAMetalLayer) {
		layer.device = device
		layer.pixelFormat = .bgra8Unorm
		layer.framebufferOnly = true
		layer.isOpaque = true
		layer.maximumDrawableCount = 3
	}

	/// Draws `raster` aspect-fitted into the layer. Returns false if the frame was skipped.
	@discardableResult
	func present(_ raster: Raster, in layer: CAMetalLayer) -> Bool {
		let w = raster.width, h = raster.height
		let dw = layer.drawableSize.width, dh = layer.drawableSize.height
		guard w > 0, h > 0, dw > 0, dh > 0, raster.pixels.count >= w * h else { return false }
		guard inflight.wait(timeout: .now()) == .success else { return false }
		var handedOff = false
		defer { if !handedOff { inflight.signal() } }

		let slot = nextTexture
		var tex = textures[slot]
		if tex == nil || tex!.width != w || tex!.height != h {
			let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
			d.usage = .shaderRead
			d.storageMode = .shared
			tex = device.makeTexture(descriptor: d)
			textures[slot] = tex
		}
		guard let texture = tex else { return false }
		raster.pixels.withUnsafeBytes { buf in
			if let base = buf.baseAddress {
				texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * 4)
			}
		}
		nextTexture = (slot + 1) % Self.ringSize

		guard let drawable = layer.nextDrawable(), let cb = queue.makeCommandBuffer() else { return false }
		let pass = MTLRenderPassDescriptor()
		pass.colorAttachments[0].texture = drawable.texture
		pass.colorAttachments[0].loadAction = .clear
		pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
		pass.colorAttachments[0].storeAction = .store
		guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return false }

		// Aspect fit: the largest uniform scale that keeps the whole frame inside the drawable.
		let fit = min(Double(dw) / Double(w), Double(dh) / Double(h))
		let z = zoom ?? (1, 0, 0)
		// NDC: x right, y up; the translation is given in drawable fractions with y down.
		var place = SIMD4<Float>(Float(Double(w) * fit * z.scale / Double(dw)), Float(Double(h) * fit * z.scale / Double(dh)),
		                         Float(z.tx * 2), Float(-z.ty * 2))
		// Whole-number magnification stays pixel-exact; anything else is smoothed.
		let integral = !smoothScaling || (fit * z.scale >= 1 && abs(fit * z.scale - (fit * z.scale).rounded()) < 0.01)
		enc.setRenderPipelineState(pipeline)
		enc.setVertexBytes(&place, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
		enc.setFragmentTexture(texture, index: 0)
		enc.setFragmentSamplerState(integral ? nearest : linear, index: 0)
		enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
		enc.endEncoding()

		handedOff = true
		let sem = inflight
		cb.addCompletedHandler { _ in sem.signal() }
		cb.present(drawable)
		cb.commit()
		return true
	}
}
