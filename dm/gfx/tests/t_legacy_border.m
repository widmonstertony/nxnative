// Run the same sampler registry and real GPU border checks on the legacy host.
#define DM_NVN_LEGACY_RENDERER_TEST 1
#define main border_registry_main
#include "t_border.m"
#undef main

// Exercise production encode_args_, not just manually filled argument slots.
// Changing the registry after encode must not retire the in-flight twin.
static void encoded_border(void) {
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "struct B { uint mask; float4 k[32]; };\n"
        "struct A { sampler s [[id(0)]]; sampler w [[id(1)]]; constant B* b [[id(2)]]; };\n"
        "kernel void sample_border(constant A& a [[buffer(0)]], device float4* o [[buffer(1)]], texture2d<float> t [[texture(0)]]) {\n"
        " float2 uv(-1.0); float4 n=t.sample(a.s,uv); if(a.b->mask&1u) n+=(t.sample(a.w,uv)-n)*a.b->k[0]; o[0]=n; }\n";
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
    for (int private_encoder = 0; private_encoder < 2; private_encoder++) {
        g_legacy_direct_arguments = !private_encoder;
        for (int corrected = 0; corrected < 2; corrected++) {
            samp_par sp = {0}; sp.magf=sp.minf=1; sp.ws=sp.wt=sp.wr=5;
            float colour[4]={.25,.5,.75,1};
            if (corrected) memcpy(sp.border,colour,sizeof colour); else sp.border[3]=1;
            mtl_reg_samp(31,&sp);
            NvShader *sh=[NvShader new]; sh->fn=fn; sh->stage=5; strcpy(sh->key,"border-test");
            sh->ae=[fn newArgumentEncoderWithBufferIndex:0]; sh->arg_len=sh->ae.encodedLength;
            sh->rf.nb=3; sh->rf.border=3; sh->rf.abi=0;
            sh->rf.b[0]=(nvn_rbind){.kind=NVN_RB_SAMPI,.aid=0,.reg=31};
            sh->rf.b[1]=(nvn_rbind){.kind=NVN_RB_SAMPI,.aid=1,.reg=31,.bw=1};
            sh->rf.b[2]=(nvn_rbind){.kind=NVN_RB_BORDER,.aid=2};
            arena_begin(); g_sub_samplers=[NSMutableArray array]; args_dirty_all();
            id<MTLBuffer> result=[g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared];
            id<MTLCommandBuffer> cb=q_cb(); id<MTLComputeCommandEncoder> encoder=[cb computeCommandEncoder];
            [encoder setComputePipelineState:pipeline];
            int encoded=encode_args_(encoder,sh,5,0);
            CHECK(encoded,"production argument encoding succeeds");
            if (!encoded) { [encoder endEncoding]; continue; }
            CHECK(g_sub_samplers.count>=2,"both referenced samplers retained");
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
            for(int c=0;c<4;c++) CHECK(fabsf(values[c]-(corrected?colour[c]:(c==3?1.f:0.f)))<.006f,
                "encoding=%d corrected=%d channel=%d got=%g",private_encoder,corrected,c,values[c]);
        }
    }
}

int main(int argc,char **argv) { @autoreleasepool {
    int status=border_registry_main(argc,argv);
    encoded_border();
    printf("t_legacy_border: %d checks, %d failed\n",checks,fails);
    return status || fails;
} }
