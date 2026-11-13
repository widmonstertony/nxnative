#pragma once
#include <stddef.h>
#include <stdint.h>
#include <TargetConditionals.h>
#import <Metal/Metal.h>
#include "nvn_deswizzle.h"

int nvn_deswz_gpu_init(id<MTLDevice> dev);
// Small RGBA16F arrays: write raw component bits through an integer texture
// view, across all layers in one dispatch per mip (no per-face staging/copies).
int nvn_deswz_gpu_direct_supported(const nvn_texdesc *d);
#if TARGET_OS_OSX || defined(DM_NVN_MODERN_RENDERER)
int nvn_deswz_gpu_direct_m4(id<MTL4ComputeCommandEncoder> enc, id<MTL4ArgumentTable> table,
                            id<MTLBuffer> params, size_t params_off, id<MTLBuffer> src, uint64_t src_off,
                            const nvn_texdesc *d, unsigned level, id<MTLTexture> uint_view);
#endif
int nvn_deswz_gpu_encode(id<MTLComputeCommandEncoder> enc, id<MTLBuffer> src, uint64_t src_off,
                         const nvn_texdesc *d, unsigned level, unsigned layer,
                         id<MTLBuffer> dst, uint64_t dst_off, size_t dst_pitch);
#if TARGET_OS_OSX || defined(DM_NVN_MODERN_RENDERER)
int nvn_deswz_gpu_encode_m4(id<MTL4ComputeCommandEncoder> enc, id<MTL4ArgumentTable> table,
                            id<MTLBuffer> params, size_t params_off, id<MTLBuffer> src, uint64_t src_off,
                            const nvn_texdesc *d, unsigned level, unsigned layer,
                            id<MTLBuffer> dst, uint64_t dst_off, size_t dst_pitch);
#endif
