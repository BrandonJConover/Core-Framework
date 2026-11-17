/// Metal Shading Language source of the GPU scene renderer, compiled at runtime like
/// `MetalFramePresenter`'s. The struct layouts match `GPUFrame.uniforms` (36 floats), `GPUMaterial`
/// (16 bytes) and `GPUVertex.layout` (44 bytes, see the vertex descriptor in `MetalScenePresenter`).
enum GPUSceneShaders {
	static let source = """
	#include <metal_stdlib>
	using namespace metal;

	struct SceneUniforms {
		float4x4 viewProjection;
		float4 eye;
		float4 fogColor;
		float4 fogParams;      // x start, y end, z enabled
		float4 lightDirection; // unused by tier 1 (colours are baked); HD tiers light base colour with the normal
		float4 lightParams;    // ambient, diffuse
	};

	struct Material {
		int layer;     // texture array layer, -1 while not uploaded
		uint flags;    // 1 = has transparent texels
		uint average;  // RGBA8 average colour, stand-in until uploaded
		uint reserved;
	};

	struct VertexIn {
		float3 position [[attribute(0)]];
		float3 normal [[attribute(1)]];
		float2 uv [[attribute(2)]];
		float4 color [[attribute(3)]];
		float4 base [[attribute(4)]];
		ushort2 materialFlags [[attribute(5)]];
	};

	struct VertexOut {
		float4 position [[position]];
		float2 uv;
		float4 color;
		float viewDepth;
		uint material [[flat]];
	};

	vertex VertexOut sceneVertex(VertexIn in [[stage_in]], constant SceneUniforms &u [[buffer(1)]]) {
		VertexOut o;
		float4 p = u.viewProjection * float4(in.position, 1.0);
		o.viewDepth = p.w;
		// Ground decorations share the terrain's plane: pull them a hair towards the camera.
		if ((in.materialFlags.y & 1) != 0) { p.z -= 0.0002 * p.w; }
		o.position = p;
		o.uv = in.uv;
		o.color = in.color;
		o.material = in.materialFlags.x;
		return o;
	}

	fragment float4 sceneFragment(VertexOut in [[stage_in]],
	                              constant SceneUniforms &u [[buffer(1)]],
	                              constant Material *materials [[buffer(2)]],
	                              texture2d_array<float> textures [[texture(0)]],
	                              sampler smp [[sampler(0)]]) {
		float4 c = in.color;
		if (in.material != 0) {
			Material m = materials[in.material];
			if (m.layer >= 0) {
				c *= textures.sample(smp, in.uv, uint(m.layer));
			} else {
				c.rgb *= unpack_unorm4x8_to_float(m.average).rgb;
			}
		}
		if (c.a < 0.004) { discard_fragment(); }
		if (u.fogParams.z > 0.5) {
			float f = saturate((in.viewDepth - u.fogParams.x) / max(u.fogParams.y - u.fogParams.x, 1.0));
			c.rgb = mix(c.rgb, u.fogColor.rgb, f);
		}
		return c;
	}

	// 2D layer: the software client's raster (straight alpha, transparent where the 3D scene shows).
	struct CompositeOut { float4 position [[position]]; float2 uv; };

	vertex CompositeOut compositeVertex(uint vid [[vertex_id]], constant float2 &scale [[buffer(0)]]) {
		float2 c = float2((vid & 1) != 0 ? 1.0 : -1.0, (vid & 2) != 0 ? 1.0 : -1.0);
		CompositeOut o;
		o.position = float4(c * scale, 0.0, 1.0);
		o.uv = float2((c.x + 1.0) * 0.5, (1.0 - c.y) * 0.5);
		return o;
	}

	fragment float4 compositeFragment(CompositeOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) {
		return tex.sample(smp, in.uv);
	}
	"""
}
