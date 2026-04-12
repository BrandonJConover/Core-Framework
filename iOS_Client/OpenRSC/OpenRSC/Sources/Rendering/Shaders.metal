#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Full-screen quad: 2 triangles covering NDC [-1,1]
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
