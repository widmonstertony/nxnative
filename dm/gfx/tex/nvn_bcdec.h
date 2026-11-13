// 不支持 BC 压缩格式的显卡（A15 / A16 等，苹果 GPU 族 Apple8 及以下）：BC 贴图在 CPU 上解压成不压缩格式。
// 游戏贴图里的 BC3 由老机型补充包离线换成 ASTC（dm/tools/astc_pack.py）；剩下的 BC（精灵图里的 BC3、少量 BC1 / BC4 / BC5 / BC6H）走这里。
// GPUs without BC compressed format support (A15 / A16 etc., Apple GPU family Apple8 and below): BC textures are decompressed on the CPU into uncompressed formats.
// BC3 in game textures is converted offline to ASTC by the Legacy Device Pack (dm/tools/astc_pack.py); the remaining BC (BC3 in sprites, a few BC1 / BC4 / BC5 / BC6H) goes through here.
#pragma once
#include <stddef.h>
#include <stdint.h>

// NVN 格式是 BC → 返回 1，*mtl_pf = 解压后的 Metal 像素格式、*bpp = 解压后每像素字节；不是 BC 返回 0
// NVN format is BC → returns 1, *mtl_pf = Metal pixel format after decompression, *bpp = bytes per pixel after decompression; returns 0 if not BC
int nvn_bc_unpacked(uint32_t nvn_fmt, uint32_t *mtl_pf, int *bpp);
// 解一片 w×h 像素：src 按块行排（每块行 pitch 字节），dst 每像素行 dpitch 字节。成功 0
// Decode a w×h pixel region: src is laid out by block rows (pitch bytes per block row), dst has dpitch bytes per pixel row. Returns 0 on success
int nvn_bc_decode(uint32_t nvn_fmt, const uint8_t *src, size_t pitch, uint32_t w, uint32_t h, uint8_t *dst, size_t dpitch);
// BC6H 的 HDR 贴图：默认解成 RGBA16Float（每像素 8 字节）；打开后解成 RGB9E5Float（每像素 4 字节），内存减半，代价是：无符号 5 位指数 9 位尾数的共享指数，负值截为 0，精度略低。DM_BC6H_RGB9E5=1 打开。
// BC6H (HDR) textures decode into RGBA16Float by default (8 bytes per pixel). Switched on they decode into RGB9E5Float (4 bytes per pixel), which halves their memory: the exponent is shared and unsigned,
// so negative values become 0 and the mantissa is 9 bits. Set before the first texture is made (DM_BC6H_RGB9E5=1); it changes what nvn_bc_unpacked answers for 0x4f / 0x50.
void nvn_bc_set_bc6h_rgb9e5(int on);
int nvn_bc_bc6h_rgb9e5(void);
// One RGB triple packed as RGB9E5 (the shared-exponent format of Metal's RGB9E5Float): negative, NaN and out-of-range inputs clamp.
uint32_t nvn_rgb9e5_pack(float r, float g, float b);
