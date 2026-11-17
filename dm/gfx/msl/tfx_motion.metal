// Camera motion vectors for MetalFX's temporal scaler (nvn_mtl.m up_tfx_motion; DM_UPSCALER=metalfx-temporal): a game that draws no velocity (Ocarina of Time) gets, per texel,
// where the surface it shows was in the previous frame, from its depth and the camera's view-projection now and a frame before. Right for everything that moves with the camera only;
// a moving object gets the motion of a still one there (MetalFX's history rejection takes the rest).
// tfx_prep (one thread): reads this frame's view-projection from the game's view buffer (as the GPU has it now: inline updates landed) and inverts it; takes the previous one from
// the game's own previous set where it keeps one (prev_off), else from the host's copy (two slots, written and read alternately, so the copy is never written while read), and
// the host's copy where both exist but differ; stores this one for the next frame without its jitter; and decides a camera cut: the mean displacement of up to 64 depth samples (8x8
// grid, sky excluded) over cut_frac of the width, or the game's previous set differing from the host's copy. tfx_motion: per texel, MetalFX's convention (pixels to where it was, +x right, +y down), without the jitter; on a cut, a vector far
// off the screen, so no history is taken.
// Jitter: a subpixel offset (jx, jy) in pixels moves the projection in clip space, dx = 2 jx / w, dy = -2 jy / h: the view-projection's rows 0 and 1 gain dx and dy times row 3 (the
// host's jitter, when it has one, is applied that way). The previous matrices are always without it (the game's own set is written from its own matrices; the host's copy has it
// taken out), so the vector is where the surface was minus where this texel's sample would be without jitter.
#include <metal_stdlib>
using namespace metal;
struct tfx_params {
    uint w, h;               // the content (pixels); the depth's content is at its origin
    uint vp_off;             // byte offset of this frame's view-projection in the view buffer
    uint prev_off;           // byte offset of the previous frame's, if the game keeps it (0: not)
    uint row_major;          // 1: the matrix is stored row by row (GL row_major), 0: column by column
    uint have_prev;          // the slot not written now holds last frame's view-projection
    uint slot;               // the slot written now (0 or 1)
    float jit[2];            // this frame's subpixel jitter in pixels (this frame's matrix includes it); 0 without jitter
    float cut_frac;          // a mean displacement over this fraction of the width is a cut
};
struct tfx_state { float4 inv[4]; float4 prev[4]; uint ok, cut, samples; float mean; uint prev_src, game_matches; };   // rows of inverse(VP_cur) and of VP_prev;
// prev_src: 0 none (this frame's: no motion), 1 the host's copy, 2 the game's; game_matches: the game's previous set equals the host's copy, with or without its jitter (1), not (0), not compared (2)
struct tfx_hist { float4 vp[2][4]; float4 jvp[2][4]; };   // rows of the view-projection per slot: without the jitter, and as the buffer held it (with it)

static float4x4 rows_of(device const float *m, uint row_major) {   // Metal's float4x4 is column-major: build it from rows so that M * v is the GL product
    float4x4 r;
    for (uint i = 0; i < 4; i++) for (uint j = 0; j < 4; j++) r[j][i] = row_major ? m[4 * i + j] : m[4 * j + i];
    return r;
}
static float4x4 inverse4(float4x4 m, thread bool &ok) {   // cofactors (Metal has no 4x4 inverse)
    float a00 = m[0][0], a01 = m[0][1], a02 = m[0][2], a03 = m[0][3], a10 = m[1][0], a11 = m[1][1], a12 = m[1][2], a13 = m[1][3],
          a20 = m[2][0], a21 = m[2][1], a22 = m[2][2], a23 = m[2][3], a30 = m[3][0], a31 = m[3][1], a32 = m[3][2], a33 = m[3][3];
    float b00 = a00 * a11 - a01 * a10, b01 = a00 * a12 - a02 * a10, b02 = a00 * a13 - a03 * a10, b03 = a01 * a12 - a02 * a11, b04 = a01 * a13 - a03 * a11, b05 = a02 * a13 - a03 * a12,
          b06 = a20 * a31 - a21 * a30, b07 = a20 * a32 - a22 * a30, b08 = a20 * a33 - a23 * a30, b09 = a21 * a32 - a22 * a31, b10 = a21 * a33 - a23 * a31, b11 = a22 * a33 - a23 * a32;
    float det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
    ok = isfinite(det) && fabs(det) > 1e-30f;
    float id = ok ? 1.0f / det : 0.0f;
    float4x4 r;
    r[0] = float4(a11 * b11 - a12 * b10 + a13 * b09, a02 * b10 - a01 * b11 - a03 * b09, a31 * b05 - a32 * b04 + a33 * b03, a22 * b04 - a21 * b05 - a23 * b03) * id;
    r[1] = float4(a12 * b08 - a10 * b11 - a13 * b07, a00 * b11 - a02 * b08 + a03 * b07, a32 * b02 - a30 * b05 - a33 * b01, a20 * b05 - a22 * b02 + a23 * b01) * id;
    r[2] = float4(a10 * b10 - a11 * b08 + a13 * b06, a01 * b08 - a00 * b10 - a03 * b06, a30 * b04 - a31 * b02 + a33 * b00, a21 * b02 - a20 * b04 - a23 * b00) * id;
    r[3] = float4(a11 * b07 - a10 * b09 - a12 * b06, a00 * b09 - a01 * b07 + a02 * b06, a31 * b01 - a30 * b03 - a32 * b00, a20 * b03 - a21 * b01 + a22 * b00) * id;
    return r;
}
static float4x4 from_rows(const device float4 *r) { float4x4 m; for (uint i = 0; i < 4; i++) for (uint j = 0; j < 4; j++) m[j][i] = r[i][j]; return m; }
static void to_rows(float4x4 m, device float4 *r) { for (uint i = 0; i < 4; i++) r[i] = float4(m[0][i], m[1][i], m[2][i], m[3][i]); }
// Where texel p (its centre, in pixels, +y down) at depth d (GL: ndc z = 2d - 1) was in the previous frame, in pixels; false when it cannot be placed
static bool reproject(float2 p, float d, float2 size, float4x4 inv, float4x4 prev, thread float2 &q) {
    float4 ndc = float4(2.0f * p.x / size.x - 1.0f, 1.0f - 2.0f * p.y / size.y, 2.0f * d - 1.0f, 1.0f);
    float4 wp = inv * ndc;
    if (!(fabs(wp.w) > 1e-20f)) return false;
    float4 c = prev * (wp / wp.w);
    if (!(c.w > 1e-20f)) return false;   // behind the previous camera
    float2 n = c.xy / c.w;
    q = float2((n.x + 1.0f) * 0.5f * size.x, (1.0f - n.y) * 0.5f * size.y);
    return all(isfinite(q));
}
kernel void tfx_prep(constant tfx_params &pm [[buffer(0)]], device const uchar *view [[buffer(1)]], device tfx_hist &hist [[buffer(2)]], device tfx_state &st [[buffer(3)]],
                     depth2d<float, access::read> depth [[texture(0)]]) {
    float4x4 cur = rows_of((device const float *)(view + pm.vp_off), pm.row_major);
    bool ok; float4x4 inv = inverse4(cur, ok);
    float4x4 plain = cur; float dx = 2.0f * pm.jit[0] / float(pm.w), dy = -2.0f * pm.jit[1] / float(pm.h);   // this frame's matrix without its jitter, for the next frame
    for (uint c = 0; c < 4; c++) { plain[c][0] -= dx * plain[c][3]; plain[c][1] -= dy * plain[c][3]; }
    // The game's previous set is a copy of last frame's buffer (Ocarina of Time: as the host left it, so with last frame's jitter): it matches the host's copy as written or without the
    // jitter. Either way the motion takes the host's copy without the jitter; the game's set only when the host has none (the first frame after a gap, which restarts anyway)
    float4x4 prev = plain, host = from_rows(hist.vp[pm.slot ^ 1u]), hostj = from_rows(hist.jvp[pm.slot ^ 1u]); uint src = 0, match = 2;
    if (pm.prev_off) {
        float4x4 game = rows_of((device const float *)(view + pm.prev_off), pm.row_major); float d = 0, dj = 0, s = 0;
        if (pm.have_prev) for (uint c = 0; c < 4; c++) { float4 a = abs(game[c] - host[c]), b = abs(game[c] - hostj[c]), h = abs(host[c]);
                                                        d = max(d, max(max(a.x, a.y), max(a.z, a.w))); dj = max(dj, max(max(b.x, b.y), max(b.z, b.w))); s = max(s, max(max(h.x, h.y), max(h.z, h.w))); }
        if (pm.have_prev) match = min(d, dj) <= 1e-5f * max(s, 1e-30f);
        if (pm.have_prev) { prev = host; src = 1; } else { prev = game; src = 2; }
    } else if (pm.have_prev) { prev = host; src = 1; }
    to_rows(plain, hist.vp[pm.slot]); to_rows(cur, hist.jvp[pm.slot]);
    to_rows(inv, st.inv); to_rows(prev, st.prev); st.prev_src = src; st.game_matches = match;
    float2 size = float2(pm.w, pm.h), sum = 0; uint n = 0;
    if (ok && src) for (uint gy = 0; gy < 8; gy++) for (uint gx = 0; gx < 8; gx++) {
        uint2 t = uint2((2 * gx + 1) * pm.w / 16, (2 * gy + 1) * pm.h / 16); float d = depth.read(t);
        float2 p = float2(t) + 0.5f, q;
        if (d < 1.0f && reproject(p, d, size, inv, prev, q)) { sum += fabs(q - p); n++; }
    }
    float mean = n ? length(sum / float(n)) : 0.0f;
    // A cut: the depth samples moved over cut_frac of the width, or the game's previous view-projection is not the one this frame's predecessor had (a game that writes its previous
    // set from its own camera history restarts it on a cut or a load: Ocarina of Time's matched in 81 frames of play, so a mismatch is taken as a cut)
    st.ok = ok; st.samples = n; st.mean = mean; st.cut = (ok && n && mean > pm.cut_frac * float(pm.w)) || match == 0;
}
kernel void tfx_motion(constant tfx_params &pm [[buffer(0)]], device const tfx_state &st [[buffer(3)]], depth2d<float, access::read> depth [[texture(0)]],
                       texture2d<float, access::write> mv [[texture(1)]], uint2 t [[thread_position_in_grid]]) {
    if (t.x >= pm.w || t.y >= pm.h) return;
    float2 m = 0;
    if (st.cut) m = float2(2.0f * pm.w, 2.0f * pm.h);   // off the screen: MetalFX finds no history for any texel
    else if (st.ok) {
        float2 p = float2(t) + 0.5f, q;
        if (reproject(p, depth.read(t), float2(pm.w, pm.h), from_rows(st.inv), from_rows(st.prev), q))
            m = q - (p - float2(pm.jit[0], pm.jit[1]));   // to where it was (the previous matrices have no jitter) from where this sample is without this frame's jitter
    }
    mv.write(float4(m, 0, 0), t);
}
// The reactive mask (nvn_mtl.m up_tfx_mask): 1 where the scene colour changed since its snapshot before the translucent and effect passes, from the relative change of luminance r
// (signed, over the brighter of the two): its local part, |r| less the mean of r over the 5x5 around the texel (lo to hi as 0 to 1), so a full-screen layer that moves every texel by
// a few percent (Ocarina of Time composites a half-size haze layer and a volumetric fog over the whole scene after the opaque passes) cancels while a sprite's or a particle's edges
// stay; and the whole of it from alo to ahi, so a strong change counts over its whole area. The largest over the 3x3 around the texel (the edges a moving effect blurs), and at least
// last frame's mask: where an effect was a frame ago the history still holds it (the camera's motion does not follow the effect). 0 without a snapshot this frame.
// A threadgroup takes a 16x16 tile: r of its 20x20 (the tile and 2 around) once into threadgroup memory, the 5x5 means and 3x3 maxima from there: 2 texture reads a texel and a
// few more for the edges, not 50 (in a game run at 2880x1620 the 50-read version took 0.43 ms a frame); the 5x5 sum separable (rows, then columns), half precision.
// The glow (have_glow): the compose adds a bloom (Ocarina of Time: 240x135, its fragment texture 1) after the snapshot's range, so the glow around a moving light (Navi) is in no
// diff above. Its change since last frame, high-passed at the glow's own size (tfx_glow_d, tfx_glow_hp: the change less its 5x5 mean, so a broad glow that pulses as a whole cancels and
// a moving blob stays), over the brightness there (the scene's luminance and the glow), glo to ghi as 0 to 1. Without the high pass a game run's lava glow, pulsing over the whole cave,
// set the mask's mean to 70-90 % and the history was thrown away
// The whole picture's brightness (have_lum): the scaler's input's mean luminance this frame against last frame's (tfx_lum_mean), as a change relative to the larger, flo to fhi as 0
// to 1 over the whole picture. A fade, a flash or the lights going down change every texel and none of the terms above sees it: they compare the scene before and after its
// translucent passes in one frame, and a fade is drawn after them (by the compose) or between frames. Without it the output lagged a fade to black and back by 30 % in t_upscaler_tfx
struct tfx_mparams { uint w, h, have, have_prev; float lo, hi, alo, ahi; uint have_glow; float glo, ghi, gfloor; uint have_lum, lum_now, lum_prev; float flo, fhi; };
static float tfx_lum(float3 c) { return dot(max(c, 0.0f), float3(0.2126f, 0.7152f, 0.0722f)); }
// The mean luminance of c (w x h at its origin) over a 64x32 grid of texels, into lum[slot]: one threadgroup of 256 threads
struct tfx_lparams { uint w, h, slot; };
kernel void tfx_lum_mean(constant tfx_lparams &p [[buffer(0)]], texture2d<float, access::read> c [[texture(0)]], device float *lum [[buffer(1)]],
                         uint i [[thread_index_in_threadgroup]], uint si [[simdgroup_index_in_threadgroup]], uint sl [[thread_index_in_simdgroup]], uint ns [[simdgroups_per_threadgroup]]) {
    threadgroup float part[32];
    float s = 0;
    for (uint k = i; k < 2048; k += 256) { uint gx = k % 64, gy = k / 64; s += tfx_lum(c.read(uint2((2 * gx + 1) * p.w / 128, (2 * gy + 1) * p.h / 64)).rgb); }
    s = simd_sum(s); if (sl == 0) part[si] = s;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (i == 0) { float t = 0; for (uint k = 0; k < ns; k++) t += part[k]; lum[p.slot] = t / 2048.0f; }
}
kernel void tfx_mask(constant tfx_mparams &p [[buffer(0)]], texture2d<float, access::read> now [[texture(0)]], texture2d<float, access::read> before [[texture(1)]],
                     texture2d<float, access::write> mask [[texture(2)]], texture2d<float, access::read> prev [[texture(3)]], texture2d<float> glow [[texture(4)]],
                     texture2d<float> glow_hp [[texture(5)]], texture2d<float, access::write> raw [[texture(6)]], device atomic_uint *covered [[buffer(1)]], device const float *lum [[buffer(2)]],
                     uint2 t [[thread_position_in_grid]], uint2 l [[thread_position_in_threadgroup]], uint2 g [[threadgroup_position_in_grid]]) {
    threadgroup half rs[20][20], hs[20][16];   // r of the tile and 2 around; the 5-wide row sums of each of the tile's columns
    bool in = t.x < p.w && t.y < p.h;
    if (p.have) {
        int2 base = int2(g) * 16 - 2;
        for (uint i = l.y * 16 + l.x; i < 400; i += 256) {
            uint2 q = uint2(clamp(base + int2(i % 20, i / 20), int2(0), int2(p.w - 1, p.h - 1)));
            float a = tfx_lum(now.read(q).rgb), b = tfx_lum(before.read(q).rgb);
            rs[i / 20][i % 20] = half((a - b) / max(max(a, b), 0.05f));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint i = l.y * 16 + l.x; i < 320; i += 256) { uint y = i / 16, x = i % 16; hs[y][x] = rs[y][x] + rs[y][x + 1] + rs[y][x + 2] + rs[y][x + 3] + rs[y][x + 4]; }   // the 5x5 mean, separable
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    // prev: last frame's own terms (raw), not last frame's mask: taking the mask, which held the frame before's, kept every mark for good (a sprite's start still 0.6 twenty frames on)
    float m = 0, tl = 0, tw = 0, tg = 0;   // m: this frame's terms (tl, tw, tg: local, whole and glow, the log's breakdown)
    if (in && p.have) {
        float mean = (float(hs[l.y][l.x]) + float(hs[l.y + 1][l.x]) + float(hs[l.y + 2][l.x]) + float(hs[l.y + 3][l.x]) + float(hs[l.y + 4][l.x])) / 25.0f;
        float lm = 0, am = 0;
        for (uint dy = 1; dy <= 3; dy++) for (uint dx = 1; dx <= 3; dx++) { float r = float(rs[l.y + dy][l.x + dx]); lm = max(lm, abs(r - mean)); am = max(am, abs(r)); }
        tl = smoothstep(p.lo, p.hi, lm); tw = smoothstep(p.alo, p.ahi, am); m = max(m, max(tl, tw));
    }
    if (in && p.have_glow) {
        constexpr sampler bl(filter::linear, address::clamp_to_edge);
        float2 uv = (float2(t) + 0.5f) / float2(p.w, p.h);
        float hp = glow_hp.sample(bl, uv).r, gn = tfx_lum(glow.sample(bl, uv).rgb), sc = p.have ? tfx_lum(now.read(t).rgb) : 0.0f;
        tg = smoothstep(p.glo, p.ghi, hp / max(gn + sc, p.gfloor)); m = max(m, tg);
    }
    if (in && p.have_lum) { float a = lum[p.lum_now], b = lum[p.lum_prev]; m = max(m, smoothstep(p.flo, p.fhi, abs(a - b) / max(max(a, b), 0.02f))); }   // the whole picture's brightness
    // the sums in 1/255ths of the mask and of each term, for their means in the log (one atomic per SIMD group each; 4K fits in 32 bits)
    uint n = simd_sum(in ? uint(m * 255.0f + 0.5f) : 0u), nl = simd_sum(in ? uint(tl * 255.0f + 0.5f) : 0u), nw = simd_sum(in ? uint(tw * 255.0f + 0.5f) : 0u), ng = simd_sum(in ? uint(tg * 255.0f + 0.5f) : 0u);
    if (simd_is_first()) { if (n) atomic_fetch_add_explicit(&covered[0], n, memory_order_relaxed); if (nl) atomic_fetch_add_explicit(&covered[1], nl, memory_order_relaxed);
                           if (nw) atomic_fetch_add_explicit(&covered[2], nw, memory_order_relaxed); if (ng) atomic_fetch_add_explicit(&covered[3], ng, memory_order_relaxed); }
    if (in) { raw.write(float4(m), t); mask.write(float4(max(m, p.have_prev ? prev.read(t).r : 0.0f)), t); }   // MetalFX's: this frame's and last frame's terms
}
// The glow's change at its own size (tfx_glow_d), then that change less its local mean, as a magnitude (tfx_glow_hp): see tfx_mask. gw x gh the glow's size, w x h the render size the
// motion is at. The change is against a running average of the glow's luminance (avg_last, reprojected: where the camera's motion at the texel's place says it was), blended by `blend`
// each frame (1: last frame's glow alone). With the camera jittered the bloom chain's first downsample (about 8x, few taps) catches small bright things (embers, the lava's cracks,
// Navi's core) on other taps every frame, so the glow flickers by a texel all over: a game run's mask covered 26-54 % of Dodongo's Cavern against last frame's glow. The flicker
// averages out in the running average, a moving or growing glow still differs from it
struct tfx_gparams { uint gw, gh, w, h, hp, box, have_avg; float blend; uint blur; };
kernel void tfx_glow_d(constant tfx_gparams &p [[buffer(0)]], texture2d<float> glow [[texture(0)]], texture2d<float> avg_last [[texture(1)]], texture2d<float, access::read> mv [[texture(2)]],
                       texture2d<float, access::write> d [[texture(3)]], texture2d<float, access::write> avg [[texture(4)]], uint2 t [[thread_position_in_grid]]) {
    if (t.x >= p.gw || t.y >= p.gh) return;
    constexpr sampler bl(filter::linear, address::clamp_to_edge);
    float2 uv = (float2(t) + 0.5f) / float2(p.gw, p.gh), at = uv * float2(p.w, p.h);
    float2 m = mv.read(uint2(min(at, float2(p.w - 1, p.h - 1)))).xy;
    float gn = tfx_lum(glow.read(t).rgb), ga = p.have_avg ? avg_last.sample(bl, uv + m / float2(p.w, p.h)).r : gn;
    d.write(float4(gn - ga), t);
    avg.write(float4(mix(ga, gn, p.blend)), t);
}
// The change (blurred 3x3 with blur: a flicker is a texel, a halo several), less its mean over box x box (5 or 9), as a magnitude; hp 0: the change as it is (the tests' comparison)
kernel void tfx_glow_hp(constant tfx_gparams &p [[buffer(0)]], texture2d<float, access::read> d [[texture(0)]], texture2d<float, access::write> hp [[texture(1)]], uint2 t [[thread_position_in_grid]]) {
    if (t.x >= p.gw || t.y >= p.gh) return;
    int r = int(p.box / 2); float c = 0, mean = 0;
    for (int dy = -r; dy <= r; dy++) for (int dx = -r; dx <= r; dx++) {
        float v = d.read(uint2(clamp(int2(t) + int2(dx, dy), int2(0), int2(p.gw - 1, p.gh - 1)))).r;
        mean += v; if (abs(dx) <= 1 && abs(dy) <= 1) c += v;
    }
    float centre = p.hp && p.blur ? c / 9.0f : d.read(t).r;
    hp.write(float4(abs(centre - (p.hp ? mean / float((2 * r + 1) * (2 * r + 1)) : 0.0f))), t);
}
// Not a coherence weight (the change one-signed over a window taken as a pulse, to drop the ring the high pass leaves at a pulsing pool's edge): Navi's glow changes as her wings flap,
// her core 850 to 2,000 px from frame to frame while she hovers, one-signed too, and a 41-frame capture of Dodongo's Cavern showed the weight taking her away (3.6 % of her area marked
// against 17.5 %) while the ring it removes was small there (0.65 % of the lava's area)
// The sharpen after the temporal scaler (nvn_mtl.m up_tfx_sharpen), in the form of AMD FidelityFX's RCAS: the centre and its 4-neighbour cross; a negative lobe for the cross, as large
// as the neighbourhood allows without the result leaving the cross's range (per channel: from its minimum over 4 times its maximum, and from the room to the peak), at most 3/16,
// times the strength. A flat area comes out as it is, an edge does not ring. Linear colour above 1 (HDR) is taken relative to the neighbourhood's peak
struct tfx_sparams { uint w, h; float s; uint ox, oy; };   // ox, oy: where in dst the result goes (the game's output rectangle)
kernel void tfx_sharpen(constant tfx_sparams &p [[buffer(0)]], texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]], uint2 t [[thread_position_in_grid]]) {
    if (t.x >= p.w || t.y >= p.h) return;
    int2 c = int2(t), hi = int2(p.w - 1, p.h - 1);
    float4 e4 = src.read(t);
    float3 e = e4.rgb, b = src.read(uint2(clamp(c + int2(0, -1), int2(0), hi))).rgb, d = src.read(uint2(clamp(c + int2(-1, 0), int2(0), hi))).rgb,
           f = src.read(uint2(clamp(c + int2(1, 0), int2(0), hi))).rgb, h = src.read(uint2(clamp(c + int2(0, 1), int2(0), hi))).rgb;
    float3 mn = min(min(b, d), min(f, h)), mx = max(max(b, d), max(f, h));
    float k = max(1.0f, max(max(max(mx.r, mx.g), mx.b), max(max(e.r, e.g), e.b)));   // HDR: the neighbourhood's peak as 1
    float3 mn4 = max(mn / k, 0.0f), mx4 = mx / k, ek = e / k;
    float3 hit_min = min(mn4, ek) / max(4.0f * mx4, 1e-6f), hit_max = (1.0f - max(mx4, ek)) / min(4.0f * mn4 - 4.0f, -1e-6f);   // RCAS's limiters (FidelityFX 1.0)
    float3 lobe3 = max(-hit_min, hit_max);
    float lobe = max(-0.1875f, min(max(max(lobe3.r, lobe3.g), lobe3.b), 0.0f)) * p.s;
    float3 o = (lobe * (b + d + f + h) + e) / (4.0f * lobe + 1.0f);
    o = clamp(o, min(mn, e), max(mx, e));   // RCAS keeps 0 to 1 only: a hard edge would undershoot and overshoot its two sides (0.2 | 0.8 → 0.15 | 0.85); within the cross nothing rings
    dst.write(float4(o, e4.a), t + uint2(p.ox, p.oy));
}
