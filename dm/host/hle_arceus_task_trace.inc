// Read-only trace for the repeatable 1.1.1 main+16e34fc fault. The weak
// owner may be absent; diagnostics must not dereference it, acquire a guest
// reference, change registers, or substitute an allocator. Kernel-mediated
// reads also tolerate an object being unmapped during a snapshot.
#include <mach/mach.h>
#include <pthread.h>

struct arceus_task_snapshot {
    uint64_t sequence, service, heap, weak, owner, owner_heap, item, caller;
    uint64_t type, object, incoming, incoming_control, expected_type, chain[8], thread;
    unsigned chain_count, type_match;
    uint32_t weak_count, strong_count, reads, stage;
};
static _Atomic int g_arceus_trace_active;
static uint64_t g_arceus_trace_base;
static pthread_mutex_t g_arceus_trace_lock = PTHREAD_MUTEX_INITIALIZER;
static struct arceus_task_snapshot g_arceus_trace_ring[32];
static uint64_t g_arceus_trace_sequence;
static unsigned g_arceus_trace_fault_dumps;

static int arceus_trace_read(uint64_t at, void *out, size_t size) {
    if (!at || size > UINT64_MAX-at) return 0;
    vm_size_t got = 0;
    kern_return_t result = vm_read_overwrite(mach_task_self(), at, size,
        (vm_address_t)(uintptr_t)out, &got);
    return result == KERN_SUCCESS && got == size;
}
static void arceus_trace_capture(struct arceus_task_snapshot *s) {
    uint64_t words[18] = {0};
    if (arceus_trace_read(s->service, words, sizeof words)) {
        s->heap=words[1]; s->weak=words[17]; s->reads|=1;
    }
    uint8_t control[32]={0};
    if (arceus_trace_read(s->weak, control, sizeof control)) {
        memcpy(&s->weak_count,control+8,4); memcpy(&s->strong_count,control+12,4);
        memcpy(&s->type,control+16,8); memcpy(&s->object,control+24,8); s->reads|=2;
    }
    if(g_arceus_trace_base) arceus_trace_read(g_arceus_trace_base+0x4281918,&s->expected_type,8);
    uint64_t type=s->type;
    for(unsigned i=0;type&&i<8;i++) {
        s->chain[s->chain_count++]=type;
        if(type==s->expected_type) { s->type_match=1; break; }
        if(!arceus_trace_read(type,&type,8)) break;
    }
    if (s->owner && s->owner <= UINT64_MAX-0x118 &&
        arceus_trace_read(s->owner+0x118,&s->owner_heap,8)) s->reads|=4;
}
static void arceus_trace_print(const struct arceus_task_snapshot *s) {
    LOG("Arceus task trace seq=%llu stage=%u service=%#llx heap=%#llx weak=%#llx refs=%u/%u type=%#llx object=%#llx owner=%#llx owner_heap=%#llx incoming=%#llx item=%llu gate_return=%#llx thread=%#llx incoming_control=%#llx reads=%u type_match=%u expected=%#llx chain=%u:%#llx,%#llx,%#llx,%#llx,%#llx,%#llx,%#llx,%#llx",
        (unsigned long long)s->sequence,s->stage,(unsigned long long)s->service,
        (unsigned long long)s->heap,(unsigned long long)s->weak,s->weak_count,s->strong_count,
        (unsigned long long)s->type,(unsigned long long)s->object,(unsigned long long)s->owner,
        (unsigned long long)s->owner_heap,(unsigned long long)s->incoming,
        (unsigned long long)s->item,(unsigned long long)s->caller,(unsigned long long)s->thread,(unsigned long long)s->incoming_control,s->reads,s->type_match,(unsigned long long)s->expected_type,s->chain_count,
        (unsigned long long)s->chain[0],(unsigned long long)s->chain[1],(unsigned long long)s->chain[2],(unsigned long long)s->chain[3],
        (unsigned long long)s->chain[4],(unsigned long long)s->chain[5],(unsigned long long)s->chain[6],(unsigned long long)s->chain[7]);
}
static void arceus_task_trace(uint64_t *regs, int param) {
    if (!atomic_load_explicit(&g_arceus_trace_active,memory_order_acquire)) return;
    struct arceus_task_snapshot s={.stage=(uint32_t)param,.caller=regs[30],.thread=(uint64_t)(uintptr_t)pthread_self()};
    if (param==0 || param==2 || param==3) { s.service=regs[0]; s.item=regs[1]; }
    else if (param==1 || param==5) { s.service=regs[21]; s.owner=regs[8]; s.item=regs[22]; }
    else if (param==4) s.service=regs[19];
    else return;
    if (param==2 && regs[1] <= UINT64_MAX-0x28) {
        arceus_trace_read(regs[1]+0x20,&s.incoming,8);
        arceus_trace_read(regs[1]+0x28,&s.incoming_control,8);
    }
    if(param==5 && regs[29]>=0x60) arceus_trace_read(regs[29]-0x60,&s.owner,8);
    arceus_trace_capture(&s);
    pthread_mutex_lock(&g_arceus_trace_lock);
    s.sequence=++g_arceus_trace_sequence;
    g_arceus_trace_ring[(s.sequence-1)%32]=s;
    if (param==1 && !s.owner && g_arceus_trace_fault_dumps++<2) {
        LOG("[RED] Arceus task owner unresolved before original allocator read; last 32 snapshots, registers and guest state unchanged");
        uint64_t first=s.sequence>32?s.sequence-31:1;
        for(uint64_t n=first;n<=s.sequence;n++) arceus_trace_print(&g_arceus_trace_ring[(n-1)%32]);
    } else if (s.sequence<=12 || param==2 || param==3 || param==4 || !(s.sequence%128))
        arceus_trace_print(&s);
    pthread_mutex_unlock(&g_arceus_trace_lock);
}
static void arceus_task_trace_init(void) {
    for(int i=0;i<g_nmod;i++) {
        module_t *m=&g_mod[i];
        if (!strcmp(m->name,"main") && m->base &&
            !strcmp(m->build_id,"aee8f150dda1b5a838806e1a5ea6827a") &&
            m->text_end==0x32a5690 && m->ro_off==0x32a6000 && m->data_off==0x401a000 &&
            gate_obs_present(OBS_ARCEUS_TASK_TRACE)) {
            g_arceus_trace_base=(uint64_t)(uintptr_t)m->base;
            atomic_store_explicit(&g_arceus_trace_active,1,memory_order_release);
            LOG("Arceus read-only resource task lifetime trace enabled (6 exact-build sites)");
            return;
        }
    }
}
__attribute__((constructor)) static void arceus_task_trace_gate(void) {
    gate_obs_set(OBS_ARCEUS_TASK_TRACE,arceus_task_trace);
}
