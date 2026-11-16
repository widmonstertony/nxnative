// Exercise production trace reads against valid, absent and inaccessible guest objects.
#include <assert.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/mman.h>
static unsigned logs;

#include "../dm.h"
#undef LOG
#define LOG(...) do{logs++; if(0) printf(__VA_ARGS__);}while(0)
static module_t mods[1];module_t *g_mod=mods;int g_nmod=1;
static void(*attached)(uint64_t*,int);static int have=1;
void gate_obs_set(int i,void(*f)(uint64_t*,int)){assert(i==36);attached=f;}
int gate_obs_present(int i){return i==36&&have;}
#include "../hle_arceus_task_trace.inc"
int main(void){
 strcpy(g_mod[0].name,"main");strcpy(g_mod[0].build_id,"wrong");g_mod[0].base=(void*)1;g_mod[0].text_end=0x32a5690;g_mod[0].ro_off=0x32a6000;g_mod[0].data_off=0x401a000;arceus_task_trace_init();assert(!g_arceus_trace_active);
 strcpy(g_mod[0].build_id,"aee8f150dda1b5a838806e1a5ea6827a");have=0;arceus_task_trace_init();assert(!g_arceus_trace_active);have=1;arceus_task_trace_init();assert(g_arceus_trace_active);
 uint64_t service[64]={0},owner[64]={0},ctrl[4]={0},args[8]={0};service[1]=0x123456;service[17]=(uintptr_t)ctrl;ctrl[1]=((uint64_t)7<<32)|9;ctrl[2]=0xabc;ctrl[3]=(uintptr_t)owner+0x50;owner[0x118/8]=0x987654;
 struct arceus_task_snapshot s={.service=(uintptr_t)service,.owner=(uintptr_t)owner};arceus_trace_capture(&s);assert(s.reads==7&&s.heap==0x123456&&s.weak_count==9&&s.strong_count==7&&s.owner_heap==0x987654);
 uint64_t regs[31]={0},original[31];regs[0]=(uintptr_t)service;regs[1]=(uintptr_t)args;regs[21]=(uintptr_t)service;regs[19]=(uintptr_t)service;regs[22]=5;regs[8]=(uintptr_t)owner;args[4]=(uintptr_t)ctrl;memcpy(original,regs,sizeof regs);
 uint64_t frame[32]={0};frame[4]=(uintptr_t)owner;regs[29]=(uintptr_t)frame+0x80;memcpy(original,regs,sizeof regs);
 for(int p=0;p<=5;p++){attached(regs,p);assert(!memcmp(regs,original,sizeof regs));}
 regs[8]=0;memcpy(original,regs,sizeof regs);for(int i=0;i<100;i++)attached(regs,1);assert(!memcmp(regs,original,sizeof regs));assert(g_arceus_trace_sequence==106&&g_arceus_trace_fault_dumps==100);
 size_t sz=16384;void *unreadable=mmap(0,sz,PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0);assert(unreadable!=MAP_FAILED);uint64_t out=0xdead;assert(!arceus_trace_read((uintptr_t)unreadable,&out,8));assert(!arceus_trace_read(0,&out,8));assert(!arceus_trace_read(UINT64_MAX-3,&out,8));assert(out==0xdead);
 service[17]=(uintptr_t)unreadable;s=(struct arceus_task_snapshot){.service=(uintptr_t)service};arceus_trace_capture(&s);assert(s.reads==1);munmap(unreadable,sz);
 puts("PASS: build/gate guards, live/null/unmapped/overflow reads, ref snapshot, ring wrap, bounded dumps, unchanged guest registers");
}
