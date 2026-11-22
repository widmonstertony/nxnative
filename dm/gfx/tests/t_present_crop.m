// Present crop regression: colored 8×8 texture, closed-form RGBA expectations; real Metal rendering, no dependence on the game or on cross-run determinism.
// nvn_mtl.m's nvn_game_fps is a weak default and hle_nvn.c gives the strong definition; in one translation unit that is a redefinition, so the weak one is renamed (this test does not look at the frame-rate target)
#define nvn_game_fps nvn_game_fps_mtl_default
#include "../nvn/nvn_mtl.m"
#undef nvn_game_fps
#define g_ft g_ft_hle   // both files have a static g_ft (nvn_mtl.m's fragment argument table, hle_nvn.c's textures a flush can mark CPU-written), so hle_nvn.c's is renamed too
#include "../nvn/hle_nvn.c"
#undef g_ft
#include <assert.h>
uint64_t g_t0_ns;   // process start time from host main.c (used by hle_nvn's per-frame @t_s); unit test stub
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int g_layer_crop[4];   // what the vi layer crop (hle_vi.c) answers: x, y, w, h, all 0 = none
void dm_vi_layer_crop(int c[4]) { memcpy(c, g_layer_crop, sizeof g_layer_crop); }
#ifdef CROP_LEGACY_HEADER
#include CROP_LEGACY_HEADER
#define ENCODE legacy_present_encode
#else
#define ENCODE present_encode
#endif
static int failed, cases;
#define EXPECT(n, w, v) do { int a=(w),b=(v); cases++; printf("%s expected %d → got %d %s\n",n,a,b,a==b?"✓":"✗");failed+=a!=b; } while(0)
static const uint8_t colors[4][4]={{255,0,0,255},{0,255,0,255},{0,0,255,255},{255,255,0,255}};
#ifndef CROP_LEGACY_HEADER
extern int g_shape_w,g_shape_h;   // t_host_stubs.c: the last shape the present reported to the front end
#endif

#ifndef CROP_LEGACY_HEADER
// Exercise the persistent scaler used by real presents, completing each command buffer before its allocator and output leave scope.
static int check_present_resize(id<MTLTexture> src, int w, int h) {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
    d.storageMode=MTLStorageModePrivate;d.usage=MTLTextureUsageRenderTarget;
    id<MTLTexture> out=[g_dev newTextureWithDescriptor:d];res_add(out);res_commit();
    id<MTL4CommandAllocator> al=[g_dev newCommandAllocator];id<MTL4CommandBuffer> cb=[g_dev newCommandBuffer];id<MTLSharedEvent> ev=[g_dev newSharedEvent];
    assert(al && ev);
    [cb beginCommandBufferWithAllocator:al];int kind=present_encode_m4(cb,src,out,NULL,g_present_uv[0],&g_fx_present,NULL);[cb endCommandBuffer];
    [g_q4 commit:&cb count:1];[g_q4 signalEvent:ev value:1];
    EXPECT("resize present completes",1,[ev waitUntilSignaledValue:1 timeoutMS:10000]);res_remove(out);return kind;
}
#endif

#ifndef CROP_LEGACY_HEADER
// ---------- The HDR present (DM_HDR_PRESENT; present_hdr, present.metal fs_hdr) into an RGBA16Float canvas, without a window ----------
// CPU references of fs_hdr's curves (SMPTE ST 2084, IEC 61966-2-1, BT.2087), in double
static double ref_pq_encode(double nits) { const double m1=0.1593017578125,m2=78.84375,c1=0.8359375,c2=18.8515625,c3=18.6875; double p=pow(fmax(fmin(nits/10000,1),0),m1); return pow((c1+c2*p)/(1+c3*p),m2); }
static double ref_srgb_linear(double c) { return c<=0.04045?c/12.92:pow((c+0.055)/1.055,2.4); }
static void ref_709_to_2020(const double l[3], double o[3]) {
    o[0]=0.627404*l[0]+0.329283*l[1]+0.043313*l[2]; o[1]=0.069097*l[0]+0.919540*l[1]+0.011362*l[2]; o[2]=0.016391*l[0]+0.088013*l[1]+0.895595*l[2]; }
static void ref_2020_to_709(const double l[3], double o[3]) {
    o[0]=1.660491*l[0]-0.587641*l[1]-0.072850*l[2]; o[1]=-0.124550*l[0]+1.132900*l[1]-0.008349*l[2]; o[2]=-0.018151*l[0]-0.100579*l[1]+1.118730*l[2]; }
static double ref_pq_nits(double e) { const double m1=0.1593017578125,m2=78.84375,c1=0.8359375,c2=18.8515625,c3=18.6875; double p=pow(e,1/m2); return pow(fmax(p-c1,0)/(c2-c3*p),1/m1)*10000; }
// A uniform N x N source of format pf filled with px (bytes of one texel), presented with the HDR constants of kind into an N*up x N*up RGBA16Float canvas (usage: its texture usage),
// through MetalFX when fx is non-NULL. Returns the encoding kind (PRESENT_*) and the canvas's centre texel in out[4]
static int t_p709;   // present_hdr's p709: the PQ picture taken as BT.709 primaries (DM_HDR_GAMUT=709, a diagnostic)
static int hdr_present_fmt(MTLPixelFormat cpf, MTLPixelFormat pf, const void *px, size_t bpp, int kind, int up, MTLTextureUsage usage, fx_state *fx, double out[4]) {
    const int N=8, W=N*up;
    MTLTextureDescriptor *sd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf width:N height:N mipmapped:NO];sd.storageMode=MTLStorageModeShared;sd.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> src=[g_dev newTextureWithDescriptor:sd];uint8_t buf[8*8*16];
    for(int i=0;i<N*N;i++)memcpy(buf+i*bpp,px,bpp);
    [src replaceRegion:MTLRegionMake2D(0,0,N,N) mipmapLevel:0 withBytes:buf bytesPerRow:N*bpp];
    MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:cpf width:W height:W mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=usage;
    id<MTLTexture> dst=[g_dev newTextureWithDescriptor:od];res_add(src);res_add(dst);res_commit();
    float h[4];present_hdr(src,kind,t_p709,h);
    id<MTL4CommandAllocator> al=[g_dev newCommandAllocator];id<MTL4CommandBuffer> cb=[g_dev newCommandBuffer];id<MTLSharedEvent> ev=[g_dev newSharedEvent];
    [cb beginCommandBufferWithAllocator:al];int k=present_encode_m4(cb,src,dst,NULL,g_present_uv[0],fx,h);[cb endCommandBuffer];
    [g_q4 commit:&cb count:1];[g_q4 signalEvent:ev value:1];
    EXPECT("HDR present completes",1,[ev waitUntilSignaledValue:1 timeoutMS:10000]);
    if(cpf==MTLPixelFormatRGB10A2Unorm){uint32_t o;[dst getBytes:&o bytesPerRow:W*4 fromRegion:MTLRegionMake2D(W/2,W/2,1,1) mipmapLevel:0];
        out[0]=(o&1023)/1023.;out[1]=(o>>10&1023)/1023.;out[2]=(o>>20&1023)/1023.;out[3]=(o>>30)/3.;}
    else{__fp16 o[4];[dst getBytes:o bytesPerRow:W*8 fromRegion:MTLRegionMake2D(W/2,W/2,1,1) mipmapLevel:0];for(int i=0;i<4;i++)out[i]=o[i];}
    res_remove(src);res_remove(dst);return k;
}
static int hdr_present_one(MTLPixelFormat pf, const void *px, size_t bpp, int kind, int up, MTLTextureUsage usage, fx_state *fx, double out[4]) {
    return hdr_present_fmt(MTLPixelFormatRGBA16Float,pf,px,bpp,kind,up,usage,fx,out);
}
static void expect_rgb(const char *name, const double got[4], const double want[3], double tol) {
    int ok=fabs(got[0]-want[0])<=tol&&fabs(got[1]-want[1])<=tol&&fabs(got[2]-want[2])<=tol;
    cases++;failed+=!ok;
    printf("%s expected %.4f %.4f %.4f → got %.4f %.4f %.4f %s\n",name,want[0],want[1],want[2],got[0],got[1],got[2],ok?"✓":"✗");
}
static void check_present_hdr(void) {
    // Which encoding each source format is read in (hdr_src_enc): Mario Kart World's HDR swapchain (NVN 0x3D, RGB10A2) is PQ on the PQ layer; RGBA8 is SDR; float is linear
    EXPECT("HDR: RGB10A2 on the PQ layer is PQ",HDR_ENC_PQ,hdr_src_enc(MTLPixelFormatRGB10A2Unorm,FRONT_HDR_PQ));
    EXPECT("HDR: RGB10A2 on the scRGB layer is PQ too",HDR_ENC_PQ,hdr_src_enc(MTLPixelFormatRGB10A2Unorm,FRONT_HDR_SCRGB));
    EXPECT("HDR: RGBA8 is SDR",HDR_ENC_SDR,hdr_src_enc(MTLPixelFormatRGBA8Unorm,FRONT_HDR_PQ));
    EXPECT("HDR: BGRA8 sRGB is SDR",HDR_ENC_SDR,hdr_src_enc(MTLPixelFormatBGRA8Unorm_sRGB,FRONT_HDR_PQ));
    EXPECT("HDR: RGBA16F is linear",HDR_ENC_LINEAR,hdr_src_enc(MTLPixelFormatRGBA16Float,FRONT_HDR_PQ));
    EXPECT("HDR: RG11B10F is linear",HDR_ENC_LINEAR,hdr_src_enc(MTLPixelFormatRG11B10Float,FRONT_HDR_SCRGB));
    const double tol=2e-3;   // half-float canvas and the GPU's pow
    MTLTextureUsage rt=MTLTextureUsageRenderTarget;double got[4];
    // RGB10A2 holding PQ BT.2020, PQ layer: copied as it is
    uint32_t pq10=512u|(256u<<10)|(800u<<20)|(3u<<30);
    hdr_present_one(MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_PQ,1,rt,NULL,got);
    expect_rgb("HDR: an RGB10A2 PQ picture is copied into the PQ layer",got,(double[3]){512/1023.,256/1023.,800/1023.},tol);
    // RGBA8 SDR, PQ layer: sRGB decoded, BT.709 → BT.2020, placed at paper white (203 nits), PQ encoded. White lands on PQ(203) ≈ 0.58
    uint8_t white[4]={255,255,255,255};
    hdr_present_one(MTLPixelFormatRGBA8Unorm,white,4,FRONT_HDR_PQ,1,rt,NULL,got);
    double pw=ref_pq_encode(203);
    expect_rgb("HDR: SDR white goes to PQ paper white (203 nits)",got,(double[3]){pw,pw,pw},tol);
    uint8_t c8[4]={200,100,30,255};double l[3]={ref_srgb_linear(200/255.),ref_srgb_linear(100/255.),ref_srgb_linear(30/255.)},w[3];ref_709_to_2020(l,w);
    hdr_present_one(MTLPixelFormatRGBA8Unorm,c8,4,FRONT_HDR_PQ,1,rt,NULL,got);
    expect_rgb("HDR: an SDR colour converted to PQ BT.2020",got,(double[3]){ref_pq_encode(w[0]*203),ref_pq_encode(w[1]*203),ref_pq_encode(w[2]*203)},tol);
    // RGBA16F scRGB, scRGB layer: copied (values above 1 and below 0 kept); RGBA8 into the scRGB layer: sRGB decoded to linear
    __fp16 f16[4]={2.5,0.5,-0.125,1};
    hdr_present_one(MTLPixelFormatRGBA16Float,f16,8,FRONT_HDR_SCRGB,1,rt,NULL,got);
    expect_rgb("HDR: an scRGB picture is copied into the extended linear layer",got,(double[3]){2.5,0.5,-0.125},tol);
    hdr_present_one(MTLPixelFormatRGBA8Unorm,c8,4,FRONT_HDR_SCRGB,1,rt,NULL,got);
    expect_rgb("HDR: an SDR colour decoded into the extended linear layer",got,l,tol);
    // RGB10A2 PQ BT.2020 into the scRGB layer (DM_HDR_PRESENT_KIND=scrgb): PQ decoded to nits, divided by paper white, BT.2020 → BT.709 with negatives kept.
    // A saturated BT.2020 green (outside BT.709) gives negative red and blue; 1000 nits white gives 1000 / 203
    {   double pqv[3]={512/1023.,256/1023.,800/1023.},n[3],o3[3];for(int i=0;i<3;i++)n[i]=ref_pq_nits(pqv[i])/203;ref_2020_to_709(n,o3);
        hdr_present_one(MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_SCRGB,1,rt,NULL,got);
        expect_rgb("HDR: an RGB10A2 PQ picture decoded into the extended linear layer",got,o3,4e-3);
        EXPECT("HDR: the HDR present writes alpha 1",1,got[3]==1);
        uint32_t green=0u|(700u<<10)|(0u<<20)|(3u<<30);double g3[3]={0,ref_pq_nits(700/1023.)/203,0};ref_2020_to_709(g3,o3);
        hdr_present_one(MTLPixelFormatRGB10A2Unorm,&green,4,FRONT_HDR_SCRGB,1,rt,NULL,got);
        expect_rgb("HDR: a BT.2020 green outside BT.709 keeps its negative red and blue",got,o3,o3[1]*2e-3+2e-3);
        EXPECT("HDR: that green's red is negative",1,got[0]<0&&got[2]<0);
        uint32_t w1000;{unsigned q=(unsigned)lround(ref_pq_encode(1000)*1023);w1000=q|(q<<10)|(q<<20)|(3u<<30);}
        double wn=ref_pq_nits(lround(ref_pq_encode(1000)*1023)/1023.)/203;
        hdr_present_one(MTLPixelFormatRGB10A2Unorm,&w1000,4,FRONT_HDR_SCRGB,1,rt,NULL,got);
        expect_rgb("HDR: 1000-nit white is 1000 / 203 of paper white",got,(double[3]){wn,wn,wn},wn*3e-3);
    }
    // The PQ layer in RGB10A2Unorm (DM_HDR_PRESENT_FORMAT=rgb10a2): PQ values copied bit for bit, an SDR picture converted, alpha 1 (an RGBA8 source with alpha 0)
    hdr_present_fmt(MTLPixelFormatRGB10A2Unorm,MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_PQ,1,rt,NULL,got);
    expect_rgb("HDR: an RGB10A2 PQ picture is copied into an RGB10A2 PQ layer",got,(double[3]){512/1023.,256/1023.,800/1023.},0.4/1023);
    uint8_t white0[4]={255,255,255,0};
    hdr_present_fmt(MTLPixelFormatRGB10A2Unorm,MTLPixelFormatRGBA8Unorm,white0,4,FRONT_HDR_PQ,1,rt,NULL,got);
    expect_rgb("HDR: SDR white goes to PQ paper white in an RGB10A2 layer",got,(double[3]){pw,pw,pw},1.5/1023);
    EXPECT("HDR: alpha 1 from a source with alpha 0",1,got[3]==1);
    // DM_HDR_GAMUT=709 (front_hdr_primaries_709 1; present_hdr p709): a PQ picture taken as BT.709 primaries is decoded, BT.709 → BT.2020, encoded again for the PQ layer, decoded
    // with no matrix for the scRGB layer; the flag means nothing for an SDR or linear source. Without it (auto: front_hdr_primaries_709's weak default 0 here) every PQ picture is copied
    {   t_p709=1;double pqv[3]={512/1023.,256/1023.,800/1023.},n[3],w2[3],o3[3];
        for(int i=0;i<3;i++)n[i]=ref_pq_nits(pqv[i]);ref_709_to_2020(n,w2);for(int i=0;i<3;i++)o3[i]=ref_pq_encode(w2[i]);
        hdr_present_one(MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_PQ,1,rt,NULL,got);
        expect_rgb("HDR: a BT.709 PQ picture converted to BT.2020 in the PQ layer",got,o3,2e-3);
        EXPECT("HDR: its colour moved (not copied)",1,fabs(got[2]-pqv[2])>5e-3);
        hdr_present_fmt(MTLPixelFormatRGB10A2Unorm,MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_PQ,1,rt,NULL,got);
        expect_rgb("HDR: the same into an RGB10A2 PQ layer",got,o3,1.5/1023);
        for(int i=0;i<3;i++)o3[i]=n[i]/203;
        hdr_present_one(MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_SCRGB,1,rt,NULL,got);
        expect_rgb("HDR: a BT.709 PQ picture decoded into the scRGB layer without the matrix",got,o3,4e-3*o3[2]+1e-3);
        float h[4];MTLTextureDescriptor *d8=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
        present_hdr([g_dev newTextureWithDescriptor:d8],FRONT_HDR_PQ,1,h);EXPECT("HDR: BT.709 primaries flag only a PQ source",0,(int)h[3]);
        present_hdr([g_dev newTextureWithDescriptor:[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGB10A2Unorm width:8 height:8 mipmapped:NO]],FRONT_HDR_PQ,0,h);
        EXPECT("HDR: a BT.2020 PQ source is not flagged",0,(int)h[3]);
        EXPECT("HDR: auto takes every PQ picture as BT.2020 (front_hdr_primaries_709 0)",0,front_hdr_primaries_709());
        t_p709=0;
    }
    // A linear picture into the PQ layer: 1.0 is paper white
    __fp16 one[4]={1,1,1,1};
    hdr_present_one(MTLPixelFormatRGBA16Float,one,8,FRONT_HDR_PQ,1,rt,NULL,got);
    expect_rgb("HDR: linear 1.0 goes to PQ paper white",got,(double[3]){pw,pw,pw},tol);
    if([MTLFXSpatialScalerDescriptor supportsMetal4FX:g_dev]) {   // MetalFX upscaling 2x in the HDR present: PQ values go through untouched; a picture that is converted is not written into the canvas by the scaler
        g_fx_mode=1;fx_state fx={0};
        int k=hdr_present_one(MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_PQ,2,rt|MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead,&fx,got);
        printf("HDR: MetalFX with an RGB10A2 source into RGBA16F: %s\n",k==PRESENT_METALFX?"scaled by MetalFX":"MetalFX refused the formats: bilinear");
        expect_rgb("HDR: MetalFX keeps an RGB10A2 PQ picture's values",got,(double[3]){512/1023.,256/1023.,800/1023.},4e-3);
        res_remove(fx.in);res_remove(fx.out);fx=(fx_state){0};
        k=hdr_present_one(MTLPixelFormatRGBA8Unorm,white,4,FRONT_HDR_PQ,2,rt|MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead,&fx,got);
        EXPECT("HDR: MetalFX scales an SDR picture into the PQ layer",PRESENT_METALFX,k);
        expect_rgb("HDR: with MetalFX the SDR picture is still converted (the scaler does not write the canvas)",got,(double[3]){pw,pw,pw},4e-3);
        res_remove(fx.in);res_remove(fx.out);fx=(fx_state){0};
        // The scRGB layer with a PQ source through MetalFX: the scaler takes the PQ values (perceptual mode), and fs_hdr decodes its output
        double pqv[3]={512/1023.,256/1023.,800/1023.},n[3],o3[3];for(int i=0;i<3;i++)n[i]=ref_pq_nits(pqv[i])/203;ref_2020_to_709(n,o3);
        k=hdr_present_one(MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_SCRGB,2,rt|MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead,&fx,got);
        EXPECT("HDR: MetalFX scales a PQ picture into the scRGB layer",PRESENT_METALFX,k);
        expect_rgb("HDR: MetalFX's PQ output decoded into the scRGB layer",got,o3,0.015*o3[2]);   // MetalFX moves PQ code values by up to about 1e-3 (0.7812 for 0.7820 above): about 1 % in linear light at 1,470 nits
        res_remove(fx.in);res_remove(fx.out);fx=(fx_state){0};
        // A linear source into the RGB10A2 PQ layer through MetalFX: scaled in float (HDR mode), so 4.0 (812 nits) is not clipped at 1 before fs_hdr encodes it
        __fp16 f4[4]={4,4,4,1};double p4=ref_pq_encode(4*203);
        k=hdr_present_fmt(MTLPixelFormatRGB10A2Unorm,MTLPixelFormatRGBA16Float,f4,8,FRONT_HDR_PQ,2,rt|MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead,&fx,got);
        EXPECT("HDR: MetalFX scales a linear picture into the RGB10A2 PQ layer",PRESENT_METALFX,k);
        expect_rgb("HDR: a linear 4.0 through MetalFX reaches PQ(812 nits), not PQ(203)",got,(double[3]){p4,p4,p4},4e-3);
        res_remove(fx.in);res_remove(fx.out);fx=(fx_state){0};
        // A BT.709 PQ picture through MetalFX into a canvas MetalFX could write: still converted after the scaler, so MetalFX does not write the canvas
        t_p709=1;{double pqv[3]={512/1023.,256/1023.,800/1023.},n[3],w2[3],o3[3];for(int i=0;i<3;i++)n[i]=ref_pq_nits(pqv[i]);ref_709_to_2020(n,w2);for(int i=0;i<3;i++)o3[i]=ref_pq_encode(w2[i]);
        k=hdr_present_one(MTLPixelFormatRGB10A2Unorm,&pq10,4,FRONT_HDR_PQ,2,rt|MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead,&fx,got);
        EXPECT("HDR: MetalFX scales a BT.709 PQ picture",PRESENT_METALFX,k);
        expect_rgb("HDR: with MetalFX the BT.709 PQ picture is still converted to BT.2020",got,o3,4e-3);}t_p709=0;
        res_remove(fx.in);res_remove(fx.out);g_fx_mode=0;
    } else printf("no Metal 4 MetalFX spatial scaler on this GPU: the HDR present through MetalFX is not checked\n");
}
#endif

static void check(id<MTLTexture> src, const char *name, const int crop[4], int w, int h, int color) {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageRenderTarget;
    id<MTLTexture> dst=[g_dev newTextureWithDescriptor:d];id<MTLCommandBuffer> cb=[g_q commandBuffer];
    EXPECT("encode succeeds",1,ENCODE(cb,src,dst,crop));[cb commit];[cb waitUntilCompleted];
    EXPECT("GPU done",MTLCommandBufferStatusCompleted,cb.status);
    uint8_t *out=malloc(w*h*4);[dst getBytes:out bytesPerRow:w*4 fromRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0];
    int bad=0;
    for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
        int q=color;
        if(q==4) { // square valid area onto a 2:1 target: 4 black columns on each side, the middle 8 columns all red.
            static const uint8_t black[4]={0,0,0,255};
            const uint8_t *want=x<4||x>=12?black:colors[0];bad+=memcmp(out+4*(y*w+x),want,4)!=0;continue;
        }
        if(q==-2) { // crop=(1,1,4,4): 3×3 red, last column green, last row blue, bottom-right 1 cell yellow.
            q=(x+1>=4)+2*(y+1>=4);
        } else if(q<0) { // same-size default whole frame: the boundary is dead center.
            q=(x>=w/2)+2*(y>=h/2);
        }
        bad+=memcmp(out+4*(y*w+x),colors[q],4)!=0;
    }
    EXPECT(name,0,bad);free(out);
}

// This fixture is the only present producer. A window now holds a logical queue receipt;
// wait for replay, then for the display ticket (snapshots do not return that ticket).
static uint64_t display_ticket(uint64_t receipt, uint64_t before) {
    EXPECT("present returned a logical receipt",1,receipt!=0);
    if (!receipt) return 0;
    nvn_queue_present_wait(receipt);
    uint64_t queued, done; mtl_present_progress(&queued,&done);
    EXPECT("one frame reached the display queue",1,queued==before+1);
    if (queued!=before+1) return 0;
    mtl_present_wait(queued);
    return queued;
}

#ifndef CROP_LEGACY_HEADER
static void check_external_png(const char *path) {
    NSURL *url = [NSURL fileURLWithPath:@(path)];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    int green = 0;
    if (image) {
        uint8_t pixels[4 * 4 * 4];
        CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(pixels, 4, 4, 8, 16, color, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
        if (ctx) {
            CGContextDrawImage(ctx, CGRectMake(0, 0, 4, 4), image);
            for (int i = 0; i < 16; i++)
                green += pixels[4*i] == 0 && pixels[4*i+1] == 255 && pixels[4*i+2] == 0;
            CGContextRelease(ctx);
        }
        CGColorSpaceRelease(color);
        CGImageRelease(image);
    }
    if (source) CFRelease(source);
    EXPECT(path, 16, green);
}

static void check_external_screenshots(void) {
    char dir[] = "/tmp/nxnative-external-shot.XXXXXX";
    if (!mkdtemp(dir)) { EXPECT("screenshot test directory", 1, 0); return; }
    char scheduled[sizeof dir + 16], queued[sizeof dir + 16], spec[sizeof scheduled + 3];
    snprintf(scheduled, sizeof scheduled, "%s/scheduled.png", dir);
    snprintf(queued, sizeof queued, "%s/queued.png", dir);
    snprintf(spec, sizeof spec, "1:%s", scheduled);
    setenv("DM_NVN_SHOT", spec, 1);
    unsetenv("DM_NVN_SHOT_OUT");

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    td.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [g_dev newTextureWithDescriptor:td];
    const uint8_t black[4 * 4 * 4] = {0};
    [tex replaceRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0 withBytes:black bytesPerRow:16];

    id<MTLSharedEvent> ready = [g_dev newSharedEvent];
    assert(ready);
    id<MTLCommandQueue> producer = [g_dev newCommandQueue];
    id<MTLCommandBuffer> cb = [producer commandBuffer];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = tex;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 0, 1);
    [[cb renderCommandEncoderWithDescriptor:pass] endEncoding];
    [cb encodeSignalEvent:ready value:1];
    // Leave the producer unsubmitted while the external present first reaches readback.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_global_queue(0, 0), ^{ [cb commit]; });
    uint64_t serial = mtl_ext_tex((__bridge void *)tex);
    dm_gfx_shot_at(1, queued);
    uint64_t ticket = mtl_present_ext(serial, 1.0 / 60, (__bridge void *)ready, 1, NULL);
    EXPECT("external present returns a ticket", 1, ticket != 0);
    if (ticket) mtl_present_wait(ticket);
    check_external_png(scheduled);
    check_external_png(queued);
    EXPECT("producer completes", 1, [ready waitUntilSignaledValue:1 timeoutMS:5000]);
    mtl_ext_tex_release(serial);
    unlink(scheduled);
    unlink(queued);
    rmdir(dir);
}
#endif

int main(int argc, char **argv) { @autoreleasepool {
    mtl_init();
#ifndef CROP_LEGACY_HEADER
    if (argc == 2 && !strcmp(argv[1], "--external-screenshots")) {
        check_external_screenshots();
        return failed != 0;
    }
    mtl_present_layer(1,1);   // square fixtures: a sized square layer, so the checks below see the crop's texels and the bars of that shape; the display's own shape is checked at the end
#endif
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> src=[g_dev newTextureWithDescriptor:d];uint8_t px[8*8*4];
    for(int y=0;y<8;y++)for(int x=0;x<8;x++)memcpy(px+4*(y*8+x),colors[(x>=4)+2*(y>=4)],4);
    [src replaceRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0 withBytes:px bytesPerRow:32];
    int zero[4]={0},tl[4]={0,0,4,4},tr[4]={4,0,4,4},bl[4]={0,4,4,4},br[4]={4,4,4,4},one[4]={3,3,1,1},inset[4]={1,1,4,4};
    check(src,"default whole frame 64 pixels",zero,8,8,-1);
    check(src,"NULL default whole frame 64 pixels",NULL,8,8,-1);
    check(src,"top-left crop scaled up, 256 pixels all red",tl,16,16,0);
    check(src,"non-zero x crop scaled up, 256 pixels all green",tr,16,16,1);
    check(src,"non-zero y crop scaled up, 256 pixels all blue",bl,16,16,2);
    check(src,"bottom-right crop at the edge, 256 pixels all yellow",br,16,16,3);
    check(src,"single texel scaled up without crossing edges, 256 pixels all red",one,16,16,0);
    check(src,"non-zero x and y offset, 16 pixels byte-identical to a hand-written sub-rectangle",inset,4,4,-2);
    check(src,"aspect of the valid area kept, 128 pixels red in the middle / black on both sides",tl,16,8,4);
#ifndef CROP_LEGACY_HEADER
    {
        // sRGB swapchain: present sends the raw bytes (as the Switch's scan-out does) without decoding first; unfixed, 128/64/200 decode to about 55/13/148
        MTLTextureDescriptor *sd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:8 height:8 mipmapped:NO];sd.storageMode=MTLStorageModeShared;sd.usage=MTLTextureUsageShaderRead;
        id<MTLTexture> s8=[g_dev newTextureWithDescriptor:sd];uint8_t g[8*8*4];
        for(int i=0;i<64;i++){g[4*i]=128;g[4*i+1]=64;g[4*i+2]=200;g[4*i+3]=255;}
        [s8 replaceRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0 withBytes:g bytesPerRow:32];
        MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=MTLTextureUsageRenderTarget;
        id<MTLTexture> dst=[g_dev newTextureWithDescriptor:od];id<MTLCommandBuffer> cb=[g_q commandBuffer];
        EXPECT("sRGB source encode succeeds",1,ENCODE(cb,s8,dst,zero));[cb commit];[cb waitUntilCompleted];
        uint8_t o[8*8*4];[dst getBytes:o bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0];
        int bad=0;for(int i=0;i<64;i++)bad+=abs(o[4*i]-128)>1||abs(o[4*i+1]-64)>1||abs(o[4*i+2]-200)>1;
        EXPECT("sRGB swapchain present sends raw bytes, 64 pixels",0,bad);
    }
#endif
#ifndef CROP_LEGACY_HEADER
    {   // DM_PRESENT_UPSCALE: which content MetalFX scales, and to which size (the picture's rectangle on the canvas)
        const struct { unsigned cw,ch,dw,dh,w,h; int upscale; } sizes[] = {
            {1280,720,2868,1320,2347,1320,1},   // handheld, letterboxed on an iPhone
            {1952,900,2868,1320,2868,1320,1},   // ratios within 1 % fill the canvas
            {1280,720,2560,1440,2560,1440,1},   // Retina window
            {1280,720,1280,720,1280,720,0},     // native size
            {1600,900,1280,720,1280,720,0},     // downscale
            {8,8,16,8,8,8,0},                  // larger canvas, native-size picture
        };
        for (unsigned i=0;i<sizeof sizes/sizeof *sizes;i++) {
            MTLViewport vp=present_viewport(sizes[i].cw,sizes[i].ch,sizes[i].dw,sizes[i].dh);
            EXPECT("MetalFX only upscales the picture",sizes[i].upscale,fx_wanted(vp,sizes[i].cw,sizes[i].ch));
            EXPECT("picture width",sizes[i].w,(int)vp.width);EXPECT("picture height",sizes[i].h,(int)vp.height);
        }
        EXPECT("empty content is not upscaled",0,fx_wanted((MTLViewport){0,0,2868,1320,0,1},0,720));
    }
    if([MTLFXSpatialScalerDescriptor supportsMetal4FX:g_dev]) {   // the present pass through MetalFX into an offscreen canvas (present_offscreen_m4, as DM_NVN_SHOT_OUT uses it)
        g_fx_mode=1;
        const int N=64;MTLTextureDescriptor *bd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:N height:N mipmapped:NO];bd.storageMode=MTLStorageModeShared;bd.usage=MTLTextureUsageShaderRead;
        id<MTLTexture> big=[g_dev newTextureWithDescriptor:bd];uint8_t *bp=malloc(N*N*4);
        for(int y=0;y<N;y++)for(int x=0;x<N;x++)memcpy(bp+4*(y*N+x),colors[(x>=N/2)+2*(y>=N/2)],4);
        for(int y=N/2;y<N;y++)for(int x=0;x<N/2;x++){uint8_t g[4]={128,64,200,255};memcpy(bp+4*(y*N+x),g,4);}   // lower-left quadrant: a mid grey-violet the sRGB bytes must keep
        [big replaceRegion:MTLRegionMake2D(0,0,N,N) mipmapLevel:0 withBytes:bp bytesPerRow:N*4];free(bp);
        res_add(big);res_commit();
        const int W=4*N,H=2*N;MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:H mipmapped:NO];
        od.storageMode=MTLStorageModePrivate;od.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;id<MTLTexture> out=[g_dev newTextureWithDescriptor:od];
        const int crops[4][4]={{0},{8,8,48,48},{8,8,48,48},{8,8,48,48}};
        for (int mode=0;mode<4;mode++) {
            g_fx_mode=mode==3?0:1;atomic_store(&g_origin_ll,mode==2);
            EXPECT("offscreen present reports the scaler actually used",mode==3?PRESENT_STANDARD:PRESENT_METALFX,present_offscreen_wait(big,crops[mode],out));
            id<MTLBuffer> rb=[g_dev newBufferWithLength:W*H*4 options:MTLResourceStorageModeShared];id<MTLCommandBuffer> cb=[g_q commandBuffer];id<MTLBlitCommandEncoder> bl=[cb blitCommandEncoder];
            [bl copyFromTexture:out sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(W,H,1) toBuffer:rb destinationOffset:0 destinationBytesPerRow:W*4 destinationBytesPerImage:W*H*4];
            [bl endEncoding];[cb commit];[cb waitUntilCompleted];
            const uint8_t *o=rb.contents;   // BGRA
        #define PX(x,y,c) o[4*((y)*W+(x))+(c)]
            int bars=0;for(int y=0;y<H;y++)for(int x=0;x<W;x++)if(x<64||x>=192)bars+=PX(x,y,0)||PX(x,y,1)||PX(x,y,2);
            EXPECT("  black bars beside the square picture, 0 lit pixels",0,bars);
            int bad=0;const int cxs[2]={64+32,64+96},cys[2]={32,96};
            for(int q=0;q<4;q++){int x=cxs[q&1],y=cys[q>>1],sq=mode==2?q^2:q;const uint8_t *want=sq==2?(const uint8_t[4]){128,64,200,255}:colors[sq];
                bad+=abs(PX(x,y,2)-want[0])>3||abs(PX(x,y,1)-want[1])>3||abs(PX(x,y,0)-want[2])>3;}
            EXPECT("  quadrant centres keep their colours, raw bytes of the sRGB source (4 checked)",0,bad);
        #undef PX
        }
        atomic_store(&g_origin_ll,0);g_fx_mode=1;
        MTLTextureDescriptor *smallD=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:32 height:32 mipmapped:NO];
        smallD.storageMode=MTLStorageModePrivate;smallD.usage=MTLTextureUsageRenderTarget;
        id<MTLTexture> small=[g_dev newTextureWithDescriptor:smallD];int whole[4]={0},invalidCrop[4]={63,0,2,2};
        EXPECT("MetalFX requested but downscaling uses standard",PRESENT_STANDARD,present_offscreen_wait(big,whole,small));
        EXPECT("offscreen rejects an invalid crop before submission",PRESENT_FAILED,present_offscreen_wait(big,invalidCrop,out));

        uint64_t savedPresent=g_present_n;g_present_n=1;
        EXPECT("initial present makes its scaler",PRESENT_METALFX,check_present_resize(big,W,H));
        id<MTL4FXSpatialScaler> first=g_fx_present.sc;
        g_present_n=2;
        EXPECT("resizing within 30 presents falls back to standard",PRESENT_STANDARD,check_present_resize(big,192,96));
        EXPECT("resizing keeps the previous scaler until replacement",1,g_fx_present.sc==first);
        g_present_n=31;
        EXPECT("stable new size makes its scaler",PRESENT_METALFX,check_present_resize(big,192,96));
        EXPECT("replacement has the new picture size",96,(int)g_fx_present.sc.outputWidth);
        EXPECT("exactly two scalers made",2,g_fx_present.made);
        g_present_n=32;
        EXPECT("same size reuses its scaler",PRESENT_METALFX,check_present_resize(big,192,96));
        EXPECT("reuse makes no new scaler",2,g_fx_present.made);
        // DM_FX_INPLACE and DM_FX_DIRECT: the scaler reads a private window texture in place and writes a canvas it can write, while the frame that draws that texture is
        // still running on the queue (committed just before, as a present follows its frame). The scaler must still see the whole frame: the encoder before it orders it after
        // the queue's earlier work only around work of its own (an encoder of barriers alone ordered nothing, and the scaler read the frame before, in every round)
        {
            const int S=256,ROUNDS=8;
            MTLTextureDescriptor *wd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:S height:S mipmapped:NO];
            wd.storageMode=MTLStorageModePrivate;wd.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;id<MTLTexture> win=[g_dev newTextureWithDescriptor:wd];
            MTLTextureDescriptor *cd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:2*S height:2*S mipmapped:NO];
            cd.storageMode=MTLStorageModePrivate;cd.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;id<MTLTexture> canvas=[g_dev newTextureWithDescriptor:cd];
            id<MTLBuffer> args=[g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared],rb=[g_dev newBufferWithLength:4*S*S*4 options:MTLResourceStorageModeShared];
            res_add(win);res_add(canvas);res_add(args);res_commit();
            NSError *err=nil;id<MTL4Compiler> comp=[g_dev newCompilerWithDescriptor:[MTL4CompilerDescriptor new] error:&err];
            id<MTLLibrary> lib=[g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nstruct A { uint iters; uint tag; };\n"
                "kernel void frame(constant A &a [[buffer(0)]], texture2d<float, access::write> t [[texture(0)]], uint2 i [[thread_position_in_grid]]) {\n"
                "  float x = float(i.x); for (uint k = 0; k < a.iters; k++) x = fma(x, 1.0000001f, 0.5f); float g = x > -1.0f ? float(a.tag) / 255.0f : 0.0f; t.write(float4(g, g, g, 1), i); }\n" options:nil error:&err];
            MTL4LibraryFunctionDescriptor *fd=[MTL4LibraryFunctionDescriptor new];fd.name=@"frame";fd.library=lib;
            MTL4ComputePipelineDescriptor *pd=[MTL4ComputePipelineDescriptor new];pd.computeFunctionDescriptor=fd;
            id<MTLComputePipelineState> ps=lib&&comp?[comp newComputePipelineStateWithDescriptor:pd compilerTaskOptions:nil error:&err]:nil;
            EXPECT("the slow frame kernel compiles",1,ps!=nil);
            MTL4ArgumentTableDescriptor *ad=[MTL4ArgumentTableDescriptor new];ad.maxBufferBindCount=1;ad.maxTextureBindCount=1;
            id<MTL4ArgumentTable> at=[g_dev newArgumentTableWithDescriptor:ad error:&err];
            id<MTL4CommandAllocator> fal=[g_dev newCommandAllocator],pal=[g_dev newCommandAllocator];id<MTLSharedEvent> ev=[g_dev newSharedEvent];
            g_present_n=1000;int stale=0,kinds=0;
            for (int round=1;ps&&round<=ROUNDS;round++) {
                uint32_t tag=40+round*23;((uint32_t *)args.contents)[0]=50000;((uint32_t *)args.contents)[1]=tag;
                [at setAddress:args.gpuAddress atIndex:0];[at setTexture:win.gpuResourceID atIndex:0];[fal reset];[pal reset];
                id<MTL4CommandBuffer> fcb=[g_dev newCommandBuffer];[fcb beginCommandBufferWithAllocator:fal];
                id<MTL4ComputeCommandEncoder> ce=[fcb computeCommandEncoder];[ce setComputePipelineState:ps];[ce setArgumentTable:at];
                [ce dispatchThreads:MTLSizeMake(S,S,1) threadsPerThreadgroup:MTLSizeMake(16,16,1)];[ce endEncoding];[fcb endCommandBuffer];
                id<MTL4CommandBuffer> pcb=[g_dev newCommandBuffer];[pcb beginCommandBufferWithAllocator:pal];
                kinds+=present_encode_m4(pcb,win,canvas,NULL,g_present_uv[0],&g_fx_present,NULL)==PRESENT_METALFX;[pcb endCommandBuffer];
                [g_q4 commit:&fcb count:1];[g_q4 commit:&pcb count:1];[g_q4 signalEvent:ev value:round];
                if (![ev waitUntilSignaledValue:round timeoutMS:10000]) { EXPECT("in-place present completes",1,0); break; }
                id<MTLCommandBuffer> cb=[g_q commandBuffer];id<MTLBlitCommandEncoder> bl=[cb blitCommandEncoder];
                [bl copyFromTexture:canvas sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(2*S,2*S,1) toBuffer:rb destinationOffset:0 destinationBytesPerRow:2*S*4 destinationBytesPerImage:4*S*S*4];
                [bl endEncoding];[cb commit];[cb waitUntilCompleted];
                const uint8_t *o=rb.contents;int bad=0;
                for (int y=4;y<2*S-4;y+=9) for (int x=4;x<2*S-4;x+=9) bad+=abs(o[4*(y*2*S+x)+1]-(int)tag)>3;
                stale+=bad!=0;
            }
            EXPECT("in-place presents go through MetalFX",ROUNDS,kinds);
            EXPECT("the scaler read the window texture in place: no input copy made",1,g_fx_present.in==nil&&g_fx_present.in_place_n>=ROUNDS);
            EXPECT("the scaler wrote the canvas: no present pass, no output texture made",1,g_fx_present.out==nil&&g_fx_present.direct_n>=ROUNDS);
            EXPECT("the scaler saw the whole frame still drawing at the present, rounds stale",0,stale);
            res_remove(win);res_remove(canvas);res_remove(args);
        }
        g_present_n=savedPresent;

        // Whole-window capture uses the same upscale and remains asynchronous; its completion includes the final BGRA readback.
        dispatch_semaphore_t grabbed=dispatch_semaphore_create(0);
        mtl_grab_next_present(^(CGImageRef img) {
            EXPECT("whole-window capture produces an image",1,img!=NULL);
            if (img) {
                EXPECT("whole-window image width",W,(int)CGImageGetWidth(img));
                CFDataRef data=CGDataProviderCopyData(CGImageGetDataProvider(img));const uint8_t *p=CFDataGetBytePtr(data);
                size_t off=96*CGImageGetBytesPerRow(img)+96*4;
                EXPECT("whole-window capture preserves sRGB bytes",1,abs(p[off]-200)<=3&&abs(p[off+1]-64)<=3&&abs(p[off+2]-128)<=3);
                CFRelease(data);
            }
            dispatch_semaphore_signal(grabbed);
        });
        grab_present(big,whole,CGSizeMake(W,H));
        EXPECT("whole-window capture callback completes",0,(int)dispatch_semaphore_wait(grabbed,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)));
        res_remove(big);g_fx_mode=0;
    } else printf("no Metal 4 MetalFX spatial scaler on this GPU: the MetalFX present is not checked\n");
    check_present_hdr();
#endif
    int invalid[4][4]={{-1,0,4,4},{0,-1,4,4},{0,0,0,4},{7,0,4,4}};
    for(int i=0;i<4;i++) {
        MTLTextureDescriptor *dd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];dd.usage=MTLTextureUsageRenderTarget;dd.storageMode=MTLStorageModeShared;
        id<MTLTexture> dst=[g_dev newTextureWithDescriptor:dd];
        EXPECT("invalid crop is not encoded and does not fake success by stretching the whole image",0,ENCODE([g_q commandBuffer],src,dst,invalid[i]));
    }
    // Real QueuePresent entry: set crop and enqueue first, then immediately change the window; the present ticket must keep that frame's copy.
    PFNNVNDEVICEGETPROCADDRESSPROC get=(PFNNVNDEVICEGETPROCADDRESSPROC)h_nvnBootstrapLoader("nvnDeviceGetProcAddress");
    NVNT_nvnWindowSetCrop set=(NVNT_nvnWindowSetCrop)get(NULL,"nvnWindowSetCrop");
    NVNT_nvnQueuePresentTexture present=(NVNT_nvnQueuePresentTexture)get(NULL,"nvnQueuePresentTexture");
    NVNqueueBuilder builder={0}; NVNqueue queue={0};
    h_nvnQueueBuilderSetDefaults(&builder);
    EXPECT("fixture queue initialized",1,h_nvnQueueInitialize(&queue,&builder));
    uint64_t before, done;
    tex_t tex={.magic=MAGIC('T', 'E', 'X', 0), .serial =10001};tex.d.width=tex.d.height=8;tex.d.depth=tex.d.levels=1;tex.d.format=NVN_FORMAT_RGBA8;tex.d.target=NVN_TEXTURE_TARGET_2D;serial_put(tex.serial,src);
    win_t win={.ntex=1};win.tex[0]=(NVNtexture *)&tex;set((NVNwindow *)&win,4,4,4,4);
    mtl_present_progress(&before,&done);
    // Replay is held until the window changes: QueuePresent must take this frame's crop when it queues the frame, not when replay presents it
    nvn_queue_test_hold(1);
    present(&queue,(NVNwindow *)&win,0);set((NVNwindow *)&win,0,0,8,8);
    {   // without a working hold the crop check below would pass whenever replay ran first
        uint64_t held; usleep(20000); mtl_present_progress(&held,&done);
        EXPECT("the held replay queues no frame for the display",1,held==before);
    }
    nvn_queue_test_hold(0);
    uint64_t tk=display_ticket(win.ticket[0],before);
#ifdef CROP_LEGACY_HEADER
    EXPECT("old queue struct has no room for a four-value copy (struct check)",1,sizeof(pq_item)>=sizeof(tex_t)+sizeof(double)+sizeof(uint64_t)+sizeof br);
#else
    pthread_mutex_lock(&g_pq_mu);
    int saved=tk && memcmp(g_pq[(tk-1)%PQ].crop,br,sizeof br)==0;pthread_mutex_unlock(&g_pq_mu);
    EXPECT("real QueuePresent: the frame's crop copy does not change with the window",1,saved);
#endif
    h_nvnWindowFinalize((NVNwindow *)&win);
#ifndef CROP_LEGACY_HEADER
    {   // A window without a crop of its own presents by the vi layer crop (Link's Awakening in handheld mode: 1280x720 of its 1920x1080 window textures, cropped through vi::SetLayerCrop)
        int none[4]={0},lay[4]={0,4,4,4},over[4]={0,0,16,16},lc[4];
        memset(g_layer_crop,0,sizeof g_layer_crop);EXPECT("no window or layer crop: the whole texture",1,present_crop(none,8,8,lc)==none);
        memcpy(g_layer_crop,lay,sizeof lay);const int *r=present_crop(none,8,8,lc);EXPECT("no window crop: the layer crop",1,r==lc&&!memcmp(lc,lay,sizeof lay));
        EXPECT("the window's own crop wins over the layer crop",1,present_crop(br,8,8,lc)==br);
        memcpy(g_layer_crop,over,sizeof over);EXPECT("a layer crop larger than the texture: the whole texture",1,present_crop(none,8,8,lc)==none);
        memcpy(g_layer_crop,lay,sizeof lay);win_t w2={.ntex=1};w2.tex[0]=(NVNtexture *)&tex;
        mtl_present_progress(&before,&done);
        nvn_queue_test_hold(1);
        present(&queue,(NVNwindow *)&w2,0);memset(g_layer_crop,0,sizeof g_layer_crop);
        nvn_queue_test_hold(0);
        uint64_t t2=display_ticket(w2.ticket[0],before);
        pthread_mutex_lock(&g_pq_mu);int got=t2 && memcmp(g_pq[(t2-1)%PQ].crop,lay,sizeof lay)==0;pthread_mutex_unlock(&g_pq_mu);
        EXPECT("real QueuePresent: a window without a crop queues the layer crop",1,got);
        h_nvnWindowFinalize((NVNwindow *)&w2);
    }
    {   // The crop only picks texels; the picture has the layer's shape (Super Mario Galaxy 2's storybook cutscenes: 1200x960 of a 1920x1080 swapchain, shown at 16:9, issue #949)
        const int W=64,H=36,TW=64,TH=36;MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:TW height:TH mipmapped:NO];td.storageMode=MTLStorageModeShared;td.usage=MTLTextureUsageShaderRead;
        id<MTLTexture> sw=[g_dev newTextureWithDescriptor:td];uint8_t *sp=malloc(TW*TH*4);
        const int crop54[4]={0,0,40,32};   // 5:4 in the top-left corner: red inside, green outside
        for(int y=0;y<TH;y++)for(int x=0;x<TW;x++)memcpy(sp+4*(y*TW+x),colors[x>=crop54[2]||y>=crop54[3]],4);
        [sw replaceRegion:MTLRegionMake2D(0,0,TW,TH) mipmapLevel:0 withBytes:sp bytesPerRow:TW*4];free(sp);res_add(sw);res_commit();
        double sa,sb;
        mtl_present_layer(0,0);present_shape(sw,&sa,&sb);EXPECT("no sized layer: the display's width",1920,(int)sa);EXPECT("no sized layer: the display's height",1080,(int)sb);
        for(int m4=0;m4<2;m4++) {
            int outH[2]={H,40};   // 16:9 fills; a 16:10 canvas keeps the bars above and below
            for(int k=0;k<2;k++) {
                MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:W height:outH[k] mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=MTLTextureUsageRenderTarget;
                id<MTLTexture> ot=[g_dev newTextureWithDescriptor:od];res_add(ot);res_commit();
                if(m4){EXPECT("Metal 4 present of a 5:4 crop",1,present_offscreen_wait(sw,crop54,ot)!=PRESENT_FAILED);}
                else{id<MTLCommandBuffer> cb=[g_q commandBuffer];EXPECT("classic present of a 5:4 crop",1,present_encode(cb,sw,ot,crop54));[cb commit];[cb waitUntilCompleted];}
                uint8_t *o=malloc(W*outH[k]*4);[ot getBytes:o bytesPerRow:W*4 fromRegion:MTLRegionMake2D(0,0,W,outH[k]) mipmapLevel:0];
                int bad=0,top=(outH[k]-H)/2;static const uint8_t black[4]={0,0,0,255};
                for(int y=0;y<outH[k];y++)for(int x=0;x<W;x++)bad+=memcmp(o+4*(y*W+x),y<top||y>=top+H?black:colors[0],4)!=0;
                EXPECT(k?"5:4 crop on a 16:10 canvas: 16:9 of red, black above and below":"5:4 crop on a 16:9 canvas: all red, no side bars",0,bad);free(o);res_remove(ot);
            }
        }
        mtl_present_layer(4,3);present_shape(sw,&sa,&sb);EXPECT("a sized layer gives its own shape",4*(int)sb,3*(int)sa);mtl_present_layer(0,0);
        MTLTextureDescriptor *td2=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1920 height:1344 mipmapped:NO];td2.storageMode=MTLStorageModePrivate;td2.usage=MTLTextureUsageShaderRead;
        id<MTLTexture> tall=[g_dev newTextureWithDescriptor:td2];
        present_shape(tall,&sa,&sb);EXPECT("a taller texture without DM_SCREEN_ASPECT: 16:9",1080,(int)sb);
        mtl_present_screen(1920,1344);present_shape(tall,&sa,&sb);EXPECT("DM_SCREEN_ASPECT: a texture that follows it keeps the taller shape",1344,(int)sb);
        present_shape(sw,&sa,&sb);EXPECT("DM_SCREEN_ASPECT: a 16:9 texture of a build without stubs stays 16:9",1080,(int)sb);mtl_present_screen(0,0);
        // The front end's layout and the mouse follow the same shape, not the crop's (front_picture_shape): a real present of the 5:4 crop
        tex_t st={.magic=MAGIC('T', 'E', 'X', 0), .serial =10002};st.d.width=TW;st.d.height=TH;st.d.depth=st.d.levels=1;st.d.format=NVN_FORMAT_RGBA8;st.d.target=NVN_TEXTURE_TARGET_2D;serial_put(st.serial,sw);
        win_t w3={.ntex=1};w3.tex[0]=(NVNtexture *)&st;set((NVNwindow *)&w3,crop54[0],crop54[1],crop54[2],crop54[3]);
        mtl_present_progress(&before,&done);
        present(&queue,(NVNwindow *)&w3,0);display_ticket(w3.ticket[0],before);
        h_nvnWindowFinalize((NVNwindow *)&w3);
        EXPECT("the shape reported to the front end is the layer's, width",1920,g_shape_w);EXPECT("the shape reported to the front end is the layer's, height",1080,g_shape_h);
        res_remove(sw);
    }
#endif
    h_nvnQueueFinalize(&queue);
    printf("== %d checks, %d failed ==\n",cases,failed);return failed!=0;
} }
