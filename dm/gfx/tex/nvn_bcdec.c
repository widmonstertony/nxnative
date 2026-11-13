// 见 nvn_bcdec.h。解码用 bcdec（dm/third_party/bcdec，单头文件，MIT / 公有领域）。
// See nvn_bcdec.h. Decoding uses bcdec (dm/third_party/bcdec, single header, MIT / public domain).
#define BCDEC_IMPLEMENTATION
#define BCDEC_BC4BC5_PRECISE   // BC4 / BC5 带有符号版本的接口 | interface with signed variants of BC4 / BC5
#include "../../third_party/bcdec/bcdec.h"
#include "nvn_bcdec.h"
#include <math.h>
#include <string.h>

enum { R8Unorm = 10, R8Snorm = 12, RG8Unorm = 30, RG8Snorm = 32, RGBA8Unorm = 70, RGBA8Unorm_sRGB = 71, RGB9E5Float = 93, RGBA16Float = 115 };
static int g_bc6h_rgb9e5;   // BC6H into RGB9E5Float, 4 bytes per pixel instead of 8 (nvn_bcdec.h)
void nvn_bc_set_bc6h_rgb9e5(int on) { g_bc6h_rgb9e5 = on != 0; }
int nvn_bc_bc6h_rgb9e5(void) { return g_bc6h_rgb9e5; }

uint32_t nvn_rgb9e5_pack(float r, float g, float b) {   // the reference packing of EXT_texture_shared_exponent
    const float max_value = 65408.0f;   // (511 / 512) * 2^15
    float c[3] = {r, g, b};
    for (int i = 0; i < 3; i++) c[i] = c[i] > 0 ? (c[i] < max_value ? c[i] : max_value) : 0;   // negative and NaN fail the test and become 0
    float peak = fmaxf(c[0], fmaxf(c[1], c[2]));
    int e = peak > 0 ? (int)fmaxf(-16.0f, floorf(log2f(peak))) + 16 : 0;
    float denom = exp2f((float)(e - 24));
    if ((int)floorf(peak / denom + 0.5f) == 512) { e++; denom *= 2; }
    uint32_t m[3];
    for (int i = 0; i < 3; i++) { float q = floorf(c[i] / denom + 0.5f); m[i] = q > 511 ? 511 : (uint32_t)q; }
    return m[0] | (m[1] << 9) | (m[2] << 18) | ((uint32_t)e << 27);
}

static float half_to_float(uint16_t h) {
    int s = (h >> 15) & 1, e = (h >> 10) & 31, m = h & 1023;
    float v = e == 0 ? ldexpf((float)m, -24) : e == 31 ? (m ? NAN : INFINITY) : ldexpf((float)(m | 1024), e - 25);
    return s ? -v : v;
}
// NVN：0x41 RGB_DXT1、0x42 RGBA_DXT1、0x43 DXT3、0x44 DXT5、0x45–0x48 同上 sRGB、0x49 / 0x4a BC4 无 / 有符号、0x4b / 0x4c BC5、0x4d / 0x4e BC7（sRGB）、0x4f / 0x50 BC6H 有 / 无符号
// NVN: 0x41 RGB_DXT1, 0x42 RGBA_DXT1, 0x43 DXT3, 0x44 DXT5, 0x45–0x48 the same in sRGB, 0x49 / 0x4a BC4 unsigned / signed, 0x4b / 0x4c BC5, 0x4d / 0x4e BC7 (sRGB), 0x4f / 0x50 BC6H signed / unsigned
int nvn_bc_unpacked(uint32_t f, uint32_t *pf, int *bpp) {
    switch (f) {
    case 0x41: case 0x42: case 0x43: case 0x44: case 0x4d: *pf = RGBA8Unorm; *bpp = 4; return 1;
    case 0x45: case 0x46: case 0x47: case 0x48: case 0x4e: *pf = RGBA8Unorm_sRGB; *bpp = 4; return 1;
    case 0x49: *pf = R8Unorm; *bpp = 1; return 1;
    case 0x4a: *pf = R8Snorm; *bpp = 1; return 1;
    case 0x4b: *pf = RG8Unorm; *bpp = 2; return 1;
    case 0x4c: *pf = RG8Snorm; *bpp = 2; return 1;
    case 0x4f: case 0x50: if (g_bc6h_rgb9e5) { *pf = RGB9E5Float; *bpp = 4; } else { *pf = RGBA16Float; *bpp = 8; } return 1;
    default: return 0;
    }
}

static void block(uint32_t f, const uint8_t *b, uint8_t *o, int op) {   // 一块 → 4×4 像素（o 每行 op 字节） | one block → 4×4 pixels (o has op bytes per row)
    switch (f) {
    case 0x41: case 0x42: case 0x45: case 0x46: bcdec_bc1(b, o, op); break;
    case 0x43: case 0x47: bcdec_bc2(b, o, op); break;
    case 0x44: case 0x48: bcdec_bc3(b, o, op); break;
    case 0x49: bcdec_bc4(b, o, op, 0); break;
    case 0x4a: bcdec_bc4(b, o, op, 1); break;
    case 0x4b: bcdec_bc5(b, o, op, 0); break;
    case 0x4c: bcdec_bc5(b, o, op, 1); break;
    case 0x4d: case 0x4e: bcdec_bc7(b, o, op); break;
    case 0x4f: case 0x50: {   // bcdec 出 RGB 半精度，补 alpha = 1.0 | bcdec outputs RGB half-float; add alpha = 1.0
        uint16_t rgb[16 * 3]; bcdec_bc6h_half(b, rgb, 4 * 3, f == 0x4f);
        if (g_bc6h_rgb9e5) {   // alpha is 1.0 in a sampled RGB9E5 texture
            for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++) {
                const uint16_t *s = rgb + (y * 4 + x) * 3;
                *((uint32_t *)(o + y * op) + x) = nvn_rgb9e5_pack(half_to_float(s[0]), half_to_float(s[1]), half_to_float(s[2]));
            }
            break;
        }
        for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++) {
            uint16_t *d = (uint16_t *)(o + y * op) + x * 4; const uint16_t *s = rgb + (y * 4 + x) * 3;
            d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = 0x3c00;
        }
        break; }
    }
}

int nvn_bc_decode(uint32_t f, const uint8_t *src, size_t pitch, uint32_t w, uint32_t h, uint8_t *dst, size_t dpitch) {
    uint32_t pf; int bpp; if (!nvn_bc_unpacked(f, &pf, &bpp)) return -1;
    int bb = (f == 0x41 || f == 0x42 || f == 0x45 || f == 0x46 || f == 0x49 || f == 0x4a) ? 8 : 16;   // 每块字节 | bytes per block
    _Alignas(8) uint8_t tmp[4 * 4 * 8];
    for (uint32_t by = 0; by * 4 < h; by++) for (uint32_t bx = 0; bx * 4 < w; bx++) {
        const uint8_t *b = src + by * pitch + bx * bb;
        uint32_t cw = w - bx * 4 < 4 ? w - bx * 4 : 4, ch = h - by * 4 < 4 ? h - by * 4 : 4;
        uint8_t *o = dst + (size_t)by * 4 * dpitch + (size_t)bx * 4 * bpp;
        if (cw == 4 && ch == 4) { block(f, b, o, (int)dpitch); continue; }
        block(f, b, tmp, 4 * bpp);   // 边上不满 4×4 的块：先解到临时块再拷需要的部分 | blocks at the edge that are not a full 4×4: decode into a temporary block first, then copy the needed part
        for (uint32_t y = 0; y < ch; y++) memcpy(o + y * dpitch, tmp + y * 4 * bpp, cw * bpp);
    }
    return 0;
}
