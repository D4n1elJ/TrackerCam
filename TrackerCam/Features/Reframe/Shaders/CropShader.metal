#include <metal_stdlib>
using namespace metal;

// Reframe (crop + scale) and YUV→RGB convert in a single pass (plan §10 GPU Pipeline).
// Input is the delivered 420 bi-planar buffer (luma R8 + chroma RG8). Crop is expressed in
// normalized source coordinates (top-left origin) so the SAME params drive preview and record.

struct CropParams {
    float2 cropOrigin;   // normalized [0,1], top-left of crop in source
    float2 cropSize;     // normalized [0,1]
};

// BT.709 video-range YUV → RGB.
static float3 yuvToRGB(float y, float2 cbcr) {
    float yy = (y - 16.0/255.0) * (255.0/219.0);
    float cb = (cbcr.x - 128.0/255.0) * (255.0/224.0);
    float cr = (cbcr.y - 128.0/255.0) * (255.0/224.0);
    float r = yy + 1.5748 * cr;
    float g = yy - 0.1873 * cb - 0.4681 * cr;
    float b = yy + 1.8556 * cb;
    return float3(r, g, b);
}

kernel void reframeYUV(texture2d<float, access::sample> lumaTex   [[texture(0)]],
                       texture2d<float, access::sample> chromaTex [[texture(1)]],
                       texture2d<float, access::write>  outTex    [[texture(2)]],
                       constant CropParams& params                [[buffer(0)]],
                       uint2 gid                                  [[thread_position_in_grid]]) {
    uint2 outSize = uint2(outTex.get_width(), outTex.get_height());
    if (gid.x >= outSize.x || gid.y >= outSize.y) return;

    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::normalized);

    float2 outUV = (float2(gid) + 0.5) / float2(outSize);
    float2 srcUV = params.cropOrigin + outUV * params.cropSize;

    float y = lumaTex.sample(s, srcUV).r;
    float2 cbcr = chromaTex.sample(s, srcUV).rg;
    float3 rgb = clamp(yuvToRGB(y, cbcr), 0.0, 1.0);

    outTex.write(float4(rgb, 1.0), gid);
}

// ---- Passthrough used by the preview to draw the reframed texture into the drawable (aspect-fill).

struct BlitVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex BlitVertexOut blitVertex(uint vid [[vertex_id]]) {
    // Full-screen triangle.
    float2 positions[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
    float2 uvs[3]       = { float2(0.0, 2.0),  float2(0.0, 0.0), float2(2.0, 0.0) };
    BlitVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

fragment float4 blitFragment(BlitVertexOut in [[stage_in]],
                             texture2d<float, access::sample> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::normalized);
    return tex.sample(s, in.uv);
}
