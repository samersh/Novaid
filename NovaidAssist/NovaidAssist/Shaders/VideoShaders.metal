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

/// YUV to RGB conversion matrix (BT.709 HDTV standard)
constant float3x3 kYUVToRGBMatrix = float3x3(
    float3(1.0,     1.0,    1.0),
    float3(0.0,    -0.187,  1.856),
    float3(1.575,  -0.468,  0.0)
);

/// Fragment shader for BGRA texture rendering
fragment float4 fragment_main(VertexOut in [[stage_in]],
                               texture2d<float> videoTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::clamp_to_edge);

    // Sample the video texture (BGRA format)
    float4 color = videoTexture.sample(textureSampler, in.texCoord);

    return color;
}

/// Fragment shader for YUV (NV12) texture rendering
/// ARKit captures in NV12 format (bi-planar YUV 420)
/// This fixes the blue color tint issue
fragment float4 fragment_yuv(VertexOut in [[stage_in]],
                              texture2d<float> yTexture [[texture(0)]],
                              texture2d<float> uvTexture [[texture(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::clamp_to_edge);

    // Sample Y (luma) plane
    float y = yTexture.sample(textureSampler, in.texCoord).r;

    // Sample UV (chroma) plane
    float2 uv = uvTexture.sample(textureSampler, in.texCoord).rg;

    // Convert from YUV to RGB
    // Y: [0, 1], UV: [0, 1] centered at 0.5
    float3 yuv = float3(y, uv.x - 0.5, uv.y - 0.5);
    float3 rgb = kYUVToRGBMatrix * yuv;

    return float4(rgb, 1.0);
}
