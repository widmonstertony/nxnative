// Linear depth/stencil flags must retain normal Metal depth storage on both backends.
#define nvn_game_fps nvn_game_fps_mtl_default
#include "../nvn/nvn_mtl.m"
#undef nvn_game_fps
#define g_ft g_ft_hle
#include "../nvn/hle_nvn.c"
#undef g_ft
uint64_t g_t0_ns;
void *front_metal_layer(void) { return NULL; }
#ifdef DM_NVN_LEGACY_RENDERER_TEST
int front_screen_max_fps(void) { return 60; }
#endif
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int cases, failed;
#define EXPECT(n,w,v) do { int a=(w), b=(v); cases++; printf("%s expected %d -> got %d %s\n",n,a,b,a==b?"PASS":"FAIL"); failed+=a!=b; } while (0)
static void linear_depth_case(void) {
    void *mem=NULL; if (posix_memalign(&mem,getpagesize(),262144)) abort(); memset(mem,0,262144);
    pool_t pool={.magic=MAGIC('P','O','O','L'),.mem=mem,.size=262144,.flags=0x24}; mtl_pool_add(mem,262144);
    int formats[]={NVN_FORMAT_DEPTH16,NVN_FORMAT_DEPTH32F,NVN_FORMAT_DEPTH32F_STENCIL8,NVN_FORMAT_STENCIL8};
    for (unsigned i=0;i<sizeof formats/sizeof *formats;i++) {
        NVNtextureBuilder tb; NVNtexture tex; h_nvnTextureBuilderSetDefaults(&tb); h_nvnTextureBuilderSetWidth(&tb,16); h_nvnTextureBuilderSetHeight(&tb,16);
        h_nvnTextureBuilderSetFormat(&tb,formats[i]); h_nvnTextureBuilderSetFlags(&tb,NVN_TEXTURE_FLAGS_LINEAR_RENDER_TARGET);
        h_nvnTextureBuilderSetStorage(&tb,(const NVNmemoryPool *)&pool,0);
        EXPECT("linear depth/stencil init",1,h_nvnTextureInitialize(&tex,&tb));
        id<MTLTexture> t=tex_mtl((const tex_t *)&tex);
        EXPECT("linear depth/stencil resolves without a buffer view",1,t!=nil && t.buffer==nil);
        if (t) {
            id<MTLCommandBuffer> cb=q_cb(); MTLRenderPassDescriptor *pd=[MTLRenderPassDescriptor renderPassDescriptor];
            if (formats[i]!=NVN_FORMAT_STENCIL8) { pd.depthAttachment.texture=t; pd.depthAttachment.loadAction=MTLLoadActionClear; pd.depthAttachment.storeAction=MTLStoreActionStore; pd.depthAttachment.clearDepth=.25; }
            if (formats[i]==NVN_FORMAT_STENCIL8 || formats[i]==NVN_FORMAT_DEPTH32F_STENCIL8) { pd.stencilAttachment.texture=t; pd.stencilAttachment.loadAction=MTLLoadActionClear; pd.stencilAttachment.storeAction=MTLStoreActionStore; pd.stencilAttachment.clearStencil=7; }
            [[cb renderCommandEncoderWithDescriptor:pd] endEncoding]; [cb commit]; [cb waitUntilCompleted];
            EXPECT("linear depth/stencil clear completed",MTLCommandBufferStatusCompleted,cb.status);
        }
        h_nvnTextureFinalize(&tex);
    }
    mtl_pool_del(mem); mtl_alias_drop_pool(&pool); defer_drain(); free(mem);
}
int main(void) { @autoreleasepool {
    mtl_init(); linear_depth_case();
    printf("LINEAR_DEPTH cases=%d failed=%d\n", cases, failed); return failed != 0;
} }
