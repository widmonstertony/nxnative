// Exercise the production upload and sampled-view paths with CPU BC decoding
// forced on a BC-capable Mac GPU. No game assets or test-only production hooks.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(label,c) do { checks++; if (!(c)) { failed++; fprintf(stderr,"FAIL: %s\n",label); } } while (0)
static void finish(void) {
    CHECK("upload submission completes",mtl_wait(mtl_sub_commit(),5000000000ull));
    CHECK("upload has no GPU error",!mtl_last_commit_error());
}
static void uploads(int format, int bpp, int direct) {
    g_direct_upload_on=direct;
    static uint64_t serial=990000;
    tex_t t={.magic=MAGIC('T','E','X',0),.serial=serial++,.has_layout=1};
    t.d=(nvn_texdesc){.target=4,.format=format,.width=7,.height=5,.depth=2,.levels=3,.samples=1};
    nvn_tex_layout(&t.d,&t.L);
    size_t poolsize=(t.L.size+4096+getpagesize()-1)&~(size_t)(getpagesize()-1);
    void *mem=NULL; if(posix_memalign(&mem,getpagesize(),poolsize))abort(); memset(mem,0,poolsize);
    pool_t pool={.magic=MAGIC('P','O','O','L'),.mem=mem,.size=poolsize,.flags=NVN_MEMORY_POOL_FLAGS_CPU_UNCACHED|NVN_MEMORY_POOL_FLAGS_GPU_CACHED};
    t.pool=&pool; t.mem=(uint8_t*)mem+4096;
    mtl_pool_add(mem,poolsize); nvn_dirty_add_range(mem,poolsize);
    size_t bytes=0; for(unsigned l=0;l<3;l++)bytes+=(size_t)MAX(7u>>l,1u)*MAX(5u>>l,1u)*2*bpp;
    uint8_t *expected=malloc(bytes);
    id<MTLBuffer> readback=[g_dev newBufferWithLength:bytes+512 options:MTLResourceStorageModeShared];
    for(unsigned round=0;round<2;round++) {
        dm_guest_write_prepare(mem,poolsize); size_t off=0;
        for(unsigned l=0;l<3;l++)for(unsigned a=0;a<2;a++) {
            unsigned w=MAX(7u>>l,1u),h=MAX(5u>>l,1u),nb=((w+3)/4)*((h+3)/4);
            unsigned bb=format==0x41||format==0x49?8:16;
            uint8_t blocks[64]={0},pixel[4]={0};
            for(unsigned i=0;i<nb;i++) {
                uint8_t *b=blocks+i*bb;
                if(format==0x41) { b[0]=round?0xe0:0; b[1]=round?7:0xf8; pixel[round?1:0]=255; pixel[3]=255; }
                else { b[0]=(uint8_t)(200+round+a+l); pixel[0]=b[0]; if(format==0x4b){b[8]=100+round+a+l;pixel[1]=b[8];} }
            }
            CHECK("compressed blocks swizzle",!nvn_swizzle(&t.d,l,a,blocks,((w+3)/4)*bb,t.mem));
            for(unsigned i=0;i<w*h;i++)memcpy(expected+off+(size_t)i*bpp,pixel,bpp);
            off+=(size_t)w*h*bpp;
        }
        mtl_sub_begin(); id<MTLTexture> image=tex_mtl(&t); CHECK("decoded texture exists",image!=nil); finish();
        if(!image)break;
        CHECK("decoded mip count",image.mipmapLevelCount==3); CHECK("decoded array layers",image.arrayLength==2);
        id<MTLCommandBuffer> cb=q_cb(); id<MTLBlitCommandEncoder> enc=[cb blitCommandEncoder]; off=0;
        for(unsigned l=0;l<3;l++)for(unsigned a=0;a<2;a++) {
            unsigned w=MAX(7u>>l,1u),h=MAX(5u>>l,1u);
            [enc copyFromTexture:image sourceSlice:a sourceLevel:l sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(w,h,1) toBuffer:readback destinationOffset:256+off destinationBytesPerRow:w*bpp destinationBytesPerImage:w*h*bpp];
            off+=(size_t)w*h*bpp;
        }
        [enc endEncoding]; [cb commit]; [cb waitUntilCompleted];
        CHECK("GPU readback completes",cb.status==MTLCommandBufferStatusCompleted);
        CHECK("every decoded mip/layer pixel matches independent uniform-block reference",!memcmp((uint8_t*)readback.contents+256,expected,bytes));
    }
    mtl_tex_release(&t); mtl_drain(); mtl_alias_drop_pool(&pool); nvn_dirty_remove_range(mem); mtl_pool_del(mem); mtl_drain(); free(mem); free(expected);
}
static void views(void) {
    for(unsigned f=0x41;f<=0x50;f++) {
        uint32_t unpacked=0,native=0; int bpp=0; uint8_t sw[4];
        CHECK("BC family has decoded format",nvn_bc_unpacked(f,&unpacked,&bpp));
        CHECK("BC family has native format",nvn_fmt_to_mtl(f,&native,sw));
        tex_t t={.magic=MAGIC('T','E','X',0),.serial=1000000+f};
        t.d=(nvn_texdesc){.target=1,.format=f,.width=4,.height=4,.depth=1,.levels=1,.samples=1};
        g_bc_cpu=0; CHECK("native BC descriptor unchanged",tex_desc(&t,0).pixelFormat==native);
        g_bc_cpu=1; MTLTextureDescriptor *d=tex_desc(&t,0); d.storageMode=MTLStorageModeShared;
        id<MTLTexture> base=[g_dev newTextureWithDescriptor:d]; CHECK("decoded base allocated",base!=nil); if(!base)continue;
        CHECK("decoded base format",base.pixelFormat==unpacked); serial_put(t.serial,base);
        view_t v={.set_format=1,.format=f}; mtl_reg_tex(200+f,&t,&v);
        os_unfair_lock_lock(&g_rmu); id<MTLTexture> view=tex_by_id(200+f);
        CHECK("sampled BC view exists",view!=nil); CHECK("sampled BC view uses decoded storage format",view.pixelFormat==unpacked);
        CHECK("sampled BC view cache reused",tex_by_id(200+f)==view); os_unfair_lock_unlock(&g_rmu);
        CHECK("render-target view uses decoded format",rt_view_fmt(base,&v,1)==unpacked);
        MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];
        attach(rp.colorAttachments[0],&t,&v,1);
        CHECK("decoded attachment is retained",rp.colorAttachments[0].texture.pixelFormat==unpacked);
        p_clear_tex clear={.tex=&t,.view=v,.has_view=1,.mask=15,.r={0,0,0,4,4,1}};
        clear.c.f[0]=0.25f; clear.c.f[1]=0.5f; clear.c.f[2]=0.75f; clear.c.f[3]=1;
        state_reset(); memset(&R,0,sizeof R); mtl_sub_begin(); clear_tex(&clear); finish();
        mtl_drain();
    }
}
int main(int argc,char **argv) { @autoreleasepool {
    mtl_init(); g_bc_cpu=1;
    CHECK("GPU deswizzle is enabled for the regression",g_nvn_deswz_gpu);
    if(argc<2||strcmp(argv[1],"views"))for(int direct=0;direct<2;direct++){uploads(0x41,4,direct);uploads(0x49,1,direct);uploads(0x4b,2,direct);}
    if(argc<2||strcmp(argv[1],"uploads"))views();
    printf("t_bc_cpu: %d checks, %d failed\n",checks,failed); return failed!=0;
}}
