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

int main(void) { @autoreleasepool {
    mtl_init();
    CHECK(wrapm(NVN_WRAP_MODE_CLAMP_TO_BORDER, YES) == MTLSamplerAddressModeClampToZero,
        "transparent border selects clamp-to-zero on older hardware");
    CHECK(wrapm(NVN_WRAP_MODE_CLAMP_TO_BORDER, NO) == MTLSamplerAddressModeClampToBorderColor,
        "hardware border path still uses clamp-to-border-color");
    encoded_border();
    printf("t_legacy_border: %d checks, %d failed\n",checks,fails);
    return fails != 0;
} }
