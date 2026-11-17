import Foundation
import Metal
import QuartzCore
import Scape530

/// The GPU scene renderer (tier 1) and compositor. Per frame it
///  1. uploads what changed (baked chunk vertices of the visible chunks, the frame's dynamic geometry,
///     a few more texture layers),
///  2. draws the 3D scene into the drawable with MSAA, a depth buffer, an anisotropic texture sampler
///     and linear distance fog, inside the viewport rectangle the software client reserved, then
///  3. draws the software client's 2D raster over it with alpha blending (the raster is transparent
///     where the 3D scene shows through, see `Raster(transparent:)`).
///
/// All of it runs on the game queue that calls `present`. Geometry comes from `GPUFrame`
/// (Sources/Scape530/GPU); nothing here knows about rt4 beyond the vertex layout.
final class MetalScenePresenter {
	let device: MTLDevice
	private let queue: MTLCommandQueue
	private let library: MTLLibrary
	private let vertexDescriptor: MTLVertexDescriptor
	private var scenePipelines: [Int: (opaque: MTLRenderPipelineState, blend: MTLRenderPipelineState)] = [:]
	private let compositePipeline: MTLRenderPipelineState
	private let depthWrite: MTLDepthStencilState
	private let depthTestOnly: MTLDepthStencilState
	private let linearClamp: MTLSamplerState
	private let nearestClamp: MTLSamplerState
	private var samplers: [Int: MTLSamplerState] = [:]

	// Per-drawable-size attachments.
	private var msaaColor: MTLTexture?
	private var depth: MTLTexture?
	private var attachmentKey = ""

	// Texture array and material table.
	private var textureSet: GPUTextureSet?
	private var textureKey = ""
	private var textureArray: MTLTexture?
	private var uploaded: [Int: Int] = [:]
	private var failedTextures: Set<Int> = []
	private var materialsBuffer: MTLBuffer?
	private var materialsDirty = true
	private var lastTexturesEnabled = true
	/// Texture layers generated per frame (each is a procedural texture render on the game thread).
	var texturesPerFrame = 3

	// Geometry.
	private struct ChunkBuffers { var opaque: MTLBuffer?; var blend: MTLBuffer?; var lastUsed = 0 }
	private var chunkBuffers: [Int: ChunkBuffers] = [:]
	private var sceneGeneration = -1
	private var frameNumber = 0
	private var dynamicOpaque: [MTLBuffer?] = [nil, nil, nil]
	private var dynamicBlend: [MTLBuffer?] = [nil, nil, nil]

	// UI raster ring (as `MetalFramePresenter`).
	private static let ringSize = 3
	private var uiTextures: [MTLTexture?] = Array(repeating: nil, count: MetalScenePresenter.ringSize)
	private var ringSlot = 0
	private let inflight = DispatchSemaphore(value: MetalScenePresenter.ringSize)

	/// Bilinear (true) or nearest (false) scaling of the 2D layer when the game is scaled to the screen.
	var smoothScaling = true

	/// Highest MSAA count the device supports among 4, 2, 1.
	private func supportedSamples(_ wanted: Int) -> Int {
		for n in [4, 2] where n <= wanted && device.supportsTextureSampleCount(n) { return n }
		return 1
	}

	init?(device: MTLDevice) {
		self.device = device
		guard let queue = device.makeCommandQueue() else { return nil }
		self.queue = queue
		do {
			library = try device.makeLibrary(source: GPUSceneShaders.source, options: nil)
		} catch {
			print("[gpu] shader compile failed: \(error)")
			return nil
		}

		// Layout of `GPUVertex` (Sources/Scape530/GPU/GPUTypes.swift).
		let vd = MTLVertexDescriptor()
		vd.attributes[0].format = .float3
		vd.attributes[0].offset = GPUVertex.layout.position
		vd.attributes[1].format = .float3
		vd.attributes[1].offset = GPUVertex.layout.normal
		vd.attributes[2].format = .float2
		vd.attributes[2].offset = GPUVertex.layout.uv
		vd.attributes[3].format = .uchar4Normalized
		vd.attributes[3].offset = GPUVertex.layout.color
		vd.attributes[4].format = .uchar4Normalized
		vd.attributes[4].offset = GPUVertex.layout.base
		vd.attributes[5].format = .ushort2
		vd.attributes[5].offset = GPUVertex.layout.materialFlags
		for i in 0...5 { vd.attributes[i].bufferIndex = 0 }
		vd.layouts[0].stride = GPUVertex.layout.stride
		vd.layouts[0].stepFunction = .perVertex
		vertexDescriptor = vd

		do {
			let d = MTLRenderPipelineDescriptor()
			d.vertexFunction = library.makeFunction(name: "compositeVertex")
			d.fragmentFunction = library.makeFunction(name: "compositeFragment")
			let c = d.colorAttachments[0]!
			c.pixelFormat = .bgra8Unorm
			c.isBlendingEnabled = true
			c.rgbBlendOperation = .add
			c.alphaBlendOperation = .add
			c.sourceRGBBlendFactor = .sourceAlpha
			c.destinationRGBBlendFactor = .oneMinusSourceAlpha
			c.sourceAlphaBlendFactor = .one
			c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
			compositePipeline = try device.makeRenderPipelineState(descriptor: d)
		} catch {
			print("[gpu] composite pipeline failed: \(error)")
			return nil
		}

		let ds = MTLDepthStencilDescriptor()
		ds.depthCompareFunction = .less
		ds.isDepthWriteEnabled = true
		let dt = MTLDepthStencilDescriptor()
		dt.depthCompareFunction = .less
		dt.isDepthWriteEnabled = false
		guard let w = device.makeDepthStencilState(descriptor: ds), let t = device.makeDepthStencilState(descriptor: dt) else { return nil }
		depthWrite = w
		depthTestOnly = t

		func sampler(_ filter: MTLSamplerMinMagFilter) -> MTLSamplerState? {
			let s = MTLSamplerDescriptor()
			s.minFilter = filter
			s.magFilter = filter
			s.sAddressMode = .clampToEdge
			s.tAddressMode = .clampToEdge
			return device.makeSamplerState(descriptor: s)
		}
		guard let l = sampler(.linear), let n = sampler(.nearest) else { return nil }
		linearClamp = l
		nearestClamp = n
	}

	// MARK: pipelines and samplers

	private func pipelines(samples: Int) -> (opaque: MTLRenderPipelineState, blend: MTLRenderPipelineState)? {
		if let p = scenePipelines[samples] { return p }
		func make(blend: Bool) -> MTLRenderPipelineState? {
			let d = MTLRenderPipelineDescriptor()
			d.vertexFunction = library.makeFunction(name: "sceneVertex")
			d.fragmentFunction = library.makeFunction(name: "sceneFragment")
			d.vertexDescriptor = vertexDescriptor
			d.rasterSampleCount = samples
			d.depthAttachmentPixelFormat = .depth32Float
			let c = d.colorAttachments[0]!
			c.pixelFormat = .bgra8Unorm
			if blend {
				c.isBlendingEnabled = true
				c.rgbBlendOperation = .add
				c.alphaBlendOperation = .add
				c.sourceRGBBlendFactor = .sourceAlpha
				c.destinationRGBBlendFactor = .oneMinusSourceAlpha
				c.sourceAlphaBlendFactor = .one
				c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
			} else {
				// Cut-out textures (leaves, fences) anti-alias through MSAA coverage.
				d.isAlphaToCoverageEnabled = samples > 1
			}
			do { return try device.makeRenderPipelineState(descriptor: d) } catch {
				print("[gpu] scene pipeline failed: \(error)")
				return nil
			}
		}
		guard let o = make(blend: false), let b = make(blend: true) else { return nil }
		scenePipelines[samples] = (o, b)
		return (o, b)
	}

	private func sampler(anisotropy: Int) -> MTLSamplerState? {
		let level = min(16, max(1, anisotropy))
		if let s = samplers[level] { return s }
		let d = MTLSamplerDescriptor()
		d.minFilter = .linear
		d.magFilter = .linear
		d.mipFilter = .linear
		d.sAddressMode = .repeat
		d.tAddressMode = .repeat
		d.maxAnisotropy = level
		let s = device.makeSamplerState(descriptor: d)
		if let s { samplers[level] = s }
		return s
	}

	// MARK: attachments

	private func ensureAttachments(width: Int, height: Int, samples: Int) {
		let key = "\(width)x\(height)x\(samples)"
		guard key != attachmentKey else { return }
		attachmentKey = key
		msaaColor = nil
		depth = nil
		#if targetEnvironment(simulator)
		let transient = MTLStorageMode.private
		#else
		// Tile memory only: neither the multisampled colour nor the depth outlives the pass.
		let transient = MTLStorageMode.memoryless
		#endif
		if samples > 1 {
			let c = MTLTextureDescriptor()
			c.textureType = .type2DMultisample
			c.pixelFormat = .bgra8Unorm
			c.width = width
			c.height = height
			c.sampleCount = samples
			c.usage = .renderTarget
			c.storageMode = transient
			msaaColor = device.makeTexture(descriptor: c)
		}
		let d = MTLTextureDescriptor()
		d.textureType = samples > 1 ? .type2DMultisample : .type2D
		d.pixelFormat = .depth32Float
		d.width = width
		d.height = height
		d.sampleCount = samples
		d.usage = .renderTarget
		d.storageMode = transient
		depth = device.makeTexture(descriptor: d)
	}

	// MARK: textures

	/// Allocates the texture array for a new brightness / scene store, then generates and uploads a few layers
	/// of the textures the frame uses per call. Until a layer is up its material falls back to the average colour.
	private func updateTextures(_ frame: GPUFrame, world: WorldView) {
		let key = "\(frame.brightness)"
		if textureSet == nil || key != textureKey {
			guard let set = world.makeGPUTextureSet() else { return }
			textureSet = set
			textureKey = key
			uploaded = [:]
			failedTextures = []
			let d = MTLTextureDescriptor()
			d.textureType = .type2DArray
			d.pixelFormat = .rgba8Unorm
			d.width = GPUTextureSet.size
			d.height = GPUTextureSet.size
			d.arrayLength = max(1, set.layerCount)
			d.mipmapLevelCount = 8 // 128, 64, ... 1
			d.usage = .shaderRead
			d.storageMode = .shared
			textureArray = device.makeTexture(descriptor: d)
			materialsDirty = true
		}
		guard let set = textureSet, let array = textureArray else { return }
		var budget = texturesPerFrame
		var added = false
		let n = GPUTextureSet.size
		for id in frame.usedTextures.sorted() where budget > 0 && uploaded[id] == nil && !failedTextures.contains(id) {
			guard let layer = set.layerOf[id], let rgba = set.rgba(id: id) else { failedTextures.insert(id); continue }
			rgba.withUnsafeBytes { buf in
				if let base = buf.baseAddress {
					array.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, slice: layer, withBytes: base, bytesPerRow: n * 4, bytesPerImage: n * n * 4)
				}
			}
			uploaded[id] = layer
			budget -= 1
			added = true
		}
		if added, let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
			blit.generateMipmaps(for: array)
			blit.endEncoding()
			cb.commit()
			materialsDirty = true
		}
		if frame.settings.texturesEnabled != lastTexturesEnabled {
			lastTexturesEnabled = frame.settings.texturesEnabled
			materialsDirty = true
		}
		if materialsDirty {
			// With textures off every material keeps layer -1 and shades with its average colour.
			let table = set.materials(uploaded: frame.settings.texturesEnabled ? uploaded : [:])
			table.withUnsafeBytes { buf in
				materialsBuffer = device.makeBuffer(bytes: buf.baseAddress!, length: buf.count, options: .storageModeShared)
			}
			materialsDirty = false
		}
	}

	// MARK: geometry buffers

	private func buffer(for vertices: [GPUVertex]) -> MTLBuffer? {
		guard !vertices.isEmpty else { return nil }
		return vertices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
	}

	private func chunkBuffer(_ c: GPUChunkMesh, blend: Bool) -> MTLBuffer? {
		var entry = chunkBuffers[c.id] ?? ChunkBuffers()
		if blend { if entry.blend == nil { entry.blend = buffer(for: c.blend) } } else if entry.opaque == nil { entry.opaque = buffer(for: c.opaque) }
		entry.lastUsed = frameNumber
		chunkBuffers[c.id] = entry
		return blend ? entry.blend : entry.opaque
	}

	/// Per-frame dynamic vertices go through a ring of growable shared buffers.
	private func dynamicBuffer(_ ring: inout [MTLBuffer?], slot: Int, vertices: [GPUVertex]) -> MTLBuffer? {
		guard !vertices.isEmpty else { return nil }
		let bytes = vertices.count * GPUVertex.layout.stride
		if ring[slot] == nil || ring[slot]!.length < bytes {
			var size = 64 * 1024
			while size < bytes { size <<= 1 }
			ring[slot] = device.makeBuffer(length: size, options: .storageModeShared)
		}
		guard let b = ring[slot] else { return nil }
		vertices.withUnsafeBytes { memcpy(b.contents(), $0.baseAddress!, bytes) }
		return b
	}

	/// Drops GPU buffers of chunks not drawn for a while (rebuilt chunks get new ids, so old ones age out).
	private func purge() {
		if frameNumber % 120 == 0 {
			chunkBuffers = chunkBuffers.filter { frameNumber - $0.value.lastUsed < 240 }
		}
	}

	// MARK: frame

	/// Draws `frame` and the 2D `raster` over it into the layer. Returns false if the frame was skipped.
	@discardableResult
	func present(_ raster: Raster, frame: GPUFrame, world: WorldView, in layer: CAMetalLayer) -> Bool {
		let w = raster.width, h = raster.height
		let dw = layer.drawableSize.width, dh = layer.drawableSize.height
		guard w > 0, h > 0, dw > 0, dh > 0, raster.pixels.count >= w * h else { return false }
		guard inflight.wait(timeout: .now()) == .success else { return false }
		var handedOff = false
		defer { if !handedOff { inflight.signal() } }

		frameNumber += 1
		if frame.sceneGeneration != sceneGeneration {
			sceneGeneration = frame.sceneGeneration
			chunkBuffers = [:]
		}
		updateTextures(frame, world: world)
		// Nothing to draw textured geometry with yet (no scene textures): leave this frame to the software path.
		guard materialsBuffer != nil, textureArray != nil else { return false }

		// 2D layer texture.
		let slot = ringSlot
		var ui = uiTextures[slot]
		if ui == nil || ui!.width != w || ui!.height != h {
			let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
			d.usage = .shaderRead
			d.storageMode = .shared
			ui = device.makeTexture(descriptor: d)
			uiTextures[slot] = ui
		}
		guard let uiTexture = ui else { return false }
		raster.pixels.withUnsafeBytes { buf in
			if let base = buf.baseAddress {
				uiTexture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * 4)
			}
		}
		ringSlot = (slot + 1) % Self.ringSize

		let samples = supportedSamples(frame.settings.msaaSamples)
		guard let drawable = layer.nextDrawable(), let cb = queue.makeCommandBuffer(),
		      let pipes = pipelines(samples: samples),
		      let smp = sampler(anisotropy: frame.settings.anisotropy) else { return false }
		let target = drawable.texture
		ensureAttachments(width: target.width, height: target.height, samples: samples)

		// Game pixels to drawable pixels: aspect fit like `MetalFramePresenter`.
		let fit = min(Double(dw) / Double(w), Double(dh) / Double(h))
		let originX = (Double(dw) - Double(w) * fit) / 2, originY = (Double(dh) - Double(h) * fit) / 2

		let clear = frame.clearColor
		let pass = MTLRenderPassDescriptor()
		let color = pass.colorAttachments[0]!
		if samples > 1, let msaa = msaaColor {
			color.texture = msaa
			color.resolveTexture = target
			color.storeAction = .multisampleResolve
		} else {
			color.texture = target
			color.storeAction = .store
		}
		color.loadAction = .clear
		color.clearColor = MTLClearColor(red: Double(clear.r), green: Double(clear.g), blue: Double(clear.b), alpha: 1)
		if let depth {
			pass.depthAttachment.texture = depth
			pass.depthAttachment.loadAction = .clear
			pass.depthAttachment.clearDepth = 1
			pass.depthAttachment.storeAction = .dontCare
		}
		if let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
			encodeScene(enc, frame: frame, pipelines: pipes, sampler: smp, slot: slot,
			            viewport: (originX + Double(frame.viewport.x) * fit, originY + Double(frame.viewport.y) * fit, Double(frame.viewport.w) * fit, Double(frame.viewport.h) * fit),
			            target: (target.width, target.height))
			enc.endEncoding()
		}

		// 2D layer over it.
		let uiPass = MTLRenderPassDescriptor()
		uiPass.colorAttachments[0].texture = target
		uiPass.colorAttachments[0].loadAction = .load
		uiPass.colorAttachments[0].storeAction = .store
		if let enc = cb.makeRenderCommandEncoder(descriptor: uiPass) {
			var scale = SIMD2<Float>(Float(Double(w) * fit / Double(dw)), Float(Double(h) * fit / Double(dh)))
			let integral = !smoothScaling || (fit >= 1 && abs(fit - fit.rounded()) < 0.01)
			enc.setRenderPipelineState(compositePipeline)
			enc.setVertexBytes(&scale, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
			enc.setFragmentTexture(uiTexture, index: 0)
			enc.setFragmentSamplerState(integral ? nearestClamp : linearClamp, index: 0)
			enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
			enc.endEncoding()
		}

		purge()
		handedOff = true
		let sem = inflight
		cb.addCompletedHandler { _ in sem.signal() }
		cb.present(drawable)
		cb.commit()
		return true
	}

	private func encodeScene(_ enc: MTLRenderCommandEncoder, frame: GPUFrame, pipelines: (opaque: MTLRenderPipelineState, blend: MTLRenderPipelineState),
	                         sampler smp: MTLSamplerState, slot: Int, viewport vp: (Double, Double, Double, Double), target: (Int, Int)) {
		// Viewport in drawable pixels, scissored to the drawable.
		enc.setViewport(MTLViewport(originX: vp.0, originY: vp.1, width: vp.2, height: vp.3, znear: 0, zfar: 1))
		let sx = max(0, min(target.0 - 1, Int(vp.0.rounded(.down)))), sy = max(0, min(target.1 - 1, Int(vp.1.rounded(.down))))
		let ex = max(sx + 1, min(target.0, Int((vp.0 + vp.2).rounded(.up)))), ey = max(sy + 1, min(target.1, Int((vp.1 + vp.3).rounded(.up))))
		enc.setScissorRect(MTLScissorRect(x: sx, y: sy, width: ex - sx, height: ey - sy))
		// rt4 culls faces that are not counter-clockwise on screen (see `GPUVertex`).
		enc.setFrontFacing(.counterClockwise)
		enc.setCullMode(.back)

		var uniforms = frame.uniforms
		let uniformBytes = uniforms.count * MemoryLayout<Float>.stride
		enc.setVertexBytes(&uniforms, length: uniformBytes, index: 1)
		enc.setFragmentBytes(&uniforms, length: uniformBytes, index: 1)
		if let m = materialsBuffer { enc.setFragmentBuffer(m, offset: 0, index: 2) }
		if let t = textureArray { enc.setFragmentTexture(t, index: 0) }
		enc.setFragmentSamplerState(smp, index: 0)

		let dynOpaque = dynamicBuffer(&dynamicOpaque, slot: slot, vertices: frame.dynamic.opaque)
		let dynBlend = dynamicBuffer(&dynamicBlend, slot: slot, vertices: frame.dynamic.blend)

		// Opaque: static ranges nearest first, then actors and animated locs.
		enc.setRenderPipelineState(pipelines.opaque)
		enc.setDepthStencilState(depthWrite)
		for item in frame.list.items where !item.blend {
			guard let b = chunkBuffer(frame.list.chunks[Int(item.chunk)], blend: false) else { continue }
			enc.setVertexBuffer(b, offset: 0, index: 0)
			enc.drawPrimitives(type: .triangle, vertexStart: Int(item.first), vertexCount: Int(item.count))
		}
		if let b = dynOpaque {
			enc.setVertexBuffer(b, offset: 0, index: 0)
			enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: frame.dynamic.opaque.count)
		}

		// Translucent faces after, farthest chunk first, depth-tested but not written.
		enc.setRenderPipelineState(pipelines.blend)
		enc.setDepthStencilState(depthTestOnly)
		for item in frame.list.items where item.blend {
			guard let b = chunkBuffer(frame.list.chunks[Int(item.chunk)], blend: true) else { continue }
			enc.setVertexBuffer(b, offset: 0, index: 0)
			enc.drawPrimitives(type: .triangle, vertexStart: Int(item.first), vertexCount: Int(item.count))
		}
		if let b = dynBlend {
			enc.setVertexBuffer(b, offset: 0, index: 0)
			enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: frame.dynamic.blend.count)
		}
	}
}
