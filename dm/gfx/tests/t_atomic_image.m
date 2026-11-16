
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#define DM_NVN_LEGACY_RENDERER_TEST 1
#include "../nvn/nvn_mtl.m"
uint64_t g_t0_ns;
int dm_guest_as_contains(uintptr_t address) { (void)address; return 0; }
void *front_metal_layer(void) { return NULL; }
int front_screen_max_fps(void) { return 60; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

static void begin_order(id e,int k) { legacy_order_begin(e,k,g_cb); }
static void end_order(id e,int k) { (void)k; m4_end(e); }
static int checks;
#define CHECK(x) do { checks++; if (!(x)) { fprintf(stderr,"check %d failed: %s\n",checks,#x); return 1; } } while(0)
int main(void) { @autoreleasepool {
    mtl_init(); id<MTLDevice> device=g_dev; CHECK(device);
    NSError *error=nil;
    MTLCompileOptions *options=[MTLCompileOptions new]; options.languageVersion=MTLLanguageVersion3_0;
    id<MTLLibrary> lib=[device newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nstruct Arguments {\n    constant uint* value [[id(0)]];\n    texture2d<float> mask [[id(3)]];\n    sampler maskSmplr [[id(4)]];\n    device atomic_uint* target [[id(5)]];\n};\n\nstatic inline uint4 dm_legacy_atomic_max_2d(device atomic_uint* image,\n        uint2 xy, uint value, constant uint* layout) {\n    if (xy.x >= layout[0] || xy.y >= layout[1] || layout[2] != 1u || layout[3] != 1u)\n        return uint4(0u);\n    ulong at = ulong(xy.y) * ulong(layout[4]) + ulong(xy.x);\n    if (at >= ulong(layout[5])) return uint4(0u);\n    uint previous = atomic_fetch_max_explicit(image + at, value, memory_order_relaxed);\n    return uint4(previous, 0u, 0u, 0u);\n}\n\nfragment void update_image(constant Arguments& args [[buffer(0)]],\n        float4 pos [[position]], constant uint* dm_legacy_atomic_layout [[buffer(29)]]) {\n    uint2 xy = uint2(pos.xy);\n    float2 size = float2(dm_legacy_atomic_layout[0], dm_legacy_atomic_layout[1]);\n    if (args.mask.sample(args.maskSmplr, pos.xy / size).x < 0.5) discard_fragment();\n    uint previous = dm_legacy_atomic_max_2d(args.target, xy, *args.value, dm_legacy_atomic_layout).x;\n}\n\nvertex float4 fullscreen(uint vid [[vertex_id]]) {\n    float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};\n    return float4(p[vid], 0.5, 1.0);\n}\nkernel void observe(texture2d<uint, access::read> image [[texture(0)]],\n        device uint* out [[buffer(0)]], uint2 xy [[thread_position_in_grid]]) {\n    if (xy.x < image.get_width() && xy.y < image.get_height())\n        out[xy.y * image.get_width() + xy.x] = image.read(xy).x;\n}\n" options:options error:&error];
    if(error) NSLog(@"%@",error); CHECK(lib);
    id<MTLFunction> fs=[lib newFunctionWithName:@"update_image"];
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];
    pd.vertexFunction=[lib newFunctionWithName:@"fullscreen"]; pd.fragmentFunction=fs;
    pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
    pd.colorAttachments[0].writeMask=MTLColorWriteMaskNone;
    id<MTLRenderPipelineState> pipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];
    if(error) NSLog(@"%@",error); CHECK(pipeline);
    id<MTLComputePipelineState> reader=[device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"observe"] error:&error]; CHECK(reader);
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Uint width:7 height:3 mipmapped:NO];
    td.storageMode=MTLStorageModePrivate; td.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> image=[device newTextureWithDescriptor:td]; CHECK(image);
    uint32_t layout[6]; NSUInteger bytes=0;
    CHECK(nvn_atomic_2d_layout(image,layout,&bytes));
    CHECK(layout[0]==7 && layout[1]==3 && layout[2]==1 && layout[3]==1 && layout[4]==64 && layout[5]==192 && bytes==768);
    CHECK(!nvn_zero_image_layout(image,layout,&bytes));
    CHECK(!nvn_atomic_2d_layout(nil,layout,&bytes));
    td.textureType=MTLTextureType2DArray; td.arrayLength=3;
    id<MTLTexture> array=[device newTextureWithDescriptor:td]; CHECK(array);
    uint32_t arrayLayout[6]; NSUInteger arrayBytes;
    CHECK(nvn_zero_image_layout(array,arrayLayout,&arrayBytes));
    CHECK(arrayLayout[2]==3 && arrayBytes==2304);
    CHECK(!nvn_atomic_2d_layout(array,arrayLayout,&arrayBytes));
    td.textureType=MTLTextureType2D; td.arrayLength=1; td.pixelFormat=MTLPixelFormatR32Float;
    td.storageMode=MTLStorageModeShared;
    id<MTLTexture> mask=[device newTextureWithDescriptor:td]; CHECK(mask);
    CHECK(!nvn_atomic_2d_layout(mask,layout,&bytes));
    float maskValues[21]; uint32_t expected[21];
    for(int y=0;y<3;y++) for(int x=0;x<7;x++) { maskValues[y*7+x]=(x%2==0 && y!=1); expected[y*7+x]=y*7+x+1; }
    expected[0]=500;
    [mask replaceRegion:MTLRegionMake2D(0,0,7,3) mipmapLevel:0 withBytes:maskValues bytesPerRow:7*sizeof(float)];
    td.pixelFormat=MTLPixelFormatRGBA8Unorm; td.storageMode=MTLStorageModePrivate; td.usage=MTLTextureUsageRenderTarget;
    id<MTLTexture> attachment=[device newTextureWithDescriptor:td]; CHECK(attachment);
    MTLSamplerDescriptor *sd=[MTLSamplerDescriptor new]; sd.supportArgumentBuffers=YES; sd.minFilter=sd.magFilter=MTLSamplerMinMagFilterNearest;
    sd.sAddressMode=sd.tAddressMode=MTLSamplerAddressModeClampToEdge;
    id<MTLSamplerState> sampler=[device newSamplerStateWithDescriptor:sd]; CHECK(sampler);
    id<MTLArgumentEncoder> ae=[fs newArgumentEncoderWithBufferIndex:0]; CHECK(ae);

    id<MTLCommandQueue> queue=[device newCommandQueue];
    mtl_sub_begin(); id<MTLCommandBuffer> cb=g_cb;
    id<MTLBuffer> seed=[device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    memset(seed.contents,0,bytes);
    for(int y=0;y<3;y++) memcpy((uint32_t*)seed.contents+y*layout[4],expected+y*7,28);
    id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder]; begin_order(blit,3);
    nvn_zero_image_copy(blit,image,seed,layout,YES); end_order(blit,3);

    tex_t target={.magic=MAGIC('T','E','X',0),.serial=99791};
    target.d=(nvn_texdesc){.target=NVN_TEXTURE_TARGET_2D,.format=NVN_FORMAT_R32UI,.width=7,.height=3,.depth=1,.levels=1,.samples=1};
    nvn_tex_layout(&target.d,&target.L); res_add(image); serial_put(target.serial,image); mtl_reg_tex(601,&target,NULL);
    NvProg *program=[NvProg new]; program->sh[0]=[NvShader new]; program->sh[1]=[NvShader new];
    NvShader *fragment=program->sh[1]; fragment->zero_image_variant=3; fragment->zero_image_aid=5;
    fragment->zero_image_reg=1; fragment->zero_image_format=MTLPixelFormatR32Uint;
    fragment->rf.nb=3;
    fragment->rf.b[0]=(nvn_rbind){.kind=NVN_RB_IMGA,.aid=5,.reg=1,.rw=1};
    fragment->rf.b[1]=(nvn_rbind){.kind=NVN_RB_TEX,.aid=3,.reg=0};
    fragment->rf.b[2]=(nvn_rbind){.kind=NVN_RB_CBUF,.aid=0,.reg=0};
    state_reset(); memset(&R,0,sizeof R); S.img[1][1]=601;
    p_draw draw={0};
    CHECK(!zero_image_prepare(program,&draw,NULL,1));
    program->sh[0]->rf.nv=1; CHECK(!zero_image_prepare(program,&draw,NULL,0)); program->sh[0]->rf.nv=0;
    R.rt.n=1; R.rt.color[0]=&target; CHECK(!zero_image_prepare(program,&draw,NULL,0)); R.rt.n=0;
    R.rt.depth=&target; CHECK(!zero_image_prepare(program,&draw,NULL,0)); R.rt.depth=NULL;
    S.tex[1][0]=601; CHECK(!zero_image_prepare(program,&draw,NULL,0)); S.tex[1][0]=0;
    g_treg[601].t.mem=(void*)0x100000; g_treg[601].t.L.size=0x1000;
    S.ubo[1][0].addr=0x100020; S.ubo[1][0].size=16;
    CHECK(!zero_image_prepare(program,&draw,NULL,0)); S.ubo[1][0].addr=0; S.ubo[1][0].size=0;
    g_treg[601].t.mem=NULL;
    NSMutableArray *shadows=[NSMutableArray new], *reads=[NSMutableArray new], *arguments=[NSMutableArray new];
    uint32_t wanted[3][21];
    for(int pass=0;pass<3;pass++) {
        uint32_t value=pass==0?100:pass==1?50:200;
        int start=pass==1?2:0, width=pass==0?5:pass==1?5:7;
        CHECK(zero_image_prepare(program,&draw,NULL,0));
        id<MTLBuffer> shadow=g_zero_image_buffer; CHECK(shadow && g_zero_image_texture==image);
        for(NSUInteger i=0;i<bytes/4;i++) ((uint32_t*)shadow.contents)[i]=0xdeadbeef;
        [shadows addObject:shadow];

        id<MTLBuffer> args=[device newBufferWithLength:ae.encodedLength options:MTLResourceStorageModeShared];
        [arguments addObject:args]; [ae setArgumentBuffer:args offset:0];
        id<MTLBuffer> valueBuffer=[device newBufferWithBytes:&value length:sizeof value options:MTLResourceStorageModeShared]; [arguments addObject:valueBuffer];
        [ae setBuffer:valueBuffer offset:0 atIndex:0]; [ae setTexture:mask atIndex:3]; [ae setSamplerState:sampler atIndex:4]; [ae setBuffer:shadow offset:0 atIndex:5];
        MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture=attachment; rp.colorAttachments[0].loadAction=MTLLoadActionClear;
        rp.colorAttachments[0].storeAction=MTLStoreActionDontCare;
        id<MTLRenderCommandEncoder> re=[cb renderCommandEncoderWithDescriptor:rp]; begin_order(re,1);
        [re setRenderPipelineState:pipeline]; [re setViewport:(MTLViewport){0,0,7,3,0,1}];
        [re setScissorRect:(MTLScissorRect){start,0,width,3}];
        [re useResource:shadow usage:MTLResourceUsageRead|MTLResourceUsageWrite stages:MTLRenderStageFragment];
        [re useResource:mask usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
        [re setFragmentBuffer:args offset:0 atIndex:0];
        [re setFragmentBytes:layout length:sizeof layout atIndex:29];
        [re useResource:valueBuffer usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
        [re drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; g_enc=re; rp_end();
        CHECK(!g_zero_image_buffer);
        id<MTLBuffer> read=[device newBufferWithLength:sizeof expected options:MTLResourceStorageModeShared]; [reads addObject:read];
        id<MTLComputeCommandEncoder> ce=[cb computeCommandEncoder]; begin_order(ce,2); [ce setComputePipelineState:reader];
        [ce setTexture:image atIndex:0]; [ce setBuffer:read offset:0 atIndex:0];
        [ce dispatchThreads:MTLSizeMake(7,3,1) threadsPerThreadgroup:MTLSizeMake(7,3,1)]; end_order(ce,2);
        for(int y=0;y<3;y++) for(int x=start;x<start+width;x++) if(maskValues[y*7+x] && expected[y*7+x]<value) expected[y*7+x]=value;
        memcpy(wanted[pass],expected,sizeof expected);
    }
    [cb commit]; [cb waitUntilCompleted]; if(cb.error) NSLog(@"%@",cb.error); CHECK(cb.status==MTLCommandBufferStatusCompleted);
    for(int pass=0;pass<3;pass++) {
        id<MTLBuffer> read=reads[pass], shadow=shadows[pass];
        for(int i=0;i<21;i++) { if (((uint32_t*)read.contents)[i]!=wanted[pass][i]) fprintf(stderr,"pass=%d pixel=%d got=%u expected=%u\n",pass,i,((uint32_t*)read.contents)[i],wanted[pass][i]); CHECK(((uint32_t*)read.contents)[i]==wanted[pass][i]); }
        for(int y=0;y<3;y++) for(unsigned x=7;x<layout[4];x++) CHECK(((uint32_t*)shadow.contents)[y*layout[4]+x]==0xdeadbeef);
    }
    printf("{\"checks\":%d,\"device\":\"%s\",\"passes\":3,\"raster_discard_copyback\":true}\n",checks,device.name.UTF8String);
    return 0;
} }
