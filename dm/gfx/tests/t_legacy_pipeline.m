// An unwritten second blend source uses zero; compare the folded descriptor with a shader that explicitly writes that zero.
#define DM_NVN_LEGACY_RENDERER_TEST 1
#include "../nvn/nvn_mtl.m"

uint64_t g_t0_ns;
int dm_guest_as_contains(uintptr_t p) { (void)p; return 0; }
int front_screen_max_fps(void) { return 60; }
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(c, label) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)

static void pixels(id<MTLRenderPipelineState> ps, __fp16 out[4]) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:4 height:4 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModeShared;
    id<MTLTexture> t = [g_dev newTextureWithDescriptor:td];
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(.75, .5, .25, .875); rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLCommandQueue> q = [g_dev newCommandQueue]; id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    [e setRenderPipelineState:ps]; [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [e endEncoding];
    [cb commit]; [cb waitUntilCompleted]; CHECK(cb.status == MTLCommandBufferStatusCompleted, "blend draw completes");
    [t getBytes:out bytesPerRow:32 fromRegion:MTLRegionMake2D(1,1,1,1) mipmapLevel:0];
}

int main(int argc, char **argv) { @autoreleasepool {
    mtl_init(); NSError *error = nil;
    NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "vertex float4 v(uint i [[vertex_id]]) { return float4(i == 1 ? 3.0 : -1.0, i == 2 ? 3.0 : -1.0, 0, 1); }\n"
        "fragment float4 f() { return float4(.125,.25,.5,.375); }\n"
        "struct O { float4 a [[color(0)]]; float4 b [[color(0), index(1)]]; };\n"
        "fragment O f2() { return {float4(.125,.25,.5,.375), float4(0)}; }\n";
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:src options:nil error:&error];
    CHECK(lib != nil, "reference shaders compile"); if (!lib) return 1;
    NvShader *vs = [NvShader new], *fs = [NvShader new];
    vs->fn = [lib newFunctionWithName:@"v"];
    fs->fn = [lib newFunctionWithName:@"f"];
    fs->rf.color_known = 1; fs->rf.color_mask = 1;
    pso_key k = {0}; k.samples = 1; k.chmask = 15; k.blend_en = 1; k.cfmt[0] = MTLPixelFormatRGBA16Float;
    int factors[] = {NVN_BLEND_FUNC_SRC1_COLOR, NVN_BLEND_FUNC_ONE_MINUS_SRC1_COLOR, NVN_BLEND_FUNC_SRC1_ALPHA, NVN_BLEND_FUNC_ONE_MINUS_SRC1_ALPHA};
    for (int i = 0; i < 4; i++) {
        k.blend[0] = (blend_st){.src_rgb=factors[i], .dst_rgb=factors[(i+1)%4], .src_a=factors[(i+2)%4], .dst_a=factors[(i+3)%4], .eq_rgb=1, .eq_a=1};
        MTLRenderPipelineDescriptor *d = pso_desc(&k, vs, fs, nil, 0);
        CHECK(d.colorAttachments[0].blendingEnabled, "blending remains enabled");
        MTLRenderPipelineDescriptor *ref = [d copy]; ref.fragmentFunction = [lib newFunctionWithName:@"f2"];
        ref.colorAttachments[0].sourceRGBBlendFactor = bfac(k.blend[0].src_rgb); ref.colorAttachments[0].destinationRGBBlendFactor = bfac(k.blend[0].dst_rgb);
        ref.colorAttachments[0].sourceAlphaBlendFactor = bfac(k.blend[0].src_a); ref.colorAttachments[0].destinationAlphaBlendFactor = bfac(k.blend[0].dst_a);
        id<MTLRenderPipelineState> reference = [g_dev newRenderPipelineStateWithDescriptor:ref error:&error];
        CHECK(reference != nil, "explicit secondary source compiles");
        __fp16 want[4]; if (reference) pixels(reference, want);
        for (int metal4 = 0; metal4 < 2; metal4++) {
            id<MTLRenderPipelineState> ps = metal4 ? pso_build(&k, vs, fs, nil, 0, 0, &error) : [g_dev newRenderPipelineStateWithDescriptor:d error:&error];
            CHECK(ps != nil, "folded pipeline compiles on both paths");
            if (ps && reference) { __fp16 got[4]; pixels(ps, got); CHECK(!memcmp(want, got, sizeof got), "folded blending equals explicit zero source"); }
        }
    }
    fs->rf.color_mask = 3;
    CHECK(pso_desc(&k, vs, fs, nil, 0).colorAttachments[0].sourceRGBBlendFactor == bfac(k.blend[0].src_rgb), "written secondary output is preserved");
    fs->rf.color_mask = 1; fs->rf.color_known = 0;
    CHECK(pso_desc(&k, vs, fs, nil, 0).colorAttachments[0].sourceRGBBlendFactor == bfac(k.blend[0].src_rgb), "unknown output map is preserved");
    // A written source 1 must use the alternate entry on either compiler path.
    NSString *dualSource = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "struct O { float4 a [[color(0)]]; float4 b [[color(1)]]; };\n"
        "struct D { float4 a [[color(0)]]; float4 b [[color(0), index(1)]]; };\n"
        "fragment O mrt() { return {float4(.125,.25,.5,.375), float4(.25,.5,.75,.625)}; }\n"
        "fragment D dual() { return {float4(.125,.25,.5,.375), float4(.25,.5,.75,.625)}; }\n";
    id<MTLLibrary> dl = [g_dev newLibraryWithSource:dualSource options:nil error:&error];
    CHECK(dl != nil, "dual-source and MRT entries compile together");
    fs->fn = [dl newFunctionWithName:@"mrt"];
    fs->fn_d = [dl newFunctionWithName:@"dual"];
    fs->rf.color_known = 1; fs->rf.color_mask = 3; fs->has_dual = 1;
    for (int i = 0; i < 4; i++) {
        k.blend[0] = (blend_st){.src_rgb=factors[i], .dst_rgb=NVN_BLEND_FUNC_ONE, .src_a=factors[i], .dst_a=NVN_BLEND_FUNC_ONE, .eq_rgb=1, .eq_a=1};
        MTLRenderPipelineDescriptor *d = pso_desc(&k, vs, fs, nil, 0);
        CHECK(d.fragmentFunction == fs->fn_d, "SRC1 pipeline selects the dual-source entry");
        for (int metal4 = 0; metal4 < 2; metal4++) {
            id<MTLRenderPipelineState> ps = metal4 ? pso_build(&k, vs, fs, nil, 0, 0, &error) : [g_dev newRenderPipelineStateWithDescriptor:d error:&error];
            CHECK(ps != nil, "written secondary source compiles on both paths");
            if (ps) {
                __fp16 got[4]; pixels(ps, got);
                float src[4]={.125,.25,.5,.375}, secondary[4]={.25,.5,.75,.625}, dst[4]={.75,.5,.25,.875};
                for (int c=0;c<4;c++) {
                    float factor = (i<2 && c<3) ? secondary[c] : secondary[3];
                    if (i&1) factor = 1-factor;
                    CHECK(fabsf((float)got[c] - (dst[c]+src[c]*factor)) < .001, "actual secondary color/alpha reaches the blend unit");
                }
            }
        }
    }
    k.blend_en = 0; k.cfmt[1] = MTLPixelFormatRGBA16Float; k.chmask = 255;
    MTLRenderPipelineDescriptor *mrt = pso_desc(&k, vs, fs, nil, 0);
    CHECK(mrt.fragmentFunction == fs->fn, "ordinary MRT keeps the original entry");
    CHECK(mrt.colorAttachments[1].writeMask == MTLColorWriteMaskAll, "ordinary MRT keeps output 1 writable");
    CHECK([g_dev newRenderPipelineStateWithDescriptor:mrt error:&error] != nil, "ordinary MRT pipeline compiles");
    CHECK(pso_build(&k, vs, fs, nil, 0, 0, &error) != nil, "ordinary MRT compiles on Metal 4");
    k.blend_en = 1;
    CHECK(pso_desc(&k, vs, fs, nil, 0).colorAttachments[1].pixelFormat == MTLPixelFormatInvalid, "dual source omits MRT 1 from the physical pipeline");
    MTLRenderPipelineDescriptor *boundMRT = pso_desc(&k, vs, fs, nil, 0);
    CHECK([g_dev newRenderPipelineStateWithDescriptor:boundMRT error:&error] != nil, "dual source permits a bound unwritten MRT 1 on Metal");
    CHECK(pso_build(&k, vs, fs, nil, 0, 0, &error) != nil, "dual source permits a bound unwritten MRT 1 on Metal 4");
    // Replay real NVN draws while both guest targets remain bound. Switching blend modes
    // must split physical passes, retain clears, and restore normal output 1.
    if (!getenv("DM_NVN_TBDR")) setenv("DM_NVN_TBDR", "0", 1); setenv("DM_PSO_HYBRID", "0", 1);
    tex_t targets[2] = {0}; id<MTLTexture> textures[2];
    for (int i=0;i<2;i++) {
        targets[i].magic=MAGIC('T','E','X',0); targets[i].serial=99501+i;
        targets[i].d=(nvn_texdesc){.target=NVN_TEXTURE_TARGET_2D,.format=NVN_FORMAT_RGBA16F,.width=4,.height=4,.depth=1,.levels=1,.samples=1};
        MTLTextureDescriptor *td=tex_desc(&targets[i],0); td.storageMode=MTLStorageModeShared;
        textures[i]=[g_dev newTextureWithDescriptor:td]; res_add(textures[i]); mtl_tex_init(&targets[i]); serial_put(targets[i].serial,textures[i]);
    }
    NvProg *program=[NvProg new]; program->sh[0]=vs;program->sh[1]=fs;
    prog_t guestProgram={.serial=99500}; serial_put(guestProgram.serial,program);
    state_reset(); memset(&R,0,sizeof R); S.prog=&guestProgram; S.chmask.mask=255;
    S.poly.cull=NVN_FACE_NONE; S.poly.mode=NVN_POLYGON_MODE_FILL;
    S.blend[0]=(blend_st){.src_rgb=NVN_BLEND_FUNC_SRC1_COLOR,.dst_rgb=NVN_BLEND_FUNC_ONE,.src_a=NVN_BLEND_FUNC_SRC1_ALPHA,.dst_a=NVN_BLEND_FUNC_ONE,.eq_rgb=1,.eq_a=1};
    R.has_rt=1;R.rt.n=2;R.rt.color[0]=&targets[0];R.rt.color[1]=&targets[1];
    R.clear_c[0]=R.clear_c[1]=1;R.cc[0]=MTLClearColorMake(.75,.5,.25,.875);R.cc[1]=MTLClearColorMake(.2,.3,.4,.5);
    p_draw triangle={.prim=NVN_DRAW_PRIMITIVE_TRIANGLES,.count=3,.instances=1};
    for (int phase=0;phase<3;phase++) {
        S.color.blend_en=phase==1?0:1;g_pso_dirty=g_dss_dirty=1;
        mtl_sub_begin();draw(&triangle,NULL);
        CHECK(g_enc_dual==(phase!=1), "production draw picks the matching physical pass");
        CHECK((g_pass.cfmt[1]!=0)==(phase==1), "ordinary MRT target is restored only when written");
        mtl_sub_commit();mtl_drain();CHECK(!mtl_last_commit_error(), "production dual/MRT draw completes without validation error");
        __fp16 second[4];[textures[1] getBytes:second bytesPerRow:32 fromRegion:MTLRegionMake2D(1,1,1,1) mipmapLevel:0];
        float clear[4]={.2,.3,.4,.5},written[4]={.25,.5,.75,.625};
        for(int c=0;c<4;c++) CHECK(fabsf((float)second[c]-(phase==0?clear[c]:written[c]))<.001, "secondary target clear/write survives dual-source transitions");
    }
    mtl_sub_begin();
    for(int phase=0;phase<3;phase++) {
        uint64_t before=g_pass.serial;
        S.color.blend_en=phase==1?1:0;g_pso_dirty=g_dss_dirty=1;draw(&triangle,NULL);
        CHECK(g_pass.serial>before, "changing dual-source mode splits the physical pass within one submission");
        CHECK(g_enc_dual==(phase==1), "same-submission transition chooses the correct attachment layout");
    }
    mtl_sub_commit();mtl_drain();CHECK(!mtl_last_commit_error(), "same-submission dual/MRT transitions complete");
    S.color.blend_en=1;uint8_t map[8]={0};id<MTLFunction> tile=fs->fn;
    CHECK(!fz_p2_draw(program,&triangle,NULL,map,&tile), "tile-fetch planner preserves dual-source draws as a separate pass");
    CHECK(tile == nil, "rejected tile merge clears any previous specialization");
    for(int i=0;i<2;i++)mtl_tex_release(&targets[i]);

    fs->has_dual=0; fs->fn_d=nil;
    if (argc > 2) {
        NSString *text=[NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:&error];
        MTLCompileOptions *options=[MTLCompileOptions new]; options.languageVersion=MTLLanguageVersion3_0;
        options.preserveInvariance=YES; options.fastMathEnabled=NO;
        id<MTLLibrary> actual=[g_dev newLibraryWithSource:text options:options error:&error];
        CHECK(actual != nil, "actual supplemental fragment library compiles");
        MTLFunctionConstantValues *values=[MTLFunctionConstantValues new];
        id<MTLFunction> primary=[actual newFunctionWithName:@"main0" constantValues:values error:&error];
        id<MTLFunction> secondary=[actual newFunctionWithName:@"main0_d" constantValues:values error:&error];
        CHECK(primary && secondary, "actual primary and dual entries remain available");
        NSUInteger original=[primary newArgumentEncoderWithBufferIndex:0].encodedLength;
        CHECK(original && original == [secondary newArgumentEncoderWithBufferIndex:0].encodedLength,
              "actual dual entry preserves the original argument-buffer layout");
    }
    {
        NSString *source = argc > 1 ? [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:&error] :
            @"#include <metal_stdlib>\nusing namespace metal; struct O {float4 c [[color(0)]];float z [[depth(any)]];}; fragment O main0() {return O{float4(1),.5};}";
        id<MTLLibrary> fragmentLibrary = [g_dev newLibraryWithSource:source options:nil error:&error];
        id<MTLLibrary> vertexLibrary = [g_dev newLibraryWithSource:
            @"#include <metal_stdlib>\nusing namespace metal; struct V {float4 p [[position]];float4 uv [[user(locn1)]];}; vertex V v(uint i [[vertex_id]]) {return V{float4(0,0,.5,1),float4(0)};}"
            options:nil error:&error];
        CHECK(fragmentLibrary && vertexLibrary, "actual depth fragment and matching vertex compile");
        vs->fn = [vertexLibrary newFunctionWithName:@"v"];
        fs->fn = [fragmentLibrary newFunctionWithName:@"main0"];
        fs->depth_out=1;
        k.blend_en=0; k.cfmt[0]=MTLPixelFormatBGRA8Unorm; k.topology=MTLPrimitiveTopologyClassTriangle;
        for (NSNumber *format in @[@0,@250,@252,@260,@0]) {
            k.dfmt=format.unsignedIntValue; k.sfmt=k.dfmt==260?260:0;
            NSError *why=nil;
            id<MTLRenderPipelineState> ps=pso_build(&k,vs,fs,nil,0,0,&why);
            printf("actual depth fragment: format=%u pipeline=%d error=%s\n", k.dfmt, ps!=nil, why.localizedDescription.UTF8String?:"-");
            CHECK((ps!=nil)==(k.dfmt!=0), "depth output requires a real depth attachment");
        }
    }
    printf("legacy blend: %d checks, %d failures\n", checks, failed);
    return failed != 0;
}}
