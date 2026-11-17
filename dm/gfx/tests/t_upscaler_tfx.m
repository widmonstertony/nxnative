// The game's upscaler on MetalFX's temporal scaler (DM_UPSCALER=metalfx-temporal; nvn_mtl.m up_tfx_encode), offscreen on synthetic colour, depth and motion, through the same
// dispatch the spatial scaler takes (up_mfx_encode: one of the game's upscaler shaders reading a 960x540 texture and writing a 1920x1080 image):
// - without a resolver (none is written for any game yet) every dispatch is drawn by the spatial scaler, and the image is filled;
// - with one that hands depth and motion, the temporal scaler draws: a static scene converges (successive outputs stop changing, its mean is the input's), a bright square that moves
//   8 input pixels a frame is followed (its centre in the output is twice its centre in the input, and the place it left a few frames before is background again; with any
//   vectors), a pan of a fine low-contrast pattern converges on the current frame only with the right motion vectors (MetalFX's sign: to where the texel was), a square-rooted input comes out squared, a smaller content in the same textures (a dynamic resolution) keeps the scaler, and a frame with no evaluation
//   restarts the history, and a colour the resolver hands (in another format, linear) is taken in place of the dispatch's;
// - the profile's resolver (tfx_compose, Ocarina of Time's): the compose draw's depth target, of this frame only, with the dispatch's own colour; zero motion with DM_UPSCALER_TFX_MOTION=zero;
//   camera motion from the view buffer (tfx_view) against a synthetic camera over a plane; the reactive mask on a translucent sprite moving over a still scene
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(c, label) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)
#ifndef T_MV_SIGN
#define T_MV_SIGN 1   // the motion vectors' sign (a build with 0 or -1 shows the motion check fails with wrong vectors)
#endif
enum { IW = 960, IH = 540, OW = 1920, OH = 1080, SQ = 64, STEP = 8 };
static tex_t texture(uint64_t serial, unsigned w, unsigned h, int format) {
    tex_t t = {.magic = MAGIC('T','E','X',0), .serial = serial, .off = serial << 24};
    t.d = (nvn_texdesc){.target = NVN_TEXTURE_TARGET_2D, .format = format, .width = w, .height = h, .depth = 1, .levels = 1, .samples = 1, .flags = NVN_TEXTURE_FLAGS_IMAGE};
    nvn_tex_layout(&t.d, &t.L); return t;
}
static void clear(id<MTLTexture> t, MTLClearColor c, int depth, double z) {
    id<MTLCommandBuffer> cb = q_cb(); MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    if (depth) { rp.depthAttachment.texture = t; rp.depthAttachment.loadAction = MTLLoadActionClear; rp.depthAttachment.storeAction = MTLStoreActionStore; rp.depthAttachment.clearDepth = z; }
    else { rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore; rp.colorAttachments[0].clearColor = c; }
    [[cb renderCommandEncoderWithDescriptor:rp] endEncoding]; [cb commit]; [cb waitUntilCompleted];
}
static void upload(id<MTLTexture> t, const void *px, size_t texel) {   // a whole texture from CPU texels (a private texture: through a buffer)
    size_t row = t.width * texel, n = row * t.height; id<MTLBuffer> b = [g_dev newBufferWithBytes:px length:n options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = q_cb(); id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromBuffer:b sourceOffset:0 sourceBytesPerRow:row sourceBytesPerImage:n sourceSize:MTLSizeMake(t.width, t.height, 1) toTexture:t destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
    [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
}
static float *readback(id<MTLTexture> t) {   // RGBA16F texels as floats (the caller frees)
    NSUInteger n = t.width * t.height; id<MTLBuffer> b = [g_dev newBufferWithLength:n * 8 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = q_cb(); id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(t.width, t.height, 1) toBuffer:b destinationOffset:0 destinationBytesPerRow:t.width * 8 destinationBytesPerImage:n * 8];
    [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    float *f = malloc(n * 16); const __fp16 *p = b.contents; for (NSUInteger i = 0; i < n * 4; i++) f[i] = p[i];
    return f;
}
static double mean_r(const float *f, NSUInteger x0, NSUInteger y0, NSUInteger w, NSUInteger h, NSUInteger stride) {
    double s = 0; for (NSUInteger y = y0; y < y0 + h; y++) for (NSUInteger x = x0; x < x0 + w; x++) s += f[4 * (y * stride + x)];
    return s / (double)(w * h);
}
// The test's resolver: depth and motion it was given, or none
static id<MTLTexture> r_dep, r_mot, r_col; static int r_reset, r_calls;
static int resolve(NvShader *cs, MTLRegion color, up_tfx_inputs *x) {
    (void)cs; (void)color; r_calls++;
    if (!r_dep) { x->why = "test: none"; return 0; }
    if (r_col) { x->color = r_col; x->color_rect = MTLRegionMake2D(0, 0, r_col.width, r_col.height); }
    x->depth = r_dep; x->motion = r_mot; x->mv_scale[0] = x->mv_scale[1] = 1; x->depth_reversed = 1; x->reset = r_reset; r_reset = 0;
    return 1;
}
static NvShader *upscaler(void) {
    char key[24] = "7629d857a0a93833_b"; if (DM_GAME_UPSCALER_N) snprintf(key, sizeof key, "%.16s_b", DM_GAME_UPSCALER_KEYS);
    NvShader *s = [NvShader new]; snprintf(s->key, sizeof s->key, "%s", key); s->up_color = UP_COLOR_LINEAR;
    s->rf.nb = 2; s->rf.b[0] = (nvn_rbind){.kind = NVN_RB_TEX, .dtt = MTLTextureType2D, .dpf = NVN_DPF_FLOAT, .reg = 0};
    s->rf.b[1] = (nvn_rbind){.kind = NVN_RB_IMG, .dtt = MTLTextureType2D, .dpf = NVN_DPF_FLOAT, .reg = 1, .rw = 1};
    return s;
}
static uint64_t frame_no; static NvProg *compose_draw, *scene_draw;   // draws the frame makes before the dispatch (up_tfx_capture), or nil
static const tex_t *scene_depth, *scene_color, *compose_color;   // their targets
static NvProg *extra_draw; static const tex_t *extra_color, *extra_depth;   // a draw after the compose, into its own targets
static NvShader *stage1; static uint32_t stage1_in, up_in, stage2_in;   // the network's first stage: a dispatch reading texture stage1_in at reg 3 before the upscaler's, which then reads up_in;
                                                                           // with stage2_in, a later stage reads that texture too
static int frame(NvShader *up) {   // one frame: the upscaler's dispatch in a submission of its own
    atomic_store(&g_cur_frame, ++frame_no);
    if (scene_draw) { R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = scene_color; R.rt.depth = scene_depth; up_tfx_capture(scene_draw); }
    if (compose_draw) { if (compose_color) { R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = compose_color; R.rt.depth = scene_depth; } up_tfx_capture(compose_draw); }
    if (extra_draw) { const tex_t *c0 = R.rt.color[0], *d0 = R.rt.depth; R.rt.color[0] = extra_color; R.rt.depth = extra_depth; up_tfx_capture(extra_draw); R.rt.color[0] = c0; R.rt.depth = d0; }
    if (stage1) { S.tex[5][3] = stage1_in; up_tfx_dispatch_note(stage1); if (stage2_in) { S.tex[5][3] = stage2_in; up_tfx_dispatch_note(stage1); } S.tex[5][0] = up_in; }   // as the dispatch path notes each dispatch before the upscaler's
    mtl_sub_begin(); int drawn = up_mfx_encode(up);
    int ok = mtl_wait(mtl_sub_commit(), 5000000000ull) && !mtl_last_commit_error();
    return drawn && ok;
}
static void rects(unsigned cw, unsigned ch) { const uint32_t r[8] = {0, 0, cw - 1, ch - 1, 0, 0, OW - 1, OH - 1}; memcpy(S.push[1], r, sizeof r); }
// A pan: a fine, low-contrast pattern (all of it inside the clamp a temporal scaler puts on its history, so nothing but the motion vectors tells history from the current frame)
// moved PAN input pixels to the right since the previous frame, at every texel, and its motion. pos: how far it has moved
enum { PAN = 3 };
static float pan_at(double x, double y) { return 0.5f + 0.08f * (float)(sin(2 * M_PI * x / 7.3) * sin(2 * M_PI * y / 5.1)); }
static void pan(__fp16 *col, __fp16 *mot, int pos, int moving) {
    for (int y = 0; y < IH; y++) for (int x = 0; x < IW; x++) {
        __fp16 *c = col + 4 * (y * IW + x); c[0] = c[1] = c[2] = pan_at(x + 0.5 - pos, y + 0.5); c[3] = 1;
        mot[2 * (y * IW + x)] = moving ? -PAN * T_MV_SIGN : 0; mot[2 * (y * IW + x) + 1] = 0;   // MetalFX: to where the texel was in the previous frame
    }
}
// How far the output is from the current frame: the mean of |2x2 box of the output - the input texel| over the middle half (edges take what came in from outside)
static double pan_error(const float *f, const __fp16 *col) {
    double e = 0; int n = 0;
    for (int y = IH / 4; y < IH * 3 / 4; y++) for (int x = IW / 4; x < IW * 3 / 4; x++, n++) {
        double b = (f[4 * ((2 * y) * OW + 2 * x)] + f[4 * ((2 * y) * OW + 2 * x + 1)] + f[4 * ((2 * y + 1) * OW + 2 * x)] + f[4 * ((2 * y + 1) * OW + 2 * x + 1)]) / 4;
        e += fabs(b - (double)col[4 * (y * IW + x)]);
    }
    return e / n;
}
// A picture of the background and a bright square whose left edge is at sx (input pixels), and its motion (the square's texels moved STEP to the right since the previous frame)
static void scene(__fp16 *col, __fp16 *mot, int sx, int moving) {
    for (int y = 0; y < IH; y++) for (int x = 0; x < IW; x++) {
        int in = x >= sx && x < sx + SQ && y >= IH / 2 - SQ / 2 && y < IH / 2 + SQ / 2;
        __fp16 *c = col + 4 * (y * IW + x); float v = in ? 1.0f : 0.1f + 0.05f * (float)((x / 16 + y / 16) & 1);   // the background a coarse static checker
        c[0] = c[1] = c[2] = v; c[3] = 1;
        mot[2 * (y * IW + x)] = in && moving ? -STEP * T_MV_SIGN : 0; mot[2 * (y * IW + x) + 1] = 0;   // MetalFX: to where the texel was in the previous frame
    }
}
// A synthetic camera at (cx, 0, 0) turned by yaw (radians, to the right) over the plane z = -PD, seen through a GL perspective (vertical field 60 degrees, near 0.1, far 25000), and the
// plane's picture: the low-contrast pan pattern in plane units of PS per input pixel at the centre. Everything in doubles, as the reference
enum { PD = 10 };
static const double PS = 2.0 * PD * 0.57735026918962576 / IH;   // world units per input pixel on the plane at the centre
static void cam_pv(double yaw, double cx, double P[16], double V[16]) {
    double fy = 1 / tan(M_PI / 6), fx = fy * IH / IW, n = 0.1, f = 25000, p[16] = {fx, 0, 0, 0, 0, fy, 0, 0, 0, 0, (f + n) / (n - f), 2 * f * n / (n - f), 0, 0, -1, 0};
    double c = cos(yaw), s = sin(yaw), v[16] = {c, 0, s, -c * cx, 0, 1, 0, 0, -s, 0, c, s * cx, 0, 0, 0, 1};   // R_y(yaw) after moving the world by -cx
    memcpy(P, p, sizeof p); memcpy(V, v, sizeof v);
}
static void cam_vp(double yaw, double cx, double vp[16]) {
    double P[16], V[16]; cam_pv(yaw, cx, P, V);
    for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) { double a = 0; for (int k = 0; k < 4; k++) a += P[4 * i + k] * V[4 * k + j]; vp[4 * i + j] = a; }
}
static int cam_hit(double yaw, double cx, double px, double py, double w[3]) {   // the plane point texel centre (px, py) shows
    double fy = 1 / tan(M_PI / 6), fx = fy * IH / IW, nx = 2 * px / IW - 1, ny = 1 - 2 * py / IH, d[3] = {nx / fx, ny / fy, -1}, c = cos(yaw), s = sin(yaw);
    double wd[3] = {c * d[0] - s * d[2], d[1], s * d[0] + c * d[2]};   // R_y(yaw) transposed
    if (wd[2] >= -1e-9) return 0;
    double t = -PD / wd[2]; w[0] = cx + t * wd[0]; w[1] = t * wd[1]; w[2] = -PD; return 1;
}
static void cam_project(const double vp[16], const double w[3], double *px, double *py, double *depth) {
    double c[4]; for (int i = 0; i < 4; i++) c[i] = vp[4 * i] * w[0] + vp[4 * i + 1] * w[1] + vp[4 * i + 2] * w[2] + vp[4 * i + 3];
    *px = (c[0] / c[3] + 1) / 2 * IW; *py = (1 - c[1] / c[3]) / 2 * IH; if (depth) *depth = (c[2] / c[3] + 1) / 2;
}
static uint8_t *view_mem;   // guest memory holding the view buffer at +0x1000
static double tj[2];        // the jitter the host applied this frame (pixels): texel p shows what the unjittered camera sees at p + 0.5 - tj
static void cam_buf(uint8_t *buf, double yaw, double cx, double prev_yaw, double prev_cx, float w, float h) {   // a view buffer as the game writes it (unjittered)
    double vp[16], pv[16], P[16], V[16]; cam_vp(yaw, cx, vp); cam_vp(prev_yaw, prev_cx, pv); cam_pv(yaw, cx, P, V);
    float *v = (float *)buf;
    for (int i = 0; i < 16; i++) { v[DM_GAME_TFX_VIEW_VP / 4 + i] = (float)vp[i]; if (DM_GAME_TFX_VIEW_PREV) v[DM_GAME_TFX_VIEW_PREV / 4 + i] = (float)pv[i]; }
    if (DM_GAME_TFX_JITTER) { for (int i = 0; i < 16; i++) v[DM_GAME_TFX_JIT_P / 4 + i] = (float)P[i]; for (int i = 0; i < 12; i++) v[DM_GAME_TFX_JIT_VIEW / 4 + i] = (float)V[i];
                              v[DM_GAME_TFX_JIT_SIZE / 4] = w; v[DM_GAME_TFX_JIT_SIZE / 4 + 1] = h; }
    if (DM_GAME_TFX_CUT_INV) { double c = cos(yaw), s = sin(yaw), iv[12] = {c, 0, -s, cx, 0, 1, 0, 0, s, 0, c, 0};   // the inverse view, rows: R_y(yaw) transposed, the camera's position last
                               for (int i = 0; i < 12; i++) v[DM_GAME_TFX_CUT_INV / 4 + i] = (float)iv[i]; }
}
static void cam_frame(double yaw, double cx, double prev_yaw, double prev_cx, id<MTLTexture> colour, id<MTLTexture> depth, __fp16 *cpx) {   // the view buffer, the depth and the picture
    double vp[16]; cam_vp(yaw, cx, vp);
    cam_buf(view_mem + 0x1000, yaw, cx, prev_yaw, prev_cx, IW, IH);   // rows (the profile's row-major)
    float *dp = malloc((size_t)IW * IH * 4);
    for (int y = 0; y < IH; y++) for (int x = 0; x < IW; x++) {
        double w[3], qx, qy, d = 1; float val = 0.5f;
        if (cam_hit(yaw, cx, x + 0.5 - tj[0], y + 0.5 - tj[1], w)) { cam_project(vp, w, &qx, &qy, &d); val = pan_at(w[0] / PS, w[1] / PS); }
        dp[y * IW + x] = (float)d; __fp16 *c = cpx + 4 * (y * IW + x); c[0] = c[1] = c[2] = val; c[3] = 1;
    }
    upload(depth, dp, 4); upload(colour, cpx, 8); free(dp);
}
// The motion texture against the reference (the plane point each texel shows, projected by the previous camera): the largest error in pixels, and the centre texel's vector
static double cam_motion_error(id<MTLTexture> mot, double yaw, double cx, double prev_yaw, double prev_cx, float centre[2]) {
    NSUInteger n = (NSUInteger)IW * IH; id<MTLBuffer> b = [g_dev newBufferWithLength:n * 4 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = q_cb(); id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromTexture:mot sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(IW, IH, 1) toBuffer:b destinationOffset:0 destinationBytesPerRow:IW * 4 destinationBytesPerImage:n * 4];
    [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    const __fp16 *m = b.contents; double pv[16], worst = 0; cam_vp(prev_yaw, prev_cx, pv);
    for (int y = 0; y < IH; y++) for (int x = 0; x < IW; x++) {
        double ux = x + 0.5 - tj[0], uy = y + 0.5 - tj[1], w[3], qx, qy; if (!cam_hit(yaw, cx, ux, uy, w)) continue;   // where the texel's sample is in the unjittered picture
        cam_project(pv, w, &qx, &qy, NULL);
        double ex = fabs((double)m[2 * (y * IW + x)] - (qx - ux)), ey = fabs((double)m[2 * (y * IW + x) + 1] - (qy - uy));
        worst = fmax(worst, fmax(ex, ey) / fmax(1.0, 0.002 * fmax(fabs(qx - x), fabs(qy - y))));   // half floats: within 0.2 % of the vector's size
    }
    centre[0] = m[2 * ((IH / 2) * IW + IW / 2)]; centre[1] = m[2 * ((IH / 2) * IW + IW / 2) + 1];
    return worst;
}
// One frame as the game draws it for the jitter (section 11): B (1920x1080, the same camera) and a shadow camera (another projection) bound before A, then A, then the compose and the
// upscaler. The host picks the jitter at A and writes it into A and B; the rows are checked against the expected ones, and the picture is rendered with that jitter (tj). 1 when jittered
static struct { tex_t *ccol, *sdep; NvProg *scene, *pr; NvShader *up; __fp16 *cpx; int checked, bad_a, bad_b, bad_other, cuts, copy_prev, have_last; uint8_t last_vp[64]; } jt;
static int jt_rows(const float *buf, const double M[16], int off, float dx, float dy, float tol) {   // rows 0, 1 of the matrix at off: M's plus the offset times row 3
    int bad = 0;
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) { double want = M[4 * r + c] + (r == 0 ? dx : r == 1 ? dy : 0) * M[12 + c];
        bad += fabs(buf[off / 4 + 4 * r + c] - want) > tol * fmax(1, fabs(want)); }
    return bad;
}
static int jframe(double yaw, double pyaw) {
    static uint8_t shadow0[0x3500], keep[0x3500];
    atomic_store(&g_cur_frame, ++frame_no);
    cam_buf(view_mem + 0x5000, yaw, 0, pyaw, 0, 1920, 1080); cam_buf(view_mem + 0x9000, yaw + 1, 0, pyaw + 1, 0, 153, 153);
    ((float *)(view_mem + 0x9000))[DM_GAME_TFX_JIT_P / 4] *= 1.5f; memcpy(shadow0, view_mem + 0x9000, sizeof shadow0);
    tj[0] = tj[1] = 0; cam_frame(yaw, 0, pyaw, 0, tex_mtl(jt.ccol), tex_mtl(jt.sdep), jt.cpx);
    if (jt.copy_prev && jt.have_last) memcpy(view_mem + 0x1000 + DM_GAME_TFX_VIEW_PREV, jt.last_vp, 64);   // as Ocarina of Time: its previous set copies last frame's buffer (with the host's jitter)
    uint8_t prev0[64], view0[48]; memcpy(prev0, view_mem + 0x1000 + DM_GAME_TFX_VIEW_PREV, 64); memcpy(view0, view_mem + 0x1000 + DM_GAME_TFX_JIT_VIEW, 48);
    p_bind_buf bA = {.addr = (uint64_t)view_mem + 0x1000, .size = (uint64_t)g_tfx_view_size}, bB = {.addr = (uint64_t)view_mem + 0x5000, .size = (uint64_t)g_tfx_view_size},
               bS = {.addr = (uint64_t)view_mem + 0x9000, .size = (uint64_t)g_tfx_view_size};
    R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = jt.ccol; R.rt.depth = jt.sdep;
    S.ubo[DM_GAME_TFX_VIEW_STAGE][DM_GAME_TFX_VIEW_SLOT] = bB; up_tfx_capture(jt.scene);
    S.ubo[DM_GAME_TFX_VIEW_STAGE][DM_GAME_TFX_VIEW_SLOT] = bS; up_tfx_capture(jt.scene);
    S.ubo[DM_GAME_TFX_VIEW_STAGE][DM_GAME_TFX_VIEW_SLOT] = bA; up_tfx_capture(jt.scene);
    int on = g_tfx_jit_frame == frame_no;
    tj[0] = on ? g_tfx_jit[0] : 0; tj[1] = on ? g_tfx_jit[1] : 0;
    double P[16], V[16], vp[16]; cam_pv(yaw, 0, P, V); cam_vp(yaw, 0, vp);
    float dx = 2.0f * (float)tj[0] / IW, dy = -2.0f * (float)tj[1] / IH;
    jt.checked++;
    jt.bad_a += jt_rows((float *)(view_mem + 0x1000), P, DM_GAME_TFX_JIT_P, dx, dy, 1e-6f) + jt_rows((float *)(view_mem + 0x1000), vp, DM_GAME_TFX_VIEW_VP, dx, dy, 1e-5f);
    jt.bad_b += jt_rows((float *)(view_mem + 0x5000), P, DM_GAME_TFX_JIT_P, dx, dy, 1e-6f) + jt_rows((float *)(view_mem + 0x5000), vp, DM_GAME_TFX_VIEW_VP, dx, dy, 1e-5f);
    jt.bad_other += memcmp(view_mem + 0x9000, shadow0, sizeof shadow0) != 0 || memcmp(view_mem + 0x1000 + DM_GAME_TFX_VIEW_PREV, prev0, 64) != 0 || memcmp(view_mem + 0x1000 + DM_GAME_TFX_JIT_VIEW, view0, 48) != 0;
    if (on) { memcpy(keep, view_mem + 0x1000, sizeof keep); cam_frame(yaw, 0, pyaw, 0, tex_mtl(jt.ccol), tex_mtl(jt.sdep), jt.cpx); memcpy(view_mem + 0x1000, keep, sizeof keep); }   // the picture with that jitter; A as the host left it
    memcpy(jt.last_vp, view_mem + 0x1000 + DM_GAME_TFX_VIEW_VP, 64); jt.have_last = 1;   // what the next frame's previous set copies
    up_tfx_capture(jt.pr);
    mtl_sub_begin(); CHECK(up_mfx_encode(jt.up), "a jittered frame is drawn"); CHECK(mtl_wait(mtl_sub_commit(), 5000000000ull) && !mtl_last_commit_error(), "the jittered frame completes");
    jt.cuts += tfx_state_at(g_tfx_mot_frame)->cut != 0;
    return on;
}
// The sharpen kernel on its own (tfx_sharpen), outside the replay: src (RGBA16F, w x h, rgb = v[]) sharpened at strength st, the result's red channel; the GPU time in ms
static float *sharpen_run(const float *v, int w, int h, float st, double *ms, MTLPixelFormat outf) {   // outf: the destination's format (RGBA16F read back; others only timed)
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:w height:h mipmapped:NO];
    td.storageMode = MTLStorageModePrivate; td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> a = [g_dev newTextureWithDescriptor:td]; td.pixelFormat = outf; id<MTLTexture> b = [g_dev newTextureWithDescriptor:td];
    __fp16 *px = malloc((size_t)w * h * 8); for (int i = 0; i < w * h; i++) { px[4 * i] = px[4 * i + 1] = px[4 * i + 2] = (__fp16)v[i]; px[4 * i + 3] = 1; }
    upload(a, px, 8); free(px);
    struct { uint32_t w, h; float s; uint32_t ox, oy; } pm = {(uint32_t)w, (uint32_t)h, st, 0, 0};
    double best = 1e9;
    for (int r = 0; r < (ms ? 20 : 1); r++) {
        id<MTLCommandBuffer> cb = q_cb(); id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
        [e setComputePipelineState:g_tfx_sharp_ps]; [e setTexture:a atIndex:0]; [e setTexture:b atIndex:1]; [e setBytes:&pm length:sizeof pm atIndex:0];
        [e dispatchThreadgroups:MTLSizeMake((w + 15) / 16, (h + 7) / 8, 1) threadsPerThreadgroup:MTLSizeMake(16, 8, 1)]; [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
        if (r >= 2) best = fmin(best, (cb.GPUEndTime - cb.GPUStartTime) * 1e3);   // after two to warm up; the least is the pass, without the command buffer's own overhead
    }
    if (ms) *ms = best;
    if (outf != MTLPixelFormatRGBA16Float) return NULL;
    float *o = readback(b), *out = malloc((size_t)w * h * 4); for (int i = 0; i < w * h; i++) out[i] = o[4 * i]; free(o);
    return out;
}
// A mipmapped texture's sample through the host's sampler for that registration (samp_by_id), at the level of detail lod (explicit gradients; nearest mip filter): mip 0 reads 0,
// mip 1 reads 1, so the level the bias moves it to shows
static float mip_sample(int sid, float lod) {
    static id<MTLComputePipelineState> ps; static id<MTLTexture> t;
    if (!ps) {
        NSError *e = nil; id<MTLLibrary> lib = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nkernel void k(texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], device float *o [[buffer(0)]], constant float &g [[buffer(1)]]) { o[0] = t.sample(s, float2(0.5), gradient2d(float2(g, 0), float2(0, g))).r; }" options:nil error:&e];
        ps = [g_dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k"] error:&e];
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float width:64 height:64 mipmapped:YES]; td.storageMode = MTLStorageModeShared;
        t = [g_dev newTextureWithDescriptor:td];
        for (NSUInteger l = 0; l < t.mipmapLevelCount; l++) { NSUInteger w = MAX(64 >> l, 1); float *v = malloc(w * w * 4); for (NSUInteger i = 0; i < w * w; i++) v[i] = l ? 1 : 0;
            [t replaceRegion:MTLRegionMake2D(0, 0, w, w) mipmapLevel:l withBytes:v bytesPerRow:w * 4]; free(v); }
    }
    os_unfair_lock_lock(&g_rmu); id<MTLSamplerState> smp = samp_by_id(sid); os_unfair_lock_unlock(&g_rmu);
    id<MTLBuffer> o = [g_dev newBufferWithLength:4 options:MTLResourceStorageModeShared]; float g = exp2f(lod) / 64.0f;
    id<MTLCommandBuffer> cb = q_cb(); id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
    [e setComputePipelineState:ps]; [e setTexture:t atIndex:0]; [e setSamplerState:smp atIndex:0]; [e setBuffer:o offset:0 atIndex:0]; [e setBytes:&g length:4 atIndex:1];
    [e dispatchThreads:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)]; [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    return *(float *)o.contents;
}
static double truth_error_at(const float *o, double yaw, int ow, int oh) {   // as truth_error, for an output of ow x oh at the origin of the 1920x1080 image
    double e = 0; int n = 0;
    for (int y = oh / 4; y < oh * 3 / 4; y++) for (int x = ow / 4; x < ow * 3 / 4; x++) {
        double w[3]; if (!cam_hit(yaw, 0, (x + 0.5) * IW / ow, (y + 0.5) * IH / oh, w)) continue;
        e += fabs(o[4 * (y * OW + x)] - pan_at(w[0] / PS, w[1] / PS)); n++;
    }
    return n ? e / n : 1;
}
// The reactive mask's kernel (tfx_mask) on its own at w x h with the glow term on: its GPU time in ms, the least of 18 runs
static double mask_time(int w, int h, MTLPixelFormat scene) {   // scene: the scene colour's format (and its snapshot's): Ocarina of Time's is RG11B10F
    up_tfx_mask_ready((NSUInteger)w, (NSUInteger)h);
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:scene width:w height:h mipmapped:NO]; td.storageMode = MTLStorageModePrivate;
    td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> now = [g_dev newTextureWithDescriptor:td], before = [g_dev newTextureWithDescriptor:td];
    td.pixelFormat = MTLPixelFormatRG16Float; id<MTLTexture> mv = [g_dev newTextureWithDescriptor:td];
    td.pixelFormat = MTLPixelFormatR8Unorm; id<MTLTexture> out = [g_dev newTextureWithDescriptor:td], prev = [g_dev newTextureWithDescriptor:td], raw = [g_dev newTextureWithDescriptor:td];
    td.pixelFormat = MTLPixelFormatRGBA16Float; td.width = 240; td.height = 135; id<MTLTexture> gl = [g_dev newTextureWithDescriptor:td], gl0 = [g_dev newTextureWithDescriptor:td];
    id<MTLBuffer> cnt = [g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared];
    id<MTLBuffer> lum = [g_dev newBufferWithLength:64 options:MTLResourceStorageModeShared]; ((float *)lum.contents)[0] = 0.5f; ((float *)lum.contents)[1] = 0.5f;   // the input's luminance, steady
    struct { uint32_t w, h, have, have_prev; float lo, hi, alo, ahi; uint32_t have_glow; float glo, ghi, gfloor; uint32_t have_lum, lum_now, lum_prev; float flo, fhi; } pm = {(uint32_t)w, (uint32_t)h, 1, 1,
        0.01f, 0.1f, 0.05f, 0.25f, 1, 0.02f, 0.15f, 0.05f, 1, 1, 0, 0.04f, 0.1f};   // tfx_mparams
    const char *probe = getenv("T_MASK_PROBE"); if (probe) { pm.have = probe[0] == '1'; pm.have_glow = probe[1] == '1'; }   // a cost breakdown by hand: the scene term, the glow term
    double best = 1e9;
    for (int r = 0; r < 100; r++) {   // the least of 98: another app's GPU work (a game running beside the test) lands in most of them
        id<MTLCommandBuffer> cb = q_cb(); id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
        [e setComputePipelineState:g_tfx_mask_ps]; [e setBytes:&pm length:sizeof pm atIndex:0]; [e setBuffer:cnt offset:0 atIndex:1]; [e setBuffer:lum offset:0 atIndex:2];
        [e setTexture:now atIndex:0]; [e setTexture:before atIndex:1]; [e setTexture:out atIndex:2]; [e setTexture:prev atIndex:3]; [e setTexture:gl atIndex:4]; [e setTexture:gl0 atIndex:5]; [e setTexture:raw atIndex:6]; (void)mv;
        [e dispatchThreadgroups:MTLSizeMake((w + 15) / 16, (h + 15) / 16, 1) threadsPerThreadgroup:MTLSizeMake(16, 16, 1)]; [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
        if (r >= 2) best = fmin(best, (cb.GPUEndTime - cb.GPUStartTime) * 1e3);
    }
    return best;
}
// DM_NVN_TSV's rows (mtl_tfx_rows) as a test collects them: one frame's at a time
static struct { char name[32]; double v; } g_rows[32]; static int g_rows_n;
static void row_take(uint64_t f, const char *name, double v) { (void)f; if (g_rows_n < 32) { snprintf(g_rows[g_rows_n].name, 32, "%s", name); g_rows[g_rows_n++].v = v; } }
static double row_get(const char *name) { for (int i = 0; i < g_rows_n; i++) if (!strcmp(g_rows[i].name, name)) return g_rows[i].v; return -1; }
// The output against the true picture at the output's resolution (the plane sampled at each output texel's centre): the mean absolute error over the middle half
static double truth_error(const float *o, double yaw, double cx) {
    double e = 0; int n = 0;
    for (int y = OH / 4; y < OH * 3 / 4; y++) for (int x = OW / 4; x < OW * 3 / 4; x++) {
        double w[3]; if (!cam_hit(yaw, cx, (x + 0.5) / 2, (y + 0.5) / 2, w)) continue;
        e += fabs(o[4 * (y * OW + x)] - pan_at(w[0] / PS, w[1] / PS)); n++;
    }
    return n ? e / n : 1;
}
int main(void) { @autoreleasepool {
    setenv("DM_UPSCALER", "metalfx-temporal", 1);
    mtl_init();
    g_tfx_sharpen = 0;   // the sections before the sharpen's own without it, so their measures stay those of MetalFX alone
    // 0. Costs, measured first, with the GPU not yet busy from the sections below (measured after them, the mask's ranged 0.14-0.24 ms from run to run)
    if (up_tfx_sharpen_ready()) {
        float *big = malloc((size_t)3840 * 2160 * 4); for (int i = 0; i < 3840 * 2160; i++) big[i] = (float)((i * 2654435761u) >> 24) / 255.0f;
        // Its cost where it replaces the draw back (into the game's RG11B10F output, as in Ocarina of Time): against the same kernel at strength 0, a plain copy with the same traffic.
        // The least of 18 runs each; both bound by the memory traffic (RGBA16F read, RG11B10F written at 3840x2160: 100 MB)
        double ms = 0, ms0 = 0; sharpen_run(big, 3840, 2160, 0, &ms0, MTLPixelFormatRG11B10Float); sharpen_run(big, 3840, 2160, 0.8f, &ms, MTLPixelFormatRG11B10Float); free(big);
        printf("  sharpen at 3840x2160 into RG11B10F: %.3f ms, the same pass as a plain copy %.3f ms: %.3f ms more\n", ms, ms0, ms - ms0);
        if (!rec_on() && !getenv("MTL_DEBUG_LAYER")) CHECK(ms - ms0 < 0.3, "the sharpen costs under 0.3 ms at 3840x2160 over the copy it replaces");   // timed with the encoding thread off (see the mask's)
        { double mt = 1e9, m16 = mask_time(2880, 1620, MTLPixelFormatRGBA16Float);
          for (int k = 0; k < 3 && mt > 0.2; k++) mt = fmin(mt, mask_time(2880, 1620, MTLPixelFormatRG11B10Float));   // up to 3 batches: other GPU work on the machine (a game run) spikes single ones
          printf("  reactive mask at 2880x1620 (tiled, with the glow): %.3f ms with an RG11B10F scene colour (Ocarina of Time's), %.3f ms with RGBA16F\n", mt, m16);
          // 0.14-0.19 ms measured on the Mac it was written on (the earlier 50-read kernel: 0.49 ms in the same harness, 0.43 ms in a game run); bounded with room for run-to-run noise
          // checked with the encoding thread off and no Metal debug layer only: with the thread on, the host's own GPU work runs beside the timing (0.35 ms measured then); the layer's checks slow it
          if (!rec_on() && !getenv("MTL_DEBUG_LAYER")) CHECK(mt < 0.3, "the reactive mask costs about 0.2 ms at 2880x1620 with Ocarina of Time's RG11B10F scene colour (the earlier kernel 0.49; 0.17-0.25 with a game running beside the test)"); }
    }
    NvShader *up = upscaler();
    if (!DM_GAME_UPSCALER_N) up->up_mfx = 1;   // a profile without upscalers names none: the dispatch path is the same
    CHECK(up_mfx_wanted(up), "the named shader is swapped with DM_UPSCALER=metalfx-temporal");
    if (!g_up_tfx) { printf("t_upscaler_tfx: this GPU has no Metal 4 temporal scaler; nothing more to check\n"); return failed != 0; }
    tex_t col = texture(901, IW, IH, NVN_FORMAT_RGBA16F), out = texture(902, OW, OH, NVN_FORMAT_RGBA16F), dep = texture(903, IW, IH, NVN_FORMAT_DEPTH32F), mot = texture(904, IW, IH, NVN_FORMAT_RG16F);
    mtl_tex_init(&col); mtl_tex_init(&out); mtl_tex_init(&dep); mtl_tex_init(&mot);
    mtl_reg_tex(901, &col, NULL); mtl_reg_image(902, &out, NULL);
    memset(&S, 0, sizeof S); S.tex[5][0] = 901; S.img[5][1] = 902; rects(IW, IH);
    os_unfair_lock_lock(&g_rmu); id<MTLTexture> written = tex_by_id(902); os_unfair_lock_unlock(&g_rmu);
    clear(tex_mtl(&dep), MTLClearColorMake(0, 0, 0, 0), 1, 0.5); clear(tex_mtl(&mot), MTLClearColorMake(0, 0, 0, 0), 0, 0);
    __fp16 *cpx = malloc((size_t)IW * IH * 8), *mpx = malloc((size_t)IW * IH * 4);
    // 1. No resolver (under a profile with tfx_compose: its resolver, with no compose draw this frame): the spatial scaler draws
    clear(tex_mtl(&col), MTLClearColorMake(0.5, 0.25, 0.75, 1), 0, 0); clear(written, MTLClearColorMake(0, 0, 0, 1), 0, 0);
    uint64_t n0, sp0, rs0; mtl_up_tfx_stats(&n0, &sp0, &rs0);
    CHECK(frame(up), "without a resolver the dispatch is still drawn");
    uint64_t n, sp, rs; mtl_up_tfx_stats(&n, &sp, &rs);
    CHECK(n == n0 && sp == sp0 + 1, "without a resolver the spatial scaler draws it");
    { float *f = readback(written); CHECK(fabs(mean_r(f, OW / 4, OH / 4, OW / 2, OH / 2, OW) - 0.5) < 0.02, "the spatial scaler filled the image"); free(f); }
    // 2. A static scene converges
    g_up_tfx_resolve = resolve; r_dep = tex_mtl(&dep); r_mot = tex_mtl(&mot);
    scene(cpx, mpx, IW / 2 - SQ / 2, 0); upload(tex_mtl(&col), cpx, 8); upload(tex_mtl(&mot), mpx, 4);
    float *prev = NULL; double change = 1e9; int drawn = 0;
    for (int f = 0; f < 16; f++) {
        drawn += frame(up);
        float *cur = readback(written);
        if (prev) { double d = 0; for (NSUInteger i = 0; i < (NSUInteger)OW * OH; i++) d += fabsf(cur[4 * i] - prev[4 * i]); change = d / ((double)OW * OH); free(prev); }
        prev = cur;
    }
    mtl_up_tfx_stats(&n, &sp, &rs);
    CHECK(drawn == 16 && n == n0 + 16 && sp == sp0 + 1, "with depth and motion the temporal scaler draws every frame");
    CHECK(change < 0.002, "a static scene converges: the last two outputs differ by under 0.002 on average");
    { double in_bg = 0.125, out_bg = mean_r(prev, 0, 0, OW, OH / 4, OW), out_sq = mean_r(prev, OW / 2 - SQ + 8, OH / 2 - SQ + 8, 2 * SQ - 16, 2 * SQ - 16, OW);
      printf("  static: background %.4f (input mean %.4f), square %.4f, last change %.5f\n", out_bg, in_bg, out_sq, change);
      CHECK(fabs(out_bg - in_bg) < 0.01 && fabs(out_sq - 1.0) < 0.03, "the converged output keeps the input's levels"); }
    free(prev);
    // 3. A moving object: the square moves STEP input pixels a frame; the output keeps it where the input has it and leaves no trail. This holds with wrong motion vectors too
    // (zero, or the other sign: MetalFX rejects history this far from the current colour), so it shows the history follows the scene, not that the vectors are read right: see 3b
    int sx = 100; for (int f = 0; f < 24; f++, sx += STEP) {
        scene(cpx, mpx, sx, f > 0); upload(tex_mtl(&col), cpx, 8); upload(tex_mtl(&mot), mpx, 4);
        CHECK(frame(up), "a moving frame is drawn");
    }
    sx -= STEP;   // where the last frame's square was
    { float *f = readback(written); double sw = 0, sxw = 0;
      for (int y = OH / 2 - SQ + 8; y < OH / 2 + SQ - 8; y++) for (int x = 0; x < OW; x++) { float v = f[4 * (y * OW + x)]; if (v > 0.55f) { sw += v; sxw += v * (x + 0.5); } }
      double centre = sw ? sxw / sw : -1, want = 2.0 * (sx + SQ / 2.0), left = mean_r(f, (NSUInteger)(2 * (sx - 4 * STEP)), OH / 2 - SQ + 8, 2 * 2 * STEP, 2 * SQ - 16, OW);
      printf("  moving: square centre %.1f in the output, %.1f expected; where it was 4 frames before: %.3f (background about 0.125)\n", centre, want, left);
      CHECK(fabs(centre - want) <= 3, "the output's square is where the input's is (within 3 output pixels)");
      CHECK(left < 0.3, "the place the square left is background again (no trail)");
      free(f); }
    // 3b. The motion vectors read right: a pan of a fine low-contrast pattern (see pan) with its vectors converges on the current frame; with wrong vectors (a build with
    // T_MV_SIGN 0 or -1) the history it keeps is the pattern elsewhere
    r_reset = 1; double perr = 0;
    for (int f = 0; f < 24; f++) {
        pan(cpx, mpx, PAN * f, f > 0); upload(tex_mtl(&col), cpx, 8); upload(tex_mtl(&mot), mpx, 4);
        CHECK(frame(up), "a pan frame is drawn");
        if (f >= 16) { float *o = readback(written); perr += pan_error(o, cpx) / 8; free(o); }
    }
    printf("  pan: mean error against the current frame over the last 8 frames %.4f (pattern amplitude 0.08)\n", perr);
    const double exact_pan_error = perr;
    // Measured on an M-series Mac: 0.0044 with the right vectors, 0.032 with none and 0.031 with the other sign
    CHECK(perr < 0.012, "a pan with its motion vectors converges on the current frame (wrong vectors leave three times the error and more)");
    // 4. Square-rooted input (Ocarina of Time's networks) comes out squared
    up->up_color = UP_COLOR_ROOT; clear(tex_mtl(&col), MTLClearColorMake(0.5, 0.5, 0.5, 1), 0, 0); clear(tex_mtl(&mot), MTLClearColorMake(0, 0, 0, 0), 0, 0); r_reset = 1;
    for (int f = 0; f < 4; f++) CHECK(frame(up), "a square-rooted frame is drawn");
    { float *f = readback(written); double m = mean_r(f, OW / 4, OH / 4, OW / 2, OH / 2, OW); printf("  square-rooted 0.5: %.4f\n", m); CHECK(fabs(m - 0.25) < 0.01, "square-rooted input comes out squared"); free(f); }
    up->up_color = UP_COLOR_LINEAR;
    // 5. A smaller content in the same textures (a dynamic resolution) keeps the scaler and fills the image
    const void *sc_before = NULL; for (int i = 0; i < UP_TFX_SCALERS; i++) if (g_up_tfx_sc[i].sc) sc_before = (__bridge void *)g_up_tfx_sc[i].sc;
    clear(tex_mtl(&col), MTLClearColorMake(0.3, 0.6, 0.9, 1), 0, 0); rects(864, 486); r_reset = 1;
    for (int f = 0; f < 4; f++) CHECK(frame(up), "a smaller content is drawn");
    const void *sc_after = NULL; int scalers = 0; for (int i = 0; i < UP_TFX_SCALERS; i++) if (g_up_tfx_sc[i].sc) { sc_after = (__bridge void *)g_up_tfx_sc[i].sc; scalers++; }
    CHECK(scalers == 1 && sc_after == sc_before, "a smaller content in the same textures keeps the scaler");
    { float *f = readback(written); double m = mean_r(f, OW / 4, OH / 4, OW / 2, OH / 2, OW); CHECK(fabs(m - 0.3) < 0.02, "the smaller content fills the whole image"); free(f); }
    rects(IW, IH);
    // 6. A frame with no evaluation restarts the history; consecutive frames do not
    mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a frame after the last"); mtl_up_tfx_stats(&n, &sp, &rs); CHECK(rs == rs0, "consecutive frames keep the history");
    frame_no += 3; CHECK(frame(up), "a frame after a gap"); mtl_up_tfx_stats(&n, &sp, &rs); CHECK(rs == rs0 + 1, "a frame after frames with no evaluation restarts the history");
    // 6b. The resolver's own colour in place of the dispatch's (Ocarina of Time: the compose's output before SMAA), in another format (RG11B10F, linear)
    tex_t pre = texture(906, IW, IH, NVN_FORMAT_R11G11B10F); mtl_tex_init(&pre); clear(tex_mtl(&pre), MTLClearColorMake(0.75, 0.375, 0.125, 1), 0, 0);
    up->up_color = UP_COLOR_ROOT; r_col = tex_mtl(&pre); r_reset = 1;   // the dispatch's colour square-rooted; the resolver's is linear, so not squared
    for (int f = 0; f < 4; f++) CHECK(frame(up), "a frame with the resolver's colour is drawn");
    { float *f = readback(written); double m = mean_r(f, OW / 4, OH / 4, OW / 2, OH / 2, OW); printf("  resolver's colour 0.75: %.4f\n", m); CHECK(fabs(m - 0.75) < 0.02, "the resolver's linear colour is taken, not the dispatch's, and not squared"); free(f); }
    r_col = nil; up->up_color = UP_COLOR_LINEAR;
    // 7. Depth smaller than the colour's rectangle: the spatial scaler draws
    tex_t small = texture(905, 480, 270, NVN_FORMAT_DEPTH32F); mtl_tex_init(&small); r_dep = tex_mtl(&small);
    mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a dispatch with a too small depth is drawn"); mtl_up_tfx_stats(&n, &sp, &rs);
    CHECK(n == n0 && sp == sp0 + 1, "depth smaller than the colour: the spatial scaler draws");
    // 8. The profile's resolver (tfx_compose): the compose draw's colour and depth targets, taken at that draw each frame; motion only with DM_UPSCALER_TFX_MOTION=zero for now
    if (g_tfx_has_compose) {
        tex_t comp = texture(907, IW, IH, NVN_FORMAT_R11G11B10F), comp2 = texture(908, 864, 486, NVN_FORMAT_R11G11B10F);
        mtl_tex_init(&comp); mtl_tex_init(&comp2); clear(tex_mtl(&comp), MTLClearColorMake(0.6, 0.6, 0.6, 1), 0, 0); clear(tex_mtl(&comp2), MTLClearColorMake(0.4, 0.4, 0.4, 1), 0, 0);
        // the dispatch reads the compose's colour target, as Ocarina of Time's network does (its pass dumps), square-rooted: what comes out is that squared
        mtl_reg_tex(907, &comp, NULL); mtl_reg_tex(908, &comp2, NULL); S.tex[5][0] = 907;
        R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = &comp; R.rt.depth = &dep;
        NvProg *pr = [NvProg new]; pr->sh[0] = [NvShader new]; pr->sh[1] = [NvShader new];
        snprintf(pr->sh[0]->key, sizeof pr->sh[0]->key, "%.16s_v", g_tfx_compose);
        snprintf(pr->sh[1]->key, sizeof pr->sh[1]->key, "%.16s_f", g_tfx_compose + sizeof g_tfx_compose - 17);   // the last fragment shader named (Ocarina of Time: the HDR compose's)
        NvProg *other = [NvProg new]; other->sh[0] = pr->sh[0]; other->sh[1] = [NvShader new]; snprintf(other->sh[1]->key, sizeof other->sh[1]->key, "0123456789abcdef_f");
        g_up_tfx_resolve = up_tfx_resolve_none; g_tfx_motion = 0; up->up_color = UP_COLOR_ROOT;
        mtl_up_tfx_stats(&n0, &sp0, &rs0); compose_draw = other; CHECK(frame(up), "a frame whose draws hold no compose draw");
        mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 && sp == sp0 + 1 && g_up_tfx_resolve == up_tfx_resolve_profile, "a profile with tfx_compose takes its resolver; no compose draw this frame: spatial");
        compose_draw = pr; CHECK(frame(up), "a frame with the compose draw, no motion");
        mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 && sp == sp0 + 2, "the compose found, but no motion vectors (no DM_UPSCALER_TFX_MOTION): spatial");
        CHECK(g_tfx_cap_color == tex_mtl(&comp) && g_tfx_cap_depth == tex_mtl(&dep), "the compose draw's colour target 0 and depth target are taken");
        { tex_t early = texture(912, IW, IH, NVN_FORMAT_R11G11B10F), early_d = texture(913, IW, IH, NVN_FORMAT_DEPTH32F); mtl_tex_init(&early); mtl_tex_init(&early_d);
          atomic_store(&g_cur_frame, ++frame_no);   // a frame whose compose shaders draw twice: an earlier draw into other targets, then the compose before the upscaler
          R.rt.color[0] = &early; R.rt.depth = &early_d; up_tfx_capture(pr); R.rt.color[0] = &comp; R.rt.depth = &dep; up_tfx_capture(pr);
          CHECK(g_tfx_cap_color == tex_mtl(&comp) && g_tfx_cap_depth == tex_mtl(&dep) && g_tfx_depth_serial == dep.serial, "of two draws with the compose's shaders in a frame, the last before the upscaler is taken"); }
        g_tfx_motion = 1;
        for (int f = 0; f < 4; f++) CHECK(frame(up), "a frame with the compose draw and zero motion");
        mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 + 4 && sp == sp0 + 2, "DM_UPSCALER_TFX_MOTION=zero: the temporal scaler draws, with the compose's depth");
        { float *f = readback(written); double m = mean_r(f, OW / 4, OH / 4, OW / 2, OH / 2, OW); printf("  the dispatch's square-rooted 0.6: %.4f\n", m);
          CHECK(fabs(m - 0.36) < 0.02, "the output is the dispatch's input (the compose's target) squared, as the spatial scaler takes it"); free(f); }
        CHECK(g_tfx_zero_mot && g_tfx_zero_mot.width == IW && g_tfx_zero_mot.height == IH && g_tfx_zero_mot.pixelFormat == MTLPixelFormatRG16Float, "the zero motion is RG16Float at the depth's size");
        compose_draw = nil; CHECK(frame(up), "a frame after one with the compose, without it");
        mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(sp0 == sp + 1, "last frame's compose is not this frame's: spatial");
        R.rt.color[0] = &comp2; compose_draw = pr; mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a frame whose compose draws into another texture than the upscaler reads");
        mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 && sp == sp0 + 1, "the compose hint's draw wrote another texture than the upscaler reads, which no draw wrote: spatial");
        S.tex[5][0] = 908; rects(864, 486); mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a frame with a compose of another size, the input that size");
        mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 + 1 && rs == rs0 + 1, "a compose of another size restarts the history"); rects(IW, IH);
        // The compose found by structure: a draw with shaders tfx_compose does not name (Zora's Domain's fog compose) that writes the texture the upscaler reads is taken; with the
        // hint's draw in the same frame into another texture, the structural one wins
        { NvProg *fog = [NvProg new]; fog->sh[0] = pr->sh[0]; fog->sh[1] = [NvShader new]; snprintf(fog->sh[1]->key, sizeof fog->sh[1]->key, "9e09b406de439a34");
          S.tex[5][0] = 907; R.rt.color[0] = &comp; compose_draw = fog; mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a frame whose compose has shaders tfx_compose does not name");
          mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 + 1 && sp == sp0 && g_tfx_cap_color == tex_mtl(&comp) && g_tfx_cap_depth == tex_mtl(&dep),
                                                "a compose whose shaders tfx_compose does not name is found by the texture it wrote, which the upscaler reads (temporal)");
          tex_t dep2 = texture(916, IW, IH, NVN_FORMAT_DEPTH32F); mtl_tex_init(&dep2);
          extra_draw = pr; extra_color = &comp2; extra_depth = &dep2;   // the hint's shaders, drawn after it into another target
          mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a frame with the fog compose, then the hint's shaders into another target");
          mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 + 1 && g_tfx_cap_color == tex_mtl(&comp) && g_tfx_cap_depth == tex_mtl(&dep), "the draw that wrote the upscaler's input wins over the hint's");
          extra_draw = nil; compose_draw = pr;
          // The network as Ocarina of Time runs it: its first stage reads the compose's target, and the dispatch MetalFX replaces reads what the earlier stages wrote by compute
          // (no draw wrote it). The compose is the draw that wrote the first stage's input, with shaders the hint does not name; the colour stays the replaced dispatch's input
          tex_t mid = texture(917, IW, IH, NVN_FORMAT_RGBA16F); mtl_tex_init(&mid); mtl_reg_tex(917, &mid, NULL); clear(tex_mtl(&mid), MTLClearColorMake(0.5, 0.5, 0.5, 1), 0, 0);
          stage1 = [NvShader new]; stage1->rf.nb = 1; stage1->rf.b[0] = (nvn_rbind){.kind = NVN_RB_TEX, .dtt = MTLTextureType2D, .dpf = NVN_DPF_FLOAT, .reg = 3}; stage1_in = 907; up_in = 917;
          compose_draw = fog; mtl_up_tfx_stats(&n0, &sp0, &rs0); for (int f = 0; f < 3; f++) CHECK(frame(up), "a frame of the network's chain");
          mtl_up_tfx_stats(&n, &sp, &rs);
          CHECK(n == n0 + 3 && sp == sp0 && g_tfx_cap_color == tex_mtl(&comp) && g_tfx_cap_depth == tex_mtl(&dep),
                "the network's first stage reads the compose's target and the replaced dispatch a compute-written texture: the compose is found, temporal");
          { float *f = readback(written); double m = mean_r(f, OW / 4, OH / 4, OW / 2, OH / 2, OW); free(f);
            CHECK(fabs(m - 0.25) < 0.02, "the colour is the replaced dispatch's own input (square-rooted 0.5, squared), not the compose's"); }
          compose_draw = pr; mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a frame of the chain with the hint's shaders"); mtl_up_tfx_stats(&n, &sp, &rs);
          CHECK(n == n0 + 1, "with the hint's shaders writing the first stage's input: temporal");
          // a later stage reads another drawn texture (Ocarina of Time's a335c1db reads an RGBA8 one): the first stage's input stays the compose's
          tex_t dep3 = texture(918, IW, IH, NVN_FORMAT_DEPTH32F); mtl_tex_init(&dep3); extra_draw = fog; extra_color = &comp2; extra_depth = &dep3; stage2_in = 908;
          mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a frame whose later stage reads another drawn texture"); mtl_up_tfx_stats(&n, &sp, &rs);
          CHECK(n == n0 + 1 && g_tfx_cap_color == tex_mtl(&comp) && g_tfx_cap_depth == tex_mtl(&dep), "the earliest stage's drawn input is the compose, not a later stage's");
          extra_draw = nil; stage2_in = 0;
          stage1_in = 908; mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a frame whose first stage reads a texture the compose did not write"); mtl_up_tfx_stats(&n, &sp, &rs);
          CHECK(n == n0 + 1 && g_tfx_cap_color == tex_mtl(&comp), "no dispatch of the frame read a drawn texture: the hint's draw is taken (temporal)");
          stage1 = nil; S.tex[5][0] = 907; S.tex[5][3] = 0; }
        // 9. Camera motion (tfx_view): from the compose's depth and the view buffer the scene draws bind, against a synthetic camera over a plane computed in doubles
        if (g_tfx_view_size) {
            view_mem = mmap(NULL, 0x10000, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0); CHECK(view_mem != MAP_FAILED, "guest memory for the view buffer");
            mtl_pool_add(view_mem, 0x10000);
            tex_t sdep = texture(909, IW, IH, NVN_FORMAT_DEPTH32F), scol = texture(910, IW, IH, NVN_FORMAT_R11G11B10F), ccol = texture(911, IW, IH, NVN_FORMAT_RGBA16F),
                  sdep2 = texture(914, IW, IH, NVN_FORMAT_DEPTH32F), dcopy = texture(915, IW, IH, NVN_FORMAT_DEPTH32F);
            mtl_tex_init(&sdep); mtl_tex_init(&scol); mtl_tex_init(&ccol); mtl_tex_init(&sdep2); mtl_tex_init(&dcopy);
            mtl_reg_tex(911, &ccol, NULL); S.tex[5][0] = 911;   // the picture is also what the dispatch reads (its colour: the temporal and the spatial scaler take it)
            NvProg *scene = [NvProg new]; scene->sh[0] = other->sh[0]; scene->sh[1] = other->sh[1];   // a scene draw: not the compose
            S.ubo[DM_GAME_TFX_VIEW_STAGE][DM_GAME_TFX_VIEW_SLOT] = (p_bind_buf){.addr = (uint64_t)view_mem + 0x1000, .size = (uint64_t)g_tfx_view_size};
            scene_draw = scene; compose_draw = pr; scene_depth = &sdep; scene_color = &scol; compose_color = &ccol;
            g_tfx_jitter = 0;   // sections 9 and 10 without the camera's jitter (11 has it)
            g_tfx_motion = -1; unsetenv("DM_UPSCALER_TFX_MOTION"); unsetenv("DM_UPSCALER_TFX_EXPOSURE"); g_tfx_exposure = -1; r_reset = 0; g_tfx_depth_serial = 0; g_tfx_depth_w = g_tfx_depth_h = 0;   /* as at the start: no compose seen */ g_tfx_view_frame = 0; up->up_color = UP_COLOR_LINEAR;
            const double step = atan(3.0 / ((1 / tan(M_PI / 6)) * IH / IW * IW / 2));   // a yaw step that moves the centre 3 input pixels
            double yaw = 0, cx = 0; float c[2];
            cam_frame(yaw, cx, yaw, cx, tex_mtl(&ccol), tex_mtl(&sdep), cpx);
            mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "the first frame (no view buffer known: its depth target is known from the compose)");
            mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 && sp == sp0 + 1, "the first frame: no camera yet, spatial");
            // A turn: the motion does not depend on the depth
            // (its depth a new texture every other frame, of the same size, as Ocarina of Time's allocator gives it in some runs: the camera is found by the depth's size)
            for (int f = 0; f < 6; f++) { double py = yaw; yaw += step; scene_depth = f & 1 ? &sdep2 : &sdep; cam_frame(yaw, cx, py, cx, tex_mtl(&ccol), tex_mtl(scene_depth), cpx); CHECK(frame(up), "a turning frame");
                if (f >= 1) { double err = cam_motion_error(g_tfx_mot, yaw, cx, py, cx, c); if (f == 5) printf("  turn: largest motion error %.4f px, centre %.4f,%.4f (closed form %.4f,0)\n", err, c[0], c[1], 3.0);
                    CHECK(err < 0.1, "a turn's camera motion matches the reference within 0.1 px (or 0.2 %)"); } }
            CHECK(fabs(c[0] - 3.0) < 0.02 && fabs(c[1]) < 0.02, "the centre moves by f tan(step) = 3 px, to the right where it was (MetalFX's sign)");
            scene_depth = &sdep;
            #define st tfx_state_at(g_tfx_mot_frame)   // the last motion pass's slot of the state ring, read anew each time
            CHECK(st->prev_src == 1 && st->game_matches == 1, "the host's copy of the frame before is used, and the game's previous view-projection matches it");
            mtl_up_tfx_stats(&n, &sp, &rs); CHECK(n == n0 + 6 && sp == sp0 + 1, "with the camera, the temporal scaler draws every turning frame");
            // A sideways move: the motion depends on the depth (parallax)
            for (int f = 0; f < 3; f++) { double px_ = cx; cx += 0.05; cam_frame(yaw, cx, yaw, px_, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "a moving frame");
                double err = cam_motion_error(g_tfx_mot, yaw, cx, yaw, px_, c); if (f == 2) printf("  move: largest motion error %.4f px, centre %.4f,%.4f\n", err, c[0], c[1]);
                CHECK(err < 0.1, "a sideways move's camera motion (from the depth) matches the reference within 0.1 px"); }
            // The game's previous set not the frame before's (as on a cut, when the game restarts its history): taken as a cut
            { double py = yaw; yaw += step; cam_frame(yaw, cx, py, cx, tex_mtl(&ccol), tex_mtl(&sdep), cpx);
              float *v = (float *)(view_mem + 0x1000); for (int i = 0; i < 16; i++) v[DM_GAME_TFX_VIEW_PREV / 4 + i] *= 1.5f;
              CHECK(frame(up), "a frame whose game previous set is wrong");
              double err = cam_motion_error(g_tfx_mot, yaw, cx, py, cx, c);
              (void)err; CHECK(st->prev_src == 1 && st->game_matches == 0 && st->cut == 1 && c[0] >= 2 * IW - 1, "a previous set that is not the frame before: a camera cut (the game restarts its history), every vector off the screen"); }
            // and the frame after, with the game's set right again, is no cut
            { double py = yaw; yaw += step; cam_frame(yaw, cx, py, cx, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "the frame after");
              double err = cam_motion_error(g_tfx_mot, yaw, cx, py, cx, c); CHECK(st->game_matches == 1 && st->cut == 0 && err < 0.1, "the frame after a mismatch: the sets match again, motion right"); }
            // The pan bar through the host's motion: a sideways move over the plane facing the camera shifts every texel by the same 3 input pixels (the pan above, with the vectors
            // now made from the depth and the view-projections)
            // With auto exposure, as the pan with exact vectors above (0.0044); then with the profile's fixed exposure 1, printed with a looser bound
            for (int fixed = 0; fixed < 2; fixed++) { yaw = 0; frame_no += 3; double perr = 0; g_tfx_exposure = fixed ? 1 : 0;
              for (int f = 0; f < 24; f++) { double px_ = cx; cx += 3 * PS; cam_frame(yaw, cx, yaw, px_, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "a panning frame");
                  if (f >= 16) { float *o = readback(written); perr += pan_error(o, cpx) / 8; free(o); } }
              printf("  camera pan (%s exposure): mean error against the current frame over the last 8 frames %.4f (the pan with exact vectors and auto exposure: 0.0044)\n", fixed ? "fixed 1" : "auto", perr);
              if (!fixed) CHECK(perr < exact_pan_error + 0.0006, "camera motion converges within 0.0006 of exact vectors on this GPU");
              else CHECK(perr < exact_pan_error + 0.0016, "fixed exposure converges within 0.0016 of exact vectors on this GPU"); }
            g_tfx_exposure = 1;
            // A turn, against the true picture at the output's resolution, after 24 frames from a fresh history: the host's motion, zero motion, the spatial scaler. A turn moves the
            // picture by fractions of a pixel that differ across it, so the output is a new sampling, not the input's: the true picture is the measure, not the current frame
            double terr[3];
            for (int mode = 0; mode < 3; mode++) {   // 0: camera motion, 1: zero motion, 2: spatial (no motion: the resolver finds none)
                g_tfx_motion = mode == 0 ? 2 : mode == 1 ? 1 : 0; frame_no += 3; double y0 = 0.1;
                for (int f = 0; f < 24; f++) { double py = y0; y0 += step; cam_frame(y0, 0, py, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "a turning frame against the truth"); }
                float *o = readback(written); terr[mode] = truth_error(o, y0, 0); free(o);
            }
            g_tfx_motion = 2;
            printf("  turning, against the true picture: camera motion %.4f, zero motion %.4f, spatial %.4f\n", terr[0], terr[1], terr[2]);
            CHECK(terr[0] < terr[1] * 0.8, "while turning, the host's motion is closer to the true picture than zero motion");
            CHECK(terr[0] <= terr[2] * 1.05, "while turning, the temporal scaler with the host's motion is no further from the true picture than the spatial scaler");
            CHECK(st->cut == 0, "a steady turn is no cut");
            // A cut: a turn of 40 degrees in one frame, after a converged turn. Found, every vector points off the screen, so no history is taken: the cut frame comes out as a frame
            // after a reset does (here a frame gap before it). With the cut rule off MetalFX's own rejection does about as well on a cut this large (all of the picture changes), so
            // that is printed, not checked: the rule is for cuts its rejection would not catch
            double cuterr[3];   // 0: cut rule off, 1: on, 2: a reset before the cut frame
            for (int run = 0; run < 3; run++) {
                g_tfx_cut_frac = run == 0 ? 1e9f : 0.25f; frame_no += 3; double y0 = 0.2;
                for (int f = 0; f < 16; f++) { double py = y0; y0 += step; cam_frame(y0, 0, py, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "a turning frame before the cut"); }
                double py = y0; y0 += 40 * M_PI / 180; cam_frame(y0, 0, py, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx);
                if (run == 2) frame_no += 3;   // a gap: the scaler resets
                CHECK(frame(up), "the cut frame");
                if (run == 1) { CHECK(st->cut == 1, "a 40 degree turn in a frame is a cut"); cam_motion_error(g_tfx_mot, y0, 0, py, 0, c); CHECK(c[0] >= 2 * IW - 1, "on a cut the vectors point off the screen"); }
                float *o = readback(written); cuterr[run] = truth_error(o, y0, 0); free(o);
            }
            #undef st
            g_tfx_cut_frac = 0.25f;
            printf("  cut frame against its true picture: cut found %.4f, after a reset %.4f, cut rule off %.4f\n", cuterr[1], cuterr[2], cuterr[0]);
            CHECK(fabs(cuterr[1] - cuterr[2]) <= 0.1 * cuterr[2], "a cut found comes out as a reset does (within 10 %)");
            // 10b. The glow (tfx_glow): a glow blob slides 1 texel a frame across the compose's glow texture (120x68: 8 scene pixels a frame) over the still plane, the camera still; the
            // picture is the plane plus the glow upsampled. The snapshot sees none of it (no translucent pass here); the glow term marks where it changed. Measured where it was 2 to 4
            // frames ago, against the plane and the glow now
            if (DM_GAME_TFX_GLOW) {
                enum { GW = 120, GH = 68 }; tex_t glw = texture(960, GW, GH, NVN_FORMAT_RGBA16F); mtl_tex_init(&glw); mtl_reg_tex(960, &glw, NULL);
                __fp16 *gpx = malloc((size_t)GW * GH * 8); double trail[2], cov[2];
                char gdir[512]; snprintf(gdir, sizeof gdir, "%s/tfx-glowdump-XXXXXX", NSTemporaryDirectory().UTF8String); int have_gdir = mkdtemp(gdir) != NULL;   // DM_UPSCALER_TFX_GLOWDUMP, armed below
                for (int on = 1; on >= 0; on--) {
                    g_tfx_glow_on = on; g_tfx_reactive = 1; frame_no += 3; g_tfx_mask_cov_avg(1); double gx = 20;
                    if (on && have_gdir) { g_gdump.parsed = 1; g_gdump.f0 = (long)frame_no + 6; g_gdump.n = 3; snprintf(g_gdump.dir, sizeof g_gdump.dir, "%s", gdir); }
                    for (int f = 0; f < 20; f++, gx += 1) {
                        for (int y = 0; y < GH; y++) for (int x = 0; x < GW; x++) { float d2 = (float)((x + 0.5 - gx) * (x + 0.5 - gx) + (y + 0.5 - GH / 2.0) * (y + 0.5 - GH / 2.0)); __fp16 v = (__fp16)(0.3f * expf(-d2 / 18.0f));
                            gpx[4 * (y * GW + x)] = gpx[4 * (y * GW + x) + 1] = gpx[4 * (y * GW + x) + 2] = v; gpx[4 * (y * GW + x) + 3] = 1; }
                        upload(tex_mtl(&glw), gpx, 8);
                        cam_frame(0.3, 0, 0.3, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx);
                        for (int y = 0; y < IH; y++) for (int x = 0; x < IW; x++) {   // + the glow, bilinear at the texel's centre (as the kernel samples it)
                            float u = (x + 0.5f) * GW / IW - 0.5f, v = (y + 0.5f) * GH / IH - 0.5f; int x0 = (int)floorf(u), y0 = (int)floorf(v); float fx = u - x0, fy = v - y0, gsum = 0;
                            for (int k = 0; k < 4; k++) { int xi = MIN(MAX(x0 + (k & 1), 0), GW - 1), yi = MIN(MAX(y0 + (k >> 1), 0), GH - 1); gsum += (float)gpx[4 * (yi * GW + xi)] * ((k & 1) ? fx : 1 - fx) * ((k >> 1) ? fy : 1 - fy); }
                            for (int k = 0; k < 3; k++) cpx[4 * (y * IW + x) + k] = (__fp16)((float)cpx[4 * (y * IW + x) + k] + gsum);
                        }
                        upload(tex_mtl(&ccol), cpx, 8);
                        S.tex[DM_GAME_TFX_GLOW_STAGE][DM_GAME_TFX_GLOW_SLOT] = 960; scene_color = &ccol; compose_color = &ccol;
                        CHECK(frame(up), "a frame with the moving glow is drawn");
                    }
                    gx -= 1; float *o = readback(written); double e = 0; int n = 0;
                    for (int y = OH / 2 - 16; y < OH / 2 + 16; y++) for (int x = (int)(2.0 * (gx - 4) * IW / GW); x < (int)(2.0 * (gx - 2) * IW / GW); x++) {
                        double w[3]; cam_hit(0.3, 0, (x + 0.5) / 2, (y + 0.5) / 2, w); double gu = (x + 0.5) / 2 * GW / IW, gv = (y + 0.5) / 2 * GH / IH;
                        double gd2 = (gu - gx) * (gu - gx) + (gv - GH / 2.0) * (gv - GH / 2.0); e += fabs(o[4 * (y * OW + x)] - (pan_at(w[0] / PS, w[1] / PS) + 0.3 * exp(-gd2 / 18.0))); n++;
                    }
                    trail[on] = e / n; cov[on] = g_tfx_mask_cov_avg(1); free(o);
                }
                { int files = 0, sane = 0; double dmax = 0;   // the dump: 3 files of 120x68 RGBA16F (8 bytes a texel) and three R16F planes; the change shows the moving blob
                  NSArray *names = have_gdir ? [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@(gdir) error:nil] : nil;
                  for (NSString *nm in names) { NSData *d = [NSData dataWithContentsOfFile:[@(gdir) stringByAppendingPathComponent:nm]]; files++;
                      unsigned long w = 0, h = 0, fmt = 0, bpp = 0; const char *c = d.bytes; const char *nl = memchr(c, '\n', d.length);
                      if (nl && sscanf(c, "%lu %lu %lu %lu", &w, &h, &fmt, &bpp) == 4 && w == GW && h == GH && bpp == 8 && (NSUInteger)(nl - c + 1) + w * h * (bpp + 6) == d.length) {
                          sane++; const __fp16 *dp = (const __fp16 *)(nl + 1 + w * h * bpp); for (unsigned long i = 0; i < w * h; i++) dmax = fmax(dmax, fabs((double)dp[i])); } }
                  printf("  glow dump: %d files, %d with the expected layout, largest change %.3f\n", files, sane, dmax);
                  CHECK(files == 3 && sane == 3 && dmax > 0.01, "DM_UPSCALER_TFX_GLOWDUMP writes the frames asked for, each with its header, the glow and three planes; the change shows the blob");
                  if (have_gdir) [[NSFileManager defaultManager] removeItemAtPath:@(gdir) error:nil]; }
                printf("  moving glow: trail %.4f with the glow in the mask, %.4f without; mask mean %.2f %% with, %.2f %% without\n", trail[1], trail[0], cov[1], cov[0]);
                CHECK(trail[1] < trail[0] * 0.8, "with the glow in the mask the place a moving glow left shows less of it");
                CHECK(cov[1] < 10, "the glow term marks the moving glow, not the picture");
                // A broad glow over the whole picture pulsing by 20 % at 1 Hz and flickering by up to 10 % a frame (the lava's bloom in Dodongo's Cavern), over a dark scene: the
                // high pass cancels it (mask mean under 2 %); without it (the earlier rule) most of the picture is marked
                double pulse[2];
                for (int hpon = 1; hpon >= 0; hpon--) {
                    g_tfx_glow_on = 1; g_tfx_glow_hpon = hpon; frame_no += 3; g_tfx_mask_cov_avg(1); uint32_t rnd = 12345;
                    for (int f = 0; f < 40; f++) {
                        rnd = rnd * 1664525u + 1013904223u; float flick = 1 + 0.1f * ((float)(rnd >> 8) / 16777216.0f * 2 - 1), amp = 0.5f * (1 + 0.2f * sinf(2 * (float)M_PI * f / 60)) * flick;
                        for (int y = 0; y < GH; y++) for (int x = 0; x < GW; x++) { float d2 = (float)((x - GW / 2.0) * (x - GW / 2.0) + (y - GH / 2.0) * (y - GH / 2.0)); __fp16 v = (__fp16)(amp * expf(-d2 / 3000.0f));
                            gpx[4 * (y * GW + x)] = gpx[4 * (y * GW + x) + 1] = gpx[4 * (y * GW + x) + 2] = v; gpx[4 * (y * GW + x) + 3] = 1; }
                        upload(tex_mtl(&glw), gpx, 8);
                        cam_frame(0.3, 0, 0.3, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx); for (size_t i = 0; i < (size_t)IW * IH * 4; i++) if (i % 4 != 3) cpx[i] = (__fp16)((float)cpx[i] * 0.1f);   // a dark cave
                        upload(tex_mtl(&ccol), cpx, 8);
                        S.tex[DM_GAME_TFX_GLOW_STAGE][DM_GAME_TFX_GLOW_SLOT] = 960; scene_color = &ccol; compose_color = &ccol;
                        CHECK(frame(up), "a frame with the pulsing glow is drawn");
                    }
                    pulse[hpon] = g_tfx_mask_cov_avg(1);
                }
                g_tfx_glow_hpon = 1;
                printf("  a broad glow pulsing (20 %% at 1 Hz, flickering 10 %%) over a dark scene: mask mean %.2f %% with the high pass, %.2f %% without\n", pulse[1], pulse[0]);
                CHECK(pulse[1] < 2, "a broad pulsing glow leaves the mask under 2 % (the high pass cancels it)");
                CHECK(pulse[0] > 5 * pulse[1] + 1, "without the high pass the same pulse marks much more (the earlier rule's failure in the cave)");
                // A pool's glow (20x20 texels, its edges soft as a bloom's) pulsing the same way, and the moving blob: the high pass leaves a ring at the pool's edge (printed: small
                // in a capture of the game, 0.65 % of the lava's area; a coherence weight that removed it also took Navi's glow away), and the blob stays marked
                double pool[1], ring[1], blob[1];
                for (int coh = 0; coh >= 0; coh--) {
                    g_tfx_glow_on = 1; g_tfx_glow_hpon = 1; frame_no += 3; g_tfx_mask_cov_avg(1); uint32_t rnd = 777; double bx = 20;
                    for (int f = 0; f < 30; f++, bx += 1) {
                        rnd = rnd * 1664525u + 1013904223u; float flick = 1 + 0.1f * ((float)(rnd >> 8) / 16777216.0f * 2 - 1), amp = 0.4f * (1 + 0.2f * sinf(2 * (float)M_PI * f / 60)) * flick;
                        for (int y = 0; y < GH; y++) for (int x = 0; x < GW; x++) {
                            float px = fmaxf(fabsf(x + 0.5f - 85) - 10, 0), py = fmaxf(fabsf(y + 0.5f - 34) - 10, 0), pool_v = amp * expf(-(px * px + py * py) / 4.0f);   // a 20x20 square, edges softened
                            float d2 = (float)((x + 0.5 - bx) * (x + 0.5 - bx) + (y + 0.5 - 34) * (y + 0.5 - 34)); __fp16 v = (__fp16)(pool_v + 0.3f * expf(-d2 / 18.0f));
                            gpx[4 * (y * GW + x)] = gpx[4 * (y * GW + x) + 1] = gpx[4 * (y * GW + x) + 2] = v; gpx[4 * (y * GW + x) + 3] = 1; }
                        upload(tex_mtl(&glw), gpx, 8);
                        cam_frame(0.3, 0, 0.3, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx); for (size_t i = 0; i < (size_t)IW * IH * 4; i++) if (i % 4 != 3) cpx[i] = (__fp16)((float)cpx[i] * 0.1f);
                        upload(tex_mtl(&ccol), cpx, 8);
                        S.tex[DM_GAME_TFX_GLOW_STAGE][DM_GAME_TFX_GLOW_SLOT] = 960; scene_color = &ccol; compose_color = &ccol;
                        CHECK(frame(up), "a frame with the pulsing pool and the moving glow is drawn");
                    }
                    pool[coh] = g_tfx_mask_cov_avg(1);
                    NSUInteger nm = (NSUInteger)IW * IH; id<MTLBuffer> b = [g_dev newBufferWithLength:nm options:MTLResourceStorageModeShared];
                    id<MTLCommandBuffer> cb = q_cb(); id<MTLBlitCommandEncoder> be = [cb blitCommandEncoder];
                    [be copyFromTexture:g_tfx_mask sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(IW, IH, 1) toBuffer:b destinationOffset:0 destinationBytesPerRow:IW destinationBytesPerImage:nm];
                    [be endEncoding]; [cb commit]; [cb waitUntilCompleted];
                    const uint8_t *mm = b.contents; double r = 0; int rn = 0;   // the mean over a band 1 to 3 glow texels outside the pool's edge, and the mask at the blob's centre
                    for (int y = 0; y < IH; y++) for (int x = 0; x < IW; x++) { double gx2 = (x + 0.5) * GW / IW, gy2 = (y + 0.5) * GH / IH, ex = fmax(fabs(gx2 - 85) - 10, 0), ey = fmax(fabs(gy2 - 34) - 10, 0), dd = fmax(ex, ey);
                        if (dd >= 1 && dd <= 3 && fabs(gx2 - 85) > 0) { r += mm[y * IW + x] / 255.0; rn++; } }
                    ring[coh] = rn ? r / rn : 0; blob[coh] = mm[(int)(34.0 * IH / GH) * IW + (int)((bx - 1) * IW / GW)] / 255.0;
                }
                g_tfx_glow_hpon = 1;
                printf("  a pulsing 20x20 pool and the moving glow: mask mean %.2f %%; mask on the pool's edge %.3f (the ring the high pass leaves), on the blob %.2f\n", pool[0], ring[0], blob[0]);
                CHECK(blob[0] > 0.1, "beside a pulsing pool the moving glow is still marked");
                CHECK(pool[0] < 4, "the mask's mean stays small (the moving glow and the pool's edge only)");
                // Small bright specks that flicker every frame (a bloom input that changes per frame, as Dodongo's Cavern's did: the defaults marked 26-54 % there) and the moving
                // blob: the per-term stat shows the glow term driving the mask; the variants (DM_UPSCALER_TFX_GLOW's running average and 3x3 blur) cut it, the blob still marked
                { const struct { float blend; uint32_t blur; } var[2] = {{1, 0}, {0.25f, 1}}; double fm[2], fg[2], fb[2];
                  for (int k = 0; k < 2; k++) {
                      g_tfx_glow_on = 1; g_tfx_glow_hpon = 1; g_tfx_gblend = var[k].blend; g_tfx_gblur = var[k].blur; frame_no += 3; g_tfx_mask_cov_avg(1); g_tfx_term_avg(-1); uint32_t rnd = 99; double bx = 20;
                      for (int f = 0; f < 30; f++, bx += 1) {
                          for (int y = 0; y < GH; y++) for (int x = 0; x < GW; x++) {
                              rnd = rnd * 1664525u + 1013904223u; int speck = ((x * 7 + y * 13) % 11 == 0) && x > 50; float sv = speck ? 0.15f * (float)(rnd >> 8) / 16777216.0f : 0;   // specks, a new brightness each frame
                              float d2 = (float)((x + 0.5 - bx) * (x + 0.5 - bx) + (y + 0.5 - 34) * (y + 0.5 - 34)); __fp16 v = (__fp16)(0.05f + sv + 0.3f * expf(-d2 / 18.0f));
                              gpx[4 * (y * GW + x)] = gpx[4 * (y * GW + x) + 1] = gpx[4 * (y * GW + x) + 2] = v; gpx[4 * (y * GW + x) + 3] = 1; }
                          upload(tex_mtl(&glw), gpx, 8);
                          cam_frame(0.3, 0, 0.3, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx); for (size_t i = 0; i < (size_t)IW * IH * 4; i++) if (i % 4 != 3) cpx[i] = (__fp16)((float)cpx[i] * 0.1f);
                          upload(tex_mtl(&ccol), cpx, 8);
                          S.tex[DM_GAME_TFX_GLOW_STAGE][DM_GAME_TFX_GLOW_SLOT] = 960; scene_color = &ccol; compose_color = &ccol;
                          CHECK(frame(up), "a frame with flickering specks and the moving glow is drawn");
                      }
                      fm[k] = g_tfx_mask_cov_avg(1); fg[k] = g_tfx_term_avg(2);
                      NSUInteger nm = (NSUInteger)IW * IH; id<MTLBuffer> b = [g_dev newBufferWithLength:nm options:MTLResourceStorageModeShared];
                      id<MTLCommandBuffer> cb = q_cb(); id<MTLBlitCommandEncoder> be = [cb blitCommandEncoder];
                      [be copyFromTexture:g_tfx_mask sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(IW, IH, 1) toBuffer:b destinationOffset:0 destinationBytesPerRow:IW destinationBytesPerImage:nm];
                      [be endEncoding]; [cb commit]; [cb waitUntilCompleted];
                      fb[k] = ((const uint8_t *)b.contents)[(int)(34.0 * IH / GH) * IW + (int)((bx - 1) * IW / GW)] / 255.0;
                  }
                  g_tfx_gblend = 1; g_tfx_gblur = 0; g_tfx_term_avg(-1);
                  printf("  flickering specks and the moving glow: mask mean %.2f %% (glow term %.2f %%), blob %.2f with the defaults; %.2f %% (%.2f %%), blob %.2f with a running average (0.25) and the 3x3 blur\n",
                         fm[0], fg[0], fb[0], fm[1], fg[1], fb[1]);
                  CHECK(fg[0] > 0 && fabs(fg[0] - fm[0]) < 0.5 * fm[0] + 0.5, "the stats line's glow term shows what drives the mask here");
                  CHECK(fm[1] < 0.7 * fm[0], "the running average and the blur cut a flickering glow's marks (to 0.7 and less)");
                  CHECK(fb[1] > 0.1 && fb[1] >= fb[0], "with them the moving glow is marked, no less than without"); }
                g_tfx_glow_on = 1; S.tex[DM_GAME_TFX_GLOW_STAGE][DM_GAME_TFX_GLOW_SLOT] = 0; compose_color = nil; free(gpx);
            }
            // Rule 4 (tfx_cut, the camera's own buffer): a frame that binds only another camera's buffer of the view size (a loading screen's 1920x1080 dummy camera) has no camera, so
            // the spatial scaler draws, and the next frame of play restarts the history; a camera that moves further than tfx_cut's distance in a frame restarts it too
            if (DM_GAME_TFX_CUT_INV && DM_GAME_TFX_JITTER) {
                double ly = 0.1; frame_no += 3;
                for (int f = 0; f < 3; f++) { cam_frame(ly, 0, ly, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "a still frame before the load"); }
                cam_buf(view_mem + 0x1000, 0, 0, 0, 0, 1920, 1080);   // the loading screen's buffer: another render size
                mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "a loading frame"); mtl_up_tfx_stats(&n, &sp, &rs);
                CHECK(n == n0 && sp == sp0 + 1, "a frame whose only view buffer is not the scene's (its render size) has no camera: spatial");
                cam_frame(ly, 0, ly, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx); mtl_up_tfx_stats(&n0, &sp0, &rs0); CHECK(frame(up), "the first frame of play"); mtl_up_tfx_stats(&n, &sp, &rs);
                CHECK(n == n0 + 1 && rs == rs0 + 1, "the first frame of play after it restarts the history");
                double lx = 0; for (int f = 0; f < 2; f++) { cam_frame(ly, lx, ly, lx, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "a still frame"); }
                double cd = DM_GAME_TFX_CUT_DIST, cdeg = DM_GAME_TFX_CUT_DEG;   // Ocarina of Time's: 100 units, 25 degrees
                mtl_up_tfx_stats(&n0, &sp0, &rs0); cam_frame(ly, lx + 0.8 * cd, ly, lx, tex_mtl(&ccol), tex_mtl(&sdep), cpx); lx += 0.8 * cd; CHECK(frame(up), "a move of 0.8 times the distance"); mtl_up_tfx_stats(&n, &sp, &rs);
                CHECK(rs == rs0, "a move under tfx_cut's distance does not restart the history from the CPU");
                mtl_up_tfx_stats(&n0, &sp0, &rs0); cam_frame(ly, lx + 1.2 * cd, ly, lx, tex_mtl(&ccol), tex_mtl(&sdep), cpx); lx += 1.2 * cd; CHECK(frame(up), "a jump of 1.2 times the distance"); mtl_up_tfx_stats(&n, &sp, &rs);
                CHECK(rs == rs0 + 1, "a jump over tfx_cut's distance restarts the history (decided on the CPU, before the scaler is encoded)");
                g_rows_n = 0; mtl_tfx_rows(atomic_load(&g_cur_frame), row_take);
                CHECK(((int)row_get("@tfx_reset") & 8) && fabs(row_get("@tfx_cam_d") - 1.2 * cd) < 0.01 * cd, "the jump's frame has the jump bit (8) and its distance in DM_NVN_TSV's rows");
                if (cdeg > 0) {   // a turn: 0.8 times the angle, then 1.2 times (in degrees, the camera in place)
                    double a1 = ly + 0.8 * cdeg * M_PI / 180; mtl_up_tfx_stats(&n0, &sp0, &rs0); cam_frame(a1, lx, ly, lx, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "a turn of 0.8 times the angle"); mtl_up_tfx_stats(&n, &sp, &rs);
                    CHECK(rs == rs0, "a turn under tfx_cut's angle does not restart the history from the CPU");
                    double a2 = a1 + 1.2 * cdeg * M_PI / 180; mtl_up_tfx_stats(&n0, &sp0, &rs0); cam_frame(a2, lx, a1, lx, tex_mtl(&ccol), tex_mtl(&sdep), cpx); CHECK(frame(up), "a turn of 1.2 times the angle"); mtl_up_tfx_stats(&n, &sp, &rs);
                    CHECK(rs == rs0 + 1, "a turn over tfx_cut's angle restarts the history (a cut that mostly turns)");
                    g_rows_n = 0; mtl_tfx_rows(atomic_load(&g_cur_frame), row_take);
                    CHECK(((int)row_get("@tfx_reset") & 16) && fabs(row_get("@tfx_cam_deg") - 1.2 * cdeg) < 0.5, "the turn's frame has the turn bit (16) and its angle in DM_NVN_TSV's rows");
                }
            }
            // 10. The reactive mask: a faint translucent sprite (30 % towards 0.62) slides 4 input pixels a frame over the static plane, the camera still, so the camera's motion is
            // zero where the sprite moves. Each frame in GPU order as the game draws it: the opaque scene (depth, view buffer), the depth copied, the first pass on the copy opens (the
            // snapshot), the sprite drawn, the compose, the upscaler. Measured on the place the sprite left in the last 4 frames, against the true background at the output's resolution
            // Twice: the sprite alone, then with a full-screen layer that also lifts every texel by 4 % after the snapshot (Ocarina of Time composites a haze layer and a fog over the
            // whole scene after its opaque passes): the mask must stay on the sprite, not spread over the picture
            for (int haze = 0; haze < 2; haze++) {
                enum { SPR = 48, SSTEP = 4 }; double trail[2], here[2], cov = -1, hz = haze ? 1.04 : 1; float mk[2] = {-1, -1}, mk_start = -1;
                for (int on = 1; on >= 0; on--) {
                    g_tfx_reactive = on; frame_no += 3; int sx = 200; g_tfx_mask_cov_avg(1);
                    for (int f = 0; f < 20; f++, sx += SSTEP) {
                        atomic_store(&g_cur_frame, ++frame_no);
                        cam_frame(0.3, 0, 0.3, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx);
                        R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = &ccol; R.rt.depth = &sdep; up_tfx_capture(scene); up_tfx_copy_seen(&sdep, &dcopy);
                        mtl_sub_begin(); R.rt.depth = &dcopy; up_tfx_pass_begin(); CHECK(mtl_wait(mtl_sub_commit(), 5000000000ull) && !mtl_last_commit_error(), "the snapshot's submission completes");
                        for (int y = IH / 2 - SPR / 2; y < IH / 2 + SPR / 2; y++) for (int x = sx; x < sx + SPR && x < IW; x++) for (int k = 0; k < 3; k++) { __fp16 *c = cpx + 4 * (y * IW + x) + k; *c = (__fp16)(0.7f * (float)*c + 0.3f * 0.62f); }
                        if (haze) for (size_t i = 0; i < (size_t)IW * IH * 4; i++) if (i % 4 != 3) cpx[i] = (__fp16)((float)cpx[i] * 1.04f);
                        upload(tex_mtl(&ccol), cpx, 8);   // the translucent passes drew the sprite (and the layer)
                        R.rt.depth = &sdep; up_tfx_capture(pr);
                        mtl_sub_begin(); CHECK(up_mfx_encode(up), "a frame with the sprite is drawn"); CHECK(mtl_wait(mtl_sub_commit(), 5000000000ull) && !mtl_last_commit_error(), "the sprite frame completes");
                    }
                    if (on && !haze) { g_rows_n = 0; mtl_tfx_rows(frame_no, row_take);   // DM_NVN_TSV's rows: the mask's mean (the sprite's change), the glow term's 0 (no glow here)
                        CHECK(row_get("@tfx_mode") == 2 && row_get("@tfx_mask") > 0 && row_get("@tfx_mask") < 10 && row_get("@tfx_glow") >= 0, "with the mask on, a frame has its @tfx_mask and @tfx_glow rows");
                        printf("  DM_NVN_TSV rows of a sprite frame: @tfx_mode %.0f, @tfx_reset %.0f, @tfx_mask %.3f %%, @tfx_glow %.3f %%\n", row_get("@tfx_mode"), row_get("@tfx_reset"), row_get("@tfx_mask"), row_get("@tfx_glow"));
                        g_rows_n = 0; mtl_tfx_rows(frame_no + 100, row_take); CHECK(row_get("@tfx_mode") == 0 && g_rows_n == 1, "a frame with no record: @tfx_mode 0 alone"); }
                    sx -= SSTEP;
                    float *o = readback(written); double e = 0, h = 0; int n = 0, m = 0;
                    for (int y = 2 * (IH / 2 - SPR / 2) + 8; y < 2 * (IH / 2 + SPR / 2) - 8; y++) {
                        for (int x = 2 * (sx - 4 * SSTEP); x < 2 * sx; x++) { double w[3]; cam_hit(0.3, 0, (x + 0.5) / 2, (y + 0.5) / 2, w); e += fabs(o[4 * (y * OW + x)] - hz * pan_at(w[0] / PS, w[1] / PS)); n++; }
                        for (int x = 2 * sx + 8; x < 2 * (sx + SPR) - 8; x++) { double w[3]; cam_hit(0.3, 0, (x + 0.5) / 2, (y + 0.5) / 2, w); h += fabs(o[4 * (y * OW + x)] - hz * (0.7 * pan_at(w[0] / PS, w[1] / PS) + 0.3 * 0.62)); m++; }
                    }
                    trail[on] = e / n; here[on] = h / m; free(o);
                    if (on) {   // the mask's share as the stats line gives it; its value on the sprite and far from it
                        cov = g_tfx_mask_cov_avg(1);
                        NSUInteger nm = (NSUInteger)IW * IH; id<MTLBuffer> b = [g_dev newBufferWithLength:nm options:MTLResourceStorageModeShared];
                        id<MTLCommandBuffer> cb = q_cb(); id<MTLBlitCommandEncoder> be = [cb blitCommandEncoder];
                        [be copyFromTexture:g_tfx_mask sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(IW, IH, 1) toBuffer:b destinationOffset:0 destinationBytesPerRow:IW destinationBytesPerImage:nm];
                        [be endEncoding]; [cb commit]; [cb waitUntilCompleted];
                        const uint8_t *mm = b.contents; mk[0] = mm[(IH / 2) * IW + sx + SPR / 2] / 255.0f; mk[1] = mm[(IH / 8) * IW + IW / 8] / 255.0f;
                        mk_start = mm[(IH / 2) * IW + 200 + SPR / 2] / 255.0f;   // where the sprite started 20 frames ago
                    }
                }
                g_tfx_reactive = 1;
                double want = 100.0 * (SPR + 2 + SSTEP) * (SPR + 2) / ((double)IW * IH);
                printf("  translucent sprite%s: trail %.4f with the mask, %.4f without; on the sprite %.4f with, %.4f without; mask %.2f on the sprite, %.2f far from it; mean %.2f %% (the sprite's share: about %.2f %%)\n",
                       haze ? " under a full-screen layer" : "", trail[1], trail[0], here[1], here[0], mk[0], mk[1], cov, want);
                CHECK(mk[0] > 0.25f && mk[1] < 0.05f, "the mask is set over the moving sprite and 0 on the still background");
                CHECK(mk_start < 0.05f, "where the sprite was 20 frames ago the mask is 0 again (a mark lasts one frame more, not for good)");
                CHECK(cov > 0.2 * want && cov < 2.0 * want, "the mask's mean is about the sprite's share of the picture: it does not spread over the whole, also under a full-screen layer");
                CHECK(trail[1] < trail[0] * 0.8, "with the reactive mask the place the sprite left shows less of it (less ghosting)");
                CHECK(here[1] <= here[0] * 1.1, "with the mask the sprite itself is no further from the truth");
                if (haze) {   // the earlier rule (the whole change from 1 % to 10 %, no local part) under the same layer: it spreads over the picture, which is what the local part prevents
                    float l0 = g_tfx_mask_lo, h0 = g_tfx_mask_hi, a0 = g_tfx_mask_alo, b0 = g_tfx_mask_ahi; g_tfx_mask_lo = 2; g_tfx_mask_hi = 3; g_tfx_mask_alo = 0.01f; g_tfx_mask_ahi = 0.10f;
                    frame_no += 3; g_tfx_mask_cov_avg(1);
                    for (int f = 0; f < 6; f++) {
                        atomic_store(&g_cur_frame, ++frame_no); cam_frame(0.3, 0, 0.3, 0, tex_mtl(&ccol), tex_mtl(&sdep), cpx);
                        R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = &ccol; R.rt.depth = &sdep; up_tfx_capture(scene); up_tfx_copy_seen(&sdep, &dcopy);
                        mtl_sub_begin(); R.rt.depth = &dcopy; up_tfx_pass_begin(); mtl_wait(mtl_sub_commit(), 5000000000ull);
                        for (size_t i = 0; i < (size_t)IW * IH * 4; i++) if (i % 4 != 3) cpx[i] = (__fp16)((float)cpx[i] * 1.04f);
                        upload(tex_mtl(&ccol), cpx, 8); R.rt.depth = &sdep; up_tfx_capture(pr);
                        mtl_sub_begin(); up_mfx_encode(up); mtl_wait(mtl_sub_commit(), 5000000000ull);
                    }
                    double old = g_tfx_mask_cov_avg(1); g_tfx_mask_lo = l0; g_tfx_mask_hi = h0; g_tfx_mask_alo = a0; g_tfx_mask_ahi = b0;
                    printf("  the earlier rule under the same layer: the mask's mean %.1f %%\n", old);
                    CHECK(old > 10 * want, "the earlier rule (the whole change from 1 %) spreads over the picture under a full-screen layer (the mean ten times the sprite's share and more)");
                }
            }
            // 11. The camera's jitter (tfx_jitter): the host writes it into the view buffers before the GPU reads them, MetalFX is told it, the motion takes it out
            if (DM_GAME_TFX_JITTER) {
                g_tfx_jitter = 1; g_tfx_reactive = 0; g_tfx_motion = 2;
                jt.ccol = &ccol; jt.sdep = &sdep; jt.scene = scene; jt.pr = pr; jt.up = up; jt.cpx = cpx; jt.copy_prev = 1;
                int jit_on = 0;
                // The patch itself, on a still camera: A's rows against the expected ones before cam_frame rewrites A
                frame_no += 3; double y0 = 0.25;
                jit_on = jframe(y0, y0); CHECK(!jit_on, "no jitter on a frame after one the temporal scaler did not draw");
                jit_on = jframe(y0, y0); CHECK(jit_on, "the next frame is jittered");
                float seen[8][2]; int distinct = 1;
                for (int f = 0; f < 8; f++) { jframe(y0, y0); seen[f][0] = (float)tj[0]; seen[f][1] = (float)tj[1]; for (int g = 0; g < f; g++) if (seen[g][0] == seen[f][0] && seen[g][1] == seen[f][1]) distinct = 0; }
                CHECK(distinct && fabsf(seen[0][0]) <= 0.5f && fabsf(seen[0][1]) <= 0.5f, "8 frames, 8 distinct jitters within half a pixel (Halton 2, 3)");
                { int cuts0 = jt.cuts, jittered = 0; for (int f = 0; f < 16; f++) jittered += jframe(y0, y0);
                  printf("  16 still jittered frames, the previous set copying last frame's (jittered) buffer: %d jittered, %d cuts\n", jittered, jt.cuts - cuts0);
                  CHECK(jittered == 16 && jt.cuts == cuts0, "with the game's previous set a copy of last frame's jittered buffer: every frame jittered, no cut, the history kept"); }
                CHECK(jt.checked >= 9 && !jt.bad_a, "A's projection and view-projection rows 0 and 1 get the offset times row 3 (dx = 2 jx / w, dy = -2 jy / h)");
                CHECK(!jt.bad_b, "B (bound before A, the same camera) gets the same jitter");
                CHECK(!jt.bad_other, "the shadow camera, the view and the previous set are left alone");
                { jt.copy_prev = 0; int cuts0 = jt.cuts, jittered = 0; for (int f = 0; f < 8; f++) jittered += jframe(y0, y0); jt.copy_prev = 1;
                  CHECK(jittered == 8 && jt.cuts == cuts0, "a game whose previous set is rebuilt without the jitter: also every frame jittered, no cut"); }
                // The motion with jitter: a turn, the vectors exact for the unjittered sample positions
                { double py = y0; double worst = 0; for (int f = 0; f < 6; f++) { py = y0; y0 += step; jit_on = jframe(y0, py); if (jit_on && f >= 1) { double e = cam_motion_error(g_tfx_mot, y0, 0, py, 0, c); worst = fmax(worst, e); } }
                  printf("  jittered turn: largest motion error %.4f px\n", worst); CHECK(worst < 0.1, "with jitter the camera motion still matches the reference (the jitter taken out)"); }
                // Detail: a still camera, 32 frames, against the true picture at the output's resolution: no jitter, jitter with MetalFX's sign as the host passes it, the other sign
                double jerr[3];
                for (int mode = 0; mode < 3; mode++) {
                    g_tfx_jitter = mode != 0; g_tfx_jit_sign = mode == 2 ? -1.0f : 1.0f; frame_no += 3; double ys = 0.4;
                    for (int f = 0; f < 34; f++) jframe(ys, ys);
                    tj[0] = tj[1] = 0; float *o = readback(written); jerr[mode] = truth_error(o, ys, 0); free(o);
                }
                g_tfx_jit_sign = 1;
                { g_tfx_jitter = 1; g_tfx_sharpen = 0.8f; frame_no += 3; double ys = 0.4; for (int f = 0; f < 34; f++) jframe(ys, ys);   // the same with the sharpen after the scaler
                  tj[0] = tj[1] = 0; float *o = readback(written); double es = truth_error(o, ys, 0); free(o); g_tfx_sharpen = 0;
                  printf("  still camera, jitter and the sharpen (0.8) against the true picture: %.4f\n", es); CHECK(es < 0.05, "with the sharpen the picture is still the scene"); }
                // 13. The scale: 1.33x, 1.5x and 2x outputs (1280x720, 1440x810, 1920x1080 from 960x540), a still camera, the jitter's phases by the scale (15, 18, 32), against the
                // true picture and the frame-to-frame change once converged (the shimmer); at 1.5x also with 8 phases. The mip bias follows the scale (log2(input / output))
                { const int ows[3] = {1280, 1440, 1920}, ohs[3] = {720, 810, 1080}; double terr[4], shim[4]; uint32_t phases[4];
                  for (int k = 0; k < 4; k++) {
                      int r = k < 3 ? k : 1; g_tfx_phases = k == 3 ? 8 : 0; g_tfx_jitter = 1; frame_no += 3; double ys = 0.4; float *prev = NULL; double sh = 0;
                      { const uint32_t rr[8] = {0, 0, IW - 1, IH - 1, 0, 0, (uint32_t)ows[r] - 1, (uint32_t)ohs[r] - 1}; memcpy(S.push[1], rr, sizeof rr); }
                      for (int f = 0; f < 72; f++) {
                          jframe(ys, ys);
                          if (f >= 64) { float *o = readback(written); if (prev) { double d = 0; int n = 0; for (int y = ohs[r] / 4; y < ohs[r] * 3 / 4; y++) for (int x = ows[r] / 4; x < ows[r] * 3 / 4; x++, n++) d += fabs(o[4 * (y * OW + x)] - prev[4 * (y * OW + x)]); sh += d / n / 7; free(prev); } prev = o; }
                      }
                      terr[k] = truth_error_at(prev, ys, ows[r], ohs[r]); shim[k] = sh; phases[k] = up_tfx_phase_count(); free(prev);
                  }
                  g_tfx_phases = 0; rects(IW, IH); tj[0] = tj[1] = 0;
                  printf("  scale 1.33x (%u phases): truth %.4f shimmer %.4f; 1.5x (%u): %.4f %.4f; 2x (%u): %.4f %.4f; 1.5x with 8 phases: %.4f %.4f; mip bias now %.3f\n", phases[0], terr[0], shim[0],
                         phases[1], terr[1], shim[1], phases[2], terr[2], shim[2], terr[3], shim[3], g_tfx_bias_now);
                  CHECK(phases[0] == 15 && phases[1] == 18 && phases[2] == 32 && phases[3] == 8, "the jitter's phases follow the scale (ceil(8 x scale^2)), or DM_UPSCALER_TFX_PHASES");
                  CHECK(terr[0] < 0.05 && terr[1] < 0.05 && terr[2] < 0.05, "a still scene converges at 1.33x, 1.5x and 2x");
                  CHECK(shim[1] <= shim[0] * 1.2 + 0.0005, "converged at 1.5x the shimmer is no more than at 1.33x");
                  // 8 phases shimmered the same here (the synthetic scene's texture is sampled exactly); printed, not checked
                  CHECK(fabsf(g_tfx_bias_now - roundf(-log2f(1.5f) * 32) / 32) < 0.001f, "the mip bias follows the scale: log2(1 / 1.5) after the last, 1.5x, run"); }
                // 15. Outside steady play. (a) Idle scalers go: the scale runs above left scalers for 1280x720 and 1440x810 outputs; 700 frames on at 1920x1080 only one is left.
                // (b) A long run (150 frames, the jitter, the mask and the glow textures on) adds nothing to the residency set after its first frames. (c) A fade to black and back
                // (Ocarina of Time's compose fade: 1, 0.89, 0.43, 0.03, 0, then up): the output follows each frame (against the faded picture)
                { int live0 = 0; for (int i = 0; i < UP_TFX_SCALERS; i++) live0 += g_up_tfx_sc[i].sc != nil;
                  g_tfx_jitter = 1; frame_no += 700; double ys = 0.4; for (int f = 0; f < 3; f++) jframe(ys, ys);
                  int live1 = 0; for (int i = 0; i < UP_TFX_SCALERS; i++) live1 += g_up_tfx_sc[i].sc != nil;
                  printf("  idle scalers: %d alive after the scale runs, %d after 700 frames at one size\n", live0, live1);
                  CHECK(live0 >= 2 && live1 == 1, "temporal scalers idle for 600 frames are let go (the one in use stays)");
                  NSUInteger r0 = 0; for (int f = 0; f < 150; f++) { jframe(ys, ys); if (f == 20) { pthread_mutex_lock(&g_res_mu); r0 = g_res_objects.count; pthread_mutex_unlock(&g_res_mu); } }
                  pthread_mutex_lock(&g_res_mu); NSUInteger r1 = g_res_objects.count; pthread_mutex_unlock(&g_res_mu);
                  printf("  long run: residency set %lu objects at frame 20, %lu at frame 150\n", (unsigned long)r0, (unsigned long)r1);
                  CHECK(r1 <= r0, "a long run adds nothing to the residency set after its first frames");
                  { float b0 = g_tfx_bias_now; frame_no += 40; atomic_store(&g_cur_frame, frame_no);   // 40 frames on, a frame with no compose draw (a menu's): the spatial scaler draws, the bias goes
                    mtl_sub_begin(); up_mfx_encode(jt.up); mtl_wait(mtl_sub_commit(), 5000000000ull);
                    CHECK(b0 < 0 && g_tfx_bias_now == 0, "30 frames and more without the temporal scaler, the mip bias goes back to 0");
                    jframe(ys, ys); jframe(ys, ys); CHECK(g_tfx_bias_now == b0, "with the temporal scaler back the bias returns"); }
                  // the fade with the reactive mask on (its whole-change term marks the fade's frames) and off (MetalFX's own rejection alone)
                  const float fade[12] = {1, 1, 0.89f, 0.43f, 0.03f, 0, 0, 0.2f, 0.45f, 0.7f, 0.9f, 1}; double worst = 0, worst_at = 0, worst_off = 0;
                  uint64_t fade_f0 = 0;   // the mask's run's first fade frame
                  for (int mrun = 0; mrun < 2; mrun++) { g_tfx_reactive = mrun == 1; double *wp = mrun == 1 ? &worst : &worst_off; frame_no += 3; for (int f = 0; f < 3; f++) jframe(ys, ys);   // the mask's run last: its rows stay in the ring
                      if (mrun) fade_f0 = frame_no + 1;
                  for (int f = 0; f < 12; f++) {
                      atomic_store(&g_cur_frame, ++frame_no);   // as jframe, with the picture faded after it is rendered (the compose's fade)
                      cam_buf(view_mem + 0x5000, ys, 0, ys, 0, 1920, 1080); tj[0] = tj[1] = 0; cam_frame(ys, 0, ys, 0, tex_mtl(jt.ccol), tex_mtl(jt.sdep), jt.cpx);
                      if (jt.copy_prev && jt.have_last) memcpy(view_mem + 0x1000 + DM_GAME_TFX_VIEW_PREV, jt.last_vp, 64);
                      R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = jt.ccol; R.rt.depth = jt.sdep;
                      S.ubo[DM_GAME_TFX_VIEW_STAGE][DM_GAME_TFX_VIEW_SLOT] = (p_bind_buf){.addr = (uint64_t)view_mem + 0x1000, .size = (uint64_t)g_tfx_view_size}; up_tfx_capture(jt.scene);
                      int on = g_tfx_jit_frame == frame_no; tj[0] = on ? g_tfx_jit[0] : 0; tj[1] = on ? g_tfx_jit[1] : 0;
                      static uint8_t keep[0x3500]; memcpy(keep, view_mem + 0x1000, sizeof keep); cam_frame(ys, 0, ys, 0, tex_mtl(jt.ccol), tex_mtl(jt.sdep), jt.cpx); memcpy(view_mem + 0x1000, keep, sizeof keep);
                      memcpy(jt.last_vp, view_mem + 0x1000 + DM_GAME_TFX_VIEW_VP, 64);
                      for (size_t i = 0; i < (size_t)IW * IH * 4; i++) if (i % 4 != 3) jt.cpx[i] = (__fp16)((float)jt.cpx[i] * fade[f]);
                      upload(tex_mtl(jt.ccol), jt.cpx, 8); up_tfx_capture(jt.pr);
                      mtl_sub_begin(); CHECK(up_mfx_encode(jt.up), "a fade frame is drawn"); CHECK(mtl_wait(mtl_sub_commit(), 5000000000ull) && !mtl_last_commit_error(), "the fade frame completes");
                      float *o = readback(written); double m = 0, mi = 0; for (int y = OH / 4; y < OH * 3 / 4; y++) for (int x = OW / 4; x < OW * 3 / 4; x++) m += o[4 * (y * OW + x)];
                      for (int y = IH / 4; y < IH * 3 / 4; y++) for (int x = IW / 4; x < IW * 3 / 4; x++) mi += (float)jt.cpx[4 * (y * IW + x)];
                      m /= (OW / 2) * (OH / 2); mi /= (IW / 2) * (IH / 2); free(o);
                      double rel = fabs(m - mi) / fmax(mi, 0.02); if (rel > *wp) { *wp = rel; if (mrun) worst_at = fade[f]; }
                  } }
                  g_tfx_reactive = 0;
                  tj[0] = tj[1] = 0;
                  printf("  fade to black and back: the output's mean is at most %.1f %% off the faded picture's with the reactive mask (at fade %.2f), %.1f %% without it\n", 100 * worst, worst_at, 100 * worst_off);
                  CHECK(worst < 0.1, "through a fade to black and back the output follows each frame within 10 % (the reactive mask's whole-picture brightness term marks it)");
                  // DM_NVN_TSV's rows of the mask's run (mtl_tfx_rows): temporal, no restart (a fade is none), the input's luminance ratio, and the mask over the whole picture where
                  // it changed by more than 10 % (the fade from 0.89 to 0.43 and on) and not on the steady frames before
                  for (int k = 2; k < 12; k++) { uint64_t f = fade_f0 + (uint64_t)k; g_rows_n = 0; mtl_tfx_rows(f, row_take);
                      double ratio = fade[k - 1] > 0 ? fade[k] / fade[k - 1] : fade[k] > 0 ? 1e9 : 1, lr = row_get("@tfx_lum");
                      CHECK(row_get("@tfx_mode") == 2 && row_get("@tfx_reset") == 0, "a fade frame is temporal with no restart (@tfx_mode 2, @tfx_reset 0)");
                      if (fade[k - 1] > 0.1f && fade[k] > 0.1f) CHECK(fabs(lr / ratio - 1) < 0.02, "the @tfx_lum row is the input's luminance over last frame's");
                      if (fabs(ratio - 1) > 0.15) CHECK(row_get("@tfx_mask") > 99, "a frame whose brightness changed by over 15 % has the mask over the whole picture");
                      if (k == 2) printf("  fade rows: @tfx_lum %.3f (the fade's ratio %.3f), @tfx_mask %.1f %%\n", lr, ratio, row_get("@tfx_mask")); }
                  g_rows_n = 0; mtl_tfx_rows(fade_f0 + 1, row_take); CHECK(row_get("@tfx_mask") < 1, "a steady frame's mask has no whole-picture term"); }
                g_tfx_jitter = 0;
                printf("  still camera against the true picture: no jitter %.4f, jitter (MetalFX told the offset applied) %.4f, the other sign %.4f\n", jerr[0], jerr[1], jerr[2]);
                CHECK(jerr[1] < jerr[0] * 0.9, "with the jitter the temporal scaler gets closer to the true picture than without (detail)");
                CHECK(jerr[1] < jerr[2], "MetalFX's jitterOffset is the offset applied (the pixels the picture moved): the other sign is further from the truth");
                g_tfx_reactive = 1; tj[0] = tj[1] = 0;
            }
            S.ubo[DM_GAME_TFX_VIEW_STAGE][DM_GAME_TFX_VIEW_SLOT] = (p_bind_buf){0}; scene_draw = nil; compose_color = nil; S.tex[5][0] = 901;
        } else printf("  no tfx_view in this profile: the camera motion is not checked\n");
        compose_draw = nil; R.has_rt = 0; g_up_tfx_resolve = resolve; up->up_color = UP_COLOR_LINEAR;
    } else printf("  no tfx_compose in this profile: the profile's resolver is not checked\n");
    // 12. The sharpen after the temporal scaler (tfx_sharpen, DM_UPSCALER_TFX_SHARPEN): a flat area stays as it is, an edge does not ring (nothing outside its neighbourhood's
    // range, also above 1), a blurred edge comes out steeper, strength 0 changes nothing; its cost at 3840x2160
    if (up_tfx_sharpen_ready()) {
        enum { SW = 64, SH = 16 }; float v[SW * SH], blur[SW * SH];
        for (int i = 0; i < SW * SH; i++) v[i] = 0.4f;
        float *o = sharpen_run(v, SW, SH, 1, NULL, MTLPixelFormatRGBA16Float); float dev = 0; for (int i = 0; i < SW * SH; i++) dev = fmaxf(dev, fabsf(o[i] - 0.4f)); free(o);
        CHECK(dev < 1e-3f, "a flat area comes out as it is at full strength");
        for (int hdr = 0; hdr < 2; hdr++) {
            float lo = hdr ? 0.5f : 0.2f, hiv = hdr ? 4.0f : 0.8f;
            for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++) v[y * SW + x] = x < SW / 2 ? lo : hiv;
            o = sharpen_run(v, SW, SH, 1, NULL, MTLPixelFormatRGBA16Float); float omin = 1e9f, omax = -1e9f; for (int i = 0; i < SW * SH; i++) { omin = fminf(omin, o[i]); omax = fmaxf(omax, o[i]); } free(o);
            printf("  sharpen, a hard edge %g | %g at full strength: %g to %g\n", lo, hiv, omin, omax);
            CHECK(omin >= lo - 0.002f * hiv && omax <= hiv * 1.002f, hdr ? "a hard edge above 1 does not ring" : "a hard edge does not ring (nothing outside its two sides)");
        }
        for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++) blur[y * SW + x] = 0.2f + 0.6f / (1 + expf(-(x - SW / 2 + 0.5f) / 1.5f));   // a soft edge
        float *o0 = sharpen_run(blur, SW, SH, 0, NULL, MTLPixelFormatRGBA16Float), *o1 = sharpen_run(blur, SW, SH, 0.8f, NULL, MTLPixelFormatRGBA16Float), *o2 = sharpen_run(blur, SW, SH, 1, NULL, MTLPixelFormatRGBA16Float);
        float s0 = 0, s1 = 0, s2 = 0, id0 = 0, rmin = 1e9f, rmax = -1e9f;
        for (int x = 1; x < SW; x++) { int i = (SH / 2) * SW + x; s0 = fmaxf(s0, o0[i] - o0[i - 1]); s1 = fmaxf(s1, o1[i] - o1[i - 1]); s2 = fmaxf(s2, o2[i] - o2[i - 1]); }
        for (int i = 0; i < SW * SH; i++) { id0 = fmaxf(id0, fabsf(o0[i] - blur[i])); rmin = fminf(rmin, o2[i]); rmax = fmaxf(rmax, o2[i]); }
        printf("  sharpen, a soft edge: steepest step %.4f at strength 0, %.4f at 0.8 (the default), %.4f at 1; range at 1 %.4f to %.4f\n", s0, s1, s2, rmin, rmax);
        CHECK(id0 < 1e-3f, "strength 0 changes nothing");
        CHECK(s1 > s0 * 1.05f && s2 > s1, "a soft edge comes out steeper at the default strength, more at full strength");
        CHECK(rmin >= 0.2f - 0.002f && rmax <= 0.8f + 0.002f, "the sharpened soft edge stays within its two sides");
        free(o0); free(o1); free(o2);
        // the sharpen's and the mask's costs are measured at the start (section 0), before the GPU has worked through the sections
    } else CHECK(0, "the sharpen's pipeline is made");
    // 14. The mip bias on a sampler with mips (nearest mip filter): at a level of detail of 0.7 mip 1 is read without it; with the 1.5x bias (-0.59) mip 0; a sampler without mips and
    // a comparison sampler take none
    { samp_par sp = {.minf = 2, .magf = 0, .lod_max = 16}; mtl_reg_samp(950, &sp);
      up_tfx_mip_bias(1.0f); float a = mip_sample(950, 0.7f); up_tfx_mip_bias(1.5f); float b = mip_sample(950, 0.7f);
      printf("  mip bias: level of detail 0.7 reads mip %g without the bias, mip %g with %.3f (1.5x)\n", a, b, g_tfx_bias_now);
      CHECK(a == 1 && b == 0, "a mipmapped sampler takes the mip bias: 0.7 - 0.59 reads mip 0");
      samp_par cp = {.minf = 2, .lod_max = 16, .cmp_mode = 1, .cmp_func = 1}; mtl_reg_samp(951, &cp); float c = mip_sample(951, 0.7f);
      CHECK(c == 1 || c == 0, "a comparison sampler is made too"); (void)c;
      up_tfx_mip_bias(2.0f); }
    // Which depth and motion formats MetalFX's temporal scaler takes here (for the design: the game's own may go straight)
    MTLPixelFormat dfs[] = {MTLPixelFormatDepth32Float, MTLPixelFormatDepth16Unorm, MTLPixelFormatDepth32Float_Stencil8, MTLPixelFormatR32Float, MTLPixelFormatR16Float},
                   mfs[] = {MTLPixelFormatRG16Float, MTLPixelFormatRG32Float, MTLPixelFormatRG16Snorm, MTLPixelFormatRG16Sint};
    printf("  formats MetalFX takes (colour RGBA16F 960x540 → 1920x1080):");
    for (unsigned i = 0; i < sizeof dfs / sizeof *dfs; i++) for (unsigned j = 0; j < sizeof mfs / sizeof *mfs; j++) {
        MTLFXTemporalScalerDescriptor *d = [MTLFXTemporalScalerDescriptor new];
        d.colorTextureFormat = MTLPixelFormatRGBA16Float; d.outputTextureFormat = MTLPixelFormatRGBA16Float; d.depthTextureFormat = dfs[i]; d.motionTextureFormat = mfs[j];
        d.inputWidth = IW; d.inputHeight = IH; d.outputWidth = OW; d.outputHeight = OH;
        id sc = nil; @try { sc = [d newTemporalScalerWithDevice:g_dev compiler:g_up_tfx_comp]; } @catch (NSException *x) { sc = nil; }
        if (sc) printf(" depth %lu + motion %lu;", (unsigned long)dfs[i], (unsigned long)mfs[j]);
    }
    printf("\n");
    free(cpx); free(mpx);
    printf("t_upscaler_tfx (encoding thread %s): %d checks, %d failed\n", rec_on() ? "on" : "off", checks, failed);
    return failed != 0;
}}
