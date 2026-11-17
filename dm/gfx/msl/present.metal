// The present: the frame drawn into the drawable, cropped (nvn_mtl.m present_pipeline)
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; float2 uv; };
vertex V vs(uint id [[vertex_id]]) { float2 uv = float2((id << 1) & 2, id & 2); V o; o.p = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); o.uv = uv; return o; }
struct Crop { float4 rect; float4 edge; };
fragment float4 fs(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) { return t.sample(s, clamp(in.uv * c.rect.zw + c.rect.xy, c.edge.xy, c.edge.zw)); }
// The HDR present (DM_HDR_PRESENT, nvn_mtl.m present_pipeline_hdr): the frame drawn into an RGBA16Float (or, for PQ, RGB10A2Unorm) drawable whose colorspace is BT.2100 PQ (target 1) or extended linear sRGB
// (target 2). h.x: how the source is encoded (0 SDR: sRGB gamma, BT.709; 1 PQ, BT.2020; 2 linear, BT.709, 1.0 = paper white); h.y: the target; h.z: paper white in nits;
// h.w: 1 = the PQ source taken as BT.709 primaries (DM_HDR_GAMUT=709, a diagnostic; games' PQ is BT.2020), converted to the PQ layer's BT.2020.
// A source in the target's encoding is copied as it is; another is decoded to linear light, its primaries converted, and encoded for the target
struct CropHdr { float4 rect; float4 edge; float4 h; };
constant float PQ_M1 = 0.1593017578125, PQ_M2 = 78.84375, PQ_C1 = 0.8359375, PQ_C2 = 18.8515625, PQ_C3 = 18.6875;
static float3 pq_nits(float3 e) { float3 p = pow(saturate(e), 1 / PQ_M2); return pow(max(p - PQ_C1, 0) / (PQ_C2 - PQ_C3 * p), 1 / PQ_M1) * 10000; }
static float3 pq_encode(float3 nits) { float3 p = pow(saturate(nits / 10000), PQ_M1); return pow((PQ_C1 + PQ_C2 * p) / (1 + PQ_C3 * p), PQ_M2); }
static float3 srgb_linear(float3 c) { c = saturate(c); return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045); }
// ITU-R BT.2087 (BT.709 → BT.2020) and its inverse, as columns
constant float3x3 BT709_TO_2020 = float3x3(float3(0.627404, 0.069097, 0.016391), float3(0.329283, 0.919540, 0.088013), float3(0.043313, 0.011362, 0.895595));
constant float3x3 BT2020_TO_709 = float3x3(float3(1.660491, -0.124550, -0.018151), float3(-0.587641, 1.132900, -0.100579), float3(-0.072850, -0.008349, 1.118730));
fragment float4 fs_hdr(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant CropHdr& c [[buffer(0)]]) {
    float4 v = t.sample(s, clamp(in.uv * c.rect.zw + c.rect.xy, c.edge.xy, c.edge.zw));
    uint src = uint(c.h.x), dst = uint(c.h.y); float pw = c.h.z;
    if (src == dst && c.h.w == 0) return float4(v.rgb, 1);   // opaque: the HDR layer is (front_mac.m), and a source's alpha means nothing on screen
    float3 lin = src == 1 ? pq_nits(v.rgb) / pw : src == 2 ? v.rgb : srgb_linear(v.rgb);   // linear light, 1.0 = paper white
    bool wide = src == 1 && c.h.w == 0;   // in BT.2020 primaries
    if (dst == 1) return float4(pq_encode(max(wide ? lin : BT709_TO_2020 * lin, 0) * pw), 1);
    return float4(wide ? BT2020_TO_709 * lin : lin, 1);   // scRGB: values below 0 are colours outside BT.709 (BT.2020's greens and reds), kept for the extended range
}
