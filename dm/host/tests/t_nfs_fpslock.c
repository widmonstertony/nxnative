// Exercise the production exact-build timer group, not just copied formulas.
#include "../hle_fpslock.c"
#include <assert.h>
#include <math.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
static module_t modules[1]; module_t *g_mod = modules; int g_nmod;
static int writes;
void dm_guest_write_prepare(void *p, size_t n) { (void)p; assert(n == 4); writes++; }
static void check(int mode) {
    size_t size=0x2000000; uint8_t *base=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    assert(base!=MAP_FAILED);g_nmod=1;strcpy(modules[0].name,"main");modules[0].base=base;
    strcpy(modules[0].build_id,"799d1061182c1302e08e706b84ce76e5");
    *(uint32_t *)(base+0x4835a4)=mode==5?0x54ffff2c:0xd503201f;
    uint8_t timer[0x60]={0},step[0x60]={0};
    *(uintptr_t *)(base+0xed96a8)=(uintptr_t)timer;*(uintptr_t *)(base+0xeffc60)=(uintptr_t)step;
    int target=mode==1?60:mode==2||mode==3||mode==9?30:120;
    setenv("DM_NFS_FPS",mode==1?"60":mode==2?"30":mode==3?"0":mode==9?"invalid":"120",1);
    if(mode==4)modules[0].build_id[0]='0';
    if(mode==6)*(uintptr_t *)(base+0xed96a8)=0;
    if(mode==7)*(uintptr_t *)(base+0xeffc60)=1;
    if(mode==8)*(uint32_t *)(base+0xf0043c)=7;
    dm_fps_lock_tick();
    if(mode!=4&&mode!=5){assert(atoi(getenv("DM_PRESENT_HZ"))==target);assert(!strcmp(getenv("DM_PRESENT_INTERVAL"),"display"));assert(!strcmp(getenv("DM_PRESENT_LINK"),"2"));}
    if(mode>=4&&mode<=8){assert(!writes); if(mode==6){*(uintptr_t *)(base+0xed96a8)=(uintptr_t)timer;dm_fps_lock_tick();assert(writes==5);}}
    else {
        assert(*(uint32_t *)(base+0xf0043c)==(unsigned)(target>=60));
        assert(*(uint32_t *)(timer+0x30)==19200000u/target);
        assert(*(uint32_t *)(timer+0x28)==1920000u/target);
        assert(fabsf(*(float *)(step+0x30)-1.0f/target)<1e-8f);
        assert(fabsf(*(float *)(step+0x50)-1.0f/target)<1e-8f);
        int old=writes;dm_fps_lock_tick();assert(writes==old);
        *(uint32_t *)(timer+0x30)=123;dm_fps_lock_tick();assert(writes==old+1);
    }
    munmap(base,size);
}
int main(void){for(int i=0;i<10;i++){pid_t p=fork();assert(p>=0);if(!p){check(i);_exit(0);}int status;assert(waitpid(p,&status,0)==p);assert(WIFEXITED(status)&&!WEXITSTATUS(status));}puts("NFS FPS: 10 timing-group/build/instruction/null/unreadable/initialization cases passed");}
