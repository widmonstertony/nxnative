// A fresh private Metal texture must inherit published NVN pool content.
#define DM_NVN_LEGACY_RENDERER_TEST 1
#include "../nvn/nvn_mtl.m"
#include "../nvn/nvn_protos.h"
#include "../../host/hle.h"
#include <mach-o/getsect.h>
#include <mach-o/ldsyms.h>
uint64_t g_t0_ns;
int dm_guest_as_contains(uintptr_t p) { (void)p; return 0; }
int front_screen_max_fps(void) { return 60; }
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(c,label) do { checks++; if (!(c)) { failed++; fprintf(stderr,"FAIL: %s\n",label); } } while(0)
static void initial_case(int cpu_flags,int flags,int flush,int filled,int want) {
    const size_t length=262144;
    uint8_t *mem=mmap(NULL,length,PROT_READ|PROT_WRITE,MAP_ANON|MAP_PRIVATE,-1,0);
    CHECK(mem!=MAP_FAILED,"source allocation");if(mem==MAP_FAILED)return;
    // A constant block-linear image has the same bytes regardless of GOB padding.
    memset(mem+65536,filled?0x5a:0,65536);
    unsigned long bytes=0;const hle_force_ent *entries=(const hle_force_ent *)getsectiondata(&_mh_execute_header,"__DATA","swforce",&bytes);
    void *(*boot)(const char*)=NULL;
    for(size_t i=0;i<bytes/sizeof *entries;i++)if(!strcmp(entries[i].name,"nvnBootstrapLoader"))boot=entries[i].fn;
    CHECK(boot!=NULL,"production bootstrap");if(!boot){munmap(mem,length);return;}
    PFNNVNDEVICEGETPROCADDRESSPROC gpa=(PFNNVNDEVICEGETPROCADDRESSPROC)boot("nvnDeviceGetProcAddress");
#define API(name) ((NVNT_##name)gpa(NULL,#name))
    NVNmemoryPoolBuilder pb;NVNmemoryPool pool;NVNtextureBuilder tb;NVNtexture tex={0};
    API(nvnMemoryPoolBuilderSetDefaults)(&pb);API(nvnMemoryPoolBuilderSetStorage)(&pb,mem,length);API(nvnMemoryPoolBuilderSetFlags)(&pb,cpu_flags|NVN_MEMORY_POOL_FLAGS_GPU_CACHED);
    CHECK(API(nvnMemoryPoolInitialize)(&pool,&pb),"source pool initializes");
    if(flush==1)API(nvnMemoryPoolFlushMappedRange)(&pool,65536,65536);
    API(nvnTextureBuilderSetDefaults)(&tb);API(nvnTextureBuilderSetWidth)(&tb,4);API(nvnTextureBuilderSetHeight)(&tb,4);API(nvnTextureBuilderSetFormat)(&tb,NVN_FORMAT_RGBA8);API(nvnTextureBuilderSetFlags)(&tb,flags);API(nvnTextureBuilderSetStorage)(&tb,&pool,65536);
    CHECK(API(nvnTextureInitialize)(&tex,&tb),"ordinary texture initializes");tex_t *t=(tex_t *)&tex;
    CHECK(!t->has_layout,"source has no packaged layout");
    if(flush==2)API(nvnMemoryPoolFlushMappedRange)(&pool,65536,t->L.size);
    uint64_t uploads=g_bp_up_bytes;
    mtl_reg_tex(1,t,NULL);mtl_sub_begin();id<MTLTexture> texture=tex_by_id(1);
    CHECK(texture!=nil,"sampled descriptor resolves");mtl_sub_commit();mtl_drain();
    CHECK(!tex_cpu_written(t->serial),"one-time fill keeps GPU ownership instead of becoming a tracked package");
    CHECK((g_bp_up_bytes>uploads)==(want&&filled),"only eligible nonzero initial content is uploaded");
    id<MTLBuffer> out=[g_dev newBufferWithLength:1024 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb=[g_q commandBuffer];id<MTLBlitCommandEncoder>b=[cb blitCommandEncoder];
    [b copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(4,4,1) toBuffer:out destinationOffset:0 destinationBytesPerRow:256 destinationBytesPerImage:1024];[b endEncoding];[cb commit];[cb waitUntilCompleted];
    CHECK(cb.status==MTLCommandBufferStatusCompleted,"direct GPU readback completes");
    for(int y=0;y<4;y++)for(int x=0;x<16;x++)CHECK(((uint8_t*)out.contents)[y*256+x]==(want&&filled?0x5a:0),"first-use GPU bytes equal published source or excluded zero");
    // A later lookup cannot overwrite a GPU-written texture with old pool data.
    mtl_sub_begin();id<MTLTexture> again=tex_by_id(1);CHECK(again==texture,"initial fill is performed only for a new allocation");mtl_sub_commit();mtl_drain();
    CHECK(g_bp_up_bytes==uploads+(want&&filled?64:0),"cached lookup never repeats the initial upload");
    mtl_reg_tex(1,NULL,NULL);API(nvnTextureFinalize)(&tex);API(nvnMemoryPoolFinalize)(&pool);defer_drain();munmap(mem,length);
#undef API
}
int main(void){@autoreleasepool{
    mtl_init();
    initial_case(NVN_MEMORY_POOL_FLAGS_CPU_NO_ACCESS,0,0,1,1);
    initial_case(NVN_MEMORY_POOL_FLAGS_CPU_UNCACHED,0,0,1,1);
    initial_case(NVN_MEMORY_POOL_FLAGS_CPU_CACHED,0,1,1,1);
    if(!DM_GAME_TEX_FLUSH_UPLOAD) initial_case(NVN_MEMORY_POOL_FLAGS_CPU_CACHED,0,2,1,1);
    initial_case(NVN_MEMORY_POOL_FLAGS_CPU_CACHED,0,0,1,0);
    initial_case(NVN_MEMORY_POOL_FLAGS_CPU_UNCACHED,NVN_TEXTURE_FLAGS_COMPRESSIBLE,0,1,0);
    initial_case(NVN_MEMORY_POOL_FLAGS_CPU_NO_ACCESS,0,0,0,0);
    printf("legacy initial content: %d checks, %d failed\n",checks,failed);return failed!=0;
}}
