// Exercise border sampling through the legacy host's argument encoder.
#define DM_NVN_LEGACY_RENDERER_TEST 1
#include "../nvn/nvn_mtl.m"

uint64_t g_t0_ns;
int dm_guest_as_contains(uintptr_t address) { (void)address; return 0; }
int front_screen_max_fps(void) { return 60; }
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod;
int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, fails;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; fprintf(stderr, "FAIL: "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } } while (0)

// Exercise production encode_args_, not just manually filled argument slots.
// Changing the registry after encode must not retire the in-flight twin.
static void encoded_border(void) {
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "struct B { uint mask; float4 k[32]; };\n"
        "struct A { sampler s [[id(0)]]; sampler w [[id(1)]]; constant B* b [[id(2)]]; };\n"
        "kernel void sample_border(constant A& a [[buffer(0)]], device float4* o [[buffer(1)]], texture2d<float> t [[texture(0)]]) {\n"
        " float2 uv(-1.0); float4 n=t.sample(a.s,uv); if(a.b->mask&1u) n+=(t.sample(a.w,uv)-n)*a.b->k[0]; o[0]=n;"
        " o[1]=t.sample(a.s,float2(.5)); }\n";
    NSError *error = nil;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:source options:nil error:&error];
    id<MTLFunction> fn = [lib newFunctionWithName:@"sample_border"];
    id<MTLComputePipelineState> pipeline = fn ? [g_dev newComputePipelineStateWithFunction:fn error:&error] : nil;
    CHECK(pipeline != nil, "production border test compiles: %s", error.localizedDescription.UTF8String);
    if (!pipeline) return;
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    td.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [g_dev newTextureWithDescriptor:td];
    uint32_t pixel = 0xffffffff; [texture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&pixel bytesPerRow:4];
    BOOL native_border = g_sampler_border_color;
    for (int private_encoder = 0; private_encoder < 2; private_encoder++) {
        g_legacy_direct_arguments = !private_encoder;
        for (int variant = 0; variant < 3; variant++) {
            BOOL corrected = variant == 1, zero_border = variant == 2;
            g_sampler_border_color = native_border && !zero_border;
            samp_par sp = {0}; sp.magf=sp.minf=1; sp.ws=sp.wt=sp.wr=5;
            float colour[4]={.25,.5,.75,1};
            if (corrected) memcpy(sp.border,colour,sizeof colour);
            else if (!zero_border) sp.border[3]=1;
            mtl_reg_samp(31,&sp);
            NvShader *sh=[NvShader new]; sh->fn=fn; sh->stage=5; strcpy(sh->key,"border-test");
            sh->ae=[fn newArgumentEncoderWithBufferIndex:0]; sh->arg_len=sh->ae.encodedLength;
            sh->rf.nb=3; sh->rf.border=3; sh->rf.abi=0;
            sh->rf.b[0]=(nvn_rbind){.kind=NVN_RB_SAMPI,.aid=0,.reg=31};
            sh->rf.b[1]=(nvn_rbind){.kind=NVN_RB_SAMPI,.aid=1,.reg=31,.bw=1};
            sh->rf.b[2]=(nvn_rbind){.kind=NVN_RB_BORDER,.aid=2};
            arena_begin(); g_sub_samplers=[NSMutableSet set]; args_dirty_all();
            id<MTLBuffer> result=[g_dev newBufferWithLength:32 options:MTLResourceStorageModeShared];
            id<MTLCommandBuffer> cb=q_cb(); id<MTLComputeCommandEncoder> encoder=[cb computeCommandEncoder];
            [encoder setComputePipelineState:pipeline];
            int encoded=encode_args_(encoder,sh,5,0);
            CHECK(encoded,"production argument encoding succeeds");
            if (!encoded) { [encoder endEncoding]; continue; }
            CHECK(g_sub_samplers.count >= (corrected ? 2u : 1u), "referenced samplers retained");
            id<MTLSamplerState> prior=corrected ? (__bridge id)g_sview_w[31] : (__bridge id)g_sview[31];
            CHECK([g_sub_samplers containsObject:prior],"actual in-flight sampler retained");
            sp.border[0]=sp.border[1]=sp.border[2]=sp.border[3]=1;
            mtl_reg_samp(31,&sp);
            CHECK(!g_sview_w[31] && !g_srid_w[31],"replacement drops registry twin");
            CHECK([g_sub_samplers containsObject:prior],"replacement preserves submission lifetime");
            [encoder setTexture:texture atIndex:0]; [encoder useResource:texture usage:MTLResourceUsageRead];
            [encoder setBuffer:result offset:0 atIndex:1];
            [encoder dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
            [encoder endEncoding]; [cb commit]; [cb waitUntilCompleted];
            CHECK(cb.status==MTLCommandBufferStatusCompleted,"production border dispatch completed");
            const float *values=result.contents;
            for (int c = 0; c < 4; c++) {
                float expected = corrected ? colour[c] : c == 3 && !zero_border ? 1.f : 0.f;
                CHECK(fabsf(values[c] - expected) < .006f,
                    "encoding=%d variant=%d channel=%d outside=%g", private_encoder, variant, c, values[c]);
                CHECK(fabsf(values[c + 4] - 1.f) < .006f,
                    "encoding=%d variant=%d channel=%d inside=%g", private_encoder, variant, c, values[c + 4]);
            }
        }
    }
    g_sampler_border_color = native_border;
}

static void check_pool_views(BOOL apple3) {
    int native = g_bare_native;
    if (apple3) g_bare_native = 0;
    const size_t stride = pool_window_granule(), span = 3 * stride;
    uint8_t *page = mmap(NULL, span, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    CHECK(page != MAP_FAILED, "allocate pool test pages");
    if (page == MAP_FAILED) { g_bare_native = native; return; }

    int count = g_npool;
    uintptr_t lo = (uintptr_t)page, boundary = (lo + stride - 1) & ~(stride - 1);
    boundary += stride;
    if (apple3) {
        // The crash occurs below the individual Metal buffer limit.
        CHECK(span < g_dev.maxBufferLength, "Apple3 pool is below the device's single-buffer limit");
        mtl_pool_add(page + 1, span - 2);
        CHECK(g_nlarge == 1 && g_npool == count, "register the Apple3 pool without creating a Metal buffer");
    } else {
        // Exercise a logical registration on a Mac without allocating the
        // multi-gigabyte region needed to trigger its true length limit.
        g_large_pools = legacy_grow(g_large_pools, sizeof *g_large_pools);
        g_large_pools[0] = (pool_span){lo + 1, lo + span - 1};
        g_nlarge = g_large_cap = 1;
    }
    CHECK(mtl_addr_known(boundary - 8, 16) && g_npool == count,
          "address query does not create a buffer");

    void *first = NULL, *crossing = NULL;
    uint64_t offset = 0;
    CHECK(mtl_addr(boundary - 8, 1, &first, &offset) && first != NULL,
          "map address in first window");
    nvn_dirty_add_range(page, span);
    uint64_t tracked = nvn_dirty_now();
    nvn_dirty_protect((void *)boundary, (size_t)getpagesize());
    CHECK(mtl_addr(boundary - 8, 16, &crossing, &offset) && crossing != NULL && crossing != first,
          "binding crossing a window gets a contiguous view");
    CHECK(nvn_dirty_since((void *)boundary, 1, tracked),
          "lazy buffer opens a tracked page before the GPU can write it");
    if (crossing) {
        id<MTLBuffer> window = (__bridge id<MTLBuffer>)crossing;
        uint8_t *bytes = window.contents;
        for (unsigned n = 0; n < 16; n++) bytes[offset + n] = (uint8_t)(0x4b + n);
        CHECK(*(uint8_t *)(boundary + 7) == 0x5a, "window aliases guest pages");
        id<MTLBuffer> copy = [g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cb = q_cb();
        id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
        [blit copyFromBuffer:window sourceOffset:offset toBuffer:copy destinationOffset:0 size:16];
        [blit fillBuffer:window range:NSMakeRange(offset, 16) value:0x6b];
        [blit endEncoding]; [cb commit]; [cb waitUntilCompleted];
        CHECK(cb.status == MTLCommandBufferStatusCompleted && ((const uint8_t *)copy.contents)[0] == 0x4b &&
              ((const uint8_t *)copy.contents)[15] == 0x5a,
              "GPU reads both sides of the window boundary");
        CHECK(*(uint8_t *)(boundary - 8) == 0x6b && *(uint8_t *)(boundary + 7) == 0x6b,
              "GPU writes across the window boundary after a tracked page was protected");
    }
    CHECK(!mtl_addr(lo + span - 2, 2, &crossing, &offset), "logical end excludes padding");
    CHECK(!mtl_addr(UINT64_MAX - 1, 4, &crossing, &offset), "overflowing range is rejected");
    mtl_pool_del(page + 1);
    CHECK(!mtl_addr_known(boundary - 8, 1) && !mtl_addr(boundary - 8, 1, &first, &offset),
          "finalizing the pool invalidates every window and cached lookup");
    CHECK(g_npool == count && g_nlarge == 0, "no registered window remains");
    // Advance past the queued buffer retirements before unmapping their storage.
    uint64_t done = g_done;
    g_done = g_fence + 1;
    defer_drain();
    g_done = done;
    nvn_dirty_remove_range(page);
    munmap(page, span);
    g_bare_native = native;
}

int main(void) { @autoreleasepool {
    mtl_init();
    check_pool_views(NO);
    check_pool_views(YES);
    CHECK(wrapm(NVN_WRAP_MODE_CLAMP_TO_BORDER, YES) == MTLSamplerAddressModeClampToZero,
        "transparent border selects clamp-to-zero on older hardware");
    CHECK(wrapm(NVN_WRAP_MODE_CLAMP_TO_BORDER, NO) == MTLSamplerAddressModeClampToBorderColor,
        "hardware border path still uses clamp-to-border-color");
    encoded_border();
    printf("t_legacy_border: %d checks, %d failed\n",checks,fails);
    return fails != 0;
} }
