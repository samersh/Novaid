#include <metal_stdlib>
using namespace metal;

/// Vertex shader output structure
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

/// Vertex shader for full-screen quad
/// Generates texture coordinates and positions for a full-screen quad without vertex buffer
vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    // Create full-screen triangle strip (6 vertices for 2 triangles)
    // Maps to texture coordinates (0,0) to (1,1)

    const float2 positions[6] = {
        float2(-1.0, -1.0),  // Bottom-left
        float2( 1.0, -1.0),  // Bottom-right
        float2(-1.0,  1.0),  // Top-left
        float2(-1.0,  1.0),  // Top-left
        float2( 1.0, -1.0),  // Bottom-right
        float2( 1.0,  1.0)   // Top-right
    };

    const float2 texCoords[6] = {
        float2(0.0, 1.0),  // Bottom-left (flipped Y)
        float2(1.0, 1.0),  // Bottom-right
        float2(0.0, 0.0),  // Top-left
        float2(0.0, 0.0),  // Top-left
        float2(1.0, 1.0),  // Bottom-right
        float2(1.0, 0.0)   // Top-right
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];

    return out;
}

/// Fragment shader for video texture rendering
fragment float4 fragment_main(VertexOut in [[stage_in]],
                               texture2d<float> videoTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::clamp_to_edge);

    // Sample the video texture
    float4 color = videoTexture.sample(textureSampler, in.texCoord);

    return color;
}
