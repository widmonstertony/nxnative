// BC decode correctness: decode a known block with bcdec through our glue, and compare against
// bytes produced by an independent path (a second, hand-written DXT1 decoder in this file).
// Formats with no independent reference here are checked structurally instead: every decoded
// pixel must be opaque, the block must fit its 4x4 grid, and edge blocks must be trimmed.
#include "../nvn_bcdec.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void check(int cond, const char *what) {
    if (!cond) { printf("FAIL: %s\n", what); failures++; }
}

// ---- reference DXT1 (BC1) decoder: the textbook algorithm, written independently of bcdec ----
static void put565(unsigned char *o, unsigned v, int srgb) {
    (void)srgb;
    int r = (v >> 11) & 0x1f, g = (v >> 5) & 0x3f, b = v & 0x1f;
    o[0] = (unsigned char)((r << 3) | (r >> 2));
    o[1] = (unsigned char)((g << 2) | (g >> 4));
    o[2] = (unsigned char)((b << 3) | (b >> 2));
    o[3] = 255;
}
static void ref_bc1(const unsigned char *blk, unsigned char *out, int op) {
    unsigned c0 = blk[0] | (blk[1] << 8), c1 = blk[2] | (blk[3] << 8);
    unsigned char pal[4][4];
    put565(pal[0], c0, 0);
    put565(pal[1], c1, 0);
    if (c0 > c1) {
        for (int i = 0; i < 3; i++) {
            // bcdec rounds; a truncating reference differs by one on every interpolated stop
            pal[2][i] = (unsigned char)((2 * pal[0][i] + pal[1][i] + 1) / 3);
            pal[3][i] = (unsigned char)((pal[0][i] + 2 * pal[1][i] + 1) / 3);
        }
        pal[2][3] = pal[3][3] = 255;
    } else {
        for (int i = 0; i < 3; i++) {
            pal[2][i] = (unsigned char)((pal[0][i] + pal[1][i] + 1) / 2);
            pal[3][i] = 0;
        }
        pal[2][3] = 255;
        pal[3][3] = 255;   // RGB_DXT1: the fourth colour is black but opaque
    }
    unsigned idx = blk[4] | (blk[5] << 8) | (blk[6] << 16) | ((unsigned)blk[7] << 24);
    for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++) {
            int p = (int)((idx >> (2 * (y * 4 + x))) & 3);
            memcpy(out + y * op + x * 4, pal[p], 4);
        }
}

static void test_bc1_matches_reference(void) {
    // Two blocks: one with c0 > c1 (four-colour mode) and one with c0 <= c1 (three-colour).
    unsigned char blocks[2][8] = {
        { 0x00, 0xF8, 0xE0, 0x07, 0x1B, 0x36, 0x6C, 0xD8 },   // c0 = red-ish 0xF800, c1 = green-ish 0x07E0
        { 0xE0, 0x07, 0x00, 0xF8, 0x55, 0xAA, 0x55, 0xAA },   // swapped: three-colour mode
    };
    for (int k = 0; k < 2; k++) {
        unsigned char got[4 * 16], want[4 * 16];
        int r = nvn_bc_decode(0x41, blocks[k], 8, 4, 4, got, 16);   // 0x41 = RGB_DXT1 (no alpha semantics)
        check(r == 0, "bc1 decode returns 0");
        ref_bc1(blocks[k], want, 16);
        if (memcmp(got, want, sizeof want) != 0) {
            char msg[96];
            snprintf(msg, sizeof msg, "BC1 block %d matches the reference decoder", k);
            check(0, msg);
            for (int i = 0; i < 16; i++)
                if (got[i] != want[i]) { printf("  byte %d: got %u want %u\n", i, got[i], want[i]); break; }
        } else {
            check(1, "");
        }
    }
}

static void test_formats_map(void) {
    unsigned pf; int bpp;
    struct { uint32_t fmt; unsigned pf; int bpp; } cases[] = {
        { 0x41, 70, 4 }, { 0x42, 70, 4 }, { 0x43, 70, 4 }, { 0x44, 70, 4 }, { 0x4d, 70, 4 },
        { 0x45, 71, 4 }, { 0x46, 71, 4 }, { 0x47, 71, 4 }, { 0x48, 71, 4 }, { 0x4e, 71, 4 },
        { 0x49, 10, 1 }, { 0x4a, 12, 1 }, { 0x4b, 30, 2 }, { 0x4c, 32, 2 },
        { 0x4f, 115, 8 }, { 0x50, 115, 8 },
    };
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        check(nvn_bc_unpacked(cases[i].fmt, &pf, &bpp) == 1, "format is recognised as BC");
        check(pf == cases[i].pf && bpp == cases[i].bpp, "format maps to the expected pixel format");
    }
    check(nvn_bc_unpacked(0x25, &pf, &bpp) == 0, "a non-BC format is rejected");
}

static void test_edge_blocks_trimmed(void) {
    // A 6x3 image: blocks at x=4 and y=0 are partial. Decoding must write only real pixels,
    // and the sentinel after the last row must survive (nothing written past the height).
    // 6 pixels wide = two 4-pixel blocks per block row, so the source needs two blocks and a
    // pitch of 2 * 8 bytes. (Passing one block made the second one read past the array.)
    unsigned char blk[2][8] = {
        { 0x00, 0xF8, 0xE0, 0x07, 0x1B, 0x36, 0x6C, 0xD8 },
        { 0xE0, 0x07, 0x1F, 0x00, 0x1B, 0x36, 0x6C, 0xD8 },
    };
    enum { W = 6, H = 3 };
    unsigned char out[H * W * 4 + 64];
    memset(out, 0xAB, sizeof out);
    int r = nvn_bc_decode(0x41, (const unsigned char *)blk, 16, W, H, out, W * 4);
    check(r == 0, "partial-block decode returns 0");
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            const unsigned char *p = out + y * W * 4 + x * 4;
            check(p[3] == 255, "RGB_DXT1 decodes every pixel opaque");
        }
    for (unsigned i = H * W * 4; i < sizeof out; i++)
        if (out[i] != 0xAB) { check(0, "nothing is written past the last row"); break; }
}

static void test_bc4_single_channel(void) {
    // BC4 stores one channel; the unpacked format is R8, so bytes 1..3 of each pixel stay as the
    // caller left them (tex_mtl fills alpha itself). Check the red channel varies with the block.
    unsigned char blk[8] = { 0xFF, 0x00, 0, 0, 0, 0, 0, 0 };   // endpoints 255 and 0
    // BC4 decodes to R8: one byte per pixel, dpitch = 4 for a 4-pixel row.
    unsigned char out[4 * 4];
    memset(out, 0xCC, sizeof out);
    int r = nvn_bc_decode(0x49, blk, 8, 4, 4, out, 4);   // 0x49 = BC4 unsigned
    check(r == 0, "bc4 decode returns 0");
    int uniform = 1;
    for (int i = 0; i < 16; i++) if (out[i] != 255) uniform = 0;
    check(uniform, "bc4 decodes the whole block to the endpoint value");
    check(out[1 + 4] == 255, "bc4 writes every row (not just the first)");
}


// ---- BC6H into RGB9E5 (DM_BC6H_RGB9E5): the same block through both paths, and the packing against an independent decode ----
#include <math.h>
static float ref_half(unsigned short h) {   // textbook half to float
    int s = h >> 15, e = (h >> 10) & 31, m = h & 1023;
    float v = e == 0 ? m / 1024.0f / 16384.0f : (1 + m / 1024.0f) * powf(2, (float)(e - 15));
    return s ? -v : v;
}
static float ref_rgb9e5(unsigned v, int ch) { return (float)((v >> (9 * ch)) & 511) * powf(2, (float)((int)(v >> 27) - 24)); }
static void test_rgb9e5_pack(void) {
    unsigned one = nvn_rgb9e5_pack(1, 1, 1);
    check(ref_rgb9e5(one, 0) == 1 && ref_rgb9e5(one, 1) == 1 && ref_rgb9e5(one, 2) == 1, "1.0 round-trips");
    unsigned v = nvn_rgb9e5_pack(0.5f, 0.25f, 4.0f);
    check(fabsf(ref_rgb9e5(v, 0) - 0.5f) < 0.5f / 256 && fabsf(ref_rgb9e5(v, 1) - 0.25f) < 0.25f / 256 && fabsf(ref_rgb9e5(v, 2) - 4.0f) < 4.0f / 256, "values round-trip inside the 9-bit mantissa");
    check(nvn_rgb9e5_pack(-1, NAN, 0) == 0, "negative, NaN and zero pack as zero");
    unsigned big = nvn_rgb9e5_pack(1e9f, 0, 0);
    check(ref_rgb9e5(big, 0) <= 65408.0f && ref_rgb9e5(big, 0) > 65000.0f, "out-of-range clamps to the largest value");
}
static void test_bc6h_rgb9e5_switch(void) {
    unsigned pf; int bpp;
    unsigned char blk[16] = { 0x03, 0x20, 0x40, 0x61, 0x82, 0xA3, 0xC4, 0xE5, 0x16, 0x27, 0x38, 0x49, 0x5A, 0x6B, 0x7C, 0x8D };
    unsigned short half[16 * 4]; unsigned wide[16];
    nvn_bc_set_bc6h_rgb9e5(0);
    check(nvn_bc_unpacked(0x50, &pf, &bpp) == 1 && pf == 115 && bpp == 8, "off: RGBA16Float, 8 bytes per pixel (the tested default)");
    check(nvn_bc_decode(0x50, blk, 16, 4, 4, (unsigned char *)half, 4 * 8) == 0, "RGBA16F decode");
    nvn_bc_set_bc6h_rgb9e5(1);
    check(nvn_bc_bc6h_rgb9e5() == 1, "the switch reads back");
    check(nvn_bc_unpacked(0x50, &pf, &bpp) == 1 && pf == 93 && bpp == 4, "on: RGB9E5Float, 4 bytes per pixel");
    check(nvn_bc_unpacked(0x4f, &pf, &bpp) == 1 && pf == 93 && bpp == 4, "signed BC6H too");
    check(nvn_bc_unpacked(0x41, &pf, &bpp) == 1 && pf == 70 && bpp == 4, "other BC formats are untouched");
    check(nvn_bc_decode(0x50, blk, 16, 4, 4, (unsigned char *)wide, 4 * 4) == 0, "RGB9E5 decode");
    for (int i = 0; i < 16; i++) {
        unsigned want = nvn_rgb9e5_pack(ref_half(half[i * 4]), ref_half(half[i * 4 + 1]), ref_half(half[i * 4 + 2]));
        check(wide[i] == want, "each pixel is the RGBA16F pixel packed as RGB9E5");
    }
    unsigned char edge[3 * 3 * 4 + 16]; memset(edge, 0xAB, sizeof edge);
    check(nvn_bc_decode(0x50, blk, 16, 3, 3, edge, 3 * 4) == 0, "an edge block");
    for (unsigned i = 3 * 3 * 4; i < sizeof edge; i++) check(edge[i] == 0xAB, "nothing is written past the trimmed block");
    nvn_bc_set_bc6h_rgb9e5(0);
}

__attribute__((noinline))
static void decode_edge_with_odd_stack(int pad_byte, uint32_t fmt, const unsigned char *blk, int bpp) {
    volatile char odd[3] = { (char)pad_byte, 1, 2 };
    (void)odd;
    _Alignas(8) unsigned char dst[3 * 3 * 8];
    memset(dst, 0xCD, sizeof dst);
    check(nvn_bc_decode(fmt, blk, fmt == 0x41 ? 8 : 16, 3, 3, dst, (size_t)(3 * bpp)) == 0, "edge decode stays aligned across stack layouts");
}

static void test_edge_tmp_alignment(void) {
    unsigned char blk8[8] = { 0x00, 0xf8, 0xe0, 0x07, 0xaa, 0x55, 0x00, 0xff };
    unsigned char blk16[16] = { 0x03, 0x20, 0x40, 0x61, 0x82, 0xA3, 0xC4, 0xE5, 0x16, 0x27, 0x38, 0x49, 0x5A, 0x6B, 0x7C, 0x8D };
    nvn_bc_set_bc6h_rgb9e5(0);
    decode_edge_with_odd_stack(7, 0x41, blk8, 4);
    decode_edge_with_odd_stack(7, 0x4d, blk16, 4);
    decode_edge_with_odd_stack(7, 0x50, blk16, 8);
    nvn_bc_set_bc6h_rgb9e5(1);
    decode_edge_with_odd_stack(7, 0x50, blk16, 4);
    nvn_bc_set_bc6h_rgb9e5(0);
}

int main(void) {
    test_bc1_matches_reference();
    test_formats_map();
    test_edge_blocks_trimmed();
    test_bc4_single_channel();
    test_rgb9e5_pack();
    test_bc6h_rgb9e5_switch();
    test_edge_tmp_alignment();
    if (failures) { printf("%d check(s) failed\n", failures); return 1; }
    printf("bc decode: BC1 matches an independent DXT1 decoder, format map, edge trimming, BC4 - all OK\n");
    return 0;
}
